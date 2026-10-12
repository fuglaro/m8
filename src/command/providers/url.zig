//! `providers url` — post the request to a url.
//!
//! The one provider command that reaches a network, and it is a command like
//! any other rather than the privileged path: it reads a request on stdin and
//! writes the response on stdout, and everything it needs arrives in its
//! environment.
//!
//! By default the reaching is curl's. TLS, certificates, proxies and http
//! itself are what curl is for and what a distribution already keeps patched,
//! so none of it is carried here. A no-curl build selects the standard-library
//! HTTP client instead, without changing the provider's stdin/stdout shape.

const std = @import("std");
const build_options = @import("build_options");
const api = @import("../api.zig");
const provider = @import("../../provider.zig");
const Ctx = api.Ctx;

/// The default keeps the provider tiny and delegates TLS, certificates, proxy
/// support and HTTP to the curl already installed on the machine. The other
/// branch is selected while compiling, so an executable contains only one
/// transport.
const no_curl_dep = build_options.no_curl_dep;

pub const command: api.Command = .{
    .name = "url",
    .summary = "post the request to $M8_PROVIDER_URL",
    // The request is read from the descriptor as it arrives, not handed
    // over: `url` streams it straight back out again.
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
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
    );
    if (comptime no_curl_dep) {
        try w.writeAll(
            \\The posting is done by m8's Zig standard-library HTTP client, so
            \\this build does not need curl. Whatever the api answers is passed
            \\on, an error as much as a reply; only a url that could not be
            \\reached at all is a failure here.
            \\
        );
    } else {
        try w.writeAll(
            \\The posting is done by `curl`, which has to be on PATH. Whatever
            \\the api answers is passed on, an error as much as a reply; only a
            \\url that could not be reached at all is a failure here.
            \\
        );
    }
    try w.writeAll(
        \\
        \\There is no path m8 appends. Which api lives where is a fact about a
        \\provider rather than about a format, so the whole endpoint is the url.
        \\
        \\environment:
        \\
        \\  M8_PROVIDER_URL       the whole endpoint. Required.
        \\  M8_PROVIDER_HEADER_*  one per header. Each is a shell command,
        \\                        and its output is that header's value.
        \\                        Optional, and a command that fails or says
        \\                        nothing leaves its header off.
        \\
        \\A header is named by the entry key it came from, so `header-x-api-key`
        \\arrives as M8_PROVIDER_HEADER_X_API_KEY and goes out as `x-api-key`.
        \\
        \\Each is a command rather than a value so a config can commit safely and
        \\still reach a keychain; a constant is `echo`. That is this command's
        \\convention rather than m8's — everything else the entry said arrives
        \\here too, under its own M8_PROVIDER_ name, and means whatever you make
        \\of it.
        \\
        \\A bearer token, an api version and a beta flag are all just headers,
        \\and not one of them is a format's business — which is the same reason
        \\there is no path m8 appends to a url.
        \\
        \\Two entries that name it:
        \\
        \\  "local": {
        \\    "cmd": ["m8", "providers", "url"],
        \\    "encode": ["m8", "encode", "openai-completions"],
        \\    "parse": ["m8", "parse", "openai-completions"],
        \\    "url": "http://127.0.0.1:11337/v1/chat/completions",
        \\    "header-authorization": "echo Bearer $(security find-generic-password -s omlx -w)"
        \\  }
        \\
        \\  "anthropic": {
        \\    "cmd": ["m8", "providers", "url"],
        \\    "encode": ["m8", "encode", "anthropic-messages"],
        \\    "parse": ["m8", "parse", "anthropic-messages"],
        \\    "url": "https://api.anthropic.com/v1/messages",
        \\    "header-anthropic-version": "echo 2023-06-01",
        \\    "header-x-api-key": "security find-generic-password -s anthropic-api-key -w"
        \\  }
        \\
    );
}

