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
    entry: *c.GtkSearchEntry,
    status: *c.GtkLabel,
    list: *c.GtkListBox,
    scroller: *c.GtkScrolledWindow,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    pending_power_confirm: c.gboolean,
    search_debounce_id: c.guint,
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

        const entry = c.gtk_search_entry_new();
        c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Type to search...");
        const status = c.gtk_label_new("Esc to close, Ctrl+R to refresh");
        c.gtk_label_set_xalign(@ptrCast(status), 0.0);
        c.gtk_widget_set_margin_bottom(status, 4);
        c.gtk_widget_add_css_class(status, "gs-status");

        const list = c.gtk_list_box_new();
        c.gtk_widget_add_css_class(list, "gs-results");
        c.gtk_list_box_set_selection_mode(@ptrCast(list), c.GTK_SELECTION_SINGLE);
        const scroller = c.gtk_scrolled_window_new();
        c.gtk_widget_set_vexpand(scroller, GTRUE);
        c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
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

        const key_controller = c.gtk_event_controller_key_new();
        _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(onKeyPressed), ctx, null, 0);
        c.gtk_widget_add_controller(window, @ptrCast(key_controller));
        _ = c.g_signal_connect_data(entry, "search-changed", c.G_CALLBACK(onSearchChanged), ctx, null, 0);
        _ = c.g_signal_connect_data(list, "row-activated", c.G_CALLBACK(onRowActivated), ctx, null, 0);
        _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(onDestroy), ctx, null, 0);

        c.gtk_box_append(@ptrCast(root_box), entry);
        c.gtk_box_append(@ptrCast(root_box), status);
        c.gtk_box_append(@ptrCast(root_box), scroller);
        c.gtk_window_set_child(@ptrCast(window), root_box);
        c.gtk_window_present(@ptrCast(window));

        populateResults(ctx, "");
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
        c.g_free(user_data);
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
            c.GDK_KEY_r, c.GDK_KEY_R => {
                if ((state & c.GDK_CONTROL_MASK) != 0) {
                    refreshSnapshot(ctx);
                    return GTRUE;
                }
                return GFALSE;
            },
            c.GDK_KEY_Down => {
                selectOffset(ctx, 1);
                return GTRUE;
            },
            c.GDK_KEY_Up => {
                selectOffset(ctx, -1);
                return GTRUE;
            },
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                const row = c.gtk_list_box_get_selected_row(ctx.list);
                if (row != null) c.g_signal_emit_by_name(ctx.list, "row-activated", row);
                return GTRUE;
            },
            else => return GFALSE,
        }
    }

    fn onSearchChanged(entry: ?*c.GtkSearchEntry, user_data: ?*anyopaque) callconv(.c) void {
        _ = entry;
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        clearPowerConfirmation(ctx);

        if (ctx.search_debounce_id != 0) {
            _ = c.g_source_remove(ctx.search_debounce_id);
            ctx.search_debounce_id = 0;
        }
        if (ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "Searching...");
        }
        ctx.search_debounce_id = c.g_timeout_add(90, onSearchDebounced, ctx);
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

    fn selectOffset(ctx: *UiContext, delta: i32) void {
        const selected = c.gtk_list_box_get_selected_row(ctx.list);
        if (selected == null) {
            selectFirstActionableRow(ctx);
            return;
        }

        var idx: i32 = c.gtk_list_box_row_get_index(selected) + delta;
        if (idx < 0) return;

        while (idx >= 0) : (idx += delta) {
            const target = c.gtk_list_box_get_row_at_index(ctx.list, idx);
            if (target == null) return;
            if (c.g_object_get_data(@ptrCast(target), "gs-action") != null) {
                c.gtk_list_box_select_row(ctx.list, target);
                ensureSelectedRowVisible(ctx);
                return;
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

    fn ensureSelectedRowVisible(ctx: *UiContext) void {
        const row = c.gtk_list_box_get_selected_row(ctx.list);
        if (row == null) return;

        const adjustment = c.gtk_scrolled_window_get_vadjustment(ctx.scroller);
        if (adjustment == null) return;

        const row_index = c.gtk_list_box_row_get_index(row);
        if (row_index < 0) return;

        const row_height: f64 = 44.0;
        const top = @as(f64, @floatFromInt(row_index)) * row_height;
        const bottom = top + row_height;
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

        clearList(ctx.list);
        const ranked = ctx.service.searchQuery(allocator, query) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Search failed: {s}", .{@errorName(err)}) catch "Search failed";
            defer if (!std.mem.eql(u8, msg, "Search failed")) allocator.free(msg);
            appendInfoRow(ctx.list, msg);
            setStatus(ctx, "Search failed");
            return;
        };
        defer allocator.free(ranked);

        const limit = @min(ranked.len, 20);
        const rows = ranked[0..limit];
        const empty_query = query_trimmed.len == 0;
        const route_hint = routeHintForQuery(query_trimmed);
        if (empty_query) {
            appendInfoRow(ctx.list, "Shortcuts: Enter launch | Ctrl+R refresh | Esc close");
        }
        if (route_hint) |hint| {
            appendInfoRow(ctx.list, hint);
        }
        if (rows.len == 0 and !empty_query and route_hint == null) {
            appendInfoRow(ctx.list, "No results");
        } else {
            appendGroupedRows(ctx, allocator, rows);
            if (ranked.len > limit) {
                appendInfoRow(ctx.list, "Showing top 20 results");
            }
        }
        if (ctx.service.last_query_used_stale_cache) {
            setStatus(ctx, "Refresh scheduled");
        } else if (ctx.service.last_query_refreshed_cache) {
            setStatus(ctx, "Snapshot refreshed");
        } else if (empty_query and ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "Esc to close, Ctrl+R to refresh");
        } else if (ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "");
        }

        _ = ctx.service.drainScheduledRefresh(allocator) catch false;
        selectFirstActionableRow(ctx);
    }

    fn appendInfoRow(list: *c.GtkListBox, message: []const u8) void {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_text(@ptrCast(label), msg_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        c.gtk_widget_add_css_class(label, "gs-info");

        const row = c.gtk_list_box_row_new();
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

    fn appendGroupedRows(ctx: *UiContext, allocator: std.mem.Allocator, rows: []const @import("../search/mod.zig").ScoredCandidate) void {
        var rendered_any = false;
        rendered_any = appendGroup(ctx, allocator, rows, .app, "Apps", rendered_any) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .window, "Windows", rendered_any) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .dir, "Directories", rendered_any) or rendered_any;
        rendered_any = appendGroup(ctx, allocator, rows, .action, "Actions", rendered_any) or rendered_any;
        _ = appendGroup(ctx, allocator, rows, .hint, "Hints", rendered_any);
    }

    fn appendGroup(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        rows: []const @import("../search/mod.zig").ScoredCandidate,
        kind: CandidateKind,
        title: []const u8,
        add_separator: bool,
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
            appendCandidateRow(ctx.list, allocator, row);
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
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendSectionSeparatorRow(list: *c.GtkListBox) void {
        const separator = c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL);
        c.gtk_widget_add_css_class(separator, "gs-separator");

        const row = c.gtk_list_box_row_new();
        c.gtk_list_box_row_set_child(@ptrCast(row), separator);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendCandidateRow(list: *c.GtkListBox, allocator: std.mem.Allocator, row: @import("../search/mod.zig").ScoredCandidate) void {
        const title_escaped = c.g_markup_escape_text(row.candidate.title.ptr, @intCast(row.candidate.title.len));
        if (title_escaped == null) return;
        defer c.g_free(title_escaped);
        const subtitle_escaped = c.g_markup_escape_text(row.candidate.subtitle.ptr, @intCast(row.candidate.subtitle.len));
        if (subtitle_escaped == null) return;
        defer c.g_free(subtitle_escaped);

        const icon = kindIcon(row.candidate.kind);
        const chip_markup = kindChipMarkup(row.candidate.kind);
        const primary_markup = std.fmt.allocPrint(
            allocator,
            "{s}  {s}  <b>{s}</b>",
            .{
                icon,
                chip_markup,
                std.mem.span(@as([*:0]const u8, @ptrCast(title_escaped))),
            },
        ) catch return;
        defer allocator.free(primary_markup);
        const primary_markup_z = allocator.dupeZ(u8, primary_markup) catch return;
        defer allocator.free(primary_markup_z);

        const primary_label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(primary_label), primary_markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
        c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

        const subtitle_text_z = allocator.dupeZ(u8, std.mem.span(@as([*:0]const u8, @ptrCast(subtitle_escaped)))) catch return;
        defer allocator.free(subtitle_text_z);
        const secondary_label = c.gtk_label_new(subtitle_text_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
        c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
        c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
        c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
        c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

        const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
        c.gtk_widget_set_margin_top(content, 2);
        c.gtk_widget_set_margin_bottom(content, 2);
        c.gtk_box_append(@ptrCast(content), primary_label);
        c.gtk_box_append(@ptrCast(content), secondary_label);

        const list_row = c.gtk_list_box_row_new();
        c.gtk_list_box_row_set_child(@ptrCast(list_row), content);

        const kind = kindTag(row.candidate.kind);
        const kind_c = std.fmt.allocPrint(allocator, "{s}", .{kind}) catch return;
        defer allocator.free(kind_c);
        const action_c = std.fmt.allocPrint(allocator, "{s}", .{row.candidate.action}) catch return;
        defer allocator.free(action_c);
        const kind_z = allocator.dupeZ(u8, kind_c) catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, action_c) catch return;
        defer allocator.free(action_z);

        c.g_object_set_data_full(@ptrCast(list_row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(list_row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
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

        ctx.service.recordSelection(allocator, action) catch {};

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
            showLaunchFeedback(ctx, "Action launched");
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
                showLaunchFeedback(ctx, "App launched");
            }
            return;
        }
        if (std.mem.eql(u8, kind, "dir")) {
            const cmd = std.fmt.allocPrint(allocator, "xdg-open \"{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "dir", action, "error", "command-failed");
                showLaunchFeedback(ctx, "Directory open failed");
                return;
            };
            emitTelemetry(ctx, "dir", action, "ok", cmd);
            showLaunchFeedback(ctx, "Directory opened");
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
            showLaunchFeedback(ctx, "Window focused");
            return;
        }
    }

    fn showLaunchFeedback(ctx: *UiContext, message: []const u8) void {
        clearLaunchFeedbackRows(ctx.list);
        appendLaunchFeedbackRow(ctx.list, message);
        setStatus(ctx, message);
        selectFirstActionableRow(ctx);
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
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.g_object_set_data_full(@ptrCast(row), "gs-feedback", c.g_strdup("1"), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn setStatus(ctx: *UiContext, message: []const u8) void {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);
        c.gtk_label_set_text(ctx.status, msg_z.ptr);
    }

    fn installCss(window: *c.GtkWidget) void {
        const css =
            ".gs-status { color: #8b93a8; font-size: 0.92em; }\n" ++
            ".gs-header { color: #8b93a8; }\n" ++
            ".gs-info { color: #9aa1b5; }\n" ++
            ".gs-separator { margin-top: 4px; margin-bottom: 4px; opacity: 0.3; }\n" ++
            ".gs-results > row { border-radius: 8px; padding: 2px 6px; }\n" ++
            ".gs-results > row:selected { background: rgba(140, 170, 235, 0.22); }\n" ++
            ".gs-results > row:hover { background: rgba(140, 170, 235, 0.12); }\n" ++
            ".gs-candidate-primary { color: #e8ecf7; }\n" ++
            ".gs-candidate-secondary { color: #9aa1b5; font-size: 0.92em; }\n";

        const provider = c.gtk_css_provider_new();
        defer c.g_object_unref(provider);
        c.gtk_css_provider_load_from_data(provider, css.ptr, @intCast(css.len));

        const display = c.gtk_widget_get_display(window);
        if (display != null) {
            c.gtk_style_context_add_provider_for_display(
                display,
                @ptrCast(provider),
                c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
    }

    fn routeHintForQuery(query_trimmed: []const u8) ?[]const u8 {
        if (query_trimmed.len != 1) return null;
        return switch (query_trimmed[0]) {
            '@' => "Apps route active: type app name after @",
            '#' => "Windows route active: type window title/class after #",
            '~' => "Directories route active: type folder name after ~",
            '>' => "Run route active: type command after >",
            '=' => "Calc route active: type expression after =",
            '?' => "Web route active: type search terms after ?",
            else => null,
        };
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
            .action => "action",
            .hint => "hint",
        };
    }

    fn kindIcon(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "󰀻",
            .window => "",
            .dir => "󰉋",
            .action => "",
            .hint => "󰘥",
        };
    }

    fn kindChipMarkup(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "<span foreground=\"#7fb0ff\">APP</span>",
            .window => "<span foreground=\"#78d2c7\">WIN</span>",
            .dir => "<span foreground=\"#ddb26f\">DIR</span>",
            .action => "<span foreground=\"#f18cb6\">ACT</span>",
            .hint => "<span foreground=\"#9aa1b5\">TIP</span>",
        };
    }
};
