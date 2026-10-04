//! `scan` — a pattern, across the files a glob names, answered in pages.
//!
//! A search is how a model decides what to read, so what it answers with has
//! to be what `read` takes. Every hit is placed on a page, hits on neighbouring
//! pages are gathered into one run, and the file says how many pages it holds —
//! so a scan ends with somewhere to go rather than a list of line numbers that
//! have to be converted into one.
//!
//! Lines are still lines. They are how a model reads a match and how it will
//! paste one back, which the edit ladder expects and forgives. The page is the
//! frame; the line is the thing inside it.
//!
//! A line that a page edge runs through is shown as the part of it on that
//! page, marked with an ellipsis on the side that was cut. Nothing here ever
//! pretends a page holds more than it does.
//!
//! Neither half has to be given. A glob with no pattern is the same tool asked
//! a smaller question — which files are there — answered with the line a search
//! would have printed above its matches, so finding a file and searching it are
//! one thing to learn. A pattern with no glob searches everything below here,
//! which is what somebody who did not say where meant.

const std = @import("std");
const api = @import("../api.zig");
const read = @import("read.zig");
const opts = @import("opts.zig");
const regex = @import("regex.zig");
const Ctx = api.Ctx;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

pub const command: api.Command = .{
    .name = "scan",
    .summary = "search files for a pattern, answered in pages",
    .takes = .nothing,
    .run = run,
    .help = help,
};

const default_byte_cap = 20000;

const options = [_]opts.Option{
    .{ .name = "regex" },
    .{ .name = "pages" },
    .{ .name = "page-lines", .kind = .number },
    .{ .name = "page-bytes", .kind = .number },
    .{ .name = "byte-cap", .kind = .number },
};
/// Where a search looks when it was not told where: the whole tree below here,
/// minus the dotted directories `**` never steps into.
const everything = "**";
const max_file = 16 * 1024 * 1024;

