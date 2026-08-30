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
//!
//! Both tables here — the commands, and the models `inbuilt` serves — are what
//! the pages list and what the dispatch reads, so what is advertised and what
//! answers cannot come apart.

const std = @import("std");
const config = @import("../config.zig");
const eliza = @import("providers/eliza.zig");
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
    .help = help,
};

/// One provider command. `page` is what it says about itself; `answer` is what
/// it does with a request.
const Sub = struct {
    name: []const u8,
    summary: []const u8,
    answer: *const fn (Ctx) anyerror!u8,
    page: *const fn (Ctx, *std.Io.Writer) anyerror!void,
};

const subs = [_]Sub{
    .{
        .name = "url",
        .summary = "post the request to $M8_PROVIDER_URL",
        .answer = url,
        .page = urlPage,
    },
    .{
        .name = "inbuilt",
        .summary = "answer it here, with no network",
        .answer = inbuilt,
        .page = inbuiltPage,
    },
};

fn find(name: []const u8) ?Sub {
    for (subs) |s| if (std.mem.eql(u8, s.name, name)) return s;
    return null;
}

fn run(ctx: Ctx) !u8 {
    // Naming none is somebody finding out what is here, which is a page they
    // asked for rather than a mistake.
    if (ctx.args.len == 0) {
        try help(ctx, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    const which = ctx.args[0];
    const sub = find(which) orelse {
        try ctx.err.print("m8 providers: no provider command named '{s}'\n", .{which});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    if (api.wantsHelp(ctx.args[1..])) {
        try sub.page(ctx, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    // A request arrives on stdin, and m8 runs a provider with a pipe there. A
    // terminal is nobody piping one, so what was wanted is the page rather
    // than a provider left waiting for an end of file that is not coming.
    if (std.Io.File.stdin().isTty(ctx.io) catch false) {
        try ctx.err.print("m8 providers {s}: no request on stdin\n", .{sub.name});
        try sub.page(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    return sub.answer(ctx);
}

// ------------------------------------------------------------------- pages

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    // Whatever is left names one of them: `m8 help providers url` and
    // `m8 providers url --help` are the same page.
    if (ctx.args.len > 0) {
        if (find(ctx.args[0])) |s| return s.page(ctx, w);
    }
    try w.writeAll(
        \\m8 providers — the provider commands m8 ships with
        \\
        \\  ... | m8 providers COMMAND      a request in, that api's response out
        \\  m8 providers COMMAND --help     what one reads, and what it answers
        \\
        \\A provider is a command. It reads an api-formatted request on stdin
        \\and writes that api's response on stdout — the same shape a tool has,
        \\a filter that stays in a pipeline. Reaching a url is one such command
        \\rather than the privileged path, so anything you can write a program
        \\for is a provider.
        \\
        \\commands:
        \\
        \\
    );
    for (subs) |s| try w.print("  {s: <10} {s}\n", .{ s.name, s.summary });
    try w.writeAll(
        \\
        \\An entry in core/providers.json names one as ["m8", "providers", NAME]
        \\and `api` says which codec writes the request and reads the answer.
        \\
    );
    try configured(ctx, w);
    try w.writeAll(
        \\
        \\environment:
        \\
        \\  M8_PROVIDER_API   the codec the entry named, openai-completions
        \\                    when it named none
        \\  M8_PROVIDER_*     every other string the entry said: `url` arrives
        \\                    as M8_PROVIDER_URL, `api-version` as
        \\                    M8_PROVIDER_API_VERSION. Only lowercase-and-hyphen
        \\                    keys go, because only those have a name to take,
        \\                    and `cmd` stays behind — the command already knows
        \\                    what it is.
        \\
    );
}

/// The providers this machine is configured with: what `m8 send` takes, and
/// what a 🧠 is reached through.
///
/// Which models any of them serves is not here and is not missing. That is the
/// ledger's business, written on the 🧠 that names one, so nothing in a config
/// has to be kept in step with what a provider offers. `inbuilt` is the one
/// exception, because its models are m8's own — see `m8 help providers
/// inbuilt`.
pub fn configured(ctx: Ctx, w: *std.Io.Writer) !void {
    const from = try config.coreFile(ctx.arena, ctx.io, ctx.env, "providers.json");
    try w.print("\nproviders ({s}):\n\n", .{from orelse "the copy m8 ships with"});

    const entries = config.providers(ctx.arena, ctx.io, ctx.env) catch {
        try w.writeAll("  (providers.json could not be read)\n");
        return;
    };
    if (entries.count() == 0) {
        try w.writeAll("  (none: providers.json names no provider)\n");
        return;
    }

    var it = entries.iterator();
    while (it.next()) |e| {
        const name = e.key_ptr.*;
        const p = provider.read(ctx.arena, entries, name) catch |why| {
            try w.print("  {s: <12} ({s})\n", .{ name, @errorName(why) });
            continue;
        };
        try w.print("  {s: <12} {s: <34} api: {s}\n", .{
            name,
            try std.mem.join(ctx.arena, " ", p.cmd),
            p.api,
        });
    }
}

fn urlPage(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 providers url — post the request, hand the answer back
        \\
        \\  ... | m8 providers url
        \\
        \\Posts what arrives on stdin to $M8_PROVIDER_URL and writes the
        \\response back as it arrives, in whatever size it arrives in — so a
        \\provider that streams reaches whatever is next in the pipe while the
        \\model is still saying it.
        \\
        \\There is no path m8 appends. Which api lives where is a fact about a
        \\provider rather than about a format, so the whole endpoint is the url.
        \\
        \\environment:
        \\
        \\  M8_PROVIDER_URL   the whole endpoint. Required.
        \\  M8_PROVIDER_KEY   a shell command, whose output is the bearer
        \\                    token. Optional, and nothing at all when it is
        \\                    empty or fails.
        \\
        \\The key is a command rather than a key so a config can commit safely
        \\and still reach a keychain. That is this command's convention rather
        \\than m8's — everything else the entry said arrives here too, under its
        \\own M8_PROVIDER_ name, and means whatever you make of it.
        \\
        \\An entry that names it:
        \\
        \\  "local": {
        \\    "cmd": ["m8", "providers", "url"],
        \\    "api": "openai-completions",
        \\    "url": "http://127.0.0.1:11337/v1/chat/completions",
        \\    "key": "security find-generic-password -s omlx -w"
        \\  }
        \\
    );
}

fn inbuiltPage(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 providers inbuilt — answer the request here, with no network
        \\
        \\  ... | m8 providers inbuilt
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
    for (models) |m| try w.print("  /inbuilt/{s: <10} {s}\n", .{ m.name, m.summary });
    try w.writeAll(
        \\
        \\  m8 @/inbuilt/echo -- hello
        \\  m8 @/inbuilt/you-are -- anything
        \\  m8 @/inbuilt/runner -- 'RUN;;;say;;;text=hi'
        \\  m8 @/inbuilt/eliza -- "I am not sleeping well."
        \\
        \\A 🧠 written with a leading / names a model, and what it says before
        \\its first / is the provider it is asked of. These are the only models
        \\m8 has of its own; every other one is whatever the provider you
        \\reached offers.
        \\
        \\The entry, which m8 ships with:
        \\
        \\  "inbuilt": { "cmd": ["m8", "providers", "inbuilt"], "api": "m8" }
        \\
        \\It reads nothing from the environment.
        \\
    );
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

/// One model `inbuilt` serves. There are three, they are m8's own, and they
/// exist so that the loop can be run without a network.
const Model = struct {
    name: []const u8,
    summary: []const u8,
    answer: *const fn (Ctx, doc.Mode, []const doc.Record) anyerror!u8,
};

const models = [_]Model{
    .{
        .name = "echo",
        .summary = "says the last thing anybody said, back",
        .answer = echo,
    },
    .{
        .name = "you-are",
        .summary = "\"I know you are but what am I?\", whatever you say",
        .answer = youAre,
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
};

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

    for (models) |candidate| {
        if (std.mem.eql(u8, candidate.name, m.name))
            return candidate.answer(ctx, mode, records);
    }

    try ctx.err.print("m8 providers inbuilt: no model named '{s}'\n", .{m.name});
    for (models) |candidate| try ctx.err.print("  /inbuilt/{s}\n", .{candidate.name});
    return 1;
}

fn echo(ctx: Ctx, mode: doc.Mode, records: []const doc.Record) !u8 {
    return say(ctx, mode, lastSaid(records));
}

fn youAre(ctx: Ctx, mode: doc.Mode, records: []const doc.Record) !u8 {
    _ = records;
    return say(ctx, mode, "I know you are but what am I?");
}

/// ELIZA. What she says back is decided by the last thing the person said and
/// by how many times they have spoken, both of which the ledger already holds
/// — so she keeps nothing, and a conversation with her replays exactly.
fn doctor(ctx: Ctx, mode: doc.Mode, records: []const doc.Record) !u8 {
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

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "every provider command and model is named once and says what it is" {
    for (subs) |s| {
        try testing.expect(s.name.len > 0);
        try testing.expect(s.summary.len > 0);
        try testing.expect(find(s.name) != null);
    }
    try testing.expect(find("nosuch") == null);

    for (models) |m| {
        try testing.expect(m.name.len > 0);
        try testing.expect(m.summary.len > 0);
    }
    for (models, 0..) |a, i| for (models[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}

test "the page for a provider command lists what it reads" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Nothing to find a config with, so what is listed is the copy compiled
    // in rather than whatever is on the machine running the tests.
    var env: std.process.Environ.Map = .init(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    const ctx: Ctx = .{
        .arena = arena,
        .io = threaded.io(),
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &out.writer,
        .tty = null,
    };

    try help(ctx, &out.writer);
    for (subs) |s| try testing.expect(std.mem.indexOf(u8, out.written(), s.name) != null);
    // The providers that are actually configured, which is what `send` takes.
    try testing.expect(std.mem.indexOf(u8, out.written(), "inbuilt") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_") != null);

    var url_page: std.Io.Writer.Allocating = .init(arena);
    try urlPage(ctx, &url_page.writer);
    try testing.expect(std.mem.indexOf(u8, url_page.written(), "M8_PROVIDER_URL") != null);
    try testing.expect(std.mem.indexOf(u8, url_page.written(), "M8_PROVIDER_KEY") != null);

    // Every model it serves is on the page for the command that serves them.
    var inbuilt_page: std.Io.Writer.Allocating = .init(arena);
    try inbuiltPage(ctx, &inbuilt_page.writer);
    for (models) |m|
        try testing.expect(std.mem.indexOf(u8, inbuilt_page.written(), m.name) != null);
}
