//! `cat` — a document, or what an address reads as, written back out.
//!
//! With no address it is a pure filter, and the thing that proves a document
//! survives a round trip — line endings normalised, quotes reapplied, nothing
//! else touched.
//!
//! With one it is how a chat gets into a pipe. The address is settled to the
//! turn it has got to, never the chat's own name, so what comes out is a
//! snapshot that stays put when the chat moves on. Whatever was piped in
//! follows it, which is how a pipe adds to a chat before sending it.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "cat",
    .summary = "write a document, or what an address reads as",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 cat — write a document, or what an address reads as
        \\
        \\  m8 cat [@ADDRESS]
        \\
        \\With no address it is a pure filter: no terminal, no network. It
        \\renders, since a terminal is written the emoji spelling and
        \\everything else markdown, and it is the thing that proves a document
        \\survives a round trip.
        \\
        \\With one, it writes the 🧠 that address reads as now — the turn a
        \\chat has got to, not the chat's name, so it stays put when the chat
        \\moves on — and then whatever was piped in. A document follows as it
        \\is; anything else is something said, and becomes a 🙋.
        \\
        \\  m8 cat @mathy | m8 send
        \\  echo "and in one sentence?" | m8 cat @ | m8 send | m8 tag @
        \\  echo "#### :brain:/local/tiny" | m8 cat @mathy | m8 send
        \\  m8 cat <ledger.md >same.md
        \\
        \\A document that does not parse is an error naming the line, rather
        \\than something half written out.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len > 1) {
        try ctx.err.writeAll("m8 cat: one address at most\n");
        return 1;
    }

    const src = if (ctx.args.len == 0) ctx.in else blk: {
        const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
        const a = try address.typed(ctx.arena, ctx.io, dirs, ctx.args[0], ctx.err);
        if (a.suffix != .none) {
            try ctx.err.writeAll("m8 cat: an address to read carries no `:` or `-`\n");
            return 1;
        }
        const lead = [_]doc.Record{.{ .sigil = .agent, .value = try address.read(ctx.arena, ctx.io, dirs, a) }};
        break :blk (try assembly.assemble(ctx.arena, &lead, "", ctx.in)).document;
    };

    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, src, &diag) catch |e| {
        try ctx.err.print("m8 cat: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };
    try doc.writeAll(ctx.out, ctx.mode, records);
    return 0;
}
