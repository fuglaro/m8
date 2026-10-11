//! `save` — keep a document as an agent.
//!
//! A turn is kept by `tag` and never rewritten. An agent is authored, so it
//! is overwritten: saving over one is how it is changed from a pipe, the same
//! as writing its file by hand.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const session = @import("../session.zig");
const model = @import("../m8/model.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "save",
    .summary = "keep a document as an agent",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 save — keep a document as an agent
        \\
        \\  m8 save @AGENT
        \\
        \\Writes the document on stdin as @/AGENT.md in the nearest config
        \\directory, over whatever was there, and answers with its 🧠.
        \\
        \\  m8 ref @ | m8 encode m8 | m8 save @notes     a chat, flattened
        \\  echo "#### :brain:/local/tiny" | m8 save @tiny
        \\
        \\An agent is authored, so it is a name of your own: not a turn, not a
        \\model, and not somewhere among another agent's chats.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len != 1 or !address.isAddress(ctx.args[0])) {
        try ctx.err.writeAll("m8 save: name one @AGENT to save as\n");
        return 1;
    }
    const name = std.mem.trim(u8, address.body(ctx.args[0]).?, "/");
    if (name.len == 0 or model.is(address.body(ctx.args[0]).?) or session.isGenerated(name) or
        std.mem.endsWith(u8, name, ":") or std.mem.endsWith(u8, name, "-"))
    {
        try ctx.err.print("m8 save: '{s}' is not a name an agent can have\n", .{ctx.args[0]});
        return 1;
    }

    // Beneath an agent is its chats, so an agent saved there would be one of
    // them as far as any address could tell.
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    var end: usize = 0;
    while (std.mem.indexOfScalarPos(u8, name, end, '/')) |cut| : (end = cut + 1) {
        if (try session.isAgent(ctx.arena, ctx.io, dirs, name[0..cut])) {
            try ctx.err.print("m8 save: '{s}' is an agent, so '{s}' would be one of its chats\n", .{
                name[0..cut], name,
            });
            return 1;
        }
    }

    if (ctx.in.len == 0 or doc.detect(ctx.in) == null) {
        try ctx.err.writeAll("m8 save: pipe in a document to save\n");
        return 1;
    }
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);
    try session.write(ctx.arena, ctx.io, dirs, name, records);
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = name });
    return 0;
}
