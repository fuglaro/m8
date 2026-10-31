//! `cat` converts m8 records to block, packed or unwrapped Markdown.
//! It retains only the current record, so arbitrarily long input streams do not
//! grow the command's arena for the lifetime of the process.
const std = @import("std");
const api = @import("../api.zig");
const doc = @import("../m8/doc.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "cat",
    .summary = "write m8 as block, packed or unwrapped Markdown",
    .takes = .nothing,
    .run = run,
    .help = help,
};

fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 cat [--pack | --unwrap]
        \\
        \\Reads m8 on stdin and writes block markdown by default.
        \\--pack puts each record on one line, using - for its bullet and ↵
        \\for internal newlines. Literal ↵ is doubled in packed records.
        \\
        \\--unwrap removes record framing: a nonempty value becomes # VALUE,
        \\followed by a blank line and literal content when present. Records
        \\are separated by at least one blank line; input blank separators
        \\are preserved. result/failed content retains its four-space indent.
        \\
        \\Packed and block records may be mixed. Separator newlines and the
        \\presence of the final newline are preserved in default and --pack
        \\output. Nothing is resolved. --pack and --unwrap are exclusive.
        \\
        \\  ... | m8 cat --pack | grep '^- :call::' | m8 cat
        \\
    );
}

fn modesExclusive(args: []const []const u8) bool {
    var pack = false;
    var unwrap = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--pack")) pack = true;
        if (std.mem.eql(u8, arg, "--unwrap")) unwrap = true;
    }
    return !(pack and unwrap);
}

fn run(ctx: Ctx) !u8 {
    if (!modesExclusive(ctx.args)) return usage(ctx);
    var pack = false;
    var unwrap = false;
    for (ctx.args) |arg| {
        if (std.mem.eql(u8, arg, "--pack")) {
            pack = true;
        } else if (std.mem.eql(u8, arg, "--unwrap")) {
            unwrap = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try help(ctx, ctx.out);
            return 0;
        } else return usage(ctx);
    }
    try stream(ctx, pack, unwrap);
    return 0;
}

fn stream(ctx: Ctx, packed_out: bool, unwrap: bool) !void {
    // A nested arena on ctx.arena may not reclaim memory if the outer allocator
    // is itself an arena. Use a backing allocator with real free_all semantics.
    var buf: [16 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(ctx.io, &buf);
    try streamReader(std.heap.page_allocator, &input.interface, packed_out, unwrap, ctx.out);
}

fn streamReader(allocator: std.mem.Allocator, r: *std.Io.Reader, packed_out: bool, unwrap: bool, out: *std.Io.Writer) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var record: std.ArrayList(u8) = .empty;
    var line: std.ArrayList(u8) = .empty;
    var unwrapped: doc.Unwrap = .{};
    defer line.deinit(allocator);
    while (true) {
        if (r.buffered().len == 0) {
            r.fillMore() catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
        }
        const chunk = r.buffered();
        var start: usize = 0;
        while (start < chunk.len) {
            const end = if (std.mem.indexOfScalarPos(u8, chunk, start, '\n')) |at| at + 1 else chunk.len;
            try line.appendSlice(allocator, chunk[start..end]);
            start = end;
            if (line.items.len > 0 and line.items[line.items.len - 1] == '\n') {
                try processLine(&arena, &record, line.items, packed_out, unwrap, &unwrapped, out);
                line.clearRetainingCapacity();
            }
        }
        r.tossBuffered();
    }
    if (line.items.len > 0) try processLine(&arena, &record, line.items, packed_out, unwrap, &unwrapped, out);
    if (record.items.len > 0) {
        try writeRecord(arena.allocator(), record.items, packed_out, unwrap, &unwrapped, out);
        try out.flush();
    }
}

fn processLine(arena: *std.heap.ArenaAllocator, record: *std.ArrayList(u8), raw: []const u8, packed_out: bool, unwrap: bool, state: *doc.Unwrap, out: *std.Io.Writer) !void {
    const line_end = if (raw.len > 0 and raw[raw.len - 1] == '\n') raw.len - 1 else raw.len;
    const content_end = if (line_end > 0 and raw[line_end - 1] == '\r') line_end - 1 else line_end;
    const line = raw[0..content_end];
    const headed = doc.headed(.md, line) != null or doc.headed(.m8, line) != null;
    if (record.items.len > 0 and (line.len == 0 or headed)) {
        try writeRecord(arena.allocator(), record.items, packed_out, unwrap, state, out);
        try out.flush();
        _ = arena.reset(.free_all);
        record.* = .empty;
    }
    if (line.len == 0) {
        if (unwrap) try state.separator(raw, out) else try out.writeAll(raw);
    } else {
        if (record.items.len == 0 and !headed) return error.InvalidDocument;
        if (std.mem.startsWith(u8, line, "- ")) {
            try writeRecord(arena.allocator(), raw, packed_out, unwrap, state, out);
            try out.flush();
            _ = arena.reset(.free_all);
        } else try record.appendSlice(arena.allocator(), raw);
    }
}

fn writeRecord(arena: std.mem.Allocator, raw: []const u8, packed_out: bool, unwrap: bool, state: *doc.Unwrap, out: *std.Io.Writer) !void {
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(arena, raw, &diag);
    if (records.len != 1) return error.InvalidDocument;
    if (unwrap) {
        const terminated = raw.len > 0 and raw[raw.len - 1] == '\n';
        try state.write(records[0], terminated, out);
        return;
    }
    var normalized: std.Io.Writer.Allocating = .init(arena);
    if (packed_out) try doc.writePacked(&normalized.writer, records[0]) else try doc.write(&normalized.writer, .md, records[0]);
    const bytes = normalized.written();
    const terminated = raw.len > 0 and raw[raw.len - 1] == '\n';
    try out.writeAll(if (terminated) bytes else bytes[0 .. bytes.len - 1]);
}

