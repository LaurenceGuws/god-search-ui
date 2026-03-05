const std = @import("std");
const placement = @import("../placement/mod.zig");

pub const SurfaceState = enum {
    hidden,
    visible,
};

pub const SurfaceMode = enum {
    toplevel,
    layer_shell,

    pub fn parse(raw: []const u8) ?SurfaceMode {
        if (std.ascii.eqlIgnoreCase(raw, "toplevel")) return .toplevel;
        if (std.ascii.eqlIgnoreCase(raw, "layer-shell")) return .layer_shell;
        if (std.ascii.eqlIgnoreCase(raw, "layer_shell")) return .layer_shell;
        return null;
    }
};

pub const Surface = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        apply_geometry: *const fn (context: *anyopaque, geometry: placement.Geometry) void,
        show: *const fn (context: *anyopaque) void,
        hide: *const fn (context: *anyopaque) void,
        state: *const fn (context: *anyopaque) SurfaceState,
    };

    pub fn applyGeometry(self: Surface, geometry: placement.Geometry) void {
        self.vtable.apply_geometry(self.context, geometry);
    }

    pub fn show(self: Surface) void {
        self.vtable.show(self.context);
    }

    pub fn hide(self: Surface) void {
        self.vtable.hide(self.context);
    }

    pub fn state(self: Surface) SurfaceState {
        return self.vtable.state(self.context);
    }
};

pub const LauncherSurface = Surface;
pub const NotificationSurface = Surface;

pub const SurfaceCollection = struct {
    launcher: LauncherSurface,
    notifications: NotificationSurface,
};

test "surface wrapper delegates calls" {
    const Fake = struct {
        var st: SurfaceState = .hidden;
        var last_w: i32 = 0;

        fn apply(context: *anyopaque, geometry: placement.Geometry) void {
            _ = context;
            last_w = geometry.width;
        }
        fn show(context: *anyopaque) void {
            _ = context;
            st = .visible;
        }
        fn hide(context: *anyopaque) void {
            _ = context;
            st = .hidden;
        }
        fn stateFn(context: *anyopaque) SurfaceState {
            _ = context;
            return st;
        }
    };

    var marker: u8 = 0;
    const surface = Surface{
        .name = "fake",
        .context = &marker,
        .vtable = &.{
            .apply_geometry = Fake.apply,
            .show = Fake.show,
            .hide = Fake.hide,
            .state = Fake.stateFn,
        },
    };

    surface.applyGeometry(.{ .x = 0, .y = 0, .width = 640, .height = 480 });
    try std.testing.expectEqual(@as(i32, 640), Fake.last_w);
    surface.show();
    try std.testing.expectEqual(SurfaceState.visible, surface.state());
    surface.hide();
    try std.testing.expectEqual(SurfaceState.hidden, surface.state());
}
