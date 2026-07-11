const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const output = @import("output.zig");
const killcmd = @import("kill.zig");
const docker = @import("docker.zig");
const types = @import("types.zig");
const watch = @import("watch.zig");

const PortEntry = types.PortEntry;

// Pull in other modules' own tests. The Darwin backend's socket-decode logic
// lives behind libproc structs that only have a valid layout on macOS, so it is
// only referenced there; output.zig is platform-independent.
test {
    _ = @import("output.zig");
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

test "listener identity preserves distinct addresses for one process and port" {
    const loopback = entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 });
    const wildcard = entryIPv4(3000, 100, "node", .{ 0, 0, 0, 0 });
    const ipv6 = entryIPv6(3000, 100, "node", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });

    try std.testing.expect(!std.meta.eql(types.listenerKey(&loopback), types.listenerKey(&wildcard)));
    try std.testing.expect(!std.meta.eql(types.listenerKey(&loopback), types.listenerKey(&ipv6)));
    try std.testing.expectEqual(types.listenerKey(&loopback), types.listenerKey(&loopback));
}

test "listener identity preserves IPv6 scope" {
    var first = entryIPv6(3000, 100, "node", .{ 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });
    var second = first;
    first.scope_id = 1;
    second.scope_id = 2;

    try std.testing.expect(!std.meta.eql(types.listenerKey(&first), types.listenerKey(&second)));
}

test "listener ordering is deterministic across addresses and scopes" {
    var scoped_two = entryIPv6(3000, 100, "node", .{ 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });
    scoped_two.scope_id = 2;
    var scoped_one = scoped_two;
    scoped_one.scope_id = 1;
    var entries = [_]PortEntry{
        scoped_two,
        entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 }),
        scoped_one,
        entryIPv4(3000, 100, "node", .{ 0, 0, 0, 0 }),
    };

    std.mem.sort(PortEntry, &entries, {}, types.listenerLessThan);

    try std.testing.expectEqual([4]u8{ 0, 0, 0, 0 }, entries[0].addr4);
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, entries[1].addr4);
    try std.testing.expectEqual(@as(u32, 1), entries[2].scope_id);
    try std.testing.expectEqual(@as(u32, 2), entries[3].scope_id);
}

test "scopeOf treats loopback as local and everything else as network" {
    const local = types.Scope.local;
    const network = types.Scope.network;

    const cases = .{
        .{ entryIPv4(3000, 1, "n", .{ 127, 0, 0, 1 }), local },
        .{ entryIPv4(3000, 1, "n", .{ 127, 4, 5, 6 }), local }, // 127.0.0.0/8
        .{ entryIPv4(3000, 1, "n", .{ 0, 0, 0, 0 }), network }, // all interfaces
        .{ entryIPv4(3000, 1, "n", .{ 192, 168, 1, 5 }), network }, // LAN
        .{ entryIPv6(3000, 1, "n", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }), local }, // ::1
        .{ entryIPv6(3000, 1, "n", .{0} ** 16), network }, // ::
        // ::ffff:127.0.0.1 (IPv4-mapped loopback) and ::ffff:192.168.0.1
        .{ entryIPv6(3000, 1, "n", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 127, 0, 0, 1 }), local },
        .{ entryIPv6(3000, 1, "n", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 168, 0, 1 }), network },
    };
    inline for (cases) |c| {
        const e = c[0];
        try std.testing.expectEqual(c[1], types.scopeOf(&e));
    }
}

