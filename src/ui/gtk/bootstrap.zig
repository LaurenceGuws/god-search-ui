const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const gtk_bootstrap_context = @import("bootstrap_context.zig");
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

    const widgets = gtk_bootstrap_context.WidgetRefs{
        .window = window,
        .entry = entry,
        .status = status,
        .list = list,
        .scroller = scroller,
        .preview_panel = preview_panel,
        .preview_title = preview_title,
        .preview_toggle_button = preview_toggle_button,
        .preview_text_scroller = preview_text_scroller,
        .preview_text = preview_text,
    };
    const ctx = gtk_bootstrap_context.createUiContext(launch, widgets, launch_start_ns) orelse return;
    gtk_bootstrap_context.connectSignals(ctx, widgets, hooks);

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
