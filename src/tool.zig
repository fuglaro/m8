//! The tool registry. Adding a tool means adding one line here.

const std = @import("std");
pub const api = @import("tool/api.zig");
pub const Tool = api.Tool;
pub const Ctx = api.Ctx;
pub const Tty = api.Tty;

pub const all = [_]Tool{
    @import("tool/cat.zig").tool,
    @import("tool/ask.zig").tool,
};

pub fn find(name: []const u8) ?Tool {
    for (all) |t| if (std.mem.eql(u8, t.name, name)) return t;
    return null;
}
