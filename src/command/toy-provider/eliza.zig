//! ELIZA — Weizenbaum's doctor, 1966, as a model `toy` serves.
//!
//! It belongs here for the same reason `echo` does: it answers without a
//! network, it is entirely predictable, and it says something different every
//! time, which is what makes a conversation worth having with it while the
//! loop around it is being worked on.
//!
//! The whole of it is a keyword found in what you said, whatever followed that
//! keyword with its pronouns turned around, and a sentence to put the two
//! into. The rules are in rank order and the first that matches wins, so a
//! specific one is written above the general one it would otherwise be eaten
//! by — `i am` before `my`, and `my` before `you`.
//!
//! Which of a rule's replies comes back is decided by how many times the
//! person has spoken, which the ledger already says. So the doctor varies
//! through a conversation without remembering anything outside it, and asking
//! the same thing twice gets the same answer twice — a model with no state and
//! no randomness, which is what a test wants.
//!
//! It was never an argument that a machine understands anything, and reading
//! the rules is the demonstration. Weizenbaum wrote it and then spent a book
//! being alarmed at how readily people confided in it.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// What the doctor says to somebody who has said nothing.
pub const opening = "How do you do. Please tell me what has been troubling you.";

const Rule = struct {
    /// Matched as whole words, anywhere in what was said, ignoring case.
    keyword: []const u8,
    /// `{}` is whatever followed the keyword, with its pronouns turned
    /// around. A reply holding one is passed over when there was nothing
    /// after the keyword to put in it.
    replies: []const []const u8,
};

// Shared between the spellings of one thought, so the two cannot drift.
const cannot = [_][]const u8{
    "How do you know that you can't {}?",
    "Perhaps you could {} if you tried.",
    "What would it take for you to {}?",
};
const being = [_][]const u8{
    "Did you come to me because you are {}?",
    "How long have you been {}?",
    "How do you feel about being {}?",
    "Do you enjoy being {}?",
};
const about_me = [_][]const u8{
    "Why do you think I am {}?",
    "Does it please you to believe I am {}?",
    "Perhaps you would like to be {}.",
    "Do you sometimes wish you were {}?",
};
const family = [_][]const u8{
    "Tell me more about your family.",
    "Who else in your family comes to mind?",
    "What else comes to mind when you think of your family?",
    "How do you get along with them?",
};
const greeting = [_][]const u8{
    "Hello. Please tell me what is on your mind.",
    "How do you do. What brings you here today?",
};
const machine = [_][]const u8{
    "Do machines worry you?",
    "Why do you mention computers?",
    "Are you talking about me in particular?",
    "What do you think machines have to do with your problem?",
};
const sadness = [_][]const u8{
    "I am sorry to hear that. Do you think coming here will help?",
    "Can you explain what made you feel that way?",
    "Do you think it is normal to feel like that?",
    "How long have you felt this way?",
};

