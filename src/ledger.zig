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
//!
//! Two different things are written that same way. A 🧠 naming an authored
//! agent is a mob reaching into a mob; a 🧠 naming a generated one is lineage,
//! the turn this turn continues. Both can be as deep as they are: nine mobs is
//! nine mobs and a thousand turns is a thousand turns, and neither is a fault.
//!
//! The one fault either can have is a loop, and a loop is not a depth. It is a
//! name met twice on the way to itself — so that is what is looked for, and
//! the answer to one is to say which name closed it rather than to refuse the
//! ninth include or the ten thousandth turn. Nothing here has a number in it.
//!
//! So the walk is a loop over an explicit stack, and everything it reads is
//! appended to the one list being built. Neither a link nor a turn costs a
//! call, and nothing is copied twice: reading a conversation is one pass and
//! the memory of one copy of it, however long it has been going on.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");
const doc = @import("m8/doc.zig");
const model = @import("m8/model.zig");
const session = @import("session.zig");
const toolbox = @import("toolbox.zig");

pub const Error = error{
    UnknownAgent,
    /// An agent includes one that leads back to it. A mob may include a mob
    /// nobody has read, so this is the one that happens by accident.
    IncludeLoops,
    /// A turn names one that already leads back to it. Only a hand-edited
    /// file can be shaped like that, since m8 writes a parent that existed
    /// before its child did.
    LineageLoops,
    /// A 🔝 somewhere other than opening or closing the one fence at the head
    /// of a file. There is one top or there is none.
    TopMisplaced,
    /// A 🔝 opened a top that nothing closed.
    TopUnclosed,
};

pub const ExpandError = Error || session.ReadError || toolbox.Error || std.Io.Writer.Error;

pub const Ledger = struct {
    records: []const doc.Record = &.{},
    /// The agent this is really with: the first authored name met on the way,
    /// skipping the turns and chats m8 generated. Not a record — it is
    /// something the walk knew that the flattened order cannot say, and it is
    /// only ever used to decide whose mob's scratch a run gets.
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
    if (try config.read(arena, io, dirs, try config.nameFile(arena, name))) |src| return src;
    // A chat with no pointer of its own reads as its parent's head, so it
    // names a document whether or not its file has been written yet.
    if (!session.isPointer(name) or std.mem.eql(u8, name, session.main)) return null;
    const at = session.head(arena, io, dirs, session.chatOf(name)) catch |e| switch (e) {
        error.UnknownAgent => return null,
        else => return e,
    };
    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, &.{.{ .sigil = .agent, .value = at }});
    return buf.written();
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

/// Which half of a document a reference asks for. 🧠 wants what the file
/// says; 📚 wants what it says about itself.
pub const Part = enum { body, top };

/// A document's two halves. The fence is one sigil opening and closing, at the
/// head of the file, the way a code fence works — so a reader knows which half
/// it is in from the first record rather than from the end of the file.
///
/// A file with no fence is all body and has no top at all. That is what makes
/// 📚 naming one yield nothing rather than the whole of it: there is no
/// advertisement, so nothing is advertised.
const Split = struct {
    top: []const doc.Record = &.{},
    body: []const doc.Record = &.{},

    fn of(records: []const doc.Record) Error!Split {
        if (records.len == 0 or records[0].sigil != .top) {
            for (records) |r| if (r.sigil == .top) return Error.TopMisplaced;
            return .{ .body = records };
        }
        for (records[1..], 1..) |r, i| {
            if (r.sigil != .top) continue;
            for (records[i + 1 ..]) |later| if (later.sigil == .top) return Error.TopMisplaced;
            return .{ .top = records[1..i], .body = records[i + 1 ..] };
        }
        return Error.TopUnclosed;
    }

    fn half(s: Split, part: Part) []const doc.Record {
        return switch (part) {
            .body => s.body,
            .top => s.top,
        };
    }
};

/// One document part-read: what it holds, how far through it the walk has
/// got, and what it has settled on.
const Frame = struct {
    records: []const doc.Record,
    at: usize = 0,
    /// The spelling it arrived in.
    mode: doc.Mode,
    /// The name it came from, which is also its entry on the path. Empty for
    /// records handed straight in: they were never a document, so nothing can
    /// name them again and they are nobody's origin.
    name: []const u8 = "",
    /// The first origin anything under it settled on.
    origin: []const u8 = "",
    /// Which half was asked for, which is also which path it is on.
    part: Part = .body,
};

