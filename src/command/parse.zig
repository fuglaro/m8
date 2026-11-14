//! `parse` — an api's response, as the turn it holds.
//!
//! The other direction. `encode` is about requests, which are ledger-shaped;
//! a response is turn-shaped, so it is read into the records it adds to a
//! ledger rather than into one.
//!
//! Reading is incremental whether or not the provider streamed. A provider
//! that wrote everything at once is a stream of one chunk, so parsing this
//! way is what lets streaming be something a provider MAY do rather than
//! MUST.
//!
//! It is what a provider names as its `parse`, and one command among any
//! that could be: an api m8 has no format for is read by whatever its
//! provider names there instead.

const std = @import("std");
const codec = @import("../codec.zig");
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const toolbox = @import("../toolbox.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "parse",
    .summary = "read an api's response as the turn it holds",
    // Not m8 on the way in, and read as it arrives rather than in one piece.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  ... | m8 parse FORMAT [--snip-chars N] [--snip-lines N]
        \\
        \\Reads an API response from stdin and writes the turn it holds as m8
        \\records. Unlike encode's ledger-shaped requests, responses are
        \\turn-shaped. Parsing is incremental, whether the provider streamed
        \\or returned everything at once.
        \\
        \\EXAMPLE:
        \\
        \\  export M8_PROVIDER_url='["echo","http://127.0.0.1:8000/v1/responses"]'
        \\  m8 say --no-send :demo/mathy "Say hi." \
        \\    | m8 encode openai-responses \
        \\    | m8 url-provider \
        \\    | m8 parse openai-responses
        \\
        \\OPTIONS:
        \\
        \\  --snip-chars N  Limit each thought to N UTF-8 characters (not bytes).
        \\  --snip-lines N  Keep at most N lines of each thought.
        \\
        \\N must be a positive integer. The first configured limit reached
        \\wins. The remainder is kept as a 💭snip and recombined unchanged when
        \\sent again. Without either option, nothing is snipped. A limited
        \\thought is held until its block closes; other records continue
        \\streaming as they arrive.
        \\
        \\ERRORS AND CAPTURE:
        \\
        \\Parse errors name the failure (for example, InvalidResponseJson or
        \\OutputItemIdMismatch). To capture the wire response, use tee:
        \\
        \\  ... | tee response.sse | m8 parse openai-responses
        \\
    );
    try codec.list(w);
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try ctx.err.writeAll("m8 parse: name a format\n");
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    }
    const c = codec.find(ctx.args[0]) orelse {
        try ctx.err.print("m8 parse: no format named '{s}'\n", .{ctx.args[0]});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    var limits: SnipLimits = .{};
    var i: usize = 1;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        if (std.mem.eql(u8, arg, "--snip-chars") or std.mem.eql(u8, arg, "--snip-lines")) {
            const is_chars = std.mem.eql(u8, arg, "--snip-chars");
            i += 1;
            if (i == ctx.args.len) {
                try ctx.err.print("m8 parse: {s} needs a value\n", .{arg});
                return 1;
            }
            const value = positiveLimit(ctx.args[i]) catch {
                try ctx.err.print("m8 parse: {s} needs a positive integer\n", .{arg});
                return 1;
            };
            if (is_chars) limits.chars = value else limits.lines = value;
        } else {
            try ctx.err.print("m8 parse: unknown option '{s}'\n", .{arg});
            return 1;
        }
    }

    var empty: std.Io.Reader = .fixed(&.{});
    const input = ctx.stdin orelse &empty;

    // Parsing reads upstream input incrementally and writes completed output live.
    var live: Live = .{ .out = ctx.out, .mode = ctx.mode };
    const reply = if (limits.enabled()) blk: {
        var snipping: SnippingSink = .{ .arena = ctx.arena, .downstream = live.sink(), .limits = limits };
        const reply = try c.parse(ctx.arena, input, snipping.sink());
        try snipping.finish();
        break :blk reply;
    } else try c.parse(ctx.arena, input, live.sink());
    try live.finish();
    // What a format has to say beside the turn, such as what it cost, is for
    // whoever is watching the run, and only once they have asked to be told.
    if (reply.aside.len > 0 and verbosity(ctx) > 0) {
        try ctx.err.print("{s}\n", .{reply.aside});
        try ctx.err.flush();
    }

    for (reply.calls) |call| {
        if (live.opened) try ctx.out.writeByte('\n');
        live.opened = true;
        try doc.write(ctx.out, ctx.mode, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(ctx.arena, "{s},{s}", .{ call.name, call.id }),
            // Arguments that are not a JSON object are kept as they came.
            .content = toolbox.renderArgs(ctx.arena, ctx.mode, call.arguments) catch call.arguments,
        });
    }
    return 0;
}

