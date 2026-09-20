//! `write` — change a file by saying what is already in it.
//!
//! The ladder is the whole design. A model holding a page and copying a string
//! out of it will still get the string slightly wrong — an indent it inferred,
//! a line number it pasted along with the line, an escape it wrote as though
//! it were emitting JSON — and every one of those is a turn lost to a refusal
//! that taught it nothing. So each rung forgives one specific thing, in
//! order, and the first rung that finds the block wins.
//!
//! Forgiveness that stays quiet is the failure mode, not forgiveness itself. A
//! matcher that silently accepts a near miss has decided, on the model's
//! behalf, that this was the block it meant, and the only signal anybody gets
//! is a compiler error later. So the receipt names the rung whenever it was
//! anything but exact. It still lands, and it says how.
//!
//! What is not forgiven: a multi-line replacement that matches twice. There
//! is no rung for guessing which one, because there is nothing to guess with
//! — and `pages` is right there for saying which. Both sides count, and the
//! block counted is the one that matched rather than the one that was typed:
//! an argument unescaped a rung down is multi-line by the time it lands, and
//! a one-line block swapped for twenty of them is still twenty of them in
//! every place it hit.

const std = @import("std");
const api = @import("../api.zig");
const read = @import("read.zig");
const Ctx = api.Ctx;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

pub const command: api.Command = .{
    .name = "write",
    .summary = "change a file, or append to one",
    .takes = .nothing,
    .run = run,
    .help = help,
};

const max_file = 16 * 1024 * 1024;

/// A line short enough that it says nothing about where it is. Anchoring a
/// block on `}` is how a fuzzy match lands on the wrong block entirely, so an
/// anchor has to carry enough to be worth believing.
const anchor_chars = 8;

/// Default percentage of a block that may differ once its anchors hold. The
/// call may override it with M8_ARG_TOLERANCE.
const default_tolerance = 25;

fn run(ctx: Ctx) !u8 {
    const path = ctx.env.get("M8_ARG_PATH") orelse
        (if (ctx.args.len > 0) ctx.args[0] else null) orelse
        return refuse(ctx, "no path given", .{});
    const old_string = ctx.env.get("M8_ARG_OLD_STRING") orelse
        (if (ctx.args.len > 1) ctx.args[1] else null) orelse "";
    const new_string = ctx.env.get("M8_ARG_NEW_STRING") orelse
        (if (ctx.args.len > 2) ctx.args[2] else null) orelse "";
    const allowed = number(ctx, "M8_ARG_TOLERANCE") orelse default_tolerance;

    // Pages are what this tool scopes by and answers in, so it cuts the file
    // the way the `read` that handed the model its page did.
    const config = read.pageConfig(ctx);

    const had = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch null;

    if (old_string.len == 0) return append(ctx, path, had, new_string, config);

    const bytes = had orelse return deny(ctx, "there is no {s} to edit", .{path});
    return replace(ctx, path, bytes, old_string, new_string, allowed, config);
}

// ------------------------------------------------------------------- adding

/// Writing where there was nothing, or adding to the end of what is there.
///
/// Always on a line of its own, and always leaving a newline behind: a tool
/// that appends is used over and over, and a file that loses its last newline
/// once has lost it for every append after.
fn append(ctx: Ctx, path: []const u8, had: ?[]const u8, text: []const u8, config: read.PageConfig) !u8 {
    var out: std.ArrayList(u8) = .empty;
    if (had) |bytes| {
        try out.appendSlice(ctx.arena, bytes);
        if (bytes.len > 0 and bytes[bytes.len - 1] != '\n') try out.append(ctx.arena, '\n');
    }
    const from = out.items.len;
    try out.appendSlice(ctx.arena, text);
    if (text.len == 0 or text[text.len - 1] != '\n') try out.append(ctx.arena, '\n');

    if (std.fs.path.dirname(path)) |parent|
        Dir.cwd().createDirPath(ctx.io, parent) catch {};
    Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = out.items }) catch
        return deny(ctx, "cannot write {s}", .{path});

    const pages = try read.paginateConfig(ctx.arena, out.items, config);
    if (had == null) return say(ctx, "Created a new file with {d} page{s}", .{
        pages.len,
        if (pages.len == 1) "" else "s",
    });

    const first = read.pageOf(pages, from);
    const last = read.pageOf(pages, out.items.len - 1);
    if (first == last) return say(ctx, "Appended to page {d}", .{first + 1});
    return say(ctx, "Appended to pages {d}-{d}", .{ first + 1, last + 1 });
}

