//! The OpenAI chat completions api.
//!
//! A ledger is records in the order they happened. This api wants something
//! narrower: one leading system message, and every tool call a model made
//! gathered onto the assistant turn that made them, ahead of the answers. So
//! this is where the reordering and the combining live — not in the ledger,
//! which keeps saying what happened.
//!
//! What it cannot carry, it drops: 💭 and 🔏 have no field going out, a 🚫
//! arrives as an ordinary tool message, and a 🔌 is m8's business rather than
//! the model's. Decoding gets back everything the wire actually held.
//!
//! Coming back is not symmetrical. OpenAI's own schema has no reasoning
//! channel, but the servers that speak this api added one — `reasoning_content`
//! mostly, `reasoning` elsewhere — so a reply is read as a run of records and
//! a server that sends reasoning gets a 💭 out of it. Sending one back is
//! still impossible, which is the asymmetry this api has and not a gap here.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const modelform = @import("../m8/model.zig");
const toolbox = @import("../toolbox.zig");
const api = @import("../codec.zig");

pub const codec_name = "openai-completions";

pub const codec: api.Codec = .{
    .name = codec_name,
    .summary = "OpenAI chat completions",
    .encode = encode,
    .parse = parse,
};

// ------------------------------------------------------------------ encode

pub fn encode(arena: Allocator, ledger: []const doc.Record, target: api.Target) ![]const u8 {
    const records = try api.spoken(arena, ledger);
    var buf: std.Io.Writer.Allocating = .init(arena);
    var s: std.json.Stringify = .{ .writer = &buf.writer };

    try s.beginObject();
    try s.objectField("model");
    try s.write(target.model);
    if (target.stream) {
        try s.objectField("stream");
        try s.write(true);
    }
    // The ledger's own, in this api's words, passed through untranslated.
    for (target.params) |p| {
        try s.objectField(p.key);
        try s.write(modelform.json(arena, p.value));
    }

    try s.objectField("messages");
    try s.beginArray();
    try writeSystem(arena, &s, records);
    try writeTurns(arena, &s, records);
    try s.endArray();

    if (target.tools.len > 0) {
        try s.objectField("tools");
        try s.beginArray();
        for (target.tools) |t| try toolbox.writeSchema(&s, t);
        try s.endArray();
    }
    try s.endObject();
    return buf.written();
}

/// Every 🧭, joined and hoisted to the front. The api takes one system message
/// and takes it first; a ledger may hold several, anywhere.
fn writeSystem(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    var text: std.ArrayList(u8) = .empty;
    for (records) |r| {
        if (r.sigil != .system) continue;
        const c = r.content orelse continue;
        if (text.items.len > 0) try text.append(arena, '\n');
        try text.appendSlice(arena, c);
    }
    if (text.items.len == 0) return;
    try s.beginObject();
    try s.objectField("role");
    try s.write("system");
    try s.objectField("content");
    try s.write(text.items);
    try s.endObject();
}

fn writeTurns(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    // An answer is bound to its call by id, and this api wants it written
    // beside that call. A ledger may hold them apart — somebody can say
    // something between asking and being answered, and a run that picks up an
    // owed call answers it long after — so the pairing is by id here, and a
    // record already written is not written again where it actually stands.
    const claimed = try arena.alloc(bool, records.len);
    @memset(claimed, false);

    var i: usize = 0;
    while (i < records.len) {
        const r = records[i];
        switch (r.sigil) {
            .user => {
                try simple(s, "user", r.content orelse "", "");
                i += 1;
            },
            .bot => {
                // A reply that asked for tools belongs on the same message as
                // the asking, so the run it opens is written with it.
                if (i + 1 < records.len and records[i + 1].sigil == .call) {
                    i = try run(arena, s, records, i + 1, r.content orelse "", claimed);
                } else {
                    try simple(s, "assistant", r.content orelse "", "");
                    i += 1;
                }
            },
            .call => i = try run(arena, s, records, i, "", claimed),
            // An answer whose call was never written still names what it
            // answers, and is left where the ledger put it.
            .result, .ok, .failed => {
                if (!claimed[i])
                    try simple(s, "tool", r.content orelse "", std.mem.trim(u8, r.value, " \t"));
                i += 1;
            },
            else => i += 1,
        }
    }
}

