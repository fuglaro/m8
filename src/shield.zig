//! Shields: the wrapper a tool runs inside.
//!
//! A shield is not a program that decides to restrict a tool. It is the
//! process the tool runs inside, so it holds exactly the tool's authority and
//! there is no operation available to it for restoring a capability its own
//! parent lacked. Widening is not declined here; it is unsayable. That is the
//! same argument the README makes for a provider inheriting whatever m8 is
//! already within, applied one level further down.
//!
//! Everything follows from it. Restriction is intersection, so the permitted
//! set is the same however the wrappers stack and a repeat means nothing. A
//! second definition of a name adds another wrapper rather than replacing one,
//! so a mob you have not read can tighten what it was given and can never
//! un-define it.
//!
//! With a block it is a definition; with a value alone it is an activation.
//! Activation order is wrapping order — earlier is further out — which decides
//! nothing about what is allowed and everything about what a person is shown.

const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("command/api.zig");
const doc = @import("m8/doc.zig");
const sigil = @import("m8/sigil.zig");
const config = @import("config.zig");
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
    /// A definition that contributes no command at all.
    EmptyShield,
};

/// The placeholder a runner puts a code block into.
pub const code_mark = "{{CODE}}";

/// Where the m8 that is running lives, handed to every shield.
///
/// A wrapper written as a code block cannot say `m8` and be understood — the
/// word is inside a script m8 does not read — so it is given the path instead
/// and writes `"$M8_SELF"`. Explicit, and it keeps m8 with no opinion about
/// the language the script is in.
pub const self_var = "M8_SELF";

/// Which shield, and what it appends to which environment variable.
pub const Activation = struct {
    name: []const u8,
    env_var: []const u8 = "",
    values: []const []const u8 = &.{},
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

/// An argv with `{{CODE}}` somewhere in it, which is how a code block becomes
/// something runnable without m8 knowing a single scripting language.
pub const Runner = struct {
    name: []const u8,
    argv: []const []const u8,
};

/// The wrappers, outermost first, and the environment they are handed.
pub const Resolved = struct {
    wrappers: []const []const []const u8 = &.{},
    env: []const api.EnvVar = &.{},
};

/// What a document declared, and what it turned on.
pub const Set = struct {
    defs: []const Definition = &.{},
    runners: []const Runner = &.{},
    active: []const Activation = &.{},

    /// One set standing on another. `under` comes first, so what it defines is
    /// in hand before anything above it is read and what it turned on wraps
    /// further out.
    pub fn over(a: Set, arena: Allocator, under: Set) Allocator.Error!Set {
        return .{
            .defs = try std.mem.concat(arena, Definition, &.{ under.defs, a.defs }),
            .runners = try std.mem.concat(arena, Runner, &.{ under.runners, a.runners }),
            .active = try std.mem.concat(arena, Activation, &.{ under.active, a.active }),
        };
    }
};

/// The shields m8 ships with, or whichever `core/shields.md` overrides them.
///
/// They are written in the language rather than built in, so what `jail` means
/// is a composition anyone can read, override, or take apart — and the profile
/// underneath keeps only the restrictions it cannot express as composition.
pub const default = @embedFile("core/shields.md");

pub fn core(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !Set {
    const src = (try config.core(arena, io, env, "shields.md")) orelse default;
    var diag: doc.Diagnostic = .{};
    return project(arena, .md, try doc.parse(arena, src, &diag));
}

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

/// `NAME`, or `NAME VAR value...`. Space separated, so a value holds no space.
pub fn parseValue(arena: Allocator, value: []const u8) Allocator.Error!Activation {
    var it = std.mem.tokenizeAny(u8, value, " \t");
    const name = it.next() orelse return .{ .name = "" };
    const env_var = it.next() orelse return .{ .name = name };
    var values: std.ArrayList([]const u8) = .empty;
    while (it.next()) |v| try values.append(arena, v);
    return .{ .name = name, .env_var = env_var, .values = values.items };
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
/// code in place of `{{CODE}}`.
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
        if (std.mem.eql(u8, r.name, f.lang)) break r;
    } else return Error.UnknownRunner;
    return fill(arena, runner.argv, f.code);
}

/// A runner's argv with the code in place of `{{CODE}}`.
fn fill(arena: Allocator, argv: []const []const u8, code: []const u8) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (argv) |word| {
        try out.append(arena, if (std.mem.eql(u8, word, code_mark)) code else word);
    }
    return out.items;
}

