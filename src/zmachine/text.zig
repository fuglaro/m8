//! Z-strings, alphabets and ZSCII.
//!
//! Text is the grind, and it is the grind because it was designed in 1979 to
//! fit a game into a floppy disc. Three Z-characters are packed into each
//! sixteen-bit word, five bits each, with the top bit marking the last word of
//! a string. Those five bits address one of three alphabet tables, and moving
//! between the tables is done with characters that are not characters —
//! shifts, shift locks in the early versions, and abbreviation escapes that
//! splice in a string from a table elsewhere. A character outside every
//! alphabet is written as an escape followed by two more Z-characters holding
//! the ten bits of a ZSCII code.
//!
//! ZSCII is not Unicode and not quite ASCII: 32–126 are ASCII, 13 is the only
//! newline, and 155–251 hold accented letters through a translation table the
//! game may replace. So the machine speaks ZSCII from end to end and converts
//! only where it must — at the screen, where bytes become UTF-8, and at the
//! keyboard, where they stop being it. Output stream 3 writes into the game's
//! own memory and therefore writes ZSCII, which is the reason the conversion
//! cannot happen any earlier than it does.
//!
//! Versions 1 and 2 are special-cased rather than generalised. Their alphabet
//! differs in a handful of places and their shifts rotate where later versions
//! only lean, and a general mechanism covering all of it would be harder to
//! read than the two exceptions it hid.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Story = @import("story.zig").Story;

/// The alphabets, as ZSCII. Index by Z-character minus six.
pub const a0 = "abcdefghijklmnopqrstuvwxyz";
pub const a1 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
/// Position 0 is the escape rather than a character, and position 1 is the
/// only newline the machine has — ZSCII 13, not the 10 every other format on
/// this machine means by it. The rest is punctuation, in an order chosen by
/// whoever was counting bytes that week.
pub const a2 = "\x00\x0D0123456789.,!?_#'\"/\\-:()";
/// Version 1 had no escape and no newline here, and one character later
/// versions dropped. It is a different table rather than a variation on one.
pub const a2_v1 = " 0123456789.,!?_#'\"/\\<-:()";

/// ZSCII's own newline. Not 10, and not the platform's.
pub const newline: u8 = 13;

pub const Alphabet = enum(u2) { a0, a1, a2 };

/// What a decoded string is written to. The machine prints ZSCII and converts
/// at the edges, so this is bytes rather than code points.
pub const Sink = struct {
    ctx: *anyopaque,
    put: *const fn (*anyopaque, u8) anyerror!void,

    pub fn write(s: Sink, c: u8) anyerror!void {
        return s.put(s.ctx, c);
    }
};

/// Read one Z-character alphabet entry, honouring a game's own alphabet table.
///
/// V5 lets a story replace all three alphabets with seventy-eight bytes of its
/// own. Position 0 of A2 stays the escape whatever the table says, because the
/// escape is how the encoding says "not a character" and a table cannot take
/// that back without making some strings unreadable.
fn alphabetChar(s: *const Story, which: Alphabet, index: u8) u8 {
    // Every version from 2 keeps that slot for the escape rather than a
    // character. Version 1 had no escape and put a space there, which is one
    // of the two reasons its A2 is a different table rather than a variant.
    if (which == .a2 and index == 0 and s.version >= 2) return 0;

    const table = s.alphabetTable();
    if (table != 0) {
        const at = table + @as(u32, @intFromEnum(which)) * 26 + index;
        return s.byteAt(at);
    }
    const row = switch (which) {
        .a0 => a0,
        .a1 => a1,
        .a2 => if (s.version == 1) a2_v1 else a2,
    };
    return row[index];
}

/// How many abbreviation banks a version has. V1 has none — its Z-character 1
/// is a newline — V2 has one, and V3 onwards have three.
fn abbreviationBanks(version: u8) u8 {
    return switch (version) {
        1 => 0,
        2 => 1,
        else => 3,
    };
}

pub const Decoded = struct {
    /// How many bytes of memory the string occupied, so a caller walking a
    /// table knows where the next one starts.
    len: u32,
};

/// Decode the Z-string at `addr`, writing ZSCII to `sink`.
pub fn decode(s: *const Story, addr: u32, sink: Sink) anyerror!Decoded {
    return decodeDepth(s, addr, sink, 0);
}

