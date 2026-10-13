//! Reading a 🧰 and turning a call into a command line.
//!
//! The harness hands back a 🧰's content as bytes and knows nothing about what
//! is in it. Underneath a sigil the content is its own small markdown, and
//! this is where that becomes a tool: a quoted line is the description, a
//! bullet is an argument, a 🛡 is something to stand inside, and backticks or
//! a fence are how it runs. Every kind is told apart by its own shape, so none
//! of it depends on the order they were written in.
//!
//! Two ways to say how it runs, and neither of them carries what the call
//! said: an argv is the words it was written as, a block is the script it was
//! written as, and both reach their command unchanged. A call arrives in the
//! environment as `__name__`, whichever of the two it is.
//!
//! One level down, the quote that doc.zig stripped is still there — a nested
//! content line arrives as `> text`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sigil = @import("m8/sigil.zig");
const doc = @import("m8/doc.zig");
const Mode = sigil.Mode;
const api = @import("api.zig");
const shield = @import("shield.zig");
const markdown = @import("m8/markdown.zig");
const model = @import("m8/model.zig");
const argname = @import("argname.zig");

pub const Error = error{
    /// A property line had no type.
    MissingType,
    /// Two properties would be the same environment variable. Caught where the
    /// tool is written rather than when a model happens to supply both.
    ClashingProperty,
    /// A definition-provided environment name was not a portable argument name.
    BadEnvironmentName,
    /// Definition, variable, and activation are separate header forms.
    VariableOnDefinition,
};

pub const Property = struct {
    /// May be a dotted path: `parent.child`.
    name: []const u8,
    /// `string`, `object`, `Type[]`, or `A|B|C` for an enum.
    type: []const u8,
    description: []const u8 = "",
    required: bool,
    /// Schema keys beyond the type, from `,key:value` after it. JSON Schema's
    /// own, passed through as written the way a model's parameters are: m8
    /// has no vocabulary here, and what they mean is the provider's business.
    extras: []const Extra = &.{},
};

pub const Extra = struct {
    key: []const u8,
    value: std.json.Value,
};

/// How a tool runs.
pub const Command = union(enum) {
    /// Nothing said. A tool read back off a wire is an interface only.
    none,
    /// Backtick spans on one line, one argv element each, handed on as
    /// they were written. A command wanting flags rather than variables
    /// says so itself — `m8 call` is the one m8 ships.
    argv: []const []const u8,
    /// A fenced block, run through the 🏃 its language names. The script m8
    /// hands over is the script that was written.
    block: shield.Fence,
};

pub const Tool = struct {
    name: []const u8,
    description: []const u8 = "",
    /// How it runs. Two spellings, and neither is handed what the call
    /// said — that arrives in the environment either way, which is the one
    /// mechanism there is.
    command: Command = .none,
    /// Further 🛡 this tool stands inside, on top of whatever the agent
    /// already activated. It can only add — which is the whole rule.
    shields: []const shield.Activation = &.{},
    /// A variable this tool adds to what its call is handed, from the value's
    /// last fields. The same shape a 🛡 uses, for the same reason: something a
    /// definition says once rather than a call having to carry it.
    env_var: []const u8 = "",
    env_values: []const []const u8 = &.{},
    /// Definition-level variables, allowing one `:toolbox:` header per value.
    env_vars: []const api.EnvVar = &.{},
    properties: []const Property = &.{},
};

/// What a call is handed under, in the environment rather than in the command.
///
/// Named rather than positional, so a tool in any language reads them the way
/// that language already reads its environment, and a value carries no
/// position for a command line to have to keep.
/// The whole call as JSON. Scalar arguments use `__name__`; nested, dotted
/// and arrayed arguments have no scalar spelling and live here instead.
pub const args_var = argname.all;
/// Which call this is, so a tool that runs m8 can answer the one it was asked.
pub const call_var = "M8_CALL_ID";

/// The environment name a property has, or null when it has none.
///
/// A portable identifier and nothing else, uppercased. A dotted path, a hyphen,
/// a leading digit — those have no env spelling, and inventing one by mangling
/// would collide with a name somebody meant. Such a property lives in
/// `args_var` alone, which is honest rather than lossy.
pub fn envName(arena: Allocator, name: []const u8) Allocator.Error!?[]const u8 {
    return argname.envName(arena, name);
}

