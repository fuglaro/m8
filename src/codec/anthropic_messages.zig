//! The Anthropic messages api.
//!
//! A ledger is records in the order they happened. This api wants them
//! gathered: the system prompt is a field of its own rather than a message,
//! and everything else is a run of content blocks under alternating `user` and
//! `assistant` messages. So this is where the hoisting and the grouping live —
//! not in the ledger, which keeps saying what happened.
//!
//! It carries more of a ledger than chat completions does, and the two places
//! it does are worth naming, because they are the two this format has records
//! for:
//!
//! * A thought is a `thinking` block with a `signature`, so 💭 and its 🔏
//!   survive the round trip and a reply that thought before it answered can be
//!   sent back and believed. A 💭 with no 🔏 is dropped rather than sent — the
//!   api refuses an unsigned one, and a thought that came off some other wire
//!   has no signature to give it.
//! * A tool result carries `is_error`, so a 🚫 goes out as a failure and comes
//!   back as one, where chat completions could only ever say 🧾.
//!
//! What it still cannot carry, it drops: a 🔌 is m8's business rather than the
//! model's, and 🟢 has nothing to be — that a tool worked is the ordinary case
//! and this api has no field for saying so.
//!
//! `max_tokens` is the one parameter named here. The api requires it, so a
//! request without one is not a request, and a codec that wrote an invalid
//! one would be broken rather than neutral. Whatever the 🧠 says wins; this is
//! only what is written when the ledger says nothing.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const modelform = @import("../m8/model.zig");
const toolbox = @import("../toolbox.zig");
const api = @import("../codec.zig");

pub const codec_name = "anthropic-messages";

pub const codec: api.Codec = .{
    .name = codec_name,
    .summary = "Anthropic messages",
    .encode = encode,
    .parse = parse,
};

/// What is asked for when the ledger asks for nothing. The api requires the
/// field; the number is only a number, and any 🧠 that names one replaces it.
pub const default_max_tokens = 16000;

/// The version this codec speaks, for a provider command that wants to send
/// one. m8 sends no headers — that is the command's business — and this is
/// here so the entry that names the header and the codec that writes the body
/// cannot drift apart silently.
pub const version = "2023-06-01";

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
    var asked_for_tokens = false;
    for (target.params) |p| {
        if (std.mem.eql(u8, p.key, "max_tokens")) asked_for_tokens = true;
        try s.objectField(p.key);
        try s.write(modelform.json(arena, p.value));
    }
    if (!asked_for_tokens) {
        try s.objectField("max_tokens");
        try s.write(default_max_tokens);
    }

    try writeSystem(arena, &s, records);

    try s.objectField("messages");
    try s.beginArray();
    try writeTurns(arena, &s, records);
    try s.endArray();

    if (target.tools.len > 0) {
        try s.objectField("tools");
        try s.beginArray();
        for (target.tools) |t| {
            try s.beginObject();
            try s.objectField("name");
            try s.write(t.name);
            if (t.description.len > 0) {
                try s.objectField("description");
                try s.write(t.description);
            }
            // The same schema chat completions hangs from `parameters`. Which
            // field it hangs from is all that differs.
            try s.objectField("input_schema");
            try toolbox.writeParameters(&s, t.properties);
            try s.endObject();
        }
        try s.endArray();
    }
    try s.endObject();
    return buf.written();
}

/// Every 🧭, joined into the field this api keeps them in. A ledger may hold
/// several, anywhere; the api has one, and it is not a message.
fn writeSystem(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    var text: std.ArrayList(u8) = .empty;
    for (records) |r| {
        if (r.sigil != .system) continue;
        const c = r.content orelse continue;
        if (text.items.len > 0) try text.append(arena, '\n');
        try text.appendSlice(arena, c);
    }
    if (text.items.len == 0) return;
    try s.objectField("system");
    try s.write(text.items);
}

/// Which of the two roles a record speaks as. A tool's answer is the person's
/// turn here, which is this api's arrangement rather than the ledger's.
const Side = enum {
    user,
    assistant,

    fn role(side: Side) []const u8 {
        return switch (side) {
            .user => "user",
            .assistant => "assistant",
        };
    }
};

/// A message under construction: this api takes runs of blocks rather than a
/// message per record, so one stays open until the side changes.
const Turn = struct {
    s: *std.json.Stringify,
    open: ?Side = null,

    fn speak(t: *Turn, side: Side) !void {
        if (t.open) |current| {
            if (current == side) return;
            try t.close();
        }
        try t.s.beginObject();
        try t.s.objectField("role");
        try t.s.write(side.role());
        try t.s.objectField("content");
        try t.s.beginArray();
        t.open = side;
    }

    fn close(t: *Turn) !void {
        if (t.open == null) return;
        try t.s.endArray();
        try t.s.endObject();
        t.open = null;
    }
};

