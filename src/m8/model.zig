//! The model form of a 🧠.
//!
//! A 🧠 names an agent. One written with a leading `/` names a model instead,
//! and that mark is the whole of the distinction — nothing is looked up to
//! decide it. So a name that is simply missing is a missing agent, rather
//! than being mistaken for a model nobody has configured.
//!
//!     /local/Ternary-Bonsai-1.7B-mlx-2bit,max_tokens:8192
//!     /Ternary-Bonsai-1.7B-mlx-2bit,max_tokens:8192   no provider
//!     /local/tiny                                     no parameters
//!
//! Parameters are the api's own, passed through as written. m8 has no
//! vocabulary here and translates nothing: what is written is what goes on
//! the wire, which is also what lets it survive coming back off one.
//!
//! A model is not a name. Nothing declares its own name in m8 — a file is
//! what it is called — and a model has no file, so it has no name, keeps no
//! chat, and is written out in full wherever it is used. Writing a file that
//! names one is how it comes to have a name, like everything else.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The mark that says a 🧠 names a model.
pub const mark = '/';

pub const Param = struct {
    key: []const u8,
    /// As written. What it means is the api's business.
    value: []const u8,
};

pub const Model = struct {
    /// Empty when the form carried none, which is what coming back off a wire
    /// leaves behind: a request says which model, never whose.
    provider: []const u8 = "",
    name: []const u8 = "",
    params: []const Param = &.{},

    pub fn get(m: Model, key: []const u8) ?[]const u8 {
        for (m.params) |p| if (std.mem.eql(u8, p.key, key)) return p.value;
        return null;
    }
};

/// Whether this 🧠 value names a model.
pub fn is(value: []const u8) bool {
    return value.len > 0 and value[0] == mark;
}

/// Read the model form. Null when the value names an agent instead.
pub fn parse(arena: Allocator, value: []const u8) !?Model {
    if (!is(value)) return null;
    const parts = try fields(arena, value[1..]);

    var m: Model = .{};
    const address = std.mem.trim(u8, parts[0], " \t");
    if (std.mem.indexOfScalar(u8, address, '/')) |cut| {
        m.provider = address[0..cut];
        m.name = address[cut + 1 ..];
    } else {
        m.name = address;
    }

    var params: std.ArrayList(Param) = .empty;
    for (parts[1..]) |one| {
        const field = std.mem.trim(u8, one, " \t");
        if (field.len == 0) continue;
        const cut = std.mem.indexOfScalar(u8, field, ':') orelse continue;
        try params.append(arena, .{
            .key = std.mem.trim(u8, field[0..cut], " \t"),
            .value = std.mem.trim(u8, field[cut + 1 ..], " \t"),
        });
    }
    m.params = params.items;
    return m;
}

/// Write the model form back out.
pub fn render(arena: Allocator, m: Model) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    try buf.writer.writeByte(mark);
    if (m.provider.len > 0) try buf.writer.print("{s}/", .{m.provider});
    try buf.writer.writeAll(m.name);
    for (m.params) |p| try buf.writer.print(",{s}:{s}", .{ p.key, p.value });
    return buf.written();
}

/// Split on `,` at the top level only.
///
/// A parameter's value may be JSON, and JSON has commas of its own. Splitting
/// blind would cut `[1,2]` in half and there would be no way to write one.
fn fields(arena: Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    var start: usize = 0;

    for (text, 0..) |c, i| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (quoted) {
            switch (c) {
                '\\' => escaped = true,
                '"' => quoted = false,
                else => {},
            }
            continue;
        }
        switch (c) {
            '"' => quoted = true,
            '[', '{' => depth += 1,
            ']', '}' => depth -|= 1,
            ',' => if (depth == 0) {
                try out.append(arena, text[start..i]);
                start = i + 1;
            },
            else => {},
        }
    }
    try out.append(arena, text[start..]);
    return out.items;
}

