const std = @import("std");
const gtk_types = @import("types.zig");
const gdk_adapter = @import("gdk_adapter.zig");
const placement = @import("../placement/engine.zig");

const c = gtk_types.c;

pub fn configureLauncherWindow(window: *c.GtkWidget) void {
    const display = c.gtk_widget_get_display(window) orelse return;
    var adapter_ctx = gdk_adapter.GdkAdapter{ .display = display };
    const adapter = adapter_ctx.adapter();
    const allocator = std.heap.c_allocator;
    const outputs = adapter.listOutputs(allocator) catch return;
    defer adapter.freeOutputs(allocator, outputs);
    if (outputs.len == 0) return;

    const target = outputs[0];
    const width = @max(@as(i32, 680), @min(@as(i32, 1100), @divTrunc(target.width * 48, 100)));
    const height = @max(@as(i32, 420), @min(@as(i32, 760), @divTrunc(target.height * 56, 100)));
    const min_width = @max(@as(i32, 560), @divTrunc(target.width * 32, 100));
    const min_height = @max(@as(i32, 360), @divTrunc(target.height * 36, 100));

    const focus_hint = adapter.focusHint(allocator) catch null;
    const area = adapter.workArea(allocator, target.name) catch null;
    const geometry = placement.resolve(outputs, focus_hint, area, .{
        .anchor = .center,
        .width = width,
        .height = height,
        .margins = .{ .left = 12, .right = 12, .top = 12, .bottom = 12 },
        .monitor = .{ .policy = .primary },
    }) catch placement.Geometry{ .x = 0, .y = 0, .width = width, .height = height };

    c.gtk_window_set_default_size(@ptrCast(window), geometry.width, geometry.height);
    c.gtk_widget_set_size_request(window, min_width, min_height);
}

pub fn configureNotificationPopupWindow(window: *c.GtkWidget) void {
    const display = c.gtk_widget_get_display(window) orelse {
        c.gtk_window_set_default_size(@ptrCast(window), 380, 360);
        return;
    };
    var adapter_ctx = gdk_adapter.GdkAdapter{ .display = display };
    const adapter = adapter_ctx.adapter();
    const allocator = std.heap.c_allocator;
    const outputs = adapter.listOutputs(allocator) catch {
        c.gtk_window_set_default_size(@ptrCast(window), 380, 360);
        return;
    };
    defer adapter.freeOutputs(allocator, outputs);

    if (outputs.len == 0) {
        c.gtk_window_set_default_size(@ptrCast(window), 380, 360);
        return;
    }

    const target = outputs[0];
    const width = @max(@as(i32, 300), @min(@as(i32, 460), @divTrunc(target.width * 26, 100)));
    const height = @max(@as(i32, 280), @min(@as(i32, 620), @divTrunc(target.height * 46, 100)));
    const focus_hint = adapter.focusHint(allocator) catch null;
    const area = adapter.workArea(allocator, target.name) catch null;
    const geometry = placement.resolve(outputs, focus_hint, area, .{
        .anchor = .top_right,
        .width = width,
        .height = height,
        .margins = .{ .top = 24, .right = 24, .bottom = 24, .left = 24 },
        .monitor = .{ .policy = .primary },
    }) catch placement.Geometry{ .x = 0, .y = 0, .width = width, .height = height };

    c.gtk_window_set_default_size(@ptrCast(window), geometry.width, geometry.height);
}