fn run(ctx: Ctx) !u8 {
    // A pattern and a glob, and neither has to be given. A pattern with no
    // glob is a search of everything, a glob with no pattern is a question
    // about which files exist, and both together are the search that was
    // asked for. An empty one is one that was not given.
    const given = (try opts.parse(ctx, "scan", &options, 1)) orelse return 1;
    const pattern = nonEmpty(given.text("regex"));
    const glob = nonEmpty(if (given.words.len > 0) given.words[0] else null) orelse everything;
    const cap = given.number("byte-cap") orelse default_byte_cap;
    const page_config = read.pageConfig(given);

    var vm: ?regex.Vm = null;
    if (pattern) |p| {
        const prog = switch (try regex.compile(ctx.arena, p)) {
            .bad => |why| return failure(ctx, "the pattern has {s}", .{why}),
            .program => |built| built,
        };
        vm = try regex.Vm.init(ctx.arena, prog);
    }

    var paths: std.ArrayList([]const u8) = .empty;
    try gather(ctx, glob, &paths);
    std.mem.sort([]const u8, paths.items, {}, byName);

    var results: std.ArrayList(ScanResult) = .empty;
    for (paths.items) |path| {
        if (vm) |*engine| {
            const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch continue;
            if (std.mem.indexOfScalar(u8, bytes, 0) != null) continue;
            const groups = try pagedReport(ctx.arena, engine, path, bytes, page_config);
            try results.appendSlice(ctx.arena, groups);
        } else {
            const said = try listed(ctx, path, page_config);
            if (said.len != 0) try results.append(ctx.arena, .{ .body = said, .path = path });
        }
    }

    if (results.items.len == 0) {
        try ctx.out.writeAll(if (vm == null) "[No files.]\n" else "[No matches.]\n");
        try ctx.out.flush();
        return 0;
    }

    // A results page is a run of result groups. `pages` here is intentionally
    // unrelated to the source page numbers printed inside each result.
    const asked = given.text("pages");
    const markers = try ctx.arena.alloc(read.Page, results.items.len);
    for (markers, 0..) |*m, i| m.* = .{ .at = i, .end = i, .first_line = i + 1, .last_line = i + 1 };
    const selection = if (asked) |spec| read.select(spec, markers, "") else read.Ask.whole;
    const want = switch (selection) {
        .span => |s| s,
        .whole => read.Span{ .from = 0, .to = results.items.len - 1 },
        .beyond => |s| {
            try ctx.out.print("[Results pages {d}-{d} of 1-{d}: out of scope.]\n", .{ s.from, s.to, results.items.len });
            try ctx.out.flush();
            return 0;
        },
    };

    // The head names the file, which is context rather than content: it earns
    // its line where a reader has nothing to carry over — the start of what is
    // returned, or a change of file — and nowhere else. Pages of one file's
    // matches read as one answer, so the name is said once above them.
    const introduces = struct {
        fn at(all: []const ScanResult, i: usize, from: usize) bool {
            return i == from or !std.mem.eql(u8, all[i].path, all[i - 1].path);
        }
    }.at;

    var to = want.from;
    var held: usize = 0;
    var capped = false;
    while (to <= want.to) : (to += 1) {
        const r = results.items[to];
        const opens = introduces(results.items, to, want.from);
        const n = r.body.len + if (opens) r.head.len else 0;
        const separator = if (to > want.from and opens) @as(usize, 1) else 0;
        if (to > want.from and held + separator + n > cap) {
            capped = true;
            to -= 1;
            break;
        }
        held += separator + n; // separators are content; the trailer is not
    }
    if (to > want.to) to = want.to;
    // The blank line belongs between files, where it ends one list and starts
    // another. Between pages of one file there is no break to make: they are
    // points of the same list, and a gap would split it into two.
    for (results.items[want.from .. to + 1], want.from..) |result, i| {
        if (introduces(results.items, i, want.from)) {
            if (i != want.from) try ctx.out.writeByte('\n');
            try ctx.out.writeAll(result.head);
        }
        try ctx.out.writeAll(result.body);
    }
    const paged = asked != null or capped or to + 1 < results.items.len or want.from != 0;
    if (paged) {
        try ctx.out.print("[Results pages {d}-{d} of 1-{d}.", .{ want.from + 1, to + 1, results.items.len });
        if (capped) try ctx.out.print(" Returning fewer pages due to a {d} byte cap.", .{cap});
        if (to + 1 < results.items.len) {
            try ctx.out.print(" Use pages=\"{d}-{d}\" to continue.", .{ to + 2, @min(results.items.len, to + 1 + (to - want.from + 1)) });
        } else {
            try ctx.out.writeAll(" End of scan.");
        }
        try ctx.out.writeAll("]\n");
    }
    try ctx.out.flush();
    return 0;
}

// ------------------------------------------------------------- one file

/// What one file has to say about a pattern, or nothing at all.
fn searched(ctx: Ctx, vm: *regex.Vm, path: []const u8, config: read.PageConfig) ![]const u8 {
    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch return "";
    // A binary file has nothing a line-oriented search can say about it.
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return "";
    return report(ctx.arena, vm, path, bytes, config);
}

/// The same line a search prints above its matches, and nothing under it.
fn listed(ctx: Ctx, path: []const u8, config: read.PageConfig) ![]const u8 {
    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch {
        // Too large to hold, so all that can be said is that it is there.
        const stat = Dir.cwd().statFile(ctx.io, path, .{}) catch return "";
        return named(ctx.arena, path, null, stat.size, config);
    };
    return named(ctx.arena, path, bytes, bytes.len, config);
}

/// One file's line. A file that isn't text, or was too large to hold, is
/// named with the one thing that can be said about it without reading it —
/// pages are a thing text has, and claiming them for a binary would be a lie.
fn named(arena: Allocator, path: []const u8, held: ?[]const u8, len: u64, config: read.PageConfig) ![]const u8 {
    const bytes = held orelse return std.fmt.allocPrint(arena, "{s} ({s})\n", .{
        path,
        try size(arena, len),
    });
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return std.fmt.allocPrint(
        arena,
        "{s} ({s})\n",
        .{ path, try size(arena, len) },
    );

    const pages = try read.paginateConfig(arena, bytes, config);
    return std.fmt.allocPrint(arena, "{s} ({s}, {d} lines, 1-{d} pages)\n", .{
        path,
        try size(arena, len),
        pages[pages.len - 1].last_line,
        pages.len,
    });
}

