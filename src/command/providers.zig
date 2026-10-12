//! `providers` — the provider commands m8 ships with.
//!
//! A provider reads an api-formatted request on stdin and writes that api's
//! response on stdout. These two are ordinary examples of that, written as
//! commands rather than as privileged paths inside m8, which is what makes
//! reaching a url no more special than reaching anything else.
//!
//!   url       post the request, hand the answer back
//!   toy       answer it here, for trying things out and for tests
//!
//! Each is named from `core/providers.json` as `["m8", "providers", NAME]`,
//! and reads the entry's other arguments from `M8_PROVIDER_*`.
//!
//! Both tables here — the commands, and the models `toy` serves — are what
//! the pages list and what the dispatch reads, so what is advertised and what
//! answers cannot come apart.
const std = @import("std");
const build_options = @import("build_options");
const config = @import("../config.zig");
const provider = @import("../provider.zig");
const launch = @import("../launch.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "providers",
    .summary = "the provider commands m8 ships with",
    // A request arrives raw and is streamed straight back out, so nothing
    // here wants a ledger assembled for it.
    .takes = .nothing,
    .run = run,
    .help = help,
};

pub const subs = [_]api.Command{
    @import("providers/url.zig").command,
    @import("providers/toy.zig").command,
};

fn find(name: []const u8) ?api.Command {
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
    const node = @import("../command.zig").byPath(&.{ command.name, which }) orelse {
        try ctx.err.print("m8 providers: no provider command named '{s}'\n", .{which});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    if (launch.split)
        return launch.under(ctx, .{ .spawn = node.program }, ctx.args[1..], .inherited);

    var inner = ctx;
    inner.args = ctx.args[1..];

    // The flag is m8's wherever it is written. What was named out here was
    // `providers`; the word after a provider command is that command's.
    if (api.wantsHelp(inner.args)) {
        inner.args = inner.args[1..];
        try @import("help.zig").write(inner, find(which).?, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    return find(which).?.run(inner);
}

// ------------------------------------------------------------------- pages

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
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
    // Read off the tree: saying what m8 ships is not a reason to hold the
    // one of them that carries a Z-machine.
    for (@import("../command.zig").byPath(&.{command.name}).?.children) |n|
        try w.print("  {s: <10} {s}\n", .{ n.spec.name, n.spec.summary });
    try w.writeAll(
        \\
        \\An entry in core/providers.json names one as its `cmd`:
        \\["m8", "providers", NAME]. It is handed the ledger as m8 and answers
        \\with the turn as m8, unless the entry names two more commands:
        \\
        \\  encode   makes the ledger a request, as ["m8", "encode", FORMAT]
        \\  parse    makes the answer a turn, as ["m8", "parse", FORMAT]
        \\
        \\The three are one pipeline. What each says on stderr is passed on
        \\once the turn is in, or given as the reason when one fails.
        \\
    );
    try configured(ctx, w);
    try w.writeAll(
        \\
        \\environment:
        \\
        \\  M8_VERBOSITY      1 under `-v` and 2 under `-vv`: how much to say
        \\                    on stderr. It is inherited, so an m8 started
        \\                    under one says as much without being asked
        \\  M8_PROVIDER_*     every string the entry said: `url` arrives
        \\                    as M8_PROVIDER_URL, `api-version` as
        \\                    M8_PROVIDER_API_VERSION. Only lowercase-and-hyphen
        \\                    keys go, because only those have a name to take,
        \\                    and the commands stay behind — each already
        \\                    knows what it is.
        \\
    );
}

/// The providers this machine is configured with: what `m8 send` takes, and
/// what a 🧠 is reached through.
///
/// Which models any of them serves is not here and is not missing. That is the
/// ledger's business, written on the 🧠 that names one, so nothing in a config
/// has to be kept in step with what a provider offers. `toy` is the one
/// exception, because its models are m8's own — see `m8 providers toy
/// --help`.
pub fn configured(ctx: Ctx, w: *std.Io.Writer) !void {
    const from = try config.coreFiles(ctx.arena, ctx.io, ctx.env, "providers.json");
    try w.writeAll("\nproviders, nearest first:\n\n");
    for (from) |path| try w.print("  {s}\n", .{path});
    if (from.len > 0) try w.writeAll("\n");

    const entries = config.providers(ctx.arena, ctx.io, ctx.env) catch {
        try w.writeAll("  (providers.json could not be read)\n");
        return;
    };
    if (entries.count() == 0) {
        try w.writeAll("  (none: no core/providers.json names a provider)\n");
        return;
    }

    var it = entries.iterator();
    while (it.next()) |e| {
        const name = e.key_ptr.*;
        const p = provider.read(ctx.arena, entries, name) catch |why| {
            try w.print("  {s: <12} ({s})\n", .{ name, @errorName(why) });
            continue;
        };
        try w.print("  {s: <12} {s}\n", .{ name, try std.mem.join(ctx.arena, " ", p.cmd) });
        if (p.encode) |c| try w.print("  {s: <12}   encode: {s}\n", .{ "", try std.mem.join(ctx.arena, " ", c) });
        if (p.parse) |c| try w.print("  {s: <12}   parse:  {s}\n", .{ "", try std.mem.join(ctx.arena, " ", c) });
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the page for a provider command lists what it reads" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

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
    try testing.expect(std.mem.indexOf(u8, out.written(), "providers, nearest first") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_") != null);

    var url_page: std.Io.Writer.Allocating = .init(arena);
    try @import("providers/url.zig").command.help.?(ctx, &url_page.writer);
    try testing.expect(std.mem.indexOf(u8, url_page.written(), "M8_PROVIDER_URL") != null);
    try testing.expect(std.mem.indexOf(u8, url_page.written(), "M8_PROVIDER_HEADER_") != null);
    if (build_options.no_curl_dep) {
        try testing.expect(std.mem.indexOf(u8, url_page.written(), "standard-library HTTP client") != null);
    } else {
        try testing.expect(std.mem.indexOf(u8, url_page.written(), "`curl`") != null);
    }
}
