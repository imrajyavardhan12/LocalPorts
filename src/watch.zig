const std = @import("std");
const types = @import("types.zig");

const PortEntry = types.PortEntry;
const WatchEntry = types.WatchEntry;
const RowState = types.RowState;

pub fn classify(allocator: std.mem.Allocator, previous: []const PortEntry, current: []const PortEntry) ![]WatchEntry {
    var previous_by_key: std.AutoArrayHashMapUnmanaged(u64, PortEntry) = .empty;
    defer previous_by_key.deinit(allocator);

    for (previous) |entry| {
        try previous_by_key.put(allocator, types.portPidKey(entry.port, entry.pid), entry);
    }

    var result: std.ArrayList(WatchEntry) = .empty;
    errdefer result.deinit(allocator);

    for (current) |entry| {
        const key = types.portPidKey(entry.port, entry.pid);
        const state: RowState = if (previous_by_key.contains(key)) .unchanged else .new;
        _ = previous_by_key.swapRemove(key);
        try result.append(allocator, .{ .entry = entry, .state = state });
    }

    for (previous_by_key.values()) |entry| {
        try result.append(allocator, .{ .entry = entry, .state = .removed });
    }

    std.mem.sort(WatchEntry, result.items, {}, struct {
        fn lt(_: void, a: WatchEntry, b: WatchEntry) bool {
            if (a.entry.port != b.entry.port) return a.entry.port < b.entry.port;
            return a.entry.pid < b.entry.pid;
        }
    }.lt);

    return try result.toOwnedSlice(allocator);
}

pub fn hasChanges(entries: []const WatchEntry) bool {
    for (entries) |entry| {
        if (entry.state != .unchanged) return true;
    }
    return false;
}
