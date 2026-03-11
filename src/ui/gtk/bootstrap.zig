const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const gtk_types = @import("types.zig");
const gtk_help_panel = @import("help_panel.zig");
const gtk_preview = @import("preview.zig");
const placement_bridge = @import("placement_bridge.zig");
const layer_shell = @import("layer_shell.zig");
const SurfaceMode = @import("../surfaces/mod.zig").SurfaceMode;
const PlacementPolicy = @import("../placement/mod.zig").RuntimePolicy;

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;

pub const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    resident_mode: bool,
    start_hidden: bool,
    surface_mode: SurfaceMode,
    placement_policy: PlacementPolicy,
    show_nerd_stats: bool,
    ctx: ?*UiContext,
    gtk_app: *c.GtkApplication,
};

pub const ActivateHooks = struct {
    on_key_pressed: *const fn (?*c.GtkEventControllerKey, c.guint, c.guint, c.GdkModifierType, ?*anyopaque) callconv(.c) c.gboolean,
    on_search_changed: *const fn (?*c.GtkEditable, ?*anyopaque) callconv(.c) void,
    on_entry_activate: *const fn (?*c.GtkEntry, ?*anyopaque) callconv(.c) void,
    on_row_activated: *const fn (?*c.GtkListBox, ?*c.GtkListBoxRow, ?*anyopaque) callconv(.c) void,
    on_row_selected: *const fn (?*c.GtkListBox, ?*c.GtkListBoxRow, ?*anyopaque) callconv(.c) void,
    on_adjustment_changed: *const fn (?*c.GtkAdjustment, ?*anyopaque) callconv(.c) void,
    on_window_active_notify: *const fn (?*c.GtkWindow, ?*c.GParamSpec, ?*anyopaque) callconv(.c) void,
    on_close_request: *const fn (?*c.GtkWindow, ?*anyopaque) callconv(.c) c.gboolean,
    on_destroy: *const fn (?*c.GtkWidget, ?*anyopaque) callconv(.c) void,
    install_css: *const fn (*c.GtkWidget) void,
    after_activate: *const fn (*UiContext) void,
};

