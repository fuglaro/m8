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
//!   🔏 survive the round trip. The 🔏 holds `id,encrypted_content` — two
//!   fields, because this api needs both to believe a thought it is handed
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
            .thought => if (try signed(arena, r.content orelse "")) |thought|
                try reasoning(s, thought),
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
    if (thought.text.len > 0) {
        try s.beginObject();
        try s.objectField("type");
        try s.write("summary_text");
        try s.objectField("text");
        try s.write(thought.text);
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
    text: []const u8 = "",
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
    return .{
        .text = text.items,
        .id = std.mem.trim(u8, mark[0..cut], " \t"),
        .encrypted = std.mem.trim(u8, mark[cut + 1 ..], " \t"),
    };
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

/// A 💭's content, with the 🔏 written under what was thought.
fn withSignature(arena: Allocator, text: []const u8, id: []const u8, enc: []const u8) ![]const u8 {
    if (id.len == 0 and enc.len == 0) return arena.dupe(u8, text);
    // The spelling every file is written in; a reader is handed whichever one
    // they are being written.
    const m = sigil.Sigil.signature.text(.md);
    if (text.len == 0) return std.fmt.allocPrint(arena, "{s}{s},{s}", .{ m, id, enc });
    return std.fmt.allocPrint(arena, "{s}\n{s}{s},{s}", .{ text, m, id, enc });
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
    } else if (std.mem.eql(u8, kind, "response.reasoning_summary_text.delta") or
        std.mem.eql(u8, kind, "response.reasoning_text.delta"))
    {
        // Two channels, one record. A model that summarises its thinking and
        // one that shows it are both thinking, and the ledger says so the
        // same way.
        if (str(v.object.get("delta"))) |d| try built.say(.thought, d);
    } else if (std.mem.eql(u8, kind, "response.function_call_arguments.delta")) {
        if (str(v.object.get("delta"))) |d| try built.args.appendSlice(built.arena, d);
    } else if (std.mem.eql(u8, kind, "response.completed") or
        // Cut off rather than failed: what was said still happened, and the
        // ledger keeps it.
        std.mem.eql(u8, kind, "response.incomplete"))
    {
        return true;
    } else if (std.mem.eql(u8, kind, "response.failed") or std.mem.eql(u8, kind, "error")) {
        // A refusal, an overload or a bad request arrives here with a 200, so
        // this is the only thing that would notice it. Saying nothing would
        // record a turn in which the model simply said nothing.
        return Error.ApiSaidError;
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
    if (v.object.get("error")) |e| if (e != .null) return Error.ApiSaidError;

    var built: Building = .{ .arena = arena, .sink = sink };
    const output = v.object.get("output") orelse return built.finish();
    if (output != .array) return built.finish();
    for (output.array.items) |item| {
        if (item != .object) continue;
        try built.start(item);
        try built.settle(item);
        try built.stop();
    }
    return built.finish();
}

pub const Error = error{ApiSaidError};

/// The item being read, and the reply being built out of the items that were.
///
/// The streamed and the whole shapes differ only in whether the content
/// arrives between `added` and `done` or was in the item all along, which is
/// what lets one machine read both: `start` takes what an item opens with,
/// `settle` takes what it closes with, and `stop` turns it into records.
const Building = struct {
    arena: Allocator,
    sink: api.Sink,
    records: std.ArrayList(doc.Record) = .empty,
    calls: std.ArrayList(api.Call) = .empty,

    kind: Kind = .none,
    shown: bool = false,
    text: std.ArrayList(u8) = .empty,
    args: std.ArrayList(u8) = .empty,
    id: []const u8 = "",
    name: []const u8 = "",
    call_id: []const u8 = "",
    encrypted: []const u8 = "",

    const Kind = enum { none, message, reasoning, function_call };

    fn start(b: *Building, item: std.json.Value) !void {
        b.kind = .none;
        b.shown = false;
        b.text = .empty;
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
                    if (!std.mem.eql(u8, which, "output_text")) continue;
                    if (b.text.items.len > 0) continue; // already streamed
                    try b.say(.bot, str(part.object.get("text")) orelse "");
                }
            },
            .reasoning => {
                if (str(item.object.get("encrypted_content"))) |enc| b.encrypted = enc;
                if (str(item.object.get("id"))) |got| b.id = got;
                if (b.text.items.len > 0) return; // already streamed
                const summary = item.object.get("summary") orelse return;
                if (summary != .array) return;
                for (summary.array.items) |part| {
                    if (part != .object) continue;
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

    /// Into the record and out to whoever is reading, at once.
    fn say(b: *Building, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        try b.text.appendSlice(b.arena, fragment);
        try b.show(s, fragment);
    }

    /// Out to the reader alone, for the part of a record that is built rather
    /// than streamed. A record opens on its first byte, so one the model left
    /// empty never reaches the pipe at all.
    fn show(b: *Building, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        if (!b.shown) {
            try b.sink.begin(s, "");
            b.shown = true;
        }
        try b.sink.text(fragment);
    }

    fn stop(b: *Building) !void {
        switch (b.kind) {
            .none => {},
            .message => try b.records.append(b.arena, .{
                .sigil = .bot,
                .content = b.text.items,
            }),
            .reasoning => {
                const content = try withSignature(b.arena, b.text.items, b.id, b.encrypted);
                // The 🔏 is part of the record and is only known once the
                // item ends, so it is written last — to the reader as well,
                // because what comes out of the pipe is the turn rather than
                // a view of it.
                try b.show(.thought, content[b.text.items.len..]);
                try b.records.append(b.arena, .{ .sigil = .thought, .content = content });
            },
            .function_call => {
                const raw = if (b.args.items.len == 0) "{}" else b.args.items;
                try b.records.append(b.arena, .{
                    .sigil = .call,
                    .value = try std.fmt.allocPrint(b.arena, "{s},{s}", .{ b.name, b.call_id }),
                    .content = try toolbox.renderArgs(b.arena, .md, raw),
                });
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
        return .{ .records = b.records.items, .calls = b.calls.items };
    }
};

// ------------------------------------------------------------------ decode

pub fn decode(arena: Allocator, bytes: []const u8) ![]const doc.Record {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch
        return error.MalformedRequest;
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

    // The api's own field, so there is nothing to hoist on the way back: it
    // was never an item and does not become one.
    if (str(v.object.get("instructions"))) |text|
        try out.append(arena, .{ .sigil = .system, .content = text });

    const input = v.object.get("input") orelse return out.items;
    // A bare string is the shortest thing this api takes: one person, saying
    // one thing.
    if (input == .string) {
        try out.append(arena, .{ .sigil = .user, .content = input.string });
        return out.items;
    }
    if (input != .array) return out.items;
    for (input.array.items) |item| try readItem(arena, &out, item);
    return out.items;
}

fn readItem(arena: Allocator, out: *std.ArrayList(doc.Record), item: std.json.Value) !void {
    if (item != .object) return;

    // An item with a role and no type is the short form of a message, which
    // is what this codec writes and what most of them are.
    const which = str(item.object.get("type")) orelse
        (if (item.object.get("role") != null) "message" else return);

    if (std.mem.eql(u8, which, "message")) {
        const assistant = if (str(item.object.get("role"))) |role|
            std.mem.eql(u8, role, "assistant")
        else
            false;
        try out.append(arena, .{
            .sigil = if (assistant) .bot else .user,
            .content = try contentText(arena, item.object.get("content")),
        });
    } else if (std.mem.eql(u8, which, "reasoning")) {
        var text: std.ArrayList(u8) = .empty;
        if (item.object.get("summary")) |summary| if (summary == .array) {
            for (summary.array.items) |part| {
                if (part != .object) continue;
                const t = str(part.object.get("text")) orelse continue;
                if (text.items.len > 0) try text.append(arena, '\n');
                try text.appendSlice(arena, t);
            }
        };
        try out.append(arena, .{
            .sigil = .thought,
            .content = try withSignature(
                arena,
                text.items,
                str(item.object.get("id")) orelse "",
                str(item.object.get("encrypted_content")) orelse "",
            ),
        });
    } else if (std.mem.eql(u8, which, "function_call")) {
        try out.append(arena, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(arena, "{s},{s}", .{
                str(item.object.get("name")) orelse "",
                str(item.object.get("call_id")) orelse "",
            }),
            .content = try toolbox.renderArgs(
                arena,
                .md,
                str(item.object.get("arguments")) orelse "{}",
            ),
        });
    } else if (std.mem.eql(u8, which, "function_call_output")) {
        // Nothing here says whether the tool succeeded, so it comes back a
        // 🧾. `status` is about whether the output finished, which is a
        // different question and not the one 🟢 and 🚫 answer.
        try out.append(arena, .{
            .sigil = .result,
            .value = str(item.object.get("call_id")) orelse "",
            .content = try contentText(arena, item.object.get("output")),
        });
    }
}

/// What an item said. This api takes a string or a list of parts, and what a
/// ledger keeps is what was said either way.
fn contentText(arena: Allocator, content: ?std.json.Value) ![]const u8 {
    const v = content orelse return "";
    if (v == .string) return v.string;
    if (v != .array) return "";
    var out: std.ArrayList(u8) = .empty;
    for (v.array.items) |part| {
        if (part != .object) continue;
        const text = str(part.object.get("text")) orelse continue;
        if (out.items.len > 0) try out.append(arena, '\n');
        try out.appendSlice(arena, text);
    }
    return out.items;
}

/// A tool on the wire is a schema, so this is the inverse of
/// `toolbox.writeParameters`. The 🔌 is not here to be recovered — it never
/// went out.
fn readTool(arena: Allocator, out: *std.ArrayList(doc.Record), t: std.json.Value) !void {
    if (t != .object) return;
    const name = str(t.object.get("name")) orelse return;

    var props: std.ArrayList(toolbox.Property) = .empty;
    if (t.object.get("parameters")) |schema|
        try toolbox.readParameters(arena, &props, schema);

    try out.append(arena, .{
        .sigil = .tool,
        .value = name,
        .content = try toolbox.render(arena, .md, .{
            .name = name,
            .description = str(t.object.get("description")) orelse "",
            .properties = props.items,
        }),
    });
    // Being on the wire at all is what it means for a tool to be offered, and
    // a 🧰 with no block is how that is said.
    try out.append(arena, .{ .sigil = .tool, .value = name });
}

/// The fields that are the request's shape rather than something asked for.
/// `stream` is among them: it belongs to a run, not to a conversation, and m8
/// decides it each time.
fn structural(key: []const u8) bool {
    for ([_][]const u8{ "model", "input", "tools", "instructions", "stream" }) |k| {
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
        .{ .sigil = .thought, .content = "hmm\n:lock_with_ink_pen:rs_1,ENCRYPTED" },
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

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, _: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        if (self.seen.items.len > 0) try self.seen.append(self.arena, '\n');
        try self.seen.appendSlice(self.arena, @tagName(s));
        try self.seen.append(self.arena, ':');
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
    }
    fn closeFn(_: *anyopaque) anyerror!void {}
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

    try testing.expectEqual(@as(usize, 3), reply.records.len);
    try testing.expectEqual(sigil.Sigil.thought, reply.records[0].sigil);
    // The id and the encrypted content are kept with the thought they sign,
    // because this api wants both back before it will believe it.
    try testing.expectEqualStrings(
        "weighing it\n:lock_with_ink_pen:rs_1,ENCRYPTED",
        reply.records[0].content.?,
    );
    try testing.expectEqual(sigil.Sigil.bot, reply.records[1].sigil);
    try testing.expectEqualStrings("Let me look.", reply.records[1].content.?);
    try testing.expectEqual(sigil.Sigil.call, reply.records[2].sigil);
    try testing.expectEqualStrings("say,call_1", reply.records[2].value);

    // Streamed as it arrived, and the 🔏 when the item that carried it ended.
    // The 📲 did not: a call cannot be shown until it is whole.
    try testing.expectEqualStrings(
        "thought:weighing it\n:lock_with_ink_pen:rs_1,ENCRYPTED\nbot:Let me look.",
        collect.seen.items,
    );

    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("call_1", reply.calls[0].id);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
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

    try testing.expectEqual(@as(usize, 3), reply.records.len);
    try testing.expectEqualStrings(
        "weighing it\n:lock_with_ink_pen:rs_1,ENCRYPTED",
        reply.records[0].content.?,
    );
    try testing.expectEqualStrings("Let me look.", reply.records[1].content.?);
    try testing.expectEqualStrings("say,call_1", reply.records[2].value);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "an error arriving with a 200 is still an error" {
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
    try testing.expectError(Error.ApiSaidError, parse(arena, &r, collect.sink()));
}

test "a request decodes to a ledger and encodes back to the same request" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const request =
        \\{"model":"gpt-5.5","max_output_tokens":2048,"store":false,"include":["reasoning.encrypted_content"],"instructions":"Be brief.","input":[{"role":"user","content":"Say hi."},{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"hmm"}],"encrypted_content":"ENC"},{"type":"function_call","call_id":"call_1","name":"say","arguments":"{\"text\":\"hi\"}"},{"type":"function_call_output","call_id":"call_1","output":"hi"}],"tools":[{"type":"function","name":"say","description":"Say a thing.","parameters":{"type":"object","properties":{"text":{"type":"string","description":"What to say"}},"required":["text"]}}]}
    ;
    const records = try decode(arena, request);

    try testing.expectEqual(sigil.Sigil.agent, records[0].sigil);
    try testing.expectEqualStrings(
        "/gpt-5.5,max_output_tokens:2048,store:false,include:[\"reasoning.encrypted_content\"]",
        records[0].value,
    );
    try testing.expectEqual(sigil.Sigil.tool, records[1].sigil);
    try testing.expectEqual(sigil.Sigil.tool, records[2].sigil);
    try testing.expectEqual(sigil.Sigil.system, records[3].sigil);
    try testing.expectEqual(sigil.Sigil.user, records[4].sigil);
    try testing.expectEqual(sigil.Sigil.thought, records[5].sigil);
    try testing.expectEqualStrings("hmm\n:lock_with_ink_pen:rs_1,ENC", records[5].content.?);
    try testing.expectEqual(sigil.Sigil.call, records[6].sigil);
    // Nothing on the wire said whether it worked, so it comes back a 🧾.
    try testing.expectEqual(sigil.Sigil.result, records[7].sigil);

    const m = (try modelform.parse(arena, records[0].value)).?;
    const tool = try toolbox.parse(arena, .md, records[1].value, records[1].content.?);
    const back = try encode(arena, records, .{
        .model = m.name,
        .params = m.params,
        .tools = &.{tool},
    });
    try testing.expectEqualStrings(request, back);
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
    // reply and not an error.
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 1), reply.records.len);
    try testing.expectEqualStrings(
        "working it through\n:lock_with_ink_pen:rs_1,ENC",
        reply.records[0].content.?,
    );
}