/// `NAME TYPE` or `NAME? TYPE`, from a bullet with its `*` already gone,
/// and either followed by `,key:value` extras.
///
/// The name runs to the first space and the type is the rest of the line, so
/// the last field may hold one safely and an enum keeps its spaces. `?` on the
/// name carries optional, which used to be a sigil of its own. A comma ends
/// the type rather than a space for the same reason, and the extras after it
/// are split the way a 🧠's parameters are, so a JSON value keeps its commas.
fn property(arena: Allocator, rest: []const u8) !Property {
    const line = std.mem.trim(u8, rest, " \t");
    const cut = std.mem.indexOfAny(u8, line, " \t") orelse return Error.MissingType;
    var name = line[0..cut];
    const optional = std.mem.endsWith(u8, name, "?");
    if (optional) name = name[0 .. name.len - 1];
    const parts = try model.fields(arena, line[cut + 1 ..]);
    const kind = std.mem.trim(u8, parts[0], " \t");
    if (name.len == 0 or kind.len == 0) return Error.MissingType;

    var extras: std.ArrayList(Extra) = .empty;
    for (parts[1..]) |one| {
        const field = std.mem.trim(u8, one, " \t");
        if (field.len == 0) continue;
        const at = std.mem.indexOfScalar(u8, field, ':') orelse continue;
        try extras.append(arena, .{
            .key = std.mem.trim(u8, field[0..at], " \t"),
            .value = model.json(arena, std.mem.trim(u8, field[at + 1 ..], " \t")),
        });
    }
    return .{ .name = name, .type = kind, .required = !optional, .extras = extras.items };
}

/// Parse the content of a 🧰 whose value is `NAME` or `NAME VAR value...`.
pub fn parse(arena: Allocator, mode: Mode, header: []const u8, content: []const u8) !Tool {
    // The spaces after the name carry a variable and what to append to it,
    // the shape a 🛡 has.
    var rest = std.mem.tokenizeAny(u8, header, " \t");
    const name = rest.next() orelse "";

    const raw_env_var = rest.next() orelse "";
    const env_var = if (raw_env_var.len == 0)
        ""
    else
        (try envName(arena, raw_env_var)) orelse return Error.BadEnvironmentName;
    var env_values: std.ArrayList([]const u8) = .empty;
    while (rest.next()) |v| try env_values.append(arena, v);
    const quote = doc.quote(mode);
    const bare = doc.bareQuote(mode);

    var props: std.ArrayList(Property) = .empty;
    var shields: std.ArrayList(shield.Activation) = .empty;
    var description: std.ArrayList(u8) = .empty;
    var command: Command = .none;

    // Every kind of line is told apart by its own shape, so none of this
    // depends on the order they were written in.
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // A quoted line is the tool's own description: what the model is told
        // this tool is for.
        if (std.mem.startsWith(u8, line, quote) or std.mem.eql(u8, line, bare)) {
            const text = if (line.len > bare.len) line[quote.len..] else "";
            description.items = @constCast(try join(arena, description.items, text));
            continue;
        }

        const trimmed = std.mem.trim(u8, line, " \t");

        // A fenced block, and an argv are the two ways to say how it runs.
        if (markdown.opensFence(line)) {
            command = .{ .block = try markdown.readFence(arena, line, &lines) };
            continue;
        }

        // Indented under a bullet, so it belongs to that argument — whatever
        // it starts with. A description that runs to a list of its own would
        // otherwise turn every item of it into an argument nobody declared,
        // and the model would be asked for six things that do not exist.
        if (props.items.len > 0 and line.len > 0 and (line[0] == ' ' or line[0] == '\t')) {
            const last = &props.items[props.items.len - 1];
            last.description = try join(arena, last.description, trimmed);
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "*")) {
            try props.append(arena, try property(arena, trimmed[1..]));
            continue;
        }

        if (sigil.match(mode, trimmed)) |m| {
            if (m.sigil == .shield)
                try shields.append(arena, try shield.parseValue(arena, trimmed[m.len..]));
            continue;
        }

        if (try shield.inlineArgv(arena, trimmed)) |argv| {
            command = .{ .argv = argv };
            continue;
        }
    }

    // Two properties that would be one variable are a fault in the tool, not
    // in the call that happens to supply both. Said here, where it is written.
    for (props.items, 0..) |a, i| {
        const an = (try envName(arena, a.name)) orelse continue;
        for (props.items[i + 1 ..]) |b| {
            const bn = (try envName(arena, b.name)) orelse continue;
            if (std.mem.eql(u8, an, bn)) return Error.ClashingProperty;
        }
    }

    return .{
        .name = name,
        .env_var = env_var,
        .env_values = env_values.items,
        .env_vars = if (env_var.len > 0) &.{.{ .key = env_var, .value = try std.mem.join(arena, " ", env_values.items) }} else &.{},
        .description = std.mem.trim(u8, description.items, "\n"),
        .command = command,
        .shields = shields.items,
        .properties = props.items,
    };
}

