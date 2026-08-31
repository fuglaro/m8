//! Output: four streams, two windows, and where a line breaks.
//!
//! The machine does not print to a terminal. It prints to whichever of four
//! streams are switched on — the screen, a transcript file, a table in the
//! game's own memory, and a record of commands typed — and the interesting one
//! is the third. A game uses it to measure its own text: switch output to a
//! table, print something, switch back, and read how long it was. That is not
//! decoration, it is arithmetic the game then branches on, so a stream 3 that
//! did nothing would not be a missing feature but a wrong answer. It is also
//! why the machine speaks ZSCII all the way here: stream 3 writes into the
//! game's memory, where UTF-8 would be somebody else's bytes.
//!
//! While stream 3 is on, it is the only one on. Everything else is held back,
//! including the screen, which is what makes the measurement invisible to the
//! player.
//!
//! **Where ZSCII stops.** Stream 3 is the last place that needs it, so the
//! conversion happens here, at the moment a character is written, and the two
//! screen buffers hold code points rather than bytes. That is what lets
//! `print_unicode` — which carries a code point ZSCII may have no room for —
//! take the same path as everything else instead of a special one. A buffer of
//! bytes would have to hold that character as UTF-8 and then read it back as
//! ZSCII, which turns π into õ rather than dropping it: silent corruption
//! rather than a visible gap.
//!
//! It also makes the eighty columns count characters. Wrapping over bytes
//! would give an accented letter two columns and a CJK ideograph three, which
//! is not what the header promised the game.
//!
//! The screen itself is two windows. The lower one is a scroll of text and is
//! what the transcript is made of; the upper one is a grid the game addresses
//! by row and column, and it is where a status line, a menu or a box of ASCII
//! art is drawn. A repaint may write the same cell many times in one turn,
//! which is exactly why nothing is emitted until the machine stops for input
//! at that moment the grid holds one answer rather than a history
//! of guesses, and reading it off is a pure function of where the game got to.
//!
//! Wrapping is ours rather than the game's, because the header tells the game
//! the screen is eighty columns and games believe it. Breaking at the last
//! space is not in the standard; it is what every interpreter does, and it is
//! what makes two runs of the same game diff cleanly.

const std = @import("std");
const Allocator = std.mem.Allocator;
const story_mod = @import("story.zig");
const Story = story_mod.Story;
const text = @import("text.zig");

/// How many tables stream 3 may nest. The standard says sixteen, and a game
/// that goes deeper has lost track of its own printing.
pub const max_tables = 16;

const Table = struct {
    addr: u32,
    written: u16 = 0,
};

/// What a screen buffer holds: one Unicode code point, which is one character
/// and one column. Not one byte, and not one grapheme — a combining mark takes
/// a cell it should share, and a CJK ideograph takes one where a terminal
/// would give it two. Neither happens in a Z-machine game, and the standard
/// itself counts a character as a column.
pub const Cell = u21;

/// A blank cell, and what the grid is filled with.
const blank: Cell = ' ';