fn writeTurns(arena: Allocator, s: *std.json.Stringify, records: []const doc.Record) !void {
    // An answer is bound to its call by id, and this api wants it in the
    // message directly after the one that asked. A ledger may hold them apart
    // — somebody can say something between asking and being answered, and a
    // run that picks up an owed call answers it long after — so the pairing is
    // by id here, and a record already written is not written again where it
    // actually stands.
    const claimed = try arena.alloc(bool, records.len);
    @memset(claimed, false);

    var turn: Turn = .{ .s = s };
    var i: usize = 0;
    while (i < records.len) {
        const r = records[i];
        switch (r.sigil) {
            .user => {
                try turn.speak(.user);
                try writeText(s, r.content orelse "");
                i += 1;
            },
            .thought => {
                if (try signed(arena, api.thoughtText(r))) |thought| {
                    try turn.speak(.assistant);
                    try writeThinking(s, try owedTo(arena, records, i, thought));
                }
                i += 1;
            },
            .bot => {
                try turn.speak(.assistant);
                try writeText(s, r.content orelse "");
                i += 1;
            },
            .call => i = try run(arena, &turn, records, i, claimed),
            // An answer whose call was never written still names what it
            // answers, and is left where the ledger put it.
            .result, .scroll, .link, .ok, .failed => {
                if (!claimed[i]) {
                    const id = std.mem.trim(u8, r.value, " \t");
                    if (try answerTo(arena, records, claimed, i, id)) |a| {
                        try turn.speak(.user);
                        try writeResult(s, id, a);
                    }
                }
                i += 1;
            },
            else => i += 1,
        }
    }
    try turn.close();
}

/// One assistant turn's worth of calling: every 📲 in the run onto the message
/// that made them, then the answer to each, wherever in the ledger it ended
/// up. This api requires that adjacency, so it is what the projection makes.
fn run(
    arena: Allocator,
    turn: *Turn,
    records: []const doc.Record,
    start: usize,
    claimed: []bool,
) !usize {
    var end = start;
    while (end < records.len) : (end += 1) {
        switch (records[end].sigil) {
            .call, .result, .scroll, .link, .ok, .failed => {},
            else => break,
        }
    }

    for (records[start..end]) |r| {
        if (r.sigil != .call) continue;
        try turn.speak(.assistant);
        try turn.s.beginObject();
        try turn.s.objectField("type");
        try turn.s.write("tool_use");
        try turn.s.objectField("id");
        try turn.s.write(callId(r.value));
        try turn.s.objectField("name");
        try turn.s.write(callName(r.value));
        try turn.s.objectField("input");
        // An object rather than the string chat completions takes, so the
        // arguments go back as the JSON they were.
        try turn.s.write(try arguments(arena, r.content orelse ""));
        try turn.s.endObject();
    }

    for (records[start..end]) |r| {
        if (r.sigil != .call) continue;
        const id = callId(r.value);
        if (try answerTo(arena, records, claimed, start, id)) |a| {
            try turn.speak(.user);
            try writeResult(turn.s, id, a);
        }
    }

    // Anything in the run that answered no call of this run belongs here all
    // the same; the ledger is what says so.
    for (records[start..end], start..) |r, idx| {
        switch (r.sigil) {
            .result, .scroll, .link, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        const id = std.mem.trim(u8, r.value, " \t");
        if (try answerTo(arena, records, claimed, idx, id)) |a| {
            try turn.speak(.user);
            try writeResult(turn.s, id, a);
        }
    }
    return end;
}

/// What a call was answered with: the output, the files handed over beside
/// it, and whether it ended badly.
const Answer = struct {
    said: []const u8,
    /// The 🔗 blocks beside it.
    links: []const []const u8 = &.{},
    failed: bool,
};

/// What answered `id`, from `from` onward, as the one block this api has room
/// for. Null when nothing answered it, which is a call still owed.
///
/// A call is answered by what the tool said and then by how it went. The
/// saying is joined into `content`; the verdict is `is_error`, which is the
/// one thing this api can say that chat completions cannot. 🟢 adds nothing —
/// that a tool worked is the ordinary case, and its absence says so.
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
    var failed = false;

    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .scroll, .link, .ok, .failed => {},
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
        if (r.sigil == .failed) failed = true;
        if (r.content) |content| if (content.len > 0) {
            if (said.items.len > 0) try said.append(arena, '\n');
            try said.appendSlice(arena, content);
        };

        // A verdict ends the answer; anything later with this id answers a
        // call made again rather than this one.
        if (r.sigil != .result and r.sigil != .scroll) break;
    }
    return if (found) .{
        .said = said.items,
        .links = links.items,
        .failed = failed,
    } else null;
}

