//! The sigil table. One line kind per entry, in two spellings.
//!
//! The emoji spelling is one codepoint inside U+1F300..U+1FAFF or the dingbats,
//! U+2700..U+27BF, and a renderer may decorate it with presentation modifiers.
//! Neither range holds a writing system, so an unknown character there is an
//! error rather than text. The
//! plain spelling is `:word:`, a gemoji shortcode. The words are gemoji's and
//! so they name the picture; the role is the enum tag beside it.
//!
//! A document is written in one spelling or the other and never both. See
//! `Mode`, which also decides the framing over in doc.zig.

const std = @import("std");

/// Where a sigil's codepoint comes from: the pictographs, and the dingbats.
pub const ranges = [_][2]u21{ .{ 0x1F300, 0x1FAFF }, .{ 0x2700, 0x27BF } };

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
    // A call is answered by its output as it arrives, and then by how it
    // went. 🧾 is what the tool said; 🟢 and 🚫 are the verdict, which is only
    // known once it has stopped saying it.
    result,
    // 📜 is a 🧾 meant to be read as markdown. A 🧾 is literal, and carries
    // its block indented four spaces so that anything rendering the file
    // shows it as code; a 📜 carries its block as it is. A tool may answer
    // with both, and a model is handed them joined in order.
    scroll,
    // 🔗 hands over files beside what a tool said, one `<path` line each. It
    // names its call as 🧾 does, and is kept by copying what it names into
    // the turn's `+/`, so what the ledger says was seen cannot change after.
    link,
    ok,
    failed,
    skill,
    // 🔝 is a fence rather than a record: it opens a file's top section and
    // closes it, and carries nothing of its own. Every other sigil is a header
    // and a block; this one is neither, which is what lets a reader know which
    // half it is in from the first line rather than from the end of the file.
    top,
    system,
    // 🛡 is a wrapper a tool runs inside. With a block it is a definition,
    // without one it is an activation, and both only ever add — which is what
    // makes any combination safe and the order of no consequence to what is
    // permitted.
    shield,
    // 🏃 turns a code block into something runnable: an argv the code is
    // appended to, as a shebang's interpreter is handed its script. Defined
    // before it is named, so a document reads in one pass.
    runner,
    // 🧰 has the same two forms 🛡 has, for the same reason. With a block it
    // defines a tool; with none it offers that tool here. Defining says only
    // what a thing is, so what a reply hands back is inert until something
    // already trusted names it — and one sigil means one filter closes both.
    tool,
    // ❓ is a tool asking the person something before it can go on, and ❗ is
    // what they said back. Both name the call, so a tool that asks twice is
    // answered twice and in order. Neither is anything a model is told: the
    // call they stand under is answered by the tool once it has what it needs.
    question,
    exclaim,

    pub fn emoji(s: Sigil) []const u8 {
        return switch (s) {
            .agent => "\u{1F9E0}", // 🧠
            .user => "\u{1F64B}", // 🙋
            .bot => "\u{1F916}", // 🤖
            .thought => "\u{1F4AD}", // 💭
            .signature => "\u{1F50F}", // 🔏
            .call => "\u{1F4F2}", // 📲
            .result => "\u{1F9FE}", // 🧾
            .scroll => "\u{1F4DC}", // 📜
            .link => "\u{1F517}", // 🔗
            .ok => "\u{1F7E2}", // 🟢
            .failed => "\u{1F6AB}", // 🚫
            .skill => "\u{1F4DA}", // 📚
            .top => "\u{1F51D}", // 🔝
            .system => "\u{1F9ED}", // 🧭
            // Emitted with the selector, or a terminal shows it as text.
            .shield => "\u{1F6E1}\u{FE0F}", // 🛡️
            .runner => "\u{1F3C3}", // 🏃
            .tool => "\u{1F9F0}", // 🧰
            .question => "\u{2753}", // ❓
            .exclaim => "\u{2757}", // ❗
        };
    }

    /// The plain spelling, colons included. These are gemoji shortcodes — the
    /// table GitHub renders — so anything that substitutes shortcodes shows the
    /// same glyph the emoji spelling uses. Two are not universal: Slack calls
    /// 🤖 `robot_face` and 🟢 `large_green_circle`. Slack is not a render
    /// target, and an unknown shortcode degrades to the text that was typed.
    pub fn word(s: Sigil) []const u8 {
        return switch (s) {
            .agent => ":brain:",
            .user => ":raising_hand:",
            .bot => ":robot:",
            .thought => ":thought_balloon:",
            .signature => ":lock_with_ink_pen:",
            .call => ":calling:",
            .result => ":receipt:",
            .scroll => ":scroll:",
            .link => ":link:",
            .ok => ":green_circle:",
            .failed => ":no_entry_sign:",
            .skill => ":books:",
            .top => ":top:",
            .system => ":compass:",
            .shield => ":shield:",
            .runner => ":runner:",
            .tool => ":toolbox:",
            .question => ":question:",
            .exclaim => ":exclamation:",
        };
    }

    pub fn text(s: Sigil, mode: Mode) []const u8 {
        return switch (mode) {
            .md => s.word(),
            .m8 => s.emoji(),
        };
    }

    /// Whether the rest of the header line carries anything.
    ///
    /// A 🤖's value is how a reply stopped short, when it did — a remark
    /// between the provider and whoever reads the ledger, which m8 carries
    /// and never reads. A 💭's value is a compact thought when it has no block;
    /// `snip` asks for its block to be kept aside, which is the codec's call
    /// and m8's to store.
    pub fn takesValue(s: Sigil) bool {
        return switch (s) {
            .user, .system, .top => false,
            else => true,
        };
    }

    /// How far each content line is indented inside its quote, in both
    /// spellings. Framing rather than content: written and stripped here, so
    /// every reader is handed the literal text. An empty line carries none.
    pub fn indent(s: Sigil) []const u8 {
        return switch (s) {
            .result => "    ",
            else => "",
        };
    }

    /// Whether a quoted block may follow.
    pub fn takesContent(s: Sigil) bool {
        return switch (s) {
            .agent, .skill, .signature, .ok, .top => false,
            else => true,
        };
    }
};

