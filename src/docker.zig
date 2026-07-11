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
    host_address: ?HostAddress,
    container: Container,
};

pub const HostAddress = union(enum) {
    ipv4: [4]u8,
    ipv6: [16]u8,
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
            if (!std.mem.endsWith(u8, tok, "/tcp")) continue;
            const host_address = hostAddressBeforeLastColon(tok[0..arrow]);
            const host_ports = portRangeAfterLastColon(tok[0..arrow]) orelse continue;
            const ctr_ports = portRangeBeforeSlash(tok[arrow + 2 ..]) orelse continue;
            if (host_ports.count() != ctr_ports.count()) continue;

            const n = host_ports.count();
            for (0..n) |offset| {
                const off: u32 = @intCast(offset);
                try list.append(allocator, .{
                    .host_port = @intCast(@as(u32, host_ports.start) + off),
                    .host_address = host_address,
                    .container = .{
                        .name = name,
                        .image = image,
                        .container_port = @intCast(@as(u32, ctr_ports.start) + off),
                    },
                });
            }
        }
    }

    std.mem.sort(Mapping, list.items, {}, struct {
        fn lessThan(_: void, a: Mapping, b: Mapping) bool {
            return a.host_port < b.host_port;
        }
    }.lessThan);
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

fn hostAddressBeforeLastColon(s: []const u8) ?HostAddress {
    const idx = std.mem.lastIndexOfScalar(u8, s, ':') orelse return null;
    var text = s[0..idx];
    if (text.len >= 2 and text[0] == '[' and text[text.len - 1] == ']') {
        text = text[1 .. text.len - 1];
    }
    const address = std.Io.net.IpAddress.parse(text, 0) catch return null;
    return switch (address) {
        .ip4 => |ip4| .{ .ipv4 = ip4.bytes },
        .ip6 => |ip6| .{ .ipv6 = ip6.bytes },
    };
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
    const start = firstMappingIndex(mappings, host_port) orelse return null;
    return mappings[start].container;
}

pub fn lookupEntry(mappings: []const Mapping, entry: *const PortEntry) ?Container {
    const start = firstMappingIndex(mappings, entry.port) orelse return null;
    var exact: ?Container = null;
    var exact_conflict = false;
    var fallback: ?Container = null;
    var fallback_conflict = false;

    for (mappings[start..]) |mapping| {
        if (mapping.host_port != entry.port) break;

        if (fallback) |current| {
            if (!sameContainer(current, mapping.container)) fallback_conflict = true;
        } else {
            fallback = mapping.container;
        }

        const host_address = mapping.host_address orelse continue;
        if (!addressMatches(host_address, entry)) continue;
        if (exact) |current| {
            if (!sameContainer(current, mapping.container)) exact_conflict = true;
        } else {
            exact = mapping.container;
        }
    }

    if (exact) |container| return if (exact_conflict) null else container;
    if (fallback) |container| return if (fallback_conflict) null else container;
    return null;
}

fn firstMappingIndex(mappings: []const Mapping, host_port: u16) ?usize {
    var low: usize = 0;
    var high = mappings.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (mappings[middle].host_port < host_port) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    if (low == mappings.len or mappings[low].host_port != host_port) return null;
    return low;
}

fn addressMatches(address: HostAddress, entry: *const PortEntry) bool {
    return switch (address) {
        .ipv4 => |bytes| !entry.is_ipv6 and std.mem.eql(u8, &bytes, &entry.addr4),
        .ipv6 => |bytes| entry.is_ipv6 and std.mem.eql(u8, &bytes, &entry.addr6),
    };
}

fn sameContainer(a: Container, b: Container) bool {
    return a.container_port == b.container_port and
        std.mem.eql(u8, a.name, b.name) and
        std.mem.eql(u8, a.image, b.image);
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
        e.container = lookupEntry(mappings, e);
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
