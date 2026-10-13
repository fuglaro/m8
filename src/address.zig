//! An `@` on the command line: what it names, and what each verb does to it.
//!
//!   @                   the main chat
//!   @mob/agent          that agent's own chat
//!   @mob/agent/chat1    a chat under it, as deep as chats go
//!   @…/+/gftafinvgrdy   a turn
//!   @/local/tiny        a model
//!
//! `@`, `:brain:` and 🧠 all mark one, so a 🧠 line pasted back in names what
//! it printed. A trailing `:` asks without moving anything, and a trailing
//! `-` takes a chat's pointer away so that it reads as its parent again.
//! Both suffixes belong to the `@` prompt; a command says the same with an
//! option, so nothing has to carry a mark through a parameter.
//!
//! The main chat follows the `@` prompt and nothing else. A command moves the
//! chat it names, and moves the main chat only when that is what it names.
//!
//! An authored name is a path under `@/`, and the folder part is the mob —
//! until the walk meets an agent file, after which every word is a chat under
//! it. Generated chat state mirrors that path under the sibling `+/`. So
//! `x.md` beside `x/` is an agent and its chats, and `x/` alone is a mob. The
//! one thing that cannot be told apart is a chat that is also an agent's
//! name, and that is said rather than chosen between.

const std = @import("std");
const Allocator = std.mem.Allocator;
const session = @import("session.zig");
const model = @import("m8/model.zig");
const doc = @import("m8/doc.zig");

pub const Kind = enum { main, model, turn, chat };

pub const Suffix = enum {
    none,
    /// `:` — ask, and move no pointer.
    oneshot,
    /// `-` — take the chat's pointer away.
    reset,
};

pub const Address = struct {
    kind: Kind,
    /// The chat's path, the turn, or the model as written. Empty for main.
    name: []const u8 = "",
    suffix: Suffix = .none,
};

pub const Error = error{
    /// An agent, and a chat under another agent, answering to one name.
    AgentShadowed,
    /// A reset of something that has no pointer of its own to take away.
    NothingToReset,
    /// A turn that was named and is not there.
    UnknownTurn,
    /// A pointer told to follow something that leads back to it.
    FollowLoops,
};

/// Anything a diagnosis needs that an error name cannot carry.
pub const Diagnostic = struct {
    agent: []const u8 = "",
    other: []const u8 = "",
};

/// The marks that say a word is an address.
const marks = [_][]const u8{ "@", ":brain:", "🧠" };

/// What follows the mark, or null when the word is not an address.
pub fn body(word: []const u8) ?[]const u8 {
    for (marks) |m| if (std.mem.startsWith(u8, word, m)) {
        var rest = word[m.len..];
        // A pasted 🧠 may carry the presentation selector a renderer added.
        if (std.mem.startsWith(u8, rest, "\u{FE0F}")) rest = rest["\u{FE0F}".len..];
        return rest;
    };
    return null;
}

pub fn isAddress(word: []const u8) bool {
    return body(word) != null;
}

/// Read an address, without touching the disk for anything but agents.
pub fn resolve(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    word: []const u8,
    diag: *Diagnostic,
) !Address {
    var rest = body(word) orelse word;
    var suffix: Suffix = .none;
    if (std.mem.endsWith(u8, rest, ":")) {
        suffix = .oneshot;
        rest = rest[0 .. rest.len - 1];
    } else if (std.mem.endsWith(u8, rest, "-")) {
        suffix = .reset;
        rest = rest[0 .. rest.len - 1];
    }
    rest = std.mem.trimEnd(u8, rest, "/");

    // Written as the file it is, a pointer is the chat it belongs to.
    if (session.isPointer(rest)) rest = session.chatOf(rest);

    if (rest.len == 0) return .{ .kind = .main, .suffix = suffix };
    if (model.is(rest)) return .{ .kind = .model, .name = rest, .suffix = suffix };
    if (session.isTurn(rest)) return .{ .kind = .turn, .name = rest, .suffix = suffix };

    // The first prefix that is an agent is the agent; everything after it is
    // chats. The word after it is looked at once more, because a chat named
    // like an agent in the agent's own folder would be read as the chat and
    // hide the agent without anyone saying so.
    var it = std.mem.splitScalar(u8, rest, '/');
    var end: usize = 0;
    while (it.next()) |seg| {
        end += seg.len;
        const prefix = rest[0..end];
        if (try session.isAgent(arena, io, dirs, prefix)) {
            if (it.next()) |next| {
                const other = rest[0 .. end + 1 + next.len];
                if (try session.isAgent(arena, io, dirs, other)) {
                    diag.* = .{ .agent = prefix, .other = other };
                    return Error.AgentShadowed;
                }
            }
            return .{ .kind = .chat, .name = rest, .suffix = suffix };
        }
        end += 1;
    }
    diag.* = .{ .agent = rest };
    return error.UnknownAgent;
}

