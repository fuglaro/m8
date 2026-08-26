//! `call` — run a command under whatever locks are in force.
//!
//!     m8 [-l LOCKS] call NAME [ARGS]      an m8 command
//!     m8 [-l LOCKS] call -- PROG [ARGS]   a program from the environment
//!
//! `-l` belongs to m8 rather than to `call`, so a lock covers everything a run
//! does and not just the one command. It is cumulative with the locks an agent
//! already carries; nothing said here can loosen those.
//!
//! With no kernel lock there is nothing for the sandbox to enforce, so the
//! program is spawned directly rather than through a profile that grants
//! everything.
//!
//! Output is m8: the child's stdout becomes a 🧾 receipt. A non-zero exit is a
//! 🚫 naming the code, with the child's stderr after it when there was any —
//! a failure with no reason in it tells a model only that something broke.
//! `--raw` hands stdout straight through instead — which also hands
//! over the descriptor, so a child under `--raw` can seek and truncate
//! whatever the caller redirected to. Capturing is the default for that
//! reason as much as for the format.

const std = @import("std");
const builtin = @import("builtin");
const api = @import("api.zig");
const doc = @import("../m8/doc.zig");
const sandbox = @import("../sandbox.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "call",
    .summary = "run a command under the locks in force",
    // A spawned program owns stdin. Reading it here would take the bytes it
    // is waiting for; an m8 command that wants the document gets it below.
    .takes = .nothing,
    .run = run,
};

pub const Error = error{
    UnknownCommand,
    NothingToRun,
    /// A kernel lock was asked for on a platform with no sandbox.
    LocksUnsupported,
    /// `deny` was in force.
    ToolUseDenied,
    /// `ask` was in force and the answer was no, or there was nobody to ask.
    Refused,
};

fn run(ctx: Ctx) !u8 {
    var rest: []const []const u8 = ctx.args;
    var env_program = false;
    var raw = false;

    while (rest.len > 0) {
        const word = rest[0];
        if (std.mem.eql(u8, word, "--")) {
            rest = rest[1..];
            env_program = true;
            break;
        }
        if (std.mem.eql(u8, word, "--raw")) {
            raw = true;
            rest = rest[1..];
            continue;
        }
        if (std.mem.eql(u8, word, "--help") or std.mem.eql(u8, word, "-h")) return help(ctx);
        // `-l` used to live here. It covers the whole run now, so it belongs
        // before the command rather than after it.
        if (std.mem.eql(u8, word, "-l") or std.mem.eql(u8, word, "--lock")) {
            try ctx.err.writeAll("m8 call: put -l before call, it covers the whole run\n");
            return usage(ctx, Error.NothingToRun);
        }
        break;
    }

    if (rest.len == 0) {
        if (!env_program) return help(ctx);
        try ctx.err.writeAll("m8 call: nothing after --\n");
        return usage(ctx, Error.NothingToRun);
    }

    if (!env_program) {
        // Gate locks apply to an m8 command too; `execute` covers the
        // spawning path below.
        if (has(ctx.locks, "deny")) {
            try ctx.err.writeAll("m8 call: tool use is denied by a lock\n");
            return Error.ToolUseDenied;
        }
        if (has(ctx.locks, "ask") and !try permitted(ctx, rest)) return Error.Refused;

        const inner = @import("../command.zig").findCallable(rest[0]) orelse {
            try ctx.err.print("m8 call: no command named '{s}'\n", .{rest[0]});
            return usage(ctx, Error.UnknownCommand);
        };
        var sub = ctx;
        sub.args = rest[1..];
        var in_buf: [64 * 1024]u8 = undefined;
        // Whatever the inner command wants, it gets stdin: a tool is a filter
        // in somebody else's pipeline, and there is no command line here to
        // assemble a ledger from.
        if (inner.takes != .nothing) sub.in = try api.readDocument(ctx.io, ctx.arena, &in_buf);
        return inner.run(sub);
    }

    return execute(ctx, rest, raw);
}