fn writeText(s: *std.json.Stringify, content: []const u8) !void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("text");
    try s.objectField("text");
    try s.write(content);
    try s.endObject();
}

fn writeThinking(s: *std.json.Stringify, thought: Thought) !void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("thinking");
    try s.objectField("thinking");
    try s.write(thought.text);
    try s.objectField("signature");
    try s.write(thought.signature);
    try s.endObject();
}

fn writeResult(s: *std.json.Stringify, id: []const u8, a: Answer) !void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("tool_result");
    try s.objectField("tool_use_id");
    try s.write(id);
    try s.objectField("content");
    if (a.links.len == 0) try s.write(a.said) else {
        // Files go beside what was said, as blocks of their own.
        try s.beginArray();
        if (a.said.len > 0) try writeText(s, a.said);
        for (a.links) |content| {
            var lines = std.mem.splitScalar(u8, content, '\n');
            while (lines.next()) |line| {
                const mime, const uri, _ = (try api.handed(line)) orelse continue;
                try s.beginObject();
                try s.objectField("type");
                try s.write(if (std.mem.startsWith(u8, mime, "image/")) "image" else "document");
                try s.objectField("source");
                try s.beginObject();
                try s.objectField("type");
                if (std.mem.cutPrefix(u8, uri, "ref:")) |ref| {
                    try s.write("file");
                    try s.objectField("file_id");
                    try s.write(ref);
                } else if (std.mem.startsWith(u8, uri, "data:")) {
                    _, const data = std.mem.cutScalar(u8, uri, ',') orelse .{ "", "" };
                    try s.write("base64");
                    try s.objectField("media_type");
                    try s.write(mime);
                    try s.objectField("data");
                    try s.write(data);
                } else {
                    try s.write("url");
                    try s.objectField("url");
                    try s.write(uri);
                }
                try s.endObject();
                try s.endObject();
            }
        }
        try s.endArray();
    }
    if (a.failed) {
        try s.objectField("is_error");
        try s.write(true);
    }
    try s.endObject();
}

/// A call's arguments as the object this api wants. `parseArgs` always builds
/// one, so what cannot be read is an empty one rather than a string in a
/// field that has no room for it.
fn arguments(arena: Allocator, content: []const u8) !std.json.Value {
    const args = try toolbox.parseArgs(arena, .md, content);
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, args, .{}) catch
        return .{ .object = .empty };
    return if (v == .object) v else .{ .object = .empty };
}

/// A 💭's content split into what was thought and what signs it.
const Thought = struct {
    text: []const u8 = "",
    signature: []const u8 = "",
};

/// A 💭 with its 🔏, or null when it carries none.
///
/// The api refuses an unsigned thinking block, so one is not sent. A thought
/// that arrived from somewhere else has no signature to give, and dropping it
/// is this projection losing what the target cannot say.
fn signed(arena: Allocator, content: []const u8) !?Thought {
    var text: std.ArrayList(u8) = .empty;
    var signature: []const u8 = "";
    var said = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (signatureOn(line)) |value| {
            signature = value;
            continue;
        }
        if (said) try text.append(arena, '\n');
        said = true;
        try text.appendSlice(arena, line);
    }
    if (signature.len == 0) return null;
    return .{ .text = text.items, .signature = signature };
}

