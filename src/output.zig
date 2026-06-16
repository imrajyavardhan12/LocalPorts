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

/// Trailing tag appended to a row whose listener is reachable from the network
/// (bound to a non-loopback address). Local-only rows are left clean, so the
/// signal is quiet until there is something worth noticing.
const exposed_tag = "  ! network";

/// Display toggles for scan output. New display modes go here so call sites
/// stay self-documenting and the default contract is opt-in only.
pub const Options = struct {
    verbose: bool = false,
    tree: bool = false,
    docker: bool = false,
    // Whether the `--exposed` filter is active. Used only to tailor the
    // empty-state message ("nothing network-reachable" vs "nothing listening").
    exposed: bool = false,
};

/// The empty-scan message, tailored to whether the `--exposed` filter is on so
/// an empty audit reads as reassurance rather than "nothing is listening".
fn emptyMessage(opts: Options) []const u8 {
    return if (opts.exposed)
        "No network-reachable ports found.\n"
    else
        "No listening TCP ports found.\n";
}

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
        .address => formatAddrWithScope(buf, e),
        .user => e.user orelse "-",
        .command => e.command orelse "-",
        .container => formatContainer(buf, e.container),
    };
}

/// The ADDRESS cell for the table: the address, plus the `! network` tag when
/// the listener is reachable from the network. Folding the tag into the cell
/// (rather than appending it at the row's end) keeps it next to the address and
/// — since the cell is measured for column width — aligned across rows in every
/// display mode. JSON uses `formatAddr` directly, so it stays untagged.
fn formatAddrWithScope(buf: []u8, e: *const PortEntry) []const u8 {
    const addr = formatAddr(buf, e);
    if (types.scopeOf(e) != .network) return addr;
    @memcpy(buf[addr.len..][0..exposed_tag.len], exposed_tag);
    return buf[0 .. addr.len + exposed_tag.len];
}

fn formatContainer(buf: []u8, container: ?Container) []const u8 {
    const c = container orelse return "-";
    return std.fmt.bufPrint(buf, "{s} ({s} ->{d})", .{ c.name, c.image, c.container_port }) catch "-";
}

/// Assemble the visible column list for `opts` into `buf`, returning the
/// populated slice. PROCESS and ADDRESS are always present; USER/COMMAND come
/// with --verbose and CONTAINER with --docker. COMMAND stays last (it can be
/// long, so it is never padded); CONTAINER sits just before it. This is the
/// single source of truth for the column set, shared by `writeTable` and
/// `writeWatchTable` so the two never drift.
fn assembleColumns(opts: Options, buf: *[5]Column) []Column {
    var n: usize = 0;
    buf[n] = .process;
    n += 1;
    buf[n] = .address;
    n += 1;
    if (opts.verbose) {
        buf[n] = .user;
        n += 1;
    }
    if (opts.docker) {
        buf[n] = .container;
        n += 1;
    }
    if (opts.verbose) {
        buf[n] = .command;
        n += 1;
    }
    return buf[0..n];
}