// ---------------------------------------------------------------- answering

const Hit = struct {
    // A scan answer page is one source-file page's complete match group.
    // These are deliberately not coalesced with neighbouring source pages.

    /// Which line, as the file numbers them.
    no: usize,
    page: usize,
    text: []const u8,
    /// The page edge ran through this line, on one side or the other.
    opens: bool,
    ends: bool,
};

const ScanResult = struct {
    /// The line naming the file, kept apart from the matches because whether
    /// it is worth saying depends on what was said just before it.
    head: []const u8 = "",
    body: []const u8,
    path: []const u8,
    /// The source page this group carries on from, where it is not the first
    /// of its file. Null says the file starts here, which is what makes the
    /// head worth reading as an opening rather than a resumption.
    after: ?usize = null,
};

/// Produce the independently paginatable result groups for one file. A group
/// is never split: its boundary is the source file page boundary, not the
/// answer byte cap.
fn pagedReport(arena: Allocator, vm: *regex.Vm, path: []const u8, bytes: []const u8, config: read.PageConfig) ![]ScanResult {
    const pages = try read.paginateConfig(arena, bytes, config);
    var hits: std.ArrayList(Hit) = .empty;
    var at: usize = 0;
    var no: usize = 1;
    while (at <= bytes.len) {
        const nl = std.mem.indexOfScalarPos(u8, bytes, at, '\n');
        const end = nl orelse bytes.len;
        const line = bytes[at..end];
        var found: usize = 0;
        var from: usize = 0;
        while (vm.find(line, from)) |m| {
            found += 1;
            from = if (m.end > m.at) m.end else m.at + 1;
            if (from > line.len) break;
        }
        if (found > 0) {
            const page = read.pageOf(pages, at);
            const p = pages[page];
            try hits.append(arena, .{ .no = no, .page = page, .text = bytes[@max(at, p.at)..@min(end, p.end)], .opens = at < p.at, .ends = end > p.end });
        }
        if (nl == null) break;
        at = end + 1;
        no += 1;
    }
    if (hits.items.len == 0) return &.{};

    var out: std.ArrayList(ScanResult) = .empty;
    var i: usize = 0;
    var after: ?usize = null;
    while (i < hits.items.len) {
        const page = hits.items[i].page;
        var j = i + 1;
        while (j < hits.items.len and hits.items[j].page == page) j += 1;

        // Where a group resumes a file, the page it resumes after is the one
        // thing the reader cannot work out from here: it says what was already
        // answered, so a range asked for on its own still knows its place.
        const carries = if (after) |a|
            try std.fmt.allocPrint(arena, ", continuing after page {d}", .{a + 1})
        else
            "";
        // The head stands over every group of its file that follows it, so it
        // counts what lies ahead rather than what the first of them holds. A
        // number that described only the group under it would be read as the
        // file's own, and be wrong by every page after it.
        const ahead = hits.items.len - i;
        var head: std.ArrayList(u8) = .empty;
        try head.print(arena, "{s} ({s}, {d} lines, 1-{d} pages){s} has {d} match{s}:\n", .{
            path,    try size(arena, bytes.len), pages[pages.len - 1].last_line, pages.len,
            carries, ahead,                      if (ahead == 1) "" else "es",
        });
        var body: std.ArrayList(u8) = .empty;
        try body.print(arena, "* {d} match{s} on page {d} in lines:\n", .{
            j - i, if (j - i == 1) "" else "es", page + 1,
        });
        for (hits.items[i..j]) |h| try body.print(arena, "  - {d}:{s}{s}{s}\n", .{
            h.no,
            if (h.opens) "…" else "",
            h.text,
            if (h.ends) "…" else "",
        });
        try out.append(arena, .{ .head = head.items, .body = body.items, .path = path, .after = after });
        after = page;
        i = j;
    }
    return out.items;
}

