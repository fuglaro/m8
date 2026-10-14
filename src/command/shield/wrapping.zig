//! What the shields m8 ships with have in common.
//!
//! A shield is told the name it stands as and then the command it wraps, and
//! runs that command in its own place, so what a tool sees is one process and
//! one exit status however many wrappers it stood inside. Reading that and
//! standing out of the way are the whole of it, and neither is any one
//! shield's business.

const std = @import("std");
const api = @import("../../api.zig");
const Ctx = api.Ctx;

pub const Error = error{
    /// No command after the name, so there is nothing to wrap.
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

/// Who this shield stands as, and what it wraps.
pub const Wrapped = struct {
    name: []const u8,
    argv: []const []const u8,
};

/// The name, then the command. Nothing to wrap is an error rather than a
/// no-op: a shield that ran nothing and answered zero would read as having
/// allowed something.
pub fn cut(args: []const []const u8) !Wrapped {
    if (args.len < 2) return Error.NothingToWrap;
    return .{ .name = args[0], .argv = args[1..] };
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
