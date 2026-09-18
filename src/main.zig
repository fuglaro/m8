//! m8 — a composable shell harness.
//!
//!     m8 [[@AGENT|+CHAT|^SKILL] MSG_CMD|RUN_CMD] [ARGS]
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
//! `--help` is read here rather than by whichever command was named, so no
//! command has to remember to answer it and no two answer it differently. It
//! names the `help` command, which is why `m8 send --help` and `m8 help send`
//! are one page. The exception is `--`, whose arguments are prose.
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
const provider = @import("provider.zig");
const session = @import("session.zig");
const doc = @import("m8/doc.zig");
const help = @import("command/help.zig");
const harness = @import("harness.zig");
const launch = @import("launch.zig");

comptime {
    _ = @import("m8/sigil.zig");
    _ = @import("m8/markdown.zig");
    _ = @import("m8/doc.zig");
    _ = @import("m8/model.zig");
    _ = @import("session.zig");
    _ = @import("sandbox.zig");
    _ = @import("toolbox.zig");
    _ = @import("shield.zig");
    _ = @import("provider.zig");
    _ = @import("agent.zig");
    _ = @import("ledger.zig");
    _ = @import("assembly.zig");
    _ = @import("codec.zig");
    _ = @import("config.zig");
    _ = @import("command.zig");
    _ = @import("launch.zig");
    _ = @import("zmachine/zmachine.zig");
}

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;

    const argv = try init.minimal.args.toSlice(arena);
    const args = argv[@min(1, argv.len)..];

    // Where this m8 is, so a provider naming `m8` reaches this build rather
    // than whichever one is on a PATH, or none at all.
    const self = try provider.selfPath(
        arena,
        io,
        init.environ_map,
        if (argv.len > 0) argv[0] else "m8",
    );

    // The single binary installed under one of the command names *is* that
    // command, the way a symlinked busybox is. Answering the same as the
    // program of that name is what keeps one installation from behaving
    // unlike the other. The lean launcher is only ever `m8`, and asking would
    // cost it the registry it is built without.
    if (!launch.split) {
        if (command.byProgram(std.fs.path.basename(self))) |node|
            return harness.leaf(
                init,
                command.at(node.path).?,
                try command.named(arena, node.path, @ptrCast(args)),
            );
    }

    // Streaming, so writing is `write` from wherever the descriptor already
    // is rather than a position this process is keeping. A run inherits a
    // redirect that others are writing to as well — `m8 ... >>log.md` twice,
    // or two runs in one `{ }` — and a position of its own would start each
    // of them at nought and overwrite what the last one said.
    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    var err_buf: [4 * 1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(io, &err_buf);
    const out = &stdout.interface;
    const err = &stderr.interface;

    var rest = args;

    // A name, then a command, then that command's arguments. Nothing is
    // guessed: a name is written `@x` or `+x`, and everything after a command
    // belongs to it — including a prompt, since `--` is a command too.
    var name: []const u8 = "";
    var named = false;
    // Which half of what it names. `@` and `+` want what a file says; `^`
    // wants what it says about itself, which is the same distinction 🧠 and
    // 📚 carry in the language. The mark is the whole of it — nothing is
    // looked up to decide.
    var as: doc.Sigil = .agent;
    if (rest.len > 0) {
        const word = rest[0];
        if (std.mem.startsWith(u8, word, "@")) {
            name = word[1..];
            named = true;
            rest = rest[1..];
        } else if (std.mem.startsWith(u8, word, "^")) {
            name = word[1..];
            named = true;
            as = .skill;
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
    //
    // What is read here is the *spec* of what was named — what it takes, and
    // whether its arguments are prose. Nothing here needs the command itself,
    // which is what lets the lean launcher assemble for a command it does not
    // hold.
    const helper = command.byPath(&.{help.name}).?;
    var cmd = command.byPath(&.{command.consult}).?;
    var cmd_args: []const []const u8 = &.{};
    var asked_for_help = false;
    if (rest.len > 0) {
        // `m8 --help [COMMAND]` is `m8 help [COMMAND]`. The flag is a way of
        // naming the command rather than a command's own argument.
        if (command.api.wantsHelp(@ptrCast(rest))) {
            cmd = helper;
            cmd_args = @ptrCast(rest[1..]);
            asked_for_help = true;
        } else {
            cmd = command.byPath(&.{rest[0]}) orelse {
                try err.print("m8: '{s}' is not an agent, a chat, or a command\n", .{rest[0]});
                try help.overview(err);
                try err.flush();
                return 1;
            };
            cmd_args = @ptrCast(rest[1..]);
        }
    }

    // A run command takes no name, because there is no ledger for one to go
    // into. Saying so beats quietly dropping what was typed.
    if (named and !cmd.spec.takes.isMessage()) {
        try err.print("m8 {s}: {s}, so there is nowhere to put a name\n", .{
            cmd.spec.name,
            if (cmd.spec.takes == .stdin) "takes stdin as it is" else "is handed no ledger",
        });
        try err.flush();
        return 1;
    }

    // `m8 COMMAND --help` is `m8 help COMMAND` too, read here so that no
    // command has to parse the flag and no two answer it differently. Not for
    // `--`, whose arguments are prose: there it is something somebody said.
    if (!asked_for_help and !cmd.spec.prompts and command.api.wantsHelp(cmd_args)) {
        var words: std.ArrayList([]const u8) = .empty;
        try words.append(arena, cmd.spec.name);
        try words.appendSlice(arena, cmd_args[1..]);
        cmd = helper;
        cmd_args = words.items;
    }

    // One command's arguments are prose. It is read here rather than there
    // because a prompt goes into the ledger, and the ledger is assembled here.
    var prompt: []const u8 = "";
    if (cmd.spec.prompts) {
        prompt = try std.mem.join(arena, " ", cmd_args);
        cmd_args = &.{};
    }

    const dirs = try config.discover(arena, io, init.environ_map);

    const assembled = gather(io, arena, dirs, name, named, as, prompt, cmd.spec.takes) catch |e| {
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
    if (cmd.spec.prompts and assembled.said_nothing) {
        try help.overview(err);
        try err.flush();
        return 1;
    }

    // What the child is handed, which is the promise this launcher made when
    // it decided what to assemble. A command that takes stdin as it arrives
    // keeps the descriptor; everything else gets the bytes read for it.
    const input: launch.Stdin = switch (cmd.spec.takes) {
        .nothing => .inherited,
        else => .{ .bytes = assembled.document },
    };

    // The one place this launcher's two builds differ. The branch is
    // comptime: the lean one never names a command value, and so carries none
    // of what a command value would drag in behind it.
    const reach: launch.Reach = if (launch.split)
        .{ .spawn = cmd.program }
    else
        .{ .call = command.at(cmd.path).? };

    // What a complaint names. The command under this one parses its own
    // arguments, so this launcher reaches `shield ask` by calling `shield` —
    // but `m8 shield ask:` says more than `m8 shield:` and costs nothing.
    const called = try command.named(arena, cmd.path, cmd_args);

    return harness.run(io, arena, init.environ_map, reach, called, cmd_args, input, self, out, err);
}

/// Read what this kind of command is handed.
fn gather(
    io: std.Io,
    arena: std.mem.Allocator,
    dirs: []const []const u8,
    name: []const u8,
    named: bool,
    as: doc.Sigil,
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
            as,
            prompt,
            try command.api.readDocument(io, arena, &in_buf),
        ),
    };
}