// ---------------------------------------------------------------- replacing

fn replace(
    ctx: Ctx,
    path: []const u8,
    bytes: []const u8,
    old: []const u8,
    new: []const u8,
    tolerance: usize,
    config: read.PageConfig,
) !u8 {
    const pages = try read.paginateConfig(ctx.arena, bytes, config);

    // A page range narrows where a match may start, and that is what makes a
    // second occurrence cheap to rule out: a model says which page it read the
    // block on, rather than pasting more of the file around it.
    var scope = Range{ .at = 0, .end = bytes.len };
    var scoped: ?read.Span = null;
    if (ctx.env.get("M8_ARG_PAGES")) |spec| switch (read.select(spec, pages, bytes)) {
        .span => |s| {
            scope = .{ .at = pages[s.from].at, .end = pages[s.to].end };
            scoped = s;
        },
        .beyond => |s| return deny(
            ctx,
            "pages {d}-{d} are out of scope of 1-{d}",
            .{ s.from, s.to, pages.len },
        ),
        .whole => {},
    };

    // Page markers are useful to read, but are not file content.  Only an
    // old_string that actually contains them opts into removing them; this
    // keeps a marker accidentally appearing in a normal edit from becoming a
    // new kind of forgiveness.
    const marked_old = try pageMarkers(ctx.arena, old, config.lines);
    if (marked_old.invalid) |distance| return deny(
        ctx,
        "page marker is {d} lines from its expected break, outside PAGE_LINES {d}",
        .{ distance, config.lines },
    );
    const old_without_pages = marked_old.text;
    const new_without_pages = if (marked_old.found)
        (try pageMarkers(ctx.arena, new, config.lines)).text
    else
        new;

    // How far a pasted line number may be from the line it names: one page
    // of lines. The number came off a page the model was handed, so a page is
    // as stale as it can honestly be.
    const found = try match(ctx.arena, bytes, old_without_pages, scope, tolerance, config.lines);
    if (found.at.len == 0) {
        if (scoped) |s| return deny(
            ctx,
            "found no match on pages {d}-{d}",
            .{ s.from + 1, s.to + 1 },
        );
        return deny(ctx, "found no match in {s}", .{path});
    }

    // A model that over-encodes is encoding its own output, not repeating
    // something it was handed: it reads the file through `read`, which gives
    // it the bytes, and escapes on the way out. One encoder runs over the
    // whole call, so the argument that says what to write was escaped exactly
    // as the one that said what to find, and putting back only one of them
    // lands a literal backslash and an n where a line break was meant.
    const put = if (found.undone)
        (try unescape(ctx.arena, new_without_pages)) orelse new_without_pages
    else
        new_without_pages;

    // One line can honestly appear in twenty places and mean the same thing
    // every time. A block cannot: it is long enough that two of them are two
    // different pieces of code, and choosing between them is not this tool's
    // to do. The needle is the one the ladder settled on, not the argument as
    // it arrived, because a rung that unescapes it turns a flat argument into
    // a block and the count has to follow.
    const sought = std.mem.indexOfScalar(u8, found.needle, '\n') != null;
    const written = std.mem.indexOfScalar(u8, put, '\n') != null;
    if (found.at.len > 1 and (sought or written)) return deny(
        ctx,
        "found {d} matches but a multi-line {s} must be unique",
        .{ found.at.len, if (sought) "old_string" else "new_string" },
    );

    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    for (found.at) |m| {
        try out.appendSlice(ctx.arena, bytes[at..m.at]);
        try out.appendSlice(ctx.arena, put);
        at = m.end;
    }
    try out.appendSlice(ctx.arena, bytes[at..]);

    Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = out.items }) catch
        return deny(ctx, "cannot write {s}", .{path});

    return receipt(ctx, pages, found, put.len == 0);
}

