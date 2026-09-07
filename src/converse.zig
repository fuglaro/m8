//! Running a ledger: saying what it says, and doing what it asks for.
//!
//! The ledger is the conversation. A reply is appended to it, a 📲 is
//! appended to it, and the answer to that 📲 is appended to it — so what goes
//! back to the model next time round is the same records a person would read.
//! Nothing is assembled on the side and nothing is thrown away.
//!
//! What is saved is the ledger as it arrived, still naming what it continues,
//! plus whatever this run added. Expanding that gives back exactly what ran.

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

/// Run whatever `ctx.in` holds.
///
/// `override` names a provider to send to instead of the one the ledger
/// names, and is empty when it names none. Only the provider, because only
/// the provider is ever missing: a ledger that came back off a wire knows its
/// model and everything to ask it for, and never whose model it was.
pub fn run(ctx: Ctx, override: []const u8) !void {
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

    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, expanded.records);

    var def = try agent.project(arena, records.items);
    if (override.len > 0) def.provider = override;
    if (def.model.len == 0) return agent.Error.NoModel;
    if (def.provider.len == 0) return agent.Error.NoProvider;

    const providers = try config.providers(arena, io, ctx.env);
    const p = try provider.read(arena, providers, def.provider);
    const wire = codec.find(p.api) orelse return provider.Error.UnsupportedApi;

    // The command is found once, before anything is said, so a provider that
    // is not there fails before a turn is half made.
    const argv = try provider.resolve(arena, io, ctx.self, try config.coreDir(arena, ctx.env), p.cmd);
    const environ = try provider.environment(arena, p, ctx.env);

    // Only what 🔓 named, and the last definition of a name wins.
    const offered = try agent.offer(arena, def);

    // Locks come from the ledger and the command line together. Neither can
    // loosen the other; a lock only ever removes.
    // What m8 ships with is underneath, so `jail` means something before any
    // agent is read, and an agent stands on it rather than beside it.
    const shields = try (shield.Set{
        .defs = def.shields,
        .runners = def.runners,
        .active = def.active,
    }).over(arena, try shield.core(arena, ctx.io, ctx.env));

    // The name has to exist before the turn, because the turn records it.
    const saved_as = try session.newName(arena, io);

    // Everything this run adds, in the order it happened.
    var turn: std.ArrayList(doc.Record) = .empty;
    // Records are separated by a blank line, so writing one has to know
    // whether anything came before it.
    var written = false;
    // The rendered spelling is only ever written for a terminal, and a
    // terminal is the only reader that can watch a reply arrive.
    const live = mode == .m8;

    // A call and its answer are two records, so a ledger can arrive between
    // them. What it already asked for and never got is owed before anything
    // new is said, and nothing already answered is run a second time.
    for (try ledger.outstanding(arena, records.items)) |asked| {
        for (try answer(ctx, shields, offered, .{
            .id = ledger.callId(asked.value),
            .name = ledger.callName(asked.value),
            .arguments = try toolbox.parseArgs(arena, .md, asked.content orelse ""),
        })) |record| {
            try show(arena, out, mode, &written, record);
            try records.append(arena, record);
            try turn.append(arena, record);
        }
        try out.flush();
    }

    // No cap. A model that keeps calling tools is doing what it was given
    // tools for, and where to stop is the trust model's business — `ask`
    // already gates every call for anyone who wants that.
    while (true) {
        var reply: LiveReply = .{
            .out = out,
            .mode = mode,
            .live = live,
            .written = &written,
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
            try show(arena, out, mode, &written, asked);
            try out.flush();
            try keep(arena, &records, asked);
            try turn.append(arena, asked);

            // The answer comes from the tool, not the model, and was already
            // checked against what a tool may say.
            for (try answer(ctx, shields, offered, c)) |record| {
                try show(arena, out, mode, &written, record);
                try records.append(arena, record);
                try turn.append(arena, record);
            }
            try out.flush();
        }
    }

    try show(arena, out, mode, &written, .{ .sigil = .agent, .value = saved_as });
    try out.flush();

    // Saved unexpanded: the ledger as it arrived still names what it
    // continues, so a turn holds only its own exchange and forking copies
    // nothing.
    var whole: std.ArrayList(doc.Record) = .empty;
    try whole.appendSlice(arena, try settled(arena, io, dirs, given));
    try whole.appendSlice(arena, turn.items);
    try session.write(arena, io, dirs, saved_as, whole.items);
    try session.setAlias(arena, io, dirs, session.global, saved_as);
    if (expanded.origin.len > 0)
        try session.setAlias(arena, io, dirs, expanded.origin, saved_as);
}

