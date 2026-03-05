const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const gtk_types = @import("types.zig");
const gtk_preview = @import("preview.zig");
const placement_bridge = @import("placement_bridge.zig");
const layer_shell = @import("layer_shell.zig");
const action_provider = @import("../../providers/actions.zig");
const SurfaceMode = @import("../surfaces/mod.zig").SurfaceMode;
const PlacementPolicy = @import("../placement/mod.zig").RuntimePolicy;

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;

const HelpEntryState = struct {
    key_text: []const u8,
    details: ?[]const []const u8,
    insert_text: ?[]const u8,
    ui_state: *HelpUiState,
    entry: *c.GtkWidget,
    panel: *c.GtkWidget,
    content: *c.GtkWidget,
};

const HelpToggleState = struct {
    button: *c.GtkWidget,
    panel: *c.GtkWidget,
    ui_state: *HelpUiState,
};

const HelpUiState = struct {
    entry: *c.GtkWidget,
    panel: *c.GtkWidget,
    content: *c.GtkWidget,
};

const files_options = [_][]const u8{
    "Files route: % <term>",
    "Powered by fd for quick file and folder lookup.",
    "Includes hidden files/folders by default.",
    "No launcher runtime toggle yet; adjust fd behavior in command-level config.",
};

const grep_options = [_][]const u8{
    "Grep route: & <term>",
    "Uses rg to search file contents.",
    "Default: ignore hidden entries.",
    "Set GOD_SEARCH_RG_HIDDEN=1 in environment to include hidden files/dirs.",
};

const packages_options = [_][]const u8{
    "Packages route: + <term>",
    "Searches packages via configured tools.package_manager (Lua).",
    "Filter installed only: +i <term> (or +installed <term>).",
    "Installed packages: Enter updates; extra Remove action is listed.",
    "Install/update/remove use configured package_manager + terminal tools.",
};

const icons_options = [_][]const u8{
    "Icons route: ^ <term>",
    "Searches icon filenames across installed icon themes.",
    "Includes ~/.icons, ~/.local/share/icons, /usr/share/icons and /usr/share/pixmaps.",
    "Select a result to open the icon file path directly.",
};

const nerd_icons_options = [_][]const u8{
    "Nerd Icons route: * <term>",
    "Searches Nerd Font icon names from your icon_finder dataset.",
    "Enter copies the selected glyph to clipboard.",
    "Source file: ~/personal/bash_engine/src/modules/fun/nerd_icons_fzf/icons_simple.txt",
};