/// A parameter's value as JSON: whatever it reads as, or the text itself.
///
/// So `8192` is a number and `auto` is the word. Quoting is how a value says
/// which it meant — `"8192"` is the text — and it is JSON's quoting, because
/// a second escape would be a second thing to know.
pub fn json(arena: Allocator, value: []const u8) std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, value, .{}) catch
        .{ .string = value };
}

/// The other way: what a parameter carrying this value is written as.
///
/// Bare when bare reads back as the same thing and holds no `,` to be cut at;
/// quoted otherwise. So whatever goes out comes back.
pub fn written(arena: Allocator, v: std.json.Value) ![]const u8 {
    if (v == .string and std.mem.indexOfScalar(u8, v.string, ',') == null) {
        const back = json(arena, v.string);
        if (back == .string and std.mem.eql(u8, back.string, v.string)) return v.string;
    }
    var buf: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(v, .{}, &buf.writer);
    return buf.written();
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the mark is the whole of the distinction" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expect((try parse(arena, "mathy")) == null);
    try testing.expect((try parse(arena, "team/reviewer")) == null);
    try testing.expect((try parse(arena, "=/tduyxbutjb")) == null);
    try testing.expect((try parse(arena, "/local/tiny")) != null);
}

test "a model reads as its provider, its name and the api's own parameters" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const m = (try parse(arena, "/local/Bonsai-8B,max_tokens:8192,temperature:0.7")).?;
    try testing.expectEqualStrings("local", m.provider);
    try testing.expectEqualStrings("Bonsai-8B", m.name);
    try testing.expectEqualStrings("8192", m.get("max_tokens").?);
    try testing.expectEqualStrings("0.7", m.get("temperature").?);
    try testing.expect(m.get("nosuch") == null);

    // Coming back off a wire leaves the provider behind; the rest survives.
    const bare = (try parse(arena, "/Bonsai-8B,max_tokens:8192")).?;
    try testing.expectEqualStrings("", bare.provider);
    try testing.expectEqualStrings("Bonsai-8B", bare.name);

    // The first slash splits, so a model whose name holds one keeps it.
    const nested = (try parse(arena, "/azure/openai/gpt-4")).?;
    try testing.expectEqualStrings("azure", nested.provider);
    try testing.expectEqualStrings("openai/gpt-4", nested.name);

    // No parameters at all is the ordinary case.
    const plain = (try parse(arena, "/local/tiny")).?;
    try testing.expectEqual(@as(usize, 0), plain.params.len);
}

test "a value may be JSON, commas and all" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const src = "/local/tiny,stop:[\"a\",\"b\"],logit_bias:{\"1\":-100},tag:\"with,comma\"";
    const m = (try parse(arena, src)).?;
    try testing.expectEqualStrings("tiny", m.name);
    try testing.expectEqualStrings("[\"a\",\"b\"]", m.get("stop").?);
    try testing.expectEqualStrings("{\"1\":-100}", m.get("logit_bias").?);
    // Quoting is what lets a value hold the separator.
    try testing.expectEqualStrings("with,comma", json(arena, m.get("tag").?).string);

    // And it all goes back out as it came in.
    try testing.expectEqualStrings(src, try render(arena, m));
}

test "a value is JSON when it reads as JSON, and text when it does not" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectEqual(@as(i64, 8192), json(arena, "8192").integer);
    try testing.expectEqual(true, json(arena, "true").bool);
    try testing.expectEqualStrings("auto", json(arena, "auto").string);
    // Quoting is how a value says it meant the text and not the number.
    try testing.expectEqualStrings("8192", json(arena, "\"8192\"").string);

    try testing.expectEqualStrings("8192", try written(arena, .{ .integer = 8192 }));
    try testing.expectEqualStrings("auto", try written(arena, .{ .string = "auto" }));
    // Anything that would read back as something else goes out quoted.
    try testing.expectEqualStrings("\"8192\"", try written(arena, .{ .string = "8192" }));
    try testing.expectEqualStrings("\"a,b\"", try written(arena, .{ .string = "a,b" }));
}
