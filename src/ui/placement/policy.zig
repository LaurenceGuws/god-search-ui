const wm_adapter = @import("../../wm/adapter.zig");
const engine = @import("engine.zig");

pub const WindowPolicy = struct {
    anchor: engine.Anchor,
    margins: engine.Margins,
    monitor: wm_adapter.MonitorTarget,
};

pub const LauncherPolicy = struct {
    window: WindowPolicy = .{
        .anchor = .center,
        .margins = .{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .monitor = .{ .policy = .primary },
    },
    width_percent: i32 = 48,
    height_percent: i32 = 56,
    min_width_percent: i32 = 32,
    min_height_percent: i32 = 36,
    max_width_px: i32 = 1100,
    max_height_px: i32 = 760,
    min_width_px: i32 = 560,
    min_height_px: i32 = 360,
};

pub const NotificationPolicy = struct {
    window: WindowPolicy = .{
        .anchor = .top_right,
        .margins = .{ .left = 24, .right = 24, .top = 24, .bottom = 24 },
        .monitor = .{ .policy = .primary },
    },
    width_percent: i32 = 26,
    height_percent: i32 = 46,
    min_width_px: i32 = 300,
    min_height_px: i32 = 280,
    max_width_px: i32 = 460,
    max_height_px: i32 = 620,
};

pub const RuntimePolicy = struct {
    launcher: LauncherPolicy = .{},
    notifications: NotificationPolicy = .{},
};
