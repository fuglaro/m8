//! `cast` — a ledger replayed as riff would have shown it, as an animated SVG.
//!
//! The picture is for a README, where an image is all that runs: no script,
//! only the CSS inside the SVG. So nothing is drawn frame by frame. Every line
//! is written once, plain, where it ends up, and a curtain in the background
//! colour hides what has not arrived yet. The curtain's moves, the scrolling,
//! and riff's editor and status line are each one stepped animation, however
//! long the session. A browser does no work for a step not yet due, so the
//! picture costs about the same to play at any length, and its size is the
//! text and a short line per move. The text is gathered into a few large
//! elements, a page each, and a page is switched off once it has scrolled
//! out of sight, since a browser's work on every step follows how many there
//! are.
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
//!
//! With `--static` it is a still: the whole ledger at once, as tall as it
//! is, and a 🙋 at the end left typed and unsent.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const highlight = @import("../m8/highlight.zig");
const sigil = @import("../m8/sigil.zig");
const config = @import("../config.zig");
const session = @import("../session.zig");
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
        \\  m8 cast [--size COLSxROWS] [--speed SPEEDS] [--no-riff ADDRESS] [--skip-snips] [--static]
        \\
        \\Reads a ledger on stdin and writes an SVG that plays it the way riff
        \\would have shown it: each 🙋 typed into the editor and sent, and
        \\everything after it arriving above. It holds the last frame for 3
        \\seconds and plays again. CSS is all it uses, so it plays wherever an
        \\image does, a README included.
        \\
        \\  m8 say --no-send :games/zork | m8 encode | m8 cast >zork.svg
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
        \\--skip-snips leaves out what a turn kept aside: a 💭snip, and the 🧠
        \\that names where one went.
        \\
        \\--static draws it all at once instead, as tall as it is, with
        \\nothing moving. A 🙋 at the end is left typed and unsent.
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
    var snips = true;
    var still = false;
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
        } else if (std.mem.eql(u8, arg, "--skip-snips")) {
            snips = false;
        } else if (std.mem.eql(u8, arg, "--static")) {
            still = true;
        } else if (std.mem.eql(u8, arg, "--no-riff") and value.len > 0) {
            i += 1;
            address = value;
        } else {
            try ctx.err.print("m8 cast: '{s}' is not something it takes; see m8 cast --help\n", .{arg});
            return 1;
        }
    }

    var look = try config.highlights(ctx.arena, ctx.io, ctx.env);
    look.width = cols;
    var c: Cast = try .init(ctx.arena, ctx.out, look, speeds, cols, rows);
    c.address = address;
    c.snips = snips;
    var body: std.Io.Writer.Allocating = .init(ctx.arena);
    if (still) {
        c.still = ctx.out;
        c.out = &body.writer;
    }
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

// ---------------------------------------------------------------- tracks

/// Where something animated is at a moment: translated to `x`, `y`, and from
/// there moving `steps` times, evenly, to where the next frame has it.
const Frame = struct { t: u64, x: i64 = 0, y: i64 = 0, steps: usize = 0 };

/// One element's moves over a play, as one stepped animation. Each element
/// that moves is one animation however much it moves, since a browser does
/// work for every animation on every frame but none for a step not yet due.
const Track = struct {
    frames: std.ArrayList(Frame) = .empty,

    /// Moves to `f` at its time, or at the time of the last move if that is
    /// later. A move at the very moment another arrived replaces it, unless
    /// that one ends a run of steps, which the new one then follows by a
    /// millisecond.
    fn at(tr: *Track, arena: std.mem.Allocator, f: Frame) !void {
        var g = f;
        const fs = tr.frames.items;
        if (fs.len > 0 and fs[fs.len - 1].t >= g.t) {
            g.t = fs[fs.len - 1].t;
            if (fs.len < 2 or fs[fs.len - 2].steps == 0) {
                fs[fs.len - 1] = g;
                return;
            }
            g.t += 1;
        }
        try tr.frames.append(arena, g);
    }

    /// From `x` along `n` cells, one each `ms` from `t`.
    fn along(tr: *Track, arena: std.mem.Allocator, t: u64, x: i64, y: i64, n: usize, ms: u64) !void {
        try tr.at(arena, .{ .t = t, .x = x, .y = y, .steps = n });
        try tr.at(arena, .{ .t = t + n * ms, .x = x + @as(i64, @intCast(n * cw)), .y = y });
    }

    fn css(tr: *const Track, w: *std.Io.Writer, name: []const u8, end_at: u64) !void {
        try w.print(".{s}{{animation:{s} {d}ms step-end infinite}}@keyframes {s}{{", .{ name, name, end_at, name });
        for (tr.frames.items) |f| {
            try w.print("{d:.4}%{{transform:translate({d}px,{d}px)", .{ pct(f.t, end_at), f.x, f.y });
            if (f.steps > 0) try w.print(";animation-timing-function:steps({d})", .{f.steps});
            try w.writeAll("}");
        }
        try w.writeAll("}");
    }
};