/// What happened, in pages, and how honestly it matched.
fn receipt(ctx: Ctx, pages: []const read.Page, found: Found, removed: bool) !u8 {
    const verb = if (removed) "Removed" else "Replaced";
    const first = read.pageOf(pages, found.at[0].at);
    const last = read.pageOf(pages, found.at[found.at.len - 1].end -| 1);

    var line: std.ArrayList(u8) = .empty;
    if (found.at.len == 1)
        try line.print(ctx.arena, "{s} 1 match", .{verb})
    else
        try line.print(ctx.arena, "{s} {d} matches", .{ verb, found.at.len });
    if (first == last)
        try line.print(ctx.arena, " on page {d}", .{first + 1})
    else
        try line.print(ctx.arena, " across pages {d}-{d}", .{ first + 1, last + 1 });
    if (found.how.len > 0) try line.print(ctx.arena, ". Matched {s}", .{found.how});

    return say(ctx, "{s}", .{line.items});
}

// --------------------------------------------------------------- page markers

const PageMarkers = struct {
    text: []const u8,
    found: bool = false,
    invalid: ?usize = null,
};

/// Remove the page lines emitted by `read`. A marker is trusted only when
/// the line where it was pasted is within one configured page of the source
/// line it claims to introduce; this prevents an arbitrary marker from hiding
/// a large displacement in the block.
fn pageMarkers(arena: Allocator, text: []const u8, page_lines: usize) !PageMarkers {
    const prefix = "―――――――――――――――――――――――― [Page ";
    const suffix = ")] ――――――――――――――――――――――――";
    var out: std.ArrayList(u8) = .empty;
    var found = false;
    var invalid: ?usize = null;
    var at: usize = 0;
    while (at < text.len) {
        const nl = std.mem.indexOfScalarPos(u8, text, at, '\n');
        const end = nl orelse text.len;
        const raw_line = text[at..end];
        const line = if (std.mem.endsWith(u8, raw_line, "\r")) raw_line[0 .. raw_line.len - 1] else raw_line;
        // The marker says where the next page begins in the source.  Compare
        // that with where the marker was actually pasted in this block; a
        // block may have drifted by a page, but not by an unrelated distance.
        const line_no = std.mem.count(u8, text[0..at], "\n") + 1;
        var marker = false;
        if (std.mem.startsWith(u8, line, prefix) and std.mem.endsWith(u8, line, suffix)) {
            const marker_body = line[prefix.len .. line.len - suffix.len];
            if (std.mem.indexOf(u8, marker_body, " (Lines ")) |split| {
                const page_text = marker_body[0..split];
                const range = marker_body[split + " (Lines ".len ..];
                const page_no = std.fmt.parseInt(usize, page_text, 10) catch null;
                if (page_text.len > 0 and page_no != null) {
                    if (std.mem.indexOfScalar(u8, range, '-')) |dash| {
                        const lo = std.fmt.parseInt(usize, range[0..dash], 10) catch 0;
                        const hi = std.fmt.parseInt(usize, range[dash + 1 ..], 10) catch 0;
                        if (lo > 0 and hi >= lo) {
                            const distance = if (line_no > lo) line_no - lo else lo - line_no;
                            marker = true;
                            found = true;
                            if (distance > page_lines and invalid == null) invalid = distance;
                        }
                    }
                }
            }
        }
        if (!marker) {
            try out.appendSlice(arena, text[at..end]);
            if (nl != null) try out.append(arena, '\n');
        }
        if (nl == null) break;
        at = end + 1;
    }
    return .{ .text = out.items, .found = found, .invalid = invalid };
}

// --------------------------------------------------------------- the ladder

const Range = struct { at: usize, end: usize };

const Found = struct {
    at: []const Range = &.{},
    /// What was forgiven, for the receipt. Empty when the match was exact.
    how: []const u8 = "",
    /// The spelling of the block that actually hit, which is the argument
    /// only until a rung offers another one. Counted rather than the argument
    /// wherever the shape of the block decides something.
    needle: []const u8 = "",
    /// Whether the rung that won was the unescaping one, which says something
    /// about the call rather than about the block.
    undone: bool = false,
};

