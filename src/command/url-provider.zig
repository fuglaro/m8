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
const stats = @import("url-provider/stats.zig");
const Ctx = api.Ctx;

/// The default keeps the provider tiny and delegates TLS, certificates, proxy
/// support and HTTP to the curl already installed on the machine. The other
/// branch is selected while compiling, so an executable contains only one
/// transport.
const no_curl_dep = build_options.no_curl_dep;

pub const command: api.Command = .{
    .name = "url-provider",
    .summary = "post a request to $M8_PROVIDER_url",
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
        \\  m8 url-provider --upload URL FILE [NAME=VALUE]...
        \\
        \\Posts stdin to $M8_PROVIDER_url as JSON and writes the response to
        \\stdout as it arrives. `--get URL` sends a GET to URL instead, with
        \\the same headers, and reads no stdin. `--upload` posts FILE to URL
        \\as a form, its field `file`, with each NAME=VALUE as a field beside
        \\it.
        \\
        \\A response is passed on whatever its status. A 429 with a valid
        \\Retry-After is the exception: wait as directed and replay once,
        \\discarding the first response. There is no fallback backoff.
        \\Only a url that cannot be reached is a failure.
        \\
        \\environment:
        \\
        \\  M8_PROVIDER_url          a JSON argv array; its stdout is the endpoint
        \\                           e.g. ["echo","https://example.com/v1/messages"].
        \\                           Empty or failing commands are an error.
        \\  M8_PROVIDER_header_NAME  a JSON argv array; its stdout is sent as
        \\                           header NAME: ["sh","-c",...] opts into a shell.
        \\                           Empty or failing commands leave it off.
        \\  M8_PROVIDER_stats        JSON: {"headers":[...],"body":[...],"cmd":[...]}
        \\                           Select response values for a formatter at EOF.
        \\                           Its stdout goes to stderr; the body still streams.
        \\
    );
    try w.writeAll(if (comptime no_curl_dep)
        "\nThis build carries its own HTTP client.\n"
    else
        "\nNeeds `curl` on PATH.\n");
}