test "filterExposed keeps only network listeners and preserves order" {
    const entries = [_]PortEntry{
        entryIPv4(5432, 1, "a", .{ 0, 0, 0, 0 }), // network
        entryIPv4(3000, 2, "b", .{ 127, 0, 0, 1 }), // local — dropped
        entryIPv4(8080, 3, "c", .{ 192, 168, 0, 9 }), // network
    };
    const kept = try types.filterExposed(std.testing.allocator, entries[0..]);
    defer std.testing.allocator.free(kept);

    try std.testing.expectEqual(@as(usize, 2), kept.len);
    try std.testing.expectEqual(@as(u16, 5432), kept[0].port);
    try std.testing.expectEqual(@as(u16, 8080), kept[1].port);

    // All-loopback input yields an empty (but valid) slice.
    const all_local = [_]PortEntry{entryIPv4(3000, 2, "b", .{ 127, 0, 0, 1 })};
    const none = try types.filterExposed(std.testing.allocator, all_local[0..]);
    defer std.testing.allocator.free(none);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "table empty-state message reflects the exposed filter" {
    var plain: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer plain.deinit();
    try output.writeTable(&plain.writer, &.{}, .{});
    try std.testing.expectEqualStrings("No listening TCP ports found.\n", plain.written());

    var exposed: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer exposed.deinit();
    try output.writeTable(&exposed.writer, &.{}, .{ .exposed = true });
    try std.testing.expectEqualStrings("No network-reachable ports found.\n", exposed.written());
}

test "scan diagnostics render one aggregate warning" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try output.writeScanWarning(&writer.writer, .{
        .inaccessible_processes = 2,
        .malformed_results = 1,
        .truncated = true,
    });

    const warning = writer.written();
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, warning, "warning:"));
    try std.testing.expect(std.mem.indexOf(u8, warning, "2 processes") != null);
    try std.testing.expect(std.mem.indexOf(u8, warning, "1 malformed result") != null);
    try std.testing.expect(std.mem.indexOf(u8, warning, "saturated after retries") != null);
    try std.testing.expect(std.mem.indexOf(u8, warning, "try sudo") != null);

    var complete: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer complete.deinit();
    try output.writeScanWarning(&complete.writer, .{});
    try std.testing.expectEqual(@as(usize, 0), complete.written().len);
}

test "macOS scanner sees a real listening TCP socket" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const fd = try listenOnLoopbackEphemeralPort();
    defer _ = std.c.close(fd);

    const port = try boundPort(fd);
    const entries = try @import("darwin.zig").scan(std.testing.allocator, port);
    defer std.testing.allocator.free(entries);

    const pid: u32 = @intCast(std.c.getpid());
    for (entries) |entry| {
        if (entry.port == port and entry.pid == pid) {
            try std.testing.expect(!entry.is_ipv6);
            try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, entry.addr4);
            return;
        }
    }

    return error.ExpectedScannerEntry;
}

test "macOS scanner preserves IPv4 and IPv6 listeners for one process and port" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const fd4 = try listenOnLoopbackEphemeralPort();
    defer _ = std.c.close(fd4);
    const port = try boundPort(fd4);

    const fd6 = try listenOnIpv6Port(port, .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });
    defer _ = std.c.close(fd6);

    const entries = try @import("darwin.zig").scan(std.testing.allocator, port);
    defer std.testing.allocator.free(entries);

    const pid: u32 = @intCast(std.c.getpid());
    var found_ipv4 = false;
    var found_ipv6 = false;
    for (entries) |entry| {
        if (entry.pid != pid or entry.port != port) continue;
        if (entry.is_ipv6) {
            found_ipv6 = std.mem.eql(u8, &entry.addr6, &([_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }));
        } else {
            found_ipv4 = std.mem.eql(u8, &entry.addr4, &([_]u8{ 127, 0, 0, 1 }));
        }
    }

    try std.testing.expect(found_ipv4);
    try std.testing.expect(found_ipv6);
}

test "macOS scanner collapses duplicated socket descriptors" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const fd = try listenOnLoopbackEphemeralPort();
    defer _ = std.c.close(fd);
    const duplicate = std.c.dup(fd);
    if (duplicate < 0) return error.DupFailed;
    defer _ = std.c.close(duplicate);

    const port = try boundPort(fd);
    const entries = try @import("darwin.zig").scan(std.testing.allocator, port);
    defer std.testing.allocator.free(entries);

    const pid: u32 = @intCast(std.c.getpid());
    var matches: usize = 0;
    for (entries) |entry| {
        if (entry.pid == pid and entry.port == port) matches += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), matches);
}

