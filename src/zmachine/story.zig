//! The story file: bytes, header, and the profile written over it.
//!
//! A story file is three regions in one array. Dynamic memory runs from zero
//! to the static base and is the only part a game may write; static memory
//! holds tables it may only read; high memory holds routines and strings, and
//! is reached through packed addresses rather than directly. The split is
//! declared in the header, which sits in the first sixty-four bytes and is
//! read by both sides — the game asks what the interpreter can do, and the
//! interpreter answers by writing bytes into it before execution begins.
//!
//! Those answers are the headless profile, and they are the whole
//! of what makes this interpreter headless: no colours, no pictures, no sound,
//! no timed input, eighty columns and a screen of infinite height. A game
//! reads them and takes the quiet path of its own accord — nothing is refused
//! at the opcode level that was already denied here.
//!
//! `restart` re-applies them, which is why applying them is a function rather
//! than a stretch of boot code. A game that restarts into stale capabilities
//! would be a different world from the one the ledger recorded, and it would
//! be a different world only sometimes, which is worse.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    TooShort,
    UnsupportedVersion,
    BadAddress,
};

/// Where each header field lives. Named rather than numbered at the call site,
/// because a hex offset says nothing about what it holds.
pub const h = struct {
    pub const version = 0x00;
    pub const flags1 = 0x01;
    pub const release = 0x02;
    pub const high_base = 0x04;
    pub const initial_pc = 0x06;
    pub const dictionary = 0x08;
    pub const objects = 0x0A;
    pub const globals = 0x0C;
    pub const static_base = 0x0E;
    pub const flags2 = 0x10;
    pub const serial = 0x12;
    pub const abbreviations = 0x18;
    pub const file_length = 0x1A;
    pub const checksum = 0x1C;
    pub const interpreter_number = 0x1E;
    pub const interpreter_version = 0x1F;
    pub const screen_height = 0x20;
    pub const screen_width = 0x21;
    pub const screen_width_units = 0x22;
    pub const screen_height_units = 0x24;
    pub const font_width = 0x26;
    pub const font_height = 0x27;
    pub const background = 0x2C;
    pub const foreground = 0x2D;
    pub const terminating = 0x2E;
    pub const stream3_width = 0x30;
    pub const revision_major = 0x32;
    pub const revision_minor = 0x33;
    pub const alphabet = 0x34;
    pub const extension = 0x36;
};

/// The header is sixty-four bytes, and nothing shorter is a story file.
pub const header_len = 0x40;

/// What the headless profile pins. Gathered here so it is one thing to read
/// rather than a scatter of writes, and so a test can assert what a game sees.
pub const profile = struct {
    /// 6 is the IBM PC, which is the least likely to be special-cased by a
    /// game that special-cases interpreters at all.
    pub const interpreter_number = 6;
    pub const interpreter_version_letter = 'F';
    pub const interpreter_version_number = 1;
    /// 255 lines is the spec's own word for infinite, and it is what stops a
    /// game paginating at a reader who cannot press a key to continue.
    pub const screen_height = 255;
    /// Eighty, and not infinite. A game told the screen is unbounded stops
    /// wrapping, and its output stops being diffable.
    pub const screen_width = 80;
    pub const font_width = 1;
    pub const font_height = 1;
    pub const background = 2;
    pub const foreground = 9;
    /// Standard 1.0 rather than 1.1: it declines `set_true_colour` and the 1.1
    /// header-extension additions without declining Unicode, which is 1.0.
    pub const revision_major = 1;
    pub const revision_minor = 0;
};

/// Flags 2 is the one header word both sides write, so two of its bits are
/// runtime state rather than capability: the game turns transcripting and
/// forced fixed-pitch on and off as it runs, and may read back what it set.
/// Those two survive a restart. Everything else in the word is a capability we
/// do not have, and is cleared whenever the profile is applied.
pub const flags2_transcript: u16 = 0x0001;
pub const flags2_fixed_pitch: u16 = 0x0002;
const flags2_kept = flags2_transcript | flags2_fixed_pitch;