const Codepoint = struct { cp: u21, len: usize };

fn firstCodepoint(s: []const u8) ?Codepoint {
    if (s.len == 0) return null;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return null;
    if (len > s.len) return null;
    const cp = std.unicode.utf8Decode(s[0..len]) catch return null;
    return .{ .cp = cp, .len = len };
}

/// A variation selector or a skin tone decorates the glyph before it.
fn isModifier(cp: u21) bool {
    return cp == 0xFE0E or cp == 0xFE0F or (cp >= 0x1F3FB and cp <= 0x1F3FF);
}

/// How many bytes of decoration `s` opens with. A renderer may follow a sigil
/// with a variation selector, a skin tone, or a zero-width joiner binding
/// another codepoint into the same glyph — Slack shows 🙋 as 🙋‍♀️. All of it
/// belongs to the sigil, so text pasted back from a renderer still reads as
/// the sigil rather than leaving the decoration behind as a value.
fn modifierLen(s: []const u8) usize {
    var i: usize = 0;
    while (firstCodepoint(s[i..])) |c| {
        if (isModifier(c.cp)) {
            i += c.len;
            continue;
        }
        // A joiner with nothing after it joins nothing, and is left alone.
        if (c.cp == 0x200D) {
            const next = firstCodepoint(s[i + c.len ..]) orelse break;
            i += c.len + next.len;
            continue;
        }
        break;
    }
    return i;
}

/// The sigil a plain name spells: its shortcode without the colons, which is
/// how a command line names one. `robot`, `brain`, `toolbox`.
pub fn named(name: []const u8) ?Sigil {
    for (std.enums.values(Sigil)) |s| {
        const w = s.word();
        if (std.mem.eql(u8, w[1 .. w.len - 1], name)) return s;
    }
    return null;
}

/// A matched sigil and the bytes it occupied. That is not always the length of
/// its own spelling, so the value behind it starts at `len`, never at
/// `sigil.text(mode).len`.
pub const Match = struct { sigil: Sigil, len: usize };

/// Match a sigil at the start of `s`, in the given spelling.
pub fn match(mode: Mode, s: []const u8) ?Match {
    switch (mode) {
        .md => for (std.enums.values(Sigil)) |sig| {
            const w = sig.word();
            if (std.mem.startsWith(u8, s, w)) return .{ .sigil = sig, .len = w.len };
        },
        // Compared by codepoint rather than by bytes, so a sigil whose own
        // spelling carries a variation selector still matches without one.
        .m8 => {
            const first = firstCodepoint(s) orelse return null;
            for (std.enums.values(Sigil)) |sig| {
                const base = firstCodepoint(sig.emoji()) orelse continue;
                if (base.cp != first.cp) continue;
                return .{ .sigil = sig, .len = first.len + modifierLen(s[first.len..]) };
            }
        },
    }
    return null;
}

/// True when `s` begins with a codepoint in a reserved range. Such a
/// character that is not a known sigil is an error, never content.
pub fn inReservedRange(s: []const u8) bool {
    if (s.len == 0) return false;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return false;
    if (len > s.len) return false;
    const cp = std.unicode.utf8Decode(s[0..len]) catch return false;
    for (ranges) |r| if (cp >= r[0] and cp <= r[1]) return true;
    return false;
}

// ---------------------------------------------------------------- tests

