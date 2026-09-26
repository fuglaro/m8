//! `m8 @ADDRESS WORDS` — the pipeline written once.
//!
//!     echo WORDS | m8 cat @ADDRESS | m8 send | m8 tag @ADDRESS
//!
//! is what this does, and it is kept exactly that: the same assembly, the
//! same run, the same tag. The one difference is that it is one process, so
//! the reply is shown as it arrives rather than once there is a turn to keep.
//!
//! `@` is not a command, but it sits where one would. Its arguments are prose,
//! so nothing after it has to be told from m8's own flags — which is what the
//! old `--` marker was for, and why there is no `--` any more.

const std = @import("std");
const doc = @import("m8/doc.zig");
const config = @import("config.zig");
const address = @import("address.zig");
const assembly = @import("assembly.zig");
const converse = @import("converse.zig");
const api = @import("command/api.zig");
const Ctx = api.Ctx;

/// `args` are every word after `m8`: the address, and what to say to it. None
/// at all is the main chat.
pub fn run(ctx: Ctx, args: []const []const u8) !u8 {
    const arena = ctx.arena;
    const io = ctx.io;
    const dirs = try config.discover(arena, io, ctx.env);

    const word = if (args.len > 0) args[0] else "@";
    const a = try address.typed(arena, io, dirs, word, ctx.err);
    const words = if (args.len > 0) args[1..] else args;

    if (a.suffix == .reset) {
        if (words.len > 0) {
            try ctx.err.writeAll("m8: a reset says nothing, so nothing goes after it\n");
            return 1;
        }
        try address.reset(arena, io, dirs, a);
        return 0;
    }

    const prompt = try std.mem.join(arena, " ", words);
    var in_buf: [64 * 1024]u8 = undefined;
    const piped = if (ctx.in.len > 0) ctx.in else try api.readDocument(io, arena, &in_buf);

    const lead = [_]doc.Record{.{ .sigil = .agent, .value = try address.read(arena, io, dirs, a) }};
    const assembled = try assembly.assemble(arena, &lead, prompt, piped);
    if (assembled.said_nothing) {
        // Where the terminal will one day open a conversation in place. For
        // now there is only nothing to say, and it is said.
        try ctx.err.writeAll("m8: say something after the address, or pipe it in\n");
        return 1;
    }

    var inner = ctx;
    inner.in = assembled.document;
    const turn = try converse.run(inner, .{});
    const kept = try address.tag(arena, io, dirs, a, turn);

    try ctx.out.writeByte('\n');
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = kept });
    return 0;
}