/// How much whatever started this asked to be told.
fn verbosity(ctx: Ctx) u8 {
    return ctx.verbosity;
}

const SnipLimits = struct {
    chars: ?usize = null,
    lines: ?usize = null,

    fn enabled(self: SnipLimits) bool {
        return self.chars != null or self.lines != null;
    }
};

fn positiveLimit(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.ZeroLimit;
    return value;
}

/// Buffers thought records while limits are active, then emits the readable
/// prefix and the exact remainder as a 💭snip.
const SnippingSink = struct {
    arena: std.mem.Allocator,
    downstream: codec.Sink,
    limits: SnipLimits,
    active: bool = false,
    passing: bool = false,
    has_content: bool = false,
    snipped: bool = false,
    candidate: bool = false,
    pending_tail: ?[]const u8 = null,
    value: []const u8 = "",
    content: std.ArrayList(u8) = .empty,

    fn sink(self: *SnippingSink) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *SnippingSink = @ptrCast(@alignCast(ctx));
        if (self.active or self.passing) return error.NestedRecord;
        const candidate = self.pending_tail != null and s == .thought and std.mem.eql(u8, value, "snip");
        if (self.pending_tail != null and !candidate) try self.flushPendingTail();
        if (s != .thought) {
            try self.downstream.begin(s, value);
            self.passing = true;
            return;
        }
        self.active = true;
        self.candidate = candidate;
        self.has_content = false;
        self.value = value;
        self.content = .empty;
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *SnippingSink = @ptrCast(@alignCast(ctx));
        if (!self.active) return self.downstream.text(bytes);
        if (!self.candidate and std.mem.eql(u8, self.value, "snip")) {
            // A blockful 💭snip (for example, a signature) is already kept
            // aside. A blockless 💭snip is ordinary compact thought text.
            try self.downstream.begin(.thought, self.value);
            try self.downstream.text(bytes);
            self.active = false;
            self.passing = true;
            return;
        }
        self.has_content = true;
        if (self.candidate) return self.content.appendSlice(self.arena, bytes);
        if (self.snipped) return self.content.appendSlice(self.arena, bytes);

        // Feed bytes individually so a large provider delta can release the
        // visible prefix as soon as its configured boundary is complete.
        for (bytes, 0..) |byte, i| {
            try self.content.append(self.arena, byte);
            if (snipBoundary(self.content.items, self.limits)) |cut| {
                try self.emitPrefix(self.content.items[0..cut]);
                std.mem.copyForwards(u8, self.content.items, self.content.items[cut..]);
                self.content.items.len -= cut;
                try self.content.appendSlice(self.arena, bytes[i + 1 ..]);
                self.snipped = true;
                break;
            }
        }
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *SnippingSink = @ptrCast(@alignCast(ctx));
        if (self.active) {
            if (self.candidate) {
                if (try containsSignature(self.arena, self.content.items)) {
                    try self.emitCombinedSnip();
                } else {
                    try self.flushPendingTail();
                    try self.downstream.record(.thought, self.value, self.content.items);
                }
            } else if (self.snipped) {
                if (self.content.items.len > 0) self.pending_tail = self.content.items;
            } else if (self.has_content) {
                try self.downstream.record(.thought, self.value, self.content.items);
            } else if (snipBoundary(self.value, self.limits)) |cut| {
                try self.emitPrefix(self.value[0..cut]);
                if (cut < self.value.len) self.pending_tail = self.value[cut..];
            } else {
                try self.downstream.begin(.thought, self.value);
                try self.downstream.end();
            }
            self.active = false;
            self.candidate = false;
            self.has_content = false;
            self.snipped = false;
            self.content = .empty;
        } else if (self.passing) {
            try self.downstream.end();
            self.passing = false;
        }
    }

    fn finish(self: *SnippingSink) !void {
        if (self.active or self.passing) try closeFn(self);
        try self.flushPendingTail();
    }

    fn flushPendingTail(self: *SnippingSink) !void {
        if (self.pending_tail) |tail| {
            try self.downstream.record(.thought, "snip", tail);
            self.pending_tail = null;
        }
    }

    fn emitCombinedSnip(self: *SnippingSink) !void {
        const tail = self.pending_tail orelse return error.MissingSnipTail;
        var combined: std.ArrayList(u8) = .empty;
        try combined.appendSlice(self.arena, tail);
        if (tail.len > 0 and tail[tail.len - 1] != '\n') try combined.append(self.arena, '\n');
        try combined.appendSlice(self.arena, self.content.items);
        try self.downstream.record(.thought, "snip", combined.items);
        self.pending_tail = null;
    }

    fn emitPrefix(self: *SnippingSink, prefix: []const u8) !void {
        if (std.mem.indexOfScalar(u8, prefix, '\n') == null) {
            // A one-line visible thought is the compact value form.
            try self.downstream.begin(.thought, prefix);
            try self.downstream.end();
        } else {
            try self.downstream.record(.thought, self.value, prefix);
        }
    }
};

