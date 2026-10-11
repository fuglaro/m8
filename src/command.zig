//! The command registry. Adding a command means adding one line here.
//!
//! Every command is `m8 CMD [ARGS]` with stdin, and resolves whatever it names
//! itself. `@` is not among them: it is launcher syntax, the pipeline of these
//! written once.
//!
//! The registry is written as modules rather than as command values, because
//! a module is what carries whatever is under it. From that, `tree` names
//! every command and its possible program path, which is how one registry
//! serves both builds without either keeping a list the other could drift from.

const std = @import("std");
pub const api = @import("command/api.zig");
pub const Command = api.Command;
pub const Spec = api.Spec;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;
pub const Takes = api.Takes;

/// The commands, as the modules that hold them.
const modules = .{
    @import("command/ref.zig"),
    @import("command/send.zig"),
    @import("command/tag.zig"),
    @import("command/query.zig"),
    @import("command/reset.zig"),
    @import("command/tail.zig"),
    @import("command/exclude.zig"),
    @import("command/render.zig"),
    @import("command/encode.zig"),
    @import("command/decode.zig"),
    @import("command/parse.zig"),
    @import("command/save.zig"),
    @import("command/top.zig"),
    @import("command/call.zig"),
    @import("command/munge.zig"),
    @import("command/shield.zig"),
    @import("command/providers.zig"),
    @import("command/riff.zig"),
};

pub const all = commands(modules);

fn commands(comptime ms: anytype) [ms.len]Command {
    comptime {
        var out: [ms.len]Command = undefined;
        for (ms, 0..) |m, i| out[i] = m.command;
        return out;
    }
}

