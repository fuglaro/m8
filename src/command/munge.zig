//! `munge` — reading, searching and changing files, all addressed in pages.
//!
//! `munge` makes the coordinate coarse and lets the strings carry the
//! precision, so a stale picture mostly still lands — a page number that has
//! drifted by a line or two still names the right part of the file.
//!
//! That is what pages buy. A page is stable enough to hand back and forth
//! across edits, cheap enough to scope a search with, and vague enough that
//! nothing is ever asserted against it. Lines and matches live inside a page
//! as the way a model thinks, which is the way it was trained to think, and
//! the page is the frame they are thought in.
//!
//!   read   a file in pages, or the content of a directory
//!   write  change a file by saying what is already in it
//!   scan   search files for a pattern, answered in pages
//!
//! The subcommands are the `Command` values the modules already declare, so
//! what is listed here, what is dispatched to, and what `help` prints are one
//! table rather than three.

const std = @import("std");
const api = @import("api.zig");
const launch = @import("../launch.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "munge",
    .summary = "read, search and change files, addressed in pages",
    // Every tool under here is spawned with nothing on stdin.
    .takes = .nothing,
    .run = run,
    .help = help,
};

pub const subs = [_]api.Command{
    @import("munge/read.zig").command,
    @import("munge/write.zig").command,
    @import("munge/scan.zig").command,
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
            try ctx.err.print("m8 call munge: no tool named '{s}'\n", .{which});
            try help(ctx, ctx.err);
            try ctx.err.flush();
            return 1;
        };
        return launch.under(ctx, .{ .spawn = node.program }, ctx.args[1..], .inherited);
    }

    const sub = find(which) orelse {
        try ctx.err.print("m8 call munge: no tool named '{s}'\n", .{which});
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
    // Whatever is left names one of them: `m8 help munge read` and
    // `m8 call munge read --help` are the same page.
    if (ctx.args.len > 0) {
        if (find(ctx.args[0])) |s| {
            var inner = ctx;
            inner.args = ctx.args[1..];
            return @import("help.zig").write(inner, s, w);
        }
    }
    try w.writeAll(
        \\m8 call munge — files, addressed in pages
        \\
        \\  m8 call munge TOOL [ARGS]   one of the tools below
        \\  m8 call munge TOOL --help   what that one takes
        \\
    );
    try w.writeAll("\ntools:\n\n");
    for (subs) |s| try w.print("  {s: <8} {s}\n", .{ s.name, s.summary });
    try w.writeAll(
        \\
        \\Inbuilt tools, so they are reached through `call` and never typed as
        \\commands of their own. What a call said arrives as M8_ARG_*.
        \\
        \\A page is about 100 lines, or 10000 characters where lines are long,
        \\and it is what every answer here is addressed in. Nothing is ever
        \\asserted against a page: it says which part of a file is being talked
        \\about, and the strings read out of it carry the precision.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the tools are reached under munge and nowhere else" {
    const cmd = @import("../command.zig");

    try testing.expect(find("read") != null);
    try testing.expect(find("write") != null);
    try testing.expect(find("scan") != null);
    try testing.expect(find("nosuch") == null);

    // Scoped: `munge` is one name to `call`, and no tool of it is loose
    // beside it.
    try testing.expect(cmd.findCallable("munge") != null);
    try testing.expect(cmd.findCallable("read") == null);
    try testing.expect(cmd.find("read") == null);
}

test "every tool under munge has a name, a summary and a page" {
    for (subs) |s| {
        try testing.expect(s.name.len > 0);
        try testing.expect(s.summary.len > 0);
        try testing.expect(s.help != null);
        try testing.expect(s.takes == .nothing);
    }
}
