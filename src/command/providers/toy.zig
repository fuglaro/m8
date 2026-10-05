//! `providers toy` — answer the request here, with no network.
//!
//! These exist so that the loop, tool calling, and picking up a call that was
//! never answered can all be run without a model. `api: "m8"`, so the request
//! is a ledger and the response is the records it adds to one.

const std = @import("std");
const api = @import("../api.zig");
const doc = @import("../../m8/doc.zig");
const ledger = @import("../../ledger.zig");
const modelform = @import("../../m8/model.zig");
const eliza = @import("eliza.zig");
const zmachine = @import("zmachine.zig");
const Ctx = api.Ctx;

const testing = std.testing;

pub const command: api.Command = .{
    .name = "toy",
    .summary = "answer it here, with no network",
    // The request is read from the descriptor as it arrives, not handed
    // over: `url` streams it straight back out again.
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 providers toy — answer the request here, with no network
        \\
        \\  ... | m8 providers toy
        \\
        \\Speaks m8, so the request is the ledger itself and the answer is the
        \\records it adds to one. It answers without a network, which is what
        \\makes the loop, tool calling, and picking up a call that was never
        \\answered testable rather than only demonstrable.
        \\
        \\models:
        \\
        \\
    );
    for (models) |m| try w.print("  /toy/{s: <14} {s}\n", .{ m.name, m.summary });
    try w.writeAll(
        \\
        \\  m8 @/toy/echo hello
        \\  m8 @/toy/runner 'RUN;;;say;;;text=hi'
        \\  m8 @/toy/eliza "I am not sleeping well."
        \\  m8 @/toy/Z-Machine/zork1 "I would like to play"
        \\
        \\A name ending in ... is a family rather than one model: what follows
        \\it is the model's own business. Z-Machine takes the name of a story
        \\file, which is a Z-machine game — Zork and everything after it —
        \\played through the same ledger as anything else. The first thing you
        \\say is not played: it is hashed, and the hash is the world's seed.
        \\
        \\Story files are looked for under models/Z-Machine in every config
        \\directory, nearest first, so a project can carry the story its agents
        \\are tested against and a collection of your own lives in yours:
        \\
        \\  ./.m8-st8/models/Z-Machine/
        \\  ~/.config/m8-st8/models/Z-Machine/
        \\
        \\The name is the file's stem and the folder's, spelled the way they
        \\are — like every other name in m8 — across .z1 to .z8 and Blorb
        \\containers. m8 ships with none: it plays whichever you put there.
        \\Zork I to III are MIT-licensed source from Microsoft and are
        \\compiled in their repositories.
        \\
    );

    // Which story files are actually here. Unlike the models a provider on
    // the far end of a wire serves, these are files on this machine, so the
    // page can say — and a page that can say should.
    const stories = zmachine.available(ctx) catch &.{};
    if (stories.len == 0) {
        try w.print("\nstory files (none under {s} anywhere):\n\n", .{zmachine.subdir});
        try w.writeAll("  put one there and it is a model\n");
    } else {
        try w.print("\nstory files ({s}):\n\n", .{zmachine.subdir});
        for (stories) |one| try w.print("  /toy/{s}{s}\n", .{ zmachine.prefix, one });
    }
    try w.writeByte('\n');

    try w.writeAll(
        \\A 🧠 written with a leading / names a model, and what it says before
        \\its first / is the provider it is asked of. These are the only models
        \\m8 has of its own; every other one is whatever the provider you
        \\reached offers.
        \\
        \\The entry, which m8 ships with:
        \\
        \\  "toy": { "cmd": ["m8", "providers", "toy"], "api": "m8" }
        \\
        \\It reads nothing from the environment.
        \\
    );
}

// -------------------------------------------------------------------- url

/// One model `toy` serves. They are m8's own, and they exist so that the
/// loop can be run without a network.
///
/// A name ending in `...` advertises a *family* rather than one model: what
/// follows the prefix is that model's own business, and the model decides what
/// to make of it. That is how a story file comes to be a model without m8
/// keeping a list of story files — one row on the page, and every file in
/// `models/Z-Machine` reachable through it.
const Model = struct {
    name: []const u8,
    summary: []const u8,
    /// The name as asked for, which is the whole of it for a family.
    answer: *const fn (Ctx, doc.Mode, []const doc.Record, []const u8) anyerror!u8,
};

const family_mark = "...";

/// A name is a byte string here and nothing else. m8 has no opinion about
/// case, or about anything else in a name: it decides which model was asked
/// for and hands over the rest untouched. What a family makes of what follows
/// its prefix is that model's business, and so is whether it cares.
fn serves(candidate: []const u8, asked: []const u8) bool {
    if (std.mem.endsWith(u8, candidate, family_mark)) {
        const head = candidate[0 .. candidate.len - family_mark.len];
        return asked.len > head.len and std.mem.eql(u8, asked[0..head.len], head);
    }
    return std.mem.eql(u8, candidate, asked);
}

const models = [_]Model{
    .{
        .name = "echo",
        .summary = "says the last thing anybody said, back",
        .answer = echo,
    },
    .{
        .name = "runner",
        .summary = "calls a tool per RUN;;;tool;;;property=value line",
        .answer = runner,
    },
    .{
        .name = "eliza",
        .summary = "Weizenbaum's doctor, 1966: your own words, turned around",
        .answer = doctor,
    },
    .{
        .name = "Z-Machine/" ++ family_mark,
        .summary = "a story file, played as a model: see the page below",
        .answer = zmachine.answer,
    },
};

