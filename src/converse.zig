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
const highlight = @import("m8/highlight.zig");
const api = @import("api.zig");
const Ctx = api.Ctx;
const posix = std.posix;

/// Ctrl-C reaches a run and the tool it is running together, as one process
/// group. The tool stops however it stops; the run outlives it long enough
/// to write down how, close what it will not now run, and keep all of it.
var interrupted = std.atomic.Value(bool).init(false);

fn onInterrupt(sig: posix.SIG) callconv(.c) void {
    // A second one is someone who meant it: stop where it stands.
    if (interrupted.swap(true, .monotonic)) {
        posix.sigaction(sig, &.{ .handler = .{ .handler = posix.SIG.DFL }, .mask = posix.sigemptyset(), .flags = 0 }, null);
        posix.raise(sig) catch {};
    }
}

const stopped = "Not run: the run was interrupted.";
const died = "Interrupted: the run stopped while this was running, so it may or may not have finished.";

pub const Options = struct {
    /// Write the ledger that arrived ahead of what the run adds, so what goes
    /// out is the whole turn. What `send` does; the `@` prompt shows only
    /// what the run adds.
    echo_given: bool = false,
    /// Keep the run as it goes rather than once it is over. What a provider
    /// or a tool has finished saying happened, whatever becomes of the next
    /// one, so a run that dies keeps everything up to where it died.
    keep: ?Keeper = null,
    /// Say on stderr what the run is doing: a line as a thought opens, and
    /// one as each tool is called.
    /// How much is said on stderr about what the run is doing: nothing, a
    /// line as each thing happens, or more. Whatever the run starts is told
    /// the same, as `M8_VERBOSITY`, and a run started with that set says as
    /// much without being asked.
    verbosity: u8 = 0,
};

