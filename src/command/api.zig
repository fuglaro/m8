//! The command contract: what every command is handed, and what it may talk to.
//!
//! Most commands are filters over an m8 stream: they read a document on stdin
//! and write one on stdout. Anything said to the *person* goes to the terminal
//! instead, on its own channel, so a command that opens a UI is still a legal
//! member of a pipeline.
//!
//! Keeping interaction off stdout is the whole reason this works. A command
//! that printed its prompt to stdout would corrupt every downstream reader.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("../m8/doc.zig");

pub const Ctx = struct {
    arena: Allocator,
    io: std.Io,
    /// The spelling to write in. Markdown for every command, whatever stdout
    /// is, so a command says the same thing to a terminal as to a pipe. Only
    /// the `@` prompt and a command marked `terminal` are handed the rendered
    /// spelling when stdout is one.
    mode: doc.Mode,
    /// The environment, for a command that spawns something.
    env: *const std.process.Environ.Map,
    /// Where the m8 that is running lives, so a provider naming `m8` reaches
    /// this build rather than whichever one is on a PATH, or none at all.
    self: []const u8 = "m8",
    /// The call this is answering, which names the 🧾 or 🚫 written back.
    /// Empty when a command was run straight from the shell.
    call_id: []const u8 = "",
    /// What a call hands its tool, in the environment rather than in the
    /// command, which is the one way a call is carried.
    ///
    /// Added after the environment has been rebuilt, so `contain-env` filters
    /// what was inherited and never what this call is saying.
    extra_env: []const EnvVar = &.{},
    /// Arguments after the command name.
    args: []const []const u8,
    /// The incoming document. Empty when nothing was piped in.
    ///
    /// Read whole for now. Commands that only ever append are the reason this
    /// wants to become a streaming reader later; the contract does not change
    /// when it does.
    in: []const u8,
    /// The outgoing document.
    out: *std.Io.Writer,
    /// Diagnostics and help. Never part of the document, always visible, and
    /// unlike `tty` it is there even under a pipe.
    err: *std.Io.Writer,
    /// Whether stdout is a pipe. A downstream command such as `head` is
    /// allowed to close it early; a write failure there is a successful early
    /// termination rather than a diagnostic.
    stdout_pipe: bool = false,
    /// The person, when there is one, for anything that needs an answer back.
    /// Null under a pipe or in a script, which is the signal to run
    /// non-interactively rather than to fail.
    tty: ?Tty,
};

/// One variable handed to a child. Named rather than positional, so a tool
/// written in any language reads it the way that language already reads its
/// environment.
pub const EnvVar = struct { key: []const u8, value: []const u8 };

/// How a tool asks the person something: this exit status, nothing on stdout,
/// and a stderr that opens with `ask_lead`. `EX_TEMPFAIL` — it could not
/// finish, and is worth running again.
pub const ask_exit = 75;
pub const ask_lead = "QUESTION:";
/// Who is asking follows the lead and closes with a colon: the tool itself,
/// or a shield by the name it was told it stands as.
pub const asks_tool = "tool";
pub const asks_shield = "shield_";
/// What the person answered, in the environment of the call it was said to.
/// `M8_EXCLAMATION_1` is the first thing they answered the tool, and so on
/// up. What they answered a shield has its name after: `M8_EXCLAMATION_1_ask_1`.
pub const exclamation = "M8_EXCLAMATION_";

/// A name as part of a variable's. Whoever chose it was not choosing a
/// variable's name, and nothing says they chose one a variable can have.
pub fn component(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    const out = try arena.dupe(u8, name);
    for (out) |*c| if (!std.ascii.isAlphanumeric(c.*)) {
        c.* = '_';
    };
    return out;
}

/// The interaction channel. Separate from `in`/`out` by construction.
pub const Tty = struct {
    r: *std.Io.Reader,
    w: *std.Io.Writer,
};

/// What a command is handed on `in`.
///
/// Every command is `m8 CMD ARGS` with stdin, and none of them is handed a
/// name the command line resolved for it: a command that wants one takes it
/// as an argument and resolves it itself, which is how `m8 ref @mathy` works.
///
/// So the one question is whether stdin is the command's to read. Most read
/// it whole. `call` and anything else that hands stdin to a child must not,
/// or it would swallow the bytes that child is waiting for.
pub const Takes = enum {
    stdin,
    nothing,
};

