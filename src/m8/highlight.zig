//! Markdown, highlighted for a terminal as it streams.
//!
//! It is a highlighter rather than a renderer: every character it is given is
//! written, in order, and nothing written is ever gone back over. Colour and
//! the odd added space or line break are all it adds. So it guesses early and
//! guesses generously, and a guess that turns out wrong costs a colour, not a
//! character.
//!
//! What it holds back is the least that decides a line:
//!
//! * the opening of a line, until a character that cannot be part of a quote,
//!   list, heading, rule or fence says which it is;
//! * a run of `*`, `_`, `~` or backticks, until the character after it says
//!   whether it opens;
//! * a table's first line, whole, for how many columns it has.
//!
//! Everything else is written the moment it arrives.
//!
//! * Emphasis, strong and strikethrough open on a run with no word before
//!   it and no space after, and close on the next with no space before.
//! * Code spans open on a backtick run with no word before it, even with
//!   whitespace after, and close on the next run of exactly the same length.
//!   A code span holds everything inside it as written.
//! * A link is the part from `](` to `)`, which is the first point at which it
//!   is known to be one.
//! * Nothing inline outlives its line, so every line starts plain. A line
//!   broken to fit is the same line, and only its quote and indent are plain.
//! * A fence opens at the start of a line, or at the indent of the list item
//!   it is in, and holds until it closes or the block ends. `diff` is
//!   coloured a line at a time; `json` gets best-effort key, string, atom and
//!   separator highlighting, without validating its contents.
//! * A quote or list marker is coloured, and nothing after it.
//! * A line that runs past the terminal is broken there, the next carrying
//!   the line's quote and indent, except inside a code span.
//! * A line indented four spaces past any list item it is in is literal,
//!   which is how a provider says that what it hands over is not markdown.
//!   One continuing a paragraph is still the paragraph.
//! * HTML, reference links and footnotes are left as text.

const std = @import("std");
const Error = std.Io.Writer.Error;

/// How a run of text looks, as SGR attributes.
pub const Style = struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: bool = false,
    inverse: bool = false,
    strike: bool = false,
    /// 0–255: indexed colour; 256–271: ANSI terminal palette; null: default.
    fg: ?u16 = null,
    bg: ?u16 = null,

    /// `b` over `a`: what either sets, with `b`'s colour winning.
    fn with(a: Style, b: Style) Style {
        return .{
            .bold = a.bold or b.bold,
            .faint = a.faint or b.faint,
            .italic = a.italic or b.italic,
            .underline = a.underline or b.underline,
            .inverse = a.inverse or b.inverse,
            .strike = a.strike or b.strike,
            .fg = b.fg orelse a.fg,
            .bg = b.bg orelse a.bg,
        };
    }

    fn write(s: Style, w: *std.Io.Writer) Error!void {
        try w.writeAll("\x1b[0");
        if (s.bold) try w.writeAll(";1");
        if (s.faint) try w.writeAll(";2");
        if (s.italic) try w.writeAll(";3");
        if (s.underline) try w.writeAll(";4");
        if (s.inverse) try w.writeAll(";7");
        if (s.strike) try w.writeAll(";9");
        if (s.fg) |c| {
            if (c < 256) try w.print(";38;5;{d}", .{c}) else try w.print(";{d}", .{if (c < 264) 30 + c - 256 else 90 + c - 264});
        }
        if (s.bg) |c| {
            if (c < 256) try w.print(";48;5;{d}", .{c}) else try w.print(";{d}", .{if (c < 264) 40 + c - 256 else 100 + c - 264});
        }
        try w.writeByte('m');
    }
};

// ---------------------------------------------------------------- the look
//
// Every colour the highlighter uses, and nothing else reads them.

pub const Palette = struct {
    /// `>`, list markers, and heading hashes.
    quote: Style = .{ .fg = 245 },
    list: Style = .{ .fg = 245 },
    hash: Style = .{ .fg = 245 },
    heading: Style = .{ .bold = true, .fg = 75 },
    strong: Style = .{ .bold = true, .fg = 231 },
    emphasis: Style = .{ .italic = true },
    strike: Style = .{ .strike = true },
    code: Style = .{ .fg = 180 },
    json_string: Style = .{ .fg = 2 },
    json_key: Style = .{ .fg = 180 },
    json_atom: Style = .{ .bold = true, .fg = 75 },
    json_sep: Style = .{ .fg = 245 },
    link: Style = .{ .underline = true, .fg = 75 },
    rule: Style = .{ .fg = 245 },
    /// A table's `|`, and the first row it opens with.
    pipe: Style = .{ .fg = 245 },
    header: Style = .{ .bold = true },
    /// A fence's own lines, and what is inside one that is not a diff.
    fence: Style = .{ .fg = 245 },
    block: Style = .{ .fg = 180 },
    added: Style = .{ .fg = 2 },
    removed: Style = .{ .fg = 1 },
    hunk: Style = .{ .fg = 6 },
    context: Style = .{},
    /// A line opening with four spaces.
    indented: Style = .{ .fg = 181 },
};

// ----------------------------------------------------------------

pub const Options = struct {
    /// Write the colours.
    color: bool = true,
    /// Break long lines and pad tables. Both add characters, so a copy of
    /// what was shown is no longer what was said.
    reflow: bool = true,
    /// The terminal's width in cells, or 0 for none known.
    width: usize = 0,
    palette: Palette = .{},
    /// The caller already knows this is literal content, not markdown.
    literal: bool = false,
};

