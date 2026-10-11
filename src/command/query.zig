//! `query` — say something to a chat, and answer with what it said back.
//!
//!     m8 ref @CHAT MESSAGE | m8 send | m8 tag @CHAT |
//!         m8 encode | m8 tail --sigil robot --sigil question --block
//!
//! is what this does, written once. It is one process, so the run is tagged
//! as it goes and a run that dies keeps everything up to where it died.
//!
//! It is the form of the `@` prompt that something with parameters calls: an
//! address, then the message, and options in front where a message can never
//! be mistaken for one. What comes back is text, with the ledger kept out of
//! the way, which is what a 🧰 running an agent wants to hand its caller.
//!
//! The main chat is left where it is, so an agent run this way from a tool
//! never takes over the conversation of whoever is at the terminal.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const converse = @import("../converse.zig");
const ledger = @import("../ledger.zig");
const Keeping = @import("../keeping.zig").Keeping;
const api = @import("api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "query",
    .summary = "say something to a chat, and answer with what it said back",
    // Its message is its arguments. Run by a tool, stdin is whatever that
    // tool was handed, which is not this command's to wait on.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\m8 query — say something to a chat, and answer with what it said back
        \\
        \\  m8 query [-v | -vv] [--no-advance] [--new | --parent] @ADDRESS MESSAGE
        \\
        \\Says MESSAGE to the address, runs until it replies or asks, keeps
        \\the run, and writes the reply as the text it is. The ledger is not
        \\written: stdout is the reply and nothing else.
        \\
        \\  m8 query @mathy "What is a Riemann sphere?"
        \\  m8 query @critic/job-1 "Review that."        a chat of its own
        \\
        \\Every word after the address is the message, so one that opens
        \\with a dash is still the message. Options go before the address.
        \\
        \\  --no-advance   keep the run and move nothing: a side question
        \\  --new          start from the agent, not from where the chat is
        \\  --parent       start from where the chat's parent is
        \\  -v             on stderr, a line as it thinks and as it calls a tool
        \\  -vv            on stderr, the whole turn as it is made
        \\
        \\A reply and a question come back the same way. Whatever is said to
        \\the chat next answers the question, so the caller carries on by
        \\calling this again.
        \\
        \\A chat moves on to the run; the main chat does not, unless `@` is
        \\the address. A run that ends on neither a reply nor a question is
        \\an error, and says so on stderr.
        \\
        \\It is a pipeline written once:
        \\
        \\  m8 ref @mathy "hi" | m8 send | m8 tag @mathy |
        \\      m8 encode | m8 tail --sigil robot --sigil question --block
        \\
    );
}

fn run(ctx: Ctx) !u8 {
    const arena = ctx.arena;
    const io = ctx.io;

    var verbose = false;
    var whole = false;
    var moving: address.Moving = .{};
    var start: address.Start = .head;

    // Options end at the address. Everything after it is what was said.
    var i: usize = 0;
    while (i < ctx.args.len and !address.isAddress(ctx.args[i])) : (i += 1) {
        const arg = ctx.args[i];
        if (std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-vv")) {
            whole = true;
        } else if (std.mem.eql(u8, arg, "--no-advance")) {
            moving.stay = true;
        } else if (std.mem.eql(u8, arg, "--new") and start == .head) {
            start = .new;
        } else if (std.mem.eql(u8, arg, "--parent") and start == .head) {
            start = .parent;
        } else {
            try ctx.err.print("m8 query: '{s}' is not something it takes; see m8 query --help\n", .{arg});
            return 1;
        }
    }
    if (i == ctx.args.len) {
        try ctx.err.writeAll("m8 query: name one @ADDRESS, and then what to say to it\n");
        return 1;
    }

    const dirs = try config.discover(arena, io, ctx.env);
    const a = try address.typed(arena, io, dirs, ctx.args[i], ctx.err);
    if (a.suffix != .none) {
        try ctx.err.writeAll(
            "m8 query: the address carries no `:` or `-`; " ++
                "those are `--no-advance` and `--parent`\n",
        );
        return 1;
    }
    if (start != .head and a.kind != .chat) {
        try ctx.err.writeAll("m8 query: only a chat starts over; `--new` and `--parent` want one\n");
        return 1;
    }

    const name = if (start == .head)
        try address.found(arena, io, dirs, a, ctx.err)
    else
        try address.readFrom(arena, io, dirs, a, start);

    const prompt = try std.mem.join(arena, " ", ctx.args[i + 1 ..]);
    const said = (try assembly.said(arena, prompt, "", ledger.waiting(arena, io, dirs, name))) orelse {
        try ctx.err.writeAll("m8 query: say something after the address\n");
        return 1;
    };
    const given = [_]doc.Record{ .{ .sigil = .agent, .value = name }, said };
    var document: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&document.writer, .md, &given);

    // The run writes its turn as it goes. That is the ledger, which is not
    // what was asked for: it goes to stderr when it was, and nowhere when not.
    var nowhere_buf: [1024]u8 = undefined;
    var nowhere: std.Io.Writer.Discarding = .init(&nowhere_buf);
    var inner = ctx;
    inner.in = document.written();
    inner.mode = .md;
    inner.out = if (whole) ctx.err else &nowhere.writer;

    var keeping: Keeping = .{
        .arena = arena,
        .io = io,
        .dirs = dirs,
        .a = a,
        .moving = moving,
        .home = try address.home(arena, io, dirs, a, name),
    };
    const turn = try converse.run(inner, .{
        .keep = keeping.keeper(),
        .echo_given = whole,
        // The whole turn already says what the lines would.
        .verbose = verbose and !whole,
    });
    _ = try keeping.finish(turn);

    // Only what this run said. A reply from before it is not an answer to
    // what was just asked, and handing one back would say that it was.
    const reply = reply: {
        var n = turn.len;
        while (n > given.len) : (n -= 1) {
            const r = turn[n - 1];
            if ((r.sigil == .bot or r.sigil == .question) and r.content != null) break :reply r.content.?;
        }
        try ctx.err.writeAll("m8 query: the run ended without a reply or a question\n");
        return 1;
    };
    try ctx.out.writeAll(reply);
    try ctx.out.writeByte('\n');
    return 0;
}