/// The environment a call hands its tool: one variable per scalar that has an
/// env spelling, the whole call as JSON, and which call it is.
///
/// A scalar is a string, a number or a boolean — what a shell can read as a
/// word. An array or an object has no such spelling and is in `args_var` with
/// everything else. An argument that was not supplied is unset rather than
/// empty, which is the whole of what optional means to whatever reads it.
pub fn callEnv(
    arena: Allocator,
    args: std.json.Value,
    raw_args: []const u8,
    call_id: []const u8,
) Allocator.Error![]const api.EnvVar {
    var out: std.ArrayList(api.EnvVar) = .empty;
    try out.append(arena, .{ .key = args_var, .value = raw_args });
    if (call_id.len > 0) try out.append(arena, .{ .key = call_var, .value = call_id });

    if (args != .object) return out.items;
    var it = args.object.iterator();
    while (it.next()) |e| {
        const key = (try envName(arena, e.key_ptr.*)) orelse continue;
        const value: []const u8 = switch (e.value_ptr.*) {
            .string => |v| v,
            .number_string => |v| v,
            .integer => |v| try std.fmt.allocPrint(arena, "{d}", .{v}),
            .float => |v| try std.fmt.allocPrint(arena, "{d}", .{v}),
            .bool => |v| if (v) "true" else "false",
            // Absent and null are the same absence, and unset is how a script
            // is told so. An array or an object is in the JSON instead.
            else => continue,
        };
        try out.append(arena, .{ .key = key, .value = value });
    }
    return out.items;
}

fn join(arena: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    if (a.len == 0) return arena.dupe(u8, b);
    return std.fmt.allocPrint(arena, "{s}\n{s}", .{ a, b });
}

// -------------------------------------------------------------- the schema

/// Write the tool as an OpenAI-style function declaration.
///
/// Names are flat dotted paths here and nested objects on the wire, so this
/// walks a level at a time: everything one segment past `prefix` belongs to
/// this object, and an `object` among them opens the next.
pub fn writeSchema(s: *std.json.Stringify, t: Tool) SchemaError!void {
    try s.beginObject();
    try s.objectField("type");
    try s.write("function");
    try s.objectField("function");
    try s.beginObject();
    try s.objectField("name");
    try s.write(t.name);
    if (t.description.len > 0) {
        try s.objectField("description");
        try s.write(t.description);
    }
    try s.objectField("parameters");
    try writeParameters(s, t.properties);
    try s.endObject();
    try s.endObject();
}

/// The schema itself, without the field an api hangs it from.
///
/// Chat completions calls that field `parameters` and messages calls it
/// `input_schema`. The schema under it is the same schema, so it is written
/// here once and each codec names its own field.
pub fn writeParameters(s: *std.json.Stringify, props: []const Property) SchemaError!void {
    return writeObject(s, props, "", &.{});
}

/// Stated explicitly because `writeObject` and `writeType` are mutually
/// recursive, and an inferred set cannot close over itself.
pub const SchemaError = std.Io.Writer.Error;

fn writeObject(
    s: *std.json.Stringify,
    props: []const Property,
    prefix: []const u8,
    extras: []const Extra,
) SchemaError!void {
    try s.beginObject();
    try writeExtras(s, extras, &.{ "type", "properties", "required" });
    try s.objectField("type");
    try s.write("object");
    try s.objectField("properties");
    try s.beginObject();
    for (props) |p| {
        const leaf = segment(p.name, prefix) orelse continue;
        try s.objectField(leaf);
        try writeType(s, props, p);
    }
    try s.endObject();

    try s.objectField("required");
    try s.beginArray();
    for (props) |p| {
        const leaf = segment(p.name, prefix) orelse continue;
        if (p.required) try s.write(leaf);
    }
    try s.endArray();
    try s.endObject();
}

