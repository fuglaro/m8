//! Running a ledger: saying what it says, and doing what it asks for.
//!
//! The ledger is the conversation. A reply is appended to it, a 📲 is
//! appended to it, and the answer to that 📲 is appended to it — so what goes
//! back to the model next time round is the same records a person would read.
//! Nothing is assembled on the side and nothing is thrown away.
//!
//! What a run hands back is the ledger as it arrived, still naming what it
//! continues, plus whatever this run added — a turn, ready to be kept.
//! Expanding that gives back exactly what ran. Keeping it is `tag`'s business,
//! not this one's.

const std = @import("std");
const Allocator = std.mem.Allocator;
const agent = @import("agent.zig");
const config = @import("config.zig");
const ledger = @import("ledger.zig");
const policy = @import("policy.zig");
const provider = @import("provider.zig");
const session = @import("session.zig");
const codec = @import("codec.zig");
const toolbox = @import("toolbox.zig");
const shield = @import("shield.zig");
const doc = @import("m8/doc.zig");
const sigil = @import("m8/sigil.zig");
const api = @import("command/api.zig");
const Ctx = api.Ctx;

pub const Options = struct {
    /// Write the ledger that arrived ahead of what the run adds, so what goes
    /// out is the whole turn. What `send` does under a pipe; a terminal is
    /// only ever shown the reply.
    echo_given: bool = false,
    /// Keep the run as it goes rather than once it is over. What a provider
    /// or a tool has finished saying happened, whatever becomes of the next
    /// one, so a run that dies keeps everything up to where it died.
    keep: ?Keeper = null,
};

/// Somewhere a run is kept, a piece at a time.
///
/// A piece is a turn: the 🧠 it continues, and what one model call or one
/// tool call added. The first opens with the ledger as it arrived, and each
/// one after with the name the last was kept under — so the pieces are a
/// chain, and expanding the last gives back the whole run.
pub const Keeper = struct {
    ctx: *anyopaque,
    /// Keep these records as a turn, and say what it is called.
    keep: *const fn (ctx: *anyopaque, piece: []const doc.Record) anyerror![]const u8,
};

/// How much of a run has been handed to its keeper, and what the next piece
/// continues.
const Progress = struct {
    keeper: ?Keeper,
    lead: []const doc.Record,
    kept: usize = 0,

    fn keep(self: *Progress, arena: Allocator, turn: []const doc.Record) !void {
        const k = self.keeper orelse return;
        if (turn.len == self.kept) return;
        var piece: std.ArrayList(doc.Record) = .empty;
        try piece.appendSlice(arena, self.lead);
        try piece.appendSlice(arena, turn[self.kept..]);
        const name = try k.keep(k.ctx, piece.items);
        const lead = try arena.alloc(doc.Record, 1);
        lead[0] = .{ .sigil = .agent, .value = name };
        self.lead = lead;
        self.kept = turn.len;
    }
};

