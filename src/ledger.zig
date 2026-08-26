//! The ledger: what a name expands to, in the order it was written.
//!
//! A name resolves to a file of records. A 🧠 inside it names something else,
//! and expanding replaces that record with what it names — in place, so
//! whatever stood before an inclusion still stands before it. A 🧠 that names
//! no document is a model, and stays as itself.
//!
//! Nothing is dropped and nothing is reordered. That is the whole contract.
//! The facts a request needs, and a provider's wire format, are both taken
//! from this, and only such a projection may lose anything.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");
const doc = @import("m8/doc.zig");
const model = @import("m8/model.zig");
const session = @import("session.zig");
const toolbox = @import("toolbox.zig");

pub const max_depth = 8;

pub const Error = error{
    UnknownAgent,
    IncludeTooDeep,
};

/// Stated explicitly because `expand` recurses through itself.
pub const ExpandError = Error || doc.ParseError || toolbox.Error || std.Io.Writer.Error;

pub const Ledger = struct {
    records: []const doc.Record = &.{},
    /// The agent this is really with: the first authored name met on the way,
    /// skipping the generated `=` and `+` namespaces. Not a record — it is
    /// something the walk knew that the flattened order cannot say, and it is
    /// only ever used to decide which alias to move.
    origin: []const u8 = "",
};

/// The document a name resolves to, or null when it names none. Looked up
/// before anything recurses, so "there is no such file" stays apart from
/// "something inside it was missing" — one is a model name, the other is a
/// fault worth reporting.
fn source(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
) !?[]const u8 {
    const file = try std.fmt.allocPrint(arena, "{s}.md", .{name});
    return config.read(arena, io, dirs, file);
}

/// Whether a name resolves to a document at all. What tells an agent nobody
/// has written from a model nobody has to.
pub fn names(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
) !bool {
    return (try source(arena, io, dirs, name)) != null;
}

/// Expand `name` into its records.
pub fn expand(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    depth: u8,
) ExpandError!Ledger {
    if (depth > max_depth) return Error.IncludeTooDeep;
    const src = (try source(arena, io, dirs, name)) orelse return Error.UnknownAgent;
    return expandSource(arena, io, dirs, name, src, depth);
}

fn expandSource(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    src: []const u8,
    depth: u8,
) ExpandError!Ledger {
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(arena, src, &diag);

    var l = try expandRecords(arena, io, dirs, records, doc.detect(src) orelse .md, depth);
    // An authored name is its own origin and never inherits one; a generated
    // name takes the origin of whatever it continues.
    if (!session.isGenerated(name)) l.origin = name;
    return l;
}

/// Expand the 🧠 references inside records that are already in hand.
///
/// This is what the command line assembles into: a ledger may name what it
/// continues rather than carry it, and every reader expands the same way. An
/// inclusion is replaced where it stands, so a document that named its parent
/// halfway down still reads in the order it was written.
pub fn expandRecords(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    records: []const doc.Record,
    mode: doc.Mode,
    depth: u8,
) ExpandError!Ledger {
    if (depth > max_depth) return Error.IncludeTooDeep;

    var out: std.ArrayList(doc.Record) = .empty;
    var origin: []const u8 = "";

    for (records) |r| {
        // A 🧠 written with the mark names a model and is kept as it is.
        // Anything else names an agent, and only an agent — nothing is looked
        // up to decide which, so a name that is not there is a missing agent
        // rather than a model nobody configured.
        if (r.sigil == .agent and !model.is(r.value)) {
            if (depth + 1 > max_depth) return Error.IncludeTooDeep;
            const src = (try source(arena, io, dirs, r.value)) orelse return Error.UnknownAgent;
            const inner = try expandSource(arena, io, dirs, r.value, src, depth + 1);
            if (origin.len == 0) origin = inner.origin;
            try out.appendSlice(arena, inner.records);
            continue;
        }
        try out.append(arena, try canonical(arena, mode, r));
    }
    return .{ .records = out.items, .origin = origin };
}

/// Nested content carries the quote of the document it sat in, and a ledger
/// holds records from several. `md` is the spelling every file is written in,
/// so a ledger is kept in that one and anything arriving in the other is
/// restated on the way in rather than left for a later reader to guess at.
fn canonical(arena: Allocator, mode: doc.Mode, r: doc.Record) !doc.Record {
    return restate(arena, mode, .md, r);
}

