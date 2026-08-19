//! Reading and writing m8 documents.
//!
//! A document is a sequence of records. A record starts at a line whose first
//! bytes are a sigil, and runs until the next such line. Its final field
//! therefore spans as many lines as it likes.
//!
//! Two normalisations happen on the way in, both reversed on the way out:
//!   * exactly one \r immediately before a \n is dropped, so \r\r\n ends a
//!     line's content in a literal \r.
//!   * a U+2063 between a newline and a sigil marks a content line, and is
//!     removed once it has done its job.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sigil = @import("sigil.zig");
const Sigil = sigil.Sigil;

pub const Record = struct {
    sigil: Sigil,
    /// Exactly `sigil.arity()` entries. The last is the body and may span
    /// lines; the ones before it are single-line and separator-free.
    fields: []const []const u8,

    pub fn body(r: Record) []const u8 {
        return r.fields[r.fields.len - 1];
    }
};

pub const ParseError = error{
    /// A line began with a reserved-range character that is not a sigil.
    UnknownSigil,
    /// Content appeared before the first sigil.
    DanglingContent,
    /// A structured line had fewer 🔹-separated fields than its sigil needs.
    MissingField,
} || Allocator.Error;

pub const Diagnostic = struct {
    line: usize = 0,
    detail: []const u8 = "",
};

/// Parse a whole document. Bodies are materialised into `arena` because
/// unescaping and \r-stripping both remove bytes from the middle of a span.
/// Fields before the body are slices into `src` and cost nothing.
pub fn parse(arena: Allocator, src: []const u8, diag: *Diagnostic) ParseError![]Record {
    var records: std.ArrayList(Record) = .empty;
    var body: std.ArrayList(u8) = .empty;

    var current: ?Sigil = null;
    var fields: std.ArrayList([]const u8) = .empty;

    var line_no: usize = 0;
    // A trailing newline terminates the last line rather than starting an
    // empty one, so drop it before splitting.
    const body_src = if (std.mem.endsWith(u8, src, "\n")) src[0 .. src.len - 1] else src;
    var it = std.mem.splitScalar(u8, body_src, '\n');
    while (it.next()) |raw| {
        line_no += 1;
        // Drop exactly one \r. A second one survives as literal content.
        const line = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;

        // Does this line open a new record?
        var content = line;
        var opens: ?Sigil = null;
        if (std.mem.startsWith(u8, line, sigil.escape)) {
            content = line[sigil.escape.len..];
        } else if (sigil.match(line)) |s| {
            opens = s;
        } else if (line.len > 0 and sigil.inReservedRange(line)) {
            diag.* = .{ .line = line_no, .detail = "reserved character is not a known sigil" };
            return error.UnknownSigil;
        }

        if (opens) |s| {
            if (current) |prev| try flush(arena, &records, prev, &fields, &body);
            current = s;
            fields.clearRetainingCapacity();
            body.clearRetainingCapacity();

            var rest = line[s.bytes().len..];
            // Leading fields are single-line; the body keeps every separator
            // after them.
            var taken: u8 = 1;
            while (taken < s.arity()) : (taken += 1) {
                const cut = std.mem.indexOf(u8, rest, sigil.field_sep) orelse {
                    diag.* = .{ .line = line_no, .detail = "structured line is missing a field" };
                    return error.MissingField;
                };
                try fields.append(arena, rest[0..cut]);
                rest = rest[cut + sigil.field_sep.len ..];
            }
            try body.appendSlice(arena, rest);
        } else {
            if (current == null) {
                if (content.len == 0) continue; // leading blank lines are fine
                diag.* = .{ .line = line_no, .detail = "content before the first sigil" };
                return error.DanglingContent;
            }
            try body.append(arena, '\n');
            try body.appendSlice(arena, content);
        }
    }
    if (current) |prev| try flush(arena, &records, prev, &fields, &body);
    return records.toOwnedSlice(arena);
}

