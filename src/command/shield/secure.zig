//! `shield secure` — run inside the sandbox profile with restrictions taken
//! away.
//!
//! The other one that could not be written in the shell: this needs the
//! profile that decides what a restriction means. Its restrictions arrive as
//! one space separated argument, which is how a 🛡 hands over what was
//! appended to its variable.

const std = @import("std");
const builtin = @import("builtin");
const api = @import("../api.zig");
const sandbox = @import("../../sandbox.zig");
const wrapping = @import("wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "secure",
    .summary = "run it inside the sandbox profile, with restrictions applied",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);

    var names: std.ArrayList([]const u8) = .empty;
    for (w.head) |word| {
        var it = std.mem.tokenizeAny(u8, word, " \t");
        while (it.next()) |name| try names.append(ctx.arena, name);
    }
    if (names.items.len == 0) return wrapping.through(ctx, w.argv, null);

    // A name with no line in the profile is refused. Not understanding what
    // was asked for is never a reason to apply less than was asked for.
    for (names.items) |n| if (sandbox.find(n) == null) {
        try ctx.err.print("m8 shield secure: no restriction named '{s}'\n", .{n});
        return wrapping.Error.UnknownRestriction;
    };

    var kernel: std.ArrayList([]const u8) = .empty;
    for (names.items) |n| if (sandbox.isKernel(n)) try kernel.append(ctx.arena, n);

    // The mob's scratch, which m8 made before the tool was launched. Run
    // straight from a shell there is no mob and nothing made one, so this
    // makes its own rather than refusing.
    var tmp = ctx.env.get("TMPDIR") orelse "";
    var made = false;

    var full = w.argv;
    if (kernel.items.len > 0) {
        if (builtin.os.tag != .macos) {
            try ctx.err.writeAll("m8 shield secure: needs sandbox-exec, which is macOS only\n");
            return wrapping.Error.Unsupported;
        }
        // m8's own scratch for this call, which is where the resolved profile
        // goes. Never the tool's: that one is shared by a mob.
        const own = try sandbox.makeTmp(ctx.arena, ctx.io, ctx.env);
        if (tmp.len == 0) {
            tmp = own;
            made = true;
        }
        full = try sandbox.exec(ctx.arena, ctx.io, ctx.env, w.argv, kernel.items, own, tmp);
    }

    var environ: ?*const std.process.Environ.Map = null;
    if (sandbox.containsEnv(names.items)) {
        environ = try sandbox.contained(ctx.arena, ctx.io, ctx.env, tmp);
    } else if (made) {
        var m = try ctx.env.clone(ctx.arena);
        try m.put("TMPDIR", tmp);
        const boxed = try ctx.arena.create(std.process.Environ.Map);
        boxed.* = m;
        environ = boxed;
    }
    return wrapping.through(ctx, full, environ);
}

fn page(ctx: Ctx, out: *std.Io.Writer) !void {
    _ = ctx;
    try out.writeAll(
        \\m8 shield secure — run it inside the sandbox profile
        \\
        \\  m8 shield secure "RESTRICTIONS" -- CMD [ARGS]
        \\
        \\Restrictions come as one space separated argument, which is how a
        \\🛡 hands over what was appended to its variable:
        \\
        \\  ▐ 🛡️secure
        \\  │ `bash` `-e` `-c` `exec {{M8}} shield secure "${__secures__}" -- "$@"` `bash`
        \\  ▐ 🛡️secure secures airgap
        \\
        \\A restriction it does not recognise is refused rather than ignored.
        \\Not understanding what was asked for is never a reason to apply less
        \\than was asked for.
        \\
    );
}
