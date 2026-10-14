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
//! plugin. Where they agreed, this agrees; `store` and `include` are what all
//! three set and the two things a ledger cannot do without.

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
    // The ledger's own, in this api's words, passed through untranslated.
    var said_store = false;
    var said_include = false;
    for (target.params) |p| {
        if (std.mem.eql(u8, p.key, "store")) said_store = true;
        if (std.mem.eql(u8, p.key, "include")) said_include = true;
        try s.objectField(p.key);
        try s.write(modelform.json(arena, p.value));
    }
    // Two fields this api needs before it behaves the way a ledger needs it
    // to. Neither is a preference, and both are what the 🧠 overrules if it
    // says so.
    //
    // `store` off is what makes the conversation the ledger's rather than a
    // server's: with it on, the history is kept and replayed by id at the far
    // end, which is the thing m8 exists not to do. The subscription endpoint
    // requires it off in any case.
    //
    // `include` is what makes a thought come home at all. Encrypted reasoning
    // is only returned when it is asked for, so without this a 💭 arrives
    // with nothing to sign it and could never be replayed — which would look
    // like the codec silently dropping thoughts rather than like a field
    // nobody set.
    if (!said_store) {
        try s.objectField("store");
        try s.write(false);
    }
    if (!said_include) {
        try s.objectField("include");
        try s.beginArray();
        try s.write("reasoning.encrypted_content");
        try s.endArray();
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
                try s.write(try toolbox.parseArgs(arena, .md, r.content orelse ""));
                try s.endObject();
            },
            .result, .ok, .failed => {
                if (claimed[i]) continue;
                const id = std.mem.trim(u8, r.value, " \t");
                const said = try answerTo(arena, records, claimed, i, id);
                try s.beginObject();
                try s.objectField("type");
                try s.write("function_call_output");
                try s.objectField("call_id");
                try s.write(id);
                try s.objectField("output");
                try s.write(said);
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
) ![]const u8 {
    var said: std.ArrayList(u8) = .empty;
    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, r.value, " \t"), id)) continue;

        claimed[idx] = true;
        if (r.content) |content| if (content.len > 0) {
            if (said.items.len > 0) try said.append(arena, '\n');
            try said.appendSlice(arena, content);
        };
        if (r.sigil != .result) break;
    }
    return said.items;
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
        if (signatureOn(line)) |value| {
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

/// The 🔏 a line carries, in either spelling. A nested sigil is read the way
/// it is written, and both spellings mean the same thing everywhere.
fn signatureOn(line: []const u8) ?[]const u8 {
    for ([_]doc.Mode{ .md, .m8 }) |mode| {
        const hit = sigil.match(mode, line) orelse continue;
        if (hit.sigil != .signature) continue;
        return std.mem.trim(u8, line[hit.len..], " \t");
    }
    return null;
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

/// A 🔏 as content, in the spelling every file is written in; a reader is
/// handed whichever one they are being written.
fn sealed(arena: Allocator, id: []const u8, enc: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}{s},{s}", .{ sigil.Sigil.signature.text(.md), id, enc });
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

/// Server-sent events. Every event names its own type, and an item is opened,
/// deltaed and closed — so this reads as a state machine and nothing has to
/// be inferred from position.
fn events(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var built: Building = .{ .arena = arena, .sink = sink };

    var line = first;
    while (true) {
        if (std.mem.startsWith(u8, line, "data:")) {
            const payload = std.mem.trim(u8, line["data:".len..], " ");
            if (std.mem.eql(u8, payload, "[DONE]")) break;
            if (std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{})) |v| {
                if (try event(&built, v)) break;
            } else |_| {}
        }
        const raw = (try api.nextLine(arena, r)) orelse break;
        line = std.mem.trimEnd(u8, raw, "\r\n");
    }
    return built.finish();
}

/// One event. True when the response is over.
fn event(built: *Building, v: std.json.Value) !bool {
    if (v != .object) return false;
    const kind = str(v.object.get("type")) orelse return false;

    if (std.mem.eql(u8, kind, "response.output_item.added")) {
        const item = v.object.get("item") orelse return false;
        if (item != .object) return false;
        try built.start(item);
    } else if (std.mem.eql(u8, kind, "response.output_item.done")) {
        // The finished item carries what the deltas could not: a reasoning
        // item's `encrypted_content` is only whole once it has stopped.
        const item = v.object.get("item") orelse return false;
        if (item == .object) try built.settle(item);
        try built.stop();
    } else if (std.mem.eql(u8, kind, "response.output_text.delta")) {
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
    } else if (std.mem.eql(u8, kind, "response.completed")) {
        if (v.object.get("response")) |resp| built.aside = try cost(built.arena, resp);
        return true;
    } else if (std.mem.eql(u8, kind, "response.incomplete")) {
        // Cut off rather than failed: what was said still happened, and the
        // ledger keeps it — along with that it was cut off.
        if (v.object.get("response")) |resp| built.reason = incompleteOf(resp);
        if (v.object.get("response")) |resp| built.aside = try cost(built.arena, resp);
        return true;
    } else if (std.mem.eql(u8, kind, "response.failed") or std.mem.eql(u8, kind, "error")) {
        // A refusal, an overload or a bad request arrives here with a 200, so
        // this is the only thing that would notice it. Saying nothing would
        // record a turn in which the model simply said nothing.
        if (built.kind != .none) try built.stop();
        try fail(built.arena, built.sink, v);
        return true;
    }
    return false;
}

/// One JSON object, from a provider that answered all at once.
fn whole(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, first);
    try body.appendSlice(arena, try r.allocRemaining(arena, .unlimited));

    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, body.items, .{}) catch
        return error.MalformedResponse;
    if (v != .object) return error.MalformedResponse;
    if (v.object.get("error")) |e| if (e != .null) {
        try fail(arena, sink, v);
        return .{};
    };
    if (str(v.object.get("status"))) |status| if (std.mem.eql(u8, status, "failed")) {
        try fail(arena, sink, v);
        return .{};
    };

    var built: Building = .{ .arena = arena, .sink = sink };
    built.aside = try cost(built.arena, v);
    if (str(v.object.get("status"))) |status| if (std.mem.eql(u8, status, "incomplete")) {
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
    /// What the response cost, as a line for whoever is watching.
    aside: []const u8 = "",
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

    /// What the finished item holds that the deltas did not carry. Reading it
    /// is additive: nothing already streamed is taken back, and anything that
    /// only ever arrives whole is picked up here.
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
                if (b.args.items.len > 0) return; // already streamed
                if (str(item.object.get("arguments"))) |a|
                    try b.args.appendSlice(b.arena, a);
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

    /// A stream that stopped without closing its item still gives up what it
    /// had: a thought that was cut off is a thought that was cut off, and the
    /// ledger says so rather than losing it.
    fn finish(b: *Building) !api.Reply {
        if (b.kind != .none) try b.stop();
        const reason = if (b.refused and b.reason.len == 0) "refusal" else b.reason;
        try api.stopped(b.arena, b.sink, stops, reason);
        return .{ .calls = b.calls.items, .aside = b.aside };
    }
};