fn flush(
    arena: Allocator,
    records: *std.ArrayList(Record),
    s: Sigil,
    fields: *std.ArrayList([]const u8),
    body: *std.ArrayList(u8),
) Allocator.Error!void {
    try fields.append(arena, try arena.dupe(u8, body.items));
    try records.append(arena, .{ .sigil = s, .fields = try arena.dupe([]const u8, fields.items) });
}

/// Write a record back out, re-escaping any body line that would otherwise
/// read as a sigil. Always emits \n; \r is never introduced.
pub fn write(w: *std.Io.Writer, r: Record) std.Io.Writer.Error!void {
    try w.writeAll(r.sigil.bytes());
    for (r.fields[0 .. r.fields.len - 1]) |f| {
        try w.writeAll(f);
        try w.writeAll(sigil.field_sep);
    }
    var lines = std.mem.splitScalar(u8, r.body(), '\n');
    var n: usize = 0;
    while (lines.next()) |line| : (n += 1) {
        if (n > 0) {
            try w.writeByte('\n');
            // Only a line start can be read as a sigil, and the first line
            // shares its line with the sigil already written.
            if (sigil.match(line) != null or std.mem.startsWith(u8, line, sigil.escape))
                try w.writeAll(sigil.escape);
        }
        try w.writeAll(line);
    }
    try w.writeByte('\n');
}

pub fn writeAll(w: *std.Io.Writer, records: []const Record) std.Io.Writer.Error!void {
    for (records) |r| try write(w, r);
}

/// Writes a record body incrementally.
///
/// Escaping is decided per line, and a line's first bytes are what decide it —
/// so at each line start this holds back just enough bytes to tell, then lets
/// the rest through untouched. Output stays live within a line, which is the
/// whole point when the bytes are arriving from a model a token at a time.
pub const BodyWriter = struct {
    w: *std.Io.Writer,
    pending: [sigil.max_len]u8 = undefined,
    pending_len: usize = 0,
    /// The first line shares its line with the sigil already written, so it
    /// can never be mistaken for one and is never held back.
    at_line_start: bool = false,

    /// Open a record. Leading fields are known up front; the body follows.
    pub fn begin(w: *std.Io.Writer, s: Sigil, fields: []const []const u8) std.Io.Writer.Error!BodyWriter {
        try w.writeAll(s.bytes());
        for (fields) |f| {
            try w.writeAll(f);
            try w.writeAll(sigil.field_sep);
        }
        return .{ .w = w };
    }

    pub fn write(b: *BodyWriter, bytes: []const u8) std.Io.Writer.Error!void {
        for (bytes) |c| {
            if (b.at_line_start) {
                if (c == '\n') {
                    try b.decide();
                    try b.w.writeByte('\n');
                    continue;
                }
                b.pending[b.pending_len] = c;
                b.pending_len += 1;
                if (b.pending_len == b.pending.len) try b.decide();
                continue;
            }
            try b.w.writeByte(c);
            if (c == '\n') {
                b.at_line_start = true;
                b.pending_len = 0;
            }
        }
    }

    /// Emit the held-back bytes, prefixed with an escape if they would read as
    /// the start of a new record.
    fn decide(b: *BodyWriter) std.Io.Writer.Error!void {
        const head = b.pending[0..b.pending_len];
        if (sigil.match(head) != null or std.mem.startsWith(u8, head, sigil.escape))
            try b.w.writeAll(sigil.escape);
        try b.w.writeAll(head);
        b.pending_len = 0;
        b.at_line_start = false;
    }

    pub fn finish(b: *BodyWriter) std.Io.Writer.Error!void {
        if (b.at_line_start and b.pending_len > 0) try b.decide();
        try b.w.writeByte('\n');
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn parseTest(src: []const u8) ![]Record {
    var diag: Diagnostic = .{};
    return parse(testing.allocator, src, &diag);
}

test "a body runs until the next sigil" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(arena_state.allocator(), "\u{1F9E0}mathy\n\u{1F4BB}line one\nline two\n", &diag);

    try testing.expectEqual(@as(usize, 2), recs.len);
    try testing.expectEqual(Sigil.agent, recs[0].sigil);
    try testing.expectEqualStrings("mathy", recs[0].body());
    try testing.expectEqualStrings("line one\nline two", recs[1].body());
}

test "leading fields split, the body keeps its separators" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(arena_state.allocator(), "\u{1F4E6}unit\u{1F539}celsius|fahrenheit\u{1F539}Scale\u{1F539}with a diamond\n", &diag);

    try testing.expectEqual(@as(usize, 3), recs[0].fields.len);
    try testing.expectEqualStrings("unit", recs[0].fields[0]);
    try testing.expectEqualStrings("celsius|fahrenheit", recs[0].fields[1]);
    try testing.expectEqualStrings("Scale\u{1F539}with a diamond", recs[0].body());
}

