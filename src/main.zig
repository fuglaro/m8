//! m8 — a composable shell harness.
//!
//!     m8 [:MOB/AGENT[:|-|--] [-p] [-v] [-- PROMPT]]
//!     m8 COMMAND [ARGS]
//!
//! `:MOB/AGENT` sits where a command would. Address shorthand supplies `at`
//! with one prompt argument after `--`; a bare `m8` shows the overview.
//! There is no implicit/global chat selection.
//!
//! Every command is `m8 COMMAND ARGS` with stdin, and resolves whatever it
//! names itself: `m8 ref :demo/mathy`. So there is one kind of command, and `at`
//! is the pipeline of them written once.
//!
//! `--help` is a process-level option: `m8 --help` is the overview and
//! `m8 COMMAND --help` is that command's page. It is read before a command's
//! own arguments, so no command has to remember to answer it and no two answer
//! it differently.
//!
//! `at` writes a terminal the rendered spelling and everything else
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
const config = @import("config.zig");
const test_tmp = @import("test_tmp.zig");

/// What `m8 --help` says. This belongs to the launcher rather than command
/// help: it describes the process syntax that the launcher itself owns.
fn overview(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 - the composable agentic shell harness
        \\
        \\  m8 :MOB/AGENT[:|-|--] [-p] [-v] [-- REQUEST_MESSAGE]
        \\  m8 COMMAND [ARGS]
        \\
        \\:MOB/AGENT sends a REQUEST_MESSAGE or stdin, and is short for `m8 at`.
        \\Put `--` before a request supplied as command-line arguments. `-p`
        \\renders and streams the reply even when stdout is not a terminal.
        \\`-v` says on stderr what the run is doing: a thought opening, a tool
        \\called.
        \\
        \\:demo/mathy talks to that agent's own chat and moves it on.
        \\An address is always explicit: bare m8 shows this page, not a chat.
        \\A subchat forks from its parent; `:` asks without advancing it,
        \\`-` resets to its parent, and `--` resets to its authored agent.
        \\The prompt separator is a separate `--` after the address.
        \\
        \\An address alone at a terminal opens the `tui` core/config.json names,
        \\with the address after it. With none named it is riff, sending each
        \\message with `m8 at -p -v :MOB/AGENT`.
        \\
        \\  m8 :demo/mathy -- "Tell me about the Riemann Sphere."
        \\  m8 :demo/mathy -- "Tell me more."
        \\  m8 :demo/mathy//aside -- "A different thought."
        \\
        \\Every command reads stdin and writes stdout, so the same thing is a
        \\pipeline too. A command writes markdown whatever stdout is, and takes
        \\options where address shorthand takes marks:
        \\
        \\  m8 ref :demo/mathy "And in one sentence?" | m8 send | m8 tag :demo/mathy
        \\  m8 ref :demo/mathy | m8 encode openai-completions >request.json
        \\  m8 query :demo/mathy "And in one sentence?"
        \\
        \\A provider is a file core/providers/NAME.json. Its `cmd`, `encode`,
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
    // Startup setup belongs to normal invocations, never tool children.
    if (!config.isChild(init.environ_map)) {
        if (try config.userDir(arena, init.environ_map)) |path|
            _ = try std.Io.Dir.cwd().createDirPathStatus(io, path, .fromMode(0o700));
    }

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

    // An explicit address is shorthand for `at`. Its grammar is
    // resolved here so that `at` stays one plain form.
    var line: []const []const u8 = @ptrCast(args);
    if (line.len == 0) {
        try overview(out);
        try siblings(io, arena, init.environ_map, self, out);
        try out.flush();
        return 0;
    }
    if (address.isAddress(line[0])) {
        const word: []const u8 = line[0];
        const body = address.body(word) orelse "";
        if (body.len == 0 or std.mem.eql(u8, body, ":") or std.mem.eql(u8, body, "-") or std.mem.eql(u8, body, "--")) {
            try err.writeAll("m8: address must name a mob/agent; there is no main chat\n");
            try err.flush();
            return 1;
        }
        if (line.len <= 1 and !std.mem.endsWith(u8, word, "-") and
            try std.Io.File.stdin().isTty(io) and try std.Io.File.stdout().isTty(io))
        tui: {
            // Check the address before a configured tui or riff can take over
            // the process. In particular, those interactive paths otherwise
            // bypass `at`'s normal ref validation.
            const checked: anyerror![]const u8 = preflight: {
                const dirs = try config.discover(arena, io, init.environ_map);
                const a = address.typed(arena, io, dirs, word, err) catch |e| break :preflight e;
                break :preflight address.found(arena, io, dirs, a, err);
            };
            _ = checked catch |e| {
                if (e != error.Said) return e;
                try err.flush();
                return 1;
            };
            // An `m8` first is this m8, so a tui needs nothing on a PATH.
            if (config.tui(arena, io, init.environ_map) catch |e| {
                try harness.explain(err, "", e);
                try err.flush();
                return 1;
            }) |named| {
                var words: std.ArrayList([]const u8) = .empty;
                try words.append(arena, if (std.mem.eql(u8, named[0], "m8")) self else named[0]);
                try words.appendSlice(arena, named[1..]);
                try words.append(arena, word);
                return launch.become(io, words.items);
            }
            // A build without riff still answers, one message at a time.
            if (command.find("riff") == null and
                try launch.beside(arena, io, self, command.prefix ++ "riff") == null) break :tui;
            return launch.become(io, &.{ self, "riff", "-s", "2", self, "at", "-p", "-v", word });
        }
        var at: std.ArrayList([]const u8) = .empty;
        try at.append(arena, "at");
        var rest = line[@min(1, line.len)..];
        while (rest.len > 0 and (std.mem.eql(u8, rest[0], "-p") or
            std.mem.eql(u8, rest[0], "-v") or std.mem.eql(u8, rest[0], "-vv"))) : (rest = rest[1..])
            try at.append(arena, rest[0]);
        try at.append(arena, word);
        if (rest.len > 0) {
            if (!std.mem.eql(u8, rest[0], "--")) {
                try err.writeAll("m8: put -- before what you want to say\n");
                try err.flush();
                return 1;
            }
            if (rest.len > 1) try at.append(arena, try std.mem.join(arena, " ", rest[1..]));
        }
        line = at.items;
    }

    const cmd_args = line[1..];
    if (command.find(line[0])) |c|
        return harness.run(io, arena, init.environ_map, c, @ptrCast(argv), cmd_args, self, out, err);

    // Not held here, so a program beside this one if there is one.
    const program = try std.mem.concat(arena, u8, &.{ command.prefix, line[0] });
    if (try launch.beside(arena, io, self, program)) |path| {
        var words: std.ArrayList([]const u8) = .empty;
        try words.append(arena, path);
        try words.appendSlice(arena, cmd_args);
        return launch.become(io, words.items);
    }

    try err.print("m8: '{s}' is not a command. See m8 --help.\n", .{line[0]});
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

test "interactive preflight rejects unknown agents and missing turns, but permits new chats" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();
    const dir = try test_tmp.make(arena, io, "m8-main-preflight");
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    const agent_path = try std.fs.path.join(arena, &.{ dir, try config.nameFile(arena, "mob/agent") });
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(agent_path).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agent_path, .data = "* :brain::/local/tiny\n" });
    const dirs = [_][]const u8{dir};
    var err: std.Io.Writer.Allocating = .init(arena);

    try testing.expectError(error.Said, address.typed(arena, io, config.Dirs{ .roots = &dirs }, ":mob/nobody", &err.writer));
    try testing.expect(std.mem.indexOf(u8, err.written(), "no agent named 'mob/nobody'") != null);

    err.clearRetainingCapacity();
    const missing = try address.typed(arena, io, config.Dirs{ .roots = &dirs }, ":mob/agent/+/missing", &err.writer);
    try testing.expectError(error.Said, address.found(arena, io, config.Dirs{ .roots = &dirs }, missing, &err.writer));
    try testing.expect(std.mem.indexOf(u8, err.written(), "no turn named 'mob/agent/+/missing'") != null);

    err.clearRetainingCapacity();
    const chat = try address.typed(arena, io, config.Dirs{ .roots = &dirs }, ":mob/agent//new-chat", &err.writer);
    _ = try address.found(arena, io, config.Dirs{ .roots = &dirs }, chat, &err.writer);
    try testing.expectEqualStrings("", err.written());
}

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
