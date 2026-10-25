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
    // stands inside, then how it runs, then what it takes. An empty line ends
    // it, or anything rendering the file reads the next line as more of it.
    if (t.description.len > 0) {
        try writeNested(w, mode, t.description);
        try w.writeByte('\n');
    }
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

/// Arguments are self-describing: spans and json fences hold JSON, text
/// fences hold literal strings, and a bare bullet is null. Keep every key,
/// including those not defined by the tool, in its original order.
pub fn renderArgs(arena: Allocator, mode: Mode, args: []const u8) ![]const u8 {
    _ = mode;
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, args, .{});
    if (v != .object) return error.InvalidCallArguments;
    var buf: std.Io.Writer.Allocating = .init(arena);
    const w = &buf.writer;
    var it = v.object.iterator();
    while (it.next()) |e| {
        const value = e.value_ptr.*;
        if (value == .null) {
            try w.print("* {s}\n", .{e.key_ptr.*});
            continue;
        }
        var json: std.Io.Writer.Allocating = .init(arena);
        const portable_json = value == .string and needsPortableJson(value.string);
        try std.json.Stringify.value(value, .{ .escape_unicode = portable_json }, &json.writer);
        const raw = json.written();
        if (value == .string) {
            // Without escapes JSON adds only the two surrounding quotes.
            if (portable_json) {
                try w.print("* {s}\n", .{e.key_ptr.*});
                try markdown.writeFence(w, "  ", "json", raw);
                continue;
            }
            if (!std.mem.eql(u8, raw[1 .. raw.len - 1], value.string)) {
                try w.print("* {s}\n", .{e.key_ptr.*});
                try markdown.writeFence(w, "  ", "text", value.string);
                continue;
            }
        }
        var span: std.Io.Writer.Allocating = .init(arena);
        try markdown.writeSpan(&span.writer, raw);
        const complex = value == .array or value == .object;
        const line_len = 2 + e.key_ptr.*.len + 1 + span.written().len;
        if (complex and line_len > 100) {
            var pretty: std.Io.Writer.Allocating = .init(arena);
            try std.json.Stringify.value(value, .{ .whitespace = .indent_2 }, &pretty.writer);
            try w.print("* {s}\n", .{e.key_ptr.*});
            try markdown.writeFence(w, "  ", "json", pretty.written());
        } else {
            try w.print("* {s} {s}\n", .{ e.key_ptr.*, span.written() });
        }
    }
    return std.mem.trimEnd(u8, buf.written(), "\n");
}

/// Tabs and LF have portable literal text spellings. Other control characters
/// use a JSON fence, escaping Unicode there as well for safe document transport.
fn needsPortableJson(text: []const u8) bool {
    for (text, 0..) |c, i| {
        if ((c < 0x20 and c != '\t' and c != '\n') or c == 0x7f) return true;
        if (c == 0xc2 and i + 1 < text.len and text[i + 1] >= 0x80 and text[i + 1] <= 0x9f) return true;
        if (c == 0xe2 and i + 2 < text.len and text[i + 1] == 0x80 and (text[i + 2] == 0xa8 or text[i + 2] == 0xa9)) return true;
    }
    return false;
}

