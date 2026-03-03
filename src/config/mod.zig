const std = @import("std");

pub const Settings = struct {
    pub const NotificationActionsPolicy = struct {
        show_close_button: bool = true,
        show_dbus_actions: bool = true,
    };

    surface_mode: ?@import("../ui/surfaces/mod.zig").SurfaceMode = null,
    placement_policy: @import("../ui/placement/mod.zig").RuntimePolicy = .{},
    notification_actions: NotificationActionsPolicy = .{},
    launcher_monitor_name: ?[]u8 = null,
    notifications_monitor_name: ?[]u8 = null,

    pub fn applyPlacementOverrides(self: *Settings) void {
        if (self.launcher_monitor_name) |name| {
            self.placement_policy.launcher.window.monitor = .{
                .policy = .by_name,
                .output_name = name,
            };
        }
        if (self.notifications_monitor_name) |name| {
            self.placement_policy.notifications.window.monitor = .{
                .policy = .by_name,
                .output_name = name,
            };
        }
    }

    pub fn deinit(self: *Settings, allocator: std.mem.Allocator) void {
        if (self.launcher_monitor_name) |name| allocator.free(name);
        if (self.notifications_monitor_name) |name| allocator.free(name);
        self.* = .{};
    }
};

const impl = @import("lua_config.zig");

pub fn load(allocator: std.mem.Allocator) Settings {
    return impl.load(allocator);
}
