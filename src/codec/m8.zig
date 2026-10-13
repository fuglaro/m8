//! The m8 api: the language itself.
//!
//! The one codec whose view is the whole ledger, which is why encoding loses
//! nothing. A provider declaring this api
//! is handed everything — 🧰 with its 🔌 and its 🔒 included — rather than a
//! projection, and is trusted with it because a provider command lives in
//! `core/`.
//!
//! A response is a document too: the new turn, as records. It is read a line
//! at a time, so 🤖 content reaches the reader as it arrives.

const std = @import("std");
const Allocator = std.mem.Allocator;
const api = @import("../codec.zig");
const doc = @import("../m8/doc.zig");
const ledger = @import("../ledger.zig");
const sigil = @import("../m8/sigil.zig");
const toolbox = @import("../toolbox.zig");

pub const codec: api.Codec = .{
    .name = "m8",
    .summary = "the language itself; encoding is writing it out",
    .encode = encode,
    .parse = parse,
};

fn encode(arena: Allocator, records: []const doc.Record, target: api.Target) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    try ledger.writeAll(&buf.writer, arena, target.mode, records);
    return buf.written();
}

/// Read a reply as it is written.
///
/// Each record is said as it lands, a content line while it is still being
/// written: what comes down a pipe from something reading a model is a line
/// that takes as long as the model does. The whole document is kept as
/// well, so the calls can be read from it at the end: two passes over the
/// same bytes, which is the price of a call being whole only once it ends.
fn parse(arena: Allocator, r: *std.Io.Reader, sink: api.Sink) !api.Reply {
    var all: std.ArrayList(u8) = .empty;
    var lines: Lines = .{ .arena = arena, .sink = sink };

    while (true) {
        const held = r.buffered();
        if (held.len == 0) {
            r.fillMore() catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
            continue;
        }
        try all.appendSlice(arena, held);
        var rest: []const u8 = held;
        while (std.mem.indexOfScalar(u8, rest, '\n')) |end| {
            try lines.feed(rest[0..end], true);
            rest = rest[end + 1 ..];
        }
        try lines.feed(rest, false);
        r.toss(held.len);
    }
    // A last line with no newline on it is still a line.
    try lines.feed("", true);
    if (lines.open) try sink.end();

    var calls: std.ArrayList(api.Call) = .empty;
    var diag: doc.Diagnostic = .{};
    const m = doc.detect(all.items) orelse .md;
    for (try doc.parse(arena, all.items, &diag)) |rec| {
        if (rec.sigil == .call) try calls.append(arena, .{
            .id = ledger.callId(rec.value),
            .name = ledger.callName(rec.value),
            .arguments = try toolbox.parseArgs(arena, m, rec.content orelse ""),
        });
    }
    return .{ .calls = calls.items };
}

/// The reply a line at a time, however the bytes were cut on the way in.
const Lines = struct {
    arena: Allocator,
    sink: api.Sink,
    mode: ?doc.Mode = null,
    /// A record is being said, and how many of its lines have been.
    open: bool = false,
    said: usize = 0,
    /// The line so far, while what kind of line it is is not known yet.
    head: std.ArrayList(u8) = .empty,
    /// It is a content line, and what arrives of it is said as it does.
    saying: bool = false,
    /// A return held back, in case the new line it belongs to is next.
    cr: bool = false,

    /// More of the current line, and whether that is the end of it.
    fn feed(self: *Lines, bytes: []const u8, ended: bool) !void {
        if (self.saying) {
            try self.say(bytes, ended);
            if (ended) self.saying = false;
            return;
        }
        try self.head.appendSlice(self.arena, bytes);
        if (ended) {
            defer self.head.clearRetainingCapacity();
            return self.whole(std.mem.trimEnd(u8, self.head.items, "\r"));
        }
        // A content line under a record on show need not wait for its end.
        const m = self.mode orelse return;
        const quote = doc.quote(m);
        if (!self.open or !std.mem.startsWith(u8, self.head.items, quote)) return;
        if (self.said > 0) try self.sink.text("\n");
        self.said += 1;
        self.saying = true;
        try self.say(self.head.items[quote.len..], false);
        self.head.clearRetainingCapacity();
    }

    fn say(self: *Lines, bytes: []const u8, ended: bool) !void {
        if (self.cr and !(ended and bytes.len == 0)) try self.sink.text("\r");
        self.cr = !ended and bytes.len > 0 and bytes[bytes.len - 1] == '\r';
        try self.sink.text(std.mem.trimEnd(u8, bytes, if (ended or self.cr) "\r" else ""));
    }

    /// A line that arrived in one piece, or was never one to say early.
    fn whole(self: *Lines, line: []const u8) !void {
        const m = self.mode orelse blk: {
            for ([_]doc.Mode{ .m8, .md }) |candidate| {
                if (std.mem.startsWith(u8, line, doc.header(candidate))) {
                    self.mode = candidate;
                    break :blk candidate;
                }
            }
            return;
        };

        if (std.mem.startsWith(u8, line, doc.header(m))) {
            if (self.open) try self.sink.end();
            self.open = false;
            const rest = line[doc.header(m).len..];
            if (sigil.match(m, rest)) |hit| if (shows(hit.sigil)) {
                // The line is let go of, and what opens a record is kept.
                try self.sink.begin(hit.sigil, try self.arena.dupe(u8, std.mem.trim(u8, rest[hit.len..], " \t")));
                self.open = true;
            };
            self.said = 0;
            return;
        }
        if (line.len == 0) {
            if (self.open) try self.sink.end();
            self.open = false;
            return;
        }
        if (!self.open) return;

        const quote = doc.quote(m);
        const bare = doc.bareQuote(m);
        if (!std.mem.startsWith(u8, line, quote) and !std.mem.eql(u8, line, bare)) return;

        // Lines are joined by \n, so the break belongs before the next one
        // rather than after the last.
        if (self.said > 0) try self.sink.text("\n");
        if (line.len > bare.len) try self.sink.text(line[quote.len..]);
        self.said += 1;
    }
};