/// A signed thought with the unsigned 💭 just before it put back in front:
/// one thinking block is written as what was thought and then the 🔏 kept
/// aside, and this api wants the two as one block again.
fn owedTo(arena: Allocator, records: []const doc.Record, at: usize, thought: Thought) !Thought {
    var from = at;
    while (from > 0 and records[from - 1].sigil == .thought and
        (try signed(arena, api.thoughtText(records[from - 1]))) == null) from -= 1;
    if (from == at) return thought;

    var text: std.ArrayList(u8) = .empty;
    for (records[from..at]) |r| {
        if (text.items.len > 0) try text.append(arena, '\n');
        try text.appendSlice(arena, api.thoughtText(r));
    }
    if (thought.text.len > 0) {
        if (text.items.len > 0) try text.append(arena, '\n');
        try text.appendSlice(arena, thought.text);
    }
    return .{ .text = text.items, .signature = thought.signature };
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

/// A thinking block as records: what was thought, then its 🔏 in a 💭 of its
/// own asking to be kept aside. The text is for reading and the signature
/// only for giving the thought back, so only the text stays in sight.
fn thinking(
    arena: Allocator,
    out: *std.ArrayList(doc.Record),
    text: []const u8,
    signature: []const u8,
) !void {
    if (text.len > 0) try out.append(arena, .{ .sigil = .thought, .content = text });
    if (signature.len == 0) return;
    try out.append(arena, .{ .sigil = .thought, .value = api.snip, .content = try sealed(arena, signature) });
}

/// A 🔏 as content, in the spelling every file is written in; a reader is
/// handed whichever one they are being written.
fn sealed(arena: Allocator, signature: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}{s}", .{ sigil.Sigil.signature.text(.md), signature });
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

/// Server-sent events: a block is opened, deltaed and closed, and the message
/// ends. Every event names its own type, so nothing here has to be inferred
/// from position — which is why this reads as a state machine and the chat
/// completions one reads as a fold.
fn events(arena: Allocator, r: *std.Io.Reader, sink: api.Sink, first: []const u8) !api.Reply {
    var built: Building = .{ .arena = arena, .sink = sink };

    var line = first;
    while (true) {
        if (std.mem.startsWith(u8, line, "data:")) {
            const payload = std.mem.trim(u8, line["data:".len..], " ");
            if (std.json.parseFromSliceLeaky(std.json.Value, arena, payload, .{})) |v| {
                if (try event(&built, v)) break;
            } else |_| {}
        }
        const raw = (try api.nextLine(arena, r)) orelse break;
        line = std.mem.trimEnd(u8, raw, "\r\n");
    }
    return built.finish();
}

/// One event. True when the message is over.
fn event(built: *Building, v: std.json.Value) !bool {
    if (v != .object) return false;
    const kind = str(v.object.get("type")) orelse return false;

    if (std.mem.eql(u8, kind, "message_start")) {
        const m = v.object.get("message") orelse return false;
        if (m == .object) built.tally(m.object.get("usage"));
    } else if (std.mem.eql(u8, kind, "content_block_start")) {
        const block = v.object.get("content_block") orelse return false;
        if (block != .object) return false;
        try built.start(block);
    } else if (std.mem.eql(u8, kind, "content_block_delta")) {
        const d = v.object.get("delta") orelse return false;
        if (d != .object) return false;
        const which = str(d.object.get("type")) orelse return false;
        const carries = if (std.mem.eql(u8, which, "text_delta"))
            "text"
        else if (std.mem.eql(u8, which, "thinking_delta"))
            "thinking"
        else if (std.mem.eql(u8, which, "signature_delta"))
            "signature"
        else if (std.mem.eql(u8, which, "input_json_delta"))
            "partial_json"
        else
            return false;
        if (str(d.object.get(carries))) |fragment| try built.delta(which, fragment);
    } else if (std.mem.eql(u8, kind, "content_block_stop")) {
        try built.stop();
    } else if (std.mem.eql(u8, kind, "message_delta")) {
        const d = v.object.get("delta") orelse return false;
        if (d == .object) {
            if (str(d.object.get("stop_reason"))) |why| built.reason = why;
            built.category = categoryOf(d);
        }
        built.tally(v.object.get("usage"));
    } else if (std.mem.eql(u8, kind, "message_stop")) {
        return true;
    } else if (std.mem.eql(u8, kind, "error")) {
        // An overload or a bad request arrives here with a 200, so this is
        // the only thing that would notice it. Saying nothing would record a
        // turn in which the model simply said nothing.
        if (built.kind != .none) try built.stop();
        try api.failed(built.arena, built.sink, v.object.get("error"));
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
    if (v.object.get("type")) |t| if (t == .string and std.mem.eql(u8, t.string, "error")) {
        try api.failed(arena, sink, v.object.get("error"));
        return .{};
    };

    var built: Building = .{ .arena = arena, .sink = sink };
    built.reason = str(v.object.get("stop_reason")) orelse "";
    built.category = categoryOf(v);
    built.tally(v.object.get("usage"));
    const content = v.object.get("content") orelse return built.finish();
    if (content != .array) return built.finish();
    for (content.array.items) |block| {
        if (block != .object) continue;
        try built.start(block);
        try built.stop();
    }
    return built.finish();
}

/// How a message ended, in this api's words.
const stops = api.Stops.initComptime(.{
    .{ "end_turn", "" },
    .{ "tool_use", "" },
    .{ "max_tokens", "cut off at" },
    .{ "model_context_window_exceeded", "context full at" },
    .{ "stop_sequence", "stopped at" },
    .{ "pause_turn", "paused at" },
    .{ "refusal", "declined with" },
});

/// Which policy a refusal was made under, from the `stop_details` beside a
/// stop reason. Empty when there is none, or it names none.
fn categoryOf(holder: std.json.Value) []const u8 {
    const details = holder.object.get("stop_details") orelse return "";
    if (details != .object) return "";
    return str(details.object.get("category")) orelse "";
}

/// The block being read, and the reply being built out of the blocks that
/// were.
///
/// A block names its own kind when it opens, so what is being built is never
/// guessed at. The streamed and the whole shapes differ only in whether the
/// content arrives between `start` and `stop` or was already in the block
/// that opened, which is what lets one machine read both.
const Building = struct {
    arena: Allocator,
    sink: api.Sink,
    calls: std.ArrayList(api.Call) = .empty,

    kind: Kind = .none,
    shown: bool = false,
    signature: std.ArrayList(u8) = .empty,
    id: []const u8 = "",
    name: []const u8 = "",
    args: std.ArrayList(u8) = .empty,
    /// Of the message rather than any block, and only known at its end.
    reason: []const u8 = "",
    category: []const u8 = "",
    /// What the message cost, as far as it has said: `message_start` says it
    /// first and `message_delta` again as the counts run on.
    cost: api.Cost = .{},
    costed: bool = false,
    fresh: i64 = 0,

    const Kind = enum { none, text, thinking, tool_use };

    fn start(b: *Building, block: std.json.Value) !void {
        b.kind = .none;
        b.shown = false;
        b.signature = .empty;
        b.args = .empty;
        b.id = "";
        b.name = "";

        const which = str(block.object.get("type")) orelse return;
        if (std.mem.eql(u8, which, "text")) {
            b.kind = .text;
            try b.say(.bot, str(block.object.get("text")) orelse "");
        } else if (std.mem.eql(u8, which, "thinking")) {
            b.kind = .thinking;
            try b.say(.thought, str(block.object.get("thinking")) orelse "");
            // Only the whole shape carries one here; streaming deltas it.
            if (str(block.object.get("signature"))) |sig|
                try b.signature.appendSlice(b.arena, sig);
        } else if (std.mem.eql(u8, which, "tool_use")) {
            b.kind = .tool_use;
            b.id = str(block.object.get("id")) orelse "";
            b.name = str(block.object.get("name")) orelse "";
            // A streamed block opens with an empty input and deltas the
            // arguments in; a whole one has them already. An empty object is
            // the same thing either way, so it is left for `stop` to write
            // and nothing has to know which shape this is.
            if (block.object.get("input")) |input| {
                var buf: std.Io.Writer.Allocating = .init(b.arena);
                try std.json.Stringify.value(input, .{}, &buf.writer);
                if (!std.mem.eql(u8, buf.written(), "{}"))
                    try b.args.appendSlice(b.arena, buf.written());
            }
        }
    }

    /// A usage object, over whatever an earlier one said. `input_tokens` is
    /// only what the cache did not touch here, so what was read from it and
    /// what was written to it are added back to make the whole prompt.
    fn tally(b: *Building, usage: ?std.json.Value) void {
        const u = usage orelse return;
        if (u != .object) return;
        b.costed = true;
        if (num(u.object.get("cache_read_input_tokens"))) |n| b.cost.cached = n;
        if (num(u.object.get("cache_creation_input_tokens"))) |n| b.cost.written = n;
        if (num(u.object.get("output_tokens"))) |n| b.cost.out = n;
        if (num(u.object.get("input_tokens"))) |n| b.fresh = n;
        b.cost.in = b.fresh + b.cost.cached + b.cost.written;
    }

    fn delta(b: *Building, which: []const u8, fragment: []const u8) !void {
        if (std.mem.eql(u8, which, "signature_delta")) {
            return b.signature.appendSlice(b.arena, fragment);
        }
        if (std.mem.eql(u8, which, "input_json_delta")) {
            return b.args.appendSlice(b.arena, fragment);
        }
        return b.say(if (b.kind == .thinking) .thought else .bot, fragment);
    }

    /// Out to whoever is reading. A record opens on its first byte, so one
    /// the model left empty never reaches the pipe at all.
    fn say(b: *Building, s: sigil.Sigil, fragment: []const u8) !void {
        if (fragment.len == 0) return;
        if (!b.shown) {
            try b.sink.begin(s, "");
            b.shown = true;
        }
        try b.sink.text(fragment);
    }

    fn stop(b: *Building) !void {
        switch (b.kind) {
            .none, .text => {},
            .thinking => {
                // The text has already streamed; its 💭 closes before the
                // 🔏 is written as a record of its own, known only now the
                // block has ended.
                if (b.shown) try b.sink.end();
                b.shown = false;
                if (b.signature.items.len > 0)
                    try b.sink.record(.thought, api.snip, try sealed(b.arena, b.signature.items));
            },
            .tool_use => {
                const raw = if (b.args.items.len == 0) "{}" else b.args.items;
                try b.calls.append(b.arena, .{
                    .id = b.id,
                    .name = b.name,
                    .arguments = raw,
                });
            },
        }
        if (b.shown) try b.sink.end();
        b.kind = .none;
        b.shown = false;
    }

    /// A stream that stopped without closing its block still gives up what it
    /// had: a thought that was cut off is a thought that was cut off, and the
    /// ledger says so rather than losing it.
    fn finish(b: *Building) !api.Reply {
        if (b.kind != .none) try b.stop();
        if (b.category.len > 0 and std.mem.eql(u8, b.reason, "refusal")) {
            // Which policy, in its own word, ahead of the reason's.
            const how = try std.fmt.allocPrint(b.arena, "declined by {s}", .{b.category});
            try api.stoppedAs(b.arena, b.sink, how, b.reason);
        } else {
            try api.stopped(b.arena, b.sink, stops, b.reason);
        }
        const aside = if (b.costed) try api.costLine(b.arena, b.cost) else "";
        return .{ .calls = b.calls.items, .aside = aside };
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

test "an extra that collides with m8's own key never reaches the wire" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const tool = try toolbox.parse(arena, .md, "grep",
        \\* q string,description:extra,pattern:^a
        \\  native
    );
    const records = [_]doc.Record{.{ .sigil = .user, .content = "Hi." }};
    const first = try encode(arena, &records, .{ .model = "tiny", .tools = &.{tool} });
    try testing.expect(std.mem.indexOf(u8, first, "extra") == null);
    try testing.expect(std.mem.indexOf(u8, first, "\"pattern\":\"^a\"") != null);
}

fn requestOf(arena: Allocator, records: []const doc.Record, target: api.Target) !std.json.Value {
    const body = try encode(arena, records, target);
    return std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
}

test "the system prompt is a field of its own, and max_tokens is always said" {
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
    const v = try requestOf(arena, &records, .{ .model = "claude-opus-5" });

    try testing.expectEqualStrings("Be brief.\nBe kind.", field(v, "system").string);
    // Not a message: the api has a field for it, so nothing is hoisted into
    // the conversation that was not part of it.
    const msgs = field(v, "messages").array.items;
    try testing.expectEqual(@as(usize, 1), msgs.len);
    try testing.expectEqualStrings("user", field(msgs[0], "role").string);
    // The api requires it, so a request without one is not a request.
    try testing.expectEqual(@as(i64, default_max_tokens), field(v, "max_tokens").integer);

    // Whatever the 🧠 says wins.
    const asked = try requestOf(arena, &records, .{
        .model = "claude-opus-5",
        .params = &.{.{ .key = "max_tokens", .value = "2048" }},
    });
    try testing.expectEqual(@as(i64, 2048), field(asked, "max_tokens").integer);
}

test "records group into messages, and an answer follows the call that asked" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .user, .content = "Say hi." },
        .{ .sigil = .bot, .content = "Let me look." },
        .{ .sigil = .call, .value = "say,c1", .content = "* text `hi`" },
        .{ .sigil = .result, .value = "c1", .content = "hi" },
        .{ .sigil = .call, .value = "say,c2", .content = "* text `bye`" },
        .{ .sigil = .failed, .value = "c2", .content = "nope" },
        .{ .sigil = .bot, .content = "Done." },
    };
    const v = try requestOf(arena, &records, .{ .model = "claude-opus-5" });
    const msgs = field(v, "messages").array.items;

    // user / assistant / user / assistant, because that is what this api
    // takes — the ledger's seven records are four turns here.
    try testing.expectEqual(@as(usize, 4), msgs.len);
    try testing.expectEqualStrings("user", field(msgs[0], "role").string);
    try testing.expectEqualStrings("assistant", field(msgs[1], "role").string);
    try testing.expectEqualStrings("user", field(msgs[2], "role").string);
    try testing.expectEqualStrings("assistant", field(msgs[3], "role").string);

    // The text it said and both calls, on the one turn that made them.
    const asked = field(msgs[1], "content").array.items;
    try testing.expectEqual(@as(usize, 3), asked.len);
    try testing.expectEqualStrings("text", field(asked[0], "type").string);
    try testing.expectEqualStrings("Let me look.", field(asked[1 - 1], "text").string);
    try testing.expectEqualStrings("tool_use", field(asked[1], "type").string);
    try testing.expectEqualStrings("say", field(asked[1], "name").string);
    try testing.expectEqualStrings("c1", field(asked[1], "id").string);
    // The arguments go back as the object they were, not as a string of one.
    try testing.expectEqualStrings("hi", field(field(asked[1], "input"), "text").string);
    try testing.expectEqualStrings("c2", field(asked[2], "id").string);

    // Both answers in the message directly after, which this api requires.
    const back = field(msgs[2], "content").array.items;
    try testing.expectEqual(@as(usize, 2), back.len);
    try testing.expectEqualStrings("tool_result", field(back[0], "type").string);
    try testing.expectEqualStrings("c1", field(back[0], "tool_use_id").string);
    try testing.expectEqualStrings("hi", field(back[0], "content").string);
    try testing.expect(back[0].object.get("is_error") == null);
    // 🚫 is the one thing chat completions could not say and this api can.
    try testing.expectEqualStrings("c2", field(back[1], "tool_use_id").string);
    try testing.expect(field(back[1], "is_error").bool);
}

