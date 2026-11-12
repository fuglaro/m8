//! `encode` — a ledger, in some other format.
//!
//! The ledger arrives on stdin, and every 🧠 in it is expanded into what it
//! names. What comes out is one api's view of that.
//!
//! `m8` is a format like any other here, which is why `m8 encode m8` is how a
//! chat gets flattened into a single document. It is the only one that loses
//! nothing.

const std = @import("std");
const codec = @import("../codec.zig");
const config = @import("../config.zig");
const address = @import("../address.zig");
const agent = @import("../agent.zig");
const ledger = @import("../ledger.zig");
const doc = @import("../m8/doc.zig");
const model = @import("../m8/model.zig");
const api = @import("../api.zig");
const link = @import("../link.zig");
const Ctx = api.Ctx;

pub const command: api.Command = .{
    .name = "encode",
    .summary = "write a ledger as some api's request",
    .run = run,
    .help = help,
};

fn run(ctx: Ctx) !u8 {
    // m8 is the lossless view of a ledger, so it is the useful default when
    // no projection was requested explicitly.
    var name: []const u8 = "m8";
    var breaks: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const arg = ctx.args[i];
        if (!std.mem.eql(u8, arg, "--break")) {
            name = arg;
            continue;
        }
        i += 1;
        if (i == ctx.args.len) {
            try ctx.err.writeAll("m8 encode: `--break` is followed by the name to stop at\n");
            return 1;
        }
        // A 🧠 line pasted in names what it printed, mark and all.
        try breaks.append(ctx.arena, address.body(ctx.args[i]) orelse ctx.args[i]);
    }
    const c = codec.find(name) orelse {
        try ctx.err.print("m8 encode: no format named '{s}'\n", .{name});
        try help(ctx, ctx.err);
        try ctx.err.flush();
        return 1;
    };

    const arena = ctx.arena;
    var diag: doc.Diagnostic = .{};
    const given = try doc.parse(arena, ctx.in, &diag);

    const dirs = try config.discover(arena, ctx.io, ctx.env);
    const expanded = try ledger.expandUntil(
        arena,
        ctx.io,
        dirs,
        given,
        doc.detect(ctx.in) orelse .md,
        .{ .names = breaks.items },
    );

    var records: std.ArrayList(doc.Record) = .empty;
    try records.appendSlice(arena, try ledger.inheritedAgent(arena, ctx.io, dirs));
    try records.appendSlice(arena, expanded.records);

    const env = try api.childEnvironment(arena, ctx, &.{});
    const handed = try link.handOver(arena, ctx.io, dirs, env, records.items);
    try ctx.out.writeAll(try c.encode(arena, handed, try target(ctx, records.items)));
    return 0;
}

/// Provider defaults and model parameters are translated only when the
/// selected provider declares a `param_keys` table. Without one, legacy
/// pass-through behavior is retained.
fn target(ctx: Ctx, records: []const doc.Record) !codec.Target {
    const def = try agent.project(ctx.arena, records);
    var source: std.ArrayList(model.Param) = .empty;
    const matching_provider = def.provider.len > 0 and
        std.mem.eql(u8, ctx.env.get("M8_PROVIDER_NAME") orelse "", def.provider);
    if (matching_provider) {
        var it = ctx.env.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.eql(u8, key, "M8_PROVIDER_param_values") or
                std.mem.eql(u8, key, "M8_PROVIDER_param_keys")) continue;
            const prefix = "M8_PROVIDER_param_";
            if (!std.mem.startsWith(u8, key, prefix)) continue;
            const field = key[prefix.len..];
            if (field.len == 0) continue;
            for (def.params) |p| {
                if (std.mem.eql(u8, p.key, field)) break;
            } else if (model.json(ctx.arena, entry.value_ptr.*) != .null) {
                try source.append(ctx.arena, .{ .key = field, .value = entry.value_ptr.* });
            }
        }
    }
    for (def.params) |p| {
        if (model.json(ctx.arena, p.value) == .null) {
            // A model-level null explicitly removes a provider default.
            for (source.items, 0..) |old, i| if (std.mem.eql(u8, old.key, p.key)) {
                _ = source.orderedRemove(i);
                break;
            };
        } else {
            var replaced = false;
            for (source.items) |*old| if (std.mem.eql(u8, old.key, p.key)) {
                old.value = p.value;
                replaced = true;
                break;
            };
            if (!replaced) try source.append(ctx.arena, p);
        }
    }

    const mapping_text = if (matching_provider) ctx.env.get("M8_PROVIDER_param_keys") else null;
    const values_text = if (matching_provider) ctx.env.get("M8_PROVIDER_param_values") else null;
    const mapping = if (mapping_text) |text|
        (try std.json.parseFromSliceLeaky(std.json.Value, ctx.arena, text, .{}))
    else
        null;
    const values = if (values_text) |text|
        (try std.json.parseFromSliceLeaky(std.json.Value, ctx.arena, text, .{}))
    else
        null;
    if (mapping) |m| if (m != .object) return error.BadProviderParams;
    if (values) |v| if (v != .object) return error.BadProviderParamValues;

    var params: std.ArrayList(model.Param) = .empty;
    for (source.items) |p| {
        try appendTranslated(ctx.arena, &params, p, mapping, values);
    }
    return .{
        .mode = ctx.mode,
        .model = def.model,
        .params = params.items,
        .tools = try agent.offer(ctx.arena, def),
        .stream = true,
    };
}

