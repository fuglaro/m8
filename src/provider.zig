//! Talking to a provider.
//!
//! A provider is a command. It reads a request on stdin and writes a response
//! on stdout, which is the same shape a tool has — a filter that stays in a
//! pipeline. Reaching a url is one such command rather than the privileged
//! path, so anything you can write a program for is a provider.
//!
//! What m8 writes is the ledger, as m8, and what it reads is the turn, as m8.
//! A provider that speaks something else names two more commands, and the
//! three are one pipeline: `encode` makes the ledger a request, `cmd` gets it
//! answered, and `parse` makes the answer a turn. Which apis there are is
//! then nothing m8 holds a list of: the ones it ships are `m8 encode` and
//! `m8 parse`, named in an entry the way anyone's own would be.
//!
//! Every string in the entry is handed to all three as `M8_PROVIDER_*` on
//! top of the inherited environment. A `key` is nothing special to m8; it is
//! passed through, and whether it means anything is between you and the
//! command.
//!
//! Shields are not applied here. That is safe rather than generous: a shield
//! is the process a child is launched inside, and `sandbox-exec` is one way —
//! a provider inherits whatever m8 is already inside and can never shed it. So
//! this only ever means m8 adds nothing, which is what lets a jailed agent
//! still reach its own model. Trust is held where the command is written
//! down: `core/`, which a cloned project cannot reach.

const std = @import("std");
const Allocator = std.mem.Allocator;
const codec = @import("codec.zig");
const sigil = @import("m8/sigil.zig");
const doc = @import("m8/doc.zig");

pub const Error = error{
    UnknownProvider,
    NoCommand,
    CommandNotFound,
    CommandNotExecutable,
    ProviderFailed,
};

