//! `read` — a file in pages, or the content of a directory.
//!
//! A page is the coordinate everything in `munge` answers in, and it is coarse
//! on purpose. A line number is exact and dies the moment anything above it
//! moves; a page survives an edit approximately, which is all a model needs to
//! say which part of a file it is holding. Precision is carried by the strings
//! read out of a page, never by the page number itself.
//!
//! So the trailer is the tool. Content alone leaves a model guessing where it
//! landed and what to ask for next, and a model that guesses re-reads the file
//! from the top. Every answer ends by saying which pages these were, of how
//! many, and the exact `pages` value that continues.
//!
//! One command behind two tools. A path is a file or a directory, and which
//! one it is decides what comes back rather than which name was called.

const std = @import("std");
const api = @import("../api.zig");
const Ctx = api.Ctx;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

pub const command: api.Command = .{
    .name = "read",
    .summary = "read a file in pages, or list a directory",
    // A tool is spawned with nothing on stdin. There is no document here.
    .takes = .nothing,
    .run = run,
    .help = help,
};

/// A page ends on whichever of these comes first. Lines keep a page roughly
/// the same shape as the file, and characters keep one long line from handing
/// back a page nobody can afford.
const lines_per_page = 100;
const chars_per_page = 10000;

/// How much a call may be handed at once, over which whole pages are dropped
/// from the end rather than a page being cut. `BYTE_CAP` in the environment,
/// which a 🧰 sets once rather than every call carrying it.
const default_byte_cap = 16000;

const max_file = 16 * 1024 * 1024;

/// Above this a listing gives a size and nothing else. Counting pages means
/// reading the file, and a hundred capfuls is past what a listing should read.
fn listing_limit(cap: usize) usize {
    return cap * 100;
}

fn run(ctx: Ctx) !u8 {
    const path = ctx.env.get("M8_ARG_PATH") orelse
        (if (ctx.args.len > 0) ctx.args[0] else null) orelse
        return refuse(ctx, "no path given", .{});
    const cap = number(ctx, "BYTE_CAP") orelse default_byte_cap;

    // A symlink at the path itself is followed: somebody naming it means the
    // thing it points at.
    const st = Dir.cwd().statFile(ctx.io, path, .{}) catch
        return refuse(ctx, "cannot read {s}", .{path});

    if (st.kind == .directory) return list(ctx, path, cap);

    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch
        return refuse(ctx, "cannot read {s}", .{path});

    const pages = try paginate(ctx.arena, bytes);
    const asked = ctx.env.get("M8_ARG_PAGES");

    const whole = Span{ .from = 0, .to = pages.len - 1 };
    const want = switch (if (asked) |spec| select(spec, pages, bytes) else Ask.whole) {
        .span => |s| s,
        .whole => whole,
        // Out of scope is answered in the shape of an answer, because a model
        // reads it the same way and the next call is what matters.
        .beyond => |s| {
            try ctx.out.print("[Pages {d}-{d} of 1-{d}: out of scope.]\n", .{ s.from, s.to, pages.len });
            try ctx.out.flush();
            return 0;
        },
    };

    return write(ctx, bytes, pages, want, cap, asked != null);
}

// -------------------------------------------------------------------- pages

/// One page: the bytes it covers, and what it can say about itself.
///
/// `opens_mid` and `ends_mid` are what a character break costs. A page that
/// begins or ends inside a line says so, so that a model never takes half a
/// line for a whole one and edits against it.
pub const Page = struct {
    at: usize,
    end: usize,
    first_line: usize,
    last_line: usize,
    opens_mid: bool = false,
    ends_mid: bool = false,
};

pub const Span = struct { from: usize, to: usize };

/// What a `pages` value turned out to be asking for. Nothing here is a
/// failure: a value naming no page at all is somebody saying "the file", and
/// one naming pages past the end is told what the end is.
pub const Ask = union(enum) {
    span: Span,
    /// The range as it was written, for saying what it was past.
    beyond: Span,
    whole,
};

