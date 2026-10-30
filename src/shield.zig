//! Shields turn activations into command prefixes. Each wrapper receives one
//! names argument followed by the command it wraps. Bare activations use the
//! shield's identity; explicit names replace that default and accumulate across
//! activations. Each shield runs once, at its first activation's position.

const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("api.zig");
const doc = @import("m8/doc.zig");
const sigil = @import("m8/sigil.zig");
const markdown = @import("m8/markdown.zig");
const Mode = sigil.Mode;

pub const Error = error{
    /// An activation named a shield nothing defines.
    UnknownShield,
    /// A code block named a runner that is not defined above it.
    UnknownRunner,
    /// A runner was defined twice. There is no reading of that which is
    /// clearer than saying so.
    RunnerRedefined,
    /// A shield composes one that leads back to it.
    ShieldLoops,
    /// A shield name runs more than one command, whether defined twice or
    /// with two in its body. Each would ask as the same name and read the
    /// other's answers, so two of a kind are two names.
    ShieldRunsTwice,
    /// A definition that contributes no command at all.
    EmptyShield,
};

/// A shield's identity and the names contributed to its wrapper.
pub const Activation = struct {
    name: []const u8,
    names: []const []const u8 = &.{},
};

/// One thing a definition contributes: a wrapper of its own, or another
/// shield to stand inside.
pub const Step = union(enum) {
    command: []const []const u8,
    compose: Activation,
};

pub const Definition = struct {
    name: []const u8,
    steps: []const Step = &.{},
};

/// An argv the code block is appended to, as a shebang's interpreter is
/// handed its script, which is how a code block becomes something runnable
/// without m8 knowing a single scripting language.
pub const Runner = struct {
    name: []const u8,
    argv: []const []const u8,
};

/// The wrappers, outermost first.
pub const Resolved = struct {
    wrappers: []const []const []const u8 = &.{},
};

/// What a document declared, and what it turned on.
pub const Set = struct {
    defs: []const Definition = &.{},
    runners: []const Runner = &.{},
    active: []const Activation = &.{},
};

/// The 🛡 and 🏃 in a document, in the order they were written.
pub fn project(
    arena: Allocator,
    mode: Mode,
    records: []const doc.Record,
) (Error || Allocator.Error)!Set {
    var defs: std.ArrayList(Definition) = .empty;
    var runners: std.ArrayList(Runner) = .empty;
    var active: std.ArrayList(Activation) = .empty;

    for (records) |r| switch (r.sigil) {
        // Named by a code block's language, so it has to be in hand before one
        // is read. Redefining is refused rather than resolved: there is no
        // reading of a second one that is clearer than saying so.
        .runner => {
            for (runners.items) |had| if (std.mem.eql(u8, had.name, r.value))
                return Error.RunnerRedefined;
            const argv = (try inlineArgv(arena, r.content orelse "")) orelse
                return Error.EmptyShield;
            try runners.append(arena, .{ .name = r.value, .argv = argv });
        },
        // With a block it defines, with a value alone it activates. Both only
        // ever add, so neither is the one that could loosen something.
        .shield => if (r.content) |content| {
            try defs.append(arena, .{
                .name = (try parseValue(arena, r.value)).name,
                .steps = try parseBody(arena, mode, content, runners.items),
            });
        } else {
            try active.append(arena, try parseValue(arena, r.value));
        },
        else => {},
    };

    return .{ .defs = defs.items, .runners = runners.items, .active = active.items };
}

/// `SHIELD [NAMES...]`. Names are joined into one argument at resolution time.
pub fn parseValue(arena: Allocator, value: []const u8) Allocator.Error!Activation {
    var it = std.mem.tokenizeAny(u8, value, " \t");
    const name = it.next() orelse return .{ .name = "" };
    var names: std.ArrayList([]const u8) = .empty;
    while (it.next()) |n| try names.append(arena, n);
    return .{ .name = name, .names = names.items };
}

/// The code spans on a line, as an argv. Null when there are none, which is
/// how a line that is prose rather than a command is told apart.
pub fn inlineArgv(arena: Allocator, line: []const u8) Allocator.Error!?[]const []const u8 {
    const out = try markdown.spans(arena, line);
    return if (out.len == 0) null else out;
}

