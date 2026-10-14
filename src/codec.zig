//! What an api is.
//!
//! A codec is a name, the path it lives at, and the two directions between a
//! ledger and a wire format. The name is the one written in `providers.json`
//! and the one typed at `m8 encode`, because they are the same thing — there
//! is no second table mapping one to the other.
//!
//! A ledger always has an api view. An api request never has a ledger. That
//! asymmetry is the shape of this file and it is not a gap in any particular
//! codec: a request carries what one model needs in order to answer once,
//! while a ledger carries what happened and what it was allowed to do.
//!
//! So encoding is total and loses whatever the target cannot say — order, 💭,
//! a 🔌 — which is what makes it a projection, and the ledger it came from
//! still holds all of it. Reading a response is the other direction and drops
//! nothing on purpose: what comes back is records in the order the model made
//! them, and a sigil this api did not expect is handed to `policy.zig` to
//! refuse rather than quietly discarded.
//!
//! `m8` is the one codec whose view is the whole ledger. That is the reason it
//! belongs in this table.

const std = @import("std");
const build_options = @import("build_options");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const Sigil = @import("m8/sigil.zig").Sigil;
const modelform = @import("m8/model.zig");
const ledger = @import("ledger.zig");
const toolbox = @import("toolbox.zig");

pub const Error = error{UnknownCodec};

/// The transient value a provider gives a 💭 whose content should be kept aside.
pub const snip = @import("session.zig").snip;

/// The text of a thought. A block is the full form; without one, the value is
/// the compact one-line form. `snip` is special only when the block exists,
/// so a blockless `💭snip` is ordinary thought text too.
pub fn thoughtText(r: doc.Record) []const u8 {
    return r.content orelse r.value;
}

/// What the ledger says the request is, plus the one thing it cannot: whether
/// the answer is streamed, which belongs to this run rather than to what was
/// said.
///
/// The parameters are the ledger's, in the api's own words, and go out as
/// written. m8 knows none of them by name — which is exactly what lets one it
/// has never heard of survive being sent and read back.
pub const Target = struct {
    model: []const u8 = "",
    params: []const modelform.Param = &.{},
    stream: bool = false,
    /// The tools offered, already filtered by what a blockless 🧰 named.
    tools: []const toolbox.Tool = &.{},
    /// The spelling to write, for a codec whose wire format is m8 itself.
    mode: doc.Mode = .md,
};

/// Where a reply goes as it arrives.
///
/// A reply is a sequence of records rather than a block of text. A model that
/// thinks answers with 💭 before its 🤖, and one that thinks between tool
/// calls answers with more of each — so what arrives is ordered, and the order
/// is the model's rather than this file's guess at it. The sink is opened and
/// closed around every record and the bytes in between are that record's
/// content, which is also what lets a thought be shown while it is still
/// being thought.
///
/// A sink that wants the records keeps them as they close, as `Gather` does.
pub const Sink = struct {
    ctx: *anyopaque,
    open: *const fn (ctx: *anyopaque, sigil: Sigil, value: []const u8) anyerror!void,
    write: *const fn (ctx: *anyopaque, bytes: []const u8) anyerror!void,
    close: *const fn (ctx: *anyopaque) anyerror!void,

    pub fn begin(s: Sink, sigil: Sigil, value: []const u8) !void {
        return s.open(s.ctx, sigil, value);
    }

    pub fn text(s: Sink, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        return s.write(s.ctx, bytes);
    }

    pub fn end(s: Sink) !void {
        return s.close(s.ctx);
    }

    /// A record that was never streamed, in one go. A 📲 arrives this way
    /// because its arguments are only meaningful once they are whole.
    pub fn record(s: Sink, sigil: Sigil, value: []const u8, content: []const u8) !void {
        try s.begin(sigil, value);
        try s.text(content);
        try s.end();
    }
};

/// A tool call, whether coming back from a model or going out again as part
/// of the conversation so far.
pub const Call = struct {
    id: []const u8,
    name: []const u8,
    /// The arguments as the model wrote them, still JSON.
    arguments: []const u8,
};

/// What a response held that was not said: the calls it made.
///
/// Everything said went to the sink, in the order the model produced it. A
/// call is carried here instead because a tool is run from arguments that are
/// still JSON, and those mean nothing until the last brace.
pub const Reply = struct {
    calls: []const Call = &.{},
    /// Something to say beside the reply, to whoever is watching the run
    /// rather than reading it: a line for stderr, such as what the call cost.
    aside: []const u8 = "",
};