/// Cut a file into pages.
///
/// The character break is the awkward one, because it can land inside a line.
/// A line that began early in the page is long enough to be a page of its own
/// and is cut; a line that began in the last third would only leave a sliver
/// behind, so the whole line is pushed into the next page instead. That is the
/// rule that keeps most page edges on a line edge without ever letting one
/// enormous line hold a page open.
pub fn paginate(arena: Allocator, bytes: []const u8) ![]const Page {
    var out: std.ArrayList(Page) = .empty;

    var at: usize = 0;
    var line: usize = 1;
    var opens_mid = false;

    while (true) {
        var page: Page = .{
            .at = at,
            .end = at,
            .first_line = line,
            .last_line = line,
            .opens_mid = opens_mid,
        };
        var held: usize = 0;
        opens_mid = false;

        while (page.end < bytes.len and held < lines_per_page) {
            const nl = std.mem.indexOfScalarPos(u8, bytes, page.end, '\n');
            const stop = if (nl) |i| i + 1 else bytes.len;
            const began = page.end - page.at;

            if (stop - page.at > chars_per_page) {
                if (began >= chars_per_page * 2 / 3) break;
                // A line long enough to fill a page of its own is cut, and
                // both pages say where the seam is.
                page.end = page.at + chars_per_page;
                page.ends_mid = true;
                opens_mid = true;
                break;
            }

            page.end = stop;
            page.last_line = line;
            held += 1;
            if (nl != null) line += 1;
        }

        // A line the character rule pushed forward leaves the page holding
        // whole lines only, and the next page starts where this one stopped.
        if (page.end == page.at and bytes.len > at) {
            const nl = std.mem.indexOfScalarPos(u8, bytes, page.at, '\n');
            page.end = if (nl) |i| i + 1 else bytes.len;
            page.last_line = line;
            if (nl != null) line += 1;
        }

        at = page.end;
        try out.append(arena, page);
        if (at >= bytes.len) break;
    }

    // An empty file is one empty page rather than none, so that everything
    // downstream has a page to name.
    if (out.items.len == 0) try out.append(arena, .{
        .at = 0,
        .end = 0,
        .first_line = 1,
        .last_line = 1,
    });
    return out.items;
}

// ----------------------------------------------------------------- choosing

/// Which pages a `pages` value asks for, or null when it names none of them.
///
/// Nothing here fails on a malformed value. A model that writes `10 to 12`, or
/// `p11–20`, or `21+` means something obvious, and refusing it costs a turn to
/// teach a syntax the answer could simply have honoured.
pub fn select(spec: []const u8, pages: []const Page, bytes: []const u8) Ask {
    if (anchored(spec, pages, bytes)) |s| return .{ .span = clamp(s, pages.len) };

    var lo: ?usize = null;
    var hi: ?usize = null;
    var i: usize = 0;
    var seen = false;
    while (i < spec.len) {
        if (!std.ascii.isDigit(spec[i])) {
            i += 1;
            continue;
        }
        var j = i;
        while (j < spec.len and std.ascii.isDigit(spec[j])) j += 1;
        const n = std.fmt.parseInt(usize, spec[i..j], 10) catch {
            i = j;
            continue;
        };
        seen = true;
        if (lo == null or n < lo.?) lo = n;
        if (hi == null or n > hi.?) hi = n;
        i = j;
    }
    // Words and nothing else. Somebody wrote `all`, or `the whole thing`.
    if (!seen) return .whole;

    // An open end is punctuation before the first digit, or anything at all
    // after the last. The sides differ because writing differs: a leading word
    // is a label — the argument is called `pages`, so `pages 3-4` is one — and
    // a trailing word is never anything but "onwards".
    const trimmed = std.mem.trim(u8, spec, " \t");
    if (trimmed.len > 0 and !std.ascii.isAlphanumeric(trimmed[0])) lo = 1;
    if (trimmed.len > 0 and !std.ascii.isDigit(trimmed[trimmed.len - 1])) hi = pages.len;

    if (lo.? > pages.len) return .{ .beyond = .{ .from = lo.?, .to = hi.? } };
    return .{ .span = clamp(.{ .from = lo.? - 1, .to = hi.? - 1 }, pages.len) };
}

