const std = @import("std");

pub const Command = union(enum) {
    none,
    quit,
    refresh,
    icon_diag: bool,
};

pub fn parse(input: []const u8) Command {
    const query = std.mem.trim(u8, input, " \t\r\n");
    if (std.mem.eql(u8, query, ":q")) return .quit;
    if (std.mem.eql(u8, query, ":refresh")) return .refresh;
    if (std.mem.eql(u8, query, ":icondiag")) return .{ .icon_diag = false };
    if (std.mem.eql(u8, query, ":icondiag --json")) return .{ .icon_diag = true };
    return .none;
}