/// How a needle line and a file line are allowed to differ. Each rung holds
/// everything the rungs above it hold, so they only ever say what they add.
const Rung = enum {
    /// Nothing at all: the bytes, as given.
    exact,
    /// What a model infers rather than counts.
    indentation,
    /// Every space it put somewhere slightly different.
    whitespace,
    /// A scan line pasted back with its number still on the front.
    numbered,
    /// A quarter of a block, once its ends hold.
    block,

    fn how(r: Rung) []const u8 {
        return switch (r) {
            .exact => "",
            .indentation => "ignoring indentation",
            .whitespace => "ignoring whitespace",
            .numbered => "ignoring line number prefixes",
            // Said with its numbers, where the block is counted.
            .block => "",
        };
    }
};

/// One rung, against one spelling of the block.
const Try = struct { needle: []const u8, rung: Rung, undone: bool };

/// Every rung, in order, until one of them finds the block.
///
/// Unescaping is a rung in the middle of the list rather than a looser
/// comparison, so it offers a second spelling of the block and everything
/// below it is tried against both. It is there for a model that over-encodes,
/// escaping its own output as though it were writing JSON. It only applies
/// when the block holds no real newline at all: a model doing that does it to
/// every newline it emits, while escaping the source code means is local, so a
/// block holding both is the code's and is left alone.
fn match(
    arena: Allocator,
    bytes: []const u8,
    old: []const u8,
    scope: Range,
    tolerance: usize,
    drift: usize,
) !Found {
    const undone: ?[]const u8 = if (std.mem.indexOfScalar(u8, old, '\n') == null)
        try unescape(arena, old)
    else
        null;

    var ladder: std.ArrayList(Try) = .empty;
    for ([_]Rung{ .exact, .indentation, .whitespace }) |r|
        try ladder.append(arena, .{ .needle = old, .rung = r, .undone = false });
    if (undone) |u| for ([_]Rung{ .exact, .indentation, .whitespace }) |r|
        try ladder.append(arena, .{ .needle = u, .rung = r, .undone = true });
    for ([_]Rung{ .numbered, .block }) |r| {
        try ladder.append(arena, .{ .needle = old, .rung = r, .undone = false });
        if (undone) |u| try ladder.append(arena, .{ .needle = u, .rung = r, .undone = true });
    }

    for (ladder.items) |t| {
        const hits = try find(arena, bytes, t.needle, scope, t.rung, tolerance, drift);
        if (hits.at.len == 0) continue;
        return .{
            .at = hits.at,
            .how = try note(arena, t.undone, hits.how),
            .needle = t.needle,
            .undone = t.undone,
        };
    }
    return .{};
}

fn note(arena: Allocator, undone: bool, how: []const u8) ![]const u8 {
    if (!undone) return how;
    if (how.len == 0) return "unescaped";
    return std.fmt.allocPrint(arena, "unescaped, {s}", .{how});
}

/// Every place a needle sits in the file, under one rung.
fn find(
    arena: Allocator,
    bytes: []const u8,
    needle: []const u8,
    scope: Range,
    rung: Rung,
    tolerance: usize,
    drift: usize,
) !Found {
    var out: std.ArrayList(Range) = .empty;
    var best_differ: ?usize = null;

    // Exact is a substring rather than a line window, because the common edit
    // is a fragment inside a line and it should never have to be spelled as a
    // whole one.
    if (rung == .exact) {
        var at = scope.at;
        while (std.mem.indexOfPos(u8, bytes, at, needle)) |i| {
            if (i >= scope.end) break;
            try out.append(arena, .{ .at = i, .end = i + needle.len });
            at = i + @max(needle.len, 1);
        }
        return .{ .at = out.items };
    }

    const file = try lines(arena, bytes);
    const want = try texts(arena, std.mem.trimEnd(u8, needle, "\n"));
    if (want.len == 0 or file.len < want.len) return .{};

    var how: []const u8 = rung.how();
    var i: usize = 0;
    while (i + want.len <= file.len) : (i += 1) {
        if (file[i].at < scope.at or file[i].at >= scope.end) continue;
        const window = file[i .. i + want.len];
        var block_differ: ?usize = null;
        var candidate_how: []const u8 = "";
        if (rung == .block) {
            block_differ = try blockHolds(arena, bytes, window, want, &candidate_how, tolerance, drift);
            if (block_differ == null) continue;
        } else if (!linesHold(bytes, window, want, rung, drift)) continue;

        // For fuzzy blocks, prefer the candidate with the fewest differing
        // anchored lines. Keep ties: the caller must still reject ambiguity.
        if (block_differ) |differ| {
            if (best_differ) |best| {
                if (differ < best) {
                    out.clearRetainingCapacity();
                    best_differ = differ;
                    how = candidate_how;
                } else if (differ > best) {
                    continue;
                }
            } else {
                best_differ = differ;
                how = candidate_how;
            }
        }

        // The block the model gave is the span, always. A rung forgives how
        // lines are compared, never which lines are replaced.
        const last = window[window.len - 1];
        const ends = if (std.mem.endsWith(u8, needle, "\n"))
            @min(last.next, bytes.len)
        else
            last.end;
        try out.append(arena, .{ .at = window[0].at, .end = ends });
        i += want.len - 1;
    }
    return .{ .at = out.items, .how = how };
}

