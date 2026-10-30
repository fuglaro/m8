//! Finding configuration.
//!
//! Config directories are searched nearest first: registered `.m8-st8/` paths
//! from the nearest project, then the user's own and the system's.
//! Children inherit the parent's validated `M8_ST8_DIRS` without revalidation.
//!
//! `core/` is searched the same way. A file is taken from the nearest
//! directory that has one. Providers are named files under core/providers/,
//! so registering a config directory explicitly trusts its contents.

const std = @import("std");
const Allocator = std.mem.Allocator;
const highlight = @import("m8/highlight.zig");
const build_options = @import("build_options");

pub const max_file = 4 * 1024 * 1024;

/// The config directories m8 found, nearest first and `:` between, as a
/// child is told them.
pub const dirs_var = "M8_ST8_DIRS";
/// Layer metadata must survive tools that narrow HOME/XDG variables.
pub const user_root_var = "M8_ST8_USER_ROOT";
pub const data_root_var = "M8_ST8_DATA_ROOT";

/// Explicit storage context. Roots are ordered project, user, system; a pinned
/// context retains layer metadata while restricting document lookup to one mob.
pub const Dirs = struct {
    roots: []const []const u8 = &.{},
    user_root: ?[]const u8 = null,
    system_root: []const u8 = system_dir,
    data_root: ?[]const u8 = null,
    mob: ?[]const u8 = null,
};

/// Resolve native discovery once, including the writable XDG data location.
pub fn discover(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) !Dirs {
    var user = try userDir(arena, env);
    var data: ?[]const u8 = if (absoluteEnv(env, "XDG_DATA_HOME")) |home|
        try std.fs.path.join(arena, &.{ home, "m8-st8" })
    else if (absoluteEnv(env, "HOME")) |home|
        try std.fs.path.join(arena, &.{ home, ".local", "share", "m8-st8" })
    else
        null;
    if (env.get(dirs_var) != null) {
        if (env.get(user_root_var)) |root| user = if (root.len == 0) null else root;
        if (env.get(data_root_var)) |root| data = if (root.len == 0) null else root;
    }
    var dirs: std.ArrayList([]const u8) = .empty;
    var project: ?[]const u8 = null;
    if (env.get(dirs_var)) |told| {
        var it = std.mem.tokenizeScalar(u8, told, ':');
        var include_user = false;
        var include_system = false;
        while (it.next()) |raw| {
            const d = try std.fs.path.resolve(arena, &.{raw});
            if (std.mem.eql(u8, d, system_dir)) {
                include_system = true;
                continue;
            }
            if (user != null and std.mem.eql(u8, d, user.?)) {
                include_user = true;
                continue;
            }
            if (project == null and (isChild(env) or try registered(arena, io, env, d))) project = d;
        }
        if (project) |p| try dirs.append(arena, p);
        if (include_user) try dirs.append(arena, user.?);
        if (include_system) try dirs.append(arena, system_dir);
        return .{ .roots = try dirs.toOwnedSlice(arena), .user_root = user, .data_root = data };
    } else {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = std.process.currentPath(io, &buf) catch 0;
        var walk: []const u8 = buf[0..len];
        while (walk.len > 0) {
            const candidate = try std.fs.path.join(arena, &.{ walk, dir_name });
            if (try directoryExists(io, candidate)) {
                if (try registered(arena, io, env, candidate)) project = candidate;
                break; // only the nearest project, never an ancestor overlay
            }
            const parent = std.fs.path.dirname(walk) orelse break;
            if (parent.len == walk.len) break;
            walk = parent;
        }
    }
    if (project) |p| try dirs.append(arena, p);
    if (user) |u| try dirs.append(arena, u);
    try dirs.append(arena, system_dir);
    return .{ .roots = try dirs.toOwnedSlice(arena), .user_root = user, .data_root = data };
}

/// Publish a validated storage context at a native process boundary. This is
/// serialization of Dirs, not fresh discovery, and does not pin a child mob.
pub fn inherit(arena: Allocator, dirs: Dirs, env: *std.process.Environ.Map) !void {
    try env.put(dirs_var, try std.mem.join(arena, ":", dirs.roots));
    try env.put(user_root_var, dirs.user_root orelse "");
    try env.put(data_root_var, dirs.data_root orelse "");
}

/// Hidden beside a project, plain under the user's config root.
pub const dir_name = ".m8-st8";
pub const user_dir_name = "m8-st8";

/// What an administrator puts beneath everyone, and so the last searched. Its
/// Authored mobs and core resources are read here; writable system-mob state
/// lives under the user's XDG data home, never under the system config.
pub const system_dir = build_options.system_config_dir;

/// Where something new is kept: the nearest directory, unless the only one
/// there is the system's.
pub fn saveDir(dirs: Dirs) ?[]const u8 {
    if (dirs.roots.len == 0 or std.mem.eql(u8, dirs.roots[0], system_dir)) return null;
    return dirs.roots[0];
}

/// The user's own config directory, if there is one.
pub fn userDir(arena: Allocator, env: *const std.process.Environ.Map) !?[]const u8 {
    if (absoluteEnv(env, "XDG_CONFIG_HOME")) |xdg| {
        return try std.fs.path.resolve(arena, &.{ xdg, user_dir_name });
    } else if (absoluteEnv(env, "HOME")) |home| {
        return try std.fs.path.resolve(arena, &.{ home, ".config", user_dir_name });
    }
    return null;
}

