//! `riff` — a command's output as real scrollback, over a stdin editor pinned
//! beneath it.
//!
//! The terminal does the work. A scroll region covers everything above the
//! live rows, so what the command writes is ordinary scrollback that riff
//! never repaints and never has to model. Only the command writes there; riff
//! writes the status line, the editor, and terminal modes.
//!
//! The cursor is the command's, and rests wherever its output has got to.
//! That is the one position a terminal keeps true through a resize, so it is
//! the one riff rebuilds around. The editor's cursor is drawn rather than
//! real, and the live rows are painted from a saved cursor and back.
//!
//! Every send is a run: the command is started, handed the message on stdin,
//! and streamed until it ends. It runs in a session of its own, so opening
//! `/dev/tty` fails cleanly rather than fighting riff for the terminal.

const std = @import("std");
const width = @import("../m8/highlight.zig").width;
const posix = std.posix;
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "riff",
    .summary = "run a command per message, from an editor pinned under its output",
    .takes = .nothing,
    // It draws on one, so it has to know there is one.
    .terminal = true,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 riff [-c] [-t] [-s N] CMD [ARGS]
        \\
        \\Each message sent starts CMD, hands it the message on stdin, and lets
        \\its stdout scroll past as ordinary terminal scrollback. The last line
        \\it wrote to stderr is the status line.
        \\
        \\A stderr line that leads with `::stats::` carries a panel, which
        \\stays at the right of the top status line until the next one. The
        \\panel runs to a `::` or the end of the line. Anything after the
        \\closing `::` is ignored:
        \\
        \\  ::stats::✥19▇16K::16000 in, 14000 cached
        \\
        \\The editor is one row, grows with the message to at most half the
        \\terminal, and is one row again once the message is sent.
        \\If CMD fails without stdout, its input returns to the editor before
        \\anything typed while it ran. Stderr does not prevent this recovery.
        \\
        \\  Enter    send, and a message sent mid-run waits its turn
        \\  Ctrl-j   a new line, and so is Alt-Enter
        \\  Ctrl-d   send; with nothing to send and nothing running, leave
        \\  Ctrl-c   interrupt the run; with nothing running, leave
        \\
        \\`-c` is continuous: the first message starts CMD and every message
        \\is a line on its stdin. Ctrl-d with nothing to send then closes
        \\its stdin. CMD has to work a line at a time on a pipe:
        \\
        \\  m8 riff -c python3 -i -u -q
        \\
        \\`-t` is `-c` with every message ended by a NUL byte rather than a
        \\new line, for a CMD that takes messages of more than one line.
        \\
        \\`-s N` is N status lines, the last N that CMD wrote to stderr:
        \\
        \\  m8 riff -c -s 2 python3 -i -u -q
        \\
        \\CMD is given no terminal: it runs in a detached session of its own,
        \\which is riff run again with `--detached CMD`. Its environment is riff's as it
        \\arrived, apart from COLUMNS tracking the terminal width.
        \\
    );
}

/// Runs what follows it in a session of its own, in place of this process.
const detached = "--detached";

/// How long the terminal must have kept its size, in milliseconds, before
/// the live rows are drawn again.
const settle = 100;

/// How long after a resize, in milliseconds, output is held for the terminal
/// to confirm its size before each chunk is written.
const wary = 1000;

/// The status bar and the editor's edge: a mid grey from the 256 colours,
/// which reads on a dark background and on a light one.
const gutter = 4;
const grey = "\x1b[38;5;245m";

var winch = false;
var quit = false;

fn onSignal(sig: posix.SIG) callconv(.c) void {
    if (sig == .WINCH) winch = true else quit = true;
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len > 1 and std.mem.eql(u8, ctx.args[0], detached)) {
        _ = posix.system.setsid();
        return std.process.replace(ctx.io, .{
            .argv = ctx.args[1..],
            .environ_map = ctx.env,
        });
    }
    // `-c` is continuous: one run of the command, sent every message.
    // `-t` is that with a NUL ending each message, which a new line inside
    // one cannot be taken for.
    // `-s N` is how many status lines there are.
    var continuous = false;
    var end: u8 = '\n';
    var bars: usize = 1;
    var cmd = ctx.args;
    while (cmd.len > 0) : (cmd = cmd[1..]) {
        if (std.mem.eql(u8, cmd[0], "-c")) {
            continuous = true;
        } else if (std.mem.eql(u8, cmd[0], "-t")) {
            continuous = true;
            end = 0;
        } else if (std.mem.startsWith(u8, cmd[0], "-s")) {
            // The number is the next word, or the rest of this one.
            const n = if (cmd[0].len > 2) cmd[0][2..] else if (cmd.len > 1) cmd[1] else "";
            if (cmd[0].len == 2 and cmd.len > 1) cmd = cmd[1..];
            bars = std.fmt.parseInt(usize, n, 10) catch 0;
            if (bars < 1 or bars > most_bars) {
                try ctx.err.print("m8 riff: -s is from 1 to {d}\n", .{most_bars});
                return 1;
            }
        } else break;
    }
    if (cmd.len == 0) {
        try ctx.err.writeAll("m8 riff: needs a command to run\n");
        return 1;
    }
    if (ctx.mode != .m8 or !try std.Io.File.stdin().isTty(ctx.io)) {
        try ctx.err.writeAll("m8 riff: needs a terminal on stdin and stdout\n");
        return 1;
    }

    var r: Riff = .{
        .ctx = ctx,
        .out = ctx.out,
        .cmd = cmd,
        .continuous = continuous,
        .end = end,
        .s = bars,
    };

    for ([_]posix.SIG{ .WINCH, .TERM, .HUP, .INT }) |sig|
        posix.sigaction(sig, &.{ .handler = .{ .handler = onSignal }, .mask = posix.sigemptyset(), .flags = 0 }, null);
    // A command that ends without reading its message is not a reason to die.
    posix.sigaction(.PIPE, &.{ .handler = .{ .handler = posix.SIG.IGN }, .mask = posix.sigemptyset(), .flags = 0 }, null);

    const cooked = try posix.tcgetattr(0);
    var raw = cooked;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    try posix.tcsetattr(0, .FLUSH, raw);
    defer posix.tcsetattr(0, .FLUSH, cooked) catch {};

    try r.open();
    defer r.close();
    try r.loop();
    return 0;
}

/// What riff itself says on the status line. While a command runs the line
/// is the command's, and `working` is a finished line so that whatever it
/// says first takes its place. The rest are riff's alone: it has been told to
/// stop, or it is the person's turn and this is the key that does something.
const working = "Dispatched...\n";
const stopping = "Stopping...";
const empty_hint = "(ctrl-c:cancel,ctrl-d:exit)...";
const written_hint = "(enter:dispatch,alt-enter/ctrl-j:newline)...";
const waiting_empty = "Waiting " ++ empty_hint;
const waiting_written = "Waiting " ++ written_hint;

