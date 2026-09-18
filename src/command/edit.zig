//! `edit` — change files by first saying what is already there.
//!
//! Every change carries an assertion, and the assertion is spelled the way
//! `view` spells it. That is the whole mechanism: a line number means nothing
//! on its own, but a line number with the line beside it is a claim that can
//! be checked, so an edit built on a stale picture of a file is refused rather
//! than applied to whatever happens to be at that number now.
//!
//! A denial is not a view. It says the picture is stale, and the answer to it
//! is to look again — never to patch the fragment the denial happened to show.

const std = @import("std");
const api = @import("api.zig");
const Ctx = api.Ctx;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

pub const command: api.Command = .{
    .name = "edit",
    .summary = "change files, asserting what is there first",
    .takes = .nothing,
    .run = run,
    .help = help,
};

const max_file = 16 * 1024 * 1024;

const Op = union(enum) {
    /// `=123|LINE` — line 123 is `LINE`, and an insert may anchor after it.
    assert: Line,
    /// `-123|LINE` — line 123 is `LINE`, and goes.
    remove: Line,
    /// `|LINE` — after whatever the last `=` or `-` named.
    insert: struct { anchor: usize, text: []const u8 },
    /// `*6|STRING` and the `:` lines under it.
    subst: struct { count: usize, search: []const u8, replace: []const u8 },
};

const Line = struct { at: usize, text: []const u8 };

/// The edits for one file. Contexts are independent, so the same file named
/// twice is one of these, and the order they were written in does not matter.
const Target = struct {
    path: []const u8,
    ops: std.ArrayList(Op) = .empty,
};

fn run(ctx: Ctx) !u8 {
    const base = ctx.env.get("M8_ARG_PATH") orelse
        (if (ctx.args.len > 0) ctx.args[0] else null) orelse
        return refuse(ctx, "no path given", .{});
    const changes = ctx.env.get("M8_ARG_CHANGES") orelse
        (if (ctx.args.len > 1) ctx.args[1] else null) orelse
        return refuse(ctx, "no changes given", .{});

    var targets: std.ArrayList(Target) = .empty;
    var denials: std.ArrayList([]const u8) = .empty;

    try parse(ctx, base, changes, &targets, &denials);

    // Everything is checked before anything is written, so a call either
    // happens or does not. A half-applied edit would leave a file that
    // matches nobody's picture of it.
    var written: std.ArrayList(Written) = .empty;
    for (targets.items) |*t| try plan(ctx, t, &written, &denials);

    if (denials.items.len > 0) {
        for (denials.items) |d| try ctx.err.print("Denied - {s}\n", .{d});
        try ctx.err.flush();
        return 1;
    }

    for (written.items) |w| {
        if (std.fs.path.dirname(w.path)) |parent|
            Dir.cwd().createDirPath(ctx.io, parent) catch {};
        Dir.cwd().writeFile(ctx.io, .{ .sub_path = w.path, .data = w.bytes }) catch
            return refuse(ctx, "cannot write {s}", .{w.path});
        try ctx.out.print("{s}\n", .{w.path});
    }
    try ctx.out.flush();
    return 0;
}

const Written = struct { path: []const u8, bytes: []const u8 };

// ------------------------------------------------------------------ parse

fn parse(
    ctx: Ctx,
    base: []const u8,
    changes: []const u8,
    targets: *std.ArrayList(Target),
    denials: *std.ArrayList([]const u8),
) !void {
    const arena = ctx.arena;
    var current: usize = try reach(arena, targets, base);
    var anchor: ?usize = null;
    var subst: ?usize = null; // which op the `:` lines are still filling
    var subst_lines: usize = 0; // how many have landed, so the first is not joined

    var it = std.mem.splitScalar(u8, changes, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;

        // A `:` only ever continues the substitution above it, so it is asked
        // about before anything else could claim the line.
        if (line[0] == ':') {
            const which = subst orelse {
                try deny(arena, denials, "a `:` line with no substitution above it", .{});
                continue;
            };
            const op = &targets.items[current].ops.items[which];
            // Lines join with a newline, and the first one is the whole of it
            // — an empty `:` is a substitution to an empty line, not to none.
            op.subst.replace = if (subst_lines == 0)
                line[1..]
            else
                try std.fmt.allocPrint(arena, "{s}\n{s}", .{ op.subst.replace, line[1..] });
            subst_lines += 1;
            continue;
        }
        subst = null;

        switch (line[0]) {
            '/' => {
                current = try reach(arena, targets, try std.fs.path.join(arena, &.{ base, line[1..] }));
                anchor = null;
            },
            '=' , '-' => {
                const cut = std.mem.indexOfScalar(u8, line, '|') orelse {
                    try deny(arena, denials, "`{s}` has no |", .{line});
                    continue;
                };
                const at = std.fmt.parseInt(usize, line[1..cut], 10) catch {
                    try deny(arena, denials, "`{s}` does not name a line", .{line});
                    continue;
                };
                const one: Line = .{ .at = at, .text = line[cut + 1 ..] };
                try targets.items[current].ops.append(arena, if (line[0] == '=')
                    .{ .assert = one }
                else
                    .{ .remove = one });
                anchor = at;
            },
            '|' => {
                const at = anchor orelse {
                    try deny(arena, denials, "`{s}` has nothing to anchor to", .{line});
                    continue;
                };
                try targets.items[current].ops.append(arena, .{
                    .insert = .{ .anchor = at, .text = line[1..] },
                });
            },
            '*' => {
                const cut = std.mem.indexOfScalar(u8, line, '|') orelse {
                    try deny(arena, denials, "`{s}` has no |", .{line});
                    continue;
                };
                const count = std.fmt.parseInt(usize, line[1..cut], 10) catch {
                    try deny(arena, denials, "`{s}` does not name a count", .{line});
                    continue;
                };
                subst = targets.items[current].ops.items.len;
                subst_lines = 0;
                try targets.items[current].ops.append(arena, .{
                    .subst = .{ .count = count, .search = line[cut + 1 ..], .replace = "" },
                });
            },
            else => try deny(arena, denials, "`{s}` is not a change", .{line}),
        }
    }
}

