//! The tool contract: what every tool is handed, and what it may talk to.
//!
//! A tool is a filter over an m8 stream: it reads a document on stdin and
//! writes one on stdout. Anything it says to the *person* goes to the
//! terminal instead, on its own channel, so a tool that opens a UI is still
//! a legal member of a pipeline:
//!
//!     m8 >ask "which model?" < session.m8 | m8 >cat
//!
//! Keeping interaction off stdout is the whole reason this works. A tool that
//! printed its prompt to stdout would corrupt every downstream reader.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Ctx = struct {
    arena: Allocator,
    io: std.Io,
    /// Arguments after the tool name.
    args: []const []const u8,
    /// The incoming document. Empty when nothing was piped in.
    ///
    /// Read whole for now. Tools that only ever append are the reason this
    /// wants to become a streaming reader later; the contract does not change
    /// when it does.
    in: []const u8,
    /// The outgoing document.
    out: *std.Io.Writer,
    /// The person, when there is one. Null under a pipe or in a script, which
    /// is the signal to run non-interactively rather than to fail.
    tty: ?Tty,
};

/// The interaction channel. Separate from `in`/`out` by construction.
pub const Tty = struct {
    r: *std.Io.Reader,
    w: *std.Io.Writer,

    pub fn prompt(t: Tty, comptime fmt: []const u8, args: anytype) !void {
        try t.w.print(fmt, args);
        try t.w.flush();
    }

    pub fn line(t: Tty) !?[]const u8 {
        const got = t.r.takeDelimiterInclusive('\n') catch |e| switch (e) {
            error.EndOfStream => return null,
            else => return e,
        };
        return std.mem.trimEnd(u8, got, "\r\n");
    }
};

pub const Tool = struct {
    name: []const u8,
    summary: []const u8,
    run: *const fn (Ctx) anyerror!void,
};