test "exposed filtering preserves a network sibling of a loopback listener" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const fd4 = try listenOnLoopbackEphemeralPort();
    defer _ = std.c.close(fd4);
    const port = try boundPort(fd4);
    const fd6 = try listenOnIpv6Port(port, .{0} ** 16);
    defer _ = std.c.close(fd6);

    const entries = try @import("darwin.zig").scan(std.testing.allocator, port);
    defer std.testing.allocator.free(entries);
    const exposed = try types.filterExposed(std.testing.allocator, entries);
    defer std.testing.allocator.free(exposed);

    const pid: u32 = @intCast(std.c.getpid());
    var process_rows: usize = 0;
    for (exposed) |entry| {
        if (entry.pid != pid) continue;
        process_rows += 1;
        try std.testing.expect(entry.is_ipv6);
        try std.testing.expectEqual([_]u8{0} ** 16, entry.addr6);
    }
    try std.testing.expectEqual(@as(usize, 1), process_rows);
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

test "watch classification treats an address change as removed and new" {
    const previous = [_]PortEntry{entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 })};
    const current = [_]PortEntry{entryIPv4(3000, 100, "node", .{ 0, 0, 0, 0 })};

    const classified = try watch.classify(std.testing.allocator, previous[0..], current[0..]);
    defer std.testing.allocator.free(classified);

    try std.testing.expectEqual(@as(usize, 2), classified.len);
    try std.testing.expectEqual(types.RowState.new, classified[0].state);
    try std.testing.expectEqual([4]u8{ 0, 0, 0, 0 }, classified[0].entry.addr4);
    try std.testing.expectEqual(types.RowState.removed, classified[1].state);
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, classified[1].entry.addr4);
}

test "watch classification keeps sibling endpoints independently stable" {
    const previous = [_]PortEntry{
        entryIPv4(3000, 100, "node", .{ 127, 0, 0, 1 }),
        entryIPv6(3000, 100, "node", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }),
    };
    const current = previous;

    const classified = try watch.classify(std.testing.allocator, &previous, &current);
    defer std.testing.allocator.free(classified);

    try std.testing.expectEqual(@as(usize, 2), classified.len);
    try std.testing.expect(!watch.hasChanges(classified));
}

test "watch table renders verbose columns" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]types.WatchEntry{
        .{ .entry = entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }), .state = .unchanged },
    };
    entries[0].entry.user = "rvs";
    entries[0].entry.command = "node server.js";
    try output.writeWatchTable(&writer.writer, entries[0..], .{ .verbose = true });

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "USER") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "COMMAND") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "rvs") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "node server.js") != null);
}

test "watch table default output omits enrichment columns" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]types.WatchEntry{
        .{ .entry = entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }), .state = .unchanged },
    };
    entries[0].entry.user = "rvs";
    entries[0].entry.command = "node server.js";
    entries[0].entry.ancestors = &.{.{ .pid = 100, .name = "zsh" }};
    try output.writeWatchTable(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "USER") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "COMMAND") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "CONTAINER") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\u{2514}") == null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "PROCESS") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "ADDRESS") != null);
}

test "watch table renders docker container column" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]types.WatchEntry{
        .{ .entry = entryIPv4(5432, 9743, "com.docker.backend", .{ 127, 0, 0, 1 }), .state = .new },
    };
    entries[0].entry.container = .{ .name = "pg-dev", .image = "postgres:16", .container_port = 5432 };
    try output.writeWatchTable(&writer.writer, entries[0..], .{ .docker = true });

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "CONTAINER") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "pg-dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "postgres:16") != null);
}

