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
    .decode = decode,
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
                if (try signed(arena, r.content orelse "")) |thought| {
                    try turn.speak(.assistant);
                    try writeThinking(s, thought);
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
            .result, .ok, .failed => {
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
            .call, .result, .ok, .failed => {},
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
            .result, .ok, .failed => {},
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

/// What a call was answered with: the output, and whether it ended badly.
const Answer = struct {
    said: []const u8,
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
    var found = false;
    var failed = false;

    for (records[from..], from..) |r, idx| {
        switch (r.sigil) {
            .result, .ok, .failed => {},
            else => continue,
        }
        if (claimed[idx]) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, r.value, " \t"), id)) continue;

        claimed[idx] = true;
        found = true;
        if (r.sigil == .failed) failed = true;
        if (r.content) |content| if (content.len > 0) {
            if (said.items.len > 0) try said.append(arena, '\n');
            try said.appendSlice(arena, content);
        };

        // A verdict ends the answer; anything later with this id answers a
        // call made again rather than this one.
        if (r.sigil != .result) break;
    }
    return if (found) .{ .said = said.items, .failed = failed } else null;
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
    try s.write(a.said);
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
fn withSignature(arena: Allocator, text: []const u8, signature: []const u8) ![]const u8 {
    if (signature.len == 0) return arena.dupe(u8, text);
    // The spelling every file is written in; a reader is handed whichever one
    // they are being written.
    const mark = sigil.Sigil.signature.text(.md);
    if (text.len == 0) return std.fmt.allocPrint(arena, "{s}{s}", .{ mark, signature });
    return std.fmt.allocPrint(arena, "{s}\n{s}{s}", .{ text, mark, signature });
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

    if (std.mem.eql(u8, kind, "content_block_start")) {
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
    } else if (std.mem.eql(u8, kind, "message_stop")) {
        return true;
    } else if (std.mem.eql(u8, kind, "error")) {
        // An overload or a bad request arrives here with a 200, so this is
        // the only thing that would notice it. Saying nothing would record a
        // turn in which the model simply said nothing.
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
    if (v.object.get("type")) |t| if (t == .string and std.mem.eql(u8, t.string, "error"))
        return Error.ApiSaidError;

    var built: Building = .{ .arena = arena, .sink = sink };
    const content = v.object.get("content") orelse return built.finish();
    if (content != .array) return built.finish();
    for (content.array.items) |block| {
        if (block != .object) continue;
        try built.start(block);
        try built.stop();
    }
    return built.finish();
}

pub const Error = error{ApiSaidError};

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
    records: std.ArrayList(doc.Record) = .empty,
    calls: std.ArrayList(api.Call) = .empty,

    kind: Kind = .none,
    shown: bool = false,
    text: std.ArrayList(u8) = .empty,
    signature: std.ArrayList(u8) = .empty,
    id: []const u8 = "",
    name: []const u8 = "",
    args: std.ArrayList(u8) = .empty,

    const Kind = enum { none, text, thinking, tool_use };

    fn start(b: *Building, block: std.json.Value) !void {
        b.kind = .none;
        b.shown = false;
        b.text = .empty;
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

    fn delta(b: *Building, which: []const u8, fragment: []const u8) !void {
        if (std.mem.eql(u8, which, "signature_delta")) {
            return b.signature.appendSlice(b.arena, fragment);
        }
        if (std.mem.eql(u8, which, "input_json_delta")) {
            return b.args.appendSlice(b.arena, fragment);
        }
        return b.say(if (b.kind == .thinking) .thought else .bot, fragment);
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
            .text => try b.records.append(b.arena, .{
                .sigil = .bot,
                .content = b.text.items,
            }),
            .thinking => {
                const content = try withSignature(b.arena, b.text.items, b.signature.items);
                // The 🔏 is part of the record and is only known once the
                // block ends, so it is written last — to the reader as well,
                // because what comes out of the pipe is the turn rather than
                // a view of it.
                try b.show(.thought, content[b.text.items.len..]);
                try b.records.append(b.arena, .{ .sigil = .thought, .content = content });
            },
            .tool_use => {
                const raw = if (b.args.items.len == 0) "{}" else b.args.items;
                try b.records.append(b.arena, .{
                    .sigil = .call,
                    .value = try std.fmt.allocPrint(b.arena, "{s},{s}", .{ b.name, b.id }),
                    .content = try toolbox.renderArgs(b.arena, .md, raw),
                });
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
    // was never a message and does not become one.
    if (v.object.get("system")) |system| switch (system) {
        .string => |text| try out.append(arena, .{ .sigil = .system, .content = text }),
        // The cached form is a list of text blocks. What they say is what a
        // 🧭 says; `cache_control` is the request's business.
        .array => |blocks| for (blocks.items) |block| {
            if (block != .object) continue;
            if (str(block.object.get("text"))) |text|
                try out.append(arena, .{ .sigil = .system, .content = text });
        },
        else => {},
    };

    const messages = v.object.get("messages") orelse return out.items;
    if (messages != .array) return out.items;
    for (messages.array.items) |m| try readMessage(arena, &out, m);
    return out.items;
}

fn readMessage(arena: Allocator, out: *std.ArrayList(doc.Record), m: std.json.Value) !void {
    if (m != .object) return;
    const role = str(m.object.get("role")) orelse return;
    const assistant = std.mem.eql(u8, role, "assistant");
    if (!assistant and !std.mem.eql(u8, role, "user")) return;

    const content = m.object.get("content") orelse return;
    if (content == .string) {
        try out.append(arena, .{
            .sigil = if (assistant) .bot else .user,
            .content = content.string,
        });
        return;
    }
    if (content != .array) return;
    for (content.array.items) |block| {
        if (block != .object) continue;
        try readBlock(arena, out, block, assistant);
    }
}

fn readBlock(
    arena: Allocator,
    out: *std.ArrayList(doc.Record),
    block: std.json.Value,
    assistant: bool,
) !void {
    const which = str(block.object.get("type")) orelse return;

    if (std.mem.eql(u8, which, "text")) {
        try out.append(arena, .{
            .sigil = if (assistant) .bot else .user,
            .content = str(block.object.get("text")) orelse "",
        });
    } else if (std.mem.eql(u8, which, "thinking")) {
        try out.append(arena, .{
            .sigil = .thought,
            .content = try withSignature(
                arena,
                str(block.object.get("thinking")) orelse "",
                str(block.object.get("signature")) orelse "",
            ),
        });
    } else if (std.mem.eql(u8, which, "tool_use")) {
        var buf: std.Io.Writer.Allocating = .init(arena);
        if (block.object.get("input")) |input|
            try std.json.Stringify.value(input, .{}, &buf.writer);
        const raw = if (buf.written().len == 0) "{}" else buf.written();
        try out.append(arena, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(arena, "{s},{s}", .{
                str(block.object.get("name")) orelse "",
                str(block.object.get("id")) orelse "",
            }),
            .content = try toolbox.renderArgs(arena, .md, raw),
        });
    } else if (std.mem.eql(u8, which, "tool_result")) {
        // `is_error` is what this api can say and chat completions cannot, so
        // a failure comes home a 🚫 rather than flattening to a 🧾. The 🟢 a
        // success would have had is not here to be recovered: the api has no
        // field for it, so it never went out.
        const bad = if (block.object.get("is_error")) |e| (e == .bool and e.bool) else false;
        try out.append(arena, .{
            .sigil = if (bad) .failed else .result,
            .value = str(block.object.get("tool_use_id")) orelse "",
            .content = try resultText(arena, block.object.get("content")),
        });
    }
}

/// What a tool result said. The api takes a string or a list of blocks, and
/// what a ledger keeps is what was said either way.
fn resultText(arena: Allocator, content: ?std.json.Value) ![]const u8 {
    const v = content orelse return "";
    if (v == .string) return v.string;
    if (v != .array) return "";
    var out: std.ArrayList(u8) = .empty;
    for (v.array.items) |block| {
        if (block != .object) continue;
        const text = str(block.object.get("text")) orelse continue;
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
    if (t.object.get("input_schema")) |schema|
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
    for ([_][]const u8{ "model", "messages", "tools", "system", "stream" }) |k| {
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
        .{ .sigil = .thought, .content = "hmm\n:lock_with_ink_pen:abc123" },
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

    try testing.expectEqual(@as(usize, 3), reply.records.len);
    try testing.expectEqual(sigil.Sigil.thought, reply.records[0].sigil);
    // The signature is kept with the thought that it signs, so the reply can
    // be sent back and believed.
    try testing.expectEqualStrings(
        "weighing it\n:lock_with_ink_pen:abc123",
        reply.records[0].content.?,
    );
    try testing.expectEqual(sigil.Sigil.bot, reply.records[1].sigil);
    try testing.expectEqualStrings("Let me look.", reply.records[1].content.?);
    try testing.expectEqual(sigil.Sigil.call, reply.records[2].sigil);
    try testing.expectEqualStrings("say,toolu_1", reply.records[2].value);

    // 💭 and 🤖 reached the reader as they arrived, and the 🔏 when the block
    // that carried it ended. The 📲 did not: a call cannot be shown until it
    // is whole.
    try testing.expectEqualStrings(
        "thought:weighing it\n:lock_with_ink_pen:abc123\nbot:Let me look.",
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

    try testing.expectEqual(@as(usize, 3), reply.records.len);
    try testing.expectEqualStrings(
        "weighing it\n:lock_with_ink_pen:abc123",
        reply.records[0].content.?,
    );
    try testing.expectEqualStrings("Let me look.", reply.records[1].content.?);
    try testing.expectEqualStrings("say,toolu_1", reply.records[2].value);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}

test "an error arriving with a 200 is still an error" {
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
    try testing.expectError(Error.ApiSaidError, parse(arena, &r, collect.sink()));
}

test "a request decodes to a ledger and encodes back to the same request" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const request =
        \\{"model":"claude-opus-5","max_tokens":2048,"system":"Be brief.","messages":[{"role":"user","content":[{"type":"text","text":"Say hi."}]},{"role":"assistant","content":[{"type":"thinking","thinking":"hmm","signature":"abc"},{"type":"tool_use","id":"toolu_1","name":"say","input":{"text":"hi"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"nope","is_error":true}]}],"tools":[{"name":"say","description":"Say a thing.","input_schema":{"type":"object","properties":{"text":{"type":"string","description":"What to say"}},"required":["text"]}}]}
    ;
    const records = try decode(arena, request);

    // What the wire held, as records. A 🧠 with the parameters it asked for,
    // the tool and the 🧰 that offers it, the 🧭, and then what was said.
    try testing.expectEqual(sigil.Sigil.agent, records[0].sigil);
    try testing.expectEqualStrings("/claude-opus-5,max_tokens:2048", records[0].value);
    try testing.expectEqual(sigil.Sigil.tool, records[1].sigil);
    try testing.expectEqual(sigil.Sigil.tool, records[2].sigil);
    try testing.expectEqual(sigil.Sigil.system, records[3].sigil);
    try testing.expectEqual(sigil.Sigil.user, records[4].sigil);
    try testing.expectEqual(sigil.Sigil.thought, records[5].sigil);
    try testing.expectEqualStrings("hmm\n:lock_with_ink_pen:abc", records[5].content.?);
    try testing.expectEqual(sigil.Sigil.call, records[6].sigil);
    // is_error survives the round trip, which is this api's own; chat
    // completions could only ever hand back a 🧾.
    try testing.expectEqual(sigil.Sigil.failed, records[7].sigil);

    const m = (try modelform.parse(arena, records[0].value)).?;
    const tool = try toolbox.parse(arena, .md, records[1].value, records[1].content.?);
    const back = try encode(arena, records, .{
        .model = m.name,
        .params = m.params,
        .tools = &.{tool},
    });
    try testing.expectEqualStrings(request, back);
}
