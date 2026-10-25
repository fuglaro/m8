//! `cast` — a ledger replayed as riff would have shown it, as an animated SVG.
//!
//! The picture is for a README, where an image is all that runs: no script,
//! only the CSS inside the SVG. So nothing is drawn frame by frame. Every line
//! is written once, where it ends up, and one clock runs the whole picture: a
//! number counting the milliseconds of a play, back to nought when it ends.
//! Each line reads that clock and its own few numbers to decide whether it
//! shows and how much of it: whole, or clipped to the words or characters
//! that have arrived. Scrolling is one stepped transform on everything above
//! the editor. That is what keeps a whole session to a few kilobytes.
//!
//! The text is m8's own rendering, the same bytes `render` writes, read back
//! out of its colour codes. So the look follows m8 rather than a copy of it.
//! Everything is placed on a cell grid, and every run of text is held to its
//! cells' width, because the viewer's monospace font is not ours to choose
//! and an emoji's width is a guess no two fonts agree on. Block and box
//! characters are drawn as rectangles, so they meet their neighbours the way
//! they do in a terminal whatever the font.
//!
//! It streams: one record is held at a time, and what has to come after every
//! line — the editor, the status bar and the stylesheet — is small.
//!
//! Riff shows nothing until something is sent, so records before the first 🙋
//! are left out. A 🙋 is typed into the editor and then sent, and appears in
//! the scrollback as riff's command writes it back.
//!
//! With `--no-riff` it is a plain terminal instead: each 🙋 is typed at a
//! prompt as the command that says it to the address, and what follows is
//! what that command writes, which is everything after the 🙋 and not the 🙋
//! itself.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const highlight = @import("../m8/highlight.zig");
const sigil = @import("../m8/sigil.zig");
const config = @import("../config.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "cast",
    .summary = "replay a ledger as riff would show it, as an animated SVG",
    // Read as it arrives, a record at a time.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 cast [--size COLSxROWS] [--speed SPEEDS] [--no-riff ADDRESS]
        \\
        \\Reads a ledger on stdin and writes an SVG that plays it the way riff
        \\would have shown it: each 🙋 typed into the editor and sent, and
        \\everything after it arriving above. It holds the last frame for 3
        \\seconds and plays again. CSS is all it uses, so it plays wherever an
        \\image does, a README included.
        \\
        \\  m8 ref :games/zork | m8 encode | m8 cast >zork.svg
        \\
        \\--size is the terminal, 80x24 unless said.
        \\
        \\--speed is how fast each sigil arrives: a number of milliseconds and
        \\what it is per, c for a character, w a word, l a line, b a block,
        \\and then if said the milliseconds paused before it starts. The first
        \\is for every sigil not named, and a sigil names its own:
        \\
        \\  m8 cast --speed 40l,🤖60w,💭0b,🙋50c1000
        \\
        \\Unless named, 🙋 is typed at 50c after 600 ms, and everything else is
        \\30l, after 200 ms when it answers a 🙋 and straight on otherwise. A
        \\sigil may be its shortcode instead, as in robot60w.
        \\
        \\--no-riff ADDRESS plays it at a plain terminal instead, each 🙋 typed
        \\at a >>> prompt as the command that says it:
        \\
        \\  >>> m8 :games/zork -- 'open mailbox'
        \\
        \\A message with a quote or a line break in it, or too wide for one
        \\line, is said as a heredoc, m8 ADDRESS <<'^^', and the answer is what
        \\that command writes.
        \\
        \\Records before the first 🙋 are left out, as riff shows nothing
        \\until something is sent.
        \\
    );
}

/// What a pace is per.
const Unit = enum { char, word, line, block };

/// How long each unit of a record takes to arrive, and the pause before it
/// starts when one is said.
const Pace = struct { ms: u64, unit: Unit, pause: ?u64 = null };

const Speeds = struct {
    default: Pace = .{ .ms = 30, .unit = .line },
    each: std.EnumArray(doc.Sigil, ?Pace) = .initFill(null),

    /// 🙋 is typed unless it is named, whatever the default says.
    fn of(s: *const Speeds, sig: doc.Sigil) Pace {
        return s.each.get(sig) orelse if (sig == .user) typing else s.default;
    }
};

const typing: Pace = .{ .ms = 50, .unit = .char };

fn parseSpeeds(text: []const u8) !Speeds {
    var s: Speeds = .{};
    var it = std.mem.splitScalar(u8, text, ',');
    var first = true;
    while (it.next()) |raw| : (first = false) {
        const item = std.mem.trim(u8, raw, " ");
        var at: usize = 0;
        var named: ?doc.Sigil = null;
        if (sigil.match(.m8, item)) |m| {
            named = m.sigil;
            at = m.len;
        } else {
            while (at < item.len and (std.ascii.isAlphabetic(item[at]) or item[at] == '_')) at += 1;
            if (at > 0) named = sigil.named(item[0..at]) orelse return error.BadSpeed;
        }
        if (named == null and !first) return error.BadSpeed;
        const pace = try parsePace(item[at..]);
        if (named) |sig| s.each.set(sig, pace) else s.default = pace;
    }
    return s;
}

fn parsePace(text: []const u8) !Pace {
    const at = std.mem.indexOfAny(u8, text, "cwlb") orelse return error.BadSpeed;
    const unit: Unit = switch (text[at]) {
        'c' => .char,
        'w' => .word,
        'l' => .line,
        else => .block,
    };
    return .{
        .ms = std.fmt.parseInt(u64, text[0..at], 10) catch return error.BadSpeed,
        .unit = unit,
        .pause = if (at + 1 == text.len) null else std.fmt.parseInt(u64, text[at + 1 ..], 10) catch return error.BadSpeed,
    };
}

