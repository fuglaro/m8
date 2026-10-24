//! `reset` — say what a chat follows.
//!
//! A chat with no pointer of its own reads as its parent's head, so taking
//! the pointer away is the whole of starting over. The two options are the
//! two other things a chat can be made to follow: the agent it is under, and
//! anything named.
//!
//! It is the plain form of the address prompt's trailing `-`, for whatever has
//! parameters rather than a command line to write a suffix on.

const std = @import("std");
const config = @import("../config.zig");
const address = @import("../address.zig");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "reset",
    .summary = "start a chat over, or say what it follows",
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 reset [--new | --to :MOB/AGENT//CHAT] :MOB/AGENT//CHAT
        \\
        \\Takes the chat's pointer away, so it reads as its parent again: a
        \\chat under another starts wherever that one has got to, and an
        \\agent's own chat starts from the agent. No turn is touched.
        \\
        \\  --new          start from the agent the chat is under, whatever
        \\                 the chats above it have got to
        \\  --to :MOB/AGENT//CHAT   follow TARGET as it is named, unsettled
        \\
        \\A chat named as TARGET is followed rather than read: what points at
        \\it reads as wherever it gets to, until it is itself moved on.
        \\The target must belong to the same mob.
        \\
        \\  m8 reset :demo/mathy//aside               aside reads as mathy again
        \\  m8 reset --new :demo/critic//job          job reads as critic, untalked to
        \\  m8 reset --to :demo/mathy//aside :demo/mathy//other    follow aside
        \\
        \\Something that would lead back to itself is refused.
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    var new = false;
    var to: ?[]const u8 = null;

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        if (std.mem.eql(u8, arg, "--new")) {
            new = true;
        } else if (std.mem.eql(u8, arg, "--to") and i + 1 < ctx.args.len) {
            i += 1;
            to = ctx.args[i];
        } else break;
    }
    if (i + 1 != ctx.args.len or !address.isAddress(ctx.args[i]) or (new and to != null)) {
        try ctx.err.writeAll("m8 reset: name one :MOB/AGENT//CHAT, after `--new` or `--to :MOB/AGENT//CHAT` if either\n");
        return 1;
    }

    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    const a = try address.typed(ctx.arena, ctx.io, dirs, ctx.args[i], ctx.err);
    if (a.suffix != .none) {
        try ctx.err.writeAll("m8 reset: the address carries no `:` or `-`; this is what `-` does\n");
        return 1;
    }

    if (to) |word| {
        const target = try address.typed(ctx.arena, ctx.io, dirs, word, ctx.err);
        if (target.suffix != .none) {
            try ctx.err.writeAll("m8 reset: the target carries no `:` or `-`\n");
            return 1;
        }
        // Followed as named, but still something that is there to follow.
        if (target.kind == .turn) _ = try address.found(ctx.arena, ctx.io, dirs, target, ctx.err);
        try address.follow(ctx.arena, ctx.io, dirs, a, target);
    } else if (new) {
        try address.renew(ctx.arena, ctx.io, dirs, a);
    } else {
        try address.reset(ctx.arena, ctx.io, dirs, a);
    }
    return 0;
}
