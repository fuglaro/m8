//! Restrictions: the sandbox profile.
//!
//! `core/mac-sandbox.sb` grants everything and then tags the lines that each
//! restriction takes away. A restriction only ever subtracts, so any
//! combination is safe and the order never matters — which is why a 🛡 may
//! name them in any order and compose with another without a precedence rule
//! to remember. Where a restriction needs to *deny* something, the profile
//! denies it unconditionally and tags a conditional allow instead, so the
//! invariant holds even for those.
//!
//! A line ending in `;;!! !a !b` is dropped when `a` or `b` is active. Levels
//! like `sandbox` are not expanded into the restrictions they compose; they
//! carry their own tags, so resolving stays a single pass with no lookup
//! table.
//!
//! The profile may be overridden from a `core/`, nearest first like any other
//! config.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");

pub const template = @embedFile("core/mac-sandbox.sb");

const marker = ";;!!";

pub const Restriction = struct {
    name: []const u8,
    summary: []const u8,
};

/// Every restriction `m8 secure-shield` knows, in the order help lists them.
///
/// Atoms only. A level such as `sandbox` or `jail` is a composition an agent
/// writes or includes, which is a place it can be read.
///
/// The profile enforces each one, so every descendant of the process inherits
/// it.
pub const all = [_]Restriction{
    .{ .name = "contain-reads", .summary = "no reading outside cwd, TMP, system and tool dirs" },
    .{ .name = "contain-reads-home", .summary = "as above, with HOME readable too" },
    .{ .name = "private", .summary = "as contain-reads, and tool dirs go too" },
    .{ .name = "contain-writes", .summary = "writes confined to cwd and TMP" },
    .{ .name = "contain-writes-home", .summary = "writes confined to cwd, TMP and HOME" },
    .{ .name = "only-tmp-writes", .summary = "writes confined to the current tool's TMP" },
    .{ .name = "no-writes", .summary = "no filesystem writes, including TMP" },
    .{ .name = "airgap", .summary = "no internet; loopback and unix sockets stay" },
    .{ .name = "no-loop", .summary = "no loopback or unix sockets; internet stays" },
    .{ .name = "no-edit-git", .summary = "no writing to the nearest .git entry from cwd upward" },
    .{ .name = "no-edit-m8-st8", .summary = "no writing to a config directory anywhere" },
};

pub fn find(name: []const u8) ?Restriction {
    for (all) |r| if (std.mem.eql(u8, r.name, name)) return r;
    return null;
}

/// The profile with every line the active restrictions take away removed.
/// `src` is the profile text, so a caller may pass an override from `core/`.
pub fn resolve(arena: Allocator, src: []const u8, active: []const []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, src, '\n');
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

/// The profile to use: the nearest `core/mac-sandbox.sb` if there is one,
/// otherwise the copy compiled in.
pub fn profile(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const u8 {
    return (try config.core(arena, io, env, "mac-sandbox.sb")) orelse template;
}

/// A scratch directory for a command run under `secure` straight from a
/// shell, where there is no mob and nothing made one.
pub fn makeTmp(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const u8 {
    const base = env.get("TMPDIR") orelse "/tmp";
    var word: [8]u8 = undefined;
    io.random(&word);
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&word}) catch unreachable;
    const tmp = try std.fs.path.join(arena, &.{
        base, try std.fmt.allocPrint(arena, "m8shield-{s}", .{&hex}),
    });
    try std.Io.Dir.cwd().createDirPath(io, tmp);
    return tmp;
}