/// Post the request and hand the answer back as it arrives.
///
/// `M8_PROVIDER_url` is a JSON argv command whose stdout is the whole endpoint.
/// There is no path m8 appends to it: which api lives where is a fact about a
/// provider, not about a format, and keeping a table of those is not something
/// m8 does. Constants use `echo`; environment values can use `printenv`.
///
/// Every `M8_PROVIDER_header_*` is decoded as a JSON argv array and its
/// output is that header's value. An explicit `sh -c` array opts into shell
/// behavior. This is this command's convention rather than m8's, and it is a
/// command so a config can commit safely and still reach a keychain.
fn run(ctx: Ctx) !u8 {
    // Asking rather than posting: the url is said here, because the entry's
    // own is where requests go, and nothing is read from stdin.
    if (ctx.args.len > 0 and std.mem.eql(u8, ctx.args[0], "--get")) {
        if (ctx.args.len != 2) {
            try ctx.err.writeAll("m8 url-provider: --get takes one url\n");
            return 1;
        }
        if (comptime no_curl_dep) return runStdlib(ctx, ctx.args[1], null, "");
        return runCurl(ctx, &.{ get_script, "m8 url-provider", ctx.args[1] }, false);
    }
    // Handing over a file, as a form.
    if (ctx.args.len > 0 and std.mem.eql(u8, ctx.args[0], "--upload")) {
        if (ctx.args.len < 3) {
            try ctx.err.writeAll("m8 url-provider: --upload takes a url and a file\n");
            return 1;
        }
        if (comptime no_curl_dep) {
            var random: [12]u8 = undefined;
            ctx.io.random(&random);
            const boundary = try std.fmt.allocPrint(ctx.arena, "m8-{x}", .{&random});
            const bytes = try std.Io.Dir.cwd().readFileAlloc(ctx.io, ctx.args[2], ctx.arena, .unlimited);
            return runStdlib(
                ctx,
                ctx.args[1],
                try form(ctx.arena, boundary, std.fs.path.basename(ctx.args[2]), bytes, ctx.args[3..]),
                try std.fmt.allocPrint(ctx.arena, "multipart/form-data; boundary={s}", .{boundary}),
            );
        }
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(ctx.arena, &.{ upload_script, "m8 url-provider" });
        try argv.appendSlice(ctx.arena, ctx.args[1..]);
        return runCurl(ctx, argv.items, false);
    }

    // m8 runs a provider with a pipe on stdin. A terminal is nobody piping a
    // request, so what was wanted is the page rather than a provider left
    // waiting for an end of file that is not coming.
    if (ctx.stdin_terminal) {
        try ctx.err.writeAll("m8 url-provider: no request on stdin\n");
        try page(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }

    const endpoint_command = ctx.env.get(provider.env_prefix ++ "url") orelse {
        try ctx.err.writeAll("m8 url-provider: no M8_PROVIDER_url\n");
        return 1;
    };
    const endpoint = (try ranCommand(ctx, endpoint_command, "url")) orelse {
        try ctx.err.writeAll("m8 url-provider: url command failed or produced no valid endpoint\n");
        return 1;
    };

    // This is a comptime choice, not a runtime mode. In particular, the
    // curl build never references std.http.Client and the stdlib build never
    // carries the curl command line or its curl-spawn path.
    if (comptime no_curl_dep) {
        const input = ctx.stdin orelse return runStdlib(ctx, endpoint, "", "application/json");
        return runStdlib(ctx, endpoint, try input.allocRemaining(ctx.arena, .unlimited), "application/json");
    }
    return runCurl(ctx, &.{ script, "m8 url-provider", endpoint }, true);
}

/// The no-curl transport. The stdlib client owns TLS and certificate lookup,
/// which is the useful tradeoff for a self-contained binary. Keep this
/// deliberately behind the comptime branch above: std.http is a substantial
/// dependency and should not affect the default curl build.
///
/// `body` is posted as `content_type`; with none, it is a GET.
fn runStdlib(ctx: Ctx, endpoint: []const u8, body: ?[]const u8, content_type: []const u8) !u8 {
    const method: std.http.Method = if (body == null) .GET else .POST;
    var extra: std.ArrayList(std.http.Header) = .empty;
    try headersStdlib(ctx, &extra);

    var client: std.http.Client = .{ .allocator = ctx.arena, .io = ctx.io };
    defer client.deinit();

    const uri = std.Uri.parse(endpoint) catch {
        try ctx.err.print("m8 url-provider: '{s}' is not a url\n", .{endpoint});
        return 1;
    };

    var retried = false;
    while (true) {
        // No encoding is asked for, as curl asks for none: what comes back is
        // passed on as it is, and nothing here would undo a compressed body.
        var req = client.request(method, uri, .{
            .headers = .{
                .content_type = if (body != null) .{ .override = content_type } else .default,
                .accept_encoding = .omit,
            },
            .extra_headers = extra.items,
        }) catch |e| {
            try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
            return 1;
        };
        defer req.deinit();

        (if (body) |b| req.sendBodyComplete(@constCast(b)) else req.sendBodiless()) catch |e| {
            try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
            return 1;
        };

        var redirect_buf: [8192]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch |e| {
            try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
            return 1;
        };

        var retry_seconds: ?u64 = null;
        if (!retried and @intFromEnum(response.head.status) == 429) {
            var it = response.head.iterateHeaders();
            while (it.next()) |h| {
                if (std.ascii.eqlIgnoreCase(h.name, "retry-after")) {
                    retry_seconds = retryAfterSeconds(h.value, std.Io.Timestamp.now(ctx.io, .real).toSeconds());
                    if (retry_seconds != null) break;
                }
            }
        }

        const settings = if (retry_seconds == null) stats.load(ctx) else null;
        var response_headers: std.Io.Writer.Allocating = .init(ctx.arena);
        if (settings) |s| if (s.headers.len > 0) {
            var it = response.head.iterateHeaders();
            while (it.next()) |h| try response_headers.writer.print("{s}: {s}\n", .{ h.name, h.value });
        };

        // A non-200 response still contains the api's explanation. Passing its
        // body through is part of the provider contract, just as it is in curl.
        var response_body: std.ArrayList(u8) = .empty;
        var transfer_buf: [64 * 1024]u8 = undefined;
        const reader = response.reader(&transfer_buf);
        const output = if (retry_seconds != null) ctx.err else ctx.out;
        var last_byte: u8 = '\n';
        while (true) {
            reader.fill(1) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
            const chunk = reader.buffered();
            output.writeAll(chunk) catch return 0;
            output.flush() catch return 0;
            last_byte = chunk[chunk.len - 1];
            if (settings) |s| if (s.body.len > 0) try response_body.appendSlice(ctx.arena, chunk);
            reader.toss(chunk.len);
        }
        if (retry_seconds) |seconds| {
            if (last_byte != '\n') try ctx.err.writeAll("\n");
            try waitToRetry(ctx, seconds);
            retried = true;
            continue;
        }
        if (settings) |s| stats.finish(ctx, s, response_headers.written(), response_body.items);
        return 0;
    }
}

/// Date-shaped values use only MM:SS, ignoring the calendar date and hour.
/// Interpret them within this hour: up to five minutes behind is already due;
/// otherwise wait forward (less than 55 minutes). Add a two-second cushion.
/// This intentionally does not support arbitrary HTTP dates or old date formats.
fn retryAfterSeconds(raw: []const u8, now_seconds: i64) ?u64 {
    if (raw.len == 0) return null;
    const numeric = for (raw) |c| {
        if (!std.ascii.isDigit(c)) break false;
    } else true;
    if (numeric) return std.fmt.parseInt(u64, raw, 10) catch null;

    if (raw.len != 29 or raw[3] != ',' or raw[4] != ' ' or raw[7] != ' ' or
        raw[11] != ' ' or raw[16] != ' ' or raw[19] != ':' or raw[22] != ':' or
        raw[25] != ' ' or !std.mem.eql(u8, raw[26..29], "GMT")) return null;
    const minute = retryTimePair(raw[20..22]) orelse return null;
    const second = retryTimePair(raw[23..25]) orelse return null;
    if (minute > 59 or second > 59) return null;
    // Unix seconds give UTC without a timezone conversion, including at midnight.
    const ahead = @mod(@as(i64, minute) * 60 + second - @mod(now_seconds, 3600), 3600);
    return @intCast((if (ahead >= 55 * 60) @as(i64, 0) else ahead) + 2);
}

fn retryTimePair(s: []const u8) ?u8 {
    if (!std.ascii.isDigit(s[0]) or !std.ascii.isDigit(s[1])) return null;
    return (s[0] - '0') * 10 + s[1] - '0';
}

fn waitToRetry(ctx: Ctx, seconds: u64) !void {
    try ctx.err.print("m8 url-provider: HTTP 429; retrying after Retry-After: {d} seconds\n", .{seconds});
    try ctx.err.flush();
    try ctx.io.sleep(.{ .nanoseconds = @as(i96, seconds) * std.time.ns_per_s }, .awake);
}

/// A file as a form, as curl's `-F file=@FILE` sends it, with each
/// NAME=VALUE as a field beside it. The file goes as bytes, its name saying
/// what it is: knowing a type from an extension would take a table.
fn form(
    arena: std.mem.Allocator,
    boundary: []const u8,
    name: []const u8,
    bytes: []const u8,
    fields: []const []const u8,
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    try w.print("--{s}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{s}\"\r\n" ++
        "Content-Type: application/octet-stream\r\n\r\n", .{ boundary, name });
    try w.writeAll(bytes);
    for (fields) |field| {
        const key, const value = std.mem.cutScalar(u8, field, '=') orelse .{ field, "" };
        try w.print("\r\n--{s}\r\nContent-Disposition: form-data; name=\"{s}\"\r\n\r\n{s}", .{ boundary, key, value });
    }
    try w.print("\r\n--{s}--\r\n", .{boundary});
    return out.written();
}

/// The default transport. curl keeps TLS, certificates, proxies and HTTP out
/// of the executable, which is why it is the small build.
fn runCurl(ctx: Ctx, args: []const []const u8, forward_stdin: bool) !u8 {
    var lines: std.ArrayList(u8) = .empty;
    try headers(ctx, &lines);

    const settings = stats.load(ctx);
    const environ = try api.childEnvironment(ctx.arena, ctx, &.{
        .{ .key = headers_var, .value = lines.items },
        .{ .key = "M8_URL_CAPTURE_HEADERS", .value = "1" },
    });

    // Always drain both pipes: stderr may contain curl diagnostics (and, with
    // stats, response headers), while stdout is the response body.
    //
    // No `--fail`. A status that is not 200 still has a body, and the body is
    // what the api said — the codec reads it as it reads any other answer.
    // What is left to fail is the reaching itself, which curl says on stderr.
    // The executable is single-threaded. Spool before spawning rather than
    // deadlocking a full request pipe against a full response pipe. curl's
    // --data-binary @- buffers the request before sending it in either case.
    var request_spool: ?std.Io.File = null;
    var spool_path: ?[]const u8 = null;
    defer if (spool_path) |path| std.Io.Dir.cwd().deleteFile(ctx.io, path) catch {};
    defer if (request_spool) |file| file.close(ctx.io);
    if (forward_stdin) {
        var random: [16]u8 = undefined;
        ctx.io.random(&random);
        const temp_name = try std.fs.path.join(ctx.arena, &.{
            ctx.env.get("TMPDIR") orelse "/tmp",
            try std.fmt.allocPrint(ctx.arena, "m8-url-{x}", .{&random}),
        });
        const spool = try std.Io.Dir.cwd().createFile(ctx.io, temp_name, .{
            .read = true,
            .exclusive = true,
            .permissions = .fromMode(0o600),
        });
        request_spool = spool;
        spool_path = temp_name;
        if (ctx.stdin) |input| try spoolFile(ctx.io, input, spool);
    }

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(ctx.arena, &.{ "sh", "-c" });
    try argv.appendSlice(ctx.arena, args);
    var retried = false;
    while (true) {
        // Each attempt opens a fresh descriptor: curl consumed the previous one's offset.
        const input_file = if (spool_path) |path| try std.Io.Dir.cwd().openFile(ctx.io, path, .{}) else null;
        defer if (input_file) |file| file.close(ctx.io);
        var child = std.process.spawn(ctx.io, .{
            .argv = argv.items,
            .environ_map = environ,
            .stdin = if (input_file) |file| .{ .file = file } else .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |e| {
            try ctx.err.print("m8 url-provider: {s}\n", .{@errorName(e)});
            return 1;
        };
        defer child.kill(ctx.io);

        var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
        var streams: std.Io.File.MultiReader = undefined;
        streams.init(ctx.arena, ctx.io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        defer streams.deinit();
        var body: std.ArrayList(u8) = .empty;
        var head_ready = false;
        var pending: std.ArrayList(u8) = .empty;
        var retry_seconds: ?u64 = null;
        var retry_body_last: u8 = '\n';
        const response = streams.reader(0);
        while (streams.fill(4096, .none)) |_| {
            // Both pipes are drained together. Body bytes may be observed before
            // the corresponding stderr read, so hold them only until the head is in.
            if (!head_ready) {
                if (curlResponseHead(streams.reader(1).buffered())) |head| {
                    head_ready = true;
                    if (!retried and head.status == 429) {
                        if (head.retry_after) |value| retry_seconds = retryAfterSeconds(value, std.Io.Timestamp.now(ctx.io, .real).toSeconds());
                    }
                }
            }
            const chunk = response.buffered();
            if (!head_ready) {
                try pending.appendSlice(ctx.arena, chunk);
            } else if (retry_seconds) |_| {
                try ctx.err.writeAll(pending.items);
                try ctx.err.writeAll(chunk);
                if (pending.items.len > 0) retry_body_last = pending.items[pending.items.len - 1];
                if (chunk.len > 0) retry_body_last = chunk[chunk.len - 1];
                try ctx.err.flush();
                pending.clearRetainingCapacity();
            } else {
                ctx.out.writeAll(pending.items) catch return 0;
                ctx.out.writeAll(chunk) catch return 0;
                ctx.out.flush() catch return 0;
                if (settings) |s| if (s.body.len > 0) {
                    try body.appendSlice(ctx.arena, pending.items);
                    try body.appendSlice(ctx.arena, chunk);
                };
                pending.clearRetainingCapacity();
            }
            response.toss(chunk.len);
        } else |e| switch (e) {
            error.EndOfStream => {},
            else => return e,
        }
        try streams.checkAnyError();
        const raw_stderr = streams.reader(1).buffered();
        const separated = try stats.splitCurlStderr(ctx.arena, raw_stderr);
        if (retry_body_last != '\n') try ctx.err.writeAll("\n");
        try ctx.err.writeAll(separated.diagnostics);
        try ctx.err.flush();
        const code: u8 = switch (try child.wait(ctx.io)) {
            .exited => |code| code,
            else => 1,
        };
        if (code == 0) {
            if (!head_ready) return error.InvalidHttpResponse;
            if (retry_seconds) |seconds| {
                try waitToRetry(ctx, seconds);
                retried = true;
                continue;
            }
        }
        if (settings) |s| stats.finish(ctx, s, separated.headers, body.items);
        return code;
    }
}

/// Inspect the existing stderr buffer without copying it. Only complete lines
/// count; skip diagnostics and informational heads, then stop before trailers.
fn curlResponseHead(raw: []const u8) ?struct { status: u16, retry_after: ?[]const u8 } {
    var status: ?u16 = null;
    var retry_after: ?[]const u8 = null;
    var pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, raw, pos, '\n')) |end| {
        const line = std.mem.trimEnd(u8, raw[pos..end], "\r");
        pos = end + 1;
        if (status == null) {
            if (!std.mem.startsWith(u8, line, "HTTP/")) continue;
            var words = std.mem.tokenizeAny(u8, line, " \t");
            _ = words.next();
            status = std.fmt.parseInt(u16, words.next() orelse return null, 10) catch return null;
        } else if (line.len == 0) {
            if (status.? >= 100 and status.? < 200 and status.? != 101) {
                status = null;
                retry_after = null;
            } else return .{ .status = status.?, .retry_after = retry_after };
        } else {
            const name, const value = std.mem.cutScalar(u8, line, ':') orelse continue;
            if (std.ascii.eqlIgnoreCase(name, "retry-after")) retry_after = std.mem.trim(u8, value, " \t");
        }
    }
    return null;
}

fn spoolFile(io: std.Io, input: *std.Io.Reader, output: std.Io.File) !void {
    // Positional writes leave the inherited descriptor ready to read at zero.
    var offset: u64 = 0;
    while (true) {
        if (input.buffered().len == 0) {
            input.fillMore() catch |e| switch (e) {
                error.EndOfStream => return,
                else => return e,
            };
        }
        const chunk = input.buffered();
        try output.writePositionalAll(io, chunk, offset);
        offset += chunk.len;
        input.toss(chunk.len);
    }
}

/// Where the header lines wait between here and curl.
const headers_var = "M8_PROVIDER_url_HEADERS";

/// The curl command line.
///
/// Headers reach curl as a file on descriptor 3 rather than as arguments: an
/// argument is in `ps` for every user on the machine, and one of these is a
/// key.
const script =
    \\u=$1; shift
    \\if [ "$M8_URL_CAPTURE_HEADERS" = 1 ]; then set -- "$@" --dump-header /dev/stderr; fi
    \\exec curl -sS --suppress-connect-headers -N -H 'content-type: application/json' -H @/dev/fd/3 --data-binary @- "$@" "$u"
++ heredoc;

/// The same, asking rather than posting: no body, so nothing says what one is.
const get_script =
    \\u=$1; shift
    \\if [ "$M8_URL_CAPTURE_HEADERS" = 1 ]; then set -- "$@" --dump-header /dev/stderr; fi
    \\exec curl -sS --suppress-connect-headers -N -H @/dev/fd/3 "$@" "$u"
++ heredoc;

/// The same, handing over a file: `$2` as the field `file`, and every other
/// argument as a field of its own, sent as written rather than read as curl
/// would read an `@` or a `<`.
const upload_script =
    \\u=$1 f=$2; shift 2
    \\for a; do set -- "$@" --form-string "$a"; shift; done
    \\if [ "$M8_URL_CAPTURE_HEADERS" = 1 ]; then set -- "$@" --dump-header /dev/stderr; fi
    \\exec curl -sS --suppress-connect-headers -H @/dev/fd/3 -F "file=@$f" "$@" "$u"
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
    const prefix = provider.env_prefix ++ "header_";
    var it = ctx.env.iterator();
    while (it.next()) |e| {
        const named = e.key_ptr.*;
        if (!std.mem.startsWith(u8, named, prefix)) continue;
        const value = (try ran(ctx, e.value_ptr.*)) orelse continue;
        try into.append(ctx.arena, .{
            .name = named[prefix.len..],
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
/// `header_x-api-key` arrives here as `M8_PROVIDER_header_x-api-key`, and
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
    const prefix = provider.env_prefix ++ "header_";
    var it = ctx.env.iterator();
    while (it.next()) |e| {
        const named = e.key_ptr.*;
        if (!std.mem.startsWith(u8, named, prefix)) continue;
        const value = (try ran(ctx, e.value_ptr.*)) orelse continue;
        try into.print(ctx.arena, "{s}: {s}\n", .{ named[prefix.len..], value });
    }
}

/// What a header's command said, or null when it said nothing worth sending.
///
/// A command that fails or answers with nothing leaves its header off
/// entirely, so a machine with no key configured still reaches a provider
/// that wants none. Its stderr is passed on, which is how it says what to do. Every plausible command ends in a newline, and a value
/// still holding one after trimming is header injection rather than a header,
/// so it is dropped.
fn ran(ctx: Ctx, cmd: []const u8) !?[]const u8 {
    return ranCommand(ctx, cmd, "header");
}

/// URL and header commands share argv parsing, environment and output rules.
fn ranCommand(ctx: Ctx, cmd: []const u8, comptime kind: []const u8) !?[]const u8 {
    if (cmd.len == 0) return null;
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, ctx.arena, cmd, .{}) catch {
        try ctx.err.writeAll("m8 url-provider: invalid " ++ kind ++ " command JSON (expected an argv array)\n");
        return null;
    };
    if (parsed != .array or parsed.array.items.len == 0) {
        try ctx.err.writeAll("m8 url-provider: invalid " ++ kind ++ " command JSON (expected a non-empty argv array)\n");
        return null;
    }
    const argv = try ctx.arena.alloc([]const u8, parsed.array.items.len);
    for (parsed.array.items, 0..) |item, i| {
        if (item != .string) {
            try ctx.err.print("m8 url-provider: invalid " ++ kind ++ " command JSON (argv item {d} is not a string)\n", .{i});
            return null;
        }
        argv[i] = item.string;
    }
    if (argv[0].len == 0) {
        try ctx.err.writeAll("m8 url-provider: invalid " ++ kind ++ " command JSON (argv[0] is empty)\n");
        return null;
    }
    const resolved = try provider.resolve(ctx.arena, ctx.io, ctx.self, &.{}, argv);
    const environ = try api.childEnvironment(ctx.arena, ctx, &.{});
    const r = std.process.run(ctx.arena, ctx.io, .{
        .argv = resolved,
        .environ_map = environ,
    }) catch return null;
    // The command's own diagnostics remain useful to whoever configured it.
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

test "header commands use argv directly, with shell only when requested" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    const ctx = invocation.ctx(&.{}, null);
    try std.testing.expectEqualStrings("plain value", (try ran(ctx, "[\"printf\",\"%s\",\"plain value\"]")).?);
    try std.testing.expectEqualStrings("shell value", (try ran(ctx, "[\"sh\",\"-c\",\"printf 'shell value'\"]")).?);
    try std.testing.expectEqualStrings("$(printf not-run); *", (try ran(ctx, "[\"printf\",\"%s\",\"$(printf not-run); *\"]")).?);
}

test "header commands omit empty and failed output and inherit configured environment" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_HEADER_TEST_VALUE", "passed");
    const ctx = invocation.ctx(&.{}, null);
    try std.testing.expect((try ran(ctx, "[]")) == null);
    try std.testing.expect((try ran(ctx, "[\"printf\",\"\"]")) == null);
    try std.testing.expect((try ran(ctx, "[\"printf\",\"one\\\\ntwo\"]")) == null);
    try std.testing.expect((try ran(ctx, "[\"sh\",\"-c\",\"exit 9\"]")) == null);
    try std.testing.expectEqualStrings("passed", (try ran(ctx, "[\"sh\",\"-c\",\"printf %s \\\"$M8_HEADER_TEST_VALUE\\\"\"]")).?);
    try std.testing.expect(std.mem.indexOf(u8, invocation.err.written(), "invalid header command JSON") != null);
}

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
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_url") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "M8_PROVIDER_header_") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), if (no_curl_dep) "own HTTP client" else "`curl`") != null);
}

test "a file goes up as a form, with its fields beside it" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    try std.testing.expectEqualStrings(
        "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.jpeg\"\r\n" ++
            "Content-Type: application/octet-stream\r\n\r\nabc" ++
            "\r\n--B\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nvision" ++
            "\r\n--B\r\nContent-Disposition: form-data; name=\"odd\"\r\n\r\n@notafile" ++
            "\r\n--B--\r\n",
        try form(a.allocator(), "B", "a.jpeg", "abc", &.{ "purpose=vision", "odd=@notafile" }),
    );
}