fn containsSignature(arena: std.mem.Allocator, content: []const u8) !bool {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| if (try codec.signatureOn(arena, line)) |_| return true;
    return false;
}

/// Character counting follows UTF-8 character boundaries; line limits keep the
/// separating newline with the snipped continuation.
fn snipBoundary(text: []const u8, limits: SnipLimits) ?usize {
    var at: usize = 0;
    var chars: usize = 0;
    var lines: usize = 1;
    while (at < text.len) {
        const first = text[at];
        const width: usize = if (first < 0x80) 1 else if (first & 0xe0 == 0xc0) 2 else if (first & 0xf0 == 0xe0) 3 else if (first & 0xf8 == 0xf0) 4 else 1;
        if (at + width > text.len) return null; // wait for the rest of this UTF-8 character
        const end = at + width;
        at = end;
        chars += 1;
        if (text[end - 1] == '\n') lines += 1;
        if (limits.chars) |limit| if (chars >= limit) return at;
        if (limits.lines) |limit| if (lines > limit) {
            // Keep the separator with the continuation chunk. Its marker tells
            // the encoder not to synthesize another one between the records.
            return if (at >= 2 and text[at - 2] == '\r') at - 2 else at - 1;
        };
    }
    return null;
}

fn cutAtLimit(text: []const u8, limits: SnipLimits) usize {
    return snipBoundary(text, limits) orelse text.len;
}

