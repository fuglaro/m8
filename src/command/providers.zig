//! `providers` — the provider commands m8 ships with.
//!
//! A provider reads an api-formatted request on stdin and writes that api's
//! response on stdout. These two are ordinary examples of that, written as
//! commands rather than as privileged paths inside m8, which is what makes
//! reaching a url no more special than reaching anything else.
//!
//!   url       post the request, hand the answer back
//!   inbuilt   answer it here, for trying things out and for tests
//!
//! Each is named from `core/providers.json` as `["m8", "providers", NAME]`,
//! and reads the entry's other arguments from `M8_PROVIDER_*`.

const std = @import("std");
const provider = @import("../provider.zig");
const doc = @import("../m8/doc.zig");
const ledger = @import("../ledger.zig");
const modelform = @import("../m8/model.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "providers",
    .summary = "the provider commands m8 ships with",
    // The request arrives raw, and for `url` it is streamed straight back
    // out, so nothing here wants a ledger assembled for it.
    .takes = .nothing,
    .run = run,
};

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) return usage(ctx);
    const which = ctx.args[0];
    if (std.mem.eql(u8, which, "url")) return url(ctx);
    if (std.mem.eql(u8, which, "inbuilt")) return inbuilt(ctx);
    try ctx.err.print("m8 providers: no provider command named '{s}'\n", .{which});
    return usage(ctx);
}

fn usage(ctx: Ctx) !u8 {
    try ctx.err.writeAll(
        \\m8 providers — read a request on stdin, write that api's response
        \\
        \\  m8 providers url       post it to $M8_PROVIDER_URL
        \\  m8 providers inbuilt   answer it here
        \\
        \\Named from core/providers.json as ["m8", "providers", NAME].
        \\
    );
    try ctx.err.flush();
    return 1;
}

// -------------------------------------------------------------------- url

/// Post the request and hand the answer back as it arrives.
///
/// `M8_PROVIDER_URL` is the whole endpoint. There is no path m8 appends to
/// it: which api lives where is a fact about a provider, not about a format,
/// and keeping a table of those is the sort of thing m8 stopped doing when
/// `models` left providers.json.
///
/// `M8_PROVIDER_KEY` is run as a shell command and its output is the bearer
/// token. That is this command's convention rather than m8's — the key is
/// passed through untouched and means whatever the provider it reaches makes
/// of it — and it is a command so that a config can commit safely and still
/// reach a keychain.
fn url(ctx: Ctx) !u8 {
    const endpoint = ctx.env.get(provider.env_prefix ++ "URL") orelse {
        try ctx.err.writeAll("m8 providers url: no " ++ provider.env_prefix ++ "URL\n");
        return 1;
    };

    var in_buf: [64 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &in_buf);
    const request = try in.interface.allocRemaining(ctx.arena, .unlimited);

    var extra: std.ArrayList(std.http.Header) = .empty;
    if (try bearer(ctx)) |token| try extra.append(ctx.arena, .{
        .name = "authorization",
        .value = try std.fmt.allocPrint(ctx.arena, "Bearer {s}", .{token}),
    });

    var client: std.http.Client = .{ .allocator = ctx.arena, .io = ctx.io };
    defer client.deinit();

    const uri = std.Uri.parse(endpoint) catch {
        try ctx.err.print("m8 providers url: '{s}' is not a url\n", .{endpoint});
        return 1;
    };

    var req = client.request(.POST, uri, .{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = extra.items,
    }) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = request.len };
    req.sendBodyComplete(@constCast(request)) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };
    if (response.head.status != .ok) {
        try ctx.err.print("m8 providers url: {s} answered {d}\n", .{
            endpoint,
            @intFromEnum(response.head.status),
        });
        return 1;
    }

    // Passed through as whatever arrives, in whatever size it arrives in.
    //
    // `fill(1)` waits for a byte and no more, so what is handed on is what
    // has actually turned up rather than what would round out a buffer.
    // `readSliceShort` is only short at the end of a stream — it fills first
    // — so using it here would hold a reply back until it was over, which is
    // a stream that only looks like one.
    var transfer_buf: [64 * 1024]u8 = undefined;
    const r = response.reader(&transfer_buf);
    while (true) {
        r.fill(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const chunk = r.buffered();
        // Whoever was reading has stopped — `| head` and the like. That is
        // their business, not a failure of ours.
        ctx.out.writeAll(chunk) catch return 0;
        ctx.out.flush() catch return 0;
        r.toss(chunk.len);
    }
    return 0;
}

fn bearer(ctx: Ctx) !?[]const u8 {
    const cmd = ctx.env.get(provider.env_prefix ++ "KEY") orelse return null;
    if (cmd.len == 0) return null;

    const r = std.process.run(ctx.arena, ctx.io, .{
        .argv = &.{ "sh", "-c", cmd },
    }) catch return null;
    switch (r.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    // Every plausible command ends in a newline, and a newline in an
    // Authorization header is rejected as header injection by anything that
    // checks.
    const key = std.mem.trim(u8, r.stdout, " \t\r\n");
    return if (key.len == 0) null else key;
}

// ---------------------------------------------------------------- inbuilt

/// Answer the request here. `api: "m8"`, so the request is a ledger and the
/// response is the records it adds to one.
///
/// These exist so that the loop, tool calling, and picking up a call that was
/// never answered can all be run without a model — which is what makes them
/// testable rather than only demonstrable.
fn inbuilt(ctx: Ctx) !u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &in_buf);
    const request = try in.interface.allocRemaining(ctx.arena, .unlimited);

    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, request, &diag);
    const mode = doc.detect(request) orelse .md;

    const m = (try ledger.runsOn(ctx.arena, records)) orelse {
        try ctx.err.writeAll("m8 providers inbuilt: the request names no model\n");
        return 1;
    };

    if (std.mem.eql(u8, m.name, "echo")) return say(ctx, mode, lastSaid(records));
    if (std.mem.eql(u8, m.name, "you-are"))
        return say(ctx, mode, "I know you are but what am I?");
    if (std.mem.eql(u8, m.name, "runner")) return runner(ctx, mode, records);

    try ctx.err.print("m8 providers inbuilt: no model named '{s}'\n", .{m.name});
    return 1;
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
fn runner(ctx: Ctx, mode: doc.Mode, records: []const doc.Record) !u8 {
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
