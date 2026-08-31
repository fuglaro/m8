//! The machine against real story files.
//!
//! Everything else here is tested against tables built by hand, which proves
//! the pieces and proves nothing about the whole. This runs compiled story
//! files and diffs the transcript, which is the property the whole design
//! rests on: **ledger + story file + declared versions → byte-identical
//! transcript**. If that quietly stops holding, it has to stop
//! here rather than months of stored ledgers later.
//!
//! `testdata/m8test.inf` is this repository's own, written so the compiled
//! files could live in it. The Infocom games cannot, and a test that needs a
//! file nobody may distribute is a test that does not run — so the committed
//! one is small and ours, and the large ones are found if they happen to be
//! there.
//!
//! What it covers, in one game per version: wrapping at eighty columns, signed
//! arithmetic, the object tree, a property, `random` twice, whichever way
//! saving fails in that version, output stream 3 measuring the game's own
//! text, three lines read and tokenised, a keypress, `piracy`, `verify`
//! against the real checksum, and the header the interpreter wrote.
//!
//! `czech` is the Comprehensive Z-machine Emulation CHecker, which is four
//! hundred assertions written by somebody who read the standard more carefully
//! than anybody should. It is not committed — it is not ours — but if it is on
//! the machine it is run, and it must pass with nothing failed.

const std = @import("std");
const zm = @import("zmachine.zig");

const testing = std.testing;

const stories = struct {
    const v3 = @embedFile("testdata/m8test.z3");
    const v4 = @embedFile("testdata/m8test.z4");
    const v5 = @embedFile("testdata/m8test.z5");
    const v8 = @embedFile("testdata/m8test.z8");
    const unicode = @embedFile("testdata/unicode.z5");
};

/// The part every version says the same way. Anything that differs by version
/// is asserted beside the version that differs, so a change to one is not a
/// change to all four.
const common =
    "m8test\n" ++
    "The quick brown fox jumps over the lazy dog again and again and again until the\n" ++
    "line has to break somewhere sensible.\n" ++
    "nums -3 -1 32767 -32768\n" ++
    "obj brass lamp in cave cap 7\n" ++
    "rand 976 814\n";

fn playAll(arena: std.mem.Allocator, bytes: []const u8, inputs: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var n: usize = 0;
    while (n <= inputs.len) : (n += 1) {
        const turn = try zm.play(arena, bytes, zm.seedFrom("m8"), inputs[0..n]);
        try out.appendSlice(arena, turn.text);
        try out.append(arena, '\n');
        if (turn.ended) break;
    }
    return out.items;
}

test "a V3 story runs, and fails to save the way V3 fails" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const turn = try zm.play(arena, stories.v3, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings(common ++
        // V1–3 branch rather than store, and a false branch is how it says no.
        "save failed\n" ++
        // Stream 3 counted "measured", which the screen never saw.
        "stream3 8\n" ++
        "say> ", turn.text);
    try testing.expectEqual(zm.Wants.line, turn.wants);
    try testing.expect(!turn.ended);
}

test "a V5 story stores its refusals instead, and knows undo is impossible" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const turn = try zm.play(arena, stories.v5, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings(common ++
        // Zero is "it did not work"; minus one is "this interpreter cannot",
        // and games say different things about each.
        "save 0\n" ++
        "undo -1\n" ++
        "stream3 8\n" ++
        "say> ", turn.text);
}

test "lines are read and tokenised, and a keypress is one character" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    inline for (.{ stories.v5, stories.v8 }) |bytes| {
        const whole = try playAll(arena, bytes, &.{ "one two three", "north", "x", "y" });
        try testing.expect(std.mem.indexOf(u8, whole, "you said 3 words") != null);
        try testing.expect(std.mem.indexOf(u8, whole, "you said 1 word\n") != null);
        // 'y' as a keypress is ZSCII 121, not the word "y".
        try testing.expect(std.mem.indexOf(u8, whole, "you pressed 121") != null);
        try testing.expect(std.mem.indexOf(u8, whole, "genuine") != null);
        // The checksum is over the file as it arrived, not as we wrote on it.
        try testing.expect(std.mem.indexOf(u8, whole, "verify ok") != null);
        try testing.expect(std.mem.indexOf(u8, whole, "done") != null);
    }
}

test "V4 has read_char but no piracy, and V3 has neither" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const four = try playAll(arena, stories.v4, &.{ "a", "b", "c", "y" });
    try testing.expect(std.mem.indexOf(u8, four, "you pressed 121") != null);
    try testing.expect(std.mem.indexOf(u8, four, "genuine") == null);

    const three = try playAll(arena, stories.v3, &.{ "a", "b", "c" });
    try testing.expect(std.mem.indexOf(u8, three, "you pressed") == null);
    try testing.expect(std.mem.indexOf(u8, three, "verify ok") != null);
}

