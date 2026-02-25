const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_controller = @import("controller.zig");
const gtk_async_coord = @import("async_coordinator.zig");
const gtk_results_flow = @import("results_flow.zig");
const gtk_preview = @import("preview.zig");
const gtk_nav = @import("navigation.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;

pub fn afterActivate(ctx: *UiContext) void {
    gtk_controller.updateEntryRouteIcon(ctx, "");
    ctx.service.kickAsyncStartupPrewarm();
    gtk_controller.enableStartupKeyQueue(ctx);
    if (ctx.startup_key_queue_id != 0) {
        _ = c.g_source_remove(ctx.startup_key_queue_id);
        ctx.startup_key_queue_id = 0;
    }
    ctx.startup_key_queue_id = c.g_timeout_add(220, onStartupKeyQueueTimeout, ctx);
    if (ctx.focus_ready_logged == GFALSE) {
        ctx.focus_ready_logged = GTRUE;
        logStartupMetric(ctx, "startup.focus_ready_ms");
    }
    if (ctx.startup_idle_id != 0) {
        _ = c.g_source_remove(ctx.startup_idle_id);
        ctx.startup_idle_id = 0;
    }
    ctx.startup_idle_id = c.g_idle_add(onStartupReady, ctx);
}

fn onStartupReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.startup_idle_id = 0;
    populateResults(ctx, "");
    gtk_nav.updateScrollbarActiveClass(ctx);
    return GFALSE;
}

fn onStartupKeyQueueTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.startup_key_queue_id = 0;
    gtk_controller.flushAndDisableStartupKeyQueue(ctx);
    return GFALSE;
}

fn populateResults(ctx: *UiContext, query: []const u8) void {
    gtk_results_flow.populateResults(ctx, query, .{
        .start_async_route_search = startAsyncRouteSearch,
        .cancel_async_route_search = cancelAsyncRouteSearch,
    });
    gtk_preview.refreshFromSelection(ctx);
}

fn startAsyncRouteSearch(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
    gtk_async_coord.startAsyncRouteSearch(ctx, allocator, query_trimmed, onAsyncSearchReady);
}

fn cancelAsyncRouteSearch(ctx: *UiContext) void {
    gtk_async_coord.cancelAsyncRouteSearch(ctx);
}

fn onAsyncSearchReady(_: ?*anyopaque) callconv(.c) c.gboolean {
    // Startup path only schedules baseline rows; async completion is handled by the main shell flow.
    return GFALSE;
}

fn logStartupMetric(ctx: *UiContext, metric_name: []const u8) void {
    const now_ns = std.time.nanoTimestamp();
    const diff_ns = now_ns - ctx.launch_start_ns;
    const elapsed_ns: u64 = if (diff_ns <= 0) 0 else @as(u64, @intCast(diff_ns));
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    std.log.info("{s}={d:.2}", .{ metric_name, elapsed_ms });
}
