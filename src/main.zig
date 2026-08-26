//! m8 — a composable shell harness.
//!
//!     m8 [-l LOCKS] [[@AGENT|+CHAT] MSG_CMD|RUN_CMD] [ARGS]
//!
//! `@` is how the command line names an agent; it is not part of the language.
//! Every turn is saved as a new agent in `=` and its name printed, so a saved
//! turn is addressed by name exactly like any other agent.
//!
//! The command line is a way of assembling a ledger and nothing more: a name,
//! whatever was piped in, and a prompt, in that order. A message command is
//! handed that ledger; a run command takes no name and is handed stdin, or
//! nothing at all.
//!
//! `--` is a message command, so there is no separator anywhere in this and
//! nothing has to decide whose arguments are whose. A bare `m8` runs it, which
//! is why consulting an agent and running a filter are one path.
//!
//! A name is appended as the 🧠 it is, not as what it expands to. Expanding
//! happens in whichever command needs it, which is what keeps a saved turn
//! naming its parent rather than copying it.
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
const assembly = @import("assembly.zig");
const ledger = @import("ledger.zig");
const session = @import("session.zig");
const sandbox = @import("sandbox.zig");
const doc = @import("m8/doc.zig");

comptime {
    _ = @import("m8/sigil.zig");
    _ = @import("m8/doc.zig");
    _ = @import("m8/model.zig");
    _ = @import("session.zig");
    _ = @import("sandbox.zig");
    _ = @import("toolbox.zig");
    _ = @import("provider.zig");
    _ = @import("agent.zig");
    _ = @import("ledger.zig");
    _ = @import("assembly.zig");
    _ = @import("codec.zig");
    _ = @import("config.zig");
    _ = @import("command.zig");
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
    const out = &stdout.interface;
    const err = &stderr.interface;

    var rest = args;

    // `-l` sits before the name because it covers the whole run, not one
    // command. It adds to whatever an agent already carries and can never
    // take away, since a lock only ever removes.
    //
    // One lock per flag, repeated — which is what a 🔒 array expands to
    // through `{{lock:-l}}`, and what any other argv would do. The comma list
    // belongs to the sigil value, where `,` is the field separator; argv has
    // its own idiom and this is it.
    var locks: std.ArrayList([]const u8) = .empty;
    while (rest.len >= 2 and (std.mem.eql(u8, rest[0], "-l") or std.mem.eql(u8, rest[0], "--lock"))) {
        const lock = rest[1];
        if (sandbox.find(lock) == null) {
            try err.print("m8: no lock named '{s}'\n", .{lock});
            if (std.mem.indexOfScalar(u8, lock, ',') != null)
                try err.writeAll("m8: one lock per -l, repeat the flag\n");
            try err.flush();
            return 1;
        }
        try locks.append(arena, lock);
        rest = rest[2..];
    }

    // A name, then a command, then that command's arguments. Nothing is
    // guessed: a name is written `@x` or `+x`, and everything after a command
    // belongs to it — including a prompt, since `--` is a command too.
    var name: []const u8 = "";
    var named = false;
    if (rest.len > 0) {
        const word = rest[0];
        if (std.mem.startsWith(u8, word, "@")) {
            name = word[1..];
            named = true;
            rest = rest[1..];
        } else if (std.mem.startsWith(u8, word, session.alias)) {
            name = try std.fmt.allocPrint(arena, "{s}/{s}", .{
                session.alias,
                word[session.alias.len..],
            });
            named = true;
            rest = rest[1..];
        }
    }

    // A name with nothing after it is still a consultation; so is a bare `m8`.
    var cmd = command.find(command.consult).?;
    var cmd_args: []const [:0]const u8 = &.{};
    if (rest.len > 0) {
        cmd = command.find(rest[0]) orelse {
            try err.print("m8: '{s}' is not an agent, a chat, or a command\n", .{rest[0]});
            try usage(err);
            return 1;
        };
        cmd_args = rest[1..];
    }

    // A run command takes no name, because there is no ledger for one to go
    // into. Saying so beats quietly dropping what was typed.
    if (named and !cmd.takes.isMessage()) {
        try err.print(
            "m8 {s}: takes stdin as it is, so there is nowhere to put a name\n",
            .{cmd.name},
        );
        try err.flush();
        return 1;
    }

    // One command's arguments are prose. It is read here rather than there
    // because a prompt goes into the ledger, and the ledger is assembled here.
    var prompt: []const u8 = "";
    if (cmd.prompts) {
        prompt = try std.mem.join(arena, " ", @as([]const []const u8, @ptrCast(cmd_args)));
        cmd_args = &.{};
    }

    const dirs = try config.discover(arena, io, init.environ_map);

    const assembled = gather(io, arena, dirs, name, named, prompt, cmd.takes) catch |e| {
        switch (e) {
            // Only the command line's own name reaches here; anything inside a
            // ledger is the command's business.
            error.UnknownAgent => try err.print(
                "m8: no agent named '{s}'\n",
                .{if (named) name else session.latest},
            ),
            else => try err.print("m8: {s}\n", .{@errorName(e)}),
        }
        try err.flush();
        return 1;
    };

    // Nothing piped and nothing said is somebody finding out what m8 is.
    if (cmd.prompts and assembled.said_nothing) {
        try usage(err);
        return 1;
    }

    return runCommand(init, io, arena, cmd, cmd_args, locks.items, assembled.document, out, err);
}

