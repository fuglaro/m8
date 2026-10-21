const std = @import("std");
const api = @import("../api.zig");
const config = @import("../config.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "register",
    .summary = "trust existing config directories",
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 register [-l]
        \\
        \\Registers existing .m8-st8 directories from the current directory
        \\upward. Registration applies to the canonical directory path.
        \\-l lists candidates and marks those already registered without
        \\changing the registry.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    const list_only = ctx.args.len == 1 and std.mem.eql(u8, ctx.args[0], "-l");
    if (ctx.args.len > 1 or (ctx.args.len == 1 and !list_only)) {
        try ctx.err.writeAll("m8 register: use -l to list candidates\n");
        return 1;
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.process.currentPath(ctx.io, &buf);
    const candidates = try config.candidates(ctx.arena, ctx.io, buf[0..len]);
    for (candidates) |path| {
        const was_registered = try config.registered(ctx.arena, ctx.io, ctx.env, path);
        if (list_only) {
            try ctx.out.print("{s}{s}\n", .{ path, if (was_registered) " [registered]" else "" });
        } else if (!was_registered) {
            try config.registerPath(ctx.arena, ctx.io, ctx.env, path);
            try ctx.out.print("registered {s}\n", .{path});
        }
    }
    return 0;
}
