//! `send` — run a ledger, and write the turn it makes.
//!
//! The ledger says which model and everything to ask it for, and whose model
//! it is. What comes out is the turn — the ledger as it arrived and whatever
//! the run added — and nothing is kept. Keeping it is `tag`'s business, which
//! is what lets one run be kept wherever it is tagged, or nowhere.

const std = @import("std");
const converse = @import("../converse.zig");
const api = @import("../api.zig");
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
        \\  m8 send
        \\
        \\Run the ledger on stdin and write the completed turn to stdout. The
        \\ledger selects the answering model: its provider comes from the model
        \\address, and the last model named answers. Tool calls and their
        \\results are appended to the output.
        \\
        \\EXAMPLES:
        \\
        \\  m8 say --no-send :demo/mathy "hi" | m8 send
        \\  { m8 say --no-send :demo/mathy "hi"; echo "* :brain::/local/tiny"; } | m8 send
        \\  m8 say --no-send :demo/mathy "hi" | m8 send | m8 tag :demo/mathy
        \\
        \\`send` does not keep the turn. Pipe it to `m8 tag` to save it.
        \\It accepts no arguments. Use `m8 render` to display a turn for reading,
        \\or `m8 cat --unwrap` to convert packed records to Markdown.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len > 0) {
        try ctx.err.writeAll(
            "m8 send: takes no arguments; whose model it is goes on the 🧠\n",
        );
        return 1;
    }
    _ = try converse.run(ctx, .{ .echo_given = true });
    return 0;
}
