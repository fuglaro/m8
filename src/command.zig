//! The command registry. Adding a command means adding one line here.
//!
//! Two kinds, told apart by what they take:
//!
//!   message  `[@AGENT|+CHAT] CMD [ARGS]` — handed the assembled ledger
//!   run      `CMD [ARGS]`                — handed stdin, or nothing at all
//!
//! `--` is a message command like any other. It is not punctuation separating
//! m8's arguments from yours; it is the name of the command whose arguments
//! are prose, which is why nothing has to arbitrate between the two.
//!
//! "Tool" means 🧰 in the language, so these are commands. `native` holds the
//! ones that exist only to be reached by `m8 call NAME` — inbuilt tools, with
//! no business on the command line of their own.
//!
//! The registry is written as modules rather than as command values, because
//! a module is what carries whatever is under it. From that, `tree` names
//! every command that could be a program of its own — which is how one
//! registry serves both the single binary and the split set without either
//! keeping a list the other could drift from.

const std = @import("std");
pub const api = @import("command/api.zig");
pub const Command = api.Command;
pub const Spec = api.Spec;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;
pub const Takes = api.Takes;

/// What a bare `m8` runs, and what a name with no command after it gets.
pub const consult = @import("command/consult.zig").name;

/// The commands, as the modules that hold them.
const modules = .{
    @import("command/consult.zig"),
    @import("command/cat.zig"),
    @import("command/encode.zig"),
    @import("command/decode.zig"),
    @import("command/parse.zig"),
    @import("command/send.zig"),
    @import("command/call.zig"),
    @import("command/shield.zig"),
    @import("command/filter.zig"),
    @import("command/providers.zig"),
    @import("command/help.zig"),
};

/// Inbuilt tools, as modules. Reached as `m8 call NAME`, never typed as a
/// command.
const native_modules = .{
    @import("command/args.zig"),
    @import("command/ask.zig"),
    @import("command/munge.zig"),
};

pub const all = commands(modules);
pub const native = commands(native_modules);

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

