pub const PortEntry = struct {
    port: u16,
    pid: u32,
    name: [256]u8,
    name_len: usize,
    addr4: [4]u8,
    addr6: [16]u8,
    is_ipv6: bool,
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

pub fn portPidKey(port: u16, pid: u32) u64 {
    return (@as(u64, port) << 32) | @as(u64, pid);
}
