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
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 cat — parse a document and write it back out
        \\
        \\  m8 [@AGENT|+CHAT] cat
        \\
        \\A pure filter: no terminal, no network, no arguments. It renders,
        \\since a terminal is written the emoji spelling and everything else
        \\markdown, and it is the thing that proves a document survives a round
        \\trip — line endings normalised, quotes reapplied, nothing else
        \\touched.
        \\
        \\  m8 +mathy cat
        \\  m8 cat <ledger.md >same.md
        \\
        \\A document that does not parse is an error naming the line, rather
        \\than something half written out.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, ctx.in, &diag) catch |e| {
        if (ctx.tty) |t| try t.prompt("m8 cat: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };
    try doc.writeAll(ctx.out, ctx.mode, records);
    return 0;
}