fn absoluteEnv(env: *const std.process.Environ.Map, key: []const u8) ?[]const u8 {
    const value = env.get(key) orelse return null;
    return if (value.len > 0 and std.fs.path.isAbsolute(value)) value else null;
}

/// Every `core/` directory, nearest first, for relative provider commands.
pub fn coreDirs(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map) ![]const []const u8 {
    const dirs = try discover(arena, io, env);
    const out = try arena.alloc([]const u8, dirs.roots.len);
    for (dirs.roots, out) |d, *o| o.* = try std.fs.path.join(arena, &.{ d, "core" });
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
        return try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file));
    return null;
}

/// The trust registry lives in the user's private config tree. Entries contain
/// canonical paths; the hash in the name is only an index, never authority.
pub const registry_dir_name = "registry";

pub fn registryDir(arena: Allocator, env: *const std.process.Environ.Map) !?[]const u8 {
    const home = (try userDir(arena, env)) orelse return null;
    return try std.fs.path.join(arena, &.{ home, "core", registry_dir_name });
}

fn registrationFile(arena: Allocator, env: *const std.process.Environ.Map, canonical: []const u8) !?[]const u8 {
    const root = (try registryDir(arena, env)) orelse return null;

    var name: std.ArrayList(u8) = .empty;
    try name.appendSlice(arena, "st8");
    for (canonical) |ch| {
        // Bound the readable portion so the complete filename fits NAME_MAX.
        if (name.items.len >= 200) break;
        if (ch == '/') {
            try name.appendSlice(arena, "--");
        } else {
            try name.append(arena, if (std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-' or ch == '_') ch else '-');
        }
    }
    var suffix: [18]u8 = undefined;
    try name.appendSlice(arena, try std.fmt.bufPrint(&suffix, "--{x:0>16}", .{std.hash.Wyhash.hash(0, canonical)}));
    return try std.fs.path.join(arena, &.{ root, name.items });
}

pub fn isChild(env: *const std.process.Environ.Map) bool {
    return env.get("M8_CALL_ID") != null;
}

/// Test a registration, cleaning stale entries only in normal invocations.
pub fn registered(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map, path: []const u8) !bool {
    const maintain = !isChild(env);
    if (!try directoryExists(io, path)) {
        if (maintain) try deregisterContents(arena, io, env, path);
        return false;
    }
    const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, path, arena) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            if (maintain) try deregisterContents(arena, io, env, path);
            return false;
        },
        else => return err,
    };
    const entry = (try registrationFile(arena, env, canonical)) orelse return false;
    const contents = std.Io.Dir.cwd().readFileAlloc(io, entry, arena, .limited(std.fs.max_path_bytes)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return std.mem.eql(u8, contents, canonical);
}

pub fn registerPath(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map, path: []const u8) !void {
    const canonical = try std.Io.Dir.cwd().realPathFileAlloc(io, path, arena);
    const entry = (try registrationFile(arena, env, canonical)) orelse return error.NoHomeConfig;
    const parent = std.fs.path.dirname(entry).?;
    try std.Io.Dir.cwd().createDirPath(io, parent);
    const existing = std.Io.Dir.cwd().readFileAlloc(io, entry, arena, .limited(std.fs.max_path_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (existing) |contents| {
        if (std.mem.eql(u8, contents, canonical)) return;
        return error.RegistryHashCollision;
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = entry, .data = canonical });
}

fn deregisterContents(arena: Allocator, io: std.Io, env: *const std.process.Environ.Map, path: []const u8) !void {
    const root = (try registryDir(arena, env)) orelse return;
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const full = try std.fs.path.join(arena, &.{ root, entry.name });
        const contents = std.Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(std.fs.max_path_bytes)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        if (std.mem.eql(u8, contents, path)) try std.Io.Dir.cwd().deleteFile(io, full);
    }
}

/// Existing .m8-st8 directories from cwd upward, never descendants.
pub fn candidates(arena: Allocator, io: std.Io, cwd: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var walk = cwd;
    while (walk.len > 0) {
        const candidate = try std.fs.path.join(arena, &.{ walk, dir_name });
        if (try directoryExists(io, candidate)) {
            try out.append(arena, try std.Io.Dir.cwd().realPathFileAlloc(io, candidate, arena));
        }
        const parent = std.fs.path.dirname(walk) orelse break;
        if (parent.len == walk.len) break;
        walk = parent;
    }
    return out.toOwnedSlice(arena);
}

fn directoryExists(io: std.Io, path: []const u8) !bool {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => return err,
    };
    dir.close(io);
    return true;
}

fn exists(io: std.Io, path: []const u8) bool {
    var d = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

/// Authored mob and agent definitions live under `mobs/<mob>/<agent>.md`.
pub const definitions_dir = "mobs";

/// Generated state roots are selected from the authored mob's layer.
pub const state_dir = ".chats";

fn isStateName(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "//") != null or std.mem.endsWith(u8, name, "/+") or std.mem.indexOf(u8, name, "/+/") != null;
}

