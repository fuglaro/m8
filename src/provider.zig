//! Talking to a provider.
//!
//! m8 holds no opinion about what a provider is beyond four fields. `key` is
//! a shell command rather than a secret, so the config can commit safely and
//! reach a keychain, a password manager, or another tool's settings file
//! without m8 knowing any of those exist.

const std = @import("std");
const Allocator = std.mem.Allocator;

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
    models: ?std.json.ObjectMap,

    /// The name to put on the wire. `use` when the entry names one, otherwise
    /// the entry's own key. Models absent from the config still resolve —
    /// providers may serve more than the config lists.
    pub fn wireName(p: Provider, model: []const u8) []const u8 {
        const models = p.models orelse return model;
        const entry = models.get(model) orelse return model;
        if (entry != .object) return model;
        const use = entry.object.get("use") orelse return model;
        return if (use == .string) use.string else model;
    }

    pub fn maxOutput(p: Provider, model: []const u8) ?i64 {
        const models = p.models orelse return null;
        const entry = models.get(model) orelse return null;
        if (entry != .object) return null;
        const out = entry.object.get("output") orelse return null;
        return if (out == .integer) out.integer else null;
    }
};

pub fn find(providers: std.json.ObjectMap, name: []const u8) !Provider {
    const v = providers.get(name) orelse return Error.UnknownProvider;
    if (v != .object) return Error.UnknownProvider;
    const o = v.object;
    return .{
        .name = name,
        .url = if (o.get("url")) |u| (if (u == .string) u.string else "") else "",
        .api = if (o.get("api")) |a| (if (a == .string) a.string else "openai") else "openai",
        .key_cmd = if (o.get("key")) |k| (if (k == .string) k.string else null) else null,
        .models = if (o.get("models")) |m| (if (m == .object) m.object else null) else null,
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

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

/// One completion. Returns the assistant's text.
pub fn complete(
    arena: Allocator,
    io: std.Io,
    p: Provider,
    model: []const u8,
    messages: []const Message,
) ![]const u8 {
    if (!std.mem.eql(u8, p.api, "openai")) return Error.UnsupportedApi;

    var body: std.Io.Writer.Allocating = .init(arena);
    var s: std.json.Stringify = .{ .writer = &body.writer };
    try s.beginObject();
    try s.objectField("model");
    try s.write(p.wireName(model));
    if (p.maxOutput(model)) |n| {
        try s.objectField("max_tokens");
        try s.write(n);
    }
    try s.objectField("messages");
    try s.beginArray();
    for (messages) |m| {
        try s.beginObject();
        try s.objectField("role");
        try s.write(m.role);
        try s.objectField("content");
        try s.write(m.content);
        try s.endObject();
    }
    try s.endArray();
    try s.endObject();

    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena, "{s}/chat/completions", .{trimSlash(p.url)});
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
        .payload = body.written(),
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
    model: []const u8,
    messages: []const Message,
    sink: Sink,
) !void {
    if (!std.mem.eql(u8, p.api, "openai")) return Error.UnsupportedApi;

    const body = try buildRequest(arena, p, model, messages, true);

    var client: std.http.Client = .{ .allocator = arena, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena, "{s}/chat/completions", .{trimSlash(p.url)});
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
    req.sendBodyComplete(body) catch return Error.RequestFailed;

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch return Error.RequestFailed;
    if (response.head.status != .ok) return Error.RequestFailed;

    var transfer_buf: [64 * 1024]u8 = undefined;
    const r = response.reader(&transfer_buf);

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
    }
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

fn buildRequest(
    arena: Allocator,
    p: Provider,
    model: []const u8,
    messages: []const Message,
    stream: bool,
) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(arena);
    var s: std.json.Stringify = .{ .writer = &body.writer };
    try s.beginObject();
    try s.objectField("model");
    try s.write(p.wireName(model));
    if (stream) {
        try s.objectField("stream");
        try s.write(true);
    }
    if (p.maxOutput(model)) |n| {
        try s.objectField("max_tokens");
        try s.write(n);
    }
    try s.objectField("messages");
    try s.beginArray();
    for (messages) |m| {
        try s.beginObject();
        try s.objectField("role");
        try s.write(m.role);
        try s.objectField("content");
        try s.write(m.content);
        try s.endObject();
    }
    try s.endArray();
    try s.endObject();
    return body.written();
}