/// The target for a path, made if this is the first mention of it.
fn reach(arena: Allocator, targets: *std.ArrayList(Target), path: []const u8) !usize {
    for (targets.items, 0..) |t, i| if (std.mem.eql(u8, t.path, path)) return i;
    try targets.append(arena, .{ .path = path });
    return targets.items.len - 1;
}

// --------------------------------------------------------------- checking

/// Check one file's edits and work out what it would become.
///
/// Nothing is written here. Every assertion in the whole call has to hold
/// before any file is touched, so this only ever adds to what would be written
/// or to what was refused.
fn plan(ctx: Ctx, t: *Target, written: *std.ArrayList(Written), denials: *std.ArrayList([]const u8)) !void {
    const arena = ctx.arena;
    if (t.ops.items.len == 0) return;

    // A file that is not there yet is an empty one. Splitting "" gives a
    // single empty line, so `=0|` then an insert leaves a file that ends the
    // way a text file ends.
    const bytes = Dir.cwd().readFileAlloc(ctx.io, t.path, arena, .limited(max_file)) catch "";

    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |l| try lines.append(arena, l);
    const n = lines.items.len;

    const touched_by_subst = try arena.alloc(bool, n);
    const touched_by_line = try arena.alloc(bool, n);
    const removed = try arena.alloc(bool, n);
    @memset(touched_by_subst, false);
    @memset(touched_by_line, false);
    @memset(removed, false);

    var ok = true;

    for (t.ops.items) |op| switch (op) {
        // `=0|` names the start of the file rather than a line, so it asserts
        // nothing and only anchors what comes after it.
        .assert => |one| {
            if (one.at == 0) {
                if (one.text.len > 0) {
                    try deny(arena, denials, "there is no line 0 to hold `{s}`", .{one.text});
                    ok = false;
                }
                continue;
            }
            if (!holds(arena, denials, t.path, lines.items, one)) ok = false else touched_by_line[one.at - 1] = true;
        },
        .remove => |one| {
            if (one.at == 0 or !holds(arena, denials, t.path, lines.items, one)) {
                if (one.at == 0) try deny(arena, denials, "there is no line 0 to remove", .{});
                ok = false;
                continue;
            }
            touched_by_line[one.at - 1] = true;
            removed[one.at - 1] = true;
        },
        .insert => |ins| {
            if (ins.anchor > n) {
                try deny(arena, denials, "{s} has no line {d}", .{ t.path, ins.anchor });
                ok = false;
                continue;
            }
            if (ins.anchor > 0) touched_by_line[ins.anchor - 1] = true;
        },
        .subst => |s| {
            var found: usize = 0;
            for (lines.items, 0..) |l, i| {
                const here = occurrences(l, s.search);
                if (here == 0) continue;
                found += here;
                touched_by_subst[i] = true;
            }
            if (found != s.count) {
                try deny(arena, denials, "{d} occurrences of `{s}`", .{ found, s.search });
                ok = false;
            }
        },
    };

    for (0..n) |i| if (touched_by_subst[i] and touched_by_line[i]) {
        try deny(arena, denials, "line {d} is both substituted and edited", .{i + 1});
        ok = false;
    };

    if (!ok) return;

    // Substitutions first, then what the line numbers said — which still
    // refer to the file as it was, because a substitution never moves a line
    // it did not touch and never touches a line an edit did.
    var out: std.ArrayList([]const u8) = .empty;
    try inserts(arena, &out, t.ops.items, 0);
    for (lines.items, 0..) |l, i| {
        if (!removed[i]) {
            var text = l;
            if (touched_by_subst[i]) for (t.ops.items) |op| switch (op) {
                .subst => |s| text = try replaceAll(arena, text, s.search, s.replace),
                else => {},
            };
            try out.append(arena, text);
        }
        try inserts(arena, &out, t.ops.items, i + 1);
    }

    try written.append(arena, .{
        .path = t.path,
        .bytes = try std.mem.join(arena, "\n", out.items),
    });
}

