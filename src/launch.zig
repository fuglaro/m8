//! Running the command under this one — as a call, or as a process.
//!
//! m8 is built two ways from one registry. The single binary holds every
//! command and reaches one by calling it; the split set is a program per
//! command, and reaching one is spawning it. Prompt mode is part of the
//! launcher in both builds. Which of the two a binary does is decided here and
//! nowhere else, so no command has an opinion about it.
//!
//! The split set is the guardrail rather than the optimisation. A command that
//! reaches into another command's module still compiles in the single binary
//! and shows up in the split set as a program carrying a stack it has no
//! business carrying — `zig build split` prints the sizes, and a leaf that is
//! suddenly a megabyte is the answer.
//!
//! Where a sibling is, is not searched for. A launcher spawns the program
//! beside itself, so an m8 installed anywhere reaches its own commands rather
//! than whichever ones are on a PATH — the same argument that has a provider
//! naming `m8` reach the m8 that is running.

const std = @import("std");
const api = @import("command/api.zig");
const prompt_mode = @import("prompt.zig");
const Ctx = api.Ctx;

/// Whether the commands under this one are programs of their own.
pub const split = @import("build_options").split;

/// What a child is handed on stdin. A launcher has already read whatever it
/// was going to read, so it either hands those bytes over or leaves the
/// descriptor alone for the child to read itself.
pub const Stdin = union(enum) {
    /// These bytes, and then end of file.
    bytes: []const u8,
    /// Whatever this process has. What a command taking stdin as it arrives
    /// gets, so nothing is buffered between the two.
    inherited,
};

/// The program beside this one, by name.
pub fn sibling(arena: std.mem.Allocator, self: []const u8, program: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(self) orelse return program;
    return std.fs.path.join(arena, &.{ dir, program });
}

/// How the command under this one is reached. A launcher decides this by
/// which build it is, and says which rather than being asked twice.
pub const Reach = union(enum) {
    /// `@`, which is not a command.
    prompt,
    /// The command itself, held in this binary.
    call: api.Command,
    /// The name of the program that is it.
    spawn: []const u8,
};

/// Run the command under this one, whichever way this binary reaches it.
pub fn under(ctx: Ctx, reach: Reach, args: []const []const u8, in: Stdin) !u8 {
    if (reach == .prompt) return prompt(ctx, args, in);

    const c = switch (reach) {
        .spawn => |program| return spawn(ctx, program, args, in),
        .call => |c| c,
        .prompt => unreachable,
    };

    var inner = ctx;
    inner.args = args;

    // In the single binary this is where a command receives its process-level
    // option. A split-out command answers the same option in `harness.leaf`.
    // Only the first word is reserved; everything after it belongs to the
    // page, and every other occurrence belongs to the command.
    if (c.help) |page| if (api.wantsHelp(args)) {
        inner.args = args[1..];
        try page(inner, ctx.out);
        try ctx.out.flush();
        return 0;
    };

    inner.in = switch (in) {
        .bytes => |b| b,
        // The single binary hands stdin to whoever wants it, as it always did.
        .inherited => if (c.takes == .nothing) "" else blk: {
            var buf: [64 * 1024]u8 = undefined;
            break :blk try api.readDocument(ctx.io, ctx.arena, &buf);
        },
    };
    return c.run(inner);
}

/// Run the top-level prompt mode. Unlike a command, it has no registry entry
/// or child program: `@` is launcher syntax, and it reads its own stdin.
fn prompt(ctx: Ctx, args: []const []const u8, in: Stdin) !u8 {
    var inner = ctx;
    inner.in = switch (in) {
        .bytes => |b| b,
        .inherited => "",
    };
    return prompt_mode.run(inner, args);
}

/// Run it as a process.
///
/// Stdout and stderr are the launcher's own, not pipes: what a command says
/// goes where it was going anyway, at the moment it says it, and a launcher
/// that captured it would be the thing that stopped a long answer streaming.
/// Only stdin is ever a pipe, and only when there are bytes to hand over.
fn spawn(ctx: Ctx, program: []const u8, args: []const []const u8, in: Stdin) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(ctx.arena, try sibling(ctx.arena, ctx.self, program));
    try argv.appendSlice(ctx.arena, args);

    var m = try ctx.env.clone(ctx.arena);
    for (ctx.extra_env) |v| try m.put(v.key, v.value);
    const environ = try ctx.arena.create(std.process.Environ.Map);
    environ.* = m;

    // Anything held in this process's writers is on its way to the same
    // descriptors the child is about to write to. Out of order otherwise.
    try ctx.out.flush();
    try ctx.err.flush();

    var child = try std.process.spawn(ctx.io, .{
        .argv = argv.items,
        .environ_map = environ,
        .stdin = switch (in) {
            .bytes => .pipe,
            .inherited => .inherit,
        },
    });

    // Written and closed before waiting. The child's other two streams are
    // the terminal or whatever the launcher was redirected to, so there is no
    // second pipe to fill and nothing here can deadlock on one.
    if (in == .bytes) {
        var buf: [4096]u8 = undefined;
        var w = child.stdin.?.writerStreaming(ctx.io, &buf);
        try w.interface.writeAll(in.bytes);
        try w.interface.flush();
        child.stdin.?.close(ctx.io);
        child.stdin = null;
    }

    return status(try child.wait(ctx.io));
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
