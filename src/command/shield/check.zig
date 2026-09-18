//! `shield check` — put the command to an agent.
//!
//! A checker reads text an attacker may have shaped, so it belongs beside
//! `ask` rather than instead of it. It is never more capable than what invoked
//! it, because it runs inside every shield that was already standing there.

const std = @import("std");
const api = @import("../api.zig");
const converse = @import("../../converse.zig");
const wrapping = @import("wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "check",
    .summary = "ask an agent before running it",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);
    if (w.head.len == 0 or w.head[0].len == 0) {
        try ctx.err.writeAll("m8 shield check: name the agent to ask\n");
        return wrapping.Error.NothingToWrap;
    }

    const verdict = converse.check(ctx, w.head[0], w.argv) catch |e| {
        try ctx.err.print("m8 shield check: {s}\n", .{@errorName(e)});
        return wrapping.Error.Refused;
    };
    if (verdict) |why| {
        try ctx.err.print("m8 shield check: {s}\n", .{why});
        return wrapping.Error.Refused;
    }
    return wrapping.through(ctx, w.argv, null);
}

fn page(ctx: Ctx, out: *std.Io.Writer) !void {
    _ = ctx;
    try out.writeAll(
        \\m8 shield check — ask an agent before running it
        \\
        \\  m8 shield check AGENT -- CMD [ARGS]
        \\
        \\The agent answers `allow`, or explains why not. Anything that is
        \\not an allowance is a refusal, including a turn that failed.
        \\
        \\It reads text a model may have shaped, so it stands beside `ask`
        \\rather than instead of it. It is never more capable than whatever
        \\invoked it: it runs inside every shield already standing there.
        \\
    );
}