// ---------------------------------------------------------------- the grid

/// A cell, in pixels, at a font size whose monospace advance is 0.6em. A row
/// is as tall as the font's own line, as a terminal's is.
const cw = 9;
const lh = 18;
const font_size = 15;
/// Where a row's baseline sits within it.
const baseline = 14;
const pad = 10;

const fg = "#d0d0d0";
const bg = "#1c1c1c";
/// Riff's grey, 245 of the 256 colours.
const grey = "#8a8a8a";

/// The pause before a message is typed unless one is said, and between
/// typing it and sending.
const think = 600;
const enter = 300;
/// How long a command takes to start answering unless said, and how long the
/// last frame is held before the picture plays again.
const latency = 200;
const hold = 3000;

/// What riff's status line says, as riff says it.
const waiting_empty = "Waiting (ctrl-c:cancel,ctrl-d:exit)...";
const waiting_written = "Waiting (enter:dispatch,alt-enter/ctrl-j:newline)...";
const working = "Dispatched...";

/// The plain terminal's prompt, and the word that ends a heredoc there.
const prompt = ">>> ";
const heredoc = "^^";

fn run(ctx: Ctx) !u8 {
    var cols: usize = 80;
    var rows: usize = 24;
    var speeds: Speeds = .{};
    var address: ?[]const u8 = null;
    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        const value = if (i + 1 < ctx.args.len) ctx.args[i + 1] else "";
        if (std.mem.eql(u8, arg, "--size") and value.len > 0) {
            i += 1;
            const x = std.mem.indexOfScalar(u8, value, 'x') orelse return bad(ctx, "--size is COLSxROWS, as in 80x24");
            cols = std.fmt.parseInt(usize, value[0..x], 10) catch return bad(ctx, "--size is COLSxROWS, as in 80x24");
            rows = std.fmt.parseInt(usize, value[x + 1 ..], 10) catch return bad(ctx, "--size is COLSxROWS, as in 80x24");
            if (cols < 8 or rows < 4) return bad(ctx, "--size is at least 8x4");
        } else if (std.mem.eql(u8, arg, "--speed") and value.len > 0) {
            i += 1;
            speeds = parseSpeeds(value) catch
                return bad(ctx, "--speed is a default and then sigils, each a number of ms, c, w, l or b, and a pause if said, as in 40l,🤖60w,🙋50c1000");
        } else if (std.mem.eql(u8, arg, "--no-riff") and value.len > 0) {
            i += 1;
            address = value;
        } else {
            try ctx.err.print("m8 cast: '{s}' is not something it takes; see m8 cast --help\n", .{arg});
            return 1;
        }
    }

    const look: doc.Look = .{ .width = cols, .palette = try config.highlights(ctx.arena, ctx.io, ctx.env) };
    var c: Cast = try .init(ctx.arena, ctx.out, look, speeds, cols, rows);
    c.address = address;
    try c.open();

    var diag: doc.Diagnostic = .{};
    var p: doc.Parser = .{ .arena = ctx.arena, .diag = &diag };
    var buf: [16 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &buf);
    const r = &in.interface;
    while (true) {
        r.fillMore() catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        p.feed(r.buffered(), &c) catch |e| return failed(ctx, &diag, e);
        r.tossBuffered();
    }
    p.finish(&c) catch |e| return failed(ctx, &diag, e);
    try c.close();
    try ctx.out.flush();
    return 0;
}

fn bad(ctx: Ctx, why: []const u8) !u8 {
    try ctx.err.print("m8 cast: {s}\n", .{why});
    return 1;
}

fn failed(ctx: Ctx, diag: *const doc.Diagnostic, e: anyerror) anyerror {
    if (diag.detail.len == 0) return e;
    try ctx.err.print("m8 cast: line {d}: {s}\n", .{ diag.line, diag.detail });
    return error.Said;
}

// ---------------------------------------------------------------- the clock

/// The stylesheet's fixed part. `--t` is the clock, in milliseconds, and an
/// element is told when on it with its own properties:
///
/// * `.a` shows from `--a`, and `.g` from `--a` until `--b`.
/// * `.c` shows `--n` cells, one more each `--d` from `--s`.
/// * `.m` moves along the same cells at the same times: the cursor.
const clock =
    "@property --t{syntax:'<number>';inherits:true;initial-value:0}" ++
    ".a{opacity:clamp(0,calc(var(--t) - var(--a) + 1),1)}" ++
    ".g{opacity:calc(clamp(0,calc(var(--t) - var(--a) + 1),1) * clamp(0,calc(var(--b) - var(--t)),1))}" ++
    ".c{clip-path:inset(0 calc(100% - 100% * " ++ cells_typed ++ " / var(--n)) 0 0)}" ++
    std.fmt.comptimePrint(".m{{transform:translateX(calc({s} * {d}px))}}", .{ cells_typed, cw });

const cells_typed = "round(down,clamp(0,(var(--t) - var(--s)) / var(--d),var(--n)),1)";

// ---------------------------------------------------------------- casting

