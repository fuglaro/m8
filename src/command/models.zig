//! `models` — what each provider says it serves.
//!
//! m8 keeps no list of models and knows no api's way of listing them. An
//! entry in `core/providers.json` may name a `models` command, and what that
//! prints is the list: one name a line. A url, a file and a constant are all
//! the same thing here, which is a command that says some names.
//!
//! What comes out is a 🧠 for each, written the way one is asked for, so a
//! line of it is something to paste. They are headers with nothing between
//! them: a list to read down, which is still a document.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const provider = @import("../provider.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "models",
    .summary = "the models each provider says it serves",
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 models [PROVIDER ...]
        \\
        \\Runs the `models` command of each provider in core/providers.json,
        \\or of the ones named, and writes a 🧠 for every line it prints.
        \\What a command says on stderr is passed on.
        \\
        \\The command is handed the entry as M8_PROVIDER_*, and $M8 names
        \\this m8:
        \\
        \\  "models": ["m8", "toy-provider", "--models"]
        \\  "models": ["printf", "gpt-5.5\\ngpt-6-sol\\n"]
        \\  "models": ["sh", "-c", "\"$M8\" url-provider --get URL | ..."]
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    const entries = try config.providers(ctx.arena, ctx.io, ctx.env);
    const core_dirs = try config.coreDirs(ctx.arena, ctx.io, ctx.env);

    var status: u8 = 0;
    if (ctx.args.len > 0) {
        for (ctx.args) |name| status |= try one(ctx, entries, core_dirs, name);
    } else {
        var it = entries.iterator();
        while (it.next()) |e| status |= try one(ctx, entries, core_dirs, e.key_ptr.*);
    }
    try ctx.out.flush();
    try ctx.err.flush();
    return status;
}

/// One provider's models, and whether its command ran and succeeded. m8 says
/// nothing of its own here: a provider with no command has no models to say,
/// and one whose command failed has said why or chosen not to.
fn one(
    ctx: Ctx,
    entries: std.json.ObjectMap,
    core_dirs: []const []const u8,
    name: []const u8,
) !u8 {
    const p = provider.read(ctx.arena, entries, name) catch return 1;
    const argv = provider.resolve(ctx.arena, ctx.io, ctx.self, core_dirs, p.models orelse return 0) catch return 1;
    const environ = try api.childEnvironment(ctx.arena, ctx, &.{});
    try provider.addEnvironment(ctx.arena, p, environ);

    const r = std.process.run(ctx.arena, ctx.io, .{ .argv = argv, .environ_map = environ }) catch return 1;
    try ctx.err.writeAll(r.stderr);

    var lines = std.mem.splitScalar(u8, r.stdout, '\n');
    while (lines.next()) |line| {
        const model = std.mem.trim(u8, line, " \t\r");
        if (model.len == 0) continue;
        try doc.write(ctx.out, ctx.mode, .{
            .sigil = .agent,
            .value = try std.fmt.allocPrint(ctx.arena, "/{s}/{s}", .{ name, model }),
        });
    }
    return switch (r.term) {
        .exited => |code| @intFromBool(code != 0),
        else => 1,
    };
}
