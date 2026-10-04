//! The two bits of CommonMark that live underneath a sigil.
//!
//! A record's content is its own small markdown, and two shapes in it carry
//! meaning for more than one reader: a code span is an argv element or a call's
//! value, and a fenced block is a script or a value too long to sit on a line.
//! Both are read here so that every reader agrees, and so that all of them
//! agree with whatever is rendering the document.
//!
//! That last part is the whole reason this is not a simpler scan. m8's claim
//! is that the readable output *is* the record; it only holds while m8 reads a
//! span the way the thing showing it does. A naive first-backtick-to-next
//! reading is right until somebody writes two, and then the document says one
//! thing to a person and another to m8.
//!
//! Measured against the reference implementation rather than the prose:
//!
//!     `` ` ``      a literal backtick
//!     ``a`b``      a run ends at a run of its own length
//!     ` a `        one space each side is stripped, and only one
//!     ````…````    a fence holds any shorter run of backticks

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The code spans on one line, in order.
///
/// A run of backticks opens a span and the next run of exactly that length
/// closes it. A run that never meets its match is ordinary text, and the scan
/// carries on after it rather than swallowing the rest of the line.
pub fn spans(arena: Allocator, line: []const u8) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < line.len) {
        if (line[i] != '`') {
            i += 1;
            continue;
        }
        const open = run(line, i);
        const inner = i + open;
        var j = inner;
        const close = while (j < line.len) : (j += 1) {
            if (line[j] != '`') continue;
            const n = run(line, j);
            if (n == open) break j;
            j += n - 1;
        } else {
            // Nothing closes it, so those backticks were only ever text.
            i = inner;
            continue;
        };
        try out.append(arena, strip(line[inner..close]));
        i = close + open;
    }
    return out.items;
}

/// One space is removed from each end when there is one at both, unless that
/// is all there is. It is what lets a span hold a backtick at either edge.
fn strip(s: []const u8) []const u8 {
    if (s.len < 2 or s[0] != ' ' or s[s.len - 1] != ' ') return s;
    for (s) |c| if (c != ' ') return s[1 .. s.len - 1];
    return s;
}

fn allSpace(s: []const u8) bool {
    for (s) |c| if (c != ' ') return false;
    return true;
}

fn run(s: []const u8, at: usize) usize {
    var n: usize = 0;
    while (at + n < s.len and s[at + n] == '`') n += 1;
    return n;
}

/// The longest run of backticks in `s`.
fn longest(s: []const u8) usize {
    var most: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != '`') continue;
        const n = run(s, i);
        if (n > most) most = n;
        i += n - 1;
    }
    return most;
}

/// `s` as a code span: a run longer than anything inside it, and a space at
/// each end whenever leaving it out would change what comes back.
///
/// An empty string has no spelling here — CommonMark has none — so it is
/// written as a bare pair, which reads back as text. Nothing in m8 needs one.
pub fn writeSpan(w: *std.Io.Writer, s: []const u8) !void {
    const ticks = longest(s) + 1;
    // A space at each end is only framing when there is something between, so
    // a value that is nothing but spaces must not be padded: nothing would be
    // taken off again and it would come back longer than it went in.
    const edged = s.len > 0 and s[0] == ' ' and s[s.len - 1] == ' ' and !allSpace(s);
    const pad = s.len > 0 and (s[0] == '`' or s[s.len - 1] == '`' or edged);
    for (0..ticks) |_| try w.writeByte('`');
    if (pad) try w.writeByte(' ');
    try w.writeAll(s);
    if (pad) try w.writeByte(' ');
    for (0..ticks) |_| try w.writeByte('`');
}

pub const Fence = struct {
    /// The whole info string. Its first word remains the language hint Markdown
    /// renderers use; all of it names the runner m8 uses.
    runner: []const u8,
    code: []const u8,
};

/// True when `line` opens a fence: three or more backticks, and an info string
/// with none in it.
pub fn opensFence(line: []const u8) bool {
    const at = indentOf(line);
    if (run(line, at) < 3) return false;
    return std.mem.indexOfScalar(u8, line[at + run(line, at) ..], '`') == null;
}

