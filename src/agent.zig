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
const config = @import("config.zig");
const model = @import("m8/model.zig");
const toolbox = @import("toolbox.zig");
const api = @import("api.zig");
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
    dirs: config.Dirs,
    name: []const u8,
) LoadError!Definition {
    const l = try ledger.expand(arena, io, dirs, name);
    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, try ledger.inheritedAgent(arena, io, dirs));
    try records.appendSlice(arena, l.records);
    var def = try project(arena, records.items);
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
    const ToolVar = struct { name: []const u8, value: api.EnvVar };
    var tool_vars: std.ArrayList(ToolVar) = .empty;

    for (records) |r| switch (r.sigil) {
        // Every 🧠 that named an agent was replaced by what it named, so
        // whatever is left is in the model form. The last model wins, as an
        // agent names its own model after one it includes.
        .agent => {
            if (try model.parse(arena, r.value)) |m| {
                def.provider = m.provider;
                def.model = m.name;
                def.params = m.params;
            }
        },

        // A ledger's nested content is canonically the file spelling. A block
        // defines a tool; a blockless header with a variable and values adds
        // definition configuration; a bare blockless header offers it. The
        // three forms stay separate, while all carry the same tool name.
        .tool => {
            const parsed = try toolbox.parse(arena, .md, r.value, r.content orelse "");
            if (r.content != null) {
                if (parsed.env_var.len > 0) return toolbox.Error.VariableOnDefinition;
                var merged = false;
                for (tools.items) |*old| if (std.mem.eql(u8, old.name, parsed.name)) {
                    try mergeTool(arena, old, parsed);
                    merged = true;
                    break;
                };
                if (!merged) try tools.append(arena, parsed);
            } else if (parsed.env_var.len > 0) {
                try tool_vars.append(arena, .{ .name = parsed.name, .value = .{
                    .key = parsed.env_var,
                    .value = try std.mem.join(arena, " ", parsed.env_values),
                } });
            } else {
                try add(arena, &allowed, parsed.name);
            }
        },

        else => {},
    };

    for (tool_vars.items) |tv| for (tools.items) |*tool| {
        if (!std.mem.eql(u8, tool.name, tv.name)) continue;
        var values: std.ArrayList(api.EnvVar) = .empty;
        try values.appendSlice(arena, tool.env_vars);
        try values.append(arena, tv.value);
        tool.env_vars = values.items;
    };
    def.tools = tools.items;
    def.allowed = allowed.items;
    const set = try shield.project(arena, .md, records);
    def.shields = set.defs;
    def.active = set.active;
    def.runners = set.runners;
    return def;
}

/// Merge one definition occurrence. Executable/schema ownership is unique;
/// repeated imports are harmless only when they repeat the same owner. The
/// tool description and shields are intentionally additive.
fn mergeTool(arena: Allocator, old: *toolbox.Tool, next: toolbox.Tool) !void {
    if (next.command == .none and next.properties.len > 0)
        return toolbox.Error.PropertyWithoutCommand;
    if (next.command != .none) {
        if (old.command == .none) {
            old.command = next.command;
            old.properties = next.properties;
        } else if (!sameCommand(old.command, next.command) or
            !try sameProperties(arena, old.properties, next.properties))
        {
            return toolbox.Error.ConflictingDefinition;
        }
    }
    if (next.description.len > 0) {
        old.description = if (old.description.len == 0)
            next.description
        else if (std.mem.endsWith(u8, old.description, "\n"))
            try std.mem.concat(arena, u8, &.{ old.description, next.description })
        else
            try std.mem.concat(arena, u8, &.{ old.description, "\n", next.description });
    }
    if (next.shields.len > 0) {
        var shields: std.ArrayList(shield.Activation) = .empty;
        try shields.appendSlice(arena, old.shields);
        try shields.appendSlice(arena, next.shields);
        old.shields = shields.items;
    }
}

