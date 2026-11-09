//! The OpenAI responses api.
//!
//! The one wire format whose shape a ledger already has. Chat completions
//! wants a leading system message and a turn per role; messages wants runs of
//! blocks under alternating roles. This wants a flat list of items in the
//! order they happened, which is what a ledger is — so there is no reordering
//! here and no grouping, only a translation of one record at a time. The
//! system prompt is hoisted, because it is a field of its own rather than an
//! item, and that is the whole of the projection.
//!
//! What it carries that chat completions cannot:
//!
//! * A thought is a `reasoning` item with `encrypted_content`, so 💭 and its
//!   🔏 survive the round trip. Summary parts come back as compact value-only
//!   💭 records when they are one line; the 🔏 holds `id,encrypted_content` —
//!   two fields, because this api needs both to believe a thought it is handed
//!   back. m8 reads neither; a signature is opaque here as everywhere.
//! * A tool answer carries `status`, which is `in_progress`, `completed` or
//!   `incomplete`.
//!
//! That second one is worth being exact about, because it looks like the
//! thing it is not. `status` says whether the output finished, not whether
//! the tool succeeded — a tool that ran to the end and said "permission
//! denied" is `completed`. So it is the 🧾 half of an answer and not the
//! 🟢/🚫 half, and this api has no field for the verdict at all. Where
//! messages recovers the verdict and loses the completeness, this is the
//! other way about; between the three of them no api carries both, which is
//! why m8 needs three records to say what one of them means.
//!
//! Nothing here writes `status`. It would be honest to — a 🧾 with no verdict
//! under it is exactly `incomplete` — but no client that speaks this api
//! writes one either: Codex's own does not, Pi does not and does not read one
//! back, and neither does the opencode auth plugin. A field nobody sends is a
//! field nobody has agreed the meaning of, so it stays out.
//!
//! Read against three implementations, because this api is large and most of
//! it is not a ledger's business: Codex's `codex-rs/core/src/client.rs`, Pi's
//! `packages/ai/src/api/openai-responses*.ts`, and opencode's codex auth
//! plugin. Endpoint defaults such as `store` and `include` belong to provider
//! configuration or explicit model parameters, not the wire format.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const modelform = @import("../m8/model.zig");
const toolbox = @import("../toolbox.zig");
const api = @import("../codec.zig");

pub const codec_name = "openai-responses";

pub const codec: api.Codec = .{
    .name = codec_name,
    .summary = "OpenAI responses",
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
    for (target.params) |p| {
        try s.objectField(p.key);
        try s.write(modelform.json(arena, p.value));
    }

    try writeInstructions(arena, &s, records);

    try s.objectField("input");
    try s.beginArray();
    try writeInput(arena, &s, records);
    try s.endArray();

    if (target.tools.len > 0) {
        try s.objectField("tools");
        try s.beginArray();
        for (target.tools) |t| {
            // Flat, where chat completions nests the same thing under
            // `function`. The schema below it is the same schema.
            try s.beginObject();
            try s.objectField("type");
            try s.write("function");
            try s.objectField("name");
            try s.write(t.name);
            if (t.description.len > 0) {
                try s.objectField("description");
                try s.write(t.description);
            }
            try s.objectField("parameters");
            try toolbox.writeParameters(&s, t.properties);
            try s.endObject();
        }
        try s.endArray();
    }
    try s.endObject();
    return buf.written();
}

/// Every 🧭, joined into the field this api keeps them in. A ledger may hold
/// several, anywhere; the api has one, and it is not an item.
fn writeInstructions(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    var text: std.ArrayList(u8) = .empty;
    for (records) |r| {
        if (r.sigil != .system) continue;
        const c = r.content orelse continue;
        if (text.items.len > 0) try text.append(arena, '\n');
        try text.appendSlice(arena, c);
    }
    if (text.items.len == 0) return;
    try s.objectField("instructions");
    try s.write(text.items);
}

/// The ledger, an item at a time and in its own order.
///
/// The only thing gathered is an answer: a call is answered by what the tool
/// said and then by how it went, and this api has one item to say both in. So
/// the records for one id become one `function_call_output`, written where
/// the first of them stands.
fn writeInput(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    const claimed = try arena.alloc(bool, records.len);
    @memset(claimed, false);

    for (records, 0..) |r, i| {
        switch (r.sigil) {
            .user => try message(s, "user", r.content orelse ""),
            .bot => try message(s, "assistant", r.content orelse ""),
            .thought => if (try signed(arena, api.thoughtText(r))) |thought|
                try reasoning(s, try owedTo(arena, records, i, thought)),
            .call => {
                try s.beginObject();
                try s.objectField("type");
                try s.write("function_call");
                try s.objectField("call_id");
                try s.write(callId(r.value));
                try s.objectField("name");
                try s.write(callName(r.value));
                try s.objectField("arguments");
                // A JSON string, as this api and chat completions both want.
                // A call that does not read was failed, and goes out with
                // nothing.
                try s.write(toolbox.parseArgs(arena, .md, r.content orelse "") catch "{}");
                try s.endObject();
            },
            .result, .scroll, .link, .ok, .failed => {
                if (claimed[i]) continue;
                const id = std.mem.trim(u8, r.value, " \t");
                const a = try answerTo(arena, records, claimed, i, id);
                try s.beginObject();
                try s.objectField("type");
                try s.write("function_call_output");
                try s.objectField("call_id");
                try s.write(id);
                try s.objectField("output");
                try writeOutput(s, a.said, a.links);
                try s.endObject();
            },
            else => {},
        }
    }
}

/// Everything answering `id` from `from` onward, joined, and marked so it is
/// not written again where it stands.
///
/// A verdict ends the answer; anything later with this id answers a call made
/// again rather than this one. 🟢 and 🚫 have no field here, so what a failure
/// said is all that survives of it — this api cannot tell one from the other
/// and never could.
fn answerTo(
    arena: Allocator,
    records: []const doc.Record,
    claimed: []bool,
    from: usize,
    id: []const u8,
) !Answer {
    var said: std.ArrayList(u8) = .empty;
    var links: std.ArrayList([]const u8) = .empty;
    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .scroll, .link, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, r.value, " \t"), id)) continue;

        claimed[idx] = true;
        if (r.sigil == .link) {
            try links.append(arena, r.content orelse "");
            continue;
        }
        if (r.content) |content| if (content.len > 0) {
            if (said.items.len > 0) try said.append(arena, '\n');
            try said.appendSlice(arena, content);
        };
        if (r.sigil != .result and r.sigil != .scroll) break;
    }
    return .{ .said = said.items, .links = links.items };
}

/// What answered a call: what was said, and the 🔗 blocks beside it.
const Answer = struct { said: []const u8, links: []const []const u8 };

/// An output is a string, unless files were handed over beside it, when it
/// is a list of parts.
fn writeOutput(s: *std.json.Stringify, said: []const u8, links: []const []const u8) !void {
    if (links.len == 0) return s.write(said);
    try s.beginArray();
    if (said.len > 0) try inputText(s, said);
    for (links) |content| {
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const mime, const uri, const name = (try api.handed(line)) orelse continue;
            const image = std.mem.startsWith(u8, mime, "image/");
            try s.beginObject();
            try s.objectField("type");
            try s.write(if (image) "input_image" else "input_file");
            if (std.mem.cutPrefix(u8, uri, "ref:")) |id| {
                try s.objectField("file_id");
                try s.write(id);
            } else if (image) {
                try s.objectField("image_url");
                try s.write(uri);
            } else if (std.mem.startsWith(u8, uri, "data:")) {
                try s.objectField("filename");
                try s.write(name);
                try s.objectField("file_data");
                try s.write(uri);
            } else {
                try s.objectField("file_url");
                try s.write(uri);
            }
            try s.endObject();
        }
    }
    try s.endArray();
}

fn inputText(s: *std.json.Stringify, text: []const u8) !void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("input_text");
    try s.objectField("text");
    try s.write(text);
    try s.endObject();
}

fn message(s: *std.json.Stringify, role: []const u8, content: []const u8) !void {
    try s.beginObject();
    try s.objectField("role");
    try s.write(role);
    try s.objectField("content");
    try s.write(content);
    try s.endObject();
}

