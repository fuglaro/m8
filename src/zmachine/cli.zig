//! A story file, run from the command line, for working on the machine itself.
//!
//! `zig build zrun -- game.z5 "open mailbox" "read leaflet"` plays the file
//! from the beginning with those lines typed into it, and prints what the last
//! one produced. It is the same `play` the provider uses and takes the same
//! path through it, so what it shows is what a ledger would hold — with none
//! of m8 in the way while the machine is still being got right.
//!
//! `--all` prints every turn rather than the last, which is what a transcript
//! diff against a reference interpreter wants.

const std = @import("std");
const zm = @import("zmachine.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("usage: zrun [--all] STORY [LINE...]\n", .{});
        return;
    }

    var at: usize = 1;
    var every = false;
    if (std.mem.eql(u8, args[at], "--all")) {
        every = true;
        at += 1;
    }
    if (at >= args.len) return;

    const bytes = try readAll(arena, io, args[at]);
    const inputs = args[at + 1 ..];

    var buf: [1 << 16]u8 = undefined;
    var out = std.Io.File.stdout().writerStreaming(io, &buf);
    const w = &out.interface;

    const seed = zm.seedFrom("m8");
    if (every) {
        // Replaying from the start for every prefix is exactly what the
        // provider does turn by turn, so this is the real cost as well as the
        // real output.
        var n: usize = 0;
        while (n <= inputs.len) : (n += 1) {
            const turn = try zm.play(arena, bytes, seed, inputs[0..n]);
            if (n > 0) try w.print("\n> {s}\n", .{inputs[n - 1]});
            try w.print("{s}\n", .{turn.text});
            if (turn.ended) break;
        }
    } else {
        const turn = try zm.play(arena, bytes, seed, inputs);
        try w.print("{s}\n", .{turn.text});
        try w.print(
            "\n[ended={} wants={s} consumed={d}/{d}]\n",
            .{ turn.ended, @tagName(turn.wants), turn.consumed, inputs.len },
        );
    }
    try w.flush();
}

fn readAll(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buf: [64 * 1024]u8 = undefined;
    var reader = file.readerStreaming(io, &buf);
    return reader.interface.allocRemaining(arena, .unlimited);
}
