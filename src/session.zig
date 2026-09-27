//! Chats, and the turns they point at.
//!
//! Every name lives under `@/` in a config directory, and three kinds of file
//! are generated there rather than authored:
//!
//!   `X/=/id`  a turn, named by chance and never rewritten
//!   `X/+`     a chat: a single 🧠 naming the turn it has got to
//!   `+`       the main chat: a 🧠 naming a chat, or naming a turn outright
//!
//! It is git's objects and refs. A turn is an object, a chat is a ref, and
//! the main chat is `HEAD` — attached when it names a chat, so it is the chat
//! that moves, and detached when it names a turn, so it moves itself.
//!
//! All of them are ordinary names, so nothing here knows how to load one —
//! `ledger` already does, and a 🧠 walks from a chat to a turn to its parent
//! without noticing the difference.
//!
//! A turn holds only its own exchange. The conversation is the chain of 🧠
//! behind it, so forking costs nothing: two turns may name one parent and
//! neither copies anything.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const config = @import("config.zig");
const model = @import("m8/model.zig");

/// The folder turns are kept in, beside the chat that made them.
pub const history = "=";

/// A chat's pointer, inside the chat's own folder.
pub const pointer = "+";

/// The main chat. A pointer with no chat folder around it, so it sits at the
/// top of `@/`.
pub const main = pointer;

pub const Error = error{
    NoConfigDir,
    /// Nothing has been said yet, so the main chat names nothing.
    NoMainChat,
};

/// What reading where a chat has got to can run into.
pub const ReadError = Error || error{UnknownAgent} || doc.ParseError || Allocator.Error;

/// True for a name m8 generated rather than a person authored: a turn, a
/// chat, or the main chat. Used to find the agent a conversation is really
/// with — the first authored name in the lineage.
pub fn isGenerated(name: []const u8) bool {
    return isTurn(name) or isPointer(name);
}

/// Whether a name is a turn: anything inside a `=` folder.
pub fn isTurn(name: []const u8) bool {
    return std.mem.startsWith(u8, name, history ++ "/") or
        std.mem.indexOf(u8, name, "/" ++ history ++ "/") != null;
}

/// Whether a name is a pointer that moves: a chat, or the main chat.
pub fn isPointer(name: []const u8) bool {
    return std.mem.eql(u8, name, main) or std.mem.endsWith(u8, name, "/" ++ pointer);
}

/// The chat a pointer belongs to. Empty for the main chat.
pub fn chatOf(ptr: []const u8) []const u8 {
    if (std.mem.eql(u8, ptr, main)) return "";
    return ptr[0 .. ptr.len - pointer.len - 1];
}

/// A chat's pointer.
pub fn pointerOf(arena: Allocator, chat: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ chat, pointer });
}

/// Where a turn goes when it continues `parent` without advancing any chat:
/// beside it. A turn's parent is in some chat's `=`; an agent's is the agent
/// itself; a model, or nothing at all, has no folder and so takes the top one.
pub fn besideParent(arena: Allocator, parent: []const u8) ![]const u8 {
    if (parent.len == 0 or model.is(parent)) return history;
    if (isTurn(parent)) return std.fs.path.dirname(parent) orelse history;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ parent, history });
}

/// Where a turn goes that advances `chat`.
pub fn inChat(arena: Allocator, chat: []const u8) ![]const u8 {
    if (chat.len == 0) return history;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ chat, history });
}

/// What a pointer names, or null when there is no such pointer yet.
pub fn deref(arena: Allocator, io: std.Io, dirs: []const []const u8, ptr: []const u8) ReadError!?[]const u8 {
    const src = (try config.read(arena, io, dirs, try config.nameFile(arena, ptr))) orelse return null;
    var diag: doc.Diagnostic = .{};
    for (try doc.parse(arena, src, &diag)) |r| {
        if (r.sigil == .agent) return r.value;
    }
    return null;
}

/// Whether an authored agent file exists by this name.
pub fn isAgent(arena: Allocator, io: std.Io, dirs: []const []const u8, name: []const u8) Allocator.Error!bool {
    if (name.len == 0 or isGenerated(name) or model.is(name)) return false;
    return (try config.where(arena, io, dirs, try config.nameFile(arena, name))) != null;
}