/// One object from core/providers/NAME.json, as far as m8 reads it.
pub const Provider = struct {
    name: []const u8,
    /// What to run, before any path has been resolved.
    cmd: []const []const u8,
    /// What makes the ledger a request for it, and its answer a turn. With
    /// neither, the command is handed m8 and answers in it.
    encode: ?[]const []const u8 = null,
    parse: ?[]const []const u8 = null,
    /// What lists the models it serves, one name a line. `m8 models` runs
    /// it; nothing else does.
    models: ?[]const []const u8 = null,
    /// Everything else the entry said, for the environment. Only strings,
    /// numbers and truths with lowercase-and-hyphen keys make it this far.
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
/// Only strings, numbers and truths with lowercase-and-hyphen keys are passed
/// on, because only those have an environment variable to be: `api-version`
/// arrives as `M8_PROVIDER_API_VERSION`, and `true` as `true`. Anything else in the entry is m8's business or
/// nobody's. The commands are left behind — each already knows what it is.
pub fn read(arena: Allocator, providers: std.json.ObjectMap, name: []const u8) !Provider {
    const v = providers.get(name) orelse return Error.UnknownProvider;
    if (v != .object) return Error.UnknownProvider;
    const o = v.object;

    const cmd = (try words(arena, o.get("cmd"))) orelse return Error.NoCommand;

    var args: std.ArrayList(Arg) = .empty;
    var it = o.iterator();
    while (it.next()) |e| {
        const key = e.key_ptr.*;
        // The commands are lists, so they stay behind with everything else
        // that has no one spelling: a command already knows what it is. A
        // number or a truth goes as its JSON text.
        const value = switch (e.value_ptr.*) {
            .string, .number_string => |t| t,
            .bool => |b| if (b) "true" else "false",
            .integer => |n| try std.fmt.allocPrint(arena, "{d}", .{n}),
            .float => |n| try std.fmt.allocPrint(arena, "{d}", .{n}),
            else => continue,
        };
        if (!nameable(key)) continue;
        try args.append(arena, .{ .key = key, .value = value });
    }

    return .{
        .name = name,
        .cmd = cmd,
        .encode = try words(arena, o.get("encode")),
        .parse = try words(arena, o.get("parse")),
        .models = try words(arena, o.get("models")),
        .args = args.items,
    };
}

/// A command as an entry writes it: a list of strings, with at least one.
fn words(arena: Allocator, v: ?std.json.Value) !?[]const []const u8 {
    const list = v orelse return null;
    if (list != .array or list.array.items.len == 0) return Error.NoCommand;
    var out: std.ArrayList([]const u8) = .empty;
    for (list.array.items) |item| {
        if (item != .string) return Error.NoCommand;
        try out.append(arena, item.string);
    }
    return out.items;
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

/// Add everything a provider entry said to the child environment already
/// made for it. Kept separate from cloning so a launch copies its base once.
pub fn addEnvironment(
    arena: Allocator,
    p: Provider,
    env: *std.process.Environ.Map,
) !void {
    for (p.args) |a| try env.put(try envName(arena, a.key), a.value);
    // The selected entry name is metadata, not an entry argument. Set it last
    // so an entry's own `name` field cannot shadow the actual selection.
    try env.put("M8_PROVIDER_NAME", p.name);
}

/// Where the command actually is.
///
/// `m8` means the m8 that is running, so a provider reaches this build rather
/// than whichever one happens to be on a PATH — or none at all. After that it
/// reads like a shell: an absolute path is one, a name that names a file in
/// a `core/` is that file, nearest first, and a bare word is searched for.
pub fn resolve(
    arena: Allocator,
    io: std.Io,
    self: []const u8,
    core_dirs: []const []const u8,
    cmd: []const []const u8,
) ![]const []const u8 {
    if (cmd.len == 0) return Error.NoCommand;

    var out: std.ArrayList([]const u8) = .empty;
    try out.append(arena, try locate(arena, io, self, core_dirs, cmd[0]));
    try out.appendSlice(arena, cmd[1..]);
    return out.items;
}

fn locate(
    arena: Allocator,
    io: std.Io,
    self: []const u8,
    core_dirs: []const []const u8,
    first: []const u8,
) ![]const u8 {
    if (std.mem.eql(u8, first, "m8")) return self;
    if (first.len > 0 and first[0] == '/') return first;

    for (core_dirs) |dir| {
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

    if (std.mem.indexOfScalar(u8, argv0, '/') != null) return fromCwd(arena, io, argv0);

    const path = env.get("PATH") orelse return argv0;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fs.path.join(arena, &.{ dir, argv0 });
        if (look(io, candidate)) |found| {
            // A PATH entry may itself be relative, and what is handed on is
            // read by something that has since changed directory.
            if (found.runnable) return if (dir[0] == '/') candidate else fromCwd(arena, io, candidate);
        }
    }
    return argv0;
}

/// A relative path, made absolute against the working directory.
fn fromCwd(arena: Allocator, io: std.Io, path: []const u8) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = std.process.currentPath(io, &buf) catch 0;
    return std.fs.path.resolve(arena, &.{ buf[0..len], path });
}

/// The commands a provider is, resolved: what makes the request, what gets
/// it answered, and what reads the answer. Only the middle one is always
/// there.
pub const Stages = struct {
    encode: ?[]const []const u8 = null,
    cmd: []const []const u8,
    parse: ?[]const []const u8 = null,
};

pub fn stages(
    arena: Allocator,
    io: std.Io,
    self: []const u8,
    core_dirs: []const []const u8,
    p: Provider,
) !Stages {
    return .{
        .encode = if (p.encode) |c| try resolve(arena, io, self, core_dirs, c) else null,
        .cmd = try resolve(arena, io, self, core_dirs, p.cmd),
        .parse = if (p.parse) |c| try resolve(arena, io, self, core_dirs, c) else null,
    };
}

/// Run a provider and read what it says.
///
/// The stages are one pipeline, each one's stdout the next one's stdin, and
/// m8 holds only the two ends: it writes the ledger to the first and reads
/// the turn from the last.
///
/// The ledger is written and stdin closed before anything is read back. A
/// stage reads what it is handed before answering — it cannot answer
/// otherwise — so the one shape this would deadlock on is a command that
/// writes more than a pipe holds before reading, which is not a thing a
/// provider does.
///
/// What a stage says on stderr is held until the turn is in. A provider that
/// answered has it passed on as it was said, and one that failed has it
/// given as the reason.
pub fn run(
    arena: Allocator,
    io: std.Io,
    s: Stages,
    environ: ?*const std.process.Environ.Map,
    ledger: []const u8,
    sink: codec.Sink,
    err: *std.Io.Writer,
) !codec.Reply {
    const names = [_][]const u8{ "encode", "cmd", "parse" };
    const argvs = [_]?[]const []const u8{ s.encode, s.cmd, s.parse };
    var children: [3]?std.process.Child = @splat(null);

    var first: ?std.Io.File = null;
    var last: ?std.Io.File = null;
    for (argvs, 0..) |argv, n| {
        children[n] = std.process.spawn(io, .{
            .argv = argv orelse continue,
            .environ_map = environ,
            .stdin = if (last) |from| .{ .file = from } else .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch return Error.CommandNotFound;
        // The stage before it is this one's to read now, and nobody else's:
        // held open here, its end would never be seen.
        if (last) |from| from.close(io) else first = children[n].?.stdin.?;
        children[n].?.stdin = null;
        for (children[0..n]) |*before| if (before.*) |*b| {
            b.stdout = null;
        };
        last = children[n].?.stdout.?;
    }

    var write_buf: [16 * 1024]u8 = undefined;
    var w = first.?.writerStreaming(io, &write_buf);
    try w.interface.writeAll(ledger);
    try w.interface.flush();
    first.?.close(io);

    var read_buf: [64 * 1024]u8 = undefined;
    var r = last.?.readerStreaming(io, &read_buf);
    const reply = codec.m8.codec.parse(arena, &r.interface, sink);
    // A parser may have stopped at the first malformed line. Drain what
    // remains before waiting, or a stage that wrote a large response can stay
    // blocked with its stdout pipe full and hide the diagnostic.
    if (reply) |_| {} else |_| _ = r.interface.discardRemaining() catch {};

    var failed = false;
    var said: [3][]const u8 = @splat("");
    for (&children, 0..) |*c, n| if (c.*) |*child| {
        var err_buf: [8 * 1024]u8 = undefined;
        var e = child.stderr.?.readerStreaming(io, &err_buf);
        said[n] = e.interface.allocRemaining(arena, .limited(8192)) catch "";
        const why = std.mem.trimEnd(u8, said[n], "\n");
        const code: ?u8 = switch (child.wait(io) catch std.process.Child.Term{ .unknown = 0 }) {
            .exited => |code| if (code == 0) continue else code,
            else => null,
        };
        failed = true;
        try err.print("m8: provider {s} failed", .{names[n]});
        if (code) |x| try err.print(" with exit code {d}", .{x});
        if (why.len > 0) try err.print(": {s}", .{why});
        try err.writeAll("\n");
    };
    const turn = reply catch |parse_err| {
        if (!failed) try err.print("m8: provider: {s}\n", .{@errorName(parse_err)});
        return parse_err;
    };
    if (failed) return Error.ProviderFailed;
    // A provider that answered may still have had something to say, such as
    // a credential it could not find, or what the answer cost.
    for (said) |aside| if (aside.len > 0) {
        try err.writeAll(aside);
        if (aside[aside.len - 1] != '\n') try err.writeAll("\n");
    };
    return turn;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const test_tmp = @import("test_tmp.zig");

fn providersFrom(arena: Allocator, json: []const u8) !std.json.ObjectMap {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    return v.object;
}

test "an entry is its commands, and whatever else it wants to say" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const ps = try providersFrom(arena,
        \\{"local": {
        \\  "cmd": ["m8", "url-provider"],
        \\  "encode": ["m8", "encode", "openai-completions"],
        \\  "url": "http://x/v1/chat/completions",
        \\  "key": "cat ~/.key",
        \\  "name": "not-the-selection",
        \\  "api-version": "2024-02-01",
        \\  "timeout": 30,
        \\  "use-cache": true,
        \\  "headers": {"x": "y"},
        \\  "Weird_Key": "ignored"
        \\}}
    );
    const p = try read(arena, ps, "local");

    // A stage it did not name is not there: the command is handed m8.
    try testing.expectEqualStrings("openai-completions", p.encode.?[2]);
    try testing.expect(p.parse == null);
    try testing.expectEqual(@as(usize, 2), p.cmd.len);
    try testing.expectEqualStrings("m8", p.cmd[0]);

    // Strings, numbers and truths with nameable keys go through; `cmd`
    // never does, and neither does an object or a key with no environment
    // name to take.
    try testing.expectEqualStrings("http://x/v1/chat/completions", p.get("url").?);
    try testing.expectEqualStrings("cat ~/.key", p.get("key").?);
    try testing.expectEqualStrings("2024-02-01", p.get("api-version").?);
    try testing.expect(p.get("cmd") == null);
    try testing.expectEqualStrings("30", p.get("timeout").?);
    try testing.expectEqualStrings("true", p.get("use-cache").?);
    try testing.expect(p.get("headers") == null);
    try testing.expect(p.get("Weird_Key") == null);

    try testing.expectEqualStrings("M8_PROVIDER_API_VERSION", try envName(arena, "api-version"));
    try testing.expectEqualStrings("M8_PROVIDER_URL", try envName(arena, "url"));

    var env: std.process.Environ.Map = .init(arena);
    try env.put("M8_PROVIDER_NAME", "inherited-value");
    try addEnvironment(arena, p, &env);
    try testing.expectEqualStrings("local", env.get("M8_PROVIDER_NAME").?);
    try testing.expectEqualStrings("http://x/v1/chat/completions", env.get("M8_PROVIDER_URL").?);
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

    const core_dir = try test_tmp.make(arena, io, "m8-provider-resolve");
    defer std.Io.Dir.cwd().deleteTree(io, core_dir) catch {};

    const runnable = try std.fs.path.join(arena, &.{ core_dir, "runnable" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = runnable, .data = "#!/bin/sh\n", .flags = .{ .permissions = .executable_file } });
    const plain = try std.fs.path.join(arena, &.{ core_dir, "plain" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = plain, .data = "text\n" });

    // `m8` is this m8, whatever is on PATH.
    const self = "/opt/m8/bin/m8";
    try testing.expectEqualStrings(
        self,
        (try resolve(arena, io, self, &.{core_dir}, &.{ "m8", "url-provider", "--get" }))[0],
    );
    // An absolute path is one.
    try testing.expectEqualStrings("/bin/sh", (try resolve(arena, io, self, &.{core_dir}, &.{"/bin/sh"}))[0]);
    // A file in core/ is that file.
    try testing.expectEqualStrings(runnable, (try resolve(arena, io, self, &.{core_dir}, &.{"runnable"}))[0]);
    // There, but not runnable, is an error rather than a fall-through.
    try testing.expectError(
        Error.CommandNotExecutable,
        resolve(arena, io, self, &.{core_dir}, &.{"plain"}),
    );
    // A bare name that is not in core/ is left for PATH.
    try testing.expectEqualStrings("curl", (try resolve(arena, io, self, &.{core_dir}, &.{"curl"}))[0]);
    // A path that is neither absolute nor in core/ has nowhere left to look.
    try testing.expectError(
        Error.CommandNotFound,
        resolve(arena, io, self, &.{core_dir}, &.{"nope/missing"}),
    );
    // Arguments are carried through untouched.
    const full = try resolve(arena, io, self, &.{core_dir}, &.{ "m8", "url-provider", "--get" });
    try testing.expectEqual(@as(usize, 3), full.len);
    try testing.expectEqualStrings("url-provider", full[1]);
}

test "the m8 that is running is named absolutely, however it was found" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    var env: std.process.Environ.Map = .init(arena);
    // Enough `..` to reach the root from anywhere, so /bin is named relatively.
    try env.put("PATH", "/nowhere:" ++ "../" ** 64 ++ "bin");

    // An absolute path is one.
    try testing.expectEqualStrings("/opt/m8/bin/m8", try selfPath(arena, io, &env, "/opt/m8/bin/m8"));
    // A relative one is made absolute.
    try testing.expectEqualStrings("/bin/sh", try selfPath(arena, io, &env, "../" ** 64 ++ "bin/sh"));
    // A bare name found under a relative PATH entry is too.
    try testing.expectEqualStrings("/bin/sh", try selfPath(arena, io, &env, "sh"));
}

/// A sink that keeps what it is given, so a test can see what streamed rather
/// than only what came back at the end.
const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,
    got: codec.Gather = .{ .arena = undefined },

    fn sink(self: *Collect) codec.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        self.got.arena = self.arena;
        self.got.open(s, value);
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
        try self.got.write(bytes);
    }
    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        _ = try self.got.close();
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
        .{
            .cmd = &.{ "/bin/sh", "-c", "cat >/dev/null; printf '* :robot::\n  > said it\n'" },
        },
        null,
        "* :raising_hand::\n  > ask\n",
        collect.sink(),
        &thrown.writer,
    );
    try testing.expectEqualStrings("said it", try collect.got.said(arena));
    // Streamed as bytes too, which is what a terminal watches.
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
        .{
            .cmd = &.{ "/bin/sh", "-c", "cat >/dev/null; echo 'that api is not supported' >&2; exit 3" },
        },
        null,
        "",
        collect.sink(),
        &thrown.writer,
    ));
    // The exit code and whatever it said, so the reason is not lost.
    try testing.expect(std.mem.indexOf(u8, thrown.written(), "exit code 3") != null);
    try testing.expect(std.mem.indexOf(u8, thrown.written(), "not supported") != null);
}

