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
    .decode = decode,
    .parse = parse,
};

// ------------------------------------------------------------------ encode

pub fn encode(arena: Allocator, records: []const doc.Record, target: api.Target) ![]const u8 {
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
            .call, .result, .ok, .failed => {},
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

    for (records[start..end]) |r| {
        if (r.sigil != .call) continue;
        if (try answerTo(arena, records, claimed, start, callId(r.value))) |back|
            try simple(s, "tool", back, callId(r.value));
    }

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
) !?[]const u8 {
    var said: std.ArrayList(u8) = .empty;
    var found = false;

    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, r.value, " \t"), id)) continue;

        claimed[idx] = true;
        found = true;
        const content = r.content orelse continue;
        if (content.len == 0) continue;
        if (said.items.len > 0) try said.append(arena, '\n');
        try said.appendSlice(arena, content);

        // A verdict ends the answer; anything later with this id answers a
        // call made again rather than this one.
        if (r.sigil != .result) break;
    }
    return if (found) said.items else null;
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

    var line = first;
    while (true) {
        if (std.mem.startsWith(u8, line, "data:")) {
            const payload = std.mem.trim(u8, line["data:".len..], " ");
            if (std.mem.eql(u8, payload, "[DONE]")) break;
            if (std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{})) |v| {
                // Reasoning before content: a server that puts both in one
                // delta means the thinking came first.
                if (extractReasoning(v)) |fragment| try built.to(.thought, fragment);
                if (extractDelta(v)) |fragment| try built.to(.bot, fragment);
                try gatherCalls(arena, &building, v);
            } else |_| {}
        }
        const raw = (try api.nextLine(arena, r)) orelse break;
        line = std.mem.trimEnd(u8, raw, "\r\n");
    }
    try built.stop();
    return built.reply(try finish(arena, building.items));
}

/// One JSON object, from a provider that answered all at once.
fn whole(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, first);
    const rest = try r.allocRemaining(arena, .unlimited);
    try body.appendSlice(arena, rest);

    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, body.items, .{}) catch
        return error.MalformedResponse;

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
    try built.stop();

    var building: std.ArrayList(Building) = .empty;
    if (message.object.get("tool_calls")) |list| if (list == .array) {
        for (list.array.items) |item| try gatherOne(arena, &building, item);
    };
    return built.reply(try finish(arena, building.items));
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
    records: std.ArrayList(doc.Record) = .empty,
    open: ?sigil.Sigil = null,
    buf: std.ArrayList(u8) = .empty,

    fn to(self: *Run, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        if (self.open != s) {
            try self.stop();
            try self.sink.begin(s, "");
            self.open = s;
        }
        try self.buf.appendSlice(self.arena, fragment);
        try self.sink.text(fragment);
    }

    fn stop(self: *Run) !void {
        const s = self.open orelse return;
        try self.sink.end();
        try self.records.append(self.arena, .{
            .sigil = s,
            .content = try self.arena.dupe(u8, self.buf.items),
        });
        self.buf.clearRetainingCapacity();
        self.open = null;
    }

    /// The records, with the calls written on the end as 📲 — which is where
    /// this api puts them, since it gathers a turn's calls after its text
    /// rather than in among it.
    fn reply(self: *Run, calls: []const api.Call) !api.Reply {
        for (calls) |c| try self.records.append(self.arena, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(self.arena, "{s},{s}", .{ c.name, c.id }),
            .content = try toolbox.renderArgs(self.arena, .md, c.arguments),
        });
        return .{ .records = self.records.items, .calls = calls };
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

fn extractDelta(v: std.json.Value) ?[]const u8 {
    const delta = deltaOf(v) orelse return null;
    const content = delta.object.get("content") orelse return null;
    return if (content == .string) content.string else null;
}

// ------------------------------------------------------------------ decode

pub fn decode(arena: Allocator, bytes: []const u8) ![]const doc.Record {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, api.request_options);
    if (v != .object) return error.MalformedRequest;

    var out: std.ArrayList(doc.Record) = .empty;

    // Everything the request asked for, back onto the 🧠 that asked. m8 knows
    // none of these by name, so one it has never heard of comes back too.
    //
    // Nothing on the wire says whose model it was. That is the one loss the
    // round trip is allowed, and naming a provider at `send` is what answers
    // it.
    if (str(v.object.get("model"))) |name| {
        var params: std.ArrayList(modelform.Param) = .empty;
        var it = v.object.iterator();
        while (it.next()) |e| {
            if (structural(e.key_ptr.*)) continue;
            try params.append(arena, .{
                .key = e.key_ptr.*,
                .value = try modelform.written(arena, e.value_ptr.*),
            });
        }
        try out.append(arena, .{
            .sigil = .agent,
            .value = try modelform.render(arena, .{ .name = name, .params = params.items }),
        });
    }

    if (v.object.get("tools")) |tools| if (tools == .array) {
        for (tools.array.items) |t| try readTool(arena, &out, t);
    };

    const messages = v.object.get("messages") orelse return out.items;
    if (messages != .array) return out.items;
    for (messages.array.items) |m| try readMessage(arena, &out, m);
    return out.items;
}

