//! The command line a munge operation takes, read the way one usually is.
//!
//!   --name VALUE    --name=VALUE    --flag    --    WORD
//!
//! A value is whatever follows its option, dash or not, so a replacement may
//! say anything. Everything after `--` is a word, so a path or a glob may
//! begin with a dash too.

const std = @import("std");
const api = @import("../api.zig");
const Ctx = api.Ctx;

pub const Kind = enum { text, number, flag };

pub const Option = struct {
    name: []const u8,
    kind: Kind = .text,
};

/// What a command line said: a value per option that was given, and the words
/// that were not options.
pub const Given = struct {
    options: []const Option,
    values: []const ?[]const u8,
    words: []const []const u8,

    pub fn text(self: Given, name: []const u8) ?[]const u8 {
        for (self.options, self.values) |o, v| if (std.mem.eql(u8, o.name, name)) return v;
        unreachable;
    }

    /// Checked when it was read, so one that is here is a number.
    pub fn number(self: Given, name: []const u8) ?usize {
        const raw = self.text(name) orelse return null;
        return std.fmt.parseInt(usize, raw, 10) catch unreachable;
    }

    pub fn flag(self: Given, name: []const u8) bool {
        return self.text(name) != null;
    }
};

/// Read `ctx.args` against `options`, taking at most `max_words` words.
///
/// Null when the line could not be read, which has already been said: a
/// mistake in how a command was typed is answered rather than guessed past.
pub fn parse(ctx: Ctx, op: []const u8, options: []const Option, max_words: usize) !?Given {
    const values = try ctx.arena.alloc(?[]const u8, options.len);
    @memset(values, null);
    var words: std.ArrayList([]const u8) = .empty;

    var i: usize = 0;
    var literal = false;
    while (i < ctx.args.len) : (i += 1) {
        const word = ctx.args[i];
        if (literal or !std.mem.startsWith(u8, word, "--")) {
            try words.append(ctx.arena, word);
            continue;
        }
        if (word.len == 2) {
            literal = true;
            continue;
        }

        const cut = std.mem.indexOfScalar(u8, word, '=');
        const name = word[2 .. cut orelse word.len];
        const at = for (options, 0..) |o, n| {
            if (std.mem.eql(u8, o.name, name)) break n;
        } else return wrong(ctx, op, "no option '--{s}'", .{name});

        if (options[at].kind == .flag) {
            if (cut != null) return wrong(ctx, op, "'--{s}' takes no value", .{name});
            values[at] = "";
            continue;
        }

        const value = if (cut) |c| word[c + 1 ..] else blk: {
            i += 1;
            if (i == ctx.args.len) return wrong(ctx, op, "'--{s}' needs a value", .{name});
            break :blk ctx.args[i];
        };
        if (options[at].kind == .number) {
            _ = std.fmt.parseInt(usize, value, 10) catch
                return wrong(ctx, op, "'--{s}' takes a number, not '{s}'", .{ name, value });
        }
        values[at] = value;
    }

    if (words.items.len > max_words)
        return wrong(ctx, op, "'{s}' is one word too many", .{words.items[max_words]});
    return .{ .options = options, .values = values, .words = words.items };
}

fn wrong(ctx: Ctx, op: []const u8, comptime fmt: []const u8, args: anytype) !?Given {
    try ctx.err.print("m8 munge {s}: ", .{op});
    try ctx.err.print(fmt ++ ". See m8 munge --help.\n", args);
    try ctx.err.flush();
    return null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const sample = [_]Option{
    .{ .name = "pages" },
    .{ .name = "byte-cap", .kind = .number },
    .{ .name = "dry-run", .kind = .flag },
};

fn read(arena: std.mem.Allocator, err: *std.Io.Writer, args: []const []const u8, max_words: usize) !?Given {
    var env: std.process.Environ.Map = .init(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    return parse(.{
        .arena = arena,
        .io = undefined,
        .mode = .md,
        .env = &env,
        .args = args,
        .in = "",
        .out = &out.writer,
        .err = err,
        .tty = null,
    }, "read", &sample, max_words);
}

test "options are read in either spelling, and words are what is left" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var err: std.Io.Writer.Allocating = .init(arena);

    const got = (try read(arena, &err.writer, &.{ "--pages", "2-3", "a.md", "--byte-cap=50", "--dry-run" }, 1)).?;
    try testing.expectEqualStrings("2-3", got.text("pages").?);
    try testing.expectEqual(@as(usize, 50), got.number("byte-cap").?);
    try testing.expect(got.flag("dry-run"));
    try testing.expectEqual(@as(usize, 1), got.words.len);
    try testing.expectEqualStrings("a.md", got.words[0]);

    const bare = (try read(arena, &err.writer, &.{}, 1)).?;
    try testing.expect(bare.text("pages") == null);
    try testing.expect(bare.number("byte-cap") == null);
    try testing.expect(!bare.flag("dry-run"));
}

test "a value may say anything, and -- ends the options" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var err: std.Io.Writer.Allocating = .init(arena);

    // What follows an option is its value, however much it looks like one.
    const dashed = (try read(arena, &err.writer, &.{ "--pages", "--byte-cap", "--", "--pages" }, 1)).?;
    try testing.expectEqualStrings("--byte-cap", dashed.text("pages").?);
    try testing.expectEqualStrings("--pages", dashed.words[0]);

    // Empty is a value that was given, not one that was left out.
    const empty = (try read(arena, &err.writer, &.{ "--pages", "" }, 1)).?;
    try testing.expectEqualStrings("", empty.text("pages").?);
}

test "a line that cannot be read is said rather than guessed past" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    var err: std.Io.Writer.Allocating = .init(arena);

    try testing.expect((try read(arena, &err.writer, &.{"--nosuch"}, 1)) == null);
    try testing.expect((try read(arena, &err.writer, &.{"--pages"}, 1)) == null);
    try testing.expect((try read(arena, &err.writer, &.{"--byte-cap=lots"}, 1)) == null);
    try testing.expect((try read(arena, &err.writer, &.{"--dry-run=yes"}, 1)) == null);
    try testing.expect((try read(arena, &err.writer, &.{ "a", "b" }, 1)) == null);
    try testing.expect(std.mem.indexOf(u8, err.written(), "m8 munge read: no option '--nosuch'") != null);
}