/// What a line on stderr leads with when it carries the panel: the panel
/// follows, up to a pair of colons or the end of the line.
const stats = "::stats::";

/// The most status lines there may be.
const most_bars = 8;
/// The longest a key's sequence is left unfinished before it is let go.
const keep = 16;

const Riff = struct {
    ctx: Ctx,
    out: *std.Io.Writer,
    cmd: []const []const u8,
    /// Terminal rows and columns, and how many rows the editor has. It
    /// grows with the message, never shrinks under it, and is one row again
    /// once the message is sent.
    h: usize = 0,
    w: usize = 0,
    e: usize = 0,
    sent: bool = false,
    /// The message being written, the cursor's byte offset in it, and the
    /// first of its visual rows on show.
    buf: std.ArrayList(u8) = .empty,
    at: usize = 0,
    /// Whether the terminal says it has the keyboard. One that never says is
    /// taken to have it.
    focused: bool = true,
    /// The terminal is part way through a paste, where a new line is text
    /// and no byte is a key.
    pasting: bool = false,
    /// The command has been interrupted and has not ended yet.
    stopping: bool = false,
    /// How the last child stopped: its exit code or signal number.
    stopped: ?u32 = null,
    /// A run is kept and sent each message, where otherwise each message is
    /// a run of its own.
    continuous: bool = false,
    /// What ends a message handed to a continuous run.
    end: u8 = '\n',
    top: usize = 0,
    rows: std.ArrayList(usize) = .empty,
    /// What each live row was last drawn as, so one that has not changed is
    /// not sent again. Typing is then a row's worth of bytes, not six.
    drawn: std.ArrayList(std.ArrayList(u8)) = .empty,
    line: std.Io.Writer.Allocating = .init(std.heap.page_allocator),
    queue: std.ArrayList([]const u8) = .empty,
    /// Input kept until this run produces stdout, for recovery on failure.
    input: std.ArrayList(u8) = .empty,
    output_seen: bool = false,
    /// The last line the command wrote to stderr.
    status: [512]u8 = undefined,
    status_len: usize = 0,
    status_ended: bool = false,
    /// The panel has ended; ignore the rest of this stderr line.
    stats_tail: bool = false,
    /// How many status lines were asked for, and the lines before the last,
    /// newest first, for the ones above the bottom.
    s: usize = 1,
    older: [most_bars][512]u8 = undefined,
    older_len: [most_bars]usize = @splat(0),
    /// The panel at the right of the top status line: what the command last
    /// said in a line that began with `stats`. It stays until the next one.
    panel: [64]u8 = undefined,
    panel_len: usize = 0,
    scan: Scanner = .{},
    /// Whether the terminal has been asked where the command's cursor is,
    /// and what for: a resize, or a count the command's own cursor moves
    /// have left unknown.
    /// A resize also asks how big the terminal is, and so does the look
    /// taken before the live rows are drawn again after one.
    asking: enum { no, size, check, gate, place } = .no,
    /// The first of the two answers those take, while the second is awaited.
    first: ?[2]usize = null,
    /// Where riff last put the command's cursor, until the command writes.
    spot: ?[2]usize = null,
    /// Whether it has answered since the command last wrote anything.
    asked: bool = false,
    /// When the terminal was last resized, while the live rows are still
    /// left blank for it. A row drawn full width wraps the moment the
    /// terminal narrows, and what wraps at the bottom scrolls the output
    /// away above it. So nothing is drawn until the resizing has stopped.
    resizing: ?std.Io.Timestamp = null,
    /// When the terminal last changed size. For a while after, it is likely
    /// to again before saying so, and output written then lands on rows that
    /// have moved. So each chunk waits for the terminal to say it has not.
    shaken: ?std.Io.Timestamp = null,
    clear: bool = false,
    child: ?std.process.Child = null,
    streams: [2]?posix.fd_t = .{ null, null },

    /// The rows riff owns: the status lines and the editor.
    fn live(r: *const Riff) usize {
        return if (r.h < 3) 0 else r.e + r.bars();
    }

    /// The status lines there is room for: as many as were asked for, while
    /// that leaves the editor a row within half the terminal.
    fn bars(r: *const Riff) usize {
        return @max(1, @min(r.s, (r.h / 2) -| 1));
    }

    /// The most rows the editor may have: the live rows are at most half
    /// the terminal.
    fn most(r: *const Riff) usize {
        return (r.h / 2) -| r.bars();
    }

    /// Take the terminal's size: what it said itself, or else what the
    /// system says, which can be a while behind it.
    fn measure(r: *Riff, said: ?[2]usize) void {
        var ws: posix.winsize = .{ .row = 24, .col = 80, .xpixel = 0, .ypixel = 0 };
        _ = posix.system.ioctl(1, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        r.h = if (said) |size| size[0] else ws.row;
        r.w = if (said) |size| size[1] else ws.col;
        r.e = @min(r.e, r.most());
        r.scan.w = r.w;
    }

    /// Claim the live rows by scrolling rather than clearing, so whatever was
    /// on screen is still there above them.
    fn open(r: *Riff) !void {
        r.measure(null);
        const l = r.live();
        try r.out.splatByteAll('\n', l);
        if (l > 0) try r.out.print("\x1b[{d}A", .{l});
        // Setting a region sends the cursor home, so it is put back.
        // And the terminal is asked to say when it gains and loses focus.
        try r.out.print("\x1b7\x1b[1;{d}r\x1b8\x1b[?25l\x1b[?1004h\x1b[?2004h", .{r.h - l});
        try r.render();
    }

    fn close(r: *Riff) void {
        if (r.child) |c| posix.kill(-c.id.?, .HUP) catch {};
        r.wipe() catch {};
        r.out.writeAll("\x1b[0m\x1b[?2004l\x1b[?1004l\x1b[?25h") catch {};
        r.out.flush() catch {};
    }

    fn loop(r: *Riff) !void {
        var chunk: [4096]u8 = undefined;
        var held: usize = 0;
        while (!quit) {
            if (winch) {
                // Reflow has moved everything, so ask where the command's
                // cursor landed and rebuild around the answer.
                winch = false;
                try r.ask(.size);
            }
            if (r.resizing) |since| if (r.asking == .no and since.untilNow(r.ctx.io, .awake).toMilliseconds() >= settle) {
                // A terminal can have changed again without having said so
                // yet, so it is asked before anything is drawn on it.
                r.resizing = null;
                try r.ask(.check);
            };
            if (r.queue.items.len > 0 and (r.child == null or r.continuous)) {
                // A new dispatch clears how the last command stopped before
                // this one gets a chance to say its own status.
                r.stopped = null;
                // Said first, so it shows until the command says something.
                // Sending ends whatever line the command had left open, as
                // the Enter a terminal echoes would have.
                r.status_ended = true;
                r.note(working);
                try r.render();
                if (r.child == null) try r.spawn(r.queue.orderedRemove(0));
                // A run already listening is handed whatever else is waiting.
                if (r.continuous) while (r.queue.items.len > 0) try r.hand(r.queue.orderedRemove(0));
            }

            var fds = [3]posix.pollfd{
                .{ .fd = 0, .events = posix.POLL.IN, .revents = 0 },
                .{ .fd = if (r.asking != .no) -1 else r.streams[0] orelse -1, .events = posix.POLL.IN, .revents = 0 },
                .{ .fd = r.streams[1] orelse -1, .events = posix.POLL.IN, .revents = 0 },
            };
            const n = posix.system.poll(&fds, fds.len, if (r.asking != .no) 100 else if (r.resizing != null) settle / 2 else -1);
            if (posix.errno(n) != .SUCCESS) continue;
            // A terminal that never answers is assumed to be at the bottom.
            if (n == 0 and r.asking != .no) try r.answered(r.first, null);

            if (fds[0].revents != 0) {
                const got = posix.read(0, chunk[held..]) catch 0;
                if (got == 0) return;
                // A sequence cut short by the read is kept for the next one.
                const all = chunk[0 .. held + got];
                const read = try r.keys(all);
                held = all.len - read;
                std.mem.copyForwards(u8, chunk[0..held], all[read..]);
                try r.render();
            }
            if (fds[1].revents != 0 and r.asking == .no) {
                if (r.shaken) |since| if (since.untilNow(r.ctx.io, .awake).toMilliseconds() >= wary) {
                    r.shaken = null;
                };
                if (r.shaken != null and !r.clear) {
                    try r.ask(.gate);
                    continue;
                }
                r.clear = false;
                const got = posix.read(fds[1].fd, &chunk) catch 0;
                if (got == 0) r.streams[0] = null else {
                    r.output_seen = true;
                    r.input.clearRetainingCapacity();
                    try r.scan.feed(r.out, chunk[0..got]);
                    r.asked = false;
                    r.spot = null;
                    try r.render();
                }
            }
            if (fds[2].revents != 0) {
                const got = posix.read(fds[2].fd, &chunk) catch 0;
                if (got == 0) r.streams[1] = null else {
                    r.note(chunk[0..got]);
                    try r.render();
                }
            }
            if (r.child != null and r.streams[0] == null and r.streams[1] == null) {
                const term = r.child.?.wait(r.ctx.io) catch std.process.Child.Term{ .unknown = 0 };
                r.stopped = switch (term) {
                    .exited => |code| if (code == 0) null else code,
                    .signal, .stopped => |signal| @intFromEnum(signal),
                    else => null,
                };
                // A failed, silent run has not consumed the draft from the
                // user's point of view. Restore it before newer typing,
                // keeping that typing's cursor.
                if (r.stopped != null and !r.output_seen and r.input.items.len > 0) {
                    try r.buf.insertSlice(r.ctx.arena, 0, r.input.items);
                    r.at += r.input.items.len;
                    r.sent = false;
                }
                r.input.clearRetainingCapacity();
                r.child = null;
                // Whatever it left half said is not owed an ending.
                r.scan.state = .text;
                r.scan.owed = 0;
                r.stopping = false;
                try r.render();
            }
        }
    }

    /// How riff is started again: the way this one was. Of the first two
    /// words it was started with, a program named for riff is the whole of
    /// it, and `riff` after a launcher is the two of them. Anything else is
    /// the first word alone.
    fn again(ctx: Ctx) ![]const []const u8 {
        const said = ctx.argv;
        if (said.len == 0) return ctx.arena.dupe([]const u8, &.{ ctx.self, "riff" });
        const me = try @import("../provider.zig").selfPath(ctx.arena, ctx.io, ctx.env, said[0]);
        const named = std.mem.endsWith(u8, std.fs.path.basename(said[0]), "riff");
        if (!named and said.len > 1 and std.mem.eql(u8, said[1], "riff"))
            return ctx.arena.dupe([]const u8, &.{ me, "riff" });
        return ctx.arena.dupe([]const u8, &.{me});
    }

    /// Start the command on one message. The message is written before
    /// anything is read back, which a command reading its stdin first allows.
    fn spawn(r: *Riff, message: []const u8) !void {
        const arena = r.ctx.arena;
        const io = r.ctx.io;
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, try again(r.ctx));
        try argv.append(arena, detached);
        try argv.appendSlice(arena, r.cmd);

        var env = try r.ctx.env.clone(arena);
        try env.put("COLUMNS", try std.fmt.allocPrint(arena, "{d}", .{r.w}));
        const child = try std.process.spawn(io, .{
            .argv = argv.items,
            .environ_map = &env,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        r.streams = .{ child.stdout.?.handle, child.stderr.?.handle };
        r.child = child;
        r.input.clearRetainingCapacity();
        r.output_seen = false;
        try r.hand(message);
    }

    /// Write the command a message. One run a message has then been told
    /// everything; a continuous one is told a message and left listening.
    fn hand(r: *Riff, message: []const u8) !void {
        const in = if (r.child) |*c| &c.stdin else return;
        const to = in.* orelse return;
        if (!r.output_seen) {
            // Continuous messages become separate editor lines on recovery,
            // even when the wire delimiter is a NUL rather than a newline.
            if (r.input.items.len > 0) try r.input.append(r.ctx.arena, '\n');
            try r.input.appendSlice(r.ctx.arena, message);
        }
        var buf: [4096]u8 = undefined;
        var w = to.writerStreaming(r.ctx.io, &buf);
        w.interface.writeAll(message) catch {};
        if (r.continuous) w.interface.writeByte(r.end) catch {};
        w.interface.flush() catch {};
        if (!r.continuous) r.hang();
    }

    /// Say there is no more to come, which is how a command reading until
    /// the end is told to finish.
    fn hang(r: *Riff) void {
        const in = if (r.child) |*c| &c.stdin else return;
        if (in.*) |to| to.close(r.ctx.io);
        in.* = null;
    }

    /// What the status line reads. With nothing running or due to run it is
    /// the person's turn, and what it says follows what they have written.
    fn says(r: *const Riff) []const u8 {
        return r.own() orelse r.status[0..r.status_len];
    }

    /// What riff has to say itself, which takes the bottom line when it does.
    fn own(r: *const Riff) ?[]const u8 {
        if (r.child == null and r.queue.items.len == 0)
            return if (r.buf.items.len == 0) waiting_empty else waiting_written;
        return if (r.stopping) stopping else null;
    }

    /// The status line `up` rows above the bottom one. What the command said
    /// last is the bottom line, or the one above it while riff has that.
    fn above(r: *const Riff, up: usize) []const u8 {
        if (up == 0) return r.says();
        const back = if (r.own() == null) up else up - 1;
        if (back == 0) return r.status[0..r.status_len];
        return if (back - 1 < most_bars) r.older[back - 1][0..r.older_len[back - 1]] else "";
    }

    /// Keep the last line said on stderr: a newline or a return ends it, and
    /// it stays on show until something follows.
    fn note(r: *Riff, bytes: []const u8) void {
        for (bytes) |b| {
            if (b == '\n' or b == '\r') {
                if (!r.status_ended and (r.stats_tail or r.lift(r.status_len))) {
                    // The line was the panel and nothing else, so it was not
                    // a status line and the one before it comes back down.
                    r.status = r.older[0];
                    r.status_len = r.older_len[0];
                    for (1..most_bars) |i| {
                        r.older[i - 1] = r.older[i];
                        r.older_len[i - 1] = r.older_len[i];
                    }
                    r.older_len[most_bars - 1] = 0;
                }
                r.stats_tail = false;
                r.status_ended = true;
                continue;
            }
            if (r.stats_tail) continue;
            if (r.status_ended) {
                // A new line, so the one before it moves up.
                var i: usize = most_bars - 1;
                while (i > 0) : (i -= 1) {
                    r.older[i] = r.older[i - 1];
                    r.older_len[i] = r.older_len[i - 1];
                }
                r.older[0] = r.status;
                r.older_len[0] = r.status_len;
                r.status_len = 0;
            }
            r.status_ended = false;
            if (r.status_len < r.status.len) {
                r.status[r.status_len] = b;
                r.status_len += 1;
            }
            // The panel ends at the next pair of colons. The rest of this
            // line is detail for other consumers, not another status line.
            if (b == ':' and std.mem.endsWith(u8, r.status[0..r.status_len], "::") and
                r.lift(r.status_len - 2)) r.stats_tail = true;
        }
    }

    /// Take the panel out of a status line that leads with one, up to `end`.
    fn lift(r: *Riff, end: usize) bool {
        const line = r.status[0..r.status_len];
        if (end < stats.len or !std.mem.startsWith(u8, line, stats)) return false;
        r.panel_len = @min(end - stats.len, r.panel.len);
        @memcpy(r.panel[0..r.panel_len], line[stats.len..][0..r.panel_len]);
        return true;
    }

    // ------------------------------------------------------------ drawing

    /// Break the message into visual rows, and say which row and column the
    /// cursor is on. `rows` holds the byte offset each row starts at.
    fn layout(r: *Riff) !struct { row: usize, col: usize } {
        const text = r.buf.items;
        const max = r.w -| ((2 * r.margin() -| 1) + 2);
        r.rows.clearRetainingCapacity();
        try r.rows.append(r.ctx.arena, 0);
        var col: usize = 0;
        var cur_row: usize = 0;
        var cur_col: usize = 0;
        var i: usize = 0;
        while (i <= text.len) {
            const c: Glyph = if (i < text.len) glyph(text, i) else .{ .cp = 0, .len = 1 };
            if (i < text.len and c.cp != '\n' and col + width(c.cp) > max and col > 0) {
                try r.rows.append(r.ctx.arena, i);
                col = 0;
            }
            if (i == r.at) {
                cur_row = r.rows.items.len - 1;
                cur_col = col;
            }
            if (i < text.len and c.cp == '\n') {
                try r.rows.append(r.ctx.arena, i + 1);
                col = 0;
            } else col += width(c.cp);
            i += c.len;
        }
        return .{ .row = cur_row, .col = cur_col };
    }

    /// The cells kept clear at each side of the live rows, where there is
    /// width to spare.
    fn margin(r: *const Riff) usize {
        return if (r.w >= 6 * gutter) gutter else 0;
    }

    /// The text of one visual row, without the newline that ended it.
    fn row(r: *const Riff, k: usize) []const u8 {
        const text = r.buf.items;
        const end = if (k + 1 < r.rows.items.len) r.rows.items[k + 1] else text.len;
        return std.mem.trimEnd(u8, text[r.rows.items[k]..end], "\n");
    }

    /// Redraw the live rows that have changed, and put the cursor back where
    /// the command left it. Never in the middle of something the command is
    /// still saying.
    fn render(r: *Riff) !void {
        if (r.asking != .no or r.resizing != null or !r.scan.ground()) return;
        const o = r.out;
        if (r.live() == 0) return o.flush();
        // Painting takes the cursor away and back, which is only safe when
        // the count along the line is known. The terminal knows.
        if (r.scan.x == null and !r.asked) return r.ask(.place);
        // The command may have moved the cursor into the live rows or erased
        // them, so nothing drawn there is trusted.
        if (r.scan.strayed) r.forget();

        var cur = try r.layout();
        const want = @min(r.most(), if (r.sent) 1 else @max(r.e, r.rows.items.len));
        r.sent = false;
        if (want != r.e) {
            try r.fit(want);
            cur = try r.layout();
        }
        const l = r.live();
        r.top = @min(r.top, r.rows.items.len -| r.e);
        if (cur.row < r.top) r.top = cur.row;
        if (r.e > 0 and cur.row >= r.top + r.e) r.top = cur.row + 1 - r.e;

        var any = false;
        var waiting_line: [128]u8 = undefined;
        const line = &r.line;
        for (0..l) |k| {
            line.clearRetainingCapacity();
            const w = &line.writer;
            // The editor's edge is the last cell of the left margin.
            const inner = r.w - (2 * r.margin() -| 1);
            try w.splatByteAll(' ', r.margin() -| 1);
            const b = r.bars();
            if (k < b) {
                // Grey in reverse is a grey bar with the terminal's own
                // background for its text. The top row has notched bezels;
                // rows beneath it have solid blocks at both ends. All rows
                // keep the same width.
                const up = b - 1 - k;
                const bezel = inner >= 8;
                try w.writeAll(if (!bezel) grey ++ "\x1b[7m" else if (k == 0) grey ++ "▂▟\x1b[7m" else grey ++ "██\x1b[7m");
                const room = if (bezel) inner - 4 else inner;
                // The top line gives its right end to the panel, hard up
                // against it, while that leaves it room to say something.
                const panel = r.panel[0..r.panel_len];
                const aside = if (k == 0 and span(panel) + 8 <= room) span(panel) else 0;
                var said = r.above(up);
                if (up == 0 and r.child == null and r.queue.items.len == 0 and r.stopped != null) {
                    said = std.fmt.bufPrint(
                        &waiting_line,
                        "Stopped({d}) and waiting {s}",
                        .{ r.stopped.?, if (r.buf.items.len == 0) empty_hint else written_hint },
                    ) catch said;
                }
                const used = try put(w, said, room - aside);
                try w.splatByteAll(' ', room - aside -| used);
                if (aside > 0) _ = try put(w, panel, aside);
                try w.writeAll(if (!bezel) grey ++ "\x1b[27m" else if (k == 0) grey ++ "\x1b[27m▙▂" else grey ++ "\x1b[27m██");
            } else {
                // The edge runs the height of the editor, written or not.
                try w.writeAll(grey ++ "▏\x1b[0m");
                if (r.top + k - b < r.rows.items.len) {
                    const text = r.row(r.top + k - b);
                    // The cursor is a cell in reverse: the character it is
                    // on, or a space past the end of the row. It is shown
                    // only while the keyboard is this terminal's.
                    const here = r.focused and r.top + k - b == cur.row;
                    const to = if (here) @min(r.at - r.rows.items[cur.row], text.len) else text.len;
                    const next = if (to < text.len) to + glyph(text, to).len else to;
                    _ = try put(w, text[0..to], inner);
                    if (here) try w.writeAll("\x1b[7m");
                    if (here) _ = try put(w, if (to < text.len) text[to..next] else " ", inner);
                    if (here) try w.writeAll("\x1b[0m");
                    _ = try put(w, text[next..], inner);
                }
                try w.writeAll("\x1b[K");
            }
            if (r.drawn.items.len <= k) try r.drawn.append(r.ctx.arena, .empty);
            if (std.mem.eql(u8, r.drawn.items[k].items, line.written())) continue;
            // No wrapping while painting. A terminal that has narrowed
            // without having said so would wrap a row drawn for the old
            // width, and a wrap on the bottom row scrolls the output away
            // and leaves half a bar behind in it. Cut short instead, the row
            // is put right by the resize that follows.
            if (!any) try o.writeAll("\x1b[?2026h\x1b7\x1b[?7l");
            any = true;
            try o.print("\x1b[{d};1H{s}", .{ r.h - l + 1 + k, line.written() });
            r.drawn.items[k].clearRetainingCapacity();
            try r.drawn.items[k].appendSlice(r.ctx.arena, line.written());
        }
        if (any) {
            // On again first: putting the cursor back may retype the last
            // character to leave a wrap waiting, which needs it.
            try o.writeAll("\x1b[?7h");
            try r.scan.restore(o);
            try o.writeAll("\x1b[?2026l");
        }
        try o.flush();
    }

    /// Give the editor a different number of rows.
    ///
    /// Growing takes rows from the bottom of the flow. Stepping the cursor
    /// down that many lines and back up scrolls the flow exactly as far as
    /// the command's cursor was in the way, and no further, without asking
    /// where it is. Shrinking hands rows back blank.
    fn fit(r: *Riff, rows: usize) !void {
        const o = r.out;
        const old = r.live();
        r.e = rows;
        const new = r.live();
        if (new > old) {
            for (old..new) |_| try o.writeAll("\x1bD");
            try o.print("\x1b[{d}A", .{new - old});
        }
        try o.writeAll("\x1b7");
        for (r.h - old + 1..r.h - @min(old, new) + 1) |y| try o.print("\x1b[{d};1H\x1b[2K", .{y});
        try o.print("\x1b[1;{d}r", .{r.h - new});
        try r.scan.restore(o);
        r.forget();
    }

    /// Drop the scroll region and blank everything from the cursor down,
    /// leaving the cursor where it was.
    ///
    /// A line at a time, and never with an erase to the end of the screen:
    /// from the top-left corner a terminal may take that for clearing the
    /// screen, and keep what was on it in scrollback, stale live rows and all.
    fn wipe(r: *Riff) !void {
        try r.out.writeAll("\x1b7\x1b[r\x1b8\x1b[K");
        for (0..r.h + 32) |_| try r.out.writeAll("\x1b[B\x1b[2K");
        try r.out.writeAll("\x1b8");
    }

    /// Draw every live row afresh next time.
    fn forget(r: *Riff) void {
        for (r.drawn.items) |*d| d.clearRetainingCapacity();
        r.scan.strayed = false;
    }

    /// Ask the terminal where the command's cursor is. Around a resize it
    /// is also asked how big it is, by sending the cursor as far down and
    /// right as it will go and asking again: the size the system reports is
    /// only what the terminal has got round to announcing.
    fn ask(r: *Riff, why: @TypeOf(r.asking)) !void {
        r.asking = why;
        r.first = null;
        try r.out.writeAll("\x1b[6n");
        if (why != .place) {
            try r.out.writeAll("\x1b7\x1b[9999;9999H\x1b[6n");
            if (why == .size) try r.out.writeAll("\x1b8") else try r.scan.restore(r.out);
        }
        try r.out.flush();
    }

    /// The terminal has said where the command's cursor is and, when it was
    /// asked, how big it is. Or it never will, and both are null.
    fn answered(r: *Riff, at: ?[2]usize, size: ?[2]usize) !void {
        const why = r.asking;
        r.asking = .no;
        r.first = null;
        r.asked = true;
        if (why == .place) {
            r.scan.x = if (at != null and at.?[1] < r.w) at.?[1] - 1 else null;
            return r.render();
        }
        // Nothing has moved since riff last set things out, so they can be
        // drawn. Anything else is a resize nobody announced.
        const same = if (size) |sz| sz[0] == r.h and sz[1] == r.w else true;
        const still = r.spot == null or at == null or std.mem.eql(usize, &r.spot.?, &at.?);
        if (why == .check and same and still) return r.render();
        if (why == .gate and same) {
            r.clear = true;
            return;
        }
        try r.resized(at, size);
    }

    /// Rebuild after a resize, around where the command's cursor now is.
    /// Everything below it is stale live rows, wherever reflow put them.
    fn resized(r: *Riff, at: ?[2]usize, size: ?[2]usize) !void {
        r.measure(size);
        const col = if (at) |a| a[1] else 1;
        // The answer says how far along its line the command is, which is
        // what the count needs. At the last column it cannot say whether a
        // wrap is waiting, so there the count stays unknown.
        r.scan.x = if (at != null and col < r.w) col - 1 else null;
        r.forget();
        const l = r.live();
        const bottom = r.h - l;
        try r.wipe();
        // The cursor is only ever moved from where it is, never to a row
        // riff worked out: by the time this is read the terminal may have
        // changed again, and a cursor put on the wrong row is the output
        // erased from there down next time. Down the live rows and back up
        // makes exactly the room they need, whatever the size now is.
        for (0..l) |_| try r.out.writeAll("\x1bD");
        if (l > 0) try r.out.print("\x1b[{d}A", .{l});
        try r.out.print("\x1b7\x1b[1;{d}r\x1b8", .{bottom});
        try r.out.flush();
        r.spot = .{ @min(if (at) |a| a[0] else bottom, bottom), col };
        r.resizing = .now(r.ctx.io, .awake);
        r.shaken = r.resizing;
    }

    // ------------------------------------------------------------ editing

    /// Take what was typed, and say how much of it was read: a sequence the
    /// bytes end part way through is left for when the rest has come.
    fn keys(r: *Riff, bytes: []const u8) !usize {
        var i: usize = 0;
        while (i < bytes.len) : (i += 1) switch (bytes[i]) {
            0x1b => {
                const start = i;
                // Left only when it is plainly the start of one. A lone
                // escape is a key, except in a paste where nothing is.
                const left = if (bytes.len - start > keep or (!r.pasting and bytes.len - start < 2)) bytes.len else start;
                i += 1;
                if (i >= bytes.len) return left;
                // Alt-Enter, which is a new line whatever Enter is.
                if (bytes[i] == '\r' or bytes[i] == '\n') {
                    try r.insert("\n");
                    continue;
                }
                if (bytes[i] != '[' and bytes[i] != 'O') continue;
                const csi = bytes[i] == '[';
                const from = i + 1;
                while (i + 1 < bytes.len and (bytes[i + 1] < 0x40 or bytes[i + 1] > 0x7e)) i += 1;
                i += 1;
                if (i >= bytes.len) return left;
                var params = std.mem.splitScalar(u8, bytes[from..i], ';');
                const p1 = std.fmt.parseInt(usize, params.first(), 10) catch 1;
                const p2 = std.fmt.parseInt(usize, params.next() orelse "", 10) catch 1;
                switch (bytes[i]) {
                    'A' => try r.vertical(true),
                    'B' => try r.vertical(false),
                    'C' => r.at = r.after(),
                    'D' => r.at = r.before(),
                    'H' => r.at = r.lineStart(),
                    'F' => r.at = r.lineEnd(),
                    'I' => if (csi) {
                        r.focused = true;
                    },
                    'O' => if (csi) {
                        r.focused = false;
                    },
                    '~' => switch (p1) {
                        1, 7 => r.at = r.lineStart(),
                        4, 8 => r.at = r.lineEnd(),
                        3 => r.cut(r.at, r.after()),
                        5, 6 => for (0..r.e) |_| try r.vertical(p1 == 5),
                        200, 201 => r.pasting = p1 == 200,
                        else => {},
                    },
                    'R' => if (r.asking == .place) {
                        try r.answered(.{ p1, p2 }, null);
                    } else if (r.asking != .no) {
                        if (r.first) |at| try r.answered(at, .{ p1, p2 }) else r.first = .{ p1, p2 };
                    },
                    else => {},
                }
            },
            // Enter sends. In a paste it is a line's end, and so is the pair
            // some text ends its lines with.
            '\r' => if (r.pasting) try r.insert("\n") else try r.send(),
            '\n' => if (!r.pasting or i == 0 or bytes[i - 1] != '\r') try r.insert("\n"),
            0x7f, 0x08 => if (!r.pasting) r.cut(r.before(), r.at),
            0x03 => if (r.pasting) {} else if (r.child) |c| {
                posix.kill(-c.id.?, .INT) catch {};
                // A continuous run is interrupted and carries on, so there
                // is no ending to wait for.
                r.stopping = !r.continuous;
            } else {
                quit = true;
            },
            0x04 => if (r.pasting) {} else if (r.buf.items.len > 0) try r.send() else if (r.child == null) {
                quit = true;
            } else if (r.continuous) r.hang(),
            else => |b| if (b >= 0x20 or b == '\t') try r.insert(&.{b}),
        };
        return bytes.len;
    }

    fn insert(r: *Riff, text: []const u8) !void {
        try r.buf.insertSlice(r.ctx.arena, r.at, text);
        r.at += text.len;
    }

    fn cut(r: *Riff, from: usize, to: usize) void {
        r.buf.replaceRangeAssumeCapacity(from, to - from, &.{});
        r.at = from;
    }

    fn before(r: *const Riff) usize {
        var i = r.at -| 1;
        while (i > 0 and r.buf.items[i] & 0xc0 == 0x80) i -= 1;
        return i;
    }

    fn after(r: *const Riff) usize {
        if (r.at >= r.buf.items.len) return r.at;
        return r.at + glyph(r.buf.items, r.at).len;
    }

    fn lineStart(r: *const Riff) usize {
        const nl = std.mem.lastIndexOfScalar(u8, r.buf.items[0..r.at], '\n') orelse return 0;
        return nl + 1;
    }

    fn lineEnd(r: *const Riff) usize {
        return std.mem.indexOfScalarPos(u8, r.buf.items, r.at, '\n') orelse r.buf.items.len;
    }

    /// Up or down a visual row, keeping the column.
    fn vertical(r: *Riff, up: bool) !void {
        const cur = try r.layout();
        if (if (up) cur.row == 0 else cur.row + 1 == r.rows.items.len) return;
        const k = if (up) cur.row - 1 else cur.row + 1;
        const text = r.row(k);
        var col: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const c = glyph(text, i);
            if (col + width(c.cp) > cur.col) break;
            col += width(c.cp);
            i += c.len;
        }
        r.at = r.rows.items[k] + i;
    }

    fn send(r: *Riff) !void {
        if (r.buf.items.len == 0) return;
        try r.queue.append(r.ctx.arena, try r.ctx.arena.dupe(u8, r.buf.items));
        r.sent = true;
        r.cut(0, r.buf.items.len);
    }
};

/// Just enough of a terminal's parser to know where a sequence ends, so riff
/// writes only between them, and to hold back the few that would take the
/// terminal away from it: private modes, the scroll region, and resets.
///
/// It also counts cells along the line. A character written into the last
/// column leaves the terminal waiting to wrap, and not every terminal keeps
/// that through a cursor save and restore, so riff has to know to put it back.
const Scanner = struct {
    state: enum { text, esc, csi, string, string_esc } = .text,
    seq: [32]u8 = undefined,
    n: usize = 0,
    /// The character arriving, and the bytes it is still owed.
    ch: [4]u8 = undefined,
    ch_n: usize = 0,
    owed: u8 = 0,
    /// The terminal's width, and the cells written on this line. Null once
    /// the command has moved the cursor itself, until its next line.
    w: usize = 0,
    x: ?usize = 0,
    /// The last character that took a cell, with whatever joined onto it.
    last: [16]u8 = undefined,
    last_n: usize = 0,
    last_cells: usize = 0,
    /// Whether the command has sent anything that could reach beyond its own
    /// line: a cursor move or an erase.
    strayed: bool = false,

    fn ground(s: *const Scanner) bool {
        return s.state == .text and s.owed == 0;
    }

    /// Restore the command's cursor. A wrap that was waiting is put back by
    /// writing the last character over itself, which leaves every terminal
    /// in the same state whether or not it kept it.
    fn restore(s: *const Scanner, out: *std.Io.Writer) !void {
        try out.writeAll("\x1b8");
        if (s.w > 0 and s.x == s.w)
            try out.print("\x1b[{d}G{s}", .{ s.w + 1 - s.last_cells, s.last[0..s.last_n] });
    }

    fn feed(s: *Scanner, out: *std.Io.Writer, bytes: []const u8) !void {
        for (bytes) |b| switch (s.state) {
            .text => if (b == 0x1b) {
                s.state = .esc;
                s.n = 0;
                s.hold(b);
            } else {
                try out.writeByte(b);
                if (b & 0xc0 != 0x80) {
                    s.ch_n = 0;
                    s.owed = if (b >= 0xf0) 4 else if (b >= 0xe0) 3 else if (b >= 0xc0) 2 else 1;
                }
                if (s.ch_n < s.ch.len) s.ch[s.ch_n] = b;
                s.ch_n += 1;
                s.owed -|= 1;
                if (s.owed == 0 and s.ch_n <= s.ch.len) s.wrote();
            },
            .esc, .csi => {
                s.hold(b);
                const done = if (s.state == .csi) b >= 0x40 and b <= 0x7e else b < 0x20 or b > 0x2f;
                if (s.state == .esc and b == '[') {
                    s.state = .csi;
                } else if (done or s.n == s.seq.len) {
                    const string = s.state == .esc and std.mem.indexOfScalar(u8, "]P^_X", b) != null;
                    if (!s.taken()) {
                        try out.writeAll(s.seq[0..s.n]);
                        // Colour and erasing leave the cursor where it was.
                        const still = if (s.state == .csi) std.mem.indexOfScalar(u8, "mKJ", b) != null else string or s.n > 2;
                        if (!still) s.x = null;
                        if (s.state == .csi and b != 'm' and b != 'K') s.strayed = true;
                    }
                    s.state = if (string) .string else .text;
                }
            },
            .string => {
                try out.writeByte(b);
                if (b == 0x07) s.state = .text;
                if (b == 0x1b) s.state = .string_esc;
            },
            .string_esc => {
                try out.writeByte(b);
                s.state = if (b == '\\') .text else .string;
            },
        };
    }

    fn hold(s: *Scanner, b: u8) void {
        s.seq[s.n] = b;
        s.n += 1;
    }

    /// Count a character that has been written whole.
    fn wrote(s: *Scanner) void {
        const c = glyph(s.ch[0..s.ch_n], 0);
        if (c.cp == '\n' or c.cp == '\r') s.x = 0;
        const x = s.x orelse return;
        const cells = width(c.cp);
        if (c.cp == 0x08) {
            s.x = x -| 1;
        } else if (c.cp == '\t') {
            s.x = @min(s.w -| 1, (x / 8 + 1) * 8);
        } else if (c.cp < 0x20) {
            return;
        } else if (cells > 0) {
            s.x = (if (x + cells > s.w) 0 else x) + cells;
            @memcpy(s.last[0..s.ch_n], s.ch[0..s.ch_n]);
            s.last_n = s.ch_n;
            s.last_cells = cells;
        } else if (s.last_n + s.ch_n <= s.last.len) {
            @memcpy(s.last[s.last_n..][0..s.ch_n], s.ch[0..s.ch_n]);
            s.last_n += s.ch_n;
        } else s.x = null;
    }

    /// Whether the sequence held is one the command may not send.
    fn taken(s: *const Scanner) bool {
        const seq = s.seq[0..s.n];
        if (seq.len == 2) return seq[1] == 'c';
        if (s.state != .csi) return false;
        const body = seq[2 .. seq.len - 1];
        if (body.len > 0 and std.mem.indexOfScalar(u8, "?<=>", body[0]) != null) return true;
        return switch (seq[seq.len - 1]) {
            'r' => true,
            'p' => std.mem.indexOfScalar(u8, body, '!') != null,
            'J' => std.mem.eql(u8, body, "3"),
            else => false,
        };
    }
};

const Glyph = struct { cp: u21, len: usize };

/// The character at `i`, or one byte of whatever is there instead.
fn glyph(text: []const u8, i: usize) Glyph {
    const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
    if (i + len > text.len) return .{ .cp = 0xfffd, .len = 1 };
    const cp = std.unicode.utf8Decode(text[i..][0..len]) catch return .{ .cp = 0xfffd, .len = 1 };
    return .{ .cp = cp, .len = len };
}

/// How many cells text takes, by the same count as `put`.
fn span(text: []const u8) usize {
    var discard: std.Io.Writer.Discarding = .init(&.{});
    return put(&discard.writer, text, std.math.maxInt(usize)) catch 0;
}

/// Write text into at most `max` cells and say how many it took. Escape
/// sequences are left out, a control character is a space, and text that
/// does not fit ends in an ellipsis.
fn put(o: *std.Io.Writer, text: []const u8, max: usize) !usize {
    var used: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b) {
            i += 1;
            if (i < text.len and text[i] == '[') {
                i += 1;
                while (i < text.len and (text[i] < 0x40 or text[i] > 0x7e)) i += 1;
            }
            i += 1;
            continue;
        }
        const c = glyph(text, i);
        const cells = width(c.cp);
        if (used + cells > max or (used + cells == max and i + c.len < text.len)) {
            if (used == max) return used;
            try o.writeAll("…");
            return used + 1;
        }
        if (c.cp < 0x20) try o.writeByte(' ') else try o.writeAll(text[i..][0..c.len]);
        used += cells;
        i += c.len;
    }
    return used;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn scanned(comptime chunks: []const []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    errdefer out.deinit();
    var s: Scanner = .{};
    for (chunks) |c| try s.feed(&out.writer, c);
    try testing.expect(s.ground());
    return out.toOwnedSlice();
}

