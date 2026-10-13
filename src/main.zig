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
        \\  m8 query @mathy "And in one sentence?"
        \\
        \\A provider is an entry in core/providers.json. Its `cmd`, `encode`,
        \\`parse` and `models` are commands, and every other string in it
        \\reaches them as M8_PROVIDER_*: `url` as M8_PROVIDER_URL.
        \\
    );
    try overviewCommands(w);
}

fn overviewCommands(w: *std.Io.Writer) !void {
    try w.writeAll("\nCOMMANDS:\n");
    for (command.all) |c| try w.print("  {s: <13} {s}\n", .{ c.name, c.summary });
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

    // A binary installed under one of the command names *is* that command,
    // the way a symlinked busybox is.
    if (command.byProgram(std.fs.path.basename(self))) |c| return harness.leaf(init, c, c.name);

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
        try siblings(io, arena, init.environ_map, self, out);
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
            // riff is started as a process of its own even when this binary
            // holds it, so that what it was started with is how it starts
            // itself again. Without riff anywhere, the one message is said
            // the plain way.
            if (command.find("riff") != null)
                return launch.become(io, &.{ self, "riff", self, word, "-p", "-v" });
            if (try launch.beside(arena, io, self, command.prefix ++ "riff")) |riff|
                return launch.become(io, &.{ riff, self, word, "-p", "-v" });
        }
        return harness.run(io, arena, init.environ_map, .prompt, "", @ptrCast(argv), @ptrCast(args), self, out, err);
    }

    const cmd_args: []const []const u8 = @ptrCast(args[1..]);
    if (command.find(args[0])) |c|
        return harness.run(io, arena, init.environ_map, .{ .call = c }, c.name, @ptrCast(argv), cmd_args, self, out, err);

    // Not held here, so a program beside this one if there is one.
    const program = try std.mem.concat(arena, u8, &.{ command.prefix, args[0] });
    if (try launch.beside(arena, io, self, program)) |path| {
        var words: std.ArrayList([]const u8) = .empty;
        try words.append(arena, path);
        try words.appendSlice(arena, cmd_args);
        return launch.become(io, words.items);
    }

    try err.print("m8: '{s}' is not a command. See m8 --help.\n", .{args[0]});
    try err.flush();
    return 1;
}

/// Set while a launcher is asking the programs beside it what they are, so
/// one of them that is itself a launcher does not ask in turn.
const listing = "M8_LISTING";

/// The commands that are programs beside this one, for the overview.
///
/// Each is asked for its page, and the first line of that is what it is: a
/// manual's NAME line, `m8 NAME - SUMMARY`. One that says anything else is
/// still listed, by name alone.
fn siblings(
    io: std.Io,
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    self: []const u8,
    w: *std.Io.Writer,
) !void {
    if (env.get(listing) != null) return;
    const where = std.fs.path.dirname(self) orelse return;
    var dir = std.Io.Dir.cwd().openDir(io, where, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (!std.mem.startsWith(u8, entry.name, command.prefix)) continue;
        const name = entry.name[command.prefix.len..];
        if (name.len == 0 or command.find(name) != null) continue;
        try names.append(arena, try arena.dupe(u8, name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var asking = try env.clone(arena);
    try asking.put(listing, "1");
    for (names.items) |name| {
        const path = try std.fs.path.join(arena, &.{ where, try std.mem.concat(arena, u8, &.{ command.prefix, name }) });
        const said = std.process.run(arena, io, .{
            .argv = &.{ path, "--help" },
            .environ_map = &asking,
        }) catch continue;
        const first = said.stdout[0 .. std.mem.indexOfScalar(u8, said.stdout, '\n') orelse said.stdout.len];
        const lead = try std.fmt.allocPrint(arena, "m8 {s} - ", .{name});
        const summary = if (std.mem.startsWith(u8, first, lead)) first[lead.len..] else "";
        try w.print("  {s: <13} {s}\n", .{ name, summary });
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the overview lists every command" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();

    var out: std.Io.Writer.Allocating = .init(a.allocator());
    try overview(&out.writer);
    const said = out.written();

    for (command.all) |c| {
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
