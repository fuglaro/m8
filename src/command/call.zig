//! `call` — run a command.
//!
//!     m8 call PROG [ARGS]             run a program from the environment
//!     m8 call --no-wrap PROG [ARGS]   one that answers in records itself
//!     m8 call --md PROG [ARGS]        one that answers in markdown
//!
//! What a command may not do is not asked about here. A 🛡 is the process a
//! command runs inside, so refusing, asking and confining are all arranged
//! around this rather than as conditions within it — which is why there is no
//! flag, no list, and nothing to keep in step with what a shield can mean.
//!
//! Output is m8: the child's stdout becomes a 🧾 receipt, or a 📜 under `--md`. A non-zero exit is a
//! 🚫 naming the code, with the child's stderr after it when there was any —
//! a failure with no reason in it tells a model only that something broke.
//! Stdin remains whatever descriptor call was given. Stdout is captured only
//! so it can be written as the m8 answer while the program is still speaking.
//!
//! One ending is neither: exit 75 having said nothing, with a stderr that
//! opens `QUESTION:`. That is a question for the person, and it leaves here the way
//! it arrived so the run that made the call can put it to them.

const std = @import("std");
const api = @import("../api.zig");
const doc = @import("../m8/doc.zig");
const argline = @import("call/argline.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "call",
    .summary = "run a program and write its result as m8",
    // A spawned program owns stdin. Reading it here would take the bytes it
    // is waiting for.
    .takes = .nothing,
    .run = run,
    .help = page,
};

pub const Error = error{NothingToRun};

fn run(ctx: Ctx) !u8 {
    const how: Answer = if (ctx.args.len == 0)
        .framed
    else if (std.mem.eql(u8, ctx.args[0], "--no-wrap"))
        .unwrapped
    else if (std.mem.eql(u8, ctx.args[0], "--md"))
        .scrolled
    else
        .framed;
    const args = if (how == .framed) ctx.args else ctx.args[1..];
    if (args.len == 0) return help(ctx);
    const expanded = try argline.line(ctx.arena, ctx.env, ctx.err, args);
    if (expanded.len == 0) {
        try ctx.err.writeAll("m8 call: everything expanded away\n");
        return Error.NothingToRun;
    }

    // Which call this answers is said in the environment, like everything
    // else a call says. Typed at a shell there is none, and the answer names
    // nothing.
    var inner = ctx;
    if (ctx.env.get("M8_CALL_ID")) |id| inner.call_id = id;
    return execute(inner, expanded, how);
}

/// Run an already-built command line.
///
/// Whatever may not happen has already been arranged: the argv it is handed is
/// the tool standing inside its shields, so there is nothing left here to
/// gate. Refusing, asking and confining are wrappers around this, not
/// conditions inside it.
pub fn execute(ctx: Ctx, argv: []const []const u8, how: Answer) !u8 {
    if (argv.len == 0) return Error.NothingToRun;
    return spawn(ctx, argv, how);
}

/// What becomes of what the command said.
///
/// Framing is what `m8 call` is for, and a definition asks for it by naming
/// `call`. A tool's own command is run without it: it answers in m8, by
/// whatever means its definition chose, and is read rather than quoted.
pub const Answer = enum {
    /// Quoted into a 🧾, with a verdict under it. What `m8 call` does.
    framed,
    /// Quoted into a 📜 instead, to be read as markdown. What `m8 call --md`
    /// does.
    scrolled,
    /// Records the program wrote itself, such as a 🔗, with the verdict under
    /// them. What `m8 call --no-wrap` does.
    unwrapped,
    /// Passed through exactly as it stands. The caller reads the records; it
    /// neither needs nor receives framing from here.
    document,
};

/// Resolve the program after placeholders have settled which word is argv0.
/// `m8` there is the launcher that established this environment, just as it
/// is for a provider, tool, shield, or riff.
fn executable(arena: std.mem.Allocator, self: []const u8, expanded: []const []const u8) ![]const []const u8 {
    if (!std.mem.eql(u8, expanded[0], "m8")) return expanded;
    const copy = try arena.dupe([]const u8, expanded);
    copy[0] = self;
    return copy;
}

