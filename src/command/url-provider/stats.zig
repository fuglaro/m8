//! Optional url-provider policy: select response values and invoke a formatter.
const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("../../api.zig");
const provider = @import("../../provider.zig");
const config = @import("../../config.zig");

pub const Config = struct {
    headers: []const []const u8 = &.{},
    body: []const []const u8 = &.{},
    cmd: []const []const u8,
};

pub fn load(ctx: api.Ctx) ?Config {
    return readConfig(ctx) catch |e| {
        ctx.err.print("m8: url-provider stats configuration: {s}\n", .{@errorName(e)}) catch {};
        ctx.err.flush() catch {};
        return null;
    };
}

fn readConfig(ctx: api.Ctx) !?Config {
    const raw = ctx.env.get("M8_PROVIDER_STATS") orelse return null;
    const settings = try std.json.parseFromSliceLeaky(Config, ctx.arena, raw, .{});
    if (settings.cmd.len == 0) return error.InvalidStats;
    return settings;
}

/// Stats are optional and run only after forwarding the response. Their failure
/// is diagnostic, never the HTTP transport's exit status.
pub fn finish(ctx: api.Ctx, settings: Config, headers: []const u8, body: []const u8) void {
    format(ctx, settings, headers, body) catch |e| {
        ctx.err.print("m8: url-provider stats failed: {s}\n", .{@errorName(e)}) catch {};
        ctx.err.flush() catch {};
    };
}

fn format(ctx: api.Ctx, settings: Config, headers: []const u8, body: []const u8) !void {
    const input = try select(ctx.arena, body, headers, settings.headers, settings.body);
    const argv = try provider.resolve(ctx.arena, ctx.io, ctx.self, try config.coreDirs(ctx.arena, ctx.io, ctx.env), settings.cmd);
    try ctx.err.flush();
    var child = try std.process.spawn(ctx.io, .{
        .argv = argv,
        .environ_map = ctx.env,
        .stdin = .pipe,
        .stdout = .{ .file = std.Io.File.stderr() },
        .stderr = .inherit,
    });
    defer child.kill(ctx.io);
    try child.stdin.?.writeStreamingAll(ctx.io, input);
    child.stdin.?.close(ctx.io);
    child.stdin = null;
    const term = try child.wait(ctx.io);
    if (term != .exited or term.exited != 0) return error.StatsCommandFailed;
}

pub fn select(arena: Allocator, response: []const u8, headers_raw: []const u8, headers: []const []const u8, body_paths: []const []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    // curl can include proxy/interim heads. Only select from the last head.
    var head_start: usize = 0;
    var offset: usize = 0;
    var head_lines = std.mem.splitScalar(u8, headers_raw, '\n');
    while (head_lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "HTTP/")) head_start = offset;
        offset += line.len + 1;
    }
    for (headers) |name| {
        var it = std.mem.splitScalar(u8, headers_raw[head_start..], '\n');
        while (it.next()) |line| {
            const clean = std.mem.trim(u8, line, "\r \t");
            const colon = std.mem.indexOfScalar(u8, clean, ':') orelse continue;
            if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, clean[0..colon], " \t"), name)) continue;
            const val = std.mem.trim(u8, clean[colon + 1 ..], " \t");
            const encoded = try std.json.Stringify.valueAlloc(arena, val, .{});
            try w.print("header.{s}: {s}\n", .{ name, encoded });
        }
    }
    if (body_paths.len > 0) {
        const trimmed = std.mem.trimStart(u8, response, " \r\n\t");
        if (trimmed.len > 0 and trimmed[0] != '{' and trimmed[0] != '[') {
            var lines = std.mem.splitScalar(u8, response, '\n');
            var event: std.ArrayList(u8) = .empty;
            while (lines.next()) |raw| {
                const line = std.mem.trimEnd(u8, raw, "\r");
                if (std.mem.startsWith(u8, line, "data:")) {
                    const payload = std.mem.trimStart(u8, line[5..], " ");
                    if (event.items.len > 0) try event.append(arena, '\n');
                    try event.appendSlice(arena, payload);
                } else if (line.len == 0) {
                    try selectJson(event.items, body_paths, w);
                    event.clearRetainingCapacity();
                }
            }
            try selectJson(event.items, body_paths, w);
        } else try selectJson(response, body_paths, w);
    }
    return out.written();
}