/// What one file has to say, or nothing at all.
fn report(arena: Allocator, vm: *regex.Vm, path: []const u8, bytes: []const u8, config: read.PageConfig) ![]const u8 {
    const pages = try read.paginateConfig(arena, bytes, config);

    var hits: std.ArrayList(Hit) = .empty;
    var total: usize = 0;
    var at: usize = 0;
    var no: usize = 1;
    while (at <= bytes.len) {
        const nl = std.mem.indexOfScalarPos(u8, bytes, at, '\n');
        const end = nl orelse bytes.len;
        const line = bytes[at..end];

        var found: usize = 0;
        var from: usize = 0;
        while (vm.find(line, from)) |m| {
            found += 1;
            from = if (m.end > m.at) m.end else m.at + 1;
            if (from > line.len) break;
        }

        if (found > 0) {
            total += found;
            // A line is placed on the page its match sits on, and shown as
            // much of itself as that page holds.
            const page = read.pageOf(pages, at);
            const p = pages[page];
            const shown = bytes[@max(at, p.at)..@min(end, p.end)];
            try hits.append(arena, .{
                .no = no,
                .page = page,
                .text = shown,
                .opens = at < p.at,
                .ends = end > p.end,
            });
        }

        if (nl == null) break;
        at = end + 1;
        no += 1;
    }
    if (hits.items.len == 0) return "";

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "{s} ({s}, {d} lines, 1-{d} pages) has {d} match{s}:\n", .{
        path,
        try size(arena, bytes.len),
        pages[pages.len - 1].last_line,
        pages.len,
        total,
        if (total == 1) "" else "es",
    });

    // Neighbouring pages are one run. A gap means a different part of the
    // file, and saying so is what makes the run worth reading as a whole.
    var i: usize = 0;
    while (i < hits.items.len) {
        var j = i + 1;
        while (j < hits.items.len and hits.items[j].page <= hits.items[j - 1].page + 1) j += 1;
        const near = hits.items[i..j];

        try out.print(arena, "* {d} match{s} on pages {d}-{d} in lines:\n", .{
            near.len,
            if (near.len == 1) "" else "es",
            near[0].page + 1,
            near[near.len - 1].page + 1,
        });
        for (near) |h| try out.print(arena, "  - {d}:{s}{s}{s}\n", .{
            h.no,
            if (h.opens) "…" else "",
            h.text,
            if (h.ends) "…" else "",
        });
        i = j;
    }
    return out.items;
}

// -------------------------------------------------------------------- globs

/// Every file a glob names.
///
/// Walking starts at the deepest directory the glob spells out, so a pattern
/// rooted somewhere small never costs a walk of everything above it.
fn gather(ctx: Ctx, glob: []const u8, out: *std.ArrayList([]const u8)) !void {
    var patterns: std.ArrayList([]const u8) = .empty;
    try braces(ctx.arena, glob, &patterns);

    for (patterns.items) |pattern| {
        const from = root(pattern);
        try walk(ctx, if (from.len == 0) "." else from, pattern, out);
    }
}

/// `{a,b}` spelled out, since everything below only has to think about one
/// pattern at a time.
fn braces(arena: Allocator, pattern: []const u8, out: *std.ArrayList([]const u8)) !void {
    const open = std.mem.indexOfScalar(u8, pattern, '{') orelse {
        try out.append(arena, pattern);
        return;
    };
    var depth: usize = 0;
    var close: ?usize = null;
    for (pattern[open..], open..) |c, i| {
        if (c == '{') depth += 1;
        if (c == '}') {
            depth -= 1;
            if (depth == 0) {
                close = i;
                break;
            }
        }
    }
    const shut = close orelse {
        try out.append(arena, pattern);
        return;
    };

    var depth2: usize = 0;
    var from = open + 1;
    for (pattern[open + 1 .. shut], open + 1..) |c, i| {
        if (c == '{') depth2 += 1;
        if (c == '}') depth2 -= 1;
        if (c == ',' and depth2 == 0) {
            try braces(arena, try std.mem.concat(arena, u8, &.{
                pattern[0..open], pattern[from..i], pattern[shut + 1 ..],
            }), out);
            from = i + 1;
        }
    }
    try braces(arena, try std.mem.concat(arena, u8, &.{
        pattern[0..open], pattern[from..shut], pattern[shut + 1 ..],
    }), out);
}