/// Resolve an address typed on the command line, saying what was wrong with
/// it in terms of what was typed. `error.Said` means it has been said.
pub fn typed(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    word: []const u8,
    err: *std.Io.Writer,
) !Address {
    var d: Diagnostic = .{};
    return resolve(arena, io, dirs, word, &d) catch |e| {
        switch (e) {
            Error.AgentShadowed => try err.print(
                "m8: '{s}' is an agent, and so is '{s}' in its chats' folder; rename one of them\n",
                .{ d.agent, d.other },
            ),
            error.UnknownAgent => try err.print("m8: no agent named '{s}'\n", .{d.agent}),
            else => return e,
        }
        return error.Said;
    };
}

/// The turn, agent or model an address reads as now.
pub fn read(arena: Allocator, io: std.Io, dirs: []const []const u8, a: Address) ![]const u8 {
    return switch (a.kind) {
        .main => session.settle(arena, io, dirs, session.main),
        .model, .turn => a.name,
        .chat => session.head(arena, io, dirs, a.name),
    };
}

/// The same, and looked for. A turn is a file, so one that is named and not
/// there is said here rather than handed on as a 🧠 for nothing.
///
/// A model is not looked for: its mark is the whole of what makes it one, and
/// which models a provider has is the provider's to say.
pub fn found(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    err: *std.Io.Writer,
) ![]const u8 {
    const name = try read(arena, io, dirs, a);
    if (session.isTurn(name) and !try session.exists(arena, io, dirs, name)) {
        try err.print("m8: no turn named '{s}'\n", .{name});
        return error.Said;
    }
    return name;
}

/// The agent a chat is under: the first agent met walking down its name.
pub fn agentOf(arena: Allocator, io: std.Io, dirs: []const []const u8, chat: []const u8) ![]const u8 {
    var it = std.mem.splitScalar(u8, chat, '/');
    var end: usize = 0;
    while (it.next()) |seg| {
        end += seg.len;
        if (try session.isAgent(arena, io, dirs, chat[0..end])) return chat[0..end];
        end += 1;
    }
    return error.UnknownAgent;
}

/// Where a chat starts from when it is not carried on.
pub const Start = enum {
    /// Where it has got to.
    head,
    /// Its parent's head, which is what a chat with no pointer reads as.
    parent,
    /// The agent it is under, whatever any chat above it has got to.
    new,
};

/// What a chat reads as when started from `start`. Only a chat has anywhere
/// else to start from than where it is.
pub fn readFrom(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    start: Start,
) ![]const u8 {
    if (start == .head) return read(arena, io, dirs, a);
    if (a.kind != .chat) return Error.NothingToReset;
    const agent = try agentOf(arena, io, dirs, a.name);
    if (start == .new or std.mem.eql(u8, agent, a.name)) return agent;
    return session.head(arena, io, dirs, std.fs.path.dirname(a.name).?);
}

/// Where a turn tagged at this address is kept.
///
/// A turn goes in the `+` of the chat it advances. One that advances no chat
/// goes beside the turn it continues, which is `parent` settled.
pub fn home(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    parent: []const u8,
) ![]const u8 {
    return switch (a.kind) {
        .chat => session.inChat(arena, a.name),
        .main => if (try attached(arena, io, dirs)) |chat|
            session.inChat(arena, chat)
        else
            session.besideParent(arena, parent),
        .model, .turn => session.besideParent(arena, parent),
    };
}

/// The chat the main chat is attached to, or null when it names a turn.
fn attached(arena: Allocator, io: std.Io, dirs: []const []const u8) !?[]const u8 {
    const got = (try session.deref(arena, io, dirs, session.main)) orelse return null;
    if (!session.isPointer(got)) return null;
    return session.chatOf(got);
}

