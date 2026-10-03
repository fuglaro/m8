//! `ref` — the 🧠 a document ends on, and nothing else.
//!
//! What `m8 @x hi` writes is the reply and then the 🧠 of the turn it kept,
//! which is what a person or a script wants to read. What the next command
//! wants is often the reference alone, and this is how one becomes the other.
//!
//! Only a document that ends on a 🧠 has one. A turn `send` wrote was never
//! kept, and the only 🧠 in it is the parent it continues — taking that would
//! answer with somewhere else, so it is refused instead.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "ref",
    .summary = "the 🧠 a document ends on, and nothing else",
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 ref — the 🧠 a document ends on, and nothing else
        \\
        \\  m8 ref
        \\
        \\`m8 @x hi` writes the reply and then the 🧠 of the turn it kept. This
        \\keeps that last 🧠 alone, which is what a command wanting a reference
        \\is handed.
        \\
        \\  m8 @x hi | m8 ref | m8 tag @y              fork the new turn into y
        \\  m8 @x hi | m8 ref | m8 @y "review that"    hand y the conversation
        \\
        \\A document that ends on anything else has nothing to reference: a
        \\turn `m8 send` wrote was never kept, so tag it first.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    if (ctx.args.len > 0) {
        try ctx.err.writeAll("m8 ref: takes no arguments; `m8 cat @x` is an address's 🧠\n");
        return 1;
    }
    if (ctx.in.len == 0 or doc.detect(ctx.in) == null) {
        try ctx.err.writeAll("m8 ref: pipe in a document that ends on a 🧠\n");
        return 1;
    }
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, ctx.in, &diag);
    const last = records[records.len - 1];
    if (last.sigil != .agent or last.content != null) {
        try ctx.err.writeAll(
            "m8 ref: this does not end on a 🧠, so there is nothing to reference; tag it first\n",
        );
        return 1;
    }
    try doc.write(ctx.out, ctx.mode, last);
    return 0;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn call(arena: std.mem.Allocator, in: []const u8, out: *std.Io.Writer, err: *std.Io.Writer) !u8 {
    var env: std.process.Environ.Map = .init(arena);
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    return run(.{
        .arena = arena,
        .io = threaded.io(),
        .mode = .md,
        .env = &env,
        .args = &.{},
        .in = in,
        .out = out,
        .err = err,
        .tty = null,
    });
}

test "what m8 @ writes becomes its 🧠 alone" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var out: std.Io.Writer.Allocating = .init(a.allocator());
    var err: std.Io.Writer.Allocating = .init(a.allocator());

    const said = "#### :robot:\n> hi\n\n#### :brain:x/+/abcdefghij\n";
    try testing.expectEqual(@as(u8, 0), try call(a.allocator(), said, &out.writer, &err.writer));
    try testing.expectEqualStrings("#### :brain:x/+/abcdefghij\n", out.written());
}

test "a turn nobody kept has no reference, even with its parent in it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    var out: std.Io.Writer.Allocating = .init(a.allocator());
    var err: std.Io.Writer.Allocating = .init(a.allocator());

    const sent = "#### :brain:x/+/parent\n\n#### :raising_hand:\n> hi\n\n#### :robot:\n> hi\n";
    try testing.expectEqual(@as(u8, 1), try call(a.allocator(), sent, &out.writer, &err.writer));
    try testing.expectEqualStrings("", out.written());
}
