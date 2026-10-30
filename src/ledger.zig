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
//! agent is a definition inclusion, which may cross mob boundaries; generated
//! turns and chats are state and remain confined to the activated mob. A 🧠
//! naming a generated one is lineage, the turn this turn continues. Chains can
//! be arbitrarily long; depth alone is not a fault.
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
    InvalidName,
    CrossMobReference,
    NoDataHome,
    /// An authored include leads back to the same physical definition.
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

pub const ExpandError = Error || session.ReadError || toolbox.Error || std.Io.Writer.Error || config.DefinitionError;

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
    dirs: config.Dirs,
    name: []const u8,
) !?[]const u8 {
    if (model.is(name)) return null;
    if (try config.read(arena, io, dirs, try config.nameFile(arena, name))) |src| return src;
    // A chat with no pointer of its own reads as its parent's head, so it
    // names a document whether or not its file has been written yet.
    if (!session.isPointer(name) and !session.isChat(name)) return null;
    const at = session.head(arena, io, dirs, if (session.isPointer(name)) session.chatOf(name) else name) catch |e| switch (e) {
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
    dirs: config.Dirs,
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
    /// Config root that supplied an authored definition, if any.
    source_root: []const u8 = "",
    /// This frame is a chat or turn; references made directly from it must
    /// stay inside the activated mob. Authored includes have their own scope.
    state_context: bool = false,
    /// Which half was asked for, which is also which path it is on.
    part: Part = .body,
};

/// Expand `name` into its records.
pub fn expand(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    name: []const u8,
) ExpandError!Ledger {
    const scoped = try config.pin(arena, io, dirs, name);
    const definition = if (session.isChat(name)) null else try config.definition(arena, io, scoped, name, null);
    const src = if (definition) |d| d.bytes else (try source(arena, io, scoped, name)) orelse return Error.UnknownAgent;

    var diag: doc.Diagnostic = .{};
    const parsed = try doc.parse(arena, src, &diag);
    return walk(arena, io, scoped, .{
        .records = (try Split.of(parsed)).body,
        .mode = doc.detect(src) orelse .md,
        .name = name,
        .source_root = if (definition) |d| d.root else "",
        .state_context = session.isGenerated(name) or session.isChat(name),
    }, .{});
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
    dirs: config.Dirs,
    records: []const doc.Record,
    mode: doc.Mode,
) ExpandError!Ledger {
    return expandUntil(arena, io, dirs, records, mode, .{});
}

/// Where a walk stops short: a 🧠 it leaves as it was written rather than
/// following. What comes out is still a ledger, and reads as the whole of
/// what it was cut from, because the 🧠 left standing names the rest.
pub const Breaks = struct {
    names: []const []const u8 = &.{},
    /// A snip is kept aside to be out of the way, and stays there.
    snips: bool = false,

    fn at(b: Breaks, name: []const u8) bool {
        if (b.snips and session.namesSnip(name)) return true;
        for (b.names) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }
};

/// `expandRecords`, stopping at whatever `breaks` names.
pub fn expandUntil(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    records: []const doc.Record,
    mode: doc.Mode,
    breaks: Breaks,
) ExpandError!Ledger {
    return walk(arena, io, dirs, .{ .records = (try Split.of(records)).body, .mode = mode }, breaks);
}

/// Read a document and everything it names, in order.
///
/// One loop over an explicit stack rather than a call per link. A chat is a
/// link per turn and there is no reason a long one should be a deep one: what
/// this costs is a frame, which is a slice and two numbers, and what it bounds
/// is memory rather than anything m8 has an opinion about.
///
/// That stack is also the path: a physical definition (name, source root,
/// and part) may not be reached again. Same-spelled files in higher layers
/// remain distinct, allowing direct customization chains while preserving
/// indirect-cycle detection.
fn walk(
    arena: Allocator,
    io: std.Io,
    dirs: config.Dirs,
    root: Frame,
    breaks: Breaks,
) ExpandError!Ledger {
    var scoped = dirs;
    var out: std.ArrayList(doc.Record) = .empty;
    var stack: std.ArrayList(Frame) = .empty;
    // One path map per document half. Keys include the physical source root,
    // so same-name overlay layers can wrap without making cycle checks linear.
    var paths: [2]std.StringHashMapUnmanaged(void) = .{ .empty, .empty };
    try stack.append(arena, root);
    if (root.name.len > 0) try paths[@intFromEnum(root.part)].put(arena, try pathKey(arena, root.name, root.source_root), {});

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
            if (top.name.len > 0) _ = paths[@intFromEnum(top.part)].remove(try pathKey(arena, top.name, top.source_root));
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
        // A 🧠 written with the mark names a model and is kept as it is, and
        // so is one a break names.
        // Anything else names an agent, and only an agent — nothing is looked
        // up to decide which, so a name that is not there is a missing agent
        // rather than a model nobody configured.
        if ((r.sigil == .agent or r.sigil == .skill) and !model.is(r.value)) {
            const state_target = session.isGenerated(r.value) or session.isChat(r.value);
            if (state_target or top.state_context or (scoped.mob == null and config.authored(r.value))) {
                scoped = try config.pin(arena, io, scoped, r.value);
            }
        }
        const want: Part = switch (r.sigil) {
            .agent => if (model.is(r.value) or breaks.at(r.value)) {
                try out.append(arena, try canonical(arena, top.mode, r));
                continue;
            } else .body,
            .skill => .top,
            else => {
                try out.append(arena, try canonical(arena, top.mode, r));
                continue;
            },
        };

        const direct_self = std.mem.eql(u8, r.value, top.name) and top.source_root.len > 0 and want == top.part;
        const definition = if (config.authored(r.value))
            try config.definition(arena, io, scoped, r.value, if (direct_self) top.source_root else null)
        else
            null;
        const src = if (definition) |d| d.bytes else if (config.authored(r.value))
            return Error.UnknownAgent
        else
            (try source(arena, io, scoped, r.value)) orelse return Error.UnknownAgent;
        const next_root = if (definition) |d| d.root else "";

        const identity = try pathKey(arena, r.value, next_root);
        if (paths[@intFromEnum(want)].contains(identity)) return if (session.isGenerated(r.value)) Error.LineageLoops else Error.IncludeLoops;
        var diag: doc.Diagnostic = .{};
        const parsed = try doc.parse(arena, src, &diag);
        const next: Frame = .{
            .records = (try Split.of(parsed)).half(want),
            .mode = doc.detect(src) orelse .md,
            .name = r.value,
            .part = want,
            .source_root = next_root,
            .state_context = session.isGenerated(r.value) or session.isChat(r.value),
        };

        // Nothing above is read again after this: appending may move the
        // frames, and `top` is a pointer into them.
        try paths[@intFromEnum(want)].put(arena, identity, {});
        try stack.append(arena, next);
    }

    return .{ .records = out.items, .origin = origin };
}