/// Run whatever `ctx.in` holds, writing the reply as it arrives, and hand
/// back the turn: what arrived, settled, and everything the run added.
pub fn run(ctx: Ctx, opts: Options) ![]const doc.Record {
    const arena = ctx.arena;
    const io = ctx.io;
    const out = ctx.out;
    const mode = ctx.mode;

    var diag: doc.Diagnostic = .{};
    const given = try doc.parse(arena, ctx.in, &diag);

    const dirs = try config.discover(arena, io, ctx.env);
    const expanded = try ledger.expandRecords(
        arena,
        io,
        dirs,
        given,
        doc.detect(ctx.in) orelse .md,
    );

    // A mob's own scratch, made before any tool runs. Worked out once: it
    // belongs to the mob rather than to a call, which is what lets a tool
    // write a file and answer with a path the next call can open.
    const scratch = (try config.mobTmp(arena, io, dirs, expanded.origin)) orelse "";

    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, expanded.records);

    const def = try agent.project(arena, records.items);
    if (def.model.len == 0) return agent.Error.NoModel;
    if (def.provider.len == 0) return agent.Error.NoProvider;

    const providers = try config.providers(arena, io, ctx.env);
    const p = try provider.read(arena, providers, def.provider);
    const wire = codec.find(p.api) orelse return provider.Error.UnsupportedApi;

    // The command is found once, before anything is said, so a provider that
    // is not there fails before a turn is half made.
    const argv = try provider.resolve(arena, io, ctx.self, try config.coreDir(arena, ctx.env), p.cmd);
    const environ = try provider.environment(arena, p, ctx.env);

    // Only what a blockless 🧰 named, and the last definition of a name wins.
    const offered = try agent.offer(arena, def);

    // Shields come from the ledger alone, and stack rather than replace: a
    // second one can only tighten. What m8 ships with is underneath, so `jail`
    // means something before any agent is read, and an agent stands on it
    // rather than beside it.
    const shields = try (shield.Set{
        .defs = def.shields,
        .runners = def.runners,
        .active = def.active,
    }).over(arena, try shield.core(arena, ctx.io, ctx.env));

    // Lineage names what it continues, never a pointer to it: pointers move.
    const settled = try session.settleAll(arena, io, dirs, given);

    // Everything this run adds, in the order it happened.
    var turn: std.ArrayList(doc.Record) = .empty;
    var progress: Progress = .{ .keeper = opts.keep, .lead = settled };
    // Records normally get a blank line, so writing one has to know what came
    // before it. Some records belong together and are shown touching.
    var shown: Shown = .{};
    if (opts.echo_given) for (settled) |r| try show(arena, out, mode, &shown, r);
    // The rendered spelling is only ever written for a terminal, and a
    // terminal is the only reader that can watch a reply arrive.
    const live = mode == .m8;

    // A call and its answer are two records, so a ledger can arrive between
    // them. What it already asked for and never got is owed before anything
    // new is said, and nothing already answered is run a second time.
    for (try ledger.outstanding(arena, records.items)) |asked| {
        for (try answer(ctx, scratch, shields, offered, .{
            .id = ledger.callId(asked.value),
            .name = ledger.callName(asked.value),
            .arguments = try toolbox.parseArgs(arena, .md, asked.content orelse ""),
        })) |record| {
            try show(arena, out, mode, &shown, record);
            try records.append(arena, record);
            try turn.append(arena, record);
        }
        try out.flush();
        try progress.keep(arena, turn.items);
    }

    // No cap. A model that keeps calling tools is doing what it was given
    // tools for, and where to stop is the trust model's business — `ask`
    // already gates every call for anyone who wants that.
    while (true) {
        var reply: LiveReply = .{
            .out = out,
            .mode = mode,
            .live = live,
            .shown = &shown,
        };
        const request = try wire.encode(arena, records.items, .{
            .model = def.model,
            .params = def.params,
            .tools = offered,
            // A hint rather than a contract: a provider that cannot stream
            // answers whole, and the parser reads either.
            .stream = true,
        });
        const answered = try provider.run(
            arena,
            io,
            argv,
            environ,
            request,
            wire,
            reply.sink(),
            ctx.err,
        );
        try reply.finish();
        try out.flush();

        // Every record the model produced, in the order it produced them, so
        // a reply that thought before answering keeps its 💭 and stays
        // replayable. A 📲 is skipped here and appended below instead: a call
        // and the answer to it belong together in the ledger, and the loop
        // that runs the tool is what knows where that is.
        for (answered.records) |r| {
            if (r.sigil == .call) continue;
            try keep(arena, &records, r);
            try turn.append(arena, r);
        }
        try progress.keep(arena, turn.items);
        if (answered.calls.len == 0) break;
        const calls = answered.calls;

        for (calls) |c| {
            const asked: doc.Record = .{
                .sigil = .call,
                .value = try std.fmt.allocPrint(arena, "{s},{s}", .{ c.name, c.id }),
                // Kept in the spelling every file is written in; the reader
                // is handed whichever one they are being written.
                .content = try toolbox.renderArgs(arena, .md, c.arguments),
            };
            // Show the call before running it: on a terminal that is the only
            // sign anything is happening while a tool takes its time.
            try show(arena, out, mode, &shown, asked);
            try out.flush();
            try keep(arena, &records, asked);
            try turn.append(arena, asked);

            // The answer comes from the tool, not the model, and was already
            // checked against what a tool may say.
            for (try answer(ctx, scratch, shields, offered, c)) |record| {
                try show(arena, out, mode, &shown, record);
                try records.append(arena, record);
                try turn.append(arena, record);
            }
            try out.flush();
            // A call is kept with its answer and never ahead of it: a 📲
            // with nothing under it is owed, and one kept before its tool had
            // finished would be run a second time by whoever picked it up.
            try progress.keep(arena, turn.items);
        }
    }

    try out.flush();

    var whole: std.ArrayList(doc.Record) = .empty;
    try whole.appendSlice(arena, settled);
    try whole.appendSlice(arena, turn.items);
    return whole.items;
}

