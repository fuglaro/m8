//! Reading a 🧰 and turning a call into a command line.
//!
//! The harness hands back a 🧰's content as bytes and knows nothing about what
//! is in it. This is where that content becomes a tool: a 🔌 template, some
//! 📦 and 🎁 properties, and whatever bare lines are left as the description.
//!
//! One level down, the quote that doc.zig stripped is still there — a nested
//! content line arrives as `> text`. So the grammar here is: a sigil opens a
//! property, a quote continues the one above it, and anything else belongs to
//! the tool itself.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sigil = @import("m8/sigil.zig");
const doc = @import("m8/doc.zig");
const Mode = sigil.Mode;

pub const Error = error{
    /// A property line had no type.
    MissingType,
    /// A placeholder was opened and not closed.
    UnclosedPlaceholder,
    /// The 🔌 value was not a backtick-wrapped JSON array of strings.
    BadTemplate,
    /// A 📦 was not supplied and has no default.
    MissingProperty,
    /// A property tried to be called `lock`, which m8 fills in itself.
    ReservedProperty,
};

/// The one property name a tool may not declare. It is how a 🔒 reaches the
/// command line, so a model that could supply it would name its own locks.
pub const reserved = "lock";

pub const Property = struct {
    /// May be a dotted path: `parent.child`.
    name: []const u8,
    /// `string`, `object`, `Type[]`, or `A|B|C` for an enum.
    type: []const u8,
    description: []const u8 = "",
    required: bool,
};

pub const Tool = struct {
    name: []const u8,
    description: []const u8 = "",
    /// The 🔌 value with its backticks removed. Empty when there was none.
    command: []const u8 = "",
    locks: []const []const u8 = &.{},
    properties: []const Property = &.{},
};

/// Parse the content of a 🧰 whose value is `name`.
pub fn parse(arena: Allocator, mode: Mode, name: []const u8, content: []const u8) !Tool {
    const quote = doc.quote(mode);
    const bare = doc.bareQuote(mode);

    var props: std.ArrayList(Property) = .empty;
    var locks: std.ArrayList([]const u8) = .empty;
    var description: std.ArrayList(u8) = .empty;
    var command: []const u8 = "";

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // A quoted line belongs to the property above it.
        if (std.mem.startsWith(u8, line, quote) or std.mem.eql(u8, line, bare)) {
            if (props.items.len == 0) continue;
            const text = if (line.len > bare.len) line[quote.len..] else "";
            const last = &props.items[props.items.len - 1];
            last.description = try join(arena, last.description, text);
            continue;
        }

        if (sigil.match(mode, line)) |m| {
            const value = line[m.len..];
            switch (m.sigil) {
                .command => command = try unwrap(value),
                .lock => {
                    var it = std.mem.splitScalar(u8, value, ',');
                    while (it.next()) |one| {
                        const l = std.mem.trim(u8, one, " \t");
                        if (l.len > 0) try locks.append(arena, l);
                    }
                },
                .package, .optional => {
                    const cut = std.mem.indexOfScalar(u8, value, ',') orelse return Error.MissingType;
                    const pname = std.mem.trim(u8, value[0..cut], " \t");
                    if (std.mem.eql(u8, pname, reserved)) return Error.ReservedProperty;
                    try props.append(arena, .{
                        .name = pname,
                        .type = std.mem.trim(u8, value[cut + 1 ..], " \t"),
                        .required = m.sigil == .package,
                    });
                },
                else => {},
            }
            continue;
        }

        // Anything else is the tool's own description.
        if (line.len > 0 or description.items.len > 0)
            description.items = @constCast(try join(arena, description.items, line));
    }

    return .{
        .name = name,
        .description = std.mem.trim(u8, description.items, "\n"),
        .command = command,
        .locks = locks.items,
        .properties = props.items,
    };
}

fn join(arena: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    if (a.len == 0) return arena.dupe(u8, b);
    return std.fmt.allocPrint(arena, "{s}\n{s}", .{ a, b });
}

/// The 🔌 value is wrapped in backticks so it renders as code wherever the
/// document does. They are presentation, and required.
fn unwrap(value: []const u8) ![]const u8 {
    const v = std.mem.trim(u8, value, " \t");
    if (v.len < 2 or v[0] != '`' or v[v.len - 1] != '`') return Error.BadTemplate;
    return v[1 .. v.len - 1];
}