/// Who is moving something, which is what decides how much moves.
pub const Mover = enum {
    /// The `@` prompt. The main chat goes wherever it talks.
    prompt,
    /// A command. It moves what it names and leaves the main chat where it
    /// is, so an agent run by a tool never takes over the conversation of
    /// whoever is at the terminal.
    command,
};

/// What a tag moves.
pub const Moving = struct {
    mover: Mover = .command,
    /// Keep the turn and move nothing, which is what a side question is.
    stay: bool = false,
};

/// Move whatever this address moves to `turn`.
///
/// A chat moves. The main chat attached to a chat moves that chat, and
/// detached it moves itself. For the `@` prompt the main chat also follows:
/// it is attached to a chat that was talked to, and pointed at the turn when
/// a turn or a model was.
pub fn advance(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    turn: []const u8,
    moving: Moving,
) !void {
    if (moving.stay or a.suffix == .oneshot) return;
    switch (a.kind) {
        .chat => {
            const ptr = try session.pointerOf(arena, a.name);
            try session.point(arena, io, dirs, ptr, turn);
            if (moving.mover == .prompt) try session.point(arena, io, dirs, session.main, ptr);
        },
        .main => if (try attached(arena, io, dirs)) |chat|
            try session.point(arena, io, dirs, try session.pointerOf(arena, chat), turn)
        else
            try session.point(arena, io, dirs, session.main, turn),
        .model, .turn => if (moving.mover == .prompt)
            try session.point(arena, io, dirs, session.main, turn),
    }
}

/// Reset a chat to its parent. Only a chat has a pointer of its own to take:
/// the main chat has no parent to read as, and a turn or a model is not a
/// chat.
pub fn reset(arena: Allocator, io: std.Io, dirs: []const []const u8, a: Address) !void {
    if (a.kind != .chat) return Error.NothingToReset;
    try session.unpoint(arena, io, dirs, try session.pointerOf(arena, a.name));
}

/// Reset a chat to the agent it is under, so it reads as that agent whatever
/// the chats above it have got to.
///
/// Taking the pointer away is enough whenever the chat would then read as
/// the agent anyway, and that is what is done: a chat with no pointer says
/// nothing that could go stale. Only when something above it has moved on is
/// the agent written down, because nothing else would say it.
pub fn renew(arena: Allocator, io: std.Io, dirs: []const []const u8, a: Address) !void {
    if (a.kind != .chat) return Error.NothingToReset;
    const agent = try agentOf(arena, io, dirs, a.name);
    const ptr = try session.pointerOf(arena, a.name);
    if (std.mem.eql(u8, try readFrom(arena, io, dirs, a, .parent), agent))
        return session.unpoint(arena, io, dirs, ptr);
    try session.point(arena, io, dirs, ptr, agent);
}

/// Point a chat, or the main chat, at `target` as it is named.
///
/// Nothing is settled, which is the difference from tagging a 🧠: a chat
/// named here is followed, so what points at it reads as wherever that chat
/// gets to. It is how the main chat is attached to a chat.
///
/// A pointer that names a pointer is the one place a loop can be written, so
/// one that would lead back to itself is refused before it is.
pub fn follow(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    target: Address,
) !void {
    const ptr = switch (a.kind) {
        .main => session.main,
        .chat => try session.pointerOf(arena, a.name),
        .model, .turn => return Error.NothingToReset,
    };
    const named = switch (target.kind) {
        .main => session.main,
        .chat => try session.pointerOf(arena, target.name),
        .model, .turn => target.name,
    };
    if (try session.leadsTo(arena, io, dirs, named, ptr)) return Error.FollowLoops;
    try session.point(arena, io, dirs, ptr, named);
}