fn mergeEnv(arena: Allocator, vars: *std.ArrayList(api.EnvVar)) !void {
    var i: usize = 0;
    while (i < vars.items.len) : (i += 1) {
        var j = i + 1;
        while (j < vars.items.len) {
            if (std.mem.eql(u8, vars.items[i].key, vars.items[j].key)) {
                vars.items[i].value = try std.fmt.allocPrint(arena, "{s} {s}", .{
                    vars.items[i].value, vars.items[j].value,
                });
                _ = vars.orderedRemove(j);
            } else j += 1;
        }
    }
}

/// Run one call and hand back the records that answer it.
///
/// A tool writes what it says as it says it and then how it went, so an answer
/// is a 🧾 and a verdict rather than one record — and a tool that hands back
/// definitions as well is answering with those too. All of it is kept, which
/// is the ledger's rule and not this function's.
///
/// A failure is a 🚫 with the reason in it, never an error out of the run: the
/// model asked for something, and being told what went wrong is how it gets to
/// try something else.
fn answer(
    ctx: Ctx,
    scratch: []const u8,
    shields: shield.Set,
    tools: []const toolbox.Tool,
    c: codec.Call,
) ![]const doc.Record {
    const arena = ctx.arena;
    const io = ctx.io;

    const tool = for (tools) |t| {
        if (std.mem.eql(u8, t.name, c.name)) break t;
    } else return failure(arena, c.id, "no tool named '{s}'", .{c.name});

    if (tool.command == .none)
        return failure(
            arena,
            c.id,
            "'{s}' arrived without a command, so there is nothing to run. A " ++
                "tool read back from an api is an interface only: a model " ++
                "call never carried how the tool runs.",
            .{c.name},
        );

    const args = std.json.parseFromSliceLeaky(std.json.Value, arena, c.arguments, .{}) catch
        return failure(arena, c.id, "arguments were not JSON", .{});

    for (tool.properties) |prop| {
        if (!prop.required) continue;
        if (args != .object or args.object.get(prop.name) == null)
            return failure(arena, c.id, "'{s}' is required", .{prop.name});
    }

    // Two ways to say how a tool runs, and neither carries what the call
    // said: an argv is the words it was written as, a block is the script it
    // was written as, and the values reach both in the environment.
    const argv = switch (tool.command) {
        .none => unreachable,
        .argv => |a| a,
        .block => |b| shield.through(arena, shields.runners, b) catch |e|
            return failure(arena, c.id, "{s}", .{@errorName(e)}),
    };
    if (argv.len == 0) return failure(arena, c.id, "the command is empty", .{});

    // A tool's own 🛡 activate on top of whatever the agent already turned
    // on. Activation order is wrapping order, so the agent's are further out
    // and a tool can only ever add another layer inside them.
    var active: std.ArrayList(shield.Activation) = .empty;
    try active.appendSlice(arena, shields.active);
    try active.appendSlice(arena, tool.shields);
    const stood = shield.resolve(arena, shields.defs, active.items) catch |e|
        return failure(arena, c.id, "{s}", .{@errorName(e)});
    const wrapped = try shield.wrap(arena, stood.wrappers, argv, ctx.self);

    var env: std.ArrayList(api.EnvVar) = .empty;
    try env.appendSlice(arena, stood.env);
    // The mob's scratch, and a home that is not the person's for whatever
    // wants to drop a dotfile beside what it wrote. Both are made by m8, so a
    // tool neither creates one nor finds a trailing slash on it.
    if (scratch.len > 0) {
        try env.append(arena, .{ .key = "TMPDIR", .value = scratch });
        try env.append(arena, .{ .key = "HOME", .value = scratch });
    }
    // What the tool's own definition adds, which is neither the machine's nor
    // the call's and so is written down once rather than supplied every time.
    if (tool.env_vars.len > 0) {
        try env.appendSlice(arena, tool.env_vars);
    } else if (tool.env_var.len > 0) try env.append(arena, .{
        .key = tool.env_var,
        .value = try std.mem.join(arena, " ", tool.env_values),
    });
    try env.appendSlice(arena, try toolbox.callEnv(arena, args, c.arguments, c.id));
    try mergeEnv(arena, &env);

    var captured: std.Io.Writer.Allocating = .init(arena);
    var err_sink: std.Io.Writer.Allocating = .init(arena);
    var tty_storage: api.TtyFiles = undefined;

    const call = @import("command/call.zig");
    // A tool command answers in m8. It may use `m8 call` to turn an ordinary
    // program into that answer, or implement the protocol itself; the choice
    // belongs to its definition rather than to the harness running it.
    const status = call.execute(.{
        .arena = arena,
        .io = io,
        .mode = ctx.mode,
        .env = ctx.env,
        .call_id = c.id,
        .extra_env = env.items,
        .args = &.{},
        .in = "",
        .out = &captured.writer,
        .err = &err_sink.writer,
        .tty = api.openTty(io, &tty_storage),
    }, wrapped, .document) catch |e|
        return failure(arena, c.id, "{s}", .{@errorName(e)});

    var diag: doc.Diagnostic = .{};
    const records = doc.parse(arena, captured.written(), &diag) catch
        return failure(arena, c.id, "the tool did not answer in m8", .{});
    if (records.len == 0) return if (status == 0)
        failure(arena, c.id, "the tool wrote nothing", .{})
    else
        failure(arena, c.id, "the tool exited without an m8 failure", .{});
    if (!hasVerdict(records, c.id))
        return failure(arena, c.id, "the tool did not answer its call with a verdict", .{});

    // What a tool is allowed to have said. The reply side is closed always;
    // the definition side is closed by a 🛡 rather than from here, which is
    // why nothing in this function asks what was in force.
    for (records) |r| {
        if (!policy.fromTool(r.sigil))
            return failure(arena, c.id, "a tool may not hand back {s}", .{r.sigil.word()});
    }
    return records;
}