/// The nearest `.git` entry at or above cwd, resolved for sandbox path matching.
/// Git metadata may be a directory or a worktree's `.git` file.
pub fn gitEntry(arena: Allocator, io: std.Io, cwd: []const u8) !?[]const u8 {
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

/// `sandbox-exec -p <resolved> -D ... -- argv`
/// The profile is handed over as text rather than written to a temporary file.
pub fn exec(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    argv: []const []const u8,
    active: []const []const u8,
    /// What the profile is told TMP is: the tool's.
    tmp: []const u8,
) ![]const []const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.process.currentPath(io, &buf);
    const cwd = try arena.dupe(u8, buf[0..len]);
    const parent = std.fs.path.dirname(cwd) orelse "/";
    const git = try gitEntry(arena, io, cwd);

    // macOS matches the resolved path. Resolve HOME for the restrictions that
    // use it just as currentPath resolved CWD; without HOME they grant only TMP.
    // A contain-home wrapper has already replaced the value before we arrive.
    var home: []const u8 = tmp;
    for (active) |name| {
        if (!std.mem.eql(u8, name, "contain-reads-home") and
            !std.mem.eql(u8, name, "contain-writes-home")) continue;
        const raw = env.get("HOME") orelse break;
        if (raw.len > 0)
            home = try std.Io.Dir.cwd().realPathFileAlloc(io, raw, arena);
        break;
    }

    var full: std.ArrayList([]const u8) = .empty;
    try full.appendSlice(arena, &.{
        "sandbox-exec",
        "-p",
        try resolve(arena, try profile(arena, io, env), active),
        "-D",
        try std.fmt.allocPrint(arena, "CWD={s}", .{cwd}),
        "-D",
        try std.fmt.allocPrint(arena, "PARENTWD={s}", .{parent}),
        "-D",
        try std.fmt.allocPrint(arena, "TMP={s}", .{tmp}),
        "-D",
        try std.fmt.allocPrint(arena, "HOME={s}", .{home}),
        "-D",
        try std.fmt.allocPrint(arena, "GIT={s}", .{git orelse ""}),
    });
    try full.appendSlice(arena, argv);
    return full.items;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const test_tmp = @import("test_tmp.zig");

fn res(arena: Allocator, active: []const []const u8) ![]const u8 {
    return resolve(arena, template, active);
}

test "every restriction is tagged somewhere in the profile" {
    for (all) |r| {
        const tag = try std.fmt.allocPrint(testing.allocator, "!{s}", .{r.name});
        defer testing.allocator.free(tag);
        try testing.expect(std.mem.indexOf(u8, template, tag) != null);
    }
}

test "no restrictions leaves the profile alone" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    try testing.expectEqualStrings(template, try res(a.allocator(), &.{}));
}

test "a restriction takes away only the lines it is tagged on" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const out = try res(a.allocator(), &.{"airgap"});
    try testing.expect(std.mem.indexOf(u8, out, "(allow network*)") == null);
    try testing.expect(std.mem.indexOf(u8, out, "(deny default)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "(allow process-exec)") != null);
}

test "restrictions only subtract, so combining them commutes" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const one = try res(arena, &.{ "private", "airgap" });
    const other = try res(arena, &.{ "airgap", "private" });
    try testing.expectEqualStrings(one, other);
    try testing.expect(one.len < template.len);
}

test "home containment leaves HOME and washes out under stricter containment" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const home_read = "(allow file-read* (subpath (param \"HOME\")))";
    const home_write = "(allow file-write* (subpath (param \"HOME\")))";

    const reads_home = try res(arena, &.{"contain-reads-home"});
    try testing.expect(std.mem.indexOf(u8, reads_home, home_read) != null);
    const reads_strict = try res(arena, &.{"contain-reads"});
    try testing.expect(std.mem.indexOf(u8, reads_strict, home_read) == null);
    try testing.expectEqualStrings(reads_strict, try res(arena, &.{ "contain-reads-home", "contain-reads" }));
    const reads_private = try res(arena, &.{"private"});
    try testing.expectEqualStrings(reads_private, try res(arena, &.{ "contain-reads-home", "private" }));

    const writes_home = try res(arena, &.{"contain-writes-home"});
    try testing.expect(std.mem.indexOf(u8, writes_home, home_write) != null);
    const writes_strict = try res(arena, &.{"contain-writes"});
    try testing.expect(std.mem.indexOf(u8, writes_strict, home_write) == null);
    try testing.expectEqualStrings(writes_strict, try res(arena, &.{ "contain-writes-home", "contain-writes" }));
    const writes_none = try res(arena, &.{"no-writes"});
    try testing.expectEqualStrings(writes_none, try res(arena, &.{ "contain-writes-home", "no-writes" }));
    try testing.expectEqualStrings(writes_none, try res(arena, &.{ "only-tmp-writes", "no-writes" }));
    try testing.expectEqualStrings(writes_none, try res(arena, &.{ "only-tmp-writes", "contain-writes-home", "no-writes" }));

    const only_tmp = try res(arena, &.{"only-tmp-writes"});
    try testing.expect(std.mem.indexOf(u8, only_tmp, home_write) == null);
    try testing.expect(std.mem.indexOf(u8, only_tmp, "(allow file-write* (subpath (param \"TMP\")))") != null);
    try testing.expect(std.mem.indexOf(u8, only_tmp, "(allow file-write* (subpath (param \"CWD\")))") == null);
    try testing.expectEqualStrings(only_tmp, try res(arena, &.{ "contain-writes-home", "only-tmp-writes" }));
}