/// Opens the 🤖 on the first byte. A reply that only calls a tool says
/// nothing, and an empty record would be a record of nothing.
const Live = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    opened: bool = false,
    body: ?doc.ContentWriter = null,
    pending: ?sigil.Sigil = null,
    value: []const u8 = "",

    fn sink(self: *Live) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    /// Remembered rather than written: the header waits for a byte or a
    /// value, so a record the model opened and left empty never reaches the
    /// pipe.
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        self.pending = s;
        self.value = value;
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        // Kept aside is kept out of sight on a terminal. A pipe carries all
        // of it, because whatever is next may be keeping the turn.
        if (self.mode == .m8 and self.pending == .thought and std.mem.eql(u8, self.value, "snip")) return;
        if (self.body == null) {
            if (self.opened) try self.out.writeByte('\n');
            self.body = try doc.ContentWriter.begin(
                self.out,
                self.mode,
                self.pending orelse .bot,
                self.value,
            );
            self.opened = true;
        }
        try self.body.?.write(bytes);
        try self.out.flush();
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        if (self.body) |*b| {
            try b.finish();
        } else if (self.value.len > 0) {
            // Said on the header alone — how a reply stopped short.
            if (self.opened) try self.out.writeByte('\n');
            self.opened = true;
            try doc.write(self.out, self.mode, .{ .sigil = self.pending orelse .bot, .value = self.value });
            try self.out.flush();
        }
        self.body = null;
        self.pending = null;
        self.value = "";
    }

    fn finish(self: *Live) !void {
        if (self.body) |*b| try b.finish();
    }
};

test "snip limits choose the first boundary and preserve UTF-8 characters" {
    const limits = SnipLimits{ .chars = 3, .lines = 2 };
    try std.testing.expectEqual(@as(usize, 3), cutAtLimit("abc\ndef", limits));
    try std.testing.expectEqual(@as(usize, 3), cutAtLimit("abc\ndef", .{ .chars = 10, .lines = 1 }));
    try std.testing.expectEqual(@as(usize, 5), cutAtLimit("ab\ncd\nef", .{ .lines = 2 }));
    try std.testing.expectEqual(@as(usize, 6), cutAtLimit("é🙂z", .{ .chars = 2 }));
    try std.testing.expectEqual(@as(usize, 3), cutAtLimit("abc", .{ .chars = 3 }));
}

test "snipping streams the prefix at its limit and buffers only the remainder" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var live: Live = .{ .out = &out.writer, .mode = .md };
    var snipping: SnippingSink = .{
        .arena = arena.allocator(),
        .downstream = live.sink(),
        .limits = .{ .chars = 3 },
    };
    const sink = snipping.sink();
    try sink.begin(.thought, "");
    try sink.text("abc");
    try std.testing.expectEqualStrings("* :thought_balloon::abc\n", out.written());
    try sink.text("def");
    try std.testing.expectEqualStrings("* :thought_balloon::abc\n", out.written());
    try sink.end();
    try snipping.finish();
    try std.testing.expectEqualStrings(
        "* :thought_balloon::abc\n\n* :thought_balloon::snip\n  > def\n",
        out.written(),
    );
}
test "parse snips the thought remainder under the exact snip marker" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed("* :thought_balloon::\n  > abcdef\n");
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{ "m8", "--snip-chars", "3" }, &input)));
    try std.testing.expectEqualStrings(
        "* :thought_balloon::abc\n\n* :thought_balloon::snip\n  > def\n",
        invocation.out.written(),
    );
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(invocation.arena.allocator(), invocation.out.written(), &diag);
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expectEqualStrings("abc", codec.thoughtText(records[0]));
    try std.testing.expectEqualStrings("def", codec.thoughtText(records[1]));
    try std.testing.expectEqualStrings("abcdef", try std.mem.concat(
        invocation.arena.allocator(),
        u8,
        &.{ codec.thoughtText(records[0]), codec.thoughtText(records[1]) },
    ));
}
test "snip continuation recombines exactly before the Anthropic signature" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed(
        "* :thought_balloon::\n  > abcdef\n\n* :thought_balloon::snip\n  > :lock_with_ink_pen:`sig`\n",
    );
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{ "m8", "--snip-chars", "3" }, &input)));
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(invocation.arena.allocator(), invocation.out.written(), &diag);
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expectEqualStrings("snip", records[1].value);
    try std.testing.expect(std.mem.indexOf(u8, records[1].content.?, "def\n:lock_with_ink_pen:`sig`") != null);
    const request = try codec.anthropic_messages.encode(invocation.arena.allocator(), records, .{ .model = "test" });
    try std.testing.expect(std.mem.indexOf(u8, request, "\"thinking\":\"abcdef\",\"signature\":\"sig\"") != null);
}
test "parse applies character snipping to compact one-line thoughts" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed("* :thought_balloon::abcdef\n");
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{ "m8", "--snip-chars", "3" }, &input)));
    try std.testing.expectEqualStrings(
        "* :thought_balloon::abc\n\n* :thought_balloon::snip\n  > def\n",
        invocation.out.written(),
    );
}
test "parse runs from its context reader and keeps output channels separate" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed("* :robot::\n  > answer\n");
    var ctx = invocation.ctx(&.{"m8"}, &input);
    ctx.verbosity = 1;
    try std.testing.expectEqual(@as(u8, 0), try command.run(ctx));
    try std.testing.expectEqualStrings("* :robot::\n  > answer\n", invocation.out.written());
    try std.testing.expectEqualStrings("", invocation.err.written());
}