/// Somewhere a run is kept, a piece at a time.
///
/// A piece is a turn: the 🧠 it continues, and what one model call or one
/// tool call added. The first opens with the ledger as it arrived, and each
/// one after with the name the last was kept under — so the pieces are a
/// chain, and expanding the last gives back the whole run.
pub const Keeper = struct {
    ctx: *anyopaque,
    /// The folder its turns go in, which is where their snips go too.
    home: []const u8,
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
pub fn run(handed: Ctx, opts: Options) ![]const doc.Record {
    const arena = handed.arena;
    var ctx = handed;
    ctx.verbosity = @max(handed.verbosity, opts.verbosity);
    ctx.env = try unanswered(arena, handed.env);
    const level = ctx.verbosity;
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

    // The commands are found once, before anything is said, so a provider
    // that is not there fails before a turn is half made.
    const stages = try provider.stages(arena, io, ctx.self, try config.coreDirs(arena, io, ctx.env), p);
    const environ = try api.childEnvironment(arena, ctx, &.{});
    try provider.addEnvironment(arena, p, environ);

    // Only what a blockless 🧰 named, and the last definition of a name wins.
    const offered = try agent.offer(arena, def);

    // Shields come from the ledger alone, and stack rather than replace: a
    // second one can only tighten. m8 defines none, so a name means whatever
    // the agent or something it includes says it does.
    const shields: shield.Set = .{
        .defs = def.shields,
        .runners = def.runners,
        .active = def.active,
    };

    // Lineage names what it continues, never a pointer to it: pointers move.
    const settled = try session.settleAll(arena, io, dirs, given);

    // Everything this run adds, in the order it happened.
    var turn: std.ArrayList(doc.Record) = .empty;
    var progress: Progress = .{ .keeper = opts.keep, .lead = settled };
    // Records normally get a blank line, so writing one has to know what came
    // before it. Some records belong together and are shown touching. A
    // terminal is shown every 📜 and 🤖 highlighted as markdown.
    var shown: Shown = .{ .look = if (mode == .m8) .{ .width = highlight.terminalWidth(ctx.env) } else null };
    var status: Status = .{ .err = if (level > 0 and !opts.echo_given) ctx.err else null };
    if (opts.echo_given) for (settled) |r| try show(arena, out, mode, &shown, r);
    // The rendered spelling is only ever written for a terminal, and a
    // terminal is the only reader that can watch a reply arrive.
    const live = mode == .m8;

    for ([_]posix.SIG{ .INT, .TERM }) |sig|
        posix.sigaction(sig, &.{ .handler = .{ .handler = onInterrupt }, .mask = posix.sigemptyset(), .flags = posix.SA.RESTART }, null);

    // A call and its answer are two records, so a ledger can arrive between
    // them. What it already asked for and never got is owed before anything
    // new is said, and nothing already answered is run a second time.
    //
    // A call that asked the person something is one of them: it said nothing
    // but its question, so it is run again with whatever they answered.
    talking: {
        const owed = try ledger.outstanding(arena, records.items);
        // Only a question leaves a call owed, and it writes down the call that
        // asked and those made alongside it ahead of the ❓. One with no ❓
        // after it was running when its run stopped. How far it got nobody
        // can say, so it is closed rather than run a second time, and what to
        // do about it is the model's.
        var unasked = records.items.len;
        while (unasked > 0 and records.items[unasked - 1].sigil != .question) unasked -= 1;
        for (owed, 0..) |asked, n| {
            const cut = for (records.items[unasked..]) |r| {
                if (r.sigil == .call and std.mem.eql(u8, ledger.callId(r.value), ledger.callId(asked.value))) break true;
            } else false;
            if (cut or interrupted.load(.monotonic)) {
                const closed = (try failure(arena, ledger.callId(asked.value), "{s}", .{if (cut) died else stopped}))[0];
                try show(arena, out, mode, &shown, closed);
                try records.append(arena, closed);
                try turn.append(arena, closed);
                try progress.keep(arena, turn.items);
                continue;
            }
            const c: codec.Call = .{
                .id = ledger.callId(asked.value),
                .name = ledger.callName(asked.value),
                .arguments = try toolbox.parseArgs(arena, .md, asked.content orelse ""),
            };
            const said = try ledger.exclamations(arena, records.items, c.id);
            try status.call(arena, c);
            var how: Went = .settled;
            for (try answer(ctx, scratch, shields, offered, def.tools, c, said, &how)) |record| {
                try show(arena, out, mode, &shown, record);
                try records.append(arena, record);
                try turn.append(arena, record);
            }
            // The person said no. Calls made together lean on each other, so
            // none of the rest is run: each is closed saying why, and it is
            // the person rather than the model who is waited on next.
            if (how == .refused) for (owed[n + 1 ..]) |later| {
                const closed = (try failure(arena, ledger.callId(later.value), "{s}", .{dropped}))[0];
                try show(arena, out, mode, &shown, closed);
                try records.append(arena, closed);
                try turn.append(arena, closed);
            };
            try out.flush();
            try progress.keep(arena, turn.items);
            if (how != .settled) break :talking;
        }

        // No cap. A model that keeps calling tools is doing what it was given
        // tools for, and where to stop is the trust model's business — `ask`
        // already gates every call for anyone who wants that.
        while (true) {
            if (interrupted.load(.monotonic)) return error.Interrupted;
            var reply: LiveReply = .{
                .arena = arena,
                .io = io,
                .dirs = dirs,
                .snips = if (opts.keep) |k| k.home else null,
                .said = .{ .arena = arena },
                .out = out,
                .mode = mode,
                .live = live,
                .shown = &shown,
                .status = &status,
            };
            // The ledger as it stands, in the language itself. What a model
            // is sent of it is the provider's to make.
            const request = try codec.m8.codec.encode(arena, records.items, .{});
            const answered = try provider.run(
                arena,
                io,
                stages,
                environ,
                request,
                reply.sink(),
                ctx.err,
            );
            try reply.finish();
            try out.flush();

            // A provider that said only thoughts, or said nothing at all, has
            // still answered: keep a visible value so the transcript and
            // callers do not mistake the invocation for one that never ran.
            // Tool calls are different — their answer is the tool's records,
            // so a tool-only response stays exactly that.
            var no_response = answered.calls.len == 0;
            for (reply.said.records.items) |r| if (r.sigil == .bot) {
                no_response = false;
                break;
            };
            try records.appendSlice(arena, reply.said.records.items);
            try turn.appendSlice(arena, reply.kept.items);
            if (no_response) {
                const record: doc.Record = .{ .sigil = .bot, .value = "(no response)" };
                try show(arena, out, mode, &shown, record);
                try records.append(arena, record);
                try turn.append(arena, record);
            }
            try progress.keep(arena, turn.items);
            if (answered.calls.len == 0) break;
            const calls = answered.calls;

            for (calls, 0..) |c, n| {
                const asked = try called(arena, c);
                // Show the call before running it: on a terminal that is the only
                // sign anything is happening while a tool takes its time. And
                // keep it: a call is the truth the moment it is made, and one
                // left with nothing under it by a run that died is closed as
                // interrupted by the next, never run again.
                try show(arena, out, mode, &shown, asked);
                try out.flush();
                try status.call(arena, c);
                try records.append(arena, asked);
                try turn.append(arena, asked);

                // Made, and never started.
                if (interrupted.load(.monotonic)) {
                    const closed = (try failure(arena, c.id, "{s}", .{stopped}))[0];
                    try show(arena, out, mode, &shown, closed);
                    try records.append(arena, closed);
                    try turn.append(arena, closed);
                    try progress.keep(arena, turn.items);
                    continue;
                }
                try progress.keep(arena, turn.items);

                // The answer comes from the tool, not the model, and was already
                // checked against what a tool may say.
                var how: Went = .settled;
                const answers = try answer(ctx, scratch, shields, offered, def.tools, c, &.{}, &how);
                // A question stops the run, so the calls behind it are written
                // down first. They are owed, and whoever picks this up with the
                // person's answer runs them once the one that asked is through.
                if (how == .asked) for (calls[n + 1 ..]) |later| {
                    const waits = try called(arena, later);
                    try show(arena, out, mode, &shown, waits);
                    try records.append(arena, waits);
                    try turn.append(arena, waits);
                };
                for (answers) |record| {
                    try show(arena, out, mode, &shown, record);
                    try records.append(arena, record);
                    try turn.append(arena, record);
                }
                try out.flush();
                try progress.keep(arena, turn.items);
                if (how == .asked) break :talking;
            }
        }
    }

    try out.flush();

    var whole: std.ArrayList(doc.Record) = .empty;
    try whole.appendSlice(arena, settled);
    try whole.appendSlice(arena, turn.items);
    return whole.items;
}

/// The 📲 a call is written down as.
fn called(arena: Allocator, c: codec.Call) !doc.Record {
    return .{
        .sigil = .call,
        .value = try std.fmt.allocPrint(arena, "{s},{s}", .{ c.name, c.id }),
        // Kept in the spelling every file is written in; the reader is handed
        // whichever one they are being written.
        .content = try toolbox.renderArgs(arena, .md, c.arguments),
    };
}

/// What a call is closed with when one made alongside it was refused.
const dropped = "Not run: the person refused another call made alongside this one.";

/// How a call went, for whoever decides what happens next.
const Went = enum {
    /// It answered, well or badly, and the model is told.
    settled,
    /// It asked the person something, and the run stops on the question.
    asked,
    /// It had asked, was answered, and gave up the same way without asking
    /// again. The person is who it is waiting on, not the model.
    refused,
};

/// What the person answered, as the variables a call reads it from.
///
/// Made from the ledger each time, so the ledger is the only place an answer
/// lives. The tool's own are numbered and nothing more, and a shield's have
/// its name after, each counted from one — so everything a call stands
/// inside is handed the same environment and finds only what was said to it.
fn exclaimed(arena: Allocator, said: []const ledger.Answer) ![]const api.EnvVar {
    var out: std.ArrayList(api.EnvVar) = .empty;
    for (said, 0..) |s, at| {
        if (!asks(s.who)) continue;
        var n: usize = 1;
        for (said[0..at]) |earlier| {
            if (std.mem.eql(u8, earlier.who, s.who)) n += 1;
        }
        try out.append(arena, .{
            .key = if (std.mem.eql(u8, s.who, api.asks_tool))
                try std.fmt.allocPrint(arena, "{s}{d}", .{ api.exclamation, n })
            else
                try std.fmt.allocPrint(arena, "{s}{d}_{s}", .{ api.exclamation, n, s.who[api.asks_shield.len..] }),
            .value = s.text,
        });
    }
    return out.items;
}

/// The environment without what somebody was answered further up. An agent
/// run by a tool counts its shields from one again, and would otherwise take
/// what was said to that tool's as said to its own.
fn unanswered(arena: Allocator, env: *const std.process.Environ.Map) !*const std.process.Environ.Map {
    var probe = env.iterator();
    while (probe.next()) |e| {
        if (!std.mem.startsWith(u8, e.key_ptr.*, api.exclamation)) continue;

        const own = try arena.create(std.process.Environ.Map);
        own.* = .init(arena);
        var it = env.iterator();
        while (it.next()) |entry| {
            if (!std.mem.startsWith(u8, entry.key_ptr.*, api.exclamation))
                try own.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        return own;
    }
    return env;
}

/// Whether a name is one a question can come from: the tool, or a shield
/// under a name that is safe to be a variable's.
fn asks(who: []const u8) bool {
    if (std.mem.eql(u8, who, api.asks_tool)) return true;
    if (!std.mem.startsWith(u8, who, api.asks_shield) or who.len == api.asks_shield.len) return false;
    for (who) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    return true;
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
    /// Every tool with a definition, offered or not, to say which is missing.
    defined: []const toolbox.Tool,
    c: codec.Call,
    /// What the person has answered this call's questions with so far.
    said: []const ledger.Answer,
    how: *Went,
) ![]const doc.Record {
    const arena = ctx.arena;
    const io = ctx.io;

    const tool = for (tools) |t| {
        if (std.mem.eql(u8, t.name, c.name)) break t;
    } else {
        for (defined) |t| if (std.mem.eql(u8, t.name, c.name))
            return failure(arena, c.id, "tool '{s}' is defined but not offered.", .{c.name});
        return failure(arena, c.id, "no tool named '{s}'", .{c.name});
    };

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
    // The mob's scratch. It is made by m8, so a tool neither creates one nor
    // finds a trailing slash on it.
    if (scratch.len > 0) try env.append(arena, .{ .key = "TMPDIR", .value = scratch });
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

    try env.appendSlice(arena, try exclaimed(arena, said));

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
        .self = ctx.self,
        .verbosity = ctx.verbosity,
        .call_id = c.id,
        .extra_env = env.items,
        .args = &.{},
        .in = "",
        .out = &captured.writer,
        .err = &err_sink.writer,
        .tty = api.openTty(io, &tty_storage),
    }, wrapped, .document) catch |e|
        return failure(arena, c.id, "{s}", .{@errorName(e)});

    // A question, which is the whole of what the tool said. The call stays
    // unanswered: it is run again once the person has said something.
    const complaint = std.mem.trim(u8, err_sink.written(), " \t\r\n");
    if (status == api.ask_exit and captured.written().len == 0 and
        std.mem.startsWith(u8, complaint, api.ask_lead))
    asked: {
        // Who is asking comes first, so the answer is named for them.
        const after = complaint[api.ask_lead.len..];
        const end = std.mem.indexOfScalar(u8, after, ':') orelse break :asked;
        if (!asks(after[0..end])) break :asked;
        how.* = .asked;
        const one = try arena.alloc(doc.Record, 1);
        one[0] = .{
            .sigil = .question,
            .value = try std.fmt.allocPrint(arena, "{s},{s}", .{ after[0..end], c.id }),
            .content = std.mem.trim(u8, after[end + 1 ..], " \t\r\n"),
        };
        return one;
    }
    if (status == api.ask_exit and said.len > 0) how.* = .refused;

    var diag: doc.Diagnostic = .{};
    const records = doc.parse(arena, captured.written(), &diag) catch
        return failure(arena, c.id, "the tool did not answer in m8", .{});
    // Stopped by Ctrl-C before it could say how it went, which is then all
    // there is to say. One that finished first keeps its own answer.
    if (interrupted.load(.monotonic) and !hasVerdict(records, c.id))
        return failure(arena, c.id, "Interrupted while it was running.", .{});
    if (records.len == 0) return if (status == 0)
        failure(arena, c.id, "the tool wrote nothing", .{})
    else if (complaint.len > 0)
        failure(arena, c.id, "Failed with exit code {d}: {s}", .{ status, complaint })
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

/// What was last put on the display, so the next record knows whether a
/// blank line separates it. Only the display: the parser does not need a
/// blank line between headers, and what is saved keeps them all.
const Shown = struct {
    written: bool = false,
    last: ?sigil.Sigil = null,
    /// How markdown is highlighted, for a terminal.
    look: ?doc.Look = null,

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
            .agent => l == .thought,
            .result, .scroll, .link, .ok, .failed => l == .call or l == .result or l == .scroll or l == .link,
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
    try doc.writeLooking(out, mode, shown.look, try ledger.rendered(arena, mode, r));
}

/// What a run says it is doing, for whoever is watching it work rather than
/// reading what it says: one line on stderr as a thought opens, and one as a
/// tool is called. Each stays the last thing said until the next.
///
/// A thought is its opening and no more, said once: when a line's worth of
/// it has arrived, or when it ends short of that. So nothing of a thought is
/// kept past what fits on a line.
const Status = struct {
    err: ?*std.Io.Writer = null,
    line: [max]u8 = undefined,
    len: usize = 0,
    /// A thought is arriving and its line has room left.
    open: bool = false,

    const max = 120;

    fn thinking(self: *Status, yes: bool, value: []const u8) void {
        self.len = 0;
        self.open = yes and self.err != null;
        if (self.open) self.add(value);
        if (self.open) self.add(" ");
    }

    fn thought(self: *Status, bytes: []const u8) !void {
        if (!self.open) return;
        self.add(bytes);
        // Full, so it is said now and cut, with the rest still to come.
        if (!self.open) try self.say("\u{1F4AD} ", true);
    }

    /// The thought is over. One that never filled the line is said whole.
    fn thoughtOver(self: *Status) !void {
        if (!self.open) return;
        self.open = false;
        if (std.mem.trim(u8, self.line[0..self.len], " ").len > 0) try self.say("\u{1F4AD} ", false);
    }

    /// Text as one line: whatever space it has is one space, and none leads.
    fn add(self: *Status, bytes: []const u8) void {
        for (bytes) |b| {
            const space = b == ' ' or b == '\n' or b == '\r' or b == '\t';
            if (space and (self.len == 0 or self.line[self.len - 1] == ' ')) continue;
            if (self.len == max) {
                self.open = false;
                return;
            }
            self.line[self.len] = if (space) ' ' else b;
            self.len += 1;
        }
    }

    fn call(self: *Status, arena: Allocator, c: codec.Call) !void {
        if (self.err == null) return;
        self.open = false;
        var w: std.Io.Writer = .fixed(&self.line);
        // Past the end of the line is cut, which a full writer says by failing.
        const cut = if (named(arena, &w, c)) false else |_| true;
        self.len = w.end;
        try self.say("\u{1F4F2}", cut);
    }

    /// `edit(path=a.md,old=…`: the name, and each argument as it was given.
    fn named(arena: Allocator, w: *std.Io.Writer, c: codec.Call) !void {
        try w.print("{s}(", .{c.name});
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, c.arguments, .{}) catch null;
        if (parsed != null and parsed.? == .object) {
            var it = parsed.?.object.iterator();
            var first = true;
            while (it.next()) |e| {
                if (!first) try w.writeByte(',');
                first = false;
                try w.print("{s}=", .{e.key_ptr.*});
                switch (e.value_ptr.*) {
                    .string => |s| for (s) |b| try w.writeByte(if (b == '\n' or b == '\r' or b == '\t') ' ' else b),
                    else => |v| try std.json.Stringify.value(v, .{}, w),
                }
            }
        } else try w.writeAll(c.arguments);
        try w.writeByte(')');
    }

    fn say(self: *Status, lead: []const u8, cut: bool) !void {
        const err = self.err orelse return;
        // A character that has only half arrived is not said yet.
        var end = self.len;
        while (end > 0 and self.line[end - 1] & 0xc0 == 0x80) end -= 1;
        if (end > 0 and self.line[end - 1] >= 0xc0) {
            const want = std.unicode.utf8ByteSequenceLength(self.line[end - 1]) catch 1;
            end = if (end - 1 + want <= self.len) end - 1 + want else end - 1;
        } else end = self.len;
        try err.print("{s}{s}{s}\n", .{ lead, std.mem.trimEnd(u8, self.line[0..end], " "), if (cut) "\u{2026}" else "" });
        try err.flush();
    }
};

