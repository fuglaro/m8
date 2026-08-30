//! Talking to a provider.
//!
//! A provider is a command. It reads an api-formatted request on stdin and
//! writes that api's response on stdout, which is the same shape a tool has —
//! a filter that stays in a pipeline. Reaching a url is one such command
//! rather than the privileged path, so anything you can write a program for
//! is a provider.
//!
//! Everything in the entry except `cmd` is handed to it as `M8_PROVIDER_*` on
//! top of the inherited environment. m8 knows only two of them: `cmd`, which
//! says what to run, and `api`, which says how to write the request and read
//! the answer. A `key` is nothing special to m8; it is passed through, and
//! whether it means anything is between you and the command.
//!
//! Locks are not applied here. That is safe rather than generous: a lock is a
//! sandbox the child is launched inside, and `sandbox-exec` is one way — a
//! provider inherits whatever m8 is already inside and can never shed it. So
//! this only ever means m8 adds nothing, which is what lets a jailed agent
//! still reach its own model. Trust is held where the command is written
//! down: `core/`, which a cloned project cannot reach.

const std = @import("std");
const Allocator = std.mem.Allocator;
const codec = @import("codec.zig");
const doc = @import("m8/doc.zig");

pub const Error = error{
    UnknownProvider,
    UnsupportedApi,
    NoCommand,
    CommandNotFound,
    CommandNotExecutable,
    ProviderFailed,
};

/// One entry from providers.json, as far as m8 reads it.
pub const Provider = struct {
    name: []const u8,
    api: []const u8,
    /// What to run, before any path has been resolved.
    cmd: []const []const u8,
    /// Everything else the entry said, for the environment. Only string
    /// values with lowercase-and-hyphen keys make it this far.
    args: []const Arg,

    pub fn get(p: Provider, key: []const u8) ?[]const u8 {
        for (p.args) |a| if (std.mem.eql(u8, a.key, key)) return a.value;
        return null;
    }
};

pub const Arg = struct {
    key: []const u8,
    value: []const u8,
};

/// The prefix every provider argument reaches its command under.
pub const env_prefix = "M8_PROVIDER_";

/// Read an entry, keeping what the command will be given.
///
/// Only string values with lowercase-and-hyphen keys are passed on, because
/// only those have an environment variable to be: `api-version` arrives as
/// `M8_PROVIDER_API_VERSION`. Anything else in the entry is m8's business or
/// nobody's. `cmd` is left behind — the command already knows what it is.
pub fn read(arena: Allocator, providers: std.json.ObjectMap, name: []const u8) !Provider {
    const v = providers.get(name) orelse return Error.UnknownProvider;
    if (v != .object) return Error.UnknownProvider;
    const o = v.object;

    var cmd: std.ArrayList([]const u8) = .empty;
    if (o.get("cmd")) |c| {
        if (c != .array) return Error.NoCommand;
        for (c.array.items) |item| {
            if (item != .string) return Error.NoCommand;
            try cmd.append(arena, item.string);
        }
    }
    if (cmd.items.len == 0) return Error.NoCommand;

    var args: std.ArrayList(Arg) = .empty;
    var it = o.iterator();
    while (it.next()) |e| {
        const key = e.key_ptr.*;
        // `cmd` is m8's alone — the command already knows what it is. `api`
        // goes through, because what to write may be the command's business
        // as much as m8's.
        if (std.mem.eql(u8, key, "cmd")) continue;
        if (e.value_ptr.* != .string) continue;
        if (!nameable(key)) continue;
        try args.append(arena, .{ .key = key, .value = e.value_ptr.*.string });
    }

    const api = if (o.get("api")) |a| (if (a == .string) a.string else codec.default) else codec.default;
    if (o.get("api") == null) try args.append(arena, .{ .key = "api", .value = api });

    return .{
        .name = name,
        .api = api,
        .cmd = cmd.items,
        .args = args.items,
    };
}

