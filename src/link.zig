//! Handing over what a 🔗 names.
//!
//! A 🔗 hands over files beside what a tool said. Its value is the call it
//! answers, as a 🧾's is, and each line of its block that opens with `<` names
//! a file. What the rest of that line says is between the tool that wrote it
//! and the provider entry's `upload`: m8 reads none of it.
//!
//! `encode` runs `upload` for every such line before a codec sees the ledger,
//! and writes what it said over the line, for the codec to read.

const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("config.zig");
const doc = @import("m8/doc.zig");

/// What opens a line naming a file.
pub const file_lead = "<";

/// What opens the line a file is handed over as, in place of the one naming
/// it: `>MIME URI NAME`, as `upload` said it.
pub const hand_lead = ">";

/// Larger than any file an api takes whole, as base64, and small enough to hold.
pub const max_said = 64 * 1024 * 1024;

/// The entry's command that says how a file reaches the api.
pub const upload_var = "M8_PROVIDER_UPLOAD";

pub const Error = error{
    /// A 🔗 with no `upload` to hand its files over.
    NoUpload,
    /// An `upload` that failed, or said no `MIME URI`.
    UploadFailed,
};

/// The ledger, with every file its 🔗s name handed over by the entry's
/// `upload`, when it has one. Without one the ledger is as it was, and a
/// codec that meets a file is the one to refuse it.
pub fn handOver(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    env: *const std.process.Environ.Map,
    records: []const doc.Record,
) ![]const doc.Record {
    const cmd = env.get(upload_var) orelse return records;
    const out = try arena.dupe(doc.Record, records);
    for (out) |*r| {
        if (r.sigil != .link) continue;
        var text: std.ArrayList(u8) = .empty;
        var lines = std.mem.splitScalar(u8, r.content orelse "", '\n');
        while (lines.next()) |line| {
            if (std.mem.cutPrefix(u8, line, file_lead)) |named| {
                try text.print(arena, "{s}{s}\n", .{ hand_lead, try upload(arena, io, dirs, env, cmd, named) });
            } else {
                try text.print(arena, "{s}\n", .{line});
            }
        }
        r.content = text.items[0 .. text.items.len - 1];
    }
    return out;
}

/// What `cmd` says of the file a 🔗 line names. It runs with the line as
/// `$1`, and the config directory m8 keeps things in as `$2`. What it says
/// on stderr is passed on.
fn upload(
    arena: Allocator,
    io: std.Io,
    dirs: []const []const u8,
    env: *const std.process.Environ.Map,
    cmd: []const u8,
    named: []const u8,
) ![]const u8 {
    var child = try std.process.spawn(io, .{
        .argv = &.{ "sh", "-c", cmd, "m8 upload", named, config.saveDir(dirs) orelse "" },
        .environ_map = env,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .inherit,
    });
    var buf: [4096]u8 = undefined;
    var r = child.stdout.?.reader(io, &buf);
    const said = try r.interface.allocRemaining(arena, .limited(max_said));
    switch (try child.wait(io)) {
        .exited => |code| if (code != 0) return Error.UploadFailed,
        else => return Error.UploadFailed,
    }
    const line = std.mem.trim(u8, said, " \t\r\n");
    if (std.mem.indexOfScalar(u8, line, ' ') == null) return Error.UploadFailed;
    return line;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// A 🔗 with `content`, after the hand-over, with `cmd` as the entry's `upload`.
fn testHand(arena: Allocator, io: std.Io, cmd: ?[]const u8, content: []const u8) ![]const u8 {
    var env: std.process.Environ.Map = .init(arena);
    if (cmd) |c| try env.put(upload_var, c);
    const records = [_]doc.Record{.{ .sigil = .link, .value = "c1", .content = content }};
    const got = try handOver(arena, io, &.{"/kept"}, &env, &records);
    return got[0].content.?;
}

test "a 🔗's files are handed over as the entry's upload says" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();
    const io = threaded.io();

    // The line goes as it was written, and the config directory comes second.
    try testing.expectEqualStrings(
        ">image/jpeg ref:ab:shot.jpeg /kept\nlater\n>image/jpeg ref:cd:+/x.pdf /kept",
        try testHand(arena, io, "printf 'image/jpeg ref:%s %s' \"$1\" \"$2\"", "<ab:shot.jpeg\nlater\n<cd:+/x.pdf"),
    );

    // Without an upload nothing is handed over, for a codec to refuse.
    try testing.expectEqualStrings("<a.jpeg", try testHand(arena, io, null, "<a.jpeg"));

    try testing.expectError(error.UploadFailed, testHand(arena, io, "exit 1", "<a.jpeg"));
    try testing.expectError(error.UploadFailed, testHand(arena, io, "echo file-1", "<a.jpeg"));
}