/// Expand `name` into its records.
pub fn expand(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
) ExpandError!Ledger {
    const src = (try source(arena, io, dirs, name)) orelse return Error.UnknownAgent;

    var diag: doc.Diagnostic = .{};
    const parsed = try doc.parse(arena, src, &diag);
    return walk(arena, io, dirs, .{
        .records = (try Split.of(parsed)).body,
        .mode = doc.detect(src) orelse .md,
        .name = name,
    });
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
) ExpandError!Ledger {
    return walk(arena, io, dirs, .{ .records = (try Split.of(records)).body, .mode = mode });
}

/// Read a document and everything it names, in order.
///
/// One loop over an explicit stack rather than a call per link. A chat is a
/// link per turn and there is no reason a long one should be a deep one: what
/// this costs is a frame, which is a slice and two numbers, and what it bounds
/// is memory rather than anything m8 has an opinion about.
///
/// That stack is also the path, so what is on it is exactly what a name may
/// not name again. That is the whole of it: no count, no ceiling, and nothing
/// to choose a number for. `on_path` is pushed and popped with the frames
/// rather than remembering everywhere the walk has been, because a name met
/// twice side by side is a document used twice — met twice along one path it
/// is a loop, and a loop is the only thing that has no end.
fn walk(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    root: Frame,
) ExpandError!Ledger {
    var out: std.ArrayList(doc.Record) = .empty;
    var stack: std.ArrayList(Frame) = .empty;
    // One path per half. A file's top and its body are disjoint, so a body
    // that names its own top is a reference and not a loop; the two would be
    // indistinguishable on one path.
    var paths: [2]std.StringHashMapUnmanaged(void) = .{ .empty, .empty };

    try stack.append(arena, root);
    if (root.name.len > 0) try paths[@intFromEnum(root.part)].put(arena, root.name, {});

    var origin: []const u8 = "";
    while (stack.items.len > 0) {
        const top = &stack.items[stack.items.len - 1];

        // Read to the end of a document: settle what it was with, hand that
        // up, and take it off the path.
        if (top.at == top.records.len) {
            // An authored name is its own origin and never inherits one; a
            // generated name takes the origin of whatever it continues. A top
            // is nobody's origin: it says what a file is for, and a
            // conversation is never with an advertisement.
            const settled = if (top.part == .top)
                ""
            else if (top.name.len > 0 and !session.isGenerated(top.name))
                top.name
            else
                top.origin;
            if (top.name.len > 0) _ = paths[@intFromEnum(top.part)].remove(top.name);
            stack.items.len -= 1;

            if (stack.items.len == 0) {
                origin = settled;
            } else {
                const up = &stack.items[stack.items.len - 1];
                if (up.origin.len == 0) up.origin = settled;
            }
            continue;
        }

        const r = top.records[top.at];
        top.at += 1;

        // Two sigils reach into another document, and which one it is decides
        // which half comes back. 🧠 wants what a file says; 📚 wants what it
        // says about itself. The mark decides at every reference rather than
        // being inherited, so a top may advertise what it builds on and a body
        // may pull in a skill's advertisement.
        //
        // A 🧠 written with the mark names a model and is kept as it is.
        // Anything else names an agent, and only an agent — nothing is looked
        // up to decide which, so a name that is not there is a missing agent
        // rather than a model nobody configured.
        const want: Part = switch (r.sigil) {
            .agent => if (model.is(r.value)) {
                try out.append(arena, try canonical(arena, top.mode, r));
                continue;
            } else .body,
            .skill => .top,
            else => {
                try out.append(arena, try canonical(arena, top.mode, r));
                continue;
            },
        };

        // Already on the way here, so following it would be following it
        // again. Which kind it is decides only what to call it: lineage is
        // the turn this one continues, and an inclusion is a mob reaching
        // into a mob.
        if (paths[@intFromEnum(want)].contains(r.value)) return if (session.isGenerated(r.value))
            Error.LineageLoops
        else
            Error.IncludeLoops;

        const src = (try source(arena, io, dirs, r.value)) orelse return Error.UnknownAgent;
        var diag: doc.Diagnostic = .{};
        const parsed = try doc.parse(arena, src, &diag);
        const next: Frame = .{
            .records = (try Split.of(parsed)).half(want),
            .mode = doc.detect(src) orelse .md,
            .name = r.value,
            .part = want,
        };

        // Nothing above is read again after this: appending may move the
        // frames, and `top` is a pointer into them.
        try paths[@intFromEnum(want)].put(arena, next.name, {});
        try stack.append(arena, next);
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

/// The model this ledger runs on: the last 🧠 in the model form, since every
/// 🧠 that named an agent was replaced by what it named.
pub fn runsOn(arena: Allocator, records: []const doc.Record) !?model.Model {
    var found: ?model.Model = null;
    for (records) |r| {
        if (r.sigil != .agent) continue;
        if (try model.parse(arena, r.value)) |m| found = m;
    }
    return found;
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
/// A call and its answer are separate records, so a ledger can end between
/// them — a run that was interrupted, or one handed over mid-turn. Those are
/// the calls still owed, and they are what a run picks up before it says
/// anything else. Everything already answered is history and is never run
/// twice.
///
/// Anything the tool wrote counts as answering, verdict or not. A 🧾 with no
/// 🟢 or 🚫 under it is a tool that spoke and was cut off, and running it again
/// to find out how it would have ended would do whatever it does a second
/// time. What happened is in the ledger either way, which is the point of it.
pub fn outstanding(arena: Allocator, records: []const doc.Record) ![]const doc.Record {
    var answered: std.ArrayList([]const u8) = .empty;
    for (records) |r| switch (r.sigil) {
        .result, .ok, .failed => try answered.append(arena, std.mem.trim(u8, r.value, " \t")),
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
        const logical = if (std.mem.endsWith(u8, name, ".md")) name[0 .. name.len - 3] else name;
        const path = try std.fs.path.join(gpa, &.{ f.dir, try config.nameFile(gpa, logical) });
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
        \\#### :compass:
        \\> Helper.
    );
    try f.agent(arena, "outer.md",
        \\#### :brain:/local/tiny
        \\
        \\#### :compass:
        \\> First.
        \\
        \\#### :brain:helper
        \\
        \\#### :compass:
        \\> Last.
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "outer");

    // 🧠local/tiny stays, and the include sits between the two 🧭 it was
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
    try f.agent(arena, "mathy.md", "#### :brain:/local/tiny\n\n#### :compass:\n> Be brief.\n");
    try f.agent(arena, "+/one.md", "#### :brain:mathy\n\n#### :raising_hand:\n> Hi.\n\n#### :robot:\n> Hello.\n");
    try f.agent(arena, "+/two.md", "#### :brain:+/one\n\n#### :raising_hand:\n> More.\n\n#### :robot:\n> Sure.\n");
    try f.agent(arena, "mathy/+.md", "#### :brain:+/two\n");

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "mathy/+");

    const want = [_]doc.Sigil{ .agent, .system, .user, .bot, .user, .bot };
    try testing.expectEqual(want.len, l.records.len);
    for (want, l.records) |s, r| try testing.expectEqual(s, r.sigil);
    try testing.expectEqualStrings("mathy", l.origin);
    try testing.expectEqualStrings("tiny", (try runsOn(arena, l.records)).?.name);
}

test "a thought kept aside is a snip on disk and whole again when read" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-snip");
    defer f.deinit(arena);
    try f.agent(arena, "mathy.md", "#### :brain:/local/tiny\n");

    const dirs = [_][]const u8{f.dir};
    const turn = "mathy/+/abcdefghij";
    try session.write(arena, f.io, &dirs, turn, &.{
        .{ .sigil = .agent, .value = "mathy" },
        .{ .sigil = .thought, .content = "weighing it" },
        .{ .sigil = .thought, .value = "snip", .content = ":lock_with_ink_pen:SIG" },
        .{ .sigil = .bot, .content = "Hi." },
    });

    // The turn names the snip and holds none of it.
    const saved = (try config.read(arena, f.io, &dirs, try config.nameFile(arena, turn))).?;
    try testing.expect(std.mem.indexOf(u8, saved, "SIG") == null);
    // A 🧠 like any other, beside the turn that names it.
    var saved_diag: doc.Diagnostic = .{};
    const snip = (try doc.parse(arena, saved, &saved_diag))[2];
    try testing.expectEqual(doc.Sigil.agent, snip.sigil);
    try testing.expect(std.mem.startsWith(u8, snip.value, "mathy/+/" ++ session.snip_prefix));
    try testing.expect((try config.read(arena, f.io, &dirs, try config.nameFile(arena, snip.value))) != null);

    // Read back, everything is where it was, still asking to be kept aside.
    const l = try expand(arena, f.io, &dirs, turn);
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqualStrings("weighing it", l.records[1].content.?);
    try testing.expectEqualStrings(":lock_with_ink_pen:SIG", l.records[2].content.?);
    try testing.expect(session.isSnip(l.records[2]));
    try testing.expectEqualStrings("mathy", l.origin);

    // A snip that is gone is said, not quietly left out.
    try f.agent(arena, "mathy/+/lost.md", "#### :brain:mathy\n\n#### :brain:mathy/+/snip-nowherenea\n");
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "mathy/+/lost"));
}