/// Put a candidate command line to an agent. Null when it answered `allow`,
/// otherwise whatever it said instead.
///
/// Its reply is never streamed and never reaches the receipt; it exists to
/// decide, not to be read. `m8 shield check AGENT -- CMD...`, which is what
/// 🛡check expands into.
///
/// Nothing is passed through to make the checker less capable than its caller.
/// It does not need to be: a shield is a wrapper, so the checker already runs
/// inside every shield that was standing outside it. What used to be a list
/// handed down is now the shape of the process tree.
pub fn check(ctx: Ctx, who: []const u8, argv: []const []const u8) !?[]const u8 {
    const dirs = try config.discover(ctx.arena, ctx.io, ctx.env);
    return agentCheck(ctx, dirs, who, argv);
}

fn agentCheck(
    ctx: Ctx,
    dirs: []const []const u8,
    who: []const u8,
    argv: []const []const u8,
) !?[]const u8 {
    const arena = ctx.arena;
    const l = try ledger.expand(arena, ctx.io, dirs, who);
    const def = try agent.project(arena, l.records);
    if (def.model.len == 0) return agent.Error.NoModel;
    if (def.provider.len == 0) return agent.Error.NoProvider;

    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, l.records);
    try records.append(arena, .{
        .sigil = .user,
        .content = try std.mem.join(arena, " ", argv),
    });

    // Its reply is never streamed and never reaches the receipt; it exists to
    // decide, not to be read.
    var quiet: Quiet = .{};
    const reply = try once(ctx, def, records.items, quiet.sink());
    const said = std.mem.trim(u8, try reply.said(ctx.arena), " \t\r\n");
    if (std.ascii.eqlIgnoreCase(said, "allow")) return null;
    return if (said.len > 0) said else "the checker said nothing";
}