test "no-edit-git resolves nearest entries and falls back upward" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const base = try scratch(arena, io, "m8-git-lookup");
    defer std.Io.Dir.cwd().deleteTree(io, base) catch {};
    const outer_git = try std.fs.path.join(arena, &.{ base, ".git" });
    const repo = try std.fs.path.join(arena, &.{ base, "repo" });
    const nested = try std.fs.path.join(arena, &.{ repo, "nested" });
    try std.Io.Dir.cwd().createDirPath(io, outer_git);
    try std.Io.Dir.cwd().createDirPath(io, nested);

    try testing.expectEqualStrings(outer_git, (try gitEntry(arena, io, nested)).?);
    const inner_git = try std.fs.path.join(arena, &.{ repo, ".git" });
    try std.Io.Dir.cwd().createDirPath(io, inner_git);
    try testing.expectEqualStrings(inner_git, (try gitEntry(arena, io, nested)).?);

    try std.Io.Dir.cwd().deleteTree(io, inner_git);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = inner_git, .data = "gitdir: elsewhere" });
    try testing.expectEqualStrings(inner_git, (try gitEntry(arena, io, nested)).?);

    try std.Io.Dir.cwd().deleteFile(io, inner_git);
    try testing.expectEqualStrings(outer_git, (try gitEntry(arena, io, nested)).?);

    var root_has_git = true;
    _ = std.Io.Dir.cwd().statFile(io, "/.git", .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => root_has_git = false,
        else => return err,
    };
    if (!root_has_git) try testing.expect((try gitEntry(arena, io, "/")) == null);
}

/// The broad pair the two permanent rules are written against.
const broad_deny = "(deny file-write* (regex #\"(^|/)\\.?m8-st8($|/)\"))";
const broad_allow = "(allow file-write* (regex #\"(^|/)\\.?m8-st8($|/)\"))";

test "no-edit-m8-st8 removes the broad config allow covering core" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const out = try res(arena, &.{"no-edit-m8-st8"});
    try testing.expect(std.mem.indexOf(u8, out, broad_deny) != null);
    try testing.expect(std.mem.indexOf(u8, out, broad_allow) == null);
}

test "only-tmp-writes and no-writes remove broad and special config/GIT allows" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const config_allow = broad_allow;
    const git_allow = "(allow file-write* (subpath (param \"GIT\")))";
    for ([_][]const []const u8{ &.{"only-tmp-writes"}, &.{"no-writes"} }) |active| {
        const out = try res(arena, active);
        try testing.expect(std.mem.indexOf(u8, out, config_allow) == null);
        try testing.expect(std.mem.indexOf(u8, out, git_allow) == null);
    }
}

test "TMP writes are allowed only when requested" {
    const tmp_write = "(allow file-write* (subpath (param \"TMP\")))";
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    try testing.expect(std.mem.indexOf(u8, try res(arena, &.{"only-tmp-writes"}), tmp_write) != null);
    try testing.expect(std.mem.indexOf(u8, try res(arena, &.{"no-writes"}), tmp_write) == null);
}

test "only-tmp-writes preserves TMP across combinations" {
    const scratch_rule = "(allow file-write* (subpath (param \"TMP\")))";
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    for ([_][]const []const u8{ &.{"only-tmp-writes"}, &.{ "only-tmp-writes", "contain-writes-home", "private" } }) |active| {
        try testing.expect(std.mem.indexOf(u8, try res(arena, active), scratch_rule) != null);
    }
}

test "no-writes denies the current tool's scratch" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-tmp");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-writes"}, "echo scratch > tool-scratch/file"));
}
test "only-tmp-writes allows TMP but denies cwd" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-only-tmp");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{"only-tmp-writes"}, "echo tmp > tool-scratch/file"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"only-tmp-writes"}, "echo cwd > cwd-file"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{ "only-tmp-writes", "contain-writes-home" }, "echo cwd > cwd-file"));
}
test "no-edit-m8-st8 protects core writes" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-core-toggle");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    const core = try std.fs.path.join(testing.allocator, &.{ dir, ".m8-st8", "core" });
    defer testing.allocator.free(core);
    try std.Io.Dir.cwd().createDirPath(io, core);

    const write = "echo changed > .m8-st8/core/profile";
    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{}, write));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, write));
}

