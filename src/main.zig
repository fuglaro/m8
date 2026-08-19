//! m8 — a composable shell harness.
//!
//!     m8 >tool [args]     run a tool as a filter over an m8 stream
//!     m8 @agent "text"    address an agent (not wired up yet)
//!
//! Everything the process does hangs off one arena. A run is short: read a
//! document, transform it, write it, exit. Nothing outlives that, so nothing
//! needs freeing individually.

const std = @import("std");
const tool = @import("tool.zig");
const config = @import("config.zig");
const agent = @import("agent.zig");
const provider = @import("provider.zig");
const doc = @import("m8/doc.zig");

comptime {
    _ = @import("m8/sigil.zig");
    _ = @import("m8/doc.zig");
}

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;

    const argv = try init.minimal.args.toSlice(arena);
    const args = argv[@min(1, argv.len)..];

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    var err_buf: [4 * 1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &err_buf);

    if (args.len == 0) {
        try usage(&stderr.interface);
        return 1;
    }

    const verb = args[0];
    if (std.mem.startsWith(u8, verb, ">")) {
        const name = verb[1..];
        const t = tool.find(name) orelse {
            try stderr.interface.print("m8: no tool named '{s}'\n", .{name});
            try usage(&stderr.interface);
            return 1;
        };

        var in_buf: [64 * 1024]u8 = undefined;
        const input = try readDocument(io, arena, &in_buf);

        var tty_storage: TtyFiles = undefined;
        const tty = openTty(io, &tty_storage);

        t.run(.{
            .arena = arena,
            .io = io,
            .args = @ptrCast(args[1..]),
            .in = input,
            .out = &stdout.interface,
            .tty = tty,
        }) catch |e| {
            try stdout.interface.flush();
            try stderr.interface.print("m8 >{s}: {s}\n", .{ name, @errorName(e) });
            try stderr.interface.flush();
            return 1;
        };

        try stdout.interface.flush();
        if (tty) |t2| try t2.w.flush();
        return 0;
    }

    if (std.mem.startsWith(u8, verb, "@")) {
        runAgent(init, io, arena, verb[1..], args[1..], &stdout.interface) catch |e| {
            try stdout.interface.flush();
            try stderr.interface.print("m8 @{s}: {s}\n", .{ verb[1..], @errorName(e) });
            try stderr.interface.flush();
            return 1;
        };
        try stdout.interface.flush();
        return 0;
    }

    try stderr.interface.print("m8: '{s}' is not a tool or an agent\n", .{verb});
    try usage(&stderr.interface);
    return 1;
}

/// Address an agent.
///
/// The chain on stdin is the conversation so far; it may be empty. The new
/// turn is appended, answered, and the whole chain written out, so a session
/// is a file that grows and forking one is copying it.
fn runAgent(
    init: std.process.Init,
    io: std.Io,
    arena: std.mem.Allocator,
    name: []const u8,
    args: []const [:0]const u8,
    out: *std.Io.Writer,
) !void {
    const dirs = try config.discover(arena, io, init.environ_map);
    const def = try agent.load(arena, io, dirs, name, 0);
    const providers = try config.providers(arena, io, dirs);
    const p = try provider.find(providers, def.provider);

    var in_buf: [64 * 1024]u8 = undefined;
    const piped = try readDocument(io, arena, &in_buf);

    var diag: doc.Diagnostic = .{};
    const prior = try doc.parse(arena, piped, &diag);

    var chain: std.ArrayList(doc.Record) = .empty;
    if (prior.len == 0) {
        try chain.append(arena, .{ .sigil = .address, .fields = &.{def.name} });
    } else {
        try chain.appendSlice(arena, prior);
    }
    if (args.len > 0) {
        const text = try std.mem.join(arena, " ", @as([]const []const u8, @ptrCast(args)));
        try chain.append(arena, .{ .sigil = .user, .fields = &.{text} });
    }

    // The definition supplies the system prompt; the chain supplies the turns.
    var messages: std.ArrayList(provider.Message) = .empty;
    if (def.system.len > 0)
        try messages.append(arena, .{ .role = "system", .content = def.system });
    for (chain.items) |r| switch (r.sigil) {
        .user => try messages.append(arena, .{ .role = "user", .content = r.body() }),
        .assistant => try messages.append(arena, .{ .role = "assistant", .content = r.body() }),
        else => {},
    };

    // The turns so far land immediately; only the reply has to be waited for.
    try doc.writeAll(out, chain.items);
    try out.flush();

    var body = try doc.BodyWriter.begin(out, .assistant, &.{});
    var live: LiveReply = .{ .body = &body, .out = out };
    try provider.completeStreaming(arena, io, p, def.model, messages.items, live.sink());
    try body.finish();
    try out.flush();
}

/// Bridges the provider's byte stream into the document, flushing each
/// fragment so the text appears as it is generated rather than at the end.
const LiveReply = struct {
    body: *doc.BodyWriter,
    out: *std.Io.Writer,

    fn sink(self: *LiveReply) provider.Sink {
        return .{ .ctx = self, .write = writeFn };
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        try self.body.write(bytes);
        try self.out.flush();
    }
};

/// Read the incoming document.
///
/// A terminal on stdin means there is no incoming document — nobody pipes a
/// conversation in by hand — so it reads as empty. Waiting for an EOF the
/// terminal will never send just hangs.
fn readDocument(io: std.Io, arena: std.mem.Allocator, buf: []u8) ![]const u8 {
    const in = std.Io.File.stdin();
    if (try in.isTty(io)) return "";
    var r = in.readerStreaming(io, buf);
    return r.interface.allocRemaining(arena, .unlimited);
}

const TtyFiles = struct {
    file: std.Io.File,
    r: std.Io.File.Reader,
    w: std.Io.File.Writer,
    r_buf: [4096]u8,
    w_buf: [4096]u8,
};

/// Open the terminal as its own channel. Absent under a pipe, which tools
/// read as "run non-interactively" rather than as a failure.
fn openTty(io: std.Io, storage: *TtyFiles) ?tool.Tty {
    const f = std.Io.Dir.openFileAbsolute(io, "/dev/tty", .{ .mode = .read_write }) catch return null;
    storage.file = f;
    storage.r = f.readerStreaming(io, &storage.r_buf);
    storage.w = f.writerStreaming(io, &storage.w_buf);
    return .{ .r = &storage.r.interface, .w = &storage.w.interface };
}

fn usage(w: *std.Io.Writer) !void {
    try w.writeAll("m8 — a composable shell harness\n\nusage:\n  m8 @AGENT [text]  address an agent, appending to the chain on stdin\n  m8 >TOOL [args]   run a tool over an m8 stream on stdin\n\ntools:\n");
    for (tool.all) |t| try w.print("  >{s: <6} {s}\n", .{ t.name, t.summary });
    try w.flush();
}