/// One assistant turn's worth of calling: every 📲 in the run onto one
/// message, then the answer to each, wherever in the ledger it ended up.
fn run(
    arena: Allocator,
    s: *std.json.Stringify,
    records: []const doc.Record,
    start: usize,
    said: []const u8,
    claimed: []bool,
) !usize {
    var end = start;
    while (end < records.len) : (end += 1) {
        switch (records[end].sigil) {
            .call, .result, .link, .ok, .failed => {},
            else => break,
        }
    }

    try s.beginObject();
    try s.objectField("role");
    try s.write("assistant");
    try s.objectField("content");
    try s.write(said);
    try s.objectField("tool_calls");
    try s.beginArray();
    for (records[start..end]) |r| {
        if (r.sigil != .call) continue;
        try s.beginObject();
        try s.objectField("id");
        try s.write(callId(r.value));
        try s.objectField("type");
        try s.write("function");
        try s.objectField("function");
        try s.beginObject();
        try s.objectField("name");
        try s.write(callName(r.value));
        try s.objectField("arguments");
        try s.write(try toolbox.parseArgs(arena, .md, r.content orelse ""));
        try s.endObject();
        try s.endObject();
    }
    try s.endArray();
    try s.endObject();

    // A tool message holds text alone, so the files handed over are shown
    // in a message of the person's after every answer, which is as near to
    // the answer as this api lets them stand.
    var shown: std.ArrayList([]const u8) = .empty;
    for (records[start..end]) |r| {
        if (r.sigil != .call) continue;
        const back = (try answerTo(arena, records, claimed, start, callId(r.value))) orelse continue;
        try shown.appendSlice(arena, back.links);
        try simple(s, "tool", back.said, callId(r.value));
    }
    if (shown.items.len > 0) try showFiles(s, shown.items);

    // Anything in the run that answered no call of this run belongs here all
    // the same; the ledger is what says so.
    for (records[start..end], start..) |r, idx| {
        switch (r.sigil) {
            .result, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        claimed[idx] = true;
        try simple(s, "tool", r.content orelse "", std.mem.trim(u8, r.value, " \t"));
    }
    return end;
}

/// What answered `id`, from `from` onward, as the one message this api has
/// room for. Null when nothing answered it, which is a call still owed.
///
/// A call is answered by what the tool said and then by how it went, and chat
/// completions has one message per call to say both in. So they are joined:
/// the output, and the reason underneath it when there was a failure. 🟢 adds
/// nothing to say — that a tool worked is the ordinary case, and this api has
/// no way to mark it either.
///
/// This is the projection losing something, which is what a projection does.
/// Reading it back cannot tell a 🚫 from a 🧾 and never could.
fn answerTo(
    arena: Allocator,
    records: []const doc.Record,
    claimed: []bool,
    from: usize,
    id: []const u8,
) !?Answer {
    var said: std.ArrayList(u8) = .empty;
    var links: std.ArrayList([]const u8) = .empty;
    var found = false;

    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .link, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, r.value, " \t"), id)) continue;

        claimed[idx] = true;
        found = true;
        if (r.sigil == .link) {
            try links.append(arena, r.content orelse "");
            continue;
        }
        const content = r.content orelse continue;
        if (content.len == 0) continue;
        if (said.items.len > 0) try said.append(arena, '\n');
        try said.appendSlice(arena, content);

        // A verdict ends the answer; anything later with this id answers a
        // call made again rather than this one.
        if (r.sigil != .result) break;
    }
    return if (found) .{ .said = said.items, .links = links.items } else null;
}

/// What answered a call: what was said, and the 🔗 blocks beside it.
const Answer = struct { said: []const u8, links: []const []const u8 };

/// Files a tool handed over, as one message of the person's.
fn showFiles(s: *std.json.Stringify, links: []const []const u8) !void {
    try s.beginObject();
    try s.objectField("role");
    try s.write("user");
    try s.objectField("content");
    try s.beginArray();
    for (links) |content| {
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const mime, const uri, const name = (try api.handed(line)) orelse continue;
            const ref = std.mem.cutPrefix(u8, uri, "ref:");
            try s.beginObject();
            try s.objectField("type");
            if (std.mem.startsWith(u8, mime, "image/")) {
                // An image part here takes a url and nothing else.
                if (ref != null) return error.UnsupportedLink;
                try s.write("image_url");
                try s.objectField("image_url");
                try s.beginObject();
                try s.objectField("url");
                try s.write(uri);
                try s.endObject();
            } else {
                try s.write("file");
                try s.objectField("file");
                try s.beginObject();
                if (ref) |id| {
                    try s.objectField("file_id");
                    try s.write(id);
                } else {
                    try s.objectField("filename");
                    try s.write(name);
                    try s.objectField("file_data");
                    try s.write(uri);
                }
                try s.endObject();
            }
            try s.endObject();
        }
    }
    try s.endArray();
    try s.endObject();
}

