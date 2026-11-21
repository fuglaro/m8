//! Bubblewrap backend. Read containment is implemented with an empty root and
//! narrowly mounted runtime roots; unsupported layouts fail closed.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Used for any restriction whose semantics this backend cannot guarantee.
pub const Error = error{ UnsupportedRestriction, UnsupportedWritableLayout };

/// Build a Bubblewrap argv. No bwrap process is run here.
pub fn exec(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    argv: []const []const u8,
    active: []const []const u8,
    tmp: []const u8,
) ![]const []const u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buf);
    const cwd = try arena.dupe(u8, cwd_buf[0..cwd_len]);

    var read_policy = false;
    var strict_read = false;
    var read_home = false;
    var private_reads = false;
    var saw_writes = false;
    var saw_strict = false;
    var only_tmp = false;
    var allow_home = false;
    var no_writes = false;
    var protect_git = false;
    for (active) |name| {
        if (std.mem.eql(u8, name, "contain-reads")) {
            read_policy = true;
            strict_read = true;
        } else if (std.mem.eql(u8, name, "contain-reads-home")) {
            read_policy = true;
            read_home = true;
        } else if (std.mem.eql(u8, name, "private")) {
            read_policy = true;
            private_reads = true;
        } else if (std.mem.eql(u8, name, "contain-writes") or std.mem.eql(u8, name, "contain-writes-soft")) {
            saw_writes = true;
            saw_strict = true;
        } else if (std.mem.eql(u8, name, "contain-writes-home")) {
            saw_writes = true;
            allow_home = true;
        } else if (std.mem.eql(u8, name, "only-tmp-writes")) {
            saw_writes = true;
            only_tmp = true;
        } else if (std.mem.eql(u8, name, "no-writes")) {
            saw_writes = true;
            no_writes = true;
        } else if (std.mem.eql(u8, name, "no-edit-git")) {
            protect_git = true;
        } else {
            return Error.UnsupportedRestriction;
        }
    }

    var home: ?[]const u8 = null;
    if (allow_home and !saw_strict and !only_tmp and !no_writes) {
        if (env.get("HOME")) |raw| {
            if (raw.len != 0) home = std.Io.Dir.cwd().realPathFileAlloc(io, raw, arena) catch null;
        }
    }

    const canonical_tmp = if (read_policy or (saw_writes and !no_writes))
        try std.Io.Dir.cwd().realPathFileAlloc(io, tmp, arena)
    else
        tmp;
    // Restriction combinations are intersections, not unions. A tmp-only
    // policy removes cwd/home grants; no-writes removes every grant.
    var grants: std.ArrayList([]const u8) = .empty;
    if (saw_writes and !no_writes) {
        try appendCollapsed(arena, &grants, if (only_tmp) canonical_tmp else cwd);
        if (!only_tmp) try appendCollapsed(arena, &grants, canonical_tmp);
        if (!only_tmp and !saw_strict) if (home) |h| try appendCollapsed(arena, &grants, h);
    }

    // Canonical roots are mounted first, aliases second. Collapsing nested
    // roots avoids later parent mounts hiding earlier child restrictions.
    var read_roots: std.ArrayList([]const u8) = .empty;
    var aliases: std.ArrayList(Alias) = .empty;
    if (read_policy) {
        try addReadRoot(arena, io, &read_roots, &aliases, cwd);
        try addReadRoot(arena, io, &read_roots, &aliases, tmp);
        for (system_paths) |path| try addReadRoot(arena, io, &read_roots, &aliases, path);
        if (read_home and !strict_read and !private_reads) if (env.get("HOME")) |raw| {
            if (raw.len > 0) try addReadRoot(arena, io, &read_roots, &aliases, raw);
        };
        if (!private_reads) {
            for (tool_paths) |path| try addReadRoot(arena, io, &read_roots, &aliases, path);
            if (env.get("HOME")) |raw| {
                if (raw.len > 0) for ([_][]const u8{ ".local/bin", ".cargo/bin", "go/bin" }) |suffix| {
                    const path = try std.fs.path.join(arena, &.{ raw, suffix });
                    try addReadRoot(arena, io, &read_roots, &aliases, path);
                };
            }
        }
    }

    var effective_writes: std.ArrayList([]const u8) = .empty;
    if (read_policy and !no_writes) {
        if (!saw_writes) {
            try effective_writes.appendSlice(arena, read_roots.items);
        } else {
            // Mounts grant both read and write access. Never mount a write
            // grant that would reveal data outside the read allowlist.
            for (grants.items) |grant| for (read_roots.items) |root| {
                if (containsPath(grant, root)) {
                    try appendCollapsed(arena, &effective_writes, root);
                } else if (containsPath(root, grant)) {
                    try appendCollapsed(arena, &effective_writes, grant);
                }
            };
        }
    }

    var git: ?[]const u8 = null;
    if (protect_git) git = try findGitEntry(arena, io, cwd);
    if (git) |git_path| {
        for (grants.items) |grant| {
            // A writable bind below .git can obscure the read-only mount.
            if (containsPath(git_path, grant)) return Error.UnsupportedWritableLayout;
        }
    }

    var out: std.ArrayList([]const u8) = .empty;
    try out.appendSlice(arena, &.{ "bwrap", "--die-with-parent", "--new-session", "--unshare-user", "--unshare-pid", "--cap-drop", "ALL" });
    if (read_policy) {
        try out.appendSlice(arena, &.{ "--tmpfs", "/", "--dir", "/tmp" });
        for (read_roots.items) |path| {
            try out.appendSlice(arena, &.{ if (coveredBy(effective_writes.items, path)) "--bind" else "--ro-bind", path, path });
        }
        for (effective_writes.items) |path| {
            if (!hasExact(read_roots.items, path)) try out.appendSlice(arena, &.{ "--bind", path, path });
        }
        // Recreate merged-/usr and caller-provided aliases without exposing
        // their parent directories (e.g. /bin -> /usr/bin, symlinked HOME).
        // Use symlinks, not additional binds: permission checks then reach
        // the canonical mounts, including nested write/metadata restrictions.
        for (aliases.items) |alias| {
            if (coveredBy(read_roots.items, alias.target)) continue;
            // A visible parent alias already preserves its host children.
            // Creating a second alias below it would overwrite real entries.
            var parent_alias = false;
            for (aliases.items) |other| {
                if (!std.mem.eql(u8, other.target, alias.target) and containsPath(other.target, alias.target)) {
                    parent_alias = true;
                    break;
                }
            }
            if (!parent_alias) try out.appendSlice(arena, &.{ "--symlink", alias.source, alias.target });
        }
    } else {
        try out.appendSlice(arena, &.{ if (saw_writes or !protect_git) "--ro-bind" else "--bind", "/", "/" });
        for (grants.items) |path| try out.appendSlice(arena, &.{ "--bind", path, path });
    }
    // Some local-model runtimes hard-code /tmp instead of honoring TMPDIR.
    // Alias only the tool scratch, never the host's /tmp; omit it whenever
    // policy has revoked scratch writes.
    if (saw_writes and !no_writes and !std.mem.eql(u8, canonical_tmp, "/tmp"))
        try out.appendSlice(arena, &.{ "--bind", canonical_tmp, "/tmp" });
    try out.appendSlice(arena, &.{ "--dev", "/dev", "--remount-ro", "/dev", "--proc", "/proc", "--remount-ro", "/proc" });
    if (git) |path| {
        var visible = !read_policy;
        for (read_roots.items) |root| if (containsPath(root, path)) {
            visible = true;
            break;
        };
        if (visible) try out.appendSlice(arena, &.{ "--ro-bind", path, path });
    }
    if (read_policy) try out.appendSlice(arena, &.{ "--remount-ro", "/" });
    try out.appendSlice(arena, &.{ "--chdir", cwd });
    try out.append(arena, "--");
    try out.appendSlice(arena, argv);
    return out.items;
}