test "what a command says passes, and what would take the terminal does not" {
    const kept = try scanned(&.{"a\x1b[31mb\x1b[0m\x1b]8;;http://x\x1b\\c\x1b(B\x1b[2K\x1b[5;1H"});
    defer testing.allocator.free(kept);
    try testing.expectEqualStrings("a\x1b[31mb\x1b[0m\x1b]8;;http://x\x1b\\c\x1b(B\x1b[2K\x1b[5;1H", kept);

    const dropped = try scanned(&.{"a\x1b[?1049h\x1b[1;5r\x1bc\x1b[!p\x1b[3J\x1b[>1ub"});
    defer testing.allocator.free(dropped);
    try testing.expectEqualStrings("ab", dropped);
}

test "a sequence split across reads is still one sequence" {
    const got = try scanned(&.{ "a\x1b[?10", "49hb\x1b[3", "1mc" });
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("ab\x1b[31mc", got);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var s: Scanner = .{};
    try s.feed(&out.writer, "\xf0\x9f");
    try testing.expect(!s.ground());
    try s.feed(&out.writer, "\xa7\xa0");
    try testing.expect(s.ground());
}

test "the status line is the last line said, cut to fit" {
    var r: Riff = .{ .ctx = undefined, .out = undefined, .cmd = &.{} };
    r.note("one\ntwo\rthree\n");
    try testing.expectEqualStrings("three", r.status[0..r.status_len]);
    // What riff says itself gives way to the next thing the command says.
    r.note(working);
    r.note("thinking");
    try testing.expectEqualStrings("thinking", r.status[0..r.status_len]);

    // The lines before it are kept, newest first, for the rows above. While
    // riff has the bottom line, what the command said last is one up.
    try testing.expectEqualStrings(waiting_empty, r.above(0));
    try testing.expectEqualStrings("thinking", r.above(1));
    try testing.expectEqualStrings("Dispatched...", r.above(2));
    try testing.expectEqualStrings("three", r.above(3));
    try testing.expectEqualStrings("two", r.above(4));
    try testing.expectEqualStrings("", r.above(most_bars + 2));

    // As many status lines as were asked for, while the editor keeps a row.
    r.s = 3;
    r.h = 24;
    try testing.expectEqual(@as(usize, 3), r.bars());
    try testing.expectEqual(@as(usize, 9), r.most());
    r.h = 6;
    try testing.expectEqual(@as(usize, 2), r.bars());
    r.h = 3;
    try testing.expectEqual(@as(usize, 1), r.bars());

    // With nothing running the line is riff's, and follows the editor.
    try testing.expectEqualStrings(waiting_empty, r.says());
    try r.buf.appendSlice(testing.allocator, "hi");
    defer r.buf.deinit(testing.allocator);
    try testing.expectEqualStrings(waiting_written, r.says());
    // With a message due to run it is the command's, until it is stopped.
    try r.queue.append(testing.allocator, "hi");
    defer r.queue.deinit(testing.allocator);
    try testing.expectEqualStrings("thinking", r.says());
    r.stopping = true;
    try testing.expectEqualStrings(stopping, r.says());

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try testing.expectEqual(@as(usize, 5), try put(&out.writer, "\x1b[1m💭 thinking", 5));
    try testing.expectEqualStrings("💭 t…", out.written());
}