test "no-edit-git protects the nested repo and leaves its outer repo writable" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const outer = try scratch(arena, io, "m8-restriction-git-outer");
    defer std.Io.Dir.cwd().deleteTree(io, outer) catch {};
    const outer_git = try std.fs.path.join(arena, &.{ outer, ".git" });
    const repo = try std.fs.path.join(arena, &.{ outer, "nested-repo" });
    const nearest = try std.fs.path.join(arena, &.{ repo, ".git" });
    try std.Io.Dir.cwd().createDirPath(io, outer_git);
    try std.Io.Dir.cwd().createDirPath(io, nearest);
    const objects = try std.fs.path.join(arena, &.{ nearest, "objects" });
    try std.Io.Dir.cwd().createDirPath(io, objects);

    try testing.expect(!try sandboxAllows(testing.allocator, io, repo, &.{"no-edit-git"}, "echo changed > .git/objects/test"));
    try std.Io.Dir.cwd().deleteTree(io, nearest);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = nearest, .data = "gitdir: elsewhere" });
    try testing.expect(!try sandboxAllows(testing.allocator, io, repo, &.{"no-edit-git"}, "echo changed > .git"));

    const outer_file = try std.fs.path.join(arena, &.{ outer_git, "m8-sandbox-test" });
    const outer_script = try std.fmt.allocPrint(arena, "echo changed > '{s}' && rm '{s}'", .{ outer_file, outer_file });
    // Keep the nearest .git file in place: only the synthetic outer repo may
    // be written by this command.
    try testing.expect(try sandboxAllows(testing.allocator, io, repo, &.{"no-edit-git"}, outer_script));
}

// Exercise the entry-scoped rule against the real sandbox, including both
// metadata representations and an enclosing repository left writable.

fn canApplySandbox(io: std.Io) !bool {
    var child = std.process.spawn(io, .{
        .argv = &.{ "sandbox-exec", "-p", "(version 1) (allow default)", "/usr/bin/true" },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;
    return switch (try child.wait(io)) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn sandboxAllows(gpa: Allocator, io: std.Io, dir: []const u8, active: []const []const u8, script: []const u8) !bool {
    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();
    const arena = a.allocator();

    const git = try gitEntry(arena, io, dir);
    const tmp = try std.fs.path.join(arena, &.{ dir, "tool-scratch" });
    try std.Io.Dir.cwd().createDirPath(io, tmp);

    const path = try std.fs.path.join(arena, &.{ dir, "resolved.sb" });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = try resolve(arena, template, active),
    });

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "sandbox-exec",                                                                        "-f",
            path,                                                                                  "-D",
            try std.fmt.allocPrint(arena, "CWD={s}", .{dir}),                                      "-D",
            try std.fmt.allocPrint(arena, "PARENTWD={s}", .{std.fs.path.dirname(dir) orelse "/"}), "-D",
            try std.fmt.allocPrint(arena, "TMP={s}", .{tmp}),                                      "-D",
            try std.fmt.allocPrint(arena, "HOME={s}", .{dir}),                                     "-D",
            try std.fmt.allocPrint(arena, "GIT={s}", .{git orelse ""}),                            "/bin/sh",
            "-c",                                                                                  script,
        },
        .cwd = .{ .path = dir },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    return switch (try child.wait(io)) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// The CWD parameter has to be a *resolved* path. macOS matches the profile
/// against resolved paths, and /tmp is commonly a symlink — so a cwd given in
/// its unresolved spelling does not match (subpath (param "CWD")) and
/// contain-writes denies the working directory itself. `currentPath` resolves;
/// the shared test helper does the same for paths built by hand.
fn scratch(gpa: Allocator, io: std.Io, name: []const u8) ![]const u8 {
    return test_tmp.make(gpa, io, name);
}

test "a config directory cannot be staged elsewhere and renamed in" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-rename");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    // Staging outside the target name is fine; landing it is not. A rename
    // carries a whole subtree with no per-entry check, so the destination
    // path is the only thing standing in the way.
    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p staging && echo x > staging/evil.md"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mv staging .m8-st8"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p .m8-st8 2>/dev/null; mv staging .m8-st8/core"));
}

test "a config directory cannot be reached through a symlink" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-symlink");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p elsewhere"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "ln -s elsewhere .m8-st8"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p .m8-st8 2>/dev/null; ln -s elsewhere .m8-st8/core"));
}

test "a restriction leaves ordinary work alone" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (!try canApplySandbox(io)) return error.SkipZigTest;

    const dir = try scratch(testing.allocator, io, "m8-restriction-control");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{ "private", "contain-writes", "no-loop", "airgap" }, "mkdir -p sub && echo hi > sub/notes.txt && cat sub/notes.txt"));
}

test "the table is atoms, so a level is a composition and not an entry" {
    // What `jail` means is whatever an agent's shields say, where it can be
    // read and taken apart. Naming it here would be the same fact in two places.
    for ([_][]const u8{ "jail", "sandbox", "deny", "ask", "freeze-toolbox", "contain-env", "contain-home" }) |n|
        try testing.expect(find(n) == null);
    for ([_][]const u8{ "private", "airgap", "no-edit-git" }) |n|
        try testing.expect(find(n) != null);
}
