const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const output = @import("output.zig");
const killcmd = @import("kill.zig");
const docker = @import("docker.zig");
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

test "CLI parses kill controls" {
    const all = [_][]const u8{ "localports", "--kill", "8000", "--all" };
    const all_config = try expectConfig(cli.parseArgs(all[0..]));
    try std.testing.expectEqual(cli.Action.kill, all_config.action);
    try std.testing.expectEqual(@as(?u16, 8000), all_config.kill_port);
    try std.testing.expect(all_config.kill_all);

    const pid = [_][]const u8{ "localports", "--kill", "8000", "--pid", "6524" };
    const pid_config = try expectConfig(cli.parseArgs(pid[0..]));
    try std.testing.expectEqual(@as(?u16, 8000), pid_config.kill_port);
    try std.testing.expectEqual(@as(?u32, 6524), pid_config.kill_match_pid);

    const kill_pid = [_][]const u8{ "localports", "--kill-pid", "6524" };
    const kill_pid_config = try expectConfig(cli.parseArgs(kill_pid[0..]));
    try std.testing.expectEqual(cli.Action.kill, kill_pid_config.action);
    try std.testing.expectEqual(@as(?u32, 6524), kill_pid_config.kill_pid);
    try std.testing.expectEqual(@as(?u16, null), kill_pid_config.kill_port);
}

test "CLI rejects invalid kill-control combinations" {
    const all_no_port = [_][]const u8{ "localports", "--all" };
    _ = try expectFailure(.all_or_pid_requires_kill_port, cli.parseArgs(all_no_port[0..]));

    const pid_no_port = [_][]const u8{ "localports", "--pid", "123" };
    _ = try expectFailure(.all_or_pid_requires_kill_port, cli.parseArgs(pid_no_port[0..]));

    const all_and_pid = [_][]const u8{ "localports", "--kill", "8000", "--all", "--pid", "123" };
    _ = try expectFailure(.all_pid_conflict, cli.parseArgs(all_and_pid[0..]));

    const kill_pid_and_kill = [_][]const u8{ "localports", "--kill-pid", "123", "--kill", "8000" };
    _ = try expectFailure(.kill_pid_conflict, cli.parseArgs(kill_pid_and_kill[0..]));

    const pid_missing_value = [_][]const u8{ "localports", "--kill", "8000", "--pid" };
    _ = try expectFailure(.pid_requires_value, cli.parseArgs(pid_missing_value[0..]));

    const kill_pid_missing_value = [_][]const u8{ "localports", "--kill-pid" };
    _ = try expectFailure(.kill_pid_requires_value, cli.parseArgs(kill_pid_missing_value[0..]));

    const bad_pid = [_][]const u8{ "localports", "--kill-pid", "abc" };
    _ = try expectFailure(.invalid_pid_number, cli.parseArgs(bad_pid[0..]));
}

test "CLI parses verbose flag" {
    const defaults = [_][]const u8{"localports"};
    const default_config = try expectConfig(cli.parseArgs(defaults[0..]));
    try std.testing.expect(!default_config.verbose);

    const verbose = [_][]const u8{ "localports", "--verbose" };
    const verbose_config = try expectConfig(cli.parseArgs(verbose[0..]));
    try std.testing.expectEqual(cli.Action.scan, verbose_config.action);
    try std.testing.expect(verbose_config.verbose);

    const json_verbose = [_][]const u8{ "localports", "--json", "--verbose" };
    const json_verbose_config = try expectConfig(cli.parseArgs(json_verbose[0..]));
    try std.testing.expect(json_verbose_config.verbose);
    try std.testing.expect(json_verbose_config.json_output);

    const filtered = [_][]const u8{ "localports", "-p", "8000", "--verbose" };
    const filtered_config = try expectConfig(cli.parseArgs(filtered[0..]));
    try std.testing.expectEqual(@as(?u16, 8000), filtered_config.filter_port);
    try std.testing.expect(filtered_config.verbose);
}

test "CLI parses tree flag" {
    const defaults = [_][]const u8{"localports"};
    try std.testing.expect(!(try expectConfig(cli.parseArgs(defaults[0..]))).tree);

    const tree = [_][]const u8{ "localports", "--tree" };
    const tree_config = try expectConfig(cli.parseArgs(tree[0..]));
    try std.testing.expectEqual(cli.Action.scan, tree_config.action);
    try std.testing.expect(tree_config.tree);

    const combo = [_][]const u8{ "localports", "--tree", "--verbose" };
    const combo_config = try expectConfig(cli.parseArgs(combo[0..]));
    try std.testing.expect(combo_config.tree);
    try std.testing.expect(combo_config.verbose);
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

test "kill resolve single mode refuses ambiguous matches" {
    const none = [_]PortEntry{};
    try std.testing.expectEqual(killcmd.KillResolution.none, killcmd.resolve(none[0..], .single));

    const one = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    const selected = killcmd.resolve(one[0..], .single);
    try std.testing.expectEqual(@as(u32, 123), selected.one.pid);

    const multiple = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(3000, 456, "node", .{ 127, 0, 0, 1 }),
    };
    try std.testing.expectEqual(@as(usize, 2), killcmd.resolve(multiple[0..], .single).ambiguous);
}

