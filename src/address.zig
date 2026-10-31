//! Explicit mob/agent addresses. Authored agents may be nested; `//` starts
//! a subchat path, and `/+/TURN` names an immutable turn. No global chat.

const std = @import("std");
const Allocator = std.mem.Allocator;
const session = @import("session.zig");
const model = @import("m8/model.zig");
const doc = @import("m8/doc.zig");

pub const Kind = enum { model, turn, chat };

pub const Suffix = enum {
    none,
    /// `:` — ask, and move no pointer.
    oneshot,
    /// `-` — start from the chat's parent.
    reset,
    /// `--` — start from the authored agent.
    reset_new,
};

pub const Address = struct {
    kind: Kind,
    /// The explicit chat path, turn, or model.
    name: []const u8 = "",
    suffix: Suffix = .none,
};

pub const Error = error{
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
};

/// The marks that say a word is an address.
const marks = [_][]const u8{ ":brain:", "🧠", ":" };

/// What follows the mark, or null when the word is not an address.
pub fn body(word: []const u8) ?[]const u8 {
    for (marks) |m| if (std.mem.startsWith(u8, word, m)) {
        var rest = word[m.len..];
        // A pasted 🧠 may carry the presentation selector a renderer added,
        // and a header line ends its sigil with `:`.
        if (std.mem.startsWith(u8, rest, "\u{FE0F}")) rest = rest["\u{FE0F}".len..];
        if (std.mem.startsWith(u8, rest, doc.sigil_end)) rest = rest[doc.sigil_end.len..];
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
    dirs: config.Dirs,
    word: []const u8,
    diag: *Diagnostic,
) !Address {
    var rest = body(word) orelse word;
    var suffix: Suffix = .none;
    if (std.mem.endsWith(u8, rest, ":")) {
        suffix = .oneshot;
        rest = rest[0 .. rest.len - 1];
    } else if (std.mem.endsWith(u8, rest, "--")) {
        // Check the two-character suffix first: it is also a trailing `-`.
        suffix = .reset_new;
        rest = rest[0 .. rest.len - 2];
    } else if (std.mem.endsWith(u8, rest, "-")) {
        suffix = .reset;
        rest = rest[0 .. rest.len - 1];
    }
    rest = std.mem.trimEnd(u8, rest, "/");

    // Pointer-file spellings are accepted too, but //chat needs no trailing +.
    if (session.isPointer(rest)) rest = session.chatOf(rest);

    if (rest.len == 0 or rest[0] == '@') return error.InvalidName;
    if (model.is(rest)) return .{ .kind = .model, .name = rest, .suffix = suffix };
    if (config.mobName(rest) == null) return error.InvalidName;
    if (session.isTurn(rest)) return .{ .kind = .turn, .name = rest, .suffix = suffix };

    // // starts a subchat path; /+/ introduces an immutable turn.
    const agent = ownerName(rest) orelse return error.InvalidName;
    if (try session.isAgent(arena, io, dirs, agent))
        return .{ .kind = .chat, .name = rest, .suffix = suffix };
    diag.* = .{ .agent = agent };
    return error.UnknownAgent;
}

/// Resolve an address typed on the command line, saying what was wrong with
/// it in terms of what was typed. `error.Said` means it has been said.
pub fn typed(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    word: []const u8,
    err: *std.Io.Writer,
) !Address {
    var d: Diagnostic = .{};
    return resolve(arena, io, dirs, word, &d) catch |e| {
        switch (e) {
            error.UnknownAgent => try err.print("m8: no agent named '{s}'\n", .{d.agent}),
            else => return e,
        }
        return error.Said;
    };
}

/// The turn, agent or model an address reads as now.
pub fn read(arena: Allocator, io: std.Io, dirs: config.Dirs, a: Address) ![]const u8 {
    return switch (a.kind) {
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
    dirs: config.Dirs,
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

fn ownerName(name: []const u8) ?[]const u8 {
    const mob = config.mobName(name) orelse return null;
    const delimiter = std.mem.indexOf(u8, name, "//") orelse return name;
    if (delimiter <= mob.len) return null;
    return name[0..delimiter];
}

/// The authored agent that owns this chat tree.
pub fn agentOf(arena: Allocator, io: std.Io, dirs: config.Dirs, chat: []const u8) ![]const u8 {
    const agent = ownerName(chat) orelse return error.InvalidName;
    if (try session.isAgent(arena, io, dirs, agent)) return agent;
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
    dirs: config.Dirs,
    a: Address,
    start: Start,
) ![]const u8 {
    if (start == .head) return read(arena, io, dirs, a);
    if (a.kind != .chat) return Error.NothingToReset;
    const agent = try agentOf(arena, io, dirs, a.name);
    if (start == .new or std.mem.eql(u8, agent, a.name)) return agent;
    return session.head(arena, io, dirs, try session.parentChat(arena, a.name));
}

/// Where a turn tagged at this address is kept.
///
/// A turn goes in the `+` of the chat it advances. One that advances no chat
/// goes beside the turn it continues, which is `parent` settled.
pub fn home(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    a: Address,
    parent: []const u8,
) ![]const u8 {
    _ = io;
    _ = dirs;
    return switch (a.kind) {
        .chat => session.inChat(arena, a.name),
        .turn => session.besideParent(arena, if (config.mobName(parent) != null) parent else a.name),
        .model => error.InvalidName,
    };
}

/// What a tag moves.
pub const Moving = struct {
    /// Keep the turn and move nothing, which is what a side question is.
    stay: bool = false,
};

/// Advance only the explicitly addressed chat. Side questions move nothing.
pub fn advance(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    a: Address,
    turn: []const u8,
    moving: Moving,
) !void {
    if (moving.stay or a.suffix == .oneshot) return;
    switch (a.kind) {
        .chat => {
            const ptr = try session.pointerOf(arena, a.name);
            try session.point(arena, io, dirs, ptr, turn);
        },
        .model, .turn => {},
    }
}

/// Reset a chat to its parent. Only a chat has a pointer of its own to take:
/// a turn or a model is not a
/// chat.
pub fn reset(arena: Allocator, io: std.Io, dirs: config.Dirs, a: Address) !void {
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
pub fn renew(arena: Allocator, io: std.Io, dirs: config.Dirs, a: Address) !void {
    if (a.kind != .chat) return Error.NothingToReset;
    const agent = try agentOf(arena, io, dirs, a.name);
    const ptr = try session.pointerOf(arena, a.name);
    if (std.mem.eql(u8, try readFrom(arena, io, dirs, a, .parent), agent))
        return session.unpoint(arena, io, dirs, ptr);
    try session.point(arena, io, dirs, ptr, agent);
}

/// Point a chat at `target` as it is named.
///
/// Nothing is settled, which is the difference from tagging a 🧠: a chat
/// named here is followed, so what points at it reads as wherever that chat
/// gets to. The target must belong to the same mob.
///
/// A pointer that names a pointer is the one place a loop can be written, so
/// one that would lead back to itself is refused before it is.
pub fn follow(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    a: Address,
    target: Address,
) !void {
    const ptr = switch (a.kind) {
        .chat => try session.pointerOf(arena, a.name),
        .model, .turn => return Error.NothingToReset,
    };
    const scoped = try config.pin(arena, io, dirs, a.name);
    if (target.kind != .model) _ = try config.pin(arena, io, scoped, target.name);
    const named = switch (target.kind) {
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
    dirs: config.Dirs,
    a: Address,
    records: []const doc.Record,
    moving: Moving,
) ![]const u8 {
    if (a.kind == .model) return error.InvalidName;
    const scoped = try config.pin(arena, io, dirs, a.name);
    const settled = try session.settleAll(arena, io, scoped, records);
    const turn = if (settled.len == 1 and settled[0].sigil == .agent and settled[0].content == null)
        settled[0].value
    else blk: {
        const parent = for (settled) |r| {
            if (r.sigil == .agent) break r.value;
        } else "";
        const name = try session.newName(arena, io, try home(arena, io, scoped, a, parent));
        try session.write(arena, io, scoped, name, settled);
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

test "nested authored agents and generated chat trees have distinct grammar" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-address-nested");
    defer f.deinit();
    try f.write(arena, "crew/devyn", "* :brain::/local/tiny\n");
    try f.write(arena, "crew/devyn/utils/shields", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    var d: Diagnostic = .{};
    const authored_agent = try resolve(arena, f.io, dirs, ":crew/devyn/utils/shields", &d);
    try testing.expectEqualStrings("crew/devyn/utils/shields", authored_agent.name);
    const fork = try resolve(arena, f.io, dirs, ":crew/devyn//forked", &d);
    try testing.expectEqual(Kind.chat, fork.kind);
    const underscored_chat = try resolve(arena, f.io, dirs, ":crew/devyn//_private", &d);
    try testing.expectEqual(Kind.chat, underscored_chat.kind);
    const ambiguous = try resolve(arena, f.io, dirs, ":crew/devyn/+/forked", &d);
    try testing.expectEqual(Kind.turn, ambiguous.kind);
    const turn = try resolve(arena, f.io, dirs, ":crew/devyn//forked/+/qgivwhgxnh", &d);
    try testing.expectEqual(Kind.turn, turn.kind);
    try testing.expectEqualStrings("crew/devyn//forked/+/qgivwhgxnh", turn.name);
}
test "explicit mob addresses and suffixes; no global chat or hidden agents" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-address-marks");
    defer f.deinit();
    try f.write(arena, "mob/agent", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    var d: Diagnostic = .{};
    for ([_][]const u8{ ":mob/agent", ":brain:mob/agent", ":brain::mob/agent", "🧠mob/agent", "🧠:mob/agent" }) |w| {
        const got = try resolve(arena, f.io, dirs, w, &d);
        try testing.expectEqual(Kind.chat, got.kind);
        try testing.expectEqualStrings("mob/agent", got.name);
    }
    try testing.expect(!isAddress("@"));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, "@", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":agent", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":mob/.agent", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":mob/_", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":mob/_agent", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":mob/agent/_nested", &d));
    try testing.expectError(error.InvalidName, resolve(arena, f.io, dirs, ":mob/agent/utils/_shields", &d));
    try testing.expectError(error.UnknownAgent, resolve(arena, f.io, dirs, ":mob/missing", &d));
    try testing.expectEqual(Suffix.oneshot, (try resolve(arena, f.io, dirs, ":mob/agent:", &d)).suffix);
    try testing.expectEqual(Suffix.reset, (try resolve(arena, f.io, dirs, ":mob/agent//c1-", &d)).suffix);
    try testing.expectEqual(Suffix.reset_new, (try resolve(arena, f.io, dirs, ":mob/agent//c1--", &d)).suffix);
    try testing.expectEqual(Kind.turn, (try resolve(arena, f.io, dirs, ":mob/agent/+/abc", &d)).kind);
    const stateless = try resolve(arena, f.io, dirs, ":/local/tiny", &d);
    try testing.expectEqual(Kind.model, stateless.kind);
    try testing.expectError(error.InvalidName, home(arena, f.io, dirs, stateless, stateless.name));
}

test "tagging, side questions, subchat inheritance and reset retain explicit chat behavior" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-address-chats");
    defer f.deinit();
    try f.write(arena, "mob/agent", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    var d: Diagnostic = .{};
    const own = try resolve(arena, f.io, dirs, ":mob/agent", &d);
    const one = try tag(arena, f.io, dirs, own, &.{
        .{ .sigil = .agent, .value = "mob/agent" },
        .{ .sigil = .user, .content = "hello" },
    }, .{});
    try testing.expectEqualStrings(one, try read(arena, f.io, dirs, own));
    try testing.expect(std.mem.startsWith(u8, one, "mob/agent/+/"));
    const sub = try resolve(arena, f.io, dirs, ":mob/agent//job/sub", &d);
    try testing.expectEqualStrings(one, try read(arena, f.io, dirs, sub));
    const two = try tag(arena, f.io, dirs, sub, &.{
        .{ .sigil = .agent, .value = one },
        .{ .sigil = .user, .content = "next" },
    }, .{});
    try testing.expectEqualStrings(two, try read(arena, f.io, dirs, sub));
    try testing.expect(std.mem.startsWith(u8, two, "mob/agent//job/sub/+/"));
    try testing.expectEqualStrings(one, try readFrom(arena, f.io, dirs, sub, .parent));
    try testing.expectEqualStrings("mob/agent", try readFrom(arena, f.io, dirs, sub, .new));
    const side = try resolve(arena, f.io, dirs, ":mob/agent//job/sub:", &d);
    _ = try tag(arena, f.io, dirs, side, &.{
        .{ .sigil = .agent, .value = two },
        .{ .sigil = .user, .content = "aside" },
    }, .{});
    try testing.expectEqualStrings(two, try read(arena, f.io, dirs, sub));
    try renew(arena, f.io, dirs, sub);
    try testing.expectEqualStrings("mob/agent", try read(arena, f.io, dirs, sub));
    try reset(arena, f.io, dirs, sub);
    try testing.expectEqualStrings(one, try read(arena, f.io, dirs, sub));
    var err: std.Io.Writer.Allocating = .init(arena);
    const missing = try resolve(arena, f.io, dirs, ":mob/agent/+/missing", &d);
    try testing.expectError(error.Said, found(arena, f.io, dirs, missing, &err.writer));
}

test "chat following stays inside a mob and refuses cycles" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-address-follow");
    defer f.deinit();
    try f.write(arena, "mob/agent", "* :brain::/local/tiny\n");
    try f.write(arena, "other/agent", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    var d: Diagnostic = .{};
    const one = try resolve(arena, f.io, dirs, ":mob/agent//one", &d);
    const two = try resolve(arena, f.io, dirs, ":mob/agent//two", &d);
    try follow(arena, f.io, dirs, two, one);
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, dirs, one, two));
    try testing.expectError(Error.FollowLoops, follow(arena, f.io, dirs, one, one));
    const other = try resolve(arena, f.io, dirs, ":other/agent", &d);
    try testing.expectError(error.CrossMobReference, follow(arena, f.io, dirs, one, other));
    const model_target = try resolve(arena, f.io, dirs, ":/local/tiny", &d);
    try follow(arena, f.io, dirs, one, model_target);
    try testing.expectEqualStrings("/local/tiny", try read(arena, f.io, dirs, one));
    try testing.expectError(error.CrossMobReference, tag(arena, f.io, dirs, one, &.{.{ .sigil = .agent, .value = "other/agent" }}, .{}));
}