fn reasoning(s: *std.json.Stringify, thought: Thought) !void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("reasoning");
    try s.objectField("id");
    try s.write(thought.id);
    try s.objectField("summary");
    try s.beginArray();
    for (thought.parts) |part| {
        try s.beginObject();
        try s.objectField("type");
        try s.write("summary_text");
        try s.objectField("text");
        try s.write(part);
        try s.endObject();
    }
    try s.endArray();
    try s.objectField("encrypted_content");
    try s.write(thought.encrypted);
    try s.endObject();
}

/// A 💭's content split into what was thought and what signs it.
///
/// The 🔏 here is `id,encrypted_content`, because this api wants both back
/// before it will believe a thought. `,` separates a fixed number of fields
/// and the last may hold one, which is the grammar's rule and not this
/// codec's exception to it.
const Thought = struct {
    /// One per summary part: each is a 💭 of its own in the ledger.
    parts: []const []const u8 = &.{},
    id: []const u8 = "",
    encrypted: []const u8 = "",
};

fn signed(arena: Allocator, content: []const u8) !?Thought {
    var text: std.ArrayList(u8) = .empty;
    var mark: []const u8 = "";
    var said = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (try api.signatureOn(arena, line)) |value| {
            mark = value;
            continue;
        }
        if (said) try text.append(arena, '\n');
        said = true;
        try text.appendSlice(arena, line);
    }
    // A thought this api never signed is one it will not take back.
    if (mark.len == 0) return null;
    const cut = std.mem.indexOfScalar(u8, mark, ',') orelse return null;
    const parts: []const []const u8 = if (text.items.len == 0)
        &.{}
    else
        try arena.dupe([]const u8, &.{text.items});
    return .{
        .parts = parts,
        .id = std.mem.trim(u8, mark[0..cut], " \t"),
        .encrypted = std.mem.trim(u8, mark[cut + 1 ..], " \t"),
    };
}

/// A signed thought with the unsigned 💭 just before it gathered back in as
/// its summary: an item is written as a 💭 per part and then its 🔏 kept
/// aside, and this api wants them as one item again.
fn owedTo(arena: Allocator, records: []const doc.Record, at: usize, thought: Thought) !Thought {
    var from = at;
    while (from > 0 and records[from - 1].sigil == .thought and
        (try signed(arena, api.thoughtText(records[from - 1]))) == null) from -= 1;
    if (from == at) return thought;

    var parts: std.ArrayList([]const u8) = .empty;
    for (records[from..at]) |r| try parts.append(arena, api.thoughtText(r));
    try parts.appendSlice(arena, thought.parts);
    return .{ .parts = parts.items, .id = thought.id, .encrypted = thought.encrypted };
}

/// A reasoning item's 🔏, as a 💭 of its own asking to be kept aside. The
/// summary is for reading and the encrypted content only for giving the
/// thought back, so only the summary stays in sight.
fn signature(
    arena: Allocator,
    out: *std.ArrayList(doc.Record),
    id: []const u8,
    enc: []const u8,
) !void {
    if (id.len == 0 and enc.len == 0) return;
    try out.append(arena, .{ .sigil = .thought, .value = api.snip, .content = try sealed(arena, id, enc) });
}

/// A 🔏 as content: the item's id and its encrypted content, as one span.
fn sealed(arena: Allocator, id: []const u8, enc: []const u8) ![]const u8 {
    return api.sealed(arena, try std.fmt.allocPrint(arena, "{s},{s}", .{ id, enc }));
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
    while (true) {
        const raw = (try api.nextLine(arena, r)) orelse return .{};
        const line = std.mem.trimEnd(u8, raw, "\r\n");
        if (std.mem.trim(u8, line, " \t").len == 0) continue;

        if (std.mem.startsWith(u8, line, "data:") or std.mem.startsWith(u8, line, "event:"))
            return events(arena, r, sink, line);
        return whole(arena, r, sink, raw);
    }
}

/// Server-sent events may interleave output items. Only the earliest item
/// streams to the sink; later items wait until it closes, keeping both tool
/// arguments and the sink's single open record attached to their own item.
fn events(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var stream: Stream = .{ .arena = arena, .sink = sink };

    var line = first;
    while (true) {
        if (std.mem.startsWith(u8, line, "data:")) {
            const payload = std.mem.trim(u8, line["data:".len..], " ");
            if (std.mem.eql(u8, payload, "[DONE]")) {
                stream.terminal = true;
                break;
            }
            if (std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{})) |v| {
                if (try stream.accept(v)) break;
            } else |_| return error.InvalidResponseJson;
        }
        const raw = (try api.nextLine(arena, r)) orelse break;
        line = std.mem.trimEnd(u8, raw, "\r\n");
    }
    return stream.finish();
}

const Stream = struct {
    arena: Allocator,
    sink: api.Sink,
    items: std.ArrayList(Item) = .empty,
    calls: std.ArrayList(api.Call) = .empty,
    next: i64 = 0,
    reason: []const u8 = "",
    incomplete: bool = false,
    terminal: bool = false,
    refused: bool = false,

    const Item = struct {
        index: i64,
        id: []const u8,
        built: Building,
        waiting: ?*api.Gather = null,
        closed: bool = false,
    };

    fn accept(s: *Stream, v: std.json.Value) !bool {
        if (v != .object) return false;
        const kind = str(v.object.get("type")) orelse return false;
        const index = if (v.object.get("output_index")) |value|
            num(value) orelse return error.InvalidOutputIndex
        else
            null;
        if (index) |n| if (n < 0) return error.InvalidOutputIndex;
        const item = v.object.get("item");
        const event_id = str(v.object.get("item_id"));
        const item_id = if (item != null and item.? == .object) str(item.?.object.get("id")) else null;
        if (event_id != null and item_id != null and !std.mem.eql(u8, event_id.?, item_id.?))
            return error.OutputItemIdMismatch;
        const id = event_id orelse item_id;

        // The final output item carries the content of these notices, even
        // when a gateway supplies an item only at completion.
        if (std.mem.eql(u8, kind, "response.output_text.done") or
            std.mem.eql(u8, kind, "response.content_part.done")) return false;

        const added = std.mem.eql(u8, kind, "response.output_item.added");
        const done = std.mem.eql(u8, kind, "response.output_item.done");
        if (added or done) {
            const n = index orelse return error.MissingOutputIndex;
            if (n < s.next) return error.EventForClosedOutputItem;
            if (item == null or item.? != .object) return error.InvalidOutputItem;
            const known = for (s.items.items) |existing| {
                if (existing.index == n) break true;
            } else false;
            if (added and known) return error.DuplicateOutputItem;
            if (!known) {
                for (s.items.items) |existing| {
                    if (id != null and std.mem.eql(u8, existing.id, id.?))
                        return error.DuplicateOutputItem;
                }
                const waiting = if (n == s.next) null else blk: {
                    const gather = try s.arena.create(api.Gather);
                    gather.* = .{ .arena = s.arena };
                    break :blk gather;
                };
                var built: Building = .{
                    .arena = s.arena,
                    .sink = if (waiting) |g| g.sink() else s.sink,
                };
                try built.start(item.?);
                try s.items.append(s.arena, .{ .index = n, .id = id orelse "", .built = built, .waiting = waiting });
            }
        }

        if (index != null or id != null) {
            const target = for (s.items.items) |*candidate| {
                if (if (index) |n| candidate.index == n else std.mem.eql(u8, candidate.id, id.?))
                    break candidate;
            } else return error.UnknownOutputItem;
            if (target.index < s.next or target.closed) return error.EventForClosedOutputItem;
            if (id) |got| {
                if (target.id.len == 0) {
                    for (s.items.items) |existing| {
                        if (existing.index != target.index and std.mem.eql(u8, existing.id, got))
                            return error.OutputItemIdMismatch;
                    }
                    target.id = got;
                } else if (!std.mem.eql(u8, target.id, got)) return error.OutputItemIdMismatch;
            }
            if (done) {
                const item_kind = str(item.?.object.get("type")) orelse return error.InvalidOutputItem;
                if (target.built.kind != .none and !std.mem.eql(u8, item_kind, @tagName(target.built.kind)))
                    return error.OutputItemTypeMismatch;
                try target.built.settle(item.?);
                try target.built.stop();
                target.closed = true;
            } else if (!added) try delta(&target.built, v);
            try s.drain(false);
            return false;
        }

        if (std.mem.startsWith(u8, kind, "response.output_") or
            std.mem.startsWith(u8, kind, "response.function_call_arguments.") or
            std.mem.startsWith(u8, kind, "response.reasoning_") or
            std.mem.startsWith(u8, kind, "response.refusal.")) return error.MissingOutputItemIdentity;
        const response = v.object.get("response") orelse .null;
        const status = if (response == .object) str(response.object.get("status")) orelse "" else "";
        if (std.mem.eql(u8, kind, "response.failed") or std.mem.eql(u8, kind, "error") or std.mem.eql(u8, status, "failed")) {
            s.terminal = true;
            try s.drain(true);
            s.calls.clearRetainingCapacity();
            try fail(s.arena, s.sink, v);
            return true;
        }
        if (std.mem.eql(u8, kind, "response.completed") or std.mem.eql(u8, kind, "response.incomplete")) {
            s.terminal = true;
            s.incomplete = std.mem.eql(u8, kind, "response.incomplete") or std.mem.eql(u8, status, "incomplete");
            if (s.incomplete) s.reason = incompleteOf(response);
            return true;
        }
        return false;
    }

    /// Only the earliest output slot may own the live sink. Other items
    /// accumulate records, not wire events, until that slot reaches them.
    fn drain(s: *Stream, ending: bool) !void {
        while (true) {
            var target: ?*Item = null;
            for (s.items.items) |*candidate| {
                if (candidate.index < s.next) continue;
                if (!ending and candidate.index != s.next) continue;
                if (target == null or candidate.index < target.?.index) target = candidate;
            }
            const current = target orelse return;
            if (current.waiting) |g| {
                for (g.records.items) |record|
                    try s.sink.record(record.sigil, record.value, record.content orelse "");
                if (current.built.shown) {
                    try s.sink.begin(g.pending, g.value);
                    try s.sink.text(g.text.items);
                }
                current.waiting = null;
                current.built.sink = s.sink;
            }
            if (!current.closed and !ending) return;
            if (current.built.kind != .none) try current.built.stop();
            try s.calls.appendSlice(s.arena, current.built.calls.items);
            s.refused = s.refused or current.built.refused;
            s.next = std.math.add(i64, current.index, 1) catch return error.InvalidOutputIndex;
        }
    }

    fn finish(s: *Stream) !api.Reply {
        for (s.items.items) |item| {
            if (!item.closed and item.built.kind == .function_call) s.incomplete = true;
        }
        try s.drain(true);
        if (s.calls.items.len > 0 and !s.terminal) s.incomplete = true;
        if (s.incomplete and s.reason.len == 0) s.reason = "incomplete";
        const reason = if (s.refused and s.reason.len == 0) "refusal" else s.reason;
        try api.stopped(s.arena, s.sink, stops, reason);
        if (s.incomplete) return error.IncompleteResponse;
        return .{ .calls = s.calls.items };
    }
};

