//! The sigil table. One byte-sequence per line kind.
//!
//! Every sigil is a 4-byte UTF-8 sequence inside U+1F300..U+1FAFF. That range
//! holds no writing systems, so matching raw bytes at a line start is safe:
//! UTF-8 is self-synchronising, and a valid multi-byte sequence can never
//! appear inside another character's encoding.

const std = @import("std");

pub const range_lo: u21 = 0x1F300;
pub const range_hi: u21 = 0x1FAFF;

/// U+1F539 SMALL BLUE DIAMOND. Separates fields within a structured line.
pub const field_sep = "\u{1F539}";

pub const Sigil = enum {
    // definition. `agent` names an agent — a skill, a model, or a parent turn
    // is one too — and naming one is how you use it. Identity comes from the
    // file, so nothing ever declares its own name.
    agent,
    allow,
    tool,
    required,
    optional,
    system,
    user,
    thought,
    meta,
    assistant,
    call,
    arg,
    err,
    result,
    script,

    /// Number of 🔹-separated fields on the line. The final field absorbs any
    /// remaining separators and continues across following non-sigil lines.
    pub fn arity(s: Sigil) u8 {
        return switch (s) {
            .tool, .call, .arg, .err, .result => 2,
            .required, .optional => 3,
            else => 1,
        };
    }

    pub fn bytes(s: Sigil) []const u8 {
        return switch (s) {
            .agent => "\u{1F9E0}",
            .allow => "\u{1F527}",
            .tool => "\u{1F4D0}",
            .required => "\u{1F4E6}",
            .optional => "\u{1F381}",
            .system => "\u{1F4BB}",
            .user => "\u{1F9D1}",
            .thought => "\u{1F4AD}",
            .meta => "\u{1F50F}",
            .assistant => "\u{1F916}",
            .call => "\u{1F4DE}",
            .arg => "\u{1F9E9}",
            .err => "\u{1F6AB}",
            .result => "\u{1F4C3}",
            .script => "\u{1F4DA}",
        };
    }
};

/// Longest sigil in bytes. Every sigil is 4, but nothing depends on that.
pub const max_len: usize = blk: {
    var n: usize = 0;
    for (std.enums.values(Sigil)) |s| n = @max(n, s.bytes().len);
    break :blk n;
};

/// Match a sigil at the start of `s`. Returns null if none matches.
pub fn match(s: []const u8) ?Sigil {
    for (std.enums.values(Sigil)) |sig| {
        if (std.mem.startsWith(u8, s, sig.bytes())) return sig;
    }
    return null;
}

/// True when `s` begins with a codepoint in the reserved range. Such a
/// character that is not a known sigil is an error, never content.
pub fn inReservedRange(s: []const u8) bool {
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return false;
    if (len > s.len) return false;
    const cp = std.unicode.utf8Decode(s[0..len]) catch return false;
    return cp >= range_lo and cp <= range_hi;
}

test "every sigil is inside the reserved range" {
    for (std.enums.values(Sigil)) |s| {
        try std.testing.expect(inReservedRange(s.bytes()));
        try std.testing.expectEqual(@as(usize, 4), s.bytes().len);
    }
}

test "the field separator is reserved but is not a sigil" {
    try std.testing.expect(inReservedRange(field_sep));
    try std.testing.expect(match(field_sep) == null);
}
