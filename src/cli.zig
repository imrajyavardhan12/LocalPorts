const std = @import("std");

pub const Action = enum {
    scan,
    watch,
    kill,
    help,
    version,
};

pub const Config = struct {
    action: Action = .scan,
    filter_port: ?u16 = null,
    json_output: bool = false,
    watch_interval: u32 = 2,
    kill_port: ?u16 = null,
    force_kill: bool = false,
    verbose: bool = false,
    tree: bool = false,
    // Kill controls. `kill_all` and `kill_match_pid` refine `--kill <port>`;
    // `kill_pid` is a standalone `--kill-pid <pid>` target.
    kill_all: bool = false,
    kill_match_pid: ?u32 = null,
    kill_pid: ?u32 = null,
};

pub const ParseFailureKind = enum {
    port_requires_value,
    kill_requires_value,
    pid_requires_value,
    kill_pid_requires_value,
    invalid_port_number,
    invalid_pid_number,
    watch_json_unsupported,
    all_or_pid_requires_kill_port,
    all_pid_conflict,
    kill_pid_conflict,
    unknown_argument,
};

pub const ParseFailure = struct {
    kind: ParseFailureKind,
    arg: ?[]const u8 = null,
};

pub const ParseResult = union(enum) {
    config: Config,
    failure: ParseFailure,
};

pub fn parseArgs(args: anytype) ParseResult {
    var config: Config = .{};
    var watch_seen = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg: []const u8 = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            config.json_output = true;
        } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) return fail(.port_requires_value, null);
            config.filter_port = std.fmt.parseInt(u16, args[i], 10) catch return fail(.invalid_port_number, args[i]);
        } else if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
            watch_seen = true;
            config.watch_interval = 2;

            if (i + 1 < args.len) {
                const next_arg: []const u8 = args[i + 1];
                if (std.fmt.parseInt(u32, next_arg, 10)) |interval| {
                    i += 1;
                    config.watch_interval = @max(interval, 1);
                } else |_| {}
            }
        } else if (std.mem.eql(u8, arg, "--kill") or std.mem.eql(u8, arg, "-k")) {
            i += 1;
            if (i >= args.len) return fail(.kill_requires_value, null);
            config.kill_port = std.fmt.parseInt(u16, args[i], 10) catch return fail(.invalid_port_number, args[i]);
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            config.force_kill = true;
        } else if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
            config.kill_all = true;
        } else if (std.mem.eql(u8, arg, "--pid")) {
            i += 1;
            if (i >= args.len) return fail(.pid_requires_value, null);
            config.kill_match_pid = std.fmt.parseInt(u32, args[i], 10) catch return fail(.invalid_pid_number, args[i]);
        } else if (std.mem.eql(u8, arg, "--kill-pid")) {
            i += 1;
            if (i >= args.len) return fail(.kill_pid_requires_value, null);
            config.kill_pid = std.fmt.parseInt(u32, args[i], 10) catch return fail(.invalid_pid_number, args[i]);
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--tree")) {
            config.tree = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "version")) {
            config.action = .version;
            return .{ .config = config };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            config.action = .help;
            return .{ .config = config };
        } else if (std.fmt.parseInt(u16, arg, 10)) |port| {
            config.filter_port = port;
        } else |_| {
            return fail(.unknown_argument, arg);
        }
    }

    const port_kill = config.kill_port != null;
    const direct_kill = config.kill_pid != null;

    // --all and --pid both narrow a port kill but contradict each other.
    if (config.kill_all and config.kill_match_pid != null)
        return fail(.all_pid_conflict, null);

    // --kill-pid is a standalone target; it cannot combine with port-kill flags.
    if (direct_kill and (port_kill or config.kill_all or config.kill_match_pid != null))
        return fail(.kill_pid_conflict, null);

    // --all / --pid only make sense as refinements of --kill <port>.
    if ((config.kill_all or config.kill_match_pid != null) and !port_kill)
        return fail(.all_or_pid_requires_kill_port, null);

    if (port_kill or direct_kill) {
        config.action = .kill;
    } else if (watch_seen) {
        if (config.json_output) return fail(.watch_json_unsupported, null);
        config.action = .watch;
    } else {
        config.action = .scan;
    }

    return .{ .config = config };
}

fn fail(kind: ParseFailureKind, arg: ?[]const u8) ParseResult {
    return .{ .failure = .{ .kind = kind, .arg = arg } };
}