pub const Screen = struct {
    arena: Allocator,
    story: *Story,
    width: usize,

    /// Committed lower-window text, newlines included.
    lower: std.ArrayList(Cell) = .empty,
    /// The line being built, not yet wide enough to have to break.
    line: std.ArrayList(Cell) = .empty,
    buffering: bool = true,

    /// The upper window, `upper_rows` rows of `width` cells.
    upper: std.ArrayList(Cell) = .empty,
    upper_rows: usize = 0,
    row: usize = 0,
    col: usize = 0,

    /// Which window printing goes to. Zero is the scroll, one is the grid.
    window: u8 = 0,

    screen_on: bool = true,
    transcript_on: bool = false,
    commands_on: bool = false,

    tables: [max_tables]Table = @splat(.{ .addr = 0 }),
    depth: usize = 0,

    pub fn init(arena: Allocator, story: *Story, width: usize) Screen {
        return .{ .arena = arena, .story = story, .width = width };
    }

    // ------------------------------------------------------------- output

    /// One ZSCII character, to wherever output is currently going.
    ///
    /// Stream 3 is answered first and in ZSCII, because it writes into the
    /// game's own memory and the game will read those bytes back. Everything
    /// past that point is a code point.
    pub fn put(s: *Screen, c: u8) !void {
        if (c == 0) return;
        if (s.depth > 0) return s.putTable(c);
        const cp = text.toUnicode(s.story, c);
        // A ZSCII code with nothing printable behind it — padding, or a code
        // the game's own translation table left empty.
        if (cp == 0) return;
        return s.write(cp);
    }

    pub fn print(s: *Screen, zscii: []const u8) !void {
        for (zscii) |c| try s.put(c);
    }

    /// A code point from `print_unicode`, which does not come through ZSCII.
    ///
    /// Only stream 3 has to care: it needs a byte, so a character ZSCII cannot
    /// say becomes a question mark there, which is the standard's own answer.
    /// The screen takes it exactly as it takes anything else.
    pub fn putUnicode(s: *Screen, cp: Cell) !void {
        if (s.depth > 0) {
            return s.putTable(text.fromUnicode(s.story, cp) orelse '?');
        }
        return s.write(cp);
    }

    /// Where both of them arrive: one character, into one of the two windows.
    fn write(s: *Screen, cp: Cell) !void {
        if (!s.screen_on) return;
        if (s.window == 1) return s.putUpper(cp);
        return s.putLower(cp);
    }

    pub fn newLine(s: *Screen) !void {
        try s.put(text.newline);
    }

    fn putTable(s: *Screen, c: u8) !void {
        const t = &s.tables[s.depth - 1];
        // The count is the first word and the characters follow it, so the
        // table grows forwards from its own header.
        s.story.setByte(t.addr + 2 + t.written, c);
        t.written +%= 1;
        s.story.setWord(t.addr, t.written);
    }

    fn putUpper(s: *Screen, c: Cell) !void {
        if (c == '\n') {
            s.col = 0;
            if (s.row + 1 < s.upper_rows) s.row += 1;
            return;
        }
        if (s.upper_rows == 0) return;
        if (s.row >= s.upper_rows) return;
        // The grid does not scroll and does not wrap. What runs off the right
        // edge is gone, which is what the standard says and what a game
        // drawing a status line into eighty columns expects.
        if (s.col >= s.width) return;
        try s.ensureUpper();
        s.upper.items[s.row * s.width + s.col] = c;
        s.col += 1;
    }

    fn putLower(s: *Screen, c: Cell) !void {
        if (c == '\n') {
            try s.lower.appendSlice(s.arena, s.line.items);
            try s.lower.append(s.arena, '\n');
            s.line.clearRetainingCapacity();
            return;
        }
        try s.line.append(s.arena, c);
        if (!s.buffering or s.line.items.len <= s.width) return;

        // The line is one character too long, so it has to break. The last
        // space is where, and the space itself goes with the break; a line
        // with no space in it at all is broken where the screen ends, since
        // the alternative is a line that lies about its width.
        const items = s.line.items;
        const at = std.mem.lastIndexOfScalar(Cell, items, blank);
        const cut = if (at != null and at.? > 0) at.? else s.width;
        const carry = if (at != null and at.? > 0) cut + 1 else cut;

        try s.lower.appendSlice(s.arena, items[0..cut]);
        try s.lower.append(s.arena, '\n');
        const rest = s.arena.dupe(Cell, items[carry..]) catch items[carry..];
        s.line.clearRetainingCapacity();
        try s.line.appendSlice(s.arena, rest);
    }

    fn ensureUpper(s: *Screen) !void {
        const want = s.upper_rows * s.width;
        while (s.upper.items.len < want) try s.upper.append(s.arena, blank);
    }

    // ------------------------------------------------------------ windows

    /// `split_window`. V3 clears the new upper window and later versions keep
    /// what was there, which is the difference between a status line redrawn
    /// every turn and a window a game builds up.
    ///
    /// Shrinking gives rows back to the scroll, and on a real screen they stay
    /// where they are until something scrolls over them — so what was on them
    /// was read. `release` puts them into the transcript, which is what a
    /// scroll is here. Curses opens by painting an epigraph into twelve rows
    /// and then shrinking to one; without this it would print nothing at all.
    pub fn splitWindow(s: *Screen, rows: usize) !void {
        const want = @min(rows, 255);
        if (want < s.upper_rows) try s.release(want);
        s.upper_rows = want;
        try s.ensureUpper();
        if (s.story.version == 3) s.clearUpper();
        if (s.window == 1 and s.row >= s.upper_rows) {
            s.row = if (s.upper_rows == 0) 0 else s.upper_rows - 1;
        }
    }

    /// Write the rows below `keep` into the scroll, and clear them.
    ///
    /// Leading and trailing blank rows are dropped and interior ones kept, so
    /// a game's own spacing survives without a screenful of nothing arriving
    /// with it. A block that is blank all through says nothing and is not
    /// worth a line — a status line shrinking to nought is the ordinary case,
    /// and it should be silent.
    fn release(s: *Screen, keep: usize) !void {
        var rows: std.ArrayList([]const Cell) = .empty;
        var r = keep;
        while (r < s.upper_rows) : (r += 1) {
            const start = r * s.width;
            if (start >= s.upper.items.len) break;
            const end = @min(start + s.width, s.upper.items.len);
            try rows.append(s.arena, trimBlank(s.upper.items[start..end]));
        }

        var first: usize = 0;
        while (first < rows.items.len and rows.items[first].len == 0) first += 1;
        var last = rows.items.len;
        while (last > first and rows.items[last - 1].len == 0) last -= 1;
        if (first == last) return;

        // In front of whatever the scroll already holds, because the upper
        // window sits above it on the screen. A game paints the top of a
        // screenful and then fills in underneath, and the order the transcript
        // wants is the order a reader's eye takes, not the order the writes
        // happened in.
        var block: std.ArrayList(Cell) = .empty;
        for (rows.items[first..last]) |row| {
            try block.appendSlice(s.arena, row);
            try block.append(s.arena, '\n');
        }
        // The line still being written is not disturbed: it is below the
        // window on the screen, and `takeLower` already puts it last.
        try s.lower.insertSlice(s.arena, 0, block.items);

        // Cleared, so a window that grows again does not hand them back twice.
        for (s.upper.items[keep * s.width ..]) |*c| c.* = blank;
    }

    fn trimBlank(row: []const Cell) []const Cell {
        var end = row.len;
        while (end > 0 and row[end - 1] == blank) end -= 1;
        return row[0..end];
    }

    /// `set_window`. Moving to the grid puts the cursor back at its corner,
    /// which is what a game drawing a status line relies on.
    pub fn setWindow(s: *Screen, which: u8) void {
        s.window = which;
        if (which == 1) {
            s.row = 0;
            s.col = 0;
        }
    }

    /// `set_cursor`, one-based, and only in the grid. The scroll has no
    /// addressable cursor outside V6, and V6 is not here.
    pub fn setCursor(s: *Screen, row: u16, col: u16) void {
        if (s.window != 1) return;
        s.row = if (row == 0) 0 else row - 1;
        s.col = if (col == 0) 0 else col - 1;
    }

    pub fn cursor(s: *const Screen) struct { row: u16, col: u16 } {
        return .{ .row = @intCast(s.row + 1), .col = @intCast(s.col + 1) };
    }

    fn clearUpper(s: *Screen) void {
        for (s.upper.items) |*c| c.* = blank;
    }

    /// `erase_window`. Minus one unsplits and clears everything, minus two
    /// clears both but leaves the split standing.
    pub fn eraseWindow(s: *Screen, which: i16) !void {
        switch (which) {
            -1 => {
                // Unsplitting is shrinking to nothing, and the rows go the
                // same way they would through `split_window 0`.
                try s.release(0);
                s.upper_rows = 0;
                s.upper.clearRetainingCapacity();
                s.window = 0;
                s.row = 0;
                s.col = 0;
            },
            -2 => s.clearUpper(),
            1 => {
                s.clearUpper();
                if (s.window == 1) {
                    s.row = 0;
                    s.col = 0;
                }
            },
            // Clearing the scroll is a screen operation, and the transcript is
            // not a screen: what has been said stays said. A game that clears
            // it is starting a fresh screenful, so we start a fresh line.
            0 => try s.breakLine(),
            else => {},
        }
    }

    /// `erase_line`: from the cursor to the right edge, in the grid only.
    pub fn eraseLine(s: *Screen) !void {
        if (s.window != 1 or s.upper_rows == 0 or s.row >= s.upper_rows) return;
        try s.ensureUpper();
        var c = s.col;
        while (c < s.width) : (c += 1) s.upper.items[s.row * s.width + c] = blank;
    }

    /// End the current line if it has anything on it. Not a newline in the
    /// game's output — a place where one was already implied.
    fn breakLine(s: *Screen) !void {
        if (s.line.items.len == 0) return;
        try s.lower.appendSlice(s.arena, s.line.items);
        try s.lower.append(s.arena, '\n');
        s.line.clearRetainingCapacity();
    }

    // ------------------------------------------------------------ streams

    /// `output_stream`. Three takes a table and nests; the rest are flags.
    pub fn outputStream(s: *Screen, which: i16, table: u32) void {
        switch (which) {
            1 => s.screen_on = true,
            -1 => s.screen_on = false,
            // Accepted and discarded. The ledger already is the transcript, so
            // a second copy would be a second copy of the same thing — but the
            // flag is readable, and a game that checks it is told the truth
            // about what it asked for.
            2, -2 => {
                s.transcript_on = which > 0;
                const at = story_mod.h.flags2;
                const bit = story_mod.flags2_transcript;
                const was = s.story.wordAt(at);
                s.story.setWord(at, if (s.transcript_on) was | bit else was & ~bit);
            },
            3 => {
                if (s.depth < max_tables) {
                    s.tables[s.depth] = .{ .addr = table };
                    s.story.setWord(table, 0);
                    s.depth += 1;
                }
            },
            -3 => {
                if (s.depth > 0) s.depth -= 1;
            },
            4 => s.commands_on = true,
            -4 => s.commands_on = false,
            else => {},
        }
    }

    pub fn bufferMode(s: *Screen, on: bool) void {
        s.buffering = on;
    }

    // ------------------------------------------------------------- taking

    /// The scroll, as UTF-8, and cleared. This is the emit boundary: whatever
    /// the game said since the last time anybody asked.
    pub fn takeLower(s: *Screen, arena: Allocator) ![]const u8 {
        try s.breakLineForTake();
        var out: std.Io.Writer.Allocating = .init(arena);
        // Nothing to translate here any more: the cells are already what they
        // mean, and a newline encodes to a newline like any other character.
        for (s.lower.items) |c| try writeCell(&out.writer, c);
        s.lower.clearRetainingCapacity();
        return out.written();
    }

    /// The pending line goes out too, without a newline of its own — the game
    /// stopped mid-line because it is waiting for the player, and the prompt
    /// it printed is that line.
    fn breakLineForTake(s: *Screen) !void {
        if (s.line.items.len == 0) return;
        try s.lower.appendSlice(s.arena, s.line.items);
        s.line.clearRetainingCapacity();
    }

    /// The grid, as UTF-8, rows trimmed of trailing spaces and empty rows kept
    /// so a game's own spacing survives. Nothing at all when there is no upper
    /// window, which is the ordinary case for a V3 game.
    pub fn upperText(s: *Screen, arena: Allocator) ![]const u8 {
        if (s.upper_rows == 0) return "";
        var out: std.Io.Writer.Allocating = .init(arena);

        var r: usize = 0;
        var any = false;
        while (r < s.upper_rows) : (r += 1) {
            const start = r * s.width;
            if (start >= s.upper.items.len) break;
            const end = @min(start + s.width, s.upper.items.len);
            const row = trimBlank(s.upper.items[start..end]);
            if (r > 0) try out.writer.writeByte('\n');
            for (row) |c| try writeCell(&out.writer, c);
            if (row.len > 0) any = true;
        }
        // A window that is all spaces is a window the game has emptied. Saying
        // nothing is better than saying a screenful of blank lines, and games
        // do shrink the window to nothing mid-play.
        if (!any) return "";
        return out.written();
    }

    /// Whether anything is waiting to be emitted, which is how the machine
    /// tells a turn that said something from a turn that did not.
    pub fn pending(s: *const Screen) bool {
        return s.lower.items.len > 0 or s.line.items.len > 0;
    }
};