/// `N@string` — N pages from wherever a string is, and a negative N for the
/// pages above it.
///
/// A match near a page edge is the case this exists for. Landing on a match in
/// the first ten lines of a page means the thing it belongs to started on the
/// page before, so that page comes too, and a single page asked for around a
/// match at the far edge becomes two rather than a page that stops just as it
/// gets interesting.
fn anchored(spec: []const u8, pages: []const Page, bytes: []const u8) ?Span {
    const at = std.mem.indexOfScalar(u8, spec, '@') orelse return null;
    const count = std.fmt.parseInt(isize, std.mem.trim(u8, spec[0..at], " \t"), 10) catch return null;
    if (count == 0) return null;
    const needle = spec[at + 1 ..];
    if (needle.len == 0) return null;

    const hit = std.mem.indexOf(u8, bytes, needle) orelse return null;
    var p: usize = 0;
    for (pages, 0..) |page, i| if (hit >= page.at and hit < @max(page.end, page.at + 1)) {
        p = i;
        break;
    };

    const line = lineOf(bytes, hit);
    const near_top = line < pages[p].first_line + 10;
    const near_end = line + 10 > pages[p].last_line;

    if (count > 0) {
        var n: usize = @intCast(count);
        if (n == 1 and near_end) n = 2;
        const from = if (near_top and p > 0) p - 1 else p;
        return .{ .from = from, .to = from + n - 1 };
    }

    var n: usize = @intCast(-count);
    if (n == 1 and near_top) n = 2;
    const to = if (near_end and p + 1 < pages.len) p + 1 else p;
    return .{ .from = to -| (n - 1), .to = to };
}

/// Which page an offset is on. A page is what every answer here is addressed
/// in, so anything that found something in a file says where in these terms.
pub fn pageOf(pages: []const Page, at: usize) usize {
    var i = pages.len - 1;
    while (i > 0) : (i -= 1) if (at >= pages[i].at) return i;
    return 0;
}

fn lineOf(bytes: []const u8, at: usize) usize {
    return std.mem.count(u8, bytes[0..at], "\n") + 1;
}

fn clamp(s: Span, len: usize) Span {
    return .{ .from = @min(s.from, len - 1), .to = @min(s.to, len - 1) };
}

// ------------------------------------------------------------------ writing

/// The content, and then what a model needs to ask for the next of it.
fn write(ctx: Ctx, bytes: []const u8, pages: []const Page, want: Span, cap: usize, asked: bool) !u8 {
    // Whole pages go, or they do not. A page cut to fit would be a page whose
    // number no longer means what every other answer means by it.
    var to = want.from;
    var held: usize = 0;
    var capped = false;
    while (to <= want.to) : (to += 1) {
        const holds = pages[to].end - pages[to].at;
        if (to > want.from and held + holds > cap) {
            capped = true;
            to -= 1;
            break;
        }
        held += holds;
    }
    if (to > want.to) to = want.to;

    const first = pages[want.from];
    const last = pages[to];
    try ctx.out.writeAll(bytes[first.at..last.end]);
    if (last.end > first.at and bytes[last.end - 1] != '\n') try ctx.out.writeByte('\n');

    // Nothing to say when the whole file was asked for and the whole file went.
    const whole = !asked and !capped;
    if (!whole) {
        try ctx.out.print("[Pages {d}-{d} of 1-{d}. Lines {d}-{d}.", .{
            want.from + 1, to + 1, pages.len,
            first.first_line, last.last_line,
        });
        if (first.opens_mid) try ctx.out.print(" Opens mid-line {d}.", .{first.first_line});
        if (last.ends_mid) try ctx.out.print(" Ends mid-line {d}.", .{last.last_line});
        if (capped) try ctx.out.print(" Returning fewer pages due to a {d} byte cap.", .{cap});
        if (to + 1 < pages.len) {
            // The same width they asked for, so continuing is the same shape
            // of call rather than a new decision every time.
            const width = to - want.from + 1;
            try ctx.out.print(" Use pages=\"{d}-{d}\" to continue.", .{
                to + 2, @min(pages.len, to + 1 + width),
            });
        } else try ctx.out.writeAll(" End of file.");
        try ctx.out.writeAll("]\n");
    }

    try ctx.out.flush();
    return 0;
}

// -------------------------------------------------------------- directories

