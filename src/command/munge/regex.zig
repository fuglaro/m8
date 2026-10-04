//! A regular expression engine, small enough to read in one sitting.
//!
//! Bundled rather than depended on, and deliberately not general. What a scan
//! over source needs is a pattern per line and the offsets it matched at, so
//! there are no capture slots, no matching across a newline, and no Unicode
//! case folding. Dropping captures is what keeps the whole thing small: a
//! thread is a program counter and a start offset, eight bytes, copied by
//! value, and the match loop never allocates.
//!
//! Parse to an AST, compile the AST to bytecode, run the bytecode on a Pike
//! VM. The VM walks every live thread in lock step, one input byte at a time,
//! so the work is bounded by pattern size times input size and a pattern can
//! never blow up the way a backtracker can. There is no timeout because there
//! is nothing to time out — linear is structural here, not a tuning.
//!
//! What a scan actually asks is usually "where is this literal", so the two
//! fast paths matter more than the VM does: a pattern that is nothing but
//! literal bytes never compiles at all, and one that merely begins with
//! literal bytes uses them to skip to candidate positions and runs the VM only
//! there.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ------------------------------------------------------------------ program

/// A 256 bit set, which is every byte a class could hold.
pub const Class = struct {
    bits: [4]u64 = .{ 0, 0, 0, 0 },

    fn set(c: *Class, b: u8) void {
        c.bits[b >> 6] |= @as(u64, 1) << @truncate(b);
    }

    fn range(c: *Class, from: u8, to: u8) void {
        var b: usize = from;
        while (b <= to) : (b += 1) c.set(@intCast(b));
    }

    fn has(c: Class, b: u8) bool {
        return c.bits[b >> 6] & (@as(u64, 1) << @truncate(b)) != 0;
    }

    fn negate(c: *Class) void {
        for (&c.bits) |*w| w.* = ~w.*;
    }
};

/// Where a zero width assertion holds. Everything here is about the edges of
/// one line, because a line is all this ever looks at.
pub const Where = enum { start, end, word, not_word };

/// Five things to run, and an assertion. `byte` and `class` consume input;
/// `split` and `jmp` are how everything else is spelled; `match` is the end.
pub const Op = union(enum) {
    byte: u8,
    class: u32,
    /// Two ways on, in priority order. `a` is tried first, which is what
    /// makes alternation leftmost-first and a greedy repeat greedy.
    split: struct { a: u32, b: u32 },
    jmp: u32,
    assert: Where,
    match,
};

pub const Program = struct {
    ops: []const Op,
    classes: []const Class,
    /// The whole pattern, when it is nothing but bytes. The VM never runs.
    literal: ?[]const u8 = null,
    /// Bytes every match must start with, for skipping ahead to candidates.
    prefix: ?[]const u8 = null,
    /// `^`, so only one start position is worth trying.
    anchored: bool = false,
};

pub const Match = struct { at: usize, end: usize };

pub const Compiled = union(enum) {
    program: Program,
    /// Said plainly, naming the construct, because the model that wrote the
    /// pattern is the one who has to fix it.
    bad: []const u8,
};

// ------------------------------------------------------------------- syntax

const Node = union(enum) {
    empty,
    byte: u8,
    class: Class,
    assert: Where,
    cat: []Node,
    alt: []Node,
    rep: Rep,
};

const Rep = struct {
    of: *Node,
    min: u32,
    /// Null is unbounded.
    max: ?u32,
    greedy: bool,
};