const Cast = struct {
    arena: std.mem.Allocator,
    out: *std.Io.Writer,
    look: doc.Look,
    speeds: Speeds,
    cols: usize,
    rows: usize,
    /// The address said to at a plain terminal, or riff's when there is none.
    address: ?[]const u8 = null,

    /// The record being read: rendered, and as it was said.
    rendered: std.Io.Writer.Allocating,
    said: std.ArrayList(u8) = .empty,
    body: ?doc.ContentWriter = null,
    sig: doc.Sigil = .user,
    lines: usize = 0,

    /// Whether the first 🙋 has been reached.
    started: bool = false,
    /// The time the next thing arrives at, and the scrollback row it takes.
    t: u64 = 0,
    row: usize = 0,

    /// What comes after the scrollback: the editor, status and cursor
    /// elements, and the styles the text has used.
    later: std.Io.Writer.Allocating,
    styles: std.ArrayList(Sgr) = .empty,
    /// The scrollback's offset in rows, and when it last changed.
    scrolls: std.ArrayList([2]u64) = .empty,
    scrolled: u64 = 0,

    /// The status line being said, and since when.
    status: []const u8 = waiting_empty,
    status_from: u64 = 0,
    /// When the editor was last emptied, which is when its cursor went home,
    /// and whether nothing has arrived since.
    sent: u64 = 0,
    answering: bool = false,

    fn init(arena: std.mem.Allocator, out: *std.Io.Writer, look: doc.Look, speeds: Speeds, cols: usize, rows: usize) !Cast {
        return .{
            .arena = arena,
            .out = out,
            .look = look,
            .speeds = speeds,
            .cols = cols,
            .rows = rows,
            .rendered = .init(arena),
            .later = .init(arena),
        };
    }

    /// The left margin riff keeps, the editor's edge sitting in its last cell.
    fn margin(c: *const Cast) usize {
        return if (c.cols >= 24) 4 else 0;
    }

    /// Rows above the status bar and editor, which a plain terminal has none
    /// of.
    fn region(c: *const Cast) usize {
        return if (c.address == null) c.rows - 2 else c.rows;
    }

    fn open(c: *Cast) !void {
        const w = c.cols * cw + 2 * pad;
        const h = c.rows * lh + 2 * pad;
        try c.out.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,'DejaVu Sans Mono',monospace" font-size="{d}" fill="{s}">
            \\<rect width="100%" height="100%" rx="6" fill="{s}"/>
            \\<clipPath id="r"><rect y="{d}" width="{d}" height="{d}"/></clipPath>
            \\<g clip-path="url(#r)"><g class="s">
            \\
        , .{ w, h, w, h, font_size, fg, bg, pad, w, c.region() * lh });
    }

    pub fn begin(c: *Cast, s: doc.Sigil, value: []const u8) !void {
        c.rendered.clearRetainingCapacity();
        c.said.clearRetainingCapacity();
        c.body = try doc.ContentWriter.beginLooking(&c.rendered.writer, .m8, c.look, s, value);
        c.sig = s;
        c.lines = 0;
    }

    pub fn line(c: *Cast) !void {
        if (c.lines > 0) {
            try c.body.?.write("\n");
            try c.said.append(c.arena, '\n');
        }
        c.lines += 1;
    }

    pub fn text(c: *Cast, bytes: []const u8) !void {
        try c.body.?.write(bytes);
        try c.said.appendSlice(c.arena, bytes);
    }

    pub fn end(c: *Cast) !void {
        if (c.lines > 0) try c.body.?.finish();
        c.body = null;
        const first = !c.started;
        if (first) {
            if (c.sig != .user) return;
            c.started = true;
        }

        const pace: Pace = if (c.sig == .user) .{ .ms = 0, .unit = .block } else c.speeds.of(c.sig);
        if (c.address) |address| {
            // The answer starts on the row after the command, and every record
            // and the next prompt after a blank one.
            if (!first and !c.answering) c.row += 1;
            if (c.sig == .user) {
                try c.command(address, c.said.items);
                c.answering = true;
                return;
            }
        } else if (!first) c.row += 1; // the blank line between records

        if (c.sig == .user)
            try c.typeIn(c.said.items)
        else
            c.t += pace.pause orelse if (c.answering) latency else 0;
        if (c.address != null and c.answering)
            try c.out.print("<rect class=\"g\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" style=\"--a:{d};--b:{d}\"/>\n", .{ pad, pad + c.row * lh, cw, lh, c.sent, c.t });
        c.answering = c.sig == .user;
        const from = c.t;
        var it = std.mem.splitScalar(u8, std.mem.trimEnd(u8, c.rendered.written(), "\n"), '\n');
        while (it.next()) |l| try c.place(l, pace);
        if (pace.unit == .block) c.t = from + pace.ms;
    }

    /// A message typed into the editor, and then sent.
    fn typeIn(c: *Cast, message: []const u8) !void {
        const pace = c.speeds.of(.user);
        try c.say(waiting_empty, c.t);
        c.t += pace.pause orelse think;
        try c.say(waiting_written, c.t);

        // The editor is one row here; a message of several reads on one.
        const flat = try c.arena.dupe(u8, message);
        for (flat) |*b| if (b.* == '\n') {
            b.* = ' ';
        };
        const m = c.margin();
        const y = pad + (c.rows - 1) * lh;
        const shown = try layout(c.arena, flat, c.cols - 2 * m, .{}, pace.unit == .word);
        const took = duration(pace, shown);
        const send = c.t + took + enter;

        const w = &c.later.writer;
        try w.writeAll("<g");
        const words = try group(w, pace, shown, c.t, send);
        try w.writeAll(">");
        try c.texts(w, shown, m, y, words);
        try w.writeAll("</g>\n");

        // The cursor: home since the last send, along the message as it is
        // typed, and gone once it is sent.
        try cursor(w, pad + m * cw, y, c.sent, send, pace, c.t, c.t + took, shown.cells());

        c.t = send;
        c.sent = send;
        try c.say(working, send);
    }

    /// A message typed at a plain terminal's prompt as the command that says
    /// it to the address, and entered.
    fn command(c: *Cast, address: []const u8, message: []const u8) !void {
        const pace = c.speeds.of(.user);
        const prompted = c.t;
        c.t += pace.pause orelse think;

        const one = try std.fmt.allocPrint(c.arena, "m8 {s} -- '{s}'", .{ address, message });
        const fits = std.mem.indexOfAny(u8, message, "'\n") == null and
            prompt.len + (try layout(c.arena, one, std.math.maxInt(usize), .{}, false)).last <= c.cols;
        const typed = if (fits) one else try std.fmt.allocPrint(c.arena, "m8 {s} <<'" ++ heredoc ++ "'\n{s}\n" ++ heredoc, .{ address, message });

        var lines = std.mem.splitScalar(u8, typed, '\n');
        var at: ?u64 = prompted;
        while (lines.next()) |l| : (at = null) {
            var rest = l;
            var col: usize = 0;
            var from = c.t;
            if (at) |p| {
                try c.reach(p);
                try c.out.print("<text x=\"{d}\" y=\"{d}\" textLength=\"{d}\" class=\"a\" style=\"--a:{d}\">&gt;&gt;&gt;</text>\n", .{ pad, pad + c.row * lh + baseline, 3 * cw, p });
                col = prompt.len;
                from = p;
            }
            // A line too wide for the terminal carries on in the next row,
            // the cursor with it.
            while (true) {
                const shown = try layout(c.arena, rest, c.cols - col, .{}, pace.unit == .word);
                const y = pad + c.row * lh;
                const start = c.t;
                try c.placeRow(shown, pace, col);
                const last = shown.rest == null and lines.peek() == null;
                try cursor(c.out, pad + col * cw, y, from, if (last) c.t + enter else c.t, pace, start, c.t, shown.cells());
                rest = rest[shown.rest orelse break ..];
                col = 0;
                from = c.t;
            }
        }
        c.t += enter;
        // Entered, the cursor waits on the next row for the answer.
        c.sent = c.t;
        try c.reach(c.t);
    }

    /// One rendered line into the scrollback, arriving at the pace given. A
    /// line wider than the terminal carries on in the next row, as a
    /// terminal wraps it.
    fn place(c: *Cast, rendered: []const u8, pace: Pace) !void {
        var rest = rendered;
        var style: Sgr = .{};
        while (true) {
            const shown = try layout(c.arena, rest, c.cols, style, pace.unit == .word);
            try c.placeRow(shown, pace, 0);
            rest = rest[shown.rest orelse break ..];
            style = shown.style;
        }
    }

    fn placeRow(c: *Cast, shown: Shown, pace: Pace, col: usize) !void {
        const at = c.t;
        const y = pad + c.row * lh;
        if (shown.runs.len > 0) {
            try c.out.writeAll("<g");
            const words = try group(c.out, pace, shown, at, null);
            try c.out.writeAll(">");
            try c.texts(c.out, shown, col, y, words);
            try c.out.writeAll("</g>\n");
        }
        try c.reach(at);
        c.row += 1;
        switch (pace.unit) {
            .block => {},
            .line => c.t += pace.ms,
            .word, .char => c.t += duration(pace, shown),
        }
    }

    /// The scrollback scrolled from `at` as far as the row being written.
    fn reach(c: *Cast, at: u64) !void {
        if (c.row < c.region()) return;
        const off = c.row + 1 - c.region();
        if (off == c.scrolled) return;
        try c.scrolls.append(c.arena, .{ at, off });
        c.scrolled = off;
    }

    /// Every run of a line, each held to the width of its cells, and every
    /// block character drawn.
    fn texts(c: *Cast, w: *std.Io.Writer, shown: Shown, col: usize, y: usize, words: ?Words) !void {
        for (shown.runs) |r| {
            const x = pad + (col + r.col) * cw;
            const said = try c.attrs(r, shown, words);
            if (r.block) |cp| {
                try drawShape(w, cp, x, y, said);
                continue;
            }
            try w.print("<text x=\"{d}\" y=\"{d}\"{s}", .{ x, y + baseline, said });
            if (r.cells > 1 and !r.wide) try w.print(" textLength=\"{d}\"", .{r.cells * cw});
            try w.writeAll(">");
            for (r.text) |b| switch (b) {
                '&' => try w.writeAll("&amp;"),
                '<' => try w.writeAll("&lt;"),
                '>' => try w.writeAll("&gt;"),
                else => try w.writeByte(b),
            };
            try w.writeAll("</text>");
        }
    }

    /// A run's style, and when its word arrives if words arrive one by one.
    fn attrs(c: *Cast, r: Run, shown: Shown, words: ?Words) ![]const u8 {
        const plain = std.meta.eql(r.style, Sgr{});
        if (words) |ws| {
            var j: usize = 0;
            for (shown.word_ends) |e| j += @intFromBool(e <= r.col);
            const at = ws.at + j * ws.ms;
            return if (plain)
                std.fmt.allocPrint(c.arena, " class=\"a\" style=\"--a:{d}\"", .{at})
            else
                std.fmt.allocPrint(c.arena, " class=\"a f{d}\" style=\"--a:{d}\"", .{ try c.class(r.style), at });
        }
        return if (plain) "" else std.fmt.allocPrint(c.arena, " class=\"f{d}\"", .{try c.class(r.style)});
    }

    fn class(c: *Cast, s: Sgr) !usize {
        for (c.styles.items, 0..) |known, k| if (std.meta.eql(known, s)) return k;
        try c.styles.append(c.arena, s);
        return c.styles.items.len - 1;
    }

    /// The status line says `what` from `at`, and what it said before stops.
    fn say(c: *Cast, what: []const u8, at: u64) !void {
        if (std.mem.eql(u8, what, c.status)) return;
        try c.statusText(c.status, c.status_from, at);
        c.status = what;
        c.status_from = at;
    }

    fn statusText(c: *Cast, what: []const u8, from: u64, until: ?u64) !void {
        const w = &c.later.writer;
        const m = c.margin();
        try w.print("<text x=\"{d}\" y=\"{d}\" fill=\"{s}\"", .{ pad + (m + 1) * cw, pad + (c.rows - 2) * lh + baseline, bg });
        if (until) |u|
            try w.print(" class=\"g\" style=\"--a:{d};--b:{d}\"", .{ from, u })
        else
            try w.print(" class=\"a\" style=\"--a:{d}\"", .{from});
        try w.print(">{s}</text>\n", .{what[0..@min(what.len, c.cols -| 2 * m + 1 -| 4)]});
    }

    fn close(c: *Cast) !void {
        const end_at = c.t + hold;
        const o = c.out;
        if (c.address != null) {
            // The next prompt, waiting.
            if (c.started) c.row += 1;
            const y = pad + c.row * lh;
            try o.print("<text x=\"{d}\" y=\"{d}\" textLength=\"{d}\" class=\"a\" style=\"--a:{d}\">&gt;&gt;&gt;</text>", .{ pad, y + baseline, 3 * cw, c.t });
            try o.print("<rect class=\"a\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" style=\"--a:{d}\"/>\n", .{ pad + prompt.len * cw, y, cw, lh, c.t });
            try c.placeRow(.{ .runs = &.{}, .first = 0, .last = 0, .word_ends = &.{} }, .{ .ms = 0, .unit = .block }, 0);
            try o.writeAll("</g></g>\n");
        } else try c.riffBelow();
        try c.stylesheet(end_at);
    }

    /// The status bar and the editor, below the scrollback.
    fn riffBelow(c: *Cast) !void {
        if (std.mem.eql(u8, c.status, working)) try c.say(waiting_empty, c.t);
        try c.statusText(c.status, c.status_from, null);
        const o = c.out;
        try o.writeAll("</g></g>\n");

        // The status bar and the editor's edge, as riff draws them.
        const m = c.margin();
        const inner = c.cols - (2 * m -| 1);
        const sy = pad + (c.rows - 2) * lh;
        const ey = pad + (c.rows - 1) * lh;
        const x0 = pad + (m -| 1) * cw;
        const in_grey = " fill=\"" ++ grey ++ "\"";
        if (inner >= 8) {
            try drawShape(o, 0x2582, x0, sy, in_grey);
            try drawShape(o, 0x259F, x0 + cw, sy, in_grey);
            try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}/>", .{ x0 + 2 * cw, sy, (inner - 4) * cw, lh, in_grey });
            try drawShape(o, 0x2599, x0 + (inner - 2) * cw, sy, in_grey);
            try drawShape(o, 0x2582, x0 + (inner - 1) * cw, sy, in_grey);
            try o.writeAll("\n");
        } else try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}/>\n", .{ x0, sy, inner * cw, lh, in_grey });
        try drawShape(o, 0x258F, x0, ey, in_grey);
        try o.writeAll("\n");
        try o.writeAll(c.later.written());
        // The cursor home after the last send, for as long as the picture holds.
        try o.print("<rect class=\"a\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" style=\"--a:{d}\"/>\n", .{ pad + m * cw, ey, cw, lh, c.sent });
    }

    fn stylesheet(c: *Cast, end_at: u64) !void {
        const o = c.out;
        try o.print("<style><![CDATA[{s}svg{{animation:t {d}ms linear infinite}}@keyframes t{{to{{--t:{d}}}}}", .{ clock, end_at, end_at });
        for (c.styles.items, 0..) |s, k| {
            try o.print(".f{d}{{", .{k});
            try s.css(o);
            try o.writeAll("}");
        }
        if (c.scrolls.items.len > 0) {
            try o.print(".s{{animation:s {d}ms step-end infinite}}@keyframes s{{0%{{transform:none}}", .{end_at});
            for (c.scrolls.items) |s| {
                const when = @as(f64, @floatFromInt(s[0])) * 100.0 / @as(f64, @floatFromInt(end_at));
                try o.print("{d:.3}%{{transform:translateY(-{d}px)}}", .{ when, s[1] * lh });
            }
            try o.print("100%{{transform:translateY(-{d}px)}}}}", .{c.scrolled * lh});
        }
        try o.writeAll("]]></style>\n</svg>\n");
    }
};