fn writeType(s: *std.json.Stringify, props: []const Property, p: Property) SchemaError!void {
    // Arrayness lives on the parent type; the children carry plain dots.
    const array = std.mem.endsWith(u8, p.type, "[]");
    const base = if (array) p.type[0 .. p.type.len - 2] else p.type;
    // Extras go on the outermost node, so an array's are the array's own. A
    // key meant for its items is written as `items:{...}` by whoever means it.
    const inner: []const Extra = if (array) &.{} else p.extras;

    if (array) {
        try s.beginObject();
        try writeExtras(s, p.extras, &.{ "type", "items" });
        try s.objectField("type");
        try s.write("array");
        try s.objectField("items");
    }

    if (std.mem.eql(u8, base, "object")) {
        // An object's own children carry the descriptions.
        try writeObject(s, props, p.name, inner);
    } else {
        try s.beginObject();
        const is_enum = std.mem.indexOfScalar(u8, base, '|') != null;
        const described = p.description.len > 0;
        // Only what this node is actually given: an extra `description` on a
        // bullet with no lines under it has nothing to lose to.
        const own = [_][]const u8{
            "type",
            if (is_enum) "enum" else "",
            if (described) "description" else "",
        };
        try writeExtras(s, inner, &own);
        try s.objectField("type");
        if (std.mem.indexOfScalar(u8, base, '|') != null) {
            // An enum is a string with the values named.
            try s.write("string");
            try s.objectField("enum");
            try s.beginArray();
            var it = std.mem.splitScalar(u8, base, '|');
            while (it.next()) |v| try s.write(std.mem.trim(u8, v, " \t"));
            try s.endArray();
        } else {
            try s.write(base);
        }
        if (p.description.len > 0) {
            try s.objectField("description");
            try s.write(p.description);
        }
        try s.endObject();
    }

    if (array) try s.endObject();
}

/// Extras, less any key m8 writes on this node itself.
///
/// The ledger keeps a key said twice — `description` as an extra and from the
/// lines under the bullet — because the format has no opinion on it. The wire
/// does: these are m8's own codecs, and sending a duplicate would leave which
/// one counts to whichever provider reads it. So m8's own wins here, and the
/// request says one thing.
fn writeExtras(s: *std.json.Stringify, extras: []const Extra, own: []const []const u8) SchemaError!void {
    next: for (extras) |e| {
        for (own) |k| if (std.mem.eql(u8, k, e.key)) continue :next;
        try s.objectField(e.key);
        try s.write(e.value);
    }
}

/// The one segment of `name` directly beneath `prefix`, or null when `name`
/// belongs somewhere else entirely.
fn segment(name: []const u8, prefix: []const u8) ?[]const u8 {
    var rest = name;
    if (prefix.len > 0) {
        if (!std.mem.startsWith(u8, name, prefix)) return null;
        if (name.len <= prefix.len or name[prefix.len] != '.') return null;
        rest = name[prefix.len + 1 ..];
    }
    // One segment only: anything deeper belongs to a nested object.
    return if (std.mem.indexOfScalar(u8, rest, '.') == null) rest else null;
}

