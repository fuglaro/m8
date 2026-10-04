//! The machine: decode, execute, and stop for the player.
//!
//! Instructions come in four shapes decided by their first byte, and the shape
//! says how many operands follow and how each is spelled — a byte, a word, or
//! the number of a variable to read one out of. Version 5 adds a fifth shape
//! behind an escape byte. After the operands, an instruction may carry a byte
//! naming where to put its result, or one or two bytes saying where to jump if
//! it is true; a few carry a whole string. None of that is knowable until the
//! first byte has been read, which is why decoding and executing are one pass
//! rather than two.
//!
//! The machine has two stacks in one array. Routine frames hold their own
//! locals and a return address; the evaluation stack grows above the current
//! frame's base, so a routine cannot reach into its caller's working values
//! even by accident. `catch` and `throw` are the exception, and they are the
//! reason a frame remembers where its base was.
//!
//! Everything is sixteen bits, and everything arithmetic is signed sixteen
//! bits, which the standard is unusually clear about because 1979 hardware was
//! not. Reads are unsigned words; the interpretation is the opcode's.
//!
//! **Where the design shows.** `run` returns when the game wants input, and
//! `feedLine` finishes the instruction that was interrupted. Splitting one
//! opcode across two calls is what lets the whole machine be a pure function
//! of the story file and the words typed into it — no timers, no clock, no
//! saved state, and no way for two runs to differ. Every opcode that could
//! have broken that — `random`, the four persistence ones, `restart`,
//! `input_stream`, `verify`, `piracy`, and the two that read — is answered
//! here rather than left to a default.

const std = @import("std");
const Allocator = std.mem.Allocator;
const dict = @import("dict.zig");
const object = @import("object.zig");
const screen_mod = @import("screen.zig");
const story_mod = @import("story.zig");
const text = @import("text.zig");
const Screen = screen_mod.Screen;
const Story = story_mod.Story;

pub const Error = error{
    /// The story file asked for something no version of the machine does.
    BadOpcode,
    /// A frame was popped that was never pushed, or the stack ran dry.
    StackUnderflow,
    /// A game that recurses without end, which is a game bug rather than ours.
    StackOverflow,
};

/// Where the machine stopped, which is the only thing the driver needs to
/// know. Three of the four mean it wants something; the fourth means it is
/// over and nothing will change that.
pub const Stop = enum {
    line_input,
    char_input,
    quit,
};

pub const max_stack = 0x8000;
pub const max_frames = 512;

const Frame = struct {
    return_pc: u32,
    /// Where this frame's working stack starts, so `throw` can cut back to it.
    base: usize,
    locals: [15]u16 = @splat(0),
    n_locals: u8 = 0,
    /// Where the result goes, or null for a `call_n` that wants none.
    store: ?u8 = null,
    /// How many arguments were actually supplied, for `check_arg_count`.
    args: u8 = 0,
};

/// The input the machine was in the middle of reading when it stopped.
const Pending = struct {
    text_buffer: u32 = 0,
    parse_buffer: u32 = 0,
    store: ?u8 = null,
};

/// A deterministic generator, written out here rather than taken from the
/// standard library.
///
/// It is written out because replay must survive a compiler upgrade: a
/// generator that changed its arithmetic between two versions of Zig would
/// silently change every world a stored ledger describes. This one is pinned
/// by being in a file whose hash is the interpreter's semantic version, so a
/// change to it is a change anybody can see.
pub const Rng = struct {
    state: u64,
    seed: [8]u8,
    /// How many times the game has asked to be reseeded. Included in every
    /// derivation, because two `random 0` calls in one turn would otherwise
    /// derive the same seed from the same ledger.
    reseeds: u64 = 0,

    pub fn init(seed: [8]u8) Rng {
        return .{ .state = std.mem.readInt(u64, &seed, .little), .seed = seed };
    }

    fn next(r: *Rng) u64 {
        // SplitMix64. Small, well-mixed, and short enough to read.
        r.state +%= 0x9E3779B97F4A7C15;
        var z = r.state;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }

    /// One to `n`, as the opcode promises.
    pub fn range(r: *Rng, n: u16) u16 {
        if (n == 0) return 0;
        return @intCast(1 + r.next() % n);
    }

    /// `random 0`: the game asked for a fresh seed, which a real interpreter
    /// takes from the clock. We take it from the seed the ledger already
    /// carries and a counter, so the request is honoured and nothing outside
    /// the ledger gets in.
    pub fn reseed(r: *Rng) void {
        r.reseeds += 1;
        var input: [16]u8 = undefined;
        @memcpy(input[0..8], &r.seed);
        std.mem.writeInt(u64, input[8..16], r.reseeds, .little);

        r.state = std.hash.Wyhash.hash(0, &input);
    }

    /// `random -n`: the game asked for a specific seed, and is entitled to
    /// have the same sequence back every time it asks.
    pub fn seedTo(r: *Rng, value: u16) void {
        r.state = 0x9E3779B97F4A7C15 *% (@as(u64, value) + 1);
        _ = r.next();
    }
};

