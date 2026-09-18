//! The few facts a request needs, taken from a ledger.
//!
//! This is a projection and nothing else. The ledger is the truth — every
//! record, in the order it was written — and a request needs less than that:
//! which model, which shields, which tools, and which of those the agent has
//! actually offered. Nothing here is ever written back.
//!
//! What a turn *said* is not in here. That belongs to the ledger, and to
//! whichever api encoding is about to reshape it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const ledger = @import("ledger.zig");
const model = @import("m8/model.zig");
const toolbox = @import("toolbox.zig");
const shield = @import("shield.zig");

pub const Error = error{ NoModel, NoProvider };

pub const LoadError = Error || ledger.ExpandError || shield.Error;

pub const Definition = struct {
    name: []const u8 = "",
    provider: []const u8 = "",
    model: []const u8 = "",
    /// The agent this conversation is with, from the walk that built the
    /// ledger. Empty when the whole chain was generated.
    origin: []const u8 = "",
    /// The model's parameters, in the api's own vocabulary. m8 translates
    /// none of them; they go out as written.
    params: []const model.Param = &.{},
    /// Every 🧰 that carried a block, in the order met. A later definition of
    /// a name wins, which is settled in `offer` rather than here.
    tools: []const toolbox.Tool = &.{},
    /// Every 🧰 that carried none, which names a tool to offer. A tool reaches
    /// the model only if it is named here.
    allowed: []const []const u8 = &.{},
    /// Every 🛡 that carried a block. Cumulative, because a shield is a
    /// wrapper: a second definition of a name stacks one, so including
    /// something can tighten and can never un-define.
    shields: []const shield.Definition = &.{},
    /// Every 🛡 that carried a value alone, in the order met. Activation order
    /// is wrapping order.
    active: []const shield.Activation = &.{},
    /// Every 🏃, which a code block's language names. Defined before use, so
    /// one forward pass is the whole of resolving them.
    runners: []const shield.Runner = &.{},
};

/// Read a ledger and project it.
pub fn load(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
) LoadError!Definition {
    const l = try ledger.expand(arena, io, dirs, name);
    var def = try project(arena, l.records);
    if (def.model.len == 0) return Error.NoModel;
    def.name = name;
    def.origin = l.origin;
    return def;
}

/// The facts, whatever the ledger happens to hold. A missing model is not an
/// error here: a ledger arriving on stdin may be handed one on the command
/// line instead, and only the caller knows whether that happened.
pub fn project(arena: Allocator, records: []const doc.Record) LoadError!Definition {
    var def: Definition = .{};
    var tools: std.ArrayList(toolbox.Tool) = .empty;
    var allowed: std.ArrayList([]const u8) = .empty;

    for (records) |r| switch (r.sigil) {
        // Every 🧠 that named an agent was replaced by what it named, so
        // whatever is left is in the model form. The first one wins, which is
        // also how an agent puts its own model in front of one it includes.
        .agent => if (def.model.len == 0) {
            if (try model.parse(arena, r.value)) |m| {
                def.provider = m.provider;
                def.model = m.name;
                def.params = m.params;
            }
        },

        // A ledger's nested content is canonically the file spelling. With a
        // block this defines a tool; with none it offers one, which is the
        // same split 🛡 has. The name is read the same way either way, so a
        // definition and the line that offers it are spelled alike.
        .tool => if (r.content) |content|
            try tools.append(arena, try toolbox.parse(arena, .md, r.value, content))
        else
            try add(arena, &allowed, (try toolbox.parse(arena, .md, r.value, "")).name),

        else => {},
    };

    def.tools = tools.items;
    def.allowed = allowed.items;
    const set = try shield.project(arena, .md, records);
    def.shields = set.defs;
    def.active = set.active;
    def.runners = set.runners;
    return def;
}

