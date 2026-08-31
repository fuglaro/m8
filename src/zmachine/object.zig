//! The object tree: attributes, properties, and who is inside what.
//!
//! Everything in a Z-machine game is an object — rooms, the player, a brass
//! lantern, and a good many things that are only a place to hang a flag. Each
//! has a fixed set of attributes it either has or does not, a variable set of
//! numbered properties, and exactly three links: parent, sibling, child. A
//! room's contents are its child and that child's siblings, so "what is in
//! here" is a walk rather than a list, and moving an object is unhooking it
//! from one chain and pushing it onto the front of another.
//!
//! The table is laid out twice. V1–3 give an object nine bytes, thirty-two
//! attributes and a one-byte object number, so a game may hold 255 of them;
//! V4 onwards give it fourteen bytes, forty-eight attributes and two-byte
//! numbers. The shapes differ enough that reading them through one set of
//! accessors is the only thing keeping the version out of the opcodes.
//!
//! Object zero is not an object. It is what a parent link says when there is
//! no parent, and the standard's own advice is that a game asking about it is
//! a game with a bug — so every accessor here answers zero rather than
//! reaching for an entry that would be the property defaults table.

const std = @import("std");
const Story = @import("story.zig").Story;
const text = @import("text.zig");

/// How many property defaults sit in front of the object entries.
fn defaultsCount(version: u8) u32 {
    return if (version <= 3) 31 else 63;
}

fn entrySize(version: u8) u32 {
    return if (version <= 3) 9 else 14;
}

fn attributeBytes(version: u8) u32 {
    return if (version <= 3) 4 else 6;
}

/// The highest property number a version has room for.
pub fn maxProperty(version: u8) u16 {
    return if (version <= 3) 31 else 63;
}

/// Where an object's entry begins. Object numbering starts at one, and the
/// entries begin after the defaults table.
fn entry(s: *const Story, obj: u16) u32 {
    const base = s.objects();
    return base + defaultsCount(s.version) * 2 + (@as(u32, obj) - 1) * entrySize(s.version);
}

pub fn exists(s: *const Story, obj: u16) bool {
    if (obj == 0) return false;
    return entry(s, obj) + entrySize(s.version) <= s.mem.len;
}

// ------------------------------------------------------------- attributes

/// Attribute zero is the top bit of the first byte, which is to say the
/// attributes are numbered as if the whole run were one big-endian integer.
pub fn hasAttribute(s: *const Story, obj: u16, attr: u16) bool {
    if (!exists(s, obj)) return false;
    if (attr >= attributeBytes(s.version) * 8) return false;
    const byte = s.byteAt(entry(s, obj) + attr / 8);
    return (byte & (@as(u8, 0x80) >> @intCast(attr % 8))) != 0;
}

pub fn setAttribute(s: *Story, obj: u16, attr: u16, on: bool) void {
    if (!exists(s, obj)) return;
    if (attr >= attributeBytes(s.version) * 8) return;
    const at = entry(s, obj) + attr / 8;
    const mask = @as(u8, 0x80) >> @intCast(attr % 8);
    const byte = s.byteAt(at);
    s.setByte(at, if (on) byte | mask else byte & ~mask);
}

// -------------------------------------------------------------- the tree

fn linkOffset(s: *const Story, which: enum { parent, sibling, child }) u32 {
    const attrs = attributeBytes(s.version);
    const stride: u32 = if (s.version <= 3) 1 else 2;
    return attrs + switch (which) {
        .parent => 0,
        .sibling => stride,
        .child => stride * 2,
    };
}

fn readLink(s: *const Story, obj: u16, which: anytype) u16 {
    if (!exists(s, obj)) return 0;
    const at = entry(s, obj) + linkOffset(s, which);
    return if (s.version <= 3) s.byteAt(at) else s.wordAt(at);
}

fn writeLink(s: *Story, obj: u16, which: anytype, value: u16) void {
    if (!exists(s, obj)) return;
    const at = entry(s, obj) + linkOffset(s, which);
    if (s.version <= 3) s.setByte(at, @truncate(value)) else s.setWord(at, value);
}

pub fn parent(s: *const Story, obj: u16) u16 {
    return readLink(s, obj, .parent);
}

pub fn sibling(s: *const Story, obj: u16) u16 {
    return readLink(s, obj, .sibling);
}

pub fn child(s: *const Story, obj: u16) u16 {
    return readLink(s, obj, .child);
}

