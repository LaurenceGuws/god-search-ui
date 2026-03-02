const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_bootstrap = @import("bootstrap.zig");
const gtk_async = @import("async_state.zig");
const gtk_async_coord = @import("async_coordinator.zig");
const gtk_controller = @import("controller.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;
const LaunchContext = gtk_bootstrap.LaunchContext;

pub fn onCloseRequest(_: ?*c.GtkWindow, user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.resident_mode == GTRUE) {
        c.gtk_editable_set_text(@ptrCast(ctx.entry), "");
        c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
        c.gtk_widget_set_visible(ctx.window, GFALSE);
        return GTRUE;
    }
    return GFALSE;
}

pub fn onDestroy(_: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null) return;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    const launch: *LaunchContext = @ptrCast(@alignCast(ctx.launch_ctx));
    if (launch.ctx == ctx) {
        launch.ctx = null;
    }
    disconnectSignalsByData(@ptrCast(ctx.window), ctx);
    if (ctx.search_debounce_id != 0) {
        _ = c.g_source_remove(ctx.search_debounce_id);
        ctx.search_debounce_id = 0;
    }
    if (ctx.status_reset_id != 0) {
        _ = c.g_source_remove(ctx.status_reset_id);
        ctx.status_reset_id = 0;
    }
    if (ctx.async_spinner_id != 0) {
        _ = c.g_source_remove(ctx.async_spinner_id);
        ctx.async_spinner_id = 0;
    }
    if (ctx.startup_idle_id != 0) {
        _ = c.g_source_remove(ctx.startup_idle_id);
        ctx.startup_idle_id = 0;
    }
    if (ctx.startup_key_queue_id != 0) {
        _ = c.g_source_remove(ctx.startup_key_queue_id);
        ctx.startup_key_queue_id = 0;
    }
    gtk_controller.disableStartupKeyQueue(ctx);
    gtk_async_coord.beginAsyncShutdown(ctx);
    const ready_id = gtk_async_coord.takeAsyncReadySourceId(ctx);
    if (ready_id != 0) {
        _ = c.g_source_remove(ready_id);
    }
    ctx.async_worker_active = GFALSE;
    gtk_async.freePendingAsyncQuery(ctx);
    c.g_mutex_clear(&ctx.async_worker_lock);
    c.g_cond_clear(&ctx.async_worker_cond);
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    allocator.destroy(allocator_ptr);
    c.g_free(ctx);
}

fn disconnectSignalsByData(instance: *anyopaque, data: *anyopaque) void {
    _ = c.g_signal_handlers_disconnect_matched(
        instance,
        c.G_SIGNAL_MATCH_DATA,
        0,
        0,
        null,
        null,
        data,
    );
}
