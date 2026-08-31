//! `/inbuilt/Z-Machine/...` — a story file, wearing a model's interface.
//!
//! The other inbuilt models answer from the last thing said. This one answers
//! from all of it, because a game has a world and the world is what the ledger
//! holds. Every call rebuilds the machine from the story file, replays every
//! 🙋 through it in order, and says what the last one produced. Nothing is kept
//! between calls, because a model api has nowhere to keep it — and once that
//! is true, the ledger is the save file, forking a chat forks the world, and
//! two runs of the same words cannot differ.
//!
//! The first 🙋 is not played. It is hashed, and the hash is the seed the
//! world is built from, which is why "hello" and "hello!" are two different
//! games and why neither of them is a game anybody else is playing.
//!
//! What is deliberately *not* read: the 🤖 records this provider wrote last
//! time. The machine's state comes from replaying the input, so a doctored
//! transcript changes nothing about the world — which is what makes handing an
//! agent a false history a test rather than a corruption.
//!
//! The machine itself is `src/zmachine/`, and it has never heard of m8.
//! `src/zmachine/README.md` is the shape of the whole.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("../../config.zig");
const doc = @import("../../m8/doc.zig");
const zm = @import("../../zmachine/zmachine.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

/// What a model name begins with to be one of these. A model whose name ends
/// in `...` in the inbuilt table serves a family, and this is that family's.
pub const prefix = "Z-Machine/";

/// Where story files are looked for, under every config directory in turn.
/// Not `core/`: a story file is data rather than a command, and `core/` is for
/// the things a cloned project must not be able to define.
pub const subdir = "models/Z-Machine";

/// What a story file may be called. Blorb containers hold one inside them and
/// are unwrapped before anything else looks.
pub const extensions = [_][]const u8{
    ".z1", ".z2",     ".z3",  ".z4",    ".z5",
    ".z6", ".z7",     ".z8",  ".dat",   ".zblorb",
    ".blb", ".blorb",
};

pub const Error = error{
    NoStoryNamed,
    NameEscapes,
    NothingToSeedWith,
};

/// Whether this model name names a story file.
///
/// Exactly, like every other name in m8. A model is named after the file it is
/// found in, so the name is the file's name and the folder's — `Z-Machine`
/// both places, and `zork1` for `zork1.z3`. Folding case here would make m8
/// the only thing in the chain that did, and would leave a name that works on
/// one machine failing on another.
pub fn serves(name: []const u8) bool {
    return std.mem.startsWith(u8, name, prefix);
}

pub fn storyName(name: []const u8) []const u8 {
    return if (serves(name)) name[prefix.len..] else name;
}

// ------------------------------------------------------------- finding it

pub const Found = struct {
    /// The file's own stem, as it is spelled on disk.
    name: []const u8,
    path: []const u8,
    bytes: []const u8,
};

/// Find a story file by name, nearest config directory first.
///
/// The name may hold a path — `infocom/trinity` — and it is taken relative to
/// each `models/Z-Machine` in turn. It may not climb out of one: a story file
/// somewhere else is named by putting it there, which is how every other file
/// in m8 comes to have a name.
///
/// The name is the file's, spelled the way the file is. m8 tries each known
/// extension after it and nothing else — no folding, no searching. A
/// case-insensitive filesystem may be kinder than that on its own account,
/// which is the filesystem's business and not a promise m8 makes.
pub fn find(ctx: Ctx, name: []const u8) !Found {
    if (name.len == 0) return Error.NoStoryNamed;
    if (std.fs.path.isAbsolute(name)) return Error.NameEscapes;
    var walk = std.mem.splitScalar(u8, name, '/');
    while (walk.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return Error.NameEscapes;
    }

    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    for (dirs) |dir| {
        const base = try std.fs.path.join(ctx.arena, &.{ dir, subdir });
        for (extensions) |ext| {
            const path = try std.fmt.allocPrint(ctx.arena, "{s}/{s}{s}", .{ base, name, ext });
            if (try readStory(ctx.arena, ctx.io, path)) |bytes| {
                return .{ .name = std.fs.path.stem(path), .path = path, .bytes = bytes };
            }
        }
    }
    return Error.NoStoryNamed;
}

fn known(ext: []const u8) bool {
    for (extensions) |e| if (std.mem.eql(u8, e, ext)) return true;
    return false;
}

fn readStory(arena: Allocator, io: std.Io, path: []const u8) !?[]const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(16 << 20)) catch return null;
    return unwrapBlorb(bytes) orelse bytes;
}

