const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_status = @import("status.zig");

const c = gtk_types.c;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;

pub fn request(ctx: *UiContext) void {
    if (ctx.deferred_dynamic_clear_id != 0) return;
    ctx.deferred_dynamic_clear_id = c.g_idle_add(onDeferredDynamicClear, ctx);
}

pub fn cancel(ctx: *UiContext) void {
    if (ctx.deferred_dynamic_clear_id != 0) {
        _ = c.g_source_remove(ctx.deferred_dynamic_clear_id);
        ctx.deferred_dynamic_clear_id = 0;
    }
    if (ctx.deferred_stats_refresh_id != 0) {
        _ = c.g_source_remove(ctx.deferred_stats_refresh_id);
        ctx.deferred_stats_refresh_id = 0;
    }
}

fn onDeferredDynamicClear(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.deferred_dynamic_clear_id = 0;
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    ctx.service.clearDynamicState(allocator);
    scheduleStatsRefresh(ctx);
    return GFALSE;
}

fn scheduleStatsRefresh(ctx: *UiContext) void {
    if (ctx.show_nerd_stats != gtk_types.GTRUE) return;
    if (ctx.deferred_stats_refresh_id != 0) {
        _ = c.g_source_remove(ctx.deferred_stats_refresh_id);
    }
    // Delay to let allocator/OS settle before sampling RSS in status stats.
    ctx.deferred_stats_refresh_id = c.g_timeout_add(1000, onDeferredStatsRefresh, ctx);
}

fn onDeferredStatsRefresh(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.deferred_stats_refresh_id = 0;
    gtk_status.refreshStatusForCurrentQuery(ctx);
    return GFALSE;
}
