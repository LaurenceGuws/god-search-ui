const std = @import("std");
const app_mod = @import("../app/mod.zig");
const gtk_types = @import("gtk/types.zig");
const gtk_styles = @import("gtk/styles.zig");
const gtk_bootstrap = @import("gtk/bootstrap.zig");
const gtk_widgets = @import("gtk/widgets.zig");
const gtk_nav = @import("gtk/navigation.zig");
const gtk_query = @import("gtk/query_helpers.zig");
const gtk_async = @import("gtk/async_state.zig");
const gtk_async_search = @import("gtk/async_search.zig");
const gtk_render = @import("gtk/render.zig");
const gtk_menus = @import("gtk/menus.zig");
const gtk_status = @import("gtk/status.zig");
const gtk_icons = @import("gtk/icons.zig");
const gtk_selection = @import("gtk/selection.zig");
const gtk_controller = @import("gtk/controller.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const LaunchContext = gtk_bootstrap.LaunchContext;

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
        gtk_bootstrap.activate(gtk_app, launch, .{
            .on_key_pressed = onKeyPressed,
            .on_search_changed = onSearchChanged,
            .on_entry_activate = onEntryActivate,
            .on_row_activated = onRowActivated,
            .on_row_selected = onRowSelected,
            .on_adjustment_changed = onResultsAdjustmentChanged,
            .on_destroy = onDestroy,
            .install_css = installCss,
            .after_activate = afterActivate,
        });
    }

    fn afterActivate(ctx: *UiContext) void {
        gtk_controller.updateEntryRouteIcon(ctx, "");
        populateResults(ctx, "");
        gtk_nav.updateScrollbarActiveClass(ctx);
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
        return gtk_controller.handleKeyPressed(ctx, keyval, state, .{
            .refresh_snapshot = refreshSnapshot,
        });
    }

    fn onEntryActivate(_: ?*c.GtkEntry, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        gtk_controller.handleEntryActivate(ctx);
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
        gtk_controller.updateEntryRouteIcon(ctx, query);
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
        gtk_controller.handleResultsAdjustmentChanged(ctx);
    }

    fn searchDebounceMsForQuery(query_trimmed: []const u8) c.guint {
        return gtk_query.searchDebounceMsForQuery(query_trimmed);
    }

    fn onRowActivated(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
        if (row == null or user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        const kind_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind");
        const action_ptr = c.g_object_get_data(@ptrCast(row), "gs-action");
        if (kind_ptr == null or action_ptr == null) return;

        const kind = std.mem.span(@as([*:0]const u8, @ptrCast(kind_ptr)));
        const action = std.mem.span(@as([*:0]const u8, @ptrCast(action_ptr)));
        gtk_selection.executeSelected(ctx, kind, action, .{
            .set_status = setStatus,
            .show_launch_feedback = showLaunchFeedback,
            .emit_telemetry = emitTelemetry,
            .arm_power_confirmation = armPowerConfirmation,
            .clear_power_confirmation = clearPowerConfirmation,
            .show_dir_action_menu = showDirActionMenu,
            .show_file_action_menu = showFileActionMenu,
        });
    }

    fn onRowSelected(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
        if (row == null or user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        gtk_controller.handleRowSelected(ctx, row.?, .{
            .set_status = setStatus,
        });
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