test "kill resolve all mode targets every match" {
    const none = [_]PortEntry{};
    try std.testing.expectEqual(killcmd.KillResolution.none, killcmd.resolve(none[0..], .all));

    const multiple = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(3000, 456, "node", .{ 127, 0, 0, 1 }),
    };
    try std.testing.expectEqual(@as(usize, 2), killcmd.resolve(multiple[0..], .all).many);
}

test "kill resolve pid mode selects matching pid or reports absence" {
    const multiple = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(3000, 456, "ruby", .{ 127, 0, 0, 1 }),
    };

    const hit = killcmd.resolve(multiple[0..], .{ .pid = 456 });
    try std.testing.expectEqual(@as(u32, 456), hit.one.pid);

    const miss = killcmd.resolve(multiple[0..], .{ .pid = 999 });
    try std.testing.expectEqual(@as(u32, 999), miss.pid_not_listed);

    const empty = [_]PortEntry{};
    try std.testing.expectEqual(killcmd.KillResolution.none, killcmd.resolve(empty[0..], .{ .pid = 123 }));
}

test "table output renders empty scans and IPv4 rows" {
    var empty_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer empty_writer.deinit();
    try output.writeTable(&empty_writer.writer, &.{}, .{});
    try std.testing.expectEqualStrings("No listening TCP ports found.\n", empty_writer.written());

    var row_writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer row_writer.deinit();
    const entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    try output.writeTable(&row_writer.writer, entries[0..], .{});
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
    try output.writeJson(&writer.writer, entries[0..], .{});

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
    try output.writeJson(&writer.writer, entries[0..], .{});

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
    try output.writeJson(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"address\":\"2001:0db8:0000:0000:0000:0000:0000:0001\"") != null);
}

test "verbose table renders USER and COMMAND columns" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    entries[0].user = "rvs";
    entries[0].command = "node server.js";
    try output.writeTable(&writer.writer, entries[0..], .{ .verbose = true });

    try std.testing.expectEqualStrings(
        "PORT   PID    PROCESS  ADDRESS    USER  COMMAND\n" ++
            "3000   123    node     127.0.0.1  rvs   node server.js\n",
        writer.written(),
    );
}

test "verbose table shows dashes for missing user and command" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    try output.writeTable(&writer.writer, entries[0..], .{ .verbose = true });

    try std.testing.expectEqualStrings(
        "PORT   PID    PROCESS  ADDRESS    USER  COMMAND\n" ++
            "3000   123    node     127.0.0.1  -     -\n",
        writer.written(),
    );
}

test "verbose JSON adds user and command fields" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    entries[0].user = "rvs";
    entries[0].command = "node server.js";
    try output.writeJson(&writer.writer, entries[0..], .{ .verbose = true });

    try std.testing.expectEqualStrings(
        "[\n" ++
            "  {\"port\":3000,\"pid\":123,\"proto\":\"tcp\",\"process\":\"node\",\"address\":\"127.0.0.1\",\"user\":\"rvs\",\"command\":\"node server.js\"}\n" ++
            "]\n",
        writer.written(),
    );
}

test "verbose JSON emits empty strings for missing user and command" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    try output.writeJson(&writer.writer, entries[0..], .{ .verbose = true });

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"user\":\"\",\"command\":\"\"") != null);
}

test "default JSON omits verbose fields" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    entries[0].user = "rvs";
    entries[0].command = "node server.js";
    try output.writeJson(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "user") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "command") == null);
}

test "tree table renders ancestry beneath the row" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 12345, "node", .{ 127, 0, 0, 1 })};
    const ancestors = [_]types.Ancestor{
        .{ .pid = 12340, .name = "npm" },
        .{ .pid = 12300, .name = "zsh" },
    };
    entries[0].ancestors = ancestors[0..];
    try output.writeTable(&writer.writer, entries[0..], .{ .tree = true });

    try std.testing.expectEqualStrings(
        "PORT   PID    PROCESS  ADDRESS\n" ++
            "3000   12345  node     127.0.0.1\n" ++
            (" " ** 14) ++ "\u{2514}\u{2500} npm (12340)\n" ++
            (" " ** 16) ++ "\u{2514}\u{2500} zsh (12300)\n",
        writer.written(),
    );
}

test "tree JSON adds an ancestors array" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 12345, "node", .{ 127, 0, 0, 1 })};
    const ancestors = [_]types.Ancestor{
        .{ .pid = 12340, .name = "npm" },
        .{ .pid = 12300, .name = "zsh" },
    };
    entries[0].ancestors = ancestors[0..];
    try output.writeJson(&writer.writer, entries[0..], .{ .tree = true });

    try std.testing.expectEqualStrings(
        "[\n" ++
            "  {\"port\":3000,\"pid\":12345,\"proto\":\"tcp\",\"process\":\"node\",\"address\":\"127.0.0.1\"," ++
            "\"ancestors\":[{\"pid\":12340,\"name\":\"npm\"},{\"pid\":12300,\"name\":\"zsh\"}]}\n" ++
            "]\n",
        writer.written(),
    );
}

