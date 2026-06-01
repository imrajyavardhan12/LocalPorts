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
            try killHandler(allocator, config.kill_port.?, config.force_kill, init.io);
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

    var out_buf: [65536]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    const w = &file_writer.interface;
    if (config.json_output) {
        try output.writeJson(w, entries);
    } else {
        try output.writeTable(w, entries);
    }
    try w.flush();
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
        .invalid_port_number => fatal("invalid port number"),
        .watch_json_unsupported => fatal("--json cannot be used with --watch"),
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
        \\  --force, -f         Skip confirmation for --kill
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

fn killHandler(allocator: std.mem.Allocator, port: u16, force: bool, io: std.Io) !void {
    const entries = try doScan(allocator, port);
    defer allocator.free(entries);

    const entry = switch (killcmd.selectTarget(entries)) {
        .none => {
            std.debug.print("No process found listening on port {d}.\n", .{port});
            std.process.exit(1);
        },
        .multiple => |count| {
            std.debug.print("Multiple processes ({d}) found listening on port {d}; refusing to choose one automatically.\n", .{ count, port });

            var out_buf: [65536]u8 = undefined;
            var file_writer = std.Io.File.stdout().writer(io, &out_buf);
            const w = &file_writer.interface;
            try output.writeTable(w, entries);
            try w.flush();

            std.process.exit(1);
        },
        .target => |entry| entry,
    };
    const pid: std.posix.pid_t = @intCast(entry.pid);

    if (!force) {
        const name = entry.name[0..entry.name_len];
        std.debug.print("Kill process {s} (PID {d}) on port {d}? [y/N] ", .{ name, entry.pid, port });
        var stdin_buf: [1]u8 = undefined;
        const bytes_read = std.posix.read(std.posix.STDIN_FILENO, &stdin_buf) catch 0;
        const confirm = if (bytes_read > 0) stdin_buf[0] else 'n';
        std.debug.print("\n", .{});
        if (confirm != 'y' and confirm != 'Y') {
            std.process.exit(2);
        }
    }

    // Best-effort: PID may be recycled between scan and signal; macOS does not
    // provide a pidfd-style handle here, so this CLI accepts that inherent race.
    std.posix.kill(pid, std.posix.SIG.TERM) catch |e| {
        if (e == error.PermissionDenied) {
            std.debug.print("error: permission denied. Try running with sudo.\n", .{});
        } else {
            std.debug.print("error: failed to send signal: {}\n", .{e});
        }
        std.process.exit(1);
    };

    // Wait up to 5 seconds for process to exit via SIGTERM.
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
            std.debug.print("error: failed to send SIGKILL: {}\n", .{e});
            std.process.exit(1);
        };

        for (0..10) |_| {
            try std.Io.sleep(io, .fromMilliseconds(100), .awake);
            if (!processExists(pid)) break;
        }
    }

    const name = entry.name[0..entry.name_len];
    if (processExists(pid)) {
        std.debug.print("error: process {s} (PID {d}) still appears to be running after SIGKILL.\n", .{ name, entry.pid });
        std.process.exit(1);
    }

    std.debug.print("Killed {s} (PID {d})\n", .{ name, entry.pid });
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