/// Read what this kind of command is handed.
fn gather(
    io: std.Io,
    arena: std.mem.Allocator,
    dirs: []const []const u8,
    name: []const u8,
    named: bool,
    prompt: []const u8,
    takes: command.Takes,
) !assembly.Assembled {
    var in_buf: [64 * 1024]u8 = undefined;
    return switch (takes) {
        // Stdin belongs to whatever the command hands it to.
        .nothing => .{},
        // Handed on untouched: it is not m8 yet.
        .stdin => .{
            .document = try command.api.readDocument(io, arena, &in_buf),
            .said_nothing = false,
        },
        .ledger => try assembly.assemble(
            arena,
            io,
            dirs,
            name,
            named,
            prompt,
            try command.api.readDocument(io, arena, &in_buf),
        ),
    };
}

/// Commands take their arguments verbatim; they parse their own.
fn runCommand(
    init: std.process.Init,
    io: std.Io,
    arena: std.mem.Allocator,
    c: command.Command,
    args: []const [:0]const u8,
    locks: []const []const u8,
    input: []const u8,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
) !u8 {
    var tty_storage: command.api.TtyFiles = undefined;
    const tty = command.api.openTty(io, &tty_storage);

    const status = c.run(.{
        .arena = arena,
        .io = io,
        .mode = if (std.Io.File.stdout().isTty(io) catch false) .m8 else .md,
        .env = init.environ_map,
        .locks = locks,
        .args = @ptrCast(args),
        .in = input,
        .out = out,
        .err = err,
        .tty = tty,
    }) catch |e| {
        try out.flush();
        if (tty) |t| try t.w.flush();
        switch (e) {
            error.UnknownAgent => try err.writeAll("m8: that ledger names an agent that is not there\n"),
            error.UnknownProvider => try err.writeAll("m8: no provider in providers.json by that name\n"),
            error.NoModel => try err.writeAll("m8: nothing in that ledger names a model\n"),
            error.NoProvider => try err.writeAll(
                "m8: that ledger names a model but not whose; say which, as `m8 send PROVIDER`\n",
            ),
            else => try err.print("m8 {s}: {s}\n", .{ c.name, @errorName(e) }),
        }
        try err.flush();
        return 1;
    };

    try out.flush();
    if (tty) |t| try t.w.flush();
    return status;
}

fn usage(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 — a composable shell harness
        \\
        \\  m8 [-l LOCKS] [[@AGENT|+CHAT] MSG_CMD|RUN_CMD] [ARGS]
        \\
        \\@mathy starts a chat named +mathy. Carry it on with +mathy, or
        \\with a plain m8, which continues whichever chat came last.
        \\Talking to @mathy again starts that chat over.
        \\
        \\  m8 @mathy -- "Tell me about the Riemann Sphere."
        \\  m8 +mathy -- "Tell me more."
        \\  m8 -- "And in one sentence?"
        \\
        \\A message command is handed a ledger assembled from the name, what
        \\was piped in, and the prompt. `--` is one of them, so everything
        \\after it is what you want to say. A run command takes no name and
        \\is handed stdin as it arrived.
        \\
        \\  m8 +mathy encode m8 >ledger.md
        \\  m8 encode openai-completions <ledger.md >request.json
        \\  m8 decode openai-completions <request.json | m8 send local
        \\
    );
    try list(w, "message commands", true);
    try list(w, "run commands", false);
    try w.writeAll("\nm8 call NAME reaches m8's own filters and its inbuilt tools.\n");
    try w.flush();
}

fn list(w: *std.Io.Writer, heading: []const u8, message: bool) !void {
    try w.print("\n{s}:\n\n", .{heading});
    for (command.all) |c| {
        if (c.takes.isMessage() != message) continue;
        try w.print("  {s: <7} {s}\n", .{ c.name, c.summary });
    }
}
