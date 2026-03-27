 pub const PortEntry = struct {
     port: u16,
     pid: u32,
     name: [256]u8,
     name_len: usize,
     addr4: [4]u8,
     addr6: [16]u8,
     is_ipv6: bool,
 };