/// A fragment applied directly to the item named by its event.
fn delta(built: *Building, v: std.json.Value) !void {
    const kind = str(v.object.get("type")) orelse return;
    if (std.mem.eql(u8, kind, "response.output_text.delta")) {
        if (str(v.object.get("delta"))) |d| try built.say(.bot, d);
    } else if (std.mem.eql(u8, kind, "response.refusal.delta")) {
        if (str(v.object.get("delta"))) |d| try built.say(.bot, d);
        built.refused = true;
    } else if (std.mem.eql(u8, kind, "response.reasoning_summary_text.delta") or
        std.mem.eql(u8, kind, "response.reasoning_text.delta"))
    {
        // Two channels, one sigil. A model that summarises its thinking and
        // one that shows it are both thinking, and the ledger says so the
        // same way — a 💭 per part, so one heading never runs into the next.
        const index = num(v.object.get("summary_index")) orelse num(v.object.get("content_index")) orelse 0;
        if (index != built.part) try built.nextPart(index);
        if (str(v.object.get("delta"))) |d| try built.say(.thought, d);
    } else if (std.mem.eql(u8, kind, "response.reasoning_summary_part.done")) {
        // Said now rather than when the next part opens, which may be a long
        // think away, or never: the last part would wait for the whole item.
        if (built.kind == .reasoning) try built.nextPart(built.part);
    } else if (std.mem.eql(u8, kind, "response.function_call_arguments.delta")) {
        if (str(v.object.get("delta"))) |d| try built.args.appendSlice(built.arena, d);
    } else if (std.mem.eql(u8, kind, "response.function_call_arguments.done")) {
        if (built.kind == .function_call) {
            if (str(v.object.get("arguments"))) |arguments| {
                built.args = .empty;
                try built.args.appendSlice(built.arena, arguments);
            }
        }
    }
}

/// One JSON object, from a provider that answered all at once.
fn whole(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, first);
    try body.appendSlice(arena, try r.allocRemaining(arena, .unlimited));

    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, body.items, .{}) catch
        return error.InvalidResponseJson;
    if (v != .object) return error.InvalidResponseObject;
    if (v.object.get("error")) |e| if (e != .null) {
        try fail(arena, sink, v);
        return .{};
    };
    if (str(v.object.get("status"))) |status| if (std.mem.eql(u8, status, "failed")) {
        try fail(arena, sink, v);
        return .{};
    };

    var built: Building = .{ .arena = arena, .sink = sink };
    if (str(v.object.get("status"))) |status| if (std.mem.eql(u8, status, "incomplete")) {
        built.incomplete = true;
        built.reason = incompleteOf(v);
    };
    const output = v.object.get("output") orelse {
        // Not a response at all, so whatever it is is why there is none: a
        // gateway's `{"detail": ...}` on a refused request, say.
        if (built.reason.len == 0) {
            try fail(arena, sink, v);
            return .{};
        }
        return built.finish();
    };
    if (output != .array) return built.finish();
    for (output.array.items) |item| {
        if (item != .object) continue;
        try built.start(item);
        try built.settle(item);
        try built.stop();
    }
    return built.finish();
}

/// The useful part of a failed event. OpenAI documents `response.error`, but
/// compatible providers (and some gateways) put the same information beside
/// the status or on the event itself. Prefer the documented location while
/// still looking farther when it contains no explanatory text.
fn failureOf(event_value: std.json.Value) ?std.json.Value {
    if (event_value != .object) return null;
    const event_object = event_value.object;
    const response = event_object.get("response");
    var fallback: ?std.json.Value = null;

    if (response) |resp| if (resp == .object) {
        if (resp.object.get("error")) |e| if (e != .null) {
            if (hasFailureText(e)) return e;
            fallback = e;
        };
        if (resp.object.get("status_details")) |details| if (details == .object) {
            if (details.object.get("error")) |e| if (e != .null) {
                if (hasFailureText(e)) return e;
                if (fallback == null) fallback = e;
            };
        };
    };
    // In a non-streamed reply the response itself is the top-level object.
    if (event_object.get("status_details")) |details| if (details == .object) {
        if (details.object.get("error")) |e| if (e != .null) {
            if (hasFailureText(e)) return e;
            if (fallback == null) fallback = e;
        };
    };
    if (event_object.get("error")) |e| if (e != .null) {
        if (hasFailureText(e)) return e;
        if (fallback == null) fallback = e;
    };

    // Return the holder, not just its text, so a code or type beside the
    // fallback message remains visible in `(message - failed with code)`.
    if (hasFailureText(event_value)) return event_value;
    if (response) |resp| if (hasFailureText(resp)) return resp;
    if (fallback) |f| if (hasTerm(f)) return f;
    return null;
}

/// Say the failure: by what it said of itself, or with nothing anywhere
/// saying why, by what arrived.
fn fail(arena: Allocator, sink: api.Sink, event_value: std.json.Value) !void {
    if (failureOf(event_value)) |e| return api.failed(arena, sink, e);
    var raw: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(event_value, .{}, &raw.writer);
    try api.failedWith(arena, sink, raw.written());
}

fn hasTerm(value: std.json.Value) bool {
    if (value != .object) return false;
    for ([_][]const u8{ "code", "type" }) |name| {
        if (str(value.object.get(name))) |text| if (text.len > 0) return true;
    }
    return false;
}

