//! Say something to an explicitly addressed conversation. Starting point,
//! storage and presentation are independent; stdin belongs to the caller
//! unless `-i` explicitly makes it part of the submission.
const std = @import("std");
const api = @import("../api.zig");
const doc = @import("../m8/doc.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const assembly = @import("../assembly.zig");
const ledger = @import("../ledger.zig");
const session = @import("../session.zig");
const converse = @import("../converse.zig");
const Keeping = @import("../keeping.zig").Keeping;
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "say",
    .summary = "say something to a chat, and keep the run",
    .takes = .nothing,
    .terminal = true,
    .run = run,
    .help = help,
};

const Options = struct {
    word: []const u8,
    prompt: []const u8 = "",
    chat: ?[]const u8 = null,
    start: address.Start = .head,
    stay: bool = false,
    piped: bool = false,
    render: bool = false,
    unwrap: bool = false,
    answer: bool = false,
    send: bool = true,
    verbosity: u8 = 0,

    fn parse(args: []const []const u8) !Options {
        var o: Options = .{ .word = "" };
        var i: usize = 0;
        while (i < args.len and !address.isAddress(args[i])) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-r")) {
                o.render = true;
            } else if (std.mem.eql(u8, arg, "-v")) {
                o.verbosity = @max(o.verbosity, 1);
            } else if (std.mem.eql(u8, arg, "-vv")) {
                o.verbosity = 2;
            } else if (std.mem.eql(u8, arg, "-i")) {
                o.piped = true;
            } else if (std.mem.eql(u8, arg, "--no-advance")) {
                o.stay = true;
            } else if (std.mem.eql(u8, arg, "--no-send")) {
                o.send = false;
            } else if (std.mem.eql(u8, arg, "--unwrap")) {
                o.unwrap = true;
            } else if (std.mem.eql(u8, arg, "--answer")) {
                o.answer = true;
            } else if (std.mem.eql(u8, arg, "--new") and o.start == .head) {
                o.start = .new;
            } else if (std.mem.eql(u8, arg, "--parent") and o.start == .head) {
                o.start = .parent;
            } else if (std.mem.eql(u8, arg, "--chat") and o.chat == null and i + 1 < args.len) {
                i += 1;
                o.chat = args[i];
            } else return error.InvalidOptions;
        }
        if (i == args.len or args.len > i + 2) return error.InvalidOptions;
        o.word = args[i];
        if (args.len == i + 2) o.prompt = args[i + 1];
        if (o.render and o.unwrap or !o.send and o.answer) return error.InvalidOptions;
        return o;
    }

    fn target(self: *Options, a: address.Address, arena: std.mem.Allocator) !address.Address {
        var out = a;
        if (self.chat) |chat| {
            if (a.suffix != .none or a.kind != .chat or !config.authored(a.name)) return error.ChatAddressConflict;
            const name = try std.fmt.allocPrint(arena, "{s}//{s}", .{ a.name, chat });
            if (config.mobName(name) == null or !session.isChat(name)) return error.InvalidName;
            out.name = name;
        }
        switch (a.suffix) {
            .none => {},
            .oneshot => self.stay = true,
            .reset, .reset_new => {
                const start: address.Start = if (a.suffix == .reset) .parent else .new;
                if (self.start != .head and self.start != start) return error.StartConflict;
                self.start = start;
            },
        }
        if (self.start != .head and a.kind != .chat) return error.NothingToReset;
        return out;
    }
};

