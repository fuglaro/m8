//! Building a command line from the call environment.
//!
//! A placeholder naming a variable becomes whole argv elements, and every
//! other word passes through untouched. A value is never spliced into a larger
//! one, so what a call said cannot become syntax in whatever runs.

const std = @import("std");

pub const Error = error{
    /// A placeholder was opened and not closed.
    UnclosedPlaceholder,
    /// `?` with no flag after it, which could never emit anything.
    FlaglessQuestion,
    /// `?` on a value that is neither `true` nor `false`.
    NotABoolean,
};

/// What a placeholder may name. One prefix covers `M8_ARG_<NAME>` and
/// `M8_ARGS` both, and nothing outside it is looked at — so the braces a
/// templating language meant for itself pass straight through.
const prefix = "{{M8_ARG";
/// The longer one, which is the only spelling with an argument's name in it
/// to make a flag from. `M8_ARGS` is the call rather than an argument.
const named = "M8_ARG_";

/// How a placeholder says what to do with the value it names.
const Form = enum {
    /// `{{M8_ARG_NAME}}` — the flag is the argument's own name.
    own,
    /// `{{M8_ARG_NAME|-f}}` — this flag, or none when nothing follows.
    given,
    /// `{{M8_ARG_NAME?-f}}` — the flag alone, and only when true.
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
    if (!std.mem.startsWith(u8, word, prefix)) return out.append(arena, word);
    if (!std.mem.endsWith(u8, word, "}}") or word.len <= prefix.len) {
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

    // The flag a bare placeholder carries is the argument's own name, which
    // is what the variable was made from in the first place.
    if (form == .own and std.mem.startsWith(u8, name, named) and name.len > named.len) {
        const lower = try std.ascii.allocLowerString(arena, name[named.len..]);
        flag = try std.fmt.allocPrint(arena, "--{s}", .{lower});
    }

    // A definition that could never emit anything is wrong however the call
    // went, so it is caught before the value is looked at.
    if (form == .boolean and flag.len == 0) {
        try err.print("m8 call: '{s}' asks for a flag and names none\n", .{word});
        return Error.FlaglessQuestion;
    }

    const value = env.get(name) orelse return;
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
    const vars = &[_][2][]const u8{.{ "M8_ARG_COMMAND", "echo hi" }};

    try expectArgv(try built(arena, vars, &.{"{{M8_ARG_COMMAND}}"}), &.{ "--command", "echo hi" });
    try expectArgv(try built(arena, vars, &.{"{{M8_ARG_COMMAND|-c}}"}), &.{ "-c", "echo hi" });
    try expectArgv(try built(arena, vars, &.{"{{M8_ARG_COMMAND|}}"}), &.{"echo hi"});

    // A placeholder is a whole element, so it sits among ordinary words
    // without either becoming part of the other.
    try expectArgv(
        try built(arena, vars, &.{ "bash", "-euo", "pipefail", "{{M8_ARG_COMMAND|-c}}" }),
        &.{ "bash", "-euo", "pipefail", "-c", "echo hi" },
    );
}

test "the call itself is not an argument, so it carries no flag" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"a\":1}";
    const vars = &[_][2][]const u8{.{ "M8_ARGS", json }};
    try expectArgv(try built(arena, vars, &.{"{{M8_ARGS}}"}), &.{json});
}

test "unset is absent, and empty is a value a command was given" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The whole of what optional means to a command: the flag is not there.
    try expectArgv(
        try built(arena, &.{}, &.{ "echo", "{{M8_ARG_NOPE}}", "x" }),
        &.{ "echo", "x" },
    );
    try expectArgv(
        try built(arena, &.{.{ "M8_ARG_E", "" }}, &.{ "echo", "{{M8_ARG_E}}" }),
        &.{ "echo", "--e", "" },
    );
}

test "true emits the flag alone, false and unset emit nothing" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const yes = &[_][2][]const u8{.{ "M8_ARG_DEEP", "true" }};
    const no = &[_][2][]const u8{.{ "M8_ARG_DEEP", "false" }};
    try expectArgv(try built(arena, yes, &.{"{{M8_ARG_DEEP?--deep}}"}), &.{"--deep"});
    try expectArgv(try built(arena, no, &.{"{{M8_ARG_DEEP?--deep}}"}), &.{});
    try expectArgv(try built(arena, &.{}, &.{"{{M8_ARG_DEEP?--deep}}"}), &.{});

    // Anything else is refused rather than dropped: a call that looked like
    // it succeeded while ignoring what was asked is the worse answer.
    const other = &[_][2][]const u8{.{ "M8_ARG_DEEP", "1" }};
    try testing.expectError(
        Error.NotABoolean,
        built(arena, other, &.{"{{M8_ARG_DEEP?--deep}}"}),
    );
}

test "only a word opening with the prefix is looked at" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The braces a templating language meant for itself, which is why the
    // prefix is matched rather than the braces alone.
    try expectArgv(
        try built(arena, &.{}, &.{ "awk", "{{print $1}}", "f" }),
        &.{ "awk", "{{print $1}}", "f" },
    );

    // Nor is one spliced into a larger word, so a value cannot become syntax.
    try expectArgv(
        try built(arena, &.{.{ "M8_ARG_X", "v" }}, &.{"x{{M8_ARG_X}}"}),
        &.{"x{{M8_ARG_X}}"},
    );
}

test "a definition that could never work is refused where it is written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectError(
        Error.UnclosedPlaceholder,
        built(arena, &.{}, &.{"{{M8_ARG_X}"}),
    );
    // Caught before the value is looked at, because it is wrong however the
    // call went.
    try testing.expectError(
        Error.FlaglessQuestion,
        built(arena, &.{}, &.{"{{M8_ARG_X?}}"}),
    );
}
