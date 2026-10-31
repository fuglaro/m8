//! `encode` — a ledger, in some other format.
//!
//! The ledger arrives on stdin, and every 🧠 in it is expanded into what it
//! names. What comes out is one api's view of that.
//!
//! `m8` is a format like any other here, which is why `m8 encode m8` is how a
//! chat gets flattened into a single document. It is the only one that loses
//! nothing.

const std = @import("std");
const codec = @import("../codec.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const agent = @import("../agent.zig");
const ledger = @import("../ledger.zig");
const doc = @import("../m8/doc.zig");
const api = @import("../api.zig");
const link = @import("../link.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "encode",
    .summary = "write a ledger as some api's request",
    .run = run,
    .help = help,
};

fn run(ctx: Ctx) !u8 {
    // m8 is the lossless view of a ledger, so it is the useful default when
    // no projection was requested explicitly.
    var name: []const u8 = "m8";
    var breaks: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        if (!std.mem.eql(u8, arg, "--break")) {
            name = arg;
            continue;
        }
        i += 1;
        if (i == ctx.args.len) {
            try ctx.err.writeAll("m8 encode: `--break` is followed by the name to stop at\n");
            return 1;
        }
        // A 🧠 line pasted in names what it printed, mark and all.
        try breaks.append(ctx.arena, address.body(ctx.args[i]) orelse ctx.args[i]);
    }
    const c = codec.find(name) orelse {
        try ctx.err.print("m8 encode: no format named '{s}'\n", .{name});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    const arena = ctx.arena;
    var diag: doc.Diagnostic = .{};
    const given = try doc.parse(arena, ctx.in, &diag);

    const dirs = try config.discover(arena, ctx.io, ctx.env);
    const expanded = try ledger.expandUntil(
        arena,
        ctx.io,
        dirs,
        given,
        doc.detect(ctx.in) orelse .md,
        .{ .names = breaks.items },
    );

    const env = try api.childEnvironment(arena, ctx, &.{});
    const records = try link.handOver(arena, ctx.io, dirs, env, expanded.records);
    try ctx.out.writeAll(try c.encode(arena, records, try target(ctx, expanded.records)));
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
        // A hint rather than a contract: a provider that cannot stream
        // answers whole, and `parse` reads either.
        .stream = true,
    };
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 encode [--break NAME]... [FORMAT]
        \\
        \\With no FORMAT, the ledger is written as m8, the lossless format.
        \\The ledger arrives on stdin, with every 🧠 expanded into what it
        \\names. What comes out is one api's view of it.
        \\
        \\  m8 say --no-send :demo/mathy | m8 encode m8 >ledger.md
        \\  m8 encode openai-completions <ledger.md >request.json
        \\
        \\Encoding is total and loses whatever the target cannot say, which is
        \\what makes it a projection: the ledger it came from still holds all
        \\of it. `m8` is the one format whose view is the whole ledger, which
        \\is why `encode m8` is how a chat becomes one flat document. A file a
        \\🔗 names goes as its provider entry's `upload` says, and with no
        \\`upload`, or one that fails, is an error.
        \\
        \\`--break NAME` leaves a 🧠 naming NAME as it was written rather than
        \\expanding it, so what comes out is the ledger from there on. NAME is
        \\what a 🧠 says: a turn, or an agent.
        \\
        \\  m8 say --no-send :demo/mathy | m8 encode --break mathy/+/tduyxbutjb
        \\  m8 say --no-send :demo/mathy | m8 encode --break mathy     the chat, without its agent
        \\
        \\A request needs no provider, because the ledger carries the model and
        \\its parameters — so one can be built for a provider m8 has never been
        \\told about.
        \\
    );
    try codec.list(w);
}
