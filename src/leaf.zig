//! The root of a command built on its own: one binary that is one command.
//!
//! Which command is a build option rather than a file per program, so there
//! is no second list to keep in step with the registry. The lookup is
//! comptime, so the command this binary is, is the only implementation it
//! carries.

const std = @import("std");
const command = @import("command.zig");
const harness = @import("harness.zig");

/// The command's name.
const which = @import("build_options").command;

pub fn main(init: std.process.Init) !u8 {
    return harness.leaf(
        init,
        comptime command.commandAt(which) orelse @compileError("no command at '" ++ which ++ "'"),
        which,
    );
}