/// A sink that keeps the reply as records, for whoever wants it whole.
pub const Gather = struct {
    arena: Allocator,
    records: std.ArrayList(doc.Record) = .empty,
    pending: Sigil = .bot,
    value: []const u8 = "",
    text: std.ArrayList(u8) = .empty,

    pub fn sink(self: *Gather) Sink {
        return .{ .ctx = self, .open = openFn, .write = writeFn, .close = closeFn };
    }

    pub fn open(self: *Gather, s: Sigil, value: []const u8) void {
        self.pending = s;
        self.value = value;
    }

    pub fn write(self: *Gather, bytes: []const u8) !void {
        try self.text.appendSlice(self.arena, bytes);
    }

    /// The record just closed, or null for one that said nothing: a codec is
    /// entitled to open a record and find the model had no more to say.
    pub fn close(self: *Gather) !?doc.Record {
        const r: doc.Record = .{
            .sigil = self.pending,
            .value = self.value,
            .content = if (self.text.items.len > 0) self.text.items else null,
        };
        self.* = .{ .arena = self.arena, .records = self.records };
        if (r.content == null and r.value.len == 0) return null;
        try self.records.append(self.arena, r);
        return r;
    }

    /// The 🤖 content, joined — what was said, with no account of how it came
    /// to be said. For a caller deciding on the answer rather than recording
    /// it.
    pub fn said(self: *const Gather, arena: Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (self.records.items) |rec| {
            if (rec.sigil != .bot or rec.content == null) continue;
            if (out.items.len > 0) try out.append(arena, '\n');
            try out.appendSlice(arena, rec.content orelse "");
        }
        return out.items;
    }

    fn openFn(ctx: *anyopaque, s: Sigil, value: []const u8) anyerror!void {
        @as(*Gather, @ptrCast(@alignCast(ctx))).open(s, value);
    }
    fn writeFn(ctx: *anyopaque, bytes: []const u8) anyerror!void {
        try @as(*Gather, @ptrCast(@alignCast(ctx))).write(bytes);
    }
    fn closeFn(ctx: *anyopaque) anyerror!void {
        _ = try @as(*Gather, @ptrCast(@alignCast(ctx))).close();
    }
};

/// What each of an api's stop reasons reads as: the words before the
/// provider's own term. Empty for a reason that means the model finished or
/// asked for tools, which the ledger already shows.
pub const Stops = std.StaticStringMap([]const u8);

/// A reply that stopped short, said as a 🤖 with a value and nothing under it.
///
/// A provider says why generation ended in its own dialect, and a ledger that
/// dropped it would record a cut-off answer as a whole one. So each codec
/// keeps it in the one form they share: a few words for whoever reads the
/// transcript, with the provider's term last and untouched, which is what
/// anything wanting to act on it can match without m8 knowing what any of
/// them mean. A reason a codec has not heard of still reads as stopping.
///
/// Last in the reply, because it is said of everything above it.
pub fn stopped(
    arena: Allocator,
    sink: Sink,
    stops: Stops,
    reason: []const u8,
) !void {
    if (reason.len == 0) return;
    const how = stops.get(reason) orelse "stopped at";
    if (how.len == 0) return;
    try stoppedAs(arena, sink, how, reason);
}

/// The same, with the words chosen by the codec — for a reason that carries
/// detail of its own, such as which policy a refusal was made under.
pub fn stoppedAs(
    arena: Allocator,
    sink: Sink,
    how: []const u8,
    reason: []const u8,
) !void {
    try sink.record(.bot, try std.fmt.allocPrint(arena, "({s} {s})", .{ how, reason }), "");
}