fn simple(s: *std.json.Stringify, role: []const u8, content: []const u8, call_id: []const u8) !void {
    try s.beginObject();
    try s.objectField("role");
    try s.write(role);
    try s.objectField("content");
    try s.write(content);
    if (call_id.len > 0) {
        try s.objectField("tool_call_id");
        try s.write(call_id);
    }
    try s.endObject();
}

fn callId(value: []const u8) []const u8 {
    const cut = std.mem.indexOfScalar(u8, value, ',') orelse return "";
    return std.mem.trim(u8, value[cut + 1 ..], " \t");
}

fn callName(value: []const u8) []const u8 {
    const cut = std.mem.indexOfScalar(u8, value, ',') orelse return value;
    return std.mem.trim(u8, value[0..cut], " \t");
}

// ------------------------------------------------------------------- parse

/// Read a response, whichever shape it turned up in.
///
/// `stream: true` changes this api's response shape rather than only its
/// delivery, so a provider that ignored the flag answers with one whole JSON
/// object instead of a stream of events. Both are read here, told apart by
/// what actually arrived — the same move `doc.detect` makes on stdin: decide
/// from the first line, then commit.
fn parse(arena: Allocator, r: *std.Io.Reader, sink: api.Sink) !api.Reply {
    // The first line that says anything decides.
    while (true) {
        const raw = (try api.nextLine(arena, r)) orelse return .{};
        const line = std.mem.trimEnd(u8, raw, "\r\n");
        if (std.mem.trim(u8, line, " \t").len == 0) continue;

        if (std.mem.startsWith(u8, line, "data:") or std.mem.startsWith(u8, line, "event:"))
            return events(arena, r, sink, line);
        return whole(arena, r, sink, raw);
    }
}

/// Server-sent events: each `data:` line carries a whole JSON fragment whose
/// delta is appended. The stream ends at `data: [DONE]`.
fn events(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var built: Run = .{ .arena = arena, .sink = sink };
    var building: std.ArrayList(Building) = .empty;
    var reason: []const u8 = "";
    var refused = false;

    var line = first;
    while (true) {
        if (std.mem.startsWith(u8, line, "data:")) {
            const payload = std.mem.trim(u8, line["data:".len..], " ");
            if (std.mem.eql(u8, payload, "[DONE]")) break;
            if (std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{})) |v| {
                if (errorOf(v)) |e| {
                    try built.stop();
                    try api.failed(arena, sink, e);
                    return built.reply(try finish(arena, building.items), "");
                }
                // Reasoning before content: a server that puts both in one
                // delta means the thinking came first.
                if (extractReasoning(v)) |fragment| try built.to(.thought, fragment);
                if (extractDelta(v)) |fragment| try built.to(.bot, fragment);
                if (extractRefusal(v)) |fragment| {
                    try built.to(.bot, fragment);
                    refused = true;
                }
                try gatherCalls(arena, &building, v);
                // Null on every chunk but the one that ends the choice.
                if (finishOf(v)) |f| reason = f;
            } else |_| {}
        }
        const raw = (try api.nextLine(arena, r)) orelse break;
        line = std.mem.trimEnd(u8, raw, "\r\n");
    }
    try built.stop();
    return built.reply(try finish(arena, building.items), refusedOr(refused, reason));
}

/// One JSON object, from a provider that answered all at once.
fn whole(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, first);
    const rest = try r.allocRemaining(arena, .unlimited);
    try body.appendSlice(arena, rest);

    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, body.items, .{}) catch
        return error.MalformedResponse;

    if (errorOf(v)) |e| {
        try api.failed(arena, sink, e);
        return .{};
    }
    const message = messageOf(v) orelse return .{};
    var built: Run = .{ .arena = arena, .sink = sink };
    for ([_][]const u8{ "reasoning_content", "reasoning" }) |name| {
        if (message.object.get(name)) |c| if (c == .string) {
            try built.to(.thought, c.string);
            break;
        };
    }
    if (message.object.get("content")) |c| {
        if (c == .string) try built.to(.bot, c.string);
    }
    var refused = false;
    if (message.object.get("refusal")) |c| if (c == .string and c.string.len > 0) {
        try built.to(.bot, c.string);
        refused = true;
    };
    try built.stop();

    var building: std.ArrayList(Building) = .empty;
    if (message.object.get("tool_calls")) |list| if (list == .array) {
        for (list.array.items) |item| try gatherOne(arena, &building, item);
    };
    return built.reply(try finish(arena, building.items), refusedOr(refused, finishOf(v) orelse ""));
}