fn hasFailureText(value: std.json.Value) bool {
    if (value == .string) return value.string.len > 0;
    if (value != .object) return false;
    for ([_][]const u8{ "message", "summary", "detail" }) |name| {
        if (str(value.object.get(name))) |text| if (text.len > 0) return true;
    }
    return false;
}

/// Why a response is incomplete, in this api's words. Completing says nothing
/// here at all: only an incomplete response carries a reason.
const stops = api.Stops.initComptime(.{
    .{ "max_output_tokens", "cut off at" },
    .{ "content_filter", "filtered by" },
    .{ "refusal", "declined with" },
});

/// The reason an incomplete response gives, or the status itself when it
/// gives none, so that being cut off is never what goes unsaid.
fn incompleteOf(response: std.json.Value) []const u8 {
    if (response != .object) return "incomplete";
    const details = response.object.get("incomplete_details") orelse return "incomplete";
    if (details != .object) return "incomplete";
    return str(details.object.get("reason")) orelse "incomplete";
}

/// The item being read, and the reply being built out of the items that were.
///
/// The streamed and the whole shapes differ only in whether the content
/// arrives between `added` and `done` or was in the item all along, which is
/// what lets one machine read both: `start` takes what an item opens with,
/// `settle` takes what it closes with, and `stop` turns it into records.
const Building = struct {
    arena: Allocator,
    sink: api.Sink,
    calls: std.ArrayList(api.Call) = .empty,

    kind: Kind = .none,
    shown: bool = false,
    /// Whether the part being read has said anything yet.
    said: bool = false,
    /// A thought summary is held until its part closes, so a one-line summary
    /// can use the compact value form rather than a quoted block.
    summary: std.ArrayList(u8) = .empty,
    args: std.ArrayList(u8) = .empty,
    id: []const u8 = "",
    name: []const u8 = "",
    call_id: []const u8 = "",
    encrypted: []const u8 = "",
    /// Of the response rather than any item, and only known at its end.
    reason: []const u8 = "",
    incomplete: bool = false,
    /// The summary part being read, and how many before it became 💭 already.
    part: i64 = 0,
    parts: usize = 0,
    /// A refusal completes like anything else here, so the part's own type is
    /// what says the model declined.
    refused: bool = false,

    const Kind = enum { none, message, reasoning, function_call };

    fn start(b: *Building, item: std.json.Value) !void {
        b.kind = .none;
        b.shown = false;
        b.part = 0;
        b.parts = 0;
        b.said = false;
        b.summary = .empty;
        b.args = .empty;
        b.id = "";
        b.name = "";
        b.call_id = "";
        b.encrypted = "";

        const which = str(item.object.get("type")) orelse return;
        if (std.mem.eql(u8, which, "message")) {
            b.kind = .message;
        } else if (std.mem.eql(u8, which, "reasoning")) {
            b.kind = .reasoning;
            b.id = str(item.object.get("id")) orelse "";
        } else if (std.mem.eql(u8, which, "function_call")) {
            b.kind = .function_call;
            b.call_id = str(item.object.get("call_id")) orelse "";
            b.name = str(item.object.get("name")) orelse "";
            b.id = str(item.object.get("id")) orelse "";
        }
    }

    /// What the finished item holds that the deltas did not carry. Visible
    /// text is not repeated; completed function arguments replace deltas.
    fn settle(b: *Building, item: std.json.Value) !void {
        switch (b.kind) {
            .message => if (item.object.get("content")) |content| {
                if (content != .array) return;
                for (content.array.items) |part| {
                    if (part != .object) continue;
                    const which = str(part.object.get("type")) orelse continue;
                    // A refusal is the model's words too, under its own field.
                    const key = if (std.mem.eql(u8, which, "output_text"))
                        "text"
                    else if (std.mem.eql(u8, which, "refusal"))
                        "refusal"
                    else
                        continue;
                    if (std.mem.eql(u8, key, "refusal")) b.refused = true;
                    if (b.said) continue; // already streamed
                    try b.say(.bot, str(part.object.get(key)) orelse "");
                }
            },
            .reasoning => {
                if (str(item.object.get("encrypted_content"))) |enc| b.encrypted = enc;
                if (str(item.object.get("id"))) |got| b.id = got;
                if (b.said or b.parts > 0) return; // already streamed
                const summary = item.object.get("summary") orelse return;
                if (summary != .array) return;
                for (summary.array.items, 0..) |part, i| {
                    if (part != .object) continue;
                    if (i > 0) try b.nextPart(@intCast(i));
                    if (str(part.object.get("text"))) |t| try b.say(.thought, t);
                }
            },
            .function_call => {
                // The completed value is authoritative even when only some
                // of its argument deltas arrived.
                if (str(item.object.get("arguments"))) |arguments| {
                    b.args = .empty;
                    try b.args.appendSlice(b.arena, arguments);
                }
            },
            .none => {},
        }
    }

    /// Close the summary part being read as a 💭 of its own, and read the
    /// next. A part that said nothing leaves nothing behind.
    fn nextPart(b: *Building, index: i64) !void {
        if (b.said) b.parts += 1;
        if (b.summary.items.len > 0) {
            const compact = std.mem.indexOfAny(u8, b.summary.items, "\r\n") == null;
            try b.sink.record(
                .thought,
                if (compact) b.summary.items else "",
                if (compact) "" else b.summary.items,
            );
            b.summary = .empty;
        }
        if (b.shown) try b.sink.end();
        b.shown = false;
        b.said = false;
        b.part = index;
    }

    /// Out to whoever is reading. A record opens on its first byte, so one
    /// the model left empty never reaches the pipe at all.
    fn say(b: *Building, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        b.said = true;
        if (s == .thought) {
            try b.summary.appendSlice(b.arena, fragment);
            return;
        }
        if (!b.shown) {
            try b.sink.begin(s, "");
            b.shown = true;
        }
        try b.sink.text(fragment);
    }

    fn stop(b: *Building) !void {
        switch (b.kind) {
            .none, .message => {},
            .reasoning => {
                // The last part closes, and the 🔏 — known only now the item
                // has ended — follows as a record of its own.
                try b.nextPart(b.part + 1);
                if (b.id.len > 0 or b.encrypted.len > 0)
                    try b.sink.record(.thought, api.snip, try sealed(b.arena, b.id, b.encrypted));
            },
            .function_call => {
                const raw = if (b.args.items.len == 0) "{}" else b.args.items;
                try b.calls.append(b.arena, .{
                    .id = b.call_id,
                    .name = b.name,
                    .arguments = raw,
                });
            },
        }
        if (b.shown) try b.sink.end();
        b.kind = .none;
        b.shown = false;
    }

    /// Keep received output and its stop reason before reporting an
    /// incomplete response to the caller.
    fn finish(b: *Building) !api.Reply {
        if (b.kind != .none) try b.stop();
        const reason = if (b.refused and b.reason.len == 0) "refusal" else b.reason;
        try api.stopped(b.arena, b.sink, stops, reason);
        if (b.incomplete) return error.IncompleteResponse;
        return .{ .calls = b.calls.items };
    }
};

fn num(v: ?std.json.Value) ?i64 {
    const got = v orelse return null;
    return if (got == .integer) got.integer else null;
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

fn requestOf(arena: Allocator, records: []const doc.Record, target: api.Target) !std.json.Value {
    const body = try encode(arena, records, target);
    return std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
}

test "the system prompt is a field, and the rest is the ledger in its own order" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // 🧭 after 🙋, and two of them: the ledger is allowed to say this and the
    // api is not, so the encoder is where it gets fixed.
    const records = [_]doc.Record{
        .{ .sigil = .user, .content = "Say hi." },
        .{ .sigil = .system, .content = "Be brief." },
        .{ .sigil = .system, .content = "Be kind." },
        .{ .sigil = .bot, .content = "Let me look." },
        .{ .sigil = .call, .value = "say,fc_1", .content = "* text `\"hi\"`" },
        .{ .sigil = .result, .value = "fc_1", .content = "hi" },
        .{ .sigil = .bot, .content = "Done." },
    };
    const v = try requestOf(arena, &records, .{ .model = "gpt-5.5" });

    try testing.expectEqualStrings("Be brief.\nBe kind.", field(v, "instructions").string);

    // One item per record, in the order they happened: no grouping, no
    // alternation, nothing hoisted but the 🧭. This is the whole projection.
    const input = field(v, "input").array.items;
    try testing.expectEqual(@as(usize, 5), input.len);
    try testing.expectEqualStrings("user", field(input[0], "role").string);
    try testing.expectEqualStrings("assistant", field(input[1], "role").string);
    try testing.expectEqualStrings("function_call", field(input[2], "type").string);
    try testing.expectEqualStrings("fc_1", field(input[2], "call_id").string);
    // Arguments are a JSON string here, as they are in chat completions.
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , field(input[2], "arguments").string);
    try testing.expectEqualStrings("function_call_output", field(input[3], "type").string);
    try testing.expectEqualStrings("hi", field(input[3], "output").string);
    try testing.expectEqualStrings("assistant", field(input[4], "role").string);
}

