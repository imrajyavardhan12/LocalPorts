const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const output = @import("output.zig");
const cli = @import("cli.zig");
const killcmd = @import("kill.zig");
const watch = @import("watch.zig");
const PortEntry = types.PortEntry;

const version = @import("version.zig").version;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const config = switch (cli.parseArgs(args)) {
        .config => |config| config,
        .failure => |failure| fatalParse(failure),
    };

    switch (config.action) {
        .version => {
            printVersion(init.io);
            return;
        },
        .help => {
            printHelp(init.io);
            return;
        },
        .kill => {
            try killHandler(allocator, config, init.io);
            return;
        },
        .watch => {
            try watchLoop(allocator, config.watch_interval, config.filter_port, init.io);
            return;
        },
        .scan => {},
    }

    const entries = try doScan(allocator, config.filter_port);
    defer allocator.free(entries);

    // Enriched fields (user/command/ancestors) are arena-backed; one deinit
    // frees them all.
    var enrich_arena = std.heap.ArenaAllocator.init(allocator);
    defer enrich_arena.deinit();
    if (config.verbose or config.tree) {
        doEnrich(enrich_arena.allocator(), entries, config.verbose, config.tree);
    }

    const opts: output.Options = .{ .verbose = config.verbose, .tree = config.tree };
    var out_buf: [65536]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    const w = &file_writer.interface;
    if (config.json_output) {
        try output.writeJson(w, entries, opts);
    } else {
        try output.writeTable(w, entries, opts);
    }
    try w.flush();
}

fn doEnrich(arena: std.mem.Allocator, entries: []PortEntry, verbose: bool, tree: bool) void {
    if (builtin.os.tag == .macos) {
        @import("darwin.zig").enrich(arena, entries, verbose, tree);
    }
}

fn doScan(allocator: std.mem.Allocator, filter_port: ?u16) ![]PortEntry {
    if (builtin.os.tag == .macos) {
        return @import("darwin.zig").scan(allocator, filter_port);
    } else if (builtin.os.tag == .linux) {
        return @import("linux.zig").scan(allocator, filter_port);
    } else {
        @compileError("Unsupported operating system");
    }
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}

fn fatalParse(failure: cli.ParseFailure) noreturn {
    switch (failure.kind) {
        .port_requires_value => fatal("--port requires a value"),
        .kill_requires_value => fatal("--kill requires a value"),
        .pid_requires_value => fatal("--pid requires a value"),
        .kill_pid_requires_value => fatal("--kill-pid requires a value"),
        .invalid_port_number => fatal("invalid port number"),
        .invalid_pid_number => fatal("invalid pid number"),
        .watch_json_unsupported => fatal("--json cannot be used with --watch"),
        .all_or_pid_requires_kill_port => fatal("--all and --pid require --kill <port>"),
        .all_pid_conflict => fatal("--all cannot be combined with --pid"),
        .kill_pid_conflict => fatal("--kill-pid cannot be combined with --kill, --all, or --pid"),
        .unknown_argument => {
            std.debug.print("error: unknown argument: {s}\n", .{failure.arg.?});
            std.process.exit(1);
        },
    }
}

fn printHelp(io: std.Io) void {
    var out_buf: [2048]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &out_buf);
    const w = &file_writer.interface;
    w.print(
        \\Usage: localports [options] [port]
        \\
        \\Options:
        \\  --port, -p <port>  Filter by port number
        \\  --json             Output as JSON
        \\  --watch, -w [secs]  Watch mode (default 2 seconds)
        \\  --kill, -k <port>   Kill process on port (refuses ambiguous matches)
        \\  --all, -a           With --kill <port>: kill all matching processes
        \\  --pid <pid>         With --kill <port>: kill only that pid if on the port
        \\  --kill-pid <pid>    Kill a process by explicit PID
        \\  --force, -f         Skip confirmation for kills
        \\  --verbose           Show user and full command (scan only; use sudo for all)
        \\  --tree              Show each listener's parent process chain (scan only)
        \\  --version, -v       Show version
        \\  --help, -h          Show this help
        \\
        \\Examples:
        \\  localports
        \\  localports 3000
        \\  localports --port 3000
        \\  localports --json
        \\  localports --watch
        \\  localports --watch 1
        \\  localports 3000 --watch
        \\  localports --kill 3000
        \\  localports --kill 3000 --force
        \\  localports --kill 8000 --all
        \\  localports --kill 8000 --pid 6524
        \\  localports --kill-pid 6524
        \\
        \\Note: run with sudo to see all processes.
        \\
    , .{}) catch {};
    w.flush() catch {};
}