/// Keep `records` as a turn tagged at `a`, and move what `a` moves.
///
/// A document that is one 🧠 and nothing else already names a turn, so it is
/// pointed at rather than kept again. Anything else is kept, as a new turn,
/// and pointed at. Either way the answer is the turn now pointed at.
pub fn tag(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: Address,
    records: []const doc.Record,
    moving: Moving,
) ![]const u8 {
    const settled = try session.settleAll(arena, io, dirs, records);
    const turn = if (settled.len == 1 and settled[0].sigil == .agent and settled[0].content == null)
        settled[0].value
    else blk: {
        const parent = for (settled) |r| {
            if (r.sigil == .agent) break r.value;
        } else "";
        const name = try session.newName(arena, io, try home(arena, io, dirs, a, parent));
        try session.write(arena, io, dirs, name, settled);
        break :blk name;
    };
    try advance(arena, io, dirs, a, turn, moving);
    return turn;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const config = @import("config.zig");
const test_tmp = @import("test_tmp.zig");

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        return .{ .io = io, .dir = try test_tmp.make(gpa, io, name) };
    }

    fn write(f: Fixture, gpa: Allocator, name: []const u8, text: []const u8) !void {
        const logical = if (std.mem.endsWith(u8, name, ".md")) name[0 .. name.len - 3] else name;
        const path = try std.fs.path.join(gpa, &.{ f.dir, try config.nameFile(gpa, logical) });
        if (std.fs.path.dirname(path)) |d| try std.Io.Dir.cwd().createDirPath(f.io, d);
        try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = text });
    }

    fn deinit(f: Fixture) void {
        std.Io.Dir.cwd().deleteTree(f.io, f.dir) catch {};
    }
};

test "every mark reads as an address, and suffixes are read off the end" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-marks");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};

    for ([_][]const u8{ "@mob/agent", ":brain:mob/agent", "🧠mob/agent", "🧠\u{FE0F}mob/agent" }) |w| {
        const got = try resolve(arena, f.io, &dirs, w, &d);
        try testing.expectEqual(Kind.chat, got.kind);
        try testing.expectEqualStrings("mob/agent", got.name);
    }
    try testing.expect(!isAddress("cat"));

    try testing.expectEqual(Kind.main, (try resolve(arena, f.io, &dirs, "@", &d)).kind);
    try testing.expectEqual(Suffix.oneshot, (try resolve(arena, f.io, &dirs, "@mob/agent:", &d)).suffix);
    try testing.expectEqual(Suffix.reset, (try resolve(arena, f.io, &dirs, "@mob/agent/c1-", &d)).suffix);
    try testing.expectEqual(Kind.model, (try resolve(arena, f.io, &dirs, "@/local/tiny:", &d)).kind);
    try testing.expectEqual(Kind.turn, (try resolve(arena, f.io, &dirs, "@mob/agent/+/abc", &d)).kind);
    try testing.expectError(error.UnknownAgent, resolve(arena, f.io, &dirs, "@nobody", &d));
}

test "a chat named like an agent beside it is said, not chosen" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-shadow");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    try f.write(arena, "mob/agent/other.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};

    try testing.expectError(Error.AgentShadowed, resolve(arena, f.io, &dirs, "@mob/agent/other", &d));
    try testing.expectEqualStrings("mob/agent", d.agent);
    try testing.expectEqualStrings("mob/agent/other", d.other);

    // A mob with no agent of its name is only a mob.
    try f.write(arena, "team/lead.md", "#### :brain:/local/tiny\n");
    const lead = try resolve(arena, f.io, &dirs, "@team/lead/plan", &d);
    try testing.expectEqualStrings("team/lead/plan", lead.name);
}

