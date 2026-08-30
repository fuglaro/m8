//! `send` — hand a ledger to a provider and carry on with it.
//!
//! The ledger says which model and what to ask it for. All it can be missing
//! is whose model it was, because a request on the wire never said — so what
//! `send` takes is a provider, and that is what makes a decoded request
//! runnable again.

const std = @import("std");
const converse = @import("../converse.zig");
const providers = @import("providers.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "send",
    .summary = "run a ledger, optionally against a named provider",
    .run = run,
    .help = help,
};

/// What a provider is belongs to `m8 help providers`; what is listed here is
/// which ones this machine has, because that is the argument.
fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 send — run a ledger against a provider
        \\
        \\  m8 [@AGENT|+CHAT] send [PROVIDER]
        \\
        \\The ledger says which model and everything to ask it for. All it can
        \\be missing is whose model it was, because a request on the wire never
        \\said — so what send takes is a provider, and that is what makes a
        \\decoded request runnable again.
        \\
        \\  m8 +mathy send
        \\  m8 decode openai-completions <request.json | m8 send local
        \\
        \\Naming one here is used instead of whatever the ledger names. Naming
        \\none, the 🧠 decides: what a model address says before its first `/`
        \\is the provider it is asked of.
        \\
        \\Whatever the run says is appended to the ledger — a reply, a 📲, and
        \\the answer to that 📲 — and the turn is saved and its name printed.
        \\
    );
    try providers.configured(ctx, w);
    try w.writeAll(
        \\
        \\m8 help providers says what one of those is and how to write another.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    const override = if (ctx.args.len > 0) ctx.args[0] else "";
    try converse.run(ctx, override);
    return 0;
}
