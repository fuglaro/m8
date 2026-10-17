//! Reading and writing the m8 harness.
//!
//! A record is a header line and at most one content block:
//!
//!     ▐ 🧰:shell         * :toolbox::shell
//!     │ run a command      > run a command
//!
//! The header is a sigil, a `:`, and its value. The content is the block
//! quoted beneath it. In markdown the header is a list item and the quote is
//! indented under it, so that anything rendering the file shows each record
//! as one item holding its block, rather than a list and a quote apart. That is the whole of the harness — content never nests further
//! and records never interleave, so this file stays the same size no matter
//! how many kinds of content the language grows.
//!
//! Exactly one space follows the quote and is stripped, so content is verbatim
//! and a line that looks like a record is only a line. A quote alone, with no
//! space, is an empty content line: a paragraph break must not depend on
//! trailing whitespace, which editors strip. A blank line closes the block.
//! It is not required between records: a header is never content, so one that
//! follows another opens its record whether or not a line separates them.
//!
//! A sigil may also ask for its lines to be indented inside the quote, as 🧾
//! does so that a renderer shows what a tool said as code. That indent is
//! framing too: written and stripped here, and an error when missing, except
//! on an empty line, which carries nothing to indent.
//!
//! What a content block *means* is decided by the sigil above it, and none of
//! that is known here. A prose block is handed back as bytes; a structured one
//! is handed back as bytes too, for its own reader to make sense of.
//!
//! One \r immediately before a \n is dropped, exactly one, so \r\r\n ends a
//! line's content in a literal \r.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sigil = @import("sigil.zig");
const highlight = @import("highlight.zig");
pub const Sigil = sigil.Sigil;
pub const Look = highlight.Options;

pub const Mode = sigil.Mode;

pub const Record = struct {
    sigil: Sigil,
    /// The rest of the header line. Empty for a sigil that takes none.
    value: []const u8 = "",
    /// The quoted block, lines joined by \n, or null when there was none.
    content: ?[]const u8 = null,
};

/// What opens a record, per spelling.
pub fn header(mode: Mode) []const u8 {
    return switch (mode) {
        .md => "* ",
        .m8 => "\u{2590} ", // ▐
    };
}

/// What ends a sigil on a header line, before its value.
pub const sigil_end = ":";

/// The quote mark, per spelling, as a block nests one inside its content.
pub fn quote(mode: Mode) []const u8 {
    return switch (mode) {
        .md => "> ",
        .m8 => "\u{2502} ", // │
    };
}

/// A quote with nothing after it: the mark and no space.
pub fn bareQuote(mode: Mode) []const u8 {
    return quote(mode)[0 .. quote(mode).len - 1];
}

/// What carries a record's content line: the quote, indented under the
/// header's list item in markdown.
pub fn lead(mode: Mode) []const u8 {
    return switch (mode) {
        .md => "  > ",
        .m8 => quote(.m8),
    };
}

/// A content line with nothing on it: the lead and no space.
pub fn bareLead(mode: Mode) []const u8 {
    return lead(mode)[0 .. lead(mode).len - 1];
}

/// A header line read: its sigil and its value. Null when the line is not
/// one, which includes a sigil without the `:` that ends it.
pub const Header = struct { sigil: Sigil, value: []const u8 };

pub fn headed(mode: Mode, line: []const u8) ?Header {
    if (!std.mem.startsWith(u8, line, header(mode))) return null;
    const rest = line[header(mode).len..];
    const m = sigil.match(mode, rest) orelse return null;
    if (!std.mem.startsWith(u8, rest[m.len..], sigil_end)) return null;
    return .{ .sigil = m.sigil, .value = rest[m.len + sigil_end.len ..] };
}