fn decodeDepth(s: *const Story, addr: u32, sink: Sink, depth: u8) anyerror!Decoded {
    var at = addr;
    var alphabet: Alphabet = .a0;
    // V1 and V2 lock; V3 onward only ever shift for one character, which is
    // the same mechanism with the lock always released.
    var locked: Alphabet = .a0;
    var pending: ?u8 = null; // an abbreviation bank waiting for its index
    var escape: u8 = 0; // 0 none, 1 waiting for the top five bits, 2 the rest
    var escape_top: u8 = 0;

    while (true) {
        const word = s.wordAt(at);
        at += 2;
        const chars = [3]u8{
            @intCast((word >> 10) & 0x1F),
            @intCast((word >> 5) & 0x1F),
            @intCast(word & 0x1F),
        };

        for (chars) |z| {
            if (escape == 1) {
                escape_top = z;
                escape = 2;
                continue;
            }
            if (escape == 2) {
                escape = 0;
                const code: u16 = (@as(u16, escape_top) << 5) | z;
                // Ten bits can say more than ZSCII has room for. What is over
                // the top is a story file saying something the machine has no
                // way to hear, and dropping it is the only honest answer.
                if (code <= 0xFF) try sink.write(@intCast(code));
                continue;
            }
            if (pending) |bank| {
                pending = null;
                // An abbreviation may not contain one. The standard forbids
                // it; the depth guard is here so a story file that does it
                // anyway stops rather than recurses until the stack is gone.
                if (depth == 0) {
                    const index: u32 = 32 * (@as(u32, bank) - 1) + z;
                    const entry = s.abbreviations() + index * 2;
                    // Abbreviation addresses are word addresses, doubled
                    // whatever the version — the packing scale is for routines
                    // and strings, and this is neither.
                    _ = try decodeDepth(s, @as(u32, s.wordAt(entry)) * 2, sink, depth + 1);
                }
                continue;
            }

            switch (z) {
                0 => try sink.write(' '),
                1 => {
                    if (s.version == 1) {
                        try sink.write(newline);
                    } else if (abbreviationBanks(s.version) >= 1) {
                        pending = 1;
                    }
                },
                2, 3 => {
                    if (s.version <= 2) {
                        // The early machines rotate: two goes up the ring and
                        // three goes down it, for the next character only.
                        alphabet = rotate(locked, z == 2);
                    } else {
                        pending = z;
                    }
                },
                4, 5 => {
                    if (s.version <= 2) {
                        locked = rotate(locked, z == 4);
                        alphabet = locked;
                    } else {
                        alphabet = if (z == 4) .a1 else .a2;
                    }
                },
                else => {
                    const index: u8 = z - 6;
                    if (alphabet == .a2 and index == 0 and s.version >= 2) {
                        escape = 1;
                    } else {
                        const c = alphabetChar(s, alphabet, index);
                        if (c != 0) try sink.write(c);
                    }
                    alphabet = locked;
                },
            }
        }

        if ((word & 0x8000) != 0) break;
        // A string that never sets its top bit would walk to the end of
        // memory. Stopping at the edge keeps a broken file from becoming a
        // broken interpreter.
        if (at >= s.mem.len) break;
    }

    return .{ .len = at - addr };
}

/// Round the ring of three: two goes up it and three goes down, which is how
/// V1 and V2 reach an alphabet rather than naming one.
///
/// The arithmetic is widened before it is done. Three alphabets fit in two
/// bits exactly, which leaves no room to add to the last one and come back
/// round — the wrap has to happen after the addition, not during it.
fn rotate(from: Alphabet, up: bool) Alphabet {
    const n: u8 = @intFromEnum(from);
    const next: u8 = if (up) (n + 1) % 3 else (n + 2) % 3;
    return @enumFromInt(@as(u2, @intCast(next)));
}

/// Decode into a freshly allocated ZSCII string. For dictionary words, object
/// names and anything else the machine reads rather than prints.
pub fn decodeAlloc(arena: Allocator, s: *const Story, addr: u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var c: Collector = .{ .arena = arena, .out = &out };
    _ = try decode(s, addr, c.sink());
    return out.items;
}

const Collector = struct {
    arena: Allocator,
    out: *std.ArrayList(u8),

    fn sink(self: *Collector) Sink {
        return .{ .ctx = self, .put = put };
    }
    fn put(ctx: *anyopaque, c: u8) anyerror!void {
        const self: *Collector = @ptrCast(@alignCast(ctx));
        try self.out.append(self.arena, c);
    }
};

// ------------------------------------------------------------- ZSCII text