/// Validate mob/agent[//chat/path][/+[/turn]]. Empty components are only
/// meaningful at the single authored/chat boundary, never in filesystem paths.
pub fn mobName(name: []const u8) ?[]const u8 {
    if (name.len == 0 or name[0] == '/') return null;
    const chat_at = std.mem.indexOf(u8, name, "//");
    const history_at = std.mem.indexOf(u8, name, "/+/") orelse (if (std.mem.endsWith(u8, name, "/+")) @as(?usize, name.len - 2) else null);
    const authored_end = @min(chat_at orelse name.len, history_at orelse name.len);
    var authored_parts = std.mem.splitScalar(u8, name[0..authored_end], '/');
    const mob = authored_parts.next() orelse return null;
    if (!validComponent(mob)) return null;
    var count: usize = 1;
    while (authored_parts.next()) |part| {
        if (!validAgentComponent(part)) return null;
        count += 1;
    }
    if (count < 2) return null;
    var at = authored_end;
    if (chat_at != null and chat_at.? == at) {
        at += 2;
        const end = history_at orelse name.len;
        if (end <= at) return null;
        var chats = std.mem.splitScalar(u8, name[at..end], '/');
        while (chats.next()) |part| if (!validComponent(part)) return null;
        at = end;
    }
    if (at < name.len) {
        if (!std.mem.startsWith(u8, name[at..], "/+")) return null;
        at += 2;
        if (at < name.len) {
            if (name[at] != '/' or !validComponent(name[at + 1 ..]) or std.mem.indexOfScalar(u8, name[at + 1 ..], '/') != null) return null;
        }
    }
    return mob;
}

fn validAgentComponent(part: []const u8) bool {
    return validComponent(part) and part[0] != '_';
}

fn validComponent(part: []const u8) bool {
    return part.len > 0 and part[0] != '.' and !std.mem.eql(u8, part, "+") and std.mem.indexOfScalar(u8, part, '\\') == null;
}

/// An authored agent has at least mob/agent, with any depth of authored
/// path; generated `+` names are never definitions.
pub fn authored(name: []const u8) bool {
    if (mobName(name) == null or isStateName(name)) return false;
    return true;
}

/// Relative to an owning definition/state root, not an overlay lookup.
pub fn nameFile(arena: Allocator, name: []const u8) ![]const u8 {
    const mob = mobName(name) orelse return error.InvalidName;
    if (!isStateName(name) and !authored(name)) return error.InvalidName;
    const logical = name[mob.len + 1 ..];
    // A double slash is a logical delimiter, not a filesystem separator.
    // The reserved `_` component keeps subchats separate from authored agents.
    const rest = try std.mem.replaceOwned(u8, arena, logical, "//", "/_/");
    const chat = std.mem.indexOf(u8, name, "//") != null and std.mem.indexOf(u8, name, "/+/") == null and !std.mem.endsWith(u8, name, "/+");
    return if (isStateName(name))
        std.fmt.allocPrint(arena, "mobs/{s}/{s}/{s}{s}.md", .{ mob, state_dir, rest, if (chat) "/+" else "" })
    else
        std.fmt.allocPrint(arena, "mobs/{s}/{s}.md", .{ mob, rest });
}

pub const tmp_dir_name = ".mob-space";

fn hasFile(io: std.Io, path: []const u8) bool {
    var f = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}

/// Which config directory holds `rel`, nearest first.
///
/// `read` answers with the bytes. This answers with where they came from, for
/// anything that has to write beside a file rather than read it.
pub fn where(arena: Allocator, io: std.Io, dirs: Dirs, rel: []const u8) !?[]const u8 {
    if (std.mem.startsWith(u8, rel, "mobs/")) {
        const tail = rel[5..];
        const slash = std.mem.indexOfScalar(u8, tail, '/') orelse return null;
        const mob = tail[0..slash];
        const is_state = std.mem.startsWith(u8, tail[slash + 1 ..], state_dir ++ "/");
        if (is_state) {
            const selected = (try mobSelection(arena, io, dirs, try std.fmt.allocPrint(arena, "{s}/lookup", .{mob}))) orelse return null;
            const root = try stateRoot(arena, dirs, selected.root);
            return if (hasFile(io, try std.fs.path.join(arena, &.{ root, rel }))) root else null;
        }
        // Authored files overlay independently of the layer that owns state.
        for (dirs.roots) |root| if (hasFile(io, try std.fs.path.join(arena, &.{ root, rel }))) return root;
        return null;
    }
    for (dirs.roots) |dir| {
        if (hasFile(io, try std.fs.path.join(arena, &.{ dir, rel }))) return dir;
    }
    return null;
}

fn mobSelection(arena: Allocator, io: std.Io, dirs: Dirs, agent: []const u8) !?struct { root: []const u8, name: []const u8 } {
    const mob = mobName(agent) orelse return null;
    if (dirs.mob) |scope| if (!std.mem.eql(u8, scope, mob)) return error.CrossMobReference;
    for (dirs.roots) |root| {
        const candidate = try std.fs.path.join(arena, &.{ root, "mobs", mob });
        if (directoryExists(io, candidate) catch false) return .{ .root = root, .name = mob };
    }
    return null;
}

fn stateRoot(arena: Allocator, dirs: Dirs, root: []const u8) ![]const u8 {
    const layer: []const u8 = if (std.mem.eql(u8, root, dirs.system_root)) "system" else if (dirs.user_root != null and std.mem.eql(u8, root, dirs.user_root.?)) "user" else return root;
    return std.fs.path.join(arena, &.{ dirs.data_root orelse return error.NoDataHome, layer });
}