/// Whether a record is said as it arrives.
///
/// Everything is but a 📲, whose arguments mean nothing until the last brace.
/// An unexpected sigil is let through so that `policy.zig` refuses it, where
/// dropping it here would lose it quietly.
fn shows(s: sigil.Sigil) bool {
    return s != .call;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// A sink that writes what it is given as `sigil:content`, one record a line,
/// so a test can assert the order as well as the bytes.
const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,
    /// The same stream, as the records it makes.
    got: api.Gather = .{ .arena = undefined },

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, value: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        self.got.arena = self.arena;
        self.got.open(s, value);
        if (self.seen.items.len > 0) try self.seen.append(self.arena, '\n');
        try self.seen.appendSlice(self.arena, @tagName(s));
        try self.seen.append(self.arena, ':');
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
        try self.got.write(bytes);
    }
    fn closeFn(ctx: *anyopaque) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        _ = try self.got.close();
    }
};

test "a content line is said while it is still being written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var collect: Collect = .{ .arena = arena };
    var lines: Lines = .{ .arena = arena, .sink = collect.sink() };
    try lines.feed("#### :rob", false);
    try lines.feed("ot:", true);
    try lines.feed("> on", false);
    try testing.expectEqualStrings("bot:on", collect.seen.items);
    try lines.feed("e\r", false);
    try lines.feed("", true);
    try lines.feed(">", false);
    try lines.feed(" two", true);
    try testing.expectEqualStrings("bot:one\ntwo", collect.seen.items);
}

test "a blockless thought keeps its value, including snip" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var r: std.Io.Reader = .fixed("#### :thought_balloon:snip\n");
    var collect: Collect = .{ .arena = arena };
    _ = try parse(arena, &r, collect.sink());

    try testing.expectEqual(@as(usize, 1), collect.got.records.items.len);
    try testing.expectEqual(sigil.Sigil.thought, collect.got.records.items[0].sigil);
    try testing.expectEqualStrings("snip", collect.got.records.items[0].value);
    try testing.expect(collect.got.records.items[0].content == null);
}

test "a reply in the language streams as it is written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\#### :thought_balloon:
        \\> thinking
        \\
        \\#### :robot:
        \\> one
        \\> two
        \\
        \\#### :calling:say,c1
        \\> * text `hi`
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    // Every record comes back, in the order it was written.
    try testing.expectEqual(@as(usize, 2), collect.got.records.items.len);
    try testing.expectEqual(sigil.Sigil.thought, collect.got.records.items[0].sigil);
    try testing.expectEqual(sigil.Sigil.bot, collect.got.records.items[1].sigil);
    try testing.expectEqualStrings("one\ntwo", collect.got.records.items[1].content.?);

    // 💭 and 🤖 reached the reader as they arrived, each as its own record;
    // the call did not, because a call cannot be shown until it is whole.
    try testing.expectEqualStrings("thought:thinking\nbot:one\ntwo", collect.seen.items);
    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("c1", reply.calls[0].id);
    try testing.expectEqualStrings("say", reply.calls[0].name);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}