// Keep these explicit: binding /usr would also expose /usr/local under
// private, and binding all of /etc would expose host credentials.
const system_paths = [_][]const u8{
    "/usr/bin",         "/usr/sbin",          "/usr/lib",         "/usr/lib64",     "/usr/share",
    "/bin",             "/sbin",              "/lib",             "/lib64",         "/etc/hosts",
    "/etc/resolv.conf", "/etc/nsswitch.conf", "/etc/ld.so.cache", "/etc/localtime", "/etc/passwd",
    "/etc/group",       "/etc/ssl",
};
const tool_paths = [_][]const u8{ "/usr/local/bin", "/usr/local/lib", "/usr/local/opt" };
const Alias = struct { source: []const u8, target: []const u8 };

fn addReadRoot(arena: Allocator, io: std.Io, roots: *std.ArrayList([]const u8), aliases: *std.ArrayList(Alias), path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) return Error.UnsupportedWritableLayout;
    const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, path, arena) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return,
        else => return err,
    };
    try appendCollapsed(arena, roots, canonical);
    if (!std.mem.eql(u8, canonical, path)) {
        for (aliases.items) |alias| if (std.mem.eql(u8, alias.target, path)) return;
        try aliases.append(arena, .{ .source = canonical, .target = path });
    }
}

fn hasExact(paths: []const []const u8, path: []const u8) bool {
    for (paths) |candidate| if (std.mem.eql(u8, candidate, path)) return true;
    return false;
}

