//! Assembling a ledger: what an address reads as, whatever was piped in, and
//! the prompt, in that order.
//!
//!   nothing piped   LEAD → prompt
//!   m8 piped        LEAD → the document → prompt
//!   anything else   LEAD → prompt, with the text after it
//!
//! One rule is behind all of it — what arrived is added to, and nothing else
//! is. A document that arrived is records already, so it follows the lead as
//! it is. Anything else piped in is prose rather than context — it is what
//! somebody would have typed after the address — so it joins the prompt.
//!
//! The order is the order it was written. A 🧭 that ends up after a 🙋 stays
//! there; putting it first is the business of whichever api encoding is about
//! to want it that way. So is which model it runs on: the last one named, so
//! a model piped in after a chat is the one that answers.
//!
//! Nothing here reads the disk. What an address reads as is `address`'s
//! business, and it arrives here as the record it settled on.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("m8/doc.zig");

pub const Assembled = struct {
    /// The ledger, in the spelling every file is written in.
    document: []const u8 = "",
    /// Whether anything was piped in or typed. An address on its own is not
    /// something to say.
    said_nothing: bool = true,
};

/// A document is told from prose by its first line alone, so one that opens
/// like a document and then goes wrong is an error rather than a prompt.
pub fn assemble(
    arena: Allocator,
    lead: []const doc.Record,
    prompt: []const u8,
    piped: []const u8,
) !Assembled {
    const is_document = piped.len > 0 and doc.detect(piped) != null;
    const prose = if (is_document) "" else std.mem.trim(u8, piped, " \t\r\n");

    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, lead);

    if (is_document) {
        var diag: doc.Diagnostic = .{};
        try records.appendSlice(arena, try doc.parse(arena, piped, &diag));
    }

    // The prompt and whatever prose was piped are one thing said, not two: a
    // prompt in front of piped text is a preamble to it.
    const said = if (prompt.len > 0 and prose.len > 0)
        try std.fmt.allocPrint(arena, "{s}\n{s}", .{ prompt, prose })
    else if (prompt.len > 0) prompt else prose;
    if (said.len > 0) try records.append(arena, .{ .sigil = .user, .content = said });

    var buf: std.Io.Writer.Allocating = .init(arena);
    try doc.writeAll(&buf.writer, .md, records.items);
    return .{
        .document = buf.written(),
        .said_nothing = piped.len == 0 and prompt.len == 0,
    };
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn sigils(arena: Allocator, a: Assembled) ![]const doc.Record {
    var diag: doc.Diagnostic = .{};
    return doc.parse(arena, a.document, &diag);
}

const chat_lead: []const doc.Record = &.{.{ .sigil = .agent, .value = "mob/agent/=/last" }};

test "nothing piped: the lead, then the prompt" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const got = try assemble(arena, chat_lead, "hello", "");
    const r = try sigils(arena, got);
    try testing.expectEqual(@as(usize, 2), r.len);
    try testing.expectEqualStrings("mob/agent/=/last", r[0].value);
    try testing.expectEqualStrings("hello", r[1].content.?);
    try testing.expect(!got.said_nothing);

    // Neither piped nor said is nothing to say.
    try testing.expect((try assemble(arena, chat_lead, "", "")).said_nothing);
}

test "an m8 document piped in follows the lead as it is" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const piped = "#### :brain:/local/tiny\n\n#### :raising_hand:\n> piped\n";
    const got = try assemble(arena, chat_lead, "more", piped);
    const r = try sigils(arena, got);
    try testing.expectEqual(@as(usize, 4), r.len);
    try testing.expectEqualStrings("mob/agent/=/last", r[0].value);
    try testing.expectEqualStrings("/local/tiny", r[1].value);
    try testing.expectEqualStrings("piped", r[2].content.?);
    try testing.expectEqualStrings("more", r[3].content.?);

    // With no lead it is the document alone, and a prompt is not needed.
    const alone = try assemble(arena, &.{}, "", piped);
    try testing.expectEqualStrings("/local/tiny", (try sigils(arena, alone))[0].value);
    try testing.expect(!alone.said_nothing);
}

test "prose piped in joins the prompt rather than becoming its own record" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const got = try assemble(arena, chat_lead, "Summarize:", "line one\nline two\n");
    const r = try sigils(arena, got);
    try testing.expectEqual(@as(usize, 2), r.len);
    // One 🙋, the prompt as a preamble to what was piped.
    try testing.expectEqualStrings("Summarize:\nline one\nline two", r[1].content.?);

    // With no prompt it is the piped text alone.
    const bare = try assemble(arena, chat_lead, "", "just this\n");
    try testing.expectEqualStrings("just this", (try sigils(arena, bare))[1].content.?);
}

test "a header-shaped prompt without a sigil stays prose" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const got = try assemble(arena, chat_lead, "", "#### Should be raw because no real sigil.\n=\n");
    const r = try sigils(arena, got);
    try testing.expectEqual(@as(usize, 2), r.len);
    try testing.expectEqualStrings("#### Should be raw because no real sigil.\n=", r[1].content.?);
}

test "a document that opens right and then goes wrong is an error, not a prompt" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();

    // Detection is the first line alone. This one is a document, and a broken
    // one, so it is refused rather than quietly sent as something to say.
    try testing.expectError(error.UnknownSigil, assemble(
        a.allocator(),
        chat_lead,
        "",
        "#### :brain:/local/tiny\n\n#### :nosuchsigil:\n",
    ));
}