/// What a finished response says it cost, as a line. `input_tokens` is the
/// whole prompt here, with the cached share a detail of it.
fn cost(arena: Allocator, response: std.json.Value) ![]const u8 {
    if (response != .object) return "";
    const u = response.object.get("usage") orelse return "";
    if (u != .object) return "";
    var c: api.Cost = .{
        .in = num(u.object.get("input_tokens")) orelse 0,
        .out = num(u.object.get("output_tokens")) orelse 0,
    };
    if (u.object.get("input_tokens_details")) |d| if (d == .object) {
        c.cached = num(d.object.get("cached_tokens")) orelse 0;
        c.written = num(d.object.get("cache_write_tokens")) orelse 0;
    };
    if (u.object.get("output_tokens_details")) |d| if (d == .object) {
        c.thinking = num(d.object.get("reasoning_tokens")) orelse 0;
    };
    return api.costLine(arena, c);
}

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
        .{ .sigil = .call, .value = "say,fc_1", .content = "* text `hi`" },
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
        .{ .sigil = .call, .value = "say,fc_1", .content = "* text `hi`" },
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
        .{ .sigil = .thought, .value = api.snip, .content = ":lock_with_ink_pen:rs_1,ENCRYPTED" },
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
    try testing.expectEqualStrings(":lock_with_ink_pen:rs_1,ENCRYPTED", collect.got.records.items[1].content.?);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[2].sigil);
    try testing.expectEqualStrings("Let me look.", collect.got.records.items[2].content.?);

    // The compact summary and then the 🔏 when the item that carried it
    // ended. The 📲 did not: a call cannot be shown until it is whole.
    try testing.expectEqualStrings(
        "thought:\nthought::lock_with_ink_pen:rs_1,ENCRYPTED\nbot:Let me look.",
        collect.seen.items,
    );

    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("call_1", reply.calls[0].id);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "a finished response says what it cost" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: response.completed
        \\data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1200,"input_tokens_details":{"cached_tokens":1024,"cache_write_tokens":100},"output_tokens":80,"output_tokens_details":{"reasoning_tokens":64}}}}
        \\
    ;
    const at_once =
        \\{"status":"completed","output":[],"usage":{"input_tokens":1200,"input_tokens_details":{"cached_tokens":1024,"cache_write_tokens":100},"output_tokens":80,"output_tokens_details":{"reasoning_tokens":64}}}
    ;
    for ([_][]const u8{ body, at_once }) |got| {
        var r: std.Io.Reader = .fixed(got);
        var collect: Collect = .{ .arena = arena };
        try testing.expectEqualStrings(
            "::stats::\u{2725}80\u{2586}1K::\u{1F9EE} 1200 in, 1024 cached (85%), 100 written, 80 out (64 thinking)",
            (try parse(arena, &r, collect.sink())).aside,
        );
    }
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
    try testing.expectEqualStrings(":lock_with_ink_pen:rs_1,ENCRYPTED", collect.got.records.items[1].content.?);
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