pub fn pin(arena: Allocator, io: std.Io, dirs: Dirs, name: []const u8) !Dirs {
    const selected = (try mobSelection(arena, io, dirs, name)) orelse return error.UnknownAgent;
    var pinned = dirs;
    pinned.mob = selected.name;
    return pinned;
}

/// Writable mob container: .chats and .mob-space are siblings within it.
pub fn mobHome(arena: Allocator, io: std.Io, dirs: Dirs, name: []const u8) !?[]const u8 {
    const selected = (try mobSelection(arena, io, dirs, name)) orelse return null;
    return try std.fs.path.resolve(arena, &.{ try stateRoot(arena, dirs, selected.root), "mobs", selected.name });
}

pub fn filePath(arena: Allocator, io: std.Io, dirs: Dirs, name: []const u8) ![]const u8 {
    if (!isStateName(name)) {
        const found = (try definition(arena, io, dirs, name, null)) orelse return error.UnknownAgent;
        return std.fs.path.join(arena, &.{ found.root, try nameFile(arena, name) });
    }
    const selected = (try mobSelection(arena, io, dirs, name)) orelse return error.UnknownAgent;
    const root = try stateRoot(arena, dirs, selected.root);
    return std.fs.path.join(arena, &.{ root, try nameFile(arena, name) });
}

/// Absolute owning config root for the mob (not its generated state path).
pub fn mobSt8Dir(
    arena: Allocator,
    io: std.Io,
    dirs: Dirs,
    agent: []const u8,
) !?[]const u8 {
    const selected = (try mobSelection(arena, io, dirs, agent)) orelse return null;
    return try std.fs.path.resolve(arena, &.{selected.root});
}

/// The directory for a mob's state, made absolute so children can locate the
/// mob independently of their temporary-directory policy.
pub fn mobDir(
    arena: Allocator,
    io: std.Io,
    dirs: Dirs,
    agent: []const u8,
) !?[]const u8 {
    const home = (try mobHome(arena, io, dirs, agent)) orelse return null;
    return try std.fs.path.join(arena, &.{ home, state_dir });
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
    dirs: Dirs,
    agent: []const u8,
) !?[]const u8 {
    const mob = (try mobDir(arena, io, dirs, agent)) orelse return null;
    const parent = std.fs.path.dirname(mob) orelse return null;
    const tmp = try std.fs.path.join(arena, &.{ parent, tmp_dir_name });
    try std.Io.Dir.cwd().createDirPath(io, tmp);
    // Canonical paths also work when XDG data home is reached through a symlink.
    const real = try std.Io.Dir.cwd().realPathFileAlloc(io, tmp, arena);
    return std.mem.trimEnd(u8, real, "/");
}

pub const Definition = struct { root: []const u8, bytes: []const u8 };

/// Read an authored definition, optionally starting strictly above `after`.
pub fn definition(arena: Allocator, io: std.Io, dirs: Dirs, name: []const u8, after: ?[]const u8) !?Definition {
    const rel = try nameFile(arena, name);
    var past = after == null;
    for (dirs.roots) |root| {
        if (!past) {
            if (std.mem.eql(u8, root, after.?)) past = true;
            continue;
        }
        const path = try std.fs.path.join(arena, &.{ root, rel });
        if (!hasFile(io, path)) continue;
        return .{ .root = root, .bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file)) };
    }
    return null;
}

pub const DefinitionError = @typeInfo(@typeInfo(@TypeOf(definition)).@"fn".return_type.?).error_union.error_set;

/// Read a file from the nearest config directory that has one.
pub fn read(arena: Allocator, io: std.Io, dirs: Dirs, rel: []const u8) !?[]const u8 {
    const root = (try where(arena, io, dirs, rel)) orelse return null;
    return std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(arena, &.{ root, rel }), arena, .limited(max_file)) catch null;
}

/// Providers are individual JSON files. The first file of each basename in
/// nearest-first core directories owns that provider; files are never merged.
pub fn providers(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !std.json.ObjectMap {
    var selected: std.json.ObjectMap = .empty;
    for (try coreDirs(arena, io, env)) |root| {
        const dir_path = try std.fs.path.join(arena, &.{ root, "providers" });
        var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if ((entry.kind != .file and entry.kind != .sym_link) or !std.mem.endsWith(u8, entry.name, ".json")) continue;
            const name = entry.name[0 .. entry.name.len - 5];
            if (selected.contains(name)) continue;
            const path = try std.fs.path.join(arena, &.{ dir_path, entry.name });
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file));
            const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
            try selected.put(arena, try arena.dupe(u8, name), parsed);
        }
    }
    return selected;
}

pub const Error = error{
    /// `tui` in core/config.json is not a list of words.
    BadTui,
    /// `highlights` in core/config.json is not a valid highlight string.
    BadHighlight,
};

