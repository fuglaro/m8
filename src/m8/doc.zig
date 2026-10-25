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

/// Parse a whole document. Values and content are materialised into `arena`,
/// since stripping quotes and \r both remove bytes from the middle of a span.
pub fn parse(arena: Allocator, src: []const u8, diag: *Diagnostic) ParseError![]Record {
    return gather(arena, src, null, diag);
}

pub fn parseMode(arena: Allocator, src: []const u8, mode: Mode, diag: *Diagnostic) ParseError![]Record {
    return gather(arena, src, mode, diag);
}

fn gather(arena: Allocator, src: []const u8, mode: ?Mode, diag: *Diagnostic) ParseError![]Record {
    var p: Parser = .{ .arena = arena, .mode = mode, .diag = diag };
    var c: Collect = .{ .arena = arena };
    try p.feed(src, &c);
    try p.finish(&c);
    return c.records.toOwnedSlice(arena);
}

/// Records, gathered from what a parser hands on.
const Collect = struct {
    arena: Allocator,
    records: std.ArrayList(Record) = .empty,
    content: std.ArrayList(u8) = .empty,
    lines: usize = 0,

    pub fn begin(c: *Collect, s: Sigil, value: []const u8) Allocator.Error!void {
        try c.records.append(c.arena, .{ .sigil = s, .value = try c.arena.dupe(u8, value) });
        c.lines = 0;
    }

    pub fn line(c: *Collect) Allocator.Error!void {
        if (c.lines > 0) try c.content.append(c.arena, '\n');
        c.lines += 1;
    }

    pub fn text(c: *Collect, bytes: []const u8) Allocator.Error!void {
        try c.content.appendSlice(c.arena, bytes);
    }

    pub fn end(c: *Collect) Allocator.Error!void {
        if (c.lines > 0) c.records.items[c.records.items.len - 1].content = try c.arena.dupe(u8, c.content.items);
        c.content.clearRetainingCapacity();
    }
};

