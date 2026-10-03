//! Root module for the complete project test suite.

comptime {
    _ = @import("main.zig");
    _ = @import("m8/sigil.zig");
    _ = @import("m8/markdown.zig");
    _ = @import("m8/doc.zig");
    _ = @import("m8/model.zig");
    _ = @import("session.zig");
    _ = @import("sandbox.zig");
    _ = @import("toolbox.zig");
    _ = @import("shield.zig");
    _ = @import("provider.zig");
    _ = @import("agent.zig");
    _ = @import("ledger.zig");
    _ = @import("assembly.zig");
    _ = @import("codec.zig");
    _ = @import("config.zig");
    _ = @import("command.zig");
    _ = @import("launch.zig");
    _ = @import("address.zig");
    _ = @import("prompt.zig");
    _ = @import("zmachine/zmachine.zig");
}
