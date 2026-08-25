//! Resolving the macOS sandbox profile.
//!
//! `mac-sandbox.sb` grants everything and then tags the lines that each
//! restriction takes away. A flag only ever subtracts, so any combination is
//! safe and the order never matters — which is why `-w` can be repeated
//! without a precedence rule to remember.
//!
//! A line ending in `;;!! !a !b` is dropped when `a` or `b` is active. Levels
//! like `sandbox` are not expanded into the flags they compose; they carry
//! their own tags, so resolving stays a single pass with no lookup table.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const template = @embedFile("mac-sandbox.sb");

const marker = ";;!!";

pub const Restriction = struct {
    name: []const u8,
    summary: []const u8,
};

/// Every `-w` value, in the order the help should list them.
pub const all = [_]Restriction{
    .{ .name = "contain-reads", .summary = "no reading outside cwd, TMP, system and tool dirs" },
    .{ .name = "private", .summary = "as above, and tool dirs go too" },
    .{ .name = "contain-writes", .summary = "writes confined to cwd and TMP" },
    .{ .name = "no-writes", .summary = "nothing is writable, including TMP" },
    .{ .name = "airgap", .summary = "no internet; loopback and unix sockets stay" },
    .{ .name = "no-loop", .summary = "no loopback or unix sockets; internet stays" },
    .{ .name = "sandbox", .summary = "private + contain-writes + no-loop" },
    .{ .name = "jail", .summary = "sandbox, and no internet either" },
};

pub fn find(name: []const u8) ?Restriction {
    for (all) |r| if (std.mem.eql(u8, r.name, name)) return r;
    return null;
}

/// The profile with every line the active restrictions take away removed.
pub fn resolve(arena: Allocator, active: []const []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, template, '\n');
    var first = true;
    while (it.next()) |line| {
        if (dropped(line, active)) continue;
        if (!first) try out.append(arena, '\n');
        first = false;
        try out.appendSlice(arena, line);
    }
    return out.toOwnedSlice(arena);
}

fn dropped(line: []const u8, active: []const []const u8) bool {
    const at = std.mem.indexOf(u8, line, marker) orelse return false;
    var tags = std.mem.tokenizeAny(u8, line[at + marker.len ..], " \t");
    while (tags.next()) |tag| {
        if (tag.len < 2 or tag[0] != '!') continue;
        for (active) |a| if (std.mem.eql(u8, a, tag[1..])) return true;
    }
    return false;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "every documented restriction is tagged somewhere in the profile" {
    for (all) |r| {
        const tag = try std.fmt.allocPrint(testing.allocator, "!{s}", .{r.name});
        defer testing.allocator.free(tag);
        try testing.expect(std.mem.indexOf(u8, template, tag) != null);
    }
}

test "no restrictions leaves the profile alone" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    try testing.expectEqualStrings(template, try resolve(a.allocator(), &.{}));
}

test "a restriction takes away only the lines it is tagged on" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const out = try resolve(a.allocator(), &.{"airgap"});

    // The one line tagged !airgap is the blanket network grant.
    try testing.expect(std.mem.indexOf(u8, out, "(allow network*)") == null);
    // Untagged lines survive, including the deny that makes the grant matter.
    try testing.expect(std.mem.indexOf(u8, out, "(deny default)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "(allow process-exec)") != null);
}

test "flags only subtract, so combining them commutes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const one = try resolve(arena, &.{ "private", "airgap" });
    const other = try resolve(arena, &.{ "airgap", "private" });
    try testing.expectEqualStrings(one, other);
    try testing.expect(one.len < template.len);
}

test "a level subtracts at least as much as the flags it composes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const jail = try resolve(arena, &.{"jail"});
    const parts = try resolve(arena, &.{ "private", "contain-writes", "no-loop", "airgap" });
    try testing.expectEqualStrings(parts, jail);
}