// ------------------------------------------------------------- the template

const open = "{{";
const close = "}}";

/// Expand a 🔌 template against the JSON of a call.
///
/// A placeholder is a whole element and expands to as many arguments as it
/// needs, which is why it can never be spliced into a larger string.
pub fn expand(
    arena: Allocator,
    template: []const u8,
    args: std.json.Value,
    raw_args: []const u8,
) ![]const []const u8 {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, template, .{}) catch
        return Error.BadTemplate;
    if (parsed != .array) return Error.BadTemplate;

    var out: std.ArrayList([]const u8) = .empty;
    for (parsed.array.items) |element| {
        if (element != .string) return Error.BadTemplate;
        const text = element.string;

        // `{{{...}}}` is a literal `{{...}}`.
        if (std.mem.startsWith(u8, text, "{{{") and std.mem.endsWith(u8, text, "}}}")) {
            try out.append(arena, text[1 .. text.len - 1]);
            continue;
        }
        if (!std.mem.startsWith(u8, text, open) or !std.mem.endsWith(u8, text, close)) {
            try out.append(arena, text);
            continue;
        }

        const inner = text[open.len .. text.len - close.len];
        // `{{}}` hands the whole call over as one argument, for a command
        // that would rather read JSON than flags.
        if (inner.len == 0) {
            try out.append(arena, raw_args);
            continue;
        }

        var key = inner;
        var flag: []const u8 = undefined;
        if (std.mem.indexOfScalar(u8, inner, ':')) |cut| {
            key = inner[0..cut];
            flag = inner[cut + 1 ..];
        } else {
            flag = try std.fmt.allocPrint(arena, "--{s}", .{key});
        }

        const value = if (args == .object) args.object.get(key) else null;
        // A missing key is simply absent. Whether that is allowed is the
        // property's business, not the template's.
        if (value) |v| try emit(arena, &out, flag, "", v);
    }
    return out.items;
}

/// Walk to the leaves, joining keys with a `.` and repeating the flag once per
/// array element. An array carries no index; that is what a POSIX command
/// wants, and the one place the shape is lost.
fn emit(
    arena: Allocator,
    out: *std.ArrayList([]const u8),
    flag: []const u8,
    suffix: []const u8,
    v: std.json.Value,
) !void {
    switch (v) {
        .object => |o| {
            var it = o.iterator();
            while (it.next()) |e| {
                try emit(arena, out, flag, try std.fmt.allocPrint(arena, "{s}.{s}", .{ suffix, e.key_ptr.* }), e.value_ptr.*);
            }
        },
        .array => |a| for (a.items) |item| try emit(arena, out, flag, suffix, item),
        // Absent rather than empty: a flag that is not passed is how a command
        // is told nothing, and `false` is how JSON says the same.
        .null => {},
        .bool => |b| if (b) try pushFlag(arena, out, flag, suffix),
        else => {
            try pushFlag(arena, out, flag, suffix);
            try out.append(arena, try scalar(arena, v));
        },
    }
}

/// With no flag there is nothing to hang a dotted path on, so bare values are
/// all that is left.
fn pushFlag(arena: Allocator, out: *std.ArrayList([]const u8), flag: []const u8, suffix: []const u8) !void {
    if (flag.len == 0) return;
    try out.append(arena, try std.fmt.allocPrint(arena, "{s}{s}", .{ flag, suffix }));
}

fn scalar(arena: Allocator, v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(arena, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(arena, "{d}", .{f}),
        .number_string => |s| s,
        else => "",
    };
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
    return writeObject(s, props, "");
}

/// Stated explicitly because `writeObject` and `writeType` are mutually
/// recursive, and an inferred set cannot close over itself.
pub const SchemaError = std.Io.Writer.Error;