/// What an answer holds in place of choices when the api refused the request
/// itself — a bad key, an unknown model, an overload.
fn errorOf(v: std.json.Value) ?std.json.Value {
    if (v != .object) return null;
    const e = v.object.get("error") orelse return null;
    return if (e == .null) null else e;
}

/// A refusal is words the model said, so they are its 🤖; this api still
/// calls that finishing, so the field's own name is what says it declined.
/// Anything else a choice ended on — running out, say — is said instead.
fn refusedOr(refused: bool, reason: []const u8) []const u8 {
    if (refused and (reason.len == 0 or std.mem.eql(u8, reason, "stop"))) return "refusal";
    return reason;
}

/// How the first choice ended, in this api's words. `stop` covers a stop
/// sequence as well as finishing, so the two cannot be told apart here.
const stops = api.Stops.initComptime(.{
    .{ "stop", "" },
    .{ "tool_calls", "" },
    .{ "function_call", "" },
    .{ "length", "cut off at" },
    .{ "content_filter", "filtered by" },
    .{ "refusal", "declined with" },
});

fn finishOf(v: std.json.Value) ?[]const u8 {
    if (v != .object) return null;
    const choices = v.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;
    const f = first.object.get("finish_reason") orelse return null;
    return if (f == .string) f.string else null;
}

/// The reply being built, as a run of records rather than one blob.
///
/// Which record is open is decided by what arrives: a reasoning fragment after
/// text closes the 🤖 and opens a 💭, and the other way about. So a server
/// that interleaves them produces records that interleave the same way, and
/// one that does not produces the ordinary 💭-then-🤖 pair.
const Run = struct {
    arena: Allocator,
    sink: api.Sink,
    open: ?sigil.Sigil = null,

    fn to(self: *Run, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        if (self.open != s) {
            try self.stop();
            try self.sink.begin(s, "");
            self.open = s;
        }
        try self.sink.text(fragment);
    }

    fn stop(self: *Run) !void {
        if (self.open == null) return;
        try self.sink.end();
        self.open = null;
    }

    /// The calls, and how the reply stopped said last.
    fn reply(self: *Run, calls: []const api.Call, reason: []const u8) !api.Reply {
        try api.stopped(self.arena, self.sink, stops, reason);
        return .{ .calls = calls };
    }
};

fn messageOf(v: std.json.Value) ?std.json.Value {
    if (v != .object) return null;
    const choices = v.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;
    const message = first.object.get("message") orelse return null;
    return if (message == .object) message else null;
}

/// A call arrives in pieces across events, addressed by index: the id and
/// name once, then the arguments a fragment at a time. Nothing is complete
/// until the stream ends, so each piece is appended where it belongs.
const Building = struct {
    id: std.ArrayList(u8) = .empty,
    name: std.ArrayList(u8) = .empty,
    arguments: std.ArrayList(u8) = .empty,
};

fn finish(arena: Allocator, building: []const Building) ![]const api.Call {
    var out: std.ArrayList(api.Call) = .empty;
    for (building) |b| try out.append(arena, .{
        .id = b.id.items,
        .name = b.name.items,
        .arguments = if (b.arguments.items.len == 0) "{}" else b.arguments.items,
    });
    return out.items;
}

fn gatherCalls(arena: Allocator, calls: *std.ArrayList(Building), v: std.json.Value) !void {
    const delta = deltaOf(v) orelse return;
    const list = delta.object.get("tool_calls") orelse return;
    if (list != .array) return;
    for (list.array.items) |item| try gatherOne(arena, calls, item);
}

