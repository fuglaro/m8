//! `secure-shield` — combine the space-separated restriction names in its
//! first argument into one sandbox profile, then run the wrapped command.

const std = @import("std");
const builtin = @import("builtin");
const api = @import("../api.zig");
const sandbox = @import("../sandbox.zig");
const wrapping = @import("shield/wrapping.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "secure-shield",
    .summary = "run it inside the sandbox profile, with restrictions applied",
    .takes = .nothing,
    .run = run,
    .help = page,
};

fn run(ctx: Ctx) !u8 {
    const w = try wrapping.cut(ctx.args);

    var names: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, w.name, " \t");
    while (it.next()) |name| try names.append(ctx.arena, name);
    if (names.items.len == 0) return wrapping.Error.UnknownRestriction;

    // A name with no line in the profile is refused. Not understanding what
    // was asked for is never a reason to apply less than was asked for.
    for (names.items) |n| if (sandbox.find(n) == null) {
        try ctx.err.print("m8 secure-shield: no restriction named '{s}'\n", .{n});
        return wrapping.Error.UnknownRestriction;
    };

    // The mob's scratch, which m8 made before the tool was launched. Run
    // straight from a shell there is no mob and nothing made one, so this
    // makes its own rather than refusing.
    var tmp = ctx.env.get("TMPDIR") orelse "";
    var made = false;

    if (builtin.os.tag != .macos) {
        try ctx.err.writeAll("m8 secure-shield: needs sandbox-exec, which is macOS only\n");
        return wrapping.Error.Unsupported;
    }
    if (tmp.len == 0) {
        tmp = try sandbox.makeTmp(ctx.arena, ctx.io, ctx.env);
        made = true;
    }
    const full = try sandbox.exec(ctx.arena, ctx.io, ctx.env, w.argv, names.items, tmp);

    var environ: ?*const std.process.Environ.Map = null;
    if (made)
        environ = try api.childEnvironment(ctx.arena, ctx, &.{.{ .key = "TMPDIR", .value = tmp }});
    return wrapping.through(ctx, full, environ);
}

fn page(ctx: Ctx, out: *std.Io.Writer) !void {
    _ = ctx;
    try out.writeAll(
        \\  m8 secure-shield "NAMES" CMD [ARGS]
        \\
        \\NAMES is one argument containing space-separated restrictions.
        \\They are combined into one sandbox profile before CMD runs:
        \\
        \\  m8 secure-shield "private airgap" bash -c 'ls'
        \\
        \\In a document, define the wrapper and activate it with names:
        \\
        \\  ▐ 🛡️:secure
        \\  │ `m8` `secure-shield`
        \\  ▐ 🛡️:secure private airgap
        \\
    );
    // Read from the same table validation uses, so help cannot drift from
    // what secure accepts.
    try out.writeAll("\nrestrictions:\n\n");
    for (sandbox.all) |r|
        try out.print("  {s: <22} {s}\n", .{ r.name, r.summary });
    try out.writeAll(
        \\
        \\A restriction it does not recognise is refused rather than ignored.
        \\Not understanding what was asked for is never a reason to apply less
        \\than was asked for.
        \\
    );
}