fn writeObject(s: *std.json.Stringify, props: []const Property, prefix: []const u8) SchemaError!void {
    try s.beginObject();
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

    if (array) {
        try s.beginObject();
        try s.objectField("type");
        try s.write("array");
        try s.objectField("items");
    }

    if (std.mem.eql(u8, base, "object")) {
        // An object's own children carry the descriptions.
        try writeObject(s, props, p.name);
    } else {
        try s.beginObject();
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

/// Stated explicitly because `readObject` and `readType` are mutually
/// recursive, and an inferred set cannot close over itself.
pub const ReadError = Allocator.Error;

/// Read a schema back into properties: the inverse of `writeParameters`.
///
/// Nested objects flatten back to dotted paths, an array's items give the
/// `[]` suffix, and an enum's values rejoin with `|`. A 🔌 is not here to be
/// recovered — it never went out.
pub fn readParameters(
    arena: Allocator,
    props: *std.ArrayList(Property),
    schema: std.json.Value,
) ReadError!void {
    return readObject(arena, props, schema, "");
}

fn readObject(
    arena: Allocator,
    props: *std.ArrayList(Property),
    schema: std.json.Value,
    prefix: []const u8,
) ReadError!void {
    if (schema != .object) return;
    const properties = schema.object.get("properties") orelse return;
    if (properties != .object) return;

    var required: []const std.json.Value = &.{};
    if (schema.object.get("required")) |req| {
        if (req == .array) required = req.array.items;
    }

    var it = properties.object.iterator();
    while (it.next()) |e| {
        const key = e.key_ptr.*;
        const full = if (prefix.len == 0)
            key
        else
            try std.fmt.allocPrint(arena, "{s}.{s}", .{ prefix, key });
        const is_required = for (required) |rv| {
            if (rv == .string and std.mem.eql(u8, rv.string, key)) break true;
        } else false;
        try readType(arena, props, e.value_ptr.*, full, is_required, false);
    }
}

fn readType(
    arena: Allocator,
    props: *std.ArrayList(Property),
    v: std.json.Value,
    name: []const u8,
    required: bool,
    in_array: bool,
) ReadError!void {
    if (v != .object) return;
    const t = str(v.object.get("type")) orelse "string";

    // Arrayness lives on the parent type, so the items decide what it is an
    // array of and the `[]` is put back here.
    if (std.mem.eql(u8, t, "array")) {
        const items = v.object.get("items") orelse return;
        return readType(arena, props, items, name, required, true);
    }
    const suffix = if (in_array) "[]" else "";

    if (std.mem.eql(u8, t, "object")) {
        try props.append(arena, .{
            .name = name,
            .type = try std.fmt.allocPrint(arena, "object{s}", .{suffix}),
            .required = required,
        });
        // Parents are always declared, never inferred, so the children follow.
        return readObject(arena, props, v, name);
    }

    var base: []const u8 = t;
    if (v.object.get("enum")) |en| if (en == .array) {
        var joined: std.ArrayList(u8) = .empty;
        for (en.array.items, 0..) |item, i| {
            if (i > 0) try joined.append(arena, '|');
            if (item == .string) try joined.appendSlice(arena, item.string);
        }
        if (joined.items.len > 0) base = joined.items;
    };

    try props.append(arena, .{
        .name = name,
        .type = try std.fmt.allocPrint(arena, "{s}{s}", .{ base, suffix }),
        .description = str(v.object.get("description")) orelse "",
        .required = required,
    });
}


fn str(v: ?std.json.Value) ?[]const u8 {
    const got = v orelse return null;
    return if (got == .string) got.string else null;
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

    if (t.command.len > 0)
        try w.print("{s}`{s}`\n", .{ sigil.Sigil.command.text(mode), t.command });
    if (t.locks.len > 0)
        try w.print("{s}{s}\n", .{
            sigil.Sigil.lock.text(mode),
            try std.mem.join(arena, ", ", t.locks),
        });
    for (t.properties) |p| {
        const s: sigil.Sigil = if (p.required) .package else .optional;
        try w.print("{s}{s},{s}\n", .{ s.text(mode), p.name, p.type });
        try writeNested(w, mode, p.description);
    }
    // Bare lines, so they must come last: anything after them would be read
    // as more description rather than as a property.
    if (t.description.len > 0) {
        try w.writeAll(t.description);
        try w.writeByte('\n');
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

/// A call's arguments as 📦 records, one per key, so a saved turn reads as the
/// language rather than as a blob of JSON.
pub fn renderArgs(arena: Allocator, mode: Mode, args: []const u8) ![]const u8 {
    const v = std.json.parseFromSliceLeaky(std.json.Value, arena, args, .{}) catch
        return arena.dupe(u8, args);
    if (v != .object) return arena.dupe(u8, args);

    var buf: std.Io.Writer.Allocating = .init(arena);
    var it = v.object.iterator();
    var first = true;
    while (it.next()) |e| {
        if (!first) try buf.writer.writeByte('\n');
        first = false;
        try buf.writer.print("{s}{s}\n", .{ sigil.Sigil.package.text(mode), e.key_ptr.* });
        var text: std.Io.Writer.Allocating = .init(arena);
        try std.json.Stringify.value(e.value_ptr.*, .{}, &text.writer);
        // A string goes in as itself: the point of the block is that a human
        // reads the value, not an escaped copy of it.
        const raw = if (e.value_ptr.* == .string) e.value_ptr.*.string else text.written();
        try writeNested(&buf.writer, mode, raw);
    }
    return std.mem.trimEnd(u8, buf.written(), "\n");
}

/// Read 📦 records back into the JSON a provider wants.
///
/// A value that parses as JSON and is not a string is taken as that; anything
/// else is the text itself. The one ambiguity is a string that happens to
/// spell a number — `123` returns as an integer — and the alternative is
/// escaping every value, which would cost the block the readability it exists
/// for.
pub fn parseArgs(arena: Allocator, mode: Mode, content: []const u8) ![]const u8 {
    const quote = doc.quote(mode);
    const bare = doc.bareQuote(mode);

    var obj: std.json.ObjectMap = .empty;
    var key: ?[]const u8 = null;
    var val: std.ArrayList(u8) = .empty;
    var seen: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, quote) or std.mem.eql(u8, line, bare)) {
            if (key == null) continue;
            if (seen > 0) try val.append(arena, '\n');
            if (line.len > bare.len) try val.appendSlice(arena, line[quote.len..]);
            seen += 1;
            continue;
        }
        const m = sigil.match(mode, line) orelse continue;
        if (m.sigil != .package) continue;
        if (key) |k| try obj.put(arena, k, valueOf(arena, val.items));
        key = line[m.len..];
        val = .empty;
        seen = 0;
    }
    if (key) |k| try obj.put(arena, k, valueOf(arena, val.items));

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

fn expandTest(arena: Allocator, template: []const u8, json: []const u8) ![]const []const u8 {
    const args = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    return expand(arena, template, args, json);
}

fn expectArgv(got: []const []const u8, want: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "a placeholder takes the flag from its key, or from what it is given" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"with\": [\"check\", \"sandbox\"], \"cmd_str\": \"echo hi\"}";

    try expectArgv(try expandTest(arena, "[\"{{cmd_str}}\"]", json), &.{ "--cmd_str", "echo hi" });
    try expectArgv(try expandTest(arena, "[\"{{cmd_str:-c}}\"]", json), &.{ "-c", "echo hi" });
    try expectArgv(try expandTest(arena, "[\"{{with:-w}}\"]", json), &.{ "-w", "check", "-w", "sandbox" });
    try expectArgv(try expandTest(arena, "[\"{{with:}}\"]", json), &.{ "check", "sandbox" });
}

test "the worked example from the README" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const got = try expandTest(
        a.allocator(),
        "[\"m8\", \"call\", \"{{with:-w}}\", \"--\", \"bash\", \"{{cmd_str:-c}}\"]",
        "{\"with\": [\"check\", \"sandbox\"], \"cmd_str\": \"echo hi\"}",
    );
    try expectArgv(got, &.{ "m8", "call", "-w", "check", "-w", "sandbox", "--", "bash", "-c", "echo hi" });
}

test "objects expand their leaves, and naming nothing leaves the values" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"opts\": {\"a\": 1, \"b\": {\"c\": 2}}}";
    try expectArgv(try expandTest(arena, "[\"{{opts:-o}}\"]", json), &.{ "-o.a", "1", "-o.b.c", "2" });
    try expectArgv(try expandTest(arena, "[\"{{opts:}}\"]", json), &.{ "1", "2" });
}

