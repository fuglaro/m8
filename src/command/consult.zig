//! `--` — consult an agent.
//!
//! The command whose arguments are prose. Everything after it is the prompt,
//! which is why it needs no separator: `--` is not punctuation between m8's
//! arguments and yours, it is the name of the thing that takes yours.
//!
//! What it does with the assembled ledger is what `send` does. They differ in
//! what their arguments mean — a prompt here, a provider/model there — and
//! that is the whole of it.

const std = @import("std");
const converse = @import("../converse.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

/// The name is two dashes, which no other command may be called.
pub const name = "--";

pub const command: api.Command = .{
    .name = name,
    .summary = "consult an agent; everything after is the prompt",
    .prompts = true,
    .run = run,
};

fn run(ctx: Ctx) !u8 {
    // The prompt was appended to the ledger during assembly, so there is
    // nothing left here to read.
    try converse.run(ctx, "");
    return 0;
}