/// Flatten activations into the wrappers they stand for.
///
/// Every definition of a name contributes, in the order they were met, since a
/// later one stacks a wrapper rather than replacing one. What comes back is
/// outermost first.
pub fn resolve(
    arena: Allocator,
    defs: []const Definition,
    active: []const Activation,
) (Error || Allocator.Error)!Resolved {
    var wrappers: std.ArrayList([]const []const u8) = .empty;
    var vars: std.ArrayList(api.EnvVar) = .empty;
    var path: std.ArrayList([]const u8) = .empty;

    for (active) |a| try one(arena, defs, a, &wrappers, &vars, &path);
    return .{ .wrappers = wrappers.items, .env = vars.items };
}

fn one(
    arena: Allocator,
    defs: []const Definition,
    a: Activation,
    wrappers: *std.ArrayList([]const []const u8),
    vars: *std.ArrayList(api.EnvVar),
    path: *std.ArrayList([]const u8),
) (Error || Allocator.Error)!void {
    for (path.items) |seen| if (std.mem.eql(u8, seen, a.name)) return Error.ShieldLoops;

    if (a.env_var.len > 0) try append(arena, vars, a.env_var, a.values);

    var found = false;
    try path.append(arena, a.name);
    for (defs) |d| {
        if (!std.mem.eql(u8, d.name, a.name)) continue;
        found = true;
        for (d.steps) |s| switch (s) {
            .command => |argv| try wrappers.append(arena, argv),
            .compose => |inner| try one(arena, defs, inner, wrappers, vars, path),
        };
    }
    path.items.len -= 1;

    if (!found) return Error.UnknownShield;
}

/// Values appended to a variable, space separated, in the order activated.
fn append(
    arena: Allocator,
    vars: *std.ArrayList(api.EnvVar),
    key: []const u8,
    values: []const []const u8,
) Allocator.Error!void {
    if (values.len == 0) return;
    const added = try std.mem.join(arena, " ", values);
    for (vars.items) |*v| if (std.mem.eql(u8, v.key, key)) {
        v.value = try std.fmt.allocPrint(arena, "{s} {s}", .{ v.value, added });
        return;
    };
    try vars.append(arena, .{ .key = key, .value = added });
}

/// The command a tool actually runs: every wrapper, outermost first, and the
/// tool's own argv suffixed as arguments to all of them.
///
/// A wrapper opening with `m8` means the m8 that is running, not whichever one
/// is on a PATH or none at all — the same rule a provider's command follows,
/// and the reason the shields m8 ships with work on a machine where nothing
/// has been installed.
pub fn wrap(
    arena: Allocator,
    wrappers: []const []const []const u8,
    argv: []const []const u8,
    self: []const u8,
) Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (wrappers) |w| for (w, 0..) |word, i| {
        try out.append(arena, if (i == 0 and std.mem.eql(u8, word, "m8")) self else word);
    };
    try out.appendSlice(arena, argv);
    return out.items;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a line of inline code is an argv, and prose is not" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const argv = (try inlineArgv(arena, "`bash` `-euo` `pipefail` `-c` `\"$0\" \"$@\" | m8 filter`")).?;
    try testing.expectEqual(@as(usize, 5), argv.len);
    try testing.expectEqualStrings("bash", argv[0]);
    try testing.expectEqualStrings("\"$0\" \"$@\" | m8 filter", argv[4]);

    try testing.expect((try inlineArgv(arena, "just some words")) == null);
}

test "a code block runs through the runner its language names" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const runners = [_]Runner{.{
        .name = "bash",
        .argv = &.{ "m8", "call", "bash", "-c", code_mark, "bash" },
    }};
    const steps = try parseBody(arena, .md, "```bash\nexec m8 shield ask -- \"$@\"\n```", &runners);
    try testing.expectEqual(@as(usize, 1), steps.len);
    const argv = steps[0].command;
    try testing.expectEqual(@as(usize, 6), argv.len);
    try testing.expectEqualStrings("exec m8 shield ask -- \"$@\"", argv[4]);
    // The argv0 placeholder is the author's, not m8's.
    try testing.expectEqualStrings("bash", argv[5]);

    try testing.expectError(Error.UnknownRunner, parseBody(arena, .md, "```python\nx\n```", &runners));
    try testing.expectError(Error.EmptyShield, parseBody(arena, .md, "nothing runnable here", &runners));
}

test "a second definition of a name stacks a wrapper and cannot replace one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // What a mob you have not read might do: define `guard` again. It adds.
    const all = [_]Definition{
        .{ .name = "guard", .steps = &.{.{ .command = &.{"yours"} }} },
        .{ .name = "guard", .steps = &.{.{ .command = &.{"theirs"} }} },
    };
    const got = try resolve(arena, &all, &.{.{ .name = "guard" }});
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
    try testing.expectEqualStrings("yours", got.wrappers[0][0]);
    try testing.expectEqualStrings("theirs", got.wrappers[1][0]);

    // Yours is still outermost, so theirs runs inside it.
    const full = try wrap(arena, got.wrappers, &.{ "grep", "-r", "x" }, "/opt/m8");
    try testing.expectEqual(@as(usize, 5), full.len);
    try testing.expectEqualStrings("yours", full[0]);
    try testing.expectEqualStrings("theirs", full[1]);
    try testing.expectEqualStrings("grep", full[2]);
}

