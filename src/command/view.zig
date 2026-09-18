//! `view` — the lines of a file, or the content of a directory.
//!
//! What this answers with is what `edit` takes. A file line is `=123|LINE`, a
//! grep over a directory names each file the way an edit context names it, and
//! a count of what matched is the same line an edit asserts against. Looking
//! and changing are one language, so nothing is translated between them and a
//! model never has to write down a line it did not just read.

const std = @import("std");
const api = @import("api.zig");
const Ctx = api.Ctx;
const Dir = std.Io.Dir;

pub const command: api.Command = .{
    .name = "view",
    .summary = "list the lines of a file, or the content of a directory",
    // A tool is spawned with nothing on stdin. There is no document here.
    .takes = .nothing,
    .run = run,
    .help = help,
};

const default_limit = 400;
const default_width = 400;
const max_file = 16 * 1024 * 1024;

/// The result, built whole and then windowed. `offset` and `limit` are of the
/// complete answer that would otherwise be given, so they cannot be applied
/// while it is still being found.
const Lines = std.ArrayList([]const u8);

fn run(ctx: Ctx) !u8 {
    const path = ctx.env.get("M8_ARG_PATH") orelse
        (if (ctx.args.len > 0) ctx.args[0] else null) orelse
        return refuse(ctx, "no path given", .{});

    const grep = ctx.env.get("M8_ARG_GREP");
    const find = ctx.env.get("M8_ARG_FIND");
    const offset = number(ctx, "M8_ARG_OFFSET") orelse 0;
    const limit = number(ctx, "M8_ARG_LIMIT") orelse default_limit;
    const width = number(ctx, "M8_ARG_WIDTH") orelse default_width;
    const before = number(ctx, "M8_ARG_BEFORE") orelse 0;
    const after = number(ctx, "M8_ARG_AFTER") orelse 0;

    // A symlink at the path itself is followed: somebody naming it means the
    // thing it points at. Symlinks *within* a traversal are another matter,
    // and are not followed at all.
    const st = Dir.cwd().statFile(ctx.io, path, .{}) catch
        return refuse(ctx, "cannot read {s}", .{path});

    var out: Lines = .empty;
    if (st.kind == .directory) {
        try directory(ctx, &out, path, grep, find, before, after);
    } else {
        const bytes = Dir.cwd().readFileAlloc(ctx.io, path, ctx.arena, .limited(max_file)) catch
            return refuse(ctx, "cannot read {s}", .{path});
        try fileLines(ctx.arena, &out, bytes, grep, before, after);
    }

    return window(ctx, out.items, offset, limit, width);
}

// ------------------------------------------------------------------ files

/// The lines of one file, numbered from 1.
///
/// Splitting on a newline is what makes the end of a file visible: a trailing
/// newline leaves a final empty element, which shows as an empty numbered line
/// and is the only honest way to say a file ends the way it does.
fn fileLines(
    arena: std.mem.Allocator,
    out: *Lines,
    bytes: []const u8,
    grep: ?[]const u8,
    before: usize,
    after: usize,
) !void {
    var lines: Lines = .empty;
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |l| try lines.append(arena, l);

    if (grep) |needle| {
        var wanted = try arena.alloc(bool, lines.items.len);
        @memset(wanted, false);
        for (lines.items, 0..) |l, i| {
            if (needle.len == 0 or std.mem.indexOf(u8, l, needle) == null) continue;
            const from = i -| before;
            const to = @min(lines.items.len - 1, i + after);
            for (from..to + 1) |j| wanted[j] = true;
        }
        for (lines.items, 0..) |l, i| {
            if (!wanted[i]) continue;
            try out.append(arena, try std.fmt.allocPrint(arena, "={d}|{s}", .{ i + 1, l }));
        }
        return;
    }

    for (lines.items, 0..) |l, i|
        try out.append(arena, try std.fmt.allocPrint(arena, "={d}|{s}", .{ i + 1, l }));
}

/// How many times a literal occurs. Non-overlapping, which is what replacing
/// every occurrence will do to it.
fn occurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var n: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, at, needle)) |i| {
        n += 1;
        at = i + needle.len;
    }
    return n;
}

// ------------------------------------------------------------ directories

fn directory(
    ctx: Ctx,
    out: *Lines,
    root: []const u8,
    grep: ?[]const u8,
    find: ?[]const u8,
    before: usize,
    after: usize,
) !void {
    if (grep) |needle| return walk(ctx, out, root, "", .{ .grep = .{ .needle = needle, .before = before, .after = after } });
    if (find) |name| return walk(ctx, out, root, "", .{ .find = name });
    return walk(ctx, out, root, "", .{ .list = {} });
}

const How = union(enum) {
    list,
    grep: struct { needle: []const u8, before: usize, after: usize },
    find: []const u8,
};