/// Bridges the provider's byte stream into the document, flushing each
/// fragment so the text appears as it is generated rather than at the end.
const LiveReply = struct {
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8 = &.{},
    /// Where a `💭snip` is kept as it arrives, or null to hand it on whole.
    snips: ?[]const u8 = null,
    out: *std.Io.Writer,
    mode: doc.Mode,
    live: bool,
    shown: *Shown,
    status: *Status,
    /// Opened on the first byte. A model that only calls a tool says nothing,
    /// and an empty 🤖 above the call would be a record of nothing.
    body: ?doc.ContentWriter = null,
    pending: ?sigil.Sigil = null,
    /// What the model said, for the ledger still running.
    said: codec.Gather,
    /// The same, as the turn keeps it: a snip is named rather than held.
    kept: std.ArrayList(doc.Record) = .empty,

    fn sink(self: *LiveReply) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    /// Remembered rather than written. A record with nothing in it is a record
    /// of nothing, and a codec is entitled to open one and find the model had
    /// no more to say — so the header waits for a byte, or a value, to justify
    /// it.
    ///
    /// The reply side is closed by construction — a model's text becomes 🤖
    /// content, which is quoted verbatim and so can never introduce a record.
    /// This is the one seam where model output does become records, and
    /// checking here keeps that a rule rather than a happy accident of the
    /// current data path.
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (!policy.fromModel(s)) return error.ModelSaidTooMuch;
        self.pending = s;
        self.said.open(s, value);
        // A thought kept aside follows the summary of it, and would take the
        // summary's place: the line is for the one a person would read.
        self.status.thinking(s == .thought and !std.mem.eql(u8, value, session.snip), value);
    }

    fn snipped(self: *const LiveReply) bool {
        return self.pending == .thought and
            self.said.text.items.len > 0 and
            std.mem.eql(u8, self.said.value, session.snip);
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (bytes.len == 0) return;
        try self.said.write(bytes);
        try self.status.thought(bytes);
        // Kept aside is kept out of sight: bound for its snip when the run is
        // kept, and otherwise hidden from a terminal alone.
        if (self.snipped() and (self.snips != null or self.mode == .m8)) return;
        if (self.body == null) {
            const s = self.pending orelse .bot;
            try self.shown.begin(self.out, s);
            self.body = try doc.ContentWriter.beginLooking(
                self.out,
                self.mode,
                self.shown.look,
                s,
                self.said.value,
            );
        }
        try self.body.?.write(bytes);
        if (self.live) try self.out.flush();
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        try self.status.thoughtOver();
        if (try self.said.close()) |r| {
            const k: doc.Record = if (self.snips != null and session.isSnip(r)) .{
                .sigil = .agent,
                .value = try session.keepSnip(self.arena, self.io, self.dirs, self.snips.?, r.content.?),
            } else r;
            try self.kept.append(self.arena, k);
            if (self.body) |*b| {
                try b.finish();
            } else if (k.value.len > 0) {
                // Said on the header alone — how a reply stopped short, or
                // where a snip went.
                try self.shown.begin(self.out, k.sigil);
                try doc.write(self.out, self.mode, .{ .sigil = k.sigil, .value = k.value });
                if (self.live) try self.out.flush();
            }
        }
        self.body = null;
        self.pending = null;
    }

    /// A codec that stopped without closing its record still said it.
    fn finish(self: *LiveReply) !void {
        if (self.pending != null) try closeFn(self);
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
    var progress: Progress = .{ .keeper = .{ .ctx = &kept, .home = "", .keep = Kept.keep }, .lead = &given };
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
    var status: Status = .{};
    var reply: LiveReply = .{
        .arena = arena,
        .io = undefined,
        .said = .{ .arena = arena },
        .out = &out.writer,
        .mode = .md,
        .live = false,
        .shown = &shown,
        .status = &status,
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

test "a run says what it is doing, a line at a time" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var out: std.Io.Writer.Allocating = .init(arena);
    var err: std.Io.Writer.Allocating = .init(arena);
    var shown: Shown = .{};
    var status: Status = .{ .err = &err.writer };
    var reply: LiveReply = .{
        .arena = arena,
        .io = undefined,
        .said = .{ .arena = arena },
        .out = &out.writer,
        .mode = .md,
        .live = false,
        .shown = &shown,
        .status = &status,
    };
    const sink = reply.sink();

    // A short thought is said once it is over, on one line.
    try sink.begin(.thought, "");
    try sink.text("\n  Looking at\nthe caf\xc3");
    try std.testing.expectEqualStrings("", err.written());
    try sink.text("\xa9 menu");
    try sink.end();
    try std.testing.expectEqualStrings("\u{1F4AD} Looking at the caf\u{e9} menu\n", err.written());

    // A long one is said as soon as the line is full, cut, and left alone.
    err.clearRetainingCapacity();
    try sink.begin(.thought, "plan");
    try sink.text("x" ** 200);
    const full = "\u{1F4AD} plan " ++ "x" ** (Status.max - 5) ++ "\u{2026}\n";
    try std.testing.expectEqualStrings(full, err.written());
    try sink.text("more");
    try sink.end();
    try std.testing.expectEqualStrings(full, err.written());

    // What is kept aside and what is answered are not what it is doing.
    err.clearRetainingCapacity();
    try sink.record(.thought, session.snip, "the whole of it");
    try sink.record(.bot, "", "answer");
    try std.testing.expectEqualStrings("", err.written());

    // A call is its name and what it was given, cut where the line ends.
    try status.call(arena, .{ .id = "c1", .name = "edit", .arguments = "{\"path\":\"a.md\",\"n\":2,\"old\":\"one\\ntwo\"}" });
    try std.testing.expectEqualStrings("\u{1F4F2}edit(path=a.md,n=2,old=one two)\n", err.written());
    err.clearRetainingCapacity();
    try status.call(arena, .{ .id = "c2", .name = "write", .arguments = "{\"text\":\"" ++ "y" ** 300 ++ "\"}" });
    try std.testing.expectEqualStrings("\u{1F4F2}write(text=" ++ "y" ** (Status.max - 11) ++ "\u{2026}\n", err.written());

    // Unasked, it says nothing.
    var quiet: Status = .{};
    try quiet.call(arena, .{ .id = "c3", .name = "edit", .arguments = "{}" });
    quiet.thinking(true, "");
    try quiet.thought("hm");
    try quiet.thoughtOver();
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
            "#### :receipt:c1\n>     one\n#### :receipt:c1\n>     two\n#### :green_circle:c1\n\n" ++
            "#### :calling:read,c2\n> * path y\n#### :no_entry_sign:c2\n> no\n\n" ++
            "#### :robot:\n> done\n",
        out.written(),
    );
}

