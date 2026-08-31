//! Keys that are not characters.
//!
//! ZSCII has room for cursor keys, function keys and a numeric keypad in the
//! same numeric space as letters, and a game may read one directly. A chat has
//! no keyboard, so each of those gets a character that looks like the key it
//! stands for: ↑ for cursor up, ① for F1, ０ for keypad zero. They are
//! typeable, they are legible, and none of them collides with anything a
//! player would otherwise type.
//!
//! The keypad digits are full-width rather than ordinary ones because a game
//! can tell "pressed 5" from "pressed keypad 5", and a mapping that could not
//! would be answering a question the game did not ask.
//!
//! What decides whether ↑ is a keypress or a character is context, and there
//! is no escape hatch. A message that is *exactly* one symbol, when the game
//! is waiting for a single key, is that key; the same symbol inside a line is
//! a character in the line. That rule is not explained to the player, in the
//! same way a real terminal does not explain that pressing an arrow key does
//! something different at a menu than in a sentence. Working it out is part of
//! the task.

const std = @import("std");
const Story = @import("story.zig").Story;
const text = @import("text.zig");

pub const Key = struct {
    zscii: u8,
    symbol: []const u8,
    what: []const u8,
};

/// Every input-only code that has a symbol. Ordinary printable characters are
/// not here: they say themselves.
pub const table = [_]Key{
    .{ .zscii = 129, .symbol = "↑", .what = "cursor up" },
    .{ .zscii = 130, .symbol = "↓", .what = "cursor down" },
    .{ .zscii = 131, .symbol = "←", .what = "cursor left" },
    .{ .zscii = 132, .symbol = "→", .what = "cursor right" },
    .{ .zscii = 133, .symbol = "①", .what = "F1" },
    .{ .zscii = 134, .symbol = "②", .what = "F2" },
    .{ .zscii = 135, .symbol = "③", .what = "F3" },
    .{ .zscii = 136, .symbol = "④", .what = "F4" },
    .{ .zscii = 137, .symbol = "⑤", .what = "F5" },
    .{ .zscii = 138, .symbol = "⑥", .what = "F6" },
    .{ .zscii = 139, .symbol = "⑦", .what = "F7" },
    .{ .zscii = 140, .symbol = "⑧", .what = "F8" },
    .{ .zscii = 141, .symbol = "⑨", .what = "F9" },
    .{ .zscii = 142, .symbol = "⑩", .what = "F10" },
    .{ .zscii = 143, .symbol = "⑪", .what = "F11" },
    .{ .zscii = 144, .symbol = "⑫", .what = "F12" },
    .{ .zscii = 145, .symbol = "０", .what = "keypad 0" },
    .{ .zscii = 146, .symbol = "１", .what = "keypad 1" },
    .{ .zscii = 147, .symbol = "２", .what = "keypad 2" },
    .{ .zscii = 148, .symbol = "３", .what = "keypad 3" },
    .{ .zscii = 149, .symbol = "４", .what = "keypad 4" },
    .{ .zscii = 150, .symbol = "５", .what = "keypad 5" },
    .{ .zscii = 151, .symbol = "６", .what = "keypad 6" },
    .{ .zscii = 152, .symbol = "７", .what = "keypad 7" },
    .{ .zscii = 153, .symbol = "８", .what = "keypad 8" },
    .{ .zscii = 154, .symbol = "９", .what = "keypad 9" },
    .{ .zscii = 27, .symbol = "⎋", .what = "escape" },
    .{ .zscii = 13, .symbol = "⏎", .what = "return" },
    .{ .zscii = 8, .symbol = "⌫", .what = "delete" },
};

/// The ZSCII code a message stands for, when the message is *exactly* one
/// symbol and nothing else. Whitespace around it is forgiven, because a chat
/// client is entitled to add some; anything else is not a keypress.
pub fn only(message: []const u8) ?u8 {
    const trimmed = std.mem.trim(u8, message, " \t\r\n");
    for (table) |k| {
        if (std.mem.eql(u8, trimmed, k.symbol)) return k.zscii;
    }
    return null;
}

/// What a message means when the game is waiting for a single keypress.
///
/// A symbol is that key. Anything else is read as its first character, which
/// is what a player pressing "y" at a yes-or-no prompt means and what typing a
/// whole word at one means too. A message with nothing the machine can say in
/// it becomes Return, since the game asked for a key and is owed one.
pub fn press(s: *const Story, message: []const u8) u8 {
    if (only(message)) |code| return code;
    // Only the line ending is forgiven here. A space is a key somebody can
    // press, and trimming it away would answer a different question than the
    // one the player asked.
    const trimmed = std.mem.trim(u8, message, "\r\n");
    var it = std.unicode.Utf8Iterator{ .bytes = trimmed, .i = 0 };
    while (it.nextCodepoint()) |cp| {
        if (text.fromUnicode(s, cp)) |code| return code;
    }
    return text.newline;
}

