//! `watch` — a chat, written out as it moves.
//!
//! A chat is one 🧠 in a file that is replaced whenever the chat moves, and
//! the turns it names are never rewritten. So there is nothing to tail: the
//! pointer is read again, and when it names something new the ledger is
//! walked back from there to the last thing shown. Every turn was whole
//! before the pointer named it, so nothing half written is ever read.
//!
//! The walk also stops at the chat's agent. A chat that was reset leads back
//! to that without meeting what was last shown, so it starts over under its
//! agent's 🧠 and nothing has to notice that it was reset.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const highlight = @import("../m8/highlight.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const session = @import("../session.zig");
const ledger = @import("../ledger.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "watch",
    .summary = "write a chat out as it moves",
    .takes = .nothing,
    // It is for a person looking on, so a terminal is shown what `m8 @` shows.
    .terminal = true,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 watch [--unsnip] :MOB/AGENT//CHAT
        \\
        \\Writes what the chat holds, and then whatever is added to it, until
        \\it is interrupted. It is how to look on at a chat something else is
        \\running, such as one an agent hands its work to.
        \\
        \\  m8 watch :crew/cody//delegated
        \\
        \\Each piece opens with the 🧠 it continues: the turn before it, or
        \\the agent when the chat starts afresh. A chat that is reset starts
        \\over from its agent.
        \\
        \\What arrives is a turn at a time, since a turn is what is kept: a
        \\reply once it is whole, and a call once it is answered.
        \\
        \\`--unsnip` expands snipped content instead of leaving its 🧠 standing.
        \\
        \\Only the chat's own pointer is read. One with none is waited on,
        \\rather than shown as the chat above it.
        \\
        \\New ::stats:: lines from its sibling +.log go unchanged to stderr.
        \\Old stats are not replayed. The log is advisory; the pointer remains
        \\authoritative, and both are polled.
        \\
    );
}

/// How long between looks at the pointer.
const pause: std.Io.Duration = .fromMilliseconds(150);

fn run(ctx: Ctx) !u8 {
    var args = ctx.args;
    const unsnip = args.len > 0 and std.mem.eql(u8, args[0], "--unsnip");
    if (unsnip) args = args[1..];
    if (args.len != 1 or !address.isAddress(args[0])) {
        try ctx.err.writeAll("m8 watch: name one :MOB/AGENT//CHAT\n");
        return 1;
    }
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    const a = try address.typed(ctx.arena, ctx.io, dirs, args[0], ctx.err);
    if (a.kind != .chat or a.suffix != .none) {
        try ctx.err.writeAll("m8 watch: only a chat moves, and it is named without `:` or `-`\n");
        return 1;
    }
    const agent = try address.agentOf(ctx.arena, ctx.io, dirs, a.name);
    const ptr = try session.pointerOf(ctx.arena, a.name);
    const log_path = try session.logPath(ctx.arena, ctx.io, dirs, a.name);
    // Start at EOF: this watcher reports new advisory stats, not old history.
    var log_offset: u64 = if (std.Io.Dir.cwd().statFile(ctx.io, log_path, .{})) |st| st.size else |_| 0;

    // What was last shown outlives the look that showed it.
    var shown_buf: [std.fs.max_path_bytes]u8 = undefined;
    var shown: []const u8 = agent;
    const look: doc.Look = .{
        .width = highlight.terminalWidth(ctx.env),
        .palette = if (ctx.mode == .m8) try config.highlights(ctx.arena, ctx.io, ctx.env) else .{},
    };
    var scratch: std.heap.ArenaAllocator = .init(ctx.arena);
    while (true) : (try ctx.io.sleep(pause, .awake)) {
        _ = scratch.reset(.retain_capacity);
        const arena = scratch.allocator();

        pollLog(ctx.io, log_path, &log_offset, ctx.err) catch {};

        const named = (try session.deref(arena, ctx.io, dirs, ptr)) orelse agent;
        const head = try session.settle(arena, ctx.io, dirs, named);
        if (std.mem.eql(u8, head, shown)) continue;

        // Back at the agent there is nothing said yet, and the 🧠 that says
        // so opens whatever is said next.
        if (!std.mem.eql(u8, head, agent)) {
            const new = try ledger.expandUntil(
                arena,
                ctx.io,
                dirs,
                &.{.{ .sigil = .agent, .value = head }},
                .md,
                .{ .names = &.{ shown, agent }, .snips = !unsnip },
            );
            try ledger.writeAll(ctx.out, arena, ctx.mode, look, new.records);
            try ctx.out.writeByte('\n');
            try ctx.out.flush();
        }
        shown = shown_buf[0..head.len];
        @memcpy(shown_buf[0..head.len], head);
    }
}

// Advisory only: complete lines are forwarded; partial lines wait for next poll.
fn pollLog(io: std.Io, path: []const u8, offset: *u64, err: *std.Io.Writer) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return;
    defer file.close(io);
    if (try file.length(io) < offset.*) offset.* = 0;
    var buf: [64 * 1024]u8 = undefined;
    const n = try file.readPositionalAll(io, &buf, offset.*);
    const last = std.mem.lastIndexOfScalar(u8, buf[0..n], '\n') orelse {
        if (n == buf.len) offset.* += n; // Discard an oversized malformed record.
        return;
    };
    var lines = std.mem.splitScalar(u8, buf[0 .. last + 1], '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "::stats::")) {
        try err.writeAll(line);
        try err.writeByte('\n');
    };
    offset.* += last + 1;
    try err.flush();
}

test "watch log follows complete stats only and recovers from truncation" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const dir = try @import("../test_tmp.zig").make(arena, io, "m8-watch-log");
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};
    const path = try std.fs.path.join(arena, &.{ dir, "+.log" });
    var out: std.Io.Writer.Allocating = .init(arena);
    var offset: u64 = 0;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "noise\n::stats::partial" });
    try pollLog(io, path, &offset, &out.writer);
    try std.testing.expectEqualStrings("", out.written());
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "noise\n::stats::partial complete\nnoise\n::stats::next\n" });
    try pollLog(io, path, &offset, &out.writer);
    try pollLog(io, path, &offset, &out.writer);
    try std.testing.expectEqualStrings("::stats::partial complete\n::stats::next\n", out.written());
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "::stats::reset\n" });
    try pollLog(io, path, &offset, &out.writer);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), "::stats::reset\n"));
}
