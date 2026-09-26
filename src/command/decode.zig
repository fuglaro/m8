//! `decode` — some other format, as a ledger.
//!
//! The inverse of `encode`, and an approximation by construction. A ledger
//! always has an api view; an api request never has a ledger, because it
//! carries what one model needs in order to answer once rather than what
//! happened and what it was allowed to do.
//!
//! So what comes back is ledger-shaped rather than the ledger. A chat
//! completions request cannot tell a 🚫 from a 🧾, and a tool arrives without
//! its 🔌 or its 🔒 — a model call has no business carrying either, so those
//! not coming home is the rule holding rather than a corner missed. What was
//! on the wire does come back, all of it.
//!
//! `m8 decode m8` is the exception that says why: m8 is the one format whose
//! view is the whole ledger, so it is the one that approximates nothing. It
//! is a null operation and is meant to be, since reading the language and
//! writing it out is what proves a document round-trips.

const std = @import("std");
const codec = @import("../codec.zig");
const ledger = @import("../ledger.zig");
const model = @import("../m8/model.zig");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "decode",
    .summary = "read some api's request back as a ledger",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 decode — read some api's request back as a ledger
        \\
        \\  m8 decode FORMAT [PROVIDER] <request.json
        \\
        \\Stdin is not m8 yet, so this is the way in.
        \\
        \\  m8 decode openai-completions local <request.json | m8 send
        \\  m8 decode m8 <ledger.md
        \\
        \\A request says which model and everything to ask it for, and never
        \\whose model it was. This is where that went missing, so this is where
        \\it is said: PROVIDER goes on every model the request names, and what
        \\comes out runs as it is.
        \\
        \\What comes back is ledger-shaped rather than the ledger: a request
        \\carries what one model needs in order to answer once, so a 🚫 cannot
        \\be told from a 🧾 and a tool arrives without its 🔌 or its 🔒. What
        \\was on the wire does come back, all of it. `decode m8` is the
        \\exception that says why, and approximates nothing.
        \\
    );
    try codec.list(w);
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try ctx.err.writeAll("m8 decode: name a format\n");
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }
    const c = codec.find(ctx.args[0]) orelse {
        try ctx.err.print("m8 decode: no format named '{s}'\n", .{ctx.args[0]});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    if (ctx.args.len > 2) {
        try ctx.err.writeAll("m8 decode: a format, and a provider at most\n");
        return 1;
    }
    const records = try ctx.arena.dupe(doc.Record, try c.decode(ctx.arena, ctx.in));
    if (ctx.args.len == 2) for (records) |*r| {
        if (r.sigil != .agent) continue;
        var m = (try model.parse(ctx.arena, r.value)) orelse continue;
        m.provider = ctx.args[1];
        r.value = try model.render(ctx.arena, m);
    };
    try ledger.writeAll(ctx.out, ctx.arena, ctx.mode, records);
    return 0;
}