pub const ParseError = error{
    /// A header carried a character that is not a sigil in this spelling.
    UnknownSigil,
    /// A line was in the other spelling. A document is one or the other.
    ModeMixed,
    /// Content appeared with no record above it, or after a blank line closed
    /// the block.
    OrphanContent,
    /// A quote was not followed by a space. Missing it is never content.
    MissingSpace,
    /// A sigil on a header line was not ended by its `:`.
    MissingColon,
    /// A line of a block its sigil indents was not indented.
    MissingIndent,
    /// A line that is neither blank, a header, nor a content line.
    UnexpectedLine,
    /// A sigil that takes no value was given one.
    UnexpectedValue,
    /// A sigil that takes no content was given a block.
    UnexpectedContent,
    /// The first line was neither spelling, so there is nothing to lock to.
    NotADocument,
} || Allocator.Error;

pub const Diagnostic = struct {
    line: usize = 0,
    detail: []const u8 = "",
};

/// Which spelling a document is in, from its first non-blank line. Null when
/// it is not a document at all — which is how a piped prompt is told from a
/// piped conversation. The first line must carry a real sigil as well as the
/// framing header; a line that merely looks like a header is still prose.
pub fn detect(src: []const u8) ?Mode {
    const line = firstLine(src) orelse return null;
    for ([_]Mode{ .m8, .md }) |m| if (headed(m, line) != null) return m;
    return null;
}

/// The framing spelling, without deciding whether its first header is valid.
/// Parsing uses this after a caller has explicitly handed us a document, so a
/// malformed header can still receive the useful `UnknownSigil` diagnostic.
fn framing(src: []const u8) ?Mode {
    const line = firstLine(src) orelse return null;
    for ([_]Mode{ .m8, .md }) |m|
        if (std.mem.startsWith(u8, line, header(m))) return m;
    return null;
}

fn firstLine(src: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, src, '\n');
    while (it.next()) |raw| {
        const line = trimCr(raw);
        if (line.len > 0) return line;
    }
    return null;
}

fn trimCr(raw: []const u8) []const u8 {
    // Exactly one. A second survives as literal content.
    return if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
}

/// Parse a whole document. Values are slices into `src`; content is
/// materialised into `arena`, since stripping quotes and \r both remove bytes
/// from the middle of a span.
pub fn parse(arena: Allocator, src: []const u8, diag: *Diagnostic) ParseError![]Record {
    const mode = framing(src) orelse {
        if (std.mem.trim(u8, src, " \t\r\n").len == 0) return &.{};
        diag.* = .{ .line = 1, .detail = "first line is not a record header" };
        return error.NotADocument;
    };
    return parseMode(arena, src, mode, diag);
}

