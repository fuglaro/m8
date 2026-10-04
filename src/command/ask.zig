//! `ask` — put a question to the person, append their answer to the chain.
//!
//! The shape every interactive command takes: talk to the terminal, then exit
//! having added exactly one record to the document. What the person typed
//! lands in the query, not in the scrollback, so the next command in the pipe
//! sees it.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ask",
    .summary = "ask the person something and append it as a user record",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 ask — ask the person something, and append what they said
        \\
        \\  ... | m8 ask [QUESTION] | ...
        \\
        \\It writes the document through unchanged and adds one 🙋 holding the
        \\answer, so the next command in the pipe sees it.
        \\
        \\The question goes to the terminal rather than to stdout, which is
        \\what keeps an interactive tool a legal member of a pipeline. With no
        \\terminal there is nobody to ask, and the document is left as it was.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);
    try doc.writeAll(ctx.out, ctx.mode, records);

    const question = if (ctx.args.len > 0) ctx.args[0] else "?";

    const answer = if (ctx.tty) |t| blk: {
        try t.prompt("{s} ", .{question});
        break :blk (try t.line()) orelse return 0;
    } else return 0; // nobody to ask; leave the document as it was

    // Records are separated by a blank line, and there is always one above.
    if (records.len > 0) try ctx.out.writeByte('\n');
    try doc.write(ctx.out, ctx.mode, .{
        .sigil = .user,
        .content = std.mem.trimEnd(u8, answer, "\r"),
    });
    return 0;
}
