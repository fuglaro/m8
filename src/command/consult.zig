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
    .help = help,
};

/// `--` never sees this flag itself: its arguments are prose, so `m8 -- --help`
/// is something somebody said. `m8 help --` is how the page is asked for.
fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 -- — consult an agent; everything after is the prompt
        \\
        \\  m8 [@AGENT|+CHAT] -- WHATEVER YOU WANT TO SAY
        \\
        \\The command whose arguments are prose, which is why it needs no
        \\separator: `--` is not punctuation between m8's arguments and yours,
        \\it is the name of the thing that takes yours. A bare `m8`, and a name
        \\with nothing after it, run it.
        \\
        \\  m8 @mathy -- "Tell me about the Riemann Sphere."
        \\  m8 +mathy -- "Tell me more."
        \\  cat notes.txt | m8 -- "Summarize:"
        \\
        \\What it does with the assembled ledger is what `send` does. They
        \\differ in what their arguments mean — a prompt here, a provider there
        \\— and that is the whole of it.
        \\
        \\Since everything after it is prose, `m8 -- --help` is a question you
        \\asked an agent. This page is `m8 help --`.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    // The prompt was appended to the ledger during assembly, so there is
    // nothing left here to read.
    try converse.run(ctx, "");
    return 0;
}
