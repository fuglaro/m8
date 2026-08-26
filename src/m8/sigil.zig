//! The sigil table. One line kind per entry, in two spellings.
//!
//! The emoji spelling is a 4-byte UTF-8 sequence inside U+1F300..U+1FAFF. That
//! range holds no writing systems, so an unknown character there is an error
//! rather than text. The plain spelling is `:word:`, the convention every chat
//! system already uses for an emoji written out, and each word names the role
//! rather than the picture.
//!
//! A document is written in one spelling or the other and never both. See
//! `Mode`, which also decides the framing over in doc.zig.

const std = @import("std");

pub const range_lo: u21 = 0x1F300;
pub const range_hi: u21 = 0x1FAFF;

/// Separates a fixed number of fields inside a value, so the last field may
/// hold one safely. How many fields a value has is decided by the sigil above
/// it, not by this table.
pub const field_sep = ",";

/// Which spelling a document is written in. `md` is what files and pipes hold,
/// and is also valid markdown. `m8` is what a terminal is shown.
pub const Mode = enum { md, m8 };

pub const Sigil = enum {
    // `agent` names an agent — a skill, a model, or a parent turn is one too —
    // and naming one is how you use it. Identity comes from the file, so
    // nothing ever declares its own name.
    agent,
    user,
    bot,
    thought,
    signature,
    call,
    // `package` is a declared property under a tool and a supplied argument
    // under a call. Which one it is comes from the sigil above it.
    package,
    optional,
    result,
    failed,
    skill,
    system,
    allow,
    // 🔓 says a tool is available here; 🔒 says what it may not do.
    lock,
    tool,
    // 🔌 is how a tool is run: the argv template it plugs into.
    command,

    pub fn emoji(s: Sigil) []const u8 {
        return switch (s) {
            .agent => "\u{1F9E0}", // 🧠
            .user => "\u{1F64B}", // 🙋
            .bot => "\u{1F916}", // 🤖
            .thought => "\u{1F4AD}", // 💭
            .signature => "\u{1F50F}", // 🔏
            .call => "\u{1F4F2}", // 📲
            .package => "\u{1F4E6}", // 📦
            .optional => "\u{1F381}", // 🎁
            .result => "\u{1F9FE}", // 🧾
            .failed => "\u{1F6AB}", // 🚫
            .skill => "\u{1F4DA}", // 📚
            .system => "\u{1F4BB}", // 💻
            .allow => "\u{1F513}", // 🔓
            .lock => "\u{1F512}", // 🔒
            .tool => "\u{1F9F0}", // 🧰
            .command => "\u{1F50C}", // 🔌
        };
    }

    /// The plain spelling, colons included. Each is a real emoji shortcode for
    /// its own emoji, so anything that substitutes shortcodes shows the emoji.
    pub fn word(s: Sigil) []const u8 {
        return switch (s) {
            .agent => ":brain:",
            .user => ":raising_hand:",
            .bot => ":robot:",
            .thought => ":thought_balloon:",
            .signature => ":lock_with_ink_pen:",
            .call => ":calling:",
            .package => ":package:",
            .optional => ":gift:",
            .result => ":receipt:",
            .failed => ":no_entry_sign:",
            .skill => ":books:",
            .system => ":computer:",
            .allow => ":unlock:",
            .lock => ":lock:",
            .tool => ":toolbox:",
            .command => ":electric_plug:",
        };
    }

    pub fn text(s: Sigil, mode: Mode) []const u8 {
        return switch (mode) {
            .md => s.word(),
            .m8 => s.emoji(),
        };
    }

    /// Whether the rest of the header line carries anything.
    pub fn takesValue(s: Sigil) bool {
        return switch (s) {
            .user, .bot, .thought, .system => false,
            else => true,
        };
    }

    /// Whether a quoted block may follow.
    pub fn takesContent(s: Sigil) bool {
        return switch (s) {
            .agent, .skill, .allow, .signature, .lock, .command => false,
            else => true,
        };
    }
};

/// Match a sigil at the start of `s`, in the given spelling.
pub fn match(mode: Mode, s: []const u8) ?Sigil {
    for (std.enums.values(Sigil)) |sig| {
        if (std.mem.startsWith(u8, s, sig.text(mode))) return sig;
    }
    return null;
}

/// True when `s` begins with a codepoint in the reserved range. Such a
/// character that is not a known sigil is an error, never content.
pub fn inReservedRange(s: []const u8) bool {
    if (s.len == 0) return false;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return false;
    if (len > s.len) return false;
    const cp = std.unicode.utf8Decode(s[0..len]) catch return false;
    return cp >= range_lo and cp <= range_hi;
}

// ---------------------------------------------------------------- tests

test "every emoji is inside the reserved range and four bytes" {
    for (std.enums.values(Sigil)) |s| {
        try std.testing.expect(inReservedRange(s.emoji()));
        try std.testing.expectEqual(@as(usize, 4), s.emoji().len);
    }
}

test "no spelling is a prefix of another" {
    const all = std.enums.values(Sigil);
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try std.testing.expect(!std.mem.startsWith(u8, a.emoji(), b.emoji()));
        try std.testing.expect(!std.mem.startsWith(u8, b.emoji(), a.emoji()));
        try std.testing.expect(!std.mem.startsWith(u8, a.word(), b.word()));
        try std.testing.expect(!std.mem.startsWith(u8, b.word(), a.word()));
    };
}

test "every plain spelling is bounded by colons" {
    for (std.enums.values(Sigil)) |s| {
        const w = s.word();
        try std.testing.expect(w.len > 2);
        try std.testing.expectEqual(@as(u8, ':'), w[0]);
        try std.testing.expectEqual(@as(u8, ':'), w[w.len - 1]);
    }
}

test "the field separator is not a sigil in either spelling" {
    try std.testing.expect(match(.md, field_sep) == null);
    try std.testing.expect(match(.m8, field_sep) == null);
}
