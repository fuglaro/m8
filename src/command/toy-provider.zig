//! `toy-provider` — answer the request here, with no network.
//!
//! These exist so that the loop, tool calling, and picking up a call that was
//! never answered can all be run without a model. `api: "m8"`, so the request
//! is a ledger and the response is the records it adds to one.

const std = @import("std");
const api = @import("../api.zig");
const doc = @import("../m8/doc.zig");
const ledger = @import("../ledger.zig");
const modelform = @import("../m8/model.zig");
const eliza = @import("toy-provider/eliza.zig");
const zmachine = @import("toy-provider/zmachine.zig");
const Ctx = api.Ctx;

const testing = std.testing;

pub const command: api.Command = .{
    .name = "toy-provider",
    .summary = "answer a request here, with no network",
    // The request is read from the descriptor as it arrives, not handed
    // over: `url` streams it straight back out again.
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  ... | m8 toy-provider
        \\  m8 toy-provider --models
        \\
        \\Reads a ledger on stdin and writes the turn that answers it, both as
        \\m8. The last 🧠 in the ledger names the model. `--models` prints
        \\every name that answers, one a line.
        \\
        \\models:
        \\
        \\
    );
    for (models) |m| try w.print("  {s: <16} {s}\n", .{ m.name, m.summary });
    try w.writeAll(
        \\
        \\A Z-Machine name is a story file's stem, from core/Z-Machine in a
        \\config directory.
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
/// `core/Z-Machine` reachable through it.
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
        .summary = "a story file, played as a model",
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
    if (ctx.args.len > 0 and std.mem.eql(u8, ctx.args[0], "--models")) return names(ctx);

    // m8 runs a provider with a pipe on stdin. A terminal is nobody piping a
    // request, so what was wanted is the page rather than a provider left
    // waiting for an end of file that is not coming.
    if (std.Io.File.stdin().isTty(ctx.io) catch false) {
        try ctx.err.writeAll("m8 toy-provider: no request on stdin\n");
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
        try ctx.err.writeAll("m8 toy-provider: the request names no model\n");
        try ctx.err.flush();
        return 1;
    };

    for (models) |candidate| {
        if (serves(candidate.name, m.name))
            return candidate.answer(ctx, mode, records, m.name);
    }

    try ctx.err.print("m8 toy-provider: no model named '{s}'\n", .{m.name});
    for (models) |candidate| try ctx.err.print("  /toy/{s}\n", .{candidate.name});
    // Buffered, and the process is about to end: without this the caller is
    // told a provider failed and never told why.
    try ctx.err.flush();
    return 1;
}

/// Every model there is to ask for, one a line: what an entry's `models`
/// command says. A family is the story files that are here, since those are
/// the names that answer.
fn names(ctx: Ctx) !u8 {
    for (models) |m| {
        if (!std.mem.endsWith(u8, m.name, family_mark)) {
            try ctx.out.print("{s}\n", .{m.name});
            continue;
        }
        const head = m.name[0 .. m.name.len - family_mark.len];
        for (zmachine.available(ctx) catch &.{}) |story| try ctx.out.print("{s}{s}\n", .{ head, story });
    }
    try ctx.out.flush();
    return 0;
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
            .content = try @import("../toolbox.zig").renderArgs(ctx.arena, mode, json.written()),
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