pub fn find(name: []const u8) ?Command {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

// ------------------------------------------------------------------ tree

/// One command, where it lives, and whatever lives under it.
///
/// Nothing in here is a function pointer. A launcher walks this to decide what
/// goes on a child's stdin and what to call it, and walking it links none of
/// the implementations.
pub const Node = struct {
    spec: Spec,
    /// The words that reach it, `m8` aside: `call`, `munge`, `read`.
    path: []const []const u8,
    /// Its logical program spelling, hyphenated from the command path.
    program: []const u8,
    children: []const Node = &.{},
};

pub const tree: []const Node = nodes(modules, "m8", &.{});

fn childrenOf(comptime m: type, comptime program: []const u8, comptime path: []const []const u8) []const Node {
    comptime {
        if (!@hasDecl(m, "subs")) return &.{};
        var out: []const Node = &.{};
        for (m.subs) |s| out = out ++ &[_]Node{.{
            .spec = s.spec(),
            .path = path ++ &[_][]const u8{s.name},
            .program = joined(program, s.name),
        }};
        return out;
    }
}

fn nodes(comptime ms: anytype, comptime program: []const u8, comptime path: []const []const u8) []const Node {
    comptime {
        var out: []const Node = &.{};
        for (ms) |m| {
            const here = path ++ &[_][]const u8{m.command.name};
            const name = joined(program, m.command.name);
            out = out ++ &[_]Node{.{
                .spec = m.command.spec(),
                .path = here,
                .program = name,
                .children = childrenOf(m, name, here),
            }};
        }
        return out;
    }
}

fn joined(comptime program: []const u8, comptime name: []const u8) []const u8 {
    return program ++ "-" ++ name;
}

/// The command a path reaches, for a binary that is only ever that one.
///
/// Comptime, and the whole of why a split-out command is small: the walk
/// touches every module's name and returns one command, so one `run` is
/// referenced and the rest of the registry is names that cost nothing.
pub fn commandAt(comptime path: []const []const u8) ?Command {
    comptime return among(modules, path);
}

fn among(comptime ms: anytype, comptime path: []const []const u8) ?Command {
    comptime {
        if (path.len == 0) return null;
        for (ms) |m| {
            if (!std.mem.eql(u8, m.command.name, path[0])) continue;
            if (path.len == 1) return m.command;
            if (@hasDecl(m, "subs") and path.len == 2) {
                for (m.subs) |sub| if (std.mem.eql(u8, sub.name, path[1])) return sub;
            }
            return null;
        }
        return null;
    }
}

/// The same walk at runtime, for the single binary answering to a name it was
/// installed as. It reaches every command, which is what the single binary is.
pub fn at(path: []const []const u8) ?Command {
    if (path.len == 0) return null;
    var where: []const Command = &all;
    var found: ?Command = null;
    for (path, 0..) |word, depth| {
        found = for (where) |c| {
            if (std.mem.eql(u8, c.name, word)) break c;
        } else return null;
        where = childrenAt(path[0 .. depth + 1]);
    }
    return found;
}

/// What lives under a path, as commands. The tree already says what lives
/// where; this is the same shape with the implementations attached.
fn childrenAt(path: []const []const u8) []const Command {
    const node = byPath(path) orelse return &.{};
    if (node.children.len == 0) return &.{};
    inline for (modules) |m| {
        if (@hasDecl(m, "subs") and std.mem.eql(u8, m.command.name, path[path.len - 1]))
            return &m.subs;
    }
    return &.{};
}

/// A program's path, as the words a build option spells with spaces.
pub fn words(comptime spelling: []const u8) []const []const u8 {
    comptime {
        var out: []const []const u8 = &.{};
        var it = std.mem.splitScalar(u8, spelling, ' ');
        while (it.next()) |w| if (w.len > 0) {
            out = out ++ &[_][]const u8{w};
        };
        return out;
    }
}

/// The node a program name belongs to, for a binary working out which command
/// it was installed as.
pub fn byProgram(name: []const u8) ?Node {
    return search(tree, name);
}

fn search(where: []const Node, name: []const u8) ?Node {
    for (where) |n| {
        if (std.mem.eql(u8, n.program, name)) return n;
        if (search(n.children, name)) |found| return found;
    }
    return null;
}

/// The node reached by walking words from the top, for a launcher turning a
/// command line into a program.
pub fn byPath(path: []const []const u8) ?Node {
    var where = tree;
    var found: ?Node = null;
    for (path) |word| {
        found = for (where) |n| {
            if (std.mem.eql(u8, n.spec.name, word)) break n;
        } else return null;
        where = found.?.children;
    }
    return found;
}

/// What a command line names, as far as its words reach a command.
///
/// A launcher dispatches the command it reached and lets that command parse
/// the rest, so `shield ask` is reached as `shield` — but a complaint reads
/// better for naming the whole of what was typed, and walking the words to
/// the end of it here is the whole of the difference.
pub fn named(
    arena: std.mem.Allocator,
    path: []const []const u8,
    args: []const []const u8,
) ![]const u8 {
    var where = byPath(path) orelse return std.mem.join(arena, " ", path);
    for (args) |word| {
        var deeper: ?Node = null;
        for (where.children) |n| if (std.mem.eql(u8, n.spec.name, word)) {
            deeper = n;
            break;
        };
        where = deeper orelse break;
    }
    return std.mem.join(arena, " ", where.path);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a command is found by name" {
    try testing.expect(find("ref") != null);
    try testing.expect(find("call") != null);
    try testing.expect(find("munge") != null);
    try testing.expect(find("--") == null);
    try testing.expect(find("nosuch") == null);
}

test "every command has a name and a summary" {
    for (all) |c| {
        try testing.expect(c.name.len > 0);
        try testing.expect(c.summary.len > 0);
        // Names are typed at a shell, so nothing that needs quoting.
        for (c.name) |ch| try testing.expect(std.ascii.isLower(ch) or ch == '-');
    }
}

test "every command has a page of its own" {
    // The shared writer can fall back to a summary, which is better than
    // nothing and is not good enough for a command that ships.
    for (all) |c| try testing.expect(c.help != null);
}

test "no two commands share a name" {
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}

test "the tree gives every command a program spelling" {
    try testing.expectEqualStrings("m8-ref", byPath(&.{"ref"}).?.program);
    try testing.expectEqualStrings("m8-munge", byPath(&.{"munge"}).?.program);
    // Munge's operations belong to one command, not split programs.
    try testing.expect(byPath(&.{ "munge", "read" }) == null);

    // And back again, which is how a binary knows which command it is.
    try testing.expectEqualStrings("munge", byProgram("m8-munge").?.spec.name);
    try testing.expect(byProgram("m8-nosuch") == null);
}

test "a complaint names the path the words reached, not the top of it" {
    const a = testing.allocator;

    // The launcher calls `shield` and lets it read `ask`, so the words are
    // what says which of the two failed.
    const both_words = try named(a, &.{"shield"}, &.{ "ask", "--", "echo" });
    defer a.free(both_words);
    try testing.expectEqualStrings("shield ask", both_words);

    // A word that names nothing under it is the command's own argument.
    const top = try named(a, &.{"shield"}, &.{"bogus"});
    defer a.free(top);
    try testing.expectEqualStrings("shield", top);

    // And a command already reached by its whole path stays itself.
    const leaf_path = try named(a, &.{ "shield", "ask" }, &.{ "--", "echo" });
    defer a.free(leaf_path);
    try testing.expectEqualStrings("shield ask", leaf_path);
}

test "a program name is unique, and every node carries its own path" {
    var seen: std.ArrayList([]const u8) = .empty;
    defer seen.deinit(testing.allocator);
    try walk(tree, &seen);
}

fn walk(where: []const Node, seen: *std.ArrayList([]const u8)) !void {
    for (where) |n| {
        for (seen.items) |had| try testing.expect(!std.mem.eql(u8, had, n.program));
        try seen.append(testing.allocator, n.program);
        // The path is what a launcher hands on, so it has to reach the node.
        try testing.expectEqualStrings(n.spec.name, byPath(n.path).?.spec.name);
        try walk(n.children, seen);
    }
}

test "what the tree names is what a command binary would run" {
    // The tree is read by a launcher and `commandAt` by a leaf's own root.
    // Two walks over one registry, so they are checked against each other
    // rather than trusted to stay in step.
    try testing.expectEqualStrings("munge", comptime commandAt(words("munge")).?.name);
    try testing.expect(comptime commandAt(words("munge read")) == null);
    try testing.expect(comptime commandAt(words("nosuch")) == null);
}

test "the runtime walk reaches what the comptime one does" {
    // The single binary answering to a program name and a split-out binary
    // being that command must land on the same one.
    try testing.expectEqualStrings("munge", at(&.{"munge"}).?.name);
    try testing.expect(at(&.{ "munge", "read" }) == null);
    try testing.expect(at(&.{"nosuch"}) == null);

    // Every node in the tree is reachable both ways, and is the same command.
    try both(tree);
}

fn both(where: []const Node) !void {
    for (where) |n| {
        try testing.expectEqualStrings(n.spec.name, at(n.path).?.name);
        try testing.expectEqual(n.spec.takes, at(n.path).?.takes);
        try both(n.children);
    }
}

test "the split set is exactly the tree" {
    // `build.zig` cannot walk a comptime tree, so it reads a list. This is
    // where that list is held to the registry: a command added here and not
    // there is a failing test rather than a program nobody ships, and the
    // other way round is a build that fails for no stated reason.
    const listed = @embedFile("commands.txt");

    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, listed, '\n');
    while (lines.next()) |line| {
        const path = std.mem.trim(u8, line, " \t\r");
        if (path.len == 0 or path[0] == '#') continue;
        count += 1;

        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(testing.allocator);
        var it = std.mem.splitScalar(u8, path, ' ');
        while (it.next()) |word| if (word.len > 0) try parts.append(testing.allocator, word);

        const node = byPath(parts.items) orelse {
            std.debug.print("commands.txt names '{s}', which the registry has not\n", .{path});
            return error.NotACommand;
        };
        // And what the build calls it is what the registry calls it.
        try testing.expect(std.mem.startsWith(u8, node.program, "m8"));
    }

    try testing.expectEqual(size(tree), count);
}

fn size(where: []const Node) usize {
    var n: usize = 0;
    for (where) |node| n += 1 + size(node.children);
    return n;
}