/// In rank order: the first keyword found in what was said is the one that
/// answers, so a specific rule is written above the general one that would
/// otherwise swallow it.
const rules = [_]Rule{
    .{ .keyword = "i need", .replies = &.{
        "Why do you need {}?",
        "Would it really help you to get {}?",
        "Are you certain you need {}?",
        "What would you do if you had {}?",
    } },
    .{ .keyword = "i can't", .replies = &cannot },
    .{ .keyword = "i cannot", .replies = &cannot },
    .{ .keyword = "i don't", .replies = &.{
        "Don't you really {}?",
        "Why don't you {}?",
        "Do you wish to be able to {}?",
    } },
    .{ .keyword = "i feel", .replies = &.{
        "Tell me more about such feelings.",
        "Do you often feel {}?",
        "Why do you feel {}?",
        "When do you usually feel {}?",
    } },
    .{ .keyword = "i think", .replies = &.{
        "Do you doubt {}?",
        "Do you really think so?",
        "But you are not sure {}.",
    } },
    .{ .keyword = "i want", .replies = &.{
        "What would it mean to you if you got {}?",
        "Why do you want {}?",
        "Suppose you got {} soon.",
        "What would you do if you got {}?",
    } },
    .{ .keyword = "i remember", .replies = &.{
        "Do you often think of {}?",
        "What else do you remember?",
        "Why do you remember {} just now?",
    } },
    .{ .keyword = "i am", .replies = &being },
    .{ .keyword = "i'm", .replies = &being },
    .{ .keyword = "why don't you", .replies = &.{
        "Do you really believe I don't {}?",
        "Perhaps in good time I will {}.",
        "Do you want me to {}?",
    } },
    .{ .keyword = "why can't i", .replies = &.{
        "Do you think you should be able to {}?",
        "Do you want to be able to {}?",
        "What would it mean if you could {}?",
    } },
    .{ .keyword = "are you", .replies = &.{
        "Why does it matter to you whether I am {}?",
        "Would you prefer it if I were not {}?",
        "Perhaps I am {} in your fantasies.",
    } },
    .{ .keyword = "you are", .replies = &about_me },
    .{ .keyword = "you're", .replies = &about_me },
    .{ .keyword = "am i", .replies = &.{
        "Do you believe you are {}?",
        "Would you want to be {}?",
        "What would it mean to you if you were {}?",
    } },
    .{ .keyword = "computer", .replies = &machine },
    .{ .keyword = "machine", .replies = &machine },
    .{ .keyword = "dream", .replies = &.{
        "What does that dream suggest to you?",
        "Do you dream often?",
        "What persons appear in your dreams?",
        "How do you feel about your dreams?",
    } },
    .{ .keyword = "sorry", .replies = &.{
        "There are many times when no apology is needed.",
        "What feelings do you have when you apologise?",
        "Please don't apologise.",
    } },
    .{ .keyword = "hello", .replies = &greeting },
    .{ .keyword = "hi", .replies = &greeting },
    .{ .keyword = "mother", .replies = &family },
    .{ .keyword = "father", .replies = &family },
    .{ .keyword = "sister", .replies = &family },
    .{ .keyword = "brother", .replies = &family },
    .{ .keyword = "family", .replies = &family },
    .{ .keyword = "children", .replies = &family },
    .{ .keyword = "friend", .replies = &.{
        "Why do you bring up the subject of friends?",
        "Do your friends worry you?",
        "Tell me more about them.",
    } },
    .{ .keyword = "sad", .replies = &sadness },
    .{ .keyword = "unhappy", .replies = &sadness },
    .{ .keyword = "depressed", .replies = &sadness },
    .{ .keyword = "afraid", .replies = &sadness },
    .{ .keyword = "always", .replies = &.{
        "Can you think of a specific example?",
        "When?",
        "Really, always?",
    } },
    .{ .keyword = "never", .replies = &.{
        "Never?",
        "Are you sure it has never happened?",
        "Can you think of one time it did?",
    } },
    .{ .keyword = "because", .replies = &.{
        "Is that the real reason?",
        "What other reason might there be?",
        "Does that reason seem to explain anything else?",
    } },
    .{ .keyword = "yes", .replies = &.{
        "You seem quite certain.",
        "I see. Go on.",
        "Why do you think so?",
    } },
    .{ .keyword = "no", .replies = &.{
        "Why not?",
        "Are you saying that to be negative?",
        "You are being somewhat negative.",
    } },
    .{ .keyword = "my", .replies = &.{
        "Why do you say your {}?",
        "Does that suggest anything else which belongs to you?",
        "Tell me more about your {}.",
        "Is it important to you that your {}?",
    } },
    .{ .keyword = "you", .replies = &.{
        "We were discussing you, not me.",
        "Why do you say that about me?",
        "Are we talking about you, or about me?",
    } },
};

/// When nothing was recognised, which is most of the time and is the point.
const anything = [_][]const u8{
    "Please go on.",
    "What does that suggest to you?",
    "Tell me more about that.",
    "I see. And what does that tell you?",
    "Can you elaborate on that?",
    "Does talking about this bother you?",
    "Why do you say that?",
    "How does that make you feel?",
};

/// The pronouns, turned around, so what somebody said about themselves can be
/// said back to them. One pass over the words, so a swap is never undone by
/// the one below it.
const reflections = [_][2][]const u8{
    .{ "i'm", "you are" },
    .{ "i'd", "you would" },
    .{ "i've", "you have" },
    .{ "i'll", "you will" },
    .{ "i", "you" },
    .{ "me", "you" },
    .{ "my", "your" },
    .{ "mine", "yours" },
    .{ "myself", "yourself" },
    .{ "am", "are" },
    .{ "was", "were" },
    .{ "you're", "I am" },
    .{ "you've", "I have" },
    .{ "you'll", "I will" },
    .{ "your", "my" },
    .{ "yours", "mine" },
    .{ "yourself", "myself" },
    .{ "you", "me" },
};

/// What the doctor says back.
///
/// `nth` is how many times the person has spoken, which decides which of a
/// rule's replies comes back. The ledger already knows it, so nothing here has
/// to be remembered between calls.
pub fn reply(arena: Allocator, said: []const u8, nth: usize) ![]const u8 {
    const text = std.mem.trim(u8, said, " \t\r\n");
    if (text.len == 0) return opening;

    for (rules) |rule| {
        const at = wordIndex(text, rule.keyword) orelse continue;
        const rest = try reflect(arena, tail(text, at + rule.keyword.len));
        const template = pick(rule.replies, rest, nth) orelse continue;
        return fill(arena, template, rest);
    }
    return anything[nth % anything.len];
}

/// Where a keyword occurs as whole words. An apostrophe is part of a word, so
/// `i` does not match inside `i'm` and there is a rule for each.
fn wordIndex(haystack: []const u8, needle: []const u8) ?usize {
    var at: usize = 0;
    while (std.ascii.findIgnoreCasePos(haystack, at, needle)) |i| {
        const end = i + needle.len;
        const before = i == 0 or !isWord(haystack[i - 1]);
        const after = end == haystack.len or !isWord(haystack[end]);
        if (before and after) return i;
        at = i + 1;
    }
    return null;
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '\'';
}

