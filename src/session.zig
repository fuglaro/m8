//! Chat pointers and immutable linked turns within one selected mob layer.
//! Authored definitions are `mobs/MOB/AGENT/PATH.md`; generated state lives
//! under `mobs/MOB/.chats/AGENT/_/CHAT/...`. Logical `AGENT//CHAT` names
//! a chat; `/+/TURN` names its history. User/system state is relocated by
//! config. Subchats inherit their parent's head until their own pointer exists.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const config = @import("config.zig");
const model = @import("m8/model.zig");

/// The folder turns are kept in, beside the chat that made them.
pub const history = "+";

/// A chat's pointer, inside the chat's own folder.
pub const pointer = "+";

/// The transient value a provider uses when its content should be kept aside.
pub const snip = "snip";

/// A snip is a turn's aside, kept in the same `+` folder as the turn that
/// names it. The prefix is longer than a turn's name and holds a character
/// one never does, so the two can never be taken for each other.
pub const snip_prefix = "snip-";

/// A fresh short reference for a snip.
pub fn newSnip(arena: Allocator, io: std.Io) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}{s}", .{ snip_prefix, &newId(io) });
}

/// Keep `content` as a new snip in `folder`, and say what it is called.
///
/// The snip holds the `💭snip` a codec wrote, so the 🧠 naming it reads back
/// as exactly that, and keeping what was read keeps it aside again.
pub fn keepSnip(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    folder: []const u8,
    content: []const u8,
) ![]const u8 {
    const name = try std.fmt.allocPrint(arena, "{s}/{s}", .{ folder, try newSnip(arena, io) });
    try writeFile(arena, io, dirs, name, &.{.{ .sigil = .thought, .value = snip, .content = content }});
    return name;
}

/// Whether a record asks for what it holds to be kept aside. The marker is
/// meaningful only with a block on the same thought; a blockless `💭snip` is
/// the compact one-line thought "snip".
pub fn isSnip(r: doc.Record) bool {
    return r.sigil == .thought and r.content != null and std.mem.eql(u8, r.value, snip);
}

/// Whether a name is a snip's: the file a kept-aside thought was written to.
pub fn namesSnip(name: []const u8) bool {
    return std.mem.startsWith(u8, std.fs.path.basename(name), snip_prefix);
}

pub const Error = error{
    NoConfigDir,
};

/// What reading where a chat has got to can run into.
pub const ReadError = Error || error{ UnknownAgent, InvalidName, CrossMobReference, NoDataHome } || doc.ParseError || Allocator.Error;

/// True for a name m8 generated rather than a person authored: a turn, a
/// chat. Used to find the agent a conversation is really
/// with — the first authored name in the lineage.
pub fn isGenerated(name: []const u8) bool {
    return isTurn(name) or isPointer(name) or isChat(name);
}

/// A named subchat; the authored agent's own chat has no // suffix.
pub fn isChat(name: []const u8) bool {
    return config.mobName(name) != null and std.mem.indexOf(u8, name, "//") != null and !isTurn(name) and !isPointer(name);
}

/// Whether a name is a turn: anything inside a `+` folder.
pub fn isTurn(name: []const u8) bool {
    return config.mobName(name) != null and !isPointer(name) and std.mem.indexOf(u8, name, "/+/") != null;
}

/// Whether a name is a pointer that moves: a chat.
pub fn isPointer(name: []const u8) bool {
    return config.mobName(name) != null and std.mem.endsWith(u8, name, "/" ++ pointer);
}

/// The chat a pointer belongs to.
pub fn chatOf(ptr: []const u8) []const u8 {
    return ptr[0 .. ptr.len - pointer.len - 1];
}

/// A subchat inherits from its enclosing chat, stopping at its authored agent.
pub fn parentChat(arena: Allocator, chat: []const u8) ![]const u8 {
    _ = arena;
    const marker = std.mem.indexOf(u8, chat, "//") orelse return error.InvalidName;
    const tail = chat[marker + 2 ..];
    if (std.mem.lastIndexOfScalar(u8, tail, '/')) |slash|
        return chat[0 .. marker + 2 + slash];
    return chat[0..marker];
}

/// A chat's pointer.
pub fn pointerOf(arena: Allocator, chat: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ chat, pointer });
}

/// Where a turn goes when it continues `parent` without advancing any chat:
/// beside it. A turn's parent is in some chat's `+`; an agent's is the agent
/// itself. Models and empty names have no mob-owned storage folder.
pub fn besideParent(arena: Allocator, parent: []const u8) ![]const u8 {
    if (config.mobName(parent) == null) return error.InvalidName;
    if (isTurn(parent)) return std.fs.path.dirname(parent) orelse history;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ parent, history });
}

