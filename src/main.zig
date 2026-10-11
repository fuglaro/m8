//! m8 — a composable shell harness.
//!
//!     m8 [@ADDRESS[:|-] [-p] [-v] [-- PROMPT]]
//!     m8 COMMAND [ARGS]
//!
//! `@` is how the command line names an address, and it sits where a command
//! would. A prompt follows `--`, so nothing has to arbitrate between m8's
//! arguments and yours. A bare `m8` is `m8 @`, the main chat.
//!
//! Every other command is `m8 COMMAND ARGS` with stdin, and resolves whatever
//! it names itself: `m8 ref @mathy`. So there is one kind of command, and the
//! `@` prompt is the pipeline of them written once.
//!
//! `--help` is a process-level option: `m8 --help` is the overview and
//! `m8 COMMAND --help` is that command's page. It is read before a command's
//! own arguments, so no command has to remember to answer it and no two answer
//! it differently.
//!
//! The `@` prompt writes a terminal the rendered spelling and everything else
//! markdown. A command writes markdown whatever stdout is, and `m8 render` is
//! how a document becomes the rendered spelling.
//!
//! Everything the process does hangs off one arena. A run is short: read a
//! document, transform it, write it, exit. Nothing outlives that, so nothing
//! needs freeing individually.

const std = @import("std");
const command = @import("command.zig");
const provider = @import("provider.zig");
const address = @import("address.zig");
const harness = @import("harness.zig");
const launch = @import("launch.zig");

/// What `m8 --help` says. This belongs to the launcher rather than command
/// help: it describes the process syntax that the launcher itself owns.
fn overview(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 - the composable agentic shell harness
        \\
        \\  m8 @AGENT[:|-] [-p] [-v] [-- REQUEST_MESSAGE]
        \\  m8 COMMAND [ARGS]
        \\
        \\@AGENT sends a REQUEST_MESSAGE or stdin. Put `--` before a
        \\request supplied as command-line arguments. `-p` renders and
        \\streams the reply even when stdout is not a terminal. `-v` says on
        \\stderr what the run is doing: a thought opening, a tool called.
        \\
        \\@mathy talks to mathy's own chat, and moves it on. A plain m8 carries
        \\on whichever chat was talked to last. A chat under an agent is a fork
        \\of it, `:` asks without moving anything, and `-` starts a chat over.
        \\
        \\  m8 @mathy -- "Tell me about the Riemann Sphere."
        \\  m8 @ -- "Tell me more."
        \\  m8 @mathy/aside -- "A different thought."
        \\
        \\Every command reads stdin and writes stdout, so the same thing is a
        \\pipeline too. A command writes markdown whatever stdout is, and takes
        \\options where `@` takes marks:
        \\
        \\  m8 ref @ "And in one sentence?" | m8 send | m8 tag @
        \\  m8 ref @mathy | m8 encode openai-completions >request.json
        \\  m8 decode openai-completions local <request.json | m8 send
        \\  m8 query @mathy "And in one sentence?"
        \\
    );
    try overviewCommands(w);
}

fn overviewCommands(w: *std.Io.Writer) !void {
    try w.writeAll("\nCOMMANDS:\n");
    for (command.tree) |n| try w.print("  {s: <10} {s}\n", .{ n.spec.name, n.spec.summary });
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

    // The launcher owns its overview. Only the first word is reserved; a
    // prompt's `--help` is prose after its required `--` separator.
    if (command.api.wantsHelp(@ptrCast(args))) {
        try overview(out);
        try out.flush();
        return 0;
    }

    // An address, or nothing at all, is the prompt. The prompt parser owns
    // the `--` separator after the address.
    if (args.len == 0 or address.isAddress(args[0])) {
        // An address and nothing else, at a terminal, is a conversation: the
        // same address again and again from an editor, which is `riff` run on
        // this m8. `-p` is how riff asks, so with it there is no going round
        // twice, and it is also how to say one message the plain way.
        const word: []const u8 = if (args.len > 0) args[0] else "@";
        if (args.len <= 1 and !std.mem.endsWith(u8, word, "-") and
            try std.Io.File.stdin().isTty(io) and try std.Io.File.stdout().isTty(io))
        {
            return launched(io, arena, init, command.byPath(&.{"riff"}).?, &.{ self, word, "-p", "-v" }, self, out, err);
        }
        return harness.run(io, arena, init.environ_map, .prompt, "", @ptrCast(args), .inherited, self, out, err);
    }

    const node = command.byPath(&.{args[0]}) orelse {
        try err.print("m8: '{s}' is not a command. See m8 --help.\n", .{args[0]});
        try err.flush();
        return 1;
    };
    const cmd_args: []const []const u8 = @ptrCast(args[1..]);

    // `launch.under` answers a command's leading `--help` in the single
    // binary; a split-out leaf answers the same option itself.
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

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the overview lists every command" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();

    var out: std.Io.Writer.Allocating = .init(a.allocator());
    try overview(&out.writer);
    const said = out.written();

    for (command.tree) |n| {
        const c = n.spec;
        var seen: usize = 0;
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, said, at, c.name)) |i| {
            at = i + c.name.len;
            // Only the listing, which is two spaces and then the name.
            if (i >= 2 and said[i - 2] == ' ' and said[i - 1] == ' ') seen += 1;
        }
        try testing.expect(seen >= 1);
    }
}