fn pathKey(arena: Allocator, name: []const u8, root: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}\x00{s}", .{ root, name });
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

/// Write records in `mode`, nested content included, and highlighted as
/// `look` says when there is one.
///
/// `doc.writeAll` writes content verbatim, which is right — it knows nothing
/// about what a sigil's block means. Two sigils carry a whole grammar inside
/// theirs, and this is what knows that.
pub fn writeAll(
    w: *std.Io.Writer,
    arena: Allocator,
    mode: doc.Mode,
    look: ?doc.Look,
    records: []const doc.Record,
) !void {
    for (records, 0..) |r, i| {
        if (i > 0) try w.writeByte('\n');
        try doc.writeLooking(w, mode, look, try rendered(arena, mode, r));
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
        // Argument bullets use the same Markdown in both document modes.
        // Restating them must not decode their types without a tool schema.
        .call => r,
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
    // In the order it happened, so an answer settles the call before it and
    // never one made later under an id a provider used twice.
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| switch (r.sigil) {
        .call => try out.append(arena, r),
        .result, .scroll, .link, .ok, .failed => {
            const id = std.mem.trim(u8, r.value, " \t");
            var i: usize = 0;
            while (i < out.items.len) {
                if (std.mem.eql(u8, callId(out.items[i].value), id)) _ = out.orderedRemove(i) else i += 1;
            }
        },
        else => {},
    };
    return out.items;
}

/// One thing the person answered, and who had asked: the tool, or one of the
/// shields it stood inside.
pub const Answer = struct { who: []const u8, text: []const u8 };

/// Who asked, from a ❓ or ❗ value, which says that first and the call after.
pub fn asker(value: []const u8) []const u8 {
    const v = std.mem.trim(u8, value, " \t");
    return v[0 .. std.mem.indexOfScalar(u8, v, ',') orelse 0];
}

/// The call a ❓ or ❗ value is about.
pub fn askedId(value: []const u8) []const u8 {
    const v = std.mem.trim(u8, value, " \t");
    return if (std.mem.indexOfScalar(u8, v, ',')) |at| v[at + 1 ..] else v;
}

/// What the person has answered a call's questions with, oldest first.
///
/// Counted from the call itself. An id is the provider's to choose, and one
/// that chose the same id twice has not had its second call answered by what
/// was said to its first.
pub fn exclamations(arena: Allocator, records: []const doc.Record, id: []const u8) ![]const Answer {
    var out: std.ArrayList(Answer) = .empty;
    for (records) |r| switch (r.sigil) {
        .call => if (std.mem.eql(u8, callId(r.value), id)) out.clearRetainingCapacity(),
        .exclaim => if (std.mem.eql(u8, askedId(r.value), id))
            try out.append(arena, .{ .who = asker(r.value), .text = r.content orelse "" }),
        else => {},
    };
    return out.items;
}

/// What a ledger is waiting on the person for: who asked and of which call,
/// as its last record says it, when its last record is a question.
pub fn asking(records: []const doc.Record) ?[]const u8 {
    if (records.len == 0) return null;
    const last = records[records.len - 1];
    return if (last.sigil == .question) std.mem.trim(u8, last.value, " \t") else null;
}

/// The same, of whatever a name reads as. A name that reads as nothing is
/// waiting on nobody, and whoever runs it is the one to say what is wrong.
pub fn waiting(arena: Allocator, io: std.Io, dirs: config.Dirs, name: []const u8) ?[]const u8 {
    const l = expand(arena, io, dirs, name) catch return null;
    return asking(l.records);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const test_tmp = @import("test_tmp.zig");

const Fixture = struct {
    io: std.Io,
    dir: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Fixture {
        const io = threaded.io();
        return .{ .io = io, .dir = try test_tmp.make(gpa, io, name) };
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
    try f.agent(arena, "test/helper.md",
        \\* :compass::
        \\  > Helper.
    );
    try f.agent(arena, "test/outer.md",
        \\* :brain::/local/tiny
        \\
        \\* :compass::
        \\  > First.
        \\
        \\* :brain::test/helper
        \\
        \\* :compass::
        \\  > Last.
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer");

    // 🧠local/tiny stays, and the include sits between the two 🧭 it was
    // written between.
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqual(doc.Sigil.agent, l.records[0].sigil);
    try testing.expectEqualStrings("/local/tiny", l.records[0].value);
    try testing.expectEqualStrings("First.", l.records[1].content.?);
    try testing.expectEqualStrings("Helper.", l.records[2].content.?);
    try testing.expectEqualStrings("Last.", l.records[3].content.?);
    try testing.expectEqualStrings("test/outer", l.origin);
}

test "a chat expands through its turns to the agent it began with" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-chat");
    defer f.deinit(arena);
    try f.agent(arena, "test/mathy.md", "* :brain::/local/tiny\n\n* :compass::\n  > Be brief.\n");
    try f.agent(arena, "test/mathy/+/one.md", "* :brain::test/mathy\n\n* :raising_hand::\n  > Hi.\n\n* :robot::\n  > Hello.\n");
    try f.agent(arena, "test/mathy/+/two.md", "* :brain::test/mathy/+/one\n\n* :raising_hand::\n  > More.\n\n* :robot::\n  > Sure.\n");
    try f.agent(arena, "test/mathy/+.md", "* :brain::test/mathy/+/two\n");

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+");

    const want = [_]doc.Sigil{ .agent, .system, .user, .bot, .user, .bot };
    try testing.expectEqual(want.len, l.records.len);
    for (want, l.records) |s, r| try testing.expectEqual(s, r.sigil);
    try testing.expectEqualStrings("test/mathy", l.origin);
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
    try f.agent(arena, "test/mathy.md", "* :brain::/local/tiny\n");

    const dirs = [_][]const u8{f.dir};
    const turn = "test/mathy/+/abcdefghij";
    try session.write(arena, f.io, config.Dirs{ .roots = &dirs }, turn, &.{
        .{ .sigil = .agent, .value = "test/mathy" },
        .{ .sigil = .thought, .content = "weighing it" },
        .{ .sigil = .thought, .value = "snip", .content = ":lock_with_ink_pen:`SIG`" },
        .{ .sigil = .bot, .content = "Hi." },
    });

    // The turn names the snip and holds none of it.
    const saved = (try config.read(arena, f.io, config.Dirs{ .roots = &dirs }, try config.nameFile(arena, turn))).?;
    try testing.expect(std.mem.indexOf(u8, saved, "SIG") == null);
    // A 🧠 like any other, beside the turn that names it.
    var saved_diag: doc.Diagnostic = .{};
    const snip = (try doc.parse(arena, saved, &saved_diag))[2];
    try testing.expectEqual(doc.Sigil.agent, snip.sigil);
    try testing.expect(std.mem.startsWith(u8, snip.value, "test/mathy/+/" ++ session.snip_prefix));
    try testing.expect((try config.read(arena, f.io, config.Dirs{ .roots = &dirs }, try config.nameFile(arena, snip.value))) != null);

    // Read back, everything is where it was, still asking to be kept aside.
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, turn);
    try testing.expectEqual(@as(usize, 4), l.records.len);
    try testing.expectEqualStrings("weighing it", l.records[1].content.?);
    try testing.expectEqualStrings(":lock_with_ink_pen:`SIG`", l.records[2].content.?);
    try testing.expect(session.isSnip(l.records[2]));
    try testing.expectEqualStrings("test/mathy", l.origin);

    // A snip that is gone is said, not quietly left out.
    try f.agent(arena, "test/mathy/+/lost.md", "* :brain::test/mathy\n\n* :brain::test/mathy/+/snip-nowherenea\n");
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+/lost"));
}

test "tool calls stay, and only an unanswered one is still owed" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-calls");
    defer f.deinit(arena);
    try f.agent(arena, "test/mathy/+/t.md",
        \\* :brain::/local/tiny
        \\
        \\* :calling::say,c1
        \\  > * text `"hi"`
        \\
        \\* :receipt::c1
        \\  >     hi
        \\
        \\* :calling::say,c2
        \\  > * text `"bye"`
    );

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+/t");

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
    try f.agent(arena, "test/mathy.md", "* :brain::/local/tiny\n\n* :compass::\n  > Be brief.\n");

    // Every run writes one link, so a chat this long is a chain this deep.
    // Far past the cap on how far one agent may include another, and far
    // past what a call per link would have left of the stack — which is what
    // this length is for. Anything less would pass either way.
    const turns = 5000;
    var parent: []const u8 = "test/mathy";
    for (0..turns) |i| {
        const name = try std.fmt.allocPrint(arena, "test/mathy/+/t{d}", .{i});
        try f.agent(
            arena,
            try std.fmt.allocPrint(arena, "{s}.md", .{name}),
            try std.fmt.allocPrint(
                arena,
                "* :brain::{s}\n\n* :raising_hand::\n  > {d}\n\n* :robot::\n  > ok\n",
                .{ parent, i },
            ),
        );
        parent = name;
    }
    try f.agent(arena, "test/mathy/+.md", try std.fmt.allocPrint(arena, "* :brain::{s}\n", .{parent}));

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+");

    // 🧠 and 🧭 from the agent, then a 🙋 and a 🤖 per turn, in the order they
    // happened — oldest first, since a turn's parent stands where it was named.
    try testing.expectEqual(@as(usize, 2 + turns * 2), l.records.len);
    try testing.expectEqualStrings("test/mathy", l.origin);
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
    try f.agent(arena, "test/mathy/+/a.md", "* :brain::test/mathy/+/b\n\n* :raising_hand::\n  > one\n");
    try f.agent(arena, "test/mathy/+/b.md", "* :brain::test/mathy/+/a\n\n* :raising_hand::\n  > two\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.LineageLoops, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+/a"));

    // A turn naming itself is the same fault, one link shorter.
    try f.agent(arena, "test/mathy/+/self.md", "* :brain::test/mathy/+/self\n");
    try testing.expectError(Error.LineageLoops, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy/+/self"));
}

test "an agent met twice is not a cycle" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-twice");
    defer f.deinit(arena);
    try f.agent(arena, "test/helper.md", "* :compass::\n  > Helper.\n");
    try f.agent(arena, "test/outer.md", "* :brain::/local/tiny\n\n* :brain::test/helper\n\n* :brain::test/helper\n");

    // Twice along one path is a cycle; twice side by side is a mob used
    // twice, and both copies stand where they were named.
    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer");
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
    try f.agent(arena, "test/ping.md", "* :brain::test/pong\n");
    try f.agent(arena, "test/pong.md", "* :brain::test/ping\n");
    try f.agent(arena, "test/selfy.md", "* :brain::test/selfy\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.IncludeLoops, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/ping"));
    // A same-layer self-reference is a customization request; with no more
    // distant definition to wrap, lookup is exhausted.
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/selfy"));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/nosuch"));
}