fn gatherOne(arena: Allocator, calls: *std.ArrayList(Building), item: std.json.Value) !void {
    if (item != .object) return;
    const index: usize = if (item.object.get("index")) |i|
        (if (i == .integer) @intCast(i.integer) else calls.items.len)
    else
        calls.items.len;
    while (calls.items.len <= index) try calls.append(arena, .{});
    const into = &calls.items[index];

    if (item.object.get("id")) |x| {
        if (x == .string) try into.id.appendSlice(arena, x.string);
    }
    const f = item.object.get("function") orelse return;
    if (f != .object) return;
    if (f.object.get("name")) |x| {
        if (x == .string) try into.name.appendSlice(arena, x.string);
    }
    if (f.object.get("arguments")) |x| {
        if (x == .string) try into.arguments.appendSlice(arena, x.string);
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

/// The reasoning fragment a delta carries, under whichever name the server
/// chose. `reasoning_content` is what OpenAI-compatible servers settled on and
/// `reasoning` is the other spelling in the wild; OpenAI's own completions
/// schema has neither, which is why this api's header says 💭 has no field
/// here. It costs nothing to read one when a server does offer it.
fn extractReasoning(v: std.json.Value) ?[]const u8 {
    const delta = deltaOf(v) orelse return null;
    for ([_][]const u8{ "reasoning_content", "reasoning" }) |name| {
        if (delta.object.get(name)) |x| if (x == .string) return x.string;
    }
    return null;
}

fn extractRefusal(v: std.json.Value) ?[]const u8 {
    const delta = deltaOf(v) orelse return null;
    const refusal = delta.object.get("refusal") orelse return null;
    return if (refusal == .string) refusal.string else null;
}

fn extractDelta(v: std.json.Value) ?[]const u8 {
    const delta = deltaOf(v) orelse return null;
    const content = delta.object.get("content") orelse return null;
    return if (content == .string) content.string else null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn field(v: std.json.Value, name: []const u8) std.json.Value {
    return v.object.get(name).?;
}

test "the api gets one system message first, whatever order the ledger is in" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // 🧭 after 🙋, and two of them: the ledger is allowed to say this and the
    // api is not, so the encoder is where it gets fixed.
    const records = [_]doc.Record{
        .{ .sigil = .user, .content = "Hi." },
        .{ .sigil = .system, .content = "Be brief." },
        .{ .sigil = .system, .content = "Be kind." },
    };
    const body = try encode(arena, &records, .{ .model = "tiny" });
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const msgs = field(v, "messages").array.items;

    try testing.expectEqual(@as(usize, 2), msgs.len);
    try testing.expectEqualStrings("system", field(msgs[0], "role").string);
    try testing.expectEqualStrings("Be brief.\nBe kind.", field(msgs[0], "content").string);
    try testing.expectEqualStrings("user", field(msgs[1], "role").string);
}

test "calls gather onto the turn that made them, ahead of their answers" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .agent, .value = "local/tiny" },
        .{ .sigil = .bot, .content = "Let me look." },
        .{ .sigil = .call, .value = "say,c1", .content = "* text `hi`" },
        .{ .sigil = .result, .value = "c1", .content = "hi" },
        .{ .sigil = .call, .value = "say,c2", .content = "* text `bye`" },
        .{ .sigil = .failed, .value = "c2", .content = "nope" },
        .{ .sigil = .bot, .content = "Done." },
    };
    const body = try encode(arena, &records, .{ .model = "tiny" });
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const msgs = field(v, "messages").array.items;

    try testing.expectEqual(@as(usize, 4), msgs.len);
    try testing.expectEqualStrings("assistant", field(msgs[0], "role").string);
    try testing.expectEqualStrings("Let me look.", field(msgs[0], "content").string);

    const calls = field(msgs[0], "tool_calls").array.items;
    try testing.expectEqual(@as(usize, 2), calls.len);
    try testing.expectEqualStrings("c1", field(calls[0], "id").string);
    try testing.expectEqualStrings("say", field(field(calls[0], "function"), "name").string);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , field(field(calls[0], "function"), "arguments").string);

    // Both answers follow, and a 🚫 is a tool message like any other.
    try testing.expectEqualStrings("tool", field(msgs[1], "role").string);
    try testing.expectEqualStrings("c1", field(msgs[1], "tool_call_id").string);
    try testing.expectEqualStrings("c2", field(msgs[2], "tool_call_id").string);
    try testing.expectEqualStrings("nope", field(msgs[2], "content").string);
    try testing.expectEqualStrings("assistant", field(msgs[3], "role").string);
}

