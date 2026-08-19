//! `>cat` — parse a document and write it back.
//!
//! Pure filter, no terminal, no network. It earns its place as the thing that
//! proves a document survives a round trip: line endings normalised, escapes
//! reapplied, nothing else touched.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const tool: api.Tool = .{
    .name = "cat",
    .summary = "parse a document and write it back out",
    .run = run,
};

fn run(ctx: Ctx) !void {
    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, ctx.in, &diag) catch |e| {
        if (ctx.tty) |t| try t.prompt("m8 >cat: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };
    try doc.writeAll(ctx.out, records);
}