pub fn activate(gtk_app: *c.GtkApplication, launch: *LaunchContext, hooks: ActivateHooks) void {
    if (launch.ctx) |existing_ctx| {
        c.gtk_window_present(@ptrCast(existing_ctx.window));
        _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(existing_ctx.entry)));
        hooks.after_activate(existing_ctx);
        return;
    }

    const launch_start_ns = std.time.nanoTimestamp();
    const window = c.gtk_application_window_new(gtk_app);
    c.gtk_window_set_title(@ptrCast(window), "God Search");
    const use_layer_launcher = layer_shell.shouldUseLayerShell(launch.surface_mode);
    if (use_layer_launcher and !layer_shell.applyLauncher(window, launch.placement_policy.launcher)) {
        std.log.err("launcher: layer-shell requested but unavailable", .{});
        c.gtk_window_destroy(@ptrCast(window));
        return;
    }
    configureInitialWindowSize(window, launch.placement_policy);
    hooks.install_css(window);

    const root_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
    c.gtk_widget_set_margin_top(root_box, 12);
    c.gtk_widget_set_margin_bottom(root_box, 12);
    c.gtk_widget_set_margin_start(root_box, 12);
    c.gtk_widget_set_margin_end(root_box, 12);

    const entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Type to search...");

    const help_panel = gtk_help_panel.build(entry) orelse return;
    const help_button = help_panel.button;
    const help_panel_row = help_panel.panel_row;

    const entry_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_hexpand(entry_row, GTRUE);
    c.gtk_widget_set_vexpand(entry_row, GFALSE);
    c.gtk_widget_set_hexpand(entry, GTRUE);
    c.gtk_box_append(@ptrCast(entry_row), entry);
    c.gtk_box_append(@ptrCast(entry_row), help_button);

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
    c.gtk_widget_set_hexpand(scroller, GTRUE);
    c.gtk_widget_set_size_request(scroller, 420, -1);
    c.gtk_widget_add_css_class(scroller, "gs-results-scroll");
    c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_overlay_scrolling(@ptrCast(scroller), GTRUE);
    c.gtk_scrolled_window_set_child(@ptrCast(scroller), list);

    const preview_title = c.gtk_label_new("Preview");
    c.gtk_label_set_xalign(@ptrCast(preview_title), 0.0);
    c.gtk_widget_set_hexpand(preview_title, GTRUE);
    c.gtk_widget_add_css_class(preview_title, "gs-preview-title");

    const preview_toggle_button = c.gtk_button_new_with_label("tree");
    c.gtk_widget_add_css_class(preview_toggle_button, "gs-preview-toggle");
    c.gtk_widget_set_visible(preview_toggle_button, gtk_types.GFALSE);

    const preview_text = c.gtk_text_view_new();
    c.gtk_text_view_set_editable(@ptrCast(preview_text), gtk_types.GFALSE);
    c.gtk_text_view_set_cursor_visible(@ptrCast(preview_text), gtk_types.GFALSE);
    c.gtk_text_view_set_wrap_mode(@ptrCast(preview_text), c.PANGO_WRAP_NONE);
    c.gtk_text_view_set_monospace(@ptrCast(preview_text), GTRUE);
    c.gtk_widget_set_hexpand(preview_text, GTRUE);
    c.gtk_widget_set_vexpand(preview_text, GTRUE);
    c.gtk_widget_add_css_class(preview_text, "gs-preview-text");

    const preview_text_scroller = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_policy(@ptrCast(preview_text_scroller), c.GTK_POLICY_AUTOMATIC, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_min_content_height(@ptrCast(preview_text_scroller), 180);
    c.gtk_widget_set_vexpand(preview_text_scroller, GTRUE);
    c.gtk_widget_add_css_class(preview_text_scroller, "gs-preview-text-scroll");
    c.gtk_scrolled_window_set_child(@ptrCast(preview_text_scroller), preview_text);
    c.gtk_widget_set_visible(preview_text_scroller, gtk_types.GTRUE);

    const preview_header = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(preview_header, "gs-preview-header");
    c.gtk_box_append(@ptrCast(preview_header), preview_title);
    c.gtk_box_append(@ptrCast(preview_header), preview_toggle_button);

    const preview_inner = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
    c.gtk_widget_add_css_class(preview_inner, "gs-preview-inner");
    c.gtk_box_append(@ptrCast(preview_inner), preview_header);
    c.gtk_box_append(@ptrCast(preview_inner), preview_text_scroller);

    const preview_scroller = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_policy(@ptrCast(preview_scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_widget_set_vexpand(preview_scroller, GTRUE);
    // Reuse results-pane surface styling to keep both split panes visually consistent.
    c.gtk_widget_add_css_class(preview_scroller, "gs-results-scroll");
    c.gtk_widget_add_css_class(preview_scroller, "gs-preview-scroll");
    c.gtk_scrolled_window_set_child(@ptrCast(preview_scroller), preview_inner);

    const preview_panel = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_add_css_class(preview_panel, "gs-preview-panel");
    c.gtk_widget_set_size_request(preview_panel, 300, -1);
    c.gtk_box_append(@ptrCast(preview_panel), preview_scroller);
    c.gtk_widget_set_visible(preview_panel, gtk_types.GFALSE);

    const content_pane = c.gtk_paned_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.gtk_widget_add_css_class(content_pane, "gs-content-pane");
    c.gtk_widget_set_vexpand(content_pane, GTRUE);
    c.gtk_widget_set_hexpand(content_pane, GTRUE);
    c.gtk_paned_set_position(@ptrCast(content_pane), 620);
    c.gtk_paned_set_start_child(@ptrCast(content_pane), scroller);
    c.gtk_paned_set_end_child(@ptrCast(content_pane), preview_panel);
    c.gtk_paned_set_resize_start_child(@ptrCast(content_pane), GTRUE);
    c.gtk_paned_set_shrink_start_child(@ptrCast(content_pane), GFALSE);
    c.gtk_paned_set_resize_end_child(@ptrCast(content_pane), GFALSE);
    c.gtk_paned_set_shrink_end_child(@ptrCast(content_pane), GFALSE);

    const content_stack = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content_stack, GTRUE);
    c.gtk_widget_set_vexpand(content_stack, GTRUE);
    c.gtk_box_append(@ptrCast(content_stack), status);
    c.gtk_box_append(@ptrCast(content_stack), content_pane);

    const content_overlay = c.gtk_overlay_new();
    c.gtk_widget_set_hexpand(content_overlay, GTRUE);
    c.gtk_widget_set_vexpand(content_overlay, GTRUE);
    c.gtk_overlay_set_child(@ptrCast(content_overlay), content_stack);
    c.gtk_overlay_add_overlay(@ptrCast(content_overlay), help_panel_row);

    const ctx: *UiContext = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(UiContext))));
    const allocator_box = launch.allocator.create(std.mem.Allocator) catch {
        c.g_free(ctx);
        return;
    };
    allocator_box.* = launch.allocator;
    ctx.launch_ctx = @ptrCast(launch);
    ctx.window = @ptrCast(window);
    ctx.entry = @ptrCast(entry);
    ctx.status = @ptrCast(status);
    ctx.list = @ptrCast(list);
    ctx.scroller = @ptrCast(scroller);
    ctx.preview_panel = @ptrCast(preview_panel);
    ctx.preview_title = @ptrCast(preview_title);
    ctx.preview_toggle_button = @ptrCast(preview_toggle_button);
    ctx.preview_text_scroller = @ptrCast(preview_text_scroller);
    ctx.preview_text_view = @ptrCast(preview_text);
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

    const key_controller = c.gtk_event_controller_key_new();
    _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(hooks.on_key_pressed), ctx, null, 0);
    c.gtk_widget_add_controller(window, @ptrCast(key_controller));
    _ = c.g_signal_connect_data(entry, "changed", c.G_CALLBACK(hooks.on_search_changed), ctx, null, 0);
    _ = c.g_signal_connect_data(entry, "activate", c.G_CALLBACK(hooks.on_entry_activate), ctx, null, 0);
    _ = c.g_signal_connect_data(list, "row-activated", c.G_CALLBACK(hooks.on_row_activated), ctx, null, 0);
    _ = c.g_signal_connect_data(list, "row-selected", c.G_CALLBACK(hooks.on_row_selected), ctx, null, 0);
    _ = c.g_signal_connect_data(preview_toggle_button, "clicked", c.G_CALLBACK(gtk_preview.onPreviewToggleClicked), ctx, null, 0);
    const vadj = c.gtk_scrolled_window_get_vadjustment(@ptrCast(scroller));
    if (vadj != null) {
        _ = c.g_signal_connect_data(vadj, "changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
        _ = c.g_signal_connect_data(vadj, "value-changed", c.G_CALLBACK(hooks.on_adjustment_changed), ctx, null, 0);
    }
    _ = c.g_signal_connect_data(window, "close-request", c.G_CALLBACK(hooks.on_close_request), ctx, null, 0);
    _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(hooks.on_destroy), ctx, null, 0);
    _ = c.g_signal_connect_data(window, "notify::is-active", c.G_CALLBACK(hooks.on_window_active_notify), ctx, null, 0);

    c.gtk_box_append(@ptrCast(root_box), entry_row);
    c.gtk_box_append(@ptrCast(root_box), content_overlay);
    c.gtk_window_set_child(@ptrCast(window), root_box);
    launch.ctx = ctx;
    if (launch.start_hidden) {
        launch.start_hidden = false;
        c.gtk_widget_set_visible(window, gtk_types.GFALSE);
        return;
    }

    c.gtk_window_present(@ptrCast(window));
    _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(entry)));

    hooks.after_activate(ctx);
}

fn configureInitialWindowSize(window: *c.GtkWidget, policy: PlacementPolicy) void {
    placement_bridge.configureLauncherWindow(window, policy.launcher);
}