test "an answer that arrived late is still written beside its call" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // What a run that picked up an owed call leaves behind: the 📲 is history,
    // somebody said something, and only then was it answered.
    const records = [_]doc.Record{
        .{ .sigil = .call, .value = "say,c2", .content = "* text `bye`" },
        .{ .sigil = .user, .content = "Now say done." },
        .{ .sigil = .result, .value = "c2", .content = "bye" },
        .{ .sigil = .bot, .content = "Done." },
    };
    const body = try encode(arena, &records, .{ .model = "tiny" });
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const msgs = field(v, "messages").array.items;

    // assistant(c2), tool(c2), user, assistant — the tool answer moved up to
    // sit against the call, and is not written twice.
    try testing.expectEqual(@as(usize, 4), msgs.len);
    try testing.expectEqualStrings("assistant", field(msgs[0], "role").string);
    try testing.expectEqualStrings("c2", field(field(msgs[0], "tool_calls").array.items[0], "id").string);
    try testing.expectEqualStrings("tool", field(msgs[1], "role").string);
    try testing.expectEqualStrings("c2", field(msgs[1], "tool_call_id").string);
    try testing.expectEqualStrings("user", field(msgs[2], "role").string);
    try testing.expectEqualStrings("assistant", field(msgs[3], "role").string);
    try testing.expectEqualStrings("Done.", field(msgs[3], "content").string);
}

test "a call still owed is written without an answer" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .call, .value = "say,c1", .content = "* text `hi`" },
    };
    const body = try encode(arena, &records, .{ .model = "tiny" });
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const msgs = field(v, "messages").array.items;
    try testing.expectEqual(@as(usize, 1), msgs.len);
    try testing.expectEqual(@as(usize, 1), field(msgs[0], "tool_calls").array.items.len);
}

fn readerOver(bytes: []const u8) std.Io.Reader {
    return .fixed(bytes);
}

const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,
    /// The same stream, as the records it makes.
    got: api.Gather = .{ .arena = undefined },

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        self.got.arena = self.arena;
        self.got.open(s, value);
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
        try self.got.write(bytes);
    }
    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        _ = try self.got.close();
    }
};

test "a streamed response and a whole one read the same" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const streamed =
        \\data: {"choices":[{"delta":{"content":"Hello"}}]}
        \\
        \\data: {"choices":[{"delta":{"content":" world"}}]}
        \\
        \\data: [DONE]
        \\
    ;
    // No trailing newline: one whole JSON object is how a provider that
    // ignored `stream` answers, and it arrives without one.
    const at_once =
        \\{"choices":[{"message":{"role":"assistant","content":"Hello world"}}]}
    ;

    for ([_][]const u8{ streamed, at_once }) |body| {
        var r = readerOver(body);
        var collect: Collect = .{ .arena = arena };
        const reply = try parse(arena, &r, collect.sink());
        try testing.expectEqualStrings("Hello world", try collect.got.said(arena));
        // Streamed on the way past either way, so the reader sees the same.
        try testing.expectEqualStrings("Hello world", collect.seen.items);
        try testing.expectEqual(@as(usize, 0), reply.calls.len);
    }
}

test "a call is gathered whichever shape it came in" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Arguments arrive a fragment at a time, addressed by index.
    const streamed =
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"say"}}]}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"text\":"}}]}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"hi\"}"}}]}}]}
        \\
        \\data: [DONE]
        \\
    ;
    const at_once =
        \\{"choices":[{"message":{"content":null,"tool_calls":[
        \\{"id":"c1","function":{"name":"say","arguments":"{\"text\":\"hi\"}"}}]}}]}
    ;

    for ([_][]const u8{ streamed, at_once }) |body| {
        var r = readerOver(body);
        var collect: Collect = .{ .arena = arena };
        const reply = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), reply.calls.len);
        try testing.expectEqualStrings("c1", reply.calls[0].id);
        try testing.expectEqualStrings("say", reply.calls[0].name);
        try testing.expectEqualStrings(
            \\{"text":"hi"}
        , reply.calls[0].arguments);
    }
}

test "an error is what the api said, and the reply says so" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var r: std.Io.Reader = .fixed(
        \\{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}}
    );
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    const said = collect.got.records.items;
    try testing.expectEqual(@as(usize, 1), said.len);
    try testing.expectEqualStrings("(Incorrect API key provided. - failed with invalid_request_error)", said[0].value);
    try testing.expect(said[0].content == null);
}