/// Every command there is, including the inbuilt tools. What `help` looks in,
/// because a page for something that exists is worth having wherever it is
/// reached from.
pub fn findAny(name: []const u8) ?Command {
    if (find(name)) |c| return c;
    for (native) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// Whether `m8 call NAME` may reach this one.
///
/// Not `call`, which would be a loop with nothing in it, and not `--`, whose
/// arguments are prose — a tool is handed a document, and there is no command
/// line out here for it to have taken a prompt from. Stated once, so what
/// `call` lists and what `call` accepts cannot drift apart.
pub fn callable(c: Command) bool {
    return c.takes != .nothing and !c.prompts;
}

/// What `m8 call NAME` may reach: every inbuilt tool, and every command that
/// is a filter over a document.
pub fn findCallable(name: []const u8) ?Command {
    for (native) |c| if (std.mem.eql(u8, c.name, name)) return c;
    const c = find(name) orelse return null;
    return if (callable(c)) c else null;
}

// ------------------------------------------------------------------ tree

/// One command, where it lives, and whatever lives under it.
///
/// A node is a *home*, not every way of reaching one. `m8 call cat` reaches
/// the command that already lives at the top, so `cat` is one program however
/// it is named; only the inbuilt tools, which have no command line of their
/// own, live under `call`.
///
/// Nothing in here is a function pointer. A launcher walks this to decide what
/// goes on a child's stdin and what to call it, and walking it links none of
/// the implementations.
pub const Node = struct {
    spec: Spec,
    /// The words that reach it, `m8` aside: `call`, `munge`, `read`.
    path: []const []const u8,
    /// What it is called as a program of its own. A name that already opens
    /// with `-` joins without a separator, so the command whose arguments are
    /// prose is `m8--` rather than `m8---`.
    program: []const u8,
    children: []const Node = &.{},
};

pub const tree: []const Node = nodes(modules, "m8", &.{});

/// `call`'s children are the inbuilt tools, which is the one place the tree
/// is not simply a module's own `subs`: they are declared here because here is
/// where "reached only through `call`" is said.
fn childrenOf(comptime m: type, comptime program: []const u8, comptime path: []const []const u8) []const Node {
    comptime {
        if (m == @import("command/call.zig")) return nodes(native_modules, program, path);
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
    return program ++ (if (name[0] == '-') name else "-" ++ name);
}

/// What `m8 call NAME` reaches, as a node.
///
/// The same rule as `findCallable` and read off the tree instead of the
/// commands, so a launcher that holds no command still knows what `call` may
/// reach and what to call it. An inbuilt tool lives under `call`; everything
/// else `call` reaches already has a home at the top, and is one program
/// however it is named.
pub fn callableNode(name: []const u8) ?Node {
    if (byPath(&.{ "call", name })) |n| return n;
    const n = byPath(&.{name}) orelse return null;
    return if (n.spec.takes != .nothing and !n.spec.prompts) n else null;
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
            // The inbuilt tools are under `call`, and nothing else is.
            if (m == @import("command/call.zig")) return among(native_modules, path[1..]);
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
    if (path.len == 1 and std.mem.eql(u8, path[0], "call")) return &native;
    const node = byPath(path) orelse return &.{};
    if (node.children.len == 0) return &.{};
    inline for (modules ++ native_modules) |m| {
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

test "a command is found by name, and call reaches the right ones" {
    try testing.expect(find("cat") != null);
    try testing.expect(find("call") != null);
    try testing.expect(find(consult) != null);
    try testing.expect(find("nosuch") == null);

    // An inbuilt tool is reachable only through `call`.
    try testing.expect(find("ask") == null);
    try testing.expect(findCallable("ask") != null);

    // `m8 call call` would be a loop with nothing in it, and `m8 call --`
    // would be a tool taking a prompt from a command line it never saw.
    try testing.expect(findCallable("call") == null);
    try testing.expect(findCallable(consult) == null);
    try testing.expect(findCallable("cat") != null);
    try testing.expect(findCallable("encode") != null);
}

test "what call lists is what call accepts" {
    // Both ask `callable`, so a command cannot come to be advertised by one
    // and refused by the other.
    for (all) |c| try testing.expectEqual(callable(c), findCallable(c.name) != null);
    for (native) |c| try testing.expect(findCallable(c.name) != null);
}

test "every command has a name and a summary" {
    for (all ++ native) |c| {
        try testing.expect(c.name.len > 0);
        try testing.expect(c.summary.len > 0);
        // Names are typed at a shell, so nothing that needs quoting.
        for (c.name) |ch| try testing.expect(std.ascii.isLower(ch) or ch == '-');
    }
}

test "every command has a page of its own" {
    // The fallback in `help` prints a summary, which is better than nothing
    // and is not good enough for a command that ships.
    for (all ++ native) |c| try testing.expect(c.help != null);
}

test "no two commands share a name" {
    const every = all ++ native;
    for (every, 0..) |a, i| for (every[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}

test "only a message command may be preceded by a name" {
    // A run command has no ledger for a name to go into.
    try testing.expect(find("call").?.takes.isMessage() == false);
    try testing.expect(find("decode").?.takes.isMessage() == false);
    for ([_][]const u8{ consult, "cat", "encode", "send" }) |n|
        try testing.expect(find(n).?.takes.isMessage());

    // Exactly one command's arguments are prose.
    var prompting: usize = 0;
    for (all) |c| if (c.prompts) {
        prompting += 1;
    };
    try testing.expectEqual(@as(usize, 1), prompting);
}

test "the tree names a program for every command" {
    // What the command line spells with spaces, a program spells with
    // hyphens — and a name that is already punctuation keeps its own.
    try testing.expectEqualStrings("m8-cat", byPath(&.{"cat"}).?.program);
    try testing.expectEqualStrings("m8--", byPath(&.{consult}).?.program);
    try testing.expectEqualStrings("m8-call-munge", byPath(&.{ "call", "munge" }).?.program);
    try testing.expectEqualStrings(
        "m8-call-munge-read",
        byPath(&.{ "call", "munge", "read" }).?.program,
    );

    // A tool reached through `call` that has a home at the top is one
    // program, not two: `m8 call cat` runs `m8-cat`.
    try testing.expect(byPath(&.{ "call", "cat" }) == null);

    // And back again, which is how a binary knows which command it is.
    try testing.expectEqualStrings("munge", byProgram("m8-call-munge").?.spec.name);
    try testing.expectEqualStrings(consult, byProgram("m8--").?.spec.name);
    try testing.expect(byProgram("m8-nosuch") == null);
}

test "a complaint names the path the words reached, not the top of it" {
    const a = testing.allocator;

    // The launcher calls `shield` and lets it read `ask`, so the words are
    // what says which of the two failed.
    const both_words = try named(a, &.{"shield"}, &.{ "ask", "--", "echo" });
    defer a.free(both_words);
    try testing.expectEqualStrings("shield ask", both_words);

    // As deep as the words go, and no deeper than a command.
    const deep = try named(a, &.{"call"}, &.{ "munge", "read", "x.md" });
    defer a.free(deep);
    try testing.expectEqualStrings("call munge read", deep);

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

test "what the tree names is what a split-out binary would run" {
    // The tree is read by a launcher and `commandAt` by the command's own
    // root. Two walks over one registry, so they are checked against each
    // other rather than trusted to stay in step.
    try testing.expectEqualStrings("munge", comptime commandAt(words("call munge")).?.name);
    try testing.expectEqualStrings("read", comptime commandAt(words("call munge read")).?.name);
    try testing.expectEqualStrings(consult, comptime commandAt(words(consult)).?.name);
    try testing.expect(comptime commandAt(words("call cat")) == null);
    try testing.expect(comptime commandAt(words("nosuch")) == null);
}

test "the runtime walk reaches what the comptime one does" {
    // The single binary answering to a program name and a split-out binary
    // being that command must land on the same one.
    try testing.expectEqualStrings("munge", at(&.{ "call", "munge" }).?.name);
    try testing.expectEqualStrings("read", at(&.{ "call", "munge", "read" }).?.name);
    try testing.expectEqualStrings(consult, at(&.{consult}).?.name);
    try testing.expect(at(&.{ "call", "cat" }) == null);
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

test "what call reaches is one rule, wherever it is read from" {
    // `findCallable` holds the commands and `callableNode` holds the tree.
    // Two readings of one rule, so they are checked against each other.
    for (all ++ native) |c| {
        const by_command = findCallable(c.name);
        const by_node = callableNode(c.name);
        try testing.expectEqual(by_command == null, by_node == null);
        if (by_node) |n| try testing.expectEqualStrings(c.name, n.spec.name);
    }
    try testing.expectEqualStrings("m8-cat", callableNode("cat").?.program);
    try testing.expectEqualStrings("m8-call-munge", callableNode("munge").?.program);
    try testing.expect(callableNode("call") == null);
    try testing.expect(callableNode(consult) == null);
}

test "the split set is exactly the tree" {
    // `build.zig` cannot walk a comptime tree, so it reads a list. This is
    // where that list is held to the registry: a command added here and not
    // there is a program nobody ships, and the other way round is a build
    // that fails at the far end for no stated reason.
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