test "the stages are one pipeline, and what each says aside is kept for the end" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    var thrown: std.Io.Writer.Allocating = .init(arena);
    var collect: Collect = .{ .arena = arena };
    _ = try run(
        arena,
        io,
        .{
            .encode = &.{ "/bin/sh", "-c", "tr a-z A-Z" },
            .cmd = &.{ "/bin/sh", "-c", "sed 's/$/!/'" },
            .parse = &.{ "/bin/sh", "-c", "echo '::stats::x' >&2; printf '* :robot::\n  > '; cat" },
        },
        null,
        "ask",
        collect.sink(),
        &thrown.writer,
    );
    try testing.expectEqualStrings("ASK!", try collect.got.said(arena));
    // As it was said, with nothing put in front of it.
    try testing.expectEqualStrings("::stats::x\n", thrown.written());

    // The stage that failed is the one named.
    try testing.expectError(Error.ProviderFailed, run(
        arena,
        io,
        .{ .encode = &.{ "/bin/sh", "-c", "cat >/dev/null; echo nope >&2; exit 2" }, .cmd = &.{"cat"} },
        null,
        "ask",
        collect.sink(),
        &thrown.writer,
    ));
    try testing.expect(std.mem.indexOf(u8, thrown.written(), "provider encode failed with exit code 2: nope") != null);
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

    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("M8_TEST_INHERITED", "yes");
    try addEnvironment(arena, p, &environ);

    // On top of what was already there, not instead of it.
    try testing.expectEqualStrings("yes", environ.get("M8_TEST_INHERITED").?);
    try testing.expectEqualStrings("http://x/v1/chat/completions", environ.get("M8_PROVIDER_URL").?);
    try testing.expectEqualStrings("2024-02-01", environ.get("M8_PROVIDER_API_VERSION").?);
    // `cmd` does not: the command already knows what it is.
    try testing.expect(environ.get("M8_PROVIDER_CMD") == null);

    var thrown: std.Io.Writer.Allocating = .init(arena);
    var collect: Collect = .{ .arena = arena };
    _ = try run(
        arena,
        io,
        .{
            .cmd = &.{ "/bin/sh", "-c", "cat >/dev/null; printf '* :robot::\n  > %s\n' \"$M8_PROVIDER_URL\"" },
        },
        &environ,
        "",
        collect.sink(),
        &thrown.writer,
    );
    try testing.expectEqualStrings("http://x/v1/chat/completions", try collect.got.said(arena));
}