test "tagging keeps a turn in the chat it advances, and the prompt takes main with it" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-tag");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};
    const prompt: Moving = .{ .mover = .prompt };

    const chat = try resolve(arena, f.io, &dirs, "@mob/agent/c1", &d);
    const turn = try tag(arena, f.io, &dirs, chat, &.{
        .{ .sigil = .agent, .value = try read(arena, f.io, &dirs, chat) },
        .{ .sigil = .user, .content = "hi" },
    }, prompt);
    try testing.expect(std.mem.startsWith(u8, turn, "mob/agent/c1/+/"));
    try testing.expectEqualStrings(turn, try read(arena, f.io, &dirs, chat));
    try testing.expectEqualStrings("mob/agent/c1/+", (try session.deref(arena, f.io, &dirs, session.main)).?);

    // Attached, so the main chat moves the chat rather than itself.
    const main = try resolve(arena, f.io, &dirs, "@", &d);
    const next = try tag(arena, f.io, &dirs, main, &.{
        .{ .sigil = .agent, .value = turn },
        .{ .sigil = .user, .content = "more" },
    }, .{});
    try testing.expectEqualStrings(next, try read(arena, f.io, &dirs, chat));

    // A one-shot is kept beside nothing new and moves nothing, whether the
    // prompt wrote it as a `:` or a command was told to stay.
    const side = try resolve(arena, f.io, &dirs, "@mob/agent/c1:", &d);
    const aside = try tag(arena, f.io, &dirs, side, &.{
        .{ .sigil = .agent, .value = next },
        .{ .sigil = .user, .content = "by the way" },
    }, prompt);
    try testing.expect(std.mem.startsWith(u8, aside, "mob/agent/c1/+/"));
    try testing.expectEqualStrings(next, try read(arena, f.io, &dirs, chat));
    const stayed = try tag(arena, f.io, &dirs, chat, &.{
        .{ .sigil = .agent, .value = next },
        .{ .sigil = .user, .content = "and another" },
    }, .{ .stay = true });
    try testing.expect(std.mem.startsWith(u8, stayed, "mob/agent/c1/+/"));
    try testing.expectEqualStrings(next, try read(arena, f.io, &dirs, chat));

    // A turn named outright detaches main, and a lone 🧠 is pointed at.
    const ref = try resolve(arena, f.io, &dirs, try std.fmt.allocPrint(arena, "@{s}", .{aside}), &d);
    try testing.expectEqualStrings(aside, try tag(arena, f.io, &dirs, ref, &.{
        .{ .sigil = .agent, .value = aside },
    }, prompt));
    try testing.expectEqualStrings(aside, (try session.deref(arena, f.io, &dirs, session.main)).?);

    // Forking is naming somewhere else to tag.
    const fork = try resolve(arena, f.io, &dirs, "@mob/agent/c2", &d);
    _ = try tag(arena, f.io, &dirs, fork, &.{.{ .sigil = .agent, .value = aside }}, .{});
    try testing.expectEqualStrings(aside, try read(arena, f.io, &dirs, fork));

    // Resetting reads as the parent again, and only a chat has one.
    try reset(arena, f.io, &dirs, fork);
    try testing.expectEqualStrings("mob/agent", try read(arena, f.io, &dirs, fork));
    try testing.expectError(Error.NothingToReset, reset(arena, f.io, &dirs, main));
}

test "a command moves the chat it names and leaves the main chat alone" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-command");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    try f.write(arena, "mob/critic.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};

    // Somebody is at the terminal, talking to one agent.
    const mine = try resolve(arena, f.io, &dirs, "@mob/agent", &d);
    const said = try tag(arena, f.io, &dirs, mine, &.{
        .{ .sigil = .agent, .value = "mob/agent" },
        .{ .sigil = .user, .content = "hi" },
    }, .{ .mover = .prompt });
    try testing.expectEqualStrings("mob/agent/+", (try session.deref(arena, f.io, &dirs, session.main)).?);

    // A tool runs another. Its chat moves; whose conversation it is does not.
    const sub = try resolve(arena, f.io, &dirs, "@mob/critic/job", &d);
    const job = try tag(arena, f.io, &dirs, sub, &.{
        .{ .sigil = .agent, .value = "mob/critic" },
        .{ .sigil = .user, .content = "review that" },
    }, .{});
    try testing.expectEqualStrings(job, try read(arena, f.io, &dirs, sub));
    try testing.expectEqualStrings("mob/agent/+", (try session.deref(arena, f.io, &dirs, session.main)).?);
    try testing.expectEqualStrings(said, try read(arena, f.io, &dirs, try resolve(arena, f.io, &dirs, "@", &d)));

    // Nor does naming a turn, which a command only keeps something beside.
    const turn = try resolve(arena, f.io, &dirs, try std.fmt.allocPrint(arena, "@{s}", .{job}), &d);
    _ = try tag(arena, f.io, &dirs, turn, &.{.{ .sigil = .agent, .value = job }}, .{});
    try testing.expectEqualStrings("mob/agent/+", (try session.deref(arena, f.io, &dirs, session.main)).?);
}