test "url-provider refuses terminal stdin without consuming it" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed("unconsumed");
    var ctx = invocation.ctx(&.{}, &input);
    ctx.stdin_terminal = true;
    try std.testing.expectEqual(@as(u8, 1), try command.run(ctx));
    try std.testing.expectEqualStrings("unconsumed", input.buffered());
    try std.testing.expectEqualStrings("", invocation.out.written());
    try std.testing.expect(std.mem.startsWith(u8, invocation.err.written(), "m8 url-provider: no request on stdin\n"));
}

test "url-provider validates endpoint and no-input mode arguments before reading" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    const cases = [_]struct { args: []const []const u8, terminal: bool = false, diagnostic: []const u8 }{
        .{ .args = &.{}, .diagnostic = "m8 url-provider: no M8_PROVIDER_url\n" },
        .{ .args = &.{"--get"}, .terminal = true, .diagnostic = "m8 url-provider: --get takes one url\n" },
        .{ .args = &.{ "--get", "one", "two" }, .diagnostic = "m8 url-provider: --get takes one url\n" },
        .{ .args = &.{ "--upload", "one" }, .terminal = true, .diagnostic = "m8 url-provider: --upload takes a url and a file\n" },
    };
    for (cases) |case| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed("unconsumed");
        var ctx = invocation.ctx(case.args, &input);
        ctx.stdin_terminal = case.terminal;
        try std.testing.expectEqual(@as(u8, 1), try command.run(ctx));
        try std.testing.expectEqualStrings("unconsumed", input.buffered());
        try std.testing.expectEqualStrings("", invocation.out.written());
        try std.testing.expectEqualStrings(case.diagnostic, invocation.err.written());
    }
}

