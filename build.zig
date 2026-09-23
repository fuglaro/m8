const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The single binary: every command, reached by calling it.
    const exe = command(b, target, optimize, "m8", "src/main.zig", false, "");
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run m8").dependOn(&run.step);

    // The split set: a program per command, reaching the next by spawning it.
    // Bare m8's prompt mode is part of the launcher, not a command in the set.
    const split = b.step("split", "Build the commands as separate programs");
    split.dependOn(&b.addInstallArtifact(
        command(b, target, optimize, "m8", "src/main.zig", true, ""),
        .{},
    ).step);
    for (paths(b)) |path| {
        const leaf = command(b, target, optimize, program(b, path), "src/leaf.zig", true, path);
        split.dependOn(&b.addInstallArtifact(leaf, .{}).step);
    }

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addOptions("build_options", options(b, false, ""));
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);

    // A story file run straight through the machine, for working on the
    // machine itself rather than on m8 around it.
    const zrun = b.addExecutable(.{
        .name = "zrun",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zmachine/cli.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const zrun_step = b.addRunArtifact(zrun);
    if (b.args) |args| zrun_step.addArgs(args);
    b.step("zrun", "Play a story file").dependOn(&zrun_step.step);
}

fn command(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    root: []const u8,
    split: bool,
    path: []const u8,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options(b, split, path));
    return exe;
}

fn options(b: *std.Build, split: bool, path: []const u8) *std.Build.Step.Options {
    const o = b.addOptions();
    o.addOption(bool, "split", split);
    o.addOption([]const u8, "command", path);
    return o;
}

/// What a split-out command is called as a program: its path, hyphenated.
fn program(b: *std.Build, path: []const u8) []const u8 {
    var name = std.ArrayList(u8).initCapacity(b.allocator, path.len + 4) catch @panic("OOM");
    name.appendSlice(b.allocator, "m8") catch @panic("OOM");
    var it = std.mem.splitScalar(u8, path, ' ');
    while (it.next()) |word| {
        if (word.len == 0) continue;
        name.append(b.allocator, '-') catch @panic("OOM");
        name.appendSlice(b.allocator, word) catch @panic("OOM");
    }
    return name.items;
}

/// The split-out commands, from the file the registry's own test checks
/// itself against.
fn paths(b: *std.Build) []const []const u8 {
    const src = b.build_root.handle.readFileAlloc(
        b.graph.io,
        "src/commands.txt",
        b.allocator,
        .limited(1 << 20),
    ) catch @panic("src/commands.txt is missing");

    var out = std.ArrayList([]const u8).empty;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        out.append(b.allocator, trimmed) catch @panic("OOM");
    }
    return out.items;
}