/// Answer the request here. `api: "m8"`, so the request is a ledger and the
/// response is the records it adds to one.
///
/// These exist so that the loop, tool calling, and picking up a call that was
/// never answered can all be run without a model — which is what makes them
/// testable rather than only demonstrable.
fn run(ctx: Ctx) !u8 {
    // m8 runs a provider with a pipe on stdin. A terminal is nobody piping a
    // request, so what was wanted is the page rather than a provider left
    // waiting for an end of file that is not coming.
    if (std.Io.File.stdin().isTty(ctx.io) catch false) {
        try ctx.err.writeAll("m8 providers toy: no request on stdin\n");
        try page(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    var in_buf: [64 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &in_buf);
    const request = try in.interface.allocRemaining(ctx.arena, .unlimited);

    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, request, &diag);
    const mode = doc.detect(request) orelse .md;

    const m = (try ledger.runsOn(ctx.arena, records)) orelse {
        try ctx.err.writeAll("m8 providers toy: the request names no model\n");
        try ctx.err.flush();
        return 1;
    };

    for (models) |candidate| {
        if (serves(candidate.name, m.name))
            return candidate.answer(ctx, mode, records, m.name);
    }

    try ctx.err.print("m8 providers toy: no model named '{s}'\n", .{m.name});
    for (models) |candidate| try ctx.err.print("  /toy/{s}\n", .{candidate.name});
    // Buffered, and the process is about to end: without this the caller is
    // told a provider failed and never told why.
    try ctx.err.flush();
    return 1;
}

fn echo(ctx: Ctx, mode: doc.Mode, records: []const doc.Record, model: []const u8) !u8 {
    _ = model;
    return say(ctx, mode, lastSaid(records));
}

/// ELIZA. What she says back is decided by the last thing the person said and
/// by how many times they have spoken, both of which the ledger already holds
/// — so she keeps nothing, and a conversation with her replays exactly.
fn doctor(ctx: Ctx, mode: doc.Mode, records: []const doc.Record, model: []const u8) !u8 {
    _ = model;
    var said: []const u8 = "";
    var spoken: usize = 0;
    for (records) |r| if (r.sigil == .user) {
        said = r.content orelse "";
        spoken += 1;
    };
    return say(ctx, mode, try eliza.reply(ctx.arena, said, spoken -| 1));
}

fn say(ctx: Ctx, mode: doc.Mode, what: []const u8) !u8 {
    try doc.write(ctx.out, mode, .{ .sigil = .bot, .content = what });
    return 0;
}

/// The last thing anybody said, whoever said it.
fn lastSaid(records: []const doc.Record) []const u8 {
    var i = records.len;
    while (i > 0) {
        i -= 1;
        switch (records[i].sigil) {
            .user, .bot => return records[i].content orelse "",
            else => {},
        }
    }
    return "";
}

/// Calls whatever the last user message asked for, one call per line reading
/// `RUN;;;tool;;;property=value;;;...`.
///
/// Deliberately witless: `;;;` separates and nothing escapes it, because this
/// exists to drive m8's own tool path from a test rather than to be a
/// language. Anything else in the message is said back as text.
fn runner(ctx: Ctx, mode: doc.Mode, records: []const doc.Record, model: []const u8) !u8 {
    _ = model;
    var last: []const u8 = "";
    var at: usize = 0;
    for (records, 0..) |r, i| if (r.sigil == .user) {
        last = r.content orelse "";
        at = i;
    };

    // m8 puts no cap on a model that keeps calling tools, so a model that
    // cannot tell it has already been answered would run forever. Anything
    // asked for since the last thing said has been asked for already.
    for (records[@min(at + 1, records.len)..]) |r| {
        if (r.sigil == .call) return say(ctx, mode, "Done.");
    }

    var said: std.ArrayList(u8) = .empty;
    var calls: std.ArrayList(doc.Record) = .empty;
    var n: usize = 0;

    var lines = std.mem.splitScalar(u8, last, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "RUN;;;")) {
            if (said.items.len > 0) try said.append(ctx.arena, '\n');
            try said.appendSlice(ctx.arena, line);
            continue;
        }
        var fields = std.mem.splitSequence(u8, line["RUN;;;".len..], ";;;");
        const tool = fields.next() orelse continue;

        var args: std.json.ObjectMap = .empty;
        while (fields.next()) |field| {
            const cut = std.mem.indexOfScalar(u8, field, '=') orelse continue;
            try args.put(ctx.arena, field[0..cut], .{ .string = field[cut + 1 ..] });
        }
        var json: std.Io.Writer.Allocating = .init(ctx.arena);
        try std.json.Stringify.value(std.json.Value{ .object = args }, .{}, &json.writer);

        n += 1;
        try calls.append(ctx.arena, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(ctx.arena, "{s},run-{d}", .{ tool, n }),
            .content = try @import("../../toolbox.zig").renderArgs(ctx.arena, mode, json.written()),
        });
    }

    var out: std.ArrayList(doc.Record) = .empty;
    const text = std.mem.trim(u8, said.items, "\n");
    if (text.len > 0 or calls.items.len == 0)
        try out.append(ctx.arena, .{ .sigil = .bot, .content = text });
    try out.appendSlice(ctx.arena, calls.items);

    try doc.writeAll(ctx.out, mode, out.items);
    return 0;
}

// ---------------------------------------------------------------- tests

test "every model is named once and says what it is" {
    for (models) |m| {
        try testing.expect(m.name.len > 0);
        try testing.expect(m.summary.len > 0);
    }
    for (models, 0..) |a, i| for (models[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}

test "every model it serves is on its page" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var env: std.process.Environ.Map = .init(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    try page(.{
        .arena = arena,
        .io = threaded.io(),
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &out.writer,
        .tty = null,
    }, &out.writer);

    for (models) |m| try testing.expect(std.mem.indexOf(u8, out.written(), m.name) != null);
}
