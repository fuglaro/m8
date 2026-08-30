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

const std = @import("std");
pub const api = @import("command/api.zig");
pub const Command = api.Command;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;
pub const Takes = api.Takes;

/// What a bare `m8` runs, and what a name with no command after it gets.
pub const consult = @import("command/consult.zig").name;

pub const all = [_]Command{
    @import("command/consult.zig").command,
    @import("command/cat.zig").command,
    @import("command/encode.zig").command,
    @import("command/decode.zig").command,
    @import("command/parse.zig").command,
    @import("command/send.zig").command,
    @import("command/call.zig").command,
    @import("command/providers.zig").command,
};

/// Inbuilt tools. Reached as `m8 call NAME`, never typed as a command.
pub const native = [_]Command{
    @import("command/ask.zig").command,
};

pub fn find(name: []const u8) ?Command {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
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