/// What an address alone at a terminal opens: the `tui` of the nearest
/// core/config.json, the words of a command the address is
/// appended to. Null when none does, which leaves it to m8's own default.
pub fn tui(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !?[]const []const u8 {
    if (try core(arena, io, env, "config.json")) |bytes| {
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        if (parsed != .object) return null;
        const v = parsed.object.get("tui") orelse return null;
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

/// The markdown styles and wrapping from the nearest core/config.json.
/// An absent key uses the defaults; there is no key merging.
pub fn highlights(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
) !highlight.Options {
    var look: highlight.Options = .{};
    if (try core(arena, io, env, "config.json")) |bytes| {
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        if (parsed != .object) return look;
        const value = parsed.object.get("highlights") orelse return look;
        if (value != .string) return Error.BadHighlight;
        highlight.parseHighlights(&look, value.string) catch return Error.BadHighlight;
    }
    return look;
}

const testing = std.testing;
const test_tmp = @import("test_tmp.zig");

test "registry filenames use st8 and double-dash path separators" {
    var state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", "/config");
    const file = (try registrationFile(arena, &env, "/Users/jvl/dev/m8/.m8-st8")).?;
    try testing.expectEqualStrings("/config/m8-st8/core/registry/st8--Users--jvl--dev--m8--.m8-st8--74f65428bd20454e", file);
}

test "config trust entries are canonical path contents indexed by wyhash" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const t = try Tree.init(arena, &threaded, "m8-register-test");
    defer t.deinit(arena);
    const st8 = try t.join(arena, "work/.m8-st8");
    try std.Io.Dir.cwd().createDirPath(t.io, st8);
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    try testing.expect(!(try registered(arena, t.io, &env, st8)));
    try registerPath(arena, t.io, &env, st8);
    try testing.expect(try registered(arena, t.io, &env, st8));
    // A copied entry name cannot authorize a different canonical path because
    // the stored contents are checked as well as the hash-derived filename.
    const sibling = try t.join(arena, "else/.m8-st8");
    try std.Io.Dir.cwd().createDirPath(t.io, sibling);
    try testing.expect(!(try registered(arena, t.io, &env, sibling)));
    try std.Io.Dir.cwd().deleteTree(t.io, st8);
    try testing.expect(!(try registered(arena, t.io, &env, st8)));
    const root = (try registryDir(arena, &env)).?;
    var registry = try std.Io.Dir.cwd().openDir(t.io, root, .{ .iterate = true });
    defer registry.close(t.io);
    var entries = registry.iterate();
    try testing.expect((try entries.next(t.io)) == null);
}

test "inherited configs retain only registered directories and user/system roots" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const t = try Tree.init(arena, &threaded, "m8-trusted-discovery");
    defer t.deinit(arena);
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    const home = (try userDir(arena, &env)).?;
    _ = try std.Io.Dir.cwd().createDirPathStatus(t.io, home, .fromMode(0o700));
    if (@import("builtin").os.tag != .windows) {
        const stat = try std.Io.Dir.cwd().statFile(t.io, home, .{});
        try testing.expectEqual(@as(std.posix.mode_t, 0o700), stat.permissions.toMode() & 0o777);
    }
    const trusted = try t.join(arena, "work/.m8-st8");
    const untrusted = try t.join(arena, "other/.m8-st8");
    try std.Io.Dir.cwd().createDirPath(t.io, trusted);
    try std.Io.Dir.cwd().createDirPath(t.io, untrusted);
    try registerPath(arena, t.io, &env, trusted);
    try env.put(dirs_var, try std.mem.join(arena, ":", &.{ untrusted, trusted, home, system_dir }));
    const dirs = try discover(arena, t.io, &env);
    try testing.expectEqual(@as(usize, 3), dirs.roots.len);
    try testing.expectEqualStrings(trusted, dirs.roots[0]);
    try testing.expectEqualStrings(home, dirs.roots[1]);
    try testing.expectEqualStrings(system_dir, dirs.roots[2]);
}

test "definitions and generated state have separate roots" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectError(error.InvalidName, nameFile(arena, "mathy"));
    try testing.expectEqualStrings("mobs/team/reviewer.md", try nameFile(arena, "team/reviewer"));
    try testing.expectError(error.InvalidName, nameFile(arena, "+"));
    try testing.expectEqualStrings("mobs/team/.chats/reviewer/+.md", try nameFile(arena, "team/reviewer/+"));
    try testing.expectEqualStrings("mobs/team/.chats/reviewer/+/abcdefghij.md", try nameFile(arena, "team/reviewer/+/abcdefghij"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/+.md", try nameFile(arena, "mob/agent/+"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/+/qgivwhgxnh.md", try nameFile(arena, "mob/agent/+/qgivwhgxnh"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/_/delegated/+.md", try nameFile(arena, "mob/agent//delegated"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/_/delegated/+/qgivwhgxnh.md", try nameFile(arena, "mob/agent//delegated/+/qgivwhgxnh"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/_/delegated/subtask/+.md", try nameFile(arena, "mob/agent//delegated/subtask"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/forked/+.md", try nameFile(arena, "mob/agent/forked/+"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/forked/+/qgivwhgxnh.md", try nameFile(arena, "mob/agent/forked/+/qgivwhgxnh"));
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
    try testing.expectEqualStrings("near", (try read(arena, t.io, Dirs{ .roots = &dirs }, "mathy.md")).?);
    // Falling through to a further directory is how a user config backs a
    // project one, rather than being replaced by it.
    try testing.expectEqualStrings("far only", (try read(arena, t.io, Dirs{ .roots = &dirs }, "only.md")).?);
    try testing.expect((try read(arena, t.io, Dirs{ .roots = &dirs }, "absent.md")) == null);
}

test "mob scratch is generated state beside definitions" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const t = try Tree.init(arena, &threaded, "m8-config-scratch");
    defer t.deinit(arena);
    try t.write(arena, "mobs/team/reviewer.md", "* :brain::/local/tiny\n");
    const dirs = [_][]const u8{t.root};

    const st8 = (try mobSt8Dir(arena, t.io, Dirs{ .roots = &dirs }, "team/reviewer")).?;
    try testing.expectEqualStrings(t.root, st8);
    try testing.expect(std.fs.path.isAbsolute(st8));
    const mob = (try mobDir(arena, t.io, Dirs{ .roots = &dirs }, "team/reviewer")).?;
    try testing.expectEqualStrings(try t.join(arena, "mobs/team/.chats"), mob);
    try testing.expect(std.fs.path.isAbsolute(mob));
    const got = (try mobTmp(arena, t.io, Dirs{ .roots = &dirs }, "team/reviewer")).?;
    try testing.expectEqualStrings(try t.join(arena, "mobs/team/.mob-space"), got);
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

test "unregistered config paths in inherited M8_ST8_DIRS are filtered" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var env: std.process.Environ.Map = .init(arena);
    try env.put(dirs_var, "/p/.m8-st8:/u/m8-st8");
    const dirs = try discover(arena, threaded.io(), &env);
    try testing.expectEqual(@as(usize, 0), dirs.roots.len);
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

test "core config is selected per file, never by absent keys" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-config-highlights");
    defer t.deinit(arena);
    try t.write(arena, "near/core/config.json", "{}");
    try t.write(arena, "m8-st8/core/config.json", "{\"highlights\":\"quote:fg4\"}");
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    const near = try t.join(arena, "near");
    const far = try t.join(arena, "m8-st8");
    try registerPath(arena, t.io, &env, near);
    try registerPath(arena, t.io, &env, far);
    try env.put(dirs_var, try std.mem.join(arena, ":", &.{ near, far }));

    var p = try highlights(arena, t.io, &env);
    try testing.expectEqual(@as(?u16, 245), p.palette.quote.fg);
    try testing.expectEqual(@as(u8, 70), p.wrap_literal);
    try testing.expectEqual(@as(u8, 90), p.wrap_word);
    try t.write(arena, "near/core/config.json", "{\"highlights\":\"list:fg2,wrap:literal:0,wrap:word:100\"}");
    p = try highlights(arena, t.io, &env);
    try testing.expectEqual(@as(u8, 0), p.wrap_literal);
    try testing.expectEqual(@as(u8, 100), p.wrap_word);
    try testing.expectEqual(@as(?u16, 2), p.palette.list.fg);
    try testing.expectEqual(@as(?u16, 245), p.palette.quote.fg);
}

test "highlight config rejects wrong value types and invalid style specs" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-config-bad-highlights");
    defer t.deinit(arena);
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    try registerPath(arena, t.io, &env, t.root);
    try env.put(dirs_var, t.root);

    try t.write(arena, "core/config.json", "{\"highlights\":[]}");
    try testing.expectError(Error.BadHighlight, highlights(arena, t.io, &env));
    try t.write(arena, "core/config.json", "{\"highlights\":\"quote:fg999\"}");
    try testing.expectError(Error.BadHighlight, highlights(arena, t.io, &env));
}

test "the system's directory is never where anything is kept" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expect(saveDir(.{}) == null);
    try testing.expect(saveDir(.{ .roots = &.{system_dir} }) == null);
    try testing.expectEqualStrings("/u", saveDir(.{ .roots = &.{ "/u", system_dir } }).?);
    try testing.expect((try mobTmp(arena, threaded.io(), Dirs{ .roots = &.{system_dir} }, "")) == null);
}

