//! `munge` — reading, searching and changing files, all addressed in pages.
//!
//! `munge` makes the coordinate coarse and lets the strings carry the
//! precision, so a stale picture mostly still lands — a page number that has
//! drifted by a line or two still names the right part of the file.
//!
//! That is what pages buy. A page is stable enough to hand back and forth
//! across edits, cheap enough to scope a search with, and vague enough that
//! nothing is ever asserted against it. Lines and matches live inside a page
//! as the way a model thinks, which is the way it was trained to think, and
//! the page is the frame they are thought in.
//!
//!   read   a file in pages, or the content of a directory
//!   write  change a file by saying what is already in it
//!   scan   search files for a pattern, answered in pages
//!
//! The subcommands are the `Command` values the modules already declare, so
//! what is listed here, what is dispatched to, and what `help` prints are one
//! table rather than three.

const std = @import("std");
const api = @import("../api.zig");
const opts = @import("munge/opts.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "munge",
    .summary = "read, search and change files, addressed in pages",
    // Every command under here is spawned with nothing on stdin.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn find(name: []const u8) ?*const fn (Ctx) anyerror!u8 {
    if (std.mem.eql(u8, name, "read")) return @import("munge/read.zig").command.run;
    if (std.mem.eql(u8, name, "write")) return @import("munge/write.zig").command.run;
    if (std.mem.eql(u8, name, "scan")) return @import("munge/scan.zig").command.run;
    return null;
}

const global_options = [_]opts.Option{
    .{ .name = "pages" },
    .{ .name = "page-lines", .kind = .number },
    .{ .name = "page-bytes", .kind = .number },
};

fn run(ctx: Ctx) !u8 {
    // Global options belong before the operation
    // ("munge --page-lines 50 read file").  Stop at the operation so
    // its options remain its own business.
    var command_at: usize = 0;
    while (command_at < ctx.args.len and
        std.mem.startsWith(u8, ctx.args[command_at], "--"))
    {
        // All munge-level options currently take a separate value.
        command_at = @min(ctx.args.len, command_at + 2);
    }

    var global_ctx = ctx;
    global_ctx.args = ctx.args[0..command_at];
    _ = (try opts.parse(global_ctx, "munge", &global_options, 0)) orelse return 1;
    if (command_at == ctx.args.len) {
        try help(ctx, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    const which = ctx.args[command_at];
    const sub = find(which) orelse {
        try ctx.err.print("m8 munge: no command named '{s}'\n", .{which});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    // There is one help boundary for this command, including when a user
    // spells the operation before --help.
    if (command_at + 1 < ctx.args.len and std.mem.eql(u8, ctx.args[command_at + 1], "--help")) {
        try help(ctx, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    // Pass the already validated global values to the operation in its normal
    // option spelling.  The operation parsers retain these two entries as an
    // implementation detail; users see them only at the munge level.
    var forwarded: std.ArrayList([]const u8) = .empty;
    try forwarded.appendSlice(ctx.arena, ctx.args[0..command_at]);
    try forwarded.appendSlice(ctx.arena, ctx.args[command_at + 1 ..]);

    var inner = ctx;
    inner.args = forwarded.items;
    return sub(inner);
}

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\Usage: m8 munge [OPTIONS] COMMAND [COMMAND-OPTIONS] ARGS
        \\
        \\Options:
        \\  --page-lines N      page line target (default 100)
        \\  --page-bytes N      page byte target (default 10000)
        \\  --pages RANGE       select pages (for example 11-20 or 2@anchor)
        \\
        \\Commands:
        \\
    );
    try w.writeAll(
        \\  read     read a file or list a directory
        \\  write    change a file, or append to one
        \\  scan     search files for a pattern, answered in pages
    );
    try w.writeAll(
        \\
        \\Each command has its own options
        \\
        \\read:
        \\  read PATH           read a file or list a directory
        \\  --byte-cap N        maximum answer size
        \\
        \\write:
        \\  write PATH TEXT     replace or append file content
        \\  --old TEXT          text to match (if replacing) with fallback forgiveness on
        \\                      indentation, whitespace, over-encoded \, a line-num prefix,
        \\                      block-content tolerance between 8-char+ outer anchor lines;
        \\                      only single line edits may match many.
        \\  --tolerance N       % of anchored block lines allowed to differ (default 25)
        \\  --dry-run           view diff without making changes
        \\
        \\scan:
        \\  scan                search files
        \\  --glob GLOB         file path matching
        \\  --regex PATTERN     grep per-line on perl-style regex no backrefs no lookaround
        \\  --byte-cap N        maximum answer size
        \\
        \\Use -- before a PATH that starts with --.
        \\
        \\Answers are addressed in pages; page sizes are shared so a read,
        \\scan and write refer to the same coordinates.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the commands are reached under munge and nowhere else" {
    const cmd = @import("../command.zig");

    try testing.expect(find("read") != null);
    try testing.expect(find("write") != null);
    try testing.expect(find("scan") != null);
    try testing.expect(find("nosuch") == null);

    // The operations are scoped under one top-level command, not loose beside
    // it and not separate split programs.
    try testing.expect(cmd.find("munge") != null);
    try testing.expect(cmd.find("read") == null);
    try testing.expect(cmd.byProgram("m8-read") == null);
}
