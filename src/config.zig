//! Finding configuration.
//!
//! Config directories are searched nearest first: every `.m8/` from the
//! working directory upward, the way git finds `.git`, then the user's own.
//!
//! A file is taken from the nearest directory that has one. `providers.json`
//! is the exception: those merge key by key, so a project can override a
//! single provider without restating the rest.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_file = 4 * 1024 * 1024;

/// Config directories, nearest first.
pub fn discover(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const []const u8 {
    var dirs: std.ArrayList([]const u8) = .empty;

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = std.process.currentPath(io, &buf) catch 0;
    var walk: []const u8 = buf[0..len];
    while (walk.len > 0) {
        const candidate = try std.fs.path.join(arena, &.{ walk, ".m8" });
        if (exists(io, candidate)) try dirs.append(arena, candidate);
        const parent = std.fs.path.dirname(walk) orelse break;
        if (parent.len == walk.len) break;
        walk = parent;
    }

    if (env.get("XDG_CONFIG_HOME")) |xdg| {
        try dirs.append(arena, try std.fs.path.join(arena, &.{ xdg, "m8" }));
    } else if (env.get("HOME")) |home| {
        try dirs.append(arena, try std.fs.path.join(arena, &.{ home, ".config", "m8" }));
    }
    return dirs.toOwnedSlice(arena);
}

fn exists(io: std.Io, path: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

/// Read a file from the nearest config directory that has one.
pub fn read(arena: Allocator, io: std.Io, dirs: []const []const u8, rel: []const u8) !?[]const u8 {
    for (dirs) |dir| {
        const path = try std.fs.path.join(arena, &.{ dir, rel });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) catch continue;
        return bytes;
    }
    return null;
}

/// Every providers.json on the search path, merged by top-level key with the
/// nearest taking precedence.
pub fn providers(arena: Allocator, io: std.Io, dirs: []const []const u8) !std.json.ObjectMap {
    var merged: std.json.ObjectMap = .empty;
    var i = dirs.len;
    while (i > 0) { // furthest first, so nearer writes land on top
        i -= 1;
        const path = try std.fs.path.join(arena, &.{ dirs[i], "providers.json" });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) catch continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        if (parsed != .object) continue;
        var it = parsed.object.iterator();
        while (it.next()) |e| try merged.put(arena, e.key_ptr.*, e.value_ptr.*);
    }
    return merged;
}
