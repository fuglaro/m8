//! Join an optional prompt with explicitly supplied stdin prose as one record.
//! When the conversation is waiting on a question, that record answers it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");

/// What was said, as the record it is: a 🙋, or the ❗ that answers whoever
/// `waiting` names. Null when nothing was.
///
/// The prompt and prose are one submission, not two: the prompt is a preamble
/// to explicitly included stdin, joined by one newline when both are nonempty.
pub fn said(arena: Allocator, prompt: []const u8, prose: []const u8, waiting: ?[]const u8) !?doc.Record {
    const text = if (prompt.len > 0 and prose.len > 0)
        try std.fmt.allocPrint(arena, "{s}\n{s}", .{ prompt, prose })
    else if (prompt.len > 0) prompt else prose;
    if (text.len == 0) return null;
    return if (waiting) |id|
        .{ .sigil = .exclaim, .value = id, .content = text }
    else
        .{ .sigil = .user, .content = text };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "prompt and explicit stdin prose join with one newline, keeping whitespace" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const record = (try said(arena, "  prompt  ", "  prose \n", null)).?;
    try testing.expectEqual(doc.Sigil.user, record.sigil);
    try testing.expectEqualStrings("  prompt  \n  prose \n", record.content.?);
}

test "m8-looking stdin is ordinary prose" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const prose = "* :brain::/toy/echo\n\n* :raising_hand::\n  > words\n";

    const record = (try said(arena, "", prose, null)).?;
    try testing.expectEqual(doc.Sigil.user, record.sigil);
    try testing.expectEqualStrings(prose, record.content.?);
}

test "empty prompt and prose say nothing" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();

    try testing.expect((try said(arena_state.allocator(), "", "", null)) == null);
}

test "submission answers the waiting question as an exclaim" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const record = (try said(arena, "answer", "details", "call-1")).?;
    try testing.expectEqual(doc.Sigil.exclaim, record.sigil);
    try testing.expectEqualStrings("call-1", record.value);
    try testing.expectEqualStrings("answer\ndetails", record.content.?);
}