/// Where a chat has got to.
///
/// A chat with no pointer of its own reads as its parent's head, which is the
/// whole of what forking and resetting are: a new chat starts from wherever
/// its parent is, and a reset one goes back to following it. The parent of an
/// agent's own chat is the agent.
pub fn head(arena: Allocator, io: std.Io, dirs: []const []const u8, chat: []const u8) ReadError![]const u8 {
    var at = chat;
    while (true) {
        if (try deref(arena, io, dirs, try pointerOf(arena, at))) |got| return settle(arena, io, dirs, got);
        if (try isAgent(arena, io, dirs, at)) return at;
        at = std.fs.path.dirname(at) orelse return error.UnknownAgent;
    }
}

/// The turn, agent or model a name stands for now.
///
/// A turn records what it continues, and a pointer moves — so lineage must
/// name what the pointer names rather than the pointer. Recording `🧠+` would
/// make the turn its own ancestor as soon as the main chat moved on.
pub fn settle(arena: Allocator, io: std.Io, dirs: []const []const u8, name: []const u8) ReadError![]const u8 {
    if (std.mem.eql(u8, name, main)) {
        const got = (try deref(arena, io, dirs, main)) orelse return Error.NoMainChat;
        return settle(arena, io, dirs, got);
    }
    if (isPointer(name)) return head(arena, io, dirs, chatOf(name));
    return name;
}

/// Every 🧠 in `records` settled, so what is written names nothing that moves.
pub fn settleAll(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    records: []const doc.Record,
) ![]const doc.Record {
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| {
        var one = r;
        if (r.sigil == .agent) one.value = try settle(arena, io, dirs, r.value);
        try out.append(arena, one);
    }
    return out.items;
}

/// Point `ptr` at `target`.
pub fn point(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    ptr: []const u8,
    target: []const u8,
) !void {
    try write(arena, io, dirs, ptr, &.{.{ .sigil = .agent, .value = target }});
}

/// Take a pointer away, from the nearest directory that has one. Nothing it
/// named is touched: a turn is never rewritten, and a chat reset is a chat
/// that goes back to reading as its parent.
pub fn unpoint(arena: Allocator, io: std.Io, dirs: []const []const u8, ptr: []const u8) !void {
    const rel = try config.nameFile(arena, ptr);
    const dir = (try config.where(arena, io, dirs, rel)) orelse return;
    try std.Io.Dir.cwd().deleteFile(io, try std.fs.path.join(arena, &.{ dir, rel }));
}

/// Names are ten lowercase letters. 26^10 is about 1.4e14, so history would need
/// millions of turns before a collision was worth thinking about — and nothing
/// here is a secret, it is a filename in a directory you own.
pub const id_len = 10;

/// A fresh turn name in the `=` folder `in`.
pub fn newName(arena: Allocator, io: std.Io, in: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ in, newId(io) });
}

fn newId(io: std.Io) [id_len]u8 {
    var out: [id_len]u8 = undefined;
    var pool: [32]u8 = undefined;
    var taken: usize = pool.len;
    var i: usize = 0;
    while (i < id_len) {
        if (taken == pool.len) {
            io.random(&pool);
            taken = 0;
        }
        const b = pool[taken];
        taken += 1;
        // 26 does not divide 256, so the short tail is redrawn rather than
        // folded in — otherwise the first six letters would be likelier.
        if (b >= 26 * 9) continue;
        out[i] = 'a' + b % 26;
        i += 1;
    }
    return out;
}

/// Write `records` as the file called `name`, in the nearest config directory.
pub fn write(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    records: []const doc.Record,
) !void {
    if (dirs.len == 0) return Error.NoConfigDir;

    const path = try std.fs.path.join(arena, &.{ dirs[0], try config.nameFile(arena, name) });

    // A file is markdown. The rendered spelling is only ever for a terminal.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, records);

    // Written aside and renamed into place, so an interrupted run leaves the
    // file as it was rather than half of a turn, and two runs moving one `+`
    // cannot interleave — the last rename wins, and the turn that lost is
    // still in `=/`. Not synced: this is for a process that stops, not a
    // machine that does.
    var file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, buf.written());
    try file.replace(io);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "an id is lowercase letters only" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var seen: [26]bool = @splat(false);
    for (0..64) |_| {
        const id = newId(io);
        try std.testing.expectEqual(@as(usize, id_len), id.len);
        for (id) |c| {
            try std.testing.expect(c >= 'a' and c <= 'z');
            seen[c - 'a'] = true;
        }
    }
    // 640 letters over 26 buckets: a letter never appearing would mean the
    // rejection step is folding the range wrong.
    for (seen) |s| try std.testing.expect(s);
}