/// Reads a document as its bytes arrive, and hands each record on as soon as
/// it is known: a header once its line is whole, and a content line once its
/// quote, and any indent its sigil asks for, have been seen. What follows that
/// on the line is handed on as it comes, so a reader that writes it out again
/// is as live as whatever is writing to it.
///
/// Every rule a line breaks is decided by its opening, so holding no more than
/// that loses no error. One \r is held too, until it is known whether a \n
/// follows it.
///
/// `h` is told `begin(sigil, value)`, `line()` as each content line opens,
/// `text(bytes)` for what is on it, and `end()` once a record is over. What it
/// is handed is only borrowed.
pub const Parser = struct {
    arena: Allocator,
    /// The spelling, once the first header has said, unless a caller already
    /// knew.
    mode: ?Mode = null,
    diag: *Diagnostic,
    held: std.ArrayList(u8) = .empty,
    /// Past a content line's opening, and handing its bytes straight on.
    passing: bool = false,
    cr: bool = false,
    cur: ?Sigil = null,
    /// Still accepting content for `cur`: no blank line has closed it.
    open: bool = false,
    line_no: usize = 0,

    pub fn feed(p: *Parser, bytes: []const u8, h: anytype) !void {
        for (bytes) |b| {
            if (p.passing) {
                if (p.cr) {
                    p.cr = false;
                    if (b != '\n') try h.text("\r");
                }
                switch (b) {
                    '\n' => p.passing = false,
                    '\r' => p.cr = true,
                    else => try h.text(&.{b}),
                }
                continue;
            }
            if (b == '\n') {
                p.line_no += 1;
                try p.whole(trimCr(p.held.items), h);
                p.held.clearRetainingCapacity();
                continue;
            }
            try p.held.append(p.arena, b);
            try p.early(h);
        }
    }

    /// The end of the document: a last line with no newline is still a line,
    /// and its \r is still dropped.
    pub fn finish(p: *Parser, h: anytype) !void {
        p.cr = false;
        if (!p.passing and p.held.items.len > 0) {
            p.line_no += 1;
            try p.whole(trimCr(p.held.items), h);
            p.held.clearRetainingCapacity();
        }
        p.passing = false;
        if (p.cur != null) try h.end();
        p.cur = null;
    }

    /// A content line whose opening has been seen in full is handed on now,
    /// rather than when it ends. Anything still in question waits for its
    /// newline, where `whole` says what is wrong with it.
    fn early(p: *Parser, h: anytype) !void {
        const mode = p.mode orelse return;
        const s = p.cur orelse return;
        if (!p.open or !s.takesContent()) return;
        const opening = lead(mode).len + s.indent().len;
        if (p.held.items.len < opening) return;
        const line = p.held.items;
        if (!std.mem.startsWith(u8, line, lead(mode)) or
            !std.mem.startsWith(u8, line[lead(mode).len..], s.indent())) return;
        p.line_no += 1;
        try h.line();
        const rest = line[opening..];
        // A \r last is held, in case it is the one before a \n.
        if (rest.len > 0 and rest[rest.len - 1] == '\r') {
            try h.text(rest[0 .. rest.len - 1]);
            p.cr = true;
        } else try h.text(rest);
        p.held.clearRetainingCapacity();
        p.passing = true;
    }

    fn whole(p: *Parser, line: []const u8, h: anytype) !void {
        const line_no = p.line_no;
        if (line.len == 0) {
            p.open = false;
            return;
        }
        const mode = p.mode orelse blk: {
            for ([_]Mode{ .m8, .md }) |m| if (std.mem.startsWith(u8, line, header(m))) {
                p.mode = m;
                break :blk m;
            };
            p.diag.* = .{ .line = line_no, .detail = "first line is not a record header" };
            return error.NotADocument;
        };
        const other: Mode = switch (mode) {
            .md => .m8,
            .m8 => .md,
        };

        if (std.mem.startsWith(u8, line, header(mode))) {
            const rest = line[header(mode).len..];
            const m = sigil.match(mode, rest) orelse {
                p.diag.* = .{ .line = line_no, .detail = "not a known sigil" };
                return error.UnknownSigil;
            };
            if (!std.mem.startsWith(u8, rest[m.len..], sigil_end)) {
                p.diag.* = .{ .line = line_no, .detail = "a sigil is ended by `:` before its value" };
                return error.MissingColon;
            }
            const value = rest[m.len + sigil_end.len ..];
            if (value.len > 0 and !m.sigil.takesValue()) {
                p.diag.* = .{ .line = line_no, .detail = "this sigil takes no value" };
                return error.UnexpectedValue;
            }
            if (p.cur != null) try h.end();
            try h.begin(m.sigil, value);
            p.cur = m.sigil;
            p.open = true;
            return;
        }

        if (std.mem.startsWith(u8, line, lead(mode)) or std.mem.eql(u8, line, bareLead(mode))) {
            const s = p.cur orelse {
                p.diag.* = .{ .line = line_no, .detail = "content before the first record" };
                return error.OrphanContent;
            };
            if (!p.open) {
                p.diag.* = .{ .line = line_no, .detail = "a blank line closed this block" };
                return error.OrphanContent;
            }
            if (!s.takesContent()) {
                p.diag.* = .{ .line = line_no, .detail = "this sigil takes no content" };
                return error.UnexpectedContent;
            }
            try h.line();
            if (line.len > bareLead(mode).len) {
                const text = line[lead(mode).len..];
                if (!std.mem.startsWith(u8, text, s.indent())) {
                    p.diag.* = .{ .line = line_no, .detail = "this sigil's content is indented four spaces" };
                    return error.MissingIndent;
                }
                try h.text(text[s.indent().len..]);
            }
            return;
        }

        if (std.mem.startsWith(u8, line, header(other)) or
            std.mem.startsWith(u8, line, bareLead(other)))
        {
            p.diag.* = .{ .line = line_no, .detail = "the other spelling; a document is one or the other" };
            return error.ModeMixed;
        }
        if (std.mem.startsWith(u8, line, bareLead(mode))) {
            p.diag.* = .{ .line = line_no, .detail = "a content line needs one space after the quote" };
            return error.MissingSpace;
        }
        if (std.mem.startsWith(u8, line, bareQuote(mode))) {
            p.diag.* = .{ .line = line_no, .detail = "a content line is indented two spaces before its quote" };
            return error.UnexpectedLine;
        }
        if (sigil.inReservedRange(line)) {
            p.diag.* = .{ .line = line_no, .detail = "a sigil needs a header before it" };
            return error.UnknownSigil;
        }
        p.diag.* = .{ .line = line_no, .detail = "neither a header nor a content line" };
        return error.UnexpectedLine;
    }
};

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