/// Write a 🧰's content: the inverse of `parse`, in `mode`.
///
/// Nested content carries the quote of the document it sits in, so a tool
/// moves between spellings by being rendered rather than by having its bytes
/// rewritten. Records are emitted in a canonical order, so `render` after
/// `parse` yields the same tool rather than the same bytes.
pub fn render(arena: Allocator, mode: Mode, t: Tool) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    const w = &buf.writer;

    // The description first, because it is what the tool is; then what it
    // stands inside, then how it runs, then what it takes.
    if (t.description.len > 0) try writeNested(w, mode, t.description);
    for (t.shields) |sh| {
        try w.print("{s}{s}", .{ sigil.Sigil.shield.text(mode), sh.name });
        if (sh.env_var.len > 0) try w.print(" {s}", .{sh.env_var});
        for (sh.values) |v| try w.print(" {s}", .{v});
        try w.writeByte('\n');
    }
    switch (t.command) {
        .none => {},
        .argv => |argv| {
            for (argv, 0..) |word, i| {
                if (i > 0) try w.writeByte(' ');
                try markdown.writeSpan(w, word);
            }
            try w.writeByte('\n');
        },
        .block => |b| try markdown.writeFence(w, "", b.runner, b.code),
    }
    for (t.properties) |p| {
        try w.print("* {s}{s} {s}", .{ p.name, if (p.required) "" else "?", p.type });
        for (p.extras) |e| try w.print(",{s}:{s}", .{ e.key, try model.written(arena, e.value) });
        try w.writeByte('\n');
        var it = std.mem.splitScalar(u8, p.description, '\n');
        while (it.next()) |d| {
            if (p.description.len == 0) break;
            try w.print("  {s}\n", .{d});
        }
    }
    // A content block is lines joined by \n, with no trailing one; the
    // framing belongs to doc.write.
    return std.mem.trimEnd(u8, buf.written(), "\n");
}

/// A description one quote deeper, which is where a property's own content
/// lives once doc.zig has stripped the outer level.
fn writeNested(w: *std.Io.Writer, mode: Mode, text: []const u8) !void {
    if (text.len == 0) return;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (line.len == 0) {
            try w.writeAll(doc.bareQuote(mode));
        } else {
            try w.writeAll(doc.quote(mode));
            try w.writeAll(line);
        }
        try w.writeByte('\n');
    }
}

// ------------------------------------------------------------- call arguments

/// A call's arguments as bullets, one per key, so a saved turn reads as the
/// language rather than as a blob of JSON.
pub fn renderArgs(arena: Allocator, mode: Mode, args: []const u8) ![]const u8 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, args, .{}) catch
        return arena.dupe(u8, args);
    if (v != .object) return arena.dupe(u8, args);

    var buf: std.Io.Writer.Allocating = .init(arena);
    const w = &buf.writer;
    var it = v.object.iterator();
    while (it.next()) |e| {
        var text: std.Io.Writer.Allocating = .init(arena);
        try std.json.Stringify.value(e.value_ptr.*, .{}, &text.writer);
        // A string goes in as itself: the point is that a human reads the
        // value, not an escaped copy of it.
        const raw = if (e.value_ptr.* == .string) e.value_ptr.*.string else text.written();

        // The empty string is the name with nothing after it. A model that
        // has nothing to pass for an optional parameter can still pass it, and
        // a bare bullet says so in one line rather than three.
        if (raw.len == 0) {
            try w.print("* {s}\n", .{e.key_ptr.*});
            continue;
        }

        // One line fits beside its name, whatever is in it: a span carries a
        // backtick by opening with a longer run. Only more than one line
        // needs a block.
        if (std.mem.indexOfScalar(u8, raw, '\n') == null) {
            try w.print("* {s} ", .{e.key_ptr.*});
            try markdown.writeSpan(w, raw);
            try w.writeByte('\n');
            continue;
        }
        try w.print("* {s}\n", .{e.key_ptr.*});
        try markdown.writeFence(w, "  ", "", raw);
    }
    _ = mode;
    return std.mem.trimEnd(u8, buf.written(), "\n");
}

/// Read those bullets back into the JSON a provider wants.
///
/// A value that parses as JSON and is not a string is taken as that; anything
/// else is the text itself. The one ambiguity is a string that happens to
/// spell a number — `123` returns as an integer — and the alternative is
/// escaping every value, which would cost the block the readability it exists
/// for.
pub fn parseArgs(arena: Allocator, mode: Mode, content: []const u8) ![]const u8 {
    _ = mode;
    var obj: std.json.ObjectMap = .empty;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "*")) continue;

        const rest = std.mem.trim(u8, trimmed[1..], " \t");
        // The name runs to the first space, so the value beside it — which is
        // the whole of the rest — may hold as many as it likes.
        const cut = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        const key = rest[0..cut];
        if (key.len == 0) continue;

        const after = std.mem.trim(u8, rest[cut..], " \t");
        if (after.len > 0) {
            const found = try markdown.spans(arena, after);
            const value = if (found.len > 0) found[0] else after;
            try obj.put(arena, key, valueOf(arena, value));
            continue;
        }

        // Nothing beside it, so the value is the block underneath — and a
        // bullet with no block under it is the empty string, which is the
        // spelling `renderArgs` writes. The block form still reads the same,
        // so a model that writes one is understood either way.
        const opening = lines.peek() orelse {
            try obj.put(arena, key, .{ .string = "" });
            break;
        };
        if (!markdown.opensFence(opening)) {
            try obj.put(arena, key, .{ .string = "" });
            continue;
        }
        _ = lines.next();
        const f = try markdown.readFence(arena, opening, &lines);
        try obj.put(arena, key, valueOf(arena, f.code));
    }

    var buf: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(std.json.Value{ .object = obj }, .{}, &buf.writer);
    return buf.written();
}