fn run(given: Ctx) !u8 {
    var o = Options.parse(given.args) catch {
        try given.err.writeAll("m8 say: name one address and at most one quoted prompt; see m8 say --help\n");
        return 1;
    };
    var ctx = given;
    if (o.render) ctx.mode = .m8;
    if (o.unwrap or !o.send) ctx.mode = if (o.render) .m8 else .md;
    const arena = ctx.arena;
    const io = ctx.io;
    const dirs = try config.discover(arena, io, ctx.env);
    const typed = try address.typed(arena, io, dirs, o.word, ctx.err);
    const a = o.target(typed, arena) catch |e| {
        try ctx.err.writeAll(switch (e) {
            error.ChatAddressConflict => "m8 say: --chat takes an agent address without //chat or a suffix; use --no-advance, --parent or --new\n",
            error.StartConflict => "m8 say: the address suffix and starting option disagree\n",
            error.NothingToReset => "m8 say: only a chat can start from its parent or agent\n",
            error.InvalidName => "m8 say: --chat needs a relative chat path\n",
            else => return e,
        });
        return 1;
    };
    const name = if (o.start == .head)
        try address.found(arena, io, dirs, a, ctx.err)
    else
        try address.readFrom(arena, io, dirs, a, o.start);
    const asked = ledger.waiting(arena, io, dirs, name);
    const terminal = o.piped and ctx.stdin_terminal;
    const prose = if (!o.piped) "" else if (terminal)
        try readTerminal(ctx.stdin, arena)
    else if (ctx.stdin) |reader|
        try reader.allocRemaining(arena, .unlimited)
    else
        "";
    const said = try assembly.said(arena, o.prompt, prose, asked);
    var records: std.ArrayList(doc.Record) = .empty;
    try records.append(arena, .{ .sigil = .agent, .value = name });
    if (said) |r| try records.append(arena, r);
    var unwrapped: doc.Unwrap = .{};
    if (!o.send) {
        for (records.items) |r| {
            if (o.unwrap) try unwrapped.write(r, true, ctx.out) else try doc.write(ctx.out, ctx.mode, r);
        }
        return 0;
    }
    if (said == null) {
        if (terminal) return 0;
        if (!o.stay and !o.answer and o.start != .head) {
            if (o.start == .new) try address.renew(arena, io, dirs, a) else try address.reset(arena, io, dirs, a);
            return 0;
        }
        try ctx.err.writeAll("m8 say: say something after the address, or read prose with -i\n");
        return 1;
    }
    // Rendered submissions belong in scrollback even when stdin is a pipe
    // (as it is under riff). Only the padding is for terminal input echo.
    if (ctx.mode == .m8 and !o.answer and !o.unwrap) {
        if (terminal) try ctx.out.writeAll("  \n");
        // The agent reference and submission are separate records; user
        // submissions open a paragraph of their own.
        try ctx.out.writeByte('\n');
        try doc.write(ctx.out, .m8, said.?);
        try ctx.out.flush();
    }
    var document: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&document.writer, .md, records.items);
    var discard_buf: [1024]u8 = undefined;
    var discard: std.Io.Writer.Discarding = .init(&discard_buf);
    var inner = ctx;
    inner.in = document.written();
    const deferred = o.unwrap or o.answer;
    if (deferred) inner.out = &discard.writer;
    var keeping: Keeping = .{
        .arena = arena,
        .io = io,
        .dirs = dirs,
        .a = a,
        .moving = .{ .stay = o.stay },
        .home = try address.home(arena, io, dirs, a, name),
    };
    const verbosity = @max(ctx.verbosity, o.verbosity);
    const turn = try converse.run(inner, .{
        .owner = a.name,
        .keep = keeping.keeper(),
        .echo_given = !deferred and ctx.mode == .md,
        .verbosity = verbosity,
        .previous = if (ctx.mode == .m8 and !o.answer and !o.unwrap) said.?.sigil else null,
        .trace = if (verbosity >= 2) ctx.err else null,
    });
    const kept = try keeping.finish(turn);
    if (o.answer) {
        var n = turn.len;
        while (n > records.items.len) : (n -= 1) {
            const r = turn[n - 1];
            if ((r.sigil == .bot and (r.content != null or r.value.len > 0)) or (r.sigil == .question and r.content != null)) {
                if (o.unwrap) {
                    // A question's value identifies it; the answer text is its
                    // content, not that routing identifier.
                    try ctx.out.writeAll(r.content orelse r.value);
                    try ctx.out.writeByte('\n');
                } else try doc.write(ctx.out, ctx.mode, r);
                return 0;
            }
        }
        try ctx.err.writeAll("m8 say: the run ended without a reply or a question\n");
        return 1;
    }
    const receipt: doc.Record = .{ .sigil = .agent, .value = kept };
    if (o.unwrap) {
        for (turn) |r| try unwrapped.write(r, true, ctx.out);
        try unwrapped.write(receipt, true, ctx.out);
    } else {
        try doc.write(ctx.out, ctx.mode, receipt);
    }
    return 0;
}

// Canonical terminal reads end a submission at Ctrl-D, even when its final
// line has no newline. This is a single submission, not an editor or UI.
fn readTerminal(reader: ?*std.Io.Reader, arena: std.mem.Allocator) ![]const u8 {
    const r = reader orelse return "";
    var text: std.ArrayList(u8) = .empty;
    while (true) {
        r.fill(1) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        const got = r.buffered();
        try text.appendSlice(arena, got);
        r.toss(got.len);
        if (got[got.len - 1] != '\n') break;
    }
    return text.items;
}

