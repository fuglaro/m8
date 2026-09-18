//! `help` — what a command takes, and what is under it.
//!
//! One page per command, reached two ways: `m8 help send` and `m8 send --help`
//! are the same words on the same channel, because m8 rewrites the second into
//! the first before the command sees its arguments. A command that has
//! subcommands is asked for one of them by naming it — `m8 help providers url`
//! — and a command that has none simply ignores the rest.
//!
//! A page you asked for is written to stdout, where it can be paged and piped.
//! A page you were handed instead of what you asked for goes to stderr, where
//! it cannot become part of somebody's document.
//!
//! The lists here are the registry itself rather than a copy of it, so nothing
//! can come to be advertised that m8 would not run. They are read from the
//! tree, which is names and summaries: listing what m8 has is not a reason to
//! hold every command that has it.
//!
//! A page lives beside the command whose page it is, so where the commands are
//! programs this asks the program — `m8 help send` is `m8-send --help`. The
//! alternative is a help command that holds every page, which is a copy of the
//! whole of m8 to print a paragraph.

const std = @import("std");
const cmd = @import("../command.zig");
const launch = @import("../launch.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const name = "help";

pub const command: api.Command = .{
    .name = name,
    .summary = "what a command takes, and what is under it",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len == 0) {
        try overview(ctx.out);
        try ctx.out.flush();
        return 0;
    }

    // Whatever is left names something under it, and is that command's to
    // read: `m8 help providers url` is the url page.
    if (launch.split) {
        const node = anywhere(ctx.args[0]) orelse return unknown(ctx);
        // `--help` first, because that is the flag the command answers; what
        // follows it names whatever is under that command.
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(ctx.arena, "--help");
        try argv.appendSlice(ctx.arena, ctx.args[1..]);
        return launch.under(ctx, .{ .spawn = node.program }, argv.items, .inherited);
    }

    const c = cmd.findAny(ctx.args[0]) orelse return unknown(ctx);
    var inner = ctx;
    inner.args = ctx.args[1..];
    try write(inner, c, ctx.out);
    try ctx.out.flush();
    return 0;
}

/// A command reached wherever it lives: at the top, or under `call` because it
/// is an inbuilt tool. `help` is asked for a name and not for a path.
fn anywhere(called: []const u8) ?cmd.Node {
    if (cmd.byPath(&.{called})) |n| return n;
    return cmd.byPath(&.{ "call", called });
}

fn unknown(ctx: Ctx) !u8 {
    try ctx.err.print("m8 help: '{s}' is not a command\n", .{ctx.args[0]});
    try overview(ctx.err);
    try ctx.err.flush();
    return 1;
}

/// One command's page, or its summary when that is the whole of it.
pub fn write(ctx: Ctx, c: api.Command, w: *std.Io.Writer) !void {
    if (c.help) |h| return h(ctx, w);
    try w.print("m8 {s} — {s}\n", .{ c.name, c.summary });
}

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 help — what a command takes, and what is under it
        \\
        \\  m8 help [COMMAND [MORE]]
        \\  m8 COMMAND --help
        \\
        \\The same page either way. MORE names something under a command, so
        \\`m8 help providers url` is the page for that provider command.
        \\
    );
    try commands(w);
}

/// What a bare `m8` says, and what `m8 help` says at length.
pub fn overview(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\m8 — a composable shell harness
        \\
        \\  m8 [[@AGENT|+CHAT|^SKILL] MSG_CMD|RUN_CMD] [ARGS]
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
    try commands(w);
    try environment(w);
    try w.writeAll(
        \\
        \\m8 help COMMAND says what one takes and what is under it.
        \\m8 call NAME reaches m8's own filters and its inbuilt tools.
        \\
    );
}

fn commands(w: *std.Io.Writer) !void {
    try list(w, "message commands", true);
    try list(w, "run commands", false);
}

fn list(w: *std.Io.Writer, heading: []const u8, message: bool) !void {
    try w.print("\n{s}:\n\n", .{heading});
    for (cmd.tree) |n| {
        if (n.spec.takes.isMessage() != message) continue;
        try w.print("  {s: <10} {s}\n", .{ n.spec.name, n.spec.summary });
    }
}

/// Every variable m8 itself reads. A provider's own are on its page, since
/// what they mean is that command's business rather than m8's.
fn environment(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\
        \\environment:
        \\
        \\  XDG_CONFIG_HOME   where your own config is, as m8-st8 under it
        \\  HOME              that, when XDG_CONFIG_HOME says nothing:
        \\                    ~/.config/m8-st8
        \\  PATH              where a provider or tool named as a bare word
        \\                    is looked for, and where m8 finds itself
        \\  TMPDIR            where a shielded tool's own directory is made;
        \\                    /tmp when unset
        \\  M8_PROVIDER_*     what a providers.json entry hands its command.
        \\                    See m8 help providers.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "every command has a page, and it says which command it is" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // No HOME and no XDG, so anything that reads a config reads the copy
    // compiled in rather than whatever is on the machine running the tests.
    var env: std.process.Environ.Map = .init(arena);
    var thrown: std.Io.Writer.Allocating = .init(arena);

    for (cmd.all ++ cmd.native) |c| {
        var page_out: std.Io.Writer.Allocating = .init(arena);
        try write(.{
            .arena = arena,
            .io = threaded.io(),
            .mode = .md,
            .env = &env,
            .args = &.{},
            .in = "",
            .out = &page_out.writer,
            .err = &thrown.writer,
            .tty = null,
        }, c, &page_out.writer);

        const said = page_out.written();
        try testing.expect(said.len > 0);
        try testing.expect(std.mem.indexOf(u8, said, c.name) != null);
        // A page is prose for a person, not a document. It never opens like
        // one, or piping it somewhere would read as a ledger.
        try testing.expect(said[0] != '#');
    }
}

test "the overview lists every command" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();

    var out: std.Io.Writer.Allocating = .init(a.allocator());
    try overview(&out.writer);
    const said = out.written();

    for (cmd.tree) |n| {
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
