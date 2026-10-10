//! `shield ask` — put the command to the person.
//!
//! It asks the way any tool does: by stopping with the question, and being
//! run again once it is answered. So it needs no terminal, and whoever
//! answers the conversation is who it asked.

const std = @import("std");
const api = @import("../api.zig");
const wrapping = @import("wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ask",
    .summary = "ask the person before running it",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);

    // Who it stands as, which is who it asks as and where its answer is.
    const who = try std.fmt.allocPrint(ctx.arena, "{s}{s}", .{
        api.asks_shield, if (w.head.len > 0) w.head[0] else "ask-1",
    });

    // Run by hand there is nothing handed in, which is a question nobody has
    // answered yet like any other.
    const handed = ctx.env.get(api.params_var) orelse "";
    const said = if (handed.len == 0) null else std.Io.Dir.cwd().readFileAlloc(
        ctx.io,
        try std.fmt.allocPrint(ctx.arena, "{s}/{s}/{s}1", .{ handed, who, api.exclamation }),
        ctx.arena,
        .limited(64 * 1024),
    ) catch null;

    const answer = std.mem.trim(u8, said orelse {
        try ctx.err.print("{s}{s}: run this? [yes/no]\n{s}\n", .{
            api.ask_lead, who, try std.mem.join(ctx.arena, " ", w.argv),
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
        \\m8 shield ask — ask the person before running it
        \\
        \\  m8 shield ask [NAME] -- CMD [ARGS]
        \\
        \\NAME is who it asks as, which a shield definition says with
        \\{{SHIELD}}. Without one it is ask-1.
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
