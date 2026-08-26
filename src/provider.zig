//! Talking to a provider.
//!
//! A provider is a url, an api, and a way to get a key. That is all of it —
//! which models it serves, and what to ask them for, is the ledger's business
//! and is written on the 🧠 that names one. A provider speaking two apis is
//! two providers pointing at one url, rather than a second kind of override.
//!
//! `key` is a shell command rather than a secret, so the config can commit
//! safely and reach a keychain, a password manager, or another tool's
//! settings file without m8 knowing any of those exist.

const std = @import("std");
const Allocator = std.mem.Allocator;
const codec = @import("codec.zig");
const doc = @import("m8/doc.zig");
const toolbox = @import("toolbox.zig");

pub const Error = error{
    UnknownProvider,
    UnsupportedApi,
    KeyCommandFailed,
    RequestFailed,
    MalformedResponse,
};

pub const Provider = struct {
    name: []const u8,
    url: []const u8,
    api: []const u8,
    key_cmd: ?[]const u8,
};

pub fn find(providers: std.json.ObjectMap, name: []const u8) !Provider {
    const v = providers.get(name) orelse return Error.UnknownProvider;
    if (v != .object) return Error.UnknownProvider;
    const o = v.object;
    return .{
        .name = name,
        .url = if (o.get("url")) |u| (if (u == .string) u.string else "") else "",
        .api = if (o.get("api")) |a| (if (a == .string) a.string else codec.default) else codec.default,
        .key_cmd = if (o.get("key")) |k| (if (k == .string) k.string else null) else null,
    };
}

/// Run the key command and take its output. Trailing whitespace is stripped —
/// every plausible command (cat, printenv, sed, a keychain read) ends in a
/// newline, and a newline in an Authorization header is rejected as header
/// injection by anything that checks.
pub fn resolveKey(arena: Allocator, io: std.Io, p: Provider) !?[]const u8 {
    const cmd = p.key_cmd orelse return null;

    var child = std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", cmd },
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return Error.KeyCommandFailed;

    var buf: [8192]u8 = undefined;
    var r = child.stdout.?.readerStreaming(io, &buf);
    const raw = r.interface.allocRemaining(arena, .limited(8192)) catch return Error.KeyCommandFailed;
    const term = child.wait(io) catch return Error.KeyCommandFailed;

    switch (term) {
        .exited => |code| if (code != 0) return Error.KeyCommandFailed,
        else => return Error.KeyCommandFailed,
    }
    const key = std.mem.trim(u8, raw, " \t\r\n");
    return if (key.len == 0) null else key;
}

/// Where streamed text goes. Deliberately not a doc.BodyWriter: a provider
/// knows nothing about the document format it is feeding.
pub const Sink = struct {
    ctx: *anyopaque,
    write: *const fn (ctx: *anyopaque, bytes: []const u8) anyerror!void,
};

/// A tool call, whether coming back from a model or going out again as part
/// of the conversation so far.
pub const Call = struct {
    id: []const u8,
    name: []const u8,
    /// The arguments as the model wrote them, still JSON.
    arguments: []const u8,
};

/// The codec this model speaks, which is also what says where it lives. A
/// codec with no suffix is not a wire format — `m8` is one of those — and
/// there is nowhere to post it.
fn wire(p: Provider) !codec.Codec {
    const c = codec.find(p.api) orelse return Error.UnsupportedApi;
    if (c.suffix.len == 0) return Error.UnsupportedApi;
    return c;
}

/// One completion, waited for whole. Returns the assistant's text.
pub fn complete(
    arena: Allocator,
    io: std.Io,
    p: Provider,
    target: codec.Target,
    records: []const doc.Record,
) ![]const u8 {
    const c = try wire(p);
    const body = try c.encode(arena, records, target);

    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena, "{s}{s}", .{ trimSlash(p.url), c.suffix });
    var extra: std.ArrayList(std.http.Header) = .empty;
    if (try resolveKey(arena, io, p)) |key| {
        try extra.append(arena, .{
            .name = "authorization",
            .value = try std.fmt.allocPrint(arena, "Bearer {s}", .{key}),
        });
    }

    var resp: std.Io.Writer.Allocating = .init(arena);
    const res = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = body,
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = extra.items,
        .response_writer = &resp.writer,
    }) catch return Error.RequestFailed;

    if (res.status != .ok) return Error.RequestFailed;

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, resp.written(), .{}) catch
        return Error.MalformedResponse;
    return extractContent(parsed) orelse Error.MalformedResponse;
}

fn extractContent(v: std.json.Value) ?[]const u8 {
    if (v != .object) return null;
    const choices = v.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;
    const msg = first.object.get("message") orelse return null;
    if (msg != .object) return null;
    const content = msg.object.get("content") orelse return null;
    return if (content == .string) content.string else null;
}

fn trimSlash(s: []const u8) []const u8 {
    return std.mem.trimEnd(u8, s, "/");
}


