const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const gtk_types = @import("types.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const UiContext = gtk_types.UiContext;

pub const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
};

pub const ActivateHooks = struct {
    on_key_pressed: *const fn (?*c.GtkEventControllerKey, c.guint, c.guint, c.GdkModifierType, ?*anyopaque) callconv(.c) c.gboolean,
    on_search_changed: *const fn (?*c.GtkEditable, ?*anyopaque) callconv(.c) void,
    on_entry_activate: *const fn (?*c.GtkEntry, ?*anyopaque) callconv(.c) void,
    on_row_activated: *const fn (?*c.GtkListBox, ?*c.GtkListBoxRow, ?*anyopaque) callconv(.c) void,
    on_row_selected: *const fn (?*c.GtkListBox, ?*c.GtkListBoxRow, ?*anyopaque) callconv(.c) void,
    on_adjustment_changed: *const fn (?*c.GtkAdjustment, ?*anyopaque) callconv(.c) void,
    on_destroy: *const fn (?*c.GtkWidget, ?*anyopaque) callconv(.c) void,
    install_css: *const fn (*c.GtkWidget) void,
    after_activate: *const fn (*UiContext) void,
};

pub fn activate(gtk_app: *c.GtkApplication, launch: *LaunchContext, hooks: ActivateHooks) void {
    const window = c.gtk_application_window_new(gtk_app);
    c.gtk_window_set_title(@ptrCast(window), "God Search");
    configureInitialWindowSize(window);
    hooks.install_css(window);

    const root_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
    c.gtk_widget_set_margin_top(root_box, 12);
    c.gtk_widget_set_margin_bottom(root_box, 12);
    c.gtk_widget_set_margin_start(root_box, 12);
    c.gtk_widget_set_margin_end(root_box, 12);

    const entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Type to search...");
    const status = c.gtk_label_new("Esc to close, Ctrl+R to refresh");
    c.gtk_label_set_xalign(@ptrCast(status), 0.0);
    c.gtk_label_set_single_line_mode(@ptrCast(status), GTRUE);
    c.gtk_label_set_ellipsize(@ptrCast(status), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_max_width_chars(@ptrCast(status), 96);
    c.gtk_widget_set_margin_bottom(status, 4);
    c.gtk_widget_add_css_class(status, "gs-status");

    const list = c.gtk_list_box_new();
    c.gtk_widget_add_css_class(list, "gs-results");
    c.gtk_list_box_set_selection_mode(@ptrCast(list), c.GTK_SELECTION_SINGLE);
    const scroller = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scroller, GTRUE);
    c.gtk_widget_add_css_class(scroller, "gs-results-scroll");
    c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_overlay_scrolling(@ptrCast(scroller), GTRUE);
    c.gtk_scrolled_window_set_child(@ptrCast(scroller), list);

    const ctx: *UiContext = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(UiContext))));
    ctx.window = @ptrCast(window);
    ctx.entry = @ptrCast(entry);
    ctx.status = @ptrCast(status);
    ctx.list = @ptrCast(list);
    ctx.scroller = @ptrCast(scroller);
    ctx.allocator = @ptrCast(@constCast(&launch.allocator));
    ctx.service = launch.service;
    ctx.telemetry = launch.telemetry;
    ctx.pending_power_confirm = gtk_types.GFALSE;
    ctx.search_debounce_id = 0;
    ctx.status_reset_id = 0;
    ctx.last_status_hash = 0;
    ctx.last_status_tone = 0;
    ctx.last_render_hash = 0;
    ctx.async_search_generation = 0;
    ctx.async_spinner_id = 0;
    ctx.async_spinner_phase = 0;
    ctx.async_inflight = gtk_types.GFALSE;
    ctx.async_worker_active = gtk_types.GFALSE;
    ctx.async_pending_query_ptr = null;
    ctx.async_pending_query_len = 0;

    const key_controller = c.gtk_event_controller_key_new();
    _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(hooks.on_key_pressed), ctx, null, 0);
    c.gtk_widget_add_controller(window, @ptrCast(key_controller));
    _ = c.g_signal_connect_data(entry, "changed", c.G_CALLBACK(hooks.on_search_changed), ctx, null, 0);
    _ = c.g_signal_connect_data(entry, "activate", c.G_CALLBACK(hooks.on_entry_activate), ctx, null, 0);
    _ = c.g_signal_connect_data(list, "row-activated", c.G_CALLBACK(hooks.on_row_activated), ctx, null, 0);
    _ = c.g_signal_connect_data(list, "row-selected", c.G_CALLBACK(hooks.on_row_selected), ctx, null, 0);
    const vadj = c.gtk_scrolled_window_get_vadjustment(@ptrCast(scroller));
    if (vadj != null) {
        _ = c.g_signal_connect_data(vadj, "changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
        _ = c.g_signal_connect_data(vadj, "value-changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
    }
    _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(hooks.on_destroy), ctx, null, 0);

    c.gtk_box_append(@ptrCast(root_box), entry);
    c.gtk_box_append(@ptrCast(root_box), status);
    c.gtk_box_append(@ptrCast(root_box), scroller);
    c.gtk_window_set_child(@ptrCast(window), root_box);
    c.gtk_window_present(@ptrCast(window));

    hooks.after_activate(ctx);
}

fn configureInitialWindowSize(window: *c.GtkWidget) void {
    var width: c_int = 900;
    var height: c_int = 560;
    var min_width: c_int = 680;
    var min_height: c_int = 420;

    const display = c.gtk_widget_get_display(window);
    if (display != null) {
        const monitors = c.gdk_display_get_monitors(display);
        if (monitors != null and c.g_list_model_get_n_items(monitors) > 0) {
            const monitor_obj = c.g_list_model_get_item(monitors, 0);
            if (monitor_obj != null) {
                defer c.g_object_unref(monitor_obj);
                const monitor: *c.GdkMonitor = @ptrCast(@alignCast(monitor_obj));
                var geometry: c.GdkRectangle = undefined;
                c.gdk_monitor_get_geometry(monitor, &geometry);

                const sw: c_int = geometry.width;
                const sh: c_int = geometry.height;

                width = @max(min_width, @min(1100, @divTrunc(sw * 48, 100)));
                height = @max(min_height, @min(760, @divTrunc(sh * 56, 100)));

                min_width = @max(560, @divTrunc(sw * 32, 100));
                min_height = @max(360, @divTrunc(sh * 36, 100));
            }
        }
    }

    c.gtk_window_set_default_size(@ptrCast(window), width, height);
    c.gtk_widget_set_size_request(window, min_width, min_height);
}