pub const Fence = markdown.Fence;

/// Parse the content of a 🛡 that carried one.
///
/// Three kinds of line, and a body may mix them: a 🛡 reference composes,
/// a fenced block runs through the runner its language names, and anything
/// with backticks in it is a command spelled out.
pub fn parseBody(
    arena: Allocator,
    mode: Mode,
    content: []const u8,
    runners: []const Runner,
) (Error || Allocator.Error)![]const Step {
    var steps: std.ArrayList(Step) = .empty;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        if (sigil.match(mode, trimmed)) |m| {
            if (m.sigil != .shield) continue;
            try steps.append(arena, .{ .compose = try parseValue(arena, trimmed[m.len..]) });
            continue;
        }

        // A fenced block, run through whichever runner its language names.
        if (markdown.opensFence(line)) {
            const f = try markdown.readFence(arena, line, &lines);
            try steps.append(arena, .{ .command = try through(arena, runners, f) });
            continue;
        }

        if (try inlineArgv(arena, trimmed)) |argv|
            try steps.append(arena, .{ .command = argv });
    }

    if (steps.items.len == 0) return Error.EmptyShield;
    return steps.items;
}

/// A fenced block as something runnable: the 🏃 its language names, with the
/// code appended.
///
/// A block naming a runner that is not defined above it is refused rather than
/// run bare. Not knowing how something should be launched is never a reason to
/// launch it some other way.
pub fn through(
    arena: Allocator,
    runners: []const Runner,
    f: Fence,
) (Error || Allocator.Error)![]const []const u8 {
    const runner = for (runners) |r| {
        if (std.mem.eql(u8, r.name, f.runner)) break r;
    } else return Error.UnknownRunner;
    const argv = try arena.alloc([]const u8, runner.argv.len + 1);
    @memcpy(argv[0..runner.argv.len], runner.argv);
    argv[runner.argv.len] = f.code;
    return argv;
}

/// Flatten activations, then attach the collected names to each wrapper.
/// Wrappers stay at their first activation's position, outermost first.
pub fn resolve(
    arena: Allocator,
    defs: []const Definition,
    active: []const Activation,
) (Error || Allocator.Error)!Resolved {
    var wrappers: std.ArrayList(Pending) = .empty;
    var path: std.ArrayList([]const u8) = .empty;
    var stood: std.ArrayList(Collected) = .empty;

    for (active) |a| try one(arena, defs, a, &wrappers, &path, &stood);
    var out: std.ArrayList([]const []const u8) = .empty;
    for (wrappers.items) |w| {
        const collected = stood.items[w.shield];
        const told = try arena.alloc([]const u8, w.argv.len + 1);
        @memcpy(told[0..w.argv.len], w.argv);
        told[w.argv.len] = if (collected.names.items.len > 0)
            try std.mem.join(arena, " ", collected.names.items)
        else
            try api.component(arena, collected.name);
        try out.append(arena, told);
    }
    return .{ .wrappers = out.items };
}

const Pending = struct {
    argv: []const []const u8,
    shield: usize,
};

const Collected = struct {
    name: []const u8,
    names: std.ArrayList([]const u8) = .empty,
};

fn one(
    arena: Allocator,
    defs: []const Definition,
    a: Activation,
    wrappers: *std.ArrayList(Pending),
    path: *std.ArrayList([]const u8),
    stood: *std.ArrayList(Collected),
) (Error || Allocator.Error)!void {
    for (path.items) |seen| if (std.mem.eql(u8, seen, a.name)) return Error.ShieldLoops;

    // A repeat contributes names, but does not run or expand the shield again.
    for (stood.items) |*had| if (std.mem.eql(u8, had.name, a.name)) {
        try had.names.appendSlice(arena, a.names);
        return;
    };
    const index = stood.items.len;
    var collected: Collected = .{ .name = a.name };
    try collected.names.appendSlice(arena, a.names);
    try stood.append(arena, collected);

    var found = false;
    var ran = false;
    try path.append(arena, a.name);
    for (defs) |d| {
        if (!std.mem.eql(u8, d.name, a.name)) continue;
        found = true;
        for (d.steps) |s| switch (s) {
            .command => |argv| {
                if (ran) return Error.ShieldRunsTwice;
                ran = true;
                try wrappers.append(arena, .{ .argv = argv, .shield = index });
            },
            .compose => |inner| try one(arena, defs, inner, wrappers, path, stood),
        };
    }
    path.items.len -= 1;

    if (!found) return Error.UnknownShield;
}

