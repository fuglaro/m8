//! `parse` — an api's response, as the turn it holds.
//!
//! The third direction. `encode` and `decode` are about requests, which are
//! ledger-shaped; a response is turn-shaped, so it is not decoded into a
//! ledger but read into the records it adds to one.
//!
//! Reading is incremental whether or not the provider streamed. A provider
//! that wrote everything at once is a stream of one chunk, so parsing this
//! way is what lets streaming be something a provider MAY do rather than
//! MUST. It is defined inside m8 with a command over it: a custom api needs
//! no entry here, because a custom provider speaks whichever api it declares
//! and m8 only ever reads the ones it knows.

const std = @import("std");
const codec = @import("../codec.zig");
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const toolbox = @import("../toolbox.zig");
const api = @import("api.zig");
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
        \\m8 parse — read an api's response as the turn it holds
        \\
        \\  ... | m8 parse FORMAT
        \\
        \\The third direction. `encode` and `decode` are about requests, which
        \\are ledger-shaped; a response is turn-shaped, so it is not decoded
        \\into a ledger but read into the records it adds to one.
        \\
        \\  echo "Say hi." | m8 @mathy encode openai-completions \
        \\    | m8 providers url \
        \\    | m8 parse openai-completions
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

    var buf: [64 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &buf);

    // Written as it is read, so a streamed response reaches whatever is next
    // in the pipe while the model is still saying it.
    var live: Live = .{ .out = ctx.out, .mode = ctx.mode };
    const reply = try c.parse(ctx.arena, &in.interface, live.sink());
    try live.finish();

    for (reply.calls) |call| {
        if (live.opened) try ctx.out.writeByte('\n');
        live.opened = true;
        try doc.write(ctx.out, ctx.mode, .{
            .sigil = .call,
            .value = try std.fmt.allocPrint(ctx.arena, "{s},{s}", .{ call.name, call.id }),
            .content = try toolbox.renderArgs(ctx.arena, ctx.mode, call.arguments),
        });
    }
    return 0;
}

/// Opens the 🤖 on the first byte. A reply that only calls a tool says
/// nothing, and an empty record would be a record of nothing.
const Live = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    opened: bool = false,
    body: ?doc.ContentWriter = null,
    pending: ?sigil.Sigil = null,

    fn sink(self: *Live) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    /// Remembered rather than written: the header waits for a byte, so a
    /// record the model opened and left empty never reaches the pipe.
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, _: []const u8) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        self.pending = s;
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        if (self.body == null) {
            if (self.opened) try self.out.writeByte('\n');
            self.body = try doc.ContentWriter.begin(
                self.out,
                self.mode,
                self.pending orelse .bot,
                "",
            );
            self.opened = true;
        }
        try self.body.?.write(bytes);
        try self.out.flush();
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx));
        if (self.body) |*b| try b.finish();
        self.body = null;
        self.pending = null;
    }

    fn finish(self: *Live) !void {
        if (self.body) |*b| try b.finish();
    }
};