fn printVersion(io: std.Io) void {
    var out_buf: [64]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(io, &out_buf);
    const w = &file_writer.interface;
    w.print("localports {s}\n", .{version}) catch {};
    w.flush() catch {};
}

fn watchLoop(allocator: std.mem.Allocator, interval_secs: u32, filter_port: ?u16, io: std.Io) !void {
    const interval_ns: i96 = @as(i96, interval_secs) * std.time.ns_per_s;
    var previous_entries: ?[]PortEntry = null;
    defer if (previous_entries) |entries| allocator.free(entries);

    while (true) {
        var current_entries: ?[]PortEntry = try doScan(allocator, filter_port);
        errdefer if (current_entries) |entries| allocator.free(entries);

        const previous = if (previous_entries) |entries| entries else &.{};
        const current = current_entries.?;
        const watch_entries = try watch.classify(allocator, previous, current);
        defer allocator.free(watch_entries);

        var out_buf: [65536]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(io, &out_buf);
        const w = &file_writer.interface;
        try output.writeWatchTable(w, watch_entries);
        if (!watch.hasChanges(watch_entries) and watch_entries.len > 0) {
            try w.writeAll("No changes detected.\n");
        }
        try w.flush();

        if (previous_entries) |entries| allocator.free(entries);
        previous_entries = current_entries;
        current_entries = null;

        try std.Io.sleep(io, .fromNanoseconds(interval_ns), .awake);
    }
}

fn killHandler(allocator: std.mem.Allocator, config: cli.Config, io: std.Io) !void {
    // Standalone --kill-pid <pid>: kill by explicit PID, no port lookup.
    if (config.kill_pid) |pid| {
        try killByPid(pid, config.force_kill, io);
        return;
    }

    const port = config.kill_port.?;
    const entries = try doScan(allocator, port);
    defer allocator.free(entries);

    const mode: killcmd.KillMode = if (config.kill_all)
        .all
    else if (config.kill_match_pid) |p|
        .{ .pid = p }
    else
        .single;

    switch (killcmd.resolve(entries, mode)) {
        .none => {
            std.debug.print("No process found listening on port {d}.\n", .{port});
            std.process.exit(1);
        },
        .ambiguous => |count| {
            std.debug.print("Multiple processes ({d}) found listening on port {d}; refusing to choose one automatically. Use --all to kill all, or --pid <pid> to choose.\n", .{ count, port });
            var out_buf: [65536]u8 = undefined;
            var file_writer = std.Io.File.stdout().writer(io, &out_buf);
            const w = &file_writer.interface;
            try output.writeTable(w, entries, .{});
            try w.flush();
            std.process.exit(1);
        },
        .pid_not_listed => |p| {
            std.debug.print("PID {d} is not listening on port {d}.\n", .{ p, port });
            std.process.exit(1);
        },
        .one => |entry| {
            const name = entry.name[0..entry.name_len];
            if (!config.force_kill) {
                std.debug.print("Kill process {s} (PID {d}) on port {d}? [y/N] ", .{ name, entry.pid, port });
                if (!confirmYes()) std.process.exit(2);
            }
            const result = try terminate(entry.pid, io);
            reportTerminate(result, name, entry.pid);
            if (!terminateSucceeded(result)) std.process.exit(1);
        },
        .many => {
            if (!config.force_kill) {
                std.debug.print("Kill all {d} processes on port {d}? [y/N] ", .{ entries.len, port });
                if (!confirmYes()) std.process.exit(2);
            }
            var any_failed = false;
            for (entries) |entry| {
                const result = try terminate(entry.pid, io);
                reportTerminate(result, entry.name[0..entry.name_len], entry.pid);
                if (!terminateSucceeded(result)) any_failed = true;
            }
            if (any_failed) std.process.exit(1);
        },
    }
}