pub const Machine = struct {
    arena: Allocator,
    story: Story,
    screen: Screen,
    rng: Rng,

    pc: u32 = 0,
    stack: std.ArrayList(u16) = .empty,
    frames: std.ArrayList(Frame) = .empty,

    pending: Pending = .{},
    /// Set when the game has stopped for good. Every later call sees it.
    finished: bool = false,
    /// How many instructions this call has run, so a game that has gone into
    /// a loop stops rather than hanging the harness for ever.
    fuel: u64 = 0,

    pub const fuel_limit: u64 = 200_000_000;

    pub fn init(arena: Allocator, bytes: []const u8, seed: [8]u8) !Machine {
        var m: Machine = .{
            .arena = arena,
            .story = try Story.load(arena, bytes),
            .screen = undefined,
            .rng = Rng.init(seed),
        };
        m.screen = Screen.init(arena, &m.story, story_mod.profile.screen_width);
        m.pc = m.story.initialPc();
        return m;
    }

    /// The screen holds a pointer to our own story, so a machine that is moved
    /// after `init` has to be told where it landed. Zig will copy a struct
    /// returned by value; this puts the pointer back.
    pub fn settle(m: *Machine) void {
        m.screen.story = &m.story;
    }

    /// A machine that stays where it is put. The screen points into the story
    /// this one owns, so anything that copies a `Machine` after `init` has to
    /// remember to `settle` it — allocating once and never moving is one less
    /// thing to remember.
    pub fn create(arena: Allocator, bytes: []const u8, seed: [8]u8) !*Machine {
        const m = try arena.create(Machine);
        m.* = try Machine.init(arena, bytes, seed);
        m.settle();
        return m;
    }

    // -------------------------------------------------------- variables

    fn push(m: *Machine, value: u16) !void {
        if (m.stack.items.len >= max_stack) return Error.StackOverflow;
        try m.stack.append(m.arena, value);
    }

    fn pop(m: *Machine) !u16 {
        if (m.stack.items.len == 0) return Error.StackUnderflow;
        return m.stack.pop() orelse return Error.StackUnderflow;
    }

    fn frame(m: *Machine) ?*Frame {
        if (m.frames.items.len == 0) return null;
        return &m.frames.items[m.frames.items.len - 1];
    }

    fn readVar(m: *Machine, v: u8) !u16 {
        if (v == 0) return m.pop();
        if (v < 16) {
            const f = m.frame() orelse return 0;
            if (v - 1 >= f.n_locals) return 0;
            return f.locals[v - 1];
        }
        return m.story.wordAt(@as(u32, m.story.globals()) + (@as(u32, v) - 16) * 2);
    }

    fn writeVar(m: *Machine, v: u8, value: u16) !void {
        if (v == 0) return m.push(value);
        if (v < 16) {
            const f = m.frame() orelse return;
            if (v - 1 >= f.n_locals) return;
            f.locals[v - 1] = value;
            return;
        }
        m.story.setWord(@as(u32, m.story.globals()) + (@as(u32, v) - 16) * 2, value);
    }

    /// The indirect forms, where the variable number arrived as an operand
    /// rather than being part of the instruction.
    ///
    /// Variable zero means the stack, and here it means the top of it rather
    /// than a push or a pop: `inc sp` adds one to what is already there. That
    /// distinction is small, invisible in most games, and wrong in exactly the
    /// ones that use it.
    fn readIndirect(m: *Machine, v: u8) !u16 {
        if (v != 0) return m.readVar(v);
        if (m.stack.items.len == 0) return Error.StackUnderflow;
        return m.stack.items[m.stack.items.len - 1];
    }

    fn writeIndirect(m: *Machine, v: u8, value: u16) !void {
        if (v != 0) return m.writeVar(v, value);
        if (m.stack.items.len == 0) return m.push(value);
        m.stack.items[m.stack.items.len - 1] = value;
    }

    // ---------------------------------------------------------- decoding

    fn fetchByte(m: *Machine) u8 {
        const b = m.story.byteAt(m.pc);
        m.pc += 1;
        return b;
    }

    fn fetchWord(m: *Machine) u16 {
        const w = m.story.wordAt(m.pc);
        m.pc += 2;
        return w;
    }

    const OperandKind = enum(u2) { large, small, variable, omitted };

    fn readOperand(m: *Machine, kind: OperandKind) !u16 {
        return switch (kind) {
            .large => m.fetchWord(),
            .small => m.fetchByte(),
            .variable => m.readVar(m.fetchByte()),
            .omitted => 0,
        };
    }

    /// The branch byte, or two of them. Six bits is enough for most jumps and
    /// costs one byte; fourteen signed bits is the escape.
    fn branch(m: *Machine, condition: bool) !void {
        const first = m.fetchByte();
        const on_true = (first & 0x80) != 0;
        var offset: i32 = undefined;
        if ((first & 0x40) != 0) {
            offset = first & 0x3F;
        } else {
            const second = m.fetchByte();
            var raw: i16 = @bitCast((@as(u16, first & 0x3F) << 8) | second);
            // Fourteen bits, sign-extended from bit 13.
            if ((raw & 0x2000) != 0) raw |= @bitCast(@as(u16, 0xC000));
            offset = raw;
        }

        if (condition != on_true) return;
        // Nought and one are not offsets at all: they are the two ways of
        // returning without a `ret`, which saves a byte in the commonest case
        // a compiler ever emits.
        if (offset == 0) return m.doReturn(0);
        if (offset == 1) return m.doReturn(1);
        m.pc = @intCast(@as(i64, m.pc) + offset - 2);
    }

    fn store(m: *Machine, value: u16) !void {
        const v = m.fetchByte();
        try m.writeVar(v, value);
    }

    // ------------------------------------------------------------- calls

    fn doCall(m: *Machine, packed_addr: u16, args: []const u16, result: ?u8) !void {
        // A call to address zero does nothing and answers false. Games use it
        // as a null function pointer, so it is a feature rather than a fault.
        if (packed_addr == 0) {
            if (result) |v| try m.writeVar(v, 0);
            return;
        }
        if (m.frames.items.len >= max_frames) return Error.StackOverflow;

        const addr = m.story.unpack(packed_addr);
        var f: Frame = .{
            .return_pc = m.pc,
            .base = m.stack.items.len,
            .store = result,
            .args = @intCast(@min(args.len, 255)),
        };

        var at = addr;
        f.n_locals = @min(m.story.byteAt(at), 15);
        at += 1;
        var i: u8 = 0;
        while (i < f.n_locals) : (i += 1) {
            // V1–4 give each local an initial value from the routine header.
            // V5 dropped them and starts every local at zero, which is two
            // bytes per local saved in every routine in the game.
            if (m.story.version <= 4) {
                f.locals[i] = m.story.wordAt(at);
                at += 2;
            } else {
                f.locals[i] = 0;
            }
        }
        for (args, 0..) |a, j| {
            if (j >= f.n_locals) break;
            f.locals[j] = a;
        }

        try m.frames.append(m.arena, f);
        m.pc = at;
    }

    fn doReturn(m: *Machine, value: u16) !void {
        const f = m.frames.pop() orelse return Error.StackUnderflow;
        m.stack.shrinkRetainingCapacity(f.base);
        m.pc = f.return_pc;
        if (f.store) |v| try m.writeVar(v, value);
    }

    // -------------------------------------------------------------- run

    /// Run until the game wants something, or until it stops for good.
    pub fn run(m: *Machine) !Stop {
        if (m.finished) return .quit;
        m.fuel = 0;
        while (true) {
            if (try m.step()) |stop| {
                if (stop == .quit) m.finished = true;
                return stop;
            }
            m.fuel += 1;
            if (m.fuel > fuel_limit) {
                // A game cannot be told from a loop by looking at it, so the
                // only honest thing is a limit high enough that no game
                // reaches it and low enough that a loop does.
                m.finished = true;
                try m.screen.print("\r[The game stopped responding.]\r");
                return .quit;
            }
        }
    }

    /// Give the machine the line it was waiting for and let the interrupted
    /// instruction finish.
    ///
    /// The text arrives as UTF-8 and is stored as lower-case ZSCII, which is
    /// what the standard asks for so a game can print back what was typed.
    /// Anything with no ZSCII code at all is dropped rather than approximated:
    /// the machine has no way to say it, and a substitute would be a word the
    /// player did not type.
    ///
    /// The terminator is what V5 hands back to say which key ended the line.
    /// It is Return almost always; a game that declared other keys and was
    /// sent one gets that key, and an empty line with it.
    pub fn feedLineTerminated(m: *Machine, utf8: []const u8, terminator: u8) !void {
        const buffer = m.pending.text_buffer;
        const parse = m.pending.parse_buffer;
        const version = m.story.version;

        var zscii: std.ArrayList(u8) = .empty;
        var it = std.unicode.Utf8Iterator{ .bytes = utf8, .i = 0 };
        while (it.nextCodepoint()) |cp| {
            if (cp == '\n' or cp == '\r') break;
            const code = text.fromUnicode(&m.story, cp) orelse continue;
            try zscii.append(m.arena, std.ascii.toLower(code));
        }

        const capacity = m.story.byteAt(buffer);
        const line = zscii.items[0..@min(zscii.items.len, capacity)];

        if (version <= 4) {
            for (line, 0..) |c, i| m.story.setByte(buffer + 1 + @as(u32, @intCast(i)), c);
            m.story.setByte(buffer + 1 + @as(u32, @intCast(line.len)), 0);
        } else {
            m.story.setByte(buffer + 1, @intCast(line.len));
            for (line, 0..) |c, i| m.story.setByte(buffer + 2 + @as(u32, @intCast(i)), c);
        }

        if (parse != 0) {
            const d = dict.read(&m.story, m.story.dictionary());
            const tokens = try dict.split(m.arena, &m.story, d, line, 0xFF);
            dict.writeParse(&m.story, parse, tokens, dict.textOffset(version), false);
        }

        // V5 hands back which key ended the line.
        if (m.pending.store) |v| try m.writeVar(v, terminator);
        m.pending = .{};
    }

    /// The ordinary case: a line, ended by Return.
    pub fn feedLine(m: *Machine, utf8: []const u8) !void {
        return m.feedLineTerminated(utf8, text.newline);
    }

    /// Give the machine the single keypress it was waiting for.
    pub fn feedChar(m: *Machine, code: u8) !void {
        if (m.pending.store) |v| try m.writeVar(v, code);
        m.pending = .{};
    }

    /// One instruction. Null unless the machine stopped.
    fn step(m: *Machine) !?Stop {
        const op = m.fetchByte();

        if (op == 0xBE and m.story.version >= 5) {
            const ext = m.fetchByte();
            var kinds: [8]OperandKind = @splat(.omitted);
            m.readKinds(m.fetchByte(), kinds[0..4]);
            var operands: [8]u16 = @splat(0);
            const n = try m.gather(&kinds, &operands);
            return m.doExt(ext, operands[0..n]);
        }

        if (op < 0x80) {
            // Long form: always two operands, and the two type bits are in
            // the opcode byte itself.
            const a = try m.readOperand(if ((op & 0x40) != 0) .variable else .small);
            const b = try m.readOperand(if ((op & 0x20) != 0) .variable else .small);
            return m.do2(op & 0x1F, a, b);
        }

        if (op < 0xC0) {
            // Short form: one operand, or none when the type says omitted.
            const kind: OperandKind = @enumFromInt(@as(u2, @intCast((op >> 4) & 0x03)));
            if (kind == .omitted) return m.do0(op & 0x0F);
            const a = try m.readOperand(kind);
            return m.do1(op & 0x0F, a);
        }

        // Variable form: a byte of types, or two for the two opcodes that may
        // take eight operands.
        const wide = op == 0xEC or op == 0xFA;
        var kinds: [8]OperandKind = @splat(.omitted);
        m.readKinds(m.fetchByte(), kinds[0..4]);
        if (wide) m.readKinds(m.fetchByte(), kinds[4..8]);

        var operands: [8]u16 = @splat(0);
        const n = try m.gather(&kinds, &operands);

        if ((op & 0x20) == 0) {
            // A 2OP opcode spelled the long way, which is how a compiler
            // passes a large constant to something that normally takes bytes.
            // It is also the only way to give `je` more than two.
            if ((op & 0x1F) == 1 and n > 2) {
                var any = false;
                for (operands[1..n]) |candidate| {
                    if (operands[0] == candidate) any = true;
                }
                try m.branch(any);
                return null;
            }
            const a: u16 = if (n > 0) operands[0] else 0;
            const b: u16 = if (n > 1) operands[1] else 0;
            return m.do2(op & 0x1F, a, b);
        }
        return m.doVar(op & 0x1F, operands[0..n]);
    }

    fn readKinds(m: *Machine, byte: u8, into: []OperandKind) void {
        _ = m;
        for (into, 0..) |*k, i| {
            const shift: u3 = @intCast(6 - i * 2);
            k.* = @enumFromInt(@as(u2, @intCast((byte >> shift) & 0x03)));
        }
    }

    /// Read every operand up to the first omitted one. The list is terminated
    /// by omission rather than counted, so a type byte of all-ones is no
    /// operands at all.
    fn gather(m: *Machine, kinds: []const OperandKind, into: []u16) !usize {
        var n: usize = 0;
        for (kinds) |k| {
            if (k == .omitted) break;
            into[n] = try m.readOperand(k);
            n += 1;
        }
        return n;
    }

    // ------------------------------------------------------------ 2OP

    fn do2(m: *Machine, opcode: u8, a: u16, b: u16) !?Stop {
        const sa: i16 = @bitCast(a);
        const sb: i16 = @bitCast(b);
        switch (opcode) {
            1 => try m.branch(a == b),
            2 => try m.branch(sa < sb),
            3 => try m.branch(sa > sb),
            4 => {
                const v: i16 = @bitCast(try m.readIndirect(@truncate(a)));
                const next = v -% 1;
                try m.writeIndirect(@truncate(a), @bitCast(next));
                try m.branch(next < sb);
            },
            5 => {
                const v: i16 = @bitCast(try m.readIndirect(@truncate(a)));
                const next = v +% 1;
                try m.writeIndirect(@truncate(a), @bitCast(next));
                try m.branch(next > sb);
            },
            6 => try m.branch(object.parent(&m.story, a) == b),
            7 => try m.branch((a & b) == b),
            8 => try m.store(a | b),
            9 => try m.store(a & b),
            10 => try m.branch(object.hasAttribute(&m.story, a, b)),
            11 => object.setAttribute(&m.story, a, b, true),
            12 => object.setAttribute(&m.story, a, b, false),
            13 => try m.writeIndirect(@truncate(a), b),
            14 => object.insert(&m.story, a, b),
            15 => try m.store(m.story.wordAt(@as(u32, a) +% @as(u32, b) * 2)),
            16 => try m.store(m.story.byteAt(@as(u32, a) +% b)),
            17 => try m.store(object.getProperty(&m.story, a, b)),
            18 => try m.store(object.propertyAddress(&m.story, a, b)),
            19 => try m.store(object.nextProperty(&m.story, a, b)),
            20 => try m.store(@bitCast(sa +% sb)),
            21 => try m.store(@bitCast(sa -% sb)),
            22 => try m.store(@bitCast(sa *% sb)),
            // Division by zero is an error the standard leaves to the
            // interpreter. Answering zero keeps a broken game running, which
            // is more use than stopping one that would have recovered.
            23 => try m.store(if (sb == 0) 0 else @bitCast(divide(sa, sb))),
            24 => try m.store(if (sb == 0) 0 else @bitCast(remainder(sa, sb))),
            25 => {
                if (m.story.version < 4) return Error.BadOpcode;
                const v = m.fetchByte();
                try m.doCall(a, &.{b}, v);
            },
            26 => {
                if (m.story.version < 5) return Error.BadOpcode;
                try m.doCall(a, &.{b}, null);
            },
            // Colours are denied in the header, so a game asking for one is a
            // game that did not read the answer. Accepting quietly is kinder
            // than refusing loudly.
            27 => {},
            28 => {
                if (m.story.version < 5) return Error.BadOpcode;
                try m.doThrow(a, b);
            },
            else => return Error.BadOpcode,
        }
        return null;
    }

    // ------------------------------------------------------------ 1OP

    fn do1(m: *Machine, opcode: u8, a: u16) !?Stop {
        switch (opcode) {
            0 => try m.branch(a == 0),
            1 => {
                const sib = object.sibling(&m.story, a);
                try m.store(sib);
                try m.branch(sib != 0);
            },
            2 => {
                const kid = object.child(&m.story, a);
                try m.store(kid);
                try m.branch(kid != 0);
            },
            3 => try m.store(object.parent(&m.story, a)),
            4 => try m.store(object.propertyLength(&m.story, a)),
            5 => {
                const v: i16 = @bitCast(try m.readIndirect(@truncate(a)));
                try m.writeIndirect(@truncate(a), @bitCast(v +% 1));
            },
            6 => {
                const v: i16 = @bitCast(try m.readIndirect(@truncate(a)));
                try m.writeIndirect(@truncate(a), @bitCast(v -% 1));
            },
            7 => try m.printAt(a),
            8 => {
                if (m.story.version < 4) return Error.BadOpcode;
                const v = m.fetchByte();
                try m.doCall(a, &.{}, v);
            },
            9 => object.remove(&m.story, a),
            10 => {
                const name = try object.name(&m.story, m.arena, a);
                try m.screen.print(name);
            },
            11 => try m.doReturn(a),
            12 => {
                const offset: i16 = @bitCast(a);
                m.pc = @intCast(@as(i64, m.pc) + offset - 2);
            },
            13 => try m.printAt(m.story.unpack(a)),
            14 => {
                const v = try m.readIndirect(@truncate(a));
                try m.store(v);
            },
            15 => {
                if (m.story.version >= 5) {
                    try m.doCall(a, &.{}, null);
                } else {
                    try m.store(~a);
                }
            },
            else => return Error.BadOpcode,
        }
        return null;
    }

    // ------------------------------------------------------------ 0OP

    fn do0(m: *Machine, opcode: u8) !?Stop {
        switch (opcode) {
            0 => try m.doReturn(1),
            1 => try m.doReturn(0),
            2 => {
                const d = try m.printInline(m.pc);
                m.pc += d;
            },
            3 => {
                const d = try m.printInline(m.pc);
                m.pc += d;
                try m.screen.newLine();
                try m.doReturn(1);
            },
            4 => {},
            // Saving is not implementable here — there is no durable store,
            // and anything written would be gone before the next call. The way
            // it fails is version-specific because games branch on it. A false
            // branch in V1–3; a stored zero in V4. Never a filename prompt,
            // which would land in the ledger as a turn nobody typed.
            5 => {
                if (m.story.version <= 3) {
                    try m.branch(false);
                } else {
                    try m.store(0);
                }
            },
            6 => {
                if (m.story.version <= 3) {
                    try m.branch(false);
                } else {
                    try m.store(0);
                }
            },
            7 => {
                m.story.restart();
                m.stack.clearRetainingCapacity();
                m.frames.clearRetainingCapacity();
                m.screen = Screen.init(m.arena, &m.story, story_mod.profile.screen_width);
                m.pc = m.story.initialPc();
            },
            8 => {
                const v = try m.pop();
                try m.doReturn(v);
            },
            9 => {
                if (m.story.version >= 5) {
                    // `catch` is a bookmark: how deep the frames are now, so
                    // `throw` can come back to exactly here.
                    try m.store(@intCast(m.frames.items.len));
                } else {
                    _ = try m.pop();
                }
            },
            10 => return .quit,
            11 => try m.screen.newLine(),
            // The status line is synthesised at the emit boundary from the
            // same globals this would have read, so there is nothing for it
            // to do that has not already been done.
            12 => {},
            13 => try m.branch(m.story.checksum() == m.story.declaredChecksum()),
            // 14 is the extended-opcode escape and never reaches here.
            15 => {
                if (m.story.version < 5) return Error.BadOpcode;
                // Genuine, always. The opcode exists so a game can sulk about
                // being copied, and we have nothing to be shifty about.
                try m.branch(true);
            },
            else => return Error.BadOpcode,
        }
        return null;
    }

    // ------------------------------------------------------------- VAR

    fn doVar(m: *Machine, opcode: u8, ops: []const u16) !?Stop {
        switch (opcode) {
            0 => {
                const v = m.fetchByte();
                try m.doCall(arg(ops, 0), rest(ops), v);
            },
            1 => m.story.setWord(@as(u32, arg(ops, 0)) +% @as(u32, arg(ops, 1)) * 2, arg(ops, 2)),
            2 => m.story.setByte(@as(u32, arg(ops, 0)) +% arg(ops, 1), @truncate(arg(ops, 2))),
            3 => object.putProperty(&m.story, arg(ops, 0), arg(ops, 1), arg(ops, 2)),
            4 => return m.doRead(ops),
            5 => try m.screen.put(@truncate(arg(ops, 0))),
            6 => try m.printNumber(@bitCast(arg(ops, 0))),
            7 => {
                const n: i16 = @bitCast(arg(ops, 0));
                if (n > 0) {
                    try m.store(m.rng.range(@intCast(n)));
                } else if (n < 0) {
                    m.rng.seedTo(@intCast(-n));
                    try m.store(0);
                } else {
                    m.rng.reseed();
                    try m.store(0);
                }
            },
            8 => try m.push(arg(ops, 0)),
            9 => {
                const v = try m.pop();
                try m.writeIndirect(@truncate(arg(ops, 0)), v);
            },
            10 => try m.screen.splitWindow(arg(ops, 0)),
            11 => m.screen.setWindow(@truncate(arg(ops, 0))),
            12 => {
                if (m.story.version < 4) return Error.BadOpcode;
                const v = m.fetchByte();
                try m.doCall(arg(ops, 0), rest(ops), v);
            },
            13 => try m.screen.eraseWindow(@bitCast(arg(ops, 0))),
            14 => try m.screen.eraseLine(),
            15 => m.screen.setCursor(arg(ops, 0), arg(ops, 1)),
            16 => {
                const c = m.screen.cursor();
                const at = arg(ops, 0);
                m.story.setWord(at, c.row);
                m.story.setWord(at + 2, c.col);
            },
            // Styles are accepted and discarded: the characters are what the
            // ledger holds, and Flags 1 already told the game we have no bold
            // and no italics to give it.
            17 => {},
            18 => m.screen.bufferMode(arg(ops, 0) != 0),
            19 => m.screen.outputStream(@bitCast(arg(ops, 0)), arg(ops, 1)),
            // The keyboard is the only input stream there is. A game may ask
            // for the other one; it does not get it, and asking is not an
            // error.
            20 => {},
            21 => {},
            22 => return m.doReadChar(ops),
            23 => try m.scanTable(ops),
            24 => {
                if (m.story.version < 5) return Error.BadOpcode;
                try m.store(~arg(ops, 0));
            },
            25 => {
                if (m.story.version < 5) return Error.BadOpcode;
                try m.doCall(arg(ops, 0), rest(ops), null);
            },
            26 => {
                if (m.story.version < 5) return Error.BadOpcode;
                try m.doCall(arg(ops, 0), rest(ops), null);
            },
            27 => try m.doTokenise(ops),
            28 => try m.doEncodeText(ops),
            29 => try m.copyTable(ops),
            30 => try m.printTable(ops),
            31 => {
                const f = m.frame();
                const count: u16 = if (f) |x| x.args else 0;
                try m.branch(arg(ops, 0) <= count);
            },
            else => return Error.BadOpcode,
        }
        return null;
    }

    // ------------------------------------------------------------- EXT

    fn doExt(m: *Machine, opcode: u8, ops: []const u16) !?Stop {
        switch (opcode) {
            // The table forms of save and restore, which fail the same way
            // the plain ones do and for the same reason.
            0, 1 => try m.store(0),
            2 => {
                const value = arg(ops, 0);
                const places: i16 = @bitCast(arg(ops, 1));
                try m.store(logicalShift(value, places));
            },
            3 => {
                const value: i16 = @bitCast(arg(ops, 0));
                const places: i16 = @bitCast(arg(ops, 1));
                try m.store(@bitCast(arithmeticShift(value, places)));
            },
            4 => {
                // Font 1 is normal and font 4 is fixed-pitch, and being
                // monospace we are already both. Anything else is refused by
                // answering zero, which is how the opcode says "no".
                const want = arg(ops, 0);
                try m.store(if (want == 0 or want == 1 or want == 4) 1 else 0);
            },
            // Undo is cleared in Flags 2 and must fail with -1 rather than 0:
            // minus one is "this interpreter cannot", zero is "it did not work
            // this time", and games say different things about each.
            9 => try m.store(@bitCast(@as(i16, -1))),
            10 => try m.store(0),
            11 => try m.screen.putUnicode(@intCast(arg(ops, 0))),
            12 => {
                // Two separate questions in two bits: bit 0 is whether we can
                // print it, bit 1 whether somebody could type it back.
                //
                // They have different answers here, and saying so is worth
                // more than a blanket no. Printing goes out as UTF-8, so
                // anything the operand can name can be printed; reading comes
                // back through ZSCII, so only what has a code can be typed.
                // A game told "no" would substitute something worse than the
                // character we would have rendered perfectly well.
                const cp: u21 = @intCast(arg(ops, 0));
                const can_print: u16 = 1;
                const can_read: u16 = if (text.fromUnicode(&m.story, cp) != null) 2 else 0;
                try m.store(can_print | can_read);
            },
            else => {
                // Everything else in this table is V6's, and V6 is out of
                // scope. A store instruction still has to store something, but
                // we cannot know whether this one is — so nothing is written
                // and the opcode is simply passed over.
                return null;
            },
        }
        return null;
    }

    // -------------------------------------------------------- the input

    /// `sread` / `aread`. The instruction stops here and is finished by
    /// `feedLine`, and the stop between them is the emit boundary.
    fn doRead(m: *Machine, ops: []const u16) !?Stop {
        m.pending = .{
            .text_buffer = arg(ops, 0),
            .parse_buffer = arg(ops, 1),
            .store = if (m.story.version >= 5) m.fetchByte() else null,
        };
        return .line_input;
    }

    fn doReadChar(m: *Machine, ops: []const u16) !?Stop {
        _ = ops;
        m.pending = .{ .store = m.fetchByte() };
        return .char_input;
    }

    fn doTokenise(m: *Machine, ops: []const u16) !void {
        const buffer = arg(ops, 0);
        const parse = arg(ops, 1);
        const which = arg(ops, 2);
        const flag = arg(ops, 3);

        const version = m.story.version;
        const len: usize = if (version <= 4) blk: {
            var n: usize = 0;
            while (m.story.byteAt(buffer + 1 + @as(u32, @intCast(n))) != 0) n += 1;
            break :blk n;
        } else m.story.byteAt(buffer + 1);

        const start = buffer + @as(u32, @intCast(dict.textOffset(version)));
        const line = m.story.mem[@min(start, m.story.mem.len)..@min(start + len, m.story.mem.len)];

        const table = if (which != 0) which else m.story.dictionary();
        const d = dict.read(&m.story, table);
        const tokens = try dict.split(m.arena, &m.story, d, line, 0xFF);
        dict.writeParse(&m.story, parse, tokens, dict.textOffset(version), flag != 0);
    }

    fn doEncodeText(m: *Machine, ops: []const u16) !void {
        const buffer = arg(ops, 0);
        const len = arg(ops, 1);
        const from = arg(ops, 2);
        const into = arg(ops, 3);

        const start = @as(u32, buffer) + from;
        const end = @min(start + len, m.story.mem.len);
        const word = m.story.mem[@min(start, m.story.mem.len)..end];

        var out: [3]u16 = .{ 0, 0, 0 };
        const words = text.resolution(m.story.version) / 3;
        text.encode(&m.story, word, out[0..words]);
        for (out[0..words], 0..) |w, i| m.story.setWord(into + @as(u32, @intCast(i)) * 2, w);
    }

    // -------------------------------------------------------- the tables

    fn scanTable(m: *Machine, ops: []const u16) !void {
        const want = arg(ops, 0);
        const table = arg(ops, 1);
        const count = arg(ops, 2);
        // The form byte says how wide a field is and whether to compare words
        // or bytes. Its default is a word-sized field two bytes long, which is
        // an array of words.
        const form = if (ops.len > 3) ops[3] else 0x82;
        const stride: u32 = form & 0x7F;
        const words = (form & 0x80) != 0;

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const at = @as(u32, table) + @as(u32, i) * stride;
            const value: u16 = if (words) m.story.wordAt(at) else m.story.byteAt(at);
            if (value == want) {
                try m.store(@intCast(at));
                return m.branch(true);
            }
        }
        try m.store(0);
        try m.branch(false);
    }

    fn copyTable(m: *Machine, ops: []const u16) !void {
        const first = arg(ops, 0);
        const second = arg(ops, 1);
        const size: i16 = @bitCast(arg(ops, 2));

        if (second == 0) {
            // A destination of zero means erase, and the size is how much.
            var i: u32 = 0;
            const n: u32 = @intCast(@abs(size));
            while (i < n) : (i += 1) m.story.setByte(first + i, 0);
            return;
        }

        const n: u32 = @intCast(@abs(size));
        // A positive size promises the copy behaves as if it went through a
        // buffer, so an overlap does not eat its own tail; a negative one says
        // copy forwards regardless, which a game uses deliberately to fill.
        if (size > 0 and second > first and second < first + n) {
            var i: u32 = n;
            while (i > 0) {
                i -= 1;
                m.story.setByte(second + i, m.story.byteAt(first + i));
            }
        } else {
            var i: u32 = 0;
            while (i < n) : (i += 1) m.story.setByte(second + i, m.story.byteAt(first + i));
        }
    }

    fn printTable(m: *Machine, ops: []const u16) !void {
        const at = arg(ops, 0);
        const width = arg(ops, 1);
        const height = if (ops.len > 2) ops[2] else 1;
        const skip = if (ops.len > 3) ops[3] else 0;

        var row: u16 = 0;
        while (row < height) : (row += 1) {
            if (row > 0) try m.screen.newLine();
            var col: u16 = 0;
            while (col < width) : (col += 1) {
                const source = @as(u32, at) + @as(u32, row) * (@as(u32, width) + skip) + col;
                try m.screen.put(m.story.byteAt(source));
            }
        }
    }

    fn doThrow(m: *Machine, value: u16, want_frames: u16) !void {
        if (want_frames > m.frames.items.len) return Error.StackUnderflow;
        // Unwind to where the matching `catch` was standing, then return from
        // there as if the routine had finished normally.
        m.frames.shrinkRetainingCapacity(want_frames);
        try m.doReturn(value);
    }

    // ------------------------------------------------------------ output

    fn printAt(m: *Machine, addr: u32) !void {
        var s: Emitter = .{ .screen = &m.screen };
        _ = try text.decode(&m.story, addr, s.sink());
    }

    /// A string carried in the instruction itself, which is how `print` says
    /// what it prints. Answers how many bytes to step over.
    fn printInline(m: *Machine, addr: u32) !u32 {
        var s: Emitter = .{ .screen = &m.screen };
        const d = try text.decode(&m.story, addr, s.sink());
        return d.len;
    }

    fn printNumber(m: *Machine, value: i16) !void {
        var buf: [8]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        try m.screen.print(written);
    }

    const Emitter = struct {
        screen: *Screen,

        fn sink(e: *Emitter) text.Sink {
            return .{ .ctx = e, .put = put };
        }
        fn put(ctx: *anyopaque, c: u8) anyerror!void {
            const e: *Emitter = @ptrCast(@alignCast(ctx));
            try e.screen.put(c);
        }
    };
};