/// One turn against a provider, with nowhere for the text to go as it lands.
fn once(
    ctx: Ctx,
    def: agent.Definition,
    records: []const doc.Record,
    sink: codec.Sink,
) !codec.Reply {
    const providers = try config.providers(ctx.arena, ctx.io, ctx.env);
    const p = try provider.read(ctx.arena, providers, def.provider);
    const wire = codec.find(p.api) orelse return provider.Error.UnsupportedApi;

    const request = try wire.encode(ctx.arena, records, .{
        .model = def.model,
        .params = def.params,
    });
    return provider.run(
        ctx.arena,
        ctx.io,
        try provider.resolve(ctx.arena, ctx.io, ctx.self, try config.coreDir(ctx.arena, ctx.env), p.cmd),
        try provider.environment(ctx.arena, p, ctx.env),
        request,
        wire,
        sink,
        ctx.err,
    );
}

/// A sink that keeps nothing. What it is handed has already been gathered by
/// the parser, which is what the reply carries back.
const Quiet = struct {
    fn sink(self: *Quiet) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(_: *anyopaque, _: sigil.Sigil, _: []const u8) anyerror!void {}
    fn writeFn(_: *anyopaque, _: []const u8) anyerror!void {}
    fn closeFn(_: *anyopaque) anyerror!void {}
};

/// The one record that says a call could not be run. A slice, because that is
/// what answering a call is now, and one that never got as far as the tool has
/// nothing to put above it.
fn failure(
    arena: Allocator,
    id: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) ![]const doc.Record {
    const one = try arena.alloc(doc.Record, 1);
    one[0] = .{
        .sigil = .failed,
        .value = id,
        .content = try std.fmt.allocPrint(arena, fmt, args),
    };
    return one;
}

/// Append a record that came from the model.
///
/// The reply side is closed by construction — a model's text becomes 🤖
/// content, which is quoted verbatim and so can never introduce a record. This
/// is the one seam where model output does become records, and checking here
/// keeps that a rule rather than a happy accident of the current data path.
fn keep(arena: Allocator, records: *std.ArrayList(doc.Record), r: doc.Record) !void {
    if (!policy.fromModel(r.sigil)) return error.ModelSaidTooMuch;
    try records.append(arena, r);
}

/// What was last put on the display, so the next record knows whether a
/// blank line separates it. Only the display: the parser does not need a
/// blank line between headers, and what is saved keeps them all.
const Shown = struct {
    written: bool = false,
    last: ?sigil.Sigil = null,

    fn begin(self: *Shown, out: *std.Io.Writer, s: sigil.Sigil) !void {
        if (self.written and !touches(self.last, s)) try out.writeByte('\n');
        self.written = true;
        self.last = s;
    }

    /// A reply's 💭 run together and so do its 🤖, and a call runs into its
    /// answer: 📲 then 🧾 then 🟢 or 🚫 is one exchange. Every other
    /// transition keeps the usual blank line.
    fn touches(last: ?sigil.Sigil, s: sigil.Sigil) bool {
        const l = last orelse return false;
        return switch (s) {
            .thought, .bot => l == s,
            .result, .ok, .failed => l == .call or l == .result,
            else => false,
        };
    }
};