test "tool calls stay, and only an unanswered one is still owed" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-calls");
    defer f.deinit(arena);
    try f.agent(arena, "+/t.md",
        \\#### :brain:/local/tiny
        \\
        \\#### :calling:say,c1
        \\> * text `hi`
        \\
        \\#### :receipt:c1
        \\> hi
        \\
        \\#### :calling:say,c2
        \\> * text `bye`
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "+/t");

    // Four records, the calls among them.
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqual(doc.Sigil.call, l.records[1].sigil);
    try testing.expectEqual(doc.Sigil.result, l.records[2].sigil);

    const owed = try outstanding(arena, l.records);
    try testing.expectEqual(@as(usize, 1), owed.len);
    try testing.expectEqualStrings("c2", callId(owed[0].value));
    try testing.expectEqualStrings("say", callName(owed[0].value));
}

test "a conversation is as long as it is, whatever the include cap says" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-long");
    defer f.deinit(arena);
    try f.agent(arena, "mathy.md", "#### :brain:/local/tiny\n\n#### :compass:\n> Be brief.\n");

    // Every run writes one link, so a chat this long is a chain this deep.
    // Far past the cap on how far one agent may include another, and far
    // past what a call per link would have left of the stack — which is what
    // this length is for. Anything less would pass either way.
    const turns = 5000;
    var parent: []const u8 = "mathy";
    for (0..turns) |i| {
        const name = try std.fmt.allocPrint(arena, "+/t{d}", .{i});
        try f.agent(
            arena,
            try std.fmt.allocPrint(arena, "{s}.md", .{name}),
            try std.fmt.allocPrint(
                arena,
                "#### :brain:{s}\n\n#### :raising_hand:\n> {d}\n\n#### :robot:\n> ok\n",
                .{ parent, i },
            ),
        );
        parent = name;
    }
    try f.agent(arena, "mathy/+.md", try std.fmt.allocPrint(arena, "#### :brain:{s}\n", .{parent}));

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "mathy/+");

    // 🧠 and 🧭 from the agent, then a 🙋 and a 🤖 per turn, in the order they
    // happened — oldest first, since a turn's parent stands where it was named.
    try testing.expectEqual(@as(usize, 2 + turns * 2), l.records.len);
    try testing.expectEqualStrings("mathy", l.origin);
    try testing.expectEqualStrings("0", l.records[2].content.?);
    try testing.expectEqualStrings(
        try std.fmt.allocPrint(arena, "{d}", .{turns - 1}),
        l.records[l.records.len - 2].content.?,
    );
}

