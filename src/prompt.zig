//! `m8 @ADDRESS WORDS` — the pipeline written once.
//!
//!     echo WORDS | m8 cat @ADDRESS | m8 send | m8 tag @ADDRESS
//!
//! is what this does, and it is kept exactly that: the same assembly, the
//! same run, the same tag. The one difference is that it is one process, so
//! the reply is shown as it arrives rather than once there is a turn to keep.
//!
//! `@` is not a command, but it sits where one would. Its arguments are prose,
//! so nothing after it has to be told from m8's own flags — which is what the
//! old `--` marker was for, and why there is no `--` any more.

const std = @import("std");
const doc = @import("m8/doc.zig");
const config = @import("config.zig");
const address = @import("address.zig");
const assembly = @import("assembly.zig");
const converse = @import("converse.zig");
const api = @import("command/api.zig");
const Ctx = api.Ctx;

/// `args` are every word after `m8`: the address, and what to say to it. None
/// at all is the main chat.
pub fn run(ctx: Ctx, args: []const []const u8) !u8 {
    const arena = ctx.arena;
    const io = ctx.io;
    const dirs = try config.discover(arena, io, ctx.env);

    const word = if (args.len > 0) args[0] else "@";
    const a = try address.typed(arena, io, dirs, word, ctx.err);
    const words = if (args.len > 0) args[1..] else args;

    if (a.suffix == .reset) {
        if (words.len > 0) {
            try ctx.err.writeAll("m8: a reset says nothing, so nothing goes after it\n");
            return 1;
        }
        try address.reset(arena, io, dirs, a);
        return 0;
    }

    const prompt = try std.mem.join(arena, " ", words);
    var in_buf: [64 * 1024]u8 = undefined;
    const stdin = std.Io.File.stdin();
    const terminal_submission = ctx.in.len == 0 and words.len == 0 and try stdin.isTty(io);
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

    const lead = [_]doc.Record{.{ .sigil = .agent, .value = try address.read(arena, io, dirs, a) }};
    const assembled = try assembly.assemble(arena, &lead, prompt, piped);
    if (assembled.said_nothing) {
        // Where the terminal will one day open a conversation in place. For
        // now there is only nothing to say, and it is said.
        try ctx.err.writeAll("m8: say something after the address, or pipe it in\n");
        return 1;
    }

    // Terminal input was echo rather than output, and Ctrl-D can briefly leave
    // its caret notation under the cursor. Turn the submitted prose into the
    // first visible record before any provider latency begins.
    if (terminal_submission) try showTerminalPrompt(ctx.tty, piped);

    var inner = ctx;
    inner.in = assembled.document;
    const turn = try converse.run(inner, .{});
    const kept = try address.tag(arena, io, dirs, a, turn);

    try ctx.out.writeByte('\n');
    try doc.write(ctx.out, ctx.mode, .{ .sigil = .agent, .value = kept });
    return 0;
}

/// Acknowledge a terminal submission in the language already used for the
/// reply. The terminal driver may echo VEOF as `^D` followed by two backspaces;
/// two spaces overwrite that notation without assuming ANSI escapes, and the
/// newline puts the record on a clean line.
fn showTerminalPrompt(tty: ?api.Tty, entered: []const u8) !void {
    const t = tty orelse return;
    try t.w.writeAll("  \n");

    // A document is context rather than one thing the person said. Do not lie
    // about it by wrapping the whole document in a user record; the newline is
    // still the immediate acknowledgment that its Ctrl-D was received.
    if (doc.detect(entered) == null) {
        const prose = std.mem.trim(u8, entered, " \t\r\n");
        if (prose.len > 0) {
            try doc.write(t.w, .m8, .{ .sigil = .user, .content = prose });
            try t.w.writeByte('\n');
        }
    }
    try t.w.flush();
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