/// The command a tool actually runs: every wrapper, outermost first, and the
/// tool's own argv suffixed as arguments to all of them.
///
/// A command opening with `m8` means the m8 that is running, not whichever one
/// is on a PATH or none at all — the same rule a provider's command follows,
/// and the reason a shield written as an m8 command works on a machine where
/// nothing has been installed. The tool's own command follows the same rule.
/// Everything else is opaque; a script reaches this path as `$M8` in its
/// environment rather than by having its source rewritten.
pub fn wrap(
    arena: Allocator,
    wrappers: []const []const []const u8,
    argv: []const []const u8,
    self: []const u8,
) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (wrappers) |w| try own(arena, &out, w, self);
    // What a call said reaches the tool in its environment, never in these
    // words, so the only m8 named here is one the definition wrote.
    try own(arena, &out, argv, self);
    return out.items;
}

/// One command's words, resolving only its executable position.
fn own(arena: Allocator, out: *std.ArrayList([]const u8), words: []const []const u8, self: []const u8) Allocator.Error!void {
    for (words, 0..) |word, i|
        try out.append(arena, if (i == 0 and std.mem.eql(u8, word, "m8")) self else word);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a line of inline code is an argv, and prose is not" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const argv = (try inlineArgv(arena, "`bash` `-euo` `pipefail` `-c` `\"$0\" \"$@\" | m8 cat --pack`")).?;
    try testing.expectEqual(@as(usize, 5), argv.len);
    try testing.expectEqualStrings("bash", argv[0]);
    try testing.expectEqualStrings("\"$0\" \"$@\" | m8 cat --pack", argv[4]);

    try testing.expect((try inlineArgv(arena, "just some words")) == null);
}

test "a code block runs through the runner its language names" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const runners = [_]Runner{.{
        .name = "bash",
        .argv = &.{ "m8", "call", "bash", "-c" },
    }};
    const steps = try parseBody(arena, .md, "```bash\nexec m8 ask-shield \"$0\" \"$@\"\n```", &runners);
    try testing.expectEqual(@as(usize, 1), steps.len);
    // The code is appended, as a shebang's script is.
    const argv = steps[0].command;
    try testing.expectEqual(@as(usize, 5), argv.len);
    try testing.expectEqualStrings("exec m8 ask-shield \"$0\" \"$@\"", argv[4]);

    try testing.expectError(Error.UnknownRunner, parseBody(arena, .md, "```python\nx\n```", &runners));
    // The whole info string is the name, so a word after the language picks
    // another runner rather than being dropped.
    try testing.expectError(Error.UnknownRunner, parseBody(arena, .md, "```bash raw\nx\n```", &runners));
    const both = [_]Runner{ runners[0], .{ .name = "bash raw", .argv = &.{ "bash", "-c" } } };
    const raw = try parseBody(arena, .md, "```bash raw\nexec \"$@\"\n```", &both);
    try testing.expectEqualStrings("bash", raw[0].command[0]);
    try testing.expectEqualStrings("exec \"$@\"", raw[0].command[2]);
    try testing.expectError(Error.EmptyShield, parseBody(arena, .md, "nothing runnable here", &runners));
}

