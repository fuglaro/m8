//! `filter` — read m8 and write it back with one kind of record gone.
//!
//! A line at a time, and never more than one line held. A filter sits in the
//! middle of a shield's pipe, where what comes through it is whatever a tool
//! decided to say — which may be more than there is memory for. Reading the
//! document whole to decide which records to drop would put a ceiling on a
//! tool's output that nothing else in m8 has.
//!
//! It does not need a parser for that. A record announces its kind on its
//! first line, and every line under it is quoted, so knowing whether to write
//! this line is one bool and the sigil that set it.
//!
//! One sigil per invocation, and nothing clever. Composition is what a shield
//! is for, so `m8 filter out toolbox` does exactly that and a shield that also
//! wants 🧠 and 📚 gone stacks another filter rather than asking this one to
//! have an opinion about what a reference might be carrying.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const Error = error{
    /// No `out`, or nothing after it.
    NothingNamed,
    /// A word that is not a sigil in the plain spelling.
    UnknownSigil,
};

pub const command: api.Command = .{
    .name = "filter",
    .summary = "write a document back with one kind of record gone",
    // Stdin is this command's own, because it reads it as it arrives rather
    // than being handed all of it.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 filter — write a document back with one kind of record gone
        \\
        \\  m8 filter out SIGIL
        \\
        \\SIGIL is a sigil's plain spelling without the colons: `toolbox`,
        \\`brain`, `books`. One kind per invocation, so a shield that wants
        \\several stacks several:
        \\
        \\  ▄ 🛡️freeze-toolbox
        \\  │ 🛡️filter-toolbox
        \\  │ 🛡️filter-brain
        \\
        \\Read a line at a time and never holding more than one, so a tool may
        \\say more than there is memory for and this will not be what stops it.
        \\
        \\Nothing is resolved. A 🧠 in a tool's answer is a way of acquiring a
        \\toolbox whatever it names, so closing that channel means naming the
        \\sigils that open it rather than reading what is behind them.
        \\
        \\Anything that is not a document is handed through as it is: most of
        \\what a tool says is text, and text has no records to take out.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len < 2 or !std.mem.eql(u8, ctx.args[0], "out")) {
        try ctx.err.writeAll("m8 filter: say what to take out, as `m8 filter out SIGIL`\n");
        return Error.NothingNamed;
    }

    const wanted = for (std.enums.values(sigil.Sigil)) |s| {
        const w = s.word();
        if (std.mem.eql(u8, w[1 .. w.len - 1], ctx.args[1])) break s;
    } else {
        try ctx.err.print("m8 filter: '{s}' is not a sigil\n", .{ctx.args[1]});
        return Error.UnknownSigil;
    };

    var buf: [64 * 1024]u8 = undefined;
    const in = std.Io.File.stdin();
    if (try in.isTty(ctx.io)) return 0;
    var r = in.readerStreaming(ctx.io, &buf);
    return through(ctx, &r.interface, wanted);
}

/// The state is one bool: whether the record being read is one to drop.
///
/// Which spelling the document is in is settled by its first line, the same
/// way it is settled anywhere else, and a line that is not a header belongs to
/// whatever header last claimed one.
fn through(ctx: Ctx, r: *std.Io.Reader, wanted: sigil.Sigil) !u8 {
    var mode: ?doc.Mode = null;
    var dropping = false;

    while (true) {
        const raw = r.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const line = std.mem.trimEnd(u8, raw, "\n");

        if (mode == null) {
            // Blank lines before anything say nothing about which spelling it
            // is in, so they are written and the question stays open.
            if (std.mem.trim(u8, line, " \t\r").len == 0) {
                try ctx.out.writeAll(raw);
                continue;
            }
            mode = doc.detect(line);
            // Not a document at all. Most of what a tool says is text, and
            // text has no records in it to take out.
            if (mode == null) {
                try ctx.out.writeAll(raw);
                _ = try r.streamRemaining(ctx.out);
                break;
            }
        }

        const head = doc.header(mode.?);
        if (std.mem.startsWith(u8, line, head)) {
            const m = sigil.match(mode.?, line[head.len..]);
            dropping = m != null and m.?.sigil == wanted;
        }

        if (!dropping) try ctx.out.writeAll(raw);
        try ctx.out.flush();
    }
    return 0;
}