test "an include chain may be as deep as it is, within one mob" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-deep-include");
    defer f.deinit(arena);

    // Well past the eight this used to stop at. Nine includes is nine includes, and
    // the only thing wrong with a chain is the one that closes.
    const links = 100;
    try f.agent(arena, "test/tail.md", "* :brain::/local/tiny\n");
    var below: []const u8 = "test/tail";
    for (0..links) |i| {
        const name = try std.fmt.allocPrint(arena, "test/agent{d}", .{i});
        try f.agent(
            arena,
            try std.fmt.allocPrint(arena, "{s}.md", .{name}),
            try std.fmt.allocPrint(
                arena,
                "* :compass::\n  > {d}\n\n* :brain::{s}\n",
                .{ i, below },
            ),
        );
        below = name;
    }

    const dirs = [_][]const u8{f.dir};
    const l = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, below);

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
        .{ .sigil = .tool, .value = "say", .content = "> Says a thing.\n\n:shield:jail\n`say`\n* text string" },
        .{ .sigil = .call, .value = "say,c1", .content = "* text `\"hi\"`" },
    };

    // A terminal is written the rendered spelling all the way down: the 🛡️
    // inside the 🧰 and the quote its description sits behind are both the
    // reader's, not the file's.
    var buf: std.Io.Writer.Allocating = .init(arena);
    try writeAll(&buf.writer, arena, .m8, null, &records);
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
    try f.agent(arena, "test/outer.md", "* :brain::test/middle\n");
    try f.agent(arena, "test/middle.md", "* :brain::test/gone\n");
    // A slash no longer makes something a model; only the mark does.
    try f.agent(arena, "test/slashed.md", "* :brain::test/gone\n");
    try f.agent(arena, "test/marked.md", "* :brain::/team/gone,max_tokens:16\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer"));
    try testing.expectError(Error.UnknownAgent, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/slashed"));

    // Marked, it is a model, and nothing is looked up at all.
    const m = (try runsOn(arena, (try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/marked")).records)).?;
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
    try f.agent(arena, "test/tight-docs.md",
        \\* :top::
        \\
        \\* :compass::
        \\  > Load tight-docs when working on documentation.
        \\
        \\* :top::
        \\
        \\* :raising_hand::
        \\  > The skill itself.
    );

    const dirs = [_][]const u8{f.dir};

    // 🧠 wants what the file says.
    const body = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/tight-docs");
    try testing.expectEqual(@as(usize, 1), body.records.len);
    try testing.expectEqualStrings("The skill itself.", body.records[0].content.?);

    // 📚 wants what it says about itself, and neither half carries the fence.
    const top = try expandRecords(arena, f.io, config.Dirs{ .roots = &dirs }, &.{
        .{ .sigil = .skill, .value = "test/tight-docs" },
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
    try f.agent(arena, "test/plain.md", "* :compass::\n  > All of it.\n");

    const dirs = [_][]const u8{f.dir};
    const body = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/plain");
    try testing.expectEqual(@as(usize, 1), body.records.len);

    // There is no advertisement, so nothing is advertised. Not an error and
    // not the whole file.
    const top = try expandRecords(arena, f.io, config.Dirs{ .roots = &dirs }, &.{
        .{ .sigil = .skill, .value = "test/plain" },
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
    try f.agent(arena, "test/late.md", "* :compass::\n  > First.\n\n* :top::\n");
    try f.agent(arena, "test/unclosed.md", "* :top::\n\n* :compass::\n  > Forever.\n");
    try f.agent(arena, "test/thrice.md",
        \\* :top::
        \\
        \\* :top::
        \\
        \\* :compass::
        \\  > Body.
        \\
        \\* :top::
    );

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.TopMisplaced, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/late"));
    try testing.expectError(Error.TopUnclosed, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/unclosed"));
    try testing.expectError(Error.TopMisplaced, expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/thrice"));
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
    try f.agent(arena, "test/inner.md",
        \\* :top::
        \\
        \\* :compass::
        \\  > Inner advert.
        \\
        \\* :top::
        \\
        \\* :compass::
        \\  > Inner body.
    );
    try f.agent(arena, "test/helper.md", "* :compass::\n  > Helper body.\n");
    try f.agent(arena, "test/outer.md",
        \\* :top::
        \\
        \\* :books::test/inner
        \\
        \\* :top::
        \\
        \\* :brain::test/helper
    );

    const dirs = [_][]const u8{f.dir};
    const body = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer");
    try testing.expectEqual(@as(usize, 1), body.records.len);
    try testing.expectEqualStrings("Helper body.", body.records[0].content.?);

    const top = try expandRecords(arena, f.io, config.Dirs{ .roots = &dirs }, &.{
        .{ .sigil = .skill, .value = "test/outer" },
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
    try f.agent(arena, "test/selfish.md",
        \\* :top::
        \\
        \\* :books::test/selfish
        \\
        \\* :top::
        \\
        \\* :compass::
        \\  > Body.
    );
    // Disjoint halves, so this one terminates: the body reaches the top and
    // the top has no way back down.
    try f.agent(arena, "test/advertises-itself.md",
        \\* :top::
        \\
        \\* :compass::
        \\  > What I am for.
        \\
        \\* :top::
        \\
        \\* :books::test/advertises-itself
    );

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(Error.UnknownAgent, expandRecords(arena, f.io, config.Dirs{ .roots = &dirs }, &.{
        .{ .sigil = .skill, .value = "test/selfish" },
    }, .md));

    const ok = try expand(arena, f.io, config.Dirs{ .roots = &dirs }, "test/advertises-itself");
    try testing.expectEqual(@as(usize, 1), ok.records.len);
    try testing.expectEqualStrings("What I am for.", ok.records[0].content.?);
}

test "a call that asked is still owed, and is handed what was answered" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const records = [_]doc.Record{
        // An earlier call under the same id, long settled, with an answer of
        // its own that is none of the next one's business.
        .{ .sigil = .call, .value = "run,c1" },
        .{ .sigil = .question, .value = "tool,c1", .content = "sure?" },
        .{ .sigil = .exclaim, .value = "tool,c1", .content = "old" },
        .{ .sigil = .ok, .value = "c1" },
        .{ .sigil = .call, .value = "run,c1" },
        .{ .sigil = .call, .value = "run,c2" },
        .{ .sigil = .question, .value = "shield_ask,c1", .content = "sure?" },
        .{ .sigil = .exclaim, .value = "shield_ask,c1", .content = "yes" },
        .{ .sigil = .question, .value = "tool,c1", .content = "really?" },
    };

    // A question is not an answer, so both calls are owed, in the order made.
    const owed = try outstanding(arena, &records);
    try testing.expectEqual(@as(usize, 2), owed.len);
    try testing.expectEqualStrings("run,c1", owed[0].value);
    try testing.expectEqualStrings("run,c2", owed[1].value);

    const said = try exclamations(arena, &records, "c1");
    try testing.expectEqual(@as(usize, 1), said.len);
    try testing.expectEqualStrings("shield_ask", said[0].who);
    try testing.expectEqualStrings("yes", said[0].text);
    try testing.expectEqual(@as(usize, 0), (try exclamations(arena, &records, "c2")).len);

    // Waiting on the person only while a question is the last thing said.
    // Who asked and of which call, as it will be said back with the answer.
    try testing.expectEqualStrings("tool,c1", asking(&records).?);
    try testing.expectEqualStrings("tool", asker("tool,c1"));
    try testing.expectEqualStrings("c1", askedId("tool,c1"));
    try testing.expectEqual(@as(?[]const u8, null), asking(records[0..8]));
}

test "a break leaves its 🧠 standing, and what follows it is all that is read" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-ledger-break");
    defer f.deinit(arena);
    try f.agent(arena, "test/mathy.md", "* :brain::/local/tiny\n\n* :compass::\n  > Be mathy.\n");
    try f.agent(arena, "test/mathy/+/aaaaaaaaaa.md", "* :brain::test/mathy\n\n* :raising_hand::\n  > one\n");
    try f.agent(arena, "test/mathy/+/snip-bbbbbbbbbb.md", "* :thought_balloon::snip\n  > :lock_with_ink_pen:`c2ln`\n");
    try f.agent(arena, "test/mathy/+/cccccccccc.md",
        \\* :brain::test/mathy/+/aaaaaaaaaa
        \\
        \\* :brain::test/mathy/+/snip-bbbbbbbbbb
        \\
        \\* :robot::
        \\  > two
    );

    const dirs = [_][]const u8{f.dir};
    const head: []const doc.Record = &.{.{ .sigil = .agent, .value = "test/mathy/+/cccccccccc" }};

    // From a turn on: the 🧠 naming it, and what was added after.
    const since = try expandUntil(arena, f.io, config.Dirs{ .roots = &dirs }, head, .md, .{
        .names = &.{"test/mathy/+/aaaaaaaaaa"},
        .snips = true,
    });
    try testing.expectEqual(@as(usize, 3), since.records.len);
    try testing.expectEqualStrings("test/mathy/+/aaaaaaaaaa", since.records[0].value);
    try testing.expectEqualStrings("test/mathy/+/snip-bbbbbbbbbb", since.records[1].value);
    try testing.expectEqualStrings("two", since.records[2].content.?);

    // A name never met breaks nothing, so the agent is the other place to stop.
    const whole = try expandUntil(arena, f.io, config.Dirs{ .roots = &dirs }, head, .md, .{ .names = &.{ "test/mathy/+/zzzzzzzzzz", "test/mathy" } });
    try testing.expectEqualStrings("test/mathy", whole.records[0].value);
    try testing.expectEqualStrings("one", whole.records[1].content.?);
    try testing.expectEqual(doc.Sigil.thought, whole.records[2].sigil);
}

test "document expansion stays inside the activated mob, while another activation is independent" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-ledger-isolation");
    defer f.deinit(arena);
    try f.agent(arena, "first/helper.md", "* :brain::/local/tiny\n");
    try f.agent(arena, "first/agent.md", "* :brain::first/helper\n");
    try f.agent(arena, "second/agent.md", "* :brain::/local/tiny\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    _ = try expand(arena, f.io, dirs, "first/agent");
    // A separate invocation may activate the other mob normally.
    _ = try expand(arena, f.io, dirs, "second/agent");
    _ = try expand(arena, f.io, dirs, "first/agent");
    try f.agent(arena, "first/agent.md", "* :brain::second/agent\n");
    _ = try expand(arena, f.io, dirs, "first/agent");
    try f.agent(arena, "first/agent.md", "* :books::second/agent\n");
    _ = try expand(arena, f.io, dirs, "first/agent");
    try f.agent(arena, "first/helper/+/turn.md", "* :brain::second/agent\n");
    try testing.expectError(error.CrossMobReference, expand(arena, f.io, dirs, "first/helper/+/turn"));
    // Even through a shared authored definition, state references stay scoped
    // to the turn's activated mob.
    try f.agent(arena, "first/helper.md", "* :brain::second/helper\n");
    try f.agent(arena, "second/helper.md", "* :brain::second/agent/+\n");
    try f.agent(arena, "first/helper/+/from-shared.md", "* :brain::first/helper\n");
    try testing.expectError(error.CrossMobReference, expand(arena, f.io, dirs, "first/helper/+/from-shared"));
    try f.agent(arena, "first/chatty.md", "* :brain::second/agent//job\n");
    try testing.expectError(error.CrossMobReference, expand(arena, f.io, dirs, "first/chatty"));
    try f.agent(arena, "first/agent.md", "* :brain::first/helper\n");
    try f.agent(arena, "first/helper.md", "* :brain::second/agent\n");
    const chat_turn = "first/agent//resume/+/turn";
    try session.write(arena, f.io, dirs, chat_turn, &.{.{ .sigil = .agent, .value = "first/agent" }});
    try session.point(arena, f.io, dirs, "first/agent//resume/+", chat_turn);
    const resumed = try expand(arena, f.io, dirs, "first/agent//resume");
    try testing.expectEqualStrings("/local/tiny", resumed.records[0].value);

    const foreign_turn = "first/agent/+/foreign";
    try f.agent(arena, "first/agent/+/foreign.md", "* :brain::second/agent\n");
    try testing.expectError(error.CrossMobReference, expand(arena, f.io, dirs, foreign_turn));

    try f.agent(arena, "first/helper/+.md", "* :brain::second/agent/+\n");
    try testing.expectError(error.CrossMobReference, session.head(arena, f.io, dirs, "first/helper"));
}

test "double-slash chat references expand and settle, keeping turns and snips apart" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-ledger-double-slash");
    defer f.deinit(arena);
    try f.agent(arena, "crew/cody.md", "* :brain::/local/tiny\n");
    try f.agent(arena, "crew/cody/delegated.md", "* :brain::/local/other\n");
    const dirs: config.Dirs = .{ .roots = &.{f.dir} };
    // An unwritten chat inherits its agent, not the same-spelled namespace.
    const initial = try expand(arena, f.io, dirs, "crew/cody//delegated");
    try testing.expectEqualStrings("tiny", (try runsOn(arena, initial.records)).?.name);
    const turn = "crew/cody//delegated/+/qgivwhgxnh";
    try session.write(arena, f.io, dirs, turn, &.{
        .{ .sigil = .agent, .value = "crew/cody" },
        .{ .sigil = .thought, .value = "snip", .content = "kept aside" },
        .{ .sigil = .bot, .content = "hello" },
    });
    try session.point(arena, f.io, dirs, "crew/cody//delegated/+", turn);
    try testing.expectEqualStrings(turn, try session.settle(arena, f.io, dirs, "crew/cody//delegated"));
    const continued = try expandRecords(arena, f.io, dirs, &.{.{ .sigil = .agent, .value = "crew/cody//delegated" }}, .md);
    try testing.expectEqual(@as(usize, 3), continued.records.len);
    try testing.expectEqualStrings("kept aside", continued.records[1].content.?);
    try testing.expectEqualStrings("hello", continued.records[2].content.?);
    const nested = try expand(arena, f.io, dirs, "crew/cody/delegated");
    try testing.expectEqualStrings("other", (try runsOn(arena, nested.records)).?.name);
}

test "same-name definitions wrap through layers while references restart nearest-first" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-ledger-self-wrap-layers");
    defer f.deinit(arena);
    const near = try std.fs.path.join(arena, &.{ f.dir, "near" });
    const middle = try std.fs.path.join(arena, &.{ f.dir, "middle" });
    const far = try std.fs.path.join(arena, &.{ f.dir, "far" });
    const dirs = config.Dirs{ .roots = &.{ near, middle, far } };

    const near_agent = try std.fs.path.join(arena, &.{ near, "mobs/team/agent.md" });
    try std.Io.Dir.cwd().createDirPath(f.io, std.fs.path.dirname(near_agent).?);
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = near_agent, .data = "* :brain::team/agent\n* :compass::\n  > wrapper\n" });
    const middle_agent = try std.fs.path.join(arena, &.{ middle, "mobs/team/agent.md" });
    try std.Io.Dir.cwd().createDirPath(f.io, std.fs.path.dirname(middle_agent).?);
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = middle_agent, .data = "* :brain::team/agent\n* :brain::team/helper\n* :compass::\n  > wrapper\n" });
    const far_agent = try std.fs.path.join(arena, &.{ far, "mobs/team/agent.md" });
    try std.Io.Dir.cwd().createDirPath(f.io, std.fs.path.dirname(far_agent).?);
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = far_agent, .data = "* :brain::/local/tiny\n* :compass::\n  > base\n" });
    // The middle file's unrelated include restarts at the nearest root.
    const near_helper = try std.fs.path.join(arena, &.{ near, "mobs/team/helper.md" });
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = near_helper, .data = "* :compass::\n  > nearest helper\n" });
    const wrapped = try expand(arena, f.io, dirs, "team/agent");
    try testing.expectEqual(@as(usize, 5), wrapped.records.len);
    try testing.expectEqualStrings("/local/tiny", wrapped.records[0].value);
    try testing.expectEqualStrings("base", wrapped.records[1].content.?);
    try testing.expectEqualStrings("nearest helper", wrapped.records[2].content.?);
    try testing.expectEqualStrings("wrapper", wrapped.records[3].content.?);
    try testing.expectEqualStrings("wrapper", wrapped.records[4].content.?);
}