/// A line of the file: where it is, and which one it is.
const Line = struct {
    at: usize,
    /// Where the text stops, before any newline.
    end: usize,
    /// Where the next line starts.
    next: usize,
    no: usize,
};

fn lines(arena: Allocator, bytes: []const u8) ![]const Line {
    var out: std.ArrayList(Line) = .empty;
    var at: usize = 0;
    var no: usize = 1;
    while (true) {
        const nl = std.mem.indexOfScalarPos(u8, bytes, at, '\n');
        const end = nl orelse bytes.len;
        try out.append(arena, .{ .at = at, .end = end, .next = end + 1, .no = no });
        if (nl == null) break;
        at = end + 1;
        no += 1;
    }
    return out.items;
}

/// The needle's lines, which are text and nothing else — they are not
/// anywhere in the file, which is the whole reason this is happening.
fn texts(arena: Allocator, block: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, block, '\n');
    while (it.next()) |l| try out.append(arena, l);
    return out.items;
}

fn linesHold(bytes: []const u8, window: []const Line, want: []const []const u8, rung: Rung, drift: usize) bool {
    for (window, want) |a, b| if (!holds(bytes[a.at..a.end], b, a.no, rung, drift)) return false;
    return true;
}

/// One line against one line, under everything this rung and the rungs above
/// it forgive.
fn holds(have: []const u8, said: []const u8, no: usize, rung: Rung, drift: usize) bool {
    if (std.mem.eql(u8, have, said)) return true;
    if (rung == .exact) return false;

    if (trimEq(have, said)) return true;
    if (rung == .indentation) return false;

    if (squashEq(have, said)) return true;
    if (rung == .whitespace) return false;

    // `2998:line with a match` is what a scan answers with, and a model that
    // pastes one back meant the line, not the label. The number still has to
    // be near enough to be the line it was reading.
    if (numbered(said)) |n| {
        if (no + drift < n.no or n.no + drift < no) return false;
        return std.mem.eql(u8, have, n.text) or trimEq(have, n.text) or squashEq(have, n.text);
    }
    return false;
}

