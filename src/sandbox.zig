//! Restrictions: the sandbox profile, and the environment a child is given.
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
//! Both files may be overridden from `core/` in the user's own config, and
//! only from there: a project directory arrives with `git clone`, and these
//! two files decide what a restriction means rather than what runs under it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");

pub const template = @embedFile("core/mac-sandbox.sb");
pub const env_allowed = @embedFile("core/contain-env-allowed.txt");

const marker = ";;!!";

pub const Restriction = struct {
    name: []const u8,
    summary: []const u8,
    kernel: bool = false,
};

/// Every restriction `m8 shield secure` knows, in the order help lists them.
///
/// Atoms only. `sandbox` and `jail` used to be here too, carrying their own
/// tags so that resolving stayed one pass — they are compositions in
/// `core/shields.md` now, which is a place you can read them.
///
/// `kernel` says the profile enforces it, so every descendant of the process
/// inherits it. `contain-env` is the one m8 applies itself, when it builds the
/// environment rather than passing one on.
pub const all = [_]Restriction{
    .{ .name = "contain-reads", .kernel = true, .summary = "no reading outside cwd, TMP, system and tool dirs" },
    .{ .name = "private", .kernel = true, .summary = "as above, and tool dirs go too" },
    .{ .name = "contain-writes", .kernel = true, .summary = "writes confined to cwd and TMP" },
    .{ .name = "no-writes", .kernel = true, .summary = "nothing is writable, including TMP" },
    .{ .name = "airgap", .kernel = true, .summary = "no internet; loopback and unix sockets stay" },
    .{ .name = "no-loop", .kernel = true, .summary = "no loopback or unix sockets; internet stays" },
    .{ .name = "no-edit-git", .kernel = true, .summary = "no writing to a .git anywhere" },
    .{ .name = "no-edit-m8-st8", .kernel = true, .summary = "no writing to a config directory anywhere" },
    .{ .name = "contain-env", .summary = "the environment is rebuilt, not inherited" },
};

/// Restrictions the sandbox profile cannot express, and that m8 applies
/// itself.
pub fn isKernel(name: []const u8) bool {
    return if (find(name)) |r| r.kernel else false;
}

/// True when `active` calls for the child's environment to be rebuilt. One
/// name, because a level that wants it says so in its own composition.
pub fn containsEnv(active: []const []const u8) bool {
    for (active) |a| if (std.mem.eql(u8, a, "contain-env")) return true;
    return false;
}

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

/// The profile to use: `core/mac-sandbox.sb` from the user's config if there
/// is one, otherwise the copy compiled in.
pub fn profile(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const u8 {
    return (try config.core(arena, io, env, "mac-sandbox.sb")) orelse template;
}

/// Likewise for the environment allowlist. An override replaces the bundled
/// list rather than extending it, so what a restriction permits is always
/// readable from one file.
pub fn envAllowed(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const u8 {
    return (try config.core(arena, io, env, "contain-env-allowed.txt")) orelse env_allowed;
}

/// True when `name` is passed through by the allowlist in `src`. One name per
/// line, a trailing `*` matches a prefix, `#` comments and blank lines are
/// ignored.
pub fn envPasses(src: []const u8, name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |raw| {
        const rule = std.mem.trim(u8, raw, " \t\r");
        if (rule.len == 0 or rule[0] == '#') continue;
        if (rule[rule.len - 1] == '*') {
            if (std.mem.startsWith(u8, name, rule[0 .. rule.len - 1])) return true;
        } else if (std.mem.eql(u8, rule, name)) return true;
    }
    return false;
}

/// A directory of this call's own, for what m8 writes rather than what a tool
/// does. The two are not the same place: a tool's TMPDIR belongs to its mob
/// and outlives the call, so a resolved profile written there would be one
/// name two calls at once would both write, and the loser would run under the
/// winner's restrictions.
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

/// `sandbox-exec -f <resolved> -D ... -- argv`
pub fn exec(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    argv: []const []const u8,
    active: []const []const u8,
    /// This call's own directory, where the resolved profile is written.
    own: []const u8,
    /// What the profile is told TMP is: the tool's, not m8's.
    tmp: []const u8,
) ![]const []const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try std.process.currentPath(io, &buf);
    const cwd = try arena.dupe(u8, buf[0..len]);
    const parent = std.fs.path.dirname(cwd) orelse "/";

    const path = try std.fs.path.join(arena, &.{ own, "resolved.sb" });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = try resolve(arena, try profile(arena, io, env), active),
    });

    var full: std.ArrayList([]const u8) = .empty;
    try full.appendSlice(arena, &.{
        "sandbox-exec",
        "-f",
        path,
        "-D",
        try std.fmt.allocPrint(arena, "CWD={s}", .{cwd}),
        "-D",
        try std.fmt.allocPrint(arena, "PARENTWD={s}", .{parent}),
        "-D",
        try std.fmt.allocPrint(arena, "TMP={s}", .{tmp}),
    });
    try full.appendSlice(arena, argv);
    return full.items;
}