const Parser = struct {
    arena: Allocator,
    src: []const u8,
    at: usize = 0,
    /// `(?i)` is a flag rather than a node: it changes what a byte compiles
    /// into, and it stays changed for the rest of the pattern.
    fold: bool = false,
    why: ?[]const u8 = null,

    fn fail(p: *Parser, what: []const u8) error{Bad} {
        if (p.why == null) p.why = what;
        return error.Bad;
    }

    fn done(p: Parser) bool {
        return p.at >= p.src.len;
    }

    fn peek(p: Parser) u8 {
        return if (p.done()) 0 else p.src[p.at];
    }

    fn take(p: *Parser) u8 {
        const c = p.peek();
        p.at += 1;
        return c;
    }

    fn eat(p: *Parser, c: u8) bool {
        if (p.done() or p.src[p.at] != c) return false;
        p.at += 1;
        return true;
    }

    /// `a|b|c`
    fn alternation(p: *Parser) error{ Bad, OutOfMemory }!Node {
        var arms: std.ArrayList(Node) = .empty;
        try arms.append(p.arena, try p.sequence());
        while (p.eat('|')) try arms.append(p.arena, try p.sequence());
        if (arms.items.len == 1) return arms.items[0];
        return .{ .alt = arms.items };
    }

    /// Everything up to a `|` or a `)`.
    fn sequence(p: *Parser) error{ Bad, OutOfMemory }!Node {
        var parts: std.ArrayList(Node) = .empty;
        while (!p.done() and p.peek() != '|' and p.peek() != ')')
            try parts.append(p.arena, try p.repeated());
        if (parts.items.len == 0) return .empty;
        if (parts.items.len == 1) return parts.items[0];
        return .{ .cat = parts.items };
    }

    /// An atom and whatever repeats it.
    fn repeated(p: *Parser) error{ Bad, OutOfMemory }!Node {
        var node = try p.atom();
        while (!p.done()) {
            const min: u32, const max: ?u32 = switch (p.peek()) {
                '*' => .{ 0, null },
                '+' => .{ 1, null },
                '?' => .{ 0, 1 },
                '{' => blk: {
                    const save = p.at;
                    if (p.counted()) |c| break :blk c;
                    // Not a count after all, so it was somebody's `{`.
                    p.at = save;
                    return node;
                },
                else => return node,
            };
            if (p.peek() != '{') _ = p.take();

            const of = try p.arena.create(Node);
            of.* = node;
            node = .{ .rep = .{
                .of = of,
                .min = min,
                .max = max,
                .greedy = !p.eat('?'),
            } };
        }
        return node;
    }

    /// `{n}`, `{n,}`, `{n,m}`, or nothing.
    fn counted(p: *Parser) ?struct { u32, ?u32 } {
        std.debug.assert(p.peek() == '{');
        p.at += 1;
        const min = p.digits() orelse return null;
        if (p.eat('}')) return .{ min, min };
        if (!p.eat(',')) return null;
        if (p.eat('}')) return .{ min, null };
        const max = p.digits() orelse return null;
        if (!p.eat('}')) return null;
        return .{ min, max };
    }

    fn digits(p: *Parser) ?u32 {
        const from = p.at;
        while (!p.done() and std.ascii.isDigit(p.peek())) p.at += 1;
        if (p.at == from) return null;
        return std.fmt.parseInt(u32, p.src[from..p.at], 10) catch null;
    }

    fn atom(p: *Parser) error{ Bad, OutOfMemory }!Node {
        switch (p.take()) {
            '(' => return p.group(),
            '[' => return p.bracket(),
            '.' => {
                // Single line, so a dot is everything but the newline that
                // would have ended the line anyway.
                var c: Class = .{};
                c.negate();
                c.bits[0] &= ~(@as(u64, 1) << '\n');
                return .{ .class = c };
            },
            '^' => return .{ .assert = .start },
            '$' => return .{ .assert = .end },
            '\\' => return p.escaped(),
            '*', '+', '?' => return p.fail("a repeat with nothing to repeat"),
            ')' => return p.fail("a ) with no ("),
            else => |c| return p.literal(c),
        }
    }

    /// A byte, folded into a class of both its cases when `(?i)` is on.
    fn literal(p: *Parser, c: u8) Node {
        if (!p.fold or !std.ascii.isAlphabetic(c)) return .{ .byte = c };
        var set: Class = .{};
        set.set(std.ascii.toLower(c));
        set.set(std.ascii.toUpper(c));
        return .{ .class = set };
    }

    /// `(...)`, `(?:...)`, `(?i)`, `(?i:...)`.
    ///
    /// A capturing group parses and is then thrown away, because nothing here
    /// can report what it captured. Saying so would be worse than quietly
    /// treating it as a group: the pattern still means what it looks like.
    fn group(p: *Parser) error{ Bad, OutOfMemory }!Node {
        var scoped = false;
        const was = p.fold;
        if (p.eat('?')) {
            if (p.eat('i')) {
                p.fold = true;
                if (p.eat(')')) return .empty;
                scoped = true;
            }
            if (!p.eat(':')) {
                if (p.peek() == '=' or p.peek() == '!' or p.peek() == '<')
                    return p.fail("lookaround, which this does not have");
                if (!scoped) return p.fail("a (? form this does not have");
            }
        }
        const inner = try p.alternation();
        if (!p.eat(')')) return p.fail("a ( with no )");
        if (scoped) p.fold = was;
        return inner;
    }

    fn escaped(p: *Parser) error{ Bad, OutOfMemory }!Node {
        if (p.done()) return p.fail("a trailing backslash");
        const c = p.take();
        switch (c) {
            'd', 'D', 'w', 'W', 's', 'S' => return .{ .class = named(c) },
            'b' => return .{ .assert = .word },
            'B' => return .{ .assert = .not_word },
            'n' => return .{ .byte = '\n' },
            't' => return .{ .byte = '\t' },
            'r' => return .{ .byte = '\r' },
            '0'...'9' => return p.fail("a backreference, which this does not have"),
            else => return p.literal(c),
        }
    }

    /// `[abc]`, `[^a-z]`, `[[:alpha:]]`, and the `\d` family inside them.
    fn bracket(p: *Parser) error{ Bad, OutOfMemory }!Node {
        var set: Class = .{};
        const negated = p.eat('^');
        var first = true;
        while (true) {
            if (p.done()) return p.fail("a [ with no ]");
            if (p.peek() == ']' and !first) {
                _ = p.take();
                break;
            }
            first = false;

            if (p.peek() == '[' and p.at + 1 < p.src.len and p.src[p.at + 1] == ':') {
                try p.posix(&set);
                continue;
            }

            var lo = p.take();
            if (lo == '\\') {
                if (p.done()) return p.fail("a trailing backslash");
                const e = p.take();
                switch (e) {
                    'd', 'D', 'w', 'W', 's', 'S' => {
                        const c = named(e);
                        for (&set.bits, c.bits) |*w, b| w.* |= b;
                        continue;
                    },
                    'n' => lo = '\n',
                    't' => lo = '\t',
                    'r' => lo = '\r',
                    else => lo = e,
                }
            }

            // A `-` that is not between two things is just a `-`.
            if (p.peek() == '-' and p.at + 1 < p.src.len and p.src[p.at + 1] != ']') {
                _ = p.take();
                const hi = p.take();
                if (hi < lo) return p.fail("a range that runs backwards");
                set.range(lo, hi);
                if (p.fold) {
                    set.range(std.ascii.toLower(lo), std.ascii.toLower(hi));
                    set.range(std.ascii.toUpper(lo), std.ascii.toUpper(hi));
                }
                continue;
            }

            set.set(lo);
            if (p.fold and std.ascii.isAlphabetic(lo)) {
                set.set(std.ascii.toLower(lo));
                set.set(std.ascii.toUpper(lo));
            }
        }
        if (negated) {
            set.negate();
            set.bits[0] &= ~(@as(u64, 1) << '\n');
        }
        return .{ .class = set };
    }

    fn posix(p: *Parser, set: *Class) error{ Bad, OutOfMemory }!void {
        p.at += 2;
        const from = p.at;
        while (!p.done() and p.peek() != ':') p.at += 1;
        const name = p.src[from..p.at];
        if (!p.eat(':') or !p.eat(']')) return p.fail("an unterminated [[:name:]]");

        if (std.mem.eql(u8, name, "alpha")) {
            set.range('a', 'z');
            set.range('A', 'Z');
        } else if (std.mem.eql(u8, name, "digit")) {
            set.range('0', '9');
        } else if (std.mem.eql(u8, name, "alnum")) {
            set.range('a', 'z');
            set.range('A', 'Z');
            set.range('0', '9');
        } else if (std.mem.eql(u8, name, "space")) {
            for ([_]u8{ ' ', '\t', '\r', '\n', 11, 12 }) |b| set.set(b);
        } else if (std.mem.eql(u8, name, "upper")) {
            set.range('A', 'Z');
        } else if (std.mem.eql(u8, name, "lower")) {
            set.range('a', 'z');
        } else if (std.mem.eql(u8, name, "punct")) {
            for (33..48) |b| set.set(@intCast(b));
            for (58..65) |b| set.set(@intCast(b));
            for (91..97) |b| set.set(@intCast(b));
            for (123..127) |b| set.set(@intCast(b));
        } else if (std.mem.eql(u8, name, "xdigit")) {
            set.range('0', '9');
            set.range('a', 'f');
            set.range('A', 'F');
        } else return p.fail("a [[:name:]] this does not have");
    }
};

