//! `url-provider` — post the request to a url.
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
const provider = @import("../provider.zig");
const Ctx = api.Ctx;

/// The default keeps the provider tiny and delegates TLS, certificates, proxy
/// support and HTTP to the curl already installed on the machine. The other
/// branch is selected while compiling, so an executable contains only one
/// transport.
const no_curl_dep = build_options.no_curl_dep;

pub const command: api.Command = .{
    .name = "url-provider",
    .summary = "post a request to $M8_PROVIDER_URL",
    // The request is read from the descriptor as it arrives, not handed
    // over: `url` streams it straight back out again.
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  ... | m8 url-provider
        \\  m8 url-provider --get URL
        \\
        \\Posts stdin to $M8_PROVIDER_URL as JSON and writes the response to
        \\stdout as it arrives. `--get URL` sends a GET to URL instead, with
        \\the same headers, and reads no stdin.
        \\
        \\A response is passed on whatever its status. Only a url that cannot
        \\be reached is a failure.
        \\
        \\environment:
        \\
        \\  M8_PROVIDER_URL          the endpoint to post to
        \\  M8_PROVIDER_HEADER_NAME  a shell command whose output is sent as
        \\                           header NAME: HEADER_X_API_KEY is x-api-key.
        \\                           One that fails or prints nothing is left off.
        \\
    );
    try w.writeAll(if (comptime no_curl_dep)
        "\nThis build carries its own HTTP client.\n"
    else
        "\nNeeds `curl` on PATH.\n");
}

/// Post the request and hand the answer back as it arrives.
///
/// `M8_PROVIDER_URL` is the whole endpoint. There is no path m8 appends to
/// it: which api lives where is a fact about a provider, not about a format,
/// and keeping a table of those is not something m8 does.
///
/// Every `M8_PROVIDER_HEADER_*` is run as a shell command and its output is
/// that header's value. That is this command's convention rather than m8's,
/// and it is a command so that a config can commit safely and still reach a
/// keychain. A bearer token, an api version and a beta flag are all headers,
/// so there is one rule here rather than a field per vendor habit.
fn run(ctx: Ctx) !u8 {
    // Asking rather than posting: the url is said here, because the entry's
    // own is where requests go, and nothing is read from stdin.
    if (ctx.args.len > 0 and std.mem.eql(u8, ctx.args[0], "--get")) {
        if (ctx.args.len != 2) {
            try ctx.err.writeAll("m8 url-provider: --get takes one url\n");
            return 1;
        }
        if (comptime no_curl_dep) return runStdlib(ctx, ctx.args[1], .GET);
        return runCurl(ctx, ctx.args[1], true);
    }

    // m8 runs a provider with a pipe on stdin. A terminal is nobody piping a
    // request, so what was wanted is the page rather than a provider left
    // waiting for an end of file that is not coming.
    if (std.Io.File.stdin().isTty(ctx.io) catch false) {
        try ctx.err.writeAll("m8 url-provider: no request on stdin\n");
        try page(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    const endpoint = ctx.env.get(provider.env_prefix ++ "URL") orelse {
        try ctx.err.writeAll("m8 url-provider: no " ++ provider.env_prefix ++ "URL\n");
        return 1;
    };

    // This is a comptime choice, not a runtime mode. In particular, the
    // curl build never references std.http.Client and the stdlib build never
    // carries the curl command line or its curl-spawn path.
    if (comptime no_curl_dep) return runStdlib(ctx, endpoint, .POST);
    return runCurl(ctx, endpoint, false);
}

/// The no-curl transport. The stdlib client owns TLS and certificate lookup,
/// which is the useful tradeoff for a self-contained binary. Keep this
/// deliberately behind the comptime branch above: std.http is a substantial
/// dependency and should not affect the default curl build.
fn runStdlib(ctx: Ctx, endpoint: []const u8, method: std.http.Method) !u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(ctx.io, &in_buf);
    const request_body: []const u8 = if (method == .POST)
        try input.interface.allocRemaining(ctx.arena, .unlimited)
    else
        "";

    var extra: std.ArrayList(std.http.Header) = .empty;
    try headersStdlib(ctx, &extra);

    var client: std.http.Client = .{ .allocator = ctx.arena, .io = ctx.io };
    defer client.deinit();

    const uri = std.Uri.parse(endpoint) catch {
        try ctx.err.print("m8 url-provider: '{s}' is not a url\n", .{endpoint});
        return 1;
    };

    // No encoding is asked for, as curl asks for none: what comes back is
    // passed on as it is, and nothing here would undo a compressed body.
    var req = client.request(method, uri, .{
        .headers = .{
            .content_type = if (method == .POST) .{ .override = "application/json" } else .default,
            .accept_encoding = .omit,
        },
        .extra_headers = extra.items,
    }) catch |e| {
        try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
        return 1;
    };
    defer req.deinit();

    (if (method == .POST) req.sendBodyComplete(@constCast(request_body)) else req.sendBodiless()) catch |e| {
        try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
        return 1;
    };

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch |e| {
        try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
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
fn runCurl(ctx: Ctx, endpoint: []const u8, get: bool) !u8 {
    var lines: std.ArrayList(u8) = .empty;
    try headers(ctx, &lines);

    const environ = try api.childEnvironment(ctx.arena, ctx, &.{.{ .key = headers_var, .value = lines.items }});

    // curl reads the request from the stdin it inherits and writes the answer
    // to the stdout it inherits, so nothing passes through here on the way
    // and a stream stays one: `-N` hands on what has arrived rather than
    // what would round out a buffer.
    //
    // No `--fail`. A status that is not 200 still has a body, and the body is
    // what the api said — the codec reads it as it reads any other answer.
    // What is left to fail is the reaching itself, which curl says on stderr.
    var child = std.process.spawn(ctx.io, .{
        .argv = &.{ "sh", "-c", if (get) get_script else script, "m8 url-provider", endpoint },
        .environ_map = environ,
        .stdin = if (get) .ignore else .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |e| {
        try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
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
    \\exec curl -sS -N -H 'content-type: application/json' -H @/dev/fd/3 --data-binary @- "$1"
++ heredoc;

/// The same, asking rather than posting: no body, so nothing says what one is.
const get_script =
    \\exec curl -sS -N -H @/dev/fd/3 "$1"
++ heredoc;

const heredoc =
    \\ 3<<M8_END
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

test "the page names what it reads" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    var env: std.process.Environ.Map = .init(a.allocator());
    var out: std.Io.Writer.Allocating = .init(a.allocator());
    const ctx: Ctx = .{
        .arena = a.allocator(),
        .io = undefined,
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &out.writer,
        .tty = null,
    };
    try page(ctx, &out.writer);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_URL") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_HEADER_") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), if (no_curl_dep) "own HTTP client" else "`curl`") != null);
}