const emoji_options = [_][]const u8{
    "Emoji route: : <term>",
    "Searches emoji names from glibc transliteration data.",
    "Enter copies the selected emoji to clipboard.",
    "Source file: /usr/share/i18n/locales/translit_emojis",
};

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

    const help_button = c.gtk_button_new_with_label("?");
    c.gtk_widget_add_css_class(help_button, "gs-help-btn");
    c.gtk_widget_set_tooltip_text(help_button, "Search routes and shortcuts");

    const help_content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 4);
    c.gtk_widget_set_margin_top(help_content, 8);
    c.gtk_widget_set_margin_bottom(help_content, 8);
    c.gtk_widget_set_margin_start(help_content, 10);
    c.gtk_widget_set_margin_end(help_content, 10);

    const help_scroll = c.gtk_scrolled_window_new();
    c.gtk_widget_add_css_class(help_scroll, "gs-help-popover");
    c.gtk_widget_add_css_class(help_scroll, "gs-help-scroll");
    c.gtk_widget_set_size_request(help_scroll, 380, 360);
    c.gtk_scrolled_window_set_policy(@ptrCast(help_scroll), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_overlay_scrolling(@ptrCast(help_scroll), GTRUE);
    c.gtk_scrolled_window_set_child(@ptrCast(help_scroll), help_content);

    const help_panel_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(help_panel_row, GTRUE);
    c.gtk_widget_set_visible(help_panel_row, GFALSE);
    c.gtk_widget_set_halign(help_panel_row, c.GTK_ALIGN_FILL);
    c.gtk_widget_set_valign(help_panel_row, c.GTK_ALIGN_START);
    const help_panel_spacer = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(help_panel_spacer, GTRUE);
    c.gtk_widget_set_halign(help_scroll, c.GTK_ALIGN_END);
    c.gtk_box_append(@ptrCast(help_panel_row), help_panel_spacer);
    c.gtk_box_append(@ptrCast(help_panel_row), help_scroll);

    const help_ui_state = std.heap.page_allocator.create(HelpUiState) catch return;
    help_ui_state.* = .{
        .entry = entry,
        .panel = help_panel_row,
        .content = help_content,
    };
    populateHelpMainMenu(help_ui_state);

    const help_toggle_state = std.heap.page_allocator.create(HelpToggleState) catch return;
    help_toggle_state.* = .{
        .button = help_button,
        .panel = help_panel_row,
        .ui_state = help_ui_state,
    };
    _ = c.g_signal_connect_data(help_button, "clicked", c.G_CALLBACK(onHelpClicked), help_toggle_state, @as(c.GClosureNotify, onHelpToggleStateDestroy), 0);

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
    ctx.async_ready_id = 0;
    ctx.startup_idle_id = 0;
    ctx.async_spinner_phase = 0;
    ctx.async_inflight = gtk_types.GFALSE;
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

fn onHelpClicked(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (button == null or user_data == null) return;
    const state = @as(*HelpToggleState, @ptrCast(@alignCast(user_data.?)));
    const button_width = c.gtk_widget_get_width(state.button);
    const panel_width = c.gtk_widget_get_width(state.panel);
    const is_open = c.gtk_widget_get_visible(state.panel);
    std.log.info("help panel toggle button_w={d} panel_w={d} open={d}", .{ button_width, panel_width, is_open });
    if (is_open == GTRUE) {
        c.gtk_widget_set_visible(state.panel, GFALSE);
    } else {
        populateHelpMainMenu(state.ui_state);
        c.gtk_widget_set_visible(state.panel, GTRUE);
    }
}

fn onHelpItemClicked(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null or button == null) return;
    const state = @as(*HelpEntryState, @ptrCast(@alignCast(user_data.?)));
    if (state.details) |lines| {
        std.log.info("help item submenu key={s} details_len={d}", .{ state.key_text, lines.len });
        c.gtk_widget_set_visible(state.panel, GFALSE);
        populateHelpSubmenu(state.ui_state, state.key_text, lines);
        c.gtk_widget_set_visible(state.panel, GTRUE);
        return;
    }
    if (state.insert_text) |prefix| {
        const prefix_z = std.heap.page_allocator.dupeZ(u8, prefix) catch return;
        defer std.heap.page_allocator.free(prefix_z);
        c.gtk_editable_set_text(@ptrCast(state.entry), prefix_z.ptr);
        c.gtk_editable_set_position(@ptrCast(state.entry), -1);
        _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(state.entry)));
        c.gtk_widget_set_visible(state.panel, GFALSE);
        std.log.info("help item prefix key={s} text={s}", .{ state.key_text, prefix });
    }
}

fn onHelpEntryStateDestroy(
    data: ?*anyopaque,
    _: ?*c.GClosure,
) callconv(.c) void {
    if (data == null) return;
    const state: *HelpEntryState = @ptrCast(@alignCast(data.?));
    std.heap.page_allocator.destroy(state);
}

fn onHelpToggleStateDestroy(
    data: ?*anyopaque,
    _: ?*c.GClosure,
) callconv(.c) void {
    if (data == null) return;
    const state: *HelpToggleState = @ptrCast(@alignCast(data.?));
    std.heap.page_allocator.destroy(state.ui_state);
    std.heap.page_allocator.destroy(state);
}

fn onHelpBackClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null) return;
    const ui_state = @as(*HelpUiState, @ptrCast(@alignCast(user_data.?)));
    populateHelpMainMenu(ui_state);
}

fn appendHelpTitle(box: *c.GtkWidget, title: []const u8, subtitle: []const u8) void {
    const title_label = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(title_label), 0.0);
    c.gtk_widget_add_css_class(title_label, "gs-help-title");
    const title_z = std.heap.page_allocator.dupeZ(u8, title) catch return;
    defer std.heap.page_allocator.free(title_z);
    c.gtk_label_set_text(@ptrCast(title_label), title_z.ptr);
    c.gtk_box_append(@ptrCast(box), title_label);

    const subtitle_label = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(subtitle_label), 0.0);
    c.gtk_label_set_wrap(@ptrCast(subtitle_label), GTRUE);
    c.gtk_widget_add_css_class(subtitle_label, "gs-help-subtitle");
    const subtitle_z = std.heap.page_allocator.dupeZ(u8, subtitle) catch return;
    defer std.heap.page_allocator.free(subtitle_z);
    c.gtk_label_set_text(@ptrCast(subtitle_label), subtitle_z.ptr);
    c.gtk_box_append(@ptrCast(box), subtitle_label);
}

