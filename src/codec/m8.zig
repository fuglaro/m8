//! The m8 api: the language itself.
//!
//! The one codec whose view is the whole ledger, which is why encoding loses
//! nothing and `decode m8` is a null operation. A provider declaring this api
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
    .decode = decode,
    .parse = parse,
};

fn encode(arena: Allocator, records: []const doc.Record, target: api.Target) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    try ledger.writeAll(&buf.writer, arena, target.mode, records);
    return buf.written();
}

fn decode(arena: Allocator, bytes: []const u8) ![]const doc.Record {
    var diag: doc.Diagnostic = .{};
    return doc.parse(arena, bytes, &diag);
}

/// Read a reply as it is written.
///
/// The whole document is kept so the structure can be read from it at the
/// end, and 🤖 content is pushed on as each line lands. Two passes over the
/// same bytes, which is the price of streaming a format that is only whole
/// once it ends.
fn parse(arena: Allocator, r: *std.Io.Reader, sink: api.Sink) !api.Reply {
    var all: std.ArrayList(u8) = .empty;
    var mode: ?doc.Mode = null;
    var in_bot = false;
    var said: usize = 0;

    while (true) {
        const raw = (try api.nextLine(arena, r)) orelse break;
        try all.appendSlice(arena, raw);
        const line = std.mem.trimEnd(u8, raw, "\r\n");

        const m = mode orelse blk: {
            for ([_]doc.Mode{ .m8, .md }) |candidate| {
                if (std.mem.startsWith(u8, line, doc.header(candidate))) {
                    mode = candidate;
                    break :blk candidate;
                }
            }
            continue;
        };

        if (std.mem.startsWith(u8, line, doc.header(m))) {
            const rest = line[doc.header(m).len..];
            in_bot = if (sigil.match(m, rest)) |s| s == .bot else false;
            said = 0;
            continue;
        }
        if (line.len == 0) {
            in_bot = false;
            continue;
        }
        if (!in_bot) continue;

        const quote = doc.quote(m);
        const bare = doc.bareQuote(m);
        if (!std.mem.startsWith(u8, line, quote) and !std.mem.eql(u8, line, bare)) continue;

        // Lines are joined by \n, so the break belongs before the next one
        // rather than after the last.
        if (said > 0) try sink.text("\n");
        if (line.len > bare.len) try sink.text(line[quote.len..]);
        said += 1;
    }

    var text: std.ArrayList(u8) = .empty;
    var calls: std.ArrayList(api.Call) = .empty;
    var diag: doc.Diagnostic = .{};
    for (try doc.parse(arena, all.items, &diag)) |rec| switch (rec.sigil) {
        .bot => {
            if (text.items.len > 0) try text.append(arena, '\n');
            try text.appendSlice(arena, rec.content orelse "");
        },
        .call => try calls.append(arena, .{
            .id = ledger.callId(rec.value),
            .name = ledger.callName(rec.value),
            .arguments = try toolbox.parseArgs(arena, doc.detect(all.items) orelse .md, rec.content orelse ""),
        }),
        else => {},
    };
    return .{ .text = text.items, .calls = calls.items };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .write = writeFn };
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
    }
};

test "a reply in the language streams as it is written" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const body =
        \\# :robot:
        \\> one
        \\> two
        \\
        \\# :calling:say,c1
        \\> :package:text
        \\> > hi
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    try testing.expectEqualStrings("one\ntwo", reply.text);
    // 🤖 content reached the reader; the call did not, because a call cannot
    // be run until its arguments are whole.
    try testing.expectEqualStrings("one\ntwo", collect.seen.items);
    try testing.expectEqual(@as(usize, 1), reply.calls.len);
    try testing.expectEqualStrings("c1", reply.calls[0].id);
    try testing.expectEqualStrings("say", reply.calls[0].name);
    try testing.expectEqualStrings(
        \\{"text":"hi"}
    , reply.calls[0].arguments);
}
