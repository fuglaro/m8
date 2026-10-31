const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const requested_optimize = b.standardOptimizeOption(.{});
    // Two namings of a small build with less in it. Each only chooses what
    // the options below default to, so any of them can still be said.
    const core = b.option(
        bool,
        "core",
        "A minimal build, with riff apart as well",
    ) orelse false;
    const said_minimal = b.option(
        bool,
        "minimal",
        "A small build, with munge and the shields apart as well",
    ) orelse false;
    const said_small = b.option(
        bool,
        "small",
        "Build ReleaseSmall artifacts with debug symbols omitted; -Dformats then defaults to openai-responses and -Dsplit to cast,toy-provider",
    ) orelse false;
    const minimal = core or said_minimal;
    const small = minimal or said_small;
    const optimize: std.builtin.OptimizeMode = if (small) .ReleaseSmall else requested_optimize;
    const no_curl_dep = b.option(
        bool,
        "no-curl-dep",
        "Use Zig's stdlib HTTP client instead of requiring curl at runtime",
    ) orelse false;
    const system_config = b.option(
        []const u8,
        "system-config-dir",
        "System config directory (default: /etc/m8-st8)",
    ) orelse "/etc/m8-st8";
    const formats = wireFormats(b, small);
    const every = commands(b);
    const said_split = b.option(
        []const u8,
        "split",
        "Commands to build as programs of their own, comma-separated, or `all` (default: none, or what -Dsmall, -Dminimal or -Dcore name)",
    ) orelse if (core)
        "cast,toy-provider,munge,secure-shield,ask-shield,riff"
    else if (minimal)
        "cast,toy-provider,munge,secure-shield,ask-shield"
    else if (small)
        "cast,toy-provider"
    else
        "";
    const split = if (std.mem.eql(u8, said_split, "all")) every else said_split;

    // The launcher: every command but the ones named apart, reached by
    // calling it.
    const exe = command(b, target, optimize, small, "m8", "src/main.zig", "", every, no_curl_dep, formats, split, system_config);
    b.getInstallStep().dependOn(install(b, target, exe, small));

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run m8").dependOn(&run.step);

    // The ones named apart: a program each, installed beside the launcher,
    // which reaches one by becoming it.
    var apart = std.mem.tokenizeAny(u8, split, ", ");
    while (apart.next()) |name| {
        if (!among(every, name)) std.process.fatal("-Dsplit: no command named '{s}'", .{name});
        const leaf = command(b, target, optimize, small, b.fmt("m8-{s}", .{name}), "src/leaf.zig", name, every, no_curl_dep, formats, split, system_config);
        b.getInstallStep().dependOn(install(b, target, leaf, small));
    }

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    // The tests are of the sources, so they are handed every command.
    tests.root_module.addOptions("build_options", options(b, "", every, no_curl_dep, formats, "", system_config));
    const test_launcher = command(b, target, optimize, small, "m8-test-launcher", "src/main.zig", "", every, no_curl_dep, formats, "", system_config);
    const test_options = b.addOptions();
    test_options.addOptionPath("launcher", test_launcher.getEmittedBin());
    tests.root_module.addOptions("test_options", test_options);
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(tests).step);

    // A story file run straight through the machine, for working on the
    // machine itself rather than on m8 around it.
    const zrun = b.addExecutable(.{
        .name = "zrun",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zmachine/cli.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
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
    small: bool,
    name: []const u8,
    root: []const u8,
    which: []const u8,
    every: []const u8,
    no_curl_dep: bool,
    formats: Formats,
    split: []const u8,
    system_config_dir: []const u8,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
            .strip = if (small) true else null,
        }),
    });
    exe.root_module.addOptions("build_options", options(b, which, every, no_curl_dep, formats, split, system_config_dir));
    return exe;
}

