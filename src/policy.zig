//! What may come back from a model, and from a tool.
//!
//! A model produces a reply and some calls; a tool produces a result. Neither
//! produces *definitions*. Keeping that as a rule stated in one place — rather
//! than as a happy consequence of how the data currently flows — is what stops
//! a later change quietly making a reply able to grant itself a tool.
//!
//! The reply side is closed and always has been: 🤖 💭 🔏 and 📲, and nothing
//! else, whatever any shield says. `freeze-toolbox` governs only the
//! tool-response channel, which is the one that has a reason to be opened.

const std = @import("std");
const sigil = @import("m8/sigil.zig");
const Sigil = sigil.Sigil;

/// Honoured from a model's own output. Not a restriction: there is no setting
/// that widens this, because a reply granting itself a tool is never a feature.
pub fn fromModel(s: Sigil) bool {
    return switch (s) {
        .bot, .thought, .signature, .call => true,
        else => false,
    };
}

/// Honoured from a tool's response.
///
/// A tool answers with 🧾 as it speaks, 🔗 for files it hands over, and 🟢 or
/// 🚫 when it stops. It may also hand back definitions — that is how a
/// toolmaker works.
///
/// Closing that door is a 🛡 rather than a rule here. `freeze-toolbox` names
/// every sigil that opens it, so what is closed is written down in the
/// language and can be read, composed, or taken apart. Including an agent or a
/// skill *is* a way to acquire a toolbox, which is why that shield names 🧠 and
/// 📚 alongside 🧰 rather than resolving them to see what they carry.
pub fn fromTool(s: Sigil) bool {
    return switch (s) {
        .result, .scroll, .link, .ok, .failed => true,
        .tool, .agent, .skill => true,
        else => false,
    };
}

/// The first sigil in `records` that this source may not produce.
pub fn refuse(records: []const @import("m8/doc.zig").Record, allowed: *const fn (Sigil) bool) ?Sigil {
    for (records) |r| if (!allowed(r.sigil)) return r.sigil;
    return null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a model may not produce a definition, whatever the shields" {
    for ([_]Sigil{ .tool, .agent, .skill, .system, .shield, .runner }) |s|
        try testing.expect(!fromModel(s));
    for ([_]Sigil{ .bot, .thought, .signature, .call }) |s|
        try testing.expect(fromModel(s));
}

test "a tool answers, and may hand back definitions for a shield to take away" {
    for ([_]Sigil{ .result, .scroll, .link, .ok, .failed, .tool, .agent, .skill }) |s|
        try testing.expect(fromTool(s));
    // Never: a tool does not speak as the model or as the person, and no
    // shield opens that — it is not a door.
    for ([_]Sigil{ .bot, .user, .system }) |s|
        try testing.expect(!fromTool(s));
}

test "refuse names the first thing that does not belong" {
    const doc = @import("m8/doc.zig");
    const ok = [_]doc.Record{
        .{ .sigil = .result, .value = "c1" },
        .{ .sigil = .tool, .value = "made" },
    };
    try testing.expectEqual(@as(?Sigil, null), refuse(&ok, fromTool));

    // A reply is the closed side, and nothing widens it.
    const said = [_]doc.Record{.{ .sigil = .tool, .value = "evil" }};
    try testing.expectEqual(@as(?Sigil, .tool), refuse(&said, fromModel));
}