/// Post the request and hand the answer back as it arrives.
///
/// `M8_PROVIDER_URL` is the whole endpoint. There is no path m8 appends to
/// it: which api lives where is a fact about a provider, not about a format,
/// and keeping a table of those is the sort of thing m8 stopped doing when
/// `models` left providers.json.
///
/// Every `M8_PROVIDER_HEADER_*` is run as a shell command and its output is
/// that header's value. That is this command's convention rather than m8's,
/// and it is a command so that a config can commit safely and still reach a
/// keychain. A bearer token, an api version and a beta flag are all headers,
/// so there is one rule here rather than a field per vendor habit.
fn run(ctx: Ctx) !u8 {
    // m8 runs a provider with a pipe on stdin. A terminal is nobody piping a
    // request, so what was wanted is the page rather than a provider left
    // waiting for an end of file that is not coming.
    if (std.Io.File.stdin().isTty(ctx.io) catch false) {
        try ctx.err.writeAll("m8 providers url: no request on stdin\n");
        try page(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    const endpoint = ctx.env.get(provider.env_prefix ++ "URL") orelse {
        try ctx.err.writeAll("m8 providers url: no " ++ provider.env_prefix ++ "URL\n");
        return 1;
    };

    // This is a comptime choice, not a runtime mode. In particular, the
    // curl build never references std.http.Client and the stdlib build never
    // carries the curl command line or its curl-spawn path.
    if (comptime no_curl_dep) return runStdlib(ctx, endpoint);
    return runCurl(ctx, endpoint);
}

/// The no-curl transport. The stdlib client owns TLS and certificate lookup,
/// which is the useful tradeoff for a self-contained binary. Keep this
/// deliberately behind the comptime branch above: std.http is a substantial
/// dependency and should not affect the default curl build.
fn runStdlib(ctx: Ctx, endpoint: []const u8) !u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(ctx.io, &in_buf);
    const request_body = try input.interface.allocRemaining(ctx.arena, .unlimited);

    var extra: std.ArrayList(std.http.Header) = .empty;
    try headersStdlib(ctx, &extra);

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

    req.sendBodyComplete(@constCast(request_body)) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };

    // A non-200 response still contains the api's explanation. Passing its
    // body through is part of the provider contract, just as it is in curl.
    var transfer_buf: [64 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buf);
    while (true) {
        reader.fill(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const chunk = reader.buffered();
        ctx.out.writeAll(chunk) catch return 0;
        ctx.out.flush() catch return 0;
        reader.toss(chunk.len);
    }
    return 0;
}

/// The default transport. curl keeps TLS, certificates, proxies and HTTP out
/// of the executable, which is why it is the small build.
fn runCurl(ctx: Ctx, endpoint: []const u8) !u8 {
    var lines: std.ArrayList(u8) = .empty;
    try headers(ctx, &lines);

    var environ = try ctx.env.clone(ctx.arena);
    try environ.put(headers_var, lines.items);

    // curl reads the request from the stdin it inherits and writes the answer
    // to the stdout it inherits, so nothing passes through here on the way
    // and a stream stays one: `-N` hands on what has arrived rather than
    // what would round out a buffer.
    //
    // No `--fail`. A status that is not 200 still has a body, and the body is
    // what the api said — the codec reads it as it reads any other answer.
    // What is left to fail is the reaching itself, which curl says on stderr.
    var child = std.process.spawn(ctx.io, .{
        .argv = &.{ "sh", "-c", script, "m8 providers url", endpoint },
        .environ_map = &environ,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |e| {
        try ctx.err.print("m8 providers url: {s}\n", .{@errorName(e)});
        return 1;
    };
    return switch (child.wait(ctx.io) catch return 1) {
        .exited => |code| code,
        else => 1,
    };
}

/// Where the header lines wait between here and curl.
const headers_var = "M8_PROVIDER_URL_HEADERS";

/// The curl command line.
///
/// Headers reach curl as a file on descriptor 3 rather than as arguments: an
/// argument is in `ps` for every user on the machine, and one of these is a
/// key.
const script =
    \\exec curl -sS -N -H 'content-type: application/json' -H @/dev/fd/3 --data-binary @- "$1" 3<<M8_END
    \\$
++ headers_var ++
    \\
    \\M8_END
    \\
;

/// Collect the same configured headers for the stdlib client's typed header
/// list. This is separate from the curl wire format so each comptime build
/// only keeps the representation its transport uses.
fn headersStdlib(ctx: Ctx, into: *std.ArrayList(std.http.Header)) !void {
    const prefix = provider.env_prefix ++ "HEADER_";
    var it = ctx.env.iterator();
    while (it.next()) |e| {
        const named = e.key_ptr.*;
        if (!std.mem.startsWith(u8, named, prefix)) continue;
        const value = (try ran(ctx, e.value_ptr.*)) orelse continue;
        try into.append(ctx.arena, .{
            .name = try headerName(ctx, named[prefix.len..]),
            .value = value,
        });
    }
}

/// Where the key goes, and in what.
///
/// `authorization` carries a bearer token, because that is what a bearer
/// token is; any other header the entry names carries the key as it is. One
/// api's key is another's `x-api-key`, and which it is belongs to the entry
/// that knows the endpoint rather than to a table in here.
/// Every header the entry asked for, each one a command.
///
/// `header-x-api-key` arrives here as `M8_PROVIDER_HEADER_X_API_KEY`, and
/// what it says is run: its output is the value. One rule rather than three —
/// a bearer token, an api version, a beta flag and a tenant are all headers,
/// and the only thing they have in common is that not one of them is a
/// format's business. So none of them is known about here; they are written
/// down beside the url that needs them.
///
/// A command rather than a value, which is the whole reason a key was ever
/// one: a config can commit safely and still reach a keychain. A constant is
/// `echo` and costs a fork nobody will notice beside a model call.
fn headers(ctx: Ctx, into: *std.ArrayList(u8)) !void {
    const prefix = provider.env_prefix ++ "HEADER_";
    var it = ctx.env.iterator();
    while (it.next()) |e| {
        const named = e.key_ptr.*;
        if (!std.mem.startsWith(u8, named, prefix)) continue;
        const value = (try ran(ctx, e.value_ptr.*)) orelse continue;
        try into.print(ctx.arena, "{s}: {s}\n", .{ try headerName(ctx, named[prefix.len..]), value });
    }
}

/// `X_API_KEY` is `x-api-key`. An environment variable cannot hold a hyphen,
/// so the one the entry was written with is put back.
fn headerName(ctx: Ctx, named: []const u8) ![]const u8 {
    const out = try ctx.arena.alloc(u8, named.len);
    for (named, 0..) |c, i| out[i] = if (c == '_') '-' else std.ascii.toLower(c);
    return out;
}

/// What a header's command said, or null when it said nothing worth sending.
///
/// A command that fails or answers with nothing leaves its header off
/// entirely, so a machine with no key configured still reaches a provider
/// that wants none. Its stderr is passed on, which is how it says what to do. Every plausible command ends in a newline, and a value
/// still holding one after trimming is header injection rather than a header,
/// so it is dropped.
fn ran(ctx: Ctx, cmd: []const u8) !?[]const u8 {
    if (cmd.len == 0) return null;

    const r = std.process.run(ctx.arena, ctx.io, .{
        .argv = &.{ "sh", "-c", cmd },
    }) catch return null;
    // What the command complained about is for whoever is setting it up.
    ctx.err.writeAll(r.stderr) catch {};
    ctx.err.flush() catch {};
    switch (r.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    const value = std.mem.trim(u8, r.stdout, " \t\r\n");
    if (value.len == 0) return null;
    if (std.mem.indexOfAny(u8, value, "\r\n") != null) return null;
    return value;
}

// ---------------------------------------------------------------- inbuilt