// Exercise the subprocess pump separately from HTTP/curl integration. The shell
// stands in for the transport, not command parsing or process-input discovery.
test "url-provider curl pump forwards supplied input and separates output without stats" {
    if (comptime no_curl_dep) return error.SkipZigTest;
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    const request = try invocation.arena.allocator().alloc(u8, 256 * 1024);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try invocation.env.put("TMPDIR", try tmp.dir.realPathFileAlloc(std.testing.io, ".", invocation.arena.allocator()));
    @memset(request, 'x');
    var input: std.Io.Reader = .fixed(request);
    const ctx = invocation.ctx(&.{}, &input);
    try std.testing.expectEqual(@as(u8, 7), try runCurl(ctx, &.{ "printf 'HTTP/1.1 200 OK\\r\\n\\r\\n' >&2; cat; printf diagnostic >&2; exit 7", "test transport" }, true));
    try std.testing.expectEqualStrings(request, invocation.out.written());
    try std.testing.expectEqualStrings("diagnostic", invocation.err.written());
}

test "url-provider curl pump treats absent stdin as EOF and no-input modes leave it unread" {
    if (comptime no_curl_dep) return error.SkipZigTest;
    const Invocation = @import("../command_input_test.zig").Invocation;
    for ([_]bool{ true, false }) |forward| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try invocation.env.put("TMPDIR", try tmp.dir.realPathFileAlloc(std.testing.io, ".", invocation.arena.allocator()));
        var input: std.Io.Reader = .fixed("unconsumed");
        const ctx = invocation.ctx(&.{}, if (forward) null else &input);
        try std.testing.expectEqual(@as(u8, 0), try runCurl(ctx, &.{ "printf 'HTTP/1.1 200 OK\\r\\n\\r\\n' >&2; cat; printf done", "test transport" }, forward));
        try std.testing.expectEqualStrings("done", invocation.out.written());
        try std.testing.expectEqualStrings("", invocation.err.written());
        try std.testing.expectEqualStrings("unconsumed", input.buffered());
    }
}
test "header suffixes are preserved verbatim by both transport collectors" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_PROVIDER_header_Content-Type", "[\"printf\",\"application/example\"]");
    const ctx = invocation.ctx(&.{}, null);

    var curl_headers: std.ArrayList(u8) = .empty;
    try headers(ctx, &curl_headers);
    try std.testing.expectEqualStrings("Content-Type: application/example\n", curl_headers.items);

    var stdlib_headers: std.ArrayList(std.http.Header) = .empty;
    try headersStdlib(ctx, &stdlib_headers);
    try std.testing.expectEqual(@as(usize, 1), stdlib_headers.items.len);
    try std.testing.expectEqualStrings("Content-Type", stdlib_headers.items[0].name);
    try std.testing.expectEqualStrings("application/example", stdlib_headers.items[0].value);
}