/// A directory, as the paths a read would be given back.
///
/// Every line is something to call `read` with, spelled the way it would have
/// to be spelled, and a file says how many pages it holds so that a model can
/// choose a range before it has opened anything.
fn list(ctx: Ctx, path: []const u8, cap: usize) !u8 {
    var dir = Dir.cwd().openDir(ctx.io, path, .{ .iterate = true }) catch
        return refuse(ctx, "cannot read {s}", .{path});
    defer dir.close(ctx.io);

    var names: std.ArrayList(Dir.Entry) = .empty;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |e| try names.append(ctx.arena, .{
        .name = try ctx.arena.dupe(u8, e.name),
        .kind = e.kind,
        .inode = e.inode,
    });
    std.mem.sort(Dir.Entry, names.items, {}, byName);

    const base = std.mem.trimEnd(u8, path, "/");
    for (names.items) |e| {
        const full = try std.fs.path.join(ctx.arena, &.{ base, e.name });
        switch (e.kind) {
            .directory => try ctx.out.print("{s}/\n", .{full}),
            .sym_link => {
                var buf: [Dir.max_path_bytes]u8 = undefined;
                const n = Dir.cwd().readLink(ctx.io, full, &buf) catch {
                    try ctx.out.print("{s} ->\n", .{full});
                    continue;
                };
                try ctx.out.print("{s} -> {s}\n", .{ full, buf[0..n] });
            },
            .file => try ctx.out.print("{s}{s}\n", .{ full, try measure(ctx, full, cap) }),
            // A device, a socket, a fifo: named, and nothing claimed about it.
            else => try ctx.out.print("{s}\n", .{full}),
        }
    }

    try ctx.out.flush();
    return 0;
}

/// What a file is worth saying in a listing.
///
/// Pages cost a read, so they are only counted for something a read would
/// plausibly be pointed at. Anything enormous, and anything binary, gets its
/// size and nothing that pretends it is text.
fn measure(ctx: Ctx, full: []const u8, cap: usize) ![]const u8 {
    const st = Dir.cwd().statFile(ctx.io, full, .{}) catch return "";
    if (st.size > listing_limit(cap)) return std.fmt.allocPrint(ctx.arena, " ({s})", .{try size(ctx.arena, st.size)});

    const bytes = Dir.cwd().readFileAlloc(ctx.io, full, ctx.arena, .limited(max_file)) catch return "";
    if (std.mem.indexOfScalar(u8, bytes, 0) != null)
        return std.fmt.allocPrint(ctx.arena, " ({s})", .{try size(ctx.arena, st.size)});

    const pages = try paginate(ctx.arena, bytes);
    return std.fmt.allocPrint(ctx.arena, " ({s}, {d} lines, 1-{d} pages)", .{
        try size(ctx.arena, st.size),
        pages[pages.len - 1].last_line,
        pages.len,
    });
}

fn size(arena: Allocator, n: u64) ![]const u8 {
    if (n < 1024) return std.fmt.allocPrint(arena, "{d}B", .{n});
    if (n < 1024 * 1024) return std.fmt.allocPrint(arena, "{d}KB", .{n / 1024});
    return std.fmt.allocPrint(arena, "{d}MB", .{n / (1024 * 1024)});
}

fn byName(_: void, a: Dir.Entry, b: Dir.Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

// ------------------------------------------------------------------ plumbing

fn number(ctx: Ctx, key: []const u8) ?usize {
    const raw = ctx.env.get(key) orelse return null;
    return std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \t"), 10) catch null;
}

fn refuse(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("Denied - " ++ fmt ++ "\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 call munge read — a file in pages, or a directory's content
        \\
        \\An inbuilt tool, so it is reached through `call` and never typed as a
        \\command of its own. What the call said arrives as M8_ARG_*; a path may
        \\also be given as a word, for trying it from a shell.
        \\
        \\  path    the file or directory to read
        \\  pages   a range, "11-20", or "2@anchor" for pages at a match
        \\
        \\A page is about 100 lines, or 10000 characters when lines are long.
        \\Both tools are this command: a directory answers with its content, a
        \\file with its pages, whichever name was called.
        \\
        \\Every answer that is not a whole small file ends with where it landed
        \\and the `pages` value that continues it. A range is read as generously
        \\as it can be — "10 to 12", "p11-20" and "21+" all name something.
        \\
        \\  BYTE_CAP  bytes per answer, dropping whole pages  (default 16000)
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn lines(arena: Allocator, n: usize, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (0..n) |i| try out.print(arena, "{s} {d}\n", .{ text, i + 1 });
    return out.items;
}

test "a page holds a hundred lines" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = try lines(arena, 250, "line");
    const pages = try paginate(arena, body);

    try testing.expectEqual(@as(usize, 3), pages.len);
    try testing.expectEqual(@as(usize, 1), pages[0].first_line);
    try testing.expectEqual(@as(usize, 100), pages[0].last_line);
    try testing.expectEqual(@as(usize, 101), pages[1].first_line);
    try testing.expectEqual(@as(usize, 250), pages[2].last_line);
}

test "a long line early in a page is cut, and both sides say so" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const long = try arena.alloc(u8, 25000);
    @memset(long, 'x');
    const body = try std.fmt.allocPrint(arena, "{s}\nafter\n", .{long});
    const pages = try paginate(arena, body);

    try testing.expect(pages.len >= 3);
    try testing.expect(pages[0].ends_mid);
    try testing.expect(pages[1].opens_mid);
    try testing.expect(!pages[0].opens_mid);
}

test "a long line in the last third is pushed whole into the next page" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Seventy wide lines pass two thirds of the character budget while staying
    // well under the line count, and then one line runs past the end.
    var filler: std.ArrayList(u8) = .empty;
    for (0..70) |i| try filler.print(arena, "{d} {s}\n", .{ i + 1, "w" ** 98 });
    const long = try arena.alloc(u8, 5000);
    @memset(long, 'y');
    const body = try std.fmt.allocPrint(arena, "{s}{s}\ntail\n", .{ filler.items, long });
    const pages = try paginate(arena, body);

    try testing.expect(pages.len >= 2);
    try testing.expect(!pages[0].ends_mid);
    try testing.expect(!pages[1].opens_mid);
    try testing.expectEqual(@as(usize, 70), pages[0].last_line);
    try testing.expectEqual(@as(usize, 71), pages[1].first_line);
}

