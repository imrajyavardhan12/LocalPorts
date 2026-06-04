const std = @import("std");
const types = @import("types.zig");
const PortEntry = types.PortEntry;

// ── libproc extern declarations ────────────────────────────────────────────
extern "c" fn proc_listallpids(buffer: ?*anyopaque, buffersize: c_int) c_int;
extern "c" fn proc_pidinfo(pid: c_int, flavor: c_int, arg: u64, buffer: ?*anyopaque, buffersize: c_int) c_int;
extern "c" fn proc_pidfdinfo(pid: c_int, fd: c_int, flavor: c_int, buffer: ?*anyopaque, buffersize: c_int) c_int;
extern "c" fn proc_name(pid: c_int, buffer: ?*anyopaque, buffersize: u32) c_int;

// ── Constants from sys/proc_info.h ────────────────────────────────────────
const PROC_PIDLISTFDS: c_int = 1;
const PROC_PIDTBSDINFO: c_int = 3;
const PROX_FDTYPE_SOCKET: u32 = 2;
const PROC_PIDFDSOCKETINFO: c_int = 3;
const SOCKINFO_TCP: i32 = 2;
const TSI_S_LISTEN: i32 = 1;
const INI_IPV4: u8 = 0x1;
const INI_IPV6: u8 = 0x2;
const SZOMB: u32 = 5;

// ── C struct definitions matching sys/proc_info.h layout ─────────────────
const ProcFdInfo = extern struct {
    proc_fd: i32,
    proc_fdtype: u32,
};

const ProcFileInfo = extern struct {
    fi_openflags: u32,
    fi_status: u32,
    fi_offset: i64,
    fi_type: i32,
    fi_guardflags: u32,
};

const ProcBsdInfo = extern struct {
    pbi_flags: u32,
    pbi_status: u32,
    pbi_xstatus: u32,
    pbi_pid: u32,
    pbi_ppid: u32,
    pbi_uid: u32,
    pbi_gid: u32,
    pbi_ruid: u32,
    pbi_rgid: u32,
    pbi_svuid: u32,
    pbi_svgid: u32,
    rfu_1: u32,
    pbi_comm: [16]u8,
    pbi_name: [32]u8,
    pbi_nfiles: u32,
    pbi_pgid: u32,
    pbi_pjobc: u32,
    e_tdev: u32,
    e_tpgid: u32,
    pbi_nice: i32,
    pbi_start_tvsec: u64,
    pbi_start_tvusec: u64,
};

// in4in6_addr: 3 padding words + IPv4 address word = 16 bytes
const In4In6Addr = extern struct {
    pad: [3]u32,
    addr4: u32,
};

// in6_addr: 4 x u32 = 16 bytes, alignment 4
const In6Addr = extern struct {
    words: [4]u32,
};

const InAddr = extern union {
    in46: In4In6Addr,
    in6: In6Addr,
};

// insi_v4: 1-byte inner struct
const InV4Info = extern struct { in4_tos: u8 };

// insi_v6: uint8 + [3 pad] + int + u_short + short = 12 bytes (C-padded)
const InV6Info = extern struct {
    in6_hlim: u8,
    in6_cksum: i32, // C ABI: 3 bytes padding inserted before this
    in6_ifindex: u16,
    in6_hops: i16,
};

// in_sockinfo: 80 bytes
const InSockInfo = extern struct {
    insi_fport: i32,
    insi_lport: i32,
    insi_gencnt: u64,
    insi_flags: u32,
    insi_flow: u32,
    insi_vflag: u8,
    insi_ip_ttl: u8,
    rfu_1: u32, // C ABI: 2 bytes padding inserted before this
    insi_faddr: InAddr,
    insi_laddr: InAddr,
    insi_v4: InV4Info,
    insi_v6: InV6Info, // C ABI: 3 bytes padding inserted before this
};