/// Decode the value's explicit spelling, independently of any tool schema.
/// No bullet means absent; a bullet without a span or fence means null.
/// Anything else is not an argument, so the call is malformed.
pub fn parseArgs(arena: Allocator, mode: Mode, content: []const u8) ![]const u8 {
    _ = mode;
    var obj: std.json.ObjectMap = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (trimmed.len == 0) continue;
        if (!std.mem.startsWith(u8, trimmed, "*")) return error.InvalidCallArguments;
        const rest = std.mem.trim(u8, trimmed[1..], " \t");
        const cut = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        const key = rest[0..cut];
        if (key.len == 0) continue;
        const after = std.mem.trim(u8, rest[cut..], " \t");
        if (after.len > 0) {
            const found = try markdown.spans(arena, after);
            if (found.len != 1) return error.InvalidCallArguments;
            try obj.put(arena, key, try argumentJson(arena, found[0]));
            continue;
        }
        if (lines.peek()) |opening| {
            if (markdown.opensFence(opening)) {
                _ = lines.next();
                const f = try markdown.readFence(arena, opening, &lines);
                const value: std.json.Value = if (std.mem.eql(u8, f.runner, "text"))
                    .{ .string = f.code }
                else if (std.mem.eql(u8, f.runner, "json"))
                    try argumentJson(arena, f.code)
                else
                    return error.InvalidCallArguments;
                try obj.put(arena, key, value);
                continue;
            }
        }
        try obj.put(arena, key, .null);
    }
    var buf: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(std.json.Value{ .object = obj }, .{}, &buf.writer);
    return buf.written();
}

fn argumentJson(arena: Allocator, text: []const u8) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{}) catch return error.InvalidCallArguments;
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

test "null empty and literal quote strings have distinct spellings" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const args = "{\"empty\":\"\",\"quoted\":\"\\\"\\\"\",\"nothing\":null,\"path\":\"HAIKU.md\",\"undefined\":123}";
    const expected = "* empty `\"\"`\n* quoted\n  ```text\n  \"\"\n  ```\n* nothing\n* path `\"HAIKU.md\"`\n* undefined `123`";
    try testing.expectEqualStrings(expected, try renderArgs(arena, .md, args));
    try testing.expectEqualStrings(args, try parseArgs(arena, .md, expected));
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

test "string arguments are literal even when they spell JSON" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    for ([_][]const u8{ "null", "true", "false", "123", "1e3", "[]", "{\"x\":1}", "\"\"", " hello ", " 123 ", "   ", "`hello`", "a``b", "first\nsecond", "first\n" }) |text| {
        var json: std.Io.Writer.Allocating = .init(arena);
        try json.writer.writeAll("{\"value\":");
        try std.json.Stringify.value(text, .{}, &json.writer);
        try json.writer.writeByte('}');
        for ([_]Mode{ .md, .m8 }) |mode| {
            const rendered_args = try renderArgs(arena, mode, json.written());
            const parsed_args = try parseArgs(arena, mode, rendered_args);
            try testing.expectEqualStrings(json.written(), parsed_args);
        }
    }
}

test "complex arguments switch to pretty fences above 100 rendered characters" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    // * x `["..."]` has ten framing bytes: 90 payload bytes fits exactly.
    for ([_]usize{ 90, 91 }) |length| {
        const payload = try arena.alloc(u8, length);
        @memset(payload, 'a');
        const args = try std.fmt.allocPrint(arena, "{{\"x\":[\"{s}\"]}}", .{payload});
        const content = try renderArgs(arena, .md, args);
        try testing.expectEqual(length > 90, std.mem.indexOf(u8, content, "```json") != null);
        if (length == 90) try testing.expectEqual(@as(usize, 100), content.len);
        if (length == 91) try testing.expect(std.mem.indexOf(u8, content, "\n    \"") != null);
        try testing.expectEqualStrings(args, try parseArgs(arena, .md, content));
    }
    const args = "{\"o\":{\"b\":\"123\",\"a\":true},\"x\":[\"null\",\"true\"]}";
    try testing.expectEqualStrings(args, try parseArgs(arena, .md, try renderArgs(arena, .md, args)));
}

test "argument recovery rejects invalid JSON, unlabelled fences and stray lines" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    for ([_][]const u8{ "* n `hello`", "* s \"\"", "* a `[1,`", "* s\n  ```\n  hello\n  ```", "* s\n  ```json\n  hello\n  ```", "{\"s\":1}", "* s `1`\nnot an argument" }) |content|
        try testing.expectError(error.InvalidCallArguments, parseArgs(arena, .md, content));
    try testing.expectEqualStrings("", try renderArgs(arena, .md, "{}"));
    try testing.expectEqualStrings("* unknown `1`", try renderArgs(arena, .md, "{\"unknown\":1}"));
}