/// Apply compact style entries. Each entry replaces the prior style for its name.
pub fn parsePalette(p: *Palette, text: []const u8) error{BadHighlight}!void {
    if (text.len == 0) return;
    var entries = std.mem.splitScalar(u8, text, ',');
    while (entries.next()) |entry| {
        const colon = std.mem.lastIndexOfScalar(u8, entry, ':') orelse return error.BadHighlight;
        const name = entry[0..colon];
        const names = [_][]const u8{ "quote", "list", "hash", "heading", "strong", "em", "strike", "code", "json:string", "json:key", "json:atom", "json:sep", "link", "rule", "table:pipe", "table:head", "fence", "block", "diff:add", "diff:remove", "diff:hunk", "diff:context", "indent" };
        const styles = [_]*Style{ &p.quote, &p.list, &p.hash, &p.heading, &p.strong, &p.emphasis, &p.strike, &p.code, &p.json_string, &p.json_key, &p.json_atom, &p.json_sep, &p.link, &p.rule, &p.pipe, &p.header, &p.fence, &p.block, &p.added, &p.removed, &p.hunk, &p.context, &p.indented };
        const target = for (names, styles) |key, style| {
            if (std.mem.eql(u8, name, key)) break style;
        } else return error.BadHighlight;
        var style: Style = .{};
        var i = colon + 1;
        while (i < entry.len) {
            const c = entry[i];
            i += 1;
            switch (c) {
                '+' => {
                    style.bold = true;
                    style.faint = false;
                },
                '-' => {
                    style.faint = true;
                    style.bold = false;
                },
                'i' => style.italic = true,
                '_' => style.underline = true,
                '!' => style.inverse = true,
                '/' => style.strike = true,
                'f', 'b' => {
                    const fg = c == 'f';
                    if (i >= entry.len or entry[i] != 'g') return error.BadHighlight;
                    i += 1;
                    const terminal = i < entry.len and entry[i] == 't';
                    if (terminal) i += 1;
                    const begin = i;
                    while (i < entry.len and std.ascii.isDigit(entry[i])) : (i += 1) {}
                    if (begin == i) return error.BadHighlight;
                    const n = std.fmt.parseInt(u16, entry[begin..i], 10) catch return error.BadHighlight;
                    if ((terminal and n > 15) or (!terminal and n > 255)) return error.BadHighlight;
                    if (fg) style.fg = if (terminal) 256 + n else n else style.bg = if (terminal) 256 + n else n;
                },
                else => return error.BadHighlight,
            }
        }
        target.* = style;
    }
}

/// The width of the terminal on stdout, or what `COLUMNS` says when stdout
/// is not one, as it is not under riff.
pub fn terminalWidth(env: *const std.process.Environ.Map) usize {
    const posix = std.posix;
    var ws: posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
    if (posix.system.ioctl(1, posix.T.IOCGWINSZ, @intFromPtr(&ws)) == 0 and ws.col > 0) return ws.col;
    const cols = env.get("COLUMNS") orelse return 0;
    return std.fmt.parseInt(usize, cols, 10) catch 0;
}

/// How many cells a character takes. A table rather than `wcwidth`, which is
/// libc's and answers for the locale rather than for the terminal.
pub fn width(cp: u21) usize {
    if (cp == 0x200d or (cp >= 0x300 and cp <= 0x36f) or (cp >= 0xfe00 and cp <= 0xfe0f)) return 0;
    const wide = [_][2]u21{
        .{ 0x1100, 0x115f }, .{ 0x2e80, 0xa4cf },   .{ 0xac00, 0xd7a3 },
        .{ 0xf900, 0xfaff }, .{ 0xfe30, 0xfe4f },   .{ 0xff00, 0xff60 },
        .{ 0xffe0, 0xffe6 }, .{ 0x1f300, 0x1faff }, .{ 0x20000, 0x3fffd },
        // ❓ and ❗, the two sigils from outside the emoji block.
        .{ 0x2753, 0x2755 }, .{ 0x2757, 0x2757 },
    };
    for (wide) |range| if (cp >= range[0] and cp <= range[1]) return 2;
    return 1;
}