test "child validation preserves stale registrations and normal validation cleans them" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const root = try test_tmp.make(arena, io, "m8-child-registry");
    defer std.Io.Dir.cwd().deleteTree(io, root) catch {};
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", root);
    const project = try std.fs.path.join(arena, &.{ root, "project" });
    try std.Io.Dir.cwd().createDir(io, project, .default_dir);
    try registerPath(arena, io, &env, project);
    const entry = (try registrationFile(arena, &env, project)).?;
    try std.Io.Dir.cwd().deleteTree(io, project);
    try env.put("M8_CALL_ID", "c1");
    try testing.expect(!try registered(arena, io, &env, project));
    try testing.expectEqualStrings(project, try std.Io.Dir.cwd().readFileAlloc(io, entry, arena, .limited(max_file)));
    _ = env.swapRemove("M8_CALL_ID");
    try testing.expect(!try registered(arena, io, &env, project));
    try testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(io, entry, arena, .limited(max_file)));
}

test "children use the validated inherited list without a registry" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const root = try test_tmp.make(arena, io, "m8-inherited-dirs");
    defer std.Io.Dir.cwd().deleteTree(io, root) catch {};
    var parent: std.process.Environ.Map = .init(arena);
    try parent.put("XDG_CONFIG_HOME", root);
    const trusted = try std.fs.path.join(arena, &.{ root, "trusted" });
    const untrusted = try std.fs.path.join(arena, &.{ root, "untrusted" });
    try std.Io.Dir.cwd().createDir(io, trusted, .default_dir);
    try std.Io.Dir.cwd().createDir(io, untrusted, .default_dir);
    try registerPath(arena, io, &parent, trusted);
    const original = try std.mem.join(arena, ":", &.{ trusted, untrusted });
    try parent.put(dirs_var, original);
    const validated = try discover(arena, io, &parent);
    try testing.expectEqual(@as(usize, 1), validated.roots.len);
    try testing.expectEqualStrings(trusted, validated.roots[0]);

    var child = try parent.clone(arena);
    try child.put(dirs_var, try std.mem.join(arena, ":", validated.roots));
    try child.put("M8_CALL_ID", "c1");
    // Neither the inherited roots nor the registry need to remain accessible.
    try std.Io.Dir.cwd().deleteTree(io, trusted);
    try child.put("XDG_CONFIG_HOME", "/dev/null");
    const inherited = try discover(arena, io, &child);
    try testing.expectEqual(@as(usize, 1), inherited.roots.len);
    try testing.expectEqualStrings(trusted, inherited.roots[0]);
    try testing.expectEqualStrings(original, parent.get(dirs_var).?);
    try child.put(dirs_var, "");
    try testing.expectEqual(@as(usize, 0), (try discover(arena, io, &child)).roots.len);

    // A normal invocation still validates, rather than trusting the input list.
    try parent.put("XDG_CONFIG_HOME", "/dev/null");
    try parent.put(dirs_var, untrusted);
    try testing.expectError(error.NotDir, discover(arena, io, &parent));
}

