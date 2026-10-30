//! What every m8 binary does around a command, whichever binary it is.
//!
//! A command is handed a `Ctx` and answers with a status. Building that from a
//! process — the writers, the terminal, the document — is the same work in the
//! launcher and in a command built on its own, so it is written once here and
//! every root calls it.
//!
//! It is also where an error becomes something a person reads. A command
//! returns the error that names what went wrong and says nothing about
//! spelling; the sentence belongs out here, so two commands failing the same
//! way cannot say it two ways.

const std = @import("std");
const api = @import("api.zig");
const provider = @import("provider.zig");
const launch = @import("launch.zig");
const doc = @import("m8/doc.zig");

/// A command with its process around it: the whole of a command built on its own.
///
/// Stdin is read for anything that expects a document, because out here there
/// is no command line to assemble one from — whatever reaches this process on
/// stdin is what the launcher promised it.
///
/// `called` is the command's name, which is what a complaint names, so both
/// builds say the same thing about the same failure.
pub fn leaf(init: std.process.Init, c: api.Command, called: []const u8) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const argv = try init.minimal.args.toSlice(arena);
    const args: []const []const u8 = @ptrCast(argv[@min(1, argv.len)..]);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    var err_buf: [4 * 1024]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(io, &err_buf);
    const out = &stdout.interface;
    const err = &stderr.interface;

    const self = try m8Path(arena, io, init.environ_map, argv);
    var tty_storage: api.TtyFiles = undefined;
    var ctx: api.Ctx = .{
        .arena = arena,
        .io = io,
        .mode = if (c.terminal) mode(io) else .md,
        .env = init.environ_map,
        .self = self,
        .verbosity = verbosity(init.environ_map),
        .argv = @ptrCast(argv),
        .args = args,
        .in = "",
        .out = out,
        .err = err,
        .stdout_pipe = stdoutPipe(io),
        .tty = api.openTty(io, &tty_storage),
    };

    // The flag is m8's wherever it is written, so a command split out answers
    // it the way the launcher above it would have.
    if (api.wantsHelp(args)) {
        ctx.args = args[1..];
        try api.page(c, ctx, out);
        try out.flush();
        return 0;
    }

    var in_buf: [64 * 1024]u8 = undefined;
    // Stdin belongs to whatever a `.nothing` command hands it to.
    if (c.takes != .nothing) ctx.in = try api.readDocument(io, arena, &in_buf);

    return finish(ctx, called, c.run(ctx));
}

/// A launcher running the command it was given.
///
/// Commands take their arguments verbatim; they parse their own. Whether the
/// command is called or spawned is `launch`'s business, and either way what is
/// built here is the launcher's own context — a child process inherits from
/// it rather than being handed it.
pub fn run(
    io: std.Io,
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    c: api.Command,
    argv: []const []const u8,
    args: []const []const u8,
    self: []const u8,
    out: *std.Io.Writer,
    err: *std.Io.Writer,
) !u8 {
    var tty_storage: api.TtyFiles = undefined;
    const ctx: api.Ctx = .{
        .arena = arena,
        .io = io,
        .mode = if (c.terminal) mode(io) else .md,
        .env = env,
        .self = self,
        .verbosity = verbosity(env),
        .argv = argv,
        .args = &.{},
        .in = "",
        .out = out,
        .err = err,
        .stdout_pipe = stdoutPipe(io),
        .tty = api.openTty(io, &tty_storage),
    };
    return finish(ctx, c.name, launch.under(ctx, c, args));
}

/// Everything on its way out, and whatever went wrong said once.
fn finish(ctx: api.Ctx, name: []const u8, result: anyerror!u8) !u8 {
    const status = result catch |e| {
        if (e == error.WriteFailed and ctx.stdout_pipe) return 0;
        try ctx.out.flush();
        if (ctx.tty) |t| try t.w.flush();
        try explain(ctx.err, name, e);
        try ctx.err.flush();
        return 1;
    };

    ctx.out.flush() catch |e| {
        if (e == error.WriteFailed and ctx.stdout_pipe) return 0;
        return e;
    };
    if (ctx.tty) |t| try t.w.flush();
    // A command that answered with a status rather than an error still said
    // why on the way, and this is the one place both are on their way out.
    try ctx.err.flush();
    return status;
}