/// Install an artifact, removing Darwin's local linker symbols in a small
/// build. ReleaseSmall already omits debug symbols, but Mach-O retains the
/// LLVM outliner's thousands of `_OUTLINED_FUNCTION_*` names unless `strip -x`
/// is applied after linking. Other object formats honor Zig's strip setting.
/// `strip` is the host's, so a Mach-O built from another host keeps the names.
fn install(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    artifact: *std.Build.Step.Compile,
    small: bool,
) *std.Build.Step {
    const installed = b.addInstallArtifact(artifact, .{});
    if (!small or target.result.os.tag != .macos or builtin.os.tag != .macos)
        return &installed.step;

    const strip = b.addSystemCommand(&.{ "strip", "-x" });
    strip.addArg(b.getInstallPath(installed.dest_dir.?, installed.dest_sub_path));
    strip.step.dependOn(&installed.step);
    return &strip.step;
}

/// What a binary is told about its build: the one command it is, when it is a
/// command built on its own, the commands a launcher leaves to programs
/// beside it, and every command the sources hold.
fn options(
    b: *std.Build,
    which: []const u8,
    every: []const u8,
    no_curl_dep: bool,
    formats: Formats,
    split: []const u8,
    system_config_dir: []const u8,
) *std.Build.Step.Options {
    const o = b.addOptions();
    o.addOption([]const u8, "command", which);
    o.addOption([]const u8, "split", split);
    o.addOption([]const u8, "commands", every);
    o.addOption(bool, "no_curl_dep", no_curl_dep);
    o.addOption(bool, "format_openai_completions", formats.openai_completions);
    o.addOption(bool, "format_anthropic_messages", formats.anthropic_messages);
    o.addOption(bool, "format_openai_responses", formats.openai_responses);
    o.addOption([]const u8, "system_config_dir", system_config_dir);
    return o;
}

/// The wire formats `encode` and `parse` are built with. `m8` is the language
/// itself, so it is not among the choices.
const Formats = struct {
    openai_completions: bool = false,
    anthropic_messages: bool = false,
    openai_responses: bool = false,
};

/// A small build that names none carries `openai-responses` alone, the one
/// most providers answer in.
fn wireFormats(b: *std.Build, small: bool) Formats {
    const said = b.option(
        []const u8,
        "formats",
        "Wire formats to build in, comma-separated (default: all, or openai-responses with -Dsmall; m8 is always included)",
    ) orelse return if (small)
        .{ .openai_responses = true }
    else
        .{ .openai_completions = true, .anthropic_messages = true, .openai_responses = true };

    var out: Formats = .{};
    var it = std.mem.tokenizeScalar(u8, said, ',');
    while (it.next()) |word| {
        const name = std.mem.trim(u8, word, " \t");
        if (name.len == 0 or std.mem.eql(u8, name, "m8")) continue;
        if (std.mem.eql(u8, name, "openai-completions")) {
            out.openai_completions = true;
        } else if (std.mem.eql(u8, name, "anthropic-messages")) {
            out.anthropic_messages = true;
        } else if (std.mem.eql(u8, name, "openai-responses")) {
            out.openai_responses = true;
        } else std.process.fatal(
            "-Dformats: no format named '{s}'; " ++
                "there are openai-completions, anthropic-messages and openai-responses",
            .{name},
        );
    }
    return out;
}

/// Every command there is, comma-separated: a file directly in `src/command`
/// is a command and is named for it, and whatever a command keeps to itself
/// is in a folder beneath. So this is read off the sources rather than kept,
/// and the registry's own test holds the two to each other.
fn commands(b: *std.Build) []const u8 {
    var dir = b.build_root.handle.openDir(b.graph.io, "src/command", .{ .iterate = true }) catch
        @panic("src/command is missing");
    defer dir.close(b.graph.io);

    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(b.graph.io) catch @panic("src/command could not be read")) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        names.append(b.allocator, b.dupe(entry.name[0 .. entry.name.len - ".zig".len])) catch @panic("OOM");
    }
    // A directory hands its entries back in no order, and a build option
    // that changed between two builds of the same sources would rebuild both.
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.lessThan);
    return std.mem.join(b.allocator, ",", names.items) catch @panic("OOM");
}

fn among(names: []const u8, name: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, names, ',');
    while (it.next()) |one| if (std.mem.eql(u8, one, name)) return true;
    return false;
}
