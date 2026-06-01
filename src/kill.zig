const types = @import("types.zig");
const PortEntry = types.PortEntry;

pub const TargetSelection = union(enum) {
    none,
    target: PortEntry,
    multiple: usize,
};

pub fn selectTarget(entries: []const PortEntry) TargetSelection {
    if (entries.len == 0) return .none;
    if (entries.len > 1) return .{ .multiple = entries.len };
    return .{ .target = entries[0] };
}