/// Whether a key has an environment variable to become: lowercase letters,
/// digits and hyphens. Anything else is left where it is rather than mangled
/// into a name that would collide with something.
fn nameable(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |c| {
        if (std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-') continue;
        return false;
    }
    return true;
}

/// `api-version` becomes `M8_PROVIDER_API_VERSION`.
pub fn envName(arena: Allocator, key: []const u8) ![]const u8 {
    const out = try arena.alloc(u8, env_prefix.len + key.len);
    @memcpy(out[0..env_prefix.len], env_prefix);
    for (key, env_prefix.len..) |c, i| out[i] = if (c == '-') '_' else std.ascii.toUpper(c);
    return out;
}

/// The environment a provider command is launched with: what m8 has, plus
/// everything the entry said.
pub fn environment(
    arena: Allocator,
    p: Provider,
    inherited: *const std.process.Environ.Map,
) !*const std.process.Environ.Map {
    var m = try inherited.clone(arena);
    for (p.args) |a| try m.put(try envName(arena, a.key), a.value);
    const boxed = try arena.create(std.process.Environ.Map);
    boxed.* = m;
    return boxed;
}

/// Where the command actually is.
///
/// `m8` means the m8 that is running, so a provider reaches this build rather
/// than whichever one happens to be on a PATH — or none at all. After that it
/// reads like a shell: an absolute path is one, a name that names a file in
/// `core/` is that file, and a bare word is searched for.
pub fn resolve(
    arena: Allocator,
    io: std.Io,
    self: []const u8,
    core_dir: ?[]const u8,
    cmd: []const []const u8,
) ![]const []const u8 {
    if (cmd.len == 0) return Error.NoCommand;

    var out: std.ArrayList([]const u8) = .empty;
    try out.append(arena, try locate(arena, io, self, core_dir, cmd[0]));
    try out.appendSlice(arena, cmd[1..]);
    return out.items;
}

fn locate(
    arena: Allocator,
    io: std.Io,
    self: []const u8,
    core_dir: ?[]const u8,
    first: []const u8,
) ![]const u8 {
    if (std.mem.eql(u8, first, "m8")) return self;
    if (first.len > 0 and first[0] == '/') return first;

    if (core_dir) |dir| {
        const path = try std.fs.path.join(arena, &.{ dir, first });
        if (look(io, path)) |found| {
            // Named a file that is there but cannot be run: say so rather
            // than falling through to something else of the same name.
            if (!found.runnable) return Error.CommandNotExecutable;
            return path;
        }
    }

    if (std.mem.indexOfScalar(u8, first, '/') == null) return first;
    return Error.CommandNotFound;
}

/// Whether a path names a file, and whether anyone may run it.
const Found = struct { runnable: bool };

fn look(io: std.Io, path: []const u8) ?Found {
    const st = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    if (st.kind != .file) return null;
    return .{ .runnable = st.permissions.toMode() & 0o111 != 0 };
}

/// The path of the m8 that is running.
///
/// Zig has no self-path for this target, so argv[0] is resolved the way a
/// shell resolved it: a path is made absolute, and a bare name is looked for
/// on PATH.
pub fn selfPath(
    arena: Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    argv0: []const u8,
) ![]const u8 {
    if (argv0.len == 0) return "m8";
    if (argv0[0] == '/') return argv0;

    if (std.mem.indexOfScalar(u8, argv0, '/') != null) {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = std.process.currentPath(io, &buf) catch 0;
        return std.fs.path.resolve(arena, &.{ buf[0..len], argv0 });
    }

    const path = env.get("PATH") orelse return argv0;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(arena, &.{ dir, argv0 });
        if (look(io, candidate)) |found| {
            if (found.runnable) return candidate;
        }
    }
    return argv0;
}