fn appendCollapsed(arena: Allocator, list: *std.ArrayList([]const u8), path: []const u8) !void {
    if (!std.fs.path.isAbsolute(path)) return Error.UnsupportedWritableLayout;
    for (list.items) |existing| if (containsPath(existing, path)) return;
    var i: usize = 0;
    while (i < list.items.len) {
        if (containsPath(path, list.items[i])) {
            _ = list.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    try list.append(arena, path);
}

fn coveredBy(paths: []const []const u8, path: []const u8) bool {
    for (paths) |candidate| if (containsPath(candidate, path)) return true;
    return false;
}

fn containsPath(parent: []const u8, child: []const u8) bool {
    if (std.mem.eql(u8, parent, child)) return true;
    if (!std.mem.startsWith(u8, child, parent)) return false;
    return parent.len == 1 or child[parent.len] == std.fs.path.sep;
}

fn findGitEntry(arena: Allocator, io: std.Io, cwd: []const u8) !?[]const u8 {
    var dir = cwd;
    while (true) {
        const candidate = try std.fs.path.join(arena, &.{ dir, ".git" });
        _ = std.Io.Dir.cwd().statFile(io, candidate, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => {
                if (std.mem.eql(u8, dir, "/")) return null;
                dir = std.fs.path.dirname(dir) orelse "/";
                continue;
            },
            else => return err,
        };
        return try std.Io.Dir.cwd().realPathFileAlloc(io, candidate, arena);
    }
}

test "constructs read-only-root argv and writable grants without executing bwrap" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    const got = try exec(arena, std.testing.io, &env, &.{ "echo", "ok" }, &.{"no-writes"}, "/tmp");
    try testing.expectEqualStrings("bwrap", got[0]);
    try testing.expectEqualStrings("--ro-bind", got[7]);
    try testing.expectEqualStrings("--", got[got.len - 3]);
    try testing.expectEqualStrings("echo", got[got.len - 2]);
}

test "rejects unsupported policies" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    for ([_][]const u8{ "airgap", "no-loop", "no-edit-m8-st8" }) |restriction| {
        try testing.expectError(Error.UnsupportedRestriction, exec(arena, std.testing.io, &env, &.{"true"}, &.{restriction}, "/tmp"));
    }
}

test "read policies use an empty root and explicit read-only mounts" {
    const testing = std.testing;
    var state = std.heap.ArenaAllocator.init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    try env.put("HOME", "/");
    const a = try exec(arena, testing.io, &env, &.{"true"}, &.{ "contain-reads", "no-writes" }, "/tmp");
    const b = try exec(arena, testing.io, &env, &.{"true"}, &.{ "contain-reads-home", "private" }, "/tmp");
    try testing.expect(hasArgPair(a, "--tmpfs", "/"));
    try testing.expect(hasPair(a, "--ro-bind", "/usr/bin", "/usr/bin"));
    try testing.expect(!hasPair(a, "--ro-bind", "/", "/"));
    try testing.expect(!hasPair(b, "--ro-bind", "/", "/"));
    for (a, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--ro-bind")) try testing.expect(i + 2 < a.len);
        if (std.mem.eql(u8, arg, "--bind")) try testing.expect(i + 2 < a.len);
    }
}

fn hasArgPair(argv: []const []const u8, flag: []const u8, value: []const u8) bool {
    for (argv, 0..) |arg, i| if (std.mem.eql(u8, arg, flag) and i + 1 < argv.len and std.mem.eql(u8, argv[i + 1], value)) return true;
    return false;
}

fn hasPair(argv: []const []const u8, flag: []const u8, source: []const u8, target: []const u8) bool {
    for (argv, 0..) |arg, i| if (std.mem.eql(u8, arg, flag) and i + 2 < argv.len and std.mem.eql(u8, argv[i + 1], source) and std.mem.eql(u8, argv[i + 2], target)) return true;
    return false;
}

test "write restriction intersection is tmp-only" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    const got = try exec(arena, std.testing.io, &env, &.{"true"}, &.{ "contain-writes", "only-tmp-writes" }, "/tmp");
    var binds: usize = 0;
    for (got, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--bind")) {
            binds += 1;
            try testing.expect(std.mem.eql(u8, got[i + 1], "/tmp") or std.mem.endsWith(u8, got[i + 1], "/tmp"));
        }
    }
    try testing.expectEqual(@as(usize, 2), binds);
}

test "strict contain-writes intersects contain-writes-home regardless of order" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    try env.put("HOME", "/");
    const a = try exec(arena, std.testing.io, &env, &.{"true"}, &.{ "contain-writes-home", "contain-writes" }, "/tmp");
    const b = try exec(arena, std.testing.io, &env, &.{"true"}, &.{ "contain-writes", "contain-writes-home" }, "/tmp");
    try testing.expectEqual(a.len, b.len);
    for (a, b) |left_arg, right_arg| try testing.expectEqualStrings(left_arg, right_arg);
    var binds: usize = 0;
    for (a, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--bind")) binds += 1;
        if (i > 0 and std.mem.eql(u8, a[i - 1], "--bind")) try testing.expect(!std.mem.eql(u8, arg, "/"));
    }
    try testing.expect(binds >= 2 and binds <= 3);
}