test "an array of objects repeats the prefix and carries no index" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const got = try expandTest(a.allocator(), "[\"{{opts:-o}}\"]", "{\"opts\": [{\"a\": 1}, {\"a\": 2}]}");
    try expectArgv(got, &.{ "-o.a", "1", "-o.a", "2" });
}

test "null and false omit the key, true emits the flag alone" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"n\": null, \"f\": false, \"t\": true}";
    try expectArgv(try expandTest(arena, "[\"{{n}}\"]", json), &.{});
    try expectArgv(try expandTest(arena, "[\"{{f}}\"]", json), &.{});
    try expectArgv(try expandTest(arena, "[\"{{t}}\"]", json), &.{"--t"});
}

test "a missing key is simply absent" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    try expectArgv(try expandTest(a.allocator(), "[\"x\", \"{{nope}}\", \"y\"]", "{}"), &.{ "x", "y" });
}

test "{{}} hands the whole call over, and {{{...}}} is a literal" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const json = "{\"a\":1}";
    try expectArgv(try expandTest(arena, "[\"{{}}\"]", json), &.{json});
    try expectArgv(try expandTest(arena, "[\"{{{cmd_str}}}\"]", json), &.{"{{cmd_str}}"});
}

test "a toolbox reads its template, properties and description" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const t = try parse(a.allocator(), .md, "shell",
        \\:electric_plug:`["bash", "{{cmd:-c}}"]`
        \\:lock:jail, no-edit-git
        \\:package:cmd,string
        \\> The command to run
        \\:gift:dir,string
        \\> Where to run it
        \\Run a command.
        \\Carefully.
    );
    try testing.expectEqualStrings("shell", t.name);
    try testing.expectEqualStrings("[\"bash\", \"{{cmd:-c}}\"]", t.command);
    try testing.expectEqualStrings("Run a command.\nCarefully.", t.description);
    try expectArgv(t.locks, &.{ "jail", "no-edit-git" });

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
    const md = try parse(arena, .md, "x", ":package:cmd,string\n> Desc\nRuns.");
    const m8 = try parse(arena, .m8, "x", "\u{1F4E6}cmd,string\n\u{2502} Desc\nRuns.");
    try testing.expectEqualStrings(md.description, m8.description);
    try testing.expectEqualStrings(md.properties[0].description, m8.properties[0].description);
}

