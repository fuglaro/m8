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
        \\  m8 munge [OPTIONS] COMMAND [COMMAND-OPTIONS] ARGS
        \\
        \\Read, search, or edit files using page-addressed output. Global options
        \\must appear before COMMAND; command-specific options follow it.
        \\
        \\OPTIONS:
        \\
        \\  --page-lines N  Target lines per page (default: 30).
        \\  --page-bytes N  Target bytes per page (default: 3000).
        \\  --pages RANGE   Select pages, e.g. `11-20` or `2@anchor`.
        \\
        \\COMMANDS:
        \\
        \\  read PATH        Read a file or list a directory.
        \\  write PATH TEXT  Replace or append file content.
        \\  scan             Search files for a pattern.
        \\
        \\COMMAND OPTIONS:
        \\
        \\  read [--byte-cap N] [--pages RANGE] [--offset N] [--limit N] PATH
        \\    --byte-cap N     Maximum answer size (default: 20000 bytes).
        \\    --offset N      Zero-based line offset; with no pages, starts there.
        \\    --limit N       Maximum line count; rounded to whole pages.
        \\
        \\  write [--old TEXT] [--pages RANGE] [--offset N] [--limit N]
        \\          [--tolerance N] [--diff-pad N] [--trim] [--dry-run] PATH [TEXT]
        \\    --old TEXT       Replace matching text; without it, append TEXT.
        \\    --offset N      Zero-based line offset; with --pages, only moves start earlier.
        \\    --limit N       Maximum line count; with --pages, only moves end earlier.
        \\    --tolerance N    Allowed differing anchored lines (default: 25%).
        \\    --diff-pad N     Diff context / trim padding (default: 3).
        \\    --trim           Collapse long pure insertions; zero pad uses default.
        \\    --dry-run        Show the diff without writing changes.
        \\
        \\    Replacement matching tolerates indentation, whitespace,
        \\    over-encoded backslashes, and line-number prefixes. Multi-line
        \\    blocks use outer anchor lines of at least 8 characters and
        \\    tolerate differences within them. Only single-line edits may
        \\    match more than once.
        \\
        \\  scan [--glob GLOB] [--regex PATTERN] [--byte-cap N]
        \\    --glob GLOB      Match file paths.
        \\    --regex PATTERN  Search each line with a Perl-style regex; no
        \\                     backreferences or lookaround.
        \\    --byte-cap N     Maximum answer size (default: 20000 bytes).
        \\
        \\EXAMPLES:
        \\
        \\  m8 munge --page-lines 50 read README.md
        \\  m8 munge scan --glob '*.zig' --regex 'fn help'
        \\  m8 munge write --dry-run README.md 'new text'
        \\
        \\Use `--` before a path beginning with `--`. Page sizing is shared
        \\across read, scan, and write so their coordinates stay consistent.
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
