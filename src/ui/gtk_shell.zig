const std = @import("std");
const app_mod = @import("../app/mod.zig");
const providers_mod = @import("../providers/mod.zig");
const gtk_types = @import("gtk/types.zig");
const gtk_styles = @import("gtk/styles.zig");
const gtk_widgets = @import("gtk/widgets.zig");
const gtk_actions = @import("gtk/actions.zig");
const gtk_nav = @import("gtk/navigation.zig");
const gtk_query = @import("gtk/query_helpers.zig");
const gtk_async = @import("gtk/async_state.zig");
const gtk_async_search = @import("gtk/async_search.zig");
const gtk_render = @import("gtk/render.zig");
const gtk_menus = @import("gtk/menus.zig");
const gtk_status = @import("gtk/status.zig");
const gtk_icons = @import("gtk/icons.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
};

const UiContext = gtk_types.UiContext;
const AsyncSearchResult = gtk_async.AsyncSearchResult;

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
        gtk_nav.updateScrollbarActiveClass(ctx);
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
        gtk_async.freePendingAsyncQuery(ctx);
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
                gtk_nav.selectActionableDelta(ctx, 1);
                return GTRUE;
            },
            c.GDK_KEY_Up => {
                gtk_nav.selectActionableDelta(ctx, -1);
                return GTRUE;
            },
            c.GDK_KEY_Page_Down => {
                gtk_nav.selectActionableDelta(ctx, 5);
                return GTRUE;
            },
            c.GDK_KEY_Page_Up => {
                gtk_nav.selectActionableDelta(ctx, -5);
                return GTRUE;
            },
            c.GDK_KEY_Home => {
                gtk_nav.selectFirstActionableRow(ctx);
                return GTRUE;
            },
            c.GDK_KEY_End => {
                gtk_nav.selectLastActionableRow(ctx);
                return GTRUE;
            },
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                gtk_nav.activateSelectedRow(ctx);
                return GTRUE;
            },
            else => return GFALSE,
        }
    }

    fn onEntryActivate(_: ?*c.GtkEntry, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        gtk_nav.activateSelectedRow(ctx);
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
        gtk_nav.updateScrollbarActiveClass(ctx);
    }

    fn searchDebounceMsForQuery(query_trimmed: []const u8) c.guint {
        return gtk_query.searchDebounceMsForQuery(query_trimmed);
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
        return gtk_query.routeIconForLeadingPrefix(query);
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
        const kind_label = gtk_query.kindStatusLabel(kind);
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const msg = std.fmt.allocPrint(allocator_ptr.*, "Enter launch {s}: {s}", .{ kind_label, title }) catch return;
        defer allocator_ptr.*.free(msg);
        setStatus(ctx, msg);
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
                setStatus(ctx, "Pick a module (Enter) or type directly for blended search");
            }
            gtk_nav.selectFirstActionableRow(ctx);
            return;
        }

        if (gtk_query.shouldAsyncRouteQuery(query_trimmed)) {
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
        gtk_nav.selectFirstActionableRow(ctx);
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
        const route_hint = gtk_query.routeHintForQuery(query_trimmed);
        const highlight_token = gtk_query.highlightTokenForQuery(query_trimmed);
        const has_app_glyph_fallback = gtk_icons.hasAppGlyphFallback(rows);
        const render_hash = gtk_render.computeRenderHash(query_trimmed, route_hint, rows, ranked.len);
        if (ctx.last_render_hash != render_hash) {
            clearList(ctx.list);
            if (route_hint) |hint| {
                appendInfoRow(ctx.list, hint);
            }
            if (rows.len == 0 and !empty_query and route_hint == null) {
                appendInfoRow(ctx.list, "No results");
                appendInfoRow(ctx.list, "Try routes: @ apps  # windows  ~ dirs  % files  & grep  > run  = calc  ? web");
            } else {
                gtk_render.appendGroupedRows(ctx, allocator, rows, highlight_token, .{ .candidate_icon_widget = gtk_icons.candidateIconWidget });
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

    fn startAsyncRouteSearch(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
        gtk_async_search.startAsyncRouteSearch(
            ctx,
            allocator,
            query_trimmed,
            .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner },
            onAsyncSearchReady,
        );
    }

    fn onAsyncSearchReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const payload: *AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
        const ctx = payload.ctx;
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        defer gtk_async.freeAsyncSearchResult(allocator, payload);
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
        gtk_nav.selectFirstActionableRow(ctx);
        return GFALSE;
    }

    fn cancelAsyncRouteSearch(ctx: *UiContext) void {
        gtk_async_search.cancelAsyncRouteSearch(ctx, .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner });
    }

    fn launchPendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator) bool {
        return gtk_async_search.launchPendingAsyncQuery(
            ctx,
            allocator,
            .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner },
            onAsyncSearchReady,
        );
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
        gtk_widgets.appendAsyncRow(list, frame, message);
    }

    fn clearAsyncRows(list: *c.GtkListBox) void {
        gtk_widgets.clearAsyncRows(list);
    }

    fn appendModuleFilterMenu(ctx: *UiContext, allocator: std.mem.Allocator) void {
        gtk_widgets.appendModuleFilterMenu(ctx.list, allocator);
    }

    fn appendInfoRow(list: *c.GtkListBox, message: []const u8) void {
        gtk_widgets.appendInfoRow(list, message);
    }

    fn appendLegendRow(list: *c.GtkListBox, message: []const u8) void {
        gtk_widgets.appendLegendRow(list, message);
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


    fn appendHeaderRow(list: *c.GtkListBox, title: []const u8) void {
        gtk_widgets.appendHeaderRow(list, title);
    }

    fn appendSectionSeparatorRow(list: *c.GtkListBox) void {
        gtk_widgets.appendSectionSeparatorRow(list);
    }

    fn clearList(list: *c.GtkListBox) void {
        gtk_widgets.clearList(list);
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
        gtk_menus.showDirActionMenu(ctx, allocator, dir_path, .{
            .set_status = setStatus,
            .select_first = gtk_nav.selectFirstActionableRow,
        });
    }


    fn showFileActionMenu(ctx: *UiContext, allocator: std.mem.Allocator, file_action: []const u8) void {
        gtk_menus.showFileActionMenu(ctx, allocator, file_action, .{
            .set_status = setStatus,
            .select_first = gtk_nav.selectFirstActionableRow,
        });
    }

    fn showLaunchFeedback(ctx: *UiContext, message: []const u8) void {
        gtk_status.showLaunchFeedback(ctx, message, .{
            .select_first = gtk_nav.selectFirstActionableRow,
        });
    }

    fn setStatus(ctx: *UiContext, message: []const u8) void {
        gtk_status.setStatus(ctx, message);
    }

    fn installCss(window: *c.GtkWidget) void {
        gtk_styles.installCss(window);
    }

    fn runShellCommand(command: []const u8) !void {
        return gtk_actions.runShellCommand(command);
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

};