/// Where a turn goes that advances `chat`.
pub fn inChat(arena: Allocator, chat: []const u8) ![]const u8 {
    if (config.mobName(chat) == null) return error.InvalidName;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ chat, history });
}

/// What a pointer names, or null when there is no such pointer yet.
pub fn deref(arena: Allocator, io: std.Io, dirs: config.Dirs, ptr: []const u8) ReadError!?[]const u8 {
    const src = (try config.read(arena, io, dirs, try config.nameFile(arena, ptr))) orelse return null;
    const scope = config.mobName(ptr) orelse return error.InvalidName;
    var diag: doc.Diagnostic = .{};
    for (try doc.parse(arena, src, &diag)) |r| {
        if (r.sigil == .agent) {
            if (!model.is(r.value)) {
                const mob = config.mobName(r.value) orelse return error.InvalidName;
                if (!std.mem.eql(u8, scope, mob)) return error.CrossMobReference;
            }
            return r.value;
        }
    }
    return null;
}

/// Whether an authored agent file exists by this name.
pub fn isAgent(arena: Allocator, io: std.Io, dirs: config.Dirs, name: []const u8) ReadError!bool {
    if (!config.authored(name) or isGenerated(name) or model.is(name)) return false;
    return (try config.where(arena, io, dirs, try config.nameFile(arena, name))) != null;
}

/// Whether a turn, a chat's pointer or an agent is a file that is there.
pub fn exists(arena: Allocator, io: std.Io, dirs: config.Dirs, name: []const u8) !bool {
    return (try config.where(arena, io, dirs, try config.nameFile(arena, name))) != null;
}

/// Where a chat has got to.
///
/// A chat with no pointer of its own reads as its parent's head, which is the
/// whole of what forking and resetting are: a new chat starts from wherever
/// its parent is, and a reset one goes back to following it. The parent of an
/// agent's own chat is the agent.
pub fn head(arena: Allocator, io: std.Io, dirs: config.Dirs, chat: []const u8) ReadError![]const u8 {
    const scoped = try config.pin(arena, io, dirs, chat);
    var at = chat;
    while (true) {
        if (try deref(arena, io, scoped, try pointerOf(arena, at))) |got| return settle(arena, io, scoped, got);
        if (try isAgent(arena, io, scoped, at)) return at;
        if (std.mem.indexOf(u8, at, "//") == null) return error.UnknownAgent;
        at = try parentChat(arena, at);
    }
}

/// The turn, agent or model a name stands for now.
///
/// A turn records what it continues, and a pointer moves — so lineage must
/// name what the pointer names rather than the pointer. Recording `🧠+` would
/// make the turn its own ancestor as soon as the chat moved on.
pub fn settle(arena: Allocator, io: std.Io, dirs: config.Dirs, name: []const u8) ReadError![]const u8 {
    if (!model.is(name) and config.mobName(name) == null) return error.InvalidName;
    if (isPointer(name)) return head(arena, io, dirs, chatOf(name));
    if (isChat(name)) return head(arena, io, dirs, name);
    return name;
}

