const std = @import("std");

pub const PortEntry = struct {
    port: u16,
    pid: u32,
    name: [256]u8,
    name_len: usize,
    addr4: [4]u8,
    addr6: [16]u8,
    is_ipv6: bool,
    scope_id: u32 = 0,
    // Verbose-only fields, populated on demand by the platform backend's
    // enrich step. Null means not requested or not available (e.g. another
    // user's process without sudo). Backed by a caller-owned arena.
    user: ?[]const u8 = null,
    command: ?[]const u8 = null,
    // Process ancestry (immediate parent first, up toward launchd), populated
    // on demand by enrich under --tree. Null means not requested. Arena-backed.
    ancestors: ?[]const Ancestor = null,
    // Owning Docker container, populated on demand under --docker when the
    // listener is held by a Docker process. Null means not requested, not a
    // Docker port, or unresolved. Arena-backed.
    container: ?Container = null,
};

/// One link in a process's ancestry chain.
pub const Ancestor = struct {
    pid: u32,
    name: []const u8,
};

/// The Docker container publishing a host port.
pub const Container = struct {
    name: []const u8,
    image: []const u8,
    container_port: u16,
};

pub const RowState = enum {
    new,
    removed,
    unchanged,
};

pub const WatchEntry = struct {
    entry: PortEntry,
    state: RowState,
};

pub const ScanDiagnostics = struct {
    inaccessible_processes: usize = 0,
    malformed_results: usize = 0,
    truncated: bool = false,

    pub fn mayBeIncomplete(diagnostics: ScanDiagnostics) bool {
        return diagnostics.inaccessible_processes > 0 or
            diagnostics.malformed_results > 0 or
            diagnostics.truncated;
    }
};

pub const ScanResult = struct {
    entries: []PortEntry,
    diagnostics: ScanDiagnostics,
};

pub const ListenerKey = struct {
    port: u16,
    pid: u32,
    is_ipv6: bool,
    address: [16]u8,
    scope_id: u32,
};

pub fn listenerKey(entry: *const PortEntry) ListenerKey {
    var address = [_]u8{0} ** 16;
    if (entry.is_ipv6) {
        address = entry.addr6;
    } else {
        @memcpy(address[0..4], &entry.addr4);
    }
    return .{
        .port = entry.port,
        .pid = entry.pid,
        .is_ipv6 = entry.is_ipv6,
        .address = address,
        .scope_id = if (entry.is_ipv6) entry.scope_id else 0,
    };
}

pub fn listenerLessThan(_: void, a: PortEntry, b: PortEntry) bool {
    const a_key = listenerKey(&a);
    const b_key = listenerKey(&b);
    if (a_key.port != b_key.port) return a_key.port < b_key.port;
    if (a_key.pid != b_key.pid) return a_key.pid < b_key.pid;
    if (a_key.is_ipv6 != b_key.is_ipv6) return !a_key.is_ipv6;
    switch (std.mem.order(u8, &a_key.address, &b_key.address)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return a_key.scope_id < b_key.scope_id;
}

/// Where a listener is reachable from, derived from its bind address.
pub const Scope = enum { local, network };

/// Classify a listener by its bind address: `local` if bound to a loopback
/// address (only this machine can connect), `network` otherwise — `0.0.0.0`,
/// `::`, or a real interface address, i.e. reachable from at least one network.
/// This reflects the bind scope only; a firewall may still block inbound
/// traffic, so callers should describe `network` as "reachable from your
/// network", not "exposed to the internet".
pub fn scopeOf(e: *const PortEntry) Scope {
    if (e.is_ipv6) {
        if (isIpv6Loopback(&e.addr6)) return .local;
        // IPv4-mapped (::ffff:a.b.c.d): judge by the embedded IPv4 address.
        if (ipv4MappedOctets(&e.addr6)) |v4| {
            return if (v4[0] == 127) .local else .network;
        }
        return .network;
    }
    // IPv4 loopback is the whole 127.0.0.0/8 block.
    return if (e.addr4[0] == 127) .local else .network;
}

fn isIpv6Loopback(a: *const [16]u8) bool {
    for (a[0..15]) |b| {
        if (b != 0) return false;
    }
    return a[15] == 1;
}

/// If `a` is an IPv4-mapped IPv6 address (`::ffff:0:0/96`), return its four IPv4
/// octets; otherwise null.
fn ipv4MappedOctets(a: *const [16]u8) ?[4]u8 {
    for (a[0..10]) |b| {
        if (b != 0) return null;
    }
    if (a[10] != 0xff or a[11] != 0xff) return null;
    return .{ a[12], a[13], a[14], a[15] };
}

/// Return a freshly owned slice of the network-reachable (non-loopback) entries,
/// preserving order. The caller still owns `entries` and frees it separately.
pub fn filterExposed(allocator: std.mem.Allocator, entries: []const PortEntry) ![]PortEntry {
    var kept: std.ArrayList(PortEntry) = .empty;
    errdefer kept.deinit(allocator);
    for (entries) |e| {
        if (scopeOf(&e) == .network) try kept.append(allocator, e);
    }
    return kept.toOwnedSlice(allocator);
}