fn appendTranslated(
    arena: std.mem.Allocator,
    params: *std.ArrayList(model.Param),
    source: model.Param,
    mapping: ?std.json.Value,
    values: ?std.json.Value,
) !void {
    var key = source.key;
    var path: []const []const u8 = &.{};
    if (mapping) |table| {
        const destination = table.object.get(source.key) orelse return error.UnmappedModelParam;
        switch (destination) {
            .null => return error.BadProviderParamPath,
            .string => |name| key = name,
            .array => |segments| {
                if (segments.items.len == 0) return error.EmptyProviderParamPath;
                var path_list: std.ArrayList([]const u8) = .empty;
                for (segments.items) |segment| {
                    if (segment != .string or segment.string.len == 0) return error.BadProviderParamPath;
                    try path_list.append(arena, segment.string);
                }
                path = path_list.items;
                key = path[0];
            },
            else => return error.BadProviderParamPath,
        }
    }

    var value = model.json(arena, source.value);
    if (values) |table| {
        if (table.object.get(source.key)) |translations| {
            if (translations != .object) return error.BadProviderParamValues;
            if (value == .string) {
                if (translations.object.get(value.string)) |translated| value = translated;
            }
        }
    }
    const serialized = try std.json.Stringify.valueAlloc(arena, value, .{});
    try params.append(arena, .{ .key = key, .path = path, .value = serialized });
}

test "provider param env defaults preserve names and explicit values override" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_PROVIDER_NAME", "local");
    try invocation.env.put("M8_PROVIDER_param_temperature", "0.4");
    try invocation.env.put("M8_PROVIDER_param_x-y_A", "[1,\"x\"]");
    try invocation.env.put("M8_PROVIDER_param_omit", "null");
    try invocation.env.put("M8_PROVIDER_params_temperature", "99");
    const ctx = invocation.ctx(&.{}, null);
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, "* :brain::/local/tiny,temperature:0.2,x-y_A:null,max_tokens:10\n", &diag);
    const params = (try target(ctx, records)).params;
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqualStrings("temperature", params[0].key);
    try std.testing.expectEqualStrings("0.2", params[0].value);
    try std.testing.expectEqualStrings("max_tokens", params[1].key);
    try std.testing.expectEqualStrings("10", params[1].value);
}

test "provider param defaults require matching selection" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_PROVIDER_param_temperature", "0.4");
    const ctx = invocation.ctx(&.{}, null);
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, "* :brain::/local/tiny\n", &diag);
    try std.testing.expectEqual(@as(usize, 0), (try target(ctx, records)).params.len);
    try invocation.env.put("M8_PROVIDER_NAME", "elsewhere");
    try std.testing.expectEqual(@as(usize, 0), (try target(ctx, records)).params.len);
}