test "shields compose, and what they append to a variable accumulates" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const all = [_]Definition{
        .{ .name = "secure", .steps = &.{.{ .command = &.{ "m8", "shield", "secure" } }} },
        .{ .name = "sandbox", .steps = &.{
            .{ .compose = .{ .name = "secure", .env_var = "SECURES", .values = &.{ "private", "contain-writes" } } },
        } },
        .{ .name = "jail", .steps = &.{
            .{ .compose = .{ .name = "sandbox" } },
            .{ .compose = .{ .name = "secure", .env_var = "SECURES", .values = &.{"airgap"} } },
        } },
    };

    const got = try resolve(arena, &all, &.{.{ .name = "jail" }});
    // `secure` is reached twice, so it wraps twice — which is a repeat, and a
    // repeat of something that only subtracts means nothing.
    try testing.expectEqual(@as(usize, 2), got.wrappers.len);
    try testing.expectEqual(@as(usize, 1), got.env.len);
    try testing.expectEqualStrings("SECURES", got.env[0].key);
    try testing.expectEqualStrings("private contain-writes airgap", got.env[0].value);
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

test "activation order is wrapping order, and a repeat changes nothing permitted" {
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
    try testing.expectEqual(@as(usize, 3), got.wrappers.len);
    try testing.expectEqualStrings("outer", got.wrappers[0][0]);
    try testing.expectEqualStrings("ask", got.wrappers[1][0]);
    try testing.expectEqualStrings("outer", got.wrappers[2][0]);
}

test "a value carries a name, and optionally a variable and what to append" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bare = try parseValue(arena, "ask");
    try testing.expectEqualStrings("ask", bare.name);
    try testing.expectEqual(@as(usize, 0), bare.values.len);

    const with = try parseValue(arena, "secure SECURES airgap no-writes");
    try testing.expectEqualStrings("secure", with.name);
    try testing.expectEqualStrings("SECURES", with.env_var);
    try testing.expectEqual(@as(usize, 2), with.values.len);
    try testing.expectEqualStrings("no-writes", with.values[1]);
}

test "a wrapper opening with m8 reaches the m8 that is running" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const wrappers = [_][]const []const u8{
        &.{ "m8", "shield", "ask", "--" },
        // Only the first word, and only of a wrapper. An `m8` that is an
        // argument is somebody's argument.
        &.{ "bash", "-c", "m8 filter out toolbox" },
    };
    const full = try wrap(arena, &wrappers, &.{"m8"}, "/opt/m8/bin/m8");
    try testing.expectEqualStrings("/opt/m8/bin/m8", full[0]);
    try testing.expectEqualStrings("bash", full[4]);
    try testing.expectEqualStrings("m8 filter out toolbox", full[6]);
    // The tool's own argv is untouched: it is not a wrapper.
    try testing.expectEqualStrings("m8", full[7]);
}

test "the shields m8 ships with parse, and jail is the composition it claims" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var diag: doc.Diagnostic = .{};
    const set = try project(arena, .md, try doc.parse(arena, default, &diag));

    // Nothing is turned on by shipping it. A default that activated itself
    // would be an opinion, and this file is meant to hold none.
    try testing.expectEqual(@as(usize, 0), set.active.len);

    const got = try resolve(arena, set.defs, &.{.{ .name = "jail" }});
    var secures: []const u8 = "";
    for (got.env) |v| if (std.mem.eql(u8, v.key, "SECURES")) {
        secures = v.value;
    };
    for ([_][]const u8{
        "private",     "contain-writes", "no-loop",
        "no-edit-git", "no-edit-m8-st8", "contain-env",
        "airgap",
    }) |want| {
        if (std.mem.indexOf(u8, secures, want) == null) {
            std.debug.print("jail is missing '{s}' (got '{s}')\n", .{ want, secures });
            return error.TestUnexpectedResult;
        }
    }

    // Every restriction it names is one the profile has a line for, so a
    // shipped level cannot ask for something `m8 shield secure` would refuse.
    const sandbox = @import("sandbox.zig");
    var it = std.mem.tokenizeAny(u8, secures, " ");
    while (it.next()) |name| try testing.expect(sandbox.find(name) != null);

    // And jail closes the definition channel, which sandbox composes.
    try testing.expect(got.wrappers.len > 6);
}