pub fn parseMode(arena: Allocator, src: []const u8, mode: Mode, diag: *Diagnostic) ParseError![]Record {
    const other: Mode = switch (mode) {
        .md => .m8,
        .m8 => .md,
    };

    var records: std.ArrayList(Record) = .empty;
    var content: std.ArrayList(u8) = .empty;

    var cur: ?Sigil = null;
    var value: []const u8 = "";
    var lines: usize = 0; // content lines gathered for `cur`
    var open = false; // still accepting content for `cur`
    var blank = true; // the line before this one was blank, or there was none

    var line_no: usize = 0;
    // A trailing newline terminates the last line rather than starting an
    // empty one, so drop it before splitting.
    const body = if (std.mem.endsWith(u8, src, "\n")) src[0 .. src.len - 1] else src;
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |raw| {
        line_no += 1;
        const line = trimCr(raw);

        if (line.len == 0) {
            open = false;
            blank = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, header(mode))) {
            if (cur) |s| try flush(arena, &records, s, value, lines, &content);

            const rest = line[header(mode).len..];
            const m = sigil.match(mode, rest) orelse {
                diag.* = .{ .line = line_no, .detail = "not a known sigil" };
                return error.UnknownSigil;
            };
            if (!std.mem.startsWith(u8, rest[m.len..], sigil_end)) {
                diag.* = .{ .line = line_no, .detail = "a sigil is ended by `:` before its value" };
                return error.MissingColon;
            }
            value = rest[m.len + sigil_end.len ..];
            if (value.len > 0 and !m.sigil.takesValue()) {
                diag.* = .{ .line = line_no, .detail = "this sigil takes no value" };
                return error.UnexpectedValue;
            }
            cur = m.sigil;
            lines = 0;
            open = true;
            blank = false;
            continue;
        }

        if (std.mem.startsWith(u8, line, lead(mode)) or std.mem.eql(u8, line, bareLead(mode))) {
            if (cur == null) {
                diag.* = .{ .line = line_no, .detail = "content before the first record" };
                return error.OrphanContent;
            }
            if (!open) {
                diag.* = .{ .line = line_no, .detail = "a blank line closed this block" };
                return error.OrphanContent;
            }
            if (!cur.?.takesContent()) {
                diag.* = .{ .line = line_no, .detail = "this sigil takes no content" };
                return error.UnexpectedContent;
            }
            if (lines > 0) try content.append(arena, '\n');
            if (line.len > bareLead(mode).len) {
                const indent = cur.?.indent();
                const text = line[lead(mode).len..];
                if (!std.mem.startsWith(u8, text, indent)) {
                    diag.* = .{ .line = line_no, .detail = "this sigil's content is indented four spaces" };
                    return error.MissingIndent;
                }
                try content.appendSlice(arena, text[indent.len..]);
            }
            lines += 1;
            blank = false;
            continue;
        }

        if (std.mem.startsWith(u8, line, header(other)) or
            std.mem.startsWith(u8, line, bareLead(other)))
        {
            diag.* = .{ .line = line_no, .detail = "the other spelling; a document is one or the other" };
            return error.ModeMixed;
        }
        if (std.mem.startsWith(u8, line, bareLead(mode))) {
            diag.* = .{ .line = line_no, .detail = "a content line needs one space after the quote" };
            return error.MissingSpace;
        }
        if (std.mem.startsWith(u8, line, bareQuote(mode))) {
            diag.* = .{ .line = line_no, .detail = "a content line is indented two spaces before its quote" };
            return error.UnexpectedLine;
        }
        if (sigil.inReservedRange(line)) {
            diag.* = .{ .line = line_no, .detail = "a sigil needs a header before it" };
            return error.UnknownSigil;
        }
        diag.* = .{ .line = line_no, .detail = "neither a header nor a content line" };
        return error.UnexpectedLine;
    }
    if (cur) |s| try flush(arena, &records, s, value, lines, &content);
    return records.toOwnedSlice(arena);
}

fn flush(
    arena: Allocator,
    records: *std.ArrayList(Record),
    s: Sigil,
    value: []const u8,
    lines: usize,
    content: *std.ArrayList(u8),
) Allocator.Error!void {
    try records.append(arena, .{
        .sigil = s,
        .value = value,
        .content = if (lines == 0) null else try arena.dupe(u8, content.items),
    });
    content.clearRetainingCapacity();
}

/// Write one record. Always emits \n; \r is never introduced.
pub fn write(w: *std.Io.Writer, mode: Mode, r: Record) std.Io.Writer.Error!void {
    try w.writeAll(header(mode));
    try w.writeAll(r.sigil.text(mode));
    try w.writeAll(sigil_end);
    try w.writeAll(r.value);
    try w.writeByte('\n');

    const c = r.content orelse return;
    var it = std.mem.splitScalar(u8, c, '\n');
    while (it.next()) |line| {
        if (line.len == 0) {
            try w.writeAll(bareLead(mode));
        } else {
            try w.writeAll(lead(mode));
            try w.writeAll(r.sigil.indent());
            try w.writeAll(line);
        }
        try w.writeByte('\n');
    }
}

/// Write one record, its content highlighted as markdown when it is.
pub fn writeLooking(w: *std.Io.Writer, mode: Mode, look: ?Look, r: Record) std.Io.Writer.Error!void {
    const c = r.content orelse return write(w, mode, r);
    if (looked(mode, look, r.sigil) == null) return write(w, mode, r);
    var b = try ContentWriter.beginLooking(w, mode, look, r.sigil, r.value);
    try b.write(c);
    try b.finish();
}