fn valueOf(arena: Allocator, text: []const u8) std.json.Value {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch
        return .{ .string = text };
    return if (v == .string) .{ .string = text } else v;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a toolbox reads its template, properties and description" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const t = try parse(a.allocator(), .md, "shell",
        \\`m8` `call` `bash` `{{cmd|-c}}`
        \\:shield:jail
        \\* cmd string
        \\  The command to run
        \\* dir? string
        \\  Where to run it
        \\> Run a command.
        \\> Carefully.
    );
    try testing.expectEqualStrings("shell", t.name);
    try testing.expectEqualStrings("m8", t.command.argv[0]);
    try testing.expectEqualStrings("{{cmd|-c}}", t.command.argv[3]);
    try testing.expectEqualStrings("Run a command.\nCarefully.", t.description);
    try testing.expectEqual(@as(usize, 1), t.shields.len);
    try testing.expectEqualStrings("jail", t.shields[0].name);

    try testing.expectEqual(@as(usize, 2), t.properties.len);
    try testing.expectEqualStrings("cmd", t.properties[0].name);
    try testing.expectEqualStrings("string", t.properties[0].type);
    try testing.expectEqualStrings("The command to run", t.properties[0].description);
    try testing.expect(t.properties[0].required);
    try testing.expect(!t.properties[1].required);
}

test "a toolbox reads the same in either spelling" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const md = try parse(arena, .md, "x", "* cmd string\n  Desc\n> Runs.");
    const m8 = try parse(arena, .m8, "x", "* cmd string\n  Desc\n\u{2502} Runs.");
    try testing.expectEqualStrings(md.description, m8.description);
    try testing.expectEqualStrings(md.properties[0].description, m8.properties[0].description);
}

test "a command is backtick spans, and a line without them is not one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Backticks are what makes a line a command, so a line without them is
    // not one and the tool is left as an interface only.
    const bare = try parse(arena, .md, "x", "bash -c");
    try testing.expect(bare.command == .none);

    const spans = try parse(arena, .md, "x", "`bash` `-c`");
    try testing.expectEqual(@as(usize, 2), spans.command.argv.len);
    try testing.expectEqualStrings("bash", spans.command.argv[0]);
    try testing.expectEqualStrings("-c", spans.command.argv[1]);
}

fn schemaOf(arena: Allocator, t: Tool) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    var s: std.json.Stringify = .{ .writer = &buf.writer };
    try writeSchema(&s, t);
    return buf.written();
}

test "a flat tool becomes a function declaration" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try parse(arena, .md, "shell",
        \\* cmd string
        \\  The command
        \\* quiet? boolean
        \\> Runs a command.
    );
    try testing.expectEqualStrings(
        \\{"type":"function","function":{"name":"shell","description":"Runs a command.","parameters":{"type":"object","properties":{"cmd":{"type":"string","description":"The command"},"quiet":{"type":"boolean"}},"required":["cmd"]}}}
    , try schemaOf(arena, t));
}

test "enums, arrays and nesting reach the wire" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try parse(arena, .md, "t",
        \\* unit celsius|fahrenheit
        \\* tags string[]
        \\* opts object
        \\* opts.depth integer
        \\* opts.name? string
    );
    const got = try schemaOf(arena, t);
    try testing.expect(std.mem.indexOf(u8, got, "\"enum\":[\"celsius\",\"fahrenheit\"]") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"opts\":{\"type\":\"object\"") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"depth\":{\"type\":\"integer\"}") != null);
    // The nested required list holds the child, and the outer one does not.
    try testing.expect(std.mem.indexOf(u8, got, "\"required\":[\"depth\"]") != null);
}

