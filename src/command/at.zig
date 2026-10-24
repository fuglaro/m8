//! `at` — the pipeline written once.
//!
//!     m8 at [-p] [-v] :MOB/AGENT [PROMPT]
//!
//!     m8 ref --piped :MOB/AGENT WORDS | m8 send | m8 tag :MOB/AGENT
//!
//! is what this does, and it is kept exactly that: the same assembly, the
//! same run and the same tag. The one difference is that it is one process, so the reply is shown
//! as it arrives and tagged as it goes — a turn for every model call and
//! every tool call, each naming the one before — rather than once there is a
//! whole run to keep.
//!
//! A trailing `:` is
//! `--no-advance`, a trailing `-` is `m8 reset`, and a trailing `--` is
//! `m8 reset --new`; a document piped in follows the address as it is.
//!
//! The prompt is one argument after the address, taken as it is, so nothing
//! in it can be mistaken for m8 syntax. `-p` asks for the rendered spelling whatever
//! stdout is, and `-v` for a line on stderr as the run thinks and as it calls
//! a tool. They go before the address.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const converse = @import("../converse.zig");
const ledger = @import("../ledger.zig");
const Keeping = @import("../keeping.zig").Keeping;
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "at",
    .summary = "say something to an address, and keep the turn",
    // It reads its own stdin: a terminal is read a submission at a time.
    .takes = .nothing,
    .terminal = true,
    .run = run,
    .help = page,
};

fn run(given: Ctx) !u8 {
    // `-p` is pretty: what a terminal is written, whatever stdout is. It is
    // how something standing between m8 and the terminal asks for the reply
    // as a person reads it.
    //
    // `-v` is verbose: what the run is doing, said on stderr as it does it.
    // `-vv` is more so, to anything the run starts that has more to say.
    var pretty = false;
    var verbosity: u8 = 0;
    var args = given.args;
    while (args.len > 0) : (args = args[1..]) {
        if (std.mem.eql(u8, args[0], "-p")) pretty = true else if (std.mem.eql(u8, args[0], "-v")) verbosity = 1 else if (std.mem.eql(u8, args[0], "-vv")) verbosity = 2 else break;
    }
    var word: []const u8 = "";
    if (args.len > 0 and address.isAddress(args[0])) {
        word = args[0];
        args = args[1..];
    }
    // Absent is not empty: with none, a terminal is asked for one.
    var said: ?[]const u8 = null;
    if (args.len > 0) {
        said = args[0];
        args = args[1..];
    }
    if (args.len > 0) {
        try given.err.writeAll("m8: say it as one argument, in quotes\n");
        return 1;
    }
    var ctx = given;
    if (pretty) ctx.mode = .m8;

    const arena = ctx.arena;
    const io = ctx.io;
    const dirs = try config.discover(arena, io, ctx.env);

    const a = try address.typed(arena, io, dirs, word, ctx.err);

    if (a.suffix == .reset or a.suffix == .reset_new) {
        if (said != null) {
            try ctx.err.writeAll("m8: a reset says nothing, so nothing goes after it\n");
            return 1;
        }
        // The fresh chat is also the one being talked to now. `-` reads as
        // the parent; `--` reads as the agent, whatever the parent has done.
        if (a.suffix == .reset_new)
            try address.renew(arena, io, dirs, a)
        else
            try address.reset(arena, io, dirs, a);
        return 0;
    }

    const prompt = said orelse "";
    var in_buf: [64 * 1024]u8 = undefined;
    const stdin = std.Io.File.stdin();
    const terminal_submission = ctx.in.len == 0 and said == null and try stdin.isTty(io);
    const piped = if (ctx.in.len > 0)
        ctx.in
    else if (terminal_submission)
        try readTerminalPrompt(io, arena, stdin, &in_buf)
    else
        try api.readDocument(io, arena, &in_buf);

    // EOF before anything was entered is the quiet way out of an input that
    // was opened deliberately. An empty pipe remains "nothing to say": it did
    // not ask m8 to wait for a message in the first place.
    if (terminal_submission and piped.len == 0) return 0;

    const lead = [_]doc.Record{.{ .sigil = .agent, .value = try address.found(arena, io, dirs, a, ctx.err) }};
    const asked = ledger.waiting(arena, io, dirs, lead[0].value);
    const assembled = try assembly.assemble(arena, &lead, prompt, piped, asked);
    if (assembled.said_nothing) {
        // Where the terminal will one day open a conversation in place. For
        // now there is only nothing to say, and it is said.
        try ctx.err.writeAll("m8: say something after the address, or pipe it in\n");
        return 1;
    }

    // Terminal input was echo rather than output, and Ctrl-D can briefly leave
    // its caret notation under the cursor. Turn the submitted prose into the
    // first visible record before any provider latency begins.
    if (terminal_submission) {
        if (ctx.tty) |t| {
            try t.w.writeAll("  \n");
            try showPrompt(t.w, piped, asked);
        }
    } else if (pretty) try showPrompt(ctx.out, if (piped.len > 0) piped else prompt, asked);

    var inner = ctx;
    inner.in = assembled.document;
    var keeping: Keeping = .{
        .arena = arena,
        .io = io,
        .dirs = dirs,
        .a = a,
        .home = try address.home(arena, io, dirs, a, lead[0].value),
    };
    const turn = try converse.run(inner, .{ .owner = a.name, .keep = keeping.keeper(), .verbosity = verbosity });
    const kept = try keeping.finish(turn);

    try ctx.out.writeByte('\n');
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = kept });
    return 0;
}

