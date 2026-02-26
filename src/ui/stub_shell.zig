const std = @import("std");
const app = @import("../app/mod.zig");
const headless_controller = @import("headless/controller.zig");
const SurfaceMode = @import("surfaces/mod.zig").SurfaceMode;
const PlacementPolicy = @import("placement/mod.zig").RuntimePolicy;

pub const Shell = struct {
    pub const RunOptions = struct {
        resident_mode: bool = false,
        start_hidden: bool = false,
        surface_mode: SurfaceMode = .auto,
        placement_policy: PlacementPolicy = .{},
        notifications_show_close_button: bool = true,
        notifications_show_dbus_actions: bool = true,
    };

    pub fn run(allocator: std.mem.Allocator, service: *app.SearchService, _: *app.TelemetrySink, options: RunOptions) !void {
        _ = options;
        try headless_controller.run(allocator, service);
    }
};