test "string spellings select JSON spans text fences and portable JSON fences" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const cases = [_]struct { text: []const u8, expected: []const u8 }{
        .{ .text = "", .expected = "* s `\"\"`" },
        .{ .text = "null", .expected = "* s `\"null\"`" },
        .{ .text = "hello", .expected = "* s `\"hello\"`" },
        .{ .text = " hello ", .expected = "* s `\" hello \"`" },
        .{ .text = "a`b", .expected = "* s ``\"a`b\"``" },
        .{ .text = "a\"b", .expected = "* s\n  ```text\n  a\"b\n  ```" },
        .{ .text = "C:\\path", .expected = "* s\n  ```text\n  C:\\path\n  ```" },
        .{ .text = "a\tb", .expected = "* s\n  ```text\n  a\tb\n  ```" },
        .{ .text = "a\nb\n", .expected = "* s\n  ```text\n  a\n  b\n  \n  ```" },
        .{ .text = "a\r\nb", .expected = "* s\n  ```json\n  \"a\\r\\nb\"\n  ```" },
        .{ .text = "a\x00b", .expected = "* s\n  ```json\n  \"a\\u0000b\"\n  ```" },
        .{ .text = "a\x7fb", .expected = "* s\n  ```json\n  \"a\\u007fb\"\n  ```" },
    };
    for (cases) |case| {
        var json: std.Io.Writer.Allocating = .init(arena);
        try json.writer.writeAll("{\"s\":");
        try std.json.Stringify.value(case.text, .{}, &json.writer);
        try json.writer.writeByte('}');
        const content = try renderArgs(arena, .md, json.written());
        try testing.expectEqualStrings(case.expected, content);
        try testing.expectEqualStrings(json.written(), try parseArgs(arena, .md, content));
    }
    // Text whose literal contents look like JSON is never inferred as JSON.
    try testing.expectEqualStrings("{\"s\":\"123\"}", try parseArgs(arena, .md, "* s\n  ```text\n  123\n  ```"));
    try testing.expectEqualStrings("{\"s\":\"\"}", try parseArgs(arena, .md, "* s\n  ```text\n  \n  ```"));
    try testing.expectEqualStrings("{\"s\":\"\xe2\x98\x83\"}", try parseArgs(arena, .md, "* s\n  ```json\n  \"\\u2603\"\n  ```"));
}

test "every ASCII control and Unicode string survives the document transport" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var strings: std.ArrayList([]const u8) = .empty;
    for (0..128) |c| {
        const text = try arena.dupe(u8, "a b");
        text[1] = @intCast(c);
        try strings.append(arena, text);
    }
    try strings.appendSlice(arena, &.{ "\xc2\x85", "\xe2\x80\xa8", "\xf0\x9f\x98\x84\r", "caf\xc3\xa9", "hello\n```text\n* fake `true`\n" });
    for (strings.items) |text| {
        var json: std.Io.Writer.Allocating = .init(arena);
        try json.writer.writeAll("{\"s\":");
        try std.json.Stringify.value(text, .{}, &json.writer);
        try json.writer.writeByte('}');
        for ([_]Mode{ .md, .m8 }) |mode| {
            const record: doc.Record = .{ .sigil = .call, .value = "example,c1", .content = try renderArgs(arena, mode, json.written()) };
            var document: std.Io.Writer.Allocating = .init(arena);
            try doc.write(&document.writer, mode, record);
            var diag: doc.Diagnostic = .{};
            const records = try doc.parse(arena, document.written(), &diag);
            const back = try parseArgs(arena, mode, records[0].content.?);
            try testing.expectEqualStrings(json.written(), back);
        }
    }
}