/// One cell, as UTF-8. A code point that will not encode is dropped rather
/// than written as a replacement character: the machine put it there, so it is
/// our fault rather than the game's, and a mark saying "something was here"
/// would be a mark the game never printed.
fn writeCell(w: *std.Io.Writer, c: Cell) !void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(c, &buf) catch return;
    try w.writeAll(buf[0..n]);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn screenFor(arena: Allocator, version: u8, width: usize) !struct { *Story, Screen } {
    const s = try arena.create(Story);
    s.* = try Story.load(arena, try story_mod.blank(arena, version, 0x800));
    return .{ s, Screen.init(arena, s, width) };
}

test "a line breaks at the last space that fits" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 3, 20);
    var sc = pair[1];

    try sc.print("the quick brown fox jumps over it");
    try testing.expectEqualStrings(
        \\the quick brown fox
        \\jumps over it
    , try sc.takeLower(arena));
}

test "a word longer than the screen breaks where the screen ends" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 3, 10);
    var sc = pair[1];

    try sc.print("abcdefghijklmno pq");
    try testing.expectEqualStrings("abcdefghij\nklmno pq", try sc.takeLower(arena));
}

test "buffering off means the game decides where lines end" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 3, 10);
    var sc = pair[1];

    sc.bufferMode(false);
    try sc.print("aaaaaaaaaaaaaaaaaaaa");
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaa", try sc.takeLower(arena));
}