fn help(_: Ctx, w: *std.Io.Writer) !void {
    try w.writeAll(
        \\  m8 say [OPTS] :MOB/AGENT[:|-|--] ["PROMPT"]
        \\
        \\Say something to a chat and keep the run. Only that chat advances.
        \\A subchat is a fork: :mob/agent//aside starts where its parent is.
        \\A trailing : asks without advancing; - starts from the parent;
        \\-- starts from the authored agent instead. With no submission,
        \\- or -- resets the chat without running it.
        \\
        \\PROMPT is one argument, even when it begins with a dash. It is a 🙋
        \\submission, or the ❗ answer when the conversation awaits one.
        \\Options precede the address. Stdin is untouched unless -i is given.
        \\
        \\  -r             render and stream, even when stdout is not a terminal
        \\  -v             report thoughts and tool calls on stderr, one line each
        \\  -vv            write the whole turn to stderr as it happens
        \\  -i             read stdin as prose and say it after PROMPT
        \\  --chat NAME    select a subchat instead of writing //NAME
        \\  --new          start from the agent, not the chat's current head
        \\  --parent       start from the chat's parent
        \\  --no-advance   keep the run without moving any chat
        \\  --no-send      show the reference and submission; run and change nothing
        \\  --answer       write only this run's final reply or question
        \\  --unwrap       remove m8 framing and write Markdown, as cat does
        \\
        \\--chat takes an agent address without //chat or a trailing suffix.
        \\Use --no-advance, --parent or --new with it. Starting options must
        \\agree with the suffix, and --new and --parent cannot be combined.
        \\--unwrap and -r are alternative spellings; --answer needs a run.
        \\
        \\A terminal receives rendered records; other stdout receives m8 Markdown.
        \\--answer --unwrap writes just the answer text, without routing values.
        \\An answer is taken only from this run, never an earlier turn.
        \\
        \\  m8 say :demo/mathy "Tell me about the Riemann sphere."
        \\  m8 say --chat aside --no-advance :demo/mathy "And the Möbius strip?"
        \\  m8 say --answer --unwrap :demo/critic "Review that."
        \\  m8 say --no-send :demo/mathy "Hello" | m8 send | m8 tag :demo/mathy
        \\
    );
}

test "say options leave the prompt alone and stdin opt-in" {
    const t = std.testing;
    const o = try Options.parse(&.{ "--chat", "aside", ":mob/agent", "--help" });
    try t.expectEqualStrings("--help", o.prompt);
    try t.expectEqualStrings("aside", o.chat.?);
    try t.expect(!o.piped);
    try t.expect((try Options.parse(&.{ "-i", ":mob/agent" })).piped);
    for ([_][]const []const u8{
        &.{ "--new", "--parent", ":mob/agent" },
        &.{ "--chat", ":mob/agent" },
        &.{ "--no-store", ":mob/agent" },
        &.{ "--piped", ":mob/agent" },
        &.{ "-r", "--unwrap", ":mob/agent" },
        &.{ "--answer", "--no-send", ":mob/agent" },
        &.{ ":mob/agent", "one", "two" },
    }) |args| try t.expectError(error.InvalidOptions, Options.parse(args));
}

test "chat option rejects suffixes but own-chat suffixes work" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    for ([_]address.Suffix{ .none, .oneshot, .reset, .reset_new }) |suffix| {
        var o: Options = .{ .word = ":mob/agent" };
        const a: address.Address = .{ .kind = .chat, .name = "mob/agent", .suffix = suffix };
        _ = try o.target(a, arena.allocator());
        try t.expectEqual(suffix == .oneshot, o.stay);
        var explicit: Options = .{ .word = ":mob/agent", .chat = "aside" };
        if (suffix == .none) {
            const result = try explicit.target(a, arena.allocator());
            try t.expectEqualStrings("mob/agent//aside", result.name);
        } else try t.expectError(error.ChatAddressConflict, explicit.target(a, arena.allocator()));
    }
    var o: Options = .{ .word = "", .chat = "aside" };
    try t.expectError(error.ChatAddressConflict, o.target(.{ .kind = .chat, .name = "mob/agent//other" }, arena.allocator()));
    var bad: Options = .{ .word = "", .start = .new };
    try t.expectError(error.StartConflict, bad.target(.{ .kind = .chat, .name = "mob/agent", .suffix = .reset }, arena.allocator()));
}