fn spawn(ctx: Ctx, argv: []const []const u8, how: Answer) !u8 {
    // What was inherited, and then what this call is saying. The call's own
    // values are put last, so an inherited variable cannot shadow them. What
    // a shield does to an environment it does in its own process, further out
    // than this one.
    const environ = try api.childEnvironment(ctx.arena, ctx, ctx.extra_env);
    const full = try executable(ctx.arena, ctx.self, argv);

    var child = try std.process.spawn(ctx.io, .{
        .argv = full,
        .environ_map = environ,
        .stdin = .inherit,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Both pipes are drained together. Reading one and then the other
    // deadlocks as soon as a tool fills the pipe nobody is reading — which is
    // why `std.process.run` did it this way, and the only thing that changes
    // here is that what arrives is written out rather than kept.
    var streams: std.Io.File.MultiReader.Buffer(2) = undefined;
    var pipes: std.Io.File.MultiReader = undefined;
    pipes.init(ctx.arena, ctx.io, streams.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer pipes.deinit();

    var said: Body = .{
        .out = ctx.out,
        .mode = ctx.mode,
        .call_id = ctx.call_id,
        .frame = how == .framed or how == .scrolled,
        .sigil = if (how == .scrolled) .scroll else .result,
    };
    var complaint: Tail = .{};

    // Read as much at a time as anything else here does. Everything is tossed
    // each round, so asking for the window back is a rebase rather than a
    // growth: the buffers settle at one window and stay there, however much
    // goes through them.
    const window = 64 * 1024;
    while (pipes.fill(window, .none)) |_| {
        const out = pipes.reader(0).buffered();
        if (out.len > 0) {
            try said.write(out);
            try ctx.out.flush();
            pipes.reader(0).toss(out.len);
        }
        const complained = pipes.reader(1).buffered();
        if (complained.len > 0) {
            complaint.keep(complained);
            pipes.reader(1).toss(complained.len);
        }
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }
    try pipes.checkAnyError();

    const code = status(try child.wait(ctx.io));
    const wrote = try said.finish();
    const why = complaint.written(ctx.arena) catch "";

    // A question for the person is handed up as it was asked, so whatever
    // stands outside this sees what the tool itself would have shown it.
    if (code == api.ask_exit and !wrote and std.mem.startsWith(u8, why, api.ask_lead)) {
        try ctx.err.print("{s}\n", .{why});
        return code;
    }
    if (how == .document) {
        // Nothing said and a failure is a wrapper that stopped the tool, and
        // why it did is all there is to tell the model.
        if (!wrote and code != 0 and why.len > 0) try ctx.err.print("{s}\n", .{why});
        return code;
    }

    // The verdict, which is only knowable now. Everything the tool said is
    // already written and already gone.
    if (wrote and !said.ended) try ctx.out.writeByte('\n');
    if (code == 0) {
        try doc.write(ctx.out, ctx.mode, .{ .sigil = .ok, .value = ctx.call_id });
        return 0;
    }

    try doc.write(ctx.out, ctx.mode, .{
        .sigil = .failed,
        .value = ctx.call_id,
        .content = if (why.len > 0)
            try std.fmt.allocPrint(ctx.arena, "Failed with exit code {d}: {s}", .{ code, why })
        else
            try std.fmt.allocPrint(ctx.arena, "Failed with exit code {d}", .{code}),
    });
    return code;
}

/// What a tool said, written into a 🧾 as it says it.
///
/// The record is opened on the first byte, because a tool that says nothing is
/// answered by its verdict alone and an empty 🧾 is a record of nothing.
///
/// Newlines at the end are held rather than written. A program ends its last
/// line, and that final newline is how it ends the line rather than a blank
/// line of content — but which newline is the last one cannot be known until
/// the stream stops. So they are kept back and written only once something
/// follows them, which is the streaming form of trimming the end.
const Body = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    call_id: []const u8,
    /// False for a 🧰 that declared it answers in m8: what it says is already
    /// records, and quoting them would make them content.
    frame: bool = true,
    sigil: doc.Sigil = .result,
    w: ?doc.ContentWriter = null,
    held: usize = 0,
    wrote: bool = false,
    /// Whether what was passed through ended its last line, so a verdict
    /// after it starts on a line of its own either way.
    ended: bool = false,

    fn write(b: *Body, bytes: []const u8) !void {
        if (!b.frame) {
            if (bytes.len == 0) return;
            b.wrote = true;
            b.ended = bytes[bytes.len - 1] == '\n';
            return b.out.writeAll(bytes);
        }
        var end = bytes.len;
        while (end > 0 and bytes[end - 1] == '\n') end -= 1;

        if (end == 0) {
            b.held += bytes.len;
            return;
        }
        if (b.w == null)
            b.w = try doc.ContentWriter.begin(b.out, b.mode, b.sigil, b.call_id);
        while (b.held > 0) : (b.held -= 1) try b.w.?.write("\n");
        try b.w.?.write(bytes[0..end]);
        b.held = bytes.len - end;
    }

    /// Whether anything was written, so the caller knows to separate what
    /// comes next from it.
    fn finish(b: *Body) !bool {
        if (!b.frame) return b.wrote;
        if (b.w) |*w| {
            try w.finish();
            return true;
        }
        return false;
    }
};

/// The last of what a tool complained about.
///
/// A failing program says why it failed at the end, so the end is what is
/// worth keeping — a fixed window that the newest bytes push the oldest out
/// of. Nothing grows, however much is written to it, and what lands in the
/// ledger is what a person would have scrolled to.
const Tail = struct {
    /// Whatever fits. A reason longer than this is a program logging rather
    /// than explaining, and the explanation is still at the bottom of it.
    const size = 8 * 1024;

    buf: [size]u8 = undefined,
    at: usize = 0,
    /// Whether the oldest bytes have been pushed out, which is what the
    /// leading `...` says when it lands.
    lost: bool = false,

    fn keep(t: *Tail, bytes: []const u8) void {
        // More than the window in one go: only its own tail can survive.
        if (bytes.len >= size) {
            @memcpy(&t.buf, bytes[bytes.len - size ..]);
            t.at = 0;
            t.lost = true;
            return;
        }
        const room = size - t.at;
        if (bytes.len < room) {
            @memcpy(t.buf[t.at..][0..bytes.len], bytes);
            t.at += bytes.len;
            return;
        }
        @memcpy(t.buf[t.at..][0..room], bytes[0..room]);
        @memcpy(t.buf[0 .. bytes.len - room], bytes[room..]);
        t.at = bytes.len - room;
        t.lost = true;
    }

    /// What was kept, oldest first, said to be a tail when it is one.
    fn written(t: *const Tail, arena: std.mem.Allocator) ![]const u8 {
        if (!t.lost) return std.mem.trimEnd(u8, t.buf[0..t.at], "\n");

        var whole: std.ArrayList(u8) = .empty;
        try whole.appendSlice(arena, t.buf[t.at..]);
        try whole.appendSlice(arena, t.buf[0..t.at]);

        // Begin at a line rather than wherever the window happened to cut,
        // which also keeps the cut from landing inside a character — unless
        // that would leave nothing, which is a program that wrote more than
        // the window without ever ending a line. Then the cut is where it
        // fell, since a partial line beats no line.
        var from: usize = 0;
        if (std.mem.indexOfScalar(u8, whole.items, '\n')) |nl| {
            if (nl + 1 < whole.items.len) from = nl + 1;
        }
        const kept = std.mem.trimEnd(u8, whole.items[from..], "\n");
        return std.fmt.allocPrint(arena, "...{s}", .{kept});
    }
};

fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        // A signalled child is not an exit status; report it the way a shell
        // does rather than pretending it returned something.
        .signal => |s| @as(u8, 128) +| @as(u8, @truncate(@intFromEnum(s))),
        else => 1,
    };
}