test "CRLF parses identically to LF" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var b: std.heap.ArenaAllocator = .init(testing.allocator);
    defer b.deinit();
    var d1: Diagnostic = .{};
    var d2: Diagnostic = .{};
    const lf = try parse(a.allocator(), "\u{1F9D1}one\ntwo\n", &d1);
    const crlf = try parse(b.allocator(), "\u{1F9D1}one\r\ntwo\r\n", &d2);
    try testing.expectEqualStrings(lf[0].body(), crlf[0].body());
}

test "a doubled CR ends content in a literal CR" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(arena_state.allocator(), "\u{1F9D1}ends in CR\r\r\nnext\n", &diag);
    try testing.expectEqualStrings("ends in CR\r\nnext", recs[0].body());
}

test "an escaped sigil line is content" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diag: Diagnostic = .{};
    const recs = try parse(arena_state.allocator(), "\u{1F4BB}prompt\n\u{2063}\u{1F9E0}not a sigil\n", &diag);
    try testing.expectEqual(@as(usize, 1), recs.len);
    try testing.expectEqualStrings("prompt\n\u{1F9E0}not a sigil", recs[0].body());
}

test "an unknown reserved character is an error, not content" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.UnknownSigil, parse(arena_state.allocator(), "\u{1F9D1}hi\n\u{1F600}smile\n", &diag));
    try testing.expectEqual(@as(usize, 2), diag.line);
}

test "round trip re-escapes what it must" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src = "\u{1F4BB}prompt\n\u{2063}\u{1F9E0}not a sigil\n";
    var diag: Diagnostic = .{};
    const recs = try parse(arena, src, &diag);

    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeAll(&w, recs);
    try testing.expectEqualStrings(src, w.buffered());
}

test "streamed writing escapes the same as whole writing" {
    const cases = [_][]const u8{
        "plain\ntext",
        "prompt\n\u{1F9E0}looks like a sigil",
        "\u{1F9E0}first line is safe\n\u{1F4BB}second is not",
        "trailing newline\n",
        "\u{2063}already escaped",
    };
    for (cases) |body| {
        var whole_buf: [512]u8 = undefined;
        var whole: std.Io.Writer = .fixed(&whole_buf);
        try write(&whole, .{ .sigil = .assistant, .fields = &.{body} });

        // the same body, delivered one byte at a time
        var streamed_buf: [512]u8 = undefined;
        var streamed: std.Io.Writer = .fixed(&streamed_buf);
        var bw = try BodyWriter.begin(&streamed, .assistant, &.{});
        for (body) |c| try bw.write(&[_]u8{c});
        try bw.finish();

        try testing.expectEqualStrings(whole.buffered(), streamed.buffered());
    }
}

test "a streamed body round trips back through the parser" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const body = "one\n\u{1F9E0}two\nthree";

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var bw = try BodyWriter.begin(&w, .assistant, &.{});
    for (body) |c| try bw.write(&[_]u8{c});
    try bw.finish();

    var diag: Diagnostic = .{};
    const recs = try parse(arena_state.allocator(), w.buffered(), &diag);
    try testing.expectEqual(@as(usize, 1), recs.len);
    try testing.expectEqualStrings(body, recs[0].body());
}
