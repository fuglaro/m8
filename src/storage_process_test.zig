//! End-to-end storage, dispatch, and discovery checks against the built launcher.
const std = @import("std");
const build_options = @import("build_options");
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
    config_root: []const u8,
    data_root: []const u8,

    fn init(a: A) !Setup {
        const root = try @import("test_tmp.zig").make(a, io, "storage-process");
        errdefer removeTree(root) catch {};
        var resolved: [std.fs.max_path_bytes]u8 = undefined;
        const len = try std.Io.Dir.cwd().realPathFile(io, launcher, &resolved);
        const executable = try a.dupe(u8, resolved[0..len]);
        var env: std.process.Environ.Map = .init(a);
        const home = try path(a, &.{ root, "home" });
        const config_root = if (build_options.xdg)
            try path(a, &.{ root, "config", std.fs.path.basename(build_options.user_config_subpath) })
        else
            try path(a, &.{ home, build_options.user_config_subpath });
        const data_root = if (build_options.xdg)
            try path(a, &.{ root, "data", std.fs.path.basename(build_options.user_data_subpath) })
        else
            try path(a, &.{ home, build_options.user_data_subpath });
        try env.put("HOME", home);
        try env.put("XDG_CONFIG_HOME", try path(a, &.{ root, "config" }));
        try env.put("XDG_DATA_HOME", try path(a, &.{ root, "data" }));
        try env.put("TMPDIR", root);
        try env.put("M8_ST8_DIRS", try std.fmt.allocPrint(a, "{s}:{s}", .{ try path(a, &.{ root, "project" }), config_root }));
        try env.put("M8_CALL_ID", "storage-process-test");
        try mkdir(try path(a, &.{ root, "project/mobs/demo" }));
        try mkdir(try path(a, &.{ root, "project/core/providers" }));
        try mkdir(try path(a, &.{ config_root, "mobs/useronly" }));
        try mkdir(try path(a, &.{ config_root, "mobs/demo" }));
        try put(try path(a, &.{ root, "project/mobs/demo/echo.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ config_root, "mobs/useronly/echo.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ config_root, "mobs/demo/hidden.md" }), "* :brain::/toy/echo\n");
        try put(try path(a, &.{ root, "project/core/providers/toy.json" }), "{\"cmd\":[\"m8\",\"toy-provider\"],\"models\":[\"m8\",\"toy-provider\",\"--models\"]}\n");
        return .{ .a = a, .root = root, .env = env, .executable = executable, .config_root = config_root, .data_root = data_root };
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
    try std.testing.expect(exists(try path(a, &.{ s.data_root, "user/mobs/useronly/.chats/echo/+.md" })));
    try std.testing.expect(exists(try path(a, &.{ s.data_root, "user/mobs/useronly/.mob-space" })));
    try std.testing.expect(!exists(try path(a, &.{ s.config_root, "mobs/useronly/.chats" })));
    const runner = try path(a, &.{ root, "project/mobs/demo/runner.md" });
    try put(
        runner,
        "* :brain::/toy/runner\n\n" ++
            "* :toolbox::delegate\n" ++
            "  > `m8` `call` `sh` `-c` `HOME=\"$TMPDIR\" XDG_CONFIG_HOME=/narrow XDG_DATA_HOME=/narrow \"$M8\" say --answer --unwrap :useronly/echo//delegated \"$__message__\"`\n" ++
            "  > * `message` **string**\n\n* :toolbox::delegate\n",
    );
    try s.expect(&.{ "say", "--answer", "--unwrap", ":demo/runner", "RUN;;;delegate;;;message=delegated" }, "Done");
    const delegated_data = if (build_options.xdg)
        try path(a, &.{ root, "data", std.fs.path.basename(build_options.user_data_subpath), "user/mobs/useronly/.chats/echo/_/delegated/+.md" })
    else
        try path(a, &.{ root, "home", build_options.user_data_subpath, "user/mobs/useronly/.chats/echo/_/delegated/+.md" });
    try std.testing.expect(exists(delegated_data));
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
    const project_name = build_options.project_config_dir_name;
    try mkdir(try path(a, &.{ outer, project_name, "mobs/outer" }));
    try mkdir(try path(a, &.{ inner, project_name, "mobs/inner" }));
    try put(try path(a, &.{ outer, project_name, "mobs/outer/echo.md" }), "* :brain::/toy/echo\n");
    try put(try path(a, &.{ inner, project_name, "mobs/inner/echo.md" }), "* :brain::/toy/echo\n");
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

test "incomplete Responses turn persists partial output without dispatching calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var s = try Setup.init(a);
    defer {
        s.env.deinit();
        removeTree(s.root) catch {};
    }
    const marker = try path(a, &.{ s.root, "tool-dispatched" });
    const response = try path(a, &.{ s.root, "incomplete.sse" });
    const tool_call = try std.fmt.allocPrint(a, "touch {s}", .{marker});
    const tool_args = try std.json.Stringify.valueAlloc(a, .{ .cmd = tool_call }, .{});
    const tool_args_json = try std.json.Stringify.valueAlloc(a, tool_args, .{});
    const response_body = try std.fmt.allocPrint(a, "event: response.output_item.added\ndata: {{\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\"}}}}\n\n" ++
        "event: response.output_text.delta\ndata: {{\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"partial assistant text\"}}\n\n" ++
        "event: response.output_item.done\ndata: {{\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"content\":[{{\"type\":\"output_text\",\"text\":\"partial assistant text\"}}]}}}}\n\n" ++
        "event: response.output_item.added\ndata: {{\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"shell\",\"arguments\":\"\"}}}}\n\n" ++
        "event: response.function_call_arguments.delta\ndata: {{\"type\":\"response.function_call_arguments.delta\",\"output_index\":1,\"delta\":{s}}}\n\n" ++
        "event: response.output_item.done\ndata: {{\"type\":\"response.output_item.done\",\"output_index\":1,\"item\":{{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"shell\",\"arguments\":{s}}}}}\n\n" ++
        "event: response.incomplete\ndata: {{\"type\":\"response.incomplete\",\"response\":{{\"status\":\"incomplete\",\"incomplete_details\":{{\"reason\":\"max_output_tokens\"}}}}}}\n\n", .{ tool_args_json, tool_args_json });
    try put(response, response_body);
    const seen = try path(a, &.{ s.root, "provider-seen" });
    const provider_json = try std.json.Stringify.valueAlloc(a, .{
        .cmd = [_][]const u8{ "sh", "-c", "cat >/dev/null; if test -e \"$M8_PROVIDER_seen\"; then printf '%s\\n' '{\"status\":\"completed\",\"output\":[]}'; else : > \"$M8_PROVIDER_seen\"; cat \"$M8_PROVIDER_response\"; fi" },
        .encode = [_][]const u8{ "m8", "encode", "openai-responses" },
        .parse = [_][]const u8{ "m8", "parse", "openai-responses" },
        .response = response,
        .seen = seen,
    }, .{});
    try put(try path(a, &.{ s.root, "project/core/providers/toy.json" }), provider_json);
    const agent = try std.fmt.allocPrint(a, "* :brain::/toy/test\n\n" ++
        "* :toolbox::shell\n" ++
        "  > `touch` `{s}`\n" ++
        "  > * `cmd` **string**\n\n" ++
        "* :toolbox::shell\n", .{marker});
    try put(try path(a, &.{ s.root, "project/mobs/demo/incomplete.md" }), agent);
    const result = try s.run(&.{ "say", "--answer", "--unwrap", ":demo/incomplete", "please" });
    try std.testing.expect(!result.ok);
    try std.testing.expect(std.mem.indexOf(u8, result.err, "IncompleteResponse") != null);
    try std.testing.expect(!exists(marker));
    const saved = try s.run(&.{ "cat", ":demo/incomplete" });
    try std.testing.expect(saved.ok);
    try std.testing.expect(std.mem.indexOf(u8, saved.out, "partial assistant text") != null);
    try std.testing.expect(std.mem.indexOf(u8, saved.out, "max_output_tokens") != null);

    // The same offered call does run when the response actually completes.
    // This proves the marker check is not passing because of a broken tool.
    const terminal = std.mem.indexOf(u8, response_body, "event: response.incomplete").?;
    const completed = try std.mem.concat(a, u8, &.{
        response_body[0..terminal],
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
    });
    try put(response, completed);
    try std.Io.Dir.cwd().deleteFile(io, seen);
    const finished = try s.run(&.{ "say", "--answer", "--unwrap", ":demo/incomplete//finished", "please" });
    if (!finished.ok) std.debug.print("completed control:\n{s}\n{s}\n", .{ finished.out, finished.err });
    try std.testing.expect(finished.ok);
    try std.testing.expect(exists(marker));
}