test "a template must be a backticked JSON array" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    try testing.expectError(Error.BadTemplate, parse(a.allocator(), .md, "x", ":electric_plug:[\"no\", \"backticks\"]"));
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
        \\:package:cmd,string
        \\> The command
        \\:gift:quiet,boolean
        \\Runs a command.
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
        \\:package:unit,celsius|fahrenheit
        \\:package:tags,string[]
        \\:package:opts,object
        \\:package:opts.depth,integer
        \\:gift:opts.name,string
    );
    const got = try schemaOf(arena, t);
    try testing.expect(std.mem.indexOf(u8, got, "\"enum\":[\"celsius\",\"fahrenheit\"]") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"opts\":{\"type\":\"object\"") != null);
    try testing.expect(std.mem.indexOf(u8, got, "\"depth\":{\"type\":\"integer\"}") != null);
    // The nested required list holds the child, and the outer one does not.
    try testing.expect(std.mem.indexOf(u8, got, "\"required\":[\"depth\"]") != null);
}

test "a tool may not declare a property called lock" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    try testing.expectError(
        Error.ReservedProperty,
        parse(a.allocator(), .md, "x", ":package:lock,string"),
    );
    // Only that exact name; anything else is the tool's own business.
    _ = try parse(a.allocator(), .md, "x", ":package:locking,string");
}

test "a tool survives being rendered and read back, in either spelling" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const src =
        \\:electric_plug:`["m8", "call", "{{with:-w}}", "--", "bash", "{{cmd:-c}}"]`
        \\:lock:jail, airgap
        \\:package:cmd,string
        \\> What to run.
        \\> Two lines of it.
        \\:gift:with,check|sandbox
        \\> Extras.
        \\:package:opts,object
        \\:package:opts.depth,integer
        \\Runs a command.
    ;
    const first = try parse(arena, .md, "shell", src);

    for ([_]Mode{ .md, .m8 }) |mode| {
        const again = try parse(arena, mode, "shell", try render(arena, mode, first));
        try testing.expectEqualStrings(first.name, again.name);
        try testing.expectEqualStrings(first.description, again.description);
        try testing.expectEqualStrings(first.command, again.command);
        try testing.expectEqual(first.locks.len, again.locks.len);
        for (first.locks, again.locks) |x, y| try testing.expectEqualStrings(x, y);
        try testing.expectEqual(first.properties.len, again.properties.len);
        for (first.properties, again.properties) |x, y| {
            try testing.expectEqualStrings(x.name, y.name);
            try testing.expectEqualStrings(x.type, y.type);
            try testing.expectEqualStrings(x.description, y.description);
            try testing.expectEqual(x.required, y.required);
        }
    }
}

test "call arguments survive a trip through 📦 records" {
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
