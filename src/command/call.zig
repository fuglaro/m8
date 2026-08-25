//! `call` — run a command, optionally with the world taken away.
//!
//!     m8 call [-w R]... NAME [ARGS]      an m8 command
//!     m8 call [-w R]... -- PROG [ARGS]   a program from the environment
//!
//! `-w` names a restriction from the sandbox profile. Each one only ever
//! subtracts, so they may be repeated in any order. With none given there is
//! nothing to enforce and the program is spawned directly, rather than through
//! a sandbox that grants everything.

const std = @import("std");
const builtin = @import("builtin");
const api = @import("api.zig");
const sandbox = @import("../sandbox.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "call",
    .summary = "run a command, optionally restricted",
    // A spawned program owns stdin. Reading it here would take the bytes it
    // is waiting for; an m8 command that wants the document gets it below.
    .reads = false,
    .run = run,
};

pub const Error = error{
    UnknownRestriction,
    UnknownCommand,
    NothingToRun,
    /// `-w` needs a sandbox, and only macOS has one here.
    RestrictionsUnsupported,
};

fn run(ctx: Ctx) !u8 {
    var with: std.ArrayList([]const u8) = .empty;
    var rest: []const []const u8 = ctx.args;
    var env_program = false;

    while (rest.len > 0) {
        const word = rest[0];
        if (std.mem.eql(u8, word, "--")) {
            rest = rest[1..];
            env_program = true;
            break;
        }
        if (std.mem.eql(u8, word, "-w")) {
            if (rest.len < 2) {
                try ctx.err.writeAll("m8 call: -w needs a restriction\n");
                return usage(ctx, Error.UnknownRestriction);
            }
            if (sandbox.find(rest[1]) == null) {
                try ctx.err.print("m8 call: no restriction named '{s}'\n", .{rest[1]});
                return usage(ctx, Error.UnknownRestriction);
            }
            try with.append(ctx.arena, rest[1]);
            rest = rest[2..];
            continue;
        }
        if (std.mem.eql(u8, word, "--help") or std.mem.eql(u8, word, "-h")) return help(ctx);
        break;
    }

    if (rest.len == 0) {
        // Nothing named at all is the help case; `--` with nothing after it
        // is a mistake worth naming.
        if (!env_program and with.items.len == 0) return help(ctx);
        return usage(ctx, Error.NothingToRun);
    }

    if (!env_program) {
        const inner = @import("../command.zig").findFilter(rest[0]) orelse {
            try ctx.err.print("m8 call: no command named '{s}'\n", .{rest[0]});
            return usage(ctx, Error.UnknownCommand);
        };
        // An m8 command runs in this process, so there is nothing to sandbox.
        if (with.items.len > 0) return usage(ctx, Error.RestrictionsUnsupported);
        var sub = ctx;
        sub.args = rest[1..];
        var in_buf: [64 * 1024]u8 = undefined;
        if (inner.reads) sub.in = try api.readDocument(ctx.io, ctx.arena, &in_buf);
        return inner.run(sub);
    }

    if (with.items.len == 0) return spawn(ctx, rest, null);
    if (builtin.os.tag != .macos) return usage(ctx, Error.RestrictionsUnsupported);
    return spawnRestricted(ctx, rest, with.items);
}

/// Straight through: same stdio, same environment, our exit status is theirs.
fn spawn(ctx: Ctx, argv: []const []const u8, env: ?*const std.process.Environ.Map) !u8 {
    var child = try std.process.spawn(ctx.io, .{
        .argv = argv,
        .environ_map = env,
    });
    return switch (try child.wait(ctx.io)) {
        .exited => |code| code,
        // A signalled child is not an exit status; report it the way a shell
        // does rather than pretending it returned something.
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}

fn spawnRestricted(ctx: Ctx, argv: []const []const u8, with: []const []const u8) !u8 {
    const cwd = try currentPath(ctx);
    const parent = std.fs.path.dirname(cwd) orelse "/";

    // TMPDIR has to exist before the profile names it, and has to be somewhere
    // the profile will still allow once the restrictions bite.
    const base = ctx.env.get("TMPDIR") orelse "/tmp";
    const tmp = try std.fs.path.join(ctx.arena, &.{ base, try tmpName(ctx) });
    const dir = std.Io.Dir.cwd();
    try dir.createDirPath(ctx.io, tmp);

    const profile = try std.fs.path.join(ctx.arena, &.{ tmp, "resolved.sb" });
    try dir.writeFile(ctx.io, .{
        .sub_path = profile,
        .data = try sandbox.resolve(ctx.arena, with),
    });

    var full: std.ArrayList([]const u8) = .empty;
    try full.appendSlice(ctx.arena, &.{
        "sandbox-exec",                                              "-f",
        profile,                                                     "-D",
        try std.fmt.allocPrint(ctx.arena, "CWD={s}", .{cwd}),        "-D",
        try std.fmt.allocPrint(ctx.arena, "PARENTWD={s}", .{parent}), "-D",
        try std.fmt.allocPrint(ctx.arena, "TMP={s}", .{tmp}),
    });
    try full.appendSlice(ctx.arena, argv);

    // The child's own TMPDIR must be the one the profile allows, or it writes
    // where it is denied and fails in a way nothing explains.
    var env = try ctx.env.clone(ctx.arena);
    try env.put("TMPDIR", tmp);

    return spawn(ctx, full.items, &env);
}

fn currentPath(ctx: Ctx) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.process.currentPath(ctx.io, &buf);
    return ctx.arena.dupe(u8, buf[0..len]);
}

fn tmpName(ctx: Ctx) ![]const u8 {
    var raw: [8]u8 = undefined;
    ctx.io.random(&raw);
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&raw}) catch unreachable;
    return std.fmt.allocPrint(ctx.arena, "m8call-{s}", .{&hex});
}

fn usage(ctx: Ctx, e: Error) !u8 {
    _ = try help(ctx);
    return e;
}

fn help(ctx: Ctx) !u8 {
    // Help goes to stderr, which leaves stdout free for the document and is
    // still there when the terminal is not.
    const w = ctx.err;
    try w.writeAll(
        \\m8 call — run a command, optionally restricted
        \\
        \\  m8 call [-w R]... NAME [ARGS]     an m8 command
        \\  m8 call [-w R]... -- PROG [ARGS]  a program from the environment
        \\
        \\-w takes the world away. Each only subtracts, so any combination
        \\is safe and the order never matters.
        \\
        \\
    );
    for (sandbox.all) |r| try w.print("  {s: <15} {s}\n", .{ r.name, r.summary });
    try w.writeAll("\ncommands:\n\n");
    for (@import("../command.zig").all) |c| {
        if (std.mem.eql(u8, c.name, "call")) continue;
        try w.print("  {s: <15} {s}\n", .{ c.name, c.summary });
    }
    try w.flush();
    return 0;
}