/// When the words of a line arrive, when they arrive one by one: the first
/// at `at`, and each after it `ms` later.
const Words = struct { at: u64, ms: u64 };

/// The attributes that bring a line in at `at` at the pace given, and take
/// it away again at `gone` when there is one. Words arriving one by one are
/// each told when, so those are handed back.
fn group(w: *std.Io.Writer, pace: Pace, shown: Shown, at: u64, gone: ?u64) !?Words {
    const typed = pace.unit == .char and pace.ms > 0 and shown.cells() > 0;
    const by_word = pace.unit == .word;
    const class = if (typed)
        (if (gone != null) "c g" else "c")
    else if (gone != null) "g" else if (by_word) "" else "a";
    if (class.len > 0) try w.print(" class=\"{s}\"", .{class});
    try w.print(" style=\"--a:{d}", .{at});
    if (gone) |g| try w.print(";--b:{d}", .{g});
    if (typed) try w.print(";--s:{d};--d:{d};--n:{d}", .{ at, pace.ms, shown.cells() });
    try w.writeAll("\"");
    return if (by_word) .{ .at = at, .ms = pace.ms } else null;
}

/// A cursor at `x`, there from `a` until `b`, moving along `n` cells as they
/// are typed from `start`, or to the end of them at `end` when they arrive
/// otherwise.
fn cursor(w: *std.Io.Writer, x: usize, y: usize, a: u64, b: u64, pace: Pace, start: u64, end: u64, n: usize) !void {
    const typed = pace.unit == .char and pace.ms > 0;
    try w.print("<rect class=\"g m\" x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" style=\"--a:{d};--b:{d};--s:{d};--d:{d};--n:{d}\"/>\n", .{
        x, y, cw, lh, a, b, if (typed) start else end, if (typed) pace.ms else 1, n,
    });
}