/// A moment as a share of the play, as a keyframe gives it.
fn pct(t: u64, end_at: u64) f64 {
    return @as(f64, @floatFromInt(t)) * 100.0 / @as(f64, @floatFromInt(end_at));
}

fn px(cell: usize, size: usize) i64 {
    return @intCast(pad + cell * size);
}

// ---------------------------------------------------------------- casting

/// Rows of text gathered into one `<text>`, each run a `<tspan>` placed and
/// held to its cells, and the block characters drawn beside it. A browser
/// lays out and paints by the `<text>`, so a few large ones play far faster
/// than one a run.
const Group = struct {
    spans: std.Io.Writer.Allocating,
    shapes: std.Io.Writer.Allocating,
    rows: usize = 0,

    fn init(arena: std.mem.Allocator) Group {
        return .{ .spans = .init(arena), .shapes = .init(arena) };
    }

    fn flush(g: *Group, w: *std.Io.Writer) !void {
        if (g.spans.written().len > 0) try w.print("<text>{s}</text>\n", .{g.spans.written()});
        if (g.shapes.written().len > 0) try w.print("{s}\n", .{g.shapes.written()});
        g.spans.clearRetainingCapacity();
        g.shapes.clearRetainingCapacity();
        g.rows = 0;
    }
};

/// How many rows of the scrollback, or of messages, share a `<text>`, which
/// is a page.
const group_rows = 100;

/// A page of the scrollback: switched on when its first row arrives, and off
/// again once it has scrolled out of sight, so that a long session costs
/// what a screenful does. A page of messages is on from the first being
/// typed until the last is sent. Chromium honours this; Firefox draws every page
/// regardless, which it does quickly enough on its own.
const Page = struct { from: u64, end: usize = 0, gone: ?u64 = null };

/// A record as it was said and as it renders, kept past its end.
const Said = struct { sig: doc.Sigil, said: []const u8, rendered: []const u8 };

/// How text is set: spaces kept as a terminal keeps them, and every
/// character its own glyph in its own cell. A wide character is a size
/// smaller, as an emoji at the font's size stands taller than its row.
const text_css = "text{white-space:pre;font-kerning:none;font-variant-ligatures:none}.w{font-size:14px}";

/// What riff's status line says, top to bottom in its strip.
const statuses = [_][]const u8{ waiting_empty, waiting_written, working };

