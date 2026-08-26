//! `send` — hand a ledger to a provider and carry on with it.
//!
//! The ledger says which model and what to ask it for. All it can be missing
//! is whose model it was, because a request on the wire never said — so what
//! `send` takes is a provider, and that is what makes a decoded request
//! runnable again.

const std = @import("std");
const converse = @import("../converse.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "send",
    .summary = "run a ledger, optionally against a named provider",
    .run = run,
};

fn run(ctx: Ctx) !u8 {
    const override = if (ctx.args.len > 0) ctx.args[0] else "";
    try converse.run(ctx, override);
    return 0;
}
