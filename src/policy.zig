//! What may come back from a model, and from a tool.
//!
//! A model produces a reply and some calls; a tool produces a result. Neither
//! produces *definitions*. Keeping that as a rule stated in one place — rather
//! than as a happy consequence of how the data currently flows — is what stops
//! a later change quietly making a reply able to grant itself a tool.
//!
//! The reply side is closed and always has been: 🤖 💭 🔏 📲 and its 📦, and
//! nothing else, whatever any lock says. `freeze-toolbox` governs only the
//! tool-response channel, which is the one that has a reason to be opened.

const std = @import("std");
const sigil = @import("m8/sigil.zig");
const Sigil = sigil.Sigil;

/// Honoured from a model's own output. Not a lock: there is no setting that
/// widens this, because a reply granting itself a tool is never a feature.
pub fn fromModel(s: Sigil) bool {
    return switch (s) {
        .bot, .thought, .signature, .call, .package => true,
        else => false,
    };
}

/// Honoured from a tool's response.
///
/// A tool answers with 🧾 as it speaks and 🟢 or 🚫 when it stops. It may also
/// hand back definitions — that is
/// how a toolmaker works — and `freeze-toolbox` is what closes that door.
/// Including an agent or a skill *is* a way to acquire a toolbox, so 🧠 and 📚
/// are on the same side of it as 🧰 and 🔓 rather than being resolved to see
/// whether they happen to carry one.
pub fn fromTool(s: Sigil, is_frozen: bool) bool {
    return switch (s) {
        .result, .ok, .failed => true,
        .tool, .allow, .agent, .skill => !is_frozen,
        else => false,
    };
}

pub fn frozen(locks: []const []const u8) bool {
    for (locks) |l| {
        if (std.mem.eql(u8, l, "freeze-toolbox")) return true;
        if (std.mem.eql(u8, l, "sandbox")) return true;
        if (std.mem.eql(u8, l, "jail")) return true;
    }
    return false;
}

/// The first sigil in `records` that this source may not produce.
pub fn refuse(records: []const @import("m8/doc.zig").Record, allowed: *const fn (Sigil) bool) ?Sigil {
    for (records) |r| if (!allowed(r.sigil)) return r.sigil;
    return null;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "a model may not produce a definition, whatever the locks" {
    for ([_]Sigil{ .tool, .allow, .agent, .skill, .system, .lock, .command }) |s|
        try testing.expect(!fromModel(s));
    for ([_]Sigil{ .bot, .thought, .signature, .call, .package }) |s|
        try testing.expect(fromModel(s));
}

test "a tool answers freely, and hands back definitions only when not frozen" {
    for ([_]Sigil{ .result, .ok, .failed }) |s| {
        try testing.expect(fromTool(s, false));
        try testing.expect(fromTool(s, true));
    }
    for ([_]Sigil{ .tool, .allow, .agent, .skill }) |s| {
        try testing.expect(fromTool(s, false));
        try testing.expect(!fromTool(s, true));
    }
    // Never, either way: a tool does not speak as the model or the person.
    for ([_]Sigil{ .bot, .user, .system }) |s| {
        try testing.expect(!fromTool(s, false));
        try testing.expect(!fromTool(s, true));
    }
}

test "the levels that include freeze-toolbox imply it" {
    try testing.expect(frozen(&.{"freeze-toolbox"}));
    try testing.expect(frozen(&.{"sandbox"}));
    try testing.expect(frozen(&.{"jail"}));
    try testing.expect(!frozen(&.{"airgap"}));
    try testing.expect(!frozen(&.{}));
}

test "refuse names the first thing that does not belong" {
    const doc = @import("m8/doc.zig");
    const records = [_]doc.Record{
        .{ .sigil = .result, .value = "c1" },
        .{ .sigil = .tool, .value = "evil" },
    };
    try testing.expectEqual(@as(?Sigil, null), refuse(&records, fromTool0));
    try testing.expectEqual(@as(?Sigil, .tool), refuse(&records, fromToolFrozen));
}

fn fromTool0(s: Sigil) bool {
    return fromTool(s, false);
}
fn fromToolFrozen(s: Sigil) bool {
    return fromTool(s, true);
}