/// Every 🧠 in `records` settled, so what is written names nothing that moves.
pub fn settleAll(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    records: []const doc.Record,
) ![]const doc.Record {
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| {
        if ((r.sigil == .agent or r.sigil == .skill) and !model.is(r.value)) {
            const mob = config.mobName(r.value) orelse return error.InvalidName;
            if (dirs.mob) |scope| if (!std.mem.eql(u8, scope, mob)) return error.CrossMobReference;
        }
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
    dirs: config.Dirs,
    ptr: []const u8,
    target: []const u8,
) !void {
    const scoped = try config.pin(arena, io, dirs, ptr);
    try validateReferences(scoped, &.{.{ .sigil = .agent, .value = target }});
    try write(arena, io, scoped, ptr, &.{.{ .sigil = .agent, .value = target }});
}

/// Append stats with the saved ledger reference in the detail field.
/// The compact panel is unchanged; pointers remain authoritative.
pub fn appendStats(arena: Allocator, io: std.Io, dirs: config.Dirs, chat: []const u8, target: ?[]const u8, payload: []const u8) !void {
    const path = try logPath(arena, io, dirs, chat);
    const saved = target orelse return appendLog(arena, io, path, payload);
    const relative = std.mem.startsWith(u8, saved, chat) and saved.len > chat.len and saved[chat.len] == '/';
    const name = if (relative) saved[chat.len + 1 ..] else saved;
    const split = std.mem.indexOf(u8, payload, "::") orelse payload.len;
    const detail = if (split < payload.len) payload[split + 2 ..] else "";
    const linked = try std.fmt.allocPrint(arena, "{s}::{s}:{s}{s}", .{ payload[0..split], name, if (detail.len > 0) " " else "", detail });
    try appendLog(arena, io, path, linked);
}

/// Resolve through config's selected state root, then replace the pointer's
/// markdown filename with the sibling log filename.
pub fn logPath(arena: Allocator, io: std.Io, dirs: config.Dirs, chat: []const u8) ![]const u8 {
    const ptr = try pointerOf(arena, chat);
    const md = try config.filePath(arena, io, dirs, ptr);
    const stem = if (std.mem.endsWith(u8, md, ".md")) md[0 .. md.len - 3] else return error.InvalidName;
    return std.fmt.allocPrint(arena, "{s}.log", .{stem});
}

fn appendLog(arena: Allocator, io: std.Io, path: []const u8, value: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    const bytes = try std.fmt.allocPrint(arena, "::stats::{s}\n", .{value});
    // One append write where possible, without locking or delivery guarantees.
    const rc = std.posix.system.open(try arena.dupeZ(u8, path), .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true }, @as(std.posix.mode_t, 0o600));
    if (std.posix.errno(rc) != .SUCCESS) return error.LogOpenFailed;
    const file: std.Io.File = .{ .handle = @intCast(rc), .flags = .{ .nonblocking = false } };
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

/// Take a pointer away, from the nearest directory that has one. Nothing it
/// named is touched: a turn is never rewritten, and a chat reset is a chat
/// that goes back to reading as its parent.
pub fn unpoint(arena: Allocator, io: std.Io, dirs: config.Dirs, ptr: []const u8) !void {
    const rel = try config.nameFile(arena, ptr);
    const dir = (try config.where(arena, io, dirs, rel)) orelse return;
    try std.Io.Dir.cwd().deleteFile(io, try std.fs.path.join(arena, &.{ dir, rel }));
}

/// Names are ten lowercase letters. 26^10 is about 1.4e14, so history would need
/// millions of turns before a collision was worth thinking about — and nothing
/// here is a secret, it is a filename in a directory you own.
pub const id_len = 10;

/// A fresh turn name in the `+` folder `in`.
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
///
/// A turn's `💭snip` is kept first: what it holds goes to a snip beside the
/// turn, and the turn keeps only the 🧠 naming it. Which thoughts ask is the
/// codec's decision; that they are kept is this.
pub fn write(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    name: []const u8,
    records: []const doc.Record,
) !void {
    const scoped = try config.pin(arena, io, dirs, name);
    try validateReferences(scoped, records);
    const kept = if (isTurn(name)) try keepAside(arena, io, scoped, name, records) else records;
    return writeFile(arena, io, scoped, name, kept);
}

fn validateReferences(dirs: config.Dirs, records: []const doc.Record) !void {
    for (records) |r| {
        if ((r.sigil == .agent or r.sigil == .skill) and !model.is(r.value)) {
            const mob = config.mobName(r.value) orelse return error.InvalidName;
            if (dirs.mob) |scope| if (!std.mem.eql(u8, scope, mob)) return error.CrossMobReference;
        }
    }
}

/// The records with every `💭snip` written to a snip, and the 🧠 naming it
/// left in its place.
fn keepAside(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    turn: []const u8,
    records: []const doc.Record,
) ![]const doc.Record {
    const folder = std.fs.path.dirname(turn) orelse history;
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| try out.append(arena, if (isSnip(r))
        .{ .sigil = .agent, .value = try keepSnip(arena, io, dirs, folder, r.content.?) }
    else
        r);
    return out.items;
}

fn writeFile(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    name: []const u8,
    records: []const doc.Record,
) !void {
    const path = try config.filePath(arena, io, dirs, name);

    // A file is markdown. The rendered spelling is only ever for a terminal.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, records);

    // Written aside and renamed into place, so an interrupted run leaves the
    // file as it was rather than half of a turn, and two runs moving one `+`
    // cannot interleave — the last rename wins, and the turn that lost is
    // still in `+/`. Not synced: this is for a process that stops, not a
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

test "snip needs a block on the same thought" {
    try testing.expect(!isSnip(.{ .sigil = .thought, .value = snip }));
    try testing.expect(isSnip(.{ .sigil = .thought, .value = snip, .content = "hidden" }));
    try testing.expect(!isSnip(.{ .sigil = .thought, .value = "summary", .content = "hidden" }));
}

test "a snip is a fresh short reference" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const one = try newSnip(a.allocator(), threaded.io());
    try testing.expect(std.mem.startsWith(u8, one, snip_prefix));
    try testing.expectEqual(snip_prefix.len + id_len, one.len);
    for (one[snip_prefix.len..]) |c| try testing.expect(c >= 'a' and c <= 'z');
}

test "a name says what kind it is by its shape alone" {
    try testing.expect(!isTurn("+/abc"));
    try testing.expect(isTurn("mob/agent//chat1/+/abc"));
    try testing.expect(!isTurn("mob/agent"));
    try testing.expect(!isPointer("+"));
    try testing.expect(isPointer("mob/agent//chat1/+"));
    try testing.expect(!isTurn("mob/agent//chat1/+"));
    try testing.expect(!isPointer("mob/agent"));
    try testing.expectEqualStrings("mob/agent", chatOf("mob/agent/+"));
}

test "a turn that advances nothing goes beside its parent" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    try testing.expectEqualStrings("mob/agent//c/+", try besideParent(arena, "mob/agent//c/+/abc"));
    try testing.expectEqualStrings("mob/agent/+", try besideParent(arena, "mob/agent"));
    try testing.expectError(error.InvalidName, besideParent(arena, "/local/tiny"));
    try testing.expectError(error.InvalidName, besideParent(arena, "+/abc"));
    try testing.expectError(error.InvalidName, besideParent(arena, ""));
}

