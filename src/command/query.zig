//! `query` — say something to a chat, and answer with what it said back.
//!
//!     m8 ref :MOB/AGENT//CHAT MESSAGE | m8 send | m8 tag :MOB/AGENT//CHAT |
//!         m8 encode | m8 tail --sigil robot --sigil question --block
//!
//! is what this does, written once. It is one process, so the run is tagged
//! as it goes and a run that dies keeps everything up to where it died.
//!
//! It is the form of the address prompt that something with parameters calls: an
//! address, then the message as one argument, and options in front where a
//! message can never be mistaken for one. What comes back is text, with the ledger kept out of
//! the way, which is what a 🧰 running an agent wants to hand its caller.
//!
//! Only the explicitly addressed chat is advanced. Another mob can be
//! activated by a new command invocation, with its own resolution scope.

const std = @import("std");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const converse = @import("../converse.zig");
const ledger = @import("../ledger.zig");
const Keeping = @import("../keeping.zig").Keeping;
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "query",
    .summary = "say something to a chat, and answer with what it said back",
    // Its message is its argument. Run by a tool, stdin is whatever that tool
    // was handed, which is not this command's to wait on unless `--piped`
    // says it is.
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 query [-v | -vv] [--no-advance | --no-store] [--new | --parent] [--piped] :MOB/AGENT [MESSAGE]
        \\
        \\Says MESSAGE to the address, runs until it replies or asks, keeps
        \\the run, and writes the reply as the text it is. The ledger is not
        \\written: stdout is the reply and nothing else.
        \\
        \\  m8 query :demo/mathy "What is a Riemann sphere?"
        \\  m8 query :demo/critic//job-1 "Review that."        a chat of its own
        \\
        \\MESSAGE is the one argument after the address, so one that opens
        \\with a dash is still the message. Options go before the address.
        \\
        \\  --no-advance   keep the run and move nothing: a side question
        \\  --no-store     keep nothing, so nothing moves and nothing is written
        \\  --new          start from the agent, not from where the chat is
        \\  --parent       start from where the chat's parent is
        \\  --piped        read stdin as prose, and say it after the MESSAGE
        \\  -v             on stderr, a line as it thinks and as it calls a tool
        \\  -vv            on stderr, the whole turn as it is made
        \\
        \\A reply and a question come back the same way. Whatever is said to
        \\the chat next answers the question, so the caller carries on by
        \\calling this again.
        \\
        \\Only the explicitly addressed chat advances. A run that ends on
        \\neither a reply nor a question is
        \\an error, and says so on stderr.
        \\
        \\It is a pipeline written once:
        \\
        \\  m8 ref :demo/mathy "hi" | m8 send | m8 tag :demo/mathy |
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
    var piped = false;
    var store = true;

    // Options end at the address. The one argument after it is what was said.
    var i: usize = 0;
    while (i < ctx.args.len and !address.isAddress(ctx.args[i])) : (i += 1) {
        const arg = ctx.args[i];
        if (std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-vv")) {
            whole = true;
        } else if (std.mem.eql(u8, arg, "--no-advance")) {
            moving.stay = true;
        } else if (std.mem.eql(u8, arg, "--no-store")) {
            store = false;
        } else if (std.mem.eql(u8, arg, "--piped")) {
            piped = true;
        } else if (std.mem.eql(u8, arg, "--new") and start == .head) {
            start = .new;
        } else if (std.mem.eql(u8, arg, "--parent") and start == .head) {
            start = .parent;
        } else {
            try ctx.err.print("m8 query: '{s}' is not something it takes; see m8 query --help\n", .{arg});
            return 1;
        }
    }
    if (i == ctx.args.len or ctx.args.len > i + 2) {
        try ctx.err.writeAll("m8 query: name one :MOB/AGENT, and then one MESSAGE to say to it\n");
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

    const prompt = if (ctx.args.len == i + 2) ctx.args[i + 1] else "";
    var in_buf: [64 * 1024]u8 = undefined;
    const prose = if (piped) try api.readDocument(io, arena, &in_buf) else "";
    const said = (try assembly.said(arena, prompt, prose, ledger.waiting(arena, io, dirs, name))) orelse {
        try ctx.err.writeAll("m8 query: say something after the address, or pipe it in with `--piped`\n");
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
        .home = if (store) try address.home(arena, io, dirs, a, name) else "",
    };
    const turn = try converse.run(inner, .{
        .owner = a.name,
        .keep = if (store) keeping.keeper() else null,
        .echo_given = whole,
        // The whole turn already says what the lines would.
        .verbosity = if (whole) 2 else @intFromBool(verbose),
    });
    if (store) _ = try keeping.finish(turn);

    // Only what this run said. A reply from before it is not an answer to
    // what was just asked, and handing one back would say that it was.
    const reply = reply: {
        var n = turn.len;
        while (n > given.len) : (n -= 1) {
            const r = turn[n - 1];
            if (r.sigil == .bot) {
                if (r.content) |text| break :reply text;
                if (r.value.len > 0) break :reply r.value;
            }
            if (r.sigil == .question and r.content != null) break :reply r.content.?;
        }
        try ctx.err.writeAll("m8 query: the run ended without a reply or a question\n");
        return 1;
    };
    try ctx.out.writeAll(reply);
    try ctx.out.writeByte('\n');
    return 0;
}