test "curl response head waits for complete headers and skips diagnostics and interim heads" {
    const raw = "warning before headers\nHTTP/1.1 100 Continue\r\nRetry-After: 99\r\n\r\n" ++
        "HTTP/2 429\r\nrEtRy-AfTeR: \t0 \t\r\n\r\n";
    // Every prefix before the final blank line is incomplete.
    for (0..raw.len) |len| try std.testing.expect(curlResponseHead(raw[0..len]) == null);
    const head = curlResponseHead(raw).?;
    try std.testing.expectEqual(@as(u16, 429), head.status);
    try std.testing.expectEqualStrings("0", head.retry_after.?);
    const with_trailer = curlResponseHead(raw ++ "Retry-After: 999\r\ncurl: diagnostic\n").?;
    try std.testing.expectEqualStrings("0", with_trailer.retry_after.?);
    try std.testing.expect(curlResponseHead("HTTP/1.1 200 OK\n\n").?.retry_after == null);
    try std.testing.expect(curlResponseHead("curl: connection failed\n") == null);
}

test "curl pump replays once only with Retry-After and preserves final error and request" {
    if (comptime no_curl_dep) return error.SkipZigTest;
    const Invocation = @import("../command_input_test.zig").Invocation;
    const cases = [_]struct { status: []const u8, header: []const u8, retry_expected: bool, second_status: []const u8 = "429" }{
        .{ .status = "429", .header = "Retry-After: 0", .retry_expected = true, .second_status = "200" },
        .{ .status = "429", .header = "Retry-After: 0", .retry_expected = true },
        .{ .status = "429", .header = "X-No-Retry: 0", .retry_expected = false },
        .{ .status = "429", .header = "Retry-After: invalid", .retry_expected = false },
        .{ .status = "503", .header = "Retry-After: 0", .retry_expected = false },
    };
    for (cases) |case| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const arena = invocation.arena.allocator();
        const dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", arena);
        try invocation.env.put("TMPDIR", dir);
        try invocation.env.put("M8_RETRY_TEST_DIR", dir);
        try invocation.env.put("M8_RETRY_TEST_STATUS", case.status);
        try invocation.env.put("M8_RETRY_TEST_HEADER", case.header);
        try invocation.env.put("M8_RETRY_TEST_SECOND_STATUS", case.second_status);
        var input: std.Io.Reader = .fixed("exact request\nwith another line\n");
        const transport =
            \\d=$M8_RETRY_TEST_DIR
            \\printf x >> "$d/count"
            \\if [ -f "$d/request" ]; then
            \\  cmp - "$d/request" || exit 9
            \\  printf 'HTTP/1.1 %s Response\r\nRetry-After: 0\r\n\r\n' "$M8_RETRY_TEST_SECOND_STATUS" >&2
            \\  printf second
            \\  printf 'X-Trailer: stays-off-stdout\r\n' >&2
            \\else
            \\  cat > "$d/request"
            \\  printf 'HTTP/1.1 %s Response\r\n%s\r\n\r\n' "$M8_RETRY_TEST_STATUS" "$M8_RETRY_TEST_HEADER" >&2
            \\  printf first-body
            \\fi
        ;
        try std.testing.expectEqual(@as(u8, 0), try runCurl(invocation.ctx(&.{}, &input), &.{ transport, "test transport" }, true));
        try std.testing.expectEqualStrings(if (case.retry_expected) "second" else "first-body", invocation.out.written());
        const count = try tmp.dir.readFileAlloc(std.testing.io, "count", arena, .unlimited);
        try std.testing.expectEqualStrings(if (case.retry_expected) "xx" else "x", count);
        try std.testing.expectEqualStrings(
            if (case.retry_expected)
                "first-body\nm8 url-provider: HTTP 429; retrying after Retry-After: 0 seconds\n"
            else
                "",
            invocation.err.written(),
        );
    }
}

