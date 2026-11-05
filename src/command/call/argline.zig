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
    /// `!` with no flag after it, which could never emit anything.
    FlaglessNegation,
    /// `?` on a value that is neither `true` nor `false`.
    NotABoolean,
    /// List expansion needs an array of scalar values.
    NotAList,
    NotAListItem,
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
    /// `{{name!--f}}` — the flag alone, unless the value is exactly true.
    unless_true,
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
    if (std.mem.indexOfAny(u8, inner, "|?!")) |cut| {
        name = inner[0..cut];
        flag = inner[cut + 1 ..];
        form = switch (inner[cut]) {
            '?' => .boolean,
            '!' => .unless_true,
            else => .given,
        };
    }

    const list = (form == .own or form == .given) and
        name.len >= 2 and name[0] == '[' and name[name.len - 1] == ']';
    if (list) name = name[1 .. name.len - 1];

    // The flag a bare placeholder carries is the argument's own name. An
    // empty name therefore naturally becomes `--`, the all-arguments form.
    if (form == .own) flag = try std.fmt.allocPrint(arena, "--{s}", .{name});

    // A definition that could never emit anything is wrong however the call
    // went, so it is caught before the value is looked at.
    if (form == .boolean and flag.len == 0) {
        try err.print("m8 call: '{s}' asks for a flag and names none\n", .{word});
        return Error.FlaglessQuestion;
    }
    if (form == .unless_true and flag.len == 0) {
        try err.print("m8 call: '{s}' asks for a flag and names none\n", .{word});
        return Error.FlaglessNegation;
    }

    const key = (try argname.envName(arena, name)) orelse return out.append(arena, word);
    if (list) return expandList(arena, env, err, out, name, flag);
    const value = env.get(key) orelse {
        if (form == .unless_true) return out.append(arena, flag);
        return;
    };
    if (form == .unless_true) {
        if (std.mem.eql(u8, value, "true")) return;
        return out.append(arena, flag);
    }
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

/// Arrays have no scalar environment spelling; read them from the whole call.
fn expandList(
    arena: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    err: *std.Io.Writer,
    out: *std.ArrayList([]const u8),
    name: []const u8,
    flag: []const u8,
) !void {
    const raw = env.get("____") orelse return;
    const call = try std.json.parseFromSlice(std.json.Value, arena, raw, .{
        .allocate = .alloc_always,
        .parse_numbers = false,
    });
    if (call.value != .object) {
        try err.writeAll("m8 call: list expansion requires a JSON object in ____\n");
        return Error.NotAList;
    }
    const value = call.value.object.get(name) orelse return;
    if (value != .array) {
        try err.print("m8 call: {s} must be a list\n", .{name});
        return Error.NotAList;
    }
    for (value.array.items, 0..) |item, i| {
        const text = switch (item) {
            .string, .number_string => |v| v,
            .bool => |v| if (v) "true" else "false",
            else => {
                try err.print("m8 call: {s}[{d}] must be a string, number or boolean\n", .{ name, i });
                return Error.NotAListItem;
            },
        };
        if (flag.len > 0) try out.append(arena, flag);
        try out.append(arena, text);
    }
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

test "inverse conditional emits unless the value is exactly true" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const placeholder = &.{"{{deep!--deep}}"};

    const yes = &[_][2][]const u8{.{ "__deep__", "true" }};
    const no = &[_][2][]const u8{.{ "__deep__", "false" }};
    const other = &[_][2][]const u8{.{ "__deep__", "1" }};
    const empty = &[_][2][]const u8{.{ "__deep__", "" }};
    try expectArgv(try built(arena, yes, placeholder), &.{});
    try expectArgv(try built(arena, no, placeholder), &.{"--deep"});
    try expectArgv(try built(arena, &.{}, placeholder), &.{"--deep"});
    try expectArgv(try built(arena, other, placeholder), &.{"--deep"});
    try expectArgv(try built(arena, empty, placeholder), &.{"--deep"});
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

test "list placeholders expand whole-call JSON items in order" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"items\":[\"a b\",\"\",7,true,false]}";
    const vars = &[_][2][]const u8{.{ "____", json }};

    try expectArgv(
        try built(arena, vars, &.{ "before", "{{[items]}}", "after" }),
        &.{ "before", "--items", "a b", "--items", "", "--items", "7", "--items", "true", "--items", "false", "after" },
    );
    try expectArgv(
        try built(arena, vars, &.{"{{[items]|--foo}}"}),
        &.{ "--foo", "a b", "--foo", "", "--foo", "7", "--foo", "true", "--foo", "false" },
    );
    try expectArgv(
        try built(arena, vars, &.{"{{[items]|}}"}),
        &.{ "a b", "", "7", "true", "false" },
    );
}

test "missing and empty JSON lists emit nothing" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const placeholder = &.{ "x", "{{[items]}}", "y" };

    try expectArgv(try built(arena, &.{}, placeholder), &.{ "x", "y" });
    try expectArgv(
        try built(arena, &.{.{ "____", "{}" }}, placeholder),
        &.{ "x", "y" },
    );
    try expectArgv(
        try built(arena, &.{.{ "____", "{\"items\":[]}" }}, placeholder),
        &.{ "x", "y" },
    );
}

test "list placeholders reject non-arrays and non-scalar items" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const template = &.{"{{[items]}}"};

    inline for (.{
        "{\"items\":null}",
        "{\"items\":\"text\"}",
        "{\"items\":3}",
        "{\"items\":true}",
        "{\"items\":{}}",
    }) |json| try testing.expectError(
        Error.NotAList,
        built(arena, &.{.{ "____", json }}, template),
    );
    inline for (.{
        "null",
        "{}",
        "[]",
        "[1]",
    }) |item| {
        const json = try std.fmt.allocPrint(arena, "{{\"items\":[{s}]}}", .{item});
        try testing.expectError(
            Error.NotAListItem,
            built(arena, &.{.{ "____", json }}, template),
        );
    }
}

test "scalar placeholders remain unchanged beside list placeholders" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const vars = &[_][2][]const u8{
        .{ "____", "{\"items\":[\"first\",\"last\"]}" },
        .{ "__name__", "value with spaces" },
    };
    try expectArgv(
        try built(arena, vars, &.{ "{{name}}", "{{[items]|}}", "{{name|-n}}" }),
        &.{ "--name", "value with spaces", "first", "last", "-n", "value with spaces" },
    );
}

test "list items are literal and number spellings are preserved" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const vars = &[_][2][]const u8{
        .{ "____", "{\"items\":[\"{{name}}\",\"$(echo nope)\",1.25,1e3]}" },
        .{ "__name__", "not expanded" },
        .{ "__items__", "not the list" },
    };
    try expectArgv(
        try built(arena, vars, &.{"{{[items]|}}"}),
        &.{ "{{name}}", "$(echo nope)", "1.25", "1e3" },
    );
}