/// Whether a game has declared this key as one that ends a line of input.
///
/// V5 lets a story name the keys it wants to hear about mid-line — a menu that
/// responds to the arrow keys without waiting for Return. 255 in the table
/// means every function key at once, which is the shorthand most games use.
pub fn terminates(s: *const Story, code: u8) bool {
    const table_at = s.terminatingTable();
    if (table_at == 0) return false;
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        const entry = s.byteAt(table_at + i);
        if (entry == 0) return false;
        if (entry == 255) return isFunction(code);
        if (entry == code) return true;
    }
    return false;
}

/// The function keys, as the standard counts them: the cursor keys, F1 to F12,
/// the keypad, and the mouse codes we do not have.
pub fn isFunction(code: u8) bool {
    return (code >= 129 and code <= 154) or (code >= 252 and code <= 254);
}

/// A line of the symbols, for the instructions the player is given at the
/// start. Grouped rather than listed one per line, because it is a warmup and
/// not a manual.
pub fn summary(arena: std.mem.Allocator) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    try out.writer.writeAll("↑ ↓ ← → are the cursor keys, ⏎ Return, ⎋ Escape, ⌫ Delete,\n");
    try out.writer.writeAll("① to ⑫ are F1 to F12, and ０ to ９ are the numeric keypad.");
    return out.written();
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const story_mod = @import("story.zig");

test "a message that is exactly one symbol is that key, and nothing else is" {
    try testing.expectEqual(@as(?u8, 129), only("↑"));
    try testing.expectEqual(@as(?u8, 129), only("  ↑\n"));
    try testing.expectEqual(@as(?u8, 133), only("①"));
    try testing.expectEqual(@as(?u8, 145), only("０"));
    try testing.expectEqual(@as(?u8, 13), only("⏎"));

    // Inside anything at all, it is a character rather than a key.
    try testing.expectEqual(@as(?u8, null), only("go ↑"));
    try testing.expectEqual(@as(?u8, null), only("↑↑"));
    try testing.expectEqual(@as(?u8, null), only("north"));

    // The keypad digits are not the ordinary ones, which is the whole reason
    // they are full-width.
    try testing.expectEqual(@as(?u8, null), only("0"));
}

test "a keypress falls back to the first character the machine can say" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const s = try story_mod.Story.load(arena, try story_mod.blank(arena, 5, 0x400));
    try testing.expectEqual(@as(u8, 'y'), press(&s, "yes"));
    try testing.expectEqual(@as(u8, 'y'), press(&s, "yes\n"));
    // Space is a key, so it survives where a line ending would not.
    try testing.expectEqual(@as(u8, ' '), press(&s, " "));
    try testing.expectEqual(@as(u8, 129), press(&s, "↑"));
    // Nothing sayable at all, so Return: the game asked for a key.
    try testing.expectEqual(@as(u8, 13), press(&s, "中"));
    try testing.expectEqual(@as(u8, 13), press(&s, ""));
}

test "a game may declare which keys end a line, and 255 means all of them" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 5, 0x400);
    std.mem.writeInt(u16, bytes[story_mod.h.terminating..][0..2], 0x120, .big);
    bytes[0x120] = 129; // cursor up
    bytes[0x121] = 0;
    const s = try story_mod.Story.load(arena, bytes);

    try testing.expect(terminates(&s, 129));
    try testing.expect(!terminates(&s, 130));
    try testing.expect(!terminates(&s, 'a'));

    const all = try story_mod.blank(arena, 5, 0x400);
    std.mem.writeInt(u16, all[story_mod.h.terminating..][0..2], 0x120, .big);
    all[0x120] = 255;
    all[0x121] = 0;
    const every = try story_mod.Story.load(arena, all);
    try testing.expect(terminates(&every, 130));
    try testing.expect(terminates(&every, 144));
    try testing.expect(!terminates(&every, 'a'));

    // A game that declared nothing terminates on nothing but Return, which
    // never reaches this question.
    const none = try story_mod.Story.load(arena, try story_mod.blank(arena, 5, 0x400));
    try testing.expect(!terminates(&none, 129));
}