fn duration(pace: Pace, shown: Shown) u64 {
    return switch (pace.unit) {
        .char => pace.ms * shown.cells(),
        .word => pace.ms * shown.word_ends.len,
        .line, .block => 0,
    };
}

// ---------------------------------------------------------------- block characters

/// A block or box character as rectangles, in eighths of a cell, and how
/// solid it is in hundredths.
const Shape = struct {
    rects: [2][4]u8,
    n: usize = 1,
    alpha: u8 = 100,
};

fn shape(cp: u21) ?Shape {
    const ul = .{ 0, 0, 4, 4 };
    const ur = .{ 4, 0, 4, 4 };
    const ll = .{ 0, 4, 4, 4 };
    const lr = .{ 4, 4, 4, 4 };
    const top = .{ 0, 0, 8, 4 };
    const bottom = .{ 0, 4, 8, 4 };
    const Two = struct {
        fn of(a: [4]u8, b: [4]u8) Shape {
            return .{ .rects = .{ a, b }, .n = 2 };
        }
    };
    const one = struct {
        fn of(a: [4]u8) Shape {
            return .{ .rects = .{ a, a } };
        }
    }.of;
    return switch (cp) {
        0x2502 => one(.{ 4, 0, 1, 8 }), // │
        0x2580 => one(top),
        0x2581...0x2588 => one(.{ 0, @intCast(0x2588 - cp), 8, @intCast(cp - 0x2580) }),
        0x2589...0x258F => one(.{ 0, 0, @intCast(0x2590 - cp), 8 }),
        0x2590 => one(.{ 4, 0, 4, 8 }),
        0x2591...0x2593 => .{ .rects = .{ .{ 0, 0, 8, 8 }, .{ 0, 0, 8, 8 } }, .alpha = @intCast(25 * (cp - 0x2590)) },
        0x2594 => one(.{ 0, 0, 8, 1 }),
        0x2595 => one(.{ 7, 0, 1, 8 }),
        0x2596 => one(ll),
        0x2597 => one(lr),
        0x2598 => one(ul),
        0x2599 => Two.of(ul, bottom),
        0x259A => Two.of(ul, lr),
        0x259B => Two.of(top, ll),
        0x259C => Two.of(top, lr),
        0x259D => one(ur),
        0x259E => Two.of(ur, ll),
        0x259F => Two.of(ur, bottom),
        else => null,
    };
}