test "extras after the type reach the wire as written, before m8's own keys" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try parse(arena, .md, "t",
        \\* limit integer,minimum:0,examples:[1,2]
        \\  How many
        \\* tone warm | dry,note:"a, b"
        \\* ids? string[],maxItems:5
        \\* opts object,additionalProperties:false
        \\* opts.depth PositiveInt
    );
    try testing.expectEqualStrings("integer", t.properties[0].type);
    try testing.expectEqualStrings("warm | dry", t.properties[1].type);
    const got = try schemaOf(arena, t);
    // A JSON value keeps its commas, and nothing is translated — not even a
    // type no provider has heard of.
    try testing.expect(std.mem.indexOf(u8, got, "\"limit\":{\"minimum\":0,\"examples\":[1,2],\"type\":\"integer\",\"description\":\"How many\"}") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"tone\":{\"note\":\"a, b\",\"type\":\"string\",\"enum\":[\"warm\",\"dry\"]}") != null);
    // An array's extras are the array's own, not its items'.
    try testing.expect(std.mem.indexOf(u8, got, "\"ids\":{\"maxItems\":5,\"type\":\"array\",\"items\":{\"type\":\"string\"}}") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"opts\":{\"additionalProperties\":false,\"type\":\"object\"") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"depth\":{\"type\":\"PositiveInt\"}") != null);
}

test "a key written twice goes out once, as m8's own" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const t = try parse(arena, .md, "t",
        \\* q string,description:extra,pattern:^a
        \\  native
    );
    const got = try schemaOf(arena, t);
    try testing.expect(std.mem.indexOf(u8, got, "{\"pattern\":\"^a\",\"type\":\"string\",\"description\":\"native\"}") != null);

    // With nothing of m8's own to lose to, the extra is what goes out.
    const bare = try parse(arena, .md, "t", "* q string,description:extra");
    try testing.expect(std.mem.indexOf(u8, try schemaOf(arena, bare), "{\"description\":\"extra\",\"type\":\"string\"}") != null);
}

test "logical property names become their environment spellings" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    // The logical name is preserved, including its capitalization.
    const t = try parse(a.allocator(), .md, "x", "* self string\n* secures string");
    try testing.expectEqual(@as(usize, 2), t.properties.len);
    try testing.expectEqualStrings("__self__", (try envName(a.allocator(), t.properties[0].name)).?);
}

test "a tool survives being rendered and read back, in either spelling" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const src =
        \\`m8` `call` `bash` `{{cmd|-c}}`
        \\:shield:jail
        \\* cmd string
        \\  What to run.
        \\  Two lines of it.
        \\* with? check|sandbox
        \\  Extras.
        \\* opts object
        \\* opts.depth integer
        \\> Runs a command.
    ;
    const first = try parse(arena, .md, "shell", src);

    for ([_]Mode{ .md, .m8 }) |mode| {
        const again = try parse(arena, mode, "shell", try render(arena, mode, first));
        try testing.expectEqualStrings(first.name, again.name);
        try testing.expectEqualStrings(first.description, again.description);
        try testing.expectEqual(first.command.argv.len, again.command.argv.len);
        for (first.command.argv, again.command.argv) |x, y| try testing.expectEqualStrings(x, y);
        try testing.expectEqual(first.shields.len, again.shields.len);
        for (first.shields, again.shields) |x, y| try testing.expectEqualStrings(x.name, y.name);
        try testing.expectEqual(first.properties.len, again.properties.len);
        for (first.properties, again.properties) |x, y| {
            try testing.expectEqualStrings(x.name, y.name);
            try testing.expectEqualStrings(x.type, y.type);
            try testing.expectEqualStrings(x.description, y.description);
            try testing.expectEqual(x.required, y.required);
        }
    }
}

test "call arguments survive a trip through the document and back" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const args =
        \\{"cmd":"echo hi\nand bye","depth":3,"deep":{"a":[1,2]},"on":true}
    ;
    for ([_]Mode{ .md, .m8 }) |mode| {
        const back = try parseArgs(arena, mode, try renderArgs(arena, mode, args));
        const want = try std.json.parseFromSliceLeaky(std.json.Value, arena, args, .{});
        const got = try std.json.parseFromSliceLeaky(std.json.Value, arena, back, .{});
        try testing.expectEqualStrings(want.object.get("cmd").?.string, got.object.get("cmd").?.string);
        try testing.expectEqual(want.object.get("depth").?.integer, got.object.get("depth").?.integer);
        try testing.expectEqual(want.object.get("on").?.bool, got.object.get("on").?.bool);
        try testing.expectEqual(@as(usize, 2), got.object.get("deep").?.object.get("a").?.array.items.len);
    }
}

