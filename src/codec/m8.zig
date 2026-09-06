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
    var open: bool = false;
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
            if (open) {
                try sink.end();
                open = false;
            }
            const rest = line[doc.header(m).len..];
            if (sigil.match(m, rest)) |hit| if (shows(hit.sigil)) {
                try sink.begin(hit.sigil, std.mem.trim(u8, rest[hit.len..], " \t"));
                open = true;
            };
            said = 0;
            continue;
        }
        if (line.len == 0) {
            if (open) {
                try sink.end();
                open = false;
            }
            continue;
        }
        if (!open) continue;

        const quote = doc.quote(m);
        const bare = doc.bareQuote(m);
        if (!std.mem.startsWith(u8, line, quote) and !std.mem.eql(u8, line, bare)) continue;

        // Lines are joined by \n, so the break belongs before the next one
        // rather than after the last.
        if (said > 0) try sink.text("\n");
        if (line.len > bare.len) try sink.text(line[quote.len..]);
        said += 1;
    }
    if (open) try sink.end();

    // Second pass, over the same bytes, for the structure a line at a time
    // could not give: the records as records, in the order they were written.
    // Nothing is filtered out here. A reply may only hold what `policy.zig`
    // says a model can produce, and letting an unexpected sigil through to be
    // refused there is the point — dropping it quietly is how a 💭 came to be
    // silently lost on the way to the ledger.
    var recs: std.ArrayList(doc.Record) = .empty;
    var calls: std.ArrayList(api.Call) = .empty;
    var diag: doc.Diagnostic = .{};
    const m = doc.detect(all.items) orelse .md;
    for (try doc.parse(arena, all.items, &diag)) |rec| {
        if (rec.sigil == .call) try calls.append(arena, .{
            .id = ledger.callId(rec.value),
            .name = ledger.callName(rec.value),
            .arguments = try toolbox.parseArgs(arena, m, rec.content orelse ""),
        });
        try recs.append(arena, rec);
    }
    return .{ .records = recs.items, .calls = calls.items };
}

/// Whether a record can be shown before it is whole.
///
/// 💭 and 🤖 are prose and read the same half-written. A 📲 is not: its
/// arguments mean nothing until the last brace, so it is gathered and shown
/// by whoever is about to run it. The ledger gets every record either way and
/// in the written order — only the live display is selective.
fn shows(s: sigil.Sigil) bool {
    return s == .bot or s == .thought;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// A sink that writes what it is given as `sigil:content`, one record a line,
/// so a test can assert the order as well as the bytes.
const Collect = struct {
    arena: Allocator,
    seen: std.ArrayList(u8) = .empty,

    fn sink(self: *Collect) api.Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }
    fn openFn(ctx: *anyopaque, s: sigil.Sigil, _: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        if (self.seen.items.len > 0) try self.seen.append(self.arena, '\n');
        try self.seen.appendSlice(self.arena, @tagName(s));
        try self.seen.append(self.arena, ':');
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *Collect = @ptrCast(@alignCast(ctx));
        try self.seen.appendSlice(self.arena, bytes);
    }
    fn closeFn(_: *anyopaque) anyerror!void {}
};

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
        \\> :package:text
        \\> > hi
    ;
    var r: std.Io.Reader = .fixed(body);
    var collect: Collect = .{ .arena = arena };
    const reply = try parse(arena, &r, collect.sink());

    // Every record comes back, in the order it was written.
    try testing.expectEqual(@as(usize, 3), reply.records.len);
    try testing.expectEqual(sigil.Sigil.thought, reply.records[0].sigil);
    try testing.expectEqual(sigil.Sigil.bot, reply.records[1].sigil);
    try testing.expectEqual(sigil.Sigil.call, reply.records[2].sigil);
    try testing.expectEqualStrings("one\ntwo", reply.records[1].content.?);

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