pub const Story = struct {
    /// Live memory. Dynamic memory is written by the game; the rest is not,
    /// though the interpreter itself writes the header.
    mem: []u8,
    /// The file exactly as it arrived, for `restart` and for `verify`. The
    /// checksum is over this rather than over `mem`, since we have written the
    /// profile into `mem` and a game asking whether it is intact is asking
    /// about the file.
    original: []const u8,
    version: u8,
    static_base: u16,
    high_base: u16,

    pub fn load(arena: Allocator, bytes: []const u8) !Story {
        if (bytes.len < header_len) return Error.TooShort;
        const version = bytes[h.version];
        switch (version) {
            1, 2, 3, 4, 5, 8 => {},
            // V6 is the graphical machine and V7 is unused in the wild. Both
            // are out of scope, and saying so is better than running one
            // badly.
            else => return Error.UnsupportedVersion,
        }

        const mem = try arena.dupe(u8, bytes);
        const original = try arena.dupe(u8, bytes);

        var s: Story = .{
            .mem = mem,
            .original = original,
            .version = version,
            .static_base = std.mem.readInt(u16, bytes[h.static_base..][0..2], .big),
            .high_base = std.mem.readInt(u16, bytes[h.high_base..][0..2], .big),
        };
        if (s.static_base > mem.len) return Error.BadAddress;
        s.applyProfile();
        return s;
    }

    // ------------------------------------------------------------ memory

    pub fn byteAt(s: *const Story, addr: u32) u8 {
        // Reading past the end is a broken story file rather than a broken
        // interpreter, and answering zero keeps the failure inside the game
        // where its own diagnostics can see it.
        if (addr >= s.mem.len) return 0;
        return s.mem[addr];
    }

    pub fn wordAt(s: *const Story, addr: u32) u16 {
        if (addr + 1 >= s.mem.len) return 0;
        return std.mem.readInt(u16, s.mem[addr..][0..2], .big);
    }

    pub fn setByte(s: *Story, addr: u32, value: u8) void {
        if (addr >= s.mem.len) return;
        s.mem[addr] = value;
    }

    pub fn setWord(s: *Story, addr: u32, value: u16) void {
        if (addr + 1 >= s.mem.len) return;
        std.mem.writeInt(u16, s.mem[addr..][0..2], value, .big);
    }

    // ------------------------------------------------------- header reads

    pub fn release(s: *const Story) u16 {
        return s.wordAt(h.release);
    }

    pub fn serial(s: *const Story) []const u8 {
        return s.original[h.serial..][0..6];
    }

    pub fn declaredChecksum(s: *const Story) u16 {
        return std.mem.readInt(u16, s.original[h.checksum..][0..2], .big);
    }

    /// The length the header declares, in bytes. Scaled by version, because
    /// the field is a word and the files outgrew it.
    pub fn declaredLength(s: *const Story) u32 {
        const raw: u32 = std.mem.readInt(u16, s.original[h.file_length..][0..2], .big);
        return raw * @as(u32, switch (s.version) {
            1, 2, 3 => 2,
            4, 5 => 4,
            else => 8,
        });
    }

    /// The checksum a game computes with `verify`: every byte after the header
    /// summed, modulo 65536, over the file as it arrived.
    pub fn checksum(s: *const Story) u16 {
        const declared = s.declaredLength();
        const end = @min(if (declared == 0) s.original.len else declared, s.original.len);
        var sum: u16 = 0;
        for (s.original[@min(header_len, end)..end]) |b| sum +%= b;
        return sum;
    }

    pub fn globals(s: *const Story) u16 {
        return s.wordAt(h.globals);
    }

    pub fn objects(s: *const Story) u16 {
        return s.wordAt(h.objects);
    }

    pub fn dictionary(s: *const Story) u16 {
        return s.wordAt(h.dictionary);
    }

    pub fn abbreviations(s: *const Story) u16 {
        return s.wordAt(h.abbreviations);
    }

    pub fn alphabetTable(s: *const Story) u16 {
        return if (s.version >= 5) s.wordAt(h.alphabet) else 0;
    }

    pub fn extensionTable(s: *const Story) u16 {
        return if (s.version >= 5) s.wordAt(h.extension) else 0;
    }

    /// A word from the header extension table, or zero when the table is
    /// absent or too short to hold it. Entry 1 is the mouse X coordinate, 3
    /// the Unicode translation table, and the table declares its own length —
    /// so reading past what it declares is reading somebody else's memory.
    pub fn extensionWord(s: *const Story, entry: u16) u16 {
        const table = s.extensionTable();
        if (table == 0 or entry == 0) return 0;
        const declared = s.wordAt(table);
        if (entry > declared) return 0;
        return s.wordAt(table + @as(u32, entry) * 2);
    }

    pub fn terminatingTable(s: *const Story) u16 {
        return if (s.version >= 5) s.wordAt(h.terminating) else 0;
    }

    /// Whether the status line shows a clock rather than a score.
    ///
    /// Version 3 only, and read from the game's own flags rather than chosen
    /// by us. V1 and V2 have no clock games — Deadline was the first, and it
    /// was V3 — so the bit means nothing there and reading it would be reading
    /// whatever a 1980 compiler happened to leave behind.
    pub fn timeGame(s: *const Story) bool {
        return s.version == 3 and (s.mem[h.flags1] & 0x02) != 0;
    }

    pub fn transcripting(s: *const Story) bool {
        return (s.wordAt(h.flags2) & flags2_transcript) != 0;
    }

    // ------------------------------------------------------------ packing

    /// Where a packed address points. The multiplier is the version's, and V6
    /// and V7's offset fields are absent here because those versions are.
    pub fn unpack(s: *const Story, packed_addr: u16) u32 {
        const scale: u32 = switch (s.version) {
            1, 2, 3 => 2,
            4, 5 => 4,
            else => 8,
        };
        return @as(u32, packed_addr) * scale;
    }

    pub fn initialPc(s: *const Story) u32 {
        return s.wordAt(h.initial_pc);
    }

    // ------------------------------------------------------------ profile

    /// Write the profile's answers into the header.
    ///
    /// Called once at boot and again on every `restart`, which is the whole
    /// reason it is a function: a restarted game asks the same questions and
    /// must get the same answers, and the only way to be sure of that is for
    /// there to be one place the answers are written.
    pub fn applyProfile(s: *Story) void {
        const m = s.mem;
        if (s.version <= 3) {
            // Bit 1 is the game's own statement about its status line and bit
            // 2 is about its media, so both are read rather than written.
            // What we clear is what we cannot do: no Tandy censorship, no
            // screen splitting, no variable-pitch default — and a zero in bit
            // 4 says the status line *is* available, which is the one place a
            // cleared bit is a capability rather than the lack of one.
            m[h.flags1] &= ~@as(u8, 0b0111_1000);
        } else {
            // No colours, pictures, boldface, italics, sound or timed input.
            // Fixed-space is the one thing we do have, and saying so is what
            // lets a game lay out ASCII art and trust the result.
            m[h.flags1] &= ~@as(u8, 0b1010_1111);
            m[h.flags1] |= 0b0001_0000;
        }

        // Flags 2 keeps only what the game itself is entitled to have set.
        // Everything else in the word is a capability we do not have, and a
        // game that asked for one is answered by the bit going out again.
        const kept = s.wordAt(h.flags2) & flags2_kept;
        s.setWord(h.flags2, kept);

        m[h.interpreter_number] = profile.interpreter_number;
        m[h.interpreter_version] = if (s.version <= 3)
            profile.interpreter_version_number
        else
            profile.interpreter_version_letter;

        // The screen fields are V4+; in V1–3 those bytes belong to nobody and
        // writing them would be writing over a header the game never reads.
        if (s.version >= 4) {
            m[h.screen_height] = profile.screen_height;
            m[h.screen_width] = profile.screen_width;
        }
        if (s.version >= 5) {
            // Units and lines are the same scale because the font is one unit
            // by one unit, which is what keeps 0x20 and 0x24 from disagreeing.
            s.setWord(h.screen_width_units, profile.screen_width);
            s.setWord(h.screen_height_units, profile.screen_height);
            m[h.font_width] = profile.font_width;
            m[h.font_height] = profile.font_height;
            m[h.background] = profile.background;
            m[h.foreground] = profile.foreground;
        }
        if (s.version >= 4) {
            m[h.revision_major] = profile.revision_major;
            m[h.revision_minor] = profile.revision_minor;
        }
    }

    /// Reset to the file as it arrived and apply the profile again.
    ///
    /// Static and high memory were never writable, so only dynamic memory can
    /// have changed — but copying the whole file is simpler than copying part
    /// of it, and being simpler is worth more here than being clever. The two
    /// runtime bits of Flags 2 survive, because the standard says a restart
    /// keeps transcripting on if it was on: a player who asked for a
    /// transcript did not stop asking by restarting.
    pub fn restart(s: *Story) void {
        const kept = s.wordAt(h.flags2) & flags2_kept;
        @memcpy(s.mem, s.original);
        s.setWord(h.flags2, kept);
        s.applyProfile();
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// The smallest thing that is a story file: a header, a static base past it,
/// and enough room after that to point at.
pub fn blank(arena: Allocator, version: u8, len: usize) ![]u8 {
    const bytes = try arena.alloc(u8, @max(len, 0x100));
    @memset(bytes, 0);
    bytes[h.version] = version;
    std.mem.writeInt(u16, bytes[h.static_base..][0..2], 0x80, .big);
    std.mem.writeInt(u16, bytes[h.high_base..][0..2], 0x80, .big);
    std.mem.writeInt(u16, bytes[h.initial_pc..][0..2], 0x80, .big);
    std.mem.writeInt(u16, bytes[h.globals..][0..2], 0x40, .big);
    return bytes;
}

test "a version m8 does not run is refused rather than run badly" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    for ([_]u8{ 1, 2, 3, 4, 5, 8 }) |v| {
        const bytes = try blank(arena, v, 0x200);
        const s = try Story.load(arena, bytes);
        try testing.expectEqual(v, s.version);
    }
    for ([_]u8{ 0, 6, 7, 9 }) |v| {
        const bytes = try blank(arena, v, 0x200);
        try testing.expectError(Error.UnsupportedVersion, Story.load(arena, bytes));
    }
    try testing.expectError(Error.TooShort, Story.load(arena, "m8"));
}

test "the profile is what a game reads, and a restart reads it again" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try blank(arena, 5, 0x200);
    // A game that asked for everything: colours, pictures, sound, menus.
    std.mem.writeInt(u16, bytes[h.flags2..][0..2], 0xFFFF, .big);
    var s = try Story.load(arena, bytes);

    try testing.expectEqual(@as(u8, 80), s.mem[h.screen_width]);
    try testing.expectEqual(@as(u8, 255), s.mem[h.screen_height]);
    try testing.expectEqual(@as(u8, 6), s.mem[h.interpreter_number]);
    try testing.expectEqual(@as(u8, 'F'), s.mem[h.interpreter_version]);
    // Fixed-space available, and nothing else.
    try testing.expectEqual(@as(u8, 0b0001_0000), s.mem[h.flags1]);
    // Only the two bits the game is entitled to keep survive.
    try testing.expectEqual(flags2_kept, s.wordAt(h.flags2));

    // The game turns transcripting off and writes to dynamic memory.
    s.setWord(h.flags2, flags2_transcript);
    s.setByte(0x50, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), s.byteAt(0x50));

    s.restart();
    try testing.expectEqual(@as(u8, 0), s.byteAt(0x50));
    // Transcripting was asked for and is still asked for; the rest is denied
    // again, exactly as at boot.
    try testing.expectEqual(flags2_transcript, s.wordAt(h.flags2));
    try testing.expectEqual(@as(u8, 80), s.mem[h.screen_width]);
}

test "the checksum is over the file that arrived, not the one we wrote on" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try blank(arena, 3, 0x200);
    std.mem.writeInt(u16, bytes[h.file_length..][0..2], 0x100, .big); // 0x200 bytes
    bytes[0x100] = 0x10;
    bytes[0x101] = 0x20;

    const s = try Story.load(arena, bytes);
    try testing.expectEqual(@as(u32, 0x200), s.declaredLength());
    // Writing the profile changed the header, and the header is not counted.
    try testing.expectEqual(@as(u16, 0x30), s.checksum());
}

test "a packed address is unpacked by its version's multiplier" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const three = try Story.load(arena, try blank(arena, 3, 0x200));
    const five = try Story.load(arena, try blank(arena, 5, 0x200));
    const eight = try Story.load(arena, try blank(arena, 8, 0x200));

    try testing.expectEqual(@as(u32, 0x100), three.unpack(0x80));
    try testing.expectEqual(@as(u32, 0x200), five.unpack(0x80));
    try testing.expectEqual(@as(u32, 0x400), eight.unpack(0x80));
}
