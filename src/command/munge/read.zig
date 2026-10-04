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
//! many, and examples for continuing or refocusing the `pages` range.
//!
//! One command behind two tools. A path is a file or a directory, and which
//! one it is decides what comes back rather than which name was called.

const std = @import("std");
const api = @import("../api.zig");
const opts = @import("opts.zig");
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
pub const default_page_lines = 100;
const default_page_bytes = 10000;

/// How much a call may be handed at once, over which whole pages are dropped
/// from the end rather than a page being cut.
const default_byte_cap = 20000;

const options = [_]opts.Option{
    .{ .name = "pages" },
    .{ .name = "page-lines", .kind = .number },
    .{ .name = "page-bytes", .kind = .number },
    .{ .name = "byte-cap", .kind = .number },
};

pub const PageConfig = struct {
    lines: usize = default_page_lines,
    bytes: usize = default_page_bytes,
};

/// The page size a call is working in, read from the one place both tools
/// read it from. A page is the coordinate `munge` answers in, so `write` has
/// to cut a file into the same pages `read` handed back — a scope counted off
/// pages of a different size names somewhere the model never looked.
pub fn pageConfig(given: opts.Given) PageConfig {
    return .{
        .lines = @max(@as(usize, 1), given.number("page-lines") orelse default_page_lines),
        .bytes = @max(@as(usize, 1), given.number("page-bytes") orelse default_page_bytes),
    };
}

const ListingRow = struct {
    full: []const u8,
    kind: @TypeOf(@as(Dir.Entry, undefined).kind),
    estimated_bytes: usize,
    page: usize,
};

const max_file = 16 * 1024 * 1024;

/// Above this a listing gives a size and nothing else. Counting pages means
/// reading the file, and a hundred capfuls is past what a listing should read.
fn listing_limit(cap: usize) usize {
    return cap * 100;
}

fn run(ctx: Ctx) !u8 {
    const given = (try opts.parse(ctx, "read", &options, 1)) orelse return 1;
    if (given.words.len == 0) return refuse(ctx, "no path given", .{});
    const path = given.words[0];
    const cap = given.number("byte-cap") orelse default_byte_cap;
    const config = pageConfig(given);
    const asked = given.text("pages");

    // A symlink at the path itself is followed: somebody naming it means the
    // thing it points at.
    const st = Dir.cwd().statFile(ctx.io, path, .{}) catch
        return refuse(ctx, "cannot read {s}", .{path});

    if (st.kind == .directory) return list(ctx, path, cap, config, asked);

    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch
        return refuse(ctx, "cannot read {s}", .{path});

    const pages = try paginateConfig(ctx.arena, bytes, config);

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
    return paginateConfig(arena, bytes, .{});
}