/// The part of a glob that is a plain path, which is where a walk can start.
fn root(pattern: []const u8) []const u8 {
    const star = std.mem.indexOfAny(u8, pattern, "*?") orelse return std.fs.path.dirname(pattern) orelse "";
    const head = pattern[0..star];
    const slash = std.mem.lastIndexOfScalar(u8, head, '/') orelse return "";
    return head[0..slash];
}

fn walk(ctx: Ctx, here: []const u8, pattern: []const u8, out: *std.ArrayList([]const u8)) !void {
    var dir = Dir.cwd().openDir(ctx.io, here, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var it = dir.iterate();
    while (try it.next(ctx.io)) |e| {
        // A dotted directory is somebody's machinery rather than their work,
        // and a symlink is a way to walk the same tree twice or leave it.
        if (e.name.len > 0 and e.name[0] == '.') continue;
        if (e.kind == .sym_link) continue;

        const full = if (std.mem.eql(u8, here, "."))
            try ctx.arena.dupe(u8, e.name)
        else
            try std.fmt.allocPrint(ctx.arena, "{s}/{s}", .{ here, e.name });

        if (e.kind == .directory) {
            try walk(ctx, full, pattern, out);
            continue;
        }
        if (e.kind == .file and matches(pattern, full)) try out.append(ctx.arena, full);
    }
}

/// Whether a path is what a glob named.
fn matches(pattern: []const u8, path: []const u8) bool {
    var pats: [64][]const u8 = undefined;
    var strs: [64][]const u8 = undefined;
    const np = cut(pattern, &pats);
    const ns = cut(path, &strs);
    return segments(pats[0..np], strs[0..ns]);
}

fn cut(text: []const u8, into: *[64][]const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, text, '/');
    while (it.next()) |part| {
        if (n == into.len) break;
        into[n] = part;
        n += 1;
    }
    return n;
}

fn segments(pats: []const []const u8, strs: []const []const u8) bool {
    if (pats.len == 0) return strs.len == 0;

    // `**` is any run of directories, including none at all.
    if (std.mem.eql(u8, pats[0], "**")) {
        var k: usize = 0;
        while (k <= strs.len) : (k += 1) {
            if (segments(pats[1..], strs[k..])) return true;
            // What `**` walks over is directories, and never a dotted one:
            // stepping past it here would let it reach inside .git.
            if (k < strs.len and strs[k].len > 0 and strs[k][0] == '.') return false;
        }
        return false;
    }

    if (strs.len == 0) return false;
    if (!segment(pats[0], strs[0])) return false;
    return segments(pats[1..], strs[1..]);
}

/// One path segment, where `*` stops at the separator and a dotted name is
/// only ever matched by a pattern that says the dot itself.
fn segment(pat: []const u8, name: []const u8) bool {
    if (name.len > 0 and name[0] == '.' and !(pat.len > 0 and pat[0] == '.')) return false;
    return wild(pat, name);
}

fn wild(pat: []const u8, name: []const u8) bool {
    if (pat.len == 0) return name.len == 0;
    switch (pat[0]) {
        '*' => {
            var k: usize = 0;
            while (k <= name.len) : (k += 1)
                if (wild(pat[1..], name[k..])) return true;
            return false;
        },
        '?' => return name.len > 0 and wild(pat[1..], name[1..]),
        else => return name.len > 0 and pat[0] == name[0] and wild(pat[1..], name[1..]),
    }
}

// ----------------------------------------------------------------- plumbing