test "the header the interpreter wrote is the header the game reads" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The story prints the word at 0x20, which is the screen height in the
    // high byte and the width in the low one: 255 and 80.
    const five = try playAll(arena, stories.v5, &.{ "a", "b", "c", "y" });
    const want: i16 = @bitCast(@as(u16, 255) << 8 | 80);
    var buf: [32]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "screen {d}", .{want});
    try testing.expect(std.mem.indexOf(u8, five, line) != null);

    // V1–3 have no screen fields, so those bytes belong to nobody and are
    // left alone rather than written over.
    const three = try playAll(arena, stories.v3, &.{ "a", "b", "c" });
    try testing.expect(std.mem.indexOf(u8, three, "screen 0") != null);
}

test "the invariant: the same ledger replays to the same transcript" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const inputs = [_][]const u8{ "one two", "b", "c", "y" };
    inline for (.{ stories.v3, stories.v4, stories.v5, stories.v8 }) |bytes| {
        const once = try playAll(arena, bytes, &inputs);
        const twice = try playAll(arena, bytes, &inputs);
        try testing.expectEqualStrings(once, twice);
    }
}

test "a different first message is a different world" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The seed is the first message, so two players who said different things
    // get different rolls out of the same story file.
    const one = try zm.play(arena, stories.v5, zm.seedFrom("hello"), &.{});
    const two = try zm.play(arena, stories.v5, zm.seedFrom("hello!"), &.{});
    const same = try zm.play(arena, stories.v5, zm.seedFrom("hello"), &.{});

    try testing.expectEqualStrings(one.text, same.text);
    try testing.expect(!std.mem.eql(u8, one.text, two.text));
}

test "input the game never asked for is reported, not swallowed" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The story reads three lines and a key, then quits. A fifth message
    // arrives after the end of the world.
    const surplus = [_][]const u8{ "a", "b", "c", "y", "hello?" };
    const turn = try zm.play(arena, stories.v5, zm.seedFrom("m8"), &surplus);

    try testing.expect(turn.ended);
    try testing.expectEqual(zm.Wants.nothing, turn.wants);
    // Four were played and the fifth was not, which is what the provider
    // turns into a notice rather than a silent drop.
    try testing.expectEqual(@as(usize, 4), turn.consumed);
}

// ------------------------------------------------------- the big one

// Czech, if it is here. Not committed — it is not ours — so its absence is a
// skip rather than a failure, and its presence is four hundred assertions from
// somebody who read the standard properly.
//
// Build it with `inform -v3 czech.inf scratch/stories/czech_v3.z3` and so on
// for 4, 5 and 8.
test "czech: every assertion in the standard's own checker" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var ran: usize = 0;
    inline for (.{ "3", "4", "5", "8" }) |v| {
        const path = "scratch/stories/czech_v" ++ v ++ ".z" ++ v;
        if (std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20))) |bytes| {
            const turn = try zm.play(arena, bytes, zm.seedFrom("czech"), &.{});
            // It says how it went in its own words, and there is only one
            // acceptable number in the sentence.
            try testing.expect(std.mem.indexOf(u8, turn.text, "Failed: 0,") != null);
            try testing.expect(std.mem.indexOf(u8, turn.text, "Didn't crash: hooray!") != null);
            ran += 1;
        } else |_| {}
    }
    if (ran == 0) return error.SkipZigTest;
}

test "a character ZSCII cannot say still reaches both windows" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const turn = try zm.play(arena, stories.unicode, zm.seedFrom("m8"), &.{});

    // The grid holds one code point per cell, so π and 中 take one each and
    // what follows them is not pushed along. The scroll says the same thing.
    try testing.expect(std.mem.indexOf(u8, turn.text, "upper äπ中 end") != null);
    try testing.expect(std.mem.indexOf(u8, turn.text, "lower äπ中") != null);

    // `check_unicode` answers two questions, and here they differ: we can
    // print anything the operand can name, and can only read back what ZSCII
    // has a code for. A blanket no would make a game substitute something
    // worse than what we would have rendered.
    try testing.expect(std.mem.indexOf(u8, turn.text, "check ascii-ish 3") != null);
    try testing.expect(std.mem.indexOf(u8, turn.text, "check pi 1") != null);

    // Stream 3 is the one place that is still ZSCII, because it writes into
    // the game's own memory and the game reads those bytes back. So ä is 155
    // and π — which has no code — is a question mark, 63.
    try testing.expect(std.mem.indexOf(u8, turn.text, "stream3 len 2 first 155 second 63") != null);
}