test "a stopped child changes the waiting line as the editor changes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var out: std.Io.Writer.Allocating = .init(arena);
    var ctx: Ctx = undefined;
    ctx.arena = arena;
    var r: Riff = .{ .ctx = ctx, .out = &out.writer, .cmd = &.{}, .h = 3, .w = 100 };
    defer r.line.deinit();

    r.stopped = 7;
    try r.render();
    try testing.expect(std.mem.indexOf(u8, r.drawn.items[0].items, "Stopped(7) and waiting " ++ empty_hint) != null);

    try r.buf.appendSlice(arena, "next");
    try r.render();
    try testing.expect(std.mem.indexOf(u8, r.drawn.items[0].items, "Stopped(7) and waiting " ++ written_hint) != null);

    r.stopped = @intFromEnum(posix.SIG.TERM);
    try r.render();
    try testing.expect(std.mem.indexOf(u8, r.drawn.items[0].items, "Stopped(15) and waiting " ++ written_hint) != null);

    r.stopped = null;
    try r.render();
    try testing.expect(std.mem.indexOf(u8, r.drawn.items[0].items, waiting_written) != null);
}

test "a line that leads with stats updates only the panel" {
    var r: Riff = .{ .ctx = undefined, .out = undefined, .cmd = &.{} };
    r.note("one\n::stats::\u{2725}16K\u{2587}19::16000 in\n");
    try testing.expectEqualStrings("\u{2725}16K\u{2587}19", r.panel[0..r.panel_len]);
    try testing.expectEqualStrings("one", r.status[0..r.status_len]);
    try testing.expectEqual(@as(usize, 0), r.older_len[0]);
    try testing.expectEqual(@as(usize, 7), span(r.panel[0..r.panel_len]));

    // A panel alone is no status line, and it stays when lines follow.
    r.note("::stats::2K_3\n");
    try testing.expectEqualStrings("2K_3", r.panel[0..r.panel_len]);
    try testing.expectEqualStrings("one", r.status[0..r.status_len]);
    try testing.expectEqual(@as(usize, 0), r.older_len[0]);
    r.note("::stats::short:");
    r.note(":noisy detail");
    r.note(" and more\r\n");
    try testing.expectEqualStrings("short", r.panel[0..r.panel_len]);
    try testing.expectEqualStrings("one", r.status[0..r.status_len]);
    try testing.expectEqual(@as(usize, 0), r.older_len[0]);
    r.note("a::b\n");
    try testing.expectEqualStrings("a::b", r.status[0..r.status_len]);
    try testing.expectEqualStrings("short", r.panel[0..r.panel_len]);
}

