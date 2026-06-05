const types = @import("types.zig");
const PortEntry = types.PortEntry;

/// How a port kill should choose among the processes listening on that port.
pub const KillMode = union(enum) {
    /// `--kill <port>`: kill the sole listener, or refuse if more than one.
    single,
    /// `--kill <port> --all`: kill every listener on the port.
    all,
    /// `--kill <port> --pid <pid>`: kill that pid, only if it is on the port.
    pid: u32,
};

/// The decision for a port kill. `entries` are the processes already filtered
/// to the target port, so `many` means "kill all of `entries`".
pub const KillResolution = union(enum) {
    /// No process is listening on the port.
    none,
    /// `single` mode found more than one listener; refuse to choose.
    ambiguous: usize,
    /// `pid` mode: the requested pid is not listening on the port.
    pid_not_listed: u32,
    /// Exactly one process to kill.
    one: PortEntry,
    /// Kill all of `entries`; the value is the count.
    many: usize,
};

pub fn resolve(entries: []const PortEntry, mode: KillMode) KillResolution {
    if (entries.len == 0) return .none;
    switch (mode) {
        .single => {
            if (entries.len > 1) return .{ .ambiguous = entries.len };
            return .{ .one = entries[0] };
        },
        .all => return .{ .many = entries.len },
        .pid => |pid| {
            for (entries) |e| {
                if (e.pid == pid) return .{ .one = e };
            }
            return .{ .pid_not_listed = pid };
        },
    }
}
