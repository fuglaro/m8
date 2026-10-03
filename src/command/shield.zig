//! `shield` — the wrappers m8 ships with.
//!
//! A shield is a command that runs a command. These three are the ones that
//! could not be written in the shell: `secure` needs the profile that decides
//! what a restriction means, `ask` needs the person, and `check` needs an
//! agent. Everything else a shield does is a program you already have, which
//! is why `deny` is `/usr/bin/false` and a filter is a pipe.
//!
//! Each takes the command it wraps after `--` and runs it in its own place, so
//! what a tool sees is one process and one exit status however many wrappers
//! it stood inside.
//!
//! They are commands under this one rather than branches within it, which is
//! what keeps `check` — a whole nested agent turn — from being carried by the
//! two that have no use for it.

const std = @import("std");
const api = @import("api.zig");
const launch = @import("../launch.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "shield",
    .summary = "run a command inside one of the wrappers m8 ships with",
    .takes = .nothing,
    .run = run,
    .help = help,
};

pub const subs = [_]api.Command{
    @import("shield/secure.zig").command,
    @import("shield/ask.zig").command,
    @import("shield/check.zig").command,
};

pub fn find(name: []const u8) ?api.Command {
    for (subs) |s| if (std.mem.eql(u8, s.name, name)) return s;
    return null;
}

/// `m8 shield NAME [ARGS] -- CMD...`
fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    const which = ctx.args[0];
    const cmd = @import("../command.zig");
    const node = cmd.byPath(&.{ command.name, which }) orelse {
        try ctx.err.print("m8 shield: no shield named '{s}'\n", .{which});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return @import("shield/wrapping.zig").Error.UnknownShield;
    };

    if (launch.split)
        return launch.under(ctx, .{ .spawn = node.program }, ctx.args[1..], .inherited);

    var inner = ctx;
    inner.args = ctx.args[1..];

    // The flag is m8's wherever it is written. What was named out here was
    // `shield`; the word after a subcommand is ours.
    if (api.wantsHelp(inner.args)) {
        inner.args = inner.args[1..];
        try @import("help.zig").write(inner, find(which).?, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    return find(which).?.run(inner);
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 shield — run a command inside one of the wrappers m8 ships with
        \\
        \\  m8 shield secure "RESTRICTIONS" -- CMD [ARGS]
        \\  m8 shield ask -- CMD [ARGS]
        \\  m8 shield check AGENT -- CMD [ARGS]
        \\
        \\A shield is a command that runs a command, so most of them are
        \\programs you already have and are written in the language rather
        \\than here. These three could not be: `secure` needs the profile
        \\that decides what a restriction means, `ask` needs the person, and
        \\`check` needs an agent.
        \\
    );
    // Read off the tree: saying what m8 ships is not a reason to hold the
    // one of them that is a whole agent turn.
    try w.writeAll("\nshields:\n\n");
    for (@import("../command.zig").byPath(&.{command.name}).?.children) |n|
        try w.print("  {s: <8} {s}\n", .{ n.spec.name, n.spec.summary });
    try w.writeAll("\nm8 shield NAME --help is that one's page.\n");
}