/// Unhook an object from wherever it is. Its own child list comes with it —
/// taking the lamp out of the case does not empty the lamp.
pub fn remove(s: *Story, obj: u16) void {
    if (!exists(s, obj)) return;
    const p = parent(s, obj);
    if (p == 0) return;

    const first = child(s, p);
    if (first == obj) {
        writeLink(s, p, .child, sibling(s, obj));
    } else {
        // Walk the sibling chain to find whoever points at us. A chain that
        // does not contain us is a broken tree, and stopping is better than
        // walking it forever.
        var prev = first;
        var guard: u32 = 0;
        while (prev != 0 and guard < 0xFFFF) : (guard += 1) {
            const next = sibling(s, prev);
            if (next == obj) {
                writeLink(s, prev, .sibling, sibling(s, obj));
                break;
            }
            prev = next;
        }
    }
    writeLink(s, obj, .parent, 0);
    writeLink(s, obj, .sibling, 0);
}

/// Move an object to the front of another's child list. The front, because
/// that is what the machine has always done and games depend on the order
/// things are listed in.
pub fn insert(s: *Story, obj: u16, destination: u16) void {
    if (!exists(s, obj) or !exists(s, destination)) return;
    remove(s, obj);
    writeLink(s, obj, .sibling, child(s, destination));
    writeLink(s, obj, .parent, destination);
    writeLink(s, destination, .child, obj);
}

// ------------------------------------------------------------ properties

/// Where an object's property table starts: a length byte, the short name,
/// then the properties.
fn propertyTable(s: *const Story, obj: u16) u32 {
    if (!exists(s, obj)) return 0;
    const at = entry(s, obj) + attributeBytes(s.version) + (if (s.version <= 3) @as(u32, 3) else 6);
    return s.wordAt(at);
}

/// The object's short name, as ZSCII. Empty when it has none, which is
/// ordinary — plenty of objects are never printed.
pub fn name(s: *const Story, arena: std.mem.Allocator, obj: u16) ![]const u8 {
    const table = propertyTable(s, obj);
    if (table == 0) return "";
    const words = s.byteAt(table);
    if (words == 0) return "";
    return text.decodeAlloc(arena, s, table + 1);
}

/// Where the properties begin, past the short name.
fn firstProperty(s: *const Story, obj: u16) u32 {
    const table = propertyTable(s, obj);
    if (table == 0) return 0;
    return table + 1 + @as(u32, s.byteAt(table)) * 2;
}

const PropertyHeader = struct {
    number: u16,
    len: u32,
    /// Where the data starts, past however many size bytes there were.
    data: u32,
    /// Where the next header starts.
    next: u32,
};

/// Read one property header.
///
/// V1–3 spend one byte: five bits of number and three of length-minus-one.
/// V4 onwards spend one or two, and which it is lives in the top bit — a
/// second byte buys six bits of length, where a zero means sixty-four rather
/// than nothing, since a property of no length would have nothing to say.
fn readHeader(s: *const Story, at: u32) ?PropertyHeader {
    const size = s.byteAt(at);
    if (size == 0) return null;

    if (s.version <= 3) {
        const len: u32 = (size >> 5) + 1;
        return .{
            .number = size & 0x1F,
            .len = len,
            .data = at + 1,
            .next = at + 1 + len,
        };
    }
    if ((size & 0x80) != 0) {
        var len: u32 = s.byteAt(at + 1) & 0x3F;
        if (len == 0) len = 64;
        return .{
            .number = size & 0x3F,
            .len = len,
            .data = at + 2,
            .next = at + 2 + len,
        };
    }
    const len: u32 = if ((size & 0x40) != 0) 2 else 1;
    return .{
        .number = size & 0x3F,
        .len = len,
        .data = at + 1,
        .next = at + 1 + len,
    };
}

/// Find a property on an object. Properties are stored in descending order of
/// number, which is what lets a search stop early rather than read to the end.
fn findProperty(s: *const Story, obj: u16, number: u16) ?PropertyHeader {
    var at = firstProperty(s, obj);
    if (at == 0) return null;
    var guard: u32 = 0;
    while (guard < 0x1000) : (guard += 1) {
        const p = readHeader(s, at) orelse return null;
        if (p.number == number) return p;
        if (p.number < number) return null;
        at = p.next;
    }
    return null;
}

/// The default for a property, from the table in front of the objects. A game
/// asking for a property an object does not have is asking for this.
pub fn propertyDefault(s: *const Story, number: u16) u16 {
    if (number == 0 or number > maxProperty(s.version)) return 0;
    return s.wordAt(s.objects() + (@as(u32, number) - 1) * 2);
}