test "a chat starts from where it is, from its parent, or from its agent" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-start");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};

    const own = try resolve(arena, f.io, &dirs, "@mob/agent", &d);
    const talked = try tag(arena, f.io, &dirs, own, &.{
        .{ .sigil = .agent, .value = "mob/agent" },
        .{ .sigil = .user, .content = "hi" },
    }, .{});
    const job = try resolve(arena, f.io, &dirs, "@mob/agent/job", &d);
    const done = try tag(arena, f.io, &dirs, job, &.{
        .{ .sigil = .agent, .value = talked },
        .{ .sigil = .user, .content = "more" },
    }, .{});

    try testing.expectEqualStrings(done, try readFrom(arena, f.io, &dirs, job, .head));
    // A chat nobody has used reads as its parent, which has been talked to.
    try testing.expectEqualStrings(talked, try readFrom(arena, f.io, &dirs, job, .parent));
    // The agent is what nobody has said anything to.
    try testing.expectEqualStrings("mob/agent", try readFrom(arena, f.io, &dirs, job, .new));
    try testing.expectEqualStrings("mob/agent", try readFrom(arena, f.io, &dirs, own, .parent));
    try testing.expectError(
        Error.NothingToReset,
        readFrom(arena, f.io, &dirs, try resolve(arena, f.io, &dirs, "@", &d), .new),
    );

    // Renewing writes that down, because the chat above has moved on and
    // nothing else would say it.
    try renew(arena, f.io, &dirs, job);
    try testing.expectEqualStrings("mob/agent", try read(arena, f.io, &dirs, job));
    try testing.expectEqualStrings("mob/agent", (try session.deref(arena, f.io, &dirs, "mob/agent/job/+")).?);
    try reset(arena, f.io, &dirs, job);
    try testing.expectEqualStrings(talked, try read(arena, f.io, &dirs, job));

    // Where taking the pointer away already reads as the agent, that is all
    // it does: the agent's own chat, and then a chat under it.
    try renew(arena, f.io, &dirs, own);
    try testing.expectEqualStrings("mob/agent", try read(arena, f.io, &dirs, own));
    try testing.expect(try session.deref(arena, f.io, &dirs, "mob/agent/+") == null);
    _ = try tag(arena, f.io, &dirs, job, &.{
        .{ .sigil = .agent, .value = "mob/agent" },
        .{ .sigil = .user, .content = "again" },
    }, .{});
    try renew(arena, f.io, &dirs, job);
    try testing.expectEqualStrings("mob/agent", try read(arena, f.io, &dirs, job));
    try testing.expect(try session.deref(arena, f.io, &dirs, "mob/agent/job/+") == null);
}

test "following is unsettled, and never leads back to itself" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-address-follow");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};
    var d: Diagnostic = .{};

    const main = try resolve(arena, f.io, &dirs, "@", &d);
    const one = try resolve(arena, f.io, &dirs, "@mob/agent/one", &d);
    const two = try resolve(arena, f.io, &dirs, "@mob/agent/two", &d);
    const first = try tag(arena, f.io, &dirs, one, &.{
        .{ .sigil = .agent, .value = "mob/agent" },
        .{ .sigil = .user, .content = "hi" },
    }, .{});

    // The main chat is put on a chat by following it.
    try follow(arena, f.io, &dirs, main, one);
    try testing.expectEqualStrings("mob/agent/one/+", (try session.deref(arena, f.io, &dirs, session.main)).?);
    try testing.expectEqualStrings(first, try read(arena, f.io, &dirs, main));

    // A chat following a chat reads as wherever that one gets to.
    try follow(arena, f.io, &dirs, two, one);
    const second = try tag(arena, f.io, &dirs, one, &.{
        .{ .sigil = .agent, .value = first },
        .{ .sigil = .user, .content = "more" },
    }, .{});
    try testing.expectEqualStrings(second, try read(arena, f.io, &dirs, two));

    // Straight back, round through another, and through a chat that only
    // reads as the one above it.
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, &dirs, one, one));
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, &dirs, one, two));
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, &dirs, one, main));
    const under = try resolve(arena, f.io, &dirs, "@mob/agent/one/under", &d);
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, &dirs, one, under));
    try testing.expectEqualStrings(second, try read(arena, f.io, &dirs, one));

    // A turn that was named has to be there.
    var err: std.Io.Writer.Allocating = .init(arena);
    const gone = try resolve(arena, f.io, &dirs, "@mob/agent/+/nothinghere", &d);
    try testing.expectError(error.Said, found(arena, f.io, &dirs, gone, &err.writer));
    try testing.expectEqualStrings("m8: no turn named 'mob/agent/+/nothinghere'\n", err.written());
    const kept = try resolve(arena, f.io, &dirs, try std.fmt.allocPrint(arena, "@{s}", .{first}), &d);
    try testing.expectEqualStrings(first, try found(arena, f.io, &dirs, kept, &err.writer));
}