/// Acknowledge a submission in the language already used for the reply.
///
/// At a terminal the caller first overwrites what the driver echoed for VEOF:
/// `^D` followed by two backspaces, which two spaces cover without assuming
/// ANSI escapes, and a newline puts the record on a clean line.
fn showPrompt(w: *std.Io.Writer, entered: []const u8, asked: ?[]const u8) !void {
    // A document is context rather than one thing the person said. Do not lie
    // about it by wrapping the whole document in a user record; the newline is
    // still the immediate acknowledgment that its Ctrl-D was received.
    if (doc.detect(entered) == null) {
        // Said to a question, it is the answer to it.
        try doc.write(w, .m8, if (asked) |id|
            .{ .sigil = .exclaim, .value = id, .content = entered }
        else
            .{ .sigil = .user, .content = entered });
        try w.writeByte('\n');
    }
    try w.flush();
}

/// Read prose entered directly at a terminal. Canonical terminal input makes
/// Enter one completed line and Ctrl-D the end of the submission, so this can
/// stay a plain reader rather than becoming a terminal UI.
///
/// With text pending on the current line, VEOF makes `read` return that text
/// rather than returning end-of-stream. Such a canonical read has no trailing
/// newline; stopping there makes one Ctrl-D sufficient instead of asking for a
/// second one on the now-empty line. The buffer is deliberately much larger
/// than a terminal's canonical line buffer, so a full underlying read cannot
/// look like that partial final line.
fn readTerminalPrompt(
    io: std.Io,
    arena: std.mem.Allocator,
    stdin: std.Io.File,
    buf: []u8,
) ![]const u8 {
    var reader = stdin.readerStreaming(io, buf);
    const r = &reader.interface;
    var text: std.ArrayList(u8) = .empty;

    while (true) {
        r.fill(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const got = r.buffered();
        try text.appendSlice(arena, got);
        r.toss(got.len);
        if (got[got.len - 1] != '\n') break;
    }
    return text.items;
}

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 at [-p] [-v] :MOB/AGENT[:|-|--] ["PROMPT"]
        \\
        \\Sends PROMPT, one argument taken as it is, or stdin. `-p` renders and
        \\streams the reply even when stdout is not a terminal. `-v` says on
        \\stderr what the run is doing: a thought opening, a tool called.
        \\
        \\:demo/mathy talks to mathy's own chat and moves only that chat.
        \\A subchat is a fork; `:` asks without advancing it, `-` resets it
        \\to its parent,
        \\and `--` starts from its agent instead.
        \\
    );
}
