const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const output = @import("output.zig");
const killcmd = @import("kill.zig");
const types = @import("types.zig");
const watch = @import("watch.zig");

const PortEntry = types.PortEntry;

// Pull in the platform backend's own tests on the platforms where it compiles.
// The Darwin backend's socket-decode logic lives behind libproc structs that
// only have a valid layout on macOS, so it is only referenced there.
test {
    if (builtin.os.tag == .macos) {
        _ = @import("darwin.zig");
    }
}

test "CLI defaults to table scan" {
    const argv = [_][]const u8{"localports"};
    const config = try expectConfig(cli.parseArgs(argv[0..]));

    try std.testing.expectEqual(cli.Action.scan, config.action);
    try std.testing.expectEqual(@as(?u16, null), config.filter_port);
    try std.testing.expect(!config.json_output);
}

test "CLI parses port filters" {
    const positional = [_][]const u8{ "localports", "3000" };
    const positional_config = try expectConfig(cli.parseArgs(positional[0..]));
    try std.testing.expectEqual(cli.Action.scan, positional_config.action);
    try std.testing.expectEqual(@as(?u16, 3000), positional_config.filter_port);

    const flag = [_][]const u8{ "localports", "--port", "5432" };
    const flag_config = try expectConfig(cli.parseArgs(flag[0..]));
    try std.testing.expectEqual(cli.Action.scan, flag_config.action);
    try std.testing.expectEqual(@as(?u16, 5432), flag_config.filter_port);
}

test "CLI parses watch mode" {
    const defaults = [_][]const u8{ "localports", "--watch" };
    const default_config = try expectConfig(cli.parseArgs(defaults[0..]));
    try std.testing.expectEqual(cli.Action.watch, default_config.action);
    try std.testing.expectEqual(@as(u32, 2), default_config.watch_interval);

    const custom = [_][]const u8{ "localports", "-w", "1" };
    const custom_config = try expectConfig(cli.parseArgs(custom[0..]));
    try std.testing.expectEqual(cli.Action.watch, custom_config.action);
    try std.testing.expectEqual(@as(u32, 1), custom_config.watch_interval);

    const zero = [_][]const u8{ "localports", "--watch", "0" };
    const zero_config = try expectConfig(cli.parseArgs(zero[0..]));
    try std.testing.expectEqual(@as(u32, 1), zero_config.watch_interval);

    const filtered = [_][]const u8{ "localports", "3000", "--watch" };
    const filtered_config = try expectConfig(cli.parseArgs(filtered[0..]));
    try std.testing.expectEqual(cli.Action.watch, filtered_config.action);
    try std.testing.expectEqual(@as(?u16, 3000), filtered_config.filter_port);
}

test "CLI parses kill mode and force" {
    const argv = [_][]const u8{ "localports", "--kill", "3000", "--force" };
    const config = try expectConfig(cli.parseArgs(argv[0..]));

    try std.testing.expectEqual(cli.Action.kill, config.action);
    try std.testing.expectEqual(@as(?u16, 3000), config.kill_port);
    try std.testing.expect(config.force_kill);
}

test "CLI rejects JSON watch output" {
    const argv = [_][]const u8{ "localports", "--json", "--watch" };
    _ = try expectFailure(.watch_json_unsupported, cli.parseArgs(argv[0..]));
}

test "CLI gives kill precedence over watch" {
    const argv = [_][]const u8{ "localports", "--watch", "1", "--kill", "3000" };
    const config = try expectConfig(cli.parseArgs(argv[0..]));

    try std.testing.expectEqual(cli.Action.kill, config.action);
    try std.testing.expectEqual(@as(?u16, 3000), config.kill_port);
}

test "CLI parses help and version actions" {
    const help = [_][]const u8{ "localports", "--help" };
    const help_config = try expectConfig(cli.parseArgs(help[0..]));
    try std.testing.expectEqual(cli.Action.help, help_config.action);

    const version = [_][]const u8{ "localports", "version" };
    const version_config = try expectConfig(cli.parseArgs(version[0..]));
    try std.testing.expectEqual(cli.Action.version, version_config.action);
}

test "CLI reports invalid input" {
    const missing_port = [_][]const u8{ "localports", "--port" };
    _ = try expectFailure(.port_requires_value, cli.parseArgs(missing_port[0..]));

    const invalid_port = [_][]const u8{ "localports", "--port", "abc" };
    _ = try expectFailure(.invalid_port_number, cli.parseArgs(invalid_port[0..]));

    const unknown = [_][]const u8{ "localports", "--wat" };
    const failure = try expectFailure(.unknown_argument, cli.parseArgs(unknown[0..]));
    try std.testing.expectEqualStrings("--wat", failure.arg.?);
}

test "port-pid watch keys do not collide on pid low bits" {
    try std.testing.expectEqual((@as(u64, 3000) << 32) | 1, types.portPidKey(3000, 1));
    try std.testing.expect(types.portPidKey(3000, 1) != types.portPidKey(3000, 65537));
}

