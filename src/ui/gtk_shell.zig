const std = @import("std");
const app_mod = @import("../app/mod.zig");
const providers_mod = @import("../providers/mod.zig");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const CandidateKind = @import("../search/mod.zig").CandidateKind;
const GTRUE: c.gboolean = 1;
const GFALSE: c.gboolean = 0;

const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
};

const UiContext = extern struct {
    window: *c.GtkWidget,
    entry: *c.GtkEntry,
    status: *c.GtkLabel,
    list: *c.GtkListBox,
    scroller: *c.GtkScrolledWindow,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    pending_power_confirm: c.gboolean,
    search_debounce_id: c.guint,
    status_reset_id: c.guint,
    last_status_hash: u64,
    last_status_tone: u8,
    last_render_hash: u64,
    async_search_generation: u64,
    async_spinner_id: c.guint,
    async_spinner_phase: u8,
    async_inflight: c.gboolean,
    async_worker_active: c.gboolean,
    async_pending_query_ptr: ?[*]u8,
    async_pending_query_len: usize,
};

const AsyncRenderedRow = struct {
    kind: CandidateKind,
    score: i32,
    title: []u8,
    subtitle: []u8,
    action: []u8,
    icon: []u8,
};

const AsyncSearchResult = struct {
    ctx: *UiContext,
    generation: u64,
    total_len: usize,
    query: []u8,
    rows: []AsyncRenderedRow,
};

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app_mod.SearchService, telemetry: *app_mod.TelemetrySink) !void {
        const gtk_app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(gtk_app);

        var launch = LaunchContext{
            .allocator = allocator,
            .service = service,
            .telemetry = telemetry,
        };
        _ = c.g_signal_connect_data(gtk_app, "activate", c.G_CALLBACK(onActivate), &launch, null, 0);
        _ = c.g_application_run(@ptrCast(gtk_app), 0, null);
    }

    fn onActivate(app_ptr: ?*anyopaque, user_data: ?*anyopaque) callconv(.c) void {
        const gtk_app: *c.GtkApplication = @ptrCast(@alignCast(app_ptr.?));
        const launch: *LaunchContext = @ptrCast(@alignCast(user_data.?));
        const window = c.gtk_application_window_new(gtk_app);
        c.gtk_window_set_title(@ptrCast(window), "God Search");
        configureInitialWindowSize(window);
        installCss(window);

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
        ctx.pending_power_confirm = GFALSE;
        ctx.search_debounce_id = 0;
        ctx.status_reset_id = 0;
        ctx.last_status_hash = 0;
        ctx.last_status_tone = 0;
        ctx.last_render_hash = 0;
        ctx.async_search_generation = 0;
        ctx.async_spinner_id = 0;
        ctx.async_spinner_phase = 0;
        ctx.async_inflight = GFALSE;
        ctx.async_worker_active = GFALSE;
        ctx.async_pending_query_ptr = null;
        ctx.async_pending_query_len = 0;
        updateEntryRouteIcon(ctx, "");

        const key_controller = c.gtk_event_controller_key_new();
        _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(onKeyPressed), ctx, null, 0);
        c.gtk_widget_add_controller(window, @ptrCast(key_controller));
        _ = c.g_signal_connect_data(entry, "changed", c.G_CALLBACK(onSearchChanged), ctx, null, 0);
        _ = c.g_signal_connect_data(entry, "activate", c.G_CALLBACK(onEntryActivate), ctx, null, 0);
        _ = c.g_signal_connect_data(list, "row-activated", c.G_CALLBACK(onRowActivated), ctx, null, 0);
        _ = c.g_signal_connect_data(list, "row-selected", c.G_CALLBACK(onRowSelected), ctx, null, 0);
        const vadj = c.gtk_scrolled_window_get_vadjustment(@ptrCast(scroller));
        if (vadj != null) {
            _ = c.g_signal_connect_data(vadj, "changed", c.G_CALLBACK(onResultsAdjustmentChanged), ctx, null, 0);
            _ = c.g_signal_connect_data(vadj, "value-changed", c.G_CALLBACK(onResultsAdjustmentChanged), ctx, null, 0);
        }
        _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(onDestroy), ctx, null, 0);

        c.gtk_box_append(@ptrCast(root_box), entry);
        c.gtk_box_append(@ptrCast(root_box), status);
        c.gtk_box_append(@ptrCast(root_box), scroller);
        c.gtk_window_set_child(@ptrCast(window), root_box);
        c.gtk_window_present(@ptrCast(window));

        populateResults(ctx, "");
        updateScrollbarActiveClass(ctx);
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

    fn onDestroy(_: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
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
        freePendingAsyncQuery(ctx);
        // Intentionally keep UiContext alive until process exit.
        // Async route worker callbacks may still complete after destroy.
    }

    fn onKeyPressed(
        _: ?*c.GtkEventControllerKey,
        keyval: c.guint,
        _: c.guint,
        state: c.GdkModifierType,
        user_data: ?*anyopaque,
    ) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        switch (keyval) {
            c.GDK_KEY_Escape => {
                c.gtk_window_close(@ptrCast(ctx.window));
                return GTRUE;
            },
            c.GDK_KEY_l, c.GDK_KEY_L => {
                if ((state & c.GDK_CONTROL_MASK) != 0) {
                    _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(ctx.entry)));
                    return GTRUE;
                }
                return GFALSE;
            },
            c.GDK_KEY_r, c.GDK_KEY_R => {
                if ((state & c.GDK_CONTROL_MASK) != 0) {
                    refreshSnapshot(ctx);
                    return GTRUE;
                }
                return GFALSE;
            },
            c.GDK_KEY_Down => {
                selectActionableDelta(ctx, 1);
                return GTRUE;
            },
            c.GDK_KEY_Up => {
                selectActionableDelta(ctx, -1);
                return GTRUE;
            },
            c.GDK_KEY_Page_Down => {
                selectActionableDelta(ctx, 5);
                return GTRUE;
            },
            c.GDK_KEY_Page_Up => {
                selectActionableDelta(ctx, -5);
                return GTRUE;
            },
            c.GDK_KEY_Home => {
                selectFirstActionableRow(ctx);
                return GTRUE;
            },
            c.GDK_KEY_End => {
                selectLastActionableRow(ctx);
                return GTRUE;
            },
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                activateSelectedRow(ctx);
                return GTRUE;
            },
            else => return GFALSE,
        }
    }

    fn onEntryActivate(_: ?*c.GtkEntry, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        activateSelectedRow(ctx);
    }

    fn activateSelectedRow(ctx: *UiContext) void {
        var row = c.gtk_list_box_get_selected_row(ctx.list);
        if (row == null) {
            selectFirstActionableRow(ctx);
            row = c.gtk_list_box_get_selected_row(ctx.list);
        }
        if (row != null) c.g_signal_emit_by_name(ctx.list, "row-activated", row);
    }

    fn onSearchChanged(entry: ?*c.GtkEditable, user_data: ?*anyopaque) callconv(.c) void {
        _ = entry;
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        clearPowerConfirmation(ctx);

        if (ctx.search_debounce_id != 0) {
            _ = c.g_source_remove(ctx.search_debounce_id);
            ctx.search_debounce_id = 0;
        }
        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
        updateEntryRouteIcon(ctx, query);
        if (std.mem.trim(u8, query, " \t\r\n").len == 0) {
            cancelAsyncRouteSearch(ctx);
        }
        if (ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "Searching...");
        }
        const debounce_ms = searchDebounceMsForQuery(std.mem.trim(u8, query, " \t\r\n"));
        ctx.search_debounce_id = c.g_timeout_add(debounce_ms, onSearchDebounced, ctx);
    }

    fn onSearchDebounced(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        ctx.search_debounce_id = 0;

        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        if (text_ptr == null) {
            populateResults(ctx, "");
            return GFALSE;
        }
        const query = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
        populateResults(ctx, query);
        return GFALSE;
    }

    fn onResultsAdjustmentChanged(_: ?*c.GtkAdjustment, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        updateScrollbarActiveClass(ctx);
    }

    fn updateScrollbarActiveClass(ctx: *UiContext) void {
        const vadj = c.gtk_scrolled_window_get_vadjustment(ctx.scroller);
        if (vadj == null) return;
        const upper = c.gtk_adjustment_get_upper(vadj);
        const page = c.gtk_adjustment_get_page_size(vadj);
        const active = (upper - page) > 1.0;
        if (active) {
            c.gtk_widget_add_css_class(@ptrCast(@alignCast(ctx.list)), "gs-scroll-active");
        } else {
            c.gtk_widget_remove_css_class(@ptrCast(@alignCast(ctx.list)), "gs-scroll-active");
        }
    }

    fn searchDebounceMsForQuery(query_trimmed: []const u8) c.guint {
        const query_len = query_trimmed.len;
        if (query_len == 0) return 110;
        if (query_len >= 1 and (query_trimmed[0] == '%' or query_trimmed[0] == '&')) {
            const term_len = if (query_len > 1) std.mem.trim(u8, query_trimmed[1..], " \t\r\n").len else 0;
            if (term_len <= 1) return 300;
            if (term_len <= 3) return 220;
            return 160;
        }
        if (query_len <= 2) return 90;
        if (query_len <= 5) return 75;
        return 60;
    }

    fn updateEntryRouteIcon(ctx: *UiContext, query: []const u8) void {
        const entry: *c.GtkEntry = @ptrCast(@alignCast(ctx.entry));
        const route_icon = routeIconForLeadingPrefix(query);
        if (route_icon) |icon_name| {
            const icon_z = std.heap.page_allocator.dupeZ(u8, icon_name) catch return;
            defer std.heap.page_allocator.free(icon_z);
            c.gtk_entry_set_icon_from_icon_name(entry, c.GTK_ENTRY_ICON_PRIMARY, icon_z.ptr);
            c.gtk_entry_set_icon_sensitive(entry, c.GTK_ENTRY_ICON_PRIMARY, GTRUE);
            c.gtk_entry_set_icon_activatable(entry, c.GTK_ENTRY_ICON_PRIMARY, GFALSE);
            return;
        }
        c.gtk_entry_set_icon_from_icon_name(entry, c.GTK_ENTRY_ICON_PRIMARY, null);
    }

    fn routeIconForLeadingPrefix(query: []const u8) ?[]const u8 {
        if (query.len == 0) return null;
        return switch (query[0]) {
            '@' => "applications-system-symbolic",
            '#' => "window-new-symbolic",
            '~' => "folder-symbolic",
            '%' => "text-x-generic-symbolic",
            '&' => "edit-find-symbolic",
            '>' => "utilities-terminal-symbolic",
            '=' => "accessories-calculator-symbolic",
            '?' => "web-browser-symbolic",
            else => null,
        };
    }

    fn onRowActivated(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
        if (row == null or user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        const kind_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind");
        const action_ptr = c.g_object_get_data(@ptrCast(row), "gs-action");
        if (kind_ptr == null or action_ptr == null) return;

        const kind = std.mem.span(@as([*:0]const u8, @ptrCast(kind_ptr)));
        const action = std.mem.span(@as([*:0]const u8, @ptrCast(action_ptr)));
        executeSelected(ctx, kind, action);
    }

    fn onRowSelected(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
        if (row == null or user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        if (ctx.pending_power_confirm == GTRUE) return;
        if (ctx.service.last_query_used_stale_cache or ctx.service.last_query_refreshed_cache) return;

        const title_ptr = c.g_object_get_data(@ptrCast(row), "gs-title");
        if (title_ptr == null) return;
        const title = std.mem.span(@as([*:0]const u8, @ptrCast(title_ptr)));
        const kind_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind");
        const kind = if (kind_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(kind_ptr))) else "";
        const kind_label = kindStatusLabel(kind);
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const msg = std.fmt.allocPrint(allocator_ptr.*, "Enter launch {s}: {s}", .{ kind_label, title }) catch return;
        defer allocator_ptr.*.free(msg);
        setStatus(ctx, msg);
    }

    fn selectActionableDelta(ctx: *UiContext, delta: i32) void {
        if (delta == 0) return;
        const step: i32 = if (delta > 0) 1 else -1;
        const target_moves: i32 = @intCast(@abs(delta));
        const selected = c.gtk_list_box_get_selected_row(ctx.list);
        if (selected == null) {
            if (delta > 0) {
                selectFirstActionableRow(ctx);
            } else {
                selectLastActionableRow(ctx);
            }
            return;
        }

        var idx: i32 = c.gtk_list_box_row_get_index(selected) + step;
        if (idx < 0) return;

        var moved: i32 = 0;
        while (idx >= 0) : (idx += step) {
            const target = c.gtk_list_box_get_row_at_index(ctx.list, idx);
            if (target == null) return;
            if (c.g_object_get_data(@ptrCast(target), "gs-action") != null) {
                moved += 1;
                if (moved >= target_moves) {
                    c.gtk_list_box_select_row(ctx.list, target);
                    ensureSelectedRowVisible(ctx);
                    return;
                }
            }
        }
    }

    fn selectFirstActionableRow(ctx: *UiContext) void {
        var idx: i32 = 0;
        while (true) : (idx += 1) {
            const row = c.gtk_list_box_get_row_at_index(ctx.list, idx);
            if (row == null) break;
            if (c.g_object_get_data(@ptrCast(row), "gs-action") != null) {
                c.gtk_list_box_select_row(ctx.list, row);
                ensureSelectedRowVisible(ctx);
                return;
            }
        }
        c.gtk_list_box_select_row(ctx.list, null);
    }

    fn selectLastActionableRow(ctx: *UiContext) void {
        var idx: i32 = 0;
        while (c.gtk_list_box_get_row_at_index(ctx.list, idx) != null) : (idx += 1) {}
        idx -= 1;
        while (idx >= 0) : (idx -= 1) {
            const row = c.gtk_list_box_get_row_at_index(ctx.list, idx);
            if (row == null) break;
            if (c.g_object_get_data(@ptrCast(row), "gs-action") != null) {
                c.gtk_list_box_select_row(ctx.list, row);
                ensureSelectedRowVisible(ctx);
                return;
            }
        }
        c.gtk_list_box_select_row(ctx.list, null);
    }

    fn ensureSelectedRowVisible(ctx: *UiContext) void {
        const row = c.gtk_list_box_get_selected_row(ctx.list);
        if (row == null) return;

        const adjustment = c.gtk_scrolled_window_get_vadjustment(ctx.scroller);
        if (adjustment == null) return;

        var alloc: c.GtkAllocation = undefined;
        c.gtk_widget_get_allocation(@ptrCast(row), &alloc);
        const top = @as(f64, @floatFromInt(alloc.y));
        const bottom = @as(f64, @floatFromInt(alloc.y + alloc.height));
        const value = c.gtk_adjustment_get_value(adjustment);
        const page_size = c.gtk_adjustment_get_page_size(adjustment);

        if (top < value) {
            c.gtk_adjustment_set_value(adjustment, top);
        } else if (bottom > (value + page_size)) {
            c.gtk_adjustment_set_value(adjustment, bottom - page_size);
        }
    }

    fn populateResults(ctx: *UiContext, query: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        const query_trimmed = std.mem.trim(u8, query, " \t\r\n");

        if (query_trimmed.len == 0) {
            cancelAsyncRouteSearch(ctx);
            const empty_hash = std.hash.Wyhash.hash(0, "module-filter-menu");
            if (ctx.last_render_hash != empty_hash) {
                clearList(ctx.list);
                appendModuleFilterMenu(ctx, allocator);
                ctx.last_render_hash = empty_hash;
            }
            if (ctx.pending_power_confirm == GFALSE) {
                setStatus(ctx, "Choose a module filter or type without prefix for blended search");
            }
            selectFirstActionableRow(ctx);
            return;
        }

        if (shouldAsyncRouteQuery(query_trimmed)) {
            startAsyncRouteSearch(ctx, allocator, query_trimmed);
            return;
        }
        cancelAsyncRouteSearch(ctx);

        const ranked = ctx.service.searchQuery(allocator, query) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Search failed: {s}", .{@errorName(err)}) catch "Search failed";
            defer if (!std.mem.eql(u8, msg, "Search failed")) allocator.free(msg);
            appendInfoRow(ctx.list, msg);
            setStatus(ctx, "Search failed");
            return;
        };
        defer allocator.free(ranked);

        renderRankedRows(ctx, allocator, query_trimmed, ranked, ranked.len);
        _ = ctx.service.drainScheduledRefresh(allocator) catch false;
        selectFirstActionableRow(ctx);
    }

    fn renderRankedRows(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        query_trimmed: []const u8,
        ranked: []const @import("../search/mod.zig").ScoredCandidate,
        total_len: usize,
    ) void {
        const limit = @min(ranked.len, 20);
        const rows = ranked[0..limit];
        const empty_query = query_trimmed.len == 0;
        const route_hint = routeHintForQuery(query_trimmed);
        const highlight_token = highlightTokenForQuery(query_trimmed);
        const has_app_glyph_fallback = hasAppGlyphFallback(rows);
        const render_hash = computeRenderHash(query_trimmed, route_hint, rows, ranked.len);
        if (ctx.last_render_hash != render_hash) {
            clearList(ctx.list);
            if (route_hint) |hint| {
                appendInfoRow(ctx.list, hint);
            }
            if (rows.len == 0 and !empty_query and route_hint == null) {
                appendInfoRow(ctx.list, "No results");
                appendInfoRow(ctx.list, "Try routes: @ apps  # windows  ~ dirs  % files  & grep  > run  = calc  ? web");
            } else {
                appendGroupedRows(ctx, allocator, rows, highlight_token);
                if (total_len > limit) {
                    appendInfoRow(ctx.list, "Showing top 20 results");
                }
            }
            ctx.last_render_hash = render_hash;
        }
        if (ctx.service.last_query_used_stale_cache) {
            setStatus(ctx, "Refresh scheduled");
        } else if (ctx.service.last_query_refreshed_cache) {
            setStatus(ctx, "Snapshot refreshed");
        } else if (empty_query and has_app_glyph_fallback and ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "App icon fallback active (headless :icondiag for breakdown)");
        } else if (empty_query and ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "Esc close | Ctrl+R refresh | @ apps # windows ~ dirs % files & grep > run = calc ? web");
        } else if (ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "");
        }
    }

    fn computeRenderHash(
        query_trimmed: []const u8,
        route_hint: ?[]const u8,
        rows: []const @import("../search/mod.zig").ScoredCandidate,
        total_len: usize,
    ) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(query_trimmed);
        if (route_hint) |hint| h.update(hint);
        var len_buf: [32]u8 = undefined;
        const len_txt = std.fmt.bufPrint(&len_buf, "{d}", .{total_len}) catch "";
        h.update(len_txt);
        for (rows) |row| {
            h.update(kindTag(row.candidate.kind));
            h.update(row.candidate.title);
            h.update(row.candidate.subtitle);
            h.update(row.candidate.action);
        }
        return h.final();
    }

    fn shouldAsyncRouteQuery(query_trimmed: []const u8) bool {
        if (query_trimmed.len < 2) return false;
        const route = query_trimmed[0];
        if (route != '%' and route != '&') return false;
        return std.mem.trim(u8, query_trimmed[1..], " \t\r\n").len > 0;
    }

    fn startAsyncRouteSearch(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
        ctx.async_search_generation += 1;
        const generation = ctx.async_search_generation;
        const query_copy = allocator.dupe(u8, query_trimmed) catch return;
        beginAsyncSpinner(ctx);

        if (ctx.async_worker_active == GTRUE) {
            queuePendingAsyncQuery(ctx, allocator, query_copy);
            return;
        }
        if (!spawnAsyncRouteSearchWorker(ctx, allocator, generation, query_copy)) {
            allocator.free(query_copy);
            endAsyncSpinner(ctx);
        }
    }

    fn spawnAsyncRouteSearchWorker(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        generation: u64,
        query_owned: []u8,
    ) bool {
        const payload = allocator.create(AsyncSearchResult) catch {
            return false;
        };
        payload.* = .{
            .ctx = ctx,
            .generation = generation,
            .total_len = 0,
            .query = query_owned,
            .rows = &.{},
        };
        const worker = std.Thread.spawn(.{}, asyncRouteSearchWorker, .{payload}) catch {
            freeAsyncSearchResult(allocator, payload);
            return false;
        };
        ctx.async_worker_active = GTRUE;
        worker.detach();
        return true;
    }

    fn asyncRouteSearchWorker(payload: *AsyncSearchResult) void {
        const ctx = payload.ctx;
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        const ranked = ctx.service.searchQuery(allocator, payload.query) catch {
            payload.total_len = 0;
            payload.rows = &.{};
            _ = c.g_idle_add(onAsyncSearchReady, payload);
            return;
        };
        defer allocator.free(ranked);

        payload.total_len = ranked.len;
        const limit = @min(ranked.len, 20);
        payload.rows = allocator.alloc(AsyncRenderedRow, limit) catch {
            payload.total_len = 0;
            payload.rows = &.{};
            _ = c.g_idle_add(onAsyncSearchReady, payload);
            return;
        };

        for (ranked[0..limit], 0..) |row, idx| {
            payload.rows[idx] = .{
                .kind = row.candidate.kind,
                .score = row.score,
                .title = allocator.dupe(u8, row.candidate.title) catch "",
                .subtitle = allocator.dupe(u8, row.candidate.subtitle) catch "",
                .action = allocator.dupe(u8, row.candidate.action) catch "",
                .icon = allocator.dupe(u8, row.candidate.icon) catch "",
            };
        }

        _ = c.g_idle_add(onAsyncSearchReady, payload);
    }

    fn onAsyncSearchReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const payload: *AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
        const ctx = payload.ctx;
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        defer freeAsyncSearchResult(allocator, payload);
        ctx.async_worker_active = GFALSE;
        if (payload.generation != ctx.async_search_generation) {
            _ = launchPendingAsyncQuery(ctx, allocator);
            return GFALSE;
        }

        endAsyncSpinner(ctx);
        var scored = allocator.alloc(@import("../search/mod.zig").ScoredCandidate, payload.rows.len) catch return GFALSE;
        defer allocator.free(scored);
        for (payload.rows, 0..) |row, idx| {
            scored[idx] = .{
                .candidate = .{
                    .kind = row.kind,
                    .title = row.title,
                    .subtitle = row.subtitle,
                    .action = row.action,
                    .icon = row.icon,
                },
                .score = row.score,
            };
        }

        renderRankedRows(ctx, allocator, std.mem.trim(u8, payload.query, " \t\r\n"), scored, payload.total_len);
        selectFirstActionableRow(ctx);
        return GFALSE;
    }

    fn cancelAsyncRouteSearch(ctx: *UiContext) void {
        ctx.async_search_generation += 1;
        freePendingAsyncQuery(ctx);
        endAsyncSpinner(ctx);
    }

    fn queuePendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator, query_owned: []u8) void {
        if (ctx.async_pending_query_ptr) |ptr| {
            const prev = ptr[0..ctx.async_pending_query_len];
            allocator.free(prev);
        }
        ctx.async_pending_query_ptr = query_owned.ptr;
        ctx.async_pending_query_len = query_owned.len;
    }

    fn launchPendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator) bool {
        const query_owned = takePendingAsyncQuery(ctx) orelse return false;
        const generation = ctx.async_search_generation;
        if (!spawnAsyncRouteSearchWorker(ctx, allocator, generation, query_owned)) {
            allocator.free(query_owned);
            endAsyncSpinner(ctx);
            return false;
        }
        return true;
    }

    fn takePendingAsyncQuery(ctx: *UiContext) ?[]u8 {
        const ptr = ctx.async_pending_query_ptr orelse return null;
        const slice = ptr[0..ctx.async_pending_query_len];
        ctx.async_pending_query_ptr = null;
        ctx.async_pending_query_len = 0;
        return slice;
    }

    fn freePendingAsyncQuery(ctx: *UiContext) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        if (ctx.async_pending_query_ptr) |ptr| {
            allocator.free(ptr[0..ctx.async_pending_query_len]);
            ctx.async_pending_query_ptr = null;
            ctx.async_pending_query_len = 0;
        }
    }

    fn beginAsyncSpinner(ctx: *UiContext) void {
        ctx.async_inflight = GTRUE;
        if (ctx.async_spinner_id != 0) {
            _ = c.g_source_remove(ctx.async_spinner_id);
            ctx.async_spinner_id = 0;
        }
        ctx.async_spinner_phase = 0;
        updateAsyncSpinnerFrame(ctx);
        ctx.async_spinner_id = c.g_timeout_add(120, onAsyncSpinnerTick, ctx);
    }

    fn endAsyncSpinner(ctx: *UiContext) void {
        ctx.async_inflight = GFALSE;
        if (ctx.async_spinner_id != 0) {
            _ = c.g_source_remove(ctx.async_spinner_id);
            ctx.async_spinner_id = 0;
        }
        clearAsyncRows(ctx.list);
    }

    fn onAsyncSpinnerTick(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        if (ctx.async_inflight == GFALSE) {
            ctx.async_spinner_id = 0;
            return GFALSE;
        }
        updateAsyncSpinnerFrame(ctx);
        return GTRUE;
    }

    fn updateAsyncSpinnerFrame(ctx: *UiContext) void {
        const frames = [_][]const u8{ "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⠋", "⠙" };
        const frame = frames[ctx.async_spinner_phase % frames.len];
        ctx.async_spinner_phase +%= 1;

        var status_buf: [40]u8 = undefined;
        const status_msg = std.fmt.bufPrint(&status_buf, "{s} Searching...", .{frame}) catch "Searching...";
        clearAsyncRows(ctx.list);
        appendAsyncRow(ctx.list, frame, "Searching modules...");
        if (ctx.pending_power_confirm == GFALSE) setStatus(ctx, status_msg);
    }

    fn appendAsyncRow(list: *c.GtkListBox, frame: []const u8, message: []const u8) void {
        const markup = std.fmt.allocPrint(
            std.heap.page_allocator,
            "<span foreground=\"#b5d6ff\" size=\"x-large\" weight=\"700\">{s}</span> <span foreground=\"#aeb8cc\">{s}</span>",
            .{ frame, message },
        ) catch return;
        defer std.heap.page_allocator.free(markup);
        const markup_z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
        defer std.heap.page_allocator.free(markup_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-async-search");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.g_object_set_data_full(@ptrCast(row), "gs-async", c.g_strdup("1"), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn clearAsyncRows(list: *c.GtkListBox) void {
        var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            if (c.g_object_get_data(@ptrCast(child), "gs-async") != null) {
                c.gtk_list_box_remove(list, child);
            }
            child = next;
        }
    }

    fn freeAsyncSearchResult(allocator: std.mem.Allocator, payload: *AsyncSearchResult) void {
        allocator.free(payload.query);
        for (payload.rows) |row| {
            if (row.title.len > 0) allocator.free(row.title);
            if (row.subtitle.len > 0) allocator.free(row.subtitle);
            if (row.action.len > 0) allocator.free(row.action);
            if (row.icon.len > 0) allocator.free(row.icon);
        }
        if (payload.rows.len > 0) allocator.free(payload.rows);
        allocator.destroy(payload);
    }

    fn appendModuleFilterMenu(ctx: *UiContext, allocator: std.mem.Allocator) void {
        appendHeaderRow(ctx.list, "Module Filters");
        appendInfoRow(ctx.list, "Select a module (Enter) or type directly for blended search.");
        appendLegendRow(ctx.list, "Hotkeys: Enter select | Ctrl+L focus | PgUp/PgDn move | Home/End jump | Ctrl+R refresh | Esc close");

        appendModuleFilterRow(ctx.list, allocator, "Apps", "Filter installed applications", "@", .app);
        appendModuleFilterRow(ctx.list, allocator, "Windows", "Filter open windows", "#", .window);
        appendModuleFilterRow(ctx.list, allocator, "Directories", "Filter recent directories", "~", .dir);
        appendModuleFilterRow(ctx.list, allocator, "Files", "Advanced file finder (fd)", "%", .file);
        appendModuleFilterRow(ctx.list, allocator, "Code Search", "Text search (rg)", "&", .grep);
        appendModuleFilterRow(ctx.list, allocator, "Run", "Run command route", ">", .action);
        appendModuleFilterRow(ctx.list, allocator, "Calc", "Calculator route", "=", .action);
        appendModuleFilterRow(ctx.list, allocator, "Web", "Web search route", "?", .action);
    }

    fn appendModuleFilterRow(
        list: *c.GtkListBox,
        allocator: std.mem.Allocator,
        title: []const u8,
        subtitle: []const u8,
        route: []const u8,
        kind: CandidateKind,
    ) void {
        const title_markup = std.fmt.allocPrint(allocator, "<span weight=\"600\">{s}</span>", .{title}) catch return;
        defer allocator.free(title_markup);
        const title_markup_z = allocator.dupeZ(u8, title_markup) catch return;
        defer allocator.free(title_markup_z);

        const primary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(primary_label), title_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
        c.gtk_widget_set_hexpand(primary_label, GTRUE);
        c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

        const icon_text_z = allocator.dupeZ(u8, kindIcon(kind)) catch return;
        defer allocator.free(icon_text_z);
        const icon = c.gtk_label_new(icon_text_z.ptr);
        c.gtk_widget_add_css_class(icon, "gs-kind-icon");
        c.gtk_widget_set_valign(icon, c.GTK_ALIGN_CENTER);

        const chip = kindChipWidget(kind);
        c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);

        const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
        c.gtk_box_append(@ptrCast(primary_row), primary_label);
        c.gtk_box_append(@ptrCast(primary_row), chip);

        const subtitle_z = allocator.dupeZ(u8, subtitle) catch return;
        defer allocator.free(subtitle_z);
        const secondary_label = c.gtk_label_new(subtitle_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
        c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
        c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

        const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
        c.gtk_widget_set_margin_top(text_col, 2);
        c.gtk_widget_set_margin_bottom(text_col, 2);
        c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
        c.gtk_box_append(@ptrCast(text_col), primary_row);
        c.gtk_box_append(@ptrCast(text_col), secondary_label);

        const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(content, "gs-entry-layout");
        c.gtk_box_append(@ptrCast(content), icon);
        c.gtk_box_append(@ptrCast(content), text_col);

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-actionable-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), content);

        const kind_z = allocator.dupeZ(u8, "module") catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, route) catch return;
        defer allocator.free(action_z);
        const title_z = allocator.dupeZ(u8, title) catch return;
        defer allocator.free(title_z);
        c.g_object_set_data_full(@ptrCast(row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendInfoRow(list: *c.GtkListBox, message: []const u8) void {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_text(@ptrCast(label), msg_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-info");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendLegendRow(list: *c.GtkListBox, message: []const u8) void {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_text(@ptrCast(label), msg_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-legend");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn refreshSnapshot(ctx: *UiContext) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        ctx.service.invalidateSnapshot();
        ctx.service.prewarmProviders(allocator) catch return;

        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        if (text_ptr == null) {
            populateResults(ctx, "");
            return;
        }
        const query = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
        populateResults(ctx, query);
    }

    fn appendGroupedRows(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        rows: []const @import("../search/mod.zig").ScoredCandidate,
        highlight_token: []const u8,
    ) void {
        var rendered_any = false;
        rendered_any = appendGroup(ctx, allocator, rows, .app, "Apps", rendered_any, highlight_token) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .window, "Windows", rendered_any, highlight_token) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .dir, "Directories", rendered_any, highlight_token) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .file, "Files", rendered_any, highlight_token) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .grep, "Code Search", rendered_any, highlight_token) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .action, "Actions", rendered_any, highlight_token) or rendered_any;
        _ = appendGroup(ctx, allocator, rows, .hint, "Hints", rendered_any, highlight_token);
    }

    fn appendGroup(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        rows: []const @import("../search/mod.zig").ScoredCandidate,
        kind: CandidateKind,
        title: []const u8,
        add_separator: bool,
        highlight_token: []const u8,
    ) bool {
        var match_count: usize = 0;
        for (rows) |row| {
            if (row.candidate.kind == kind) {
                match_count += 1;
            }
        }
        if (match_count == 0) return false;

        if (add_separator) appendSectionSeparatorRow(ctx.list);
        var header_buf: [96]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "{s} ({d})", .{ title, match_count }) catch title;
        appendHeaderRow(ctx.list, header);
        for (rows) |row| {
            if (row.candidate.kind != kind) continue;
            appendCandidateRow(ctx.list, allocator, row, highlight_token);
        }
        return true;
    }

    fn appendHeaderRow(list: *c.GtkListBox, title: []const u8) void {
        const title_escaped = c.g_markup_escape_text(title.ptr, @intCast(title.len));
        if (title_escaped == null) return;
        defer c.g_free(title_escaped);

        const markup = std.fmt.allocPrint(std.heap.page_allocator, "<b>{s}</b>", .{std.mem.span(@as([*:0]const u8, @ptrCast(title_escaped)))}) catch return;
        defer std.heap.page_allocator.free(markup);
        const markup_z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
        defer std.heap.page_allocator.free(markup_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-header");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendSectionSeparatorRow(list: *c.GtkListBox) void {
        const separator = c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL);
        c.gtk_widget_add_css_class(separator, "gs-separator");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), separator);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendCandidateRow(
        list: *c.GtkListBox,
        allocator: std.mem.Allocator,
        row: @import("../search/mod.zig").ScoredCandidate,
        highlight_token: []const u8,
    ) void {
        const title_markup = highlightedMarkup(allocator, row.candidate.title, highlight_token) catch return;
        defer allocator.free(title_markup);
        const primary_markup = std.fmt.allocPrint(
            allocator,
            "<span weight=\"600\">{s}</span>",
            .{
                title_markup,
            },
        ) catch return;
        defer allocator.free(primary_markup);
        const primary_markup_z = allocator.dupeZ(u8, primary_markup) catch return;
        defer allocator.free(primary_markup_z);

        const primary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(primary_label), primary_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
        c.gtk_widget_set_hexpand(primary_label, GTRUE);
        c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

        const icon_widget = candidateIconWidget(allocator, row.candidate.kind, row.candidate.action, row.candidate.icon);
        c.gtk_widget_set_valign(icon_widget, c.GTK_ALIGN_CENTER);
        const chip = kindChipWidget(row.candidate.kind);
        c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);
        const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
        c.gtk_box_append(@ptrCast(primary_row), primary_label);
        c.gtk_box_append(@ptrCast(primary_row), chip);

        const subtitle_markup = highlightedMarkup(allocator, row.candidate.subtitle, highlight_token) catch return;
        defer allocator.free(subtitle_markup);
        const subtitle_markup_z = allocator.dupeZ(u8, subtitle_markup) catch return;
        defer allocator.free(subtitle_markup_z);
        const secondary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(secondary_label), subtitle_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
        c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
        c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

        const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
        c.gtk_widget_set_margin_top(text_col, 2);
        c.gtk_widget_set_margin_bottom(text_col, 2);
        c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
        c.gtk_widget_set_hexpand(text_col, GTRUE);
        c.gtk_box_append(@ptrCast(text_col), primary_row);
        c.gtk_box_append(@ptrCast(text_col), secondary_label);

        const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(content, "gs-entry-layout");
        c.gtk_box_append(@ptrCast(content), icon_widget);
        c.gtk_box_append(@ptrCast(content), text_col);

        const list_row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(list_row, "gs-actionable-row");
        c.gtk_list_box_row_set_child(@ptrCast(list_row), content);

        const kind = kindTag(row.candidate.kind);
        const kind_c = std.fmt.allocPrint(allocator, "{s}", .{kind}) catch return;
        defer allocator.free(kind_c);
        const action_c = std.fmt.allocPrint(allocator, "{s}", .{row.candidate.action}) catch return;
        defer allocator.free(action_c);
        const title_c = std.fmt.allocPrint(allocator, "{s}", .{row.candidate.title}) catch return;
        defer allocator.free(title_c);
        const kind_z = allocator.dupeZ(u8, kind_c) catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, action_c) catch return;
        defer allocator.free(action_z);
        const title_z = allocator.dupeZ(u8, title_c) catch return;
        defer allocator.free(title_z);

        c.g_object_set_data_full(@ptrCast(list_row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(list_row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(list_row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
        const title_tip = allocator.dupeZ(u8, row.candidate.title) catch null;
        if (title_tip) |tip| {
            defer allocator.free(tip);
            c.gtk_widget_set_tooltip_text(primary_label, tip.ptr);
        }
        const subtitle_tip = allocator.dupeZ(u8, row.candidate.subtitle) catch null;
        if (subtitle_tip) |tip| {
            defer allocator.free(tip);
            c.gtk_widget_set_tooltip_text(secondary_label, tip.ptr);
        }
        c.gtk_list_box_append(@ptrCast(list), list_row);
    }

    fn clearList(list: *c.GtkListBox) void {
        var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_list_box_remove(list, child);
            child = next;
        }
    }

    fn executeSelected(ctx: *UiContext, kind: []const u8, action: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        if (!std.mem.eql(u8, kind, "dir_option") and !std.mem.eql(u8, kind, "file_option") and !std.mem.eql(u8, kind, "module")) {
            ctx.service.recordSelection(allocator, action) catch {};
        }

        if (std.mem.eql(u8, kind, "action")) {
            if (providers_mod.requiresConfirmation(action)) {
                if (ctx.pending_power_confirm == GFALSE) {
                    armPowerConfirmation(ctx);
                    emitTelemetry(ctx, "action", action, "guarded", "await-confirm");
                    return;
                }
                clearPowerConfirmation(ctx);
            } else {
                clearPowerConfirmation(ctx);
            }
            const cmd = providers_mod.resolveActionCommand(action) orelse {
                emitTelemetry(ctx, "action", action, "error", "unknown-action");
                showLaunchFeedback(ctx, "Action failed: unknown action");
                return;
            };
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "action", action, "error", "command-failed");
                showLaunchFeedback(ctx, "Action failed to launch");
                return;
            };
            emitTelemetry(ctx, "action", action, "ok", cmd);
            c.gtk_window_close(@ptrCast(ctx.window));
            return;
        }
        if (std.mem.eql(u8, kind, "dir_option")) {
            runShellCommand(action) catch {
                emitTelemetry(ctx, "dir", action, "error", "command-failed");
                showLaunchFeedback(ctx, "Directory action failed");
                return;
            };
            emitTelemetry(ctx, "dir", action, "ok", "option-command");
            c.gtk_window_close(@ptrCast(ctx.window));
            return;
        }
        if (std.mem.eql(u8, kind, "file_option")) {
            runShellCommand(action) catch {
                emitTelemetry(ctx, "file", action, "error", "command-failed");
                showLaunchFeedback(ctx, "File action failed");
                return;
            };
            emitTelemetry(ctx, "file", action, "ok", "option-command");
            c.gtk_window_close(@ptrCast(ctx.window));
            return;
        }
        if (std.mem.eql(u8, kind, "module")) {
            applyModuleFilter(ctx, allocator, action);
            return;
        }
        clearPowerConfirmation(ctx);
        if (std.mem.eql(u8, kind, "app")) {
            if (!std.mem.eql(u8, action, "__drun__")) {
                runShellCommand(action) catch {
                    emitTelemetry(ctx, "app", action, "error", "command-failed");
                    showLaunchFeedback(ctx, "App failed to launch");
                    return;
                };
                emitTelemetry(ctx, "app", action, "ok", action);
                c.gtk_window_close(@ptrCast(ctx.window));
            }
            return;
        }
        if (std.mem.eql(u8, kind, "dir")) {
            showDirActionMenu(ctx, allocator, action);
            return;
        }
        if (std.mem.eql(u8, kind, "file") or std.mem.eql(u8, kind, "grep")) {
            showFileActionMenu(ctx, allocator, action);
            return;
        }
        if (std.mem.eql(u8, kind, "window")) {
            const cmd = std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow \"address:{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "window", action, "error", "command-failed");
                showLaunchFeedback(ctx, "Window focus failed");
                return;
            };
            emitTelemetry(ctx, "window", action, "ok", cmd);
            c.gtk_window_close(@ptrCast(ctx.window));
            return;
        }
    }

    fn applyModuleFilter(ctx: *UiContext, allocator: std.mem.Allocator, module_action: []const u8) void {
        const route = std.mem.trim(u8, module_action, " \t\r\n");
        if (route.len == 0) return;
        const text = std.fmt.allocPrint(allocator, "{s} ", .{route}) catch return;
        defer allocator.free(text);
        const text_z = allocator.dupeZ(u8, text) catch return;
        defer allocator.free(text_z);

        clearPowerConfirmation(ctx);
        c.gtk_editable_set_text(@ptrCast(ctx.entry), text_z.ptr);
        c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
        const caret = c.gtk_editable_get_position(@ptrCast(ctx.entry));
        c.gtk_editable_select_region(@ptrCast(ctx.entry), caret, caret);
        _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(ctx.entry)));
        const status = std.fmt.allocPrint(allocator, "Module filter active: {s}", .{route}) catch return;
        defer allocator.free(status);
        setStatus(ctx, status);
    }

    fn showDirActionMenu(ctx: *UiContext, allocator: std.mem.Allocator, dir_path: []const u8) void {
        clearList(ctx.list);
        appendHeaderRow(ctx.list, "Directory Actions");
        const path_msg = std.fmt.allocPrint(allocator, "Target: {s}", .{dir_path}) catch return;
        defer allocator.free(path_msg);
        appendInfoRow(ctx.list, path_msg);
        appendInfoRow(ctx.list, "Enter to run selected action | Esc to close | Type to return to search");

        const term_cmd = buildDirTerminalCommand(allocator, dir_path) catch null;
        if (term_cmd) |cmd| {
            defer allocator.free(cmd);
            appendDirOptionRow(ctx.list, allocator, "Open Terminal Here", "Launch terminal in this folder", cmd);
        }

        const explorer_cmd = buildDirExplorerCommand(allocator, dir_path) catch null;
        if (explorer_cmd) |cmd| {
            defer allocator.free(cmd);
            appendDirOptionRow(ctx.list, allocator, "Open in File Explorer", "Use default file manager", cmd);
        }

        const editor_cmd = buildDirEditorCommand(allocator, dir_path) catch null;
        if (editor_cmd) |cmd| {
            defer allocator.free(cmd);
            appendDirOptionRow(ctx.list, allocator, "Open in Editor", "Use $VISUAL/$EDITOR fallback", cmd);
        }

        const copy_cmd = buildDirCopyPathCommand(allocator, dir_path) catch null;
        if (copy_cmd) |cmd| {
            defer allocator.free(cmd);
            appendDirOptionRow(ctx.list, allocator, "Copy Path", "Copy directory path to clipboard", cmd);
        }

        setStatus(ctx, "Directory action menu");
        selectFirstActionableRow(ctx);
    }

    fn appendDirOptionRow(list: *c.GtkListBox, allocator: std.mem.Allocator, title: []const u8, subtitle: []const u8, command: []const u8) void {
        const title_markup = std.fmt.allocPrint(allocator, "<span weight=\"600\">{s}</span>", .{title}) catch return;
        defer allocator.free(title_markup);
        const title_markup_z = allocator.dupeZ(u8, title_markup) catch return;
        defer allocator.free(title_markup_z);

        const primary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(primary_label), title_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
        c.gtk_widget_set_hexpand(primary_label, GTRUE);
        c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

        const icon_text_z = allocator.dupeZ(u8, kindIcon(.dir)) catch return;
        defer allocator.free(icon_text_z);
        const icon = c.gtk_label_new(icon_text_z.ptr);
        c.gtk_widget_add_css_class(icon, "gs-kind-icon");
        c.gtk_widget_set_valign(icon, c.GTK_ALIGN_CENTER);

        const chip = c.gtk_label_new("DIR".ptr);
        c.gtk_widget_add_css_class(chip, "gs-chip");
        c.gtk_widget_add_css_class(chip, "gs-chip-dir");
        c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);

        const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
        c.gtk_box_append(@ptrCast(primary_row), primary_label);
        c.gtk_box_append(@ptrCast(primary_row), chip);

        const subtitle_z = allocator.dupeZ(u8, subtitle) catch return;
        defer allocator.free(subtitle_z);
        const secondary_label = c.gtk_label_new(subtitle_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
        c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
        c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

        const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
        c.gtk_widget_set_margin_top(text_col, 2);
        c.gtk_widget_set_margin_bottom(text_col, 2);
        c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
        c.gtk_box_append(@ptrCast(text_col), primary_row);
        c.gtk_box_append(@ptrCast(text_col), secondary_label);

        const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(content, "gs-entry-layout");
        c.gtk_box_append(@ptrCast(content), icon);
        c.gtk_box_append(@ptrCast(content), text_col);

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-actionable-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), content);

        const kind_z = allocator.dupeZ(u8, "dir_option") catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, command) catch return;
        defer allocator.free(action_z);
        const title_z = allocator.dupeZ(u8, title) catch return;
        defer allocator.free(title_z);
        c.g_object_set_data_full(@ptrCast(row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn buildDirTerminalCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, dir_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'cd -- \"$1\" || exit 1; term=\"${{TERMINAL:-}}\"; if [ -n \"$term\" ] && command -v \"$term\" >/dev/null 2>&1; then exec \"$term\"; fi; for t in kitty alacritty footclient foot wezterm gnome-terminal konsole xfce4-terminal tilix xterm; do if command -v \"$t\" >/dev/null 2>&1; then exec \"$t\"; fi; done; exit 127' _ {s}",
            .{quoted},
        );
    }

    fn buildDirExplorerCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, dir_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
    }

    fn buildDirEditorCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, dir_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'if [ -n \"$VISUAL\" ]; then exec \"$VISUAL\" \"$1\"; elif [ -n \"$EDITOR\" ]; then exec \"$EDITOR\" \"$1\"; else exec xdg-open \"$1\"; fi' _ {s}",
            .{quoted},
        );
    }

    fn buildDirCopyPathCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, dir_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard' _ {s}",
            .{quoted},
        );
    }

    fn showFileActionMenu(ctx: *UiContext, allocator: std.mem.Allocator, file_action: []const u8) void {
        const parsed = parseFileAction(file_action);
        clearList(ctx.list);
        appendHeaderRow(ctx.list, "File Actions");
        const target_msg = std.fmt.allocPrint(allocator, "Target: {s}", .{parsed.path}) catch return;
        defer allocator.free(target_msg);
        appendInfoRow(ctx.list, target_msg);
        appendInfoRow(ctx.list, "Enter to run selected action | Esc to close | Type to return to search");

        const edit_cmd = buildFileEditCommand(allocator, parsed.path, parsed.line) catch null;
        if (edit_cmd) |cmd| {
            defer allocator.free(cmd);
            appendFileOptionRow(ctx.list, allocator, "Open in Editor", "Use $VISUAL/$EDITOR (line-aware when possible)", cmd);
        }

        const open_cmd = buildFileOpenCommand(allocator, parsed.path) catch null;
        if (open_cmd) |cmd| {
            defer allocator.free(cmd);
            appendFileOptionRow(ctx.list, allocator, "Open with Default App", "Use xdg-open", cmd);
        }

        const reveal_cmd = buildFileRevealCommand(allocator, parsed.path) catch null;
        if (reveal_cmd) |cmd| {
            defer allocator.free(cmd);
            appendFileOptionRow(ctx.list, allocator, "Reveal in File Explorer", "Open parent directory", cmd);
        }

        const copy_cmd = buildFileCopyPathCommand(allocator, parsed.path) catch null;
        if (copy_cmd) |cmd| {
            defer allocator.free(cmd);
            appendFileOptionRow(ctx.list, allocator, "Copy Path", "Copy file path to clipboard", cmd);
        }

        setStatus(ctx, "File action menu");
        selectFirstActionableRow(ctx);
    }

    fn appendFileOptionRow(list: *c.GtkListBox, allocator: std.mem.Allocator, title: []const u8, subtitle: []const u8, command: []const u8) void {
        const title_markup = std.fmt.allocPrint(allocator, "<span weight=\"600\">{s}</span>", .{title}) catch return;
        defer allocator.free(title_markup);
        const title_markup_z = allocator.dupeZ(u8, title_markup) catch return;
        defer allocator.free(title_markup_z);

        const primary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(primary_label), title_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
        c.gtk_widget_set_hexpand(primary_label, GTRUE);
        c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

        const icon_text_z = allocator.dupeZ(u8, kindIcon(.file)) catch return;
        defer allocator.free(icon_text_z);
        const icon = c.gtk_label_new(icon_text_z.ptr);
        c.gtk_widget_add_css_class(icon, "gs-kind-icon");
        c.gtk_widget_set_valign(icon, c.GTK_ALIGN_CENTER);

        const chip = c.gtk_label_new("FILE".ptr);
        c.gtk_widget_add_css_class(chip, "gs-chip");
        c.gtk_widget_add_css_class(chip, "gs-chip-file");
        c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);

        const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
        c.gtk_box_append(@ptrCast(primary_row), primary_label);
        c.gtk_box_append(@ptrCast(primary_row), chip);

        const subtitle_z = allocator.dupeZ(u8, subtitle) catch return;
        defer allocator.free(subtitle_z);
        const secondary_label = c.gtk_label_new(subtitle_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
        c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
        c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

        const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
        c.gtk_widget_set_margin_top(text_col, 2);
        c.gtk_widget_set_margin_bottom(text_col, 2);
        c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
        c.gtk_box_append(@ptrCast(text_col), primary_row);
        c.gtk_box_append(@ptrCast(text_col), secondary_label);

        const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(content, "gs-entry-layout");
        c.gtk_box_append(@ptrCast(content), icon);
        c.gtk_box_append(@ptrCast(content), text_col);

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-actionable-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), content);

        const kind_z = allocator.dupeZ(u8, "file_option") catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, command) catch return;
        defer allocator.free(action_z);
        const title_z = allocator.dupeZ(u8, title) catch return;
        defer allocator.free(title_z);
        c.g_object_set_data_full(@ptrCast(row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    const ParsedFileAction = struct {
        path: []const u8,
        line: ?[]const u8,
    };

    fn parseFileAction(file_action: []const u8) ParsedFileAction {
        if (std.mem.lastIndexOfScalar(u8, file_action, ':')) |idx| {
            if (idx + 1 < file_action.len) {
                const suffix = file_action[idx + 1 ..];
                if (isDigitsOnly(suffix)) {
                    return .{ .path = file_action[0..idx], .line = suffix };
                }
            }
        }
        return .{ .path = file_action, .line = null };
    }

    fn isDigitsOnly(value: []const u8) bool {
        if (value.len == 0) return false;
        for (value) |ch| {
            if (!std.ascii.isDigit(ch)) return false;
        }
        return true;
    }

    fn buildFileOpenCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, file_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
    }

    fn buildFileRevealCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
        const parent = std.fs.path.dirname(file_path) orelse file_path;
        const quoted = try shellSingleQuote(allocator, parent);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
    }

    fn buildFileCopyPathCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, file_path);
        defer allocator.free(quoted);
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard' _ {s}",
            .{quoted},
        );
    }

    fn buildFileEditCommand(allocator: std.mem.Allocator, file_path: []const u8, line: ?[]const u8) ![]u8 {
        const quoted = try shellSingleQuote(allocator, file_path);
        defer allocator.free(quoted);
        if (line) |line_num| {
            const line_q = try shellSingleQuote(allocator, line_num);
            defer allocator.free(line_q);
            return std.fmt.allocPrint(
                allocator,
                "sh -lc 'editor=\"${{VISUAL:-${{EDITOR:-}}}}\"; if [ -z \"$editor\" ]; then exec xdg-open \"$1\"; fi; case \"$editor\" in nvim|vim|vi|helix|hx|kak|nano) exec \"$editor\" +\"$2\" \"$1\" ;; code|codium|code-insiders) exec \"$editor\" --goto \"$1:$2\" ;; subl) exec \"$editor\" \"$1:$2\" ;; *) exec \"$editor\" \"$1\" ;; esac' _ {s} {s}",
                .{ quoted, line_q },
            );
        }
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'if [ -n \"$VISUAL\" ]; then exec \"$VISUAL\" \"$1\"; elif [ -n \"$EDITOR\" ]; then exec \"$EDITOR\" \"$1\"; else exec xdg-open \"$1\"; fi' _ {s}",
            .{quoted},
        );
    }

    fn shellSingleQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        try out.append(allocator, '\'');
        for (value) |ch| {
            if (ch == '\'') {
                try out.appendSlice(allocator, "'\\''");
            } else {
                try out.append(allocator, ch);
            }
        }
        try out.append(allocator, '\'');
        return out.toOwnedSlice(allocator);
    }

    fn showLaunchFeedback(ctx: *UiContext, message: []const u8) void {
        clearLaunchFeedbackRows(ctx.list);
        appendLaunchFeedbackRow(ctx.list, message);
        setStatusWithTone(ctx, postLaunchStatus(message), launchStatusTone(message));
        scheduleStatusReset(ctx);
        selectFirstActionableRow(ctx);
    }

    fn scheduleStatusReset(ctx: *UiContext) void {
        if (ctx.status_reset_id != 0) {
            _ = c.g_source_remove(ctx.status_reset_id);
            ctx.status_reset_id = 0;
        }
        ctx.status_reset_id = c.g_timeout_add(1700, onStatusReset, ctx);
    }

    fn onStatusReset(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        ctx.status_reset_id = 0;
        if (ctx.pending_power_confirm == GTRUE) return GFALSE;

        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
        const query_trimmed = std.mem.trim(u8, query, " \t\r\n");
        if (query_trimmed.len == 0) {
            setStatus(ctx, "Esc close | Ctrl+R refresh | @ apps # windows ~ dirs % files & grep > run = calc ? web");
        } else {
            setStatus(ctx, "");
        }
        return GFALSE;
    }

    fn clearLaunchFeedbackRows(list: *c.GtkListBox) void {
        var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            if (c.g_object_get_data(@ptrCast(child), "gs-feedback") != null) {
                c.gtk_list_box_remove(list, child);
            }
            child = next;
        }
    }

    fn appendLaunchFeedbackRow(list: *c.GtkListBox, message: []const u8) void {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);

        const label = c.gtk_label_new(msg_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-info");

        const row = c.gtk_list_box_row_new();
        c.gtk_widget_add_css_class(row, "gs-meta-row");
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.g_object_set_data_full(@ptrCast(row), "gs-feedback", c.g_strdup("1"), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn setStatus(ctx: *UiContext, message: []const u8) void {
        setStatusWithTone(ctx, message, launchStatusTone(message));
    }

    const StatusTone = enum {
        neutral,
        info,
        success,
        failure,
    };

    fn setStatusWithTone(ctx: *UiContext, message: []const u8, tone: StatusTone) void {
        const status_hash = std.hash.Wyhash.hash(0, message);
        const tone_code = statusToneCode(tone);
        if (ctx.last_status_hash == status_hash and ctx.last_status_tone == tone_code) return;

        const status_widget: *c.GtkWidget = @ptrCast(@alignCast(ctx.status));
        c.gtk_widget_remove_css_class(status_widget, "gs-status-info");
        c.gtk_widget_remove_css_class(status_widget, "gs-status-success");
        c.gtk_widget_remove_css_class(status_widget, "gs-status-failure");
        c.gtk_widget_remove_css_class(status_widget, "gs-status-searching");
        if (std.mem.indexOf(u8, message, "Searching") != null) {
            c.gtk_widget_add_css_class(status_widget, "gs-status-searching");
        }
        switch (tone) {
            .info => c.gtk_widget_add_css_class(status_widget, "gs-status-info"),
            .success => c.gtk_widget_add_css_class(status_widget, "gs-status-success"),
            .failure => c.gtk_widget_add_css_class(status_widget, "gs-status-failure"),
            .neutral => {},
        }
        const prefix = statusPrefix(tone);
        if (prefix.len > 0) {
            const composed = std.fmt.allocPrint(std.heap.page_allocator, "{s} {s}", .{ prefix, message }) catch return;
            defer std.heap.page_allocator.free(composed);
            const msg_z = std.heap.page_allocator.dupeZ(u8, composed) catch return;
            defer std.heap.page_allocator.free(msg_z);
            c.gtk_label_set_text(ctx.status, msg_z.ptr);
        } else {
            const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
            defer std.heap.page_allocator.free(msg_z);
            c.gtk_label_set_text(ctx.status, msg_z.ptr);
        }
        ctx.last_status_hash = status_hash;
        ctx.last_status_tone = tone_code;
    }

    fn installCss(window: *c.GtkWidget) void {
        const css =
            ".gs-status { color: #8b93a8; font-size: 0.92em; }\n" ++
            ".gs-status-info { color: #80a6d8; }\n" ++
            ".gs-status-success { color: #87c97f; }\n" ++
            ".gs-status-failure { color: #e58a8a; }\n" ++
            ".gs-status-searching { color: #c6e0ff; font-size: 1.02em; font-weight: 700; }\n" ++
            ".gs-header { color: #8b93a8; }\n" ++
            ".gs-info { color: #9aa1b5; }\n" ++
            ".gs-async-search { color: #aeb8cc; }\n" ++
            ".gs-legend { color: #7c8498; font-size: 0.88em; }\n" ++
            ".gs-separator { margin-top: 4px; margin-bottom: 4px; opacity: 0.3; }\n" ++
            ".gs-results-scroll, .gs-results-scroll > viewport { background: transparent; border: none; box-shadow: none; }\n" ++
            ".gs-results-scroll junction { background: transparent; border: none; box-shadow: none; }\n" ++
            ".gs-results-scroll undershoot.left, .gs-results-scroll undershoot.right { background-image: none; background: transparent; }\n" ++
            ".gs-results-scroll scrollbar { min-width: 8px; border: none; box-shadow: none; background: transparent; }\n" ++
            ".gs-results-scroll scrollbar separator { min-width: 0; min-height: 0; background: transparent; }\n" ++
            ".gs-results-scroll scrollbar trough { background: rgba(140, 170, 235, 0.14); border: none; box-shadow: none; border-radius: 999px; }\n" ++
            ".gs-results-scroll scrollbar slider { min-width: 8px; min-height: 24px; background: rgba(140, 170, 235, 0.30); border: none; box-shadow: none; border-radius: 999px; }\n" ++
            ".gs-results > row { background: transparent !important; background-color: transparent !important; background-image: none !important; border: none !important; padding: 4px 8px; border-radius: 8px; overflow: hidden; }\n" ++
            ".gs-results > row:selected,\n" ++
            ".gs-results > row:selected:focus,\n" ++
            ".gs-results > row:selected:focus-visible,\n" ++
            ".gs-results > row:selected:backdrop,\n" ++
            ".gs-results > row:hover,\n" ++
            ".gs-results > row:focus,\n" ++
            ".gs-results > row:focus-visible,\n" ++
            ".gs-results > row:focus-within { background: transparent !important; background-color: transparent !important; background-image: none !important; border: none !important; box-shadow: none !important; outline: none !important; }\n" ++
            ".gs-results > row > box { border-radius: 8px; }\n" ++
            ".gs-results.gs-scroll-active > row > box { margin-right: 12px; }\n" ++
            ".gs-results.gs-scroll-active .gs-kind-icon { margin-left: -2px; }\n" ++
            ".gs-results > row.gs-actionable-row { transition: background-color 130ms ease, border-color 130ms ease, opacity 120ms ease; }\n" ++
            ".gs-results > row.gs-meta-row { padding-top: 2px; padding-bottom: 2px; }\n" ++
            ".gs-results > row.gs-actionable-row:hover > box,\n" ++
            ".gs-results > row.gs-actionable-row:selected > box,\n" ++
            ".gs-results > row.gs-actionable-row:selected:focus > box,\n" ++
            ".gs-results > row.gs-actionable-row:selected:focus-visible > box,\n" ++
            ".gs-results > row.gs-actionable-row:focus > box,\n" ++
            ".gs-results > row.gs-actionable-row:focus-visible > box,\n" ++
            ".gs-results > row.gs-actionable-row:focus-within > box {\n" ++
            "  background: rgba(140, 170, 235, 0.20);\n" ++
            "  border: 1px solid rgba(164, 192, 255, 0.55);\n" ++
            "  border-radius: 8px;\n" ++
            "  outline: none;\n" ++
            "  box-shadow: none;\n" ++
            "}\n" ++
            ".gs-results > row.gs-actionable-row:selected .gs-candidate-primary { color: #f5f8ff; }\n" ++
            ".gs-results > row.gs-actionable-row:selected .gs-candidate-secondary { color: #d6def1; }\n" ++
            ".gs-kind-icon { color: #a9b1c7; font-size: 2.35em; margin-left: 6px; margin-right: 8px; }\n" ++
            ".gs-candidate-primary { color: #e8ecf7; transition: color 120ms ease; }\n" ++
            ".gs-candidate-secondary { color: #9aa1b5; font-size: 0.92em; transition: color 120ms ease; }\n" ++
            ".gs-entry-layout > .gs-candidate-content { min-width: 0; }\n" ++
            ".gs-primary-row { min-height: 20px; }\n" ++
            ".gs-chip { font-size: 0.72em; font-weight: 700; letter-spacing: 0.03em; padding: 2px 8px; border-radius: 999px; }\n" ++
            ".gs-chip-app { color: #7fb0ff; background: rgba(127, 176, 255, 0.16); }\n" ++
            ".gs-chip-window { color: #78d2c7; background: rgba(120, 210, 199, 0.16); }\n" ++
            ".gs-chip-dir { color: #ddb26f; background: rgba(221, 178, 111, 0.16); }\n" ++
            ".gs-chip-file { color: #8bc3ff; background: rgba(139, 195, 255, 0.16); }\n" ++
            ".gs-chip-grep { color: #b8a6ff; background: rgba(184, 166, 255, 0.16); }\n" ++
            ".gs-chip-action { color: #f18cb6; background: rgba(241, 140, 182, 0.16); }\n" ++
            ".gs-chip-hint { color: #9aa1b5; background: rgba(154, 161, 181, 0.16); }\n";

        const provider = c.gtk_css_provider_new();
        defer c.g_object_unref(provider);
        c.gtk_css_provider_load_from_data(provider, css.ptr, @intCast(css.len));

        const display = c.gtk_widget_get_display(window);
        if (display != null) {
            c.gtk_style_context_add_provider_for_display(
                display,
                @ptrCast(provider),
                c.GTK_STYLE_PROVIDER_PRIORITY_USER,
            );
        }
    }

    fn routeHintForQuery(query_trimmed: []const u8) ?[]const u8 {
        if (query_trimmed.len != 1) return null;
        return switch (query_trimmed[0]) {
            '@' => "Apps route active: type app name after @",
            '#' => "Windows route active: type window title/class after #",
            '~' => "Directories route active: type folder name after ~",
            '%' => "Files route active: type file name after %",
            '&' => "Grep route active: type text to search after &",
            '>' => "Run route active: type command after >",
            '=' => "Calc route active: type expression after =",
            '?' => "Web route active: type search terms after ?",
            else => null,
        };
    }

    fn highlightTokenForQuery(query_trimmed: []const u8) []const u8 {
        var token = std.mem.trim(u8, query_trimmed, " \t\r\n");
        if (token.len == 0) return "";
        if (token.len > 1) {
            token = switch (token[0]) {
                '@', '#', '~', '%', '&', '>', '=', '?' => std.mem.trim(u8, token[1..], " \t\r\n"),
                else => token,
            };
        }
        return token;
    }

    fn highlightedMarkup(allocator: std.mem.Allocator, text: []const u8, token: []const u8) ![]u8 {
        if (text.len == 0) return allocator.dupe(u8, "");

        const trimmed_token = std.mem.trim(u8, token, " \t\r\n");
        if (trimmed_token.len == 0) return escapeMarkupAlloc(allocator, text);

        const idx = firstCaseInsensitiveIndex(text, trimmed_token) orelse return escapeMarkupAlloc(allocator, text);
        const head = try escapeMarkupAlloc(allocator, text[0..idx]);
        defer allocator.free(head);
        const hit = try escapeMarkupAlloc(allocator, text[idx .. idx + trimmed_token.len]);
        defer allocator.free(hit);
        const tail = try escapeMarkupAlloc(allocator, text[idx + trimmed_token.len ..]);
        defer allocator.free(tail);

        return std.fmt.allocPrint(allocator, "{s}<b>{s}</b>{s}", .{ head, hit, tail });
    }

    fn escapeMarkupAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        const escaped_ptr = c.g_markup_escape_text(text.ptr, @intCast(text.len));
        if (escaped_ptr == null) return error.OutOfMemory;
        defer c.g_free(escaped_ptr);
        const escaped = std.mem.span(@as([*:0]const u8, @ptrCast(escaped_ptr)));
        return allocator.dupe(u8, escaped);
    }

    fn firstCaseInsensitiveIndex(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0 or haystack.len < needle.len) return null;
        var idx: usize = 0;
        while (idx + needle.len <= haystack.len) : (idx += 1) {
            if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
        }
        return null;
    }

    fn kindStatusLabel(kind: []const u8) []const u8 {
        if (std.mem.eql(u8, kind, "app")) return "app";
        if (std.mem.eql(u8, kind, "window")) return "window";
        if (std.mem.eql(u8, kind, "dir")) return "directory";
        if (std.mem.eql(u8, kind, "file")) return "file";
        if (std.mem.eql(u8, kind, "grep")) return "match";
        if (std.mem.eql(u8, kind, "module")) return "module filter";
        if (std.mem.eql(u8, kind, "action")) return "action";
        if (std.mem.eql(u8, kind, "hint")) return "hint";
        return "item";
    }

    fn postLaunchStatus(message: []const u8) []const u8 {
        if (std.mem.eql(u8, message, "Action launched")) return "Action launched | Enter repeats selected action";
        if (std.mem.eql(u8, message, "App launched")) return "App launched | Enter repeats selected app";
        if (std.mem.eql(u8, message, "Directory opened")) return "Directory opened | Enter repeats selected item";
        if (std.mem.eql(u8, message, "Window focused")) return "Window focused | Enter repeats selected window";
        return message;
    }

    fn launchStatusTone(message: []const u8) StatusTone {
        if (std.mem.indexOf(u8, message, "Searching") != null) return .info;
        if (std.mem.indexOf(u8, message, "Refresh") != null) return .info;
        if (std.mem.indexOf(u8, message, "fallback") != null) return .info;
        if (std.mem.indexOf(u8, message, "failed") != null) return .failure;
        if (std.mem.indexOf(u8, message, "launched") != null) return .success;
        if (std.mem.indexOf(u8, message, "opened") != null) return .success;
        if (std.mem.indexOf(u8, message, "focused") != null) return .success;
        return .neutral;
    }

    fn statusToneCode(tone: StatusTone) u8 {
        return switch (tone) {
            .neutral => 0,
            .info => 1,
            .success => 2,
            .failure => 3,
        };
    }

    fn statusPrefix(tone: StatusTone) []const u8 {
        return switch (tone) {
            .neutral => "",
            .info => "[i]",
            .success => "[ok]",
            .failure => "[!]",
        };
    }

    fn candidateIconWidget(allocator: std.mem.Allocator, kind: CandidateKind, action: []const u8, icon: []const u8) *c.GtkWidget {
        if (kind == .app) {
            if (resolveAppIconName(allocator, icon, action)) |icon_name_z| {
                defer allocator.free(icon_name_z);
                const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
                c.gtk_image_set_pixel_size(@ptrCast(image), 30);
                c.gtk_widget_add_css_class(image, "gs-kind-icon");
                return @ptrCast(image);
            }
        }

        const fallback_icon_z = allocator.dupeZ(u8, kindIcon(kind)) catch return c.gtk_label_new(null);
        defer allocator.free(fallback_icon_z);
        const icon_label = c.gtk_label_new(fallback_icon_z.ptr);
        c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
        return @ptrCast(icon_label);
    }

    fn appIconNameFromAction(allocator: std.mem.Allocator, action: []const u8) ?[:0]u8 {
        const token = actionCommandToken(action);
        if (token.len == 0) return null;
        return allocator.dupeZ(u8, token) catch null;
    }

    fn resolveAppIconName(allocator: std.mem.Allocator, icon: []const u8, action: []const u8) ?[:0]u8 {
        const explicit = std.mem.trim(u8, icon, " \t\r\n");
        if (explicit.len > 0) {
            if (resolveIconVariant(allocator, explicit)) |name| return name;
        }
        if (appIconNameFromAction(allocator, action)) |token_name| {
            defer allocator.free(token_name);
            if (resolveIconVariant(allocator, token_name)) |name| return name;
        }
        return null;
    }

    fn resolveIconVariant(allocator: std.mem.Allocator, raw_name: []const u8) ?[:0]u8 {
        var name = std.mem.trim(u8, raw_name, " \t\r\n\"'");
        if (name.len == 0) return null;

        var candidates: [6][]const u8 = undefined;
        var count: usize = 0;
        candidates[count] = name;
        count += 1;

        if (std.mem.lastIndexOfScalar(u8, name, '/')) |slash_idx| {
            if (slash_idx + 1 < name.len) {
                const base = name[slash_idx + 1 ..];
                candidates[count] = base;
                count += 1;
                name = base;
            }
        }

        if (std.mem.endsWith(u8, name, ".desktop") and name.len > ".desktop".len) {
            candidates[count] = name[0 .. name.len - ".desktop".len];
            count += 1;
        }
        if (std.mem.endsWith(u8, name, "-desktop") and name.len > "-desktop".len) {
            candidates[count] = name[0 .. name.len - "-desktop".len];
            count += 1;
        }

        if (count > 1 and std.mem.endsWith(u8, candidates[count - 1], ".desktop") and candidates[count - 1].len > ".desktop".len) {
            candidates[count] = candidates[count - 1][0 .. candidates[count - 1].len - ".desktop".len];
            count += 1;
        }

        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            const candidate = candidates[idx];
            if (candidate.len == 0) continue;
            if (iconExists(candidate)) {
                return allocator.dupeZ(u8, candidate) catch null;
            }
        }

        // If theme inspection is unavailable, keep best-effort fallback.
        return allocator.dupeZ(u8, candidates[0]) catch null;
    }

    fn iconExists(name: []const u8) bool {
        const display = c.gdk_display_get_default();
        if (display == null) return false;
        const theme = c.gtk_icon_theme_get_for_display(display);
        if (theme == null) return false;
        const name_z = std.heap.page_allocator.dupeZ(u8, name) catch return false;
        defer std.heap.page_allocator.free(name_z);
        return c.gtk_icon_theme_has_icon(theme, name_z.ptr) != 0;
    }

    fn actionCommandToken(action: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, action, " \t\r\n");
        if (trimmed.len == 0) return "";

        var words = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
        while (words.next()) |word_raw| {
            var word = std.mem.trim(u8, word_raw, "\"'");
            if (word.len == 0) continue;
            if (std.mem.eql(u8, word, "env")) continue;
            if (word[0] == '%') continue;
            if (word[0] == '-') continue;
            if (std.mem.indexOfScalar(u8, word, '=') != null and word[0] != '/' and !std.mem.startsWith(u8, word, "./")) continue;

            if (std.mem.lastIndexOfScalar(u8, word, '/')) |slash_idx| {
                if (slash_idx + 1 < word.len) word = word[slash_idx + 1 ..];
            }
            return word;
        }
        return "";
    }

    fn hasAppGlyphFallback(rows: []const @import("../search/mod.zig").ScoredCandidate) bool {
        for (rows) |row| {
            if (row.candidate.kind != .app) continue;
            if (std.mem.trim(u8, row.candidate.icon, " \t\r\n").len > 0) continue;
            if (actionCommandToken(row.candidate.action).len == 0) return true;
        }
        return false;
    }

    fn runShellCommand(command: []const u8) !void {
        const command_z = try std.heap.page_allocator.dupeZ(u8, command);
        defer std.heap.page_allocator.free(command_z);

        var gerr: ?*c.GError = null;
        const ok = c.g_spawn_command_line_async(command_z.ptr, &gerr);
        if (ok == 0) {
            if (gerr != null) c.g_error_free(gerr);
            return error.CommandFailed;
        }
    }

    fn armPowerConfirmation(ctx: *UiContext) void {
        ctx.pending_power_confirm = GTRUE;
        setStatus(ctx, "Press Enter again to confirm Power menu");
    }

    fn clearPowerConfirmation(ctx: *UiContext) void {
        if (ctx.pending_power_confirm == GFALSE) return;
        ctx.pending_power_confirm = GFALSE;
        setStatus(ctx, "");
    }

    fn emitTelemetry(ctx: *UiContext, kind: []const u8, action: []const u8, status: []const u8, detail: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        ctx.telemetry.emitActionEvent(allocator_ptr.*, kind, action, status, detail) catch {};
    }

    fn kindTag(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "app",
            .window => "window",
            .dir => "dir",
            .file => "file",
            .grep => "grep",
            .action => "action",
            .hint => "hint",
        };
    }

    fn kindIcon(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "󰀻",
            .window => "",
            .dir => "󰉋",
            .file => "󰈙",
            .grep => "󰍉",
            .action => "",
            .hint => "󰘥",
        };
    }

    fn kindChipWidget(kind: @import("../search/mod.zig").CandidateKind) *c.GtkWidget {
        const label = c.gtk_label_new(kindChipText(kind).ptr);
        c.gtk_widget_add_css_class(label, "gs-chip");
        switch (kind) {
            .app => c.gtk_widget_add_css_class(label, "gs-chip-app"),
            .window => c.gtk_widget_add_css_class(label, "gs-chip-window"),
            .dir => c.gtk_widget_add_css_class(label, "gs-chip-dir"),
            .file => c.gtk_widget_add_css_class(label, "gs-chip-file"),
            .grep => c.gtk_widget_add_css_class(label, "gs-chip-grep"),
            .action => c.gtk_widget_add_css_class(label, "gs-chip-action"),
            .hint => c.gtk_widget_add_css_class(label, "gs-chip-hint"),
        }
        return @ptrCast(label);
    }

    fn kindChipText(kind: @import("../search/mod.zig").CandidateKind) [:0]const u8 {
        return switch (kind) {
            .app => "APP",
            .window => "WIN",
            .dir => "DIR",
            .file => "FILE",
            .grep => "GREP",
            .action => "ACT",
            .hint => "TIP",
        };
    }
};
