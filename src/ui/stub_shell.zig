const std = @import("std");

pub const Shell = struct {
    pub fn run() !void {
        std.debug.print("[ui] GTK shell is disabled. Rebuild with -Denable_gtk=true\n", .{});
    }
};