/// What followed the keyword, to the end of that thought. Punctuation ends it,
/// the way it ends one in the original: what comes after is a separate thing
/// to say and has no business inside this sentence.
fn tail(said: []const u8, from: usize) []const u8 {
    const rest = said[from..];
    const stop = std.mem.indexOfAny(u8, rest, ".,;:!?") orelse rest.len;
    return std.mem.trim(u8, rest[0..stop], " \t\r\n");
}

fn reflect(arena: Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var words = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var first = true;
    while (words.next()) |word| {
        if (!first) try out.append(arena, ' ');
        first = false;
        try out.appendSlice(arena, turned(word) orelse word);
    }
    return out.items;
}

fn turned(word: []const u8) ?[]const u8 {
    for (reflections) |r| if (std.ascii.eqlIgnoreCase(word, r[0])) return r[1];
    return null;
}

/// The reply this many turns in, passing over any that wants something after
/// the keyword when there was nothing after it.
fn pick(replies: []const []const u8, rest: []const u8, nth: usize) ?[]const u8 {
    for (0..replies.len) |i| {
        const r = replies[(nth + i) % replies.len];
        if (rest.len > 0 or std.mem.indexOf(u8, r, "{}") == null) return r;
    }
    return null;
}

fn fill(arena: Allocator, template: []const u8, rest: []const u8) ![]const u8 {
    const at = std.mem.indexOf(u8, template, "{}") orelse return template;
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{
        template[0..at],
        rest,
        template[at + 2 ..],
    });
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a keyword is answered with what followed it, turned around" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    try testing.expectEqualStrings(
        "Why do you need a holiday?",
        try reply(arena, "I need a holiday", 0),
    );
    // The pronouns are turned around, so what was said about themselves is
    // said back to them.
    try testing.expectEqualStrings(
        "Did you come to me because you are worried about your work?",
        try reply(arena, "I am worried about my work", 0),
    );
    // Punctuation ends the thought: what comes after it is a separate one.
    try testing.expectEqualStrings(
        "Why do you need a break?",
        try reply(arena, "I need a break, badly.", 0),
    );
    // Case is ignored, and the case of what was said is kept.
    try testing.expectEqualStrings(
        "Why do you say your Ferrari?",
        try reply(arena, "MY Ferrari", 0),
    );
}

test "the first rule that matches wins, so a specific one comes first" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // `i am` is above `my`, which is above `you`.
    try testing.expectEqualStrings(
        "Did you come to me because you are tired of your job?",
        try reply(arena, "I am tired of my job", 0),
    );
    // A keyword is whole words: `no` is not in `nothing`, and `i` is not in
    // `i'm`, which has a rule of its own.
    try testing.expectEqualStrings(
        "Did you come to me because you are nothing to you?",
        try reply(arena, "I'm nothing to me", 0),
    );
}

test "nothing recognised is still an answer, and it moves on" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const first = try reply(arena, "The rain in Spain.", 0);
    const second = try reply(arena, "The rain in Spain.", 1);
    try testing.expect(first.len > 0);
    try testing.expect(!std.mem.eql(u8, first, second));

    // Saying nothing at all is the one thing that opens rather than answers.
    try testing.expectEqualStrings(opening, try reply(arena, "   \n ", 3));
}

test "how many times you have spoken is the whole of its memory" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // The same thing said at the same point in a conversation is answered
    // the same way: no state, no randomness, so a test can hold it.
    for (0..8) |n| try testing.expectEqualStrings(
        try reply(arena, "I feel stuck", n),
        try reply(arena, "I feel stuck", n),
    );
    // And it does not say the same thing twice running.
    try testing.expect(!std.mem.eql(
        u8,
        try reply(arena, "I feel stuck", 0),
        try reply(arena, "I feel stuck", 1),
    ));
}

test "a reply wanting what came after the keyword is passed over when nothing did" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    // `i feel` with nothing after it cannot be answered by a reply holding
    // `{}`, so one that does not is used instead.
    for (0..6) |n| {
        const said = try reply(arena, "I feel", n);
        try testing.expect(std.mem.indexOf(u8, said, "{}") == null);
        try testing.expect(said.len > 0);
    }
}

test "every rule is reachable and every reply is well formed" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    for (rules) |rule| {
        try testing.expect(rule.keyword.len > 0);
        try testing.expect(rule.replies.len > 0);
        // A keyword nothing can reach is a rule that never runs: every one
        // of them has to be the first match for the keyword said alone.
        const said = try std.fmt.allocPrint(arena, "{s} something", .{rule.keyword});
        try testing.expect(wordIndex(said, rule.keyword) != null);
        for (rules) |above| {
            if (std.mem.eql(u8, above.keyword, rule.keyword)) break;
            try testing.expect(wordIndex(said, above.keyword) == null);
        }
        // At most one hole, since only the first is filled.
        for (rule.replies) |r| {
            try testing.expect(r.len > 0);
            if (std.mem.indexOf(u8, r, "{}")) |at|
                try testing.expect(std.mem.indexOf(u8, r[at + 2 ..], "{}") == null);
        }
    }
    for (anything) |r| try testing.expect(std.mem.indexOf(u8, r, "{}") == null);
}