test "lineage that closes on itself says so, rather than running out of depth" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-lineage-cycle");
    defer f.deinit(arena);
    // m8 never writes this: a turn names one that existed before it did. Only
    // an edited file is shaped like this, and it is still worth naming.
    try f.agent(arena, "+/a.md", "#### :brain:+/b\n\n#### :raising_hand:\n> one\n");
    try f.agent(arena, "+/b.md", "#### :brain:+/a\n\n#### :raising_hand:\n> two\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.LineageLoops, expand(arena, f.io, &dirs, "+/a"));

    // A turn naming itself is the same fault, one link shorter.
    try f.agent(arena, "+/self.md", "#### :brain:+/self\n");
    try testing.expectError(Error.LineageLoops, expand(arena, f.io, &dirs, "+/self"));
}

test "an agent met twice is not a cycle" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-twice");
    defer f.deinit(arena);
    try f.agent(arena, "helper.md", "#### :compass:\n> Helper.\n");
    try f.agent(arena, "outer.md", "#### :brain:/local/tiny\n\n#### :brain:helper\n\n#### :brain:helper\n");

    // Twice along one path is a cycle; twice side by side is a mob used
    // twice, and both copies stand where they were named.
    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, "outer");
    try testing.expectEqual(@as(usize, 3), l.records.len);
    try testing.expectEqualStrings("Helper.", l.records[1].content.?);
    try testing.expectEqualStrings("Helper.", l.records[2].content.?);
}