test "a call answered twice is one output, and a failure keeps only what it said" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .call, .value = "say,fc_1", .content = "* text `\"hi\"`" },
        .{ .sigil = .result, .value = "fc_1", .content = "part one" },
        .{ .sigil = .failed, .value = "fc_1", .content = "nope" },
    };
    const v = try requestOf(arena, &records, .{ .model = "gpt-5.5" });
    const input = field(v, "input").array.items;

    // The api has one item per call, so the saying and the verdict join —
    // and 🚫 leaves nothing behind but what it said, because there is no
    // field here for how it went.
    try testing.expectEqual(@as(usize, 2), input.len);
    try testing.expectEqualStrings("function_call_output", field(input[1], "type").string);
    try testing.expectEqualStrings("part one\nnope", field(input[1], "output").string);
    try testing.expect(input[1].object.get("is_error") == null);
}

test "a thought goes out only when it is signed, with the id this api needs" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .thought, .value = "hmm" },
        .{ .sigil = .thought, .value = api.snip, .content = ":lock_with_ink_pen:`rs_1,ENCRYPTED`" },
        .{ .sigil = .thought, .content = "came off another wire" },
        .{ .sigil = .bot, .content = "Hello." },
    };
    const v = try requestOf(arena, &records, .{ .model = "gpt-5.5" });
    const input = field(v, "input").array.items;

    // The signed one, and then what was said. The unsigned one is dropped:
    // this api will not take back a thought it never signed.
    try testing.expectEqual(@as(usize, 2), input.len);
    try testing.expectEqualStrings("reasoning", field(input[0], "type").string);
    try testing.expectEqualStrings("rs_1", field(input[0], "id").string);
    try testing.expectEqualStrings("ENCRYPTED", field(input[0], "encrypted_content").string);
    const summary = field(input[0], "summary").array.items;
    try testing.expectEqualStrings("summary_text", field(summary[0], "type").string);
    try testing.expectEqualStrings("hmm", field(summary[0], "text").string);
    try testing.expectEqualStrings("assistant", field(input[1], "role").string);
}

test "a tool is flat here, where chat completions nests the same schema" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const tool: toolbox.Tool = .{
        .name = "say",
        .description = "Say a thing.",
        .properties = &.{.{ .name = "text", .type = "string", .description = "What", .required = true }},
    };
    const v = try requestOf(arena, &.{}, .{ .model = "gpt-5.5", .tools = &.{tool} });
    const t = field(v, "tools").array.items[0];

    try testing.expectEqualStrings("function", field(t, "type").string);
    try testing.expectEqualStrings("say", field(t, "name").string);
    try testing.expect(t.object.get("function") == null);
    const params = field(t, "parameters");
    try testing.expectEqualStrings("object", field(params, "type").string);
    try testing.expectEqualStrings("string", field(field(params, "properties"), "text").object.get("type").?.string);
}

/// A sink that writes what it is given as `sigil:content`, one record a line,
/// so a test can assert the order as well as the bytes.
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
        if (self.seen.items.len > 0) try self.seen.append(self.arena, '\n');
        try self.seen.appendSlice(self.arena, @tagName(s));
        try self.seen.append(self.arena, ':');
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

test "a streamed reply reads as the items it was made of" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[]}}
        \\
        \\event: response.reasoning_summary_text.delta
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":0,"delta":"weighing it"}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"weighing it"}],"encrypted_content":"ENCRYPTED"}}
        \\
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"msg_1","role":"assistant","content":[]}}
        \\
        \\event: response.output_text.delta
        \\data: {"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Let me look."}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Let me look.","annotations":[]}]}}
        \\
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","id":"fc_i","call_id":"call_1","name":"say","arguments":""}}
        \\
        \\event: response.function_call_arguments.delta
        \\data: {"type":"response.function_call_arguments.delta","output_index":2,"delta":"{\"text\":"}
        \\
        \\event: response.function_call_arguments.delta
        \\data: {"type":"response.function_call_arguments.delta","output_index":2,"delta":"\"hi\"}"}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":2,"item":{"type":"function_call","id":"fc_i","call_id":"call_1","name":"say","arguments":"{\"text\":\"hi\"}"}}
        \\
        \\event: response.completed
        \\data: {"type":"response.completed","response":{"id":"resp_1","status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqual(sigil.Sigil.thought, collect.got.records.items[0].sigil);
    try testing.expectEqualStrings("weighing it", collect.got.records.items[0].value);
    try testing.expect(collect.got.records.items[0].content == null);
    // The id and the encrypted content follow the thought they sign, in a 💭
    // asking to be kept aside: this api wants both back before it will
    // believe it, and nobody needs to read them.
    try testing.expectEqualStrings(api.snip, collect.got.records.items[1].value);
    try testing.expectEqualStrings(":lock_with_ink_pen:`rs_1,ENCRYPTED`", collect.got.records.items[1].content.?);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[2].sigil);
    try testing.expectEqualStrings("Let me look.", collect.got.records.items[2].content.?);

    // The compact summary and then the 🔏 when the item that carried it
    // ended. The 📲 did not: a call cannot be shown until it is whole.
    try testing.expectEqualStrings(
        "thought:\nthought::lock_with_ink_pen:`rs_1,ENCRYPTED`\nbot:Let me look.",
        collect.seen.items,
    );

    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("call_1", reply.calls[0].id);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "a finished response parses without built-in aside stats" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"hello"}]}],"usage":{"input_tokens":1200,"output_tokens":80}}
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqualStrings("", reply.aside);
    try testing.expectEqualStrings("hello", collect.got.records.items[0].content.?);
}

test "a summary part that says it ended is said once" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Each part closes itself, and the item's end then finds nothing held.
    const body =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[]}}
        \\
        \\event: response.reasoning_summary_text.delta
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":0,"delta":"**Verifying**"}
        \\
        \\event: response.reasoning_summary_part.done
        \\data: {"type":"response.reasoning_summary_part.done","output_index":0,"summary_index":0,"part":{"type":"summary_text","text":"**Verifying**"}}
        \\
    ;
    const rest =
        \\event: response.reasoning_summary_text.delta
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":1,"delta":"**Refining**"}
        \\
        \\event: response.reasoning_summary_part.done
        \\data: {"type":"response.reasoning_summary_part.done","output_index":0,"summary_index":1,"part":{"type":"summary_text","text":"**Refining**"}}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"**Verifying**"},{"type":"summary_text","text":"**Refining**"}],"encrypted_content":"ENC"}}
        \\
        \\event: response.completed
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ body, "\n", rest }));
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqualStrings("**Verifying**", collect.got.records.items[0].value);
    try testing.expectEqualStrings("**Refining**", collect.got.records.items[1].value);
    try testing.expectEqualStrings(api.snip, collect.got.records.items[2].value);
}

