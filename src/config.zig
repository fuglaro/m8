//! Finding configuration.
//!
//! Config directories are searched nearest first: every `.m8-st8/` from the
//! working directory upward, the way git finds `.git`, then the user's own.
//!
//! `core/` is the exception. It holds the files that decide what a restriction
//! *means* — the sandbox profile and the environment allowlist — and a
//! project directory arrives with `git clone`, so only the user's own config
//! is consulted for it.
//!
//! A file is taken from the nearest directory that has one. `providers.json`
//! lives in `core/` with the rest, because a provider is a command that runs
//! on your machine and a project arrives with a `git clone`. Mobs travel with
//! agents; providers are yours.

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

/// The user's `core/`, if there is one. Where a provider command written as
/// a relative name is looked for.
pub fn coreDir(arena: Allocator, env: *const std.process.Environ.Map) !?[]const u8 {
    const base = (try userDir(arena, env)) orelse return null;
    return try std.fs.path.join(arena, &.{ base, "core" });
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

/// Where a `core/` file is read from, when there is one to read. Null when
/// nothing is there and the copy compiled in is what is used — which is what
/// a help page says instead of naming a file that does not exist.
pub fn coreFile(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    name: []const u8,
) !?[]const u8 {
    const base = (try coreDir(arena, env)) orelse return null;
    const path = try std.fs.path.join(arena, &.{ base, name });
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return path;
}

fn exists(io: std.Io, path: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

/// Authored definitions live here. A 🧠 still names one by the same logical
/// path: `@mathy` on the command line is `@/mathy.md` on disk.
pub const definitions_dir = "@";

/// Generated state lives alongside definitions rather than among them. Its
/// tree mirrors the logical names under `@/`: the pointer `mathy/+` is
/// `+/mathy/+.md`, and the turn `mathy/+/abc` is `+/mathy/+/abc.md`.
pub const state_dir = "+";

/// Whether a logical name is generated state. `+` is reserved as the pointer
/// and history path component, so its presence says this without disk access.
fn isStateName(name: []const u8) bool {
    return std.mem.eql(u8, name, "+") or
        std.mem.startsWith(u8, name, "+/") or
        std.mem.endsWith(u8, name, "/+") or
        std.mem.indexOf(u8, name, "/+/") != null;
}

/// The file a logical name is, relative to a config directory.
pub fn nameFile(arena: Allocator, name: []const u8) ![]const u8 {
    const root = if (isStateName(name)) state_dir else definitions_dir;
    return std.fmt.allocPrint(arena, "{s}/{s}.md", .{ root, name });
}

/// Where a mob keeps its scratch. Inside the mob's mirrored state folder, so
/// authored definitions and all generated or mutable material stay apart.
///
/// Keeping it out of a version control system is the repository's business
/// rather than m8's — this one carries a `.gitignore` in its own config
/// directory as the suggestion.
pub const tmp_dir_name = ".tmpdir";

fn hasFile(io: std.Io, path: []const u8) bool {
    var f = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}

/// Which config directory holds `rel`, nearest first.
///
/// `read` answers with the bytes. This answers with where they came from, for
/// anything that has to write beside a file rather than read it.
pub fn where(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    rel: []const u8,
) !?[]const u8 {
    for (dirs) |dir| {
        if (hasFile(io, try std.fs.path.join(arena, &.{ dir, rel }))) return dir;
    }
    return null;
}

/// A mob's scratch directory, made before a tool runs.
///
/// Persistence is the whole of why it is here. A tool that writes a file and
/// answers with its path is only useful if the next call can open it, and a
/// directory of one call's own means it never can. Nothing removes it: a tool
/// tidies up after itself or leaves what was meant to last, and resetting a
/// mob is the user's to reach for.
///
/// The path is real rather than reached through a symlink, because a config
/// directory is found by walking up from `currentPath`, which is resolved
/// already — which is what the profile's `TMP` has to match, and what an
/// inherited `TMPDIR` on macOS does not.
pub fn mobTmp(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    agent: []const u8,
) !?[]const u8 {
    if (dirs.len == 0) return null;

    // The mob is where the agent lives, so one named below the top keeps its
    // scratch below the top too. A ledger handed straight in names no agent,
    // and takes the nearest config's own.
    var base = dirs[0];
    var mob: []const u8 = "";
    if (agent.len > 0) {
        if (try where(arena, io, dirs, try nameFile(arena, agent))) |found| {
            base = found;
            mob = std.fs.path.dirname(agent) orelse "";
        }
    }

    const tmp = try std.fs.path.join(arena, &.{ base, state_dir, mob, tmp_dir_name });
    try std.Io.Dir.cwd().createDirPath(io, tmp);
    // No trailing slash, ever, so no tool has to strip one.
    return std.mem.trimEnd(u8, tmp, "/");
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

/// The providers, from `core/`.
///
/// A whole-file override like the other core files: yours replaces the
/// built-in one rather than adding to it, so what runs is what you wrote and
/// nothing you did not. The default is compiled in, which is what makes
/// `toy` there before anything is configured.
pub fn providers(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !std.json.ObjectMap {
    const bytes = (try core(arena, io, env, "providers.json")) orelse default_providers;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
    if (parsed != .object) return .empty;
    return parsed.object;
}

/// The providers m8 ships with. Overridden whole by `core/providers.json`.
pub const default_providers = @embedFile("core/providers.json");

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "definitions and generated state have separate roots" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectEqualStrings("@/mathy.md", try nameFile(arena, "mathy"));
    try testing.expectEqualStrings("@/team/reviewer.md", try nameFile(arena, "team/reviewer"));
    try testing.expectEqualStrings("+/+.md", try nameFile(arena, "+"));
    try testing.expectEqualStrings("+/mathy/+.md", try nameFile(arena, "mathy/+"));
    try testing.expectEqualStrings("+/mathy/+/abcdefghij.md", try nameFile(arena, "mathy/+/abcdefghij"));
}

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

test "mob scratch is generated state beside definitions" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const t = try Tree.init(arena, &threaded, "m8-config-scratch");
    defer t.deinit(arena);
    try t.write(arena, "@/team/reviewer.md", "#### :brain:/local/tiny\n");
    const dirs = [_][]const u8{t.root};

    const got = (try mobTmp(arena, t.io, &dirs, "team/reviewer")).?;
    try testing.expectEqualStrings(try t.join(arena, "+/team/.tmpdir"), got);
    var scratch = try std.Io.Dir.cwd().openDir(t.io, got, .{});
    scratch.close(t.io);
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