/// What a launcher needs to know about a command, which is not what the
/// command does.
///
/// The separation is the whole of how one registry serves two builds. A
/// launcher reads a `Spec` to decide what goes on a child's stdin and what to
/// call it; it never touches `run`. Nothing in here is a function pointer, so
/// a launcher that only reads specs links none of the implementations — the
/// registry costs it a couple of kilobytes rather than the whole stack.
///
/// Two places say the same thing, and that is deliberate: a command declares
/// what it expects, a launcher promises it, and keeping the two in step is a
/// maintainer's job rather than something the type system hides.
pub const Spec = struct {
    name: []const u8,
    summary: []const u8,
    takes: Takes = .stdin,
};

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    /// Whether `in` is filled with stdin.
    takes: Takes = .stdin,
    /// Whether it is handed the rendered spelling when stdout is a terminal.
    /// Almost nothing is: a command that answered a terminal differently
    /// would be two commands, and only one of them could be piped.
    terminal: bool = false,
    /// The exit status. A filter returns 0; `call` returns whatever it ran.
    run: *const fn (Ctx) anyerror!u8,
    /// This command at length: what it takes, what it answers with, and
    /// whatever is under it.
    ///
    /// The writer is handed in rather than taken from `Ctx`, because which
    /// channel a page belongs on is the caller's business: a page somebody
    /// asked for goes to stdout where it can be paged and piped, and a page
    /// handed back instead of what they asked for goes to stderr where it
    /// cannot become part of a document.
    ///
    /// `ctx.args` are the words after the command's own name, so a command
    /// with subcommands under it can hand out the page for one of them.
    help: ?*const fn (Ctx, *std.Io.Writer) anyerror!void = null,

    /// The half of this a launcher reads. Comptime, so taking it leaves `run`
    /// unreferenced and the implementation out of the binary.
    pub fn spec(c: Command) Spec {
        return .{
            .name = c.name,
            .summary = c.summary,
            .takes = c.takes,
        };
    }
};

/// Whether the next word is asking for a page rather than naming anything.
///
/// Asked once, here, so no command has to remember to answer `--help` and no
/// two answer it differently. m8 reads it before a command sees its arguments;
/// prompt words after an `@` are prose only after their `--` separator.
pub fn wantsHelp(args: []const []const u8) bool {
    return args.len > 0 and std.mem.eql(u8, args[0], "--help");
}

test "only a leading long help option asks for help" {
    try std.testing.expect(wantsHelp(&.{"--help"}));
    try std.testing.expect(wantsHelp(&.{ "--help", "more" }));
    try std.testing.expect(!wantsHelp(&.{}));
    try std.testing.expect(!wantsHelp(&.{"-h"}));
    try std.testing.expect(!wantsHelp(&.{ "value", "--help" }));
}

/// The terminal, opened as its own channel.
pub const TtyFiles = struct {
    file: std.Io.File,
    r: std.Io.File.Reader,
    w: std.Io.File.Writer,
    r_buf: [4096]u8,
    w_buf: [4096]u8,
};

/// Open the terminal as its own channel. Absent under a pipe, which commands
/// read as "run non-interactively" rather than as a failure.
pub fn openTty(io: std.Io, storage: *TtyFiles) ?Tty {
    const f = std.Io.Dir.openFileAbsolute(io, "/dev/tty", .{ .mode = .read_write }) catch return null;
    storage.file = f;
    storage.r = f.readerStreaming(io, &storage.r_buf);
    storage.w = f.writerStreaming(io, &storage.w_buf);
    return .{ .r = &storage.r.interface, .w = &storage.w.interface };
}

/// Read the incoming document.
///
/// A terminal on stdin means there is no incoming document — nobody pipes a
/// conversation in by hand — so it reads as empty. Waiting for an EOF the
/// terminal will never send just hangs.
pub fn readDocument(io: std.Io, arena: Allocator, buf: []u8) ![]const u8 {
    const in = std.Io.File.stdin();
    if (try in.isTty(io)) return "";
    var r = in.readerStreaming(io, buf);
    return r.interface.allocRemaining(arena, .unlimited);
}