test "an empty string is the name and nothing after it" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // What gets written: a bare bullet, with no span and no block.
    try testing.expectEqualStrings(
        \\* old_string
        \\* path `HAIKU.md`
    , try renderArgs(arena, .md, "{\"old_string\":\"\",\"path\":\"HAIKU.md\"}"));

    // What gets read: the same, and the block spelling a model may write
    // instead, and a bare bullet does not swallow the line after it.
    for ([_][]const u8{
        "* old_string\n* path `HAIKU.md`",
        "* old_string\n  ```\n\n  ```\n* path `HAIKU.md`",
    }) |src| {
        const got = try std.json.parseFromSliceLeaky(std.json.Value, arena, try parseArgs(arena, .md, src), .{});
        try testing.expectEqualStrings("", got.object.get("old_string").?.string);
        try testing.expectEqualStrings("HAIKU.md", got.object.get("path").?.string);
    }
}

test "a property has an environment name only when it already is one" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectEqualStrings("__pattern__", (try envName(arena, "pattern")).?);
    try testing.expectEqualStrings("__ignore_case__", (try envName(arena, "ignore_case")).?);
    try testing.expectEqualStrings("__myArg__", (try envName(arena, "myArg")).?);

    // No mangling: a name that is not already an identifier has no variable,
    // and is read from the JSON instead.
    for ([_][]const u8{ "opts.a", "dry-run", "2fast", "a b" }) |n|
        try testing.expect((try envName(arena, n)) == null);
    try testing.expectEqualStrings("____", (try envName(arena, "")).?);
}

test "argument environment names preserve case and spelling" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // These are distinct environment variables under the new convention.
    _ = try parse(arena, .md, "t", "* myArg string\n* MYARG string\n");
    _ = try parse(arena, .md, "t", "* myArg string\n* my_arg string\n");
}

test "a call is handed its arguments named, and all of them as JSON" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const raw =
        \\{"pattern":"x . ; rm -rf ~","count":3,"deep":true,"tags":["a"],"opts":{"a":1},"skipped":null}
    ;
    const args = try std.json.parseFromSliceLeaky(std.json.Value, arena, raw, .{});
    const env = try callEnv(arena, args, raw, "c7");

    const find = struct {
        fn get(vars: []const api.EnvVar, key: []const u8) ?[]const u8 {
            for (vars) |v| if (std.mem.eql(u8, v.key, key)) return v.value;
            return null;
        }
    }.get;

    // The value arrives whole and inert: it is never part of any command.
    try testing.expectEqualStrings("x . ; rm -rf ~", find(env, "__pattern__").?);
    try testing.expectEqualStrings("3", find(env, "__count__").?);
    try testing.expectEqualStrings("true", find(env, "__deep__").?);
    try testing.expectEqualStrings("c7", find(env, call_var).?);
    try testing.expectEqualStrings("M8_CALL_ID", call_var);
    try testing.expectEqualStrings(raw, find(env, args_var).?);

    // Compound values have no env spelling, and null is an absence rather
    // than an empty string. Both are in the JSON, which is where they read.
    try testing.expect(find(env, "__tags__") == null);
    try testing.expect(find(env, "__opts__") == null);
    try testing.expect(find(env, "__skipped__") == null);
}

test "a 🧰 may add a variable of its own, after its name" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const both = try parse(arena, .md, "make secures airgap no-writes", "`sh`");
    try testing.expectEqualStrings("make", both.name);
    try testing.expectEqualStrings("__secures__", both.env_var);
    try testing.expectEqual(@as(usize, 2), both.env_values.len);
    try testing.expectEqualStrings("no-writes", both.env_values[1]);

    const bare = try parse(arena, .md, "make", "`sh`");
    try testing.expectEqualStrings("make", bare.name);
    try testing.expectEqualStrings("", bare.env_var);
}
