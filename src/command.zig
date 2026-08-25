//! The command registry. Adding a command means adding one line here.
//!
//! A command is what the CLI falls back to when the first word is not `@agent`,
//! `+chat` or `--`. Most are filters over an m8 stream; `call` is the one that
//! runs something else.
//!
//! "Tool" means 🧰 in the language, so these are commands. The ones that are
//! filters are also what `m8 call NAME` reaches, which is why there is one
//! table rather than two.

const std = @import("std");
pub const api = @import("command/api.zig");
pub const Command = api.Command;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;

pub const all = [_]Command{
    @import("command/call.zig").command,
    @import("command/cat.zig").command,
    @import("command/ask.zig").command,
};

pub fn find(name: []const u8) ?Command {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// The commands `m8 call NAME` may reach: everything but `call` itself.
pub fn findFilter(name: []const u8) ?Command {
    if (std.mem.eql(u8, name, "call")) return null;
    return find(name);
}