test "watch table renders ancestry trees" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]types.WatchEntry{
        .{ .entry = entryIPv4(3000, 12345, "node", .{ 127, 0, 0, 1 }), .state = .unchanged },
    };
    const ancestors = [_]types.Ancestor{
        .{ .pid = 12340, .name = "npm" },
        .{ .pid = 12300, .name = "zsh" },
    };
    entries[0].entry.ancestors = ancestors[0..];
    try output.writeWatchTable(&writer.writer, entries[0..], .{ .tree = true });

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\u{2514}\u{2500} npm (12340)") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\u{2514}\u{2500} zsh (12300)") != null);
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

test "kill targets each process once when it owns multiple listeners" {
    const entries = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv6(3000, 123, "node", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }),
        entryIPv4(3000, 456, "ruby", .{ 127, 0, 0, 1 }),
    };

    const targets = try killcmd.uniqueProcessTargets(std.testing.allocator, &entries);
    defer std.testing.allocator.free(targets);

    try std.testing.expectEqual(@as(usize, 2), targets.len);
    try std.testing.expectEqual(@as(u32, 123), targets[0].pid);
    try std.testing.expectEqual(@as(u32, 456), targets[1].pid);

    const one_process = try killcmd.uniqueProcessTargets(std.testing.allocator, entries[0..2]);
    defer std.testing.allocator.free(one_process);
    try std.testing.expectEqual(@as(u32, 123), killcmd.resolve(one_process, .single).one.pid);
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

test "kill safety refuses Docker-owned single target" {
    const entries = [_]PortEntry{entryIPv4(5432, 900, "com.docker.backend", .{ 127, 0, 0, 1 })};
    const resolution = killcmd.resolve(entries[0..], .single);

    const target = killcmd.unsafeDockerPortKillTarget(entries[0..], resolution) orelse return error.ExpectedDockerRefusal;
    try std.testing.expectEqual(@as(u32, 900), target.pid);
    try std.testing.expectEqual(@as(u16, 5432), target.port);
}

test "kill safety refuses all mode when any target is Docker-owned" {
    const entries = [_]PortEntry{
        entryIPv4(5432, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(5432, 900, "com.docker.backend", .{ 127, 0, 0, 1 }),
    };
    const resolution = killcmd.resolve(entries[0..], .all);

    const target = killcmd.unsafeDockerPortKillTarget(entries[0..], resolution) orelse return error.ExpectedDockerRefusal;
    try std.testing.expectEqual(@as(u32, 900), target.pid);
}

test "kill safety applies to selected Docker pid but not ambiguous non-action" {
    const entries = [_]PortEntry{
        entryIPv4(5432, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv4(5432, 900, "com.docker.backend", .{ 127, 0, 0, 1 }),
    };

    const selected = killcmd.resolve(entries[0..], .{ .pid = 900 });
    try std.testing.expectEqual(@as(u32, 900), (killcmd.unsafeDockerPortKillTarget(entries[0..], selected) orelse return error.ExpectedDockerRefusal).pid);

    const ambiguous = killcmd.resolve(entries[0..], .single);
    try std.testing.expect(killcmd.unsafeDockerPortKillTarget(entries[0..], ambiguous) == null);

    const node = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    try std.testing.expect(killcmd.unsafeDockerPortKillTarget(node[0..], killcmd.resolve(node[0..], .single)) == null);
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

test "table tags network-bound listeners and leaves loopback rows clean" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{
        entryIPv4(5432, 900, "postgres", .{ 0, 0, 0, 0 }),
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
    };
    try output.writeTable(&writer.writer, entries[0..], .{});

    const out = writer.written();
    // The 0.0.0.0 row is tagged; the loopback row is not.
    try std.testing.expect(std.mem.indexOf(u8, out, "0.0.0.0  ! network") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "127.0.0.1  ! network") == null);
    try std.testing.expect(std.mem.count(u8, out, "! network") == 1);
}

test "verbose table keeps the network tag beside the address, not at the row end" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv4(5000, 641, "proc", .{ 0, 0, 0, 0 })};
    entries[0].user = "rvs";
    entries[0].command = "the-long-command";
    try output.writeTable(&writer.writer, entries[0..], .{ .verbose = true });

    const out = writer.written();
    // The tag follows the address directly, and stays ahead of USER/COMMAND
    // rather than being stranded after a long command at the row's end.
    try std.testing.expect(std.mem.indexOf(u8, out, "0.0.0.0  ! network") != null);
    const tag = std.mem.indexOf(u8, out, "! network").?;
    const user = std.mem.indexOf(u8, out, "rvs").?;
    const cmd = std.mem.indexOf(u8, out, "the-long-command").?;
    try std.testing.expect(tag < user);
    try std.testing.expect(user < cmd);
}