test "an agent that includes one leading back to it says so" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-cycle");
    defer f.deinit(arena);
    try f.agent(arena, "ping.md", "#### :brain:pong\n");
    try f.agent(arena, "pong.md", "#### :brain:ping\n");
    try f.agent(arena, "selfy.md", "#### :brain:selfy\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.IncludeLoops, expand(arena, f.io, &dirs, "ping"));
    try testing.expectError(Error.IncludeLoops, expand(arena, f.io, &dirs, "selfy"));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "nosuch"));
}

test "a mob may be as deep as it is, since depth is not the fault" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-deep-include");
    defer f.deinit(arena);

    // Well past the eight this used to stop at. Nine mobs is nine mobs, and
    // the only thing wrong with a chain is the one that closes.
    const links = 100;
    try f.agent(arena, "tail.md", "#### :brain:/local/tiny\n");
    var below: []const u8 = "tail";
    for (0..links) |i| {
        const name = try std.fmt.allocPrint(arena, "mob{d}", .{i});
        try f.agent(
            arena,
            try std.fmt.allocPrint(arena, "{s}.md", .{name}),
            try std.fmt.allocPrint(
                arena,
                "#### :compass:\n> {d}\n\n#### :brain:{s}\n",
                .{ i, below },
            ),
        );
        below = name;
    }

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, &dirs, below);

    // One 🧭 per link, outermost first, and the model at the bottom.
    try testing.expectEqual(@as(usize, links + 1), l.records.len);
    try testing.expectEqualStrings(
        try std.fmt.allocPrint(arena, "{d}", .{links - 1}),
        l.records[0].content.?,
    );
    try testing.expectEqualStrings("0", l.records[links - 1].content.?);
    try testing.expectEqualStrings("/local/tiny", l.records[links].value);
    // The outermost authored name is what the chat would be with.
    try testing.expectEqualStrings(below, l.origin);
}

test "nested content is kept in one spelling and restated for the reader" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        .{ .sigil = .tool, .value = "say", .content = "> Says a thing.\n:shield:jail\n`say`\n* text string" },
        .{ .sigil = .call, .value = "say,c1", .content = "* text `hi`" },
    };

    // A terminal is written the rendered spelling all the way down: the 🛡️
    // inside the 🧰 and the quote its description sits behind are both the
    // reader's, not the file's.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try writeAll(&buf.writer, arena, .m8, &records);
    try testing.expect(std.mem.indexOf(u8, buf.written(), "\u{1F6E1}\u{FE0F}jail") != null);
    try testing.expect(std.mem.indexOf(u8, buf.written(), ":shield:") == null);
    try testing.expect(std.mem.indexOf(u8, buf.written(), "\u{2502} \u{2502} Says a thing.") != null);
    try testing.expect(std.mem.indexOf(u8, buf.written(), "> ") == null);

    // And reading that back gives the canonical spelling again, so what lands
    // in a file is never half one and half the other.
    var diag: doc.Diagnostic = .{};
    const back = try doc.parse(arena, buf.written(), &diag);
    try testing.expectEqual(records.len, back.len);
    for (records, back) |r, b| {
        const same = try canonical(arena, .m8, b);
        try testing.expectEqualStrings(r.content.?, same.content.?);
    }
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
    try f.agent(arena, "outer.md", "#### :brain:middle\n");
    try f.agent(arena, "middle.md", "#### :brain:gone\n");
    // A slash no longer makes something a model; only the mark does.
    try f.agent(arena, "slashed.md", "#### :brain:team/gone\n");
    try f.agent(arena, "marked.md", "#### :brain:/team/gone,max_tokens:16\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "outer"));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, &dirs, "slashed"));

    // Marked, it is a model, and nothing is looked up at all.
    const m = (try runsOn(arena, (try expand(arena, f.io, &dirs, "marked")).records)).?;
    try testing.expectEqualStrings("team", m.provider);
    try testing.expectEqualStrings("gone", m.name);
    try testing.expectEqualStrings("16", m.get("max_tokens").?);
}

