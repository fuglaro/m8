//! `shield` — the wrappers m8 ships with.
//!
//! A shield is a command that runs a command. These two are the ones that
//! could not be written in the shell: `secure` needs the profile that decides
//! what a restriction means, and `ask` needs the person. Everything else a
//! shield does is a program you already have, which is why `deny` is
//! `/usr/bin/false` and a filter is a pipe.
//!
//! Both take the command they wrap after `--` and run it in their own place,
//! so what a tool sees is one process and one exit status however many
//! wrappers it stood inside.

const std = @import("std");
const builtin = @import("builtin");
const sandbox = @import("../sandbox.zig");
const converse = @import("../converse.zig");
const api = @import("api.zig");
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

pub const command: api.Command = .{
    .name = "shield",
    .summary = "run a command inside one of the wrappers m8 ships with",
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 shield — run a command inside one of the wrappers m8 ships with
        \\
        \\  m8 shield secure "RESTRICTIONS" -- CMD [ARGS]
        \\  m8 shield ask -- CMD [ARGS]
        \\  m8 shield check AGENT -- CMD [ARGS]
        \\
        \\A shield is a command that runs a command, so most of them are
        \\programs you already have and are written in the language rather
        \\than here. These two could not be: `secure` needs the profile that
        \\decides what a restriction means, and `ask` needs the person.
        \\
        \\`secure` takes its restrictions as one space separated argument,
        \\which is how a 🛡 hands over what was appended to its variable:
        \\
        \\  ▄ 🛡️secure
        \\  │ ```bash
        \\  │ exec m8 shield secure "${SECURES}" -- "$@"
        \\  │ ```
        \\  ▄ 🛡️secure SECURES airgap
        \\
        \\A restriction it does not recognise is refused rather than ignored.
        \\Not understanding what was asked for is never a reason to apply less
        \\than was asked for.
        \\
        \\`ask` puts the command to whoever is at the terminal. With no
        \\terminal there is nobody to ask, and the answer is no.
        \\
    );
}

/// `m8 shield NAME [ARGS] -- CMD...`
fn run(ctx: Ctx) !u8 {
    const cut = for (ctx.args, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--")) break i;
    } else return Error.NothingToWrap;

    const head = ctx.args[0..cut];
    const argv = ctx.args[cut + 1 ..];
    if (head.len == 0 or argv.len == 0) return Error.NothingToWrap;

    if (std.mem.eql(u8, head[0], "ask")) return ask(ctx, argv);
    if (std.mem.eql(u8, head[0], "secure")) return secure(ctx, head[1..], argv);
    if (std.mem.eql(u8, head[0], "check")) return check(ctx, head[1..], argv);
    try ctx.err.print("m8 shield: no shield named '{s}'\n", .{head[0]});
    return Error.UnknownShield;
}

/// Put the command to the person. Nobody to ask is a no: a pipe or a cron job
/// must not be a way of skipping the question.
fn ask(ctx: Ctx, argv: []const []const u8) !u8 {
    const t = ctx.tty orelse {
        try ctx.err.writeAll("m8 shield: 'ask' is in force and there is no terminal\n");
        return Error.Refused;
    };
    try t.prompt("run: {s} ? [y/N] ", .{try std.mem.join(ctx.arena, " ", argv)});
    const line = (try t.line()) orelse return Error.Refused;
    const answer = std.mem.trim(u8, line, " \t");
    if (!std.mem.eql(u8, answer, "y") and !std.mem.eql(u8, answer, "Y")) return Error.Refused;
    return through(ctx, argv, null);
}

/// Put the command to an agent, which answers `allow` or explains itself.
///
/// A checker reads text an attacker may have shaped, so it belongs beside
/// `ask` rather than instead of it. It is never more capable than what invoked
/// it, because it runs inside every shield that was already standing there.
fn check(ctx: Ctx, head: []const []const u8, argv: []const []const u8) !u8 {
    if (head.len == 0 or head[0].len == 0) {
        try ctx.err.writeAll("m8 shield check: name the agent to ask\n");
        return Error.NothingToWrap;
    }
    const verdict = converse.check(ctx, head[0], argv) catch |e| {
        try ctx.err.print("m8 shield check: {s}\n", .{@errorName(e)});
        return Error.Refused;
    };
    if (verdict) |why| {
        try ctx.err.print("m8 shield check: {s}\n", .{why});
        return Error.Refused;
    }
    return through(ctx, argv, null);
}

/// Run inside the sandbox profile with the named restrictions taken away.
fn secure(ctx: Ctx, head: []const []const u8, argv: []const []const u8) !u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (head) |word| {
        var it = std.mem.tokenizeAny(u8, word, " \t");
        while (it.next()) |name| try names.append(ctx.arena, name);
    }
    if (names.items.len == 0) return through(ctx, argv, null);

    // A name with no line in the profile is refused. Not understanding what
    // was asked for is never a reason to apply less than was asked for.
    for (names.items) |n| if (sandbox.find(n) == null) {
        try ctx.err.print("m8 shield secure: no restriction named '{s}'\n", .{n});
        return Error.UnknownRestriction;
    };

    var kernel: std.ArrayList([]const u8) = .empty;
    for (names.items) |n| if (sandbox.isKernel(n)) try kernel.append(ctx.arena, n);

    var full = argv;
    var tmp: []const u8 = "";
    if (kernel.items.len > 0) {
        if (builtin.os.tag != .macos) {
            try ctx.err.writeAll("m8 shield secure: needs sandbox-exec, which is macOS only\n");
            return Error.Unsupported;
        }
        tmp = try sandbox.makeTmp(ctx.arena, ctx.io, ctx.env);
        full = try sandbox.exec(ctx.arena, ctx.io, ctx.env, argv, kernel.items, tmp);
    }

    var environ: ?*const std.process.Environ.Map = null;
    if (sandbox.containsEnv(names.items)) {
        environ = try sandbox.contained(ctx.arena, ctx.io, ctx.env, tmp);
    } else if (tmp.len > 0) {
        var m = try ctx.env.clone(ctx.arena);
        try m.put("TMPDIR", tmp);
        const boxed = try ctx.arena.create(std.process.Environ.Map);
        boxed.* = m;
        environ = boxed;
    }
    return through(ctx, full, environ);
}

/// Hand the command the terminal and this process's exit status. A wrapper is
/// not a filter: what it wraps talks to whoever m8 was talking to.
fn through(ctx: Ctx, argv: []const []const u8, environ: ?*const std.process.Environ.Map) !u8 {
    try ctx.out.flush();
    try ctx.err.flush();
    var child = try std.process.spawn(ctx.io, .{ .argv = argv, .environ_map = environ });
    return switch (try child.wait(ctx.io)) {
        .exited => |code| code,
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}