/// Write a record, with the blank line that separates it from the last one.
fn show(
    arena: Allocator,
    out: *std.Io.Writer,
    mode: doc.Mode,
    shown: *Shown,
    r: doc.Record,
) !void {
    try shown.begin(out, r.sigil);
    try doc.write(out, mode, try ledger.rendered(arena, mode, r));
}

/// Bridges the provider's byte stream into the document, flushing each
/// fragment so the text appears as it is generated rather than at the end.
const LiveReply = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    live: bool,
    shown: *Shown,
    /// Opened on the first byte. A model that only calls a tool says nothing,
    /// and an empty 🤖 above the call would be a record of nothing.
    body: ?doc.ContentWriter = null,
    pending: ?sigil.Sigil = null,
    value: []const u8 = "",

    fn sink(self: *LiveReply) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    /// Remembered rather than written. A record with nothing in it is a record
    /// of nothing, and a codec is entitled to open one and find the model had
    /// no more to say — so the header waits for a byte, or a value, to justify
    /// it.
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        self.pending = s;
        self.value = value;
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (bytes.len == 0) return;
        // Kept aside is kept out of sight: a terminal shows the header alone,
        // and the turn still holds all of it.
        if (self.mode == .m8 and self.pending == .thought and std.mem.eql(u8, self.value, session.snip)) return;
        if (self.body == null) {
            const s = self.pending orelse .bot;
            try self.shown.begin(self.out, s);
            self.body = try doc.ContentWriter.begin(
                self.out,
                self.mode,
                s,
                self.value,
            );
        }
        try self.body.?.write(bytes);
        if (self.live) try self.out.flush();
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (self.body) |*b| {
            try b.finish();
        } else if (self.value.len > 0) {
            // Said on the header alone — how a reply stopped short.
            const s = self.pending orelse .bot;
            try self.shown.begin(self.out, s);
            try doc.write(self.out, self.mode, .{ .sigil = s, .value = self.value });
            if (self.live) try self.out.flush();
        }
        self.body = null;
        self.pending = null;
        self.value = "";
    }

    fn finish(self: *LiveReply) !void {
        if (self.body) |*b| try b.finish();
        self.body = null;
    }
};

/// A tool answers the call it was handed. A verdict for another call is still
/// a valid record, but it does not settle this one.
fn hasVerdict(records: []const doc.Record, id: []const u8) bool {
    for (records) |r| switch (r.sigil) {
        .ok, .failed => if (std.mem.eql(u8, r.value, id)) return true,
        else => {},
    };
    return false;
}