test "a wrapper is told the name it stands as, before what it wraps" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const all = [_]Definition{
        .{ .name = "guard", .steps = &.{.{ .command = &.{ "yours", "-x" } }} },
        .{ .name = "odd name", .steps = &.{.{ .command = &.{"odd"} }} },
        // Standing as another shield is standing under that one's name.
        .{ .name = "alias", .steps = &.{.{ .compose = .{ .name = "odd name" } }} },
    };
    const got = try resolve(arena, &all, &.{ .{ .name = "guard" }, .{ .name = "alias" } });
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
    // After the author's own words, so the command is all that follows.
    try testing.expectEqualStrings("guard", got.wrappers[0][2]);
    // Made safe to be a folder's name, which is what it becomes.
    try testing.expectEqualStrings("odd_name", got.wrappers[1][1]);

    const full = try wrap(arena, got.wrappers, &.{ "grep", "x" }, "/opt/m8");
    try expectArgv(full, &.{ "yours", "-x", "guard", "odd", "odd_name", "grep", "x" });
}

fn expectArgv(got: []const []const u8, want: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "a name runs one command, so a second is refused rather than replacing it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // What a mob you have not read might do: define `guard` again. Nothing
    // runs, so it cannot loosen what it was given.
    const twice = [_]Definition{
        .{ .name = "guard", .steps = &.{.{ .command = &.{"yours"} }} },
        .{ .name = "guard", .steps = &.{.{ .command = &.{"theirs"} }} },
    };
    try testing.expectError(Error.ShieldRunsTwice, resolve(arena, &twice, &.{.{ .name = "guard" }}));

    const both = [_]Definition{
        .{ .name = "guard", .steps = &.{ .{ .command = &.{"yours"} }, .{ .command = &.{"theirs"} } } },
    };
    try testing.expectError(Error.ShieldRunsTwice, resolve(arena, &both, &.{.{ .name = "guard" }}));

    // Only when it stands: defined and never activated is nothing.
    _ = try resolve(arena, &twice, &.{});

    // A command beside the shields it stands inside is still one command.
    const mixed = [_]Definition{
        .{ .name = "inner", .steps = &.{.{ .command = &.{"inner"} }} },
        .{ .name = "guard", .steps = &.{ .{ .compose = .{ .name = "inner" } }, .{ .command = &.{"yours"} } } },
    };
    const got = try resolve(arena, &mixed, &.{.{ .name = "guard" }});
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
}

test "shields compose and contribute names to one wrapper" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const all = [_]Definition{
        .{ .name = "secure", .steps = &.{.{ .command = &.{ "m8", "secure-shield" } }} },
        .{ .name = "sandbox", .steps = &.{
            .{ .compose = .{ .name = "secure", .names = &.{ "private", "contain-writes" } } },
        } },
        .{ .name = "jail", .steps = &.{
            .{ .compose = .{ .name = "sandbox" } },
            .{ .compose = .{ .name = "secure", .names = &.{"airgap"} } },
        } },
    };

    const got = try resolve(arena, &all, &.{.{ .name = "jail" }});
    // `secure` is reached twice and stands once, told what both said.
    try testing.expectEqual(@as(usize, 1), got.wrappers.len);
    try expectArgv(got.wrappers[0], &.{ "m8", "secure-shield", "private contain-writes airgap" });
}

test "a shield that leads back to itself is a loop, and an unknown one is refused" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const looping = [_]Definition{
        .{ .name = "a", .steps = &.{.{ .compose = .{ .name = "b" } }} },
        .{ .name = "b", .steps = &.{.{ .compose = .{ .name = "a" } }} },
    };
    try testing.expectError(Error.ShieldLoops, resolve(arena, &looping, &.{.{ .name = "a" }}));

    // Nothing defines it, so there is no wrapper to stand inside. Refused
    // rather than quietly running unwrapped.
    try testing.expectError(Error.UnknownShield, resolve(arena, &.{}, &.{.{ .name = "nosuch" }}));
}

test "activation order is wrapping order, and a repeat stands where the first did" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const all = [_]Definition{
        .{ .name = "outer", .steps = &.{.{ .command = &.{"outer"} }} },
        .{ .name = "ask", .steps = &.{.{ .command = &.{"ask"} }} },
    };
    const got = try resolve(arena, &all, &.{
        .{ .name = "outer" },
        .{ .name = "ask" },
        .{ .name = "outer" },
    });
    // Activated first is furthest out; `ask` last would be innermost, which is
    // where it sees the bare command rather than a stack of prefixes.
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
    try testing.expectEqualStrings("outer", got.wrappers[0][0]);
    try testing.expectEqualStrings("ask", got.wrappers[1][0]);
}