const test_tmp = @import("test_tmp.zig");

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        return .{ .io = io, .dir = try test_tmp.make(gpa, io, name) };
    }

    fn write(f: Fixture, gpa: Allocator, name: []const u8, body: []const u8) !void {
        const logical = if (std.mem.endsWith(u8, name, ".md")) name[0 .. name.len - 3] else name;
        const path = try std.fs.path.join(gpa, &.{ f.dir, try config.nameFile(gpa, logical) });
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
    try f.write(arena, "mob/agent.md", "* :brain::/local/tiny\n");
    const dirs = [_][]const u8{f.dir};

    // Nothing said yet: the agent's chat is the agent, and so is a sub chat.
    try testing.expectEqualStrings("mob/agent", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent"));
    try testing.expectEqualStrings("mob/agent", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent//c1/sub"));

    // The agent's chat moves, and a chat forked from it follows until it
    // has a pointer of its own.
    try f.write(arena, "mob/agent/+.md", "* :brain::mob/agent/+/one\n");
    try testing.expectEqualStrings("mob/agent/+/one", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent//c1"));

    // A nested authored agent is its own inheritance root, not a chat below
    // the ancestor agent, even when that ancestor has a moved head.
    try f.write(arena, "mob/agent/nested", "* :brain::/local/tiny\n");
    try testing.expectEqualStrings("mob/agent/nested", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent/nested"));
    try testing.expectEqualStrings("mob/agent/nested", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent/nested//forked"));
    try testing.expectError(error.UnknownAgent, head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent/missing"));

    try f.write(arena, "mob/agent//c1/+.md", "* :brain::mob/agent//c1/+/two\n");
    try testing.expectEqualStrings("mob/agent//c1/+/two", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent//c1/sub"));

    // Unpointing goes back to the parent, and never removes a turn.
    try unpoint(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent//c1/+");
    try testing.expectEqualStrings("mob/agent/+/one", try head(arena, f.io, config.Dirs{ .roots = &dirs }, "mob/agent//c1"));

    try testing.expectError(error.UnknownAgent, head(arena, f.io, config.Dirs{ .roots = &dirs }, "nobody/c"));
}

test "a global pointer is not a valid storage name" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-session-main");
    defer f.deinit();
    const dirs = [_][]const u8{f.dir};
    try testing.expectError(error.InvalidName, settle(arena, f.io, config.Dirs{ .roots = &dirs }, "+"));
}

test "stats log links saved stages without logging pointer changes" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-session-log");
    defer f.deinit();
    try f.write(arena, "mob/agent", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    const chat = "mob/agent//job";
    const ptr = try pointerOf(arena, chat);
    try point(arena, f.io, dirs, ptr, "mob/agent");
    try appendStats(arena, f.io, dirs, chat, "mob/agent//job/+/saved", "80::1200 in, 80 out");
    try appendStats(arena, f.io, dirs, chat, "mob/agent//job/+/saved", "80");
    try appendStats(arena, f.io, dirs, chat, null, "80::unlinked");
    try unpoint(arena, f.io, dirs, ptr);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(f.io, try logPath(arena, f.io, dirs, chat), arena, .unlimited);
    try testing.expectEqualStrings("::stats::80::+/saved: 1200 in, 80 out\n::stats::80::+/saved:\n::stats::80::unlinked\n", bytes);
    try testing.expectEqual(@as(?[]const u8, null), try deref(arena, f.io, dirs, ptr));
}