/// `get_prop`: one byte or two, or the default when the object has neither.
///
/// A property longer than two bytes has no defined value, and every
/// interpreter answers with its first word. Games do not ask, but a game that
/// does gets the same answer here as it would anywhere else.
pub fn getProperty(s: *const Story, obj: u16, number: u16) u16 {
    const p = findProperty(s, obj, number) orelse return propertyDefault(s, number);
    return if (p.len == 1) s.byteAt(p.data) else s.wordAt(p.data);
}

/// `put_prop`. Writing a property the object does not have is a game bug the
/// standard says to trap; we let it pass silently, since the alternative is
/// stopping a game that would otherwise have run.
pub fn putProperty(s: *Story, obj: u16, number: u16, value: u16) void {
    const p = findProperty(s, obj, number) orelse return;
    if (p.len == 1) s.setByte(p.data, @truncate(value)) else s.setWord(p.data, value);
}

/// `get_prop_addr`: where the data is, or zero when there is none.
pub fn propertyAddress(s: *const Story, obj: u16, number: u16) u16 {
    const p = findProperty(s, obj, number) orelse return 0;
    return @intCast(p.data);
}

/// `get_prop_len`: how long the property at this address is, read backwards
/// from its own size byte. Address zero answers zero, which the standard
/// requires because a game may hand it the result of a failed `get_prop_addr`.
pub fn propertyLength(s: *const Story, data_addr: u16) u16 {
    if (data_addr == 0) return 0;
    const size = s.byteAt(@as(u32, data_addr) - 1);
    if (s.version <= 3) return (size >> 5) + 1;
    if ((size & 0x80) != 0) {
        const len = size & 0x3F;
        return if (len == 0) 64 else len;
    }
    return if ((size & 0x40) != 0) 2 else 1;
}

/// `get_next_prop`: zero asks for the first, anything else asks for the one
/// after it, and zero comes back at the end of the list.
pub fn nextProperty(s: *const Story, obj: u16, number: u16) u16 {
    if (number == 0) {
        const at = firstProperty(s, obj);
        if (at == 0) return 0;
        const p = readHeader(s, at) orelse return 0;
        return p.number;
    }
    const p = findProperty(s, obj, number) orelse return 0;
    const next = readHeader(s, p.next) orelse return 0;
    return next.number;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const story_mod = @import("story.zig");

/// A tiny object table, built by hand: three objects in a V3 layout, with
/// object 2 and 3 inside object 1.
fn threeObjects(arena: std.mem.Allocator, version: u8) !Story {
    const bytes = try story_mod.blank(arena, version, 0x600);
    const base: u32 = 0x100;
    std.mem.writeInt(u16, bytes[story_mod.h.objects..][0..2], @intCast(base), .big);

    const defaults = defaultsCount(version) * 2;
    const size = entrySize(version);
    const attrs = attributeBytes(version);
    const stride: u32 = if (version <= 3) 1 else 2;

    const put = struct {
        fn link(b: []u8, at: u32, v: u16, wide: bool) void {
            if (wide) std.mem.writeInt(u16, b[at..][0..2], v, .big) else b[at] = @truncate(v);
        }
    }.link;

    var i: u16 = 1;
    while (i <= 3) : (i += 1) {
        const e = base + defaults + (@as(u32, i) - 1) * size;
        const p: u16 = if (i == 1) 0 else 1;
        const sib: u16 = if (i == 2) 3 else 0;
        const kid: u16 = if (i == 1) 2 else 0;
        put(bytes, e + attrs, p, version > 3);
        put(bytes, e + attrs + stride, sib, version > 3);
        put(bytes, e + attrs + stride * 2, kid, version > 3);
        // Every object points at the same property table, which holds a
        // zero-length name and no properties at all.
        std.mem.writeInt(u16, bytes[e + attrs + stride * 3 ..][0..2], 0x400, .big);
    }
    return try Story.load(arena, bytes);
}

test "an object's contents are its child and that child's siblings" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    for ([_]u8{ 3, 5 }) |version| {
        var s = try threeObjects(arena, version);
        try testing.expectEqual(@as(u16, 2), child(&s, 1));
        try testing.expectEqual(@as(u16, 3), sibling(&s, 2));
        try testing.expectEqual(@as(u16, 1), parent(&s, 2));

        // Taking object 2 out leaves 3 as the only child.
        remove(&s, 2);
        try testing.expectEqual(@as(u16, 3), child(&s, 1));
        try testing.expectEqual(@as(u16, 0), parent(&s, 2));

        // Putting it back puts it at the front.
        insert(&s, 2, 1);
        try testing.expectEqual(@as(u16, 2), child(&s, 1));
        try testing.expectEqual(@as(u16, 3), sibling(&s, 2));

        // Object zero is not an object, and asking about it answers nothing
        // rather than reading the property defaults as if they were one.
        try testing.expectEqual(@as(u16, 0), parent(&s, 0));
        try testing.expect(!exists(&s, 0));
    }
}

