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

const default_byte_cap = 16000;
/// Where a search looks when it was not told where: the whole tree below here,
/// minus the dotted directories `**` never steps into.
const everything = "**";
const max_file = 16 * 1024 * 1024;

fn run(ctx: Ctx) !u8 {
    // Two args, and neither has to be given. A pattern with no glob is a
    // search of everything, a glob with no pattern is a question about which
    // files exist, and both together are the search that was asked for.
    const pattern = arg(ctx, "M8_ARG_REGEX") orelse
        (if (ctx.args.len > 0) ctx.args[0] else null);
    const glob = arg(ctx, "M8_ARG_GLOB") orelse
        (if (ctx.args.len > 1) ctx.args[1] else null) orelse everything;
    const cap = number(ctx, "BYTE_CAP") orelse default_byte_cap;

    var vm: ?regex.Vm = null;
    if (pattern) |p| {
        const prog = switch (try regex.compile(ctx.arena, p)) {
            .bad => |why| return deny(ctx, "the pattern has {s}", .{why}),
            .program => |built| built,
        };
        vm = try regex.Vm.init(ctx.arena, prog);
    }

    var paths: std.ArrayList([]const u8) = .empty;
    try gather(ctx, glob, &paths);
    std.mem.sort([]const u8, paths.items, {}, byName);

    var held: usize = 0;
    var files: usize = 0;
    var capped = false;
    for (paths.items) |path| {
        const said = if (vm) |*engine|
            try searched(ctx, engine, path)
        else
            try listed(ctx, path);
        if (said.len == 0) continue;
        if (files > 0 and held + said.len > cap) {
            capped = true;
            break;
        }
        try ctx.out.writeAll(said);
        held += said.len;
        files += 1;
    }

    if (files == 0) try ctx.out.writeAll(if (vm == null)
        "[No files.]\n"
    else
        "[No matches.]\n");
    if (capped) try ctx.out.print(
        "[Returning fewer files due to a {d} byte cap.]\n",
        .{cap},
    );
    try ctx.out.flush();
    return 0;
}

// ------------------------------------------------------------- one file

/// What one file has to say about a pattern, or nothing at all.
fn searched(ctx: Ctx, vm: *regex.Vm, path: []const u8) ![]const u8 {
    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch return "";
    // A binary file has nothing a line-oriented search can say about it.
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return "";
    return report(ctx.arena, vm, path, bytes);
}

/// The same line a search prints above its matches, and nothing under it.
fn listed(ctx: Ctx, path: []const u8) ![]const u8 {
    const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch {
        // Too large to hold, so all that can be said is that it is there.
        const stat = Dir.cwd().statFile(ctx.io, path, .{}) catch return "";
        return named(ctx.arena, path, null, stat.size);
    };
    return named(ctx.arena, path, bytes, bytes.len);
}

/// One file's line. A file that isn't text, or was too large to hold, is
/// named with the one thing that can be said about it without reading it —
/// pages are a thing text has, and claiming them for a binary would be a lie.
fn named(arena: Allocator, path: []const u8, held: ?[]const u8, len: u64) ![]const u8 {
    const bytes = held orelse return std.fmt.allocPrint(arena, "{s} ({s})\n", .{
        path,
        try size(arena, len),
    });
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return std.fmt.allocPrint(
        arena,
        "{s} ({s})\n",
        .{ path, try size(arena, len) },
    );

    const pages = try read.paginate(arena, bytes);
    return std.fmt.allocPrint(arena, "{s} ({s}, {d} lines, 1-{d} pages)\n", .{
        path,
        try size(arena, len),
        pages[pages.len - 1].last_line,
        pages.len,
    });
}

// ---------------------------------------------------------------- answering

const Hit = struct {
    /// Which line, as the file numbers them.
    no: usize,
    page: usize,
    text: []const u8,
    /// The page edge ran through this line, on one side or the other.
    opens: bool,
    ends: bool,
};

/// What one file has to say, or nothing at all.
fn report(arena: Allocator, vm: *regex.Vm, path: []const u8, bytes: []const u8) ![]const u8 {
    const pages = try read.paginate(arena, bytes);

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
        for (near) |h| try out.print(arena, "    {d}:{s}{s}{s}\n", .{
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
fn arg(ctx: Ctx, key: []const u8) ?[]const u8 {
    const raw = ctx.env.get(key) orelse return null;
    return if (raw.len == 0) null else raw;
}

fn number(ctx: Ctx, key: []const u8) ?usize {
    const raw = ctx.env.get(key) orelse return null;
    return std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \t"), 10) catch null;
}

fn deny(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("[DENIED: " ++ fmt ++ "]\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 call munge scan — search files for a pattern, answered in pages
        \\
        \\An inbuilt tool, so it is reached through `call` and never typed as a
        \\command of its own. What the call said arrives as M8_ARG_*.
        \\
        \\  regex   a pattern, matched within one line at a time
        \\  glob    which files, with ** and * and ? and {a,b}
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
        \\Answers name each file's size and page count, then the matches in runs
        \\of neighbouring pages — which is what `read` and `write` take.
        \\
        \\  BYTE_CAP  bytes per answer, dropping whole files  (default 16000)
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
    const said = try report(arena, &vm, "demo.txt", body.items);

    try testing.expect(std.mem.indexOf(u8, said, "has 3 matches:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "* 2 matches on pages 1-1 in lines:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "* 1 match on pages 3-3 in lines:") != null);
    try testing.expect(std.mem.indexOf(u8, said, "    5:line 5 MARKER") != null);
    try testing.expect(std.mem.indexOf(u8, said, "    250:line 250 MARKER") != null);
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
    const said = try report(arena, &vm, "long.txt", body);

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
        try named(arena, "demo.txt", body.items, body.items.len),
    );

    // A binary file is named, not paginated.
    try testing.expectEqualStrings(
        "blob.bin (4B)\n",
        try named(arena, "blob.bin", "a\x00bc", 4),
    );

    // Nor is one too large to have been held.
    try testing.expectEqualStrings(
        "huge.bin (23MB)\n",
        try named(arena, "huge.bin", null, 23 * 1024 * 1024),
    );
}