fn appendHelpSection(box: *c.GtkWidget, section_name: []const u8) void {
    const section = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(section), 0.0);
    c.gtk_widget_set_margin_top(section, 6);
    c.gtk_widget_add_css_class(section, "gs-help-section");
    const section_z = std.heap.page_allocator.dupeZ(u8, section_name) catch return;
    defer std.heap.page_allocator.free(section_z);
    c.gtk_label_set_text(@ptrCast(section), section_z.ptr);
    c.gtk_box_append(@ptrCast(box), section);
}

fn appendHelpItemWithDetails(
    box: *c.GtkWidget,
    key_text: []const u8,
    description_text: []const u8,
    details: ?[]const []const u8,
    insert_text: ?[]const u8,
    ui_state: *HelpUiState,
) void {
    const row_button = c.gtk_button_new();
    c.gtk_widget_add_css_class(row_button, "gs-help-row");
    c.gtk_widget_add_css_class(row_button, "gs-help-item-btn");
    c.gtk_widget_set_hexpand(row_button, GTRUE);

    const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_hexpand(row, GTRUE);

    const key = c.gtk_label_new(null);
    c.gtk_widget_set_size_request(key, 70, -1);
    c.gtk_label_set_xalign(@ptrCast(key), 0.0);
    c.gtk_widget_add_css_class(key, "gs-help-key");
    const key_z = std.heap.page_allocator.dupeZ(u8, key_text) catch return;
    defer std.heap.page_allocator.free(key_z);
    c.gtk_label_set_text(@ptrCast(key), key_z.ptr);

    const desc = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(desc), 0.0);
    c.gtk_label_set_wrap(@ptrCast(desc), GTRUE);
    c.gtk_widget_set_hexpand(desc, GTRUE);
    c.gtk_widget_add_css_class(desc, "gs-help-desc");
    const desc_z = std.heap.page_allocator.dupeZ(u8, description_text) catch return;
    defer std.heap.page_allocator.free(desc_z);
    c.gtk_label_set_text(@ptrCast(desc), desc_z.ptr);

    c.gtk_box_append(@ptrCast(row), key);
    c.gtk_box_append(@ptrCast(row), desc);
    c.gtk_button_set_child(@ptrCast(row_button), @ptrCast(row));

    if (details != null or insert_text != null) {
        const state = std.heap.page_allocator.create(HelpEntryState) catch return;
        state.* = .{
            .key_text = key_text,
            .details = details,
            .insert_text = insert_text,
            .ui_state = ui_state,
            .entry = ui_state.entry,
            .panel = ui_state.panel,
            .content = ui_state.content,
        };
        _ = c.g_signal_connect_data(row_button, "clicked", c.G_CALLBACK(onHelpItemClicked), state, @as(c.GClosureNotify, onHelpEntryStateDestroy), 0);
    }

    c.gtk_box_append(@ptrCast(box), row_button);
}

fn appendHelpItem(box: *c.GtkWidget, key_text: []const u8, description_text: []const u8, ui_state: *HelpUiState) void {
    appendHelpItemWithDetails(box, key_text, description_text, null, null, ui_state);
}

fn appendHelpPrefixItem(box: *c.GtkWidget, key_text: []const u8, description_text: []const u8, ui_state: *HelpUiState) void {
    const insert_text: ?[]const u8 = if (std.mem.eql(u8, key_text, "@")) "@ " else if (std.mem.eql(u8, key_text, "#")) "# " else if (std.mem.eql(u8, key_text, "!")) "! " else if (std.mem.eql(u8, key_text, "~")) "~ " else if (std.mem.eql(u8, key_text, "+")) "+ " else if (std.mem.eql(u8, key_text, "$")) "$ " else if (std.mem.eql(u8, key_text, ">")) "> " else if (std.mem.eql(u8, key_text, "=")) "= " else if (std.mem.eql(u8, key_text, "?")) "? " else null;
    appendHelpItemWithDetails(box, key_text, description_text, null, insert_text, ui_state);
}

