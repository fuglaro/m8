//! The dictionary, and turning a typed line into words the game can match.
//!
//! Parsing in a Z-machine game happens in two halves, and only the first is
//! the interpreter's. We split the line into words, encode each one, look it
//! up, and write a small table of what was found where. The game does the
//! rest: what a verb is, what a noun is, and whether "take the lamp" makes
//! sense are all its business, and none of it is ours.
//!
//! The split is the interesting part, because it is not on spaces alone. A
//! dictionary declares its own word separators — commas, full stops, quote
//! marks — and each one is a word in its own right rather than a boundary that
//! disappears. That is how "put the lamp in the case, then go north" comes
//! apart into something a 1980 parser could work with.
//!
//! Words are truncated before they are looked up: six Z-characters in V1–3 and
//! nine from V4, which is why a V3 game cannot tell an adventurer from
//! adventuring. That truncation happens here, on the way in, and it is why the
//! ledger holds what was typed rather than what was matched — the raw line is
//! the input, and everything after it is derivation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Story = @import("story.zig").Story;
const text = @import("text.zig");

/// A dictionary's shape, read from its own header.
pub const Dictionary = struct {
    /// ZSCII codes that break a word and are words themselves.
    separators: []const u8,
    /// Bytes per entry: the encoded word, then whatever the game keeps there.
    entry_len: u8,
    count: u16,
    /// Where the entries begin.
    entries: u32,

    pub fn entryAt(d: Dictionary, index: u16) u32 {
        return d.entries + @as(u32, index) * d.entry_len;
    }
};

pub fn read(s: *const Story, addr: u32) Dictionary {
    const n = s.byteAt(addr);
    const seps_at = addr + 1;
    const entry_len = s.byteAt(seps_at + n);
    // The count is signed, and a negative one means the entries are not in
    // order. We search linearly either way, so the sign costs us nothing and
    // buys the unsorted dictionaries `tokenise` may be handed.
    const raw: i16 = @bitCast(s.wordAt(seps_at + n + 1));
    const count: u16 = @intCast(@abs(raw));
    return .{
        .separators = s.mem[@min(seps_at, s.mem.len)..@min(seps_at + n, s.mem.len)],
        .entry_len = entry_len,
        .count = count,
        .entries = seps_at + n + 3,
    };
}

/// Find an encoded word. Zero when the dictionary does not hold it, which is
/// the answer the game expects for a word nobody taught it.
pub fn lookup(s: *const Story, d: Dictionary, word: []const u16) u16 {
    if (d.entry_len == 0) return 0;
    var i: u16 = 0;
    while (i < d.count) : (i += 1) {
        const at = d.entryAt(i);
        var matched = true;
        for (word, 0..) |w, j| {
            if (s.wordAt(at + @as(u32, @intCast(j)) * 2) != w) {
                matched = false;
                break;
            }
        }
        if (matched) return @intCast(at);
    }
    return 0;
}

/// Whether a ZSCII code ends a word without being one.
fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == text.newline;
}

pub const Token = struct {
    /// Where the word starts in the typed text, counting from zero.
    start: usize,
    len: usize,
    /// The dictionary entry, or zero when there was no match.
    entry: u16,
};

/// Split a line into words and look each one up.
///
/// A separator is its own word, which is what makes it worth declaring: a
/// comma is not thrown away at the boundary, it is handed to the game as
/// something it can match on.
pub fn split(
    arena: Allocator,
    s: *const Story,
    d: Dictionary,
    line: []const u8,
    limit: usize,
) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    var i: usize = 0;

    while (i < line.len and tokens.items.len < limit) {
        const c = line[i];
        if (isSpace(c)) {
            i += 1;
            continue;
        }
        if (std.mem.indexOfScalar(u8, d.separators, c) != null) {
            try tokens.append(arena, .{
                .start = i,
                .len = 1,
                .entry = find(s, d, line[i .. i + 1]),
            });
            i += 1;
            continue;
        }
        const start = i;
        while (i < line.len and !isSpace(line[i]) and
            std.mem.indexOfScalar(u8, d.separators, line[i]) == null) : (i += 1)
        {}
        try tokens.append(arena, .{
            .start = start,
            .len = i - start,
            .entry = find(s, d, line[start..i]),
        });
    }
    return tokens.items;
}

/// Encode a word and look it up. Truncation happens in the encoding, which is
/// where the version already lives.
pub fn find(s: *const Story, d: Dictionary, word: []const u8) u16 {
    var buf: [3]u16 = .{ 0, 0, 0 };
    const words = text.resolution(s.version) / 3;
    text.encode(s, word, buf[0..words]);
    return lookup(s, d, buf[0..words]);
}