test "stream three takes the output and the screen sees none of it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 5, 80);
    const story = pair[0];
    var sc = pair[1];

    try sc.print("visible ");
    sc.outputStream(3, 0x60);
    try sc.print("measured");
    sc.outputStream(-3, 0);
    try sc.print("again");

    // The table holds its own length, then the characters.
    try testing.expectEqual(@as(u16, 8), story.wordAt(0x60));
    try testing.expectEqualStrings("measured", story.mem[0x62..0x6A]);
    // And the screen never saw them.
    try testing.expectEqualStrings("visible again", try sc.takeLower(arena));
}

test "stream three nests, and the innermost table is the one written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 5, 80);
    const story = pair[0];
    var sc = pair[1];

    sc.outputStream(3, 0x60);
    try sc.print("out");
    sc.outputStream(3, 0x80);
    try sc.print("in");
    sc.outputStream(-3, 0);
    try sc.print("er");
    sc.outputStream(-3, 0);

    try testing.expectEqual(@as(u16, 2), story.wordAt(0x80));
    try testing.expectEqualStrings("in", story.mem[0x82..0x84]);
    try testing.expectEqual(@as(u16, 5), story.wordAt(0x60));
    try testing.expectEqualStrings("outer", story.mem[0x62..0x67]);
}

test "the grid is addressed by row and column, and does not wrap" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 5, 10);
    var sc = pair[1];

    try sc.splitWindow(2);
    sc.setWindow(1);
    try sc.print("Room");
    sc.setCursor(1, 9);
    // Three characters into the last two columns: the third falls off.
    try sc.print("abc");
    sc.setCursor(2, 1);
    try sc.print("second");
    sc.setWindow(0);

    try testing.expectEqualStrings("Room    ab\nsecond", try sc.upperText(arena));

    // An emptied window says nothing rather than a screenful of blanks.
    try sc.eraseWindow(-2);
    try testing.expectEqualStrings("", try sc.upperText(arena));
}

test "unsplitting takes the grid away entirely" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const pair = try screenFor(arena, 5, 10);
    var sc = pair[1];

    try sc.splitWindow(1);
    sc.setWindow(1);
    try sc.print("status");
    try sc.eraseWindow(-1);
    try testing.expectEqualStrings("", try sc.upperText(arena));
    try testing.expectEqual(@as(u8, 0), sc.window);
}
