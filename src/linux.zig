 const std = @import("std");
 const types = @import("types.zig");
 const PortEntry = types.PortEntry;
 
 pub fn scan(_: std.mem.Allocator, _: ?u16) ![]PortEntry {
     @compileError("Linux support is not yet implemented");
 }