/// Whether a line is what it was said to be, saying so when it is not.
fn holds(arena: Allocator, denials: *std.ArrayList([]const u8), path: []const u8, lines: []const []const u8, one: Line) bool {
    if (one.at > lines.len) {
        deny(arena, denials, "{s} has no line {d}", .{ path, one.at }) catch {};
        return false;
    }
    const have = lines[one.at - 1];
    if (!std.mem.eql(u8, have, one.text)) {
        deny(arena, denials, "line {d} is `{s}`", .{ one.at, have }) catch {};
        return false;
    }
    return true;
}

/// The inserts anchored at one line, in the order they were written.
fn inserts(arena: Allocator, out: *std.ArrayList([]const u8), ops: []const Op, at: usize) !void {
    for (ops) |op| switch (op) {
        .insert => |ins| if (ins.anchor == at) try out.append(arena, ins.text),
        else => {},
    };
}

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

fn replaceAll(arena: Allocator, in: []const u8, needle: []const u8, with: []const u8) ![]const u8 {
    if (needle.len == 0) return in;
    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, in, at, needle)) |i| {
        try out.appendSlice(arena, in[at..i]);
        try out.appendSlice(arena, with);
        at = i + needle.len;
    }
    try out.appendSlice(arena, in[at..]);
    return out.items;
}

fn deny(arena: Allocator, denials: *std.ArrayList([]const u8), comptime fmt: []const u8, args: anytype) !void {
    try denials.append(arena, try std.fmt.allocPrint(arena, fmt, args));
}

fn refuse(ctx: Ctx, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.err.print("Denied - " ++ fmt ++ "\n", args);
    try ctx.err.flush();
    return 1;
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 call edline edit — change files, asserting what is there first
        \\
        \\An inbuilt tool, so it is reached through `call` and never typed as a
        \\command of its own. It is scoped under `edline` beside `view`, whose
        \\lines are what an assertion here is written in. What the call said
        \\arrives as M8_ARG_*.
        \\
        \\  path     a file, or a directory the contexts are relative to
        \\  changes  the lines below, one change each
        \\
        \\  /subpath      the file the lines under it apply to
        \\  *6|STRING     replace every occurrence, six of them in this file
        \\  :TEXT         what it becomes, a line each
        \\  =123|LINE     line 123 is LINE, and anchors an insert after it
        \\  -123|LINE     line 123 is LINE, and goes
        \\  |LINE         inserted after the last = or -
        \\
        \\Line numbers are of the file before any change, and are what `view`
        \\gave. Everything is checked before anything is written, so the call
        \\either happens or does not.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        const dir = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
        Dir.cwd().deleteTree(io, dir) catch {};
        try Dir.cwd().createDirPath(io, dir);
        return .{ .io = io, .dir = dir };
    }

    fn file(f: Fixture, gpa: Allocator, name: []const u8, body: []const u8) ![]const u8 {
        const path = try std.fs.path.join(gpa, &.{ f.dir, name });
        if (std.fs.path.dirname(path)) |d| try Dir.cwd().createDirPath(f.io, d);
        try Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = body });
        return path;
    }

    fn read(f: Fixture, gpa: Allocator, path: []const u8) ![]const u8 {
        return Dir.cwd().readFileAlloc(f.io, path, gpa, .limited(max_file));
    }

    fn deinit(f: Fixture) void {
        Dir.cwd().deleteTree(f.io, f.dir) catch {};
    }
};

const Attempt = struct { code: u8, denied: []const u8 };

