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
//! refuse rather than quietly discarded. Decoding is partial, and what it hands back is a
//! ledger-shaped approximation rather than the ledger. A tool comes back
//! without its 🔌 or its 🔒 because a model call has no business carrying
//! either, so their absence on the way home is this working rather than
//! failing.
//!
//! `m8` is the one codec whose view is the whole ledger. That is the reason it
//! belongs in this table, and the reason `decode m8` loses nothing.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");
const Sigil = @import("m8/sigil.zig").Sigil;
const modelform = @import("m8/model.zig");
const ledger = @import("ledger.zig");
const toolbox = @import("toolbox.zig");

pub const Error = error{UnknownCodec};

/// How a request is read when decoding. m8 never writes a key twice, but a
/// request from elsewhere may, and the last one is how most JSON reads it.
pub const request_options: std.json.ParseOptions = .{ .duplicate_field_behavior = .use_last };

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
/// A sink is free to keep nothing. What the ledger gets is the reply, not
/// this: showing and recording are different jobs and only one of them has to
/// hold the whole thing.
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

/// What a response turned out to hold: the records it adds to a ledger, in
/// the order the model produced them.
///
/// Handed back as well as streamed, because the ledger needs the whole of
/// them and a sink is entitled to keep nothing. The calls are carried beside
/// the records rather than read back out of them: a tool is run from
/// arguments that are still JSON, and the records hold them rendered.
pub const Reply = struct {
    records: []const doc.Record = &.{},
    calls: []const Call = &.{},

    /// The 🤖 content, joined — what was said, with no account of how it came
    /// to be said. For a caller deciding on the answer rather than recording
    /// it; a ledger wants `records`, which keeps the 💭 as well.
    pub fn said(r: Reply, arena: Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (r.records) |rec| {
            if (rec.sigil != .bot or rec.content == null) continue;
            if (out.items.len > 0) try out.append(arena, '\n');
            try out.appendSlice(arena, rec.content orelse "");
        }
        return out.items;
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
/// Last in the reply, and out to the reader as well as into the records,
/// because it is said of everything above it.
pub fn stopped(
    arena: Allocator,
    sink: Sink,
    records: *std.ArrayList(doc.Record),
    stops: Stops,
    reason: []const u8,
) !void {
    if (reason.len == 0) return;
    const how = stops.get(reason) orelse "stopped at";
    if (how.len == 0) return;
    try stoppedAs(arena, sink, records, how, reason);
}

/// The same, with the words chosen by the codec — for a reason that carries
/// detail of its own, such as which policy a refusal was made under.
pub fn stoppedAs(
    arena: Allocator,
    sink: Sink,
    records: *std.ArrayList(doc.Record),
    how: []const u8,
    reason: []const u8,
) !void {
    const value = try std.fmt.allocPrint(arena, "({s} {s})", .{ how, reason });
    try sink.record(.bot, value, "");
    try records.append(arena, .{ .sigil = .bot, .value = value });
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
    decode: *const fn (Allocator, []const u8) anyerror![]const doc.Record,
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

pub const all = [_]Codec{
    m8.codec,
    openai_completions.codec,
    anthropic_messages.codec,
    openai_responses.codec,
};

pub fn find(name: []const u8) ?Codec {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// The api a provider gets when it names none.
pub const default = "openai-completions";

/// Every format there is, for whichever page is asking. The table itself
/// rather than a copy of it, so nothing can come to be listed that `find`
/// would not return.
pub fn list(w: *std.Io.Writer) !void {
    try w.writeAll("\nformats:\n\n");
    for (all) |c| try w.print("  {s: <20} {s}\n", .{ c.name, c.summary });
    try w.print("\nA provider that names none is sent {s}.\n", .{default});
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
    // The name a provider defaults to has to be one of them.
    try testing.expect(find(default) != null);
    try testing.expect(find("nosuch") == null);
}

test "m8 encodes to itself and decodes back" {
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
    const records = try c.decode(arena, src);
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
