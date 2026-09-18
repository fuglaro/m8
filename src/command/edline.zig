//! `edline` — looking at a file and changing it, in one language.
//!
//! Two tools that only mean anything beside each other. What `view` answers
//! with is what `edit` takes: a file line is `=123|LINE` in both, a grep names
//! a file the way an edit context names it, and a count of what matched is the
//! line an edit asserts against. Neither half is much use alone — a view whose
//! numbers nothing checks, or an edit against lines nobody read — so they are
//! reached under one name rather than sitting loose beside `ask`.
//!
//!   view  the lines of a file, or the content of a directory
//!   edit  change files, asserting what is there first
//!
//! The subcommands are the `Command` values the two modules already declare,
//! so what is listed here, what is dispatched to, and what `help` prints are
//! one table rather than three.

const std = @import("std");
const api = @import("api.zig");
const launch = @import("../launch.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "edline",
    .summary = "look at files and change them, in one language",
    // Both are spawned with nothing on stdin. There is no document here.
    .takes = .nothing,
    .run = run,
    .help = help,
};

pub const subs = [_]api.Command{
    @import("view.zig").command,
    @import("edit.zig").command,
};

pub fn find(name: []const u8) ?api.Command {
    for (subs) |s| if (std.mem.eql(u8, s.name, name)) return s;
    return null;
}

fn run(ctx: Ctx) !u8 {
    // Naming neither is somebody finding out what is here, which is a page
    // they asked for rather than a mistake.
    if (ctx.args.len == 0) {
        try help(ctx, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    const which = ctx.args[0];
    if (launch.split) {
        const node = @import("../command.zig").byPath(&.{ "call", command.name, which }) orelse {
            try ctx.err.print("m8 call edline: no tool named '{s}'\n", .{which});
            try help(ctx, ctx.err);
            try ctx.err.flush();
            return 1;
        };
        return launch.under(ctx, .{ .spawn = node.program }, ctx.args[1..], .inherited);
    }

    const sub = find(which) orelse {
        try ctx.err.print("m8 call edline: no tool named '{s}'\n", .{which});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    var inner = ctx;
    inner.args = ctx.args[1..];

    // The flag is m8's wherever it is written. `call` answered it for the
    // name it saw, which was this one; the word after a subcommand is ours.
    if (api.wantsHelp(inner.args)) {
        inner.args = inner.args[1..];
        try @import("help.zig").write(inner, sub, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    return sub.run(inner);
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    // Whatever is left names one of them: `m8 help edline view` and
    // `m8 call edline view --help` are the same page.
    if (ctx.args.len > 0) {
        if (find(ctx.args[0])) |s| {
            var inner = ctx;
            inner.args = ctx.args[1..];
            return @import("help.zig").write(inner, s, w);
        }
    }
    try w.writeAll(
        \\m8 call edline — look at files and change them, in one language
        \\
        \\  m8 call edline TOOL [ARGS]   one of the two below
        \\  m8 call edline TOOL --help   what that one takes
        \\
    );
    try w.writeAll("\ntools:\n\n");
    for (subs) |s| try w.print("  {s: <8} {s}\n", .{ s.name, s.summary });
    try w.writeAll(
        \\
        \\Inbuilt tools, so they are reached through `call` and never typed as
        \\commands of their own. What a call said arrives as M8_ARG_*.
        \\
        \\They are one language. A file line is `=123|LINE` wherever it is
        \\written, so an edit asserts in the spelling a view just gave, and a
        \\denial means that picture is stale — look again rather than patch the
        \\fragment the denial happened to show.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the tools are reached under edline and nowhere else" {
    const cmd = @import("../command.zig");

    try testing.expect(find("view") != null);
    try testing.expect(find("edit") != null);
    try testing.expect(find("nosuch") == null);

    // Scoped: the pair is one name to `call`, and neither half is loose
    // beside it.
    try testing.expect(cmd.findCallable("edline") != null);
    try testing.expect(cmd.findCallable("view") == null);
    try testing.expect(cmd.findCallable("edit") == null);
    try testing.expect(cmd.find("view") == null);
    try testing.expect(cmd.find("edit") == null);
}

test "every tool under edline has a name, a summary and a page" {
    for (subs) |s| {
        try testing.expect(s.name.len > 0);
        try testing.expect(s.summary.len > 0);
        try testing.expect(s.help != null);
        // Reached through `call`, which hands a tool nothing on stdin.
        try testing.expect(s.takes == .nothing);
    }
}

test "naming neither lists both, and naming one is that one's page" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var env: std.process.Environ.Map = .init(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    const ctx: Ctx = .{
        .arena = arena,
        .io = threaded.io(),
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &err.writer,
        .tty = null,
    };

    try testing.expectEqual(@as(u8, 0), try run(ctx));
    for (subs) |s| try testing.expect(std.mem.indexOf(u8, out.written(), s.name) != null);

    // A page for one of them says which one it is, and says it under `call
    // edline` rather than as a command of its own.
    for (subs) |s| {
        var one: std.Io.Writer.Allocating = .init(arena);
        var asked = ctx;
        asked.args = &.{s.name};
        try help(asked, &one.writer);
        const said = one.written();
        try testing.expect(std.mem.startsWith(u8, said, "m8 call edline "));
        try testing.expect(std.mem.indexOf(u8, said, s.name) != null);
    }

    // Something that is not one of them is a mistake, and the page it is
    // handed goes to stderr where it cannot become part of a document.
    var missing = ctx;
    missing.args = &.{"nosuch"};
    try testing.expectEqual(@as(u8, 1), try run(missing));
    try testing.expect(std.mem.indexOf(u8, err.written(), "nosuch") != null);
}
