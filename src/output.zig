const std = @import("std");
const types = @import("types.zig");
const PortEntry = types.PortEntry;
const Ancestor = types.Ancestor;
const Container = types.Container;
const WatchEntry = types.WatchEntry;
const RowState = types.RowState;

pub const ansi = struct {
    pub const green = "\x1b[32m";
    pub const red = "\x1b[31m";
    pub const reset = "\x1b[0m";
    // ED 0 (clear from cursor to end) after CUP home. Avoids ED 2
    // ("clear entire screen"), which modern terminals also apply to
    // the scrollback buffer — undesirable for a live-refresh tool.
    pub const clear_screen = "\x1b[H\x1b[J";
};

/// Display toggles for scan output. New display modes go here so call sites
/// stay self-documenting and the default contract is opt-in only.
pub const Options = struct {
    verbose: bool = false,
    tree: bool = false,
    docker: bool = false,
};

/// The variable columns that follow the fixed PORT/PID prefix. PROCESS and
/// ADDRESS are always present; USER/COMMAND come with --verbose and CONTAINER
/// with --docker. COMMAND is kept last (it can be very long) so it never needs
/// padding; every other column is padded to its width.
const Column = enum { process, address, user, container, command };

fn columnHeader(col: Column) []const u8 {
    return switch (col) {
        .process => "PROCESS",
        .address => "ADDRESS",
        .user => "USER",
        .container => "CONTAINER",
        .command => "COMMAND",
    };
}

/// Render a column's cell for `e` into `buf` (used for ADDRESS and CONTAINER);
/// other cells borrow existing slices. The returned slice is valid until the
/// next call that reuses `buf`.
fn columnCell(col: Column, e: *const PortEntry, buf: []u8) []const u8 {
    return switch (col) {
        .process => e.name[0..e.name_len],
        .address => formatAddr(buf, e),
        .user => e.user orelse "-",
        .command => e.command orelse "-",
        .container => formatContainer(buf, e.container),
    };
}

fn formatContainer(buf: []u8, container: ?Container) []const u8 {
    const c = container orelse return "-";
    return std.fmt.bufPrint(buf, "{s} ({s} ->{d})", .{ c.name, c.image, c.container_port }) catch "-";
}

pub fn writeTable(writer: anytype, entries: []const PortEntry, opts: Options) !void {
    if (entries.len == 0) {
        try writer.writeAll("No listening TCP ports found.\n");
        return;
    }

    // Assemble the column list. COMMAND stays last; CONTAINER sits before it.
    var cols: [5]Column = undefined;
    var n: usize = 0;
    cols[n] = .process;
    n += 1;
    cols[n] = .address;
    n += 1;
    if (opts.verbose) {
        cols[n] = .user;
        n += 1;
    }
    if (opts.docker) {
        cols[n] = .container;
        n += 1;
    }
    if (opts.verbose) {
        cols[n] = .command;
        n += 1;
    }
    const columns = cols[0..n];
    const last = n - 1;

    // Compute padded widths for every column except the last (rendered raw).
    var cell_buf: [1024]u8 = undefined;
    var widths: [5]usize = .{0} ** 5;
    for (columns, 0..) |col, ci| {
        if (ci == last) break;
        var w: usize = columnHeader(col).len + 2;
        for (entries) |e| {
            const len = columnCell(col, &e, &cell_buf).len;
            if (len + 2 > w) w = len + 2;
        }
        widths[ci] = w;
    }

    // Header.
    try writer.print("PORT   PID    ", .{});
    for (columns, 0..) |col, ci| {
        if (ci == last) {
            try writer.writeAll(columnHeader(col));
        } else {
            try padWrite(writer, columnHeader(col), widths[ci]);
        }
    }
    try writer.writeByte('\n');

    // Rows.
    for (entries) |e| {
        try writer.print("{d:<6} {d:<6} ", .{ e.port, e.pid });
        for (columns, 0..) |col, ci| {
            const text = columnCell(col, &e, &cell_buf);
            if (ci == last) {
                try writer.writeAll(text);
            } else {
                try padWrite(writer, text, widths[ci]);
            }
        }
        try writer.writeByte('\n');
        if (opts.tree) try writeAncestors(writer, e.ancestors);
    }
}

pub fn writeJson(writer: anytype, entries: []const PortEntry, opts: Options) !void {
    try writer.writeByte('[');
    for (entries, 0..) |e, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("\n  {");
        try writer.print("\"port\":{d},\"pid\":{d},\"proto\":\"tcp\",\"process\":\"", .{ e.port, e.pid });
        try writeJsonEscaped(writer, e.name[0..e.name_len]);
        try writer.writeAll("\",\"address\":\"");
        try writeAddrStr(writer, &e);
        try writer.writeByte('"');
        // Opt-in fields only. Default JSON stays untouched for scripts.
        if (opts.verbose) {
            try writer.writeAll(",\"user\":\"");
            try writeJsonEscaped(writer, e.user orelse "");
            try writer.writeAll("\",\"command\":\"");
            try writeJsonEscaped(writer, e.command orelse "");
            try writer.writeByte('"');
        }
        if (opts.docker) {
            if (e.container) |c| {
                try writer.writeAll(",\"container\":{\"name\":\"");
                try writeJsonEscaped(writer, c.name);
                try writer.writeAll("\",\"image\":\"");
                try writeJsonEscaped(writer, c.image);
                try writer.print("\",\"container_port\":{d}}}", .{c.container_port});
            } else {
                try writer.writeAll(",\"container\":null");
            }
        }
        if (opts.tree) {
            try writer.writeAll(",\"ancestors\":[");
            if (e.ancestors) |ancestors| {
                for (ancestors, 0..) |anc, j| {
                    if (j > 0) try writer.writeByte(',');
                    try writer.print("{{\"pid\":{d},\"name\":\"", .{anc.pid});
                    try writeJsonEscaped(writer, anc.name);
                    try writer.writeAll("\"}");
                }
            }
            try writer.writeByte(']');
        }
        try writer.writeByte('}');
    }
    if (entries.len > 0) try writer.writeByte('\n');
    try writer.writeAll("]\n");
}

/// Print a listener's ancestry beneath its row, immediate parent first, each
/// level indented one step further (aligned under the PROCESS column).
fn writeAncestors(writer: anytype, ancestors: ?[]const Ancestor) !void {
    const list = ancestors orelse return;
    for (list, 0..) |anc, depth| {
        var indent: usize = 14 + depth * 2;
        while (indent > 0) : (indent -= 1) try writer.writeByte(' ');
        try writer.print("\u{2514}\u{2500} {s} ({d})\n", .{ anc.name, anc.pid });
    }
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
    var buf: [46]u8 = undefined;
    try writer.writeAll(formatAddr(&buf, e));
}

/// Render an address into `buf` and return the written slice. `buf` must be at
/// least 39 bytes (longest is a zero-padded IPv6 address). Single source of
/// truth for both rendering and column-width measurement.
fn formatAddr(buf: []u8, e: *const PortEntry) []const u8 {
    if (e.is_ipv6) {
        const b = &e.addr6;
        return std.fmt.bufPrint(buf, "{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}", .{
            b[0],  b[1],  b[2],  b[3],
            b[4],  b[5],  b[6],  b[7],
            b[8],  b[9],  b[10], b[11],
            b[12], b[13], b[14], b[15],
        }) catch unreachable; // buf is provably large enough (see doc comment)
    }
    const b = &e.addr4;
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch unreachable;
}