/// An api that answered with an error, said the way a reply that stopped
/// short is: what it said, then the words, then its own term last.
///
/// The error is what came back, so it is the reply — shown where an answer
/// would have been and kept in the ledger, rather than thrown past both. It
/// has nothing under it, so no api is ever told it again.
///
/// `e` is normally the object holding the api's `message` beside its `type`
/// or `code`; a few APIs use `summary`, `detail`, or a string directly.
pub fn failed(arena: Allocator, sink: Sink, e: ?std.json.Value) !void {
    var message: []const u8 = "";
    var term: []const u8 = "error";
    if (e) |v| switch (v) {
        .string => message = v.string,
        .object => {
            for ([_][]const u8{ "message", "summary", "detail" }) |name| {
                if (v.object.get(name)) |m| if (m == .string and m.string.len > 0) {
                    message = m.string;
                    break;
                };
            }
            // The type is the term, and a code stands in where there is no
            // type, or only an event's own `error`, which says nothing more.
            for ([_][]const u8{ "code", "type" }) |name| {
                if (v.object.get(name)) |t| if (t == .string and t.string.len > 0) {
                    if (std.mem.eql(u8, t.string, "error") and !std.mem.eql(u8, term, "error")) continue;
                    term = t.string;
                };
            }
        },
        else => {},
    };
    if (message.len == 0) return stoppedAs(arena, sink, "failed with", term);

    const line = try briefLine(arena, message);
    if (line.len == 0) return stoppedAs(arena, sink, "failed with", term);
    try stoppedAs(
        arena,
        sink,
        try std.fmt.allocPrint(arena, "{s} - failed with", .{line}),
        term,
    );
}

/// An api that failed without saying why, in any place anyone knew to look.
/// What arrived follows the words, cut to a line, so a shape nobody has met
/// still explains itself.
pub fn failedWith(arena: Allocator, sink: Sink, arrived: []const u8) !void {
    const line = try briefLine(arena, arrived);
    if (line.len == 0) return stoppedAs(arena, sink, "failed with", "error");
    try stoppedAs(arena, sink, "failed with", try std.fmt.allocPrint(arena, "error - {s}", .{line}));
}

/// Error text lives in a record value, so make arbitrary provider prose a
/// compact line rather than letting an HTML error or stack trace take over a
/// transcript.
fn briefLine(arena: Allocator, text: []const u8) ![]const u8 {
    const limit = 240;
    var line: std.ArrayList(u8) = .empty;
    var space = false;
    for (text) |c| {
        if (std.ascii.isWhitespace(c)) {
            space = line.items.len > 0;
            continue;
        }
        if (space) try line.append(arena, ' ');
        try line.append(arena, c);
        space = false;
    }
    if (line.items.len <= limit) return line.items;

    // Do not split a UTF-8 sequence to make room for the ellipsis.
    var end: usize = limit - 3;
    while (end > 0 and line.items[end] & 0xc0 == 0x80) end -= 1;
    line.items.len = end;
    try line.appendSlice(arena, "...");
    return line.items;
}

/// What a response says it cost, in counts every api can be read into.
/// `in` is the whole prompt, cached or not.
pub const Cost = struct {
    in: i64 = 0,
    cached: i64 = 0,
    written: i64 = 0,
    out: i64 = 0,
    thinking: i64 = 0,
};

/// A cost as a line: how much went in, how much of that the prompt cache
/// already held, and how much came out.
///
/// It leads with the same in a few cells, for something that keeps a panel:
/// what came out, a block as tall as the share the cache held, what went in.
pub fn costLine(arena: Allocator, c: Cost) ![]const u8 {
    const hit = if (c.in > 0) @divTrunc(c.cached * 100, c.in) else 0;
    var a: [8]u8 = undefined;
    var b: [8]u8 = undefined;
    var line: std.Io.Writer.Allocating = .init(arena);
    const w = &line.writer;
    try w.print("::stats::\u{2725}{s}{s}{s}::", .{ short(&a, c.out), cacheBlock(c.cached, hit), short(&b, c.in) });
    try w.print("\u{1F9EE} {d} in, {d} cached ({d}%)", .{ c.in, c.cached, hit });
    if (c.written > 0) try w.print(", {d} written", .{c.written});
    try w.print(", {d} out", .{c.out});
    if (c.thinking > 0) try w.print(" ({d} thinking)", .{c.thinking});
    return line.written();
}

/// A count in at most four characters: 999, 1K, 16K, 160K, 1M.
fn short(buf: *[8]u8, count: i64) []const u8 {
    var n: u64 = @intCast(@max(0, count));
    var unit: usize = 0;
    while (n >= 1000 and unit < 5) : (unit += 1) n /= 1000;
    return std.fmt.bufPrint(buf, "{d}{s}", .{ n % 10000, " KMGTP"[unit..][0..@min(unit, 1)] }) catch unreachable;
}