fn readMessage(arena: Allocator, out: *std.ArrayList(doc.Record), m: std.json.Value) !void {
    if (m != .object) return;
    const role = str(m.object.get("role")) orelse return;
    const content = str(m.object.get("content")) orelse "";

    if (std.mem.eql(u8, role, "system")) {
        try out.append(arena, .{ .sigil = .system, .content = content });
    } else if (std.mem.eql(u8, role, "user")) {
        try out.append(arena, .{ .sigil = .user, .content = content });
    } else if (std.mem.eql(u8, role, "tool")) {
        // Nothing here says whether the tool succeeded, so it comes back a 🧾.
        try out.append(arena, .{
            .sigil = .result,
            .value = str(m.object.get("tool_call_id")) orelse "",
            .content = content,
        });
    } else if (std.mem.eql(u8, role, "assistant")) {
        if (content.len > 0)
            try out.append(arena, .{ .sigil = .bot, .content = content });
        const calls = m.object.get("tool_calls") orelse return;
        if (calls != .array) return;
        for (calls.array.items) |c| {
            if (c != .object) continue;
            const id = str(c.object.get("id")) orelse "";
            const f = c.object.get("function") orelse continue;
            if (f != .object) continue;
            const name = str(f.object.get("name")) orelse "";
            const args = str(f.object.get("arguments")) orelse "{}";
            try out.append(arena, .{
                .sigil = .call,
                .value = try std.fmt.allocPrint(arena, "{s},{s}", .{ name, id }),
                .content = try toolbox.renderArgs(arena, .md, args),
            });
        }
    }
}

/// A tool on the wire is a schema, so this is the inverse of
/// `toolbox.writeSchema`: nested objects flatten back to dotted paths, an
/// array's items give the `[]` suffix, and an enum's values rejoin with `|`.
/// The 🔌 is not here to be recovered — it never went out.
fn readTool(arena: Allocator, out: *std.ArrayList(doc.Record), t: std.json.Value) !void {
    if (t != .object) return;
    const f = t.object.get("function") orelse return;
    if (f != .object) return;
    const name = str(f.object.get("name")) orelse return;

    var props: std.ArrayList(toolbox.Property) = .empty;
    if (f.object.get("parameters")) |params|
        try toolbox.readParameters(arena, &props, params);

    const tool: toolbox.Tool = .{
        .name = name,
        .description = str(f.object.get("description")) orelse "",
        .properties = props.items,
    };
    try out.append(arena, .{
        .sigil = .tool,
        .value = name,
        .content = try toolbox.render(arena, .md, tool),
    });
    // Being on the wire at all is what it means for a tool to be offered, and
    // a 🧰 with no block is how that is said.
    try out.append(arena, .{ .sigil = .tool, .value = name });
}

/// The fields that are the request's shape rather than something asked for.
/// `stream` is among them: it belongs to a run, not to a conversation, and m8
/// decides it each time.
fn structural(key: []const u8) bool {
    for ([_][]const u8{ "model", "messages", "tools", "stream" }) |k| {
        if (std.mem.eql(u8, key, k)) return true;
    }
    return false;
}

fn str(v: ?std.json.Value) ?[]const u8 {
    const got = v orelse return null;
    return if (got == .string) got.string else null;
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

test "a request decodes back to a ledger that encodes to the same request" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const tool: toolbox.Tool = .{
        .name = "shell",
        .description = "Runs a command.",
        .properties = &.{
            .{ .name = "cmd", .type = "string", .description = "What to run.", .required = true },
            .{ .name = "with", .type = "check|sandbox", .required = false },
            .{ .name = "tags", .type = "string[]", .required = false },
            .{ .name = "opts", .type = "object", .required = false },
            .{ .name = "opts.depth", .type = "integer", .required = true },
        },
    };
    const records = [_]doc.Record{
        .{ .sigil = .system, .content = "Be brief." },
        .{ .sigil = .user, .content = "Hi." },
        .{ .sigil = .bot, .content = "" },
        .{ .sigil = .call, .value = "shell,c1", .content = "* cmd `ls`" },
        .{ .sigil = .result, .value = "c1", .content = "a\nb" },
    };
    const first = try encode(arena, &records, .{
        .model = "tiny",
        .params = &.{
            .{ .key = "max_tokens", .value = "2048" },
            // One m8 has never heard of, to show it is not a list of known
            // names doing the work.
            .{ .key = "reasoning_effort", .value = "high" },
        },
        .tools = &.{tool},
    });

    const back = try decode(arena, first);
    // 🧠 carries the model and everything that was asked for, so nothing has
    // to be looked up to send it again. Both 🧰 records come back too.
    try testing.expectEqual(doc.Sigil.agent, back[0].sigil);
    try testing.expectEqualStrings(
        "/tiny,max_tokens:2048,reasoning_effort:high",
        back[0].value,
    );
    try testing.expectEqual(doc.Sigil.tool, back[1].sigil);
    try testing.expectEqual(doc.Sigil.tool, back[2].sigil);

    // And what comes back off the wire goes out again unchanged.
    const m = (try modelform.parse(arena, back[0].value)).?;
    const again = try encode(arena, back, .{
        .model = m.name,
        .params = m.params,
        .tools = &.{try toolbox.parse(arena, .md, back[1].value, back[1].content.?)},
    });
    try testing.expectEqualStrings(first, again);
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

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(_: *anyopaque, _: sigil.Sigil, _: []const u8) anyerror!void {}
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
    }
    fn closeFn(_: *anyopaque) anyerror!void {}
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
        try testing.expectEqualStrings("Hello world", try reply.said(arena));
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

test "a response that says nothing is nothing, not a failure" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var empty = readerOver("");
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &empty, collect.sink());
    try testing.expectEqualStrings("", try reply.said(arena));
    try testing.expectEqual(@as(usize, 0), reply.calls.len);
}
