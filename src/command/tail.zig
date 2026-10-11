//! `tail` — the last record of a document.
//!
//! What `m8 @x` writes ends on the 🧠 of the turn it kept, and what a run
//! says ends on its reply. Both are the last record of something, and this
//! is how either is taken out: whole, as its value, or as its block with the
//! m8 around it gone.
//!
//! Nothing is resolved. A 🧠 is a record like any other here, so reading the
//! last thing a chat said means expanding it first, with `m8 encode`.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const sigil = @import("../m8/sigil.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "tail",
    .summary = "the last record of a document, or the last of some kind",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 tail — the last record of a document, or the last of some kind
        \\
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

    if (ctx.in.len == 0 or doc.detect(ctx.in) == null) {
        try ctx.err.writeAll("m8 tail: pipe in a document\n");
        return 1;
    }
    var diag: doc.Diagnostic = .{};
    const records = doc.parse(ctx.arena, ctx.in, &diag) catch |e| {
        try ctx.err.print("m8 tail: line {d}: {s}\n", .{ diag.line, diag.detail });
        return e;
    };

    const last = last: {
        var n = records.len;
        while (n > 0) : (n -= 1) {
            const r = records[n - 1];
            if (wanted.items.len == 0) break :last r;
            for (wanted.items) |s| if (r.sigil == s) break :last r;
        }
        try ctx.err.writeAll("m8 tail: no record of that kind in this document\n");
        return 1;
    };

    switch (part) {
        .record => try doc.write(ctx.out, ctx.mode, last),
        .value => {
            if (last.value.len == 0) {
                try ctx.err.print("m8 tail: the last {s} has no value\n", .{last.sigil.word()});
                return 1;
            }
            try ctx.out.writeAll(last.value);
            try ctx.out.writeByte('\n');
        },
        .block => {
            const said = last.content orelse {
                try ctx.err.print("m8 tail: the last {s} has no block\n", .{last.sigil.word()});
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

fn call(arena: std.mem.Allocator, args: []const []const u8, in: []const u8) !Got {
    var env: std.process.Environ.Map = .init(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    const status = try run(.{
        .arena = arena,
        .io = undefined,
        .mode = .md,
        .env = &env,
        .args = args,
        .in = in,
        .out = &out.writer,
        .err = &err.writer,
        .tty = null,
    });
    return .{ .status = status, .out = out.written() };
}

test "what m8 @ writes ends on the 🧠 it kept, whole or as a name" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const said = "#### :robot:\n> hi\n\n#### :brain:x/+/abcdefghij\n";
    try testing.expectEqualStrings("#### :brain:x/+/abcdefghij\n", (try call(arena, &.{}, said)).out);
    try testing.expectEqualStrings("x/+/abcdefghij\n", (try call(arena, &.{"--value"}, said)).out);
}

test "a record with nothing to give is an error, not an empty line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // A turn nobody kept ends on its reply, and a reply has no value: handed
    // on as a name it would read as the main chat.
    const sent = "#### :brain:x/+/parent\n\n#### :raising_hand:\n> hi\n\n#### :robot:\n> hello\n";
    const value = try call(arena, &.{"--value"}, sent);
    try testing.expectEqual(@as(u8, 1), value.status);
    try testing.expectEqualStrings("", value.out);

    const block = try call(arena, &.{ "--sigil", "brain", "--block" }, sent);
    try testing.expectEqual(@as(u8, 1), block.status);

    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{ "--sigil", "question" }, sent)).status);
    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{ "--sigil", "nonsense" }, sent)).status);
    try testing.expectEqual(@as(u8, 1), (try call(arena, &.{}, "just text\n")).status);
}

test "the last of any kind named, as the text it holds" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ledger = "#### :robot:\n> first\n\n#### :raising_hand:\n> more\n\n" ++
        "#### :robot:\n> second\n> line\n\n#### :brain:x/+/abcdefghij\n";
    const picks = [_][]const u8{ "--sigil", "robot", "--sigil", "question", "--block" };
    try testing.expectEqualStrings("second\nline\n", (try call(arena, &picks, ledger)).out);

    const asked = ledger ++ "\n#### :question:tool,c1\n> deploy to prod?\n";
    try testing.expectEqualStrings("deploy to prod?\n", (try call(arena, &picks, asked)).out);
    try testing.expectEqualStrings("tool,c1\n", (try call(arena, &.{"--value"}, asked)).out);
}