test "a thought goes out only when it is signed" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .user, .content = "Hi." },
        .{ .sigil = .thought, .value = "hmm" },
        .{ .sigil = .thought, .value = api.snip, .content = ":lock_with_ink_pen:abc123" },
        .{ .sigil = .thought, .content = "came off another wire" },
        .{ .sigil = .bot, .content = "Hello." },
    };
    const v = try requestOf(arena, &records, .{ .model = "claude-opus-5" });
    const blocks = field(field(v, "messages").array.items[1], "content").array.items;

    // The signed one, and then what was said. The unsigned one is dropped:
    // the api refuses it, and there is no signature to invent.
    try testing.expectEqual(@as(usize, 2), blocks.len);
    try testing.expectEqualStrings("thinking", field(blocks[0], "type").string);
    try testing.expectEqualStrings("hmm", field(blocks[0], "thinking").string);
    try testing.expectEqualStrings("abc123", field(blocks[0], "signature").string);
    try testing.expectEqualStrings("Hello.", field(blocks[1], "text").string);
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

test "a streamed reply reads as the blocks it was made of" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: content_block_start
        \\data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"weighing it"}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc123"}}
        \\
        \\event: content_block_stop
        \\data: {"type":"content_block_stop","index":0}
        \\
        \\event: content_block_start
        \\data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Let me look."}}
        \\
        \\event: content_block_stop
        \\data: {"type":"content_block_stop","index":1}
        \\
        \\event: content_block_start
        \\data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"say","input":{}}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"text\":"}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"hi\"}"}}
        \\
        \\event: content_block_stop
        \\data: {"type":"content_block_stop","index":2}
        \\
        \\event: message_stop
        \\data: {"type":"message_stop"}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqual(sigil.Sigil.thought, collect.got.records.items[0].sigil);
    try testing.expectEqualStrings("weighing it", collect.got.records.items[0].content.?);
    // The signature follows the thought it signs, in a 💭 asking to be kept
    // aside, so the reply can be sent back and believed without being read.
    try testing.expectEqual(sigil.Sigil.thought, collect.got.records.items[1].sigil);
    try testing.expectEqualStrings(api.snip, collect.got.records.items[1].value);
    try testing.expectEqualStrings(":lock_with_ink_pen:abc123", collect.got.records.items[1].content.?);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[2].sigil);
    try testing.expectEqualStrings("Let me look.", collect.got.records.items[2].content.?);

    // 💭 and 🤖 reached the reader as they arrived, and the 🔏 when the block
    // that carried it ended. The 📲 did not: a call cannot be shown until it
    // is whole.
    try testing.expectEqualStrings(
        "thought:weighing it\nthought::lock_with_ink_pen:abc123\nbot:Let me look.",
        collect.seen.items,
    );

    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("toolu_1", reply.calls[0].id);
    try testing.expectEqualStrings("say", reply.calls[0].name);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "a whole reply reads the same as a streamed one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\{"id":"msg_1","type":"message","role":"assistant","content":[
        \\{"type":"thinking","thinking":"weighing it","signature":"abc123"},
        \\{"type":"text","text":"Let me look."},
        \\{"type":"tool_use","id":"toolu_1","name":"say","input":{"text":"hi"}}
        \\],"stop_reason":"tool_use"}
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    try testing.expectEqual(@as(usize, 3), collect.got.records.items.len);
    try testing.expectEqualStrings("weighing it", collect.got.records.items[0].content.?);
    try testing.expectEqualStrings(":lock_with_ink_pen:abc123", collect.got.records.items[1].content.?);
    try testing.expectEqualStrings("Let me look.", collect.got.records.items[2].content.?);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "a message cut off says so last, in this api's own word" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Cut off inside a tool call: the call is kept as the model wrote it,
    // and run as asked — how it stopped is said, not acted on.
    const body =
        \\event: content_block_start
        \\data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Moon"}}
        \\
        \\event: content_block_stop
        \\data: {"type":"content_block_stop","index":0}
        \\
        \\event: content_block_start
        \\data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"say","input":{}}}
        \\
        \\event: content_block_delta
        \\data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"text\":\"hi"}}
        \\
        \\event: content_block_stop
        \\data: {"type":"content_block_stop","index":1}
        \\
        \\event: message_delta
        \\data: {"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null},"usage":{"output_tokens":9}}
        \\
        \\event: message_stop
        \\data: {"type":"message_stop"}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("(cut off at max_tokens)", collect.got.records.items[1].value);
    try testing.expect(collect.got.records.items[1].content == null);

    // Whole, each reason in its own words; one never heard of still reads as
    // stopping, and finishing says nothing.
    const cases = [_]struct { []const u8, ?[]const u8 }{
        .{ "refusal", "(declined with refusal)" },
        .{ "model_context_window_exceeded", "(context full at model_context_window_exceeded)" },
        .{ "pause_turn", "(paused at pause_turn)" },
        .{ "something_new", "(stopped at something_new)" },
        .{ "end_turn", null },
        .{ "tool_use", null },
    };
    for (cases) |c| {
        const whole_body = try std.fmt.allocPrint(arena,
            \\{{"type":"message","role":"assistant","content":[],"stop_reason":"{s}"}}
        , .{c[0]});
        var wr: std.Io.Reader = .fixed(whole_body);
        var wc: Collect = .{ .arena = arena };
        _ = try parse(arena, &wr, wc.sink());
        if (c[1]) |want| {
            try testing.expectEqual(@as(usize, 1), wc.got.records.items.len);
            try testing.expectEqualStrings(want, wc.got.records.items[0].value);
        } else {
            try testing.expectEqual(@as(usize, 0), wc.got.records.items.len);
        }
    }
}