/// The default translation for ZSCII 155–251, which is where the accented
/// letters live. A game may replace it through the header extension table; the
/// codes above 223 have no default and are the game's business alone.
pub const default_unicode = [_]u21{
    0xE4, 0xF6, 0xFC, 0xC4, 0xD6, 0xDC, 0xDF, 0xBB, 0xAB, 0xEB, // 155
    0xEF, 0xFF, 0xCB, 0xCF, 0xE1, 0xE9, 0xED, 0xF3, 0xFA, 0xFD, // 165
    0xC1, 0xC9, 0xCD, 0xD3, 0xDA, 0xDD, 0xE0, 0xE8, 0xEC, 0xF2, // 175
    0xF9, 0xC0, 0xC8, 0xCC, 0xD2, 0xD9, 0xE2, 0xEA, 0xEE, 0xF4, // 185
    0xFB, 0xC2, 0xCA, 0xCE, 0xD4, 0xDB, 0xE5, 0xC5, 0xF8, 0xD8, // 195
    0xE3, 0xF1, 0xF5, 0xC3, 0xD1, 0xD5, 0xE6, 0xC6, 0xE7, 0xC7, // 205
    0xFE, 0xF0, 0xDE, 0xD0, 0xA3, 0x153, 0x152, 0xA1, 0xBF, // 215..223
};

/// What a ZSCII code means as Unicode. Zero when it means nothing printable,
/// which the caller drops rather than rendering.
pub fn toUnicode(s: *const Story, code: u8) u21 {
    if (code == 0) return 0;
    if (code == newline) return '\n';
    // Tab and sentence-space are V6's, and V6 is not here. A space is what
    // they were for, and a space is what fits an eighty-column line.
    if (code == 9 or code == 11) return ' ';
    if (code >= 32 and code <= 126) return code;
    if (code >= 155 and code <= 251) {
        // The game's own table wins where it has an entry, which is what the
        // header extension is for. Where it has none, so has the machine.
        if (customUnicode(s, code)) |cp| return cp;
        if (s.extensionWord(3) != 0) return 0;
        const index = code - 155;
        if (index < default_unicode.len) return default_unicode[index];
        return 0;
    }
    return 0;
}

/// The translation the story declared, if it declared one. Entry 3 of the
/// header extension points at a byte count followed by that many words.
pub fn customUnicode(s: *const Story, code: u8) ?u21 {
    const table = s.extensionWord(3);
    if (table == 0) return null;
    const count = s.byteAt(table);
    const index = code - 155;
    if (index >= count) return null;
    return s.wordAt(table + 1 + @as(u32, index) * 2);
}

/// The other direction, for input: what ZSCII code carries this code point.
/// Null when the machine has no way to say it.
pub fn fromUnicode(s: *const Story, cp: u21) ?u8 {
    if (cp == '\n' or cp == '\r') return newline;
    if (cp >= 32 and cp <= 126) return @intCast(cp);

    const table = s.extensionWord(3);
    if (table != 0) {
        const count = s.byteAt(table);
        var i: u8 = 0;
        while (i < count) : (i += 1) {
            if (s.wordAt(table + 1 + @as(u32, i) * 2) == cp) return 155 + i;
        }
        return null;
    }
    for (default_unicode, 0..) |u, i| {
        if (u == cp) return @intCast(155 + i);
    }
    return null;
}

/// Write a ZSCII code to a UTF-8 writer. Nothing at all for a code with no
/// meaning, which is how the machine's own padding stays invisible.
pub fn writeUtf8(w: *std.Io.Writer, s: *const Story, code: u8) !void {
    const cp = toUnicode(s, code);
    if (cp == 0) return;
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(@intCast(cp), &buf) catch return;
    try w.writeAll(buf[0..n]);
}

// ---------------------------------------------------------------- encoding

/// How many Z-characters a dictionary word holds. Six in the early versions
/// and nine later, which is also how far a word is truncated before it is
/// looked up — so `sword` and `swordfish` are one word to Zork and two to
/// anything compiled since.
pub fn resolution(version: u8) usize {
    return if (version <= 3) 6 else 9;
}

