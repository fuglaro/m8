//! `tail` — the last record of a document.
//!
//! What `m8 @x` writes ends on the 🧠 of the turn it kept, and what a run
//! says ends on its reply. Both are the last record of something, and this
//! is how either is taken out: whole, as its value, or as its block with the
//! m8 around it gone.
//!
//! Nothing is resolved. A 🧠 is a record like any other here, so reading the
//! last thing a chat said means expanding it first, with `m8 encode`.
//!
//! A line at a time, the way `exclude` reads, and holding one record: the
//! last one so far that could be the answer. What it is handed may be a whole
//! chat or everything a tool said, and neither has to fit in memory for its
//! last record to be found.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "tail",
    .summary = "the last record of a document, or the last of some kind",
    // Stdin is this command's own, because it reads it as it arrives rather
    // than being handed all of it.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 tail [--sigil SIGIL]... [--value | --block]
        \\
        \\Writes the last record of the document on stdin. With `--sigil`,
        \\the last one of that kind; said more than once, the last of any of
        \\them. SIGIL is a sigil's plain spelling without the colons:
        \\`robot`, `question`, `brain`.
        \\
        \\  --value    the rest of its header line, and nothing else
        \\  --block    its block, as the text it holds
        \\
        \\  m8 @x -- hi | m8 tail                      the 🧠 of the turn kept
        \\  m8 ref "@$(m8 @x -- hi | m8 tail --value)" the same, as an address
        \\  m8 ref @x | m8 encode | m8 tail --sigil robot --sigil question --block
        \\
        \\A record with no value has none to write, and one with no block has
        \\no block, so either is an error rather than an empty line: what reads
        \\this is usually about to use it as a name.
        \\
        \\Nothing is resolved. `m8 encode` expands a 🧠 into what it names.
        \\
        \\Read a line at a time, holding only the last record that could be
        \\the answer, so a document may be longer than there is memory for.
        \\
    );
}

const Part = enum { record, value, block };

fn run(ctx: Ctx) !u8 {
    var wanted: std.ArrayList(sigil.Sigil) = .empty;
    var part: Part = .record;

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        if (std.mem.eql(u8, arg, "--sigil")) {
            i += 1;
            if (i == ctx.args.len) {
                try ctx.err.writeAll("m8 tail: --sigil needs a sigil's name\n");
                return 1;
            }
            try wanted.append(ctx.arena, sigil.named(ctx.args[i]) orelse {
                try ctx.err.print("m8 tail: '{s}' is not a sigil\n", .{ctx.args[i]});
                return 1;
            });
        } else if (std.mem.eql(u8, arg, "--value") and part == .record) {
            part = .value;
        } else if (std.mem.eql(u8, arg, "--block") and part == .record) {
            part = .block;
        } else {
            try ctx.err.print("m8 tail: '{s}' is not something it takes; see m8 tail --help\n", .{arg});
            return 1;
        }
    }

    var buf: [64 * 1024]u8 = undefined;
    const in = std.Io.File.stdin();
    if (try in.isTty(ctx.io)) {
        try ctx.err.writeAll("m8 tail: pipe in a document\n");
        return 1;
    }
    var r = in.readerStreaming(ctx.io, &buf);
    return write(ctx, &r.interface, wanted.items, part);
}

/// The last record on `r` that is one of `wanted`, or the last at all when
/// nothing was named. Null when there is none.
///
/// A record announces its kind on its first line, so whether it could be the
/// answer is known before any of it is kept. One that could is held as the
/// lines it arrived as, and let go of when a later one takes its place — so
/// what is held is never more than a record. Only the one left at the end is
/// parsed, which is the same reading every other command gives a record.
fn last(ctx: Ctx, r: *std.Io.Reader, wanted: []const sigil.Sigil) !?doc.Record {
    var mode: ?doc.Mode = null;
    var held: std.ArrayList(u8) = .empty;
    var holding = false;

    while (true) {
        // A last line with no newline on it is still a line.
        var ended = false;
        var raw: []const u8 = undefined;
        if (r.takeDelimiterInclusive('\n')) |line| {
            raw = line;
        } else |e| switch (e) {
            error.EndOfStream => {
                raw = r.buffered();
                if (raw.len == 0) break;
                ended = true;
            },
            else => return e,
        }
        const line = std.mem.trimEnd(u8, raw, "\n");

        if (mode == null) {
            if (std.mem.trim(u8, line, " \t\r").len == 0) {
                if (ended) break;
                continue;
            }
            mode = doc.detect(line) orelse return error.NotADocument;
        }

        const head = doc.header(mode.?);
        if (std.mem.startsWith(u8, line, head)) {
            const m = sigil.match(mode.?, line[head.len..]);
            // A header nothing can name is still where a record starts. With
            // nothing named it may be the last one, and is said to be wrong
            // when it is read rather than skipped for the one before it.
            holding = wanted.len == 0 or
                (m != null and std.mem.indexOfScalar(sigil.Sigil, wanted, m.?.sigil) != null);
            if (holding) held.clearRetainingCapacity();
        }
        if (holding) {
            try held.appendSlice(ctx.arena, line);
            try held.append(ctx.arena, '\n');
        }
        if (ended) break;
    }

    if (held.items.len == 0) return null;
    var diag: doc.Diagnostic = .{};
    const records = doc.parseMode(ctx.arena, held.items, mode.?, &diag) catch |e| {
        try ctx.err.print("m8 tail: the last record: {s}\n", .{diag.detail});
        return e;
    };
    return records[0];
}