const Cast = struct {
    arena: std.mem.Allocator,
    out: *std.Io.Writer,
    look: doc.Look,
    speeds: Speeds,
    cols: usize,
    rows: usize,
    /// The address said to at a plain terminal, or riff's when there is none.
    address: ?[]const u8 = null,
    /// Whether what a turn kept aside is shown.
    snips: bool = true,
    /// Where a still goes, once the picture is whole and its height known:
    /// everything is written to `out` until then. A 🙋 is held until a
    /// record follows it, as the last is left unsent.
    still: ?*std.Io.Writer = null,
    held: ?Said = null,

    /// The record being read: rendered, and as it was said.
    rendered: std.Io.Writer.Allocating,
    said: std.ArrayList(u8) = .empty,
    body: ?doc.ContentWriter = null,
    sig: doc.Sigil = .user,
    value: []const u8 = "",
    lines: usize = 0,

    /// Whether the first 🙋 has been reached, and whether nothing has arrived
    /// since the last was sent.
    started: bool = false,
    answering: bool = false,
    /// The time the next thing arrives at, and the scrollback row it takes.
    t: u64 = 0,
    row: usize = 0,
    styles: std.ArrayList(Sgr) = .empty,
    scrollback: Group,
    pages: std.ArrayList(Page) = .empty,

    /// Everything in the scrollback is written as it ends up, and a curtain
    /// in the background colour hides what has not arrived yet: the rest of
    /// the row being written and every row below it. Its edge is where a
    /// terminal's cursor is, so at a plain terminal the cursor rides on it.
    curtain: Track = .{},
    scroll: Track = .{},
    scrolled: usize = 0,

    /// Riff's live rows are a panel, the status bar over the editor, that
    /// runs off the bottom of the picture and rises a row as the editor
    /// grows. Every message rides in it, a screen apart in a strip, so that
    /// only the one in the editor is ever in sight, with a curtain of its
    /// own and the cursor at that curtain's edge. The status line is a strip
    /// too.
    later: std.Io.Writer.Allocating,
    messages: usize = 0,
    drafts: Group,
    draft_pages: std.ArrayList(Page) = .empty,
    /// The editor's rows, and the panel's rise to give it them.
    e: usize = 1,
    panel: Track = .{},
    editor: Track = .{},
    cover: Track = .{},
    status: Track = .{},
    saying: usize = 0,

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
            .scrollback = .init(arena),
            .drafts = .init(arena),
        };
    }

    /// The left margin riff keeps, the editor's edge sitting in its last cell.
    fn margin(c: *const Cast) usize {
        return if (c.cols >= 24) 4 else 0;
    }

    /// Rows above the status bar and editor, which a plain terminal has none
    /// of.
    fn region(c: *const Cast) usize {
        if (c.still != null) return std.math.maxInt(u32);
        return if (c.address == null) c.rows - 1 - c.e else c.rows;
    }

    /// The most rows riff's editor has: the live rows are at most half the
    /// terminal.
    fn most(c: *const Cast) usize {
        return @max(1, c.rows / 2 -| 1);
    }

    /// How far apart the strips hold what they show, so that nothing but the
    /// one shown is ever in the picture.
    fn apart(c: *const Cast) usize {
        return (c.rows + 2) * lh;
    }

    /// The editor's first row, while it is one row.
    fn editorTop(c: *const Cast) usize {
        return pad + (c.rows - 1) * lh;
    }

    fn open(c: *Cast) !void {
        if (c.still == null) try c.header(c.out, c.rows, c.region());
        try c.edge(0, 0, 0);
        try c.scroll.at(c.arena, .{ .t = 0 });
        try c.panel.at(c.arena, .{ .t = 0 });
        try c.editor.at(c.arena, .{ .t = 0 });
        try c.cover.at(c.arena, .{ .t = 0, .x = px(c.margin(), cw), .y = @intCast(c.editorTop()) });
        try c.status.at(c.arena, .{ .t = 0 });
    }

    /// The picture `rows` high, its scrollback `above` rows of it.
    fn header(c: *Cast, o: *std.Io.Writer, rows: usize, above: usize) !void {
        const w = c.cols * cw + 2 * pad;
        const h = rows * lh + 2 * pad;
        try o.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}" font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,'DejaVu Sans Mono',monospace" font-size="{d}" fill="{s}">
            \\<rect width="100%" height="100%" rx="6" fill="{s}"/>
            \\<clipPath id="r"><rect y="{d}" width="{d}" height="{d}"/></clipPath>
            \\<g clip-path="url(#r)"><g class="s">
            \\
        , .{ w, h, w, h, font_size, fg, bg, pad, w, above * lh });
    }

    pub fn begin(c: *Cast, s: doc.Sigil, value: []const u8) !void {
        c.rendered.clearRetainingCapacity();
        c.said.clearRetainingCapacity();
        c.body = try doc.ContentWriter.beginLooking(&c.rendered.writer, .m8, c.look, s, value);
        c.sig = s;
        c.value = try c.arena.dupe(u8, value);
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
        if (!c.snips and c.snip()) return;
        // A still leaves its last 🙋 unsent, so each waits to see whether
        // anything follows it.
        if (c.held) |h| {
            c.held = null;
            try c.settle(h);
        }
        if (c.still != null and c.sig == .user) {
            c.held = .{ .sig = .user, .said = try c.arena.dupe(u8, c.said.items), .rendered = try c.arena.dupe(u8, c.rendered.written()) };
            return;
        }
        try c.settle(.{ .sig = c.sig, .said = c.said.items, .rendered = c.rendered.written() });
    }

    /// A record played: typed and sent when it is a 🙋, arriving otherwise.
    fn settle(c: *Cast, r: Said) !void {
        const first = !c.started;
        if (first) {
            if (r.sig != .user) return;
            c.started = true;
        }

        const pace: Pace = if (r.sig == .user) .{ .ms = 0, .unit = .block } else c.speeds.of(r.sig);
        if (c.address) |address| {
            // The answer starts on the row after the command, and every record
            // and the next prompt after a blank one.
            if (!first and !c.answering) c.row += 1;
            if (r.sig == .user) {
                try c.command(address, r.said, true);
                c.answering = true;
                return;
            }
        } else if (!first) c.row += 1; // the blank line between records

        if (r.sig == .user)
            try c.typeIn(r.said)
        else
            c.t += pace.pause orelse if (c.answering) latency else 0;
        c.answering = r.sig == .user;
        const from = c.t;
        var it = std.mem.splitScalar(u8, std.mem.trimEnd(u8, r.rendered, "\n"), '\n');
        while (it.next()) |l| try c.place(l, pace);
        // The newline ending the last line takes the cursor onto the next,
        // and a terminal scrolls to show it then, not when it is written in.
        try c.reach(c.t);
        if (pace.unit == .block) c.t = from + pace.ms;
    }

    /// Whether the record is a turn's aside, or the 🧠 naming where one went.
    fn snip(c: *const Cast) bool {
        return (c.sig == .thought and c.lines > 0 and std.mem.eql(u8, c.value, session.snip)) or
            (c.sig == .agent and session.namesSnip(c.value));
    }

    /// A message typed into the editor, and then sent.
    fn typeIn(c: *Cast, message: []const u8) !void {
        const pace = c.speeds.of(.user);
        try c.say(waiting_empty, c.t);
        c.t += pace.pause orelse think;
        try c.say(waiting_written, c.t);

        // The message in its own place in the strip.
        const m = c.margin();
        c.messages += 1;
        const base = c.editorTop() + c.messages * c.apart();
        if (c.drafts.rows == 0) try c.draft_pages.append(c.arena, .{ .from = c.t });
        for (try c.messageRows(message), 0..) |shown, j| {
            const y = base + j * lh;
            try c.texts(&c.drafts, shown, m, y);
            try c.grow(j + 1, c.t);
            try c.typed(&c.cover, shown, pace, m, @intCast(y), c.t);
            c.t += duration(pace, shown);
        }
        // Sent: the editor empty and one row again, the rows it gave back
        // left blank rather than scrolled into.
        c.t += enter;
        try c.editor.at(c.arena, .{ .t = c.t });
        try c.cover.at(c.arena, .{ .t = c.t, .x = px(m, cw), .y = @intCast(c.editorTop()) });
        c.e = 1;
        try c.panel.at(c.arena, .{ .t = c.t });
        try c.say(working, c.t);
        c.draft_pages.items[c.draft_pages.items.len - 1].gone = c.t;
        if (c.drafts.rows >= group_rows) try c.draftPage();
    }

    /// The messages gathered so far, written as a page.
    fn draftPage(c: *Cast) !void {
        if (c.drafts.rows == 0) return;
        try c.later.writer.print("<g class=\"m{d}\">", .{c.draft_pages.items.len - 1});
        try c.drafts.flush(&c.later.writer);
        try c.later.writer.writeAll("</g>\n");
    }

    /// A message as riff's editor holds it: a row for each of its lines, and
    /// for each time one is too wide.
    fn messageRows(c: *Cast, message: []const u8) ![]const Shown {
        const width = c.cols -| ((2 * c.margin() -| 1) + 2);
        var rows: std.ArrayList(Shown) = .empty;
        var lines = std.mem.splitScalar(u8, message, '\n');
        while (lines.next()) |l| {
            var rest = l;
            while (true) {
                const shown = try layout(c.arena, rest, @max(width, 1), .{});
                try rows.append(c.arena, shown);
                rest = rest[shown.rest orelse break ..];
            }
        }
        return rows.items;
    }

    /// The editor showing the latest message with `rows` rows of it written
    /// from `t`: grown to hold them, as far as it may, and past that
    /// scrolled within to keep the last in sight.
    fn grow(c: *Cast, rows: usize, t: u64) !void {
        const e = @min(c.most(), rows);
        if (e > c.e) {
            c.e = e;
            try c.panel.at(c.arena, .{ .t = t, .y = -@as(i64, @intCast((e - 1) * lh)) });
            try c.reach(t);
        }
        // The panel's rise carries the message up with it; what is left is
        // which message, and how far it has scrolled within.
        const shift: i64 = @intCast(c.messages * c.apart() + (rows - c.e) * lh);
        try c.editor.at(c.arena, .{ .t = t, .y = -shift });
    }

    /// A plain terminal's prompt, waiting on the row.
    fn prompted(c: *Cast) !void {
        try c.reach(c.t);
        try c.out.print("<text x=\"{d}\" y=\"{d}\" textLength=\"{d}\">&gt;&gt;&gt;</text>\n", .{ pad, pad + c.row * lh + baseline, 3 * cw });
        try c.edge(c.t, prompt.len, c.row);
    }

    /// A message typed at a plain terminal's prompt as the command that says
    /// it to the address, and entered if `sent`.
    fn command(c: *Cast, address: []const u8, message: []const u8, sent: bool) !void {
        const pace = c.speeds.of(.user);
        try c.prompted();
        c.t += pace.pause orelse think;

        const one = try std.fmt.allocPrint(c.arena, "m8 {s} -- '{s}'", .{ address, message });
        const fits = std.mem.indexOfAny(u8, message, "'\n") == null and
            prompt.len + (try layout(c.arena, one, std.math.maxInt(usize), .{})).last <= c.cols;
        const said = if (fits) one else try std.fmt.allocPrint(c.arena, "m8 {s} <<'" ++ heredoc ++ "'\n{s}\n" ++ heredoc, .{ address, message });

        var lines = std.mem.splitScalar(u8, said, '\n');
        var col: usize = prompt.len;
        while (lines.next()) |l| : (col = 0) {
            // A line too wide for the terminal carries on in the next row.
            var rest = l;
            while (true) {
                const shown = try layout(c.arena, rest, c.cols - col, .{});
                try c.placeRow(shown, pace, col, shown.rest != null or lines.peek() != null);
                rest = rest[shown.rest orelse break ..];
                col = 0;
            }
        }
        // Entered, the cursor goes to the next row to wait for the answer.
        if (!sent) return;
        c.t += enter;
        try c.edge(c.t, 0, c.row);
        try c.reach(c.t);
    }

    /// One rendered line into the scrollback, arriving at the pace given. A
    /// line wider than the terminal carries on in the next row, as a
    /// terminal wraps it.
    fn place(c: *Cast, rendered: []const u8, pace: Pace) !void {
        var rest = rendered;
        var style: Sgr = .{};
        while (true) {
            const shown = try layout(c.arena, rest, c.cols, style);
            try c.placeRow(shown, pace, 0, true);
            rest = rest[shown.rest orelse break ..];
            style = shown.style;
        }
    }

    /// A row written from `col`, the curtain drawn back off it as it arrives
    /// and, unless it is to wait at the row's end, onto the next row.
    fn placeRow(c: *Cast, shown: Shown, pace: Pace, col: usize, onward: bool) !void {
        const at = c.t;
        if (c.scrollback.rows == 0) try c.pages.append(c.arena, .{ .from = at });
        try c.texts(&c.scrollback, shown, col, pad + c.row * lh);
        try c.reach(at);
        try c.typed(&c.curtain, shown, pace, col, px(c.row, lh), at);
        c.row += 1;
        if (c.scrollback.rows >= group_rows) try c.page();
        switch (pace.unit) {
            .block => {},
            .line => c.t += pace.ms,
            .word, .char => c.t += duration(pace, shown),
        }
        if (onward) try c.edge(c.t, 0, c.row);
    }

    /// An edge moved along a row as it arrives at the pace given, from `at`:
    /// a cell at a time, a word at a time, or to its end at once.
    fn typed(c: *Cast, tr: *Track, shown: Shown, pace: Pace, col: usize, y: i64, at: u64) !void {
        if (pace.ms > 0 and pace.unit == .char and shown.cells() > 0)
            return tr.along(c.arena, at, px(col + shown.first, cw), y, shown.cells(), pace.ms);
        if (pace.ms > 0 and pace.unit == .word) {
            for (shown.word_ends, 0..) |e, j| try tr.at(c.arena, .{ .t = at + j * pace.ms, .x = px(col + e, cw), .y = y });
            return;
        }
        try tr.at(c.arena, .{ .t = at, .x = px(col + shown.last, cw), .y = y });
    }

    /// The curtain's edge at `col` of `row`, from `t`.
    fn edge(c: *Cast, t: u64, col: usize, row: usize) !void {
        try c.curtain.at(c.arena, .{ .t = t, .x = px(col, cw), .y = px(row, lh) });
    }

    /// The scrollback scrolled from `at` as far as the row being written.
    fn reach(c: *Cast, at: u64) !void {
        if (c.row < c.region()) return;
        const off = c.row + 1 - c.region();
        if (off <= c.scrolled) return;
        try c.scroll.at(c.arena, .{ .t = at, .y = -@as(i64, @intCast(off * lh)) });
        c.scrolled = off;
        for (c.pages.items) |*p| if (p.end > 0 and p.end <= off and p.gone == null) {
            p.gone = at;
        };
    }

    /// The scrollback gathered so far, written as a page.
    fn page(c: *Cast) !void {
        if (c.scrollback.rows == 0) return;
        const k = c.pages.items.len - 1;
        c.pages.items[k].end = c.row;
        try c.out.print("<g class=\"p{d}\">", .{k});
        try c.scrollback.flush(c.out);
        try c.out.writeAll("</g>\n");
    }

    /// Every run of a line, each held to the width of its cells, and every
    /// block character drawn.
    fn texts(c: *Cast, g: *Group, shown: Shown, col: usize, y: usize) !void {
        const w = &g.spans.writer;
        for (shown.runs) |r| {
            const x = pad + (col + r.col) * cw;
            const plain = std.meta.eql(r.style, Sgr{});
            const said = if (r.wide)
                (if (plain) " class=\"w\"" else try std.fmt.allocPrint(c.arena, " class=\"w f{d}\"", .{try c.class(r.style)}))
            else if (plain) "" else try std.fmt.allocPrint(c.arena, " class=\"f{d}\"", .{try c.class(r.style)});
            if (r.block) |cp| {
                try drawShape(&g.shapes.writer, cp, x, y, said);
                continue;
            }
            // A wide character sits a pixel low, so an emoji's top stays in
            // its own row.
            try w.print("<tspan x=\"{d}\" y=\"{d}\"{s}", .{ x, y + baseline + @intFromBool(r.wide), said });
            if (r.cells > 1 and !r.wide) try w.print(" textLength=\"{d}\"", .{r.cells * cw});
            try w.writeAll(">");
            for (r.text) |b| switch (b) {
                '&' => try w.writeAll("&amp;"),
                '<' => try w.writeAll("&lt;"),
                '>' => try w.writeAll("&gt;"),
                else => try w.writeByte(b),
            };
            try w.writeAll("</tspan>");
        }
        g.rows += 1;
    }

    fn class(c: *Cast, s: Sgr) !usize {
        for (c.styles.items, 0..) |known, k| if (std.meta.eql(known, s)) return k;
        try c.styles.append(c.arena, s);
        return c.styles.items.len - 1;
    }

    /// The status line says `what` from `at`.
    fn say(c: *Cast, what: []const u8, at: u64) !void {
        const k = for (statuses, 0..) |s, k| {
            if (s.ptr == what.ptr) break k;
        } else unreachable;
        if (k == c.saying) return;
        c.saying = k;
        try c.status.at(c.arena, .{ .t = at, .y = -@as(i64, @intCast(k * c.apart())) });
    }

    fn close(c: *Cast) !void {
        if (c.still) |o| return c.closeStill(o);
        const end_at = c.t + hold;
        const o = c.out;
        const w = c.cols * cw + 2 * pad;
        const h = (c.row + c.rows + 2) * lh;
        try c.page();
        if (c.address != null) {
            // The next prompt, waiting.
            if (c.started) c.row += 1;
            try c.prompted();
            try o.print("<g class=\"cu\"><rect width=\"{d}\" height=\"{d}\"/><path fill=\"{s}\" d=\"M{d} 0H{d}V{d}H-{d}V{d}H{d}Z\"/></g>\n", .{ cw, lh, bg, cw, 2 * w, h, 2 * w, lh, cw });
        } else try o.print("<path class=\"cu\" fill=\"{s}\" d=\"M0 0H{d}V{d}H-{d}V{d}H0Z\"/>\n", .{ bg, 2 * w, h, 2 * w, lh });
        try o.writeAll("</g></g>\n");
        if (c.address == null) try c.riffBelow();

        try o.writeAll("<style><![CDATA[" ++ text_css ++ "svg:active *{animation-play-state:paused}");
        try c.curtain.css(o, "cu", end_at);
        try c.scroll.css(o, "s", end_at);
        if (c.address == null) {
            try c.panel.css(o, "pn", end_at);
            try c.editor.css(o, "es", end_at);
            try c.cover.css(o, "ec", end_at);
            try c.status.css(o, "ss", end_at);
        }
        try switches(o, "p", c.pages.items, end_at);
        try switches(o, "m", c.draft_pages.items, end_at);
        try c.colours(o);
        try o.writeAll("]]></style>\n</svg>\n");
    }

    /// The whole ledger at once, as tall as it is: no curtain and nothing
    /// moving, the cursor where it was left, and a last 🙋 still unsent.
    fn closeStill(c: *Cast, final: *std.Io.Writer) !void {
        try c.page();
        const o = c.out;
        var rows: usize = undefined;
        var above: usize = undefined;
        if (c.address) |address| {
            if (c.held) |h| {
                if (c.started and !c.answering) c.row += 1;
                try c.command(address, h.said, false);
            } else {
                if (c.started) c.row += 1;
                try c.prompted();
            }
            try c.page();
            const at = c.curtain.frames.items[c.curtain.frames.items.len - 1];
            try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/>\n", .{ at.x, at.y, cw, lh });
            try o.writeAll("</g></g>\n");
            rows = c.row + 1;
            above = rows;
        } else {
            above = if (c.started) c.row + 1 else 0;
            try o.writeAll("</g></g>\n");
            rows = above + 1 + try c.riffStill(o, pad + above * lh, if (c.held) |h| h.said else null);
        }
        try c.header(final, rows, above);
        try final.writeAll(o.buffered());
        try final.writeAll("<style><![CDATA[" ++ text_css);
        try c.colours(final);
        try final.writeAll("]]></style>\n</svg>\n");
    }

    /// Riff's status bar at `sy` and its editor below, holding `message` as
    /// typed if there is one. Gives the editor's rows.
    fn riffStill(c: *Cast, o: *std.Io.Writer, sy: usize, message: ?[]const u8) !usize {
        const m = c.margin();
        const ey = sy + lh;
        const shown = if (message) |said| try c.messageRows(said) else &.{};
        const e = @max(1, shown.len);
        try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"" ++ grey ++ "\"/>\n", .{ pad + (m -| 1) * cw, ey, eighths(0, 1, cw), e * lh });
        try c.bar(o, sy);
        try c.statusText(o, if (message == null) waiting_empty else waiting_written, sy + baseline);
        var g: Group = .init(c.arena);
        for (shown, 0..) |row, j| try c.texts(&g, row, m, ey + j * lh);
        try g.flush(o);
        const x = if (shown.len > 0) px(m + shown[shown.len - 1].last, cw) else px(m, cw);
        try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"/>\n", .{ x, ey + (e - 1) * lh, cw, lh });
        return e;
    }

    /// The `.fN` classes, a colour each.
    fn colours(c: *Cast, o: *std.Io.Writer) !void {
        for (c.styles.items, 0..) |s, k| {
            try o.print(".f{d}{{", .{k});
            try s.css(o);
            try o.writeAll("}");
        }
    }

    /// Each page switched on and off, as `.{prefix}K`.
    fn switches(o: *std.Io.Writer, prefix: []const u8, pages: []const Page, end_at: u64) !void {
        for (pages, 0..) |p, k| {
            if (p.from == 0 and p.gone == null) continue;
            try o.print(".{s}{d}{{animation:{s}{d} {d}ms step-end infinite}}@keyframes {s}{d}{{0%{{display:none}}{d:.4}%{{display:inline}}", .{ prefix, k, prefix, k, end_at, prefix, k, pct(p.from, end_at) });
            if (p.gone) |g| try o.print("{d:.4}%{{display:none}}", .{pct(g, end_at)});
            try o.writeAll("}");
        }
    }

    /// The status bar and the editor, below the scrollback: the panel's
    /// back, the messages riding in it, and its front.
    fn riffBelow(c: *Cast) !void {
        if (c.saying == 2) try c.say(waiting_empty, c.t);
        try c.draftPage();
        const o = c.out;
        const w = c.cols * cw + 2 * pad;
        const deep = 2 * c.rows * lh;
        const m = c.margin();
        const sy = pad + (c.rows - 2) * lh;
        const ey = c.editorTop();
        const x0 = pad + (m -| 1) * cw;
        const in_grey = " fill=\"" ++ grey ++ "\"";

        // The back: the terminal's own background from the status bar down,
        // and the editor's edge the height of it.
        try o.print("<g class=\"pn\"><rect y=\"{d}\" width=\"{d}\" height=\"{d}\" fill=\"{s}\"/><rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}/></g>\n", .{ sy, w, deep, bg, x0, ey, eighths(0, 1, cw), deep, in_grey });

        // Every message, seen only where the editor can ever be, and the
        // curtain over what is not yet typed.
        try o.print("<clipPath id=\"e\"><rect y=\"{d}\" width=\"{d}\" height=\"{d}\"/></clipPath><g clip-path=\"url(#e)\"><g class=\"pn\"><g class=\"es\">\n", .{ pad + (c.rows - c.most()) * lh, w, deep });
        try o.writeAll(c.later.written());
        try o.print("<g class=\"ec\"><rect width=\"{d}\" height=\"{d}\"/><path fill=\"{s}\" d=\"M{d} 0H{d}V{d}H-{d}V{d}H{d}Z\"/></g></g></g></g>\n", .{ cw, lh, bg, cw, 2 * w, c.apart(), 2 * w, lh, cw });

        // The front: the status bar as riff draws it, and what it says.
        try o.writeAll("<g class=\"pn\">");
        try c.bar(o, sy);
        try o.writeAll("<g class=\"ss\">");
        for (statuses, 0..) |s, k| try c.statusText(o, s, sy + k * c.apart() + baseline);
        try o.writeAll("</g></g>\n");
    }

    /// Riff's status bar, its top at `sy`.
    fn bar(c: *Cast, o: *std.Io.Writer, sy: usize) !void {
        const m = c.margin();
        const inner = c.cols - (2 * m -| 1);
        const x0 = pad + (m -| 1) * cw;
        const in_grey = " fill=\"" ++ grey ++ "\"";
        if (inner >= 8) {
            try drawShape(o, 0x2582, x0, sy, in_grey);
            try drawShape(o, 0x259F, x0 + cw, sy, in_grey);
            try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}/>", .{ x0 + 2 * cw, sy, (inner - 4) * cw, lh, in_grey });
            try drawShape(o, 0x2599, x0 + (inner - 2) * cw, sy, in_grey);
            try drawShape(o, 0x2582, x0 + (inner - 1) * cw, sy, in_grey);
        } else try o.print("<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"{s}/>", .{ x0, sy, inner * cw, lh, in_grey });
    }

    /// What the status bar says, on its baseline at `y`.
    fn statusText(c: *Cast, o: *std.Io.Writer, s: []const u8, y: usize) !void {
        const m = c.margin();
        try o.print("<text x=\"{d}\" y=\"{d}\" fill=\"{s}\">{s}</text>", .{ pad + (m + 1) * cw, y, bg, s[0..@min(s.len, c.cols -| 2 * m + 1 -| 4)] });
    }
};

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