test "table colors the exposure tag without disturbing layout" {
    const entries = [_]PortEntry{
        entryIPv4(5432, 900, "postgres", .{ 0, 0, 0, 0 }),
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
    };

    var colored: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer colored.deinit();
    try output.writeTable(&colored.writer, entries[0..], .{ .verbose = true, .color = true });

    var plain: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer plain.deinit();
    try output.writeTable(&plain.writer, entries[0..], .{ .verbose = true, .color = false });

    // The tag is wrapped in red; the uncolored render carries no escapes.
    try std.testing.expect(std.mem.indexOf(u8, colored.written(), "\x1b[31m  ! network\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain.written(), "\x1b[") == null);

    // Stripping the escapes from the colored output reproduces the plain output
    // exactly — proving the escapes are zero-width and alignment is untouched.
    var stripped: std.ArrayList(u8) = .empty;
    defer stripped.deinit(std.testing.allocator);
    try stripAnsi(std.testing.allocator, &stripped, colored.written());
    try std.testing.expectEqualStrings(plain.written(), stripped.items);
}

test "watch table state color is gated on the color option" {
    const entries = [_]types.WatchEntry{
        .{ .entry = entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }), .state = .new },
    };

    var off: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer off.deinit();
    try output.writeWatchTable(&off.writer, entries[0..], .{ .color = false });
    try std.testing.expect(std.mem.indexOf(u8, off.written(), "\x1b[32m") == null);

    var on: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer on.deinit();
    try output.writeWatchTable(&on.writer, entries[0..], .{ .color = true });
    try std.testing.expect(std.mem.indexOf(u8, on.written(), "\x1b[32m") != null);
}

test "table truncates the long last column to the terminal width" {
    const full = "/very/long/path/to/some/program --with --many --flags --here 12345";
    var entries = [_]PortEntry{entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 })};
    entries[0].user = "rvs";
    entries[0].command = full;

    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();
    try output.writeTable(&w.writer, entries[0..], .{ .verbose = true, .max_width = 50 });
    const out = w.written();

    // Truncated (ellipsis present, full command not shown), and no rendered line
    // exceeds the width budget (each ellipsis is 3 bytes but one column).
    try std.testing.expect(std.mem.indexOf(u8, out, "\u{2026}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, full) == null);
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const visible = line.len - 2 * std.mem.count(u8, line, "\u{2026}");
        try std.testing.expect(visible <= 50);
    }

    // With no terminal width (piped), the full command is preserved.
    var piped: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer piped.deinit();
    try output.writeTable(&piped.writer, entries[0..], .{ .verbose = true });
    try std.testing.expect(std.mem.indexOf(u8, piped.written(), full) != null);
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

test "default JSON keeps its schema for multiple endpoints of one process" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    const entries = [_]PortEntry{
        entryIPv4(3000, 123, "node", .{ 127, 0, 0, 1 }),
        entryIPv6(3000, 123, "node", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }),
    };
    try output.writeJson(&writer.writer, &entries, .{});

    try std.testing.expectEqualStrings(
        "[\n" ++
            "  {\"port\":3000,\"pid\":123,\"proto\":\"tcp\",\"process\":\"node\",\"address\":\"127.0.0.1\"},\n" ++
            "  {\"port\":3000,\"pid\":123,\"proto\":\"tcp\",\"process\":\"node\",\"address\":\"::1\"}\n" ++
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

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"address\":\"2001:db8::1\"") != null);
}

