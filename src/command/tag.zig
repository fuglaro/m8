//! `tag` — keep a turn, and point an address at it.
//!
//! The one command that moves a chat. A document that is one 🧠 already names
//! a turn, so the address is pointed at it and nothing is written; anything
//! else is kept as a new turn and pointed at. Either way what comes out is
//! the 🧠 of the turn now pointed at, and nothing else — it is a ref being
//! written, and the line is its receipt.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "tag",
    .summary = "keep a turn, and point an address at it",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 tag — keep a turn, and point an address at it
        \\
        \\  m8 tag @ADDRESS[:]
        \\
        \\A document that is one 🧠 names a turn already, so the address is
        \\pointed at it and nothing is written. Anything else is kept as a new
        \\turn and pointed at. What comes out is the 🧠 now pointed at.
        \\
        \\  m8 cat @mathy | m8 send | m8 tag @mathy     what m8 @mathy does
        \\  m8 cat @mathy | m8 tag @mathy/aside          fork a chat
        \\  m8 cat @ | m8 send | m8 tag @mathy/other     keep a run elsewhere
        \\
        \\  @chat     the turn goes in the chat's +/, the chat points at it,
        \\            and the main chat points at the chat
        \\  @         the chat the main chat points at, as above; or, when it
        \\            points at a turn, the main chat itself
        \\  @turn     the turn goes beside its parent, and the main chat
        \\  @/model   points at it
        \\
        \\A trailing `:` keeps the turn and moves nothing, which is what a
        \\side question is.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len != 1) {
        try ctx.err.writeAll("m8 tag: name one address to point\n");
        return 1;
    }
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    const a = try address.typed(ctx.arena, ctx.io, dirs, ctx.args[0], ctx.err);
    if (a.suffix == .reset) {
        try ctx.err.writeAll("m8 tag: a reset is `m8 @ADDRESS-`, not something to tag\n");
        return 1;
    }

    if (ctx.in.len == 0 or doc.detect(ctx.in) == null) {
        try ctx.err.writeAll("m8 tag: pipe in a turn to keep, or a 🧠 to point at\n");
        return 1;
    }
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);

    const turn = try address.tag(ctx.arena, ctx.io, dirs, a, records);
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = turn });
    return 0;
}