test "parse rejects missing and unknown formats without consuming input" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    const cases = [_]struct { args: []const []const u8, diagnostic: []const u8 }{
        .{ .args = &.{}, .diagnostic = "m8 parse: name a format\n" },
        .{ .args = &.{"not-a-format"}, .diagnostic = "m8 parse: no format named 'not-a-format'\n" },
    };
    for (cases) |case| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed("unconsumed");
        try std.testing.expectEqual(@as(u8, 1), try command.run(invocation.ctx(case.args, &input)));
        try std.testing.expectEqualStrings("unconsumed", input.buffered());
        try std.testing.expectEqualStrings("", invocation.out.written());
        try std.testing.expect(std.mem.startsWith(u8, invocation.err.written(), case.diagnostic));
    }
}

test "parse with no context input sees EOF rather than process stdin" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{"m8"}, null)));
    try std.testing.expectEqualStrings("", invocation.out.written());
    try std.testing.expectEqualStrings("", invocation.err.written());
}

test "parse provider SSE and whole JSON produce the same ledger through EOF" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    const streamed =
        \\data: {"choices":[{"delta":{"content":"Hello"}}]}
        \\
        \\data: {"choices":[{"delta":{"content":" world"}}]}
        \\
        \\data: [DONE]
    ;
    const whole =
        \\{"choices":[{"message":{"content":"Hello world"}}]}
    ;
    for ([_][]const u8{ streamed, whole }) |body| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed(body);
        try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{"openai-completions"}, &input)));
        try std.testing.expectEqualStrings("* :robot::\n  > Hello world\n", invocation.out.written());
        try std.testing.expectEqualStrings("", invocation.err.written());
    }
}

test "parse streamed tool arguments become one call without an empty assistant record" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed(
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"say"}}]}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"text\":"}}]}}]}
        \\
        \\data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"hi\"}"}}]}}]}
        \\
        \\data: [DONE]
    );
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{"openai-completions"}, &input)));
    try std.testing.expectEqualStrings("* :calling::say,c1\n  > * text `\"hi\"`\n", invocation.out.written());
    try std.testing.expectEqualStrings("", invocation.err.written());
}

test "parse preserves non-object tool arguments after assistant text" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed(
        \\{"choices":[{"message":{"content":"Calling now","tool_calls":[{"id":"c2","function":{"name":"say","arguments":"not JSON"}}]}}]}
    );
    try std.testing.expectEqual(@as(u8, 0), try command.run(invocation.ctx(&.{"openai-completions"}, &input)));
    try std.testing.expectEqualStrings("* :robot::\n  > Calling now\n\n* :calling::say,c2\n  > not JSON\n", invocation.out.written());
    try std.testing.expectEqualStrings("", invocation.err.written());
}