// tcp_sockinfo: 120 bytes
const TcpSockInfo = extern struct {
    tcpsi_ini: InSockInfo,
    tcpsi_state: i32,
    tcpsi_timer: [4]i32,
    tcpsi_mss: i32,
    tcpsi_flags: u32,
    rfu_1: u32,
    tcpsi_tp: u64,
};

// Union of all socket protocol infos. un_sockinfo dominates at 528 bytes.
const SoiProto = extern union {
    pri_tcp: TcpSockInfo,
    _size: [528]u8, // ensures the union is exactly 528 bytes
};

// socket_info: 768 bytes
// Uses opaque u64 arrays for fields we don't access.
const SocketInfo = extern struct {
    _stat: [17]u64, // vinfo_stat, 136 bytes
    soi_so: u64,
    soi_pcb: u64,
    soi_type: i32,
    soi_protocol: i32,
    soi_family: i32,
    soi_options: i16,
    soi_linger: i16,
    soi_state: i16,
    soi_qlen: i16,
    soi_incqlen: i16,
    soi_qlimit: i16,
    soi_timeo: i16,
    soi_error: u16,
    soi_oobmark: u32,
    _rcv: [3]u64, // sockbuf_info rcv, 24 bytes
    _snd: [3]u64, // sockbuf_info snd, 24 bytes
    soi_kind: i32,
    _rfu_1: u32,
    soi_proto: SoiProto,
};

// socket_fdinfo: 792 bytes
const SocketFdInfo = extern struct {
    pfi: ProcFileInfo,
    psi: SocketInfo,
};

// ── Compile-time size assertions (catch layout bugs immediately) ──────────
comptime {
    if (@sizeOf(InSockInfo) != 80)
        @compileError("InSockInfo size mismatch: expected 80");
    if (@sizeOf(TcpSockInfo) != 120)
        @compileError("TcpSockInfo size mismatch: expected 120");
    if (@sizeOf(SocketInfo) != 768)
        @compileError("SocketInfo size mismatch: expected 768");
    if (@sizeOf(SocketFdInfo) != 792)
        @compileError("SocketFdInfo size mismatch: expected 792");
    if (@sizeOf(ProcBsdInfo) != 136)
        @compileError("ProcBsdInfo size mismatch: expected 136");
}

// ── Process status ────────────────────────────────────────────────────────

pub fn processIsRunning(pid: u32) bool {
    var info: ProcBsdInfo = undefined;
    const r = proc_pidinfo(@intCast(pid), PROC_PIDTBSDINFO, 0, @ptrCast(&info), @intCast(@sizeOf(ProcBsdInfo)));
    if (r < @as(c_int, @intCast(@sizeOf(ProcBsdInfo)))) return false;
    return info.pbi_status != SZOMB;
}

// ── Listening-socket decode (pure, unit-tested) ──────────────────────────

const DecodedListen = struct {
    port: u16,
    is_ipv6: bool,
    addr4: [4]u8,
    addr6: [16]u8,
};

/// Decode a `socket_fdinfo` into a listening-TCP descriptor, or null if the
/// socket is not TCP, not in the LISTEN state, or bound to port 0.
///
/// Pure: performs no syscalls and no allocation, so it is unit-tested against
/// synthetic `SocketFdInfo` values. PID and process name are resolved
/// separately by `scan`, since they are not part of the socket info.
fn decodeListenSocket(sfi: *const SocketFdInfo) ?DecodedListen {
    const si = &sfi.psi;
    if (si.soi_kind != SOCKINFO_TCP) return null;

    const tcp = &si.soi_proto.pri_tcp;
    if (tcp.tcpsi_state != TSI_S_LISTEN) return null;

    const ini = &tcp.tcpsi_ini;

    // Local port is stored in network byte order.
    const lport_bytes = std.mem.asBytes(&ini.insi_lport);
    const port = std.mem.readInt(u16, lport_bytes[0..2], .big);
    if (port == 0) return null;

    var decoded = DecodedListen{
        .port = port,
        .is_ipv6 = false,
        .addr4 = .{ 0, 0, 0, 0 },
        .addr6 = .{0} ** 16,
    };

    if (ini.insi_vflag & INI_IPV4 != 0) {
        @memcpy(&decoded.addr4, std.mem.asBytes(&ini.insi_laddr.in46.addr4));
    } else if (ini.insi_vflag & INI_IPV6 != 0) {
        @memcpy(&decoded.addr6, std.mem.asBytes(&ini.insi_laddr.in6.words));
        decoded.is_ipv6 = true;
    }

    return decoded;
}

