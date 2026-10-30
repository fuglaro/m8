//! `render` — a document, written the way a person reads it.
//!
//! Every other command writes markdown whatever stdout is, so that it says
//! the same thing to a terminal as to a pipe. This is where the rendered
//! spelling comes from instead: anything a command wrote, piped through here.
//!
//! It writes as it reads, a byte at a time once a line's opening is known, so
//! it can sit at the end of anything still talking. The rendered spelling
//! highlights markdown and breaks long lines, which is for reading and not for
//! reading back. `--parsable` keeps it to what still
//! parses once copied out of a terminal, and `-r` writes markdown back, which
//! makes it the thing that proves a document survives a round trip — line
//! endings normalised, quotes reapplied, nothing else touched.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const highlight = @import("../m8/highlight.zig");
const config = @import("../config.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "render",
    .summary = "write a document the way a person reads it",
    // Read as it arrives, rather than handed over whole once it has ended.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 render [-r] [--parsable] [--no-highlight]
        \\
        \\Reads a document on stdin and writes it in the emoji spelling,
        \\whatever stdout is, as it arrives. It is a pure filter: no network,
        \\and nothing is resolved. It asks only how wide the terminal is, or
        \\$COLUMNS.
        \\
        \\  m8 ref :demo/mathy | m8 encode | m8 render | less -R
        \\  m8 render <ledger.md
        \\
        \\Every 📜, 🤖, 💭 and 📲 is highlighted as markdown, and a line wider than the
        \\terminal is broken, carrying its quote and indent.
        \\🧾 and 🚫 blocks use the literal indent style, without markdown or wrapping.
        \\
        \\--parsable breaks no line and pads no table, so what a terminal shows
        \\parses again once copied out of it. The colour is still written, and
        \\a terminal leaves it behind; a file keeps it.
        \\
        \\--no-highlight writes no colour.
        \\
        \\  m8 render --parsable --no-highlight <ledger.md >shown.m8
        \\
        \\`-r` is raw: markdown, the spelling every file is kept in. A
        \\document survives that round trip with nothing changed but line
        \\endings and quotes, which is how to check that one parses.
        \\
        \\  m8 render -r <ledger.md >same.md
        \\
        \\A document that does not parse is an error naming the line, once
        \\everything before that line has been written.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var mode: doc.Mode = .m8;
    var look: doc.Look = .{ .width = highlight.terminalWidth(ctx.env) };
    for (ctx.args) |arg| {
        if (std.mem.eql(u8, arg, "-r")) {
            mode = .md;
        } else if (std.mem.eql(u8, arg, "--parsable")) {
            look.reflow = false;
        } else if (std.mem.eql(u8, arg, "--no-highlight")) {
            look.color = false;
        } else {
            try ctx.err.print("m8 render: '{s}' is not something it takes; see m8 render --help\n", .{arg});
            return 1;
        }
    }

    if (mode == .m8) {
        const configured = try config.highlights(ctx.arena, ctx.io, ctx.env);
        look.palette = configured.palette;
        look.wrap_literal = configured.wrap_literal;
        look.wrap_word = configured.wrap_word;
    }

    var diag: doc.Diagnostic = .{};
    var p: doc.Parser = .{ .arena = ctx.arena, .diag = &diag };
    var show: Show = .{ .out = ctx.out, .mode = mode, .look = look };
    var buf: [16 * 1024]u8 = undefined;
    var in = std.Io.File.stdin().readerStreaming(ctx.io, &buf);
    const r = &in.interface;
    while (true) {
        r.fillMore() catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        p.feed(r.buffered(), &show) catch |e| return failed(ctx, &show, &diag, e);
        r.tossBuffered();
        try ctx.out.flush();
    }
    p.finish(&show) catch |e| return failed(ctx, &show, &diag, e);
    return 0;
}

/// What was read is written out whole, and then what was wrong with the line
/// after it.
fn failed(ctx: Ctx, show: *Show, diag: *const doc.Diagnostic, e: anyerror) anyerror {
    if (show.body != null) try show.end();
    try ctx.out.flush();
    if (diag.detail.len == 0) return e;
    try ctx.err.print("m8 render: line {d}: {s}\n", .{ diag.line, diag.detail });
    return error.Said;
}

/// What the parser hands on, written straight back out: a blank line between
/// records, as `doc.writeAll` puts one.
const Show = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    look: doc.Look,
    body: ?doc.ContentWriter = null,
    lines: usize = 0,
    any: bool = false,

    pub fn begin(s: *Show, sigil: doc.Sigil, value: []const u8) !void {
        if (s.any) try s.out.writeByte('\n');
        s.any = true;
        s.body = try doc.ContentWriter.beginLooking(s.out, s.mode, s.look, sigil, value);
        s.lines = 0;
    }

    pub fn line(s: *Show) !void {
        if (s.lines > 0) try s.body.?.write("\n");
        s.lines += 1;
    }

    pub fn text(s: *Show, bytes: []const u8) !void {
        try s.body.?.write(bytes);
    }

    pub fn end(s: *Show) !void {
        if (s.lines > 0) try s.body.?.finish();
        s.body = null;
    }
};