test "every emoji is one reserved codepoint, followed by modifiers or nothing" {
    for (std.enums.values(Sigil)) |s| {
        try std.testing.expect(inReservedRange(s.emoji()));
        const first = firstCodepoint(s.emoji()).?;
        try std.testing.expectEqual(
            s.emoji().len,
            first.len + modifierLen(s.emoji()[first.len..]),
        );
    }
}

test "no two sigils share a first codepoint, and no word is a prefix of another" {
    const all = std.enums.values(Sigil);
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try std.testing.expect(firstCodepoint(a.emoji()).?.cp != firstCodepoint(b.emoji()).?.cp);
        try std.testing.expect(!std.mem.startsWith(u8, a.word(), b.word()));
        try std.testing.expect(!std.mem.startsWith(u8, b.word(), a.word()));
    };
}

// Pinned against github/gemoji. Both halves of a pair are load-bearing: the
// promise is that a renderer substituting the shortcode shows the same glyph
// the emoji spelling uses, and nothing else in the build would notice if one
// half drifted.
test "every plain spelling is the gemoji shortcode for its own emoji" {
    const Pin = struct { sigil: Sigil, cp: u21, word: []const u8 };
    const pins = [_]Pin{
        .{ .sigil = .agent, .cp = 0x1F9E0, .word = ":brain:" },
        .{ .sigil = .user, .cp = 0x1F64B, .word = ":raising_hand:" },
        .{ .sigil = .bot, .cp = 0x1F916, .word = ":robot:" },
        .{ .sigil = .thought, .cp = 0x1F4AD, .word = ":thought_balloon:" },
        .{ .sigil = .signature, .cp = 0x1F50F, .word = ":lock_with_ink_pen:" },
        .{ .sigil = .call, .cp = 0x1F4F2, .word = ":calling:" },
        .{ .sigil = .result, .cp = 0x1F9FE, .word = ":receipt:" },
        .{ .sigil = .scroll, .cp = 0x1F4DC, .word = ":scroll:" },
        .{ .sigil = .link, .cp = 0x1F517, .word = ":link:" },
        .{ .sigil = .ok, .cp = 0x1F7E2, .word = ":green_circle:" },
        .{ .sigil = .failed, .cp = 0x1F6AB, .word = ":no_entry_sign:" },
        .{ .sigil = .skill, .cp = 0x1F4DA, .word = ":books:" },
        .{ .sigil = .top, .cp = 0x1F51D, .word = ":top:" },
        .{ .sigil = .system, .cp = 0x1F9ED, .word = ":compass:" },
        .{ .sigil = .shield, .cp = 0x1F6E1, .word = ":shield:" },
        .{ .sigil = .runner, .cp = 0x1F3C3, .word = ":runner:" },
        .{ .sigil = .tool, .cp = 0x1F9F0, .word = ":toolbox:" },
        .{ .sigil = .question, .cp = 0x2753, .word = ":question:" },
        .{ .sigil = .exclaim, .cp = 0x2757, .word = ":exclamation:" },
    };
    try std.testing.expectEqual(std.enums.values(Sigil).len, pins.len);
    for (pins) |pin| {
        try std.testing.expectEqualStrings(pin.word, pin.sigil.word());
        try std.testing.expectEqual(pin.cp, firstCodepoint(pin.sigil.emoji()).?.cp);
    }
}

test "a renderer's decoration belongs to the sigil, not to the value" {
    const cases = [_][]const u8{
        "\u{1F64B}", // bare
        "\u{1F64B}\u{FE0F}", // variation selector
        "\u{1F64B}\u{1F3FD}", // skin tone
        "\u{1F64B}\u{200D}\u{2640}\u{FE0F}", // what Slack shows for 🙋
    };
    for (cases) |c| {
        const m = match(.m8, c).?;
        try std.testing.expectEqual(Sigil.user, m.sigil);
        try std.testing.expectEqual(c.len, m.len);
    }
}

test "the modifier scan stops at the value" {
    const line = "\u{1F9E0}mathy";
    const m = match(.m8, line).?;
    try std.testing.expectEqual(Sigil.agent, m.sigil);
    try std.testing.expectEqualStrings("mathy", line[m.len..]);
}

test "a joiner with nothing after it joins nothing" {
    const line = "\u{1F64B}\u{200D}";
    const m = match(.m8, line).?;
    try std.testing.expectEqual(Sigil.user, m.sigil);
    try std.testing.expectEqual(@as(usize, 4), m.len);
}

test "the plain spelling takes no decoration" {
    const line = ":raising_hand:\u{FE0F}";
    const m = match(.md, line).?;
    try std.testing.expectEqual(Sigil.user, m.sigil);
    try std.testing.expectEqualStrings("\u{FE0F}", line[m.len..]);
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