pub fn paginateConfig(arena: Allocator, bytes: []const u8, config: PageConfig) ![]const Page {
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

        while (page.end < bytes.len and held < config.lines) {
            const nl = std.mem.indexOfScalarPos(u8, bytes, page.end, '\n');
            const stop = if (nl) |i| i + 1 else bytes.len;
            const began = page.end - page.at;

            if (stop - page.at > config.bytes) {
                if (began >= config.bytes * 2 / 3) break;
                // A line long enough to fill a page of its own is cut, and
                // both pages say where the seam is.
                page.end = page.at + config.bytes;
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

    // Page numbers are one-based. Be forgiving when a caller uses zero for
    // the first page, without changing the other end of a range: `0-5` is
    // the same request as `1-5`, not a six-page request.
    if (lo.? == 0) lo = 1;
    if (hi.? == 0) hi = 1;

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
    // Keep page boundaries visible when more than one page is returned.  The
    // marker is deliberately a line of its own: it can be pasted back into a
    // write, where it is removed only when it came from a read answer.
    var page = want.from;
    while (page <= to) : (page += 1) {
        const current = pages[page];
        try ctx.out.writeAll(bytes[current.at..current.end]);
        if (page < to) {
            if (current.end > current.at and bytes[current.end - 1] != '\n') try ctx.out.writeByte('\n');
            try ctx.out.print("―――――――――――――――――――――――― [Page {d} (Lines {d}-{d})] ―――――――――――――――――――――――――\n", .{
                page + 2, pages[page + 1].first_line, pages[page + 1].last_line,
            });
        }
    }
    if (last.end > first.at and bytes[last.end - 1] != '\n') try ctx.out.writeByte('\n');

    // Nothing to say when the whole file was asked for and the whole file went.
    const whole = !asked and !capped;
    if (!whole) {
        try endMarker(ctx, to + 1, pages.len);
        try ctx.out.print("[Pages {d}-{d} of 1-{d}. Lines {d}-{d}.", .{
            want.from + 1,    to + 1,         pages.len,
            first.first_line, last.last_line,
        });
        if (first.opens_mid) try ctx.out.print(" Opens mid-line {d}.", .{first.first_line});
        if (last.ends_mid) try ctx.out.print(" Ends mid-line {d}.", .{last.last_line});
        if (capped) try ctx.out.print(" Returning fewer pages due to a {d} byte cap.", .{cap});
        if (to + 1 < pages.len) try pageAdvice(ctx, want.from, to, pages.len);
        try ctx.out.writeAll("]\n");
    }

    try ctx.out.flush();
    return 0;
}

/// Mark the end of the raw content before the metadata trailer. Keeping this
/// on its own line makes it unambiguous whether the returned page is complete.
fn endMarker(ctx: Ctx, last_page: usize, total: usize) !void {
    if (last_page < total) {
        try ctx.out.print("―――――――――――――――――――――――― [End of page {d}] ――――――――――――――――――――――――\n", .{last_page});
    } else {
        try ctx.out.writeAll("―――――――――――――――――――――――― [End of file] ――――――――――――――――――――――――\n");
    }
}

/// Suggest both the usual next window and wider or shifted windows. The
/// overlapping first example is useful when the interesting construct straddles
/// the page boundary; the others let a caller widen or refocus without having
/// to infer the page arithmetic from the trailer.
fn pageAdvice(ctx: Ctx, from: usize, to: usize, total: usize) !void {
    const width = to - from + 1;
    const right = @min(total, to + width);
    try ctx.out.print(" Use pages to continue or refocus, e.g. pages=\"{d}-{d}\", \"{d}-{d}\", or \"{d}-{d}\".", .{
        to,       right,
        from + 1, right,
        from + 2, @min(total, to + 2),
    });
}

// -------------------------------------------------------------- directories

/// A directory, as the paths a read would be given back.
///
/// Every line is something to call `read` with, spelled the way it would have
/// to be spelled, and a file says how many pages it holds so that a model can
/// choose a range before it has opened anything.
fn list(ctx: Ctx, path: []const u8, cap: usize, config: PageConfig, asked: ?[]const u8) !u8 {
    var dir = Dir.cwd().openDir(ctx.io, path, .{ .iterate = true }) catch
        return refuse(ctx, "cannot read {s}", .{path});
    defer dir.close(ctx.io);
    var names: std.ArrayList(Dir.Entry) = .empty;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |e| try names.append(ctx.arena, .{ .name = try ctx.arena.dupe(u8, e.name), .kind = e.kind, .inode = e.inode });
    std.mem.sort(Dir.Entry, names.items, {}, byName);
    const base = std.mem.trimEnd(u8, path, "/");
    var rows: std.ArrayList(ListingRow) = .empty;
    var page: usize = 0;
    var estimate_held: usize = 0;
    var line_count: usize = 0;
    for (names.items) |e| {
        const full = try std.fs.path.join(ctx.arena, &.{ base, e.name });
        const estimate = listingEstimate(full, e.kind) + 1;
        if (line_count > 0 and (line_count >= config.lines or estimate_held + estimate > config.bytes)) {
            page += 1;
            estimate_held = 0;
            line_count = 0;
        }
        try rows.append(ctx.arena, .{ .full = full, .kind = e.kind, .estimated_bytes = estimate, .page = page });
        estimate_held += estimate;
        line_count += 1;
    }
    const count = if (rows.items.len == 0) 1 else page + 1;
    const markers = try ctx.arena.alloc(Page, count);
    for (markers, 0..) |*marker, i| marker.* = .{ .at = i, .end = i, .first_line = i + 1, .last_line = i + 1 };
    const selected = if (asked) |spec| select(spec, markers, "") else Ask.whole;
    const span = switch (selected) {
        .span => |s| s,
        .whole => Span{ .from = 0, .to = count - 1 },
        .beyond => |s| {
            try ctx.out.print("[Pages {d}-{d} of 1-{d}: out of scope.]\n", .{ s.from, s.to, count });
            try ctx.out.flush();
            return 0;
        },
    };
    // Estimates decide the cap boundary before any selected file is opened.
    // Rendering below preserves that boundary even when metadata drifts.
    var estimated_held: usize = 0;
    var planned_to = span.from;
    var capped = false;
    while (planned_to <= span.to) : (planned_to += 1) {
        var page_estimate: usize = 0;
        for (rows.items) |row| {
            if (row.page == planned_to) page_estimate += row.estimated_bytes;
        }
        if (planned_to > span.from and estimated_held + page_estimate > cap) {
            capped = true;
            planned_to -= 1;
            break;
        }
        estimated_held += page_estimate;
    }
    if (planned_to > span.to) planned_to = span.to;

    var output: std.Io.Writer.Allocating = .init(ctx.arena);
    var last_page = span.from;
    var p = span.from;
    while (p <= planned_to) : (p += 1) {
        // Render pages independently, retaining the pre-pass page coordinates.
        // The estimate is deliberately the cap decision: actual metadata can
        // drift, and a page admitted by the estimate must not be rendered only
        // to be thrown away because its real spelling is wider.
        const one = try renderDirectoryPage(ctx, rows.items, p, cap, config);
        try output.writer.writeAll(one);
        last_page = p;
    }
    try ctx.out.writeAll(output.written());

    // A directory is a paginated document even when it has no entries.
    try endMarker(ctx, last_page + 1, count);
    try ctx.out.print("[Pages {d}-{d} of 1-{d}.", .{ span.from + 1, last_page + 1, count });
    if (capped) try ctx.out.print(" Returning fewer pages due to a {d} byte cap.", .{cap});
    if (last_page + 1 < count) {
        try pageAdvice(ctx, span.from, last_page, count);
    } else if (rows.items.len == 0) try ctx.out.writeAll(" Empty directory.");
    try ctx.out.writeAll("]\n");
    try ctx.out.flush();
    return 0;
}

fn renderDirectoryPage(ctx: Ctx, rows: []const ListingRow, page: usize, cap: usize, config: PageConfig) ![]const u8 {
    var one: std.Io.Writer.Allocating = .init(ctx.arena);
    for (rows) |row| if (row.page == page) switch (row.kind) {
        .directory => try one.writer.print("{s}/\n", .{row.full}),
        .file => try one.writer.print("{s}{s}\n", .{ row.full, try measure(ctx, row.full, cap, config) }),
        .sym_link => {
            var link: [Dir.max_path_bytes]u8 = undefined;
            const n = Dir.cwd().readLink(ctx.io, row.full, &link) catch {
                try one.writer.print("{s} -> (no longer here)\n", .{row.full});
                continue;
            };
            try one.writer.print("{s} -> {s}\n", .{ row.full, link[0..n] });
        },
        else => try one.writer.print("{s}\n", .{row.full}),
    };
    return one.written();
}
/// What a file is worth saying in a listing.
///
/// Pages cost a read, so they are only counted for something a read would
/// plausibly be pointed at. Anything enormous, and anything binary, gets its
/// size and nothing that pretends it is text.
fn measure(ctx: Ctx, full: []const u8, cap: usize, config: PageConfig) ![]const u8 {
    const st = Dir.cwd().statFile(ctx.io, full, .{}) catch
        return std.fmt.allocPrint(ctx.arena, " (no longer here)", .{});
    if (st.kind != .file) return std.fmt.allocPrint(ctx.arena, " ({s})", .{@tagName(st.kind)});
    if (st.size > listing_limit(cap)) return std.fmt.allocPrint(ctx.arena, " ({s})", .{try size(ctx.arena, st.size)});

    const bytes = Dir.cwd().readFileAlloc(ctx.io, full, ctx.arena, .limited(max_file)) catch return "";
    if (std.mem.indexOfScalar(u8, bytes, 0) != null)
        return std.fmt.allocPrint(ctx.arena, " ({s})", .{try size(ctx.arena, st.size)});

    const pages = try paginateConfig(ctx.arena, bytes, config);
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

/// Cheap upper estimate used before any selected file is opened. The metadata
/// suffix is deliberately representative rather than an artificial maximum;
/// actual rendering is allowed to move above or below the page target.
fn listingEstimate(full: []const u8, kind: @TypeOf(@as(Dir.Entry, undefined).kind)) usize {
    return full.len + @as(usize, switch (kind) {
        .directory => 2,
        .sym_link => 64,
        .file => 48,
        else => 1,
    });
}

// ------------------------------------------------------------------ plumbing

fn refuse(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("Denied - " ++ fmt ++ "\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 munge read — a file in pages, or a directory's content
        \\
        \\  m8 munge read [OPTIONS] [--] PATH
        \\
        \\  PATH              the file or directory to read
        \\  --pages RANGE     "11-20", or "2@anchor" for pages at a match
        \\  --page-lines N    page line target                 (default 100)
        \\  --page-bytes N    page byte target                 (default 10000)
        \\  --byte-cap N      answer byte target, whole pages  (default 20000)
        \\
        \\A file page is about 100 lines, or 10000 characters when lines are
        \\long. Directory pages use the same settings to group sorted entries
        \\and their metadata into pages.
        \\Both tools are this command: a directory answers with its content, a
        \\file with its pages, whichever name was called.
        \\
        \\Answers end with where they landed and examples for using `pages` to
        \\continue or refocus when more remains. A range is read as generously as it
        \\can be — "10 to 12", "p11-20" and "21+" all name something.
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

test "page lines and bytes are independently configurable" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = "aaaa\nbbbb\ncccc\n";
    const by_line = try paginateConfig(arena, body, .{ .lines = 1, .bytes = 10000 });
    try testing.expectEqual(@as(usize, 3), by_line.len);
    const by_byte = try paginateConfig(arena, body, .{ .lines = 100, .bytes = 6 });
    try testing.expect(by_byte.len >= 2);
    try testing.expectEqual(@as(usize, 1), by_byte[0].first_line);
}

test "a page larger than the byte cap remains whole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const body = "the only page\n";
    const pages = try paginateConfig(arena, body, .{ .lines = 100, .bytes = 1 });
    try testing.expectEqual(@as(usize, 1), pages.len);
    try testing.expectEqual(@as(usize, body.len), pages[0].end);
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

    // Zero is a forgiving spelling of the one-based first page. Only the
    // zero endpoint changes, so the range keeps its requested width.
    const zero = select("0", pages, body).span;
    try testing.expectEqual(@as(usize, 0), zero.from);
    try testing.expectEqual(@as(usize, 0), zero.to);
    const zero_range = select("0-5", pages, body).span;
    try testing.expectEqual(@as(usize, 0), zero_range.from);
    try testing.expectEqual(@as(usize, 4), zero_range.to);

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