// ------------------------------------------------------- the early ones

// V1 and V2, which no compiler still targets.
//
// Inform stops at version 3 and the only files in the wild are early Infocom
// releases nobody may distribute, so these are built here, byte by byte. What
// they are for is the paths that differ: the V1 alphabet, which has no escape
// and no newline where later ones do, and the shift *locks* of V1 and V2,
// which later versions replaced with a shift that lets go by itself.
//
// The rest of those versions is the V3 machine, and it is covered by the V3
// story above.

/// Pack Z-characters three to a word, the last one flagged.
fn packed_string(arena: std.mem.Allocator, zchars: []const u8) ![]u8 {
    const words = (zchars.len + 2) / 3;
    const bytes = try arena.alloc(u8, words * 2);
    for (0..words) |i| {
        var w: u16 = 0;
        for (0..3) |j| {
            const at = i * 3 + j;
            w = (w << 5) | @as(u16, if (at < zchars.len) zchars[at] else 5);
        }
        if (i == words - 1) w |= 0x8000;
        std.mem.writeInt(u16, bytes[i * 2 ..][0..2], w, .big);
    }
    return bytes;
}

/// A story that prints one string and stops.
fn speaker(arena: std.mem.Allocator, version: u8, zchars: []const u8) ![]u8 {
    const bytes = try zm.story.blank(arena, version, 0x400);
    const string = try packed_string(arena, zchars);
    // `print` carries its string in the instruction, so it goes straight after
    // the opcode; `quit` follows it.
    bytes[0x80] = 0xB2;
    @memcpy(bytes[0x81..][0..string.len], string);
    bytes[0x81 + string.len] = 0xBA;
    return bytes;
}

test "V1's alphabet is its own, and its shifts lock" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Z-character 4 locks into A1 in V1, so both letters come out capital:
    // later versions would shift for one and drop back for the other.
    const locked = try speaker(arena, 1, &.{ 4, 13, 14 });
    const turn = try zm.play(arena, locked, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings("HI", turn.text);

    // V1's A2 has a space where every later version has the escape, and holds
    // a `<` that they dropped. Five locks into A2, six is the space that later
    // versions gave to the escape, and 27 is entry 21, which is the `<`.
    const punct = try speaker(arena, 1, &.{ 5, 6, 27 });
    const other = try zm.play(arena, punct, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings(" <", other.text);

    // Z-character 1 is a newline in V1 and an abbreviation everywhere after.
    const broken = try speaker(arena, 1, &.{ 13, 1, 14 });
    const lines = try zm.play(arena, broken, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings("h\ni", lines.text);
}

test "V2 rotates through the alphabets and has one bank of abbreviations" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Two is a rotation upward for the next character only.
    const shifted = try speaker(arena, 2, &.{ 2, 13, 14 });
    const turn = try zm.play(arena, shifted, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings("Hi", turn.text);

    // And in V2 the escape is back, so ten bits of ZSCII say what the
    // alphabets cannot: '@' is 64.
    const escaped = try speaker(arena, 2, &.{ 5, 6, 64 >> 5, 64 & 0x1F });
    const at = try zm.play(arena, escaped, zm.seedFrom("m8"), &.{});
    try testing.expectEqualStrings("@", at.text);
}

test "a packed address is unpacked by its own version's multiplier" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The same packed operand reaches three different places, which is the
    // whole reason a V8 file may be eight times the size of a V3 one.
    for ([_]struct { v: u8, at: u32 }{
        .{ .v = 1, .at = 0x100 },
        .{ .v = 3, .at = 0x100 },
        .{ .v = 5, .at = 0x200 },
        .{ .v = 8, .at = 0x400 },
    }) |case| {
        const bytes = try zm.story.blank(arena, case.v, 0x600);
        // print_paddr 0x80, then quit.
        bytes[0x80] = 0x8D; // 1OP:13 with a large constant
        bytes[0x81] = 0x00;
        bytes[0x82] = 0x80;
        bytes[0x83] = 0xBA;
        const string = try packed_string(arena, &.{ 13, 14 }); // "hi"
        @memcpy(bytes[case.at..][0..string.len], string);

        const turn = try zm.play(arena, bytes, zm.seedFrom("m8"), &.{});
        try testing.expectEqualStrings("hi", turn.text);
    }
}