/// Run a provider and read what it says.
///
/// The request is written and stdin closed before anything is read back. A
/// provider reads its request before answering — it cannot answer otherwise —
/// so the one shape this would deadlock on is a command that writes more than
/// a pipe holds before reading, which is not a thing a provider does.
pub fn run(
    arena: Allocator,
    io: std.Io,
    argv: []const []const u8,
    environ: ?*const std.process.Environ.Map,
    request: []const u8,
    c: codec.Codec,
    sink: codec.Sink,
    err: *std.Io.Writer,
) !codec.Reply {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .environ_map = environ,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch return Error.CommandNotFound;

    var write_buf: [16 * 1024]u8 = undefined;
    var w = child.stdin.?.writerStreaming(io, &write_buf);
    try w.interface.writeAll(request);
    try w.interface.flush();
    child.stdin.?.close(io);
    child.stdin = null;

    var read_buf: [64 * 1024]u8 = undefined;
    var r = child.stdout.?.readerStreaming(io, &read_buf);
    const reply = try c.parse(arena, &r.interface, sink);

    var err_buf: [8 * 1024]u8 = undefined;
    var e = child.stderr.?.readerStreaming(io, &err_buf);
    const said = e.interface.allocRemaining(arena, .limited(8192)) catch "";

    switch (child.wait(io) catch return Error.ProviderFailed) {
        .exited => |code| if (code != 0) {
            const why = std.mem.trimEnd(u8, said, "\n");
            if (why.len > 0) {
                try err.print("m8: provider failed with exit code {d}: {s}\n", .{ code, why });
            } else {
                try err.print("m8: provider failed with exit code {d}\n", .{code});
            }
            return Error.ProviderFailed;
        },
        else => return Error.ProviderFailed,
    }
    return reply;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn providersFrom(arena: Allocator, json: []const u8) !std.json.ObjectMap {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    return v.object;
}

test "an entry is a command, an api, and whatever else it wants to say" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ps = try providersFrom(arena,
        \\{"local": {
        \\  "cmd": ["m8", "providers", "url"],
        \\  "url": "http://x/v1/chat/completions",
        \\  "key": "cat ~/.key",
        \\  "api-version": "2024-02-01",
        \\  "timeout": 30,
        \\  "Weird_Key": "ignored"
        \\}}
    );
    const p = try read(arena, ps, "local");

    try testing.expectEqualStrings(codec.default, p.api);
    try testing.expectEqual(@as(usize, 3), p.cmd.len);
    try testing.expectEqualStrings("m8", p.cmd[0]);

    // Strings with nameable keys go through; `cmd` never does, and neither
    // does a number or a key with no environment name to take.
    try testing.expectEqualStrings("http://x/v1/chat/completions", p.get("url").?);
    try testing.expectEqualStrings("cat ~/.key", p.get("key").?);
    try testing.expectEqualStrings("2024-02-01", p.get("api-version").?);
    try testing.expect(p.get("cmd") == null);
    try testing.expect(p.get("timeout") == null);
    try testing.expect(p.get("Weird_Key") == null);

    try testing.expectEqualStrings("M8_PROVIDER_API_VERSION", try envName(arena, "api-version"));
    try testing.expectEqualStrings("M8_PROVIDER_URL", try envName(arena, "url"));
}

test "an entry with no command is not a provider" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ps = try providersFrom(arena,
        \\{"bare": {"url": "http://x"}, "wrong": {"cmd": "not an array"}}
    );
    try testing.expectError(Error.NoCommand, read(arena, ps, "bare"));
    try testing.expectError(Error.NoCommand, read(arena, ps, "wrong"));
    try testing.expectError(Error.UnknownProvider, read(arena, ps, "nosuch"));
}

test "a command is found the way a shell would find it" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    const core_dir = try std.fs.path.join(arena, &.{ "/private/tmp", "m8-provider-resolve" });
    std.Io.Dir.cwd().deleteTree(io, core_dir) catch {};
    try std.Io.Dir.cwd().createDirPath(io, core_dir);
    defer std.Io.Dir.cwd().deleteTree(io, core_dir) catch {};

    const runnable = try std.fs.path.join(arena, &.{ core_dir, "runnable" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = runnable, .data = "#!/bin/sh\n", .flags = .{ .permissions = .executable_file } });
    const plain = try std.fs.path.join(arena, &.{ core_dir, "plain" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = plain, .data = "text\n" });

    // `m8` is this m8, whatever is on PATH.
    const self = "/opt/m8/bin/m8";
    try testing.expectEqualStrings(
        self,
        (try resolve(arena, io, self, core_dir, &.{ "m8", "providers", "url" }))[0],
    );
    // An absolute path is one.
    try testing.expectEqualStrings("/bin/sh", (try resolve(arena, io, self, core_dir, &.{"/bin/sh"}))[0]);
    // A file in core/ is that file.
    try testing.expectEqualStrings(runnable, (try resolve(arena, io, self, core_dir, &.{"runnable"}))[0]);
    // There, but not runnable, is an error rather than a fall-through.
    try testing.expectError(
        Error.CommandNotExecutable,
        resolve(arena, io, self, core_dir, &.{"plain"}),
    );
    // A bare name that is not in core/ is left for PATH.
    try testing.expectEqualStrings("curl", (try resolve(arena, io, self, core_dir, &.{"curl"}))[0]);
    // A path that is neither absolute nor in core/ has nowhere left to look.
    try testing.expectError(
        Error.CommandNotFound,
        resolve(arena, io, self, core_dir, &.{"nope/missing"}),
    );
    // Arguments are carried through untouched.
    const full = try resolve(arena, io, self, core_dir, &.{ "m8", "providers", "url" });
    try testing.expectEqual(@as(usize, 3), full.len);
    try testing.expectEqualStrings("providers", full[1]);
}

