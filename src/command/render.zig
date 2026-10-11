//! `render` — a document, written the way a person reads it.
//!
//! Every other command writes markdown whatever stdout is, so that it says
//! the same thing to a terminal as to a pipe. This is where the rendered
//! spelling comes from instead: anything a command wrote, piped through here.
//!
//! `-r` writes markdown back, which makes it the thing that proves a document
//! survives a round trip — line endings normalised, quotes reapplied, nothing
//! else touched.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "render",
    .summary = "write a document the way a person reads it",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 render — write a document the way a person reads it
        \\
        \\  m8 render [-r]
        \\
        \\Reads a document on stdin and writes it in the emoji spelling,
        \\whatever stdout is. It is a pure filter: no terminal, no network,
        \\and nothing is resolved.
        \\
        \\  m8 ref @mathy | m8 encode | m8 render | less -R
        \\  m8 render <ledger.md
        \\
        \\`-r` is raw: markdown, the spelling every file is kept in. A
        \\document survives that round trip with nothing changed but line
        \\endings and quotes, which is how to check that one parses.
        \\
        \\  m8 render -r <ledger.md >same.md
        \\
        \\A document that does not parse is an error naming the line, rather
        \\than something half written out.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var mode: doc.Mode = .m8;
    for (ctx.args) |arg| {
        if (std.mem.eql(u8, arg, "-r")) {
            mode = .md;
        } else {
            try ctx.err.print("m8 render: '{s}' is not something it takes; see m8 render --help\n", .{arg});
            return 1;
        }
    }

    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, ctx.in, &diag) catch |e| {
        try ctx.err.print("m8 render: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };
    try doc.writeAll(ctx.out, mode, records);
    return 0;
}