fn named(c: u8) Class {
    var set: Class = .{};
    switch (std.ascii.toLower(c)) {
        'd' => set.range('0', '9'),
        'w' => {
            set.range('a', 'z');
            set.range('A', 'Z');
            set.range('0', '9');
            set.set('_');
        },
        else => for ([_]u8{ ' ', '\t', '\r', '\n', 11, 12 }) |b| set.set(b),
    }
    if (std.ascii.isUpper(c)) {
        set.negate();
        set.bits[0] &= ~(@as(u64, 1) << '\n');
    }
    return set;
}

// ------------------------------------------------------------------ compile

const Emitter = struct {
    arena: Allocator,
    ops: std.ArrayList(Op) = .empty,
    classes: std.ArrayList(Class) = .empty,

    fn here(e: Emitter) u32 {
        return @intCast(e.ops.items.len);
    }

    fn emit(e: *Emitter, op: Op) !u32 {
        const at = e.here();
        try e.ops.append(e.arena, op);
        return at;
    }

    fn class(e: *Emitter, c: Class) !u32 {
        const at: u32 = @intCast(e.classes.items.len);
        try e.classes.append(e.arena, c);
        return e.emit(.{ .class = at });
    }

    fn node(e: *Emitter, n: Node) error{OutOfMemory}!void {
        switch (n) {
            .empty => {},
            .byte => |b| _ = try e.emit(.{ .byte = b }),
            .class => |c| _ = try e.class(c),
            .assert => |w| _ = try e.emit(.{ .assert = w }),
            .cat => |parts| for (parts) |part| try e.node(part),
            .alt => |arms| try e.alternation(arms),
            .rep => |r| try e.repeat(r),
        }
    }

    /// `a|b` is a split to the first arm, which is what makes the leftmost
    /// arm win when both could match.
    fn alternation(e: *Emitter, arms: []const Node) error{OutOfMemory}!void {
        if (arms.len == 1) return e.node(arms[0]);
        const split = try e.emit(.{ .split = .{ .a = 0, .b = 0 } });
        const first = e.here();
        try e.node(arms[0]);
        const jump = try e.emit(.{ .jmp = 0 });
        const second = e.here();
        try e.alternation(arms[1..]);
        e.ops.items[split] = .{ .split = .{ .a = first, .b = second } };
        e.ops.items[jump] = .{ .jmp = e.here() };
    }

    /// A counted repeat is spelled out by duplicating what it repeats, which
    /// is why `{n,m}` is bounded by the pattern rather than by a limit.
    ///
    /// Every optional copy leaves to the same place, so skipping the first one
    /// skips the rest — which is what an optional run means.
    fn repeat(e: *Emitter, r: Rep) error{OutOfMemory}!void {
        for (0..r.min) |_| try e.node(r.of.*);

        if (r.max) |max| {
            var splits: std.ArrayList(u32) = .empty;
            var bodies: std.ArrayList(u32) = .empty;
            for (r.min..max) |_| {
                try splits.append(e.arena, try e.emit(.{ .split = .{ .a = 0, .b = 0 } }));
                try bodies.append(e.arena, e.here());
                try e.node(r.of.*);
            }
            const after = e.here();
            for (splits.items, bodies.items) |at, body| e.ops.items[at] = if (r.greedy)
                .{ .split = .{ .a = body, .b = after } }
            else
                .{ .split = .{ .a = after, .b = body } };
            return;
        }

        // Unbounded: a loop that may be taken again or left.
        const split = try e.emit(.{ .split = .{ .a = 0, .b = 0 } });
        const body = e.here();
        try e.node(r.of.*);
        _ = try e.emit(.{ .jmp = split });
        const after = e.here();
        e.ops.items[split] = if (r.greedy)
            .{ .split = .{ .a = body, .b = after } }
        else
            .{ .split = .{ .a = after, .b = body } };
    }
};

