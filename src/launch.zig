//! Reaching the command under this one.
//!
//! A launcher holds some commands and calls them. One it does not hold may
//! be a program beside it, named `m8-` and the command, and reaching that is
//! becoming it: the launcher's process is replaced, so nothing waits on the
//! command and what it was started with is all it sees.
//!
//! Where a sibling is, is not searched for. A launcher looks beside itself,
//! so an m8 installed anywhere reaches its own commands rather than whichever
//! ones are on a PATH — the same argument that has a provider naming `m8`
//! reach the m8 that is running.

const std = @import("std");
const api = @import("api.zig");
const Ctx = api.Ctx;

/// The program beside this one, by name.
pub fn sibling(arena: std.mem.Allocator, self: []const u8, program: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(self) orelse return program;
    return std.fs.path.join(arena, &.{ dir, program });
}

/// The program beside this one, when it is there to run.
pub fn beside(arena: std.mem.Allocator, io: std.Io, self: []const u8, program: []const u8) !?[]const u8 {
    const path = try sibling(arena, self, program);
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    if (st.kind != .file or st.permissions.toMode() & 0o111 == 0) return null;
    return path;
}

/// Run the command under this one, held in this binary.
pub fn under(ctx: Ctx, c: api.Command, args: []const []const u8) !u8 {
    var inner = ctx;
    inner.args = args;

    // This is where a command receives its process-level option. Only the
    // first word is reserved; everything after it belongs to the page, and
    // every other occurrence belongs to the command.
    if (api.wantsHelp(args)) {
        inner.args = args[1..];
        try api.page(c, inner, ctx.out);
        try ctx.out.flush();
        return 0;
    }

    if (c.takes != .nothing) {
        var buf: [64 * 1024]u8 = undefined;
        inner.in = try api.readDocument(ctx.io, ctx.arena, &buf);
    }
    return c.run(inner);
}

/// Become another program, with these words as the whole of what it was
/// started with.
///
/// Nothing may be waiting in this process's writers when this is called: the
/// process that would have flushed them is the one being replaced. Where a
/// process cannot be replaced it is run and waited for instead, which is the
/// same thing with a parent left standing.
pub fn become(io: std.Io, argv: []const []const u8) !u8 {
    const why = std.process.replace(io, .{ .argv = argv });
    if (why != error.OperationUnsupported) return why;
    var child = try std.process.spawn(io, .{ .argv = argv });
    return status(try child.wait(io));
}

/// What a child's end becomes for whoever asked.
pub fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        // A signalled child is not an exit status; report it the way a shell
        // does rather than pretending it returned something.
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}