fn sameCommand(a: toolbox.Command, b: toolbox.Command) bool {
    return switch (a) {
        .none => b == .none,
        .argv => |aa| switch (b) {
            .argv => |bb| aa.len == bb.len and for (aa, bb) |x, y| {
                if (!std.mem.eql(u8, x, y)) break false;
            } else true,
            else => false,
        },
        .block => |aa| switch (b) {
            .block => |bb| std.mem.eql(u8, aa.runner, bb.runner) and std.mem.eql(u8, aa.code, bb.code),
            else => false,
        },
    };
}

fn sameProperties(arena: Allocator, a: []const toolbox.Property, b: []const toolbox.Property) !bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (!std.mem.eql(u8, x.name, y.name) or !std.mem.eql(u8, x.type, y.type) or
            !std.mem.eql(u8, x.description, y.description) or x.required != y.required or x.extras.len != y.extras.len)
            return false;
        for (x.extras, y.extras) |xe, ye| {
            if (!std.mem.eql(u8, xe.key, ye.key)) return false;
            const xv = try std.json.Stringify.valueAlloc(arena, xe.value, .{});
            const yv = try std.json.Stringify.valueAlloc(arena, ye.value, .{});
            if (!std.mem.eql(u8, xv, yv)) return false;
        }
    }
    return true;
}

/// The tools this agent may use: named by a blockless 🧰. Definitions have
/// one command/schema owner; descriptions and shields compose across includes.
pub fn offer(arena: Allocator, def: Definition) ![]const toolbox.Tool {
    var out: std.ArrayList(toolbox.Tool) = .empty;
    for (def.allowed) |name| {
        var found: ?toolbox.Tool = null;
        for (def.tools) |t| if (t.command != .none and std.mem.eql(u8, t.name, name)) {
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

    fn coreAgent(f: Fixture, gpa: Allocator, root: []const u8, body: []const u8) !void {
        const dir = try std.fs.path.join(gpa, &.{ root, "core" });
        try std.Io.Dir.cwd().createDirPath(f.io, dir);
        try std.Io.Dir.cwd().writeFile(f.io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ dir, "agents.md" }),
            .data = body,
        });
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
    try f.agent(arena, "test/mathy.md",
        \\* :brain::/local/tiny
        \\
        \\* :shield::jail
        \\
        \\* :toolbox::say
        \\  > `echo` `{{text|}}`
        \\  > * `text` **string**
        \\  > > Echoes.
        \\
        \\* :toolbox::say
        \\
        \\* :compass::
        \\  > Be brief.
    );

    const dirs = [_][]const u8{f.dir};
    const d = try load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/mathy");
    try testing.expectEqualStrings("local", d.provider);
    try testing.expectEqualStrings("tiny", d.model);
    try testing.expectEqualStrings("test/mathy", d.origin);
    try testing.expect(hasShield(d, "jail"));
    try testing.expectEqual(@as(usize, 1), d.tools.len);
    try testing.expectEqualStrings("say", d.tools[0].name);
    try testing.expectEqual(@as(usize, 1), (try offer(arena, d)).len);
}

test "tool variables use separate headers and accumulate" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-tool-vars");
    defer f.deinit(arena);
    try f.agent(arena, "test/pagey.md",
        \\* :brain::/local/tiny
        \\
        \\* :toolbox::read
        \\  > `read`
        \\
        \\* :toolbox::read PAGE_LINES 100
        \\
        \\* :toolbox::read PAGE_BYTES 10000
        \\
        \\* :toolbox::read BYTE_CAP 20000
        \\
        \\* :toolbox::read
    );

    const d = try load(arena, f.io, config.Dirs{ .roots = &.{f.dir} }, "test/pagey");
    const offered = try offer(arena, d);
    try testing.expectEqual(@as(usize, 1), offered.len);
    try testing.expectEqual(@as(usize, 3), offered[0].env_vars.len);
    try testing.expectEqualStrings("__PAGE_LINES__", offered[0].env_vars[0].key);
    try testing.expectEqualStrings("100", offered[0].env_vars[0].value);
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
    try f.agent(arena, "test/helper.md", "* :brain::/local/tiny\n\n* :shield::airgap\n");
    try f.agent(arena, "test/outer.md",
        \\* :brain::/local/tiny
        \\
        \\* :shield::no-edit-git
        \\
        \\* :brain::test/helper
    );

    const dirs = [_][]const u8{f.dir};
    const d = try load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer");
    try testing.expect(hasShield(d, "no-edit-git"));
    try testing.expect(hasShield(d, "airgap"));
    // Activation order is wrapping order, and the outer one is further out.
    try testing.expectEqualStrings("no-edit-git", d.active[0].name);
    try testing.expectEqualStrings("airgap", d.active[1].name);
}