fn usage(ctx: Ctx) !u8 {
    try ctx.err.writeAll("m8 cat: invalid options; see m8 cat --help\n");
    try help(ctx, ctx.err);
    return 1;
}

const testing = std.testing;

fn convert(input: []const u8, is_packed: bool) ![]const u8 {
    var reader: std.Io.Reader = .fixed(input);
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try streamReader(testing.allocator, &reader, is_packed, false, &output.writer);
    return try testing.allocator.dupe(u8, output.written());
}

fn convertUnwrap(input: []const u8) ![]const u8 {
    var reader: std.Io.Reader = .fixed(input);
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try streamReader(testing.allocator, &reader, false, true, &output.writer);
    return try testing.allocator.dupe(u8, output.written());
}

test "cat pack and unwrap flags conflict in either order" {
    try testing.expect(!modesExclusive(&.{ "--pack", "--unwrap" }));
    try testing.expect(!modesExclusive(&.{ "--unwrap", "--pack" }));
    try testing.expect(modesExclusive(&.{"--pack"}));
    try testing.expect(modesExclusive(&.{"--unwrap"}));
}

test "cat help documents unwrap formatting and exclusive modes" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try help(undefined, &output.writer);
    try testing.expect(std.mem.indexOf(u8, output.written(), "--pack and --unwrap are exclusive") != null);
    try testing.expect(std.mem.indexOf(u8, output.written(), "four-space indent") != null);
}

test "cat unwraps values, bodies, both and neither literally" {
    const got = try convertUnwrap(
        "* :robot::heading\n" ++
            "* :robot::\n  > body only\n" ++
            "* :robot::value\n  > body too\n" ++
            "* :robot::\n",
    );
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("# heading\n\nbody only\n\n# value\n\nbody too\n", got);
}

test "cat unwrap leaves question headers and receipt code literal" {
    const got = try convertUnwrap(
        "* :question::tool,call\n" ++
            "* :receipt::c1\n  >     first\n  >\n  >       second\n",
    );
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("# tool,call\n\n# c1\n\n    first\n\n      second\n", got);
}

test "cat unwraps mixed packed and block records and separates adjacent records" {
    const got = try convertUnwrap("- :robot::one↵  > body\n* :robot::two\n  > next\n");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("# one\n\nbody\n\n# two\n\nnext\n", got);
}

test "cat unwrap separates adjacent records and preserves existing blank separators" {
    const adjacent = try convertUnwrap("* :brain::one\n* :brain::two");
    defer testing.allocator.free(adjacent);
    try testing.expectEqualStrings("# one\n\n# two\n", adjacent);
    const separated = try convertUnwrap("* :brain::one\n\n\n* :brain::two\n");
    defer testing.allocator.free(separated);
    try testing.expectEqualStrings("# one\n\n\n# two\n", separated);
}

test "cat streams large packed and body lines through production reader" {
    const alloc = testing.allocator;
    const packed_line = try alloc.alloc(u8, 40 * 1024 + 20);
    defer alloc.free(packed_line);
    const prefix = "- :brain::hi ";
    @memcpy(packed_line[0..prefix.len], prefix);
    @memset(packed_line[prefix.len .. packed_line.len - 1], 'x');
    packed_line[packed_line.len - 1] = '\n';
    const block = try convert(packed_line, false);
    defer alloc.free(block);
    try testing.expect(std.mem.indexOf(u8, block, "x\n") != null);

    const body = try alloc.alloc(u8, 40 * 1024 + 20);
    defer alloc.free(body);
    const body_prefix = "* :robot::\n  > ";
    @memcpy(body[0..body_prefix.len], body_prefix);
    @memset(body[body_prefix.len .. body.len - 1], 'y');
    body[body.len - 1] = '\n';
    const repacked = try convert(body, true);
    defer alloc.free(repacked);
    try testing.expect(repacked.len > 32 * 1024);
}

test "cat preserves blanks, adjacent headers, EOF newline and arrow roundtrip" {
    const input = "\n\n- :brain::one\n\n\n* :brain::two";
    const block = try convert(input, false);
    defer testing.allocator.free(block);
    try testing.expectEqualStrings("\n\n* :brain::one\n\n\n* :brain::two", block);
    const packed_line = try convert(block, true);
    defer testing.allocator.free(packed_line);
    try testing.expectEqualStrings("\n\n- :brain::one\n\n\n- :brain::two", packed_line);

    const arrows = try convert("- :brain::a ↵↵↵↵ b\n", false);
    defer testing.allocator.free(arrows);
    const arrow_packed = try convert(arrows, true);
    defer testing.allocator.free(arrow_packed);
    try testing.expectEqualStrings("- :brain::a ↵↵↵↵ b\n", arrow_packed);
}

test "cat unwrap decodes arrows and retains empty and trailing content lines" {
    const cases = [_][2][]const u8{
        .{ "- :question::tool,call_123↵  > Which ↵↵ path?\n", "# tool,call_123\n\nWhich ↵ path?\n" },
        .{ "- :robot::title↵↵↵  > body↵↵\n", "# title↵\n\nbody↵\n" },
        .{ "* :robot::\n  >\n", "\n" },
        .{ "* :robot::\n  > text\n  >\n", "text\n\n" },
        .{ "* :robot::\n  > text", "text" },
        .{ "* :robot::\n", "" },
    };
    for (cases) |case| {
        const got = try convertUnwrap(case[0]);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(case[1], got);
    }
}