/// A sink that keeps what it is given, so a test can see what streamed rather
/// than only what came back at the end.
const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,

    fn sink(self: *Collect) codec.Sink {
        return .{ .ctx = self, .write = writeFn };
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
    }
};

test "a provider is a command: what it writes is the answer" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    var thrown: std.Io.Writer.Allocating = .init(arena);
    var collect: Collect = .{ .arena = arena };

    // Says the request back, so the test can see it arrived whole.
    const reply = try run(
        arena,
        io,
        &.{ "/bin/sh", "-c", "cat >/dev/null; printf '# :robot:\n> said it\n'" },
        null,
        "# :raising_hand:\n> ask\n",
        codec.m8.codec,
        collect.sink(),
        &thrown.writer,
    );
    try testing.expectEqualStrings("said it", reply.text);
    // Streamed as well as returned, which is what a terminal watches.
    try testing.expectEqualStrings("said it", collect.seen.items);
    try testing.expectEqual(@as(usize, 0), reply.calls.len);
}

test "a provider that fails says why, and the run stops" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    var thrown: std.Io.Writer.Allocating = .init(arena);
    var collect: Collect = .{ .arena = arena };

    try testing.expectError(Error.ProviderFailed, run(
        arena,
        io,
        &.{ "/bin/sh", "-c", "cat >/dev/null; echo 'that api is not supported' >&2; exit 3" },
        null,
        "",
        codec.m8.codec,
        collect.sink(),
        &thrown.writer,
    ));
    // The exit code and whatever it said, so the reason is not lost.
    try testing.expect(std.mem.indexOf(u8, thrown.written(), "exit code 3") != null);
    try testing.expect(std.mem.indexOf(u8, thrown.written(), "not supported") != null);
}

test "everything the entry said reaches the command, and nothing else does" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    const ps = try providersFrom(arena,
        \\{"probe": {
        \\  "cmd": ["/bin/sh"],
        \\  "url": "http://x/v1/chat/completions",
        \\  "api-version": "2024-02-01"
        \\}}
    );
    const p = try read(arena, ps, "probe");

    var inherited: std.process.Environ.Map = .init(arena);
    try inherited.put("M8_TEST_INHERITED", "yes");
    const environ = try environment(arena, p, &inherited);

    // On top of what was already there, not instead of it.
    try testing.expectEqualStrings("yes", environ.get("M8_TEST_INHERITED").?);
    try testing.expectEqualStrings("http://x/v1/chat/completions", environ.get("M8_PROVIDER_URL").?);
    try testing.expectEqualStrings("2024-02-01", environ.get("M8_PROVIDER_API_VERSION").?);
    // `api` goes, because the command may need to know what to write.
    try testing.expectEqualStrings(codec.default, environ.get("M8_PROVIDER_API").?);
    // `cmd` does not: the command already knows what it is.
    try testing.expect(environ.get("M8_PROVIDER_CMD") == null);

    var thrown: std.Io.Writer.Allocating = .init(arena);
    var collect: Collect = .{ .arena = arena };
    const reply = try run(
        arena,
        io,
        &.{ "/bin/sh", "-c", "cat >/dev/null; printf '# :robot:\n> %s\n' \"$M8_PROVIDER_URL\"" },
        environ,
        "",
        codec.m8.codec,
        collect.sink(),
        &thrown.writer,
    );
    try testing.expectEqualStrings("http://x/v1/chat/completions", reply.text);
}
