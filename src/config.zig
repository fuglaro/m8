//! Finding configuration.
//!
//! Config directories are searched nearest first: every `.m8-st8/` from the
//! working directory upward, the way git finds `.git`, then the user's own.
//!
//! `core/` is the exception. It holds the files that decide what a lock
//! *means* — the sandbox profile and the environment allowlist — and a
//! project directory arrives with `git clone`, so only the user's own config
//! is consulted for it.
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
        const candidate = try std.fs.path.join(arena, &.{ walk, dir_name });
        if (exists(io, candidate)) try dirs.append(arena, candidate);
        const parent = std.fs.path.dirname(walk) orelse break;
        if (parent.len == walk.len) break;
        walk = parent;
    }

    if (try userDir(arena, env)) |d| try dirs.append(arena, d);
    return dirs.toOwnedSlice(arena);
}

/// Hidden beside a project, plain under the user's config root.
pub const dir_name = ".m8-st8";
pub const user_dir_name = "m8-st8";

/// The user's own config directory, if there is one. Separate from `discover`
/// because `core/` is read only from here.
pub fn userDir(arena: Allocator, env: *const std.process.Environ.Map) !?[]const u8 {
    if (env.get("XDG_CONFIG_HOME")) |xdg| {
        return try std.fs.path.join(arena, &.{ xdg, user_dir_name });
    } else if (env.get("HOME")) |home| {
        return try std.fs.path.join(arena, &.{ home, ".config", user_dir_name });
    }
    return null;
}

/// Read a file from `core/` in the user's config directory. Null when there is
/// none, which means the copy compiled into the binary is used instead.
pub fn core(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    name: []const u8,
) !?[]const u8 {
    const base = (try userDir(arena, env)) orelse return null;
    const path = try std.fs.path.join(arena, &.{ base, "core", name });
    return std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) catch null;
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

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// A throwaway config tree. Real directories, because what is being tested is
/// which file gets picked out of several.
const Tree = struct {
    io: std.Io,
    threaded: *std.Io.Threaded,
    root: []const u8,

    fn init(gpa: Allocator, threaded: *std.Io.Threaded, name: []const u8) !Tree {
        const io = threaded.io();
        const root = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
        std.Io.Dir.cwd().deleteTree(io, root) catch {};
        try std.Io.Dir.cwd().createDirPath(io, root);
        return .{ .io = io, .threaded = threaded, .root = root };
    }

    fn write(t: Tree, gpa: Allocator, rel: []const u8, data: []const u8) !void {
        const path = try std.fs.path.join(gpa, &.{ t.root, rel });
        defer gpa.free(path);
        if (std.fs.path.dirname(path)) |d| try std.Io.Dir.cwd().createDirPath(t.io, d);
        try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = data });
    }

    fn join(t: Tree, gpa: Allocator, rel: []const u8) ![]const u8 {
        return std.fs.path.join(gpa, &.{ t.root, rel });
    }

    fn deinit(t: Tree, gpa: Allocator) void {
        std.Io.Dir.cwd().deleteTree(t.io, t.root) catch {};
        gpa.free(t.root);
    }
};

test "read takes the file from the nearest directory that has one" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const t = try Tree.init(arena, &threaded, "m8-config-read");
    defer t.deinit(arena);
    try t.write(arena, "near/mathy.md", "near");
    try t.write(arena, "far/mathy.md", "far");
    try t.write(arena, "far/only.md", "far only");

    const dirs = [_][]const u8{ try t.join(arena, "near"), try t.join(arena, "far") };
    try testing.expectEqualStrings("near", (try read(arena, t.io, &dirs, "mathy.md")).?);
    // Falling through to a further directory is how a user config backs a
    // project one, rather than being replaced by it.
    try testing.expectEqualStrings("far only", (try read(arena, t.io, &dirs, "only.md")).?);
    try testing.expect((try read(arena, t.io, &dirs, "absent.md")) == null);
}

test "core is read from the user's directory and nowhere else" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const t = try Tree.init(arena, &threaded, "m8-config-core");
    defer t.deinit(arena);
    try t.write(arena, "m8-st8/core/mac-sandbox.sb", "(user profile)");

    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    try testing.expectEqualStrings(
        "(user profile)",
        (try core(arena, t.io, &env, "mac-sandbox.sb")).?,
    );
    try testing.expect((try core(arena, t.io, &env, "absent.txt")) == null);

    // A project directory arrives with a clone, so it never supplies core.
    var none: std.process.Environ.Map = .init(arena);
    try testing.expect((try core(arena, t.io, &none, "mac-sandbox.sb")) == null);
}

test "the user directory follows XDG, then HOME" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var xdg: std.process.Environ.Map = .init(arena);
    try xdg.put("XDG_CONFIG_HOME", "/x");
    try testing.expectEqualStrings("/x/m8-st8", (try userDir(arena, &xdg)).?);

    var home: std.process.Environ.Map = .init(arena);
    try home.put("HOME", "/h");
    try testing.expectEqualStrings("/h/.config/m8-st8", (try userDir(arena, &home)).?);

    var none: std.process.Environ.Map = .init(arena);
    try testing.expect((try userDir(arena, &none)) == null);
}
