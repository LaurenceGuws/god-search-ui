const std = @import("std");
const gtk_types = @import("types.zig");
const gdk_adapter = @import("gdk_adapter.zig");
const placement = @import("../placement/engine.zig");
const placement_policy = @import("../placement/mod.zig");

const c = gtk_types.c;

pub fn configureLauncherWindow(window: *c.GtkWidget, policy: placement_policy.LauncherPolicy) void {
    const display = c.gtk_widget_get_display(window) orelse return;
    var adapter_ctx = gdk_adapter.GdkAdapter{ .display = display };
    const adapter = adapter_ctx.adapter();
    const allocator = std.heap.c_allocator;
    const outputs = adapter.listOutputs(allocator) catch return;
    defer adapter.freeOutputs(allocator, outputs);
    if (outputs.len == 0) return;

    const target = outputs[0];
    const width = @max(policy.min_width_px, @min(policy.max_width_px, scaledPercent(target.width, policy.width_percent)));
    const height = @max(policy.min_height_px, @min(policy.max_height_px, scaledPercent(target.height, policy.height_percent)));
    const min_width = @max(policy.min_width_px, scaledPercent(target.width, policy.min_width_percent));
    const min_height = @max(policy.min_height_px, scaledPercent(target.height, policy.min_height_percent));

    const focus_hint = adapter.focusHint(allocator) catch null;
    const area = adapter.workArea(allocator, target.name) catch null;
    const geometry = placement.resolve(outputs, focus_hint, area, .{
        .anchor = policy.window.anchor,
        .width = width,
        .height = height,
        .margins = policy.window.margins,
        .monitor = policy.window.monitor,
    }) catch placement.Geometry{ .x = 0, .y = 0, .width = width, .height = height };

    c.gtk_window_set_default_size(@ptrCast(window), geometry.width, geometry.height);
    c.gtk_widget_set_size_request(window, min_width, min_height);
}

pub fn configureNotificationPopupWindow(window: *c.GtkWidget, policy: placement_policy.NotificationPolicy) void {
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
    const width = @max(policy.min_width_px, @min(policy.max_width_px, scaledPercent(target.width, policy.width_percent)));
    const height = @max(policy.min_height_px, @min(policy.max_height_px, scaledPercent(target.height, policy.height_percent)));
    const focus_hint = adapter.focusHint(allocator) catch null;
    const area = adapter.workArea(allocator, target.name) catch null;
    const geometry = placement.resolve(outputs, focus_hint, area, .{
        .anchor = policy.window.anchor,
        .width = width,
        .height = height,
        .margins = policy.window.margins,
        .monitor = policy.window.monitor,
    }) catch placement.Geometry{ .x = 0, .y = 0, .width = width, .height = height };

    c.gtk_window_set_default_size(@ptrCast(window), geometry.width, geometry.height);
}

fn scaledPercent(value: i32, pct: i32) i32 {
    const clamped = std.math.clamp(pct, 1, 100);
    return @divTrunc(value * clamped, 100);
}
