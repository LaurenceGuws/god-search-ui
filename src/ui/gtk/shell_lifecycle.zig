const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_bootstrap = @import("bootstrap.zig");
const gtk_async = @import("async_state.zig");
const gtk_async_coord = @import("async_coordinator.zig");
const gtk_controller = @import("controller.zig");
const gtk_deferred_clear = @import("deferred_clear.zig");
const gtk_preview = @import("preview.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;
const LaunchContext = gtk_bootstrap.LaunchContext;

pub fn onCloseRequest(_: ?*c.GtkWindow, user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.resident_mode == GTRUE) {
        captureListState(ctx);
        std.log.info(
            "ram_event=ui_close_request query_hash={d} window_limit={d} clear_query_on_close={}",
            .{
                ctx.result_query_hash,
                ctx.result_window_limit,
                ctx.clear_query_on_close == GTRUE,
            },
        );
        gtk_deferred_clear.request(ctx);
        gtk_preview.cancelPendingWork(ctx);
        if (ctx.clear_query_on_close == GTRUE) {
            const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
            const allocator = allocator_ptr.*;
            c.gtk_editable_set_text(@ptrCast(ctx.entry), "");
            c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
            ctx.last_selected_row_index = -1;
            ctx.last_scroll_position = 0;
            if (ctx.last_query_text) |query_ptr| {
                allocator.free(query_ptr[0..ctx.last_query_len]);
                ctx.last_query_text = null;
                ctx.last_query_len = 0;
            }
            ctx.clear_query_on_close = GFALSE;
        }
        c.gtk_widget_set_visible(ctx.window, GFALSE);
        return GTRUE;
    }
    return GFALSE;
}

pub fn onWindowActiveNotify(window: ?*c.GtkWindow, _: ?*c.GParamSpec, user_data: ?*anyopaque) callconv(.c) void {
    if (window == null or user_data == null) return;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.resident_mode != GTRUE) return;
    if (c.gtk_widget_get_visible(ctx.window) != GTRUE) return;
    if (c.gtk_window_is_active(window) == GTRUE) return;

    captureListState(ctx);
    std.log.info(
        "ram_event=ui_focus_lost_hide query_hash={d} window_limit={d}",
        .{ ctx.result_query_hash, ctx.result_window_limit },
    );
    gtk_deferred_clear.request(ctx);
    gtk_preview.cancelPendingWork(ctx);
    c.gtk_widget_set_visible(ctx.window, GFALSE);
}

pub fn captureListState(ctx: *UiContext) void {
    const selected = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list));
    ctx.last_selected_row_index = if (selected != null) c.gtk_list_box_row_get_index(selected) else -1;

    const adjustment = c.gtk_scrolled_window_get_vadjustment(@ptrCast(ctx.scroller));
    if (adjustment != null) {
        ctx.last_scroll_position = c.gtk_adjustment_get_value(adjustment);
    } else {
        ctx.last_scroll_position = 0;
    }
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
    gtk_preview.cancelPendingWork(ctx);
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (ctx.last_query_text) |query_ptr| {
        allocator.free(query_ptr[0..ctx.last_query_len]);
        ctx.last_query_text = null;
        ctx.last_query_len = 0;
    }
    gtk_async.clearAsyncSearchCache(ctx, allocator);
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
    gtk_deferred_clear.cancel(ctx);
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
