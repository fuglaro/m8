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
pub const api = @import("api.zig");
pub const Command = api.Command;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;
pub const Takes = api.Takes;

/// Every command there is, as the modules that hold them.
const every = .{
    @import("command/ref.zig"),
    @import("command/send.zig"),
    @import("command/tag.zig"),
    @import("command/query.zig"),
    @import("command/reset.zig"),
    @import("command/tail.zig"),
    @import("command/exclude.zig"),
    @import("command/render.zig"),
    @import("command/encode.zig"),
    @import("command/parse.zig"),
    @import("command/top.zig"),
    @import("command/call.zig"),
    @import("command/munge.zig"),
    @import("command/secure-shield.zig"),
    @import("command/ask-shield.zig"),
    @import("command/url-provider.zig"),
    @import("command/toy-provider.zig"),
    @import("command/models.zig"),
    @import("command/riff.zig"),
    @import("command/watch.zig"),
};

/// The commands this binary holds. `-Dsplit` names the ones built as programs
/// of their own instead, and a module left out here is never named again, so
/// it is not compiled into this one.
const modules = kept(every);

fn kept(comptime ms: anytype) []const type {
    comptime {
        // Each name is read against every word of the option.
        @setEvalBranchQuota(100_000);
        var out: []const type = &.{};
        for (ms) |m| {
            if (!apart(m.command.name)) out = out ++ &[_]type{m};
        }
        return out;
    }
}

fn apart(name: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, @import("build_options").split, ", ");
    while (it.next()) |word| if (std.mem.eql(u8, word, name)) return true;
    return false;
}

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

// --------------------------------------------------------------- programs

/// What a command is called as a program of its own: `m8-` and its name.
pub const prefix = "m8-";

/// The command a path reaches, for a binary that is only ever that one.
///
/// Comptime, and the whole of why a command built on its own is small: the
/// walk touches every module's name and returns one command, so one `run` is
/// referenced and the rest of the registry is names that cost nothing. It
/// reads every command there is, since the one asked for is by definition
/// not among the ones the launcher holds.
pub fn commandAt(comptime name: []const u8) ?Command {
    comptime {
        for (every) |m| if (std.mem.eql(u8, m.command.name, name)) return m.command;
        return null;
    }
}

/// The command a program name belongs to, for a binary working out which
/// command it was installed as.
pub fn byProgram(name: []const u8) ?Command {
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    return find(name[prefix.len..]);
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
    for (all) |c| try testing.expect(c.help != null);
}

test "no two commands share a name" {
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
}

test "a program name finds its command" {
    try testing.expectEqualStrings("munge", byProgram("m8-munge").?.name);
    try testing.expect(byProgram("munge") == null);
    try testing.expect(byProgram("m8-nosuch") == null);
    // Munge's operations belong to one command, not programs of their own.
    try testing.expect(byProgram("m8-read") == null);
}

test "a command built on its own is the one the registry holds" {
    try testing.expectEqualStrings("munge", comptime commandAt("munge").?.name);
    try testing.expect(comptime commandAt("nosuch") == null);
}

test "every command has a page, and it says which command it is" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // No HOME and no XDG, so anything that reads a config reads the copy
    // compiled in rather than whatever is on the machine running the tests.
    var env: std.process.Environ.Map = .init(arena);
    var thrown: std.Io.Writer.Allocating = .init(arena);

    for (all) |c| {
        var page_out: std.Io.Writer.Allocating = .init(arena);
        try c.help.?(.{
            .arena = arena,
            .io = threaded.io(),
            .mode = .md,
            .env = &env,
            .args = &.{},
            .in = "",
            .out = &page_out.writer,
            .err = &thrown.writer,
            .tty = null,
        }, &page_out.writer);

        const said = page_out.written();
        try testing.expect(said.len > 0);
        try testing.expect(std.mem.indexOf(u8, said, c.name) != null);
        // A page is prose for a person, not a document. It never opens like
        // one, or piping it somewhere would read as a ledger.
        try testing.expect(said[0] != '#');
    }
}

test "the commands are exactly the files in src/command" {
    // `build.zig` cannot walk a comptime registry, so it reads the folder: a
    // file directly in it is a command, named for it. This is where the two
    // are held to each other, so a command added in one and not the other is
    // a failing test rather than a program nobody can build.
    const files = @import("build_options").commands;

    var count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, files, ',');
    while (it.next()) |name| : (count += 1) {
        if (find(name) == null) {
            std.debug.print("src/command/{s}.zig is no command in the registry\n", .{name});
            return error.NotACommand;
        }
    }
    try testing.expectEqual(all.len, count);
}