test "a refusal names its policy, ahead of the reason's own word" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const streamed =
        \\event: message_delta
        \\data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null,"stop_details":{"type":"refusal","category":"bio","explanation":null}},"usage":{"output_tokens":0}}
        \\
        \\event: message_stop
        \\data: {"type":"message_stop"}
        \\
    ;
    const at_once =
        \\{"type":"message","role":"assistant","content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"bio","explanation":null}}
    ;
    for ([_][]const u8{ streamed, at_once }) |body| {
        var r: std.Io.Reader = .fixed(body);
        var collect: Collect = .{ .arena = arena };
        _ = try parse(arena, &r, collect.sink());
        try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
        try testing.expectEqualStrings("(declined by bio refusal)", collect.got.records.items[0].value);
    }
}

test "an error is what the api said, and the reply says so" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: error
        \\data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
        \\
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());
    const said = collect.got.records.items;
    try testing.expectEqual(@as(usize, 1), said.len);
    try testing.expectEqualStrings("(Overloaded - failed with overloaded_error)", said[0].value);
    try testing.expect(said[0].content == null);

    // Whole, which is how a status that is not 200 arrives.
    var whole_r: std.Io.Reader = .fixed(
        \\{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
    );
    var again: Collect = .{ .arena = arena };
    _ = try parse(arena, &whole_r, again.sink());
    try testing.expectEqualStrings(
        "(invalid x-api-key - failed with authentication_error)",
        again.got.records.items[0].value,
    );
}

