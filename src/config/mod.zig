const build_options = @import("build_options");
const std = @import("std");

pub const Settings = struct {
    surface_mode: ?@import("../ui/surfaces/mod.zig").SurfaceMode = null,
    placement_policy: @import("../ui/placement/mod.zig").RuntimePolicy = .{},
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

const impl = if (build_options.enable_lua_config)
    @import("lua_config.zig")
else
    struct {
        pub fn load(allocator: @import("std").mem.Allocator) Settings {
            _ = @import("default_lua.zig").ensureDefaultConfig(allocator) catch false;
            return .{};
        }
    };

pub fn load(allocator: std.mem.Allocator) Settings {
    return impl.load(allocator);
}