/// One completion, delivered as it arrives.
///
/// Server-sent events: each `data:` line carries a JSON fragment whose delta
/// is appended to the sink. The stream ends at `data: [DONE]`.
pub fn completeStreaming(
    arena: Allocator,
    io: std.Io,
    p: Provider,
    target: codec.Target,
    records: []const doc.Record,
    sink: Sink,
) ![]const Call {
    const wire_format = try wire(p);
    const body = try wire_format.encode(arena, records, target);

    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena, "{s}{s}", .{ trimSlash(p.url), wire_format.suffix });
    const uri = std.Uri.parse(url) catch return Error.RequestFailed;

    var extra: std.ArrayList(std.http.Header) = .empty;
    if (try resolveKey(arena, io, p)) |key| {
        try extra.append(arena, .{
            .name = "authorization",
            .value = try std.fmt.allocPrint(arena, "Bearer {s}", .{key}),
        });
    }

    var req = client.request(.POST, uri, .{
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = extra.items,
    }) catch return Error.RequestFailed;
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = body.len };
    // The writer wants bytes it could scribble on; the body is ours and this
    // is the last thing done with it.
    req.sendBodyComplete(@constCast(body)) catch return Error.RequestFailed;

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch return Error.RequestFailed;
    if (response.head.status != .ok) return Error.RequestFailed;

    var transfer_buf: [64 * 1024]u8 = undefined;
    const r = response.reader(&transfer_buf);

    var calls: std.ArrayList(Building) = .empty;
    while (true) {
        // Inclusive: the exclusive form leaves the delimiter unconsumed, so a
        // second call returns an empty line and never advances.
        const line = r.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => break,
            else => return Error.RequestFailed,
        };
        const trimmed = std.mem.trimEnd(u8, line, "\r\n");
        if (!std.mem.startsWith(u8, trimmed, "data:")) continue;
        const payload = std.mem.trim(u8, trimmed["data:".len..], " ");
        if (std.mem.eql(u8, payload, "[DONE]")) break;

        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{}) catch continue;
        if (extractDelta(parsed)) |text| {
            if (text.len > 0) sink.write(sink.ctx, text) catch return Error.RequestFailed;
        }
        try gatherCalls(arena, &calls, parsed);
    }

    var out: std.ArrayList(Call) = .empty;
    for (calls.items) |c| try out.append(arena, .{
        .id = c.id.items,
        .name = c.name.items,
        .arguments = if (c.arguments.items.len == 0) "{}" else c.arguments.items,
    });
    return out.items;
}

/// A call arrives in pieces across events, addressed by index: the id and
/// name once, then the arguments a fragment at a time. Nothing is complete
/// until the stream ends, so each piece is appended where it belongs.
const Building = struct {
    id: std.ArrayList(u8) = .empty,
    name: std.ArrayList(u8) = .empty,
    arguments: std.ArrayList(u8) = .empty,
};

fn gatherCalls(arena: Allocator, calls: *std.ArrayList(Building), v: std.json.Value) !void {
    const delta = deltaOf(v) orelse return;
    const list = delta.object.get("tool_calls") orelse return;
    if (list != .array) return;

    for (list.array.items) |item| {
        if (item != .object) continue;
        const index: usize = if (item.object.get("index")) |i|
            (if (i == .integer) @intCast(i.integer) else 0)
        else
            0;
        while (calls.items.len <= index) try calls.append(arena, .{});
        const into = &calls.items[index];

        if (item.object.get("id")) |x| {
            if (x == .string) try into.id.appendSlice(arena, x.string);
        }
        const f = item.object.get("function") orelse continue;
        if (f != .object) continue;
        if (f.object.get("name")) |x| {
            if (x == .string) try into.name.appendSlice(arena, x.string);
        }
        if (f.object.get("arguments")) |x| {
            if (x == .string) try into.arguments.appendSlice(arena, x.string);
        }
    }
}

fn deltaOf(v: std.json.Value) ?std.json.Value {
    if (v != .object) return null;
    const choices = v.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;
    const delta = first.object.get("delta") orelse return null;
    return if (delta == .object) delta else null;
}

fn extractDelta(v: std.json.Value) ?[]const u8 {
    if (v != .object) return null;
    const choices = v.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;
    const delta = first.object.get("delta") orelse return null;
    if (delta != .object) return null;
    const content = delta.object.get("content") orelse return null;
    return if (content == .string) content.string else null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn providersFrom(arena: Allocator, json: []const u8) !std.json.ObjectMap {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    return v.object;
}

test "a provider is a url, an api and a way to get a key" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ps = try providersFrom(arena,
        \\{
        \\  "local":   {"url": "http://x/v1/"},
        \\  "local-r": {"url": "http://x/v1", "api": "some-other-api", "key": "cat k"}
        \\}
    );

    // Nothing said, so the default — and it is a name a codec answers to.
    const p = try find(ps, "local");
    try testing.expectEqualStrings(codec.default, p.api);
    try testing.expect(codec.find(p.api) != null);
    try testing.expect(p.key_cmd == null);

    // One url, two apis, two providers. No second kind of override.
    const q = try find(ps, "local-r");
    try testing.expectEqualStrings("some-other-api", q.api);
    try testing.expectEqualStrings(trimSlash(p.url), q.url);
    try testing.expectEqualStrings("cat k", q.key_cmd.?);

    try testing.expectError(Error.UnknownProvider, find(ps, "nosuch"));
}

test "the codec decides where the request goes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ps = try providersFrom(arena,
        \\{
        \\  "local": {"url": "http://x/v1/"},
        \\  "odd":   {"url": "http://x", "api": "m8"},
        \\  "gone":  {"url": "http://x", "api": "nosuch"}
        \\}
    );

    try testing.expectEqualStrings("/chat/completions", (try wire(try find(ps, "local"))).suffix);
    // `m8` is a codec but not a wire format, so it has nowhere to be posted,
    // and a name no codec answers to is refused rather than guessed at.
    try testing.expectError(Error.UnsupportedApi, wire(try find(ps, "odd")));
    try testing.expectError(Error.UnsupportedApi, wire(try find(ps, "gone")));
}
