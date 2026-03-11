const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_preview = @import("preview.zig");
const gtk_bootstrap = @import("bootstrap.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;

pub const WidgetRefs = struct {
    window: *c.GtkWidget,
    entry: *c.GtkWidget,
    status: *c.GtkWidget,
    list: *c.GtkWidget,
    scroller: *c.GtkWidget,
    preview_panel: *c.GtkWidget,
    preview_title: *c.GtkWidget,
    preview_toggle_button: *c.GtkWidget,
    preview_text_scroller: *c.GtkWidget,
    preview_text: *c.GtkWidget,
};

pub fn createUiContext(launch: *gtk_bootstrap.LaunchContext, widgets: WidgetRefs, launch_start_ns: i128) ?*UiContext {
    const ctx: *UiContext = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(UiContext))));
    const allocator_box = launch.allocator.create(std.mem.Allocator) catch {
        c.g_free(ctx);
        return null;
    };
    allocator_box.* = launch.allocator;
    ctx.launch_ctx = @ptrCast(launch);
    ctx.window = @ptrCast(widgets.window);
    ctx.entry = @ptrCast(widgets.entry);
    ctx.status = @ptrCast(widgets.status);
    ctx.list = @ptrCast(widgets.list);
    ctx.scroller = @ptrCast(widgets.scroller);
    ctx.preview_panel = @ptrCast(widgets.preview_panel);
    ctx.preview_title = @ptrCast(widgets.preview_title);
    ctx.preview_toggle_button = @ptrCast(widgets.preview_toggle_button);
    ctx.preview_text_scroller = @ptrCast(widgets.preview_text_scroller);
    ctx.preview_text_view = @ptrCast(widgets.preview_text);
    ctx.allocator = @ptrCast(allocator_box);
    ctx.service = launch.service;
    ctx.telemetry = launch.telemetry;
    ctx.resident_mode = if (launch.resident_mode) gtk_types.GTRUE else gtk_types.GFALSE;
    ctx.pending_power_confirm = gtk_types.GFALSE;
    ctx.clear_query_on_close = gtk_types.GFALSE;
    ctx.search_debounce_id = 0;
    ctx.status_reset_id = 0;
    ctx.last_status_hash = 0;
    ctx.last_status_tone = 0;
    ctx.last_render_hash = 0;
    ctx.last_preview_hash = 0;
    ctx.preview_enabled = gtk_types.GFALSE;
    ctx.preview_dir_tree_mode = gtk_types.GFALSE;
    ctx.async_search_generation = 0;
    ctx.async_spinner_id = 0;
    ctx.refresh_spinner_id = 0;
    ctx.async_ready_id = 0;
    ctx.startup_idle_id = 0;
    ctx.async_spinner_phase = 0;
    ctx.refresh_spinner_phase = 0;
    ctx.async_inflight = gtk_types.GFALSE;
    ctx.refresh_inflight = gtk_types.GFALSE;
    ctx.async_worker_active = gtk_types.GFALSE;
    ctx.async_pending_query_ptr = null;
    ctx.async_pending_query_len = 0;
    ctx.async_shutdown = gtk_types.GFALSE;
    ctx.async_worker_count = 0;
    ctx.launch_start_ns = launch_start_ns;
    ctx.focus_ready_logged = gtk_types.GFALSE;
    ctx.first_keypress_logged = gtk_types.GFALSE;
    ctx.first_input_logged = gtk_types.GFALSE;
    ctx.last_selected_row_index = -1;
    ctx.last_scroll_position = 0;
    ctx.last_query_text = null;
    ctx.last_query_len = 0;
    ctx.startup_key_queue_id = 0;
    ctx.startup_key_queue_active = gtk_types.GFALSE;
    ctx.startup_key_queue_len = 0;
    ctx.startup_key_queue = [_]u32{0} ** 24;
    ctx.async_cached_query_hash = 0;
    ctx.async_cached_total_len = 0;
    ctx.async_cached_created_ns = 0;
    ctx.async_cached_rows_ptr = null;
    ctx.async_cached_rows_len = 0;
    ctx.result_query_hash = 0;
    ctx.result_total_len = 0;
    ctx.result_window_limit = 20;
    ctx.deferred_dynamic_clear_id = 0;
    ctx.deferred_stats_refresh_id = 0;
    ctx.show_nerd_stats = if (launch.show_nerd_stats) gtk_types.GTRUE else gtk_types.GFALSE;
    ctx.active_query_hash = 0;
    ctx.active_query_started_ns = 0;
    ctx.last_ui_query_total_ns = 0;
    ctx.last_query_dynamic = gtk_types.GFALSE;
    ctx.package_preview_timeout_id = 0;
    ctx.package_preview_action_ptr = null;
    ctx.package_preview_action_len = 0;
    c.g_mutex_init(&ctx.async_worker_lock);
    c.g_cond_init(&ctx.async_worker_cond);
    return ctx;
}

pub fn connectSignals(ctx: *UiContext, widgets: WidgetRefs, hooks: gtk_bootstrap.ActivateHooks) void {
    const key_controller = c.gtk_event_controller_key_new();
    _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(hooks.on_key_pressed), ctx, null, 0);
    c.gtk_widget_add_controller(widgets.window, @ptrCast(key_controller));
    _ = c.g_signal_connect_data(widgets.entry, "changed", c.G_CALLBACK(hooks.on_search_changed), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.entry, "activate", c.G_CALLBACK(hooks.on_entry_activate), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.list, "row-activated", c.G_CALLBACK(hooks.on_row_activated), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.list, "row-selected", c.G_CALLBACK(hooks.on_row_selected), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.preview_toggle_button, "clicked", c.G_CALLBACK(gtk_preview.onPreviewToggleClicked), ctx, null, 0);
    const vadj = c.gtk_scrolled_window_get_vadjustment(@ptrCast(widgets.scroller));
    if (vadj != null) {
        _ = c.g_signal_connect_data(vadj, "changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
        _ = c.g_signal_connect_data(vadj, "value-changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
    }
    _ = c.g_signal_connect_data(widgets.window, "close-request", c.G_CALLBACK(hooks.on_close_request), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.window, "destroy", c.G_CALLBACK(hooks.on_destroy), ctx, null, 0);
    _ = c.g_signal_connect_data(widgets.window, "notify::is-active", c.G_CALLBACK(hooks.on_window_active_notify), ctx, null, 0);
}