test "each summary part is a 💭, and they go back as one item" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Two headings in one item, which used to run together as `****`.
    const body =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[]}}
        \\
        \\event: response.reasoning_summary_text.delta
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":0,"delta":"**Verifying**"}
        \\
        \\event: response.reasoning_summary_text.delta
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":1,"delta":"**Refining**"}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"**Verifying**"},{"type":"summary_text","text":"**Refining**"}],"encrypted_content":"ENC"}}
        \\
        \\event: response.completed
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    const at_once =
        \\{"id":"resp_1","object":"response","status":"completed","output":[
        \\{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"**Verifying**"},{"type":"summary_text","text":"**Refining**"}],"encrypted_content":"ENC"}]}
    ;
    for ([_][]const u8{ body, at_once }) |got| {
        var r: std.Io.Reader = .fixed(got);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
        try testing.expectEqualStrings("**Verifying**", collect.got.records.items[0].value);
        try testing.expectEqualStrings("**Refining**", collect.got.records.items[1].value);
        try testing.expect(collect.got.records.items[0].content == null);
        try testing.expect(collect.got.records.items[1].content == null);
        try testing.expectEqualStrings(api.snip, collect.got.records.items[2].value);

        // Encoded, the parts are one item's summary again, signed once.
        const request = try encode(arena, collect.got.records.items, .{ .model = "gpt-5.5" });
        try testing.expect(std.mem.indexOf(u8, request,
            \\"summary":[{"type":"summary_text","text":"**Verifying**"},{"type":"summary_text","text":"**Refining**"}],"encrypted_content":"ENC"
        ) != null);
    }
}

test "a whole reply reads the same as a streamed one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\{"id":"resp_1","object":"response","status":"completed","output":[
        \\{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"weighing it"}],"encrypted_content":"ENCRYPTED"},
        \\{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Let me look.","annotations":[]}]},
        \\{"type":"function_call","id":"fc_i","call_id":"call_1","name":"say","arguments":"{\"text\":\"hi\"}"}
        \\]}
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqualStrings("weighing it", collect.got.records.items[0].value);
    try testing.expect(collect.got.records.items[0].content == null);
    try testing.expectEqualStrings(":lock_with_ink_pen:`rs_1,ENCRYPTED`", collect.got.records.items[1].content.?);
    try testing.expectEqualStrings("Let me look.", collect.got.records.items[2].content.?);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "an error is what the api said, and the reply says so" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: response.failed
        \\data: {"type":"response.failed","response":{"status":"failed","error":{"code":"server_error","message":"oops"}}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    const said = collect.got.records.items;
    try testing.expectEqual(@as(usize, 1), said.len);
    try testing.expectEqualStrings("(oops - failed with server_error)", said[0].value);
    try testing.expect(said[0].content == null);
}

test "failed events find details in alternate response shapes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const fixtures = [_]struct { body: []const u8, want: []const u8 }{
        .{
            .body =
            \\event: response.failed
            \\data: {"type":"response.failed","detail":"less useful","response":{"status":"failed","status_details":{"error":{"code":"backend_error","summary":"upstream reset\nplease retry"}}}}
            \\
            ,
            .want = "(upstream reset please retry - failed with backend_error)",
        },
        .{
            .body =
            \\event: response.failed
            \\data: {"type":"response.failed","response":{"status":"failed","detail":"The model service is temporarily unavailable."}}
            \\
            ,
            .want = "(The model service is temporarily unavailable. - failed with error)",
        },
        .{
            .body =
            \\event: error
            \\data: {"type":"error","error":"gateway overloaded"}
            \\
            ,
            .want = "(gateway overloaded - failed with error)",
        },
    };

    for (fixtures) |fixture| {
        var r: std.Io.Reader = .fixed(fixture.body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
        try testing.expectEqualStrings(fixture.want, collect.got.records.items[0].value);
    }
}

test "a failure nobody has met still says what arrived" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const fixtures = [_]struct { body: []const u8, want: []const u8 }{
        // A code is the term where the only type is the event's own.
        .{
            .body = "data: {\"type\":\"error\",\"code\":\"rate_limit_exceeded\",\"message\":\"Slow down.\"}\n\n",
            .want = "(Slow down. - failed with rate_limit_exceeded)",
        },
        // A term and no words is still said by its term.
        .{
            .body = "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"server_error\"}}}\n\n",
            .want = "(failed with server_error)",
        },
        // Neither, so the event itself.
        .{
            .body = "data: {\"type\":\"response.failed\",\"response\":{\"error\":null}}\n\n",
            .want = "(failed with error - {\"type\":\"response.failed\",\"response\":{\"error\":null}})",
        },
        // Not a response, all at once.
        .{
            .body = "{\"detail\":\"Unauthorized\"}",
            .want = "(Unauthorized - failed with error)",
        },
    };
    for (fixtures) |fixture| {
        var r: std.Io.Reader = .fixed(fixture.body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
        try testing.expectEqualStrings(fixture.want, collect.got.records.items[0].value);
    }
}

test "a whole failed response reports status details" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\{"status":"failed","status_details":{"error":{"type":"server_error","detail":"The backend closed the stream."}},"output":[]}
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
    try testing.expectEqualStrings(
        "(The backend closed the stream. - failed with server_error)",
        collect.got.records.items[0].value,
    );
}

test "request params are only those supplied by the target" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const absent = try requestOf(arena, &.{}, .{ .model = "gpt-5.5" });
    try testing.expect(absent.object.get("store") == null);
    try testing.expect(absent.object.get("include") == null);
    const supplied = try requestOf(arena, &.{}, .{
        .model = "gpt-5.5",
        .params = &.{ .{ .key = "store", .value = "false" }, .{ .key = "include", .value = "[]" } },
    });
    try testing.expect(!field(supplied, "store").bool);
    try testing.expectEqual(@as(usize, 0), field(supplied, "include").array.items.len);
}

test "an incomplete response says why last, in this api's own word" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\{"id":"resp_1","object":"response","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[
        \\{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Moon"}]}]}
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    try testing.expectError(error.IncompleteResponse, parse(arena, &r, collect.sink()));
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
    try testing.expectEqualStrings("Moon", collect.got.records.items[0].content.?);
    try testing.expectEqualStrings("(cut off at max_output_tokens)", collect.got.records.items[1].value);
}

test "a refusal is what the model said, and says it declined" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const streamed =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","role":"assistant","content":[]}}
        \\
        \\event: response.refusal.delta
        \\data: {"type":"response.refusal.delta","output_index":0,"delta":"I can't help with that."}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"I can't help with that."}]}}
        \\
        \\event: response.completed
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    const at_once =
        \\{"id":"resp_1","object":"response","status":"completed","output":[
        \\{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"I can't help with that."}]}]}
    ;
    for ([_][]const u8{ streamed, at_once }) |body| {
        var r: std.Io.Reader = .fixed(body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
        try testing.expectEqualStrings("I can't help with that.", collect.got.records.items[0].content.?);
        try testing.expectEqualStrings("(declined with refusal)", collect.got.records.items[1].value);
    }
}

test "a model that shows its thinking and one that summarises it are both 💭" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[]}}
        \\
        \\event: response.reasoning_text.delta
        \\data: {"type":"response.reasoning_text.delta","output_index":0,"delta":"working it through"}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"ENC"}}
        \\
        \\event: response.incomplete
        \\data: {"type":"response.incomplete","response":{"status":"incomplete"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    // Received thoughts and their signature survive an incomplete response,
    // but the parser fails so no tool round can start from it.
    try testing.expectError(error.IncompleteResponse, parse(arena, &r, collect.sink()));
    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqualStrings("working it through", collect.got.records.items[0].value);
    try testing.expect(collect.got.records.items[0].content == null);
    try testing.expectEqualStrings(":lock_with_ink_pen:`rs_1,ENC`", collect.got.records.items[1].content.?);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[2].sigil);
    try testing.expectEqualStrings("(stopped at incomplete)", collect.got.records.items[2].value);
    try testing.expect(collect.got.records.items[2].content == null);
}