fn drawShape(w: *std.Io.Writer, cp: u21, x: usize, y: usize, attrs: []const u8) !void {
    const s = shape(cp).?;
    for (s.rects[0..s.n]) |q| {
        try w.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}", .{
            eighths(x, q[0], cw), eighths(y, q[1], lh), eighths(0, q[2], cw), eighths(0, q[3], lh), attrs,
        });
        if (s.alpha < 100) try w.print(" fill-opacity=\".{d}\"", .{s.alpha});
        try w.writeAll("/>");
    }
}

fn eighths(at: usize, n: u8, size: usize) f64 {
    return @as(f64, @floatFromInt(at)) + @as(f64, @floatFromInt(n * size)) / 8;
}

// ---------------------------------------------------------------- a line, laid out

/// A run of text that shares a style, starting at a cell. A block character
/// is a run of its own, drawn rather than written.
const Run = struct { col: usize, cells: usize, text: []const u8, style: Sgr, wide: bool, block: ?u21 = null };

const Shown = struct {
    runs: []const Run,
    /// The first and last cells anything is drawn in.
    first: usize,
    last: usize,
    /// The cell after each word's last character.
    word_ends: []const usize,
    /// Where what did not fit starts, and the style it starts in.
    rest: ?usize = null,
    style: Sgr = .{},

    fn cells(s: Shown) usize {
        return s.last - s.first;
    }
};