fn walk(ctx: Ctx, out: *Lines, root: []const u8, rel: []const u8, how: How) !void {
    const here = if (rel.len == 0) root else try std.fs.path.join(ctx.arena, &.{ root, rel });
    var dir = Dir.cwd().openDir(ctx.io, here, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var names: std.ArrayList(Dir.Entry) = .empty;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |e| try names.append(ctx.arena, .{
        .name = try ctx.arena.dupe(u8, e.name),
        .kind = e.kind,
        .inode = e.inode,
    });
    std.mem.sort(Dir.Entry, names.items, {}, byName);

    for (names.items) |e| {
        const sub = if (rel.len == 0)
            e.name
        else
            try std.fmt.allocPrint(ctx.arena, "{s}/{s}", .{ rel, e.name });

        switch (how) {
            .list => try out.append(ctx.arena, try contentLine(ctx, here, e, e.name)),
            .find => |needle| {
                if (std.mem.indexOf(u8, e.name, needle) != null)
                    try out.append(ctx.arena, try contentLine(ctx, here, e, sub));
                if (traversable(e)) try walk(ctx, out, root, sub, how);
            },
            .grep => |g| {
                if (traversable(e)) {
                    try walk(ctx, out, root, sub, how);
                    continue;
                }
                if (e.kind != .file) continue;
                const full = try std.fs.path.join(ctx.arena, &.{ here, e.name });
                const bytes = Dir.cwd().readFileAlloc(ctx.io, full, ctx.arena, .limited(max_file)) catch continue;
                const n = occurrences(bytes, g.needle);
                if (n == 0) continue;
                // The file names itself the way an edit context names it: the
                // path from what was viewed, and no suffix.
                try out.append(ctx.arena, try std.fmt.allocPrint(ctx.arena, "/{s}", .{sub}));
                try fileLines(ctx.arena, out, bytes, g.needle, g.before, g.after);
                try out.append(ctx.arena, try std.fmt.allocPrint(ctx.arena, "*{d}|{s}", .{ n, g.needle }));
            },
        }
    }
}

/// Whether a traversal goes into this. A dotted directory is somebody's
/// machinery rather than their work, and a symlink is a way to walk the same
/// tree twice or leave it entirely.
fn traversable(e: Dir.Entry) bool {
    return e.kind == .directory and e.name.len > 0 and e.name[0] != '.';
}

fn byName(_: void, a: Dir.Entry, b: Dir.Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

/// One line of directory content: what it is, said in its suffix.
fn contentLine(ctx: Ctx, dir_path: []const u8, e: Dir.Entry, display: []const u8) ![]const u8 {
    const full = try std.fs.path.join(ctx.arena, &.{ dir_path, e.name });
    switch (e.kind) {
        .directory => return std.fmt.allocPrint(ctx.arena, "/{s}/", .{display}),
        .sym_link => {
            var buf: [Dir.max_path_bytes]u8 = undefined;
            const n = Dir.cwd().readLink(ctx.io, full, &buf) catch
                return std.fmt.allocPrint(ctx.arena, "/{s} ->", .{display});
            const dest = buf[0..n];
            const st = Dir.cwd().statFile(ctx.io, full, .{}) catch
                return std.fmt.allocPrint(ctx.arena, "/{s} ->{s}", .{ display, dest });
            if (st.kind == .directory)
                return std.fmt.allocPrint(ctx.arena, "/{s}/ ->{s}", .{ display, dest });
            return std.fmt.allocPrint(ctx.arena, "/{s} ->{s}", .{ display, dest });
        },
        else => {
            const st = Dir.cwd().statFile(ctx.io, full, .{}) catch
                return std.fmt.allocPrint(ctx.arena, "/{s}", .{display});
            return std.fmt.allocPrint(ctx.arena, "/{s} ({d})", .{ display, st.size });
        },
    }
}

// ----------------------------------------------------------------- window

/// What is actually written: the result from `offset`, no more than `limit`
/// lines of it, and nothing wider than `width`.
///
/// A truncation says so where it happened. A line cut short ends in `~~~`, and
/// a result cut short ends in a `~~~` of its own, unnumbered so that it can
/// never be read as a line of the file.
fn window(ctx: Ctx, all: []const []const u8, offset: usize, limit: usize, width: usize) !u8 {
    const from = @min(offset, all.len);
    const shown = all[from..@min(all.len, from + limit)];
    for (shown) |line| {
        if (width > 0 and line.len > width) {
            try ctx.out.writeAll(line[0..width]);
            try ctx.out.writeAll("~~~\n");
        } else {
            try ctx.out.writeAll(line);
            try ctx.out.writeByte('\n');
        }
    }
    if (from + shown.len < all.len) try ctx.out.writeAll("~~~\n");
    try ctx.out.flush();
    return 0;
}

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
        \\m8 call edline view — the lines of a file, or a directory's content
        \\
        \\An inbuilt tool, so it is reached through `call` and never typed as a
        \\command of its own. It is scoped under `edline` beside `edit`, which
        \\is the only other thing that speaks this language. What the call said
        \\arrives as M8_ARG_*; a path may also be given as a word, for trying
        \\it from a shell.
        \\
        \\  path    the file or directory to inspect
        \\  offset  lines into the result to start at
        \\  limit   lines at most, then a final ~~~   (default 400)
        \\  width   columns at most, then ~~~         (default 400)
        \\  grep    a literal, filtering file lines
        \\  before  lines of context before a match
        \\  after   lines of context after a match
        \\  find    a literal, matching names
        \\
        \\A file line is `=123|LINE`, which is what `edit` asserts against. A
        \\grep over a directory names each file the way an edit context names
        \\it, and ends it with `*6|STRING` — the same line an edit substitutes
        \\against.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: std.mem.Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        const dir = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
        Dir.cwd().deleteTree(io, dir) catch {};
        try Dir.cwd().createDirPath(io, dir);
        return .{ .io = io, .dir = dir };
    }

    fn file(f: Fixture, gpa: std.mem.Allocator, name: []const u8, body: []const u8) ![]const u8 {
        const path = try std.fs.path.join(gpa, &.{ f.dir, name });
        if (std.fs.path.dirname(path)) |d| try Dir.cwd().createDirPath(f.io, d);
        try Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = body });
        return path;
    }

    fn deinit(f: Fixture) void {
        Dir.cwd().deleteTree(f.io, f.dir) catch {};
    }
};