/// A pattern, ready to run. The AST lives on the arena and is finished with
/// once this returns; the bytecode is what is kept.
pub fn compile(arena: Allocator, pattern: []const u8) !Compiled {
    var p = Parser{ .arena = arena, .src = pattern };
    const ast = p.alternation() catch |err| switch (err) {
        error.Bad => return .{ .bad = p.why orelse "something this does not have" },
        else => |e| return e,
    };
    if (!p.done()) return .{ .bad = "a ) with no (" };

    // Nothing but bytes: there is no reason to run a machine over it.
    if (try flatten(arena, ast)) |text| return .{ .program = .{
        .ops = &.{},
        .classes = &.{},
        .literal = text,
    } };

    var e = Emitter{ .arena = arena };
    try e.node(ast);
    _ = try e.emit(.match);

    return .{ .program = .{
        .ops = e.ops.items,
        .classes = e.classes.items,
        .prefix = try leading(arena, ast),
        .anchored = anchoredAt(ast),
    } };
}

/// The pattern as plain text, when that is all it is.
fn flatten(arena: Allocator, n: Node) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    if (!try gather(arena, n, &out, false)) return null;
    if (out.items.len == 0) return null;
    return out.items;
}

/// The bytes every match has to start with, which is what the prefilter skips
/// to. A prefix is worth having even when the rest is a machine.
fn leading(arena: Allocator, n: Node) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    _ = try gather(arena, n, &out, true);
    if (out.items.len < 2) return null;
    return out.items;
}