/// A rendered line read back into runs on the grid, a run for each style.
/// Spaces at a run's ends are stepped over rather than drawn, and a wide
/// character is a run of its own so that a font's idea of its width cannot
/// push what follows it along.
fn layout(arena: std.mem.Allocator, line: []const u8, width: usize, from: Sgr) !Shown {
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
            if (cur.items.len == 0) {
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
    const s = try layout(a.allocator(), "\u{2502}     \x1b[0;38;5;181mWest of House\x1b[0m  ", 80, .{});
    try testing.expectEqual(@as(usize, 2), s.runs.len);
    try testing.expectEqual(@as(?u21, 0x2502), s.runs[0].block);
    try testing.expectEqual(@as(usize, 6), s.runs[1].col);
    try testing.expectEqualStrings("West of House", s.runs[1].text);
    try testing.expectEqual(@as(?u8, 181), s.runs[1].style.fg);
    try testing.expectEqualSlices(usize, &.{ 1, 10, 13, 19 }, s.word_ends);
}

test "a wide character is a run of its own, and a block one is drawn" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const s = try layout(a.allocator(), "\u{2590} \u{1F916}:", 80, .{});
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
    const s = try layout(a.allocator(), line, 5, .{});
    try testing.expectEqualStrings("cd", s.runs[1].text);
    try testing.expectEqualStrings("ef", line[s.rest.?..]);
    try testing.expect(s.style.bold);
    const next = try layout(a.allocator(), line[s.rest.?..], 5, s.style);
    try testing.expect(next.runs[0].style.bold);
    try testing.expectEqual(@as(?usize, null), next.rest);
}
