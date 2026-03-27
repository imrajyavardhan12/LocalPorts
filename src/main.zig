const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const output = @import("output.zig");

const version = "0.1.1";
 
 pub fn main() !void {
     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
     defer _ = gpa.deinit();
     const allocator = gpa.allocator();
 
     const args = try std.process.argsAlloc(allocator);
     defer std.process.argsFree(allocator, args);
 
     var filter_port: ?u16 = null;
     var json_output = false;
 
     var i: usize = 1;
     while (i < args.len) : (i += 1) {
         const arg = args[i];
         if (std.mem.eql(u8, arg, "--json")) {
             json_output = true;
         } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
             i += 1;
             if (i >= args.len) fatal("--port requires a value");
             filter_port = std.fmt.parseInt(u16, args[i], 10) catch fatal("invalid port number");
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "version")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
             printHelp();
             return;
         } else if (std.fmt.parseInt(u16, arg, 10)) |port| {
             filter_port = port;
         } else |_| {
             std.debug.print("error: unknown argument: {s}\n", .{arg});
             std.process.exit(1);
         }
     }
 
     const entries = try doScan(allocator, filter_port);
     defer allocator.free(entries);
 
     var out_buf: [65536]u8 = undefined;
     var file_writer = std.fs.File.stdout().writer(&out_buf);
     const w = &file_writer.interface;
     if (json_output) {
         try output.writeJson(w, entries);
     } else {
         try output.writeTable(w, entries);
     }
     try w.flush();
 }
 
 fn doScan(allocator: std.mem.Allocator, filter_port: ?u16) ![]types.PortEntry {
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
 
 fn printHelp() void {
     std.debug.print(
         \\Usage: localports [options] [port]
         \\
         \\Options:
         \\  --port, -p <port>  Filter by port number
         \\  --json             Output as JSON
         \\  --help, -h         Show this help
         \\
         \\Examples:
         \\  localports
         \\  localports 3000
         \\  localports --port 3000
         \\  localports --json
         \\
         \\Note: run with sudo to see all processes.
         \\
     , .{});
 }

fn printVersion() void {
    var out_buf: [64]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&out_buf);
    const w = &file_writer.interface;
    w.print("localports {s}\n", .{version}) catch {};
    w.flush() catch {};
}