test "delta seconds are strict nonnegative integers with no cushion" {
    try std.testing.expectEqual(@as(?u64, 0), retryAfterSeconds("0", 0));
    try std.testing.expectEqual(@as(?u64, 123), retryAfterSeconds("123", 0));
    for ([_][]const u8{ "", "-1", "+1", "1 ", "1.5", "18446744073709551616" }) |value| {
        try std.testing.expectEqual(@as(?u64, null), retryAfterSeconds(value, 0));
    }
}

test "date hints use only UTC minutes and seconds with a two-second cushion" {
    const date = "Sun, 06 Nov 1994 08:02:00 GMT";
    try std.testing.expectEqual(@as(?u64, 242), retryAfterSeconds(date, 58 * 60)); // hour rollover
    try std.testing.expectEqual(@as(?u64, 242), retryAfterSeconds(date, 23 * 3600 + 58 * 60)); // midnight
    try std.testing.expectEqual(@as(?u64, 2), retryAfterSeconds(date, 2 * 60)); // equal
    try std.testing.expectEqual(@as(?u64, 2), retryAfterSeconds(date, 2 * 60 + 1)); // just passed
    try std.testing.expectEqual(@as(?u64, 2), retryAfterSeconds(date, 7 * 60)); // five minutes behind
    try std.testing.expectEqual(@as(?u64, 3301), retryAfterSeconds(date, 7 * 60 + 1)); // just outside window
    try std.testing.expectEqual(@as(?u64, 2402), retryAfterSeconds("Sun, 06 Nov 1994 08:50:00 GMT", 10 * 60));
    // No calendar or hour interpretation: this is deliberately a time-within-hour hint.
    try std.testing.expectEqual(retryAfterSeconds(date, 0), retryAfterSeconds("Mon, 31 Feb 2040 23:02:00 GMT", 0));
}

