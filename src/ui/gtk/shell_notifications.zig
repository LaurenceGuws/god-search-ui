const std = @import("std");
const notifications = @import("../../notifications/mod.zig");

pub fn maybeStart(allocator: std.mem.Allocator, resident_mode: bool) !?*notifications.Daemon {
    if (!resident_mode) return null;

    const daemon = try allocator.create(notifications.Daemon);
    errdefer allocator.destroy(daemon);
    daemon.* = try notifications.Daemon.init(allocator);
    errdefer daemon.deinit();
    try daemon.start();
    return daemon;
}
