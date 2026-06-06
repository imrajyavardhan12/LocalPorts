const std = @import("std");
const types = @import("types.zig");
const PortEntry = types.PortEntry;
const Container = types.Container;

const docker_ps_timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } };

/// Process names that own a published Docker port on the host. Docker Desktop
/// for Mac uses `com.docker.backend`; older setups used the proxy/vpnkit.
const docker_process_names = [_][]const u8{
    "com.docker.backend",
    "docker-proxy",
    "vpnkit",
    "com.docker.vpnkit",
};

pub fn isDockerProcess(name: []const u8) bool {
    for (docker_process_names) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    return false;
}

/// A single host-port → container mapping parsed from `docker ps`.
pub const Mapping = struct {
    host_port: u16,
    container: Container,
};

/// Parse `docker ps` output where each line is `name\timage\tports` and the
/// ports field is a comma-separated list of `HOST_IP:HOST_PORT->CTR_PORT/proto`
/// (e.g. `0.0.0.0:18080->80/tcp, [::]:18080->80/tcp`). Published port ranges
/// (e.g. `0.0.0.0:8000-8002->80-82/tcp`) expand to one mapping per host port.
/// Tokens without a host publish (no `->`) or with mismatched ranges are skipped.
/// Pure: the returned slices borrow `text`, so keep `text` alive for the lifetime
/// of the result.
pub fn parsePsOutput(allocator: std.mem.Allocator, text: []const u8) ![]Mapping {
    var list: std.ArrayList(Mapping) = .empty;
    errdefer list.deinit(allocator);

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.mem.splitScalar(u8, line, '\t');
        const name = fields.next() orelse continue;
        const image = fields.next() orelse continue;
        const ports = fields.next() orelse continue;

        var tokens = std.mem.splitScalar(u8, ports, ',');
        while (tokens.next()) |raw| {
            const tok = std.mem.trim(u8, raw, " ");
            const arrow = std.mem.indexOf(u8, tok, "->") orelse continue;
            const host_ports = portRangeAfterLastColon(tok[0..arrow]) orelse continue;
            const ctr_ports = portRangeBeforeSlash(tok[arrow + 2 ..]) orelse continue;
            if (host_ports.count() != ctr_ports.count()) continue;

            const n = host_ports.count();
            for (0..n) |offset| {
                const off: u32 = @intCast(offset);
                try list.append(allocator, .{
                    .host_port = @intCast(@as(u32, host_ports.start) + off),
                    .container = .{
                        .name = name,
                        .image = image,
                        .container_port = @intCast(@as(u32, ctr_ports.start) + off),
                    },
                });
            }
        }
    }

    return list.toOwnedSlice(allocator);
}

const PortRange = struct {
    start: u16,
    end: u16,

    fn count(r: PortRange) u32 {
        return @as(u32, r.end) - @as(u32, r.start) + 1;
    }
};

fn portRangeAfterLastColon(s: []const u8) ?PortRange {
    const idx = std.mem.lastIndexOfScalar(u8, s, ':') orelse return null;
    return parsePortRange(s[idx + 1 ..]);
}

fn portRangeBeforeSlash(s: []const u8) ?PortRange {
    const end = std.mem.indexOfScalar(u8, s, '/') orelse s.len;
    return parsePortRange(s[0..end]);
}

fn parsePortRange(s: []const u8) ?PortRange {
    const dash = std.mem.indexOfScalar(u8, s, '-');
    const start_text = if (dash) |idx| s[0..idx] else s;
    const end_text = if (dash) |idx| s[idx + 1 ..] else s;
    if (start_text.len == 0 or end_text.len == 0) return null;

    const start = std.fmt.parseInt(u16, start_text, 10) catch return null;
    const end = std.fmt.parseInt(u16, end_text, 10) catch return null;
    if (end < start) return null;
    return .{ .start = start, .end = end };
}

pub fn lookup(mappings: []const Mapping, host_port: u16) ?Container {
    for (mappings) |m| {
        if (m.host_port == host_port) return m.container;
    }
    return null;
}

/// Resolve the owning container for each Docker-held listener. Best-effort:
/// shells out to `docker ps` only when at least one entry is Docker-owned, and
/// degrades silently if docker is missing, the daemon is down, or a port has no
/// matching container. Strings are arena-backed (they borrow the captured
/// output), so the caller frees everything at once.
pub fn enrich(arena: std.mem.Allocator, entries: []PortEntry, io: std.Io) void {
    var any_docker = false;
    for (entries) |e| {
        if (isDockerProcess(e.name[0..e.name_len])) {
            any_docker = true;
            break;
        }
    }
    if (!any_docker) return;

    const text = runDockerPs(arena, io) orelse return;
    const mappings = parsePsOutput(arena, text) catch return;

    for (entries) |*e| {
        if (!isDockerProcess(e.name[0..e.name_len])) continue;
        e.container = lookup(mappings, e.port);
    }
}

fn runDockerPs(arena: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const result = std.process.run(arena, io, .{
        .argv = &.{ "docker", "ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Ports}}" },
        .timeout = docker_ps_timeout,
    }) catch return null;

    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    return result.stdout;
}