/// A block, held by its ends.
///
/// The anchors are the first and last lines substantial enough to be worth
/// believing. Everything outside them is still held to the rungs above — a
/// thin line at the edge is checked, it just never carries the match — and
/// within them the configured percentage of lines may differ, because a model
/// rebuilding a block from a page it read gets the shape right and a line or two
/// wrong.
fn blockHolds(
    arena: Allocator,
    bytes: []const u8,
    window: []const Line,
    want: []const []const u8,
    how: *[]const u8,
    tolerance: usize,
    drift: usize,
) !?usize {
    var top: ?usize = null;
    var bottom: usize = 0;
    for (want, 0..) |l, i| if (substantial(l)) {
        if (top == null) top = i;
        bottom = i;
    };
    // Nothing here is worth anchoring on, so nothing here gets a tolerance.
    const first = top orelse return null;

    const line = struct {
        fn of(b: []const u8, w: Line) []const u8 {
            return b[w.at..w.end];
        }
    };

    // Outside the anchors the rungs above still hold, exactly as they would
    // have without this one.
    for (0..first) |i|
        if (!holds(line.of(bytes, window[i]), want[i], window[i].no, .numbered, drift)) return null;
    for (bottom + 1..want.len) |i|
        if (!holds(line.of(bytes, window[i]), want[i], window[i].no, .numbered, drift)) return null;

    if (!holds(line.of(bytes, window[first]), want[first], window[first].no, .numbered, drift)) return null;
    if (!holds(line.of(bytes, window[bottom]), want[bottom], window[bottom].no, .numbered, drift)) return null;

    var differ: usize = 0;
    const within = bottom - first + 1;
    for (first..bottom + 1) |i|
        if (!holds(line.of(bytes, window[i]), want[i], window[i].no, .numbered, drift)) {
            differ += 1;
        };
    if (differ * 100 > within * tolerance) return null;

    how.* = try std.fmt.allocPrint(arena, "with {d} of {d} lines differing", .{ differ, within });
    return differ;
}

/// Whether a line says enough about where it is to anchor a block on it.
fn substantial(line: []const u8) bool {
    var n: usize = 0;
    for (line) |c| {
        if (!std.ascii.isWhitespace(c)) n += 1;
    }
    return n >= anchor_chars;
}

fn trimEq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, a, " \t\r"), std.mem.trim(u8, b, " \t\r"));
}

/// The same line with every space in it ignored, which is what a model
/// retyping a line rather than copying it gets wrong.
fn squashEq(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and std.ascii.isWhitespace(a[i])) i += 1;
        while (j < b.len and std.ascii.isWhitespace(b[j])) j += 1;
        if (i == a.len or j == b.len) return i == a.len and j == b.len;
        if (a[i] != b[j]) return false;
        i += 1;
        j += 1;
    }
}

const Numbered = struct { no: usize, text: []const u8 };

/// `2998:` on the front of a line, and what is behind it.
fn numbered(line: []const u8) ?Numbered {
    const at = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    if (at == 0) return null;
    for (line[0..at]) |c| if (!std.ascii.isDigit(c)) return null;
    const no = std.fmt.parseInt(usize, line[0..at], 10) catch return null;
    return .{ .no = no, .text = line[at + 1 ..] };
}

/// A block whose escaping doubled in transport, put back.
///
/// Null when there was nothing escaped in it, so that this never counts as a
/// rung that fired.
fn unescape(arena: Allocator, text: []const u8) !?[]const u8 {
    if (std.mem.indexOfScalar(u8, text, '\\') == null) return null;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] != '\\' or i + 1 == text.len) {
            try out.append(arena, text[i]);
            continue;
        }
        i += 1;
        switch (text[i]) {
            'n' => try out.append(arena, '\n'),
            't' => try out.append(arena, '\t'),
            'r' => try out.append(arena, '\r'),
            '\'', '"', '`', '\\' => try out.append(arena, text[i]),
            else => {
                try out.append(arena, '\\');
                try out.append(arena, text[i]);
            },
        }
    }
    return out.items;
}

// ----------------------------------------------------------------- plumbing

/// The block mismatch allowance is a percentage of the anchored lines. An
/// invalid value keeps the safe default, as the other numeric munge arguments
/// do.
fn number(ctx: Ctx, key: []const u8) ?usize {
    const raw = ctx.env.get(key) orelse return null;
    return std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \t"), 10) catch null;
}

fn say(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.out.print("[" ++ fmt ++ "]\n", args);
    try ctx.out.flush();
    return 0;
}

/// A denial is the answer, in the shape of an answer. It goes to stderr and
/// fails, which is what makes it a 🚫 rather than a receipt somebody has to
/// read twice to notice that nothing happened.
fn deny(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("[DENIED: " ++ fmt ++ "]\n", args);
    try ctx.err.flush();
    return 1;
}

