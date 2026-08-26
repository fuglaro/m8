//! `decode` — some other format, as a ledger.
//!
//! The inverse of `encode`, and only ever as faithful as the format was. A
//! chat completions request has no 🔌 in it and cannot tell a 🚫 from a 🧾, so
//! those do not come back. What was on the wire does.
//!
//! `m8 decode m8` is the null operation, and is meant to be: reading the
//! language and writing it out is what proves a document round-trips.

const std = @import("std");
const codec = @import("../codec.zig");
const ledger = @import("../ledger.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "decode",
    .summary = "read some api's request back as a ledger",
    // Not m8 on the way in, so there is no ledger to assemble yet. This is
    // the way in.
    .takes = .stdin,
    .run = run,
};

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try ctx.err.writeAll("m8 decode: name a format\n");
        return 1;
    }
    const c = codec.find(ctx.args[0]) orelse {
        try ctx.err.print("m8 decode: no format named '{s}'\n", .{ctx.args[0]});
        return 1;
    };

    const records = try c.decode(ctx.arena, ctx.in);
    try ledger.writeAll(ctx.out, ctx.arena, ctx.mode, records);
    return 0;
}
