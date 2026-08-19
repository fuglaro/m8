//! Turning an agent definition into the few facts a request needs.
//!
//! A definition is an m8 document. 📖 either names a model as
//! `provider/model`, or names another agent, whose system prompt and model
//! are injected into this one.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");
const doc = @import("m8/doc.zig");

pub const max_depth = 8;

pub const Error = error{
    UnknownAgent,
    NoModel,
    IncludeTooDeep,
};

pub const Definition = struct {
    name: []const u8,
    provider: []const u8 = "",
    model: []const u8 = "",
    /// Every 💻 record, in the order they were reached. Includes come first,
    /// so an including agent's own words end up last.
    system: []const u8 = "",
};

pub fn load(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    name: []const u8,
    depth: u8,
) !Definition {
    if (depth > max_depth) return Error.IncludeTooDeep;

    const file = try std.fmt.allocPrint(arena, "{s}.m8", .{name});
    const src = (try config.read(arena, io, dirs, file)) orelse return Error.UnknownAgent;

    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(arena, src, &diag);

    var def: Definition = .{ .name = name };
    var system: std.ArrayList(u8) = .empty;

    for (records) |r| switch (r.sigil) {
        .agent => def.name = r.body(),
        .include => {
            const spec = r.body();
            if (std.mem.indexOfScalar(u8, spec, '/')) |slash| {
                def.provider = spec[0..slash];
                def.model = spec[slash + 1 ..];
            } else {
                const inner = try load(arena, io, dirs, spec, depth + 1);
                if (def.model.len == 0) {
                    def.provider = inner.provider;
                    def.model = inner.model;
                }
                if (inner.system.len > 0) {
                    if (system.items.len > 0) try system.append(arena, '\n');
                    try system.appendSlice(arena, inner.system);
                }
            }
        },
        .system => {
            if (system.items.len > 0) try system.append(arena, '\n');
            try system.appendSlice(arena, r.body());
        },
        else => {},
    };

    if (def.model.len == 0) return Error.NoModel;
    def.system = system.items;
    return def;
}
