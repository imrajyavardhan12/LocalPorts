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
 const PROX_FDTYPE_SOCKET: u32 = 2;
 const PROC_PIDFDSOCKETINFO: c_int = 3;
 const SOCKINFO_TCP: i32 = 2;
 const TSI_S_LISTEN: i32 = 1;
 const INI_IPV4: u8 = 0x1;
 const INI_IPV6: u8 = 0x2;
 
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
 }
 
 // ── Scanner ───────────────────────────────────────────────────────────────
 
 pub fn scan(allocator: std.mem.Allocator, filter_port: ?u16) ![]PortEntry {
     var pid_buf: [4096]i32 = undefined;
     const n_raw = proc_listallpids(@ptrCast(&pid_buf), @intCast(@sizeOf(@TypeOf(pid_buf))));
     if (n_raw <= 0) return error.ProcListPidsFailed;
     const n_pids: usize = @intCast(n_raw);
 
     var entries: std.ArrayList(PortEntry) = .empty;
     errdefer entries.deinit(allocator);
 
     var fd_buf: [2048]ProcFdInfo = undefined;
     var sfi: SocketFdInfo = undefined;
 
     for (pid_buf[0..n_pids]) |pid| {
         if (pid <= 0) continue;
 
         // Get file descriptors for this PID.
         const fd_bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, @ptrCast(&fd_buf), @intCast(@sizeOf(@TypeOf(fd_buf))));
         if (fd_bytes <= 0) continue;
         const n_fds: usize = @intCast(@divTrunc(fd_bytes, @sizeOf(ProcFdInfo)));
 
         for (fd_buf[0..n_fds]) |fdi| {
             if (fdi.proc_fdtype != PROX_FDTYPE_SOCKET) continue;
 
             const r = proc_pidfdinfo(pid, fdi.proc_fd, PROC_PIDFDSOCKETINFO, @ptrCast(&sfi), @intCast(@sizeOf(SocketFdInfo)));
             if (r < @sizeOf(SocketFdInfo)) continue;
 
             const si = &sfi.psi;
             if (si.soi_kind != SOCKINFO_TCP) continue;
 
             const tcp = &si.soi_proto.pri_tcp;
             if (tcp.tcpsi_state != TSI_S_LISTEN) continue;
 
             // Convert port from network byte order.
             const lport_bytes = std.mem.asBytes(&tcp.tcpsi_ini.insi_lport);
             const port = std.mem.readInt(u16, lport_bytes[0..2], .big);
             if (port == 0) continue;
 
             if (filter_port) |fp| {
                 if (port != fp) continue;
             }
 
             // Deduplicate on (pid, port) to avoid IPv4+IPv6 double-listing.
             const pid_u32: u32 = @intCast(pid);
             var dup = false;
             for (entries.items) |existing| {
                 if (existing.pid == pid_u32 and existing.port == port) {
                     dup = true;
                     break;
                 }
             }
             if (dup) continue;
 
             var entry = PortEntry{
                 .port = port,
                 .pid = pid_u32,
                 .name = undefined,
                 .name_len = 0,
                 .addr4 = .{0, 0, 0, 0},
                 .addr6 = .{0} ** 16,
                 .is_ipv6 = false,
             };
 
             // Resolve process name.
             const nlen = proc_name(pid, @ptrCast(&entry.name), @sizeOf(@TypeOf(entry.name)));
             entry.name_len = if (nlen > 0) @intCast(nlen) else 0;
             if (nlen <= 0) {
                 entry.name[0] = '?';
                 entry.name_len = 1;
             }
 
             // Store address.
             const ini = &tcp.tcpsi_ini;
             if (ini.insi_vflag & INI_IPV4 != 0) {
                 const a = std.mem.asBytes(&ini.insi_laddr.in46.addr4);
                 @memcpy(&entry.addr4, a);
             } else if (ini.insi_vflag & INI_IPV6 != 0) {
                 const a = std.mem.asBytes(&ini.insi_laddr.in6.words);
                 @memcpy(&entry.addr6, a);
                 entry.is_ipv6 = true;
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