fn help(ctx: Ctx) !u8 {
    // Naming nothing to run is somebody finding out what may be run, so it is
    // a page they asked for rather than a mistake.
    try page(ctx, ctx.out);
    try ctx.out.flush();
    return 0;
}

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 call [--no-wrap|--md] PROG [ARGS]
        \\
        \\The program's stdout becomes a 🧾 receipt, followed by 🟢 or 🚫 for
        \\how it ended. Stdin remains the descriptor call itself was given.
        \\
        \\--md makes it a 📜 instead: the same answer, written to be read as
        \\markdown rather than as literal output.
        \\
        \\--no-wrap passes stdout through as the records the program wrote,
        \\such as a 🔗 for files it hands over, and still adds the verdict.
        \\A PROG named `m8` is the current launcher, whose absolute path every
        \\program is also handed as M8.
        \\
        \\A program asks the person something by exiting 75 with nothing on
        \\stdout and a stderr that opens `QUESTION:tool:`. It is run again
        \\once they answer, with what they said in $M8_EXCLAMATION_1,
        \\and the next answer in $M8_EXCLAMATION_2. Exiting 75 again
        \\without asking hands the
        \\conversation back to the person rather than the model.
        \\
        \\A whole argument naming a call variable becomes whole argv elements:
        \\
        \\  {{command}}       --command VALUE
        \\  {{command|-c}}    -c VALUE
        \\  {{command|}}      VALUE
        \\  {{deep?--deep}}   --deep, only when exactly true
        \\  {{deep!--deep}}   --deep, omit only when exactly true
        \\  {{}}              -- followed by the whole call as JSON
        \\  {{|}}             the whole call as JSON, without a flag
        \\
        \\An unset variable leaves nothing behind. An empty one remains an empty
        \\argument. A placeholder is a whole word, so its value cannot become
        \\syntax in the command being run.
        \\
        \\What a program may not do is a 🛡 rather than a flag here. A shield
        \\is the process a program runs inside, so it is arranged around this
        \\rather than asked about within it. See `m8 secure-shield` and `m8 ask-shield`.
        \\
    );
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "m8 in executable position is the current launcher" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const own = try executable(arena, "/opt/m8/bin/m8", &.{ "m8", "munge" });
    try testing.expectEqualStrings("/opt/m8/bin/m8", own[0]);
    try testing.expectEqualStrings("munge", own[1]);

    const other = &[_][]const u8{ "printf", "m8" };
    const untouched = try executable(arena, "/opt/m8/bin/m8", other);
    try testing.expectEqual(other.ptr, untouched.ptr);
    try testing.expectEqualStrings("m8", untouched[1]);
}