test "nested writable grants collapse to their parent in either order" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var left: std.ArrayList([]const u8) = .empty;
    var right: std.ArrayList([]const u8) = .empty;
    try appendCollapsed(arena, &left, "/work/tmp");
    try appendCollapsed(arena, &left, "/work");
    try appendCollapsed(arena, &right, "/work");
    try appendCollapsed(arena, &right, "/work/tmp");
    try testing.expectEqual(@as(usize, 1), left.items.len);
    try testing.expectEqual(@as(usize, 1), right.items.len);
    try testing.expectEqualStrings("/work", left.items[0]);
    try testing.expectEqualStrings("/work", right.items[0]);
}

test "no-edit-git alone uses writable root with protected metadata mount" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    const got = try exec(arena, std.testing.io, &env, &.{"true"}, &.{"no-edit-git"}, "/tmp");
    var root_rw = false;
    for (got, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--bind") and i + 2 < got.len and std.mem.eql(u8, got[i + 1], "/") and std.mem.eql(u8, got[i + 2], "/")) root_rw = true;
    }
    try testing.expect(root_rw);
}

test "Bubblewrap enforces writes and propagates command exit status" {
    const testing = std.testing;
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = testing.io;
    var env = try std.testing.environ.createMap(arena);
    defer env.deinit();

    const probe_argv = try exec(arena, io, &env, &.{"true"}, &.{"no-writes"}, "/tmp");
    const probe = std.process.run(arena, io, .{ .argv = probe_argv, .environ_map = &env }) catch |err| {
        std.debug.print("skipping Bubblewrap integration test: bwrap unavailable ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    switch (probe.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("skipping Bubblewrap integration test: namespace probe exited {d}; user namespaces may be unavailable\n", .{code});
            return error.SkipZigTest;
        },
        else => {
            std.debug.print("skipping Bubblewrap integration test: namespace probe did not exit normally\n", .{});
            return error.SkipZigTest;
        },
    }

    const test_tmp = @import("test_tmp.zig");
    const scratch = try test_tmp.make(arena, io, "m8-bwrap-scratch");
    defer std.Io.Dir.cwd().deleteTree(io, scratch) catch {};
    const outside = try test_tmp.make(arena, io, "m8-bwrap-outside");
    defer std.Io.Dir.cwd().deleteTree(io, outside) catch {};
    const scratch_file = try std.fs.path.join(arena, &.{ scratch, "written" });
    const outside_file = try std.fs.path.join(arena, &.{ outside, "written" });

    const denied_command = try std.fmt.allocPrint(arena, "printf no > '{s}'", .{scratch_file});
    const denied_argv = try exec(arena, io, &env, &.{ "/bin/sh", "-c", denied_command }, &.{"no-writes"}, scratch);
    const denied = try std.process.run(arena, io, .{ .argv = denied_argv, .environ_map = &env });
    try testing.expect(!exitedZero(denied.term));
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, scratch_file, .{}));

    const confined_command = try std.fmt.allocPrint(arena, "printf tmp > '{s}'; printf outside > '{s}'", .{ scratch_file, outside_file });
    const confined_argv = try exec(arena, io, &env, &.{ "/bin/sh", "-c", confined_command }, &.{"only-tmp-writes"}, scratch);
    const confined = try std.process.run(arena, io, .{ .argv = confined_argv, .environ_map = &env });
    try testing.expect(!exitedZero(confined.term));
    _ = try std.Io.Dir.cwd().statFile(io, scratch_file, .{});
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, outside_file, .{}));

    const exit_argv = try exec(arena, io, &env, &.{ "/bin/sh", "-c", "exit 23" }, &.{"no-writes"}, scratch);
    const exited = try std.process.run(arena, io, .{ .argv = exit_argv, .environ_map = &env });
    try testing.expect(switch (exited.term) {
        .exited => |code| code == 23,
        else => false,
    });
}

fn exitedZero(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}
test "writable scratch is aliased at /tmp, but no-writes revokes the alias" {
    const testing = std.testing;
    var state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(testing.io, &cwd_buf);
    const scratch = try arena.dupe(u8, cwd_buf[0..cwd_len]);

    const soft = try exec(arena, testing.io, &env, &.{"true"}, &.{"contain-writes-soft"}, scratch);
    try testing.expect(hasPair(soft, "--bind", scratch, "/tmp"));
    const strict = try exec(arena, testing.io, &env, &.{"true"}, &.{"no-writes"}, scratch);
    try testing.expect(!hasPair(strict, "--bind", scratch, "/tmp"));
}
