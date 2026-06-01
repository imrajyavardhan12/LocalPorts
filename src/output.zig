const std = @import("std");
const types = @import("types.zig");
const PortEntry = types.PortEntry;
const WatchEntry = types.WatchEntry;
const RowState = types.RowState;

pub const ansi = struct {
    pub const green = "\x1b[32m";
    pub const red = "\x1b[31m";
    pub const reset = "\x1b[0m";
    pub const clear_screen = "\x1b[2J\x1b[H";
};

pub fn writeTable(writer: anytype, entries: []const PortEntry) !void {
    if (entries.len == 0) {
        try writer.writeAll("No listening TCP ports found.\n");
        return;
    }

    // Compute PROCESS column width (min 7 for header, +2 for spacing).
    var proc_col: usize = 9;
    for (entries) |e| {
        if (e.name_len + 2 > proc_col) proc_col = e.name_len + 2;
    }

    // Header row.
    try writer.print("PORT   PID    ", .{});
    try padWrite(writer, "PROCESS", proc_col);
    try writer.writeAll("ADDRESS\n");

    for (entries) |e| {
        const name = e.name[0..e.name_len];
        try writer.print("{d:<6} {d:<6} ", .{ e.port, e.pid });
        try padWrite(writer, name, proc_col);
        try writeAddrStr(writer, &e);
        try writer.writeByte('\n');
    }
}

pub fn writeJson(writer: anytype, entries: []const PortEntry) !void {
    try writer.writeByte('[');
    for (entries, 0..) |e, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("\n  {");
        try writer.print("\"port\":{d},\"pid\":{d},\"proto\":\"tcp\",\"process\":\"", .{ e.port, e.pid });
        try writeJsonEscaped(writer, e.name[0..e.name_len]);
        try writer.writeAll("\",\"address\":\"");
        try writeAddrStr(writer, &e);
        try writer.writeAll("\"}");
    }
    if (entries.len > 0) try writer.writeByte('\n');
    try writer.writeAll("]\n");
}

pub fn writeWatchTable(writer: anytype, entries: []const WatchEntry) !void {
    try writer.writeAll(ansi.clear_screen);

    if (entries.len == 0) {
        try writer.writeAll("No listening TCP ports found.\n");
        return;
    }

    // Compute PROCESS column width.
    var proc_col: usize = 9;
    for (entries) |we| {
        if (we.entry.name_len + 2 > proc_col) proc_col = we.entry.name_len + 2;
    }

    // Header row.
    try writer.print("PORT   PID    ", .{});
    try padWrite(writer, "PROCESS", proc_col);
    try writer.writeAll("ADDRESS\n");

    for (entries) |we| {
        const e = we.entry;
        const color = switch (we.state) {
            .new => ansi.green,
            .removed => ansi.red,
            .unchanged => "",
        };
        const reset_color = if (color.len > 0) ansi.reset else "";
        const name = e.name[0..e.name_len];
        try writer.print("{s}{d:<6} {d:<6} ", .{ color, e.port, e.pid });
        try padWrite(writer, name, proc_col);
        try writeAddrStr(writer, &e);
        try writer.writeAll(reset_color);
        try writer.writeByte('\n');
    }
}

fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x08 => try writer.writeAll("\\b"),
            0x0c => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

fn padWrite(writer: anytype, s: []const u8, col_width: usize) !void {
    try writer.writeAll(s);
    var i = s.len;
    while (i < col_width) : (i += 1) try writer.writeByte(' ');
}

fn writeAddrStr(writer: anytype, e: *const PortEntry) !void {
    if (e.is_ipv6) {
        const b = &e.addr6;
        var i: usize = 0;
        while (i < 16) : (i += 2) {
            if (i > 0) try writer.writeByte(':');
            try writer.print("{x:0>2}{x:0>2}", .{ b[i], b[i + 1] });
        }
    } else {
        const b = &e.addr4;
        try writer.print("{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] });
    }
}