test "JSON output renders scoped IPv6 addresses" {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    var entries = [_]PortEntry{entryIPv6(8080, 42, "server", .{
        0xfe, 0x80, 0, 0,
        0,    0,    0, 0,
        0,    0,    0, 0,
        0,    0,    0, 1,
    })};
    entries[0].scope_id = 7;
    try output.writeJson(&writer.writer, entries[0..], .{});

    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "\"address\":\"fe80::1%7\"") != null);
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

test "CLI parses exposed flag in scan and watch" {
    try std.testing.expect(!(try expectConfig(cli.parseArgs((&[_][]const u8{"localports"})[0..]))).exposed);

    const scan = [_][]const u8{ "localports", "--exposed" };
    const scan_config = try expectConfig(cli.parseArgs(scan[0..]));
    try std.testing.expectEqual(cli.Action.scan, scan_config.action);
    try std.testing.expect(scan_config.exposed);

    const watch_argv = [_][]const u8{ "localports", "--watch", "--exposed" };
    const watch_config = try expectConfig(cli.parseArgs(watch_argv[0..]));
    try std.testing.expectEqual(cli.Action.watch, watch_config.action);
    try std.testing.expect(watch_config.exposed);
}

test "CLI parses no-color flag" {
    try std.testing.expect(!(try expectConfig(cli.parseArgs((&[_][]const u8{"localports"})[0..]))).no_color);

    const argv = [_][]const u8{ "localports", "--no-color" };
    const config = try expectConfig(cli.parseArgs(argv[0..]));
    try std.testing.expectEqual(cli.Action.scan, config.action);
    try std.testing.expect(config.no_color);
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

test "docker lookup resolves address-specific mappings on the same port" {
    const text =
        "web4\tnginx:alpine\t127.0.0.1:18080->80/tcp\n" ++
        "web6\tnginx:alpine\t[::1]:18080->81/tcp\n";
    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);

    const ipv4 = entryIPv4(18080, 1, "com.docker.backend", .{ 127, 0, 0, 1 });
    const ipv6 = entryIPv6(18080, 1, "com.docker.backend", .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 });

    const c4 = docker.lookupEntry(mappings, &ipv4) orelse return error.MissingIpv4Mapping;
    try std.testing.expectEqualStrings("web4", c4.name);
    try std.testing.expectEqual(@as(u16, 80), c4.container_port);

    const c6 = docker.lookupEntry(mappings, &ipv6) orelse return error.MissingIpv6Mapping;
    try std.testing.expectEqualStrings("web6", c6.name);
    try std.testing.expectEqual(@as(u16, 81), c6.container_port);
}

test "docker lookup does not guess across conflicting port mappings" {
    const text =
        "web4\tnginx:alpine\t0.0.0.0:18080->80/tcp\n" ++
        "web6\tcaddy:alpine\t[::]:18080->81/tcp\n";
    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);

    const unmatched = entryIPv4(18080, 1, "com.docker.backend", .{ 127, 0, 0, 1 });
    try std.testing.expect(docker.lookupEntry(mappings, &unmatched) == null);
}

test "docker lookup ignores UDP publications on a TCP listener port" {
    const text =
        "web\tnginx:alpine\t127.0.0.1:18080->80/tcp\n" ++
        "dns\tdnsmasq:latest\t127.0.0.1:18080->53/udp\n";
    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);

    const listener = entryIPv4(18080, 1, "com.docker.backend", .{ 127, 0, 0, 1 });
    const container = docker.lookupEntry(mappings, &listener) orelse return error.MissingTcpMapping;
    try std.testing.expectEqualStrings("web", container.name);
    try std.testing.expectEqual(@as(u16, 80), container.container_port);
}