/// Encode ZSCII text as a dictionary word: Z-characters packed three to a
/// word, padded with fives, with the top bit set on the last one.
///
/// Padding is Z-character 5 rather than 0 because 0 is a space, and a word
/// padded with spaces would not match the same word padded by the compiler.
pub fn encode(s: *const Story, text: []const u8, out: []u16) void {
    const limit = resolution(s.version);
    // Twelve is the most a single character can carry us past the limit: a
    // shift, an escape and two halves of a ZSCII code, arriving with the
    // buffer one short of full.
    var zchars: [12]u8 = @splat(5);
    var n: usize = 0;
    const put = struct {
        fn f(buf: *[12]u8, len: *usize, z: u8) void {
            if (len.* < buf.len) {
                buf[len.*] = z;
                len.* += 1;
            }
        }
    }.f;

    for (text) |raw| {
        if (n >= limit) break;
        const c = std.ascii.toLower(raw);

        if (c == ' ') {
            put(&zchars, &n, 0);
            continue;
        }
        if (find(s, .a0, c)) |i| {
            put(&zchars, &n, i + 6);
            continue;
        }
        if (find(s, .a1, c)) |i| {
            put(&zchars, &n, if (s.version <= 2) 2 else 4);
            put(&zchars, &n, i + 6);
            continue;
        }
        if (find(s, .a2, c)) |i| {
            put(&zchars, &n, if (s.version <= 2) 3 else 5);
            put(&zchars, &n, i + 6);
            continue;
        }
        // Nothing in the alphabets says it, so it goes as ten bits of ZSCII
        // behind the escape. Four Z-characters for one letter, which is why
        // the alphabets are ordered the way they are.
        put(&zchars, &n, if (s.version <= 2) 3 else 5);
        put(&zchars, &n, 6);
        put(&zchars, &n, c >> 5);
        put(&zchars, &n, c & 0x1F);
    }

    // Whatever was not written is already a five, which is the pad the
    // compiler used — and never a zero, since a zero is a space and a word
    // padded with spaces is a different word.
    const words = limit / 3;
    var i: usize = 0;
    while (i < words and i < out.len) : (i += 1) {
        const a: u16 = zchars[i * 3];
        const b: u16 = zchars[i * 3 + 1];
        const c: u16 = zchars[i * 3 + 2];
        out[i] = (a << 10) | (b << 5) | c;
    }
    if (words > 0 and words <= out.len) out[words - 1] |= 0x8000;
}

fn find(s: *const Story, which: Alphabet, c: u8) ?u8 {
    var i: u8 = 0;
    while (i < 26) : (i += 1) {
        // A2's escape slot holds no character, so it can never be matched
        // into — a literal zero byte in the text would otherwise encode as
        // the escape and mean something else entirely.
        if (which == .a2 and i == 0) continue;
        if (alphabetChar(s, which, i) == c) return i;
    }
    return null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const story_mod = @import("story.zig");

/// Pack Z-characters into words the way the compiler would, for a test that
/// wants a string at a known address.
fn pack(arena: Allocator, zchars: []const u8) ![]u8 {
    const words = (zchars.len + 2) / 3;
    const bytes = try arena.alloc(u8, words * 2);
    var i: usize = 0;
    while (i < words) : (i += 1) {
        var w: u16 = 0;
        var j: usize = 0;
        while (j < 3) : (j += 1) {
            const at = i * 3 + j;
            const z: u16 = if (at < zchars.len) zchars[at] else 5;
            w = (w << 5) | z;
        }
        if (i == words - 1) w |= 0x8000;
        std.mem.writeInt(u16, bytes[i * 2 ..][0..2], w, .big);
    }
    return bytes;
}

fn withString(arena: Allocator, version: u8, at: u32, zchars: []const u8) !Story {
    const bytes = try story_mod.blank(arena, version, 0x400);
    const packed_bytes = try pack(arena, zchars);
    @memcpy(bytes[at..][0..packed_bytes.len], packed_bytes);
    return try Story.load(arena, bytes);
}

test "a string is three Z-characters to the word, and the top bit ends it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // 'h' 'i' — a0 index 7 and 8, so Z-characters 13 and 14.
    const s = try withString(arena, 3, 0x100, &.{ 13, 14 });
    try testing.expectEqualStrings("hi", try decodeAlloc(arena, &s, 0x100));
}

test "shifts reach the other alphabets, and let go afterwards" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // V3: 4 shifts to A1 for one character. "Hi" then back to lower case.
    const s = try withString(arena, 3, 0x100, &.{ 4, 13, 14 });
    try testing.expectEqualStrings("Hi", try decodeAlloc(arena, &s, 0x100));

    // 5 shifts to A2, whose index 7 is '.' — the sixth entry after the escape
    // and the newline and the digits.
    const punct = try withString(arena, 3, 0x100, &.{ 5, 18, 13 });
    try testing.expectEqualStrings(".h", try decodeAlloc(arena, &punct, 0x100));
}

