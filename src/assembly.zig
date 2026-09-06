//! Assembling the ledger a command line describes.
//!
//! Three things go in, in this order: the name, whatever was piped in, and
//! the prompt. One rule is behind all of it — what arrived is the context,
//! and nothing is added to it that was not asked for.
//!
//!   nothing piped   NAME (or the last chat) → prompt
//!   m8 piped        NAME → the document → prompt
//!   anything else   NAME (or the last chat) → prompt, with the text after it
//!
//! A document that arrived is a ledger already, so no last chat is grafted
//! onto it. Anything else piped in is prose rather than context — it is what
//! somebody would have typed after `--` — so it joins the prompt, and the
//! fallback still applies.
//!
//! The order is the order it was written. A 💻 that ends up after a 🙋 stays
//! there; putting it first is the business of whichever api encoding is about
//! to want it that way.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const ledger = @import("ledger.zig");
const modelform = @import("m8/model.zig");
const session = @import("session.zig");

pub const Assembled = struct {
    /// The ledger, in the spelling every file is written in.
    document: []const u8 = "",
    /// The name actually used, once the fallback has had its say. Only for
    /// saying which agent it was that could not be found.
    name: []const u8 = "",
    /// Whether anything was piped in or typed. A name on its own is not
    /// something to say.
    said_nothing: bool = true,
};

/// A document is told from prose by its first line alone, so one that opens
/// like a document and then goes wrong is an error rather than a prompt.
pub fn assemble(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    named: bool,
    prompt: []const u8,
    piped: []const u8,
) !Assembled {
    const is_document = piped.len > 0 and doc.detect(piped) != null;
    const prose = if (is_document) "" else std.mem.trim(u8, piped, " \t\r\n");

    var records: std.ArrayList(doc.Record) = .empty;

    var use = name;
    if (!named and !is_document) use = session.latest;
    if (use.len > 0) {
        // A turn names the turn it continues, never an alias to it: aliases
        // move, and a turn that named one would become its own ancestor.
        const target = (try session.deref(arena, io, dirs, use)) orelse use;

        // Checked here, while the name is still known to have come from the
        // command line, so a typo can be named rather than reported as
        // whatever the ledger made of it. A marked name is a model and is
        // never looked up.
        if (!modelform.is(target) and
            !try ledger.names(arena, io, dirs, target)) return error.UnknownAgent;

        try records.append(arena, .{ .sigil = .agent, .value = target });
    }

    if (is_document) {
        var diag: doc.Diagnostic = .{};
        try records.appendSlice(arena, try doc.parse(arena, piped, &diag));
    }

    // The prompt and whatever prose was piped are one thing said, not two: a
    // prompt in front of piped text is a preamble to it.
    const said = if (prompt.len > 0 and prose.len > 0)
        try std.fmt.allocPrint(arena, "{s}\n{s}", .{ prompt, prose })
    else if (prompt.len > 0) prompt else prose;
    if (said.len > 0) try records.append(arena, .{ .sigil = .user, .content = said });

    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, records.items);
    return .{
        .document = buf.written(),
        .name = use,
        .said_nothing = piped.len == 0 and prompt.len == 0,
    };
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
        const f: Fixture = .{ .io = io, .dir = dir };
        // An agent, a turn, and the last chat pointing at it — so the
        // fallback has something real to reach and the alias something real
        // to be followed to.
        try f.write(gpa, "mathy.md", "#### :brain:/local/tiny\n");
        try f.write(gpa, "=/last.md", "#### :brain:mathy\n");
        try f.write(gpa, "+/+.md", "#### :brain:=/last\n");
        return f;
    }

    fn write(f: Fixture, gpa: Allocator, name: []const u8, body: []const u8) !void {
        const path = try std.fs.path.join(gpa, &.{ f.dir, name });
        if (std.fs.path.dirname(path)) |d| try std.Io.Dir.cwd().createDirPath(f.io, d);
        try std.Io.Dir.cwd().writeFile(f.io, .{ .sub_path = path, .data = body });
    }

    fn deinit(f: Fixture, gpa: Allocator) void {
        std.Io.Dir.cwd().deleteTree(f.io, f.dir) catch {};
        gpa.free(f.dir);
    }
};

fn sigils(arena: Allocator, a: Assembled) ![]const doc.Record {
    var diag: doc.Diagnostic = .{};
    return doc.parse(arena, a.document, &diag);
}