fn refuse(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("Denied - " ++ fmt ++ "\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 call munge write — change a file, or append to one
        \\
        \\An inbuilt tool, so it is reached through `call` and never typed as a
        \\command of its own. What the call said arrives as M8_ARG_*.
        \\
        \\  path        the file to change or create
        \\  old_string  what to replace; omitted, this appends
        \\  new_string  what to put there; empty, this removes
        \\  pages       a range the matches must start in
        \\  tolerance   percentage of anchored block lines allowed to differ (default 25)
        \\
        \\  PAGE_LINES  logical page line target       (default 100)
        \\  PAGE_BYTES  logical page byte target       (default 10000)
        \\
        \\The page settings are `read`'s, and they belong here for the same
        \\reason: `pages` is counted off pages of that size, and a line number
        \\pasted on the front of a line is believed within one page of where
        \\the line actually sits.
        \\
        \\A replacement that matches twice is refused whenever either side of
        \\it spans lines, because choosing between two blocks is not this
        \\tool's to do — name a page instead.
        \\
        \\Matching forgives, in order: nothing, indentation, all whitespace, an
        \\argument the model over-encoded, a line number pasted on the front,
        \\and the configured percentage of a block once its ends hold (25% by
        \\default). An end has to carry
        \\eight characters to be worth anchoring on. Whatever was forgiven is
        \\named in the receipt. An over-encoded old_string is taken to mean an
        \\over-encoded new_string, and both are put back.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const body =
    \\const std = @import("std");
    \\
    \\fn add(a: usize, b: usize) usize {
    \\    const total = a + b;
    \\    const doubled = total * 2;
    \\    const result = doubled - total;
    \\    return result;
    \\}
    \\
    \\fn sub(a: usize, b: usize) usize {
    \\    return a - b;
    \\}
    \\
;

fn matched(arena: Allocator, old: []const u8) !Found {
    return match(arena, body, old, .{ .at = 0, .end = body.len }, default_tolerance, read.default_page_lines);
}

test "an exact fragment matches wherever it sits" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const one = try matched(arena, "a - b");
    try testing.expectEqual(@as(usize, 1), one.at.len);
    try testing.expectEqualStrings("", one.how);

    const many = try matched(arena, "usize");
    try testing.expect(many.at.len > 2);
}

test "indentation is forgiven, and said" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Indented further than the file has it, so it is nowhere in the bytes as
    // written and only a line comparison can find it.
    const hit = try matched(arena, "        return result;");
    try testing.expectEqual(@as(usize, 1), hit.at.len);
    try testing.expectEqualStrings("ignoring indentation", hit.how);
    try testing.expectEqualStrings("    return result;", body[hit.at[0].at..hit.at[0].end]);
}

test "whitespace inside a line is forgiven, and said" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // A space dropped in the middle, which no trim can reach.
    const hit = try matched(arena, "fn add(a: usize,b: usize) usize {");
    try testing.expectEqual(@as(usize, 1), hit.at.len);
    try testing.expectEqualStrings("ignoring whitespace", hit.how);
}

test "a line number pasted on the front is forgiven only near its line" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const near = try matched(arena, "4:    const total = a + b;");
    try testing.expectEqual(@as(usize, 1), near.at.len);
    try testing.expectEqualStrings("ignoring line number prefixes", near.how);

    const far = try matched(arena, "4000:    const total = a + b;");
    try testing.expectEqual(@as(usize, 0), far.at.len);
}

test "how far a line number may have drifted is the page it came off" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The same paste twice, against two page sizes. A number read off a
    // hundred-line page is still believable forty lines out; read off a
    // ten-line page it names somewhere the model was never looking.
    const wide = try match(arena, body, "40:    const total = a + b;", .{ .at = 0, .end = body.len }, default_tolerance, read.default_page_lines);
    try testing.expectEqual(@as(usize, 1), wide.at.len);

    const narrow = try match(arena, body, "40:    const total = a + b;", .{ .at = 0, .end = body.len }, default_tolerance, 10);
    try testing.expectEqual(@as(usize, 0), narrow.at.len);
}