test "a name says what kind it is by its shape alone" {
    try testing.expect(isTurn("=/abc"));
    try testing.expect(isTurn("mob/agent/chat1/=/abc"));
    try testing.expect(!isTurn("mob/agent"));
    try testing.expect(isPointer("+"));
    try testing.expect(isPointer("mob/agent/+"));
    try testing.expect(!isPointer("mob/agent"));
    try testing.expectEqualStrings("mob/agent", chatOf("mob/agent/+"));
    try testing.expectEqualStrings("", chatOf("+"));
}

test "a turn that advances nothing goes beside its parent" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    try testing.expectEqualStrings("mob/agent/c/=", try besideParent(arena, "mob/agent/c/=/abc"));
    try testing.expectEqualStrings("mob/agent/=", try besideParent(arena, "mob/agent"));
    try testing.expectEqualStrings("=", try besideParent(arena, "/local/tiny"));
    try testing.expectEqualStrings("=", try besideParent(arena, "=/abc"));
    try testing.expectEqualStrings("=", try besideParent(arena, ""));
}

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        const dir = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
        std.Io.Dir.cwd().deleteTree(io, dir) catch {};
        try std.Io.Dir.cwd().createDirPath(io, dir);
        return .{ .io = io, .dir = dir };
    }

    fn write(f: Fixture, gpa: Allocator, name: []const u8, body: []const u8) !void {
        const path = try std.fs.path.join(gpa, &.{ f.dir, config.names_dir, name });
        if (std.fs.path.dirname(path)) |d| try std.Io.Dir.cwd().createDirPath(f.io, d);
        try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = body });
    }

    fn deinit(f: Fixture) void {
        std.Io.Dir.cwd().deleteTree(f.io, f.dir) catch {};
    }
};

test "a chat with no pointer reads as its parent's head" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-session-head");
    defer f.deinit();
    try f.write(arena, "mob/agent.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{f.dir};

    // Nothing said yet: the agent's chat is the agent, and so is a sub chat.
    try testing.expectEqualStrings("mob/agent", try head(arena, f.io, &dirs, "mob/agent"));
    try testing.expectEqualStrings("mob/agent", try head(arena, f.io, &dirs, "mob/agent/c1/sub"));

    // The agent's chat moves, and a chat forked from it follows until it
    // has a pointer of its own.
    try f.write(arena, "mob/agent/+.md", "#### :brain:mob/agent/=/one\n");
    try testing.expectEqualStrings("mob/agent/=/one", try head(arena, f.io, &dirs, "mob/agent/c1"));
    try f.write(arena, "mob/agent/c1/+.md", "#### :brain:mob/agent/c1/=/two\n");
    try testing.expectEqualStrings("mob/agent/c1/=/two", try head(arena, f.io, &dirs, "mob/agent/c1/sub"));

    // The main chat attached to a chat reads as that chat.
    try f.write(arena, "+.md", "#### :brain:mob/agent/c1/+\n");
    try testing.expectEqualStrings("mob/agent/c1/=/two", try settle(arena, f.io, &dirs, main));

    // Unpointing goes back to the parent, and never removes a turn.
    try unpoint(arena, f.io, &dirs, "mob/agent/c1/+");
    try testing.expectEqualStrings("mob/agent/=/one", try head(arena, f.io, &dirs, "mob/agent/c1"));

    try testing.expectError(error.UnknownAgent, head(arena, f.io, &dirs, "nobody/c"));
}

test "no main chat is said rather than guessed at" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-session-main");
    defer f.deinit();
    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.NoMainChat, settle(arena, f.io, &dirs, main));
}