/// A Blorb is a resource file with the story inside it. Games are published
/// that way when they carry cover art, so the wrapper is common enough to be
/// worth opening — and hashing what is inside rather than the wrapper is what
/// stops a bare copy and a wrapped copy of one game looking like two.
pub fn unwrapBlorb(bytes: []const u8) ?[]const u8 {
    if (bytes.len < 12) return null;
    if (!std.mem.eql(u8, bytes[0..4], "FORM")) return null;
    if (!std.mem.eql(u8, bytes[8..12], "IFRS")) return null;

    var at: usize = 12;
    while (at + 8 <= bytes.len) {
        const id = bytes[at..][0..4];
        const len = std.mem.readInt(u32, bytes[at + 4 ..][0..4], .big);
        const start = at + 8;
        const end = std.math.add(usize, start, len) catch return null;
        if (end > bytes.len) return null;
        if (std.mem.eql(u8, id, "ZCOD")) return bytes[start..end];
        // Chunks are padded to an even length, and the padding is not counted.
        at = end + (end & 1);
    }
    return null;
}

/// Every story file that can be found, for the page. Nearest first, and a name
/// already seen is not listed again — the nearer one is what would be played.
pub fn available(ctx: Ctx) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    const dirs = config.discover(ctx.arena, ctx.io, ctx.env) catch return out.items;

    for (dirs) |dir| {
        const base = std.fs.path.join(ctx.arena, &.{ dir, subdir }) catch continue;
        var d = std.Io.Dir.cwd().openDir(ctx.io, base, .{ .iterate = true }) catch continue;
        defer d.close(ctx.io);

        var it = d.iterate();
        while (it.next(ctx.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!known(std.fs.path.extension(entry.name))) continue;
            const stem = std.fs.path.stem(entry.name);
            var seen = false;
            for (out.items) |had| {
                if (std.mem.eql(u8, had, stem)) seen = true;
            }
            if (seen) continue;
            out.append(ctx.arena, ctx.arena.dupe(u8, stem) catch continue) catch continue;
        }
    }
    // A directory hands its entries back in whatever order it keeps them,
    // which is not an order. A page that changes between two readings of it
    // is a page nobody trusts.
    //
    // Case is ignored *here* and nowhere else: this is the order a list is
    // read in rather than a rule about what matches, and Advent belongs next
    // to advent on a page somebody is scanning.
    std.mem.sort([]const u8, out.items, {}, lessThan);
    return out.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.ascii.lessThanIgnoreCase(a, b);
}

// ---------------------------------------------------------------- playing

/// Answer a request. The model name says which story file; the ledger says
/// everything else.
pub fn answer(ctx: Ctx, mode: doc.Mode, records: []const doc.Record, model: []const u8) !u8 {
    const wanted = storyName(model);
    const found = find(ctx, wanted) catch |why| {
        try ctx.err.print("m8 providers inbuilt: {s}\n", .{switch (why) {
            Error.NameEscapes => "a story file is named inside models/Z-Machine, not outside it",
            else => "no story file called that",
        }});
        try ctx.err.print("  looked for '{s}' under {s}/ in every config directory\n", .{ wanted, subdir });
        try ctx.err.writeAll("  the name is the file's own, spelled the way the file is\n");
        const have = try available(ctx);
        if (have.len == 0) {
            try ctx.err.writeAll("  there are none: put a .z3 or .z5 file there and name it\n");
        } else {
            try ctx.err.writeAll("  there is:\n");
            for (have) |one| try ctx.err.print("    /inbuilt/{s}{s}\n", .{ prefix, one });
        }
        try ctx.err.flush();
        return 1;
    };

    // Only what the player said. A 💻 belongs to whoever wrote the agent and
    // has nothing to do with the world; the 🤖 records are this provider's own
    // and replaying them would be reading our own homework.
    var said: std.ArrayList([]const u8) = .empty;
    for (records) |r| {
        if (r.sigil == .user) try said.append(ctx.arena, r.content orelse "");
    }
    if (said.items.len == 0) {
        try ctx.err.writeAll("m8 providers inbuilt: nothing to derive a seed from\n");
        try ctx.err.flush();
        return 1;
    }

    // The first message is consumed, not played: it is where the world comes
    // from. Everything after it is a turn.
    const seed = zm.seedFrom(said.items[0]);
    const inputs = said.items[1..];

    const outcome = zm.play(ctx.arena, found.bytes, seed, inputs) catch |why| {
        try ctx.err.print("m8 providers inbuilt: {s} would not run: {s}\n", .{
            found.path,
            @errorName(why),
        });
        try ctx.err.flush();
        return 1;
    };

    var body: std.Io.Writer.Allocating = .init(ctx.arena);
    if (inputs.len == 0) {
        try writeBoot(ctx.arena, &body.writer, found, outcome.text);
    } else if (outcome.consumed < inputs.len) {
        // The game ended before it had heard everything, so the rest was
        // never played, and saying so is the point: a provider that quietly
        // swallowed a message would put every later turn out of step.
        try body.writer.print(
            "[This game ended at turn {d}. The machine is replayed from the ledger\n" ++
                "every time, so it stops there however much is said afterwards, and\n" ++
                "every message from here answers exactly this. Start a new chat to\n" ++
                "play it again.]",
            .{outcome.consumed + 1},
        );
    } else {
        try body.writer.writeAll(outcome.text);
    }

    try doc.write(ctx.out, mode, .{ .sigil = .bot, .content = body.written() });
    return 0;
}

