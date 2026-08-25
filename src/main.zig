//! m8 — a composable shell harness.
//!
//!     m8 [@AGENT|+CHAT] [-- PROMPT]
//!     m8 COMMAND [args]
//!
//! `@` is how the command line names an agent; it is not part of the language.
//! Every turn is saved as a new agent in `=` and its name printed,
//! so a saved turn is addressed by name exactly like any other agent.
//!
//! A terminal is written the rendered spelling and everything else markdown,
//! decided once here and carried into every writer.
//!
//! Everything the process does hangs off one arena. A run is short: read a
//! document, transform it, write it, exit. Nothing outlives that, so nothing
//! needs freeing individually.

const std = @import("std");
const command = @import("command.zig");
const config = @import("config.zig");
const agent = @import("agent.zig");
const provider = @import("provider.zig");
const session = @import("session.zig");
const doc = @import("m8/doc.zig");

comptime {
    _ = @import("m8/sigil.zig");
    _ = @import("m8/doc.zig");
    _ = @import("session.zig");
    _ = @import("sandbox.zig");
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

    //     m8 [@AGENT|+CHAT] [-- PROMPT]
    //     m8 COMMAND [args]
    //
    // The first word names an agent, a chat, or a command, and a prompt only
    // ever follows `--`. Nothing is guessed, so a prompt may say whatever it
    // likes — including a word that happens to be a command's name.
    var rest = args;
    var name: []const u8 = session.latest;

    if (rest.len > 0 and !std.mem.eql(u8, rest[0], "--")) {
        const word = rest[0];
        rest = rest[1..];

        if (std.mem.startsWith(u8, word, "@")) {
            name = word[1..];
        } else if (std.mem.startsWith(u8, word, session.alias)) {
            name = try std.fmt.allocPrint(arena, "{s}/{s}", .{ session.alias, word[session.alias.len..] });
        } else if (command.find(word)) |c| {
            return runCommand(init, io, arena, c, rest, &stdout.interface, &stderr.interface);
        } else {
            try stderr.interface.print("m8: '{s}' is not an agent, a chat, or a command\n", .{word});
            try usage(&stderr.interface);
            return 1;
        }
    }

    if (rest.len > 0) {
        if (!std.mem.eql(u8, rest[0], "--")) {
            try stderr.interface.print("m8: put -- before what you want to say\n", .{});
            try usage(&stderr.interface);
            return 1;
        }
        rest = rest[1..];
    }
    const text = rest;

    runAgent(init, io, arena, name, text, &stdout.interface) catch |e| {
        try stdout.interface.flush();
        switch (e) {
            error.NothingToSay => try usage(&stderr.interface),
            error.UnknownAgent => try stderr.interface.print(
                "m8: no agent named '{s}'\n",
                .{name},
            ),
            else => try stderr.interface.print("m8 {s}: {s}\n", .{ name, @errorName(e) }),
        }
        try stderr.interface.flush();
        return 1;
    };
    try stdout.interface.flush();
    return 0;
}

/// Address an agent.
///
/// Everything behind the name — its model, its system prompt, and any turns it
/// carries — comes from resolving 🧠 recursively, so continuing a conversation
/// and invoking an agent are one code path. The turn is saved as a new agent in
/// `=` and its name printed, which is what the person types back.
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
    const piped = try command.api.readDocument(io, arena, &in_buf);

    // A document on stdin is context to splice in; anything else is what the
    // person wants to say.
    var spliced: []const doc.Record = &.{};
    var typed: []const u8 = "";
    if (piped.len > 0) {
        if (doc.detect(piped) != null) {
            var diag: doc.Diagnostic = .{};
            spliced = try doc.parse(arena, piped, &diag);
        } else {
            typed = std.mem.trim(u8, piped, " \t\r\n");
        }
    }
    if (args.len > 0) {
        typed = try std.mem.join(arena, " ", @as([]const []const u8, @ptrCast(args)));
    }

    if (typed.len == 0 and spliced.len == 0) return error.NothingToSay;

    var messages: std.ArrayList(provider.Message) = .empty;
    if (def.system.len > 0)
        try messages.append(arena, .{ .role = "system", .content = def.system });
    for (def.turns) |r| try appendTurn(arena, &messages, r);
    for (spliced) |r| try appendTurn(arena, &messages, r);
    if (typed.len > 0)
        try messages.append(arena, .{ .role = "user", .content = typed });

    // The name has to exist before the turn, because the turn records it.
    const saved_as = try session.newName(arena, io);

    // A terminal gets the rendered spelling, and is also the only reader that
    // can see progress — down a pipe, flushing per token buys nothing and
    // costs a syscall each time.
    const tty = std.Io.File.stdout().isTty(io) catch false;
    const mode: doc.Mode = if (tty) .m8 else .md;

    var body = try doc.ContentWriter.begin(out, mode, .bot, "");
    var live: LiveReply = .{
        .body = &body,
        .out = out,
        .text = .empty,
        .arena = arena,
        .live = tty,
    };
    try provider.completeStreaming(arena, io, p, def.model, messages.items, live.sink());
    try body.finish();
    try out.writeByte('\n');
    try doc.write(out, mode, .{ .sigil = .agent, .value = saved_as });
    try out.flush();

    // Lineage names the turn continued, never an alias to it: aliases move,
    // and a turn that named one would become its own ancestor.
    const parent = (try session.deref(arena, io, dirs, name)) orelse name;

    var turn: std.ArrayList(doc.Record) = .empty;
    try turn.append(arena, .{ .sigil = .agent, .value = parent });
    try turn.appendSlice(arena, spliced);
    if (typed.len > 0)
        try turn.append(arena, .{ .sigil = .user, .content = typed });
    try turn.append(arena, .{ .sigil = .bot, .content = live.text.items });
    try session.write(arena, io, dirs, saved_as, turn.items);
    try session.setAlias(arena, io, dirs, session.global, saved_as);
    if (def.origin.len > 0) try session.setAlias(arena, io, dirs, def.origin, saved_as);
}

