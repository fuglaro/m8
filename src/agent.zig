//! Turning an agent definition into the few facts a request needs.
//!
//! A definition is an m8 document. 🧠 names whatever this one is built from —
//! an agent, a model, a skill, or a parent turn — and naming it is how it gets
//! used. A name is a path, so its folder component is the mob it lives in, and
//! a saved conversation is an ordinary agent in the `=` namespace. Resuming
//! and invoking are one thing.
//!
//! Nothing declares its own name. A file is what it is called.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");
const doc = @import("m8/doc.zig");
const session = @import("session.zig");

pub const max_depth = 8;

pub const Error = error{
    UnknownAgent,
    NoModel,
    IncludeTooDeep,
};

/// Stated explicitly because `load` and `resolve` are mutually recursive, and
/// an inferred set cannot close over itself.
pub const LoadError = Error || doc.ParseError;

pub const Definition = struct {
    name: []const u8,
    provider: []const u8 = "",
    model: []const u8 = "",
    /// Every 💻 record, in the order reached. Includes come first, so an
    /// including agent's own words end up last.
    system: []const u8 = "",
    /// 🙋 and 🤖 records gathered along the way, ancestors first. Empty for a
    /// plain agent; a conversation for anything in `=`.
    turns: []const doc.Record = &.{},
    /// The agent this conversation is with — the first authored name in the
    /// lineage, skipping the generated `=` and `+` namespaces. Empty only if
    /// the whole chain was generated, which cannot happen in practice.
    origin: []const u8 = "",
};

pub fn load(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    depth: u8,
) LoadError!Definition {
    if (depth > max_depth) return Error.IncludeTooDeep;

    const file = try std.fmt.allocPrint(arena, "{s}.md", .{name});
    const src = (try config.read(arena, io, dirs, file)) orelse return Error.UnknownAgent;

    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(arena, src, &diag);

    var def: Definition = .{
        .name = name,
        // An authored name is its own origin and never inherits one; a
        // generated one takes the origin of whatever it continues.
        .origin = if (session.isGenerated(name)) "" else name,
    };
    var system: std.ArrayList(u8) = .empty;
    var turns: std.ArrayList(doc.Record) = .empty;

    for (records) |r| switch (r.sigil) {
        .agent => {
            const inner = try resolve(arena, io, dirs, r.value, depth + 1);
            switch (inner) {
                .model => |m| {
                    if (def.model.len == 0) {
                        def.provider = m.provider;
                        def.model = m.model;
                    }
                },
                .document => |d| {
                    if (def.origin.len == 0) def.origin = d.origin;
                    if (def.model.len == 0) {
                        def.provider = d.provider;
                        def.model = d.model;
                    }
                    if (d.system.len > 0) {
                        if (system.items.len > 0) try system.append(arena, '\n');
                        try system.appendSlice(arena, d.system);
                    }
                    try turns.appendSlice(arena, d.turns);
                },
            }
        },

        .system => {
            if (system.items.len > 0) try system.append(arena, '\n');
            try system.appendSlice(arena, r.content orelse "");
        },

        .user, .bot => try turns.append(arena, r),

        else => {},
    };

    if (def.model.len == 0) return Error.NoModel;
    def.system = system.items;
    def.turns = turns.items;
    return def;
}

const Target = union(enum) {
    document: Definition,
    model: struct { provider: []const u8, model: []const u8 },
};

/// What a 🧠 names. Both `+/tduyxbutjb` and `local/Bonsai-8B` carry a slash, so the
/// slash cannot decide: a name that resolves to a document in the config path
/// is a document, and anything else is provider/model.
fn resolve(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    spec: []const u8,
    depth: u8,
) LoadError!Target {
    if (load(arena, io, dirs, spec, depth)) |d| {
        return .{ .document = d };
    } else |e| switch (e) {
        error.UnknownAgent => {},
        else => return e,
    }
    const slash = std.mem.indexOfScalar(u8, spec, '/') orelse return Error.UnknownAgent;
    return .{ .model = .{ .provider = spec[0..slash], .model = spec[slash + 1 ..] } };
}
