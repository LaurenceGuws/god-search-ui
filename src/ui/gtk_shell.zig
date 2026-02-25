const std = @import("std");
const app_mod = @import("../app/mod.zig");
const search_mod = @import("../search/mod.zig");
const gtk_types = @import("gtk/types.zig");
const gtk_styles = @import("gtk/styles.zig");
const gtk_bootstrap = @import("gtk/bootstrap.zig");
const gtk_nav = @import("gtk/navigation.zig");
const gtk_query = @import("gtk/query_helpers.zig");
const gtk_async = @import("gtk/async_state.zig");
const gtk_async_coord = @import("gtk/async_coordinator.zig");
const gtk_menus = @import("gtk/menus.zig");
const gtk_status = @import("gtk/status.zig");
const gtk_icons = @import("gtk/icons.zig");
const gtk_row_data = @import("gtk/row_data.zig");
const gtk_preview = @import("gtk/preview.zig");
const gtk_selection = @import("gtk/selection.zig");
const gtk_controller = @import("gtk/controller.zig");
const gtk_results_flow = @import("gtk/results_flow.zig");
const gtk_widgets = @import("gtk/widgets.zig");
const ipc_control = @import("../ipc/control.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const LaunchContext = gtk_bootstrap.LaunchContext;

const UiContext = gtk_types.UiContext;
const AsyncSearchResult = gtk_async.AsyncSearchResult;
const ScoredCandidate = @import("../search/mod.zig").ScoredCandidate;

pub const Shell = struct {
    pub const RunOptions = struct {
        resident_mode: bool = false,
        start_hidden: bool = false,
    };

    pub fn run(allocator: std.mem.Allocator, service: *app_mod.SearchService, telemetry: *app_mod.TelemetrySink, options: RunOptions) !void {
        const gtk_app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(gtk_app);

        var launch = LaunchContext{
            .allocator = allocator,
            .service = service,
            .telemetry = telemetry,
            .resident_mode = options.resident_mode,
            .start_hidden = options.start_hidden,
            .ctx = null,
            .gtk_app = gtk_app,
        };

        var control_server: ?ipc_control.Server = null;
        defer if (control_server) |*srv| srv.deinit();
        if (options.resident_mode) {
            control_server = try ipc_control.Server.init(allocator, onControlCommand, &launch);
            try control_server.?.start();
        }
        _ = c.g_signal_connect_data(gtk_app, "activate", c.G_CALLBACK(onActivate), &launch, null, 0);
        _ = c.g_application_run(@ptrCast(gtk_app), 0, null);
    }

    const ControlInvokePayload = struct {
        launch: *LaunchContext,
        command: ipc_control.Command,
    };

    fn onControlCommand(command: ipc_control.Command, user_data: *anyopaque) ipc_control.HandlerResult {
        const launch: *LaunchContext = @ptrCast(@alignCast(user_data));
        const payload: *ControlInvokePayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(ControlInvokePayload))));
        payload.* = .{ .launch = launch, .command = command };
        if (c.g_idle_add(onControlInvokeIdle, payload) == 0) {
            c.g_free(payload);
            return .rejected;
        }
        return .ok;
    }

    fn onControlInvokeIdle(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const payload: *ControlInvokePayload = @ptrCast(@alignCast(user_data.?));
        defer c.g_free(payload);

        switch (payload.command) {
            .summon => c.g_application_activate(@ptrCast(payload.launch.gtk_app)),
            .hide => if (payload.launch.ctx) |ctx| c.gtk_widget_set_visible(ctx.window, GFALSE),
            .toggle => if (payload.launch.ctx) |ctx| {
                if (c.gtk_widget_get_visible(ctx.window) == GTRUE) {
                    c.gtk_widget_set_visible(ctx.window, GFALSE);
                } else {
                    c.g_application_activate(@ptrCast(payload.launch.gtk_app));
                }
            } else c.g_application_activate(@ptrCast(payload.launch.gtk_app)),
            else => {},
        }
        return GFALSE;
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
            .on_close_request = onCloseRequest,
            .on_destroy = onDestroy,
            .install_css = installCss,
            .after_activate = afterActivate,
        });
    }

    fn onCloseRequest(_: ?*c.GtkWindow, user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        if (ctx.resident_mode == GTRUE) {
            c.gtk_widget_set_visible(ctx.window, GFALSE);
            return GTRUE;
        }
        return GFALSE;
    }

    fn afterActivate(ctx: *UiContext) void {
        gtk_controller.updateEntryRouteIcon(ctx, "");
        ctx.service.kickAsyncStartupPrewarm();
        gtk_controller.enableStartupKeyQueue(ctx);
        if (ctx.startup_key_queue_id != 0) {
            _ = c.g_source_remove(ctx.startup_key_queue_id);
            ctx.startup_key_queue_id = 0;
        }
        ctx.startup_key_queue_id = c.g_timeout_add(220, onStartupKeyQueueTimeout, ctx);
        if (ctx.focus_ready_logged == GFALSE) {
            ctx.focus_ready_logged = GTRUE;
            logStartupMetric(ctx, "startup.focus_ready_ms");
        }
        if (ctx.startup_idle_id != 0) {
            _ = c.g_source_remove(ctx.startup_idle_id);
            ctx.startup_idle_id = 0;
        }
        ctx.startup_idle_id = c.g_idle_add(onStartupReady, ctx);
    }

    fn onStartupReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        ctx.startup_idle_id = 0;
        populateResults(ctx, "");
        gtk_nav.updateScrollbarActiveClass(ctx);
        return GFALSE;
    }

    fn onStartupKeyQueueTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        ctx.startup_key_queue_id = 0;
        gtk_controller.flushAndDisableStartupKeyQueue(ctx);
        return GFALSE;
    }

    fn onDestroy(_: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        const launch: *LaunchContext = @ptrCast(@alignCast(ctx.launch_ctx));
        if (launch.ctx == ctx) {
            launch.ctx = null;
        }
        disconnectSignalsByData(@ptrCast(ctx.window), ctx);
        // Child widgets may already be finalized by the time window destroy runs.
        // Let GTK tear down child signal handlers naturally to avoid invalid-instance warnings.
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
        if (ctx.startup_idle_id != 0) {
            _ = c.g_source_remove(ctx.startup_idle_id);
            ctx.startup_idle_id = 0;
        }
        if (ctx.startup_key_queue_id != 0) {
            _ = c.g_source_remove(ctx.startup_key_queue_id);
            ctx.startup_key_queue_id = 0;
        }
        gtk_controller.disableStartupKeyQueue(ctx);
        gtk_async_coord.beginAsyncShutdown(ctx);
        const ready_id = gtk_async_coord.takeAsyncReadySourceId(ctx);
        if (ready_id != 0) {
            _ = c.g_source_remove(ready_id);
        }
        ctx.async_worker_active = GFALSE;
        gtk_async.freePendingAsyncQuery(ctx);
        c.g_mutex_clear(&ctx.async_worker_lock);
        c.g_cond_clear(&ctx.async_worker_cond);
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        allocator.destroy(allocator_ptr);
        c.g_free(ctx);
    }

    fn disconnectSignalsByData(instance: *anyopaque, data: *anyopaque) void {
        _ = c.g_signal_handlers_disconnect_matched(
            instance,
            c.G_SIGNAL_MATCH_DATA,
            0,
            0,
            null,
            null,
            data,
        );
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
        if (ctx.first_keypress_logged == GFALSE) {
            ctx.first_keypress_logged = GTRUE;
            logStartupMetric(ctx, "startup.first_keypress_ms");
        }
        return gtk_controller.handleKeyPressed(ctx, keyval, state, .{
            .refresh_snapshot = refreshSnapshot,
            .toggle_preview = togglePreview,
            .set_status = setStatus,
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
        if (ctx.first_input_logged == GFALSE and query.len > 0) {
            ctx.first_input_logged = GTRUE;
            logStartupMetric(ctx, "startup.first_input_ms");
        }
        if (query.len > 0 and ctx.startup_key_queue_active == GTRUE) {
            if (ctx.startup_key_queue_id != 0) {
                _ = c.g_source_remove(ctx.startup_key_queue_id);
                ctx.startup_key_queue_id = 0;
            }
            gtk_controller.flushAndDisableStartupKeyQueue(ctx);
        }
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

        const action = gtk_row_data.action(row.?) orelse return;
        const kind = gtk_row_data.kind(row.?);
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
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        if (row == null) {
            gtk_preview.clear(ctx);
            return;
        }
        gtk_controller.handleRowSelected(ctx, row.?, .{
            .set_status = setStatus,
        });
    }

    fn populateResults(ctx: *UiContext, query: []const u8) void {
        gtk_results_flow.populateResults(ctx, query, .{
            .start_async_route_search = startAsyncRouteSearch,
            .cancel_async_route_search = cancelAsyncRouteSearch,
        });
        gtk_preview.refreshFromSelection(ctx);
    }

    fn startAsyncRouteSearch(ctx: *UiContext, allocator: std.mem.Allocator, query_trimmed: []const u8) void {
        gtk_async_coord.startAsyncRouteSearch(ctx, allocator, query_trimmed, onAsyncSearchReady);
    }

    fn onAsyncSearchReady(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const payload: *AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
        const ctx = payload.ctx;
        gtk_async_coord.clearAsyncReadySourceIdIf(ctx, payload.ready_source_id);
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        if (gtk_async_coord.isAsyncShuttingDown(ctx)) return GFALSE;
        ctx.async_worker_active = GFALSE;
        if (payload.generation != ctx.async_search_generation) {
            _ = launchPendingAsyncQuery(ctx, allocator);
            return GFALSE;
        }

        gtk_async_coord.endAsyncSpinner(ctx);
        if (payload.search_error) |err| {
            gtk_results_flow.renderSearchError(ctx, allocator, err);
            gtk_nav.selectFirstActionableRow(ctx);
            return GFALSE;
        }
        var scored = allocator.alloc(ScoredCandidate, payload.rows.len) catch return GFALSE;
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

        gtk_results_flow.renderRankedRows(ctx, allocator, std.mem.trim(u8, payload.query, " \t\r\n"), scored, payload.total_len);
        gtk_nav.selectFirstActionableRow(ctx);
        return GFALSE;
    }

    fn cancelAsyncRouteSearch(ctx: *UiContext) void {
        gtk_async_coord.cancelAsyncRouteSearch(ctx);
    }

    fn launchPendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator) bool {
        return gtk_async_coord.launchPendingAsyncQuery(ctx, allocator, onAsyncSearchReady);
    }

    fn refreshSnapshot(ctx: *UiContext) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
        if (refreshUnsupportedMessageForQuery(query)) |msg| {
            setStatus(ctx, msg);
            return;
        }

        showRefreshSpinnerFeedback(ctx);
        // Give GTK a chance to paint the refresh indicator before synchronous prewarm starts.
        while (c.g_main_context_pending(null) != 0) {
            _ = c.g_main_context_iteration(null, GFALSE);
        }

        ctx.service.invalidateSnapshot();
        ctx.service.prewarmProviders(allocator) catch {
            gtk_widgets.clearAsyncRows(ctx.list);
            setStatus(ctx, "Refresh failed");
            return;
        };

        gtk_widgets.clearAsyncRows(ctx.list);
        populateResults(ctx, query);
    }

    fn showRefreshSpinnerFeedback(ctx: *UiContext) void {
        gtk_widgets.clearAsyncRows(ctx.list);
        gtk_widgets.appendAsyncRow(ctx.list, "⟳", "Refreshing cached modules...");
        ctx.last_render_hash = 0;
        if (ctx.pending_power_confirm == GFALSE) {
            setStatus(ctx, "⟳ Refreshing cache...");
        }
    }

    fn refreshUnsupportedMessageForQuery(query: []const u8) ?[]const u8 {
        const parsed = search_mod.parseQuery(query);
        return switch (parsed.route) {
            .calc => "Calculator updates as you type (no cache refresh needed)",
            .grep => "Grep runs live with rg (no cache refresh needed)",
            .files => "File search runs live with fd (no cache refresh needed)",
            .run => "Run command executes live (no cache refresh needed)",
            .web => "Web results build from your query (no cache refresh needed)",
            else => null,
        };
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

    fn togglePreview(ctx: *UiContext) void {
        gtk_preview.toggle(ctx);
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
        ctx.telemetry.emitActionEvent(allocator_ptr.*, kind, action, status, detail) catch |err| {
            std.log.warn("telemetry write failed: {s}", .{@errorName(err)});
            setStatus(ctx, "Telemetry write failed");
        };
    }

    fn logStartupMetric(ctx: *UiContext, metric_name: []const u8) void {
        const now_ns = std.time.nanoTimestamp();
        const diff_ns = now_ns - ctx.launch_start_ns;
        const elapsed_ns: u64 = if (diff_ns <= 0) 0 else @as(u64, @intCast(diff_ns));
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        std.log.info("{s}={d:.2}", .{ metric_name, elapsed_ms });
    }
};