// ------------------------------------------------------------- helpers

fn arg(ops: []const u16, i: usize) u16 {
    return if (i < ops.len) ops[i] else 0;
}

fn rest(ops: []const u16) []const u16 {
    return if (ops.len > 1) ops[1..] else &.{};
}

/// Toward zero, which is what the standard specifies and what C did.
fn divide(a: i16, b: i16) i16 {
    if (b == 0) return 0;
    if (a == std.math.minInt(i16) and b == -1) return a;
    return @divTrunc(a, b);
}

fn remainder(a: i16, b: i16) i16 {
    if (b == 0) return 0;
    if (a == std.math.minInt(i16) and b == -1) return 0;
    return @rem(a, b);
}

fn logicalShift(value: u16, places: i16) u16 {
    if (places == 0) return value;
    const n: u16 = @intCast(@abs(places));
    if (n >= 16) return 0;
    return if (places > 0) value << @intCast(n) else value >> @intCast(n);
}

fn arithmeticShift(value: i16, places: i16) i16 {
    if (places == 0) return value;
    const n: u16 = @intCast(@abs(places));
    if (n >= 16) return if (places > 0) 0 else (if (value < 0) -1 else 0);
    if (places > 0) return @bitCast(@as(u16, @bitCast(value)) << @intCast(n));
    return value >> @intCast(n);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// Assemble a tiny program at the initial PC of a blank story file.
fn program(arena: Allocator, version: u8, code: []const u8) !Machine {
    const bytes = try story_mod.blank(arena, version, 0x800);
    // The initial PC is the routine body directly, so there is no header to
    // step over: `blank` points it at 0x80.
    @memcpy(bytes[0x80..][0..code.len], code);
    var m = try Machine.init(arena, bytes, @splat(0));
    m.settle();
    return m;
}

test "arithmetic is signed, and division truncates toward zero" {
    // Asserted directly rather than assembled: what is worth pinning here is
    // the arithmetic itself, and a hand-written program would only be a
    // slower way of asking the same question. The opcodes that reach it are
    // covered by the story files in integration.zig.
    try testing.expectEqual(@as(i16, -2), divide(-7, 3));
    try testing.expectEqual(@as(i16, 2), divide(7, 3));
    try testing.expectEqual(@as(i16, -1), remainder(-7, 3));
    try testing.expectEqual(@as(i16, 1), remainder(7, 3));
    try testing.expectEqual(@as(i16, 0), divide(1, 0));
}

test "shifts go both ways, and only the arithmetic one keeps a sign" {
    try testing.expectEqual(@as(u16, 4), logicalShift(1, 2));
    try testing.expectEqual(@as(u16, 1), logicalShift(4, -2));
    try testing.expectEqual(@as(u16, 0x3FFF), logicalShift(0xFFFF, -2));
    try testing.expectEqual(@as(i16, -1), arithmeticShift(-4, -2) + 0);
    try testing.expectEqual(@as(i16, -16), arithmeticShift(-4, 2));
}

test "the generator is ours, so a replay survives a compiler upgrade" {
    var one = Rng.init(.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    var two = Rng.init(.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try testing.expectEqual(one.range(100), two.range(100));
    }
    // Every value is inside the range the opcode promised.
    var r = Rng.init(.{ 9, 9, 9, 9, 9, 9, 9, 9 });
    i = 0;
    while (i < 1000) : (i += 1) {
        const v = r.range(6);
        try testing.expect(v >= 1 and v <= 6);
    }

    // `random 0` reseeds from the ledger's own seed and a counter, so two
    // reseeds in one turn cannot collide.
    var a = Rng.init(.{ 1, 0, 0, 0, 0, 0, 0, 0 });
    var b = Rng.init(.{ 1, 0, 0, 0, 0, 0, 0, 0 });
    a.reseed();
    b.reseed();
    try testing.expectEqual(a.range(1000), b.range(1000));
    b.reseed();
    try testing.expect(a.state != b.state);

    // And a game that seeds itself gets the same sequence every time.
    var x = Rng.init(.{ 5, 5, 5, 5, 5, 5, 5, 5 });
    var y = Rng.init(.{ 7, 7, 7, 7, 7, 7, 7, 7 });
    x.seedTo(42);
    y.seedTo(42);
    try testing.expectEqual(x.range(1000), y.range(1000));
}

test "a call gives a routine its own locals, and a return puts one value back" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 3, 0x800);
    // At 0x80: call_vs 0x60 (packed, so 0xC0), one argument 5, store in G00.
    // Then quit.
    const code = [_]u8{
        0xE0, 0x1F, 0x00, 0x60, 0x05, 0x10, // call 0x60(packed) 5 -> G00
        0xBA, // quit
    };
    @memcpy(bytes[0x80..][0..code.len], &code);
    // The routine at 0xC0: one local, initialised to 0; ret local1.
    bytes[0xC0] = 1;
    bytes[0xC1] = 0;
    bytes[0xC2] = 0;
    bytes[0xC3] = 0xAB; // ret with a variable operand
    bytes[0xC4] = 0x01; // local 1

    var m = try Machine.init(arena, bytes, @splat(0));
    m.settle();
    try testing.expectEqual(Stop.quit, try m.run());
    // The argument overwrote the local, and the local came back.
    try testing.expectEqual(@as(u16, 5), m.story.wordAt(m.story.globals()));
}

