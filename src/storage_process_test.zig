//! End-to-end storage, dispatch, and discovery checks against the built launcher.
const std = @import("std");
const launcher = @import("test_options").launcher;
const A = std.mem.Allocator;
const io = std.testing.io;

const Result = struct { out: []const u8, err: []const u8, ok: bool };

fn path(a: A, parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(a, parts);
}
fn mkdir(p: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, p);
}
fn put(p: []const u8, data: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = data });
}
fn exists(p: []const u8) bool {
    std.Io.Dir.cwd().access(io, p, .{}) catch return false;
    return true;
}
fn removeTree(p: []const u8) !void {
    try std.Io.Dir.cwd().deleteTree(io, p);
}

fn turnCount(p: []const u8) !usize {
    var dir = try std.Io.Dir.cwd().openDir(io, p, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    var count: usize = 0;
    while (try it.next(io)) |entry| {
        if (entry.kind == .file) count += 1;
    }
    return count;
}
const Setup = struct {
    a: A,
    root: []const u8,
    env: std.process.Environ.Map,
    executable: []const u8,

    fn init(a: A) !Setup {
        const root = try @import("test_tmp.zig").make(a, io, "storage-process");
        errdefer removeTree(root) catch {};
        var resolved: [std.fs.max_path_bytes]u8 = undefined;
        const len = try std.Io.Dir.cwd().realPathFile(io, launcher, &resolved);
        const executable = try a.dupe(u8, resolved[0..len]);
        var env: std.process.Environ.Map = .init(a);
        try env.put("HOME", try path(a, &.{ root, "home" }));
        try env.put("XDG_CONFIG_HOME", try path(a, &.{ root, "config" }));
        try env.put("XDG_DATA_HOME", try path(a, &.{ root, "data" }));
        try env.put("TMPDIR", root);
        try env.put("M8_ST8_DIRS", try std.fmt.allocPrint(a, "{s}:{s}", .{ try path(a, &.{ root, "project" }), try path(a, &.{ root, "config", "m8-st8" }) }));
        try env.put("M8_CALL_ID", "storage-process-test");
        try mkdir(try path(a, &.{ root, "project/mobs/demo" }));
        try mkdir(try path(a, &.{ root, "project/core/providers" }));
        try mkdir(try path(a, &.{ root, "config/m8-st8/mobs/useronly" }));
        try mkdir(try path(a, &.{ root, "config/m8-st8/mobs/demo" }));
        try put(try path(a, &.{ root, "project/mobs/demo/echo.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ root, "config/m8-st8/mobs/useronly/echo.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ root, "config/m8-st8/mobs/demo/hidden.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ root, "project/core/providers/toy.json" }), "{\"cmd\":[\"m8\",\"toy-provider\"],\"models\":[\"m8\",\"toy-provider\",\"--models\"]}\n");
        return .{ .a = a, .root = root, .env = env, .executable = executable };
    }
    fn run(self: *Setup, args: []const []const u8) !Result {
        return self.runAt(self.root, args);
    }
    // process.run supplies ignored stdin (EOF), never the test runner's stdin.
    fn runAt(self: *Setup, cwd: []const u8, args: []const []const u8) !Result {
        const argv = try self.a.alloc([]const u8, args.len + 1);
        argv[0] = self.executable;
        @memcpy(argv[1..], args);
        const r = try std.process.run(self.a, io, .{ .argv = argv, .cwd = .{ .path = cwd }, .environ_map = &self.env, .stdout_limit = .limited(4 * 1024 * 1024), .stderr_limit = .limited(4 * 1024 * 1024) });
        return .{ .out = r.stdout, .err = r.stderr, .ok = r.term == .exited and r.term.exited == 0 };
    }
    fn expect(self: *Setup, args: []const []const u8, fragment: []const u8) !void {
        const r = try self.run(args);
        if (!r.ok) std.debug.print("launcher {s}:\n{s}\n{s}\n", .{ if (args.len > 0) args[0] else "(no args)", r.out, r.err });
        try std.testing.expect(r.ok);
        try std.testing.expect(std.mem.indexOf(u8, r.out, fragment) != null);
    }
};

test "launcher persists storage, resets sessions, and inherits roots in delegated children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var s = try Setup.init(a);
    defer {
        s.env.deinit();
        removeTree(s.root) catch {};
    }
    const root = s.root;
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/echo", "hello" }, "hello");
    const pointer = try path(a, &.{ root, "project/mobs/demo/.chats/echo/+.md" });
    const turns = try path(a, &.{ root, "project/mobs/demo/.chats/echo/+" });
    const before = try turnCount(turns);
    const prior = try std.Io.Dir.cwd().readFileAlloc(io, pointer, a, .limited(1 << 20));
    try s.expect(&.{ "say", "--no-advance", "--answer", "--unwrap", ":demo/echo", "stateless" }, "stateless");
    try std.testing.expectEqualStrings(prior, try std.Io.Dir.cwd().readFileAlloc(io, pointer, a, .limited(1 << 20)));
    try std.testing.expect(try turnCount(turns) > before);
    try std.testing.expect(exists(try path(a, &.{ root, "project/mobs/demo/.mob-space" })));
    try removeTree(try path(a, &.{ root, "project/mobs/demo/.mob-space" }));
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/echo", "model-head" }, "model-head");
    try std.testing.expect(exists(try path(a, &.{ root, "project/mobs/demo/.mob-space" })));
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/echo//job", "next" }, "next");
    const job = try path(a, &.{ root, "project/mobs/demo/.chats/echo/_/job/+.md" });
    try std.testing.expect(exists(job));
    try s.expect(&.{ "say", ":demo/echo//job-" }, "");
    try std.testing.expect(!exists(job));
    try s.expect(&.{ "say", "--new", ":demo/echo//job" }, "");
    try std.testing.expect(exists(job));
    try std.testing.expect(std.mem.indexOf(u8, try std.Io.Dir.cwd().readFileAlloc(io, job, a, .limited(1 << 20)), "demo/echo") != null);
    try s.expect(&.{":demo/echo//job-"}, "");
    try std.testing.expect(!exists(job));
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/echo//job", "again" }, "again");
    try s.expect(&.{":demo/echo//job--"}, "");
    try std.testing.expectEqualStrings("* :brain::demo/echo\n", try std.Io.Dir.cwd().readFileAlloc(io, job, a, .limited(1 << 20)));
    try s.expect(&.{ "say", "--answer", "--unwrap", ":useronly/echo", "relocated" }, "relocated");
    try std.testing.expect(exists(try path(a, &.{ root, "data/m8-st8/user/mobs/useronly/.chats/echo/+.md" })));
    try std.testing.expect(exists(try path(a, &.{ root, "data/m8-st8/user/mobs/useronly/.mob-space" })));
    try std.testing.expect(!exists(try path(a, &.{ root, "config/m8-st8/mobs/useronly/.chats" })));
    const runner = try path(a, &.{ root, "project/mobs/demo/runner.md" });
    try put(
        runner,
        "* :brain::/toy/runner\n\n" ++
            "* :toolbox::delegate\n" ++
            "  > `m8` `call` `sh` `-c` `HOME=\"$TMPDIR\" XDG_CONFIG_HOME=/narrow XDG_DATA_HOME=/narrow \"$M8\" say --answer --unwrap :useronly/echo//delegated \"$__message__\"`\n" ++
            "  > * message string\n\n* :toolbox::delegate\n",
    );
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/runner", "RUN;;;delegate;;;message=delegated" }, "Done");
    try std.testing.expect(exists(try path(a, &.{ root, "data/m8-st8/user/mobs/useronly/.chats/echo/_/delegated/+.md" })));
    try std.testing.expect(exists(try path(a, &.{ root, "project/mobs/demo/.chats/runner/+.md" })));
}

test "launcher rejects old dispatch names and shows help on EOF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var s = try Setup.init(arena.allocator());
    defer {
        s.env.deinit();
        removeTree(s.root) catch {};
    }
    for ([_][]const u8{ "@", "at" }) |command| {
        const r = try s.run(&.{command});
        try std.testing.expect(!r.ok);
        try std.testing.expect(r.err.len != 0);
    }
    const help = try s.run(&.{});
    try std.testing.expect(help.ok);
    try std.testing.expect(std.mem.indexOf(u8, help.out, "MOB/AGENT") != null);
}

test "launcher discovers only the registered nearest project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var s = try Setup.init(a);
    defer {
        s.env.deinit();
        removeTree(s.root) catch {};
    }
    const root = s.root;
    // Nearest project registration is authoritative, even when a parent is registered.
    _ = s.env.swapRemove("M8_CALL_ID");
    _ = s.env.swapRemove("M8_ST8_DIRS");
    _ = s.env.swapRemove("M8");
    const inner = try path(a, &.{ root, "work/child" });
    const outer = try path(a, &.{ root, "work" });
    try mkdir(try path(a, &.{ outer, ".m8-st8/mobs/outer" }));
    try mkdir(try path(a, &.{ inner, ".m8-st8/mobs/inner" }));
    try put(try path(a, &.{ outer, ".m8-st8/mobs/outer/echo.md" }), "* :brain::/toy/echo\n");
    try put(try path(a, &.{ inner, ".m8-st8/mobs/inner/echo.md" }), "* :brain::/toy/echo\n");
    try s.env.put("XDG_CONFIG_HOME", try path(a, &.{ root, "registry" }));
    const registered = try s.runAt(inner, &.{"register"});
    try std.testing.expect(registered.ok);
    const nearest = try s.runAt(inner, &.{ "say", "--no-send", ":inner/echo" });
    try std.testing.expect(nearest.ok);
    const missing_outer = try s.runAt(inner, &.{ "say", "--no-send", ":outer/echo" });
    try std.testing.expect(!missing_outer.ok);
    try s.env.put("XDG_CONFIG_HOME", try path(a, &.{ root, "registry2" }));
    const register_outer = try s.runAt(outer, &.{"register"});
    try std.testing.expect(register_outer.ok);
    const still_missing = try s.runAt(inner, &.{ "say", "--no-send", ":outer/echo" });
    try std.testing.expect(!still_missing.ok);
}
