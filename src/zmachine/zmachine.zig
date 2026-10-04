//! The Z-machine, as one thing.
//!
//! Everything under this file is a virtual machine and knows nothing about m8:
//! it loads a story file, runs it, and hands back text. That boundary is not
//! tidiness. The machine cannot reach a ledger, so it cannot accidentally
//! become stateful; the provider cannot reach the machine's insides, so replay
//! is the only way it can get state. Each half is prevented from cheating by
//! not being able to.
//!
//! What is here is the seam itself: what a caller needs in order to play a
//! story file from a list of things somebody typed.
//!
//! `play` is the whole interface, and it takes the inputs rather than a
//! machine, because there is no machine between calls. It builds one, replays
//! every line through it, and answers with what the last line produced. A
//! hundred turns of Zork replays in a few milliseconds, which is what makes
//! the statelessness affordable rather than merely correct.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const dict = @import("dict.zig");
pub const keys = @import("keys.zig");
pub const machine = @import("machine.zig");
pub const object = @import("object.zig");
pub const screen = @import("screen.zig");
pub const story = @import("story.zig");
pub const text = @import("text.zig");

comptime {
    // The machine against real story files, which is the only test that can
    // tell the pieces working from the whole working.
    _ = @import("integration.zig");
}

pub const Machine = machine.Machine;
pub const Story = story.Story;

/// The interpreter's semantic version: a hash of the sources that decide what
/// a replay produces.
///
/// A bug fix in the machine legitimately changes output, and a stored ledger
/// that replays differently afterwards is not corrupt — it is a different
/// interpreter. Saying which one produced a transcript is what makes the
/// difference detectable rather than mysterious. The hash is over the source
/// rather than a number somebody remembers to bump, because somebody does not.
///
/// It is worked out while compiling, so the binary carries twelve characters
/// rather than the sources they were made from. A checksum, not an identity:
/// it says two interpreters differ, which is all a replay needs to be told.
pub fn semantic(out: *[12]u8) void {
    out.* = comptime stamp();
}

fn stamp() [12]u8 {
    @setEvalBranchQuota(100_000_000);
    var h = std.hash.Wyhash.init(0);
    for (.{
        @embedFile("story.zig"),
        @embedFile("text.zig"),
        @embedFile("object.zig"),
        @embedFile("dict.zig"),
        @embedFile("screen.zig"),
        @embedFile("keys.zig"),
        @embedFile("machine.zig"),
        @embedFile("zmachine.zig"),
    }) |source| h.update(source);

    var out: [12]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x:0>12}", .{h.final() >> 16}) catch unreachable;
    return out;
}

/// What is running, and the whole of what a stored ledger needs in order to be
/// replayable later. All of it is derived from the file, so none of it can
/// drift from the thing it describes.
///
/// It goes out as a 💭 rather than as part of the 🤖, because it is the
/// interpreter's note about how the answer was produced and not something the
/// game says to the player. That also leaves the 🤖 naming no story file and
/// no machine, so a provider serving a procedurally generated world says the
/// same words and only this changes.
pub const Provenance = struct {
    /// What the file was called, since a story file does not hold its title.
    /// The game's own banner says the rest, and it is in the boot output.
    name: []const u8,
    version: u8,
    release: u16,
    serial: []const u8,
    /// A checksum of the file, enough to say a replay met a different one.
    checksum: [16]u8,
    semantic: [12]u8,

    pub fn of(name: []const u8, bytes: []const u8, s: *const Story) Provenance {
        var p: Provenance = .{
            .name = name,
            .version = s.version,
            .release = s.release(),
            .serial = s.serial(),
            .checksum = undefined,
            .semantic = undefined,
        };
        _ = std.fmt.bufPrint(&p.checksum, "{x:0>16}", .{std.hash.Wyhash.hash(0, bytes)}) catch {};
        semantic(&p.semantic);
        return p;
    }

    pub fn write(p: Provenance, w: *std.Io.Writer) !void {
        try w.print("Loading {s} (Release {d} / Serial {s} / hash:{s})\n", .{
            p.name,
            p.release,
            p.serial,
            p.checksum,
        });
        // No seed derivation here. The rule lives in this file and this file
        // is in the semantic hash, so it cannot change without the hash
        // changing — a second number saying so would only be a number
        // somebody has to remember to bump.
        try w.print("on Z-machine v{d} (m8-{s}).", .{ p.version, p.semantic });
    }
};