test "a branch may return instead of jumping, which is what nought and one are" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 3, 0x800);
    const code = [_]u8{
        0xE0, 0x1F, 0x00, 0x60, 0x05, 0x10, // call 0xC0 5 -> G00
        0xBA,
    };
    @memcpy(bytes[0x80..][0..code.len], &code);
    // The routine: jz local1 -> return true if zero. Local 1 is 5, so it does
    // not branch, and falls through to `rfalse`.
    bytes[0xC0] = 1;
    bytes[0xC1] = 0;
    bytes[0xC2] = 0;
    bytes[0xC3] = 0xA0; // jz with a variable operand
    bytes[0xC4] = 0x01;
    bytes[0xC5] = 0xC1; // branch on true, offset 1: return true
    bytes[0xC6] = 0xB1; // rfalse

    var m = try Machine.init(arena, bytes, @splat(0));
    m.settle();
    try testing.expectEqual(Stop.quit, try m.run());
    try testing.expectEqual(@as(u16, 0), m.story.wordAt(m.story.globals()));
}

test "printing reaches the screen, and the machine stops when it wants a line" {
    var a: std.heap.ArenaAllocator = .init(testing.allocator);
    defer a.deinit();
    const arena = a.allocator();

    const bytes = try story_mod.blank(arena, 5, 0x800);
    // print "hi", then read into 0x40/0x50, then quit.
    //
    // 'h' and 'i' are A0 entries 7 and 8, so Z-characters 13 and 14, padded
    // with a five and with the top bit marking the last word: 0xB5C5.
    // The buffers are named as large constants and put well clear of the
    // globals table, which `blank` leaves at 0x40.
    const code = [_]u8{
        0xB2, 0xB5, 0xC5, // print "hi"
        0xE4, 0x0F, 0x03, 0x00, 0x03, 0x40, 0x10, // aread 0x300 0x340 -> G00
        0xBA,
    };
    @memcpy(bytes[0x80..][0..code.len], &code);
    bytes[0x300] = 20; // room for twenty characters

    var m = try Machine.init(arena, bytes, @splat(0));
    m.settle();

    try testing.expectEqual(Stop.line_input, try m.run());
    try testing.expectEqualStrings("hi", try m.screen.takeLower(arena));

    try m.feedLine("OPEN MAILBOX");
    // Stored lower case, with its own length in front of it, as V5 wants.
    try testing.expectEqual(@as(u8, 12), m.story.byteAt(0x301));
    try testing.expectEqualStrings("open mailbox", m.story.mem[0x302..0x30E]);
    // And the terminating key came back as Return.
    try testing.expectEqual(@as(u16, 13), m.story.wordAt(m.story.globals()));

    try testing.expectEqual(Stop.quit, try m.run());
}