test "a range is read as generously as it can be" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = try lines(arena, 1000, "line");
    const pages = try paginate(arena, body);
    try testing.expectEqual(@as(usize, 10), pages.len);

    const plain = select("3-5", pages, body).span;
    try testing.expectEqual(@as(usize, 2), plain.from);
    try testing.expectEqual(@as(usize, 4), plain.to);

    // Separators nobody agreed on, and both open ends.
    const prose = select("3 to 5", pages, body).span;
    try testing.expectEqual(@as(usize, 2), prose.from);
    try testing.expectEqual(@as(usize, 4), prose.to);

    const rest = select("7-", pages, body).span;
    try testing.expectEqual(@as(usize, 6), rest.from);
    try testing.expectEqual(@as(usize, 9), rest.to);

    // A leading word is a label, so the argument's own name is not a range.
    const labelled = select("pages 3 to 5", pages, body).span;
    try testing.expectEqual(@as(usize, 2), labelled.from);
    try testing.expectEqual(@as(usize, 4), labelled.to);

    // Leading punctuation still opens the start.
    const upto = select("-4", pages, body).span;
    try testing.expectEqual(@as(usize, 0), upto.from);
    try testing.expectEqual(@as(usize, 3), upto.to);

    // Past the end is out of scope; over the end is simply the end.
    try testing.expect(select("45-46", pages, body) == .beyond);
    try testing.expectEqual(@as(usize, 9), select("9-40", pages, body).span.to);

    // A value naming no page is the file, not a refusal.
    try testing.expect(select("all of it", pages, body) == .whole);
}

test "an anchor takes the page a match is on, and its neighbour when it is near an edge" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = try lines(arena, 1000, "line");
    const pages = try paginate(arena, body);

    // Line 150 is the middle of page 2, so one page is one page.
    const mid = select("1@line 150", pages, body).span;
    try testing.expectEqual(@as(usize, 1), mid.from);
    try testing.expectEqual(@as(usize, 1), mid.to);

    // Line 105 is in the first ten lines of page 2, so page 1 comes too.
    const top = select("1@line 105", pages, body).span;
    try testing.expectEqual(@as(usize, 0), top.from);

    // Line 198 is in the last ten lines of page 2, so one page becomes two.
    const end = select("1@line 198", pages, body).span;
    try testing.expectEqual(@as(usize, 1), end.from);
    try testing.expectEqual(@as(usize, 2), end.to);

    // A negative count reaches back above the match.
    const above = select("2@line 350", pages, body).span;
    try testing.expectEqual(@as(usize, 3), above.from);
    const back = select("-2@line 350", pages, body).span;
    try testing.expectEqual(@as(usize, 2), back.from);
    try testing.expectEqual(@as(usize, 3), back.to);
}

test "an empty file is one page" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const pages = try paginate(arena, "");
    try testing.expectEqual(@as(usize, 1), pages.len);
}