/// A block as tall as the share of the prompt the cache held, and a line
/// along the bottom for none of it. It stops short of a whole block, which
/// would be a hole in a status bar.
fn cacheBlock(cached: i64, percent: i64) []const u8 {
    if (cached <= 0) return "_";
    const blocks = [_][]const u8{ "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}" };
    return blocks[@intCast(std.math.clamp(@divTrunc(percent * 7, 100), 0, 6))];
}

/// The records an api can be told, which is all of them but a 🤖 with nothing
/// under it. How a reply stopped is the ledger's to keep and no api takes it
/// back, and an empty assistant turn is something several refuse outright.
/// Dropped here, once, so no codec's pairing of a reply with its calls has to
/// step around one.
pub fn spoken(arena: Allocator, records: []const doc.Record) ![]const doc.Record {
    var out: std.ArrayList(doc.Record) = .empty;
    for (records) |r| {
        if (r.sigil == .bot and r.content == null) continue;
        try out.append(arena, r);
    }
    return out.items;
}

pub const Codec = struct {
    name: []const u8,
    summary: []const u8,
    encode: *const fn (Allocator, []const doc.Record, Target) anyerror![]const u8,
    /// Read a response as it arrives.
    ///
    /// Reading is incremental whether or not the provider bothered to stream:
    /// a provider that writes everything at once is a stream of one chunk, so
    /// parsing this way is what makes streaming optional on their side rather
    /// than required. A format offering both a streamed and a whole shape is
    /// told apart by looking at what actually arrived.
    parse: *const fn (Allocator, *std.Io.Reader, Sink) anyerror!Reply,
};

pub const m8 = @import("codec/m8.zig");
pub const openai_completions = @import("codec/openai_completions.zig");
pub const anthropic_messages = @import("codec/anthropic_messages.zig");
pub const openai_responses = @import("codec/openai_responses.zig");

/// The formats this build has. `-Dformats` picks among the wire formats, and
/// one left out is never referenced, so it is not compiled either.
pub const all = [_]Codec{m8.codec} ++
    (if (build_options.format_openai_completions) [_]Codec{openai_completions.codec} else [_]Codec{}) ++
    (if (build_options.format_anthropic_messages) [_]Codec{anthropic_messages.codec} else [_]Codec{}) ++
    (if (build_options.format_openai_responses) [_]Codec{openai_responses.codec} else [_]Codec{});

