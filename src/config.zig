//! Finding configuration.
//!
//! Config directories are searched nearest first: every `.m8-st8/` from the
//! working directory upward, the way git finds `.git`, then the user's own,
//! then the system's. A child m8 runs is told them as `M8_ST8_DIRS`, and
//! takes them from there rather than finding its own.
//!
//! `core/` is searched the same way. A file is taken from the nearest
//! directory that has one, and `providers.json` is merged through all of them,
//! so running m8 in a directory trusts the config found from it.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_file = 4 * 1024 * 1024;

/// The config directories m8 found, nearest first and `:` between, as a
/// child is told them.
pub const dirs_var = "M8_ST8_DIRS";

/// Config directories, nearest first.
pub fn discover(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const []const u8 {
    var dirs: std.ArrayList([]const u8) = .empty;
    if (env.get(dirs_var)) |told| {
        var it = std.mem.tokenizeScalar(u8, told, ':');
        while (it.next()) |d| try dirs.append(arena, d);
        return dirs.toOwnedSlice(arena);
    }

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
    if (exists(io, system_dir)) try dirs.append(arena, system_dir);
    return dirs.toOwnedSlice(arena);
}

/// Hidden beside a project, plain under the user's config root.
pub const dir_name = ".m8-st8";
pub const user_dir_name = "m8-st8";

/// What an administrator puts beneath everyone, and so the last searched. Its
/// `core/` and `@/` are read like any other; it holds no `+/`, because state
/// belongs to whoever made it, and nothing is ever written here.
pub const system_dir = "/etc/m8-st8";

/// Where something new is kept: the nearest directory, unless the only one
/// there is the system's.
pub fn saveDir(dirs: []const []const u8) ?[]const u8 {
    if (dirs.len == 0 or std.mem.eql(u8, dirs[0], system_dir)) return null;
    return dirs[0];
}

/// The user's own config directory, if there is one.
pub fn userDir(arena: Allocator, env: *const std.process.Environ.Map) !?[]const u8 {
    if (env.get("XDG_CONFIG_HOME")) |xdg| {
        return try std.fs.path.join(arena, &.{ xdg, user_dir_name });
    } else if (env.get("HOME")) |home| {
        return try std.fs.path.join(arena, &.{ home, ".config", user_dir_name });
    }
    return null;
}

/// Every `core/` there could be, nearest first. Where a provider command
/// written as a relative name is looked for.
pub fn coreDirs(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const []const u8 {
    const dirs = try discover(arena, io, env);
    const out = try arena.alloc([]const u8, dirs.len);
    for (dirs, out) |d, *o| o.* = try std.fs.path.join(arena, &.{ d, "core" });
    return out;
}

/// Every `core/` file of a name that is there to read, nearest first.
pub fn coreFiles(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    name: []const u8,
) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (try coreDirs(arena, io, env)) |dir| {
        const path = try std.fs.path.join(arena, &.{ dir, name });
        _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch continue;
        try out.append(arena, path);
    }
    return out.items;
}

/// Read the nearest `core/` file of a name. Null when there is none.
pub fn core(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    name: []const u8,
) !?[]const u8 {
    for (try coreFiles(arena, io, env, name)) |path|
        return std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) catch continue;
    return null;
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
        if (std.mem.eql(u8, dir, system_dir) and std.mem.startsWith(u8, rel, state_dir ++ "/")) continue;
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
    // The mob is where the agent lives, so one named below the top keeps its
    // scratch below the top too. A ledger handed straight in names no agent,
    // and takes the nearest config's own, as does an agent the system
    // defines, since scratch is state.
    var base = saveDir(dirs) orelse return null;
    var mob: []const u8 = "";
    if (agent.len > 0) {
        if (try where(arena, io, dirs, try nameFile(arena, agent))) |found| {
            if (!std.mem.eql(u8, found, system_dir)) base = found;
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
        if (std.mem.eql(u8, dir, system_dir) and std.mem.startsWith(u8, rel, state_dir ++ "/")) continue;
        const path = try std.fs.path.join(arena, &.{ dir, rel });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) catch continue;
        return bytes;
    }
    return null;
}

/// The providers, from every `core/providers.json`.
///
/// They compose through the stack: each file adds its entries, and the nearest
/// entry of a name is the one that stands. m8 defines none.
pub fn providers(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !std.json.ObjectMap {
    var merged: std.json.ObjectMap = .empty;
    for (try coreFiles(arena, io, env, "providers.json")) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        if (parsed != .object) continue;
        var it = parsed.object.iterator();
        while (it.next()) |e| {
            if (merged.contains(e.key_ptr.*)) continue;
            try merged.put(arena, e.key_ptr.*, e.value_ptr.*);
        }
    }
    return merged;
}

pub const Error = error{
    /// `tui` in core/config.json is not a list of words.
    BadTui,
};

/// What an address alone at a terminal opens: the `tui` of the nearest
/// core/config.json that names one, the words of a command the address is
/// appended to. Null when none does, which leaves it to m8's own default.
pub fn tui(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !?[]const []const u8 {
    for (try coreFiles(arena, io, env, "config.json")) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        if (parsed != .object) continue;
        const v = parsed.object.get("tui") orelse continue;
        if (v != .array or v.array.items.len == 0) return Error.BadTui;
        const words = try arena.alloc([]const u8, v.array.items.len);
        for (v.array.items, words) |item, *w| {
            if (item != .string) return Error.BadTui;
            w.* = item.string;
        }
        return words;
    }
    return null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const test_tmp = @import("test_tmp.zig");

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
        return .{ .io = io, .threaded = threaded, .root = try test_tmp.make(gpa, io, name) };
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

test "directories a parent told are taken as told" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var env: std.process.Environ.Map = .init(arena);
    try env.put(dirs_var, "/p/.m8-st8:/u/m8-st8");
    const dirs = try discover(arena, undefined, &env);
    try testing.expectEqual(@as(usize, 2), dirs.len);
    try testing.expectEqualStrings("/p/.m8-st8", dirs[0]);
    try testing.expectEqualStrings("/u/m8-st8", dirs[1]);
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

test "the system's directory is never where anything is kept" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expect(saveDir(&.{}) == null);
    try testing.expect(saveDir(&.{system_dir}) == null);
    try testing.expectEqualStrings("/u", saveDir(&.{ "/u", system_dir }).?);
    try testing.expect((try mobTmp(arena, threaded.io(), &.{system_dir}, "")) == null);
}