/// The environment rebuilt from the allowlist rather than inherited. HOME and
/// TMPDIR become the run's own directory: somewhere real to write that says
/// nothing about whose machine this is.
pub fn contained(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    tmp: []const u8,
) !*const std.process.Environ.Map {
    const rules = try envAllowed(arena, io, env);
    var m: std.process.Environ.Map = .init(arena);
    var it = env.iterator();
    while (it.next()) |e| {
        if (envPasses(rules, e.key_ptr.*)) try m.put(e.key_ptr.*, e.value_ptr.*);
    }
    if (tmp.len > 0) {
        try m.put("TMPDIR", tmp);
        try m.put("HOME", tmp);
    }
    const boxed = try arena.create(std.process.Environ.Map);
    boxed.* = m;
    return boxed;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn res(arena: Allocator, active: []const []const u8) ![]const u8 {
    return resolve(arena, template, active);
}

test "every kernel restriction is tagged somewhere in the profile" {
    for (all) |r| {
        if (!r.kernel) continue;
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

test "a tampering restriction removes the allow, never the deny" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const git = "(^|/)\\.git($|/)";

    const off = try res(arena, &.{});
    try testing.expect(std.mem.indexOf(u8, off, git) != null);
    // Both the deny and the allow that follows it.
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, off, git));

    const on = try res(arena, &.{"no-edit-git"});
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, on, git));
    try testing.expect(std.mem.indexOf(u8, on, "(deny file-write* (regex #\"" ++ "(^|/)\\.git($|/)") != null);
}

/// The broad pair the two permanent rules are written against.
const broad_deny = "(deny file-write* (regex #\"(^|/)\\.?m8-st8($|/)\"))";
const broad_allow = "(allow file-write* (regex #\"(^|/)\\.?m8-st8($|/)\"))";

test "the core deny survives every restriction, and comes last" {
    const core_rule = "m8-st8/core($|/)";
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    for ([_][]const []const u8{
        &.{},
        &.{"jail"},
        &.{"no-edit-m8-st8"},
        &.{ "no-writes", "private", "airgap" },
    }) |active| {
        const out = try res(arena, active);
        const at = std.mem.indexOf(u8, out, core_rule) orelse return error.CoreRuleMissing;
        // Last matching rule wins, so it must follow the allow it overrides.
        // The allow it overrides rather than the last one there is: the
        // scratch rule below it is an allow that is meant to come after.
        if (std.mem.indexOf(u8, out, broad_allow)) |allow| {
            try testing.expect(at > allow);
        }
    }
}

test "the mob's scratch stays writable under every restriction" {
    // The pair to the core deny: m8 guarantees a tool can write here, so no
    // combination of flags may take it away, and it has to follow the deny
    // that would otherwise carry it off with the rest of a config directory.
    const scratch_rule = "m8-st8/\\+/([^/]+/)*\\.tmpdir($|/)";
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    for ([_][]const []const u8{
        &.{},
        &.{"jail"},
        &.{"no-edit-m8-st8"},
        &.{ "no-writes", "private", "airgap" },
    }) |active| {
        const out = try res(arena, active);
        const at = std.mem.indexOf(u8, out, scratch_rule) orelse return error.ScratchRuleMissing;
        const deny = std.mem.indexOf(u8, out, broad_deny) orelse return error.DenyMissing;
        try testing.expect(at > deny);
    }
}