fn byName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn size(arena: Allocator, n: u64) ![]const u8 {
    if (n < 1024) return std.fmt.allocPrint(arena, "{d}B", .{n});
    if (n < 1024 * 1024) return std.fmt.allocPrint(arena, "{d}KB", .{n / 1024});
    return std.fmt.allocPrint(arena, "{d}MB", .{n / (1024 * 1024)});
}

/// What was given, where an empty value is the same as nothing given.
fn nonEmpty(raw: ?[]const u8) ?[]const u8 {
    const text = raw orelse return null;
    return if (text.len == 0) null else text;
}

fn failure(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("[FAILED: " ++ fmt ++ "]\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 munge scan — search files for a pattern, answered in pages
        \\
        \\  m8 munge scan [OPTIONS] [--] [GLOB]
        \\
        \\  GLOB              which files, with ** and * and ? and {a,b}
        \\  --regex PATTERN   matched within one line at a time
        \\  --pages RANGE     results page range, e.g. "2-4"
        \\  --page-lines N    page line target                   (default 100)
        \\  --page-bytes N    page byte target                   (default 10000)
        \\  --byte-cap N      answer byte target, whole results  (default 20000)
        \\
        \\Neither is required. Without a glob a pattern searches everything below
        \\here; without a pattern a glob asks the other question — which files it
        \\names — and answers with the same lines, without the matches under them.
        \\
        \\The pattern has literals, ., [a-z], [[:alpha:]], the \d \w \s family,
        \\^ $ \b \B, alternation, groups, * + ? {n} {n,} {n,m}, lazy repeats and
        \\(?i). No backreferences, no lookaround, and no matching across lines.
        \\A construct it does not have is named rather than guessed at.
        \\
        \\Each match group names its file, source-file page, and line. Results
        \\pages contain whole source-page groups; a group that resumes a file
        \\repeats its context and names the page it follows. Results page
        \\numbers are distinct from source-file page numbers.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a glob names what it names" {
    try testing.expect(matches("src/**/*.zig", "src/command/munge/scan.zig"));
    try testing.expect(matches("src/**/*.zig", "src/main.zig"));
    try testing.expect(!matches("src/**/*.zig", "src/main.md"));
    try testing.expect(!matches("src/**/*.zig", "docs/main.zig"));

    try testing.expect(matches("**", "anything/at/all.txt"));
    try testing.expect(matches("*.md", "README.md"));
    try testing.expect(!matches("*.md", "docs/README.md"));
    try testing.expect(matches("src/?ain.zig", "src/main.zig"));
    try testing.expect(!matches("src/?ain.zig", "src/domain.zig"));

    // A dotted name is somebody's machinery unless the pattern says the dot.
    try testing.expect(!matches("**/*", ".git/config"));
    try testing.expect(matches(".*/*", ".git/config"));
}

test "braces spell themselves out" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var out: std.ArrayList([]const u8) = .empty;
    try braces(arena, "src/*.{zig,md}", &out);
    try testing.expectEqual(@as(usize, 2), out.items.len);
    try testing.expectEqualStrings("src/*.zig", out.items[0]);
    try testing.expectEqualStrings("src/*.md", out.items[1]);

    var nested: std.ArrayList([]const u8) = .empty;
    try braces(arena, "{a,b}/{c,d}", &nested);
    try testing.expectEqual(@as(usize, 4), nested.items.len);
}

test "a walk starts at the deepest plain directory" {
    try testing.expectEqualStrings("src/command", root("src/command/*.zig"));
    try testing.expectEqualStrings("src", root("src/**/*.zig"));
    try testing.expectEqualStrings("", root("**/*.zig"));
    try testing.expectEqualStrings("", root("*.md"));
}