/// The seed, from the player's first message and nothing else.
///
/// The interpreter's own boot text is deliberately not hashed: revising a
/// welcome message would otherwise silently change every world every stored
/// ledger describes, and nobody would think to look there.
pub fn seedFrom(message: []const u8) [8]u8 {
    var seed: [8]u8 = undefined;
    std.mem.writeInt(u64, &seed, std.hash.Wyhash.hash(0, message), .little);
    return seed;
}

pub const Wants = enum { line, char, nothing };

pub const Outcome = struct {
    /// The status line and what the game said, as one chunk.
    text: []const u8,
    /// The game has stopped and no further input will change that.
    ended: bool,
    wants: Wants,
    /// How many of the inputs the machine actually took. Fewer than it was
    /// given means the game ended part way through, which is reported rather
    /// than hidden — silently swallowing a message would put every later turn
    /// out of step with the ledger that produced it.
    consumed: usize,
};

/// Play a story file from the beginning, feeding it every line in turn, and
/// answer with what the last one produced.
///
/// The machine is built here, used here, and dropped here. Nothing survives
/// the call, which is why nothing has to be serialised and why two runs of the
/// same inputs cannot differ.
pub fn play(
    arena: Allocator,
    bytes: []const u8,
    seed: [8]u8,
    inputs: []const []const u8,
) !Outcome {
    const m = try Machine.create(arena, bytes, seed);
    var stop = try m.run();
    var consumed: usize = 0;

    for (inputs) |input| {
        if (m.finished) break;
        switch (stop) {
            .line_input => {
                // A single symbol that the game declared as a terminating key
                // ends the line where it stands. Anything else is a line, even
                // when it holds the same symbol somewhere inside it. Context
                // decides and there is no escape, which is the whole of it.
                if (keys.only(input)) |code| {
                    if (keys.terminates(&m.story, code)) {
                        try m.feedLineTerminated("", code);
                    } else {
                        try m.feedLine(input);
                    }
                } else {
                    try m.feedLine(input);
                }
            },
            .char_input => try m.feedChar(keys.press(&m.story, input)),
            .quit => break,
        }
        consumed += 1;
        // Everything printed since the last time anybody looked is this turn's
        // output, and the one before it has already been taken.
        _ = try m.screen.takeLower(arena);
        stop = try m.run();
    }

    const rendered = try render(arena, m);
    return .{
        .text = rendered,
        .ended = m.finished,
        .wants = switch (stop) {
            .line_input => .line,
            .char_input => .char,
            .quit => .nothing,
        },
        .consumed = consumed,
    };
}

/// Status line first, then what the game said. One chunk, and the ledger does
/// not record which part came from where.
fn render(arena: Allocator, m: *Machine) ![]const u8 {
    const status = if (m.story.version <= 3)
        try statusLine(arena, m)
    else
        try m.screen.upperText(arena);

    // Taken either way: the buffer has to be cleared whether or not anybody
    // wanted what was in it.
    const body = try m.screen.takeLower(arena);
    if (status.len == 0) return body;
    if (body.len == 0) return status;
    return std.mem.concat(arena, u8, &.{ status, "\n", body });
}