/// What a record is highlighted with, if anything: a 📜 or a 🤖, and only
/// ever in the rendered spelling.
fn looked(mode: Mode, look: ?Look, s: Sigil) ?Look {
    const l = look orelse return null;
    if (mode != .m8 or !(l.color or l.reflow)) return null;
    return if (s == .scroll or s == .bot) l else null;
}

/// Write a document, one blank line between records.
pub fn writeAll(w: *std.Io.Writer, mode: Mode, records: []const Record) std.Io.Writer.Error!void {
    for (records, 0..) |r, i| {
        if (i > 0) try w.writeByte('\n');
        try write(w, mode, r);
    }
}

/// Writes a record's content incrementally.
///
/// The quote is owed rather than written: at the start of a line the next byte
/// decides. A newline there means the line was empty and takes the bare quote,
/// so a paragraph break never leaves trailing whitespace for an editor to
/// strip. Anything else takes the quote and then flows straight through, which
/// is what keeps output live when bytes arrive from a model one at a time.
pub const ContentWriter = struct {
    w: *std.Io.Writer,
    mode: Mode,
    indent: []const u8 = "",
    at_line_start: bool = true,
    hl: ?highlight.Highlighter = null,

    /// Open a record. The header is known up front; the content follows.
    pub fn begin(w: *std.Io.Writer, mode: Mode, s: Sigil, value: []const u8) std.Io.Writer.Error!ContentWriter {
        try w.writeAll(header(mode));
        try w.writeAll(s.text(mode));
        try w.writeAll(sigil_end);
        try w.writeAll(value);
        try w.writeByte('\n');
        return .{ .w = w, .mode = mode, .indent = s.indent() };
    }

    /// Open a record whose content is highlighted when `look` says it is.
    pub fn beginLooking(w: *std.Io.Writer, mode: Mode, look: ?Look, s: Sigil, value: []const u8) std.Io.Writer.Error!ContentWriter {
        var b = try begin(w, mode, s, value);
        if (looked(mode, look, s)) |l| b.hl = .init(w, l, lead(mode));
        return b;
    }


    pub fn write(b: *ContentWriter, bytes: []const u8) std.Io.Writer.Error!void {
        for (bytes) |c| {
            if (b.at_line_start) {
                if (c == '\n') {
                    try b.w.writeAll(bareLead(b.mode));
                    if (b.hl) |*h| try h.write("\n") else try b.w.writeByte('\n');
                    continue;
                }
                try b.w.writeAll(lead(b.mode));
                try b.w.writeAll(b.indent);
                b.at_line_start = false;
            } else if (c == '\n') {
                if (b.hl) |*h| try h.write("\n") else try b.w.writeByte('\n');
                b.at_line_start = true;
                continue;
            }
            if (b.hl) |*h| try h.write(&.{c}) else try b.w.writeByte(c);
        }
    }

    /// Closes the pending line, which is the empty one when nothing arrived.
    pub fn finish(b: *ContentWriter) std.Io.Writer.Error!void {
        if (b.hl) |*h| try h.finish();
        if (b.at_line_start) try b.w.writeAll(bareLead(b.mode));
        try b.w.writeByte('\n');
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a record is a header and its content" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(a.allocator(),
        \\* :brain::mathy
        \\
        \\* :compass::
        \\  > line one
        \\  > line two
        \\
    , &diag);

    try testing.expectEqual(@as(usize, 2), recs.len);
    try testing.expectEqual(Sigil.agent, recs[0].sigil);
    try testing.expectEqualStrings("mathy", recs[0].value);
    try testing.expect(recs[0].content == null);
    try testing.expectEqualStrings("line one\nline two", recs[1].content.?);
}

test "both spellings parse the same document" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d1: Diagnostic = .{};
    var d2: Diagnostic = .{};
    const md = try parse(a.allocator(), "* :compass::\n  > hi\n", &d1);
    const m8 = try parse(b.allocator(), "\u{2590} \u{1F9ED}:\n\u{2502} hi\n", &d2);
    try testing.expectEqual(md[0].sigil, m8[0].sigil);
    try testing.expectEqualStrings(md[0].content.?, m8[0].content.?);
}