test "a tail keeps the end, and says when it dropped the start" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Under the window, it is everything, and the newline a program ends its
    // last line with is not part of what it said.
    var small: Tail = .{};
    small.keep("one\ntwo\n");
    try testing.expectEqualStrings("one\ntwo", try small.written(arena));

    // Over it, the end survives and the start is marked as gone.
    var full: Tail = .{};
    for (0..2000) |i|
        full.keep(try std.fmt.allocPrint(arena, "line {d}\n", .{i}));
    const kept = try full.written(arena);
    try testing.expect(std.mem.startsWith(u8, kept, "..."));
    try testing.expect(std.mem.endsWith(u8, kept, "line 1999"));
    try testing.expect(kept.len <= Tail.size + 3);
    // Whole lines: the window cut somewhere, and what is shown starts after
    // the next newline rather than mid-line.
    try testing.expect(std.mem.indexOf(u8, kept, "\nline ") != null);
    try testing.expect(std.mem.indexOf(u8, kept, "line 0\n") == null);

    // One write larger than the window is its own tail.
    var flood: Tail = .{};
    const big = try arena.alloc(u8, Tail.size * 3);
    @memset(big, 'x');
    @memcpy(big[big.len - 4 ..], "end\n");
    flood.keep(big);
    try testing.expect(std.mem.endsWith(u8, try flood.written(arena), "end"));
}

test "a body opens on the first byte and holds the last newline" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Nothing said is no record at all, so a verdict stands alone.
    var quiet: std.Io.Writer.Allocating = .init(arena);
    var none: Body = .{ .out = &quiet.writer, .mode = .md, .call_id = "c1" };
    try testing.expect(!try none.finish());
    try testing.expectEqualStrings("", quiet.written());

    // Newlines only are the same thing: a program that ended a line it never
    // began has said nothing.
    var blank: std.Io.Writer.Allocating = .init(arena);
    var only: Body = .{ .out = &blank.writer, .mode = .md, .call_id = "c1" };
    try only.write("\n\n");
    try testing.expect(!try only.finish());

    // Arriving in pieces reads the same as arriving whole, and the newline at
    // the end is how the last line ended rather than a line of its own.
    var split: std.Io.Writer.Allocating = .init(arena);
    var body: Body = .{ .out = &split.writer, .mode = .md, .call_id = "c1" };
    for ([_][]const u8{ "a\n", "\n", "b\n", "\n\n" }) |chunk| try body.write(chunk);
    try testing.expect(try body.finish());
    try testing.expectEqualStrings(
        \\#### :receipt:c1
        \\>     a
        \\>
        \\>     b
        \\
    , split.written());

    // Under --md the same answer is a 📜, carried as it is.
    var md: std.Io.Writer.Allocating = .init(arena);
    var scroll: Body = .{ .out = &md.writer, .mode = .md, .call_id = "c1", .sigil = .scroll };
    try scroll.write("# a\n");
    try testing.expect(try scroll.finish());
    try testing.expectEqualStrings("#### :scroll:c1\n> # a\n", md.written());
}

test "unwrapped records pass through, and a verdict always starts its own line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var out: std.Io.Writer.Allocating = .init(arena);
    var body: Body = .{ .out = &out.writer, .mode = .md, .call_id = "c1", .frame = false };
    try body.write("#### :link:c1\n> <a.jpeg");
    try testing.expect(try body.finish());
    try testing.expect(!body.ended);
    try testing.expectEqualStrings("#### :link:c1\n> <a.jpeg", out.written());

    try body.write("\n");
    try testing.expect(body.ended);
}
