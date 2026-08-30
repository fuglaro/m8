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
//! still holds all of it. Decoding is partial, and what it hands back is a
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
const modelform = @import("m8/model.zig");
const ledger = @import("ledger.zig");
const toolbox = @import("toolbox.zig");

pub const Error = error{UnknownCodec};

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
    /// The tools offered, already filtered by 🔓.
    tools: []const toolbox.Tool = &.{},
    /// The spelling to write, for a codec whose wire format is m8 itself.
    mode: doc.Mode = .md,
};

/// Where a reply's text goes as it arrives.
///
/// Only text can be acted on before the end: it can be shown. A call cannot
/// be run until its arguments are whole, so calls are gathered rather than
/// streamed, and that is the whole reason this carries one channel.
pub const Sink = struct {
    ctx: *anyopaque,
    write: *const fn (ctx: *anyopaque, bytes: []const u8) anyerror!void,

    pub fn text(s: Sink, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        return s.write(s.ctx, bytes);
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

/// What a response turned out to hold. The text is handed back as well as
/// streamed, because the ledger needs the whole of it.
pub const Reply = struct {
    text: []const u8 = "",
    calls: []const Call = &.{},
};

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

pub const all = [_]Codec{
    m8.codec,
    openai_completions.codec,
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
pub fn nextLine(arena: Allocator, r: *std.Io.Reader) !?[]const u8 {
    if (r.takeDelimiterInclusive('\n')) |line| {
        return line;
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }
    const rest = try r.allocRemaining(arena, .unlimited);
    return if (rest.len == 0) null else rest;
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
        \\# :brain:local/tiny
        \\
        \\# :computer:
        \\> Be brief.
        \\
        \\# :raising_hand:
        \\> Hi.
        \\
    ;
    const c = find("m8").?;
    const records = try c.decode(arena, src);
    try testing.expectEqualStrings(src, try c.encode(arena, records, .{}));
}