fn write(ctx: Ctx, r: *std.Io.Reader, wanted: []const sigil.Sigil, part: Part) !u8 {
    const found = last(ctx, r, wanted) catch |e| switch (e) {
        error.NotADocument => {
            try ctx.err.writeAll("m8 tail: pipe in a document\n");
            return 1;
        },
        else => return e,
    } orelse {
        try ctx.err.writeAll(if (wanted.len == 0)
            "m8 tail: pipe in a document\n"
        else
            "m8 tail: no record of that kind in this document\n");
        return 1;
    };

    switch (part) {
        .record => try doc.write(ctx.out, ctx.mode, found),
        .value => {
            if (found.value.len == 0) {
                try ctx.err.print("m8 tail: the last {s} has no value\n", .{found.sigil.word()});
                return 1;
            }
            try ctx.out.writeAll(found.value);
            try ctx.out.writeByte('\n');
        },
        .block => {
            const said = found.content orelse {
                try ctx.err.print("m8 tail: the last {s} has no block\n", .{found.sigil.word()});
                return 1;
            };
            try ctx.out.writeAll(said);
            try ctx.out.writeByte('\n');
        },
    }
    return 0;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Got = struct { status: u8, out: []const u8 };

/// Run it over some bytes with the options already read, the way a pipe does.
fn call(arena: std.mem.Allocator, wanted: []const sigil.Sigil, part: Part, in: []const u8) !Got {
    var env: std.process.Environ.Map = .init(arena);
    var r: std.Io.Reader = .fixed(in);
    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    const status = try write(.{
        .arena = arena,
        .io = undefined,
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = "",
        .out = &out.writer,
        .err = &err.writer,
        .tty = null,
    }, &r, wanted, part);
    return .{ .status = status, .out = out.written() };
}

test "what m8 @ writes ends on the 🧠 it kept, whole or as a name" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const said = "#### :robot:\n> hi\n\n#### :brain:x/+/abcdefghij\n";
    try testing.expectEqualStrings("#### :brain:x/+/abcdefghij\n", (try call(arena, &.{}, .record, said)).out);
    try testing.expectEqualStrings("x/+/abcdefghij\n", (try call(arena, &.{}, .value, said)).out);
    // A last line with no newline on it is still the last record.
    try testing.expectEqualStrings(
        "x/+/abcdefghij\n",
        (try call(arena, &.{}, .value, "#### :robot:\n> hi\n\n#### :brain:x/+/abcdefghij")).out,
    );
}

test "a record with nothing to give is an error, not an empty line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // A turn nobody kept ends on its reply, and a reply has no value: handed
    // on as a name it would read as the main chat.
    const sent = "#### :brain:x/+/parent\n\n#### :raising_hand:\n> hi\n\n#### :robot:\n> hello\n";
    const value = try call(arena, &.{}, .value, sent);
    try testing.expectEqual(@as(u8, 1), value.status);
    try testing.expectEqualStrings("", value.out);

    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{.agent}, .block, sent)).status);
    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{.question}, .record, sent)).status);
    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{}, .record, "just text\n")).status);
    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{}, .record, "")).status);

    // A last header that is not a sigil is not passed over for the record
    // before it: what was asked for is the last one, and it cannot be read.
    try testing.expectError(
        error.UnknownSigil,
        call(arena, &.{}, .value, "#### :brain:x/+/abcdefghij\n\n#### :nonsense:\n"),
    );
}

test "the last of any kind named, as the text it holds" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ledger = "#### :robot:\n> first\n\n#### :raising_hand:\n> more\n\n" ++
        "#### :robot:\n> second\n>\n> line\n\n#### :brain:x/+/abcdefghij\n";
    const picks = [_]sigil.Sigil{ .bot, .question };
    try testing.expectEqualStrings("second\n\nline\n", (try call(arena, &picks, .block, ledger)).out);

    const asked = ledger ++ "\n#### :question:tool,c1\n> deploy to prod?\n";
    try testing.expectEqualStrings("deploy to prod?\n", (try call(arena, &picks, .block, asked)).out);
    try testing.expectEqualStrings("tool,c1\n", (try call(arena, &.{}, .value, asked)).out);
}