test "a run is kept a piece at a time, each naming the one before" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const Kept = struct {
        arena: Allocator,
        pieces: std.ArrayList([]const doc.Record) = .empty,

        fn keep(ctx: *anyopaque, piece: []const doc.Record) anyerror![]const u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.pieces.append(self.arena, piece);
            return std.fmt.allocPrint(self.arena, "+/t{d}", .{self.pieces.items.len});
        }
    };
    var kept: Kept = .{ .arena = arena };

    const given = [_]doc.Record{
        .{ .sigil = .agent, .value = "mathy" },
        .{ .sigil = .user, .content = "hi" },
    };
    var progress: Progress = .{ .keeper = .{ .ctx = &kept, .keep = Kept.keep }, .lead = &given };
    var turn: std.ArrayList(doc.Record) = .empty;

    // Nothing added is nothing to keep.
    try progress.keep(arena, turn.items);
    try std.testing.expectEqual(@as(usize, 0), kept.pieces.items.len);

    try turn.append(arena, .{ .sigil = .bot, .content = "looking" });
    try progress.keep(arena, turn.items);
    try turn.append(arena, .{ .sigil = .call, .value = "read,c1" });
    try turn.append(arena, .{ .sigil = .ok, .value = "c1" });
    try progress.keep(arena, turn.items);
    try progress.keep(arena, turn.items);

    // The first piece opens with the ledger as it arrived, and the second
    // with the turn the first became and only what was added since.
    const pieces = kept.pieces.items;
    try std.testing.expectEqual(@as(usize, 2), pieces.len);
    try std.testing.expectEqual(@as(usize, 3), pieces[0].len);
    try std.testing.expectEqualStrings("mathy", pieces[0][0].value);
    try std.testing.expectEqual(sigil.Sigil.bot, pieces[0][2].sigil);
    try std.testing.expectEqual(@as(usize, 3), pieces[1].len);
    try std.testing.expectEqualStrings("+/t1", pieces[1][0].value);
    try std.testing.expectEqual(sigil.Sigil.call, pieces[1][1].sigil);
    try std.testing.expectEqual(sigil.Sigil.ok, pieces[1][2].sigil);
}

test "only a verdict naming the call settles it" {
    const said = [_]doc.Record{
        .{ .sigil = .result, .value = "c1", .content = "hi" },
        .{ .sigil = .ok, .value = "c1" },
    };
    try std.testing.expect(hasVerdict(&said, "c1"));
    try std.testing.expect(!hasVerdict(&said, "c2"));
    // A 🧾 alone is a tool that spoke and never said how it went.
    try std.testing.expect(!hasVerdict(said[0..1], "c1"));
    try std.testing.expect(hasVerdict(&.{.{ .sigil = .failed, .value = "c1", .content = "no" }}, "c1"));
}

test "live reply separates changes of sigil" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var out: std.Io.Writer.Allocating = .init(arena);
    var shown: Shown = .{};
    var reply: LiveReply = .{
        .out = &out.writer,
        .mode = .md,
        .live = false,
        .shown = &shown,
    };
    const sink = reply.sink();

    try sink.record(.thought, "", "one");
    try sink.record(.thought, "", "two");
    try sink.record(.bot, "", "answer");
    try sink.record(.bot, "", "again");
    try sink.record(.thought, "", "three");

    try std.testing.expectEqualStrings(
        "#### :thought_balloon:\n> one\n#### :thought_balloon:\n> two\n\n" ++
            "#### :robot:\n> answer\n#### :robot:\n> again\n\n" ++
            "#### :thought_balloon:\n> three\n",
        out.written(),
    );
}

test "a call runs into its answer" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var out: std.Io.Writer.Allocating = .init(arena);
    var shown: Shown = .{};
    for ([_]doc.Record{
        .{ .sigil = .bot, .content = "looking" },
        .{ .sigil = .call, .value = "read,c1", .content = "* path x" },
        .{ .sigil = .result, .value = "c1", .content = "one" },
        .{ .sigil = .result, .value = "c1", .content = "two" },
        .{ .sigil = .ok, .value = "c1" },
        .{ .sigil = .call, .value = "read,c2", .content = "* path y" },
        .{ .sigil = .failed, .value = "c2", .content = "no" },
        .{ .sigil = .bot, .content = "done" },
    }) |r| try show(arena, &out.writer, .md, &shown, r);

    try std.testing.expectEqualStrings(
        "#### :robot:\n> looking\n\n" ++
            "#### :calling:read,c1\n> * path x\n" ++
            "#### :receipt:c1\n> one\n#### :receipt:c1\n> two\n#### :green_circle:c1\n\n" ++
            "#### :calling:read,c2\n> * path y\n#### :no_entry_sign:c2\n> no\n\n" ++
            "#### :robot:\n> done\n",
        out.written(),
    );
}
