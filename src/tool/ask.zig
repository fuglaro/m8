//! `>ask` — put a question to the person, append their answer to the chain.
//!
//! The shape every interactive tool takes: talk to the terminal, then exit
//! having added exactly one record to the document. What the person typed
//! lands in the query, not in the scrollback, so the next tool in the pipe
//! sees it.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const tool: api.Tool = .{
    .name = "ask",
    .summary = "ask the person something and append it as a user record",
    .run = run,
};

fn run(ctx: Ctx) !void {
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);
    try doc.writeAll(ctx.out, records);

    const question = if (ctx.args.len > 0) ctx.args[0] else "?";

    const answer = if (ctx.tty) |t| blk: {
        try t.prompt("{s} ", .{question});
        break :blk (try t.line()) orelse return;
    } else return; // nobody to ask; leave the document as it was

    try doc.write(ctx.out, .{
        .sigil = .user,
        .fields = &.{std.mem.trimEnd(u8, answer, "\r")},
    });
}