/// What a record is highlighted with, only in the rendered spelling.
/// Literal records use the indent style without interpreting or reflowing them.
fn looked(mode: Mode, look: ?Look, s: Sigil) ?Look {
    const l = look orelse return null;
    if (mode != .m8 or !(l.color or l.reflow)) return null;
    return switch (s) {
        .scroll, .bot, .thought, .call => l,
        .result, .failed => blk: {
            var literal = l;
            literal.literal = true;
            literal.reflow = false;
            break :blk literal;
        },
        else => null,
    };
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

test "a document fed a byte at a time reads as it does whole" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const src = "\n* :brain::x\r\n* :receipt::c1\n  >     one\r\n  >\n  >       two\r\r\n\n" ++
        "* :scroll::c1\n  > # three\r\n* :robot::\n  > last\r";
    var diag: Diagnostic = .{};
    const whole = try parse(arena, src, &diag);

    var p: Parser = .{ .arena = arena, .diag = &diag };
    var c: Collect = .{ .arena = arena };
    for (src) |b| try p.feed(&.{b}, &c);
    try p.finish(&c);
    try testing.expectEqual(whole.len, c.records.items.len);
    for (whole, c.records.items) |w, got| {
        try testing.expectEqual(w.sigil, got.sigil);
        try testing.expectEqualStrings(w.value, got.value);
        try testing.expectEqualStrings(w.content orelse "-", got.content orelse "-");
    }
    try testing.expectEqualStrings("one\n\n  two\r", whole[1].content.?);
    try testing.expectEqualStrings("last", whole[3].content.?);
}

test "a receipt and failure are indented four spaces, and an empty line carries none" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var diag: Diagnostic = .{};
    const src = "* :receipt::c1\n  >     one\n  >\n  >       two\n\n" ++
        "* :no_entry_sign::c1\n  >     failed\n  >\n  >       detail\n\n" ++
        "* :scroll::c1\n  > # three\n";
    const recs = try parse(a.allocator(), src, &diag);
    try testing.expectEqualStrings("one\n\n  two", recs[0].content.?);
    try testing.expectEqualStrings("failed\n\n  detail", recs[1].content.?);
    try testing.expectEqualStrings("# three", recs[2].content.?);

    var out: std.Io.Writer.Allocating = .init(a.allocator());
    try writeAll(&out.writer, .md, recs);
    try testing.expectEqualStrings(src, out.written());

    try testing.expectError(error.MissingIndent, parse(a.allocator(), "* :receipt::c1\n  >   one\n", &diag));
    try testing.expectEqual(@as(usize, 2), diag.line);
    try testing.expectError(error.MissingIndent, parse(a.allocator(), "* :no_entry_sign::c1\n  >   failed\n", &diag));
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

test "literal receipts and failures use the indent style without markdown or reflow" {
    for ([_]Sigil{ .result, .failed }) |s| {
        var a: std.heap.ArenaAllocator = .init(testing.allocator);
        defer a.deinit();
        var look: Look = .{ .width = 8 };
        look.palette.indented = .{ .fg = 123 };
        const content = "# **literal** `code`\n\n```diff\n+raw\n```";
        var whole: std.Io.Writer.Allocating = .init(a.allocator());
        try writeLooking(&whole.writer, .m8, look, .{ .sigil = s, .value = "c1", .content = content });
        var expected: std.Io.Writer.Allocating = .init(a.allocator());
        try expected.writer.print("{s}{s}:c1\n", .{ header(.m8), s.text(.m8) });
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) {
                try expected.writer.writeAll(bareLead(.m8));
            } else {
                try expected.writer.print("{s}    \x1b[0;38;5;123m{s}\x1b[0m", .{ lead(.m8), line });
            }
            try expected.writer.writeByte('\n');
        }
        try testing.expectEqualStrings(expected.written(), whole.written());
        var streamed: std.Io.Writer.Allocating = .init(a.allocator());
        var cw = try ContentWriter.beginLooking(&streamed.writer, .m8, look, s, "c1");
        for (content) |c| try cw.write(&.{c});
        try cw.finish();
        try testing.expectEqualStrings(whole.written(), streamed.written());
    }
}