fn appendActionsInfo(box: *c.GtkWidget, ui_state: *HelpUiState) void {
    const specs = action_provider.allSpecs();
    for (specs) |spec| {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(std.heap.page_allocator);

        const writer = detail.writer(std.heap.page_allocator);
        writer.print("{s}", .{spec.help}) catch continue;
        if (spec.confirm) {
            writer.print(" Requires confirmation.", .{}) catch continue;
        }
        const detail_text = detail.toOwnedSlice(std.heap.page_allocator) catch continue;
        defer std.heap.page_allocator.free(detail_text);
        appendHelpItem(box, spec.title, detail_text, ui_state);
    }
}

fn clearHelpContent(content: *c.GtkWidget) void {
    var child = c.gtk_widget_get_first_child(content);
    while (child != null) : (child = c.gtk_widget_get_first_child(content)) {
        c.gtk_box_remove(@ptrCast(content), child);
    }
}

fn populateHelpMainMenu(ui_state: *HelpUiState) void {
    clearHelpContent(ui_state.content);
    appendHelpTitle(ui_state.content, "Quick Reference", "Routes, commands, and keys");
    appendHelpSection(ui_state.content, "Routes");
    appendHelpPrefixItem(ui_state.content, "@", "Apps", ui_state);
    appendHelpPrefixItem(ui_state.content, "#", "Windows", ui_state);
    appendHelpPrefixItem(ui_state.content, "!", "Workspaces", ui_state);
    appendHelpPrefixItem(ui_state.content, "~", "Recent folders", ui_state);
    appendHelpItemWithDetails(ui_state.content, "%", "Files", &files_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "&", "Grep matches", &grep_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "+", "Packages", &packages_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "^", "Icons", &icons_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "*", "Nerd Icons", &nerd_icons_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, ":", "Emoji", &emoji_options, null, ui_state);
    appendHelpPrefixItem(ui_state.content, "$", "Notifications", ui_state);
    appendHelpSection(ui_state.content, "Commands");
    appendHelpPrefixItem(ui_state.content, ">", "Run shell command", ui_state);
    appendHelpPrefixItem(ui_state.content, "=", "Calculator", ui_state);
    appendHelpPrefixItem(ui_state.content, "?", "Web search", ui_state);
    appendHelpSection(ui_state.content, "Hotkeys");
    appendHelpItem(ui_state.content, "Enter", "Launch selected item", ui_state);
    appendHelpItem(ui_state.content, "Ctrl+P", "Toggle preview panel", ui_state);
    appendHelpItem(ui_state.content, "Ctrl+R", "Refresh providers", ui_state);
    appendHelpItem(ui_state.content, "PgUp/PgDn", "Move selection", ui_state);
    appendHelpItem(ui_state.content, "Esc", "Close launcher", ui_state);
    appendHelpSection(ui_state.content, "Actions");
    appendActionsInfo(ui_state.content, ui_state);
}

fn populateHelpSubmenu(ui_state: *HelpUiState, key_text: []const u8, lines: []const []const u8) void {
    clearHelpContent(ui_state.content);
    appendHelpTitle(ui_state.content, "Route Details", key_text);
    const back_button = c.gtk_button_new();
    c.gtk_widget_add_css_class(back_button, "gs-help-row");
    c.gtk_widget_add_css_class(back_button, "gs-help-item-btn");
    c.gtk_widget_set_hexpand(back_button, GTRUE);
    const back_label = c.gtk_label_new("Back");
    c.gtk_label_set_xalign(@ptrCast(back_label), 0.0);
    c.gtk_widget_add_css_class(back_label, "gs-help-key");
    c.gtk_button_set_child(@ptrCast(back_button), back_label);
    _ = c.g_signal_connect_data(back_button, "clicked", c.G_CALLBACK(onHelpBackClicked), ui_state, null, 0);
    c.gtk_box_append(@ptrCast(ui_state.content), back_button);

    for (lines) |line| {
        const line_label = c.gtk_label_new(null);
        c.gtk_label_set_xalign(@ptrCast(line_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(line_label), GTRUE);
        c.gtk_widget_add_css_class(line_label, "gs-help-desc");
        const line_z = std.heap.page_allocator.dupeZ(u8, line) catch continue;
        defer std.heap.page_allocator.free(line_z);
        c.gtk_label_set_text(@ptrCast(line_label), line_z.ptr);
        c.gtk_box_append(@ptrCast(ui_state.content), line_label);
    }
}