/// A fenced block, read from an iterator sitting on the opening fence.
///
/// The closing run must be at least as long as the opening one, so a block may
/// hold any shorter run and a value never has to be escaped to be written down.
/// A fence carries whatever indentation its opening carried, and that much is
/// taken off each line — at most, so a line indented less keeps what it has.
///
/// The closing fence ends the value, so the newline before it is framing
/// rather than something that was written. Lines are joined by one, and a
/// value that really ends in a newline is a blank line before the close.
pub fn readFence(
    arena: Allocator,
    opening: []const u8,
    lines: *std.mem.SplitIterator(u8, .scalar),
) Allocator.Error!Fence {
    const at = indentOf(opening);
    const ticks = run(opening, at);
    const runner = std.mem.trim(u8, opening[at + ticks ..], " \t");

    var code: std.ArrayList(u8) = .empty;
    var first = true;
    while (lines.next()) |body| {
        const bat = indentOf(body);
        if (run(body, bat) >= ticks and
            std.mem.trim(u8, body[bat + run(body, bat) ..], " \t").len == 0) break;
        if (!first) try code.append(arena, '\n');
        first = false;
        try code.appendSlice(arena, body[@min(at, bat)..]);
    }
    return .{ .runner = runner, .code = code.items };
}

/// `code` as a fenced block, indented by `pad`, with a run long enough to hold
/// whatever is inside it.
pub fn writeFence(w: *std.Io.Writer, pad: []const u8, lang: []const u8, code: []const u8) !void {
    const ticks = @max(3, longest(code) + 1);
    try w.writeAll(pad);
    for (0..ticks) |_| try w.writeByte('`');
    try w.print("{s}\n", .{lang});
    var line = std.mem.splitScalar(u8, code, '\n');
    while (line.next()) |l| try w.print("{s}{s}\n", .{ pad, l });
    try w.writeAll(pad);
    for (0..ticks) |_| try w.writeByte('`');
    try w.writeByte('\n');
}

fn indentOf(s: []const u8) usize {
    return s.len - std.mem.trimStart(u8, s, " \t").len;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn only(arena: Allocator, line: []const u8) ![]const u8 {
    const got = try spans(arena, line);
    try testing.expectEqual(@as(usize, 1), got.len);
    return got[0];
}

// Pinned against the CommonMark reference implementation, not against the
// prose. Each of these was run through it and is what it produced.
test "a span ends at a run of its own length, and one space each side is framing" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectEqualStrings("a", try only(arena, "`a`"));
    try testing.expectEqualStrings("`", try only(arena, "`` ` ``"));
    try testing.expectEqualStrings("a`b", try only(arena, "``a`b``"));
    try testing.expectEqualStrings("`a`", try only(arena, "`` `a` ``"));
    try testing.expectEqualStrings("a", try only(arena, "` a `"));
    // Only one, so two spaces leave one.
    try testing.expectEqualStrings(" a ", try only(arena, "`  a  `"));
    // All spaces is not framing, or a space would have no spelling at all.
    try testing.expectEqualStrings(" ", try only(arena, "` `"));

    const two = try spans(arena, "`a` `b`");
    try testing.expectEqual(@as(usize, 2), two.len);
    try testing.expectEqualStrings("b", two[1]);

    // A run nothing closes is text, and the scan carries on after it.
    try testing.expectEqual(@as(usize, 0), (try spans(arena, "``")).len);
    try testing.expectEqualStrings("b", try only(arena, "`` and `b`"));
}

test "what is written comes back, backticks and edges included" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    for ([_][]const u8{
        "a",              "`",       "a`b", "`a`", " a ",
        "``",             "a ` ` b", " `",  "` ",  "  ",
        "x . ; rm -rf ~",
    }) |want| {
        var buf: std.Io.Writer.Allocating = .init(arena);
        try writeSpan(&buf.writer, want);
        const back = try only(arena, buf.written());
        try testing.expectEqualStrings(want, back);
    }
}

test "a fence holds any shorter run, and gives back the indent it was given" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expect(opensFence("```"));
    try testing.expect(opensFence("  ```bash"));
    try testing.expect(!opensFence("``"));
    // A backtick in the info string is not a fence at all.
    try testing.expect(!opensFence("``` a`b"));

    const src = "  ````bash\n  some ``` inside\n   deeper\n  ````";
    var lines = std.mem.splitScalar(u8, src, '\n');
    const f = try readFence(arena, lines.next().?, &lines);
    try testing.expectEqualStrings("bash", f.runner);
    // More than one word remains the runner name. Markdown renderers still use
    // its first word as the highlighting language.
    var named = std.mem.splitScalar(u8, "```bash raw\nx\n```", '\n');
    const raw = try readFence(arena, named.next().?, &named);
    try testing.expectEqualStrings("bash raw", raw.runner);

    // The opening's indent comes off, at most: the deeper line keeps one.
    try testing.expectEqualStrings("some ``` inside\n deeper", f.code);

    // And it round-trips, choosing a run long enough for what is inside.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try writeFence(&buf.writer, "  ", "bash", f.code);
    var again = std.mem.splitScalar(u8, std.mem.trimEnd(u8, buf.written(), "\n"), '\n');
    const back = try readFence(arena, again.next().?, &again);
    try testing.expectEqualStrings(f.code, back.code);
}
