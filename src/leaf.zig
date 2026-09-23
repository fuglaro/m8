//! The root of a split-out command: one binary that is one command.
//!
//! Which command is a build option rather than a file per program, so adding a
//! command to the registry adds a binary to the split set and there is no
//! second list to keep in step. The lookup is comptime, so the command this
//! binary is, is the only implementation it carries.

const std = @import("std");
const command = @import("command.zig");
const harness = @import("harness.zig");

/// The path, spelled the way a command line spells it: `call munge read`.
const which = @import("build_options").command;

pub fn main(init: std.process.Init) !u8 {
    const path = comptime command.words(which);
    return harness.leaf(
        init,
        comptime command.commandAt(path) orelse @compileError("no command at '" ++ which ++ "'"),
        which,
    );
}