/// One block's worth of highlighting. Whatever opens each line has already
/// been written by the caller; `lead` is that, for a broken line to repeat.
pub const Highlighter = struct {
    out: *std.Io.Writer,
    opts: Options,
    lead: []const u8,
    lead_cells: usize,

    /// The style last written, so a change is written once.
    style: Style = .{},
    col: usize = 0,

    // The line.
    kind: enum { opening, text, heading, fence, block, header, row } = .opening,
    hold: [64]u8 = undefined,
    held: usize = 0,
    /// What a broken line is indented by: the quotes and list markers above.
    cont: [64]u8 = undefined,
    cont_n: usize = 0,
    /// How every character of a fenced line looks.
    line: Style = .{},
    /// Where the list item being read puts its content, so that only what is
    /// indented four past that is literal.
    pad: usize = 0,
    /// A paragraph is open, so an indented line continues it.
    para: bool = false,

    // Inline, none of which outlives the line.
    strong: bool = false,
    emphasis: bool = false,
    struck: bool = false,
    link: bool = false,
    bracket: bool = false,
    /// The length of the run that opened a code span, or 0 outside one.
    code: usize = 0,
    run_c: u8 = 0,
    run_n: usize = 0,
    prev: enum { space, word, punct } = .space,
    last: u8 = 0,

    // A character still arriving.
    ch: [4]u8 = undefined,
    ch_n: usize = 0,
    owed: usize = 0,

    // Across lines.
    fence_c: u8 = 0,
    fence_n: usize = 0,
    /// How far in the fence opened, which its lines are read from.
    fence_at: usize = 0,
    diff: bool = false,
    json: bool = false,
    json_string: bool = false,
    json_string_key: bool = false,
    json_escape: bool = false,
    json_key_expected: bool = false,
    json_depth: usize = 0,
    json_objects: [32]bool = undefined,
    lang: [8]u8 = undefined,
    lang_n: usize = 0,
    /// How many columns the table has, once its first line has been seen.
    columns: ?usize = null,
    row_buf: [512]u8 = undefined,
    row_n: usize = 0,
    row_base: usize = 0,
    row_k: usize = 0,
    header_row: bool = false,

    pub fn init(out: *std.Io.Writer, opts: Options, lead: []const u8) Highlighter {
        var cells: usize = 0;
        var it = std.unicode.Utf8View.initUnchecked(lead).iterator();
        while (it.nextCodepoint()) |cp| cells += width(cp);
        return .{ .out = out, .opts = opts, .lead = lead, .lead_cells = cells, .col = cells };
    }

    /// Content, newlines included. The caller writes `lead` at the start of
    /// every line after a newline, before the first byte of it arrives here.
    pub fn write(h: *Highlighter, bytes: []const u8) Error!void {
        for (bytes) |b| {
            if (b == '\n') {
                try h.endLine();
                try h.out.writeByte('\n');
            } else try h.byte(b);
        }
    }

    /// The block is over. Leaves the terminal as it found it.
    pub fn finish(h: *Highlighter) Error!void {
        if (h.kind != .opening or h.held > 0) try h.endLine();
        try h.set(.{});
    }

    fn byte(h: *Highlighter, b: u8) Error!void {
        if (h.owed == 0) {
            h.ch_n = 0;
            h.owed = std.unicode.utf8ByteSequenceLength(b) catch 1;
        }
        if (h.ch_n < h.ch.len) h.ch[h.ch_n] = b;
        h.ch_n += 1;
        h.owed -= 1;
        if (h.owed == 0) try h.char(h.ch[0..@min(h.ch_n, h.ch.len)]);
    }

    fn char(h: *Highlighter, c: []const u8) Error!void {
        switch (h.kind) {
            .opening => {
                if (c.len == 1 and h.holds(c[0]) and h.held < h.hold.len) {
                    h.hold[h.held] = c[0];
                    h.held += 1;
                    return;
                }
                try h.resolve(c);
                // Deciding may itself have started buffering the line.
                if (h.kind == .header) return h.buffer(c);
                try h.char(c);
            },
            .text, .row => try h.text(c),
            .heading => try h.emit(c, h.opts.palette.heading),
            .fence => {
                try h.emit(c, h.opts.palette.fence);
                if (c.len == 1 and c[0] != ' ' and c[0] != h.fence_c and h.lang_n < h.lang.len) {
                    h.lang[h.lang_n] = c[0];
                    h.lang_n += 1;
                }
            },
            .block => if (h.json and !h.diff) try h.jsonChar(c) else try h.emit(c, h.line),
            .header => try h.buffer(c),
        }
    }

    /// What may still be the opening of a line rather than its text.
    fn holds(h: *const Highlighter, b: u8) bool {
        if (h.opts.literal) return false;
        if (h.fence_c != 0) {
            // As far in as the fence opened, and then only its closing run.
            const held = h.hold[0..h.held];
            const in = std.mem.indexOfNone(u8, held, " ") orelse held.len;
            if (b == ' ') return in == held.len and held.len < h.fence_at;
            const all = for (held[in..]) |x| {
                if (x != h.fence_c) break false;
            } else true;
            return b == h.fence_c and all;
        }
        return std.mem.indexOfScalar(u8, " >-*_+#0123456789.)`~", b) != null;
    }

    /// The line's opening is known, so write it. `next` is the character that
    /// decided it, or null when the line ended.
    fn resolve(h: *Highlighter, next: ?[]const u8) Error!void {
        const held = h.hold[0..h.held];
        h.held = 0;

        if (h.opts.literal) {
            h.line = h.opts.palette.indented;
            h.kind = .block;
            return h.emitAll(held, h.line);
        }

        if (h.fence_c != 0) {
            const in = std.mem.indexOfNone(u8, held, " ") orelse held.len;
            if (next == null and held.len - in >= h.fence_n) {
                try h.emitAll(held, h.opts.palette.fence);
                h.fence_c = 0;
                h.json = false;
                h.kind = .text;
                return;
            }
            // A diff says what a line is by its first character inside the
            // fence's own indent.
            const first = if (held.len > h.fence_at)
                held[h.fence_at]
            else if (held.len == h.fence_at and next != null) next.?[0] else 0;
            h.line = if (!h.diff) h.opts.palette.block else switch (first) {
                '+' => h.opts.palette.added,
                '-' => h.opts.palette.removed,
                '@' => h.opts.palette.hunk,
                else => h.opts.palette.context,
            };
            h.kind = .block;
            return h.emitAll(held, if (h.json and !h.diff) h.opts.palette.json_sep else h.line);
        }

        // At the start of a line, or at the indent of the list item it is
        // in. One inside a quote is not a fence here.
        const in = std.mem.indexOfNone(u8, held, " ") orelse held.len;
        if ((in == 0 or in == h.pad) and held.len >= in + 3 and (held[in] == '`' or held[in] == '~')) {
            const run = std.mem.indexOfNone(u8, held[in..], held[in .. in + 1]) orelse held.len - in;
            if (run >= 3) {
                h.fence_c = held[in];
                h.fence_n = run;
                h.fence_at = in;
                h.para = false;
                if (in == 0) h.pad = 0;
                h.lang_n = 0;
                h.kind = .fence;
                h.columns = null;
                try h.emitAll(held[0..in], .{});
                try h.emitAll(held[in .. in + run], h.opts.palette.fence);
                for (held[in + run ..]) |b| try h.char(&.{b});
                return;
            }
        }

        const spaces = std.mem.indexOfNone(u8, held, " ") orelse held.len;
        if (next == null and spaces == held.len) {
            h.para = false;
        } else if (!h.para) {
            if (spaces < h.pad) h.pad = 0;
            if (spaces >= h.pad + 4) {
                h.columns = null;
                h.line = h.opts.palette.indented;
                h.kind = .block;
                return h.emitAll(held, h.line);
            }
        }

        var i: usize = 0;
        h.cont_n = 0;
        while (i < held.len and (held[i] == ' ' or held[i] == '>')) : (i += 1) {
            try h.emit(held[i .. i + 1], if (held[i] == '>') h.opts.palette.quote else .{});
            h.indent(held[i]);
        }
        const rest = held[i..];
        h.kind = .text;

        if (next == null and isRule(rest)) {
            h.columns = null;
            h.para = false;
            h.pad = 0;
            return h.emitAll(rest, h.opts.palette.rule);
        }
        const hashes = std.mem.indexOfNone(u8, rest, "#") orelse rest.len;
        if (hashes >= 1 and hashes <= 6 and (if (hashes < rest.len) rest[hashes] == ' ' else next == null)) {
            h.columns = null;
            h.para = false;
            h.pad = 0;
            h.kind = .heading;
            try h.emitAll(rest[0..hashes], h.opts.palette.hash);
            return h.emitAll(rest[hashes..], h.opts.palette.heading);
        }
        if (rest.len == 0 and next != null and std.mem.eql(u8, next.?, "|")) {
            h.para = false;
            h.pad = 0;
            h.row_base = h.col;
            h.row_k = 0;
            if (h.columns == null) {
                h.kind = .header;
                h.row_n = 0;
            } else h.kind = .row;
            return;
        }
        h.columns = null;

        const marker = listMarker(rest);
        if (marker > 0) h.pad = i + marker;
        if (next != null or rest.len > 0) h.para = true;
        try h.emitAll(rest[0..marker], h.opts.palette.list);
        for (0..marker) |_| h.indent(' ');
        h.prev = .space;
        for (rest[marker..]) |b| try h.text(&.{b});
    }

    fn indent(h: *Highlighter, b: u8) void {
        if (h.cont_n == h.cont.len) return;
        h.cont[h.cont_n] = b;
        h.cont_n += 1;
    }

    /// The first line of a table, kept whole until it says how many columns.
    fn buffer(h: *Highlighter, c: []const u8) Error!void {
        if (h.row_n + c.len > h.row_buf.len) {
            // Too long to wait for: what has been seen will have to do.
            var keep: [4]u8 = undefined;
            @memcpy(keep[0..c.len], c);
            try h.replay();
            return h.char(keep[0..c.len]);
        }
        @memcpy(h.row_buf[h.row_n..][0..c.len], c);
        h.row_n += c.len;
    }

    fn replay(h: *Highlighter) Error!void {
        const row = h.row_buf[0..h.row_n];
        h.columns = @max(1, std.mem.count(u8, row, "|") -| 1);
        h.kind = .row;
        h.header_row = true;
        h.row_n = 0;
        for (row) |b| try h.byte(b);
    }

    fn text(h: *Highlighter, c: []const u8) Error!void {
        const b = if (c.len == 1) c[0] else 0;
        if (h.run_n > 0 and b != h.run_c) try h.settle(b);
        if ((b == '`' or (h.code == 0 and (b == '*' or b == '_' or b == '~'))) and b != 0) {
            h.run_c = b;
            h.run_n += 1;
            return;
        }
        if (h.code > 0) return h.emit(c, h.current());
        if (b == '|' and h.kind == .row) return h.pipe();
        if (b == '[') h.bracket = true;
        if (b == '(' and h.last == ']' and h.bracket) h.link = true;
        try h.emit(c, h.current());
        if (b == ')') h.link = false;
        h.last = b;
        h.prev = if (b == ' ' or b == '\t') .space else if (std.ascii.isAlphanumeric(b) or (b == 0 and !pictograph(c))) .word else .punct;
    }

    /// A run of delimiters, now that what follows it is known. `next` is 0 at
    /// the end of the line.
    fn settle(h: *Highlighter, next: u8) Error!void {
        const n = h.run_n;
        const c = h.run_c;
        h.run_n = 0;
        const opens = h.prev != .word and next != 0 and next != ' ' and next != '\t';
        const closes = h.prev != .space;
        defer {
            h.prev = .punct;
            h.last = c;
        }

        if (c == '`') {
            if (h.code == n) {
                try h.emitRun(c, n, h.current());
                h.code = 0;
            } else {
                if (h.code == 0 and h.prev != .word and next != 0) h.code = n;
                try h.emitRun(c, n, h.current());
            }
            return;
        }

        var strong = h.strong;
        var emphasis = h.emphasis;
        var struck = h.struck;
        if (c == '~') {
            if (n <= 2) struck = toggle(struck, opens, closes);
        } else {
            if (n != 2) emphasis = toggle(emphasis, opens, closes);
            if (n >= 2) strong = toggle(strong, opens, closes);
        }
        // A delimiter wears whichever of the two styles is the wider.
        const was = h.current();
        h.strong = strong or h.strong;
        h.emphasis = emphasis or h.emphasis;
        h.struck = struck or h.struck;
        try h.emitRun(c, n, h.current().with(was));
        h.strong = strong;
        h.emphasis = emphasis;
        h.struck = struck;
    }

    fn toggle(on: bool, opens: bool, closes: bool) bool {
        return if (on) !closes else opens;
    }

    fn current(h: *const Highlighter) Style {
        var s: Style = if (h.kind == .row and h.header_row) h.opts.palette.header else .{};
        if (h.code > 0) return s.with(h.opts.palette.code);
        if (h.strong) s = s.with(h.opts.palette.strong);
        if (h.emphasis) s = s.with(h.opts.palette.emphasis);
        if (h.struck) s = s.with(h.opts.palette.strike);
        if (h.link) s = s.with(h.opts.palette.link);
        return s;
    }

    /// A column's `|`, at its share of the width, or a space past the last
    /// character when the cell is already wider than that. The last column
    /// gets three shares, as it often holds the longest and is encroached.
    fn pipe(h: *Highlighter) Error!void {
        const columns = h.columns orelse 1;
        if (h.opts.reflow and h.opts.width > h.row_base + 1 and h.row_k > 0) {
            const shares = h.row_k + @as(usize, if (h.row_k >= columns) 2 else 0);
            const at = h.row_base + shares * (h.opts.width - h.row_base - 1) / (columns + 2);
            try h.set(h.opts.palette.pipe);
            if (h.col < at) {
                while (h.col < at) : (h.col += 1) try h.out.writeByte(' ');
            } else if (h.col > at) {
                try h.out.writeByte(' ');
                h.col += 1;
            }
        }
        try h.emit("|", h.opts.palette.pipe);
        h.row_k += 1;
        h.prev = .space;
        h.last = '|';
    }

    /// JSON is intentionally only a lexical guess; a tiny delimiter stack
    /// distinguishes object keys from array strings, without validating contents.
    fn jsonChar(h: *Highlighter, c: []const u8) Error!void {
        if (c.len != 1) return h.emit(c, if (h.json_string) (if (h.json_string_key) h.opts.palette.json_key else h.opts.palette.json_string) else h.opts.palette.json_sep);
        const b = c[0];
        if (h.json_string) {
            const separator = !h.json_escape and (b == '\\' or (h.json_string_key and b == '"'));
            try h.emit(c, if (separator) h.opts.palette.json_sep else if (h.json_string_key) h.opts.palette.json_key else h.opts.palette.json_string);
            if (h.json_escape) h.json_escape = false else if (b == '\\') h.json_escape = true else if (b == '"') {
                h.json_string = false;
                if (!h.json_string_key) h.json_key_expected = false;
            }
            return;
        }
        if (b == '"') {
            h.json_string = true;
            h.json_string_key = h.json_key_expected;
            return h.emit(c, if (h.json_string_key) h.opts.palette.json_sep else h.opts.palette.json_string);
        }
        switch (b) {
            '{', '[' => {
                if (h.json_depth < h.json_objects.len) {
                    h.json_objects[h.json_depth] = b == '{';
                    h.json_depth += 1;
                }
                h.json_key_expected = b == '{';
            },
            '}', ']' => {
                if (h.json_depth > 0) h.json_depth -= 1;
                h.json_key_expected = false;
            },
            ',' => h.json_key_expected = h.json_depth > 0 and h.json_objects[h.json_depth - 1],
            ':' => h.json_key_expected = false,
            else => {},
        }
        const atom = std.ascii.isAlphanumeric(b) or std.mem.indexOfScalar(u8, "-.+", b) != null;
        return h.emit(c, if (atom) h.opts.palette.json_atom else h.opts.palette.json_sep);
    }

    fn endLine(h: *Highlighter) Error!void {
        if (h.kind == .opening) try h.resolve(null);
        if (h.kind == .header) try h.replay();
        if (h.run_n > 0) try h.settle(0);
        if (h.kind == .fence) {
            h.diff = std.mem.eql(u8, h.lang[0..h.lang_n], "diff");
            h.json = std.mem.eql(u8, h.lang[0..h.lang_n], "json");
            h.json_depth = 0;
            h.json_key_expected = false;
            h.json_string = false;
            h.json_escape = false;
        }
        try h.set(.{});
        h.header_row = false;
        h.strong = false;
        h.emphasis = false;
        h.struck = false;
        h.link = false;
        h.bracket = false;
        h.code = 0;
        h.json_string = false;
        h.json_escape = false;
        h.prev = .space;
        h.last = 0;
        h.kind = .opening;
        h.held = 0;
        h.col = h.lead_cells;
        h.owed = 0;
    }

    fn emitRun(h: *Highlighter, c: u8, n: usize, s: Style) Error!void {
        for (0..n) |_| try h.emit(&.{c}, s);
    }

    fn emitAll(h: *Highlighter, bytes: []const u8, s: Style) Error!void {
        var i: usize = 0;
        while (i < bytes.len) {
            const len = @min(std.unicode.utf8ByteSequenceLength(bytes[i]) catch 1, bytes.len - i);
            try h.emit(bytes[i..][0..len], s);
            i += len;
        }
    }

    /// One character, breaking the line first when it would not fit. What
    /// opens the broken line is plain, and the style carries on after it.
    fn emit(h: *Highlighter, c: []const u8, s: Style) Error!void {
        const cp = std.unicode.utf8Decode(c) catch 0xfffd;
        const cells: usize = if (cp == '\t') 8 - h.col % 8 else width(cp);
        const floor = h.lead_cells + h.cont_n;
        if (h.opts.reflow and h.opts.width > 0 and h.kind == .text and h.code == 0 and
            h.col + cells > h.opts.width and h.col > floor)
        {
            try h.set(.{});
            try h.out.writeByte('\n');
            try h.out.writeAll(h.lead);
            try h.out.writeAll(h.cont[0..h.cont_n]);
            h.col = floor;
        }
        try h.set(s);
        try h.out.writeAll(c);
        h.col += cells;
    }

    fn set(h: *Highlighter, s: Style) Error!void {
        if (!h.opts.color or std.meta.eql(h.style, s)) return;
        try s.write(h.out);
        h.style = s;
    }
};

