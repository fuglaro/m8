//! The process-environment spelling of a logical tool argument.

const std = @import("std");

pub const all = "____";

/// Return the reserved environment name for a logical argument. Non-portable
/// names have no scalar spelling and are carried only in `all`.
pub fn envName(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (name.len == 0) {
        const out = try std.fmt.allocPrint(arena, "{s}", .{all});
        return out;
    }
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return null;
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return null;
    const out = try std.fmt.allocPrint(arena, "__{s}__", .{name});
    return out;
}

test "logical names keep their spelling" {
    var a: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    try std.testing.expectEqualStrings("__url__", (try envName(arena, "url")).?);
    try std.testing.expectEqualStrings("__myArg__", (try envName(arena, "myArg")).?);
    try std.testing.expectEqualStrings("____", (try envName(arena, "")).?);
    try std.testing.expect((try envName(arena, "a.b")) == null);
}