test "a reply cut off says so last, in this api's own word" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const streamed =
        \\data: {"choices":[{"delta":{"content":"Moon"},"finish_reason":null}]}
        \\
        \\data: {"choices":[{"delta":{},"finish_reason":"length"}]}
        \\
        \\data: [DONE]
        \\
    ;
    const at_once =
        \\{"choices":[{"message":{"role":"assistant","content":"Moon"},"finish_reason":"length"}]}
    ;
    for ([_][]const u8{ streamed, at_once }) |body| {
        var r = readerOver(body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
        const last = collect.got.records.items[1];
        try testing.expectEqual(sigil.Sigil.bot, last.sigil);
        try testing.expectEqualStrings("(cut off at length)", last.value);
        try testing.expect(last.content == null);
        // What was said is still exactly what was said.
        try testing.expectEqualStrings("Moon", try collect.got.said(arena));
    }

    // Finishing and asking for tools are what the ledger already shows.
    for ([_][]const u8{ "stop", "tool_calls" }) |why| {
        const body = try std.fmt.allocPrint(arena,
            \\{{"choices":[{{"message":{{"role":"assistant","content":"Moon"}},"finish_reason":"{s}"}}]}}
        , .{why});
        var r = readerOver(body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
    }
}

test "a refusal is what the model said, and says it declined" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const streamed =
        \\data: {"choices":[{"delta":{"refusal":"I can't help"},"finish_reason":null}]}
        \\
        \\data: {"choices":[{"delta":{"refusal":" with that."},"finish_reason":null}]}
        \\
        \\data: {"choices":[{"delta":{},"finish_reason":"stop"}]}
        \\
        \\data: [DONE]
        \\
    ;
    const at_once =
        \\{"choices":[{"message":{"role":"assistant","content":null,"refusal":"I can't help with that."},"finish_reason":"stop"}]}
    ;
    for ([_][]const u8{ streamed, at_once }) |body| {
        var r = readerOver(body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
        try testing.expectEqualStrings("I can't help with that.", collect.got.records.items[0].content.?);
        try testing.expectEqualStrings("(declined with refusal)", collect.got.records.items[1].value);
    }
}

test "a 🤖 with nothing under it never reaches the wire" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Where converse puts it: after what was said, before the calls.
    const records = [_]doc.Record{
        .{ .sigil = .bot, .content = "Let me look." },
        .{ .sigil = .bot, .value = "(cut off at length)" },
        .{ .sigil = .call, .value = "say,c1", .content = "* text `hi`" },
        .{ .sigil = .result, .value = "c1", .content = "hi" },
    };
    const body = try encode(arena, &records, .{ .model = "tiny" });
    const msgs = field(try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{}), "messages").array.items;
    // The reply and its call are still one message.
    try testing.expectEqual(@as(usize, 2), msgs.len);
    try testing.expectEqualStrings("Let me look.", field(msgs[0], "content").string);
    try testing.expectEqual(@as(usize, 1), field(msgs[0], "tool_calls").array.items.len);
    try testing.expect(std.mem.indexOf(u8, body, "cut off") == null);
}

test "a response that says nothing is nothing, not a failure" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var empty = readerOver("");
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &empty, collect.sink());
    try testing.expectEqualStrings("", try collect.got.said(arena));
    try testing.expectEqual(@as(usize, 0), reply.calls.len);
}

test "files a 🔗 hands over go out beside the answer, uploaded or whole" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var records = [_]doc.Record{
        .{ .sigil = .call, .value = "see,c1", .content = "* file `a.jpeg`" },
        .{ .sigil = .result, .value = "c1", .content = "here" },
        .{ .sigil = .link, .value = "c1", .content = ">image/jpeg data:image/jpeg;base64,YWJj a.jpeg\n>application/pdf data:application/pdf;base64,YWJj b.pdf" },
        .{ .sigil = .ok, .value = "c1" },
    };
    const body = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, body, \\{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,YWJj"}},{"type":"file","file":{"filename":"b.pdf","file_data":"data:application/pdf;base64,YWJj"}}]}
    ) != null);

    // An image part takes a url alone, so an uploaded image cannot be shown.
    records[2].content = ">image/jpeg ref:file-a a.jpeg";
    try testing.expectError(error.UnsupportedLink, encode(arena, &records, .{ .model = "m" }));

    // A file never handed over, for want of an upload, cannot be sent.
    records[2].content = "<a.jpeg";
    try testing.expectError(error.NoUpload, encode(arena, &records, .{ .model = "m" }));
}
