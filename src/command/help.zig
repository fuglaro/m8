//! Shared command-help rendering.
//!
//! A page lives beside the command whose page it is. This module writes one
//! through the common command contract; help is process syntax, not a command
//! of its own.

const std = @import("std");
const cmd = @import("../command.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;

/// One command's page, or its summary when that is the whole of it.
pub fn write(ctx: Ctx, c: api.Command, w: *std.Io.Writer) !void {
    if (c.help) |h| return h(ctx, w);
    try w.print("m8 {s} — {s}\n", .{ c.name, c.summary });
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "every command has a page, and it says which command it is" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // No HOME and no XDG, so anything that reads a config reads the copy
    // compiled in rather than whatever is on the machine running the tests.
    var env: std.process.Environ.Map = .init(arena);
    var thrown: std.Io.Writer.Allocating = .init(arena);

    for (cmd.all) |c| {
        var page_out: std.Io.Writer.Allocating = .init(arena);
        try write(.{
            .arena = arena,
            .io = threaded.io(),
            .mode = .md,
            .env = &env,
            .args = &.{},
            .in = "",
            .out = &page_out.writer,
            .err = &thrown.writer,
            .tty = null,
        }, c, &page_out.writer);

        const said = page_out.written();
        try testing.expect(said.len > 0);
        try testing.expect(std.mem.indexOf(u8, said, c.name) != null);
        // A page is prose for a person, not a document. It never opens like
        // one, or piping it somewhere would read as a ledger.
        try testing.expect(said[0] != '#');
    }
}