pub fn writeTable(writer: anytype, entries: []const PortEntry, opts: Options) !void {
    if (entries.len == 0) {
        try writer.writeAll(emptyMessage(opts));
        return;
    }

    var cols: [5]Column = undefined;
    const columns = assembleColumns(opts, &cols);
    const last = columns.len - 1;

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

pub fn writeWatchTable(writer: anytype, entries: []const WatchEntry, opts: Options) !void {
    try writer.writeAll(ansi.clear_screen);

    if (entries.len == 0) {
        try writer.writeAll(emptyMessage(opts));
        return;
    }

    var cols: [5]Column = undefined;
    const columns = assembleColumns(opts, &cols);
    const last = columns.len - 1;

    // Compute padded widths for every column except the last.
    var cell_buf: [1024]u8 = undefined;
    var widths: [5]usize = .{0} ** 5;
    for (columns, 0..) |col, ci| {
        if (ci == last) break;
        var w: usize = columnHeader(col).len + 2;
        for (entries) |we| {
            const len = columnCell(col, &we.entry, &cell_buf).len;
            if (len + 2 > w) w = len + 2;
        }
        widths[ci] = w;
    }

    // Header row.
    try writer.print("PORT   PID    ", .{});
    for (columns, 0..) |col, ci| {
        if (ci == last) {
            try writer.writeAll(columnHeader(col));
        } else {
            try padWrite(writer, columnHeader(col), widths[ci]);
        }
    }
    try writer.writeByte('\n');

    // Rows with color coding.
    for (entries) |we| {
        const e = we.entry;
        const color = switch (we.state) {
            .new => ansi.green,
            .removed => ansi.red,
            .unchanged => "",
        };
        const reset_color = if (color.len > 0) ansi.reset else "";

        try writer.print("{s}{d:<6} {d:<6} ", .{ color, e.port, e.pid });
        for (columns, 0..) |col, ci| {
            const text = columnCell(col, &e, &cell_buf);
            if (ci == last) {
                try writer.writeAll(text);
            } else {
                try padWrite(writer, text, widths[ci]);
            }
        }
        try writer.writeAll(reset_color);
        try writer.writeByte('\n');
        if (opts.tree) try writeAncestors(writer, e.ancestors);
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
/// least 39 bytes (longest is a full eight-group IPv6 address). Single source of
/// truth for both rendering and column-width measurement.
fn formatAddr(buf: []u8, e: *const PortEntry) []const u8 {
    if (e.is_ipv6) return formatIpv6(buf, &e.addr6);
    const b = &e.addr4;
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ b[0], b[1], b[2], b[3] }) catch unreachable;
}

/// Render an IPv6 address into `buf` in RFC 5952 canonical form: lowercase hex,
/// leading zeros in each group suppressed, and the longest run of two or more
/// consecutive all-zero groups collapsed to "::" (the first such run on a tie).
/// IPv4-mapped addresses are not given the dotted-quad form (RFC 5952 4.3 is a
/// SHOULD); they render as plain hex, e.g. ::ffff:7f00:1. `buf` must be >= 39.
fn formatIpv6(buf: []u8, addr: *const [16]u8) []const u8 {
    var groups: [8]u16 = undefined;
    for (&groups, 0..) |*g, i| {
        g.* = (@as(u16, addr[i * 2]) << 8) | addr[i * 2 + 1];
    }

    // Longest run of consecutive zero groups; only runs of length >= 2 collapse.
    var run_start: usize = 0;
    var run_len: usize = 0;
    var i: usize = 0;
    while (i < 8) {
        if (groups[i] != 0) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < 8 and groups[i] == 0) : (i += 1) {}
        if (i - start > run_len) {
            run_len = i - start;
            run_start = start;
        }
    }
    if (run_len < 2) run_len = 0;

    var len: usize = 0;
    var g: usize = 0;
    var need_colon = false;
    while (g < 8) {
        if (run_len != 0 and g == run_start) {
            // The "::" supplies the separators on both sides, so any pending
            // colon is absorbed: "fe80" + "::" renders as "fe80::".
            buf[len] = ':';
            buf[len + 1] = ':';
            len += 2;
            g += run_len;
            need_colon = false;
            continue;
        }
        if (need_colon) {
            buf[len] = ':';
            len += 1;
        }
        len += (std.fmt.bufPrint(buf[len..], "{x}", .{groups[g]}) catch unreachable).len;
        need_colon = true;
        g += 1;
    }
    return buf[0..len];
}

test "formatIpv6 renders RFC 5952 canonical form" {
    var buf: [46]u8 = undefined;
    const cases = .{
        .{ [16]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, "::1" },
        .{ [16]u8{ 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, "2001:db8::1" },
        .{ [16]u8{ 0x20, 0x01, 0x0d, 0xb8, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6 }, "2001:db8:1:2:3:4:5:6" },
        .{ [16]u8{ 0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, "fe80::" },
        .{ [16]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, "::" },
        // A lone zero group is left as "0" (RFC 5952 4.2.2).
        .{ [16]u8{ 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1 }, "1:0:1:1:1:1:1:1" },
        // Tie on run length: the first run collapses, the second stays.
        .{ [16]u8{ 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1 }, "1::1:0:0:1:1" },
    };
    inline for (cases) |c| {
        const addr: [16]u8 = c[0];
        try std.testing.expectEqualStrings(c[1], formatIpv6(&buf, &addr));
    }
}