test "nothing piped: the name falls back to the last chat" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-assembly-fallback");
    defer f.deinit(arena);
    const dirs = [_][]const u8{f.dir};

    const got = try assemble(arena, f.io, &dirs, "", false, "hello", "");
    const r = try sigils(arena, got);
    try testing.expectEqual(@as(usize, 2), r.len);
    // The alias was followed, so the turn will name a turn and not a mover.
    try testing.expectEqual(doc.Sigil.agent, r[0].sigil);
    try testing.expectEqualStrings("=/last", r[0].value);
    try testing.expectEqualStrings("hello", r[1].content.?);
    try testing.expect(!got.said_nothing);

    // A name that was typed is used as it is.
    const named = try assemble(arena, f.io, &dirs, "mathy", true, "hello", "");
    try testing.expectEqualStrings("mathy", (try sigils(arena, named))[0].value);

    // Neither piped nor said is somebody finding out what m8 is.
    const empty = try assemble(arena, f.io, &dirs, "", false, "", "");
    try testing.expect(empty.said_nothing);
}

test "an m8 document piped in is the context, so nothing is grafted onto it" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-assembly-document");
    defer f.deinit(arena);
    const dirs = [_][]const u8{f.dir};

    const piped = "#### :brain:/local/tiny\n\n#### :raising_hand:\n> piped\n";
    const got = try assemble(arena, f.io, &dirs, "", false, "more", piped);
    const r = try sigils(arena, got);

    // No last chat in front of it: 🧠 came from the document itself.
    try testing.expectEqual(@as(usize, 3), r.len);
    try testing.expectEqualStrings("/local/tiny", r[0].value);
    try testing.expectEqualStrings("piped", r[1].content.?);
    try testing.expectEqualStrings("more", r[2].content.?);

    // Named, the name still leads and the document follows it.
    const with = try assemble(arena, f.io, &dirs, "mathy", true, "", piped);
    const w = try sigils(arena, with);
    try testing.expectEqualStrings("mathy", w[0].value);
    try testing.expectEqualStrings("/local/tiny", w[1].value);
    // A prompt is not needed when something was piped.
    try testing.expect(!with.said_nothing);
}

test "prose piped in joins the prompt rather than becoming its own record" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-assembly-prose");
    defer f.deinit(arena);
    const dirs = [_][]const u8{f.dir};

    const got = try assemble(arena, f.io, &dirs, "", false, "Summarize:", "line one\nline two\n");
    const r = try sigils(arena, got);

    // Prose is not context, so the fallback still applies.
    try testing.expectEqual(@as(usize, 2), r.len);
    try testing.expectEqualStrings("=/last", r[0].value);
    // One 🙋, the prompt as a preamble to what was piped.
    try testing.expectEqualStrings("Summarize:\nline one\nline two", r[1].content.?);

    // With no prompt it is the piped text alone.
    const bare = try assemble(arena, f.io, &dirs, "", false, "", "just this\n");
    try testing.expectEqualStrings("just this", (try sigils(arena, bare))[1].content.?);
}

test "a document that opens right and then goes wrong is an error, not a prompt" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-assembly-malformed");
    defer f.deinit(arena);
    const dirs = [_][]const u8{f.dir};

    // Detection is the first line alone. This one is a document, and a broken
    // one, so it is refused rather than quietly sent as something to say.
    try testing.expectError(error.UnknownSigil, assemble(
        arena,
        f.io,
        &dirs,
        "",
        false,
        "",
        "#### :brain:/local/tiny\n\n#### :nosuchsigil:\n",
    ));
}

test "a name that was typed is checked here, before it becomes an ordinary 🧠" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-assembly-naming");
    defer f.deinit(arena);
    const dirs = [_][]const u8{f.dir};

    // Nothing by these names, and none carries the mark, so every one of them
    // is an agent that is not there.
    for ([_][]const u8{ "nosuch", "+/nosuch", "=/nosuch", "team/nosuch" }) |n|
        try testing.expectError(
            error.UnknownAgent,
            assemble(arena, f.io, &dirs, n, true, "hi", ""),
        );

    // A marked name is a model, which is not m8's to know about: it passes
    // through as the 🧠 it is and the provider answers for it.
    const marked = try assemble(arena, f.io, &dirs, "/local/tiny", true, "hi", "");
    try testing.expectEqualStrings("/local/tiny", (try sigils(arena, marked))[0].value);

    // The fallback is checked the same way: with no last chat to continue,
    // a bare `m8 -- ...` says so rather than inventing one.
    const bare = try std.fs.path.join(arena, &.{ f.dir, "empty" });
    try std.Io.Dir.cwd().createDirPath(f.io, bare);
    try testing.expectError(
        error.UnknownAgent,
        assemble(arena, f.io, &.{bare}, "", false, "hi", ""),
    );
}
