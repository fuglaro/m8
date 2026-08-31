const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "m8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run m8").dependOn(&run.step);

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

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);
}