test "a mob directory owns state placement while definitions overlay independently" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-mob-shadow");
    defer t.deinit(arena);
    const near = try t.join(arena, "near");
    const far = try t.join(arena, "far");
    const dirs: Dirs = .{ .roots = &.{ near, far } };
    try t.write(arena, "far/mobs/team/agent.md", "far");
    try t.write(arena, "far/mobs/team/.chats/agent/+.md", "far state");
    try testing.expectEqualStrings("far", (try read(arena, t.io, dirs, try nameFile(arena, "team/agent"))).?);
    try std.Io.Dir.cwd().createDirPath(t.io, try t.join(arena, "near/mobs/team"));
    try testing.expectEqualStrings("far", (try read(arena, t.io, dirs, try nameFile(arena, "team/agent"))).?);
    try testing.expect((try read(arena, t.io, dirs, try nameFile(arena, "team/agent/+"))) == null);
    try t.write(arena, "near/mobs/team/other.md", "near");
    try testing.expectEqualStrings("far", (try read(arena, t.io, dirs, try nameFile(arena, "team/agent"))).?);
    try testing.expectEqualStrings("near", (try read(arena, t.io, dirs, try nameFile(arena, "team/other"))).?);
    try testing.expectEqualStrings(try t.join(arena, "near/mobs/team/.chats/other/+.md"), try filePath(arena, t.io, dirs, "team/other/+"));
}

test "user and system mob state follows its authored layer into XDG data" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-relocated-state");
    defer t.deinit(arena);
    const user = try t.join(arena, "user");
    const system = try t.join(arena, "system");
    const data = try t.join(arena, "data");
    const dirs: Dirs = .{ .roots = &.{ user, system }, .user_root = user, .system_root = system, .data_root = data };
    try t.write(arena, "user/mobs/team/agent.md", "user definition");
    try t.write(arena, "system/mobs/base/agent.md", "system definition");
    // Old/co-located state is never consulted for a relocated mob.
    try t.write(arena, "user/mobs/team/.chats/agent/+.md", "wrong");
    try testing.expect((try read(arena, t.io, dirs, try nameFile(arena, "team/agent/+"))) == null);
    const session = @import("session.zig");
    try session.write(arena, t.io, dirs, "team/agent/+/one", &.{.{ .sigil = .agent, .value = "team/agent" }});
    try session.point(arena, t.io, dirs, "team/agent/+", "team/agent/+/one");
    try testing.expectEqualStrings("team/agent/+/one", try session.head(arena, t.io, dirs, "team/agent//job/sub"));
    try testing.expectEqualStrings(try t.join(arena, "data/user/mobs/team/.chats/agent/+.md"), try filePath(arena, t.io, dirs, "team/agent/+"));
    try testing.expectEqualStrings(try t.join(arena, "data/system/mobs/base/.chats/agent/+.md"), try filePath(arena, t.io, dirs, "base/agent/+"));
    try testing.expectEqualStrings(try t.join(arena, "data/user/mobs/team/.mob-space"), (try mobTmp(arena, t.io, dirs, "team/agent")).?);
    try testing.expectEqualStrings(try t.join(arena, "data/system/mobs/base/.mob-space"), (try mobTmp(arena, t.io, dirs, "base/agent")).?);
    try session.unpoint(arena, t.io, dirs, "team/agent/+");
    try testing.expectEqualStrings("team/agent", try session.head(arena, t.io, dirs, "team/agent"));
    // A new empty user mob owns state placement while definitions still fall through.
    try std.Io.Dir.cwd().createDirPath(t.io, try t.join(arena, "user/mobs/base"));
    try testing.expectEqualStrings("system definition", (try read(arena, t.io, dirs, try nameFile(arena, "base/agent"))).?);
    try testing.expectEqualStrings(try t.join(arena, "data/user/mobs/base/.chats/agent/+.md"), try filePath(arena, t.io, dirs, "base/agent/+"));
}