test "the env allowlist passes what it names and nothing else" {
    try testing.expect(envPasses(env_allowed, "PATH"));
    try testing.expect(envPasses(env_allowed, "LANG"));
    try testing.expect(envPasses(env_allowed, "LC_ALL")); // trailing *
    try testing.expect(envPasses(env_allowed, "LC_CTYPE"));
    try testing.expect(!envPasses(env_allowed, "SSH_AUTH_SOCK"));
    try testing.expect(!envPasses(env_allowed, "HOME")); // substituted, not passed
    try testing.expect(!envPasses(env_allowed, "TMPDIR"));
    try testing.expect(!envPasses(env_allowed, "AWS_SECRET_ACCESS_KEY"));
    // A comment naming a variable must not act as a rule.
    try testing.expect(!envPasses(env_allowed, "XPC_FLAGS"));
}

// The tampering rules are worth exercising against the real sandbox: the
// component anchor in them broke twice under hand testing before it was
// right, and nothing about the regex text says whether it holds.

fn sandboxAllows(gpa: Allocator, io: std.Io, dir: []const u8, active: []const []const u8, script: []const u8) !bool {
    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();
    const arena = a.allocator();

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
            try std.fmt.allocPrint(arena, "TMP={s}", .{dir}),                                      "/bin/sh",
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
/// against resolved paths, and /tmp is a symlink to /private/tmp — so a cwd
/// given as /tmp/x never matches (subpath (param "CWD")) and contain-writes
/// denies the working directory itself. `currentPath` resolves, so this only
/// bites somewhere like here, where the path is built by hand.
fn scratch(gpa: Allocator, io: std.Io, name: []const u8) ![]const u8 {
    const base = try std.fs.path.join(gpa, &.{ "/private/tmp", name });
    std.Io.Dir.cwd().deleteTree(io, base) catch {};
    try std.Io.Dir.cwd().createDirPath(io, base);
    return base;
}

test "a config directory cannot be staged elsewhere and renamed in" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const dir = try scratch(testing.allocator, io, "m8-restriction-rename");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    // Staging outside the target name is fine; landing it is not. A rename
    // carries a whole subtree with no per-entry check, so the destination
    // path is the only thing standing in the way.
    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p staging && echo x > staging/evil.md"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mv staging .m8-st8"));
    // And the same for core, with a restriction that never mentions it.
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"contain-reads"}, "mkdir -p .m8-st8 2>/dev/null; mv staging .m8-st8/core"));
}

test "a config directory cannot be reached through a symlink" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const dir = try scratch(testing.allocator, io, "m8-restriction-symlink");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "mkdir -p elsewhere"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"no-edit-m8-st8"}, "ln -s elsewhere .m8-st8"));
    try testing.expect(!try sandboxAllows(testing.allocator, io, dir, &.{"contain-reads"}, "mkdir -p .m8-st8 2>/dev/null; ln -s elsewhere .m8-st8/core"));
}

test "a restriction leaves ordinary work alone" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const dir = try scratch(testing.allocator, io, "m8-restriction-control");
    defer testing.allocator.free(dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};

    try testing.expect(try sandboxAllows(testing.allocator, io, dir, &.{ "private", "contain-writes", "no-loop", "airgap" }, "mkdir -p sub && echo hi > sub/notes.txt && cat sub/notes.txt"));
}

test "the table is atoms, so a level is a composition and not an entry" {
    // What `jail` means is in core/shields.md, where it can be read and taken
    // apart. Naming it here would be the same fact in two places.
    for ([_][]const u8{ "jail", "sandbox", "deny", "ask", "freeze-toolbox", "agent-check=x" }) |n|
        try testing.expect(find(n) == null);
    for ([_][]const u8{ "private", "airgap", "contain-env" }) |n|
        try testing.expect(find(n) != null);

    // Only the environment one is m8's own; the rest are lines in the profile.
    try testing.expect(!isKernel("contain-env"));
    try testing.expect(isKernel("airgap"));
    try testing.expect(containsEnv(&.{"contain-env"}));
    try testing.expect(!containsEnv(&.{"airgap"}));
}