/// The tools this agent may use: named by a blockless 🧰, with the last
/// definition of a name winning, so an including agent can replace what it
/// pulled in.
pub fn offer(arena: Allocator, def: Definition) ![]const toolbox.Tool {
    var out: std.ArrayList(toolbox.Tool) = .empty;
    for (def.allowed) |name| {
        var found: ?toolbox.Tool = null;
        for (def.tools) |t| if (std.mem.eql(u8, t.name, name)) {
            found = t;
        };
        if (found) |t| try out.append(arena, t);
    }
    return out.items;
}

/// Union, not append. Order never matters and a repeat means nothing, so the
/// set stays the same however a lineage is arranged.
fn add(arena: Allocator, into: *std.ArrayList([]const u8), one: []const u8) !void {
    for (into.items) |have| if (std.mem.eql(u8, have, one)) return;
    try into.append(arena, one);
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

fn hasShield(d: Definition, name: []const u8) bool {
    for (d.active) |a| if (std.mem.eql(u8, a.name, name)) return true;
    return false;
}

test "a definition yields its model, shields and tools" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-basic");
    defer f.deinit(arena);
    try f.agent(arena, "mathy.md",
        \\#### :brain:/local/tiny
        \\
        \\#### :shield:jail
        \\
        \\#### :toolbox:say
        \\> `echo` `{{M8_ARG_TEXT|}}`
        \\> * text string
        \\> > Echoes.
        \\
        \\#### :toolbox:say
        \\
        \\#### :compass:
        \\> Be brief.
    );

    const dirs = [_][]const u8{f.dir};
    const d = try load(arena, f.io, &dirs, "mathy");
    try testing.expectEqualStrings("local", d.provider);
    try testing.expectEqualStrings("tiny", d.model);
    try testing.expectEqualStrings("mathy", d.origin);
    try testing.expect(hasShield(d, "jail"));
    try testing.expectEqual(@as(usize, 1), d.tools.len);
    try testing.expectEqualStrings("say", d.tools[0].name);
    try testing.expectEqual(@as(usize, 1), (try offer(arena, d)).len);
}

test "shields accumulate over the lineage, so including cannot widen" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-union");
    defer f.deinit(arena);
    // The included agent activates one and is named last, which is where an
    // override would put it if activation replaced rather than accumulated.
    try f.agent(arena, "helper.md", "#### :brain:/local/tiny\n\n#### :shield:airgap\n");
    try f.agent(arena, "outer.md",
        \\#### :brain:/local/tiny
        \\
        \\#### :shield:no-edit-git
        \\
        \\#### :brain:helper
    );

    const dirs = [_][]const u8{f.dir};
    const d = try load(arena, f.io, &dirs, "outer");
    try testing.expect(hasShield(d, "no-edit-git"));
    try testing.expect(hasShield(d, "airgap"));
    // Activation order is wrapping order, and the outer one is further out.
    try testing.expectEqualStrings("no-edit-git", d.active[0].name);
    try testing.expectEqualStrings("airgap", d.active[1].name);
}

test "a later definition of a tool name is the one offered" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-override");
    defer f.deinit(arena);
    try f.agent(arena, "base.md",
        \\#### :brain:/local/tiny
        \\
        \\#### :toolbox:say
        \\> `echo` `base`
        \\
        \\#### :toolbox:say
    );
    try f.agent(arena, "outer.md",
        \\#### :brain:base
        \\
        \\#### :toolbox:say
        \\> `echo` `outer`
    );

    const dirs = [_][]const u8{f.dir};
    const d = try load(arena, f.io, &dirs, "outer");
    const offered = try offer(arena, d);
    try testing.expectEqual(@as(usize, 1), offered.len);
    try testing.expectEqualStrings("outer", offered[0].command.argv[1]);
}

test "an unknown agent and a missing model are told apart" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-errors");
    defer f.deinit(arena);
    try f.agent(arena, "bare.md", "#### :compass:\n> No model here.\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(ledger.Error.UnknownAgent, load(arena, f.io, &dirs, "nosuch"));
    try testing.expectError(Error.NoModel, load(arena, f.io, &dirs, "bare"));
}
