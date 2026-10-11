//! Keeping a run as it goes.
//!
//! A run is tagged a piece at a time, so the address moves with every model
//! call and every tool call rather than once at the end. Each piece is a turn
//! naming the one before it, which is all a chat ever was — and a run that
//! dies keeps everything up to where it died.
//!
//! Shared by the `@` prompt and `m8 query`, which are the two things that run
//! and keep in one process. What differs between them is only what moves.

const std = @import("std");
const doc = @import("m8/doc.zig");
const address = @import("address.zig");
const converse = @import("converse.zig");

pub const Keeping = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    dirs: []const []const u8,
    a: address.Address,
    moving: address.Moving,
    /// Where every piece of this run is kept: each continues the one before
    /// it, so the folder the first goes in is the folder they all do.
    home: []const u8,
    last: ?[]const u8 = null,

    pub fn keeper(self: *Keeping) converse.Keeper {
        return .{ .ctx = self, .home = self.home, .keep = keep };
    }

    fn keep(ctx: *anyopaque, piece: []const doc.Record) anyerror![]const u8 {
        const self: *Keeping = @ptrCast(@alignCast(ctx));
        const name = try address.tag(self.arena, self.io, self.dirs, self.a, piece, self.moving);
        self.last = name;
        return name;
    }

    /// The turn the run ended on. A run that added nothing was handed
    /// nothing to keep, and what was said to it is still a turn.
    pub fn finish(self: *Keeping, turn: []const doc.Record) ![]const u8 {
        return self.last orelse address.tag(self.arena, self.io, self.dirs, self.a, turn, self.moving);
    }
};