// ── Scanner ───────────────────────────────────────────────────────────────

// Headroom added to each libproc size query: a process (or a process's set of
// file descriptors) can appear between the size query and the fill, so we
// over-allocate slightly to avoid re-truncating in that window.
const pid_query_headroom = 64;
const fd_query_headroom = 32;
// Initial FD buffer size, grown on demand for processes with more descriptors.
const fd_initial_capacity = 256;

pub fn scan(allocator: std.mem.Allocator, filter_port: ?u16) ![]PortEntry {
    // Size the PID buffer dynamically. proc_listallpids(null, 0) reports how
    // many PIDs currently exist; we add headroom because processes can spawn
    // between this query and the fill below. A fixed buffer would silently
    // truncate on busy systems and make listeners vanish from the scan.
    const pid_hint = proc_listallpids(null, 0);
    if (pid_hint <= 0) return error.ProcListPidsFailed;
    const pid_capacity: usize = @as(usize, @intCast(pid_hint)) + pid_query_headroom;

    const pid_buf = try allocator.alloc(i32, pid_capacity);
    defer allocator.free(pid_buf);

    const pid_filled = proc_listallpids(@ptrCast(pid_buf.ptr), @intCast(pid_capacity * @sizeOf(i32)));
    if (pid_filled <= 0) return error.ProcListPidsFailed;
    const n_pids: usize = @min(@as(usize, @intCast(pid_filled)), pid_capacity);

    var entries: std.ArrayList(PortEntry) = .empty;
    errdefer entries.deinit(allocator);

    // Reusable FD buffer, grown on demand so a process with many descriptors
    // (databases, proxies, language servers) is never truncated.
    var fd_buf = try allocator.alloc(ProcFdInfo, fd_initial_capacity);
    defer allocator.free(fd_buf);

    var sfi: SocketFdInfo = undefined;

    for (pid_buf[0..n_pids]) |pid| {
        if (pid <= 0) continue;

        // Size this PID's FD list, growing the shared buffer if needed.
        const fd_needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, null, 0);
        if (fd_needed <= 0) continue;
        const fd_needed_count: usize = @intCast(@divTrunc(fd_needed, @sizeOf(ProcFdInfo)));
        if (fd_needed_count + fd_query_headroom > fd_buf.len) {
            fd_buf = try allocator.realloc(fd_buf, fd_needed_count + fd_query_headroom);
        }

        const fd_bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, @ptrCast(fd_buf.ptr), @intCast(fd_buf.len * @sizeOf(ProcFdInfo)));
        if (fd_bytes <= 0) continue;
        const n_fds: usize = @min(@as(usize, @intCast(@divTrunc(fd_bytes, @sizeOf(ProcFdInfo)))), fd_buf.len);

        for (fd_buf[0..n_fds]) |fdi| {
            if (fdi.proc_fdtype != PROX_FDTYPE_SOCKET) continue;

            const r = proc_pidfdinfo(pid, fdi.proc_fd, PROC_PIDFDSOCKETINFO, @ptrCast(&sfi), @intCast(@sizeOf(SocketFdInfo)));
            if (r < @sizeOf(SocketFdInfo)) continue;

            const decoded = decodeListenSocket(&sfi) orelse continue;

            if (filter_port) |fp| {
                if (decoded.port != fp) continue;
            }

            // Deduplicate on (pid, port) to avoid IPv4+IPv6 double-listing.
            const pid_u32: u32 = @intCast(pid);
            var dup = false;
            for (entries.items) |existing| {
                if (existing.pid == pid_u32 and existing.port == decoded.port) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;

            var entry = PortEntry{
                .port = decoded.port,
                .pid = pid_u32,
                .name = undefined,
                .name_len = 0,
                .addr4 = decoded.addr4,
                .addr6 = decoded.addr6,
                .is_ipv6 = decoded.is_ipv6,
            };

            // Resolve process name.
            const nlen = proc_name(pid, @ptrCast(&entry.name), @sizeOf(@TypeOf(entry.name)));
            entry.name_len = if (nlen > 0) @intCast(nlen) else 0;
            if (nlen <= 0) {
                entry.name[0] = '?';
                entry.name_len = 1;
            }

            try entries.append(allocator, entry);
        }
    }

    // Sort by port, then PID.
    std.mem.sort(PortEntry, entries.items, {}, struct {
        fn lt(_: void, a: PortEntry, b: PortEntry) bool {
            if (a.port != b.port) return a.port < b.port;
            return a.pid < b.pid;
        }
    }.lt);

    return try entries.toOwnedSlice(allocator);
}