test "pin preserves roots for authored overlays while refusing another mob's state" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-pinned-mob");
    defer t.deinit(arena);
    const near = try t.join(arena, "near");
    const far = try t.join(arena, "far");
    try t.write(arena, "far/mobs/team/agent.md", "far agent");
    try t.write(arena, "far/mobs/team/helper.md", "far helper");
    try t.write(arena, "near/mobs/other/agent.md", "other agent");
    const dirs: Dirs = .{ .roots = &.{ near, far } };
    const pinned = try pin(arena, t.io, dirs, "team/agent");
    try t.write(arena, "near/mobs/team/helper.md", "new shadow");
    try testing.expectEqualStrings("new shadow", (try read(arena, t.io, pinned, try nameFile(arena, "team/helper"))).?);
    try testing.expectEqualStrings("other agent", (try read(arena, t.io, pinned, try nameFile(arena, "other/agent"))).?);
    try testing.expectError(error.CrossMobReference, read(arena, t.io, pinned, try nameFile(arena, "other/agent/+")));
}

test "provider filename selects a whole entry, without merging fields" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-provider-files");
    defer t.deinit(arena);
    const near = try t.join(arena, "project");
    const user = try t.join(arena, "m8-st8");
    try t.write(arena, "project/core/providers/local.json", "{\"cmd\":[\"near\"]}");
    try t.write(arena, "m8-st8/core/providers/local.json", "{\"cmd\":[\"far\"],\"url\":\"secret\"}");
    try t.write(arena, "m8-st8/core/providers/other.json", "{\"cmd\":[\"other\"]}");
    var env: std.process.Environ.Map = .init(arena);
    try env.put("XDG_CONFIG_HOME", t.root);
    try env.put("M8_CALL_ID", "fixture");
    try env.put(dirs_var, try std.mem.join(arena, ":", &.{ near, user }));
    const entries = try providers(arena, t.io, &env);
    try testing.expectEqual(@as(usize, 2), entries.count());
    const local = entries.get("local").?.object;
    try testing.expectEqualStrings("near", local.get("cmd").?.array.items[0].string);
    try testing.expect(local.get("url") == null);
    // A malformed nearer file is an error, never a reason to use the far one.
    try t.write(arena, "project/core/providers/local.json", "{");
    try testing.expectError(error.UnexpectedEndOfInput, providers(arena, t.io, &env));
}

test "storage names reject top-level agents and traversal, and allow nested authored agents" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    for ([_][]const u8{ "agent", "mob/.hidden", "mob/../agent", "mob/agent/../+", "/mob/agent", "mob/agent//+", "mob/agent///chat", "mob/agent//chat//child", "mob/agent//../chat", "mob/agent//.hidden", "mob/agent//chat/+/id/extra", "mob/agent/+/id//chat", "+", "mob/_", "mob/_agent", "mob/agent/_nested", "mob/agent/utils/_shields" }) |name| {
        try testing.expectError(error.InvalidName, nameFile(a.allocator(), name));
    }
    try testing.expectEqualStrings("mobs/mob/agent/nested.md", try nameFile(a.allocator(), "mob/agent/nested"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/_/forked/+/qgivwhgxnh.md", try nameFile(a.allocator(), "mob/agent//forked/+/qgivwhgxnh"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/_/forked/+.md", try nameFile(a.allocator(), "mob/agent//forked"));
    try testing.expectEqualStrings("mobs/mob/.chats/agent/forked/+.md", try nameFile(a.allocator(), "mob/agent/forked/+"));
}

test "discovery selects at most one project and resolves the data home explicitly" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var env: std.process.Environ.Map = .init(arena);
    try env.put("HOME", "/home/test");
    try env.put("M8_CALL_ID", "fixture");
    try env.put(dirs_var, "/near/.m8-st8:/far/.m8-st8:/home/test/.config/m8-st8:/etc/m8-st8");
    var dirs = try discover(arena, threaded.io(), &env);
    try testing.expectEqual(@as(usize, 3), dirs.roots.len);
    try testing.expectEqualStrings("/near/.m8-st8", dirs.roots[0]);
    try testing.expectEqualStrings("/home/test/.local/share/m8-st8", dirs.data_root.?);
    try env.put("XDG_DATA_HOME", "/data");
    dirs = try discover(arena, threaded.io(), &env);
    try testing.expectEqualStrings("/data/m8-st8", dirs.data_root.?);
}

test "child storage layer identity survives a narrowed HOME and XDG environment" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try Tree.init(arena, &threaded, "m8-child-layers");
    defer t.deinit(arena);
    var env: std.process.Environ.Map = .init(arena);
    try env.put("HOME", t.root);
    try env.put("M8_CALL_ID", "fixture");
    const user = try t.join(arena, ".config/m8-st8");
    const project = try t.join(arena, "project");
    try env.put(dirs_var, try std.mem.join(arena, ":", &.{ project, user, system_dir }));
    try t.write(arena, ".config/m8-st8/mobs/team/agent.md", "user definition");
    const parent = try discover(arena, t.io, &env);
    try inherit(arena, parent, &env);
    try env.put("HOME", try t.join(arena, "project/mobs/other/.mob-space"));
    try env.put("XDG_CONFIG_HOME", "/narrow/config");
    try env.put("XDG_DATA_HOME", "/narrow/data");
    const child = try discover(arena, t.io, &env);
    try testing.expectEqual(@as(usize, 3), child.roots.len);
    try testing.expectEqualStrings(parent.user_root.?, child.user_root.?);
    try testing.expectEqualStrings(parent.data_root.?, child.data_root.?);
    try testing.expectEqualStrings(try filePath(arena, t.io, parent, "team/agent/+"), try filePath(arena, t.io, child, "team/agent/+"));
}
