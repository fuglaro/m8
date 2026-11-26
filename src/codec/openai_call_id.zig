//! Internal call IDs shared by the OpenAI Completions and Responses codecs.
//! The batch token and provider ID (or a short local number for a long ID)
//! are separated by a colon.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Assigned = struct { id: []const u8, original: ?[]const u8 };

pub const Parts = struct {
    batch: []const u8,
    payload: []const u8,
};

pub fn newBatch(arena: Allocator, io: std.Io) ![]const u8 {
    var random: [9]u8 = undefined;
    io.random(&random);
    const encoder = std.base64.url_safe_no_pad.Encoder;
    const token = try arena.alloc(u8, encoder.calcSize(random.len));
    return encoder.encode(token, &random);
}

/// Keep provider IDs as written unless long IDs need a short ledger alias.
/// The original long ID is preserved in a following :call:<internal-id> aside.
pub fn make(arena: Allocator, batch: []const u8, provider_id: []const u8, long_index: usize) !Assigned {
    const payload = if (provider_id.len > 80)
        try std.fmt.allocPrint(arena, "{d}", .{long_index})
    else
        provider_id;
    return .{
        .id = try std.fmt.allocPrint(arena, "{s}:{s}", .{ batch, payload }),
        .original = if (provider_id.len > 80) provider_id else null,
    };
}

pub fn parts(id: []const u8) ?Parts {
    const cut = std.mem.indexOfScalar(u8, id, ':') orelse return null;
    const batch = id[0..cut];
    const payload = id[cut + 1 ..];
    if (batch.len == 0) return null;
    return .{ .batch = batch, .payload = payload };
}

pub fn batchId(id: []const u8) ?[]const u8 {
    return if (parts(id)) |p| p.batch else null;
}

/// If the ID is batch-qualified, return its provider-ID portion. Otherwise
/// leave an ID from another codec untouched.
pub fn providerId(arena: Allocator, id: []const u8) ![]const u8 {
    _ = arena;
    return if (parts(id)) |p| p.payload else id;
}

pub fn asideValue(arena: Allocator, id: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, ":call:{s}", .{id});
}

test "batch-qualified IDs preserve short provider IDs verbatim" {
    const testing = std.testing;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const batch = "isuIHy18_ELu";
    for ([_][]const u8{ "", "a:b,c", "call_1", "under_score-123" }) |original| {
        const internal = try make(arena, batch, original, 1);
        try testing.expectEqualStrings(batch, batchId(internal.id).?);
        try testing.expectEqualStrings(original, try providerId(arena, internal.id));
        try testing.expect(internal.original == null);
    }
}

test "the same provider ID is distinct in separate batches" {
    const testing = std.testing;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const first = try make(arena, "isuIHy18_ELu", "call_same", 1);
    const second = try make(arena, "tduyxbutjbA1", "call_same", 1);
    try testing.expect(!std.mem.eql(u8, first.id, second.id));
    try testing.expectEqualStrings("isuIHy18_ELu", batchId(first.id).?);
    try testing.expectEqualStrings("tduyxbutjbA1", batchId(second.id).?);
    try testing.expectEqualStrings("call_same", try providerId(arena, first.id));
    try testing.expectEqualStrings("call_same", try providerId(arena, second.id));
}

test "long IDs use a short local number and exact following aside" {
    const testing = std.testing;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const original = try arena.alloc(u8, 81);
    @memset(original, 'x');
    const internal = try make(arena, "isuIHy18_ELu", original, 2);
    try testing.expectEqualStrings("isuIHy18_ELu:2", internal.id);
    try testing.expectEqualStrings(try std.fmt.allocPrint(arena, ":call:{s}", .{internal.id}), try asideValue(arena, internal.id));
    try testing.expectEqualStrings("2", (parts(internal.id).?).payload);
    try testing.expectEqualStrings("2", try providerId(arena, internal.id));
    try testing.expectEqualStrings(original, internal.original.?);
}