test "attributes are numbered as if the bytes were one long integer" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    var s = try threeObjects(arena, 3);
    try testing.expect(!hasAttribute(&s, 1, 0));
    setAttribute(&s, 1, 0, true);
    try testing.expect(hasAttribute(&s, 1, 0));
    try testing.expectEqual(@as(u8, 0x80), s.byteAt(entry(&s, 1)));

    setAttribute(&s, 1, 31, true);
    try testing.expectEqual(@as(u8, 0x01), s.byteAt(entry(&s, 1) + 3));
    setAttribute(&s, 1, 0, false);
    try testing.expect(!hasAttribute(&s, 1, 0));

    // V3 has thirty-two and no more; asking past the end is a game bug and
    // answers false rather than reading the next object's links.
    try testing.expect(!hasAttribute(&s, 1, 40));
}

test "properties are found by number, and missing ones fall back to defaults" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 3, 0x600);
    const base: u32 = 0x100;
    std.mem.writeInt(u16, bytes[story_mod.h.objects..][0..2], @intCast(base), .big);
    // Default for property 5, which is the fifth word of the table.
    std.mem.writeInt(u16, bytes[base + (5 - 1) * 2 ..][0..2], 0x1234, .big);

    const e = base + 31 * 2;
    std.mem.writeInt(u16, bytes[e + 7 ..][0..2], 0x400, .big);
    // A property table: no name, then property 10 of two bytes, property 3 of
    // one, then the terminator. Descending, as the machine requires.
    bytes[0x400] = 0; // name length in words
    bytes[0x401] = (1 << 5) | 10; // two bytes, number 10
    bytes[0x402] = 0xAB;
    bytes[0x403] = 0xCD;
    bytes[0x404] = (0 << 5) | 3; // one byte, number 3
    bytes[0x405] = 0x7F;
    bytes[0x406] = 0;

    var s = try Story.load(arena, bytes);
    try testing.expectEqual(@as(u16, 0xABCD), getProperty(&s, 1, 10));
    try testing.expectEqual(@as(u16, 0x7F), getProperty(&s, 1, 3));
    // Not present, so the default answers.
    try testing.expectEqual(@as(u16, 0x1234), getProperty(&s, 1, 5));

    try testing.expectEqual(@as(u16, 0x402), propertyAddress(&s, 1, 10));
    try testing.expectEqual(@as(u16, 0), propertyAddress(&s, 1, 5));
    try testing.expectEqual(@as(u16, 2), propertyLength(&s, 0x402));
    try testing.expectEqual(@as(u16, 1), propertyLength(&s, 0x405));
    // The standard's own special case: a length asked of nothing is zero.
    try testing.expectEqual(@as(u16, 0), propertyLength(&s, 0));

    // Walking the list is by number, highest first.
    try testing.expectEqual(@as(u16, 10), nextProperty(&s, 1, 0));
    try testing.expectEqual(@as(u16, 3), nextProperty(&s, 1, 10));
    try testing.expectEqual(@as(u16, 0), nextProperty(&s, 1, 3));

    putProperty(&s, 1, 3, 0x42);
    try testing.expectEqual(@as(u16, 0x42), getProperty(&s, 1, 3));
}

test "V4 spends two size bytes when a property is long" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 5, 0x600);
    const base: u32 = 0x100;
    std.mem.writeInt(u16, bytes[story_mod.h.objects..][0..2], @intCast(base), .big);
    const e = base + 63 * 2;
    std.mem.writeInt(u16, bytes[e + 12 ..][0..2], 0x400, .big);

    bytes[0x400] = 0;
    bytes[0x401] = 0x80 | 20; // two size bytes, property 20
    bytes[0x402] = 0x80 | 5; // five bytes of data
    bytes[0x408] = 0x40 | 7; // one size byte, two bytes, property 7
    bytes[0x409] = 0x11;
    bytes[0x40A] = 0x22;
    bytes[0x40B] = 0;

    var s = try Story.load(arena, bytes);
    try testing.expectEqual(@as(u16, 5), propertyLength(&s, 0x403));
    try testing.expectEqual(@as(u16, 0x403), propertyAddress(&s, 1, 20));
    try testing.expectEqual(@as(u16, 0x1122), getProperty(&s, 1, 7));
    try testing.expectEqual(@as(u16, 7), nextProperty(&s, 1, 20));
}