/// A rendered line read back into runs on the grid. Spaces are never drawn,
/// only stepped over, and a wide character is a run of its own so that a
/// font's idea of its width cannot push what follows it along. With `words`,
/// every word is a run of its own too, so each can arrive by itself.
fn layout(arena: std.mem.Allocator, line: []const u8, width: usize, from: Sgr, words: bool) !Shown {
    var runs: std.ArrayList(Run) = .empty;
    var ends: std.ArrayList(usize) = .empty;
    var style: Sgr = from;
    var rest: ?usize = null;
    var col: usize = 0;
    var start: usize = 0;
    var cur: std.ArrayList(u8) = .empty;
    var first: ?usize = null;
    var last: usize = 0;
    var in_word = false;

    const Flush = struct {
        fn run(a: std.mem.Allocator, rs: *std.ArrayList(Run), c: *std.ArrayList(u8), st: usize, at: usize, s: Sgr, wide: bool) !void {
            const trimmed = std.mem.trimEnd(u8, c.items, " ");
            if (trimmed.len > 0) {
                const gone = c.items.len - trimmed.len;
                try rs.append(a, .{ .col = st, .cells = at - st - gone, .text = try a.dupe(u8, trimmed), .style = s, .wide = wide });
            }
            c.clearRetainingCapacity();
        }
    };

    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == 0x1b and i + 1 < line.len and line[i + 1] == '[') {
            const stop = std.mem.indexOfAnyPos(u8, line, i + 2, "ABCDEFGHJKSTfmsu") orelse line.len - 1;
            if (line[stop] == 'm') {
                try Flush.run(arena, &runs, &cur, start, col, style, false);
                style.apply(line[i + 2 .. stop]);
                start = col;
            }
            i = stop + 1;
            continue;
        }
        const n = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
        const bytes = line[i..@min(i + n, line.len)];
        i += bytes.len;
        const cp = std.unicode.utf8Decode(bytes) catch '?';
        const cells = highlight.width(cp);
        if (cells == 0) {
            // A joiner or selector belongs to the character before it, which
            // is the last run when that was wide.
            if (cur.items.len > 0) {
                try cur.appendSlice(arena, bytes);
            } else if (runs.items.len > 0 and runs.items[runs.items.len - 1].wide) {
                const r = &runs.items[runs.items.len - 1];
                r.text = try std.mem.concat(arena, u8, &.{ r.text, bytes });
            }
            continue;
        }
        if (col + cells > width) {
            rest = i - bytes.len;
            break;
        }
        if (cp == ' ') {
            if (in_word) try ends.append(arena, col);
            in_word = false;
            // A run never holds two spaces together, which a renderer is
            // free to collapse into one; the next run starts at its own cell.
            if (cur.items.len > 0 and (words or cur.items[cur.items.len - 1] == ' ')) {
                try Flush.run(arena, &runs, &cur, start, col, style, false);
                col += 1;
                start = col;
            } else if (cur.items.len == 0) {
                col += 1;
                start = col;
            } else {
                try cur.append(arena, ' ');
                col += 1;
            }
            continue;
        }
        in_word = true;
        if (first == null) first = col;
        if (cells == 2 or shape(cp) != null) {
            try Flush.run(arena, &runs, &cur, start, col, style, false);
            try runs.append(arena, .{
                .col = col,
                .cells = cells,
                .text = try arena.dupe(u8, bytes),
                .style = style,
                .wide = cells == 2,
                .block = if (shape(cp) != null) cp else null,
            });
            col += cells;
            start = col;
        } else {
            if (cur.items.len == 0) start = col;
            try cur.appendSlice(arena, bytes);
            col += 1;
        }
        last = col;
    }
    try Flush.run(arena, &runs, &cur, start, col, style, false);
    if (in_word) try ends.append(arena, col);
    return .{ .runs = runs.items, .first = first orelse 0, .last = @max(last, first orelse 0), .word_ends = ends.items, .rest = rest, .style = style };
}

// ---------------------------------------------------------------- colour

/// The attributes the highlighter writes, read back from its SGR codes.
const Sgr = struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: bool = false,
    strike: bool = false,
    /// 0–255, the 256 colours; the 16 named ones are 0–15.
    fg: ?u8 = null,

    fn apply(s: *Sgr, params: []const u8) void {
        var it = std.mem.splitScalar(u8, params, ';');
        while (it.next()) |p| {
            const n = std.fmt.parseInt(u16, p, 10) catch 0;
            switch (n) {
                0 => s.* = .{},
                1 => s.bold = true,
                2 => s.faint = true,
                3 => s.italic = true,
                4 => s.underline = true,
                9 => s.strike = true,
                22 => {
                    s.bold = false;
                    s.faint = false;
                },
                23 => s.italic = false,
                24 => s.underline = false,
                29 => s.strike = false,
                30...37 => s.fg = @intCast(n - 30),
                90...97 => s.fg = @intCast(n - 90 + 8),
                39 => s.fg = null,
                38 => {
                    if (!std.mem.eql(u8, it.next() orelse "", "5")) return;
                    s.fg = std.fmt.parseInt(u8, it.next() orelse "", 10) catch null;
                },
                // A background is not drawn; its colour number is passed over.
                48 => {
                    _ = it.next();
                    _ = it.next();
                },
                else => {},
            }
        }
    }

    /// As CSS. Faint is the fill's opacity, as the element's own is the
    /// clock's.
    fn css(s: Sgr, w: *std.Io.Writer) !void {
        if (s.fg) |n| {
            const rgb = xterm(n);
            try w.print("fill:#{x:0>2}{x:0>2}{x:0>2};", .{ rgb[0], rgb[1], rgb[2] });
        }
        if (s.bold) try w.writeAll("font-weight:700;");
        if (s.faint) try w.writeAll("fill-opacity:.6;");
        if (s.italic) try w.writeAll("font-style:italic;");
        if (s.underline or s.strike) try w.print("text-decoration:{s};", .{if (s.underline) "underline" else "line-through"});
    }
};

