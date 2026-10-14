//! `ask-shield` — put the command to the person.
//!
//! It asks the way any tool does: by stopping with the question, and being
//! run again once it is answered. So it needs no terminal, and whoever
//! answers the conversation is who it asked.

const std = @import("std");
const api = @import("../api.zig");
const wrapping = @import("shield/wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ask-shield",
    .summary = "ask the person before running it",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);

    // Who it stands as, which is who it asks as and what its answer is
    // called. Run by hand there is no answer, which is a question nobody has
    // answered yet like any other.
    const said = ctx.env.get(try std.fmt.allocPrint(ctx.arena, "{s}1_{s}", .{ api.exclamation, w.name }));

    const answer = std.mem.trim(u8, said orelse {
        try ctx.err.print("{s}{s}{s}: run this? [yes/no]\n{s}\n", .{
            api.ask_lead, api.asks_shield, w.name, try std.mem.join(ctx.arena, " ", w.argv),
        });
        return api.ask_exit;
    }, " \t\r\n");

    // The same status as asking, and no question: the person is who decides
    // what happens instead, so the conversation goes back to them.
    if (!std.ascii.eqlIgnoreCase(answer, "y") and !std.ascii.eqlIgnoreCase(answer, "yes")) {
        try ctx.err.writeAll("The person said no to running this, and is being asked what to do instead.\n");
        return api.ask_exit;
    }

    return wrapping.through(ctx, w.argv, null);
}

fn page(ctx: Ctx, out: *std.Io.Writer) !void {
    _ = ctx;
    try out.writeAll(
        \\  m8 ask-shield NAME CMD [ARGS]
        \\
        \\NAME is who it asks as, which is the shield's own name: every
        \\shield is handed its name before the command it wraps.
        \\
        \\It stops with the command as a question, which the run that made
        \\the call puts to the person as a ❓. What they say next is the
        \\answer, and the call is run again with it.
        \\
        \\`y` or `yes` runs the command. Anything else does not, and hands
        \\the conversation back to the person to say what to do instead.
        \\
    );
}