/// Bytes off the front of a node. Answers whether the node was *entirely*
/// bytes, which is what tells a whole-pattern literal from a mere prefix.
fn gather(arena: Allocator, n: Node, out: *std.ArrayList(u8), partial: bool) !bool {
    switch (n) {
        .byte => |b| {
            try out.append(arena, b);
            return true;
        },
        .cat => |parts| {
            for (parts) |part| if (!try gather(arena, part, out, partial)) return false;
            return true;
        },
        else => return false,
    }
}

fn anchoredAt(n: Node) bool {
    return switch (n) {
        .assert => |w| w == .start,
        .cat => |parts| parts.len > 0 and anchoredAt(parts[0]),
        else => false,
    };
}

// ----------------------------------------------------------------------- vm

/// Everything the machine needs, allocated once and reused for every line.
///
/// Two thread lists sized to the program, swapped each byte, and a sparse set
/// so that a program counter already queued is recognised in constant time
/// without anything to clear between steps.
pub const Vm = struct {
    prog: Program,
    now: List,
    next: List,

    const Thread = struct { pc: u32, at: u32 };

    /// One step's worth of threads, with its own generation so that a program
    /// counter already queued in *this* step is recognised in constant time.
    /// Clearing is bumping the generation, which is why nothing is ever
    /// memset between bytes.
    const List = struct {
        t: []Thread,
        marks: []u32,
        n: usize = 0,
        era: u32 = 0,

        fn reset(l: *List) void {
            l.n = 0;
            l.era += 1;
        }
    };

    pub fn init(arena: Allocator, prog: Program) !Vm {
        const n = @max(prog.ops.len, 1);
        return .{
            .prog = prog,
            .now = .{ .t = try arena.alloc(Thread, n), .marks = try arena.alloc(u32, n) },
            .next = .{ .t = try arena.alloc(Thread, n), .marks = try arena.alloc(u32, n) },
        };
    }

    /// The leftmost match at or after `from`, or nothing.
    pub fn find(vm: *Vm, line: []const u8, from: usize) ?Match {
        if (vm.prog.literal) |text| {
            const at = std.mem.indexOfPos(u8, line, from, text) orelse return null;
            return .{ .at = at, .end = at + text.len };
        }

        var at = from;
        while (true) {
            // The prefilter: no match can begin before the bytes every match
            // begins with, so the machine never runs at those positions.
            if (vm.prog.prefix) |pre| {
                at = std.mem.indexOfPos(u8, line, at, pre) orelse return null;
            }
            if (vm.run(line, at)) |m| return m;
            if (vm.prog.anchored and vm.prog.prefix == null) return null;
            if (at >= line.len) return null;
            at += 1;
        }
    }

    /// One attempt, from one position. Threads are walked in priority order,
    /// so the first `match` reached cuts off everything below it — which is
    /// leftmost-first, the way a backtracker would have answered.
    fn run(vm: *Vm, line: []const u8, from: usize) ?Match {
        @memset(vm.now.marks, 0);
        @memset(vm.next.marks, 0);
        vm.now.era = 1;
        vm.next.era = 1;
        vm.now.n = 0;
        vm.next.n = 0;
        vm.add(&vm.now, 0, line, from);

        var end: ?usize = null;
        var at = from;
        while (true) : (at += 1) {
            var i: usize = 0;
            while (i < vm.now.n) : (i += 1) {
                const t = vm.now.t[i];
                switch (vm.prog.ops[t.pc]) {
                    .byte => |b| {
                        if (at < line.len and line[at] == b)
                            vm.add(&vm.next, t.pc + 1, line, at + 1);
                    },
                    .class => |c| {
                        if (at < line.len and vm.prog.classes[c].has(line[at]))
                            vm.add(&vm.next, t.pc + 1, line, at + 1);
                    },
                    .match => {
                        end = at;
                        // Everything below this thread is lower priority and
                        // cannot win, so it is not worth stepping.
                        break;
                    },
                    // Reached only through `add`, which follows them.
                    .split, .jmp, .assert => {},
                }
            }

            if (at >= line.len) break;
            std.mem.swap(List, &vm.now, &vm.next);
            vm.next.reset();
            if (vm.now.n == 0) break;
        }

        if (end) |e| return .{ .at = from, .end = e };
        return null;
    }

    /// Queue a thread, following everything that consumes nothing. A program
    /// counter already in this list is dropped, so the list can never outgrow
    /// the program and the work per byte is bounded by its length.
    fn add(vm: *Vm, l: *List, pc: u32, line: []const u8, at: usize) void {
        if (l.marks[pc] == l.era) return;
        l.marks[pc] = l.era;

        switch (vm.prog.ops[pc]) {
            .jmp => |to| vm.add(l, to, line, at),
            .split => |s| {
                vm.add(l, s.a, line, at);
                vm.add(l, s.b, line, at);
            },
            .assert => |w| if (holds(w, line, at)) vm.add(l, pc + 1, line, at),
            else => {
                l.t[l.n] = .{ .pc = pc, .at = @intCast(at) };
                l.n += 1;
            },
        }
    }
};