test "store and include are written unless the ledger said otherwise" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const v = try requestOf(arena, &.{}, .{ .model = "gpt-5.5" });
    // Off, so the conversation is the ledger's rather than a server's — and
    // the subscription endpoint will not take it any other way.
    try testing.expect(!field(v, "store").bool);
    // Asked for, or a 💭 comes home with nothing to sign it and can never be
    // replayed.
    try testing.expectEqualStrings(
        "reasoning.encrypted_content",
        field(v, "include").array.items[0].string,
    );

    // Whatever the 🧠 says wins, as with every other parameter.
    const said = try requestOf(arena, &.{}, .{
        .model = "gpt-5.5",
        .params = &.{
            .{ .key = "store", .value = "true" },
            .{ .key = "include", .value = "[]" },
        },
    });
    try testing.expect(field(said, "store").bool);
    try testing.expectEqual(@as(usize, 0), field(said, "include").array.items.len);
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
    _ = try parse(arena, &r, collect.sink());
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
    // Cut off rather than failed: what was said still happened, so it is a
    // reply and not an error — and it says it was cut off, even with no
    // reason given.
    _ = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqualStrings("working it through", collect.got.records.items[0].value);
    try testing.expect(collect.got.records.items[0].content == null);
    try testing.expectEqualStrings(":lock_with_ink_pen:rs_1,ENC", collect.got.records.items[1].content.?);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[2].sigil);
    try testing.expectEqualStrings("(stopped at incomplete)", collect.got.records.items[2].value);
    try testing.expect(collect.got.records.items[2].content == null);
}
