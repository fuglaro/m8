//! Building a command line from the call environment.
//!
//! A placeholder naming a variable becomes whole argv elements, and every
//! other word passes through untouched. A value is never spliced into a larger
//! one, so what a call said cannot become syntax in whatever runs.

const std = @import("std");
const argname = @import("../../argname.zig");

pub const Error = error{
    /// A placeholder was opened and not closed.
    UnclosedPlaceholder,
    /// `?` with no flag after it, which could never emit anything.
    FlaglessQuestion,
    /// `?` on a value that is neither `true` nor `false`.
    NotABoolean,
};

/// Placeholders are logical argument names. Their process spelling is made
/// by `argname`; the empty name is the complete call.
/// How a placeholder says what to do with the value it names.
const Form = enum {
    /// `{{name}}` — the flag is the argument's own name.
    own,
    /// `{{name|-f}}` — this flag, or none when nothing follows.
    given,
    /// `{{name?-f}}` — the flag alone, and only when true.
    boolean,
};

/// Expand one word into however many argv elements it becomes.
///
/// Absent is not empty: an argument that was not supplied leaves nothing
/// behind, which is the whole of what optional means to a command, while an
/// empty string is a value a command was given.
fn expand(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    err: *std.Io.Writer,
    out: *std.ArrayList([]const u8),
    word: []const u8,
) !void {
    // Expansion is only for a whole argv word. Other brace expressions are
    // ordinary program text, including templates belonging to another tool.
    if (!std.mem.startsWith(u8, word, "{{")) return out.append(arena, word);
    if (!std.mem.endsWith(u8, word, "}}") or word.len < 4) {
        try err.print("m8 call: unclosed placeholder '{s}'\n", .{word});
        return Error.UnclosedPlaceholder;
    }

    const inner = word[2 .. word.len - 2];
    var name = inner;
    var flag: []const u8 = "";
    var form: Form = .own;
    if (std.mem.indexOfAny(u8, inner, "|?")) |cut| {
        name = inner[0..cut];
        flag = inner[cut + 1 ..];
        form = if (inner[cut] == '?') .boolean else .given;
    }

    // The flag a bare placeholder carries is the argument's own name. An
    // empty name therefore naturally becomes `--`, the all-arguments form.
    if (form == .own) flag = try std.fmt.allocPrint(arena, "--{s}", .{name});

    // A definition that could never emit anything is wrong however the call
    // went, so it is caught before the value is looked at.
    if (form == .boolean and flag.len == 0) {
        try err.print("m8 call: '{s}' asks for a flag and names none\n", .{word});
        return Error.FlaglessQuestion;
    }

    const key = (try argname.envName(arena, name)) orelse return out.append(arena, word);
    const value = env.get(key) orelse return;
    if (form == .boolean) {
        if (std.mem.eql(u8, value, "false")) return;
        if (!std.mem.eql(u8, value, "true")) {
            try err.print(
                "m8 call: {s} is '{s}', and '{s}' takes true or false\n",
                .{ name, value, word },
            );
            return Error.NotABoolean;
        }
        return out.append(arena, flag);
    }
    if (flag.len > 0) try out.append(arena, flag);
    try out.append(arena, value);
}

/// The command line a template becomes. Separate from running it, so what it
/// builds can be tested without spawning anything.
pub fn line(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    err: *std.Io.Writer,
    template: []const []const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    for (template) |word| try expand(arena, env, err, &argv, word);
    return argv.items;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// Build a command line the way a call does: everything in the environment.
fn built(
    arena: std.mem.Allocator,
    vars: []const [2][]const u8,
    template: []const []const u8,
) ![]const []const u8 {
    var env: std.process.Environ.Map = .init(arena);
    for (vars) |kv| try env.put(kv[0], kv[1]);
    var err: std.Io.Writer.Allocating = .init(arena);
    return line(arena, &env, &err.writer, template);
}

fn expectArgv(got: []const []const u8, want: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "a placeholder takes the flag from its name, or from what it is given" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const vars = &[_][2][]const u8{.{ "__command__", "echo hi" }};

    try expectArgv(try built(arena, vars, &.{"{{command}}"}), &.{ "--command", "echo hi" });
    try expectArgv(try built(arena, vars, &.{"{{command|-c}}"}), &.{ "-c", "echo hi" });
    try expectArgv(try built(arena, vars, &.{"{{command|}}"}), &.{"echo hi"});

    // A placeholder is a whole element, so it sits among ordinary words
    // without either becoming part of the other.
    try expectArgv(
        try built(arena, vars, &.{ "bash", "-euo", "pipefail", "{{command|-c}}" }),
        &.{ "bash", "-euo", "pipefail", "-c", "echo hi" },
    );
}

test "the complete call uses the ordinary flag and injection forms" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"a\":1}";
    const vars = &[_][2][]const u8{.{ "____", json }};
    try expectArgv(try built(arena, vars, &.{"{{}}"}), &.{ "--", json });
    try expectArgv(try built(arena, vars, &.{"{{|}}"}), &.{json});
}

test "unset is absent, and empty is a value a command was given" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The whole of what optional means to a command: the flag is not there.
    try expectArgv(
        try built(arena, &.{}, &.{ "echo", "{{nope}}", "x" }),
        &.{ "echo", "x" },
    );
    try expectArgv(
        try built(arena, &.{.{ "__e__", "" }}, &.{ "echo", "{{e}}" }),
        &.{ "echo", "--e", "" },
    );
}

test "true emits the flag alone, false and unset emit nothing" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const yes = &[_][2][]const u8{.{ "__deep__", "true" }};
    const no = &[_][2][]const u8{.{ "__deep__", "false" }};
    try expectArgv(try built(arena, yes, &.{"{{deep?--deep}}"}), &.{"--deep"});
    try expectArgv(try built(arena, no, &.{"{{deep?--deep}}"}), &.{});
    try expectArgv(try built(arena, &.{}, &.{"{{deep?--deep}}"}), &.{});

    // Anything else is refused rather than dropped: a call that looked like
    // it succeeded while ignoring what was asked is the worse answer.
    const other = &[_][2][]const u8{.{ "__deep__", "1" }};
    try testing.expectError(
        Error.NotABoolean,
        built(arena, other, &.{"{{deep?--deep}}"}),
    );
}

test "only whole placeholders are looked at" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // An invalid name remains ordinary program text, so another templater's
    // braces survive.
    try expectArgv(
        try built(arena, &.{}, &.{ "awk", "{{print $1}}", "f" }),
        &.{ "awk", "{{print $1}}", "f" },
    );

    // Nor is one spliced into a larger word, so a value cannot become syntax.
    try expectArgv(
        try built(arena, &.{.{ "__x__", "v" }}, &.{"x{{x}}"}),
        &.{"x{{x}}"},
    );
    try expectArgv(
        try built(arena, &.{.{ "____", "json" }}, &.{"x{{}}"}),
        &.{"x{{}}"},
    );
}

test "a definition that could never work is refused where it is written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectError(
        Error.UnclosedPlaceholder,
        built(arena, &.{}, &.{"{{x}"}),
    );
    // Caught before the value is looked at, because it is wrong however the
    // call went.
    try testing.expectError(
        Error.FlaglessQuestion,
        built(arena, &.{}, &.{"{{x?}}"}),
    );
}