/// Run an already-built command line.
///
/// This is what a 🔌 expansion reaches: the template is a whole command line
/// already, and asks for the sandbox itself by naming `m8 -l ... call --`.
/// The gate locks still apply here, because they gate the decision to run
/// anything at all rather than what it may do once running.
pub fn execute(ctx: Ctx, argv: []const []const u8, raw: bool) !u8 {
    if (argv.len == 0) return Error.NothingToRun;
    if (has(ctx.locks, "deny")) {
        try ctx.err.writeAll("m8 call: tool use is denied by a lock\n");
        return Error.ToolUseDenied;
    }
    if (has(ctx.locks, "ask") and !try permitted(ctx, argv)) return Error.Refused;
    return spawn(ctx, argv, raw);
}

fn has(locks: []const []const u8, name: []const u8) bool {
    for (locks) |l| if (std.mem.eql(u8, l, name)) return true;
    return false;
}

/// `ask` with nobody to ask is a no. A pipe or a cron job must not be a way
/// of skipping the question.
fn permitted(ctx: Ctx, argv: []const []const u8) !bool {
    const t = ctx.tty orelse {
        try ctx.err.writeAll("m8 call: 'ask' is in force and there is no terminal\n");
        return false;
    };
    try t.prompt("run: {s} ? [y/N] ", .{try std.mem.join(ctx.arena, " ", argv)});
    const line = (try t.line()) orelse return false;
    const answer = std.mem.trim(u8, line, " \t");
    return std.mem.eql(u8, answer, "y") or std.mem.eql(u8, answer, "Y");
}

fn spawn(ctx: Ctx, argv: []const []const u8, raw: bool) !u8 {
    var kernel: std.ArrayList([]const u8) = .empty;
    for (ctx.locks) |l| if (sandbox.isKernel(l)) try kernel.append(ctx.arena, l);

    var full = argv;
    var environ: ?*const std.process.Environ.Map = null;
    var tmp: []const u8 = "";

    if (kernel.items.len > 0) {
        if (builtin.os.tag != .macos) {
            try ctx.err.writeAll("m8 call: kernel locks need sandbox-exec, which is macOS only\n");
            return Error.LocksUnsupported;
        }
        tmp = try makeTmp(ctx);
        full = try wrap(ctx, argv, kernel.items, tmp);
    }

    if (sandbox.containsEnv(ctx.locks)) {
        environ = try contained(ctx, tmp);
    } else if (tmp.len > 0) {
        var m = try ctx.env.clone(ctx.arena);
        try m.put("TMPDIR", tmp);
        const boxed = try ctx.arena.create(std.process.Environ.Map);
        boxed.* = m;
        environ = boxed;
    }

    if (raw) {
        var child = try std.process.spawn(ctx.io, .{ .argv = full, .environ_map = environ });
        return status(try child.wait(ctx.io));
    }

    // `run` drains both pipes at once. Reading one and then the other
    // deadlocks as soon as a tool fills the pipe nobody is reading.
    const r = try std.process.run(ctx.arena, ctx.io, .{
        .argv = full,
        .environ_map = environ,
    });
    const code = status(r.term);

    const content = if (code == 0)
        std.mem.trimEnd(u8, r.stdout, "\n")
    else blk: {
        const why = std.mem.trimEnd(u8, r.stderr, "\n");
        break :blk if (why.len > 0)
            try std.fmt.allocPrint(ctx.arena, "Failed with exit code {d}: {s}", .{ code, why })
        else
            try std.fmt.allocPrint(ctx.arena, "Failed with exit code {d}", .{code});
    };

    try doc.write(ctx.out, ctx.mode, .{
        .sigil = if (code == 0) .result else .failed,
        .value = ctx.call_id,
        .content = content,
    });
    return code;
}

fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        // A signalled child is not an exit status; report it the way a shell
        // does rather than pretending it returned something.
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}

/// The environment rebuilt from the allowlist. HOME and TMPDIR are always the
/// sandbox's own directory: a tool gets somewhere real to write that says
/// nothing about whose machine this is.
fn contained(ctx: Ctx, tmp: []const u8) !*const std.process.Environ.Map {
    const rules = try sandbox.envAllowed(ctx.arena, ctx.io, ctx.env);
    var m: std.process.Environ.Map = .init(ctx.arena);
    var it = ctx.env.iterator();
    while (it.next()) |e| {
        if (sandbox.envPasses(rules, e.key_ptr.*)) try m.put(e.key_ptr.*, e.value_ptr.*);
    }
    if (tmp.len > 0) {
        try m.put("TMPDIR", tmp);
        try m.put("HOME", tmp);
    }
    const boxed = try ctx.arena.create(std.process.Environ.Map);
    boxed.* = m;
    return boxed;
}

fn makeTmp(ctx: Ctx) ![]const u8 {
    const base = ctx.env.get("TMPDIR") orelse "/tmp";
    var word: [8]u8 = undefined;
    ctx.io.random(&word);
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&word}) catch unreachable;
    const tmp = try std.fs.path.join(ctx.arena, &.{
        base, try std.fmt.allocPrint(ctx.arena, "m8call-{s}", .{&hex}),
    });
    try std.Io.Dir.cwd().createDirPath(ctx.io, tmp);
    return tmp;
}

/// `sandbox-exec -f <resolved> -D ... -- argv`
fn wrap(ctx: Ctx, argv: []const []const u8, locks: []const []const u8, tmp: []const u8) ![]const []const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.process.currentPath(ctx.io, &buf);
    const cwd = try ctx.arena.dupe(u8, buf[0..len]);
    const parent = std.fs.path.dirname(cwd) orelse "/";

    const src = try sandbox.profile(ctx.arena, ctx.io, ctx.env);
    const path = try std.fs.path.join(ctx.arena, &.{ tmp, "resolved.sb" });
    try std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = path,
        .data = try sandbox.resolve(ctx.arena, src, locks),
    });

    var full: std.ArrayList([]const u8) = .empty;
    try full.appendSlice(ctx.arena, &.{
        "sandbox-exec",
        "-f",
        path,
        "-D",
        try std.fmt.allocPrint(ctx.arena, "CWD={s}", .{cwd}),
        "-D",
        try std.fmt.allocPrint(ctx.arena, "PARENTWD={s}", .{parent}),
        "-D",
        try std.fmt.allocPrint(ctx.arena, "TMP={s}", .{tmp}),
    });
    try full.appendSlice(ctx.arena, argv);
    return full.items;
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
        \\m8 call — run a command under the locks in force
        \\
        \\  m8 [-l LOCKS] call NAME [ARGS]     an m8 command
        \\  m8 [-l LOCKS] call -- PROG [ARGS]  a program from the environment
        \\
        \\  --raw   hand stdout through instead of writing a receipt
        \\
        \\A lock only ever removes, so any combination is safe and the order
        \\never matters. -l adds to whatever the agent already carries.
        \\
        \\
    );
    for (sandbox.all) |r| {
        try w.print("  {s: <15} {s}{s}\n", .{
            r.name,
            r.summary,
            if (r.kernel) "" else "  (m8)",
        });
    }
    // What `call` accepts, asked rather than restated, so this cannot come to
    // advertise something it would refuse.
    const cmd = @import("../command.zig");
    try w.writeAll("\ncommands:\n\n");
    for (cmd.native) |c| try w.print("  {s: <15} {s}\n", .{ c.name, c.summary });
    for (cmd.all) |c| {
        if (!cmd.callable(c)) continue;
        try w.print("  {s: <15} {s}\n", .{ c.name, c.summary });
    }
    try w.flush();
    return 0;
}