test "a conflicting tool command definition is an error" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-override");
    defer f.deinit(arena);
    try f.agent(arena, "test/base.md",
        \\* :brain::/local/tiny
        \\
        \\* :toolbox::say
        \\  > `echo` `base`
        \\
        \\* :toolbox::say
    );
    try f.agent(arena, "test/outer.md",
        \\* :brain::test/base
        \\
        \\* :toolbox::say
        \\  > `echo` `outer`
    );

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(toolbox.Error.ConflictingDefinition, load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer"));
}

test "identical imported tool owners are idempotent while descriptions accumulate" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-tool-compose");
    defer f.deinit(arena);
    try f.agent(arena, "test/base.md",
        \\* :brain::/local/tiny
        \\
        \\* :toolbox::say
        \\  > `echo` `base`
        \\  > > Base description.
    );
    try f.agent(arena, "test/outer.md",
        \\* :brain::test/base
        \\
        \\* :brain::test/base
        \\
        \\* :toolbox::say
        \\  > > Additional description.
    );

    const dirs = [_][]const u8{f.dir};
    const def = try load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/outer");
    try testing.expectEqual(@as(usize, 1), def.tools.len);
    try testing.expectEqualStrings("Base description.\nBase description.\nAdditional description.", def.tools[0].description);
    try testing.expectEqualStrings("base", def.tools[0].command.argv[1]);
}

test "an offered tool without a command owner is not offered to the model" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-description-only");
    defer f.deinit(arena);
    try f.agent(arena, "test/agent.md",
        \\* :brain::/local/tiny
        \\
        \\* :toolbox::not_ready
        \\  > > Its command is supplied by another include.
        \\
        \\* :toolbox::not_ready
    );

    const dirs = [_][]const u8{f.dir};
    const def = try load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/agent");
    try testing.expectEqual(@as(usize, 1), def.tools.len);
    try testing.expectEqual(@as(usize, 0), (try offer(arena, def)).len);
}

test "inherited core agent files prefix system, user and nearest project records" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-inherited");
    defer f.deinit(arena);
    const user = try std.fs.path.join(arena, &.{ f.dir, "user-root" });
    const system = try std.fs.path.join(arena, &.{ f.dir, "system-root" });
    try f.agent(arena, "test/agent.md", "* :brain::/local/tiny\n* :shield::agent\n");
    try f.coreAgent(arena, system, "* :shield::system\n");
    try f.coreAgent(arena, user, "* :shield::user\n");
    try f.coreAgent(arena, f.dir, "* :shield::project\n");

    const roots = [_][]const u8{ f.dir, user, system };
    const dirs: config.Dirs = .{ .roots = &roots, .user_root = user, .system_root = system };
    const def = try load(arena, f.io, dirs, "test/agent");
    try testing.expectEqual(@as(usize, 4), def.active.len);
    try testing.expectEqualStrings("system", def.active[0].name);
    try testing.expectEqualStrings("user", def.active[1].name);
    try testing.expectEqualStrings("project", def.active[2].name);
    try testing.expectEqualStrings("agent", def.active[3].name);
}

test "an unknown agent and a missing model are told apart" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const f = try Fixture.init(arena, &threaded, "m8-agent-errors");
    defer f.deinit(arena);
    try f.agent(arena, "test/bare.md", "* :compass::\n  > No model here.\n");

    const dirs = [_][]const u8{f.dir};
    try testing.expectError(ledger.Error.UnknownAgent, load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/nosuch"));
    try testing.expectError(Error.NoModel, load(arena, f.io, config.Dirs{ .roots = &dirs }, "test/bare"));
}