/// Whether stdout is a pipe rather than a file or terminal.
fn stdoutPipe(io: std.Io) bool {
    const stat = std.Io.File.stdout().stat(io) catch return false;
    return stat.kind == .named_pipe;
}

fn verbosity(env: *const std.process.Environ.Map) u8 {
    return std.fmt.parseInt(u8, env.get("M8_VERBOSITY") orelse "0", 10) catch 0;
}

/// Where the m8 launcher is, from where this binary is.
///
/// A command built on its own is installed beside the launcher, so the launcher is
/// its sibling named `m8`. Worked out here rather than inherited, so a command
/// run straight from a shell knows it too.
fn m8Path(
    arena: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    argv: []const []const u8,
) ![]const u8 {
    const me = try provider.selfPath(arena, io, env, if (argv.len > 0) argv[0] else "m8");
    if (std.mem.eql(u8, std.fs.path.basename(me), "m8")) return me;
    return launch.sibling(arena, me, "m8");
}

/// The spelling a terminal is written, for the few that ask what stdout is.
pub fn mode(io: std.Io) doc.Mode {
    return if (std.Io.File.stdout().isTty(io) catch false) .m8 else .md;
}

/// What went wrong, in a sentence. One place, so two commands failing the same
/// way cannot say it two ways.
pub fn explain(err: *std.Io.Writer, name: []const u8, e: anyerror) !void {
    switch (e) {
        error.UnknownAgent => try err.writeAll("m8: that ledger names an agent that is not there\n"),
        error.IncludeLoops => try err.writeAll(
            "m8: an agent includes one that leads back to it\n",
        ),
        error.LineageLoops => try err.writeAll(
            "m8: a turn in that chat names one that leads back to it\n",
        ),
        error.TopMisplaced => try err.writeAll(
            "m8: a top opens and closes at the head of a file, or there is none\n",
        ),
        error.TopUnclosed => try err.writeAll(
            "m8: a top was opened and nothing closed it\n",
        ),
        error.UnknownProvider => try err.writeAll("m8: no core/providers/NAME.json for that provider\n"),
        error.NoModel => try err.writeAll("m8: nothing in that ledger names a model\n"),
        error.BadSignature => try err.writeAll("m8: a 🔏 is followed by its signature as one code span\n"),
        error.NoProvider => try err.writeAll(
            "m8: that ledger names a model but not whose; write it /PROVIDER/MODEL\n",
        ),
        error.InvalidName => try err.writeAll("m8: name an explicit mob/agent path; components cannot be empty or start with a period; use mob/agent//chat for subchats and /+/TURN for turns\n"),
        error.CrossMobReference => try err.writeAll("m8: chat and turn references must stay inside their activated mob; compose other mobs through authored definitions\n"),
        error.NoDataHome => try err.writeAll("m8: set HOME or XDG_DATA_HOME for writable user/system mob state\n"),
        error.BadTui => try err.writeAll("m8: tui in core/config.json is a list of words, the command first\n"),
        error.NothingToReset => try err.writeAll(
            "m8: only an explicitly addressed chat can be reset\n",
        ),
        error.FollowLoops => try err.writeAll(
            "m8: that would have a chat follow something that leads back to it\n",
        ),
        // Already said, in terms of what was typed, or by the provider stage
        // that failed, which is the line worth leaving on screen.
        error.Said, error.ProviderFailed => {},
        else => if (name.len == 0)
            try err.print("m8: {s}\n", .{@errorName(e)})
        else
            try err.print("m8 {s}: {s}\n", .{ name, @errorName(e) }),
    }
}
