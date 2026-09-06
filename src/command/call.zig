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
    .help = page,
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
        // The flag is m8's wherever it is written, and an inbuilt tool has no
        // other way to be asked: it is never a command of its own.
        if (api.wantsHelp(sub.args)) {
            sub.args = sub.args[1..];
            try @import("help.zig").write(sub, inner, ctx.out);
            try ctx.out.flush();
            return 0;
        }
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

    var child = try std.process.spawn(ctx.io, .{
        .argv = full,
        .environ_map = environ,
        .stdin = .ignore,
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

    var said: Body = .{ .out = ctx.out, .mode = ctx.mode, .call_id = ctx.call_id };
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

    // The verdict, which is only knowable now. Everything the tool said is
    // already written and already gone.
    if (wrote) try ctx.out.writeByte('\n');
    if (code == 0) {
        try doc.write(ctx.out, ctx.mode, .{ .sigil = .ok, .value = ctx.call_id });
        return 0;
    }

    const why = complaint.written(ctx.arena) catch "";
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
    w: ?doc.ContentWriter = null,
    held: usize = 0,

    fn write(b: *Body, bytes: []const u8) !void {
        var end = bytes.len;
        while (end > 0 and bytes[end - 1] == '\n') end -= 1;

        if (end == 0) {
            b.held += bytes.len;
            return;
        }
        if (b.w == null)
            b.w = try doc.ContentWriter.begin(b.out, b.mode, .result, b.call_id);
        while (b.held > 0) : (b.held -= 1) try b.w.?.write("\n");
        try b.w.?.write(bytes[0..end]);
        b.held = bytes.len - end;
    }

    /// Whether anything was written, so the caller knows to separate what
    /// comes next from it.
    fn finish(b: *Body) !bool {
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
    try page(ctx, ctx.err);
    try ctx.err.flush();
    return e;
}

fn help(ctx: Ctx) !u8 {
    // Naming nothing to run is somebody finding out what may be run, so it is
    // a page they asked for rather than a mistake.
    try page(ctx, ctx.out);
    try ctx.out.flush();
    return 0;
}

fn page(ctx: Ctx, w: *std.Io.Writer) !void {
    // Whatever is left names something `call` can reach: `m8 help call ask`
    // and `m8 call ask --help` are the same page.
    if (ctx.args.len > 0) {
        if (@import("../command.zig").findCallable(ctx.args[0])) |inner| {
            var sub = ctx;
            sub.args = ctx.args[1..];
            return @import("help.zig").write(sub, inner, w);
        }
    }
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
    try w.writeAll("\nm8 call NAME --help is that one's page.\n");
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

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
        \\> a
        \\>
        \\> b
        \\
    , split.written());
}