test "watch classification detects new removed and unchanged rows" {
    const previous = [_]PortEntry{
        entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(4000, 200, "ruby", .{ 127, 0, 0, 1 }),
    };
    const current = [_]PortEntry{
        entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(2000, 300, "go", .{ 127, 0, 0, 1 }),
    };

    const classified = try watch.classify(std.testing.allocator, previous[0..], current[0..]);
    defer std.testing.allocator.free(classified);

    try std.testing.expect(watch.hasChanges(classified));
    try std.testing.expectEqual(@as(usize, 3), classified.len);

    try std.testing.expectEqual(@as(u16, 2000), classified[0].entry.port);
    try std.testing.expectEqual(types.RowState.new, classified[0].state);

    try std.testing.expectEqual(@as(u16, 3000), classified[1].entry.port);
    try std.testing.expectEqual(types.RowState.unchanged, classified[1].state);

    try std.testing.expectEqual(@as(u16, 4000), classified[2].entry.port);
    try std.testing.expectEqual(types.RowState.removed, classified[2].state);
}

test "watch classification reports no changes for stable rows" {
    const previous = [_]PortEntry{entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 })};
    const current = [_]PortEntry{entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 })};

    const classified = try watch.classify(std.testing.allocator, previous[0..], current[0..]);
    defer std.testing.allocator.free(classified);

    try std.testing.expect(!watch.hasChanges(classified));
    try std.testing.expectEqual(types.RowState.unchanged, classified[0].state);
}

test "kill target selection refuses ambiguous matches" {
    const none = [_]PortEntry{};
    try std.testing.expectEqual(killcmd.TargetSelection.none, killcmd.selectTarget(none[0..]));

    const one = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    const selected = killcmd.selectTarget(one[0..]);
    try std.testing.expectEqual(@as(u32, 123), selected.target.pid);

    const multiple = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(3000, 456, "node", .{ 127, 0, 0, 1 }),
    };
    const ambiguous = killcmd.selectTarget(multiple[0..]);
    try std.testing.expectEqual(@as(usize, 2), ambiguous.multiple);
}

test "table output renders empty scans and IPv4 rows" {
    var empty_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer empty_writer.deinit();
    try output.writeTable(&empty_writer.writer, &.{});
    try std.testing.expectEqualStrings("No listening TCP ports found.\n", empty_writer.written());

    var row_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer row_writer.deinit();
    const entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    try output.writeTable(&row_writer.writer, entries[0..]);
    try std.testing.expectEqualStrings(
        "PORT   PID    PROCESS  ADDRESS\n" ++
            "3000   123    node     127.0.0.1\n",
        row_writer.written(),
    );
}

test "JSON output renders valid fields and escapes process names" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{entryIPv4(3000, 123, "node\\\"dev", .{ 127, 0, 0, 1 })};
    try output.writeJson(&writer.writer, entries[0..]);

    try std.testing.expectEqualStrings(
        "[\n" ++
            "  {\"port\":3000,\"pid\":123,\"proto\":\"tcp\",\"process\":\"node\\\\\\\"dev\",\"address\":\"127.0.0.1\"}\n" ++
            "]\n",
        writer.written(),
    );
}

test "JSON output escapes control characters" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const process_name = [_]u8{ 'l', 'i', 'n', 'e', '\n', '\t', 0x01 };
    const entries = [_]PortEntry{entryIPv4(3000, 123, process_name[0..], .{ 127, 0, 0, 1 })};
    try output.writeJson(&writer.writer, entries[0..]);

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"process\":\"line\\n\\t\\u0001\"") != null);
}

test "JSON output renders IPv6 addresses" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{entryIPv6(8080, 42, "server", .{
        0x20, 0x01, 0x0d, 0xb8,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01,
    })};
    try output.writeJson(&writer.writer, entries[0..]);

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"address\":\"2001:0db8:0000:0000:0000:0000:0000:0001\"") != null);
}

fn expectConfig(result: cli.ParseResult) !cli.Config {
    return switch (result) {
        .config => |config| config,
        .failure => error.UnexpectedParseFailure,
    };
}

fn expectFailure(expected: cli.ParseFailureKind, result: cli.ParseResult) !cli.ParseFailure {
    return switch (result) {
        .config => error.ExpectedParseFailure,
        .failure => |failure| {
            try std.testing.expectEqual(expected, failure.kind);
            return failure;
        },
    };
}

fn entryIPv4(port: u16, pid: u32, name: []const u8, addr: [4]u8) PortEntry {
    var name_buf: [256]u8 = undefined;
    @memset(&name_buf, 0);
    @memcpy(name_buf[0..name.len], name);

    return .{
        .port = port,
        .pid = pid,
        .name = name_buf,
        .name_len = name.len,
        .addr4 = addr,
        .addr6 = .{0} ** 16,
        .is_ipv6 = false,
    };
}

fn entryIPv6(port: u16, pid: u32, name: []const u8, addr: [16]u8) PortEntry {
    var entry = entryIPv4(port, pid, name, .{ 0, 0, 0, 0 });
    entry.addr6 = addr;
    entry.is_ipv6 = true;
    return entry;
}