test "provider config defaults reach request fields verbatim" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    const provider_mod = @import("../provider.zig");
    const responses = @import("../codec/openai_responses.zig");
    var invocation = try Invocation.init();
    defer invocation.deinit();
    const arena = invocation.arena.allocator();
    const config_json = try std.json.parseFromSliceLeaky(std.json.Value, arena,
        \\{"local":{"cmd":["unused"],"param_store":false,"param_maxOutputTokens":12,"param_exact-Name":["x"],"param_removed":null}}
    , .{});
    const configured = try provider_mod.read(arena, config_json.object, "local");
    try provider_mod.addEnvironment(arena, configured, &invocation.env);
    const ctx = invocation.ctx(&.{}, null);
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, "* :brain::/local/tiny\n", &diag);
    const params = (try target(ctx, records)).params;
    const body = try responses.encode(arena, &.{}, .{ .model = "mock", .params = params });
    const request = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    try std.testing.expect(!request.object.get("store").?.bool);
    try std.testing.expectEqual(@as(i64, 12), request.object.get("maxOutputTokens").?.integer);
    try std.testing.expectEqualStrings("x", request.object.get("exact-Name").?.array.items[0].string);
    try std.testing.expect(request.object.get("removed") == null);
    try std.testing.expect(request.object.get("include") == null);
}

test "provider parameter paths and enum values translate into nested request fields" {
    const Invocation = @import("../command_input_test.zig").Invocation;
    var invocation = try Invocation.init();
    defer invocation.deinit();
    try invocation.env.put("M8_PROVIDER_NAME", "test-provider");
    try invocation.env.put("M8_PROVIDER_param_keys", "{\"reasoning_effort\":[\"reasoning\",\"effort\"],\"trace\":\"trace\"}");
    try invocation.env.put("M8_PROVIDER_param_values", "{\"reasoning_effort\":{\"high\":44000}}");
    const ctx = invocation.ctx(&.{}, null);
    var diag: doc.Diagnostic = .{};
    const records = try doc.parse(ctx.arena, "* :brain::/test-provider/model,reasoning_effort:high,trace:{\"enabled\":true}\\n", &diag);
    const params = (try target(ctx, records)).params;
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqualStrings("reasoning", params[0].key);
    try std.testing.expectEqual(@as(usize, 2), params[0].path.len);
    try std.testing.expectEqualStrings("effort", params[0].path[1]);
    try std.testing.expectEqualStrings("44000", params[0].value);
    try std.testing.expectEqualStrings("trace", params[1].key);
    try std.testing.expectEqual(@as(usize, 0), params[1].path.len);
}
fn help(ctx: Ctx, w: *std.Io.Writer) !void {
    _ = ctx;
    try w.writeAll(
        \\  m8 encode [--break NAME]... [FORMAT]
        \\
        \\With no FORMAT, the ledger is written as m8, the lossless format.
        \\The ledger arrives on stdin, with every 🧠 expanded into what it
        \\names. What comes out is one api's view of it.
        \\
        \\  m8 say --no-send :demo/mathy | m8 encode m8 >ledger.md
        \\  m8 encode openai-completions <ledger.md >request.json
        \\
        \\Encoding is total and loses whatever the target cannot say, which is
        \\what makes it a projection: the ledger it came from still holds all
        \\of it. `m8` is the one format whose view is the whole ledger, which
        \\is why `encode m8` is how a chat becomes one flat document. A file a
        \\🔗 names goes as its provider entry's `upload` says, and with no
        \\`upload`, or one that fails, is an error.
        \\
        \\`--break NAME` leaves a 🧠 naming NAME as it was written rather than
        \\expanding it, so what comes out is the ledger from there on. NAME is
        \\what a 🧠 says: a turn, or an agent.
        \\
        \\  m8 say --no-send :demo/mathy | m8 encode --break mathy/+/tduyxbutjb
        \\  m8 say --no-send :demo/mathy | m8 encode --break mathy     the chat, without its agent
        \\
        \\A provider pipeline may supply defaults in M8_PROVIDER_param_NAME variables,
        \\where NAME is the request field name. Defaults apply only when
        \\M8_PROVIDER_NAME matches the model provider. Explicit model parameters
        \\override defaults; null omits the field. Standalone encoding has no
        \\provider defaults.
        \\
    );
    try codec.list(w);
}
