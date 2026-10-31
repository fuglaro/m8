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
        \\  ... | m8 parse FORMAT
        \\
        \\The other direction. `encode` is about requests, which are
        \\ledger-shaped; a response is turn-shaped, so it is read into the
        \\records it adds to a ledger rather than into one.
        \\
        \\  m8 say --no-send :demo/mathy "Say hi." \
        \\    | m8 encode openai-responses \
        \\    | M8_PROVIDER_URL=http://127.0.0.1:8000/v1/responses m8 url-provider \
        \\    | m8 parse openai-responses
        \\
        \\Reading is incremental whether or not the provider streamed, so what
        \\it writes reaches the next command in the pipe while the model is
        \\still saying it. Where an api has both a streamed and a whole shape,
        \\the one that actually arrived is the one that is read.
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

    var empty: std.Io.Reader = .fixed(&.{});
    const input = ctx.stdin orelse &empty;

    // Written as it is read, so a streamed response reaches whatever is next
    // in the pipe while the model is still saying it.
    var live: Live = .{ .out = ctx.out, .mode = ctx.mode };
    const reply = try c.parse(ctx.arena, input, live.sink());
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