test "detect finds the spelling, or says it is not a document" {
    try testing.expectEqual(Mode.md, detect("* :brain::x\n").?);
    try testing.expectEqual(Mode.m8, detect("\u{2590} \u{1F9E0}:x\n").?);
    try testing.expect(detect("* not a sigil\n") == null);
    try testing.expect(detect("\u{2590} not a sigil\n") == null);
    try testing.expect(detect("just some words\n") == null);
    try testing.expect(detect("") == null);
}

test "the spellings never mix" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.ModeMixed, parse(a.allocator(), "* :compass::\n\u{2502} hi\n", &diag));
    try testing.expectEqual(@as(usize, 2), diag.line);
}

test "a sigil is ended by its colon, and content is indented under it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.MissingColon, parse(a.allocator(), "* :brain:mathy\n", &diag));
    try testing.expectError(error.MissingColon, parse(a.allocator(), "\u{2590} \u{1F9E0}mathy\n", &diag));
    try testing.expectError(error.UnexpectedLine, parse(a.allocator(), "* :compass::\n> hi\n", &diag));
    try testing.expectEqual(@as(usize, 2), diag.line);
    // Without the colon it is a bullet, not a document.
    try testing.expect(detect("* :brain:mathy\n") == null);
}

test "a quote with no space is an error, and alone is an empty line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.MissingSpace, parse(a.allocator(), "* :compass::\n  >hi\n", &diag));

    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d2: Diagnostic = .{};
    const recs = try parse(b.allocator(), "* :compass::\n  > one\n  >\n  > three\n", &d2);
    try testing.expectEqualStrings("one\n\nthree", recs[0].content.?);
}

test "a receipt is indented four spaces, and an empty line carries none" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    const src = "* :receipt::c1\n  >     one\n  >\n  >       two\n\n* :scroll::c1\n  > # three\n";
    const recs = try parse(a.allocator(), src, &diag);
    try testing.expectEqualStrings("one\n\n  two", recs[0].content.?);
    try testing.expectEqualStrings("# three", recs[1].content.?);

    var out: std.Io.Writer.Allocating = .init(a.allocator());
    try writeAll(&out.writer, .md, recs);
    try testing.expectEqualStrings(src, out.written());

    try testing.expectError(error.MissingIndent, parse(a.allocator(), "* :receipt::c1\n  >   one\n", &diag));
    try testing.expectEqual(@as(usize, 2), diag.line);
}

test "content is verbatim, so it needs no escape" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(a.allocator(), "* :compass::\n  > * :brain::not a record\n  >   indented\n", &diag);
    try testing.expectEqual(@as(usize, 1), recs.len);
    try testing.expectEqualStrings("* :brain::not a record\n  indented", recs[0].content.?);
}

test "a blank line closes the block, and records need none between them" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var d1: Diagnostic = .{};
    const packed_up = try parse(a.allocator(), "* :compass::\n  > hi\n* :brain::x\n", &d1);
    try testing.expectEqual(@as(usize, 2), packed_up.len);
    try testing.expectEqualStrings("hi", packed_up[0].content.?);

    // A run of headers with nothing between them is a run of records.
    var c: std.heap.ArenaAllocator = .init(testing.allocator);
    defer c.deinit();
    var d3: Diagnostic = .{};
    const run = try parse(c.allocator(), "* :compass::\n* :compass::\n* :compass::\n", &d3);
    try testing.expectEqual(@as(usize, 3), run.len);

    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d2: Diagnostic = .{};
    try testing.expectError(error.OrphanContent, parse(b.allocator(), "* :compass::\n  > hi\n\n  > more\n", &d2));
    try testing.expectEqual(@as(usize, 4), d2.line);
}