test "scan result groups stop at source-page boundaries" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const body = "MARKER one\nplain\nMARKER three\nplain\n";
    const prog = switch (try regex.compile(arena, "MARKER")) {
        .bad => return error.BadPattern,
        .program => |p| p,
    };
    var vm = try regex.Vm.init(arena, prog);
    const groups = try pagedReport(arena, &vm, "demo.txt", body, .{ .lines = 2, .bytes = 1000 });
    try testing.expectEqual(@as(usize, 2), groups.len);
    try testing.expect(std.mem.indexOf(u8, groups[0].body, "on page 1") != null);
    try testing.expect(std.mem.indexOf(u8, groups[1].body, "on page 2") != null);
    try testing.expect(std.mem.indexOf(u8, groups[1].head, "continuing after page 1") != null);
    try testing.expectEqual(@as(?usize, null), groups[0].after);
    try testing.expectEqual(@as(?usize, 0), groups[1].after);

    // The name of the file is the head's to say, never the body's, so a group
    // printed under one already said is printed without it.
    try testing.expect(std.mem.indexOf(u8, groups[1].body, "demo.txt") == null);
    try testing.expect(std.mem.indexOf(u8, groups[0].head, "demo.txt") != null);
}

test "a source-page result is allowed to exceed the answer cap" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const long = try arena.alloc(u8, 200);
    @memset(long, 'x');
    const body = try std.fmt.allocPrint(arena, "MARKER {s}\n", .{long});
    const prog = switch (try regex.compile(arena, "MARKER")) {
        .bad => return error.BadPattern,
        .program => |p| p,
    };
    var vm = try regex.Vm.init(arena, prog);
    const groups = try pagedReport(arena, &vm, "wide.txt", body, .{ .lines = 1, .bytes = 20 });
    try testing.expectEqual(@as(usize, 1), groups.len);
    try testing.expect(groups[0].head.len + groups[0].body.len > 20);
}

test "matches are grouped into runs of neighbouring pages" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Three hundred lines, with a marker on the first page and the third.
    var body: std.ArrayList(u8) = .empty;
    for (1..301) |i| {
        if (i == 5 or i == 7 or i == 250)
            try body.print(arena, "line {d} MARKER\n", .{i})
        else
            try body.print(arena, "line {d}\n", .{i});
    }

    const prog = switch (try regex.compile(arena, "MARKER")) {
        .bad => return error.BadPattern,
        .program => |p| p,
    };
    var vm = try regex.Vm.init(arena, prog);
    const said = try report(arena, &vm, "demo.txt", body.items, .{});

    try testing.expect(std.mem.indexOf(u8, said, "has 3 matches:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "* 2 matches on pages 1-1 in lines:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "* 1 match on pages 3-3 in lines:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "  - 5:line 5 MARKER") != null);
    try testing.expect(std.mem.indexOf(u8, said, "  - 250:line 250 MARKER") != null);
}

test "a line a page edge runs through is shown as much of itself as fits" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // One line long enough that a page ends inside it.
    const long = try arena.alloc(u8, 15000);
    @memset(long, 'x');
    const body = try std.fmt.allocPrint(arena, "start{s}end\n", .{long});

    const prog = switch (try regex.compile(arena, "start")) {
        .bad => return error.BadPattern,
        .program => |p| p,
    };
    var vm = try regex.Vm.init(arena, prog);
    const said = try report(arena, &vm, "long.txt", body, .{});

    try testing.expect(std.mem.indexOf(u8, said, "…\n") != null);
    try testing.expect(std.mem.indexOf(u8, said, "end") == null);
}

test "a glob with no pattern names files the way a search would" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var body: std.ArrayList(u8) = .empty;
    for (1..251) |i| try body.print(arena, "line {d}\n", .{i});

    // The same line a match report prints above its matches, with nothing
    // under it — so one shape is learned once.
    try testing.expectEqualStrings(
        "demo.txt (2KB, 250 lines, 1-3 pages)\n",
        try named(arena, "demo.txt", body.items, body.items.len, .{}),
    );

    // A binary file is named, not paginated.
    try testing.expectEqualStrings(
        "blob.bin (4B)\n",
        try named(arena, "blob.bin", "a\x00bc", 4, .{}),
    );

    // Nor is one too large to have been held.
    try testing.expectEqualStrings(
        "huge.bin (23MB)\n",
        try named(arena, "huge.bin", null, 23 * 1024 * 1024, .{}),
    );
}