fn appendTurn(
    arena: std.mem.Allocator,
    messages: *std.ArrayList(provider.Message),
    r: doc.Record,
) !void {
    switch (r.sigil) {
        .user => try messages.append(arena, .{ .role = "user", .content = r.content orelse "" }),
        .bot => try messages.append(arena, .{ .role = "assistant", .content = r.content orelse "" }),
        else => {},
    }
}

/// Bridges the provider's byte stream into the document, flushing each
/// fragment so the text appears as it is generated rather than at the end.
const LiveReply = struct {
    body: *doc.ContentWriter,
    out: *std.Io.Writer,
    /// Kept as well as streamed, because the saved turn needs the whole reply.
    text: std.ArrayList(u8),
    arena: std.mem.Allocator,
    live: bool,

    fn sink(self: *LiveReply) provider.Sink {
        return .{ .ctx = self, .write = writeFn };
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        try self.text.appendSlice(self.arena, bytes);
        try self.body.write(bytes);
        if (self.live) try self.out.flush();
    }
};

/// Read the incoming document.
///
/// A terminal on stdin means there is no incoming document — nobody pipes a
/// conversation in by hand — so it reads as empty. Waiting for an EOF the
/// terminal will never send just hangs.
/// Commands take their arguments verbatim; they parse their own.
fn runCommand(
    init: std.process.Init,
    io: std.Io,
    arena: std.mem.Allocator,
    c: command.Command,
    args: []const [:0]const u8,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
) !u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    const input = if (c.reads) try command.api.readDocument(io, arena, &in_buf) else "";

    var tty_storage: TtyFiles = undefined;
    const tty = openTty(io, &tty_storage);

    const status = c.run(.{
        .arena = arena,
        .io = io,
        .mode = if (std.Io.File.stdout().isTty(io) catch false) .m8 else .md,
        .env = init.environ_map,
        .args = @ptrCast(args),
        .in = input,
        .out = out,
        .err = err,
        .tty = tty,
    }) catch |e| {
        try out.flush();
        if (tty) |t2| try t2.w.flush();
        try err.print("m8 {s}: {s}\n", .{ c.name, @errorName(e) });
        try err.flush();
        return 1;
    };

    try out.flush();
    if (tty) |t2| try t2.w.flush();
    return status;
}

const TtyFiles = struct {
    file: std.Io.File,
    r: std.Io.File.Reader,
    w: std.Io.File.Writer,
    r_buf: [4096]u8,
    w_buf: [4096]u8,
};

/// Open the terminal as its own channel. Absent under a pipe, which commands
/// read as "run non-interactively" rather than as a failure.
fn openTty(io: std.Io, storage: *TtyFiles) ?command.Tty {
    const f = std.Io.Dir.openFileAbsolute(io, "/dev/tty", .{ .mode = .read_write }) catch return null;
    storage.file = f;
    storage.r = f.readerStreaming(io, &storage.r_buf);
    storage.w = f.writerStreaming(io, &storage.w_buf);
    return .{ .r = &storage.r.interface, .w = &storage.w.interface };
}

fn usage(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 — a composable shell harness
        \\
        \\  m8 [@AGENT|+CHAT] [-- PROMPT]
        \\  m8 COMMAND [args]
        \\
        \\@mathy starts a chat named +mathy. Carry it on with +mathy, or
        \\with a plain m8, which continues whichever chat came last.
        \\Talking to @mathy again starts that chat over.
        \\
        \\  m8 @mathy -- "Tell me about the Riemann Sphere."
        \\  m8 +mathy -- "Tell me more."
        \\  m8 -- "And in one sentence?"
        \\
        \\commands:
        \\
    );
    for (command.all) |c| try w.print("  {s: <6} {s}\n", .{ c.name, c.summary });
    try w.flush();
}
