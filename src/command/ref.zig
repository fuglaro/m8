//! `ref` — the 🧠 an address reads as, and what is said to it.
//!
//! It is how a chat gets into a pipe. The address is settled to the turn it
//! has got to, never the chat's own name, so what comes out is a snapshot
//! that stays put when the chat moves on — and a reference rather than a
//! copy, which is what lets `tag` point at it without keeping it again.
//!
//! What is named is looked for. A 🧠 written for a turn nobody kept would be
//! the ledger saying something that did not happen.
//!
//! Anything said follows the 🧠, as one argument. Stdin is read only when
//! `--piped` asks for it, so this never waits on a pipe somebody else is
//! holding open, and never takes input that was meant for whatever ran it.
//! What it reads is always prose: a document that should follow an address is
//! concatenated after this one, which is all a document needs.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const ledger = @import("../ledger.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ref",
    .summary = "the 🧠 an address reads as, and what is said to it",
    // Stdin is read when `--piped` says to, and is otherwise left alone.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 ref [--piped] :MOB/AGENT [MESSAGE]
        \\
        \\Writes the 🧠 that address reads as now — the turn a chat has got
        \\to, not the chat's name, so it stays put when the chat moves on. A
        \\turn, a model, and an agent nobody has talked to yet read as
        \\themselves. A turn or an agent that is not there is an error.
        \\
        \\  m8 ref :demo/mathy | m8 send | m8 tag :demo/mathy
        \\  m8 ref :demo/mathy | m8 tag :demo/mathy//aside        fork, with nothing said
        \\  m8 ref :demo/mathy | m8 encode                  the whole chat, flat
        \\
        \\A MESSAGE follows the 🧠 as a 🙋, or as the ❗ that answers a chat
        \\waiting on a question. It is one argument, and whatever it opens
        \\with it is never read as an option.
        \\
        \\`--piped` reads stdin as prose and says that too, after the MESSAGE
        \\when there is one. Without it stdin is not touched.
        \\
        \\  m8 ref :demo/mathy "and in one sentence?" | m8 send | m8 tag :demo/mathy
        \\  echo "and in one sentence?" | m8 ref --piped :demo/mathy | m8 send
        \\  m8 ref --piped :demo/mathy "Summarize:" <notes.txt | m8 send
        \\
        \\A document follows an address by being written after it:
        \\
        \\  { m8 ref :demo/mathy; echo "* :brain::/local/tiny"; } | m8 send
        \\
        \\What `m8 :demo/x` wrote ends on the 🧠 of the turn it kept, and `m8 tail`
        \\takes that out:
        \\
        \\  m8 ref ":$(m8 :demo/x -- hi | m8 tail --value)" "review that" | m8 send
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var args = ctx.args;
    const piped = args.len > 0 and std.mem.eql(u8, args[0], "--piped");
    if (piped) args = args[1..];
    if (args.len == 0 or args.len > 2 or !address.isAddress(args[0])) {
        try ctx.err.writeAll(
            "m8 ref: name one :MOB/AGENT, after `--piped` if stdin is said to it, " ++
                "and then one MESSAGE if anything is\n",
        );
        return 1;
    }
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    const a = try address.typed(ctx.arena, ctx.io, dirs, args[0], ctx.err);
    if (a.suffix != .none) {
        try ctx.err.writeAll("m8 ref: an address to read carries no `:` or `-`\n");
        return 1;
    }

    const name = try address.found(ctx.arena, ctx.io, dirs, a, ctx.err);
    var records: std.ArrayList(doc.Record) = .empty;
    try records.append(ctx.arena, .{ .sigil = .agent, .value = name });

    const prompt = if (args.len == 2) args[1] else "";
    var buf: [64 * 1024]u8 = undefined;
    const prose = if (piped) try api.readDocument(ctx.io, ctx.arena, &buf) else "";
    const asked = ledger.waiting(ctx.arena, ctx.io, dirs, name);
    if (try assembly.said(ctx.arena, prompt, prose, asked)) |r| try records.append(ctx.arena, r);

    try doc.writeAll(ctx.out, ctx.mode, records.items);
    return 0;
}
