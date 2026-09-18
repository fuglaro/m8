//! `shield ask` — put the command to the person.
//!
//! One of the two that could not be written in the shell: this one needs the
//! person. Nobody to ask is a no — a pipe or a cron job must not be a way of
//! skipping the question.

const std = @import("std");
const api = @import("../api.zig");
const wrapping = @import("wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ask",
    .summary = "ask whoever is at the terminal before running it",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);

    const t = ctx.tty orelse {
        try ctx.err.writeAll("m8 shield ask: 'ask' is in force and there is no terminal\n");
        return wrapping.Error.Refused;
    };
    try t.prompt("run: {s} ? [y/N] ", .{try std.mem.join(ctx.arena, " ", w.argv)});
    const line = (try t.line()) orelse return wrapping.Error.Refused;
    const answer = std.mem.trim(u8, line, " \t");
    if (!std.mem.eql(u8, answer, "y") and !std.mem.eql(u8, answer, "Y"))
        return wrapping.Error.Refused;
    return wrapping.through(ctx, w.argv, null);
}

fn page(ctx: Ctx, out: *std.Io.Writer) !void {
    _ = ctx;
    try out.writeAll(
        \\m8 shield ask — ask whoever is at the terminal before running it
        \\
        \\  m8 shield ask -- CMD [ARGS]
        \\
        \\Anything but `y` is no, and so is a terminal that is not there: a
        \\pipe or a cron job is not a way of skipping the question.
        \\
    );
}
