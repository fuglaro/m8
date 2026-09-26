//! m8 — a composable shell harness.
//!
//!     m8 [@ADDRESS[:|-] [WHATEVER YOU WANT TO SAY]]
//!     m8 COMMAND [ARGS]
//!
//! `@` is how the command line names an address, and it sits where a command
//! would. What follows it is prose, so nothing has to arbitrate between m8's
//! arguments and yours. A bare `m8` is `m8 @`, the main chat.
//!
//! Every other command is `m8 COMMAND ARGS` with stdin, and resolves whatever
//! it names itself: `m8 cat @mathy`. So there is one kind of command, and the
//! `@` prompt is the pipeline of them written once.
//!
//! `--help` is read here rather than by whichever command was named, so no
//! command has to remember to answer it and no two answer it differently. It
//! names the `help` command, which is why `m8 send --help` and `m8 help send`
//! are one page.
//!
//! A terminal is written the rendered spelling and everything else markdown,
//! decided once here and carried into every writer.
//!
//! Everything the process does hangs off one arena. A run is short: read a
//! document, transform it, write it, exit. Nothing outlives that, so nothing
//! needs freeing individually.

const std = @import("std");
const command = @import("command.zig");
const provider = @import("provider.zig");
const address = @import("address.zig");
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
    _ = @import("address.zig");
    _ = @import("prompt.zig");
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
    // unlike the other. The split launcher is only ever `m8`; prompt mode is
    // handled there, while the other commands remain sibling programs.
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

    const helper = command.byPath(&.{help.name}).?;

    // `m8 --help [COMMAND]` is `m8 help [COMMAND]`. The flag is a way of
    // naming the command rather than a command's own argument.
    if (command.api.wantsHelp(@ptrCast(args))) return launched(io, arena, init, helper, @ptrCast(args[1..]), self, out, err);

    // An address, or nothing at all, is the prompt. Its words are prose, so
    // nothing in them is read here.
    if (args.len == 0 or address.isAddress(args[0]))
        return harness.run(io, arena, init.environ_map, .prompt, "", @ptrCast(args), .inherited, self, out, err);

    const node = command.byPath(&.{args[0]}) orelse {
        try err.print("m8: '{s}' is not a command. See m8 --help.\n", .{args[0]});
        try err.flush();
        return 1;
    };
    const cmd_args: []const []const u8 = @ptrCast(args[1..]);

    // `m8 COMMAND --help` is `m8 help COMMAND` too, read here so that no
    // command has to parse the flag and no two answer it differently.
    if (command.api.wantsHelp(cmd_args)) {
        var words: std.ArrayList([]const u8) = .empty;
        try words.append(arena, node.spec.name);
        try words.appendSlice(arena, cmd_args[1..]);
        return launched(io, arena, init, helper, words.items, self, out, err);
    }
    return launched(io, arena, init, node, cmd_args, self, out, err);
}

/// Reach a command, whichever way this build reaches one. Each reads its own
/// stdin, so the launcher reads none.
fn launched(
    io: std.Io,
    arena: std.mem.Allocator,
    init: std.process.Init,
    node: command.Node,
    cmd_args: []const []const u8,
    self: []const u8,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
) !u8 {
    const reach: launch.Reach = if (!launch.split)
        .{ .call = command.at(node.path).? }
    else
        .{ .spawn = node.program };

    // What a complaint names. The command under this one parses its own
    // arguments, so this launcher reaches `shield ask` by calling `shield` —
    // but `m8 shield ask:` says more than `m8 shield:` and costs nothing.
    const called = try command.named(arena, node.path, cmd_args);
    return harness.run(io, arena, init.environ_map, reach, called, cmd_args, .inherited, self, out, err);
}