test "an activation carries a shield identity and optional literal names" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bare = try parseValue(arena, "ask");
    try testing.expectEqualStrings("ask", bare.name);
    try testing.expectEqual(@as(usize, 0), bare.names.len);

    const with = try parseValue(arena, "secure  airgap\tno-writes");
    try testing.expectEqualStrings("secure", with.name);
    try expectArgv(with.names, &.{ "airgap", "no-writes" });
    const check = try parseValue(arena, "check crew/reviewer");
    try expectArgv(check.names, &.{"crew/reviewer"});
}

test "explicit names replace the default and later activations append without moving the wrapper" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const defs = [_]Definition{
        .{ .name = "secure", .steps = &.{.{ .command = &.{ "m8", "secure-shield" } }} },
        .{ .name = "ask", .steps = &.{.{ .command = &.{ "m8", "ask-shield" } }} },
    };
    const got = try resolve(arena, &defs, &.{
        .{ .name = "secure" },
        .{ .name = "ask" },
        .{ .name = "secure", .names = &.{"private"} },
        .{ .name = "secure" },
        .{ .name = "secure", .names = &.{ "airgap", "no-writes" } },
    });
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
    try expectArgv(got.wrappers[0], &.{ "m8", "secure-shield", "private airgap no-writes" });
    try expectArgv(got.wrappers[1], &.{ "m8", "ask-shield", "ask" });
    const full = try wrap(arena, got.wrappers, &.{ "echo", "hello" }, "/opt/m8");
    try expectArgv(full, &.{ "/opt/m8", "secure-shield", "private airgap no-writes", "/opt/m8", "ask-shield", "ask", "echo", "hello" });

    const check_defs = [_]Definition{.{ .name = "check", .steps = &.{.{ .command = &.{ "bash", "-c", "exec \"$@\"" } }} }};
    const check = try resolve(arena, &check_defs, &.{try parseValue(arena, "check crew/reviewer")});
    try testing.expectEqualStrings("crew/reviewer", check.wrappers[0][3]);
}

test "a wrapper opening with m8 reaches the m8 that is running" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const wrappers = [_][]const []const u8{
        &.{ "m8", "ask-shield", "ask" },
        // Only the first word, and only of a wrapper. An `m8` that is an
        // argument is somebody's argument.
        &.{ "bash", "-c", "m8 cat --pack | grep -v '^- :toolbox::' | m8 cat" },
    };
    const full = try wrap(arena, &wrappers, &.{ "m8", "call", "m8", "munge" }, "/opt/m8/bin/m8");
    try testing.expectEqualStrings("/opt/m8/bin/m8", full[0]);
    try testing.expectEqualStrings("bash", full[3]);
    try testing.expectEqualStrings("m8 cat --pack | grep -v '^- :toolbox::' | m8 cat", full[5]);
    // The tool's own command follows the same rule: its first word, and no
    // other.
    try testing.expectEqualStrings("/opt/m8/bin/m8", full[6]);
    try testing.expectEqualStrings("m8", full[8]);
}

test "a wrapper resolves m8 only in executable position" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const self = "/opt/m8/bin/m8";
    const script = "\"$0\" \"$@\" | \"$M8\" cat --pack | { grep -v '^- :toolbox::' || test \"$?\" -eq 1; } | \"$M8\" cat";
    const wrappers = [_][]const []const u8{
        &.{ "m8", "ask-shield", "ask" },
        &.{ "bash", "-c", script },
    };
    const got = try wrap(arena, &wrappers, &.{ "grep", "-r", "m8" }, self);

    try testing.expectEqualStrings(self, got[0]);
    try testing.expectEqualStrings("ask-shield", got[1]);
    try testing.expectEqualStrings("bash", got[3]);
    // Shell source and an m8 that is merely data are both opaque.
    try testing.expectEqualStrings(script, got[5]);
    try testing.expectEqualStrings("m8", got[8]);
}
