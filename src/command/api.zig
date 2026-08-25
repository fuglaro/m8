//! The command contract: what every command is handed, and what it may talk to.
//!
//! Most commands are filters over an m8 stream: they read a document on stdin
//! and write one on stdout. Anything said to the *person* goes to the terminal
//! instead, on its own channel, so a command that opens a UI is still a legal
//! member of a pipeline:
//!
//!     m8 ask "which model?" < session.md | m8 cat
//!
//! Keeping interaction off stdout is the whole reason this works. A command
//! that printed its prompt to stdout would corrupt every downstream reader.

const std = @import("std");
const Allocator = std.mem.Allocator;
const doc = @import("../m8/doc.zig");

pub const Ctx = struct {
    arena: Allocator,
    io: std.Io,
    /// The spelling to write in. Rendered for a terminal, markdown otherwise,
    /// which is the same choice every m8 writer makes.
    mode: doc.Mode,
    /// The environment, for a command that spawns something.
    env: *const std.process.Environ.Map,
    /// Arguments after the command name.
    args: []const []const u8,
    /// The incoming document. Empty when nothing was piped in.
    ///
    /// Read whole for now. Commands that only ever append are the reason this
    /// wants to become a streaming reader later; the contract does not change
    /// when it does.
    in: []const u8,
    /// The outgoing document.
    out: *std.Io.Writer,
    /// Diagnostics and help. Never part of the document, always visible, and
    /// unlike `tty` it is there even under a pipe.
    err: *std.Io.Writer,
    /// The person, when there is one, for anything that needs an answer back.
    /// Null under a pipe or in a script, which is the signal to run
    /// non-interactively rather than to fail.
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

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    /// Whether `in` is filled before the command runs. False for anything that
    /// hands stdin to something else: reading it here would swallow the very
    /// bytes the child is waiting for.
    reads: bool = true,
    /// The exit status. A filter returns 0; `call` returns whatever it ran.
    run: *const fn (Ctx) anyerror!u8,
};

/// Read the incoming document.
///
/// A terminal on stdin means there is no incoming document — nobody pipes a
/// conversation in by hand — so it reads as empty. Waiting for an EOF the
/// terminal will never send just hangs.
pub fn readDocument(io: std.Io, arena: Allocator, buf: []u8) ![]const u8 {
    const in = std.Io.File.stdin();
    if (try in.isTty(io)) return "";
    var r = in.readerStreaming(io, buf);
    return r.interface.allocRemaining(arena, .unlimited);
}
