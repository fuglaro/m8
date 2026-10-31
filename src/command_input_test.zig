//! Small fixture for raw-input filters; no launcher, subprocess, or user config.
const std = @import("std");
const api = @import("api.zig");
const config = @import("config.zig");

pub const Invocation = struct {
    arena: std.heap.ArenaAllocator,
    env: std.process.Environ.Map,
    out: std.Io.Writer.Allocating,
    err: std.Io.Writer.Allocating,

    pub fn init() !Invocation {
        var env: std.process.Environ.Map = .init(std.testing.allocator);
        errdefer env.deinit();
        try env.put(config.dirs_var, "");
        try env.put(config.user_root_var, "");
        try env.put(config.data_root_var, "");
        try env.put("COLUMNS", "80");
        return .{
            .arena = .init(std.testing.allocator),
            .env = env,
            .out = .init(std.testing.allocator),
            .err = .init(std.testing.allocator),
        };
    }

    pub fn deinit(self: *Invocation) void {
        self.err.deinit();
        self.out.deinit();
        self.env.deinit();
        self.arena.deinit();
    }

    pub fn ctx(self: *Invocation, args: []const []const u8, input: ?*std.Io.Reader) api.Ctx {
        return .{
            .arena = self.arena.allocator(),
            .io = std.testing.io,
            .mode = .md,
            .env = &self.env,
            .args = args,
            .stdin = input,
            .in = "",
            .out = &self.out.writer,
            .err = &self.err.writer,
            .tty = null,
        };
    }
};