test "a message wraps into rows, and the cursor is found on one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var ctx: Ctx = undefined;
    ctx.arena = a.allocator();
    var r: Riff = .{ .ctx = ctx, .out = undefined, .cmd = &.{}, .w = 6 };
    try r.insert("abcdef\n日本語");
    const cur = try r.layout();
    try testing.expectEqual(@as(usize, 4), r.rows.items.len);
    try testing.expectEqualStrings("abcd", r.row(0));
    try testing.expectEqualStrings("ef", r.row(1));
    try testing.expectEqualStrings("日本", r.row(2));
    try testing.expectEqual(@as(usize, 3), cur.row);
    try testing.expectEqual(@as(usize, 2), cur.col);

    try r.vertical(true);
    try testing.expectEqualStrings("日", r.buf.items[r.rows.items[2]..r.at]);
}

test "Enter sends, and a paste keeps its lines" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var ctx: Ctx = undefined;
    ctx.arena = a.allocator();
    var r: Riff = .{ .ctx = ctx, .out = undefined, .cmd = &.{} };

    // Ctrl-j and Alt-Enter are new lines, and Enter is the message gone.
    _ = try r.keys("a\nb\x1b\rc");
    try testing.expectEqualStrings("a\nb\nc", r.buf.items);
    _ = try r.keys("\r");
    try testing.expectEqual(@as(usize, 0), r.buf.items.len);
    try testing.expectEqualStrings("a\nb\nc", r.queue.items[0]);

    // In a paste nothing is a key, and a line ending in both is one line.
    _ = try r.keys("\x1b[200~one\rtwo\r\nthree\x03\x04\x1b[201~");
    try testing.expectEqualStrings("one\ntwo\nthree", r.buf.items);
    try testing.expectEqual(@as(usize, 1), r.queue.items.len);

    // A paste's end cut in two by a read is waited for, not typed.
    r.cut(0, r.buf.items.len);
    const whole = "\x1b[200~x\x1b[20";
    try testing.expectEqual(whole.len - 4, try r.keys(whole));
    try testing.expect(r.pasting);
    _ = try r.keys("\x1b[201~");
    try testing.expect(!r.pasting);
    // A lone escape is a key that does nothing, and is not waited on.
    try testing.expectEqual(@as(usize, 1), try r.keys("\x1b"));
}