/// The same record in the spelling a reader is being written. The mirror of
/// `canonical`: nested content moves on the way out, never on the way in.
pub fn rendered(arena: Allocator, mode: doc.Mode, r: doc.Record) !doc.Record {
    return restate(arena, .md, mode, r);
}

/// Write records in `mode`, nested content included.
///
/// `doc.writeAll` writes content verbatim, which is right — it knows nothing
/// about what a sigil's block means. Two sigils carry a whole grammar inside
/// theirs, and this is what knows that.
pub fn writeAll(
    w: *std.Io.Writer,
    arena: Allocator,
    mode: doc.Mode,
    records: []const doc.Record,
) !void {
    for (records, 0..) |r, i| {
        if (i > 0) try w.writeByte('\n');
        try doc.write(w, mode, try rendered(arena, mode, r));
    }
}

fn restate(arena: Allocator, from: doc.Mode, to: doc.Mode, r: doc.Record) !doc.Record {
    if (from == to) return r;
    const content = r.content orelse return r;
    return switch (r.sigil) {
        .tool => .{
            .sigil = r.sigil,
            .value = r.value,
            .content = try toolbox.render(arena, to, try toolbox.parse(arena, from, r.value, content)),
        },
        .call => .{
            .sigil = r.sigil,
            .value = r.value,
            .content = try toolbox.renderArgs(arena, to, try toolbox.parseArgs(arena, from, content)),
        },
        else => r,
    };
}

/// The model this ledger runs on: the first 🧠 in the model form, since every
/// 🧠 that named an agent was replaced by what it named.
pub fn runsOn(arena: Allocator, records: []const doc.Record) !?model.Model {
    for (records) |r| {
        if (r.sigil != .agent) continue;
        if (try model.parse(arena, r.value)) |m| return m;
    }
    return null;
}

/// The call id a 📲 carries. The value is `name,id`.
pub fn callId(value: []const u8) []const u8 {
    const cut = std.mem.indexOfScalar(u8, value, ',') orelse return "";
    return std.mem.trim(u8, value[cut + 1 ..], " \t");
}

/// The tool name a 📲 carries.
pub fn callName(value: []const u8) []const u8 {
    const cut = std.mem.indexOfScalar(u8, value, ',') orelse return value;
    return std.mem.trim(u8, value[0..cut], " \t");
}

/// The 📲 records nothing has answered yet.
///
/// A call and its answer are two records, so a ledger can end between them —
/// a run that was interrupted, or one handed over mid-turn. Those are the
/// calls still owed, and they are what a run picks up before it says anything
/// else. Everything already answered is history and is never run twice.
pub fn outstanding(arena: Allocator, records: []const doc.Record) ![]const doc.Record {
    var answered: std.ArrayList([]const u8) = .empty;
    for (records) |r| switch (r.sigil) {
        .result, .failed => try answered.append(arena, std.mem.trim(u8, r.value, " \t")),
        else => {},
    };

    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| {
        if (r.sigil != .call) continue;
        const id = callId(r.value);
        const has = for (answered.items) |a| {
            if (std.mem.eql(u8, a, id)) break true;
        } else false;
        if (!has) try out.append(arena, r);
    }
    return out.items;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        const dir = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
        std.Io.Dir.cwd().deleteTree(io, dir) catch {};
        try std.Io.Dir.cwd().createDirPath(io, dir);
        return .{ .io = io, .dir = dir };
    }

    fn agent(f: Fixture, gpa: Allocator, name: []const u8, body: []const u8) !void {
        const path = try std.fs.path.join(gpa, &.{ f.dir, name });
        if (std.fs.path.dirname(path)) |d| try std.Io.Dir.cwd().createDirPath(f.io, d);
        try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = body });
    }

    fn deinit(f: Fixture, gpa: Allocator) void {
        std.Io.Dir.cwd().deleteTree(f.io, f.dir) catch {};
        gpa.free(f.dir);
    }
};

test "an inclusion lands where it was written, not at the front" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-order");
    defer f.deinit(arena);
    try f.agent(arena, "helper.md",
        \\# :computer:
        \\> Helper.
    );
    try f.agent(arena, "outer.md",
        \\# :brain:/local/tiny
        \\
        \\# :computer:
        \\> First.
        \\
        \\# :brain:helper
        \\
        \\# :computer:
        \\> Last.
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "outer", 0);

    // 🧠local/tiny stays, and the include sits between the two 💻 it was
    // written between.
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqual(doc.Sigil.agent, l.records[0].sigil);
    try testing.expectEqualStrings("/local/tiny", l.records[0].value);
    try testing.expectEqualStrings("First.", l.records[1].content.?);
    try testing.expectEqualStrings("Helper.", l.records[2].content.?);
    try testing.expectEqualStrings("Last.", l.records[3].content.?);
    try testing.expectEqualStrings("outer", l.origin);
}

