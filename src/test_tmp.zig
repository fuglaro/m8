//! Temporary directories shared by tests.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Make a uniquely named test directory beneath TMPDIR, or /tmp when unset,
/// and return its resolved path. Resolving matters on macOS, where /tmp is a
/// symlink and sandbox profiles match the path after resolution.
pub fn make(gpa: Allocator, io: std.Io, name: []const u8) ![]const u8 {
    var env = try std.testing.environ.createMap(gpa);
    defer env.deinit();
    const base = env.get("TMPDIR") orelse "/tmp";

    var random: [8]u8 = undefined;
    io.random(&random);
    const leaf = try std.fmt.allocPrint(gpa, "{s}-{x}", .{ name, &random });
    defer gpa.free(leaf);
    const path = try std.fs.path.join(gpa, &.{ base, leaf });
    defer gpa.free(path);

    try std.Io.Dir.cwd().createDirPath(io, path);
    errdefer std.Io.Dir.cwd().deleteTree(io, path) catch {};
    var resolved: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.Io.Dir.cwd().realPathFile(io, path, &resolved);
    return gpa.dupe(u8, resolved[0..len]);
}