/// Run the tool the way a call does: everything in the environment.
fn viewed(arena: std.mem.Allocator, io: std.Io, args: []const [2][]const u8) ![]const u8 {
    var env: std.process.Environ.Map = .init(arena);
    for (args) |kv| try env.put(kv[0], kv[1]);
    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    _ = try run(.{
        .arena = arena,
        .io = io,
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &err.writer,
        .tty = null,
    });
    return out.written();
}

test "a file is its lines, and the newline it ends with is one of them" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-view-lines");
    defer f.deinit();

    const ends = try f.file(arena, "ends.txt", "one\ntwo\n");
    try testing.expectEqualStrings(
        \\=1|one
        \\=2|two
        \\=3|
        \\
    , try viewed(arena, f.io, &.{.{ "M8_ARG_PATH", ends }}));

    // A file that ends without one has no such line, which is the only way to
    // tell the two files apart.
    const bare = try f.file(arena, "bare.txt", "one\ntwo");
    try testing.expectEqualStrings(
        \\=1|one
        \\=2|two
        \\
    , try viewed(arena, f.io, &.{.{ "M8_ARG_PATH", bare }}));
}

test "a grep over a directory answers in the language edit takes" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-view-grep");
    defer f.deinit();
    _ = try f.file(arena, "one.txt", "getUser here\nnothing\ngetUser and getUser\n");
    _ = try f.file(arena, "sub/two.txt", "quiet\n");
    _ = try f.file(arena, ".hidden/three.txt", "getUser\n");

    // The file names itself with no suffix, the way an edit context names it,
    // and the count is of that file alone — the same line an edit asserts.
    // A dotted directory is not walked into.
    try testing.expectEqualStrings(
        \\/one.txt
        \\=1|getUser here
        \\=3|getUser and getUser
        \\*3|getUser
        \\
    , try viewed(arena, f.io, &.{ .{ "M8_ARG_PATH", f.dir }, .{ "M8_ARG_GREP", "getUser" } }));
}

test "a truncation says where it happened" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-view-window");
    defer f.deinit();
    const p = try f.file(arena, "long.txt", "aaaaaaaa\nbbbbbbbb\ncccccccc\n");

    // A line cut short ends in ~~~ where it was cut; a result cut short ends
    // in a ~~~ of its own, unnumbered so it can never read as a file line.
    try testing.expectEqualStrings(
        \\=1|aaa~~~
        \\=2|bbb~~~
        \\~~~
        \\
    , try viewed(arena, f.io, &.{
        .{ "M8_ARG_PATH", p },
        .{ "M8_ARG_LIMIT", "2" },
        .{ "M8_ARG_WIDTH", "6" },
    }));

    // An offset is into the result that would otherwise be given.
    try testing.expectEqualStrings(
        \\=3|cccccccc
        \\=4|
        \\
    , try viewed(arena, f.io, &.{ .{ "M8_ARG_PATH", p }, .{ "M8_ARG_OFFSET", "2" } }));
}