test "docker parsePsOutput expands published port ranges" {
    const text = "web\tnginx:alpine\t0.0.0.0:8000-8002->80-82/tcp\n";

    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);

    try std.testing.expectEqual(@as(usize, 3), mappings.len);
    for (0..3) |i| {
        const host_port: u16 = @intCast(8000 + i);
        const container_port: u16 = @intCast(80 + i);
        const c = docker.lookup(mappings, host_port) orelse return error.MissingRangePort;
        try std.testing.expectEqualStrings("web", c.name);
        try std.testing.expectEqualStrings("nginx:alpine", c.image);
        try std.testing.expectEqual(container_port, c.container_port);
    }
}

test "docker parsePsOutput skips mismatched port ranges" {
    const text = "web\tnginx:alpine\t0.0.0.0:8000-8002->80-81/tcp\n";
    const mappings = try docker.parsePsOutput(std.testing.allocator, text);
    defer std.testing.allocator.free(mappings);
    try std.testing.expectEqual(@as(usize, 0), mappings.len);
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

/// Append `s` to `out` with CSI escape sequences (ESC [ ... final-byte) removed,
/// for asserting that color escapes do not alter the visible layout.
fn stripAnsi(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and (s[i] < 0x40 or s[i] > 0x7e)) : (i += 1) {} // params
            if (i < s.len) i += 1; // final byte
        } else {
            try out.append(allocator, s[i]);
            i += 1;
        }
    }
}

fn listenOnLoopbackEphemeralPort() !std.c.fd_t {
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, std.c.IPPROTO.TCP);
    if (fd < 0) return error.SocketFailed;
    errdefer _ = std.c.close(fd);

    var addr = std.mem.zeroes(std.c.sockaddr.in);
    addr.len = @sizeOf(std.c.sockaddr.in);
    addr.family = std.c.AF.INET;
    addr.port = 0;
    addr.addr = std.mem.nativeToBig(u32, 0x7f000001);

    if (std.c.bind(fd, @ptrCast(&addr), @sizeOf(std.c.sockaddr.in)) != 0) return error.BindFailed;
    if (std.c.listen(fd, 1) != 0) return error.ListenFailed;
    return fd;
}

fn boundPort(fd: std.c.fd_t) !u16 {
    var addr = std.mem.zeroes(std.c.sockaddr.in);
    var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
    if (std.c.getsockname(fd, @ptrCast(&addr), &len) != 0) return error.GetSockNameFailed;
    return std.mem.bigToNative(u16, addr.port);
}

fn listenOnIpv6Port(port: u16, address: [16]u8) !std.c.fd_t {
    const fd = std.c.socket(std.c.AF.INET6, std.c.SOCK.STREAM, std.c.IPPROTO.TCP);
    if (fd < 0) return error.SocketFailed;
    errdefer _ = std.c.close(fd);

    var one: c_int = 1;
    const IPV6_V6ONLY: u32 = 27;
    if (std.c.setsockopt(fd, std.c.IPPROTO.IPV6, IPV6_V6ONLY, &one, @sizeOf(c_int)) != 0)
        return error.SetSockOptFailed;

    var addr = std.mem.zeroes(std.c.sockaddr.in6);
    addr.len = @sizeOf(std.c.sockaddr.in6);
    addr.family = std.c.AF.INET6;
    addr.port = std.mem.nativeToBig(u16, port);
    addr.addr = address;

    if (std.c.bind(fd, @ptrCast(&addr), @sizeOf(std.c.sockaddr.in6)) != 0) return error.BindFailed;
    if (std.c.listen(fd, 1) != 0) return error.ListenFailed;
    return fd;
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