test "date hints reject other layouts, timezones and invalid minute or second fields" {
    for ([_][]const u8{
        "Sun, 06 Nov 1994 08:02:00 UTC",
        "Sun, 06 Nov 1994 08:60:00 GMT",
        "Sun, 06 Nov 1994 08:02:60 GMT",
        "Sun, 06 Nov 1994 08:ab:00 GMT",
        "Sunday, 06-Nov-94 08:02:00 GMT",
        "Sun Nov  6 08:02:00 1994",
        "08:02:00 GMT",
    }) |value| {
        try std.testing.expectEqual(@as(?u64, null), retryAfterSeconds(value, 0));
    }
}
test "url commands resolve constants and environment values" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_URL_TEST_ENDPOINT", "https://example.com/from-env");
    const ctx = invocation.ctx(&.{}, null);
    try std.testing.expectEqualStrings("https://example.com/constant", (try ranCommand(ctx, "[\"echo\",\"https://example.com/constant\"]", "url")).?);
    try std.testing.expectEqualStrings("https://example.com/from-env", (try ranCommand(ctx, "[\"printenv\",\"M8_URL_TEST_ENDPOINT\"]", "url")).?);
}

test "invalid url commands fail before consuming the request" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    for ([_][]const u8{
        "https://example.com/literal",
        "\"https://example.com/json-string\"",
        "[]",
        "[1]",
        "[\"\"]",
        "[\"printf\",\"\"]",
        "[\"printf\",\"one\\ntwo\"]",
        "[\"sh\",\"-c\",\"exit 9\"]",
    }) |cmd| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        try invocation.env.put("M8_PROVIDER_url", cmd);
        var input: std.Io.Reader = .fixed("unconsumed");
        try std.testing.expectEqual(@as(u8, 1), try command.run(invocation.ctx(&.{}, &input)));
        try std.testing.expectEqualStrings("unconsumed", input.buffered());
        try std.testing.expectEqualStrings("", invocation.out.written());
        try std.testing.expect(std.mem.indexOf(u8, invocation.err.written(), "url command failed or produced no valid endpoint") != null);
    }
}