// The provider still runs as a real child; only the command's process boundary
// is supplied in memory. Each invocation gets its own config and storage.
const Invocation = struct {
    out: []const u8,
    err: []const u8,
    status: u8,
    consumed: usize,

    fn say(arena: std.mem.Allocator, io: std.Io, args: []const []const u8, input: []const u8, terminal: bool) !Invocation {
        const root = try @import("../test_tmp.zig").make(arena, io, "m8-say-ctx");
        defer std.Io.Dir.cwd().deleteTree(io, root) catch {};
        const agent = try std.fs.path.join(arena, &.{ root, "mobs/demo" });
        const providers = try std.fs.path.join(arena, &.{ root, "core/providers" });
        try std.Io.Dir.cwd().createDirPath(io, agent);
        try std.Io.Dir.cwd().createDirPath(io, providers);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ agent, "echo.md" }), .data = "* :brain::/toy/echo\n" });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ providers, "toy.json" }), .data = "{\"cmd\":[\"m8\",\"toy-provider\"]}\n" });
        var env: std.process.Environ.Map = .init(arena);
        try env.put("M8_CALL_ID", "ctx-test");
        try env.put(config.dirs_var, root);
        try env.put(config.user_root_var, try std.fs.path.join(arena, &.{ root, "user" }));
        try env.put(config.data_root_var, try std.fs.path.join(arena, &.{ root, "data" }));
        try env.put("HOME", root);
        try env.put("XDG_CONFIG_HOME", root);
        try env.put("XDG_DATA_HOME", root);
        try env.put("TMPDIR", root);
        var input_reader: std.Io.Reader = .fixed(input);
        var out: std.Io.Writer.Allocating = .init(arena);
        var err: std.Io.Writer.Allocating = .init(arena);
        const status = try command.run(.{
            .arena = arena,
            .io = io,
            .mode = .md,
            .env = &env,
            .self = @import("test_options").launcher,
            .args = args,
            .stdin = &input_reader,
            .stdin_terminal = terminal,
            .in = "",
            .out = &out.writer,
            .err = &err.writer,
            .stdout_pipe = true,
            .tty = null,
        });
        return .{ .out = out.written(), .err = err.written(), .status = status, .consumed = input_reader.seek };
    }
};

test "say through Ctx retains piped submissions in every presentation" {
    const t = std.testing;
    var heap: std.heap.ArenaAllocator = .init(t.allocator);
    defer heap.deinit();
    const arena = heap.allocator();
    var threaded: std.Io.Threaded = .init(t.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cases = [_]struct { flags: []const []const u8, user: ?[]const u8, bot: []const u8, texts: usize = 2 }{
        .{ .flags = &.{ "-r", "-i", "--no-advance", ":demo/echo" }, .user = "🙋", .bot = "🤖" },
        .{ .flags = &.{ "-i", "--no-advance", ":demo/echo" }, .user = ":raising_hand:", .bot = ":robot:" },
        .{ .flags = &.{ "-r", "-i", "--no-advance", "--answer", ":demo/echo" }, .user = null, .bot = "🤖", .texts = 1 },
        .{ .flags = &.{ "-i", "--no-advance", "--unwrap", ":demo/echo" }, .user = null, .bot = "ctx submission" },
    };
    for (cases) |case| {
        const result = try Invocation.say(arena, io, case.flags, "ctx submission\n", false);
        try t.expectEqual(@as(u8, 0), result.status);
        try t.expectEqualStrings("", result.err);
        try t.expectEqual(case.texts, std.mem.count(u8, result.out, "ctx submission"));
        const reply = std.mem.indexOf(u8, result.out, case.bot) orelse return error.MissingReply;
        if (case.user) |user| {
            try t.expectEqual(@as(usize, 1), std.mem.count(u8, result.out, user));
            const submitted = std.mem.indexOf(u8, result.out, user).?;
            try t.expect(submitted < reply);
            try t.expect(std.mem.indexOf(u8, result.out[submitted..reply], "ctx submission") != null);
        } else {
            try t.expectEqual(@as(usize, 0), std.mem.count(u8, result.out, "🙋"));
            try t.expectEqual(@as(usize, 0), std.mem.count(u8, result.out, ":raising_hand:"));
        }
        if (case.user != null and std.mem.eql(u8, case.flags[0], "-r")) {
            try t.expect(std.mem.indexOf(u8, result.out, "\n\n") != null);
            try t.expect(std.mem.indexOf(u8, result.out, "\n\n▐ 🤖") != null);
            try t.expect(std.mem.indexOf(u8, result.out, "ctx submission") != null);
            try t.expect(std.mem.indexOf(u8, result.out, "\n\n▐ 🧠") == null);
        }
    }
}

test "say supplied stdin is opt-in and terminal EOF is a single submission" {
    const t = std.testing;
    var heap: std.heap.ArenaAllocator = .init(t.allocator);
    defer heap.deinit();
    const arena = heap.allocator();
    var threaded: std.Io.Threaded = .init(t.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const untouched = try Invocation.say(arena, io, &.{ "--no-send", ":demo/echo", "prompt" }, "not submitted", false);
    try t.expectEqual(@as(u8, 0), untouched.status);
    try t.expectEqual(@as(usize, 0), untouched.consumed);
    try t.expect(std.mem.indexOf(u8, untouched.out, "not submitted") == null);
    for ([_][]const u8{ "", "final without newline", "first\nsecond\n" }) |input| {
        const result = try Invocation.say(arena, io, &.{ "-i", "--no-send", ":demo/echo" }, input, true);
        try t.expectEqual(@as(u8, 0), result.status);
        try t.expectEqualStrings("", result.err);
        var lines = std.mem.tokenizeScalar(u8, input, '\n');
        while (lines.next()) |line| try t.expect(std.mem.indexOf(u8, result.out, line) != null);
        try t.expectEqual(input.len, result.consumed);
    }
}