test "files a 🔗 hands over go out beside the answer, uploaded or whole" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var records = [_]doc.Record{
        .{ .sigil = .call, .value = "see,c1", .content = "* file `\"a.jpeg\"`" },
        .{ .sigil = .result, .value = "c1", .content = "here" },
        .{ .sigil = .link, .value = "c1", .content = ">image/jpeg data:image/jpeg;base64,YWJj a.jpeg\n>application/pdf data:application/pdf;base64,YWJj b.pdf" },
        .{ .sigil = .ok, .value = "c1" },
    };
    const body = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, body,
        \\"output":[{"type":"input_text","text":"here"},{"type":"input_image","image_url":"data:image/jpeg;base64,YWJj"},{"type":"input_file","filename":"b.pdf","file_data":"data:application/pdf;base64,YWJj"}]
    ) != null);

    records[2].content = ">image/jpeg ref:file-a\n>application/pdf ref:file-b b.pdf";
    const ids = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, ids,
        \\{"type":"input_image","file_id":"file-a"},{"type":"input_file","file_id":"file-b"}
    ) != null);

    records[2].content = ">application/pdf https://example.com/b.pdf b.pdf";
    const url = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, url,
        \\{"type":"input_file","file_url":"https://example.com/b.pdf"}
    ) != null);

    // A file never handed over, for want of an upload, cannot be sent.
    records[2].content = "<a.jpeg";
    try testing.expectError(error.NoUpload, encode(arena, &records, .{ .model = "m" }));
}
test "completed function arguments replace partial deltas" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const head =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"bash","arguments":""}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc_1","delta":"{\"command\":"}
        \\
    ;
    const endings = [_][]const u8{
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"bash","arguments":"{\"command\":\"pwd\"}"}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
        ,
        \\data: {"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc_1","arguments":"{\"command\":\"pwd\"}"}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"bash"}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
        ,
    };
    for (endings) |ending| {
        var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ head, "\n", ending }));
        var collect: Collect = .{ .arena = arena };
        const reply = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), reply.calls.len);
        try testing.expectEqualStrings("call_1", reply.calls[0].id);
        try testing.expectEqualStrings("{\"command\":\"pwd\"}", reply.calls[0].arguments);
    }
}

test "interleaved tool calls keep their names ids and arguments" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_g","call_id":"call_g","name":"grep"}}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","id":"fc_b","call_id":"call_b","name":"bash"}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc_g","delta":"{\"glob\":"}
        \\data: {"type":"response.function_call_arguments.delta","output_index":1,"item_id":"fc_b","delta":"{\"command\":"}
        \\data: {"type":"response.function_call_arguments.delta","item_id":"fc_b","delta":"\"pwd\"}"}
        \\data: {"type":"response.function_call_arguments.done","output_index":1,"item_id":"fc_b","arguments":"{\"command\":\"pwd\"}"}
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"fc_b"}}
        \\data: {"type":"response.function_call_arguments.delta","item_id":"fc_g","delta":"\"*.svg\"}"}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_g"}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 2), reply.calls.len);
    try testing.expectEqualStrings("grep", reply.calls[0].name);
    try testing.expectEqualStrings("call_g", reply.calls[0].id);
    try testing.expectEqualStrings("{\"glob\":\"*.svg\"}", reply.calls[0].arguments);
    try testing.expectEqualStrings("bash", reply.calls[1].name);
    try testing.expectEqualStrings("call_b", reply.calls[1].id);
    try testing.expectEqualStrings("{\"command\":\"pwd\"}", reply.calls[1].arguments);
}

test "interleaved messages stream separately in output order" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_text.delta","output_index":0,"delta":"first "}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"m1"}}
        \\data: {"type":"response.output_text.delta","output_index":1,"delta":"second"}
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"m1"}}
        \\data: {"type":"response.output_text.delta","output_index":0,"delta":"message"}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
    try testing.expectEqualStrings("first message", collect.got.records.items[0].content.?);
    try testing.expectEqualStrings("second", collect.got.records.items[1].content.?);
}

test "item identity errors cannot mutate another item" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const head =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"m1"}}
        \\
    ;
    const bad = [_][]const u8{
        \\data: {"type":"response.output_text.delta","output_index":0,"item_id":"m1","delta":"wrong"}
        ,
        \\data: {"type":"response.output_text.delta","output_index":9,"delta":"unknown"}
        ,
        \\data: {"type":"response.output_text.delta","item_id":"unknown","delta":"unknown"}
        ,
        \\data: {"type":"response.output_text.delta","delta":"unaddressed"}
        ,
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m2"}}
        ,
        \\data: {"type":"response.output_item.added","output_index":2,"item":{"type":"message","id":"m1"}}
        ,
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"m1"}}
        \\data: {"type":"response.output_text.delta","output_index":1,"delta":"late"}
        ,
        \\data: {"type":"response.output_item.added","output_index":2,"item":{"type":"message"}}
        \\data: {"type":"response.output_text.delta","output_index":2,"item_id":"m1","delta":"wrong"}
        ,
        \\data: {"type":"response.output_item.added","item":{"type":"message","id":"m2"}}
        ,
        \\data: {"type":"response.output_item.added","output_index":-1,"item":{"type":"message","id":"m2"}}
        ,
        \\data: {"type":"response.output_item.added","output_index":2,"item":[]}
        ,
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_text.delta","output_index":0,"delta":"late"}
        ,
        \\data: {"type":"response.output_text.delta","output_index":"0","item_id":"m0","delta":"wrong"}
        ,
        \\data: {"type":"response.output_text.delta","output_index":-1,"item_id":"m0","delta":"wrong"}
        ,
        \\data: {"type":"response.output_item.done","output_index":0,"item_id":"m0","item":{"type":"message","id":"m1"}}
        ,
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"m0"}}
        ,
    };
    const expected = [_]anyerror{
        error.OutputItemIdMismatch,
        error.UnknownOutputItem,
        error.UnknownOutputItem,
        error.MissingOutputItemIdentity,
        error.DuplicateOutputItem,
        error.DuplicateOutputItem,
        error.EventForClosedOutputItem,
        error.OutputItemIdMismatch,
        error.MissingOutputIndex,
        error.InvalidOutputIndex,
        error.InvalidOutputItem,
        error.EventForClosedOutputItem,
        error.InvalidOutputIndex,
        error.InvalidOutputIndex,
        error.OutputItemIdMismatch,
        error.OutputItemTypeMismatch,
    };
    for (bad, expected) |ending, err| {
        var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ head, "\n", ending }));
        var collect: Collect = .{ .arena = arena };
        try testing.expectError(err, parse(arena, &r, collect.sink()));
        try testing.expectEqual(@as(usize, 0), collect.seen.items.len);
    }
}

test "interleaved items drain separately on EOF and response termination" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const head =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"r0"}}
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":0,"summary_index":0,"delta":"thinking"}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"m1"}}
        \\data: {"type":"response.output_text.delta","output_index":1,"delta":"answer"}
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"m1"}}
        \\
    ;
    const endings = [_][]const u8{
        "",
        "data: [DONE]\n",
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n",
        "data: {\"type\":\"response.incomplete\",\"response\":{\"status\":\"incomplete\"}}\n",
        "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"oops\"}}}\n",
    };
    for (endings, 0..) |ending, i| {
        var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ head, "\n", ending }));
        var collect: Collect = .{ .arena = arena };
        if (i == 3) {
            try testing.expectError(error.IncompleteResponse, parse(arena, &r, collect.sink()));
        } else _ = try parse(arena, &r, collect.sink());
        const records = collect.got.records.items;
        // The interrupted reasoning item keeps its summary and opaque id.
        try testing.expectEqualStrings("thinking", records[0].value);
        try testing.expectEqualStrings(api.snip, records[1].value);
        try testing.expectEqualStrings("answer", records[2].content.?);
        try testing.expectEqual(@as(usize, if (i >= 3) 4 else 3), records.len);
    }
}

