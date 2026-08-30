//! `encode` — a ledger, in some other format.
//!
//! The ledger arrives whole: whatever was piped in, whatever the command line
//! named, and whatever followed `--`, with every 🧠 expanded into what it
//! names. What comes out is one api's view of that.
//!
//! `m8` is a format like any other here, which is why `m8 encode m8` is how a
//! chat gets flattened into a single document. It is the only one that loses
//! nothing.

const std = @import("std");
const codec = @import("../codec.zig");
const config = @import("../config.zig");
const agent = @import("../agent.zig");
const ledger = @import("../ledger.zig");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "encode",
    .summary = "write a ledger as some api's request",
    .run = run,
    .help = help,
};

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try ctx.err.writeAll("m8 encode: name a format\n");
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }
    const c = codec.find(ctx.args[0]) orelse {
        try ctx.err.print("m8 encode: no format named '{s}'\n", .{ctx.args[0]});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    const arena = ctx.arena;
    var diag: doc.Diagnostic = .{};
    const given = try doc.parse(arena, ctx.in, &diag);

    const dirs = try config.discover(arena, ctx.io, ctx.env);
    const expanded = try ledger.expandRecords(
        arena,
        ctx.io,
        dirs,
        given,
        doc.detect(ctx.in) orelse .md,
    );

    try ctx.out.writeAll(try c.encode(arena, expanded.records, try target(ctx, expanded.records)));
    return 0;
}

/// What the ledger says the request is, plus what this run adds. The ledger
/// carries the model and its parameters, so no provider needs consulting: a
/// request can be built for a provider m8 has never been told about.
fn target(ctx: Ctx, records: []const doc.Record) !codec.Target {
    const def = try agent.project(ctx.arena, records);
    return .{
        .mode = ctx.mode,
        .model = def.model,
        .params = def.params,
        .tools = try agent.offer(ctx.arena, def),
    };
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 encode — write a ledger as some api's request
        \\
        \\  m8 [@AGENT|+CHAT] encode FORMAT
        \\
        \\The ledger arrives whole — whatever was piped in, whatever the
        \\command line named, and whatever followed `--`, with every 🧠
        \\expanded into what it names. What comes out is one api's view of it.
        \\
        \\  m8 +mathy encode m8 >ledger.md
        \\  m8 encode openai-completions <ledger.md >request.json
        \\
        \\Encoding is total and loses whatever the target cannot say, which is
        \\what makes it a projection: the ledger it came from still holds all
        \\of it. `m8` is the one format whose view is the whole ledger, which
        \\is why `encode m8` is how a chat becomes one flat document.
        \\
        \\A request needs no provider, because the ledger carries the model and
        \\its parameters — so one can be built for a provider m8 has never been
        \\told about.
        \\
    );
    try codec.list(w);
}