test "what the person answered is named for a call, and for what it stands inside" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const env = try exclaimed(arena, &.{
        .{ .who = "shield_ask", .text = "yes" },
        .{ .who = "tool", .text = "John" },
        .{ .who = "tool", .text = "Leeds" },
        // Nobody a question can come from, so nothing to call it.
        .{ .who = "shield_a=b", .text = "no" },
        .{ .who = "shield-ask-1", .text = "no" },
        .{ .who = "", .text = "no" },
    });
    // Each is counted from one, whoever else was answered in between.
    try std.testing.expectEqual(@as(usize, 3), env.len);
    try std.testing.expectEqualStrings("M8_EXCLAMATION_1_ask", env[0].key);
    try std.testing.expectEqualStrings("yes", env[0].value);
    try std.testing.expectEqualStrings("M8_EXCLAMATION_1", env[1].key);
    try std.testing.expectEqualStrings("John", env[1].value);
    try std.testing.expectEqualStrings("M8_EXCLAMATION_2", env[2].key);
    try std.testing.expectEqualStrings("Leeds", env[2].value);
    try std.testing.expect(!asks("shield_"));
    try std.testing.expect(!asks("ask"));
}

test "a run starts with nothing answered, whatever it was handed" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var env: std.process.Environ.Map = .init(arena);
    try env.put("M8_EXCLAMATION_1", "John");
    try env.put("M8_EXCLAMATION_1_ask", "yes");
    try env.put("PATH", "/bin");
    const own = try unanswered(arena, &env);
    try std.testing.expectEqual(@as(usize, 1), own.count());
    try std.testing.expectEqualStrings("/bin", own.get("PATH").?);
}
