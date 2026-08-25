//! `cat` — parse a document and write it back.
//!
//! Pure filter, no terminal, no network. Two jobs: it renders, since a
//! terminal gets the emoji spelling and everything else gets markdown, and it
//! is the thing that proves a document survives a round trip — line endings
//! normalised, quotes reapplied, nothing else touched.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "cat",
    .summary = "parse a document and write it back out",
    .run = run,
};

fn run(ctx: Ctx) !u8 {
    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, ctx.in, &diag) catch |e| {
        if (ctx.tty) |t| try t.prompt("m8 cat: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };
    try doc.writeAll(ctx.out, ctx.mode, records);
    return 0;
}