fn edited(arena: Allocator, io: std.Io, path: []const u8, changes: []const u8) !Attempt {
    var env: std.process.Environ.Map = .init(arena);
    try env.put("M8_ARG_PATH", path);
    try env.put("M8_ARG_CHANGES", changes);
    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    const code = try run(.{
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
    return .{ .code = code, .denied = err.written() };
}

test "an assertion that does not hold denies, and nothing is written" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-stale");
    defer f.deinit();
    const p = try f.file(arena, "one.txt", "alpha\nbeta\n");

    // What is there is reported, and what was expected is not: the edit said
    // that already. A denial is a rejection, not a view to work from.
    const said = try edited(arena, f.io, p, "-1|gamma");
    try testing.expectEqual(@as(u8, 1), said.code);
    try testing.expectEqualStrings("Denied - line 1 is `alpha`\n", said.denied);
    try testing.expectEqualStrings("alpha\nbeta\n", try f.read(arena, p));

    // One assertion failing takes the whole call with it, however much of it
    // would have held on its own.
    const both = try edited(arena, f.io, p, "-1|alpha\n-2|gamma");
    try testing.expectEqual(@as(u8, 1), both.code);
    try testing.expectEqualStrings("alpha\nbeta\n", try f.read(arena, p));
}

test "a substitution replaces every occurrence, and the count is of this file" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-subst");
    defer f.deinit();
    const p = try f.file(arena, "one.txt", "getUser\nx getUser y getUser\n");

    // Three of them, counted the way a view grep counts: within lines, and
    // more than once on a line when that is where they are.
    const wrong = try edited(arena, f.io, p, "*2|getUser\n:setUser");
    try testing.expectEqual(@as(u8, 1), wrong.code);
    try testing.expectEqualStrings("Denied - 3 occurrences of `getUser`\n", wrong.denied);

    const right = try edited(arena, f.io, p, "*3|getUser\n:setUser");
    try testing.expectEqual(@as(u8, 0), right.code);
    try testing.expectEqualStrings("setUser\nx setUser y setUser\n", try f.read(arena, p));

    // The search is one line and the substitution is any number of them.
    _ = try edited(arena, f.io, p, "*1|x setUser\n:one\n:two");
    try testing.expectEqualStrings("setUser\none\ntwo y setUser\n", try f.read(arena, p));
}

test "a line goes by being removed, and what follows it is anchored after it" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-lines");
    defer f.deinit();
    const p = try f.file(arena, "one.txt", "alpha\nbeta\ngamma\n");

    // `=0|` is the start of the file, a `-` with inserts under it is how a
    // line is replaced, and appending anchors to the last content line so the
    // newline the file ends with stays where it is.
    const said = try edited(arena, f.io, p,
        \\=0|
        \\|first
        \\-2|beta
        \\|BETA one
        \\|BETA two
        \\=3|gamma
        \\|last
    );
    try testing.expectEqual(@as(u8, 0), said.code);
    try testing.expectEqualStrings(
        "first\nalpha\nBETA one\nBETA two\ngamma\nlast\n",
        try f.read(arena, p),
    );
}

test "a file that is not there yet is written, parents and all" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-new");
    defer f.deinit();
    const p = try std.fs.path.join(arena, &.{ f.dir, "made/up/new.txt" });

    const said = try edited(arena, f.io, p, "=0|\n|hello\n|world");
    try testing.expectEqual(@as(u8, 0), said.code);
    try testing.expectEqualStrings("hello\nworld\n", try f.read(arena, p));
}

test "a substitution and a line edit may not meet on one line" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-clash");
    defer f.deinit();
    const p = try f.file(arena, "one.txt", "alpha\nbeta\n");

    // Where a line would be both rewritten and anchored to, neither happens.
    // Which one won would be a rule nobody could read off the page.
    const said = try edited(arena, f.io, p, "*1|alpha\n:ALPHA\n=1|alpha\n|after");
    try testing.expectEqual(@as(u8, 1), said.code);
    try testing.expectEqualStrings("Denied - line 1 is both substituted and edited\n", said.denied);
    try testing.expectEqualStrings("alpha\nbeta\n", try f.read(arena, p));
}

test "contexts are independent, and reach across files" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-edit-contexts");
    defer f.deinit();
    const one = try f.file(arena, "one.txt", "getUser\n");
    const two = try f.file(arena, "sub/two.txt", "getUser and getUser\n");

    // A change reaching across files is a context each, carrying the count
    // that file's own grep gave.
    const said = try edited(arena, f.io, f.dir,
        \\/one.txt
        \\*1|getUser
        \\:setUser
        \\/sub/two.txt
        \\*2|getUser
        \\:setUser
    );
    try testing.expectEqual(@as(u8, 0), said.code);
    try testing.expectEqualStrings("setUser\n", try f.read(arena, one));
    try testing.expectEqualStrings("setUser and setUser\n", try f.read(arena, two));

    // And one of them failing leaves both alone.
    const half = try edited(arena, f.io, f.dir,
        \\/one.txt
        \\*1|setUser
        \\:x
        \\/sub/two.txt
        \\*9|setUser
        \\:x
    );
    try testing.expectEqual(@as(u8, 1), half.code);
    try testing.expectEqualStrings("setUser\n", try f.read(arena, one));
}