pub fn find(name: []const u8) ?Codec {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// Every format there is, for whichever page is asking. The table itself
/// rather than a copy of it, so nothing can come to be listed that `find`
/// would not return.
pub fn list(w: *std.Io.Writer) !void {
    try w.writeAll("\nformats:\n\n");
    for (all) |c| try w.print("  {s: <20} {s}\n", .{ c.name, c.summary });
}

/// The next line, or null at the end.
///
/// A stream that stops without a final newline still gives up what it had. A
/// whole JSON response arrives exactly that way — one line with nothing after
/// it — so a reader that insisted on the delimiter would see nothing at all.
///
/// Nor is there a length a line stops being one at. A provider that ignored
/// the streaming hint answers in a single line however long the reply is, and
/// an event stream carrying a whole response object in one event is the same
/// thing again — so how big a buffer happens to be is no business of the
/// caller's.
pub fn nextLine(arena: Allocator, r: *std.Io.Reader) !?[]const u8 {
    if (r.takeDelimiterInclusive('\n')) |line| {
        return line;
    } else |e| switch (e) {
        error.EndOfStream => {},
        error.StreamTooLong => return try longLine(arena, r),
        else => return e,
    }
    const rest = try r.allocRemaining(arena, .unlimited);
    return if (rest.len == 0) null else rest;
}

/// A line that outgrew the reader's buffer, put back together.
///
/// A full buffer with no newline in it is the *start* of a line rather than a
/// failure: take what is held, and go back for the rest. Only a line this
/// long is copied — every other one is handed back where the reader already
/// had it, which is what keeps the usual case free.
fn longLine(arena: Allocator, r: *std.Io.Reader) ![]const u8 {
    var line: std.ArrayList(u8) = .empty;
    while (true) {
        const held = r.buffered();
        // Nothing held and still no delimiter is not a case the reader can
        // produce; saying so beats spinning here if it ever did.
        if (held.len == 0) return error.StreamTooLong;
        try line.appendSlice(arena, held);
        r.toss(held.len);

        if (r.takeDelimiterInclusive('\n')) |rest| {
            try line.appendSlice(arena, rest);
            return line.items;
        } else |e| switch (e) {
            // The stream ended mid-line, which is still the line.
            error.EndOfStream => {
                try line.appendSlice(arena, try r.allocRemaining(arena, .unlimited));
                return line.items;
            },
            error.StreamTooLong => continue,
            else => return e,
        }
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "every codec has a name and a summary, and no two share one" {
    for (all) |c| {
        try testing.expect(c.name.len > 0);
        try testing.expect(c.summary.len > 0);
        for (c.name) |ch| try testing.expect(std.ascii.isLower(ch) or ch == '-' or ch == '8');
    }
    for (all, 0..) |a, i| for (all[i + 1 ..]) |b| {
        try testing.expect(!std.mem.eql(u8, a.name, b.name));
    };
    try testing.expect(find("nosuch") == null);
}

test "a thought uses its block, or its compact value" {
    try testing.expectEqualStrings("full", thoughtText(.{
        .sigil = .thought,
        .value = "ignored",
        .content = "full",
    }));
    try testing.expectEqualStrings("compact", thoughtText(.{
        .sigil = .thought,
        .value = "compact",
    }));
    try testing.expectEqualStrings("snip", thoughtText(.{
        .sigil = .thought,
        .value = snip,
    }));
}

test "m8 encodes to itself" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const src =
        \\#### :brain:local/tiny
        \\
        \\#### :compass:
        \\> Be brief.
        \\
        \\#### :raising_hand:
        \\> Hi.
        \\
    ;
    const c = find("m8").?;
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(arena, src, &diag);
    try testing.expectEqualStrings(src, try c.encode(arena, records, .{}));
}

/// A reader with a buffer smaller than what is going through it, which is the
/// whole of what makes a long line long.
fn narrow(src: *std.Io.Reader, buf: []u8) std.Io.Reader.Limited {
    return src.limited(.unlimited, buf);
}

test "a line longer than the buffer is still one line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // Three lines, the middle one several buffers wide.
    const long = "x" ** 200;
    const src = try std.fmt.allocPrint(arena, "one\n{s}\nthree\n", .{long});

    var fixed: std.Io.Reader = .fixed(src);
    var buf: [32]u8 = undefined;
    var lim = narrow(&fixed, &buf);
    const r = &lim.interface;

    try testing.expectEqualStrings("one\n", (try nextLine(arena, r)).?);
    try testing.expectEqualStrings(long ++ "\n", (try nextLine(arena, r)).?);
    try testing.expectEqualStrings("three\n", (try nextLine(arena, r)).?);
    try testing.expect((try nextLine(arena, r)) == null);
}

test "a long last line with no newline on it is still given up" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // A whole JSON response arrives exactly this way: one line, no newline,
    // and nothing says how big it is.
    const body = "{\"choices\":[" ++ ("y" ** 500) ++ "]}";

    var fixed: std.Io.Reader = .fixed(body);
    var buf: [64]u8 = undefined;
    var lim = narrow(&fixed, &buf);
    const r = &lim.interface;

    try testing.expectEqualStrings(body, (try nextLine(arena, r)).?);
    try testing.expect((try nextLine(arena, r)) == null);
}

test "a count is cut to four characters, and a cache share is a block" {
    var b: [8]u8 = undefined;
    try testing.expectEqualStrings("19", short(&b, 19));
    try testing.expectEqualStrings("999", short(&b, 999));
    try testing.expectEqualStrings("1K", short(&b, 1234));
    try testing.expectEqualStrings("16K", short(&b, 16_400));
    try testing.expectEqualStrings("999K", short(&b, 999_999));
    try testing.expectEqualStrings("1M", short(&b, 1_000_000));
    try testing.expectEqualStrings("2G", short(&b, 2_500_000_000));
    try testing.expectEqualStrings("_", cacheBlock(0, 0));
    try testing.expectEqualStrings("\u{2581}", cacheBlock(5, 1));
    try testing.expectEqualStrings("\u{2587}", cacheBlock(6656, 87));
    try testing.expectEqualStrings("\u{2587}", cacheBlock(10, 100));
}