// ── Tests ─────────────────────────────────────────────────────────────────

fn makeSocketFdInfo(kind: i32, state: i32, vflag: u8, port: u16) SocketFdInfo {
    var sfi = std.mem.zeroes(SocketFdInfo);
    sfi.psi.soi_kind = kind;
    const tcp = &sfi.psi.soi_proto.pri_tcp;
    tcp.tcpsi_state = state;
    tcp.tcpsi_ini.insi_vflag = vflag;
    const lport_bytes = std.mem.asBytes(&tcp.tcpsi_ini.insi_lport);
    std.mem.writeInt(u16, lport_bytes[0..2], port, .big);
    return sfi;
}

test "decodeListenSocket accepts a listening IPv4 TCP socket" {
    var sfi = makeSocketFdInfo(SOCKINFO_TCP, TSI_S_LISTEN, INI_IPV4, 3000);
    @memcpy(
        std.mem.asBytes(&sfi.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.in46.addr4),
        &[_]u8{ 127, 0, 0, 1 },
    );

    const decoded = decodeListenSocket(&sfi) orelse return error.ExpectedDecode;
    try std.testing.expectEqual(@as(u16, 3000), decoded.port);
    try std.testing.expect(!decoded.is_ipv6);
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, decoded.addr4);
}

test "decodeListenSocket accepts a listening IPv6 TCP socket" {
    var sfi = makeSocketFdInfo(SOCKINFO_TCP, TSI_S_LISTEN, INI_IPV6, 8080);
    const addr = [_]u8{
        0x20, 0x01, 0x0d, 0xb8,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01,
    };
    @memcpy(
        std.mem.asBytes(&sfi.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.in6.words),
        &addr,
    );

    const decoded = decodeListenSocket(&sfi) orelse return error.ExpectedDecode;
    try std.testing.expectEqual(@as(u16, 8080), decoded.port);
    try std.testing.expect(decoded.is_ipv6);
    try std.testing.expectEqual(addr, decoded.addr6);
}

test "decodeListenSocket rejects non-TCP, non-listening, and port-zero sockets" {
    const not_tcp = makeSocketFdInfo(SOCKINFO_TCP + 1, TSI_S_LISTEN, INI_IPV4, 3000);
    try std.testing.expectEqual(@as(?DecodedListen, null), decodeListenSocket(&not_tcp));

    const not_listening = makeSocketFdInfo(SOCKINFO_TCP, TSI_S_LISTEN + 1, INI_IPV4, 3000);
    try std.testing.expectEqual(@as(?DecodedListen, null), decodeListenSocket(&not_listening));

    const port_zero = makeSocketFdInfo(SOCKINFO_TCP, TSI_S_LISTEN, INI_IPV4, 0);
    try std.testing.expectEqual(@as(?DecodedListen, null), decodeListenSocket(&port_zero));
}