test "version 1 and 2 rotate through the alphabets and can lock" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // V2: 2 rotates up one, for one character only.
    const shifted = try withString(arena, 2, 0x100, &.{ 2, 13, 14 });
    try testing.expectEqualStrings("Hi", try decodeAlloc(arena, &shifted, 0x100));

    // 4 locks there, so both letters are capitals.
    const locked = try withString(arena, 2, 0x100, &.{ 4, 13, 14 });
    try testing.expectEqualStrings("HI", try decodeAlloc(arena, &locked, 0x100));

    // Version 1's Z-character 1 is a newline rather than an abbreviation.
    const nl = try withString(arena, 1, 0x100, &.{ 13, 1, 14 });
    try testing.expectEqualStrings("h\ri", try decodeAlloc(arena, &nl, 0x100));
}

test "the escape carries ten bits of ZSCII through the alphabet" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Shift to A2, escape, then '@' (64) as five bits and five bits.
    const s = try withString(arena, 3, 0x100, &.{ 5, 6, 64 >> 5, 64 & 0x1F });
    try testing.expectEqualStrings("@", try decodeAlloc(arena, &s, 0x100));
}

test "an abbreviation splices in a string from the table" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 3, 0x400);
    // The abbreviation table at 0x200, its first entry pointing at 0x180.
    std.mem.writeInt(u16, bytes[story_mod.h.abbreviations..][0..2], 0x200, .big);
    std.mem.writeInt(u16, bytes[0x200..][0..2], 0x180 / 2, .big);

    const target = try pack(arena, &.{ 13, 14 }); // "hi"
    @memcpy(bytes[0x180..][0..target.len], target);
    const body = try pack(arena, &.{ 1, 0, 24 }); // abbreviation 0, then 's'
    @memcpy(bytes[0x100..][0..body.len], body);

    const s = try Story.load(arena, bytes);
    try testing.expectEqualStrings("his", try decodeAlloc(arena, &s, 0x100));
}

test "encoding a word is what makes it findable in the dictionary" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const s = try Story.load(arena, try story_mod.blank(arena, 3, 0x400));

    // Two words in V1–3, and what is past the sixth Z-character is gone.
    // Every plain lower-case letter costs one Z-character, so a V3 game
    // cannot tell these two apart: both are "advent" by the time they are
    // looked up.
    var noun: [2]u16 = undefined;
    var verb: [2]u16 = undefined;
    encode(&s, "adventurer", &noun);
    encode(&s, "adventuring", &verb);
    try testing.expectEqualSlices(u16, &noun, &verb);

    // Six characters is where it stops, not five: a sword and a swordfish
    // differ in the sixth, so those two really are different words.
    var sword: [2]u16 = undefined;
    var fish: [2]u16 = undefined;
    encode(&s, "sword", &sword);
    encode(&s, "swordfish", &fish);
    try testing.expect(!std.mem.eql(u16, &sword, &fish));

    // V4 onwards has nine, which is what buys back the distinction.
    const five = try Story.load(arena, try story_mod.blank(arena, 5, 0x400));
    var long_noun: [3]u16 = undefined;
    var long_verb: [3]u16 = undefined;
    encode(&five, "adventurer", &long_noun);
    encode(&five, "adventuring", &long_verb);
    try testing.expect(!std.mem.eql(u16, &long_noun, &long_verb));

    // And the round trip: what we encode decodes back to what we meant.
    const bytes = try story_mod.blank(arena, 3, 0x400);
    var packed_word: [2]u16 = undefined;
    encode(&s, "lamp", &packed_word);
    std.mem.writeInt(u16, bytes[0x100..][0..2], packed_word[0], .big);
    std.mem.writeInt(u16, bytes[0x102..][0..2], packed_word[1], .big);
    const back = try Story.load(arena, bytes);
    try testing.expectEqualStrings("lamp", try decodeAlloc(arena, &back, 0x100));
}

test "ZSCII is not ASCII, and the accented letters have a table" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const s = try Story.load(arena, try story_mod.blank(arena, 5, 0x400));
    try testing.expectEqual(@as(u21, '\n'), toUnicode(&s, newline));
    try testing.expectEqual(@as(u21, 'A'), toUnicode(&s, 'A'));
    try testing.expectEqual(@as(u21, 0xE4), toUnicode(&s, 155)); // ä
    try testing.expectEqual(@as(u21, 0xBF), toUnicode(&s, 223)); // ¿
    try testing.expectEqual(@as(u21, 0), toUnicode(&s, 230)); // no default

    try testing.expectEqual(@as(?u8, 155), fromUnicode(&s, 0xE4));
    try testing.expectEqual(@as(?u8, newline), fromUnicode(&s, '\n'));
    try testing.expectEqual(@as(?u8, null), fromUnicode(&s, 0x4E2D));
}