/// Write the parse buffer: a count, then four bytes for every word.
///
/// The four are the dictionary entry, the length, and where the word began —
/// counted in the buffer rather than in the line, which is why the offset
/// differs by one between the versions. V5 moved the text along a byte to make
/// room for a length of its own, and the parse table followed it.
pub fn writeParse(
    s: *Story,
    parse_addr: u32,
    tokens: []const Token,
    text_offset: usize,
    skip_unknown: bool,
) void {
    if (parse_addr == 0) return;
    const limit = s.byteAt(parse_addr);
    var written: u8 = 0;

    for (tokens) |t| {
        if (written >= limit) break;
        if (skip_unknown and t.entry == 0) {
            // `tokenise` may be told to leave a word it does not know alone,
            // so a game can parse a line twice through two dictionaries and
            // keep what the first one found.
            written += 1;
            continue;
        }
        const at = parse_addr + 2 + @as(u32, written) * 4;
        s.setWord(at, t.entry);
        s.setByte(at + 2, @intCast(@min(t.len, 255)));
        s.setByte(at + 3, @intCast(@min(t.start + text_offset, 255)));
        written += 1;
    }
    s.setByte(parse_addr + 1, @intCast(@min(tokens.len, limit)));
}

/// Where the typed text sits inside the text buffer, and where a word's
/// position is counted from. V1–4 put a zero terminator after the line; V5
/// keeps a length byte instead, so nothing has to be scanned to find the end.
pub fn textOffset(version: u8) usize {
    return if (version <= 4) 1 else 2;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const story_mod = @import("story.zig");

/// A dictionary holding "lamp", "take" and a comma separator.
fn withDictionary(arena: Allocator, version: u8) !Story {
    const bytes = try story_mod.blank(arena, version, 0x800);
    const at: u32 = 0x200;
    std.mem.writeInt(u16, bytes[story_mod.h.dictionary..][0..2], @intCast(at), .big);

    bytes[at] = 1; // one separator
    bytes[at + 1] = ','; // which is a comma
    const word_bytes: u8 = if (version <= 3) 4 else 6;
    bytes[at + 2] = word_bytes + 2; // entry length, with two bytes of game data
    std.mem.writeInt(u16, bytes[at + 3 ..][0..2], 3, .big); // three entries

    const s0 = try Story.load(arena, bytes);
    const entries = at + 5;
    const words = text.resolution(version) / 3;

    for ([_][]const u8{ ",", "lamp", "take" }, 0..) |w, i| {
        var buf: [3]u16 = .{ 0, 0, 0 };
        text.encode(&s0, w, buf[0..words]);
        const e = entries + i * (word_bytes + 2);
        for (buf[0..words], 0..) |x, j| {
            std.mem.writeInt(u16, bytes[e + j * 2 ..][0..2], x, .big);
        }
    }
    return try Story.load(arena, bytes);
}

test "a line comes apart into words, and a separator is one of them" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    for ([_]u8{ 3, 5 }) |version| {
        const s = try withDictionary(arena, version);
        const d = read(&s, s.dictionary());
        try testing.expectEqual(@as(u16, 3), d.count);
        try testing.expectEqualStrings(",", d.separators);

        const tokens = try split(arena, &s, d, "take lamp, please", 10);
        try testing.expectEqual(@as(usize, 4), tokens.len);

        // "take" and "lamp" are known; the comma is known because it was
        // declared; "please" is a word nobody taught this game.
        try testing.expect(tokens[0].entry != 0);
        try testing.expect(tokens[1].entry != 0);
        try testing.expect(tokens[2].entry != 0);
        try testing.expectEqual(@as(u16, 0), tokens[3].entry);

        // The comma broke the word without being swallowed by it.
        try testing.expectEqual(@as(usize, 4), tokens[1].len);
        try testing.expectEqual(@as(usize, 1), tokens[2].len);
        try testing.expectEqual(@as(usize, 9), tokens[2].start);
    }
}

test "the parse buffer holds what was found, and no more than it has room for" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var s = try withDictionary(arena, 3);
    const d = read(&s, s.dictionary());
    const tokens = try split(arena, &s, d, "take lamp", 10);

    const parse: u32 = 0x60;
    s.setByte(parse, 2); // room for two words
    writeParse(&s, parse, tokens, textOffset(3), false);

    try testing.expectEqual(@as(u8, 2), s.byteAt(parse + 1));
    try testing.expect(s.wordAt(parse + 2) != 0);
    try testing.expectEqual(@as(u8, 4), s.byteAt(parse + 4)); // "take"
    try testing.expectEqual(@as(u8, 1), s.byteAt(parse + 5)); // at buffer byte 1
    try testing.expectEqual(@as(u8, 6), s.byteAt(parse + 9)); // "lamp", byte 6

    // Room for one, so only one is written, and the count says so.
    s.setByte(parse, 1);
    writeParse(&s, parse, tokens, textOffset(3), false);
    try testing.expectEqual(@as(u8, 1), s.byteAt(parse + 1));
}

test "an unsorted dictionary is still searched, because the count says so" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 5, 0x800);
    const at: u32 = 0x200;
    std.mem.writeInt(u16, bytes[story_mod.h.dictionary..][0..2], @intCast(at), .big);
    bytes[at] = 0;
    bytes[at + 1] = 6;
    // Minus two: two entries, in no particular order.
    std.mem.writeInt(i16, bytes[at + 2 ..][0..2], -2, .big);

    const s = try Story.load(arena, bytes);
    const d = read(&s, s.dictionary());
    try testing.expectEqual(@as(u16, 2), d.count);
}