fn holds(w: Where, line: []const u8, at: usize) bool {
    const before = at > 0 and isWord(line[at - 1]);
    const after = at < line.len and isWord(line[at]);
    return switch (w) {
        .start => at == 0,
        .end => at == line.len,
        .word => before != after,
        .not_word => before == after,
    };
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn firstMatch(arena: Allocator, pattern: []const u8, line: []const u8) !?Match {
    const c = try compile(arena, pattern);
    switch (c) {
        .bad => |why| {
            std.debug.print("compile failed: {s}\n", .{why});
            return error.BadPattern;
        },
        .program => |p| {
            var vm = try Vm.init(arena, p);
            return vm.find(line, 0);
        },
    }
}

fn matchedText(arena: Allocator, pattern: []const u8, line: []const u8) !?[]const u8 {
    const m = try firstMatch(arena, pattern, line) orelse return null;
    return line[m.at..m.end];
}

test "a pattern of nothing but bytes never compiles" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const c = try compile(arena, "fn parse");
    try testing.expect(c.program.literal != null);
    try testing.expectEqual(@as(usize, 0), c.program.ops.len);
    try testing.expectEqualStrings("fn parse", (try matchedText(arena, "fn parse", "  fn parse(")).?);
}

test "the pieces of the syntax" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cases = [_]struct { []const u8, []const u8, ?[]const u8 }{
        .{ "a.c", "xabcx", "abc" },
        .{ "a[0-9]+", "aa12b", "a12" },
        .{ "[[:alpha:]]+", "-- hello --", "hello" },
        .{ "\\d{2,3}", "x12345", "123" },
        .{ "\\w+", "  spam_1!", "spam_1" },
        .{ "\\s\\S", "ab cd", " c" },
        .{ "^fn", "fn main", "fn" },
        .{ "^fn", " fn main", null },
        .{ "end$", "the end", "end" },
        .{ "end$", "the end is", null },
        .{ "\\bcat\\b", "a cat here", "cat" },
        .{ "\\bcat\\b", "concatenate", null },
        .{ "(foo|bar)baz", "a barbaz", "barbaz" },
        .{ "(?:ab)+", "xababab", "ababab" },
        .{ "a+?b", "aaab", "aaab" },
        .{ "colou?r", "the color red", "color" },
        .{ "(?i)HELLO", "say hello", "hello" },
        .{ "(?i:war)n", "WARn", "WARn" },
        .{ "[^a-z]+", "abc123abc", "123" },
        .{ "x{3}", "xxxx", "xxx" },
        .{ "ab{2,}", "abbbc", "abbb" },
    };
    for (cases) |c| {
        const got = try matchedText(arena, c[0], c[1]);
        if (c[2]) |want| {
            try testing.expect(got != null);
            try testing.expectEqualStrings(want, got.?);
        } else try testing.expect(got == null);
    }
}

test "alternation is leftmost-first, not leftmost-longest" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqualStrings("ab", (try matchedText(arena, "ab|abc", "abcd")).?);
}

test "a prefix is used to skip, and finds the same thing" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const c = try compile(arena, "pub fn [a-z]+");
    try testing.expect(c.program.prefix != null);
    try testing.expectEqualStrings("pub fn ", c.program.prefix.?);
    try testing.expectEqualStrings(
        "pub fn parse",
        (try matchedText(arena, "pub fn [a-z]+", "    pub fn parse(a")).?,
    );
}

test "what it does not have, it says" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    for ([_][]const u8{ "(?=foo)", "a\\1", "[a-", "(ab", "*x" }) |bad| {
        const c = try compile(arena, bad);
        try testing.expect(c == .bad);
        try testing.expect(c.bad.len > 0);
    }
}

test "nothing pathological takes long" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The pattern that makes a backtracker hang. Linear time is structural
    // here, so it simply answers.
    const line = "a" ** 40;
    try testing.expect(try firstMatch(arena, "(a+)+b", line) == null);
}
