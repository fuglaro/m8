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
        \\  m8 tag :MOB/AGENT/+/TURN
        \\
        \\Read a document from stdin, keep it as a turn, and point the named
        \\agent or chat at that turn. If stdin is a single bare 🧠 reference,
        \\point at the existing turn instead. Writes the resulting 🧠 reference
        \\to stdout.
        \\
        \\OPTIONS:
        \\
        \\  --no-advance  Keep the turn without moving the address pointer.
        \\
        \\EXAMPLES:
        \\
        \\  m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy
        \\  m8 tag :demo/mathy/+/tduyxbutjb
        \\  m8 tag :demo/mathy//aside/+/tduyxbutjb
        \\  m8 say --no-send :demo/mathy | m8 tag :demo/mathy//aside
        \\  m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy//other
        \\
        \\A chat address advances its pointer by default. Use `--no-advance`
        \\for a side turn that should not move it.
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
                "those are `m8 tag --no-advance` and `m8 say CHAT-` (or `say --parent CHAT`)\n",
        );
        return 1;
    }

    // A turn reference is a compact pointer operation: its containing chat is
    // the target, and the named immutable turn is what that chat should read.
    if (a.kind == .turn) {
        if (moving.stay or ctx.in.len != 0) {
            try ctx.err.writeAll("m8 tag: a turn reference takes no stdin or --no-advance\n");
            return 1;
        }
        if (!try session.exists(ctx.arena, ctx.io, dirs, a.name)) {
            try ctx.err.print("m8: no turn named '{s}'\n", .{a.name});
            return 1;
        }
        const marker = std.mem.indexOf(u8, a.name, "/+/") orelse return error.InvalidName;
        const chat = a.name[0..marker];
        const chat_address = try std.fmt.allocPrint(ctx.arena, ":{s}", .{chat});
        const target = try address.typed(ctx.arena, ctx.io, dirs, chat_address, ctx.err);
        if (target.kind != .chat) return error.InvalidName;
        try session.point(ctx.arena, ctx.io, dirs, try session.pointerOf(ctx.arena, chat), a.name);
        try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = a.name });
        return 0;
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