fn killByPid(pid: u32, force: bool, io: std.Io) !void {
    // Guard the u32 -> pid_t boundary: a pid that overflows pid_t would wrap
    // negative, and kill() with a negative pid signals a process group. Refuse.
    if (pid == 0 or pid > std.math.maxInt(std.posix.pid_t)) {
        std.debug.print("error: invalid pid {d}.\n", .{pid});
        std.process.exit(1);
    }

    if (!processExists(@intCast(pid))) {
        std.debug.print("No process with PID {d}.\n", .{pid});
        std.process.exit(1);
    }

    var name_buf: [256]u8 = undefined;
    const name = doProcessName(pid, &name_buf) orelse "?";

    if (!force) {
        std.debug.print("Kill process {s} (PID {d})? [y/N] ", .{ name, pid });
        if (!confirmYes()) std.process.exit(2);
    }

    const result = try terminate(pid, io);
    reportTerminate(result, name, pid);
    if (!terminateSucceeded(result)) std.process.exit(1);
}

const TerminateResult = enum { killed, already_gone, permission_denied, signal_failed, still_running };

fn terminateSucceeded(result: TerminateResult) bool {
    return result == .killed or result == .already_gone;
}

/// Send SIGTERM, wait up to 5s, then escalate to SIGKILL and verify the
/// process is gone. PID may be recycled between scan and signal; macOS does
/// not offer a pidfd-style handle, so this CLI accepts that inherent race.
/// A process that is already gone counts as success — important for --all,
/// where killing one listener (e.g. a server master) can make its workers
/// exit before the loop reaches them.
fn terminate(pid_u32: u32, io: std.Io) !TerminateResult {
    const pid: std.posix.pid_t = @intCast(pid_u32);

    std.posix.kill(pid, std.posix.SIG.TERM) catch |e| {
        return switch (e) {
            error.ProcessNotFound => .already_gone,
            error.PermissionDenied => .permission_denied,
            else => .signal_failed,
        };
    };

    var exited = false;
    for (0..50) |_| {
        try std.Io.sleep(io, .fromMilliseconds(100), .awake);
        if (!processExists(pid)) {
            exited = true;
            break;
        }
    }

    if (!exited) {
        std.posix.kill(pid, std.posix.SIG.KILL) catch |e| {
            if (e == error.ProcessNotFound) return .killed;
            return .signal_failed;
        };
        for (0..10) |_| {
            try std.Io.sleep(io, .fromMilliseconds(100), .awake);
            if (!processExists(pid)) break;
        }
    }

    return if (processExists(pid)) .still_running else .killed;
}

fn reportTerminate(result: TerminateResult, name: []const u8, pid: u32) void {
    switch (result) {
        .killed => std.debug.print("Killed {s} (PID {d})\n", .{ name, pid }),
        .already_gone => std.debug.print("{s} (PID {d}) is already gone.\n", .{ name, pid }),
        .permission_denied => std.debug.print("error: permission denied for {s} (PID {d}). Try running with sudo.\n", .{ name, pid }),
        .signal_failed => std.debug.print("error: failed to signal {s} (PID {d}).\n", .{ name, pid }),
        .still_running => std.debug.print("error: {s} (PID {d}) still appears to be running after SIGKILL.\n", .{ name, pid }),
    }
}

fn confirmYes() bool {
    var stdin_buf: [1]u8 = undefined;
    const bytes_read = std.posix.read(std.posix.STDIN_FILENO, &stdin_buf) catch 0;
    std.debug.print("\n", .{});
    return bytes_read > 0 and (stdin_buf[0] == 'y' or stdin_buf[0] == 'Y');
}

fn doProcessName(pid: u32, buf: *[256]u8) ?[]const u8 {
    if (builtin.os.tag == .macos) {
        if (@import("darwin.zig").processName(pid, buf)) |len| return buf[0..len];
    }
    return null;
}

fn processExists(pid: std.posix.pid_t) bool {
    if (builtin.os.tag == .macos) {
        return @import("darwin.zig").processIsRunning(@intCast(pid));
    }

    std.posix.kill(pid, @enumFromInt(0)) catch |e| switch (e) {
        error.ProcessNotFound => return false,
        error.PermissionDenied => return true,
        else => return true,
    };
    return true;
}