test "a chat expands through its turns to the agent it began with" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-chat");
    defer f.deinit(arena);
    try f.agent(arena, "mathy.md", "# :brain:/local/tiny\n\n# :computer:\n> Be brief.\n");
    try f.agent(arena, "=/one.md", "# :brain:mathy\n\n# :raising_hand:\n> Hi.\n\n# :robot:\n> Hello.\n");
    try f.agent(arena, "=/two.md", "# :brain:=/one\n\n# :raising_hand:\n> More.\n\n# :robot:\n> Sure.\n");
    try f.agent(arena, "+/mathy.md", "# :brain:=/two\n");

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "+/mathy", 0);

    const want = [_]doc.Sigil{ .agent, .system, .user, .bot, .user, .bot };
    try testing.expectEqual(want.len, l.records.len);
    for (want, l.records) |s, r| try testing.expectEqual(s, r.sigil);
    try testing.expectEqualStrings("mathy", l.origin);
    try testing.expectEqualStrings("tiny", (try runsOn(arena, l.records)).?.name);
}

test "tool calls stay, and only an unanswered one is still owed" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-calls");
    defer f.deinit(arena);
    try f.agent(arena, "=/t.md",
        \\# :brain:/local/tiny
        \\
        \\# :calling:say,c1
        \\> :package:text
        \\> > hi
        \\
        \\# :receipt:c1
        \\> hi
        \\
        \\# :calling:say,c2
        \\> :package:text
        \\> > bye
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "=/t", 0);

    // Four records, the calls among them.
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqual(doc.Sigil.call, l.records[1].sigil);
    try testing.expectEqual(doc.Sigil.result, l.records[2].sigil);

    const owed = try outstanding(arena, l.records);
    try testing.expectEqual(@as(usize, 1), owed.len);
    try testing.expectEqualStrings("c2", callId(owed[0].value));
    try testing.expectEqualStrings("say", callName(owed[0].value));
}

test "a cycle stops at the depth cap" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-cycle");
    defer f.deinit(arena);
    try f.agent(arena, "ping.md", "# :brain:pong\n");
    try f.agent(arena, "pong.md", "# :brain:ping\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.IncludeTooDeep, expand(arena, f.io, &dirs, "ping", 0));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "nosuch", 0));
}

test "nested content is kept in one spelling and restated for the reader" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .call, .value = "say,c1", .content = ":package:text\n> hi" },
    };

    // A terminal is written the rendered spelling all the way down.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try writeAll(&buf.writer, arena, .m8, &records);
    try testing.expect(std.mem.indexOf(u8, buf.written(), "\u{1F4E6}text") != null);
    try testing.expect(std.mem.indexOf(u8, buf.written(), ":package:") == null);

    // And reading that back gives the canonical spelling again, so what lands
    // in a file is never half one and half the other.
    var diag: doc.Diagnostic = .{};
    const back = try doc.parse(arena, buf.written(), &diag);
    const same = try canonical(arena, .m8, back[0]);
    try testing.expectEqualStrings(records[0].content.?, same.content.?);
}

test "a name with no mark is an agent, and a missing one is missing" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-naming");
    defer f.deinit(arena);
    // Two links deep, so the failure has somewhere to be swallowed.
    try f.agent(arena, "outer.md", "# :brain:middle\n");
    try f.agent(arena, "middle.md", "# :brain:gone\n");
    // A slash no longer makes something a model; only the mark does.
    try f.agent(arena, "slashed.md", "# :brain:team/gone\n");
    try f.agent(arena, "marked.md", "# :brain:/team/gone,max_tokens:16\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "outer", 0));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "slashed", 0));

    // Marked, it is a model, and nothing is looked up at all.
    const m = (try runsOn(arena, (try expand(arena, f.io, &dirs, "marked", 0)).records)).?;
    try testing.expectEqualStrings("team", m.provider);
    try testing.expectEqualStrings("gone", m.name);
    try testing.expectEqualStrings("16", m.get("max_tokens").?);
}