test "a block holds by its ends, and a quarter of it may differ" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Five lines between the anchors, one of them wrong: inside the quarter.
    const ok = try matched(arena,
        \\fn add(a: usize, b: usize) usize {
        \\    const total = a + b;
        \\    const doubled = total + total;
        \\    const result = doubled - total;
        \\    return result;
        \\}
    );
    try testing.expectEqual(@as(usize, 1), ok.at.len);
    try testing.expectEqualStrings("with 1 of 5 lines differing", ok.how);
    try testing.expect(std.mem.startsWith(u8, body[ok.at[0].at..], "fn add"));

    // Two of five is past it.
    const no = try matched(arena,
        \\fn add(a: usize, b: usize) usize {
        \\    const total = a + b;
        \\    const doubled = total + total;
        \\    const result = something(else);
        \\    return result;
        \\}
    );
    try testing.expectEqual(@as(usize, 0), no.at.len);
}

test "a block chooses the candidate with fewer differing lines" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\fn chosen() {
        \\    first mismatch
        \\    second mismatch
        \\    end marker
        \\fn chosen() {
        \\    wanted one
        \\    wanted
        \\    end marker
    ;
    const old =
        \\fn chosen() {
        \\    wanted one
        \\    wanted two
        \\    end marker
    ;
    const hit = try match(arena, src, old, .{ .at = 0, .end = src.len }, 50, read.default_page_lines);
    try testing.expectEqual(@as(usize, 1), hit.at.len);
    try testing.expectEqualStrings("with 1 of 4 lines differing", hit.how);
    try testing.expect(std.mem.startsWith(u8, src[hit.at[0].at..], "fn chosen() {\n    wanted one"));
}

test "a thin line at the edge of a block is checked, never anchored on" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The `}` is outside the anchors, so it is held to the rungs above and a
    // block that gets it wrong does not match at all.
    const wrong = try matched(arena,
        \\    const doubled = total * 2;
        \\    const result = doubled - total;
        \\    return result;
        \\);
    );
    try testing.expectEqual(@as(usize, 0), wrong.at.len);
}

test "a block of nothing but delimiters gets no tolerance" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const thin = try matched(arena, "}\n\n{\n");
    try testing.expectEqual(@as(usize, 0), thin.at.len);
}

test "escaping that doubled in transport is put back, and code that means it is not" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // A file whose source genuinely holds a backslash and an n.
    const src = "const nl = '\\n';\nconst t = 1;\n";

    // The argument arrived with its escaping doubled: no real newline anywhere
    // in it, so it can only have happened in transport.
    const fixed = try match(arena, src, "const nl = '\\\\n';", .{ .at = 0, .end = src.len }, default_tolerance, read.default_page_lines);
    try testing.expectEqual(@as(usize, 1), fixed.at.len);
    try testing.expectEqualStrings("unescaped", fixed.how);

    // The same block with a real newline in it is the code's own escaping, and
    // matches as it stands or not at all.
    const both = try match(arena, src, "const nl = '\\n';\nconst t = 1;", .{ .at = 0, .end = src.len }, default_tolerance, read.default_page_lines);
    try testing.expectEqual(@as(usize, 1), both.at.len);
    try testing.expectEqualStrings("", both.how);
}

test "the needle carried out is the one that hit, not the one that arrived" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Flat on the way in and a block by the time it lands, which is the whole
    // reason the count reads the needle instead of the argument.
    const src = "a\nb\nX\na\nb\nY\n";
    const hit = try match(arena, src, "a\\nb", .{ .at = 0, .end = src.len }, default_tolerance, read.default_page_lines);
    try testing.expectEqual(@as(usize, 2), hit.at.len);
    try testing.expectEqualStrings("unescaped", hit.how);
    try testing.expect(std.mem.indexOfScalar(u8, hit.needle, '\n') != null);

    try testing.expect(hit.undone);

    // Nothing was offered, so the needle is the argument as given.
    const plain = try matched(arena, "a - b");
    try testing.expectEqualStrings("a - b", plain.needle);
    try testing.expect(!plain.undone);
}

test "a scope keeps a match to the pages it was read on" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const all = try match(arena, body, "usize", .{ .at = 0, .end = body.len }, default_tolerance, read.default_page_lines);
    const half = try match(arena, body, "usize", .{ .at = 0, .end = 64 }, default_tolerance, read.default_page_lines);
    try testing.expect(half.at.len < all.at.len);
    try testing.expect(half.at.len > 0);
}