test "parse provider usage metadata stays off ledger and stderr even with verbosity" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    // Codecs currently return no built-in stats aside. This exercises real
    // provider metadata, not a synthetic Reply.aside that no codec produces.
    for ([_]u8{ 0, 1 }) |verbosity_level| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed(
            \\{"choices":[{"message":{"content":"Answer"}}],"usage":{"prompt_tokens":12,"completion_tokens":3,"total_tokens":15}}
        );
        var ctx = invocation.ctx(&.{"openai-completions"}, &input);
        ctx.verbosity = verbosity_level;
        try std.testing.expectEqual(@as(u8, 0), try command.run(ctx));
        try std.testing.expectEqualStrings("* :robot::\n  > Answer\n", invocation.out.written());
        try std.testing.expectEqualStrings("", invocation.err.written());
    }
}

test "malformed provider JSON propagates InvalidResponseJson without raw capture" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    for ([_][]const u8{ "openai-responses", "openai-completions", "anthropic-messages" }) |format| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed("{\"output\":broken JSON}\n");
        try std.testing.expectError(
            error.InvalidResponseJson,
            command.run(invocation.ctx(&.{format}, &input)),
        );
        try std.testing.expectEqualStrings("", invocation.out.written());
        try std.testing.expectEqualStrings("", invocation.err.written());
    }
}

test "non-object responses propagate InvalidResponseObject" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    for ([_][]const u8{ "openai-responses", "anthropic-messages" }) |format| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed("[]\n");
        try std.testing.expectError(
            error.InvalidResponseObject,
            command.run(invocation.ctx(&.{format}, &input)),
        );
        try std.testing.expectEqualStrings("", invocation.err.written());
    }
}

test "openai-responses incomplete propagates after partial text and reason, before calls" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    const whole =
        \\{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[
        \\{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial"}]},
        \\{"type":"function_call","id":"fc1","call_id":"c1","name":"say","arguments":"{\"text\":\"hi\"}"}]}
    ;
    const incomplete_stream =
        \\event: response.output_item.added
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","role":"assistant","content":[]}}
        \\
        \\event: response.output_text.delta
        \\data: {"type":"response.output_text.delta","output_index":0,"delta":"Partial"}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Partial"}]}}
        \\
        \\event: response.output_item.done
        \\data: {"type":"response.output_item.done","output_index":2,"item":{"type":"function_call","id":"fc1","call_id":"c1","name":"say","arguments":"{\"text\":\"hi\"}"}}
        \\
        \\event: response.incomplete
        \\data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}
        \\
    ;
    const completed_incomplete_stream = try std.mem.replaceOwned(u8, std.testing.allocator, incomplete_stream, "response.incomplete", "response.completed");
    defer std.testing.allocator.free(completed_incomplete_stream);
    const expected = "* :robot::\n  > Partial\n\n* :robot::(cut off at max_output_tokens)\n";

    for ([_][]const u8{ whole, incomplete_stream, completed_incomplete_stream }) |body| {
        var invocation = try Invocation.init();
        defer invocation.deinit();
        var input: std.Io.Reader = .fixed(body);
        try std.testing.expectError(
            error.IncompleteResponse,
            command.run(invocation.ctx(&.{"openai-responses"}, &input)),
        );
        try std.testing.expectEqualStrings(expected, invocation.out.written());
        try std.testing.expectEqualStrings("", invocation.err.written());
    }
}

test "openai-responses stream ID mismatch propagates OutputItemIdMismatch" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    var input: std.Io.Reader = .fixed(
        \\data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"m0"}}
        \\data: {"type":"response.output_text.delta","output_index":0,"item_id":"wrong","delta":"bad"}
        \\
    );
    try std.testing.expectError(
        error.OutputItemIdMismatch,
        command.run(invocation.ctx(&.{"openai-responses"}, &input)),
    );
    try std.testing.expectEqualStrings("", invocation.err.written());
}