test "the fence splits a file, and the mark decides which half comes back" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-top");
    defer f.deinit(arena);
    try f.agent(arena, "skills/tight-docs.md",
        \\#### :top:
        \\
        \\#### :compass:
        \\> Load tight-docs when working on documentation.
        \\
        \\#### :top:
        \\
        \\#### :raising_hand:
        \\> The skill itself.
    );

    const dirs = [_][]const u8{f.dir};

    // 🧠 wants what the file says.
    const body = try expand(arena, f.io, &dirs, "skills/tight-docs");
    try testing.expectEqual(@as(usize, 1), body.records.len);
    try testing.expectEqualStrings("The skill itself.", body.records[0].content.?);

    // 📚 wants what it says about itself, and neither half carries the fence.
    const top = try expandRecords(arena, f.io, &dirs, &.{
        .{ .sigil = .skill, .value = "skills/tight-docs" },
    }, .md);
    try testing.expectEqual(@as(usize, 1), top.records.len);
    try testing.expectEqual(doc.Sigil.system, top.records[0].sigil);
    try testing.expectEqualStrings(
        "Load tight-docs when working on documentation.",
        top.records[0].content.?,
    );
    for (body.records) |r| try testing.expect(r.sigil != .top);
    for (top.records) |r| try testing.expect(r.sigil != .top);
}

test "a file with no fence is all body, so naming its top yields nothing" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-notop");
    defer f.deinit(arena);
    try f.agent(arena, "plain.md", "#### :compass:\n> All of it.\n");

    const dirs = [_][]const u8{f.dir};
    const body = try expand(arena, f.io, &dirs, "plain");
    try testing.expectEqual(@as(usize, 1), body.records.len);

    // There is no advertisement, so nothing is advertised. Not an error and
    // not the whole file.
    const top = try expandRecords(arena, f.io, &dirs, &.{
        .{ .sigil = .skill, .value = "plain" },
    }, .md);
    try testing.expectEqual(@as(usize, 0), top.records.len);
}

test "there is one fence at the head of a file, or there is none" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-badtop");
    defer f.deinit(arena);
    try f.agent(arena, "late.md", "#### :compass:\n> First.\n\n#### :top:\n");
    try f.agent(arena, "unclosed.md", "#### :top:\n\n#### :compass:\n> Forever.\n");
    try f.agent(arena, "thrice.md",
        \\#### :top:
        \\
        \\#### :top:
        \\
        \\#### :compass:
        \\> Body.
        \\
        \\#### :top:
    );

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.TopMisplaced, expand(arena, f.io, &dirs, "late"));
    try testing.expectError(Error.TopUnclosed, expand(arena, f.io, &dirs, "unclosed"));
    try testing.expectError(Error.TopMisplaced, expand(arena, f.io, &dirs, "thrice"));
}

test "the mark decides at every reference rather than being inherited" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-topdeep");
    defer f.deinit(arena);
    // Its top advertises another skill's top; its body includes an agent's
    // body. Reaching one never drags in the other.
    try f.agent(arena, "inner.md",
        \\#### :top:
        \\
        \\#### :compass:
        \\> Inner advert.
        \\
        \\#### :top:
        \\
        \\#### :compass:
        \\> Inner body.
    );
    try f.agent(arena, "helper.md", "#### :compass:\n> Helper body.\n");
    try f.agent(arena, "outer.md",
        \\#### :top:
        \\
        \\#### :books:inner
        \\
        \\#### :top:
        \\
        \\#### :brain:helper
    );

    const dirs = [_][]const u8{f.dir};
    const body = try expand(arena, f.io, &dirs, "outer");
    try testing.expectEqual(@as(usize, 1), body.records.len);
    try testing.expectEqualStrings("Helper body.", body.records[0].content.?);

    const top = try expandRecords(arena, f.io, &dirs, &.{
        .{ .sigil = .skill, .value = "outer" },
    }, .md);
    try testing.expectEqual(@as(usize, 1), top.records.len);
    try testing.expectEqualStrings("Inner advert.", top.records[0].content.?);
}

test "a top that names its own top is a loop; a body naming it is not" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-toploop");
    defer f.deinit(arena);
    try f.agent(arena, "selfish.md",
        \\#### :top:
        \\
        \\#### :books:selfish
        \\
        \\#### :top:
        \\
        \\#### :compass:
        \\> Body.
    );
    // Disjoint halves, so this one terminates: the body reaches the top and
    // the top has no way back down.
    try f.agent(arena, "advertises-itself.md",
        \\#### :top:
        \\
        \\#### :compass:
        \\> What I am for.
        \\
        \\#### :top:
        \\
        \\#### :books:advertises-itself
    );

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.IncludeLoops, expandRecords(arena, f.io, &dirs, &.{
        .{ .sigil = .skill, .value = "selfish" },
    }, .md));

    const ok = try expand(arena, f.io, &dirs, "advertises-itself");
    try testing.expectEqual(@as(usize, 1), ok.records.len);
    try testing.expectEqualStrings("What I am for.", ok.records[0].content.?);
}