test "a finished message says what it cost, the cache counted back in" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\event: message_start
        \\data: {"type":"message_start","message":{"usage":{"input_tokens":76,"cache_creation_input_tokens":100,"cache_read_input_tokens":1024,"output_tokens":1}}}
        \\
        \\event: message_delta
        \\data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":80}}
        \\
        \\event: message_stop
        \\data: {"type":"message_stop"}
        \\
    ;
    const at_once =
        \\{"type":"message","content":[],"stop_reason":"end_turn","usage":{"input_tokens":76,"cache_creation_input_tokens":100,"cache_read_input_tokens":1024,"output_tokens":80}}
    ;
    for ([_][]const u8{ body, at_once }) |got| {
        var r: std.Io.Reader = .fixed(got);
        var collect: Collect = .{ .arena = arena };
        try testing.expectEqualStrings(
            "::stats::\u{2725}80\u{2586}1K::\u{1F9EE} 1200 in, 1024 cached (85%), 100 written, 80 out",
            (try parse(arena, &r, collect.sink())).aside,
        );
    }
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
    try testing.expect(std.mem.indexOf(u8, body, \\{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"YWJj"}},{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"YWJj"}}
    ) != null);

    records[2].content = ">image/jpeg ref:file-a\n>application/pdf ref:file-b b.pdf";
    const ids = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, ids, \\{"type":"image","source":{"type":"file","file_id":"file-a"}},{"type":"document","source":{"type":"file","file_id":"file-b"}}
    ) != null);

    records[2].content = ">image/png https://example.com/a.png a.png";
    const url = try encode(arena, &records, .{ .model = "m" });
    try testing.expect(std.mem.indexOf(u8, url, \\{"type":"image","source":{"type":"url","url":"https://example.com/a.png"}}
    ) != null);

    // A file never handed over, for want of an upload, cannot be sent.
    records[2].content = "<a.jpeg";
    try testing.expectError(error.NoUpload, encode(arena, &records, .{ .model = "m" }));
}
