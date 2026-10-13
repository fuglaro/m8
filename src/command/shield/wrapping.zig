//! What the shields m8 ships with have in common.
//!
//! A shield takes the command it wraps after `--` and runs it in its own
//! place, so what a tool sees is one process and one exit status however many
//! wrappers it stood inside. Splitting at `--` and standing out of the way are
//! the whole of that, and neither is any one shield's business.

const std = @import("std");
const api = @import("../../api.zig");
const Ctx = api.Ctx;

pub const Error = error{
    /// No `--`, so there is no command to wrap.
    NothingToWrap,
    /// A name this m8 does not ship.
    UnknownShield,
    /// A restriction the profile has no line for.
    UnknownRestriction,
    /// Kernel restrictions need `sandbox-exec`.
    Unsupported,
    /// The person said no, or there was nobody to ask.
    Refused,
};

/// What was said to this shield, and what it wraps.
pub const Wrapped = struct {
    head: []const []const u8,
    argv: []const []const u8,
};

/// Split at `--`. Nothing to wrap is an error rather than a no-op: a shield
/// that ran nothing and answered zero would read as having allowed something.
pub fn cut(args: []const []const u8) !Wrapped {
    const at = for (args, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--")) break i;
    } else return Error.NothingToWrap;

    const argv = args[at + 1 ..];
    if (argv.len == 0) return Error.NothingToWrap;
    return .{ .head = args[0..at], .argv = argv };
}

/// Hand the command the terminal and this process's exit status. A wrapper is
/// not a filter: what it wraps talks to whoever m8 was talking to.
pub fn through(ctx: Ctx, argv: []const []const u8, environ: ?*const std.process.Environ.Map) !u8 {
    try ctx.out.flush();
    try ctx.err.flush();
    const child_env = environ orelse try api.childEnvironment(ctx.arena, ctx, &.{});
    var child = try std.process.spawn(ctx.io, .{ .argv = argv, .environ_map = child_env });
    return switch (try child.wait(ctx.io)) {
        .exited => |code| code,
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}
