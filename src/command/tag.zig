//! `tag` — keep a turn, and point an address at it.
//!
//! The one command that moves a chat on. A document that is one 🧠 already
//! names a turn, so the address is pointed at it and nothing is written;
//! anything else is kept as a new turn and pointed at. Either way what comes
//! out is the 🧠 of the turn now pointed at, and nothing else — it is a ref
//! being written, and the line is its receipt.
//!
//! Only the explicitly addressed chat moves.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const session = @import("../session.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "tag",
    .summary = "keep a turn, and point an address at it",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 tag [--no-advance] :MOB/AGENT
        \\
        \\A document that is one 🧠 names a turn already, so the address is
        \\pointed at it and nothing is written. Anything else is kept as a new
        \\turn and pointed at. What comes out is the 🧠 now pointed at.
        \\
        \\  m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy    carry mathy on
        \\  m8 say --no-send :demo/mathy | m8 tag :demo/mathy//aside             fork a chat
        \\  m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy//other   keep a run elsewhere
        \\
        \\  :demo/agent//chat  the turn goes in the chat, and its pointer advances
        \\  :MOB/AGENT/+/TURN   a turn goes beside its parent
        \\
        \\`--no-advance` keeps the turn where it would have gone and moves
        \\nothing, which is what a side question is.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var args = ctx.args;
    var moving: address.Moving = .{};
    if (args.len > 0 and std.mem.eql(u8, args[0], "--no-advance")) {
        moving.stay = true;
        args = args[1..];
    }
    if (args.len != 1 or !address.isAddress(args[0])) {
        try ctx.err.writeAll("m8 tag: name one :MOB/AGENT to point, after `--no-advance` if nothing is to move\n");
        return 1;
    }
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    const a = try address.typed(ctx.arena, ctx.io, dirs, args[0], ctx.err);
    if (a.suffix != .none) {
        try ctx.err.writeAll(
            "m8 tag: the address carries no `:` or `-`; " ++
                "those are `m8 tag --no-advance` and `m8 reset`\n",
        );
        return 1;
    }

    if (ctx.in.len == 0 or doc.detect(ctx.in) == null) {
        try ctx.err.writeAll("m8 tag: pipe in a turn to keep, or a 🧠 to point at\n");
        return 1;
    }
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);

    // A lone 🧠 is pointed at rather than kept, so it has to be there: a chat
    // pointed at a turn nobody kept would read as nothing.
    if (records.len == 1 and records[0].sigil == .agent and records[0].content == null) {
        const named = try session.settle(ctx.arena, ctx.io, dirs, records[0].value);
        if (session.isTurn(named) and !try session.exists(ctx.arena, ctx.io, dirs, named)) {
            try ctx.err.print("m8: no turn named '{s}'\n", .{named});
            return 1;
        }
    }

    const turn = try address.tag(ctx.arena, ctx.io, dirs, a, records, moving);
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = turn });
    return 0;
}