test "earliest item streams while later output waits" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var collect: Collect = .{ .arena = arena };
    var stream: Stream = .{ .arena = arena, .sink = collect.sink() };
    const events_in = [_][]const u8{
        \\{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        ,
        \\{"type":"response.output_text.delta","output_index":0,"delta":"first"}
        ,
        \\{"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"m1"}}
        ,
        \\{"type":"response.output_text.delta","output_index":1,"delta":"second"}
        ,
        \\{"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"m1"}}
        ,
    };
    for (events_in, 0..) |raw, i| {
        const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{});
        _ = try stream.accept(v);
        if (i > 0) try testing.expectEqualStrings("bot:first", collect.seen.items);
    }
    const done = try std.json.parseFromSliceLeaky(std.json.Value, arena,
        \\{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0"}}
    , .{});
    _ = try stream.accept(done);
    try testing.expectEqualStrings("bot:first\nbot:second", collect.seen.items);
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
}

test "gateway tool calls precede a completed-only empty message" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\data: {"type":"response.created","response":{"output":[]}}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","id":"t1","call_id":"t1","name":"list","arguments":""}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":1,"item_id":"t1","delta":"{\"path\":\"./scratch/\"}"}
        \\data: {"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","id":"t2","call_id":"t2","name":"grep","arguments":""}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":2,"item_id":"t2","delta":"{\"glob\":\"./scratch/**\"}"}
        \\data: {"type":"response.output_item.added","output_index":3,"item":{"type":"function_call","id":"t3","call_id":"t3","name":"bash","arguments":""}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":3,"item_id":"t3","delta":"{\"command\":\"pwd\"}"}
        \\data: {"type":"response.function_call_arguments.done","output_index":1,"item_id":"t1","arguments":"{\"path\":\"./scratch/\"}"}
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"t1","arguments":"{\"path\":\"./scratch/\"}"}}
        \\data: {"type":"response.function_call_arguments.done","output_index":2,"item_id":"t2","arguments":"{\"glob\":\"./scratch/**\"}"}
        \\data: {"type":"response.output_item.done","output_index":2,"item":{"type":"function_call","id":"t2","arguments":"{\"glob\":\"./scratch/**\"}"}}
        \\data: {"type":"response.function_call_arguments.done","output_index":3,"item_id":"t3","arguments":"{\"command\":\"pwd\"}"}
        \\data: {"type":"response.output_item.done","output_index":3,"item":{"type":"function_call","id":"t3","arguments":"{\"command\":\"pwd\"}"}}
        \\data: {"type":"response.output_text.done","output_index":0,"item_id":"m0","text":""}
        \\data: {"type":"response.content_part.done","output_index":0,"item_id":"m0","part":{"type":"output_text","text":""}}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0","content":[{"type":"output_text","text":""}]}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\data: [DONE]
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 0), collect.got.records.items.len);
    try testing.expectEqual(@as(usize, 3), reply.calls.len);
    const names = [_][]const u8{ "list", "grep", "bash" };
    const ids = [_][]const u8{ "t1", "t2", "t3" };
    const args = [_][]const u8{ "{\"path\":\"./scratch/\"}", "{\"glob\":\"./scratch/**\"}", "{\"command\":\"pwd\"}" };
    for (reply.calls, names, ids, args) |call, name, id, arguments| {
        try testing.expectEqualStrings(name, call.name);
        try testing.expectEqualStrings(id, call.id);
        try testing.expectEqualStrings(arguments, call.arguments);
    }
}

test "completed-only output items preserve their content and call identity" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"fc1","call_id":"c1","name":"bash","arguments":"{\"command\":\"pwd\"}"}}
        \\data: {"type":"response.output_text.done","output_index":0,"item_id":"m0","text":"hello"}
        \\data: {"type":"response.content_part.done","output_index":0,"item_id":"m0","part":{"type":"output_text","text":"hello"}}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0","content":[{"type":"output_text","text":"hello"}]}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
    try testing.expectEqualStrings("hello", collect.got.records.items[0].content.?);
    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("bash", reply.calls[0].name);
    try testing.expectEqualStrings("c1", reply.calls[0].id);
    try testing.expectEqualStrings("{\"command\":\"pwd\"}", reply.calls[0].arguments);
}

test "completed event with incomplete status stops before returning tool calls" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const head =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc1","call_id":"c1","name":"bash","arguments":""}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"fc1","delta":"{}"}
        \\data: {"type":"response.function_call_arguments.done","output_index":0,"item_id":"fc1","arguments":"{}"}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc1","arguments":"{}"}}
        \\
    ;
    const cases = [_]struct { ending: []const u8, diagnostic: []const u8 }{
        .{
            .ending = "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\",\"usage\":{\"output_tokens\":4096}}}\n",
            .diagnostic = "(stopped at incomplete)",
        },
        .{
            .ending = "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}\n",
            .diagnostic = "(cut off at max_output_tokens)",
        },
    };
    for (cases) |case| {
        var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ head, "\n", case.ending }));
        var collect: Collect = .{ .arena = arena };
        try testing.expectError(error.IncompleteResponse, parse(arena, &r, collect.sink()));
        try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
        try testing.expectEqualStrings(case.diagnostic, collect.got.records.items[0].value);
    }
}

test "a waiting message becomes live without splitting its record" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var collect: Collect = .{ .arena = arena };
    var stream: Stream = .{ .arena = arena, .sink = collect.sink() };
    const incoming = [_][]const u8{
        \\{"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        ,
        \\{"type":"response.output_text.delta","output_index":0,"delta":"first"}
        ,
        \\{"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"m1"}}
        ,
        \\{"type":"response.output_text.delta","output_index":1,"delta":"second "}
        ,
        \\{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0"}}
        ,
        \\{"type":"response.output_text.delta","output_index":1,"delta":"message"}
        ,
        \\{"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"m1"}}
        ,
    };
    for (incoming, 0..) |raw, at| {
        const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{});
        _ = try stream.accept(v);
        if (at == 3) try testing.expectEqualStrings("bot:first", collect.seen.items);
        if (at == 4) try testing.expectEqualStrings("bot:first\nbot:second ", collect.seen.items);
        if (at == 5) try testing.expectEqualStrings("bot:first\nbot:second message", collect.seen.items);
    }
    _ = try stream.finish();
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
    try testing.expectEqualStrings("second message", collect.got.records.items[1].content.?);
}

test "waiting reasoning preserves completed and open summary parts" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const body =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_text.delta","output_index":0,"delta":"first"}
        \\data: {"type":"response.output_item.added","output_index":1,"item":{"type":"reasoning","id":"r1"}}
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":1,"summary_index":0,"delta":"one"}
        \\data: {"type":"response.reasoning_summary_part.done","output_index":1,"summary_index":0}
        \\data: {"type":"response.reasoning_summary_text.delta","output_index":1,"summary_index":1,"delta":"two"}
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_item.done","output_index":1,"item":{"type":"reasoning","id":"r1","encrypted_content":"SIGNED"}}
        \\data: {"type":"response.completed","response":{"status":"completed"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    const records = collect.got.records.items;
    try testing.expectEqual(@as(usize, 4), records.len);
    try testing.expectEqualStrings("first", records[0].content.?);
    try testing.expectEqualStrings("one", records[1].value);
    try testing.expectEqualStrings("two", records[2].value);
    try testing.expectEqualStrings(":lock_with_ink_pen:`r1,SIGNED`", records[3].content.?);
}

test "invalid Responses event JSON is an error rather than a lost fragment" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var r: std.Io.Reader = .fixed("data: {broken}\n\n");
    var collect: Collect = .{ .arena = arena };
    try testing.expectError(error.InvalidResponseJson, parse(arena, &r, collect.sink()));
}

test "only closed calls from a finished Responses stream are returned" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const head =
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc1","call_id":"c1","name":"bash"}}
        \\data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\"command\":\"pwd\"}"}
        \\
    ;
    const close = "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc1\"}}\n";
    const complete = "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n";
    const cases = [_]struct { ending: []const u8, incomplete: bool, calls: usize }{
        .{ .ending = "", .incomplete = true, .calls = 0 },
        .{ .ending = "data: [DONE]\n", .incomplete = true, .calls = 0 },
        .{ .ending = complete, .incomplete = true, .calls = 0 },
        .{ .ending = close, .incomplete = true, .calls = 0 },
        .{ .ending = close ++ "data: [DONE]\n", .incomplete = false, .calls = 1 },
        .{ .ending = close ++ complete, .incomplete = false, .calls = 1 },
        .{
            .ending = close ++ "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"oops\"}}}\n",
            .incomplete = false,
            .calls = 0,
        },
        .{
            .ending = close ++ "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"failed\",\"error\":{\"message\":\"oops\"}}}\n",
            .incomplete = false,
            .calls = 0,
        },
    };
    for (cases) |case| {
        var r: std.Io.Reader = .fixed(try std.mem.concat(arena, u8, &.{ head, "\n", case.ending }));
        var collect: Collect = .{ .arena = arena };
        if (case.incomplete) {
            try testing.expectError(error.IncompleteResponse, parse(arena, &r, collect.sink()));
            try testing.expectEqualStrings("(stopped at incomplete)", collect.got.records.items[0].value);
        } else {
            const reply = try parse(arena, &r, collect.sink());
            try testing.expectEqual(case.calls, reply.calls.len);
        }
    }
}