test "indirect same-name layer return is a cycle and empty nearest mob owns state" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const f = try Fixture.init(arena, &threaded, "m8-ledger-layer-cycle");
    defer f.deinit(arena);
    const near = try std.fs.path.join(arena, &.{ f.dir, "near" });
    const far = try std.fs.path.join(arena, &.{ f.dir, "far" });
    const dirs = config.Dirs{ .roots = &.{ near, far } };
    const cycle = try std.fs.path.join(arena, &.{ far, "mobs/team/agent.md" });
    try std.Io.Dir.cwd().createDirPath(f.io, std.fs.path.dirname(cycle).?);
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = cycle, .data = "* :brain::team/helper\n" });
    const helper = try std.fs.path.join(arena, &.{ far, "mobs/team/helper.md" });
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = helper, .data = "* :brain::team/agent\n" });
    const overlay = try std.fs.path.join(arena, &.{ near, "mobs/team/agent.md" });
    try std.Io.Dir.cwd().createDirPath(f.io, std.fs.path.dirname(overlay).?);
    try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = overlay, .data = "* :brain::team/agent\n" });
    try testing.expectError(Error.IncludeLoops, expand(arena, f.io, dirs, "team/agent"));
    try std.Io.Dir.cwd().createDirPath(f.io, try std.fs.path.join(arena, &.{ near, "mobs/team" }));
    try testing.expect((try config.read(arena, f.io, dirs, try config.nameFile(arena, "team/agent/+"))) == null);
}