fn selectJson(text: []const u8, paths: []const []const u8, w: *std.Io.Writer) !void {
    if (text.len == 0 or std.mem.eql(u8, text, "[DONE]")) return;
    // Parse outside the response arena so each event's tree is actually freed.
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, text, .{}) catch return;
    defer parsed.deinit();
    for (paths) |path| {
        const value = lookup(parsed.value, path) orelse continue;
        try w.print("body.{s}: ", .{path});
        try std.json.Stringify.value(value, .{}, w);
        try w.writeByte('\n');
    }
}

fn lookup(root: std.json.Value, path: []const u8) ?std.json.Value {
    var value = root;
    var keys = std.mem.splitScalar(u8, path, '.');
    while (keys.next()) |key| {
        if (value != .object) return null;
        value = value.object.get(key) orelse return null;
        // Preserve the existing treatment of a trailing dot as end-of-path.
        if (keys.rest().len == 0) break;
    }
    return value;
}

test "SSE selections retain event order, CRLF, missing values and multiline data" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const got = try select(a.allocator(), "event: start\r\ndata: {\"message\":{\"usage\":{\"in\":76}}}\r\n\r\n" ++
        "data: {\"usage\":\r\ndata: {\"out\":80}}\r\n\r\n" ++
        "data: [DONE]\n\n", "HTTP/1.1 100 Continue\r\nX-Rate: old\r\n\r\nHTTP/2 200\r\nx-rate: 7\r\nX-Rate: 8\r\n\r\n", &.{"X-Rate"}, &.{ "message.usage.in", "usage.out", "missing" });
    try std.testing.expectEqualStrings("header.X-Rate: \"7\"\nheader.X-Rate: \"8\"\nbody.message.usage.in: 76\nbody.usage.out: 80\n", got);
}

test "whole JSON containing data colon is not mistaken for SSE" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const got = try select(a.allocator(), "{\"value\":\"data: newline\\nquoted\\\"\",\"null\":null,\"object\":{\"n\":3}}", "", &.{}, &.{ "value", "null", "object" });
    try std.testing.expectEqualStrings("body.value: \"data: newline\\nquoted\\\"\"\nbody.null: null\nbody.object: {\"n\":3}\n", got);
}

pub const CurlStderr = struct { headers: []const u8, diagnostics: []const u8 };

/// curl --dump-header /dev/stderr keeps metadata off the body stream. Retain
/// HTTP heads (including interim/proxy heads) and CRLF-terminated trailers;
/// leave curl errors and other non-header text as ordinary diagnostics.
pub fn splitCurlStderr(arena: Allocator, raw: []const u8) !CurlStderr {
    var heads: std.Io.Writer.Allocating = .init(arena);
    var diagnostics: std.Io.Writer.Allocating = .init(arena);
    var in_head = false;
    var seen_head = false;
    var pos: usize = 0;
    while (pos < raw.len) {
        const end = if (std.mem.indexOfScalarPos(u8, raw, pos, '\n')) |n| n + 1 else raw.len;
        const line = raw[pos..end];
        const clean = std.mem.trimEnd(u8, line, "\r\n");
        if (std.mem.startsWith(u8, clean, "HTTP/")) {
            in_head = true;
            seen_head = true;
        }
        const curl_error = std.mem.startsWith(u8, clean, "curl:");
        const trailer = seen_head and std.mem.endsWith(u8, line, "\r\n") and std.mem.indexOfScalar(u8, clean, ':') != null;
        if (!curl_error and (in_head or trailer)) {
            try heads.writer.writeAll(line);
            if (clean.len == 0) in_head = false;
        } else try diagnostics.writer.writeAll(line);
        pos = end;
    }
    return .{ .headers = heads.written(), .diagnostics = diagnostics.written() };
}

test "curl headers and trailers stay separate from diagnostics and body" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const raw = "warning before headers\nHTTP/1.1 200 Connection established\r\n\r\n" ++
        "HTTP/1.1 103 Early Hints\r\nLink: preload\r\n\r\n" ++
        "HTTP/2 200\r\nX-Rate: 7\r\n\r\nX-Trailer: end\r\n" ++
        "curl: (18) transfer closed\n";
    const separated = try splitCurlStderr(a.allocator(), raw);
    try std.testing.expectEqualStrings("warning before headers\ncurl: (18) transfer closed\n", separated.diagnostics);
    const selected = try select(a.allocator(), "", separated.headers, &.{ "link", "x-rate", "x-trailer" }, &.{});
    try std.testing.expectEqualStrings("header.x-rate: \"7\"\nheader.x-trailer: \"end\"\n", selected);
}