/// Whether a character is a pictograph rather than a letter of some script, so
/// that what follows an emoji, such as the span after a 🔏, opens as it would
/// after punctuation.
fn pictograph(c: []const u8) bool {
    const cp = std.unicode.utf8Decode(c) catch return false;
    return (cp >= 0x1F300 and cp <= 0x1FAFF) or (cp >= 0x2600 and cp <= 0x27BF);
}

/// Three or more of one of `-`, `*` or `_`, and spaces.
fn isRule(s: []const u8) bool {
    var c: u8 = 0;
    var n: usize = 0;
    for (s) |b| {
        if (b == ' ') continue;
        if (c == 0 and std.mem.indexOfScalar(u8, "-*_", b) != null) c = b;
        if (b != c) return false;
        n += 1;
    }
    return n >= 3;
}

/// How long a list marker at the start of `s` is, its space included, or 0.
fn listMarker(s: []const u8) usize {
    if (s.len >= 2 and std.mem.indexOfScalar(u8, "-*+", s[0]) != null and s[1] == ' ') return 2;
    const digits = std.mem.indexOfNone(u8, s, "0123456789") orelse return 0;
    if (digits == 0 or digits > 9 or digits + 1 >= s.len) return 0;
    if ((s[digits] == '.' or s[digits] == ')') and s[digits + 1] == ' ') return digits + 2;
    return 0;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// What `src` looks like, each change of style written `{params}` so a test
/// can read it: `{}` is plain, `{1}` bold, `{38;5;245}` a colour.
fn shown(src: []const u8, opts: Options, lead: []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var h: Highlighter = .init(&out.writer, opts, lead);
    try h.write(src);
    try h.finish();
    var tagged: std.ArrayList(u8) = .empty;
    errdefer tagged.deinit(testing.allocator);
    var it = std.mem.splitSequence(u8, out.written(), "\x1b[0");
    try tagged.appendSlice(testing.allocator, it.first());
    while (it.next()) |part| {
        const m = std.mem.indexOfScalar(u8, part, 'm').?;
        const params = if (m > 0) part[1..m] else "";
        try tagged.print(testing.allocator, "{{{s}}}{s}", .{ params, part[m + 1 ..] });
    }
    return tagged.toOwnedSlice(testing.allocator);
}

fn expectShown(want: []const u8, src: []const u8, opts: Options) !void {
    const got = try shown(src, opts, "");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(want, got);
}

test "compact palette syntax composes and validates" {
    var p: Palette = .{};
    try parsePalette(&p, "quote:fgt4bg255+i_!/,strong:-+i,strong:fg1");
    try testing.expectEqual(@as(?u16, 260), p.quote.fg);
    try testing.expectEqual(@as(?u16, 255), p.quote.bg);
    try testing.expect(p.quote.italic and p.quote.underline and p.quote.inverse and p.quote.strike);
    try testing.expectEqual(@as(?u16, 1), p.strong.fg);
    try testing.expect(!p.strong.bold and !p.strong.faint and !p.strong.italic);
    try parsePalette(&p, "quote:+-,list:-+");
    try testing.expect(!p.quote.bold and p.quote.faint);
    try testing.expect(p.list.bold and !p.list.faint);
    try parsePalette(&p, "");
    try testing.expectError(error.BadHighlight, parsePalette(&p, "nope:fg1"));
    try parsePalette(&p, "table:pipe:fg8");
    try testing.expectEqual(@as(?u16, 8), p.pipe.fg);
    try testing.expectError(error.BadHighlight, parsePalette(&p, "quote:fg256"));
    try testing.expectError(error.BadHighlight, parsePalette(&p, "quote:fgt16"));
    try testing.expectError(error.BadHighlight, parsePalette(&p, "quote:f"));
}
test "quote, list, and heading marker styles are independent" {
    var opts: Options = .{};
    opts.palette.quote = .{ .fg = 1 };
    opts.palette.list = .{ .fg = 2 };
    opts.palette.hash = .{ .fg = 3 };
    try expectShown("{38;5;1}>{} quote\n{38;5;2}- {}list\n{38;5;3}##{1;38;5;75} heading{}", "> quote\n- list\n## heading", opts);
}

test "terminal palette indices use ANSI foreground and background codes" {
    var opts: Options = .{};
    opts.palette.quote = .{ .fg = 256, .bg = 271 };
    try expectShown("{30;107}>{} x", "> x", opts);
    opts.palette.quote = .{ .fg = 263, .bg = 264 };
    try expectShown("{37;100}>{} x", "> x", opts);
}
test "every character arrives, and nothing else does without colour or reflow" {
    const src = "# t\n> - **a** `b` [c](d)\n```diff\n+x\n```\n| a | b |\n|---|---|\n---\n";
    try expectShown(src, src, .{ .color = false, .reflow = false, .width = 4 });
}

test "emphasis opens with no word before and no space after, and ends with its line" {
    try expectShown("{1;38;5;231}**a**{} b", "**a** b", .{});
    try expectShown("{3}*a*{}", "*a*", .{});
    try expectShown("{1;3;38;5;231}***a***{}", "***a***", .{});
    try expectShown("{9}~~a~~{}", "~~a~~", .{});
    // A word before, or a space after, and it is only text.
    try expectShown("snake_case_name a * b", "snake_case_name a * b", .{});
    // Never closed, so the line's end closes it.
    try expectShown("{1;38;5;231}**a{}\nb", "**a\nb", .{});
}

test "a code span opens after an emoji as after punctuation, but not after a letter" {
    try expectShown("\u{1F50F}{38;5;180}`a-_b_`{}", "\u{1F50F}`a-_b_`", .{});
    try expectShown("\u{00E9}`a`", "\u{00E9}`a`", .{});
}

test "a code span holds everything inside it" {
    try expectShown("{38;5;180}`*a*`{} {3}*b*{}", "`*a*` *b*", .{});
    try expectShown("{38;5;180}``a`b``{}", "``a`b``", .{});
}

test "code spans allow whitespace at either edge and close only on a matching run" {
    try expectShown("{38;5;180}`` a ``{} plain", "`` a `` plain", .{});
    try expectShown("{38;5;180}` leading`{} plain", "` leading` plain", .{});
    try expectShown("{38;5;180}`trailing `{} plain", "`trailing ` plain", .{});
    try expectShown("{38;5;180}`   `{} plain", "`   ` plain", .{});
    try expectShown("{38;5;180}`\ta\t`{} plain", "`\ta\t` plain", .{});
    try expectShown("{38;5;180}`` `a` ``` b ``{} plain", "`` `a` ``` b `` plain", .{});
    // An unmatched opener colours only the rest of its line.
    try expectShown("{38;5;180}` *a*{}\nplain", "` *a*\nplain", .{});
}

test "a link is what follows the brackets" {
    try expectShown("[a]{4;38;5;75}(b){} [c] (d)", "[a](b) [c] (d)", .{});
}

test "a marker is coloured, and nothing after it" {
    try expectShown("{38;5;245}>{} {38;5;245}- {}a", "> - a", .{});
    try expectShown("{38;5;245}12. {}a", "12. a", .{});
    try expectShown("3.14 a", "3.14 a", .{});
    try expectShown("{38;5;245}##{1;38;5;75} a *b*{}", "## a *b*", .{});
    try expectShown("#a", "#a", .{});
}

test "a rule is told from a list and from emphasis" {
    try expectShown("{38;5;245}- - -{}", "- - -", .{});
    try expectShown("{38;5;245}***{}", "***", .{});
    try expectShown("{38;5;245}- --{}", "- --", .{});
    try expectShown("{38;5;245}- {}-x", "- -x", .{});
}

test "json fences highlight strings, keywords and numbers without changing text" {
    var opts: Options = .{};
    opts.palette.block = .{ .fg = 6 };
    opts.palette.code = .{ .fg = 8 };
    opts.palette.heading = .{ .fg = 9 };
    try parsePalette(&opts.palette, "json:string:fg3,json:key:fg1,json:atom:fg4,json:sep:fg2");
    try expectShown(
        "{38;5;245}```json{}\n{38;5;2}{\"{38;5;1}key{38;5;2}\": {38;5;4}true{38;5;2}, \"{38;5;1}s{38;5;2}\\{38;5;1}\"éx{38;5;2}\": {38;5;4}-12.5e+2{38;5;2}}{}\n{38;5;245}```{}\ntrue",
        "```json\n{\"key\": true, \"s\\\"éx\": -12.5e+2}\n```\ntrue",
        opts,
    );
    try expectShown(
        "{38;5;245}```json{}\n{38;5;2}{\"{38;5;1}outer{38;5;2}\":[{\"{38;5;1}k{38;5;2}\":{38;5;3}\"v\"{38;5;2}}]}{}\n{38;5;245}```{}",
        "```json\n{\"outer\":[{\"k\":\"v\"}]}\n```",
        opts,
    );
    try expectShown(
        "{38;5;245}```json{}\n{38;5;2}[{38;5;3}\"q{38;5;2}\\{38;5;3}\" b{38;5;2}\\{38;5;3}\\ n{38;5;2}\\{38;5;3}n u{38;5;2}\\{38;5;3}u1234\"{38;5;2}]{}\n{38;5;245}```{}",
        "```json\n[\"q\\\" b\\\\ n\\n u\\u1234\"]\n```",
        opts,
    );
    try expectShown(
        "{38;5;245}```json{}\n{38;5;2}{\"\":{38;5;4}0{38;5;2},\"{38;5;1}tail{38;5;2}\\{38;5;1}\\{38;5;2}\":{38;5;4}1{38;5;2}}{}\n{38;5;245}```{}",
        "```json\n{\"\":0,\"tail\\\\\":1}\n```",
        opts,
    );
    try expectShown(
        "{38;5;245}```json{}\n{38;5;4}false{38;5;2} {38;5;4}null{}\n{38;5;245}```{}",
        "```json\nfalse null\n```",
        opts,
    );
    opts.color = false;
    try expectShown("```json\n{\"x\\\\y\": \"é\", \"v\": false}\n```", "```json\n{\"x\\\\y\": \"é\", \"v\": false}\n```", opts);
}

test "a fence holds until it closes, and a diff is coloured a line at a time" {
    try expectShown(
        "{38;5;245}```diff{}\n{38;5;2}+a{}\n{38;5;1}-b{}\n{38;5;6}@@{}\n c\n{38;5;245}```{}\n{3}*d*{}",
        "```diff\n+a\n-b\n@@\n c\n```\n*d*",
        .{},
    );
    try expectShown("{38;5;245}```{}\n{38;5;180}*a*{}\n{38;5;245}````{}", "```\n*a*\n````", .{});
    // Only at the start of a line; inside a quote it is only backticks.
    try expectShown("{38;5;245}>{} {38;5;180}```a{}", "> ```a", .{});
    // Never closed, and the block's end closes it.
    try expectShown("{38;5;245}~~~{}\n{38;5;180}a{}", "~~~\na", .{});
}

test "a fence opens at its list item's indent, and is read from there" {
    try expectShown(
        "{38;5;245}1. {}a\n   {38;5;245}```diff{}\n{38;5;2}   +*b*{}\n{38;5;245} ```{}\n{38;5;245}- {3}*c*{}",
        "1. a\n   ```diff\n   +*b*\n ```\n- *c*",
        .{},
    );
    // Not at the item's indent, and it is only backticks.
    try expectShown("{38;5;245}- {}a\n {38;5;180}```b{}", "- a\n ```b", .{});
}

test "a table's pipes take their share of the width, or a space past a wide cell" {
    try expectShown(
        "| a  | b    |\n| ---  | ---  |\n| ccccc  | d  |\nx",
        "| a | b |\n| --- | --- |\n| ccccc | d |\nx",
        .{ .color = false, .width = 13 },
    );
    // The first line is the header.
    try expectShown("{38;5;245}|{1} a {38;5;245}|{}\n{38;5;245}|{} b {38;5;245}|{}", "| a |\n| b |", .{});
}

test "a table's last column gets three times the width share" {
    try expectShown(
        "| a | b | c         |",
        "| a | b | c |",
        .{ .color = false, .width = 21 },
    );
    // A single column still uses the whole available width.
    try expectShown("| a     |", "| a |", .{ .color = false, .width = 9 });
    // Without reflow, table spacing is left alone.
    try expectShown("| a | b | c |", "| a | b | c |", .{ .color = false, .reflow = false, .width = 17 });
}

test "a long line is broken at the width, carrying its quote and indent" {
    const got = try shown("> - abcdef", .{ .color = false, .width = 8 }, "| ");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("> - ab\n| >   cd\n| >   ef", got);
}

test "a broken line carries its style past its quote and indent" {
    const got = try shown("> **abcdef**", .{ .width = 6 }, "| ");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("{38;5;245}>{} {1;38;5;231}**{}\n| > {1;38;5;231}ab{}\n| > {1;38;5;231}cd{}\n| > {1;38;5;231}ef{}\n| > {1;38;5;231}**{}", got);
}

test "a line indented four past its list item is literal, unless it continues a paragraph" {
    try expectShown("{38;5;181}    *a* `b`{}", "    *a* `b`", .{});
    try expectShown("\n{38;5;181}    *a*{}", "\n    *a*", .{});
    // Continuing a paragraph, and inside a list item's own indent.
    try expectShown("a\n    {3}*b*{}", "a\n    *b*", .{});
    try expectShown("{38;5;245}- {}a\n\n    {3}*b*{}", "- a\n\n    *b*", .{});
    try expectShown("{38;5;245}- {}a\n\n{38;5;181}      *b*{}", "- a\n\n      *b*", .{});
    // A line back at the margin ends the item.
    try expectShown("{38;5;245}- {}a\n\nb\n\n{38;5;181}    *c*{}", "- a\n\nb\n\n    *c*", .{});
    // Literal lines run on, since they open no paragraph.
    try expectShown("{38;5;181}    *a*{}\n{38;5;181}    *b*{}", "    *a*\n    *b*", .{});
}

test "a code span is never broken, and what follows it is" {
    try expectShown("`abcdef`\ngh", "`abcdef`gh", .{ .color = false, .width = 4 });
}

test "wide characters count as two" {
    try expectShown("ab\n漢c", "ab漢c", .{ .color = false, .width = 3 });
}
