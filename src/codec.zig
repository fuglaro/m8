//! What an api is.
//!
//! A codec is a name, the path it lives at, and the two directions between a
//! ledger and a wire format. The name is the one written in `providers.json`
//! and the one typed at `m8 encode`, because they are the same thing — there
//! is no second table mapping one to the other.
//!
//! Encoding may lose whatever the target cannot say: order, 💭, a 🔌. That is
//! what makes it a projection. The ledger it came from still holds all of it.

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

pub const Codec = struct {
    name: []const u8,
    summary: []const u8,
    /// Appended to a provider's url. Empty when the codec is not a wire
    /// format, which is how `m8` gets to be one of these at all.
    suffix: []const u8 = "",
    encode: *const fn (Allocator, []const doc.Record, Target) anyerror![]const u8,
    decode: *const fn (Allocator, []const u8) anyerror![]const doc.Record,
};

pub const openai_completions = @import("codec/openai_completions.zig");

pub const all = [_]Codec{
    .{
        .name = "m8",
        .summary = "the language itself; encoding is writing it out",
        .encode = encodeM8,
        .decode = decodeM8,
    },
    openai_completions.codec,
};

pub fn find(name: []const u8) ?Codec {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// The default api for a provider that names none.
pub const default = "openai-completions";

fn encodeM8(arena: Allocator, records: []const doc.Record, target: Target) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(arena);
    try ledger.writeAll(&buf.writer, arena, target.mode, records);
    return buf.written();
}

fn decodeM8(arena: Allocator, bytes: []const u8) ![]const doc.Record {
    var diag: doc.Diagnostic = .{};
    return doc.parse(arena, bytes, &diag);
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
