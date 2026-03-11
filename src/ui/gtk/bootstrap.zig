const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const gtk_bootstrap_context = @import("bootstrap_context.zig");
const gtk_bootstrap_layout = @import("bootstrap_layout.zig");
const gtk_types = @import("types.zig");
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

    const layout = gtk_bootstrap_layout.build() orelse return;

    const widgets = gtk_bootstrap_context.WidgetRefs{
        .window = window,
        .entry = layout.entry,
        .status = layout.status,
        .list = layout.list,
        .scroller = layout.scroller,
        .preview_panel = layout.preview_panel,
        .preview_title = layout.preview_title,
        .preview_toggle_button = layout.preview_toggle_button,
        .preview_text_scroller = layout.preview_text_scroller,
        .preview_text = layout.preview_text,
    };
    const ctx = gtk_bootstrap_context.createUiContext(launch, widgets, launch_start_ns) orelse return;
    gtk_bootstrap_context.connectSignals(ctx, widgets, hooks);

    c.gtk_window_set_child(@ptrCast(window), layout.root_box);
    launch.ctx = ctx;
    if (launch.start_hidden) {
        launch.start_hidden = false;
        c.gtk_widget_set_visible(window, gtk_types.GFALSE);
        return;
    }

    c.gtk_window_present(@ptrCast(window));
    _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(layout.entry)));

    hooks.after_activate(ctx);
}

fn configureInitialWindowSize(window: *c.GtkWidget, policy: PlacementPolicy) void {
    placement_bridge.configureLauncherWindow(window, policy.launcher);
}