/// Lineage names the turn continued, never an alias to it: aliases move, and
/// a turn that named one would become its own ancestor as soon as it did.
fn settled(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    records: []const doc.Record,
) ![]const doc.Record {
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| {
        if (r.sigil != .agent) {
            try out.append(arena, r);
            continue;
        }
        const target = (try session.deref(arena, io, dirs, r.value)) orelse r.value;
        try out.append(arena, .{ .sigil = .agent, .value = target });
    }
    return out.items;
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

    // Two ways to say how a tool runs, and the difference is where the
    // call's values go. An argv takes them as whole elements; a block takes
    // none at all and reads them out of the environment.
    const argv = switch (tool.command) {
        .none => unreachable,
        .argv => |a| toolbox.expand(arena, a, args, c.arguments) catch |e|
            return failure(arena, c.id, "{s}", .{@errorName(e)}),
        .block => |b| shield.through(arena, shields.runners, b) catch |e|
            return failure(arena, c.id, "{s}", .{@errorName(e)}),
    };
    if (argv.len == 0) return failure(arena, c.id, "the command expanded to nothing", .{});


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
    try env.append(arena, .{ .key = shield.self_var, .value = ctx.self });
    try env.appendSlice(arena, stood.env);
    try env.appendSlice(arena, try toolbox.callEnv(arena, args, c.arguments, c.id));

    var captured: std.Io.Writer.Allocating = .init(arena);
    var err_sink: std.Io.Writer.Allocating = .init(arena);
    var tty_storage: api.TtyFiles = undefined;

    const call = @import("command/call.zig");
    // m8 owns the framing, and this is the only place it is decided. A shield
    // is launched without it, which is what makes a wrapper transparent; a
    // tool gets it unless it declared that it answers in m8 itself.
    const speaks_m8 = std.mem.eql(u8, tool.speaks, "m8");
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
    }, wrapped, if (speaks_m8) .document else .framed) catch |e|
        return failure(arena, c.id, "{s}", .{@errorName(e)});

    // Framed, `call` already wrote a 🧾 or a 🚫; speaking, what came back is
    // the tool's own records. Either way it is read back rather than guessed.
    var diag: doc.Diagnostic = .{};
    const said = doc.parse(arena, captured.written(), &diag) catch
        return failure(arena, c.id, "the tool wrote nothing readable", .{});
    if (said.len == 0 and !speaks_m8) return failure(arena, c.id, "the tool wrote nothing", .{});

    const records = if (speaks_m8) try settle(arena, said, c.id, status) else said;

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
/// The locks in force are passed through, so a checker is never more capable
/// than what invoked it — otherwise a jailed agent reaches the world by
/// talking its own checker into it. Its reply is never streamed and never
/// reaches the receipt; it exists to decide, not to be read.
/// `m8 shield check AGENT -- CMD...`, which is what 🛡check expands into.
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

/// Write a record, with the blank line that separates it from the last one.
fn show(
    arena: Allocator,
    out: *std.Io.Writer,
    mode: doc.Mode,
    written: *bool,
    r: doc.Record,
) !void {
    if (written.*) try out.writeByte('\n');
    written.* = true;
    try doc.write(out, mode, try ledger.rendered(arena, mode, r));
}

/// Bridges the provider's byte stream into the document, flushing each
/// fragment so the text appears as it is generated rather than at the end.
const LiveReply = struct {
    out: *std.Io.Writer,
    mode: doc.Mode,
    live: bool,
    written: *bool,
    /// Opened on the first byte. A model that only calls a tool says nothing,
    /// and an empty 🤖 above the call would be a record of nothing.
    body: ?doc.ContentWriter = null,
    pending: ?sigil.Sigil = null,

    fn sink(self: *LiveReply) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    /// Remembered rather than written. A record with nothing in it is a record
    /// of nothing, and a codec is entitled to open one and find the model had
    /// no more to say — so the header waits for a byte to justify it.
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, _: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        self.pending = s;
    }

    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (bytes.len == 0) return;
        if (self.body == null) {
            if (self.written.*) try self.out.writeByte('\n');
            self.written.* = true;
            self.body = try doc.ContentWriter.begin(
                self.out,
                self.mode,
                self.pending orelse .bot,
                "",
            );
        }
        try self.body.?.write(bytes);
        if (self.live) try self.out.flush();
    }

    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *LiveReply = @ptrCast(@alignCast(ctx));
        if (self.body) |*b| try b.finish();
        self.body = null;
        self.pending = null;
    }

    fn finish(self: *LiveReply) !void {
        if (self.body) |*b| try b.finish();
        self.body = null;
    }
};

/// What a speaking tool said, with the two things only m8 can know filled in.
///
/// A tool that answers in the language names its own records, but it does not
/// know which call it is answering unless it read `M8_CALL_ID`, and it cannot
/// know how it ended until after it has stopped saying so. Both are added when
/// they are missing and never when they are there — a tool that said how it
/// went is believed, because it knew something m8 would only be guessing at.
fn settle(
    arena: Allocator,
    said: []const doc.Record,
    id: []const u8,
    status: u8,
) ![]const doc.Record {
    var out: std.ArrayList(doc.Record) = .empty;
    var verdicted = false;
    for (said) |r| {
        var one = r;
        switch (r.sigil) {
            .result, .ok, .failed => {
                if (one.value.len == 0) one.value = id;
                if (r.sigil != .result) verdicted = true;
            },
            .call => if (ledger.callId(one.value).len == 0) {
                one.value = try std.fmt.allocPrint(arena, "{s},{s}", .{ ledger.callName(one.value), id });
            },
            else => {},
        }
        try out.append(arena, one);
    }
    if (!verdicted) try out.append(arena, if (status == 0)
        .{ .sigil = .ok, .value = id }
    else
        .{ .sigil = .failed, .value = id, .content = try std.fmt.allocPrint(
            arena,
            "Failed with exit code {d}",
            .{status},
        ) });
    return out.items;
}
