//! `top` — name a file for what it says about itself.
//!
//! `cat` names a file for what it says, as a 🧠. This names it as a 📚, which
//! expands to the file's top, so a skill joins a chat by being piped in front
//! of it rather than by a mark of its own on the command line.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const session = @import("../session.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "top",
    .summary = "name a file for what it says about itself",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 top — name a file for what it says about itself
        \\
        \\  m8 top @SKILL
        \\
        \\Writes a 📚 naming SKILL, and then whatever was piped in, the same way
        \\`m8 cat` does with a 🧠. A 📚 expands to the file's top — what sits
        \\between its two 🔝 — so that is what joins the ledger.
        \\
        \\  m8 top @tight-docs | m8 @mathy "tidy the README"
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len != 1 or !address.isAddress(ctx.args[0])) {
        try ctx.err.writeAll("m8 top: name one @SKILL\n");
        return 1;
    }
    const name = std.mem.trim(u8, address.body(ctx.args[0]).?, "/");
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    // A top is a file's, so only a file has one: not a chat, and not a model.
    if (!try session.isAgent(ctx.arena, ctx.io, dirs, name)) {
        try ctx.err.print("m8: no agent named '{s}'\n", .{name});
        return 1;
    }
    const lead = [_]doc.Record{.{ .sigil = .skill, .value = name }};
    const assembled = try assembly.assemble(ctx.arena, &lead, "", ctx.in);
    var diag: doc.Diagnostic = .{};
    try doc.writeAll(ctx.out, ctx.mode, try doc.parse(ctx.arena, assembled.document, &diag));
    return 0;
}
