//! Saving a turn.
//!
//! Two generated namespaces, each holding one kind of thing:
//!
//!   `=`  turns, named by chance and never rewritten
//!   `+`  aliases, named after an agent and rewritten every run
//!
//! Both are ordinary agents, so nothing here knows how to load one —
//! `agent.load` already does, and a 🧠 walks from an alias to a turn to its
//! parent without noticing the difference.
//!
//! A turn holds only its own exchange. The conversation is the chain of 🧠
//! behind it, so forking costs nothing: two turns may name one parent and
//! neither copies anything.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const config = @import("config.zig");

/// Turns. Immutable once written.
pub const history = "=";

/// Aliases into history, one per agent plus a global. Rewritten every run.
pub const alias = "+";

/// True for a name m8 generated rather than a person authored. Used to find
/// the agent a conversation is really with: the first authored name in the
/// lineage.
pub fn isGenerated(name: []const u8) bool {
    return std.mem.startsWith(u8, name, history ++ "/") or
        std.mem.startsWith(u8, name, alias ++ "/");
}

/// The agent that points at whatever was saved last. Rewritten every run, so
/// `m8 "and then?"` continues from wherever you were. It is nothing but a 🧠,
/// which is why it needs no special handling anywhere else.
///
/// The alias rewritten on every run whatever the agent. It is named `+` inside
/// `+`, so `++` reaches it under the ordinary `+X → +/X` shorthand rather than
/// needing a rule of its own.
pub const global = alias;
pub const latest = alias ++ "/" ++ global;

pub const Error = error{NoConfigDir};

/// What an alias points at now, or null when it does not exist yet. `name` is
/// the full alias name, so `+/` for the global one and `+/mathy` for an agent.
///
/// A turn records what it continues, and `+/+` is a moving pointer — so
/// lineage must name the turn itself. Recording `🧠+/+` would make the turn
/// its own ancestor as soon as the alias moved on.
pub fn deref(arena: Allocator, io: std.Io, dirs: []const []const u8, name: []const u8) !?[]const u8 {
    if (!std.mem.startsWith(u8, name, alias ++ "/")) return null;
    const file = try std.fmt.allocPrint(arena, "{s}.md", .{name});
    const src = (try config.read(arena, io, dirs, file)) orelse return null;
    var diag: doc.Diagnostic = .{};
    for (try doc.parse(arena, src, &diag)) |r| {
        if (r.sigil == .agent) return r.value;
    }
    return null;
}

/// Point the alias `+/<of>` at `target`. An empty `of` is the global alias.
pub fn setAlias(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    of: []const u8,
    target: []const u8,
) !void {
    const name = try std.fmt.allocPrint(arena, "{s}/{s}", .{ alias, of });
    try write(arena, io, dirs, name, &.{
        .{ .sigil = .agent, .value = target },
    });
}

/// Names are ten lowercase letters. 26^10 is about 1.4e14, so history would need
/// millions of turns before a collision was worth thinking about — and nothing
/// here is a secret, it is a filename in a directory you own.
pub const id_len = 10;

/// A fresh name in the `=` namespace.
pub fn newName(arena: Allocator, io: std.Io) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ history, newId(io) });
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

/// Write `records` as the agent called `name`, in the nearest config directory.
pub fn write(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    records: []const doc.Record,
) !void {
    if (dirs.len == 0) return Error.NoConfigDir;

    const rel = try std.fmt.allocPrint(arena, "{s}.md", .{name});
    const path = try std.fs.path.join(arena, &.{ dirs[0], rel });

    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |parent| cwd.createDirPath(io, parent) catch {};

    // A file is markdown. The rendered spelling is only ever for a terminal.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, records);
    try cwd.writeFile(io, .{ .sub_path = path, .data = buf.written() });
}

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