test "tree JSON emits an empty ancestors array when there are none" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{entryIPv4(3000, 12345, "node", .{ 127, 0, 0, 1 })};
    try output.writeJson(&writer.writer, entries[0..], .{ .tree = true });

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"ancestors\":[]") != null);
}

test "default output omits ancestors" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(3000, 12345, "node", .{ 127, 0, 0, 1 })};
    const ancestors = [_]types.Ancestor{.{ .pid = 12340, .name = "npm" }};
    entries[0].ancestors = ancestors[0..];
    try output.writeJson(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "ancestors") == null);
}

test "CLI parses docker flag" {
    const defaults = [_][]const u8{"localports"};
    try std.testing.expect(!(try expectConfig(cli.parseArgs(defaults[0..]))).docker);

    const argv = [_][]const u8{ "localports", "--docker" };
    const config = try expectConfig(cli.parseArgs(argv[0..]));
    try std.testing.expectEqual(cli.Action.scan, config.action);
    try std.testing.expect(config.docker);
}

test "docker isDockerProcess recognizes the Docker host processes" {
    try std.testing.expect(docker.isDockerProcess("com.docker.backend"));
    try std.testing.expect(docker.isDockerProcess("docker-proxy"));
    try std.testing.expect(docker.isDockerProcess("vpnkit"));
    try std.testing.expect(!docker.isDockerProcess("node"));
    try std.testing.expect(!docker.isDockerProcess("Python"));
}

test "docker parsePsOutput maps host ports to containers" {
    const text =
        "lp-spike\tnginx:alpine\t0.0.0.0:18080->80/tcp, [::]:18080->80/tcp\n" ++
        "db\tpostgres:16\t0.0.0.0:5432->5432/tcp\n" ++
        "idle\tredis:7\t\n"; // running but no published ports

    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);

    const c1 = docker.lookup(mappings, 18080) orelse return error.Missing18080;
    try std.testing.expectEqualStrings("lp-spike", c1.name);
    try std.testing.expectEqualStrings("nginx:alpine", c1.image);
    try std.testing.expectEqual(@as(u16, 80), c1.container_port);

    const c2 = docker.lookup(mappings, 5432) orelse return error.Missing5432;
    try std.testing.expectEqualStrings("db", c2.name);
    try std.testing.expectEqual(@as(u16, 5432), c2.container_port);

    try std.testing.expect(docker.lookup(mappings, 9999) == null);
}

test "docker parsePsOutput skips exposed-but-unpublished ports" {
    const text = "x\timg\t80/tcp, 443/tcp\n"; // exposed, not published (no ->)
    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);
    try std.testing.expectEqual(@as(usize, 0), mappings.len);
}

test "docker table renders the CONTAINER column" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(5432, 9743, "com.docker.backend", .{ 127, 0, 0, 1 })};
    entries[0].container = .{ .name = "pg-dev", .image = "postgres:16", .container_port = 5432 };
    try output.writeTable(&writer.writer, entries[0..], .{ .docker = true });

    try std.testing.expectEqualStrings(
        "PORT   PID    PROCESS" ++ (" " ** 13) ++ "ADDRESS" ++ (" " ** 4) ++ "CONTAINER\n" ++
            "5432   9743   com.docker.backend  127.0.0.1  pg-dev (postgres:16 ->5432)\n",
        writer.written(),
    );
}

test "docker JSON adds a container object, or null when unresolved" {
    var resolved: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer resolved.deinit();
    var entries = [_]PortEntry{entryIPv4(5432, 9743, "com.docker.backend", .{ 127, 0, 0, 1 })};
    entries[0].container = .{ .name = "pg-dev", .image = "postgres:16", .container_port = 5432 };
    try output.writeJson(&resolved.writer, entries[0..], .{ .docker = true });
    try std.testing.expectEqualStrings(
        "[\n  {\"port\":5432,\"pid\":9743,\"proto\":\"tcp\",\"process\":\"com.docker.backend\"," ++
            "\"address\":\"127.0.0.1\",\"container\":{\"name\":\"pg-dev\",\"image\":\"postgres:16\",\"container_port\":5432}}\n]\n",
        resolved.written(),
    );

    var unresolved: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer unresolved.deinit();
    const plain = [_]PortEntry{entryIPv4(5432, 9743, "com.docker.backend", .{ 127, 0, 0, 1 })};
    try output.writeJson(&unresolved.writer, plain[0..], .{ .docker = true });
    try std.testing.expect(std.mem.indexOf(u8, unresolved.written(), "\"container\":null") != null);
}

test "default output omits the container field" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(5432, 9743, "com.docker.backend", .{ 127, 0, 0, 1 })};
    entries[0].container = .{ .name = "pg-dev", .image = "postgres:16", .container_port = 5432 };
    try output.writeJson(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "container") == null);
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
