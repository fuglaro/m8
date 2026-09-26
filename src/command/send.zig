//! `send` — run a ledger, and write the turn it makes.
//!
//! The ledger says which model and everything to ask it for, and whose model
//! it is. What comes out is the turn — the ledger as it arrived and whatever
//! the run added — and nothing is kept. Keeping it is `tag`'s business, which
//! is what lets one run be kept wherever it is tagged, or nowhere.

const std = @import("std");
const converse = @import("../converse.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "send",
    .summary = "run a ledger and write the turn it makes",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 send — run a ledger and write the turn it makes
        \\
        \\  m8 send
        \\
        \\The ledger on stdin says which model, everything to ask it for, and
        \\whose model it is: what a model address says before its first `/`
        \\is the provider it is asked of. The last model named is the one
        \\that answers, so one piped in after a chat is the one it runs on.
        \\
        \\  m8 cat @mathy | m8 send
        \\  echo "#### :brain:/local/tiny" | m8 cat @mathy | m8 send
        \\  m8 decode openai-completions local <request.json | m8 send
        \\
        \\Whatever the run says is appended — a reply, a 📲, and the answer to
        \\that 📲. Under a pipe what comes out is the whole turn: the ledger as
        \\it arrived, settled, and then all of that. A terminal is shown only
        \\the reply. Nothing is kept: `m8 tag` keeps it.
        \\
        \\  m8 cat @mathy | m8 send | m8 tag @mathy
        \\
        \\That is what `m8 @mathy` does. m8 help providers says what a provider
        \\is and how to write another.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len > 0) {
        try ctx.err.writeAll(
            "m8 send: takes no arguments; whose model it is goes on the 🧠, " ++
                "or on `m8 decode FORMAT PROVIDER`\n",
        );
        return 1;
    }
    _ = try converse.run(ctx, .{ .echo_given = ctx.mode == .md });
    return 0;
}