/// The V1–3 status line, synthesised from the three globals the machine
/// reserves for it.
///
/// A real interpreter drew this into a strip at the top of the screen and
/// redrew it whenever the game said `show_status`. There is no strip here, so
/// it is regenerated from the same globals at the moment of emission — which
/// makes `show_status` a no-op rather than a thing to buffer, and makes the
/// line a function of where the game got to rather than of when it last
/// remembered to ask.
pub fn statusLine(arena: Allocator, m: *Machine) ![]const u8 {
    const globals = m.story.globals();
    const room = m.story.wordAt(globals);
    const first: i16 = @bitCast(m.story.wordAt(globals + 2));
    const second: i16 = @bitCast(m.story.wordAt(globals + 4));

    const where = try object.name(&m.story, arena, room);
    if (where.len == 0 and room == 0) return "";

    var name: std.Io.Writer.Allocating = .init(arena);
    for (where) |c| try text.writeUtf8(&name.writer, &m.story, c);

    const right = if (m.story.timeGame())
        try std.fmt.allocPrint(arena, "Time: {d}:{d:0>2} {s}", .{
            hourOfClock(first),
            @as(u16, @intCast(@mod(second, 60))),
            if (@mod(first, 24) < 12) "am" else "pm",
        })
    else
        try std.fmt.allocPrint(arena, "Score: {d}  Moves: {d}", .{ first, second });

    const width = story.profile.screen_width;
    var out: std.Io.Writer.Allocating = .init(arena);
    try out.writer.writeByte(' ');

    const left = name.written();
    // The room name gives way when there is not enough line for both. What is
    // on the right is a number the player is tracking; what is on the left
    // they can also see in the room description.
    const room_room = width -| (right.len + 2);
    const shown = left[0..@min(left.len, room_room)];
    try out.writer.writeAll(shown);

    const pad = width -| (1 + shown.len + right.len);
    try out.writer.splatByteAll(' ', pad);
    try out.writer.writeAll(right);
    return std.mem.trimEnd(u8, out.written(), " ");
}

fn hourOfClock(hours: i16) u16 {
    const h = @mod(hours, 24);
    if (h == 0) return 12;
    if (h > 12) return @intCast(h - 12);
    return @intCast(h);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the semantic version is a hash of what decides a replay" {
    var a: [12]u8 = undefined;
    var b: [12]u8 = undefined;
    semantic(&a);
    semantic(&b);
    try testing.expectEqualStrings(&a, &b);
    for (a) |c| try testing.expect(std.ascii.isHex(c));
}

test "the seed comes from the message and nothing else" {
    const one = seedFrom("Hi I want to play");
    const two = seedFrom("Hi I want to play");
    const other = seedFrom("Hi I want to play.");
    try testing.expectEqualSlices(u8, &one, &two);
    try testing.expect(!std.mem.eql(u8, &one, &other));
}

test "a status line puts the room on the left and the score on the right" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story.blank(arena, 3, 0x800);
    // One object, whose name is "hi", and globals pointing at it.
    const base: u32 = 0x100;
    std.mem.writeInt(u16, bytes[story.h.objects..][0..2], @intCast(base), .big);
    const e = base + 31 * 2;
    std.mem.writeInt(u16, bytes[e + 7 ..][0..2], 0x400, .big);
    bytes[0x400] = 1; // one word of name
    std.mem.writeInt(u16, bytes[0x401..][0..2], 0xB5C5, .big); // "hi"
    bytes[0x403] = 0;

    // G00 is the room, G01 the score, G02 the moves.
    std.mem.writeInt(u16, bytes[0x40..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[0x42..][0..2], 25, .big);
    std.mem.writeInt(u16, bytes[0x44..][0..2], 7, .big);

    const m = try Machine.create(arena, bytes, @splat(0));
    const line = try statusLine(arena, m);
    try testing.expectEqualStrings(" hi", line[0..3]);
    try testing.expect(std.mem.endsWith(u8, line, "Score: 25  Moves: 7"));
    try testing.expectEqual(@as(usize, 80), line.len);
}

test "a time game says the clock instead" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story.blank(arena, 3, 0x800);
    bytes[story.h.flags1] = 0x02; // this one keeps time
    const base: u32 = 0x100;
    std.mem.writeInt(u16, bytes[story.h.objects..][0..2], @intCast(base), .big);
    const e = base + 31 * 2;
    std.mem.writeInt(u16, bytes[e + 7 ..][0..2], 0x400, .big);
    bytes[0x400] = 1;
    std.mem.writeInt(u16, bytes[0x401..][0..2], 0xB5C5, .big);
    bytes[0x403] = 0;

    std.mem.writeInt(u16, bytes[0x40..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[0x42..][0..2], 20, .big); // 8 in the evening
    std.mem.writeInt(u16, bytes[0x44..][0..2], 5, .big);

    const m = try Machine.create(arena, bytes, @splat(0));
    const line = try statusLine(arena, m);
    try testing.expect(std.mem.endsWith(u8, line, "Time: 8:05 pm"));

    try testing.expectEqual(@as(u16, 12), hourOfClock(0));
    try testing.expectEqual(@as(u16, 12), hourOfClock(12));
    try testing.expectEqual(@as(u16, 1), hourOfClock(13));
}