test "a 🤖 may say how it stopped with nothing under it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var d: Diagnostic = .{};
    const src = "* :robot::\n  > Moon\n\n* :robot::(cut off at max_tokens)\n";
    const got = try parse(arena, src, &d);
    try testing.expectEqual(@as(usize, 2), got.len);
    try testing.expectEqualStrings("(cut off at max_tokens)", got[1].value);
    try testing.expect(got[1].content == null);

    var out: std.Io.Writer.Allocating = .init(arena);
    try writeAll(&out.writer, .md, got);
    try testing.expectEqualStrings(src, out.written());
}

test "value and content are refused where the sigil takes none" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var d1: Diagnostic = .{};
    try testing.expectError(error.UnexpectedValue, parse(a.allocator(), "* :compass::words\n", &d1));

    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d2: Diagnostic = .{};
    try testing.expectError(error.UnexpectedContent, parse(b.allocator(), "* :brain::x\n  > hi\n", &d2));
}

test "an unknown sigil is an error in either spelling" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var d1: Diagnostic = .{};
    try testing.expectError(error.UnknownSigil, parse(a.allocator(), "* :nope::x\n", &d1));

    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d2: Diagnostic = .{};
    try testing.expectError(error.UnknownSigil, parse(b.allocator(), "\u{2590} \u{1F600}:x\n", &d2));
}

test "CRLF parses identically, and a doubled CR survives" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d1: Diagnostic = .{};
    var d2: Diagnostic = .{};
    const lf = try parse(a.allocator(), "* :compass::\n  > one\n", &d1);
    const crlf = try parse(b.allocator(), "* :compass::\r\n  > one\r\n", &d2);
    try testing.expectEqualStrings(lf[0].content.?, crlf[0].content.?);

    var c: std.heap.ArenaAllocator = .init(testing.allocator);
    defer c.deinit();
    var d3: Diagnostic = .{};
    const cr = try parse(c.allocator(), "* :compass::\n  > ends in CR\r\r\n  > next\n", &d3);
    try testing.expectEqualStrings("ends in CR\r\nnext", cr[0].content.?);
}

test "round trip is byte for byte, in both spellings" {
    for ([_]Mode{ .md, .m8 }) |mode| {
        var a: std.heap.ArenaAllocator = .init(testing.allocator);
        defer a.deinit();
        const arena = a.allocator();

        var src: std.Io.Writer.Allocating = .init(arena);
        try writeAll(&src.writer, mode, &.{
            .{ .sigil = .agent, .value = "mathy" },
            .{ .sigil = .system, .content = "one\n\nthree" },
            .{ .sigil = .user, .content = "" },
        });

        var diag: Diagnostic = .{};
        const recs = try parse(arena, src.written(), &diag);
        var out: std.Io.Writer.Allocating = .init(arena);
        try writeAll(&out.writer, mode, recs);
        try testing.expectEqualStrings(src.written(), out.written());
    }
}

test "streamed writing matches whole writing" {
    const cases = [_][]const u8{
        "plain\ntext",
        "content\n* :brain::looks like a record",
        "para one\n\npara two",
        "trailing newline\n",
        "",
    };
    for (cases) |c| for ([_]Mode{ .md, .m8 }) |mode| {
        var whole_buf: [512]u8 = undefined;
        var whole: std.Io.Writer = .fixed(&whole_buf);
        try write(&whole, mode, .{ .sigil = .bot, .content = c });

        var streamed_buf: [512]u8 = undefined;
        var streamed: std.Io.Writer = .fixed(&streamed_buf);
        var cw = try ContentWriter.begin(&streamed, mode, .bot, "");
        for (c) |ch| try cw.write(&[_]u8{ch});
        try cw.finish();

        try testing.expectEqualStrings(whole.buffered(), streamed.buffered());
    };
}

test "a streamed body round trips back through the parser" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const content = "one\n* :brain::two\n\nthree";

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var cw = try ContentWriter.begin(&w, .md, .bot, "");
    for (content) |c| try cw.write(&[_]u8{c});
    try cw.finish();

    var diag: Diagnostic = .{};
    const recs = try parse(a.allocator(), w.buffered(), &diag);
    try testing.expectEqual(@as(usize, 1), recs.len);
    try testing.expectEqualStrings(content, recs[0].content.?);
}