/// The xterm 256-colour palette.
fn xterm(n: u8) [3]u8 {
    const named = [16][3]u8{
        .{ 0, 0, 0 },       .{ 205, 49, 49 },  .{ 13, 188, 121 }, .{ 229, 229, 16 },
        .{ 36, 114, 200 },  .{ 188, 63, 188 }, .{ 17, 168, 205 }, .{ 229, 229, 229 },
        .{ 102, 102, 102 }, .{ 241, 76, 76 },  .{ 35, 209, 139 }, .{ 245, 245, 67 },
        .{ 59, 142, 234 },  .{ 214, 112, 214 }, .{ 41, 184, 219 }, .{ 255, 255, 255 },
    };
    if (n < 16) return named[n];
    if (n >= 232) {
        const v: u8 = 8 + 10 * (n - 232);
        return .{ v, v, v };
    }
    const levels = [6]u8{ 0, 95, 135, 175, 215, 255 };
    const k = n - 16;
    return .{ levels[k / 36], levels[(k / 6) % 6], levels[k % 6] };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a speed is a default and then sigils, by emoji or by name" {
    const s = try parseSpeeds("40l,🤖60w,thought_balloon0b");
    try testing.expectEqual(Pace{ .ms = 40, .unit = .line }, s.default);
    try testing.expectEqual(Pace{ .ms = 60, .unit = .word }, s.of(.bot));
    try testing.expectEqual(Pace{ .ms = 0, .unit = .block }, s.of(.thought));
    // 🙋 is typed unless it is named.
    try testing.expectEqual(typing, s.of(.user));
    try testing.expectEqual(Pace{ .ms = 40, .unit = .line }, s.of(.agent));
    try testing.expectError(error.BadSpeed, parseSpeeds("40"));
    try testing.expectError(error.BadSpeed, parseSpeeds("40l,60w"));
    try testing.expectError(error.BadSpeed, parseSpeeds("🤖60x"));
    try testing.expectError(error.BadSpeed, parseSpeeds("40l,🤖60w2x"));
}

test "a pace may say the pause before it" {
    const s = try parseSpeeds("40l100,🙋50c1000");
    try testing.expectEqual(Pace{ .ms = 40, .unit = .line, .pause = 100 }, s.default);
    try testing.expectEqual(Pace{ .ms = 50, .unit = .char, .pause = 1000 }, s.of(.user));
}

test "a line is laid out on the grid, its spaces stepped over" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const s = try layout(a.allocator(), "\u{2502}     \x1b[0;38;5;181mWest of House\x1b[0m  ", 80, .{}, false);
    try testing.expectEqual(@as(usize, 2), s.runs.len);
    try testing.expectEqual(@as(?u21, 0x2502), s.runs[0].block);
    try testing.expectEqual(@as(usize, 6), s.runs[1].col);
    try testing.expectEqualStrings("West of House", s.runs[1].text);
    try testing.expectEqual(@as(?u8, 181), s.runs[1].style.fg);
    try testing.expectEqualSlices(usize, &.{ 1, 10, 13, 19 }, s.word_ends);
}

test "arriving by word, every word is a run" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const s = try layout(a.allocator(), "West of House", 80, .{}, true);
    try testing.expectEqual(@as(usize, 3), s.runs.len);
    try testing.expectEqualStrings("of", s.runs[1].text);
    try testing.expectEqual(@as(usize, 5), s.runs[1].col);
}

test "a wide character is a run of its own, and a block one is drawn" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const s = try layout(a.allocator(), "\u{2590} \u{1F916}:", 80, .{}, false);
    try testing.expectEqual(@as(usize, 3), s.runs.len);
    try testing.expectEqual(@as(?u21, 0x2590), s.runs[0].block);
    try testing.expect(s.runs[1].wide);
    try testing.expectEqual(@as(usize, 2), s.runs[1].col);
    try testing.expectEqual(@as(usize, 4), s.runs[2].col);
}

test "a block character's rectangles fill its share of the cell" {
    const half = shape(0x2590).?;
    try testing.expectEqual([4]u8{ 4, 0, 4, 8 }, half.rects[0]);
    const quarter = shape(0x2582).?;
    try testing.expectEqual([4]u8{ 0, 6, 8, 2 }, quarter.rects[0]);
    try testing.expectEqual(@as(usize, 2), shape(0x259F).?.n);
    try testing.expectEqual(@as(?Shape, null), shape('a'));
}

test "what does not fit is handed back, in the style it was in" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const line = "ab \x1b[0;1mcdef";
    const s = try layout(a.allocator(), line, 5, .{}, false);
    try testing.expectEqualStrings("cd", s.runs[1].text);
    try testing.expectEqualStrings("ef", line[s.rest.?..]);
    try testing.expect(s.style.bold);
    const next = try layout(a.allocator(), line[s.rest.?..], 5, s.style, false);
    try testing.expect(next.runs[0].style.bold);
    try testing.expectEqual(@as(?usize, null), next.rest);
}