/// The first call answers with three sections in one message: what this is,
/// how to play it, and the game's own opening.
///
/// One message rather than three because m8 joins a provider's 🤖 records into
/// one before it reaches the ledger. The delimiter is what a transcript-diffing
/// tool splits on, and it splits on the first two — a game that prints `---`
/// later cannot confuse it.
fn writeBoot(
    arena: Allocator,
    w: *std.Io.Writer,
    found: Found,
    opening: []const u8,
) !void {
    var s = try zm.Story.load(arena, found.bytes);
    const p = zm.Provenance.of(found.name, found.bytes, &s);
    try p.write(w);

    try w.writeAll("\n---\n");
    try w.writeAll(
        \\Type what you want to do, a line at a time. What comes back is what the
        \\game said, exactly: this is the story file itself running, not a model
        \\describing one, so nothing is paraphrased and nothing is added.
        \\
        \\The line above each reply is the status line the game keeps.
        \\
        \\Some keys are not characters. Where one is wanted, these stand for it:
        \\
    );
    try w.print("{s}\n", .{try zm.keys.summary(arena)});
    try w.writeAll(
        \\
        \\Saving, restoring and undo are not available — this chat is the save
        \\file, and its history is the only way back. RESTART works.
    );
    try w.writeAll("\n---\n");
    try w.writeAll(opening);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a Z-Machine model is told by what its name begins with, exactly" {
    try testing.expect(serves("Z-Machine/zork1"));
    try testing.expect(serves("Z-Machine/infocom/trinity"));
    try testing.expect(!serves("eliza"));
    try testing.expect(!serves("Z-Machin"));

    // Every name in m8 is a file's name, and a file's name has a case.
    // Folding it here would make this the one place that did.
    try testing.expect(!serves("z-machine/zork1"));
    try testing.expect(!serves("Z-MACHINE/zork1"));

    try testing.expectEqualStrings("zork1", storyName("Z-Machine/zork1"));
    try testing.expectEqualStrings("infocom/trinity", storyName("Z-Machine/infocom/trinity"));
}

test "a Blorb is unwrapped, and anything else is passed through" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // FORM, a length, IFRS, then a RIdx chunk and a ZCOD chunk.
    var blorb: std.ArrayList(u8) = .empty;
    try blorb.appendSlice(arena, "FORM");
    try blorb.appendSlice(arena, &.{ 0, 0, 0, 0 });
    try blorb.appendSlice(arena, "IFRS");
    try blorb.appendSlice(arena, "RIdx");
    try blorb.appendSlice(arena, &.{ 0, 0, 0, 3 });
    try blorb.appendSlice(arena, &.{ 1, 2, 3, 0 }); // three bytes, then padding
    try blorb.appendSlice(arena, "ZCOD");
    try blorb.appendSlice(arena, &.{ 0, 0, 0, 4 });
    try blorb.appendSlice(arena, "GAME");

    try testing.expectEqualStrings("GAME", unwrapBlorb(blorb.items).?);
    try testing.expectEqual(@as(?[]const u8, null), unwrapBlorb("not a blorb at all"));
    try testing.expectEqual(@as(?[]const u8, null), unwrapBlorb("sh"));
}

test "a name may not climb out of the directory it is looked up in" {
    // The check is on the name alone, so it can be asserted without a config
    // directory anywhere near it.
    const escapes = [_][]const u8{ "../secrets", "a/../../b", "/etc/passwd" };
    for (escapes) |name| {
        var bad = false;
        if (std.fs.path.isAbsolute(name)) bad = true;
        var walk = std.mem.splitScalar(u8, name, '/');
        while (walk.next()) |part| {
            if (std.mem.eql(u8, part, "..")) bad = true;
        }
        try testing.expect(bad);
    }
}
