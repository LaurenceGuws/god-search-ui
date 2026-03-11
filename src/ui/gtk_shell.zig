const std = @import("std");
const app_mod = @import("../app/mod.zig");
const providers_mod = @import("../providers/mod.zig");
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
const config_mod = @import("../config/mod.zig");
const runtime_tools = @import("../config/runtime_tools.zig");
const notifications_mod = @import("../notifications/mod.zig");
const shell_mod = @import("../shell/mod.zig");
const gtk_shell_control = @import("gtk/shell_control.zig");
const gtk_shell_lifecycle = @import("gtk/shell_lifecycle.zig");
const gtk_deferred_clear = @import("gtk/deferred_clear.zig");
const gtk_shell_notifications = @import("gtk/shell_notifications.zig");
const gtk_shell_notifications_popup = @import("gtk/shell_notifications_popup.zig");
const gtk_shell_startup = @import("gtk/shell_startup.zig");
const SurfaceMode = @import("surfaces/mod.zig").SurfaceMode;
const PlacementPolicy = @import("placement/mod.zig").RuntimePolicy;
const NotificationPolicy = @import("placement/mod.zig").NotificationPolicy;
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
        surface_mode: SurfaceMode = .layer_shell,
        placement_policy: PlacementPolicy = .{},
        show_nerd_stats: bool = true,
        notifications_show_close_button: bool = true,
        notifications_show_dbus_actions: bool = true,
    };

    pub fn run(allocator: std.mem.Allocator, service: *app_mod.SearchService, telemetry: *app_mod.TelemetrySink, options: RunOptions) !void {
        // We use our own local control socket for single-instance/summon semantics.
        // Keep GtkApplication non-unique to avoid session-bus registration timeouts
        // breaking launcher summon on some systems.
        const gtk_app = c.gtk_application_new(null, c.G_APPLICATION_NON_UNIQUE);
        defer c.g_object_unref(gtk_app);
        if (options.resident_mode) {
            c.g_application_hold(@ptrCast(gtk_app));
            defer c.g_application_release(@ptrCast(gtk_app));
        }

        var launch = LaunchContext{
            .allocator = allocator,
            .service = service,
            .telemetry = telemetry,
            .resident_mode = options.resident_mode,
            .start_hidden = options.start_hidden,
            .surface_mode = options.surface_mode,
            .placement_policy = options.placement_policy,
            .show_nerd_stats = options.show_nerd_stats,
            .ctx = null,
            .gtk_app = gtk_app,
        };

        var event_bus = shell_mod.EventBus.init(allocator);
        defer event_bus.deinit();
        var health_store = gtk_shell_control.HealthStore{};
        var control_ctx = gtk_shell_control.ControlContext{
            .event_bus = &event_bus,
            .health_store = &health_store,
        };

        var control_server: ?ipc_control.Server = null;
        defer if (control_server) |*srv| srv.deinit();
        control_server = try gtk_shell_control.maybeStart(allocator, options.resident_mode, &control_ctx);

        var module_registry = shell_mod.Registry.init(allocator);
        defer module_registry.deinit();
        var notifications_ctx = NotificationsModule.Context{
            .allocator = allocator,
            .gtk_app = gtk_app,
            .resident_mode = options.resident_mode,
            .surface_mode = options.surface_mode,
            .placement_policy = options.placement_policy.notifications,
            .show_close_button = options.notifications_show_close_button,
            .show_dbus_actions = options.notifications_show_dbus_actions,
            .health_store = &health_store,
        };
        var launcher_ctx = LauncherModule.Context{
            .gtk_app = gtk_app,
            .launch = &launch,
            .event_bus = &event_bus,
            .health_store = &health_store,
        };
        try module_registry.register(NotificationsModule.factory(&notifications_ctx));
        try module_registry.register(LauncherModule.factory(&launcher_ctx));
        try module_registry.startAll();
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
            .on_window_active_notify = gtk_shell_lifecycle.onWindowActiveNotify,
            .on_close_request = gtk_shell_lifecycle.onCloseRequest,
            .on_destroy = gtk_shell_lifecycle.onDestroy,
            .install_css = installCss,
            .after_activate = afterActivate,
        });
    }

    fn afterActivate(ctx: *UiContext) void {
        gtk_shell_startup.afterActivate(ctx);
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
            .reload_config = reloadConfig,
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
        gtk_shell_startup.storeQueryText(ctx, query);
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
        gtk_shell_startup.storeQueryText(ctx, query);
        populateResults(ctx, query);
        return GFALSE;
    }

    fn onResultsAdjustmentChanged(_: ?*c.GtkAdjustment, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        gtk_controller.handleResultsAdjustmentChanged(ctx, .{
            .poll_more = pollMoreResults,
        });
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

    fn pollMoreResults(ctx: *UiContext) void {
        if (!gtk_results_flow.shouldPollMoreOnScroll(ctx)) return;
        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
        populateResults(ctx, query);
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
        const query_trimmed = std.mem.trim(u8, payload.query, " \t\r\n");
        const had_selection = c.gtk_list_box_get_selected_row(@ptrCast(ctx.list)) != null;
        gtk_results_flow.cacheAndRenderAsyncRows(ctx, allocator, query_trimmed, scored, payload.total_len);
        if (!had_selection and ctx.result_window_limit <= 20) {
            gtk_nav.selectFirstActionableRow(ctx);
        }
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
        const parsed_query = search_mod.parseQuery(query);
        gtk_shell_startup.storeQueryText(ctx, query);
        if (refreshUnsupportedMessageForQuery(query)) |msg| {
            setStatus(ctx, msg);
            return;
        }

        if (parsed_query.route == .web) {
            gtk_async.clearAsyncSearchCache(ctx, allocator);
            ctx.service.clearDynamicState(allocator);
            providers_mod.invalidateWebCaches();
            providers_mod.invalidateAppsCache();
            gtk_icons.invalidateYaziIconCache();
            ctx.service.invalidateSnapshot();
            switch (ctx.service.scheduleRefreshFromEvent()) {
                .scheduled => beginRefreshSpinner(ctx),
                .skipped_running => beginRefreshSpinner(ctx),
                .failed_spawn => setStatus(ctx, "Refresh failed"),
            }
            return;
        }

        gtk_async.clearAsyncSearchCache(ctx, allocator);
        ctx.service.clearDynamicState(allocator);
        providers_mod.invalidateWebCaches();
        providers_mod.invalidateAppsCache();
        gtk_icons.invalidateYaziIconCache();
        ctx.service.invalidateSnapshot();
        switch (ctx.service.scheduleRefreshFromEvent()) {
            .scheduled => beginRefreshSpinner(ctx),
            .skipped_running => beginRefreshSpinner(ctx),
            .failed_spawn => setStatus(ctx, "Refresh failed"),
        }
    }

    fn reloadConfig(ctx: *UiContext) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;
        var cfg = config_mod.load(allocator);
        defer cfg.deinit(allocator);
        if (config_mod.consumeLastLoadIssue(allocator)) |issue| {
            defer allocator.free(issue);
            config_mod.issue_notice.show(issue, "Fix config.lua and reload config (Ctrl+Shift+R).");
            setStatus(ctx, "Config invalid: kept current settings (check notification)");
            return;
        }
        runtime_tools.apply(cfg);
        ctx.show_nerd_stats = if (cfg.ui.show_nerd_stats) GTRUE else GFALSE;
        gtk_async.clearAsyncSearchCache(ctx, allocator);
        ctx.service.clearDynamicState(allocator);
        gtk_icons.invalidateYaziIconCache();
        config_mod.issue_notice.clearIfActive();
        setStatus(ctx, "Config reloaded");
    }

    fn beginRefreshSpinner(ctx: *UiContext) void {
        ctx.refresh_inflight = GTRUE;
        if (ctx.refresh_spinner_id != 0) return;
        ctx.refresh_spinner_phase = 0;
        updateRefreshSpinnerFrame(ctx);
        ctx.refresh_spinner_id = c.g_timeout_add(120, onRefreshSpinnerTick, ctx);
    }

    fn endRefreshSpinner(ctx: *UiContext) void {
        ctx.refresh_inflight = GFALSE;
        if (ctx.refresh_spinner_id != 0) {
            _ = c.g_source_remove(ctx.refresh_spinner_id);
            ctx.refresh_spinner_id = 0;
        }
        gtk_widgets.clearAsyncRows(ctx.list);
        ctx.last_render_hash = 0;
    }

    fn onRefreshSpinnerTick(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        if (ctx.refresh_inflight == GFALSE) {
            ctx.refresh_spinner_id = 0;
            return GFALSE;
        }
        if (!ctx.service.refreshInFlight()) {
            endRefreshSpinner(ctx);
            const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
            const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
            setStatus(ctx, "Snapshot refreshed");
            populateResults(ctx, query);
            return GFALSE;
        }
        updateRefreshSpinnerFrame(ctx);
        return GTRUE;
    }

    fn updateRefreshSpinnerFrame(ctx: *UiContext) void {
        const frames = [_][]const u8{ "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⠋", "⠙" };
        const frame = frames[ctx.refresh_spinner_phase % frames.len];
        ctx.refresh_spinner_phase +%= 1;
        gtk_widgets.clearAsyncRows(ctx.list);
        gtk_widgets.appendAsyncRow(ctx.list, frame, "Refreshing cached modules...");
        ctx.last_render_hash = 0;
        if (ctx.pending_power_confirm == GFALSE) {
            var status_buf: [40]u8 = undefined;
            const status_msg = std.fmt.bufPrint(&status_buf, "{s} Refreshing cache...", .{frame}) catch "Refreshing cache...";
            setStatus(ctx, status_msg);
        }
    }

    fn refreshUnsupportedMessageForQuery(query: []const u8) ?[]const u8 {
        const parsed = search_mod.parseQuery(query);
        return switch (parsed.route) {
            .calc => "Calculator updates as you type (no cache refresh needed)",
            .grep => "Grep runs live with rg (no cache refresh needed)",
            .files => "File search runs live with fd (no cache refresh needed)",
            .notifications => "Notifications route is live (no cache refresh needed)",
            .run => "Run command executes live (no cache refresh needed)",
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

    const NotificationsModule = struct {
        const Context = struct {
            allocator: std.mem.Allocator,
            gtk_app: *c.GtkApplication,
            resident_mode: bool,
            surface_mode: SurfaceMode,
            placement_policy: NotificationPolicy,
            show_close_button: bool,
            show_dbus_actions: bool,
            health_store: *gtk_shell_control.HealthStore,
        };

        const State = struct {
            ctx: *Context,
            daemon: ?*notifications_mod.Daemon = null,
            popup: ?*gtk_shell_notifications_popup.PopupManager = null,
            started: bool = false,
        };

        fn factory(ctx: *Context) shell_mod.module.ModuleFactory {
            return .{
                .name = "notifications",
                .context = ctx,
                .init = init,
            };
        }

        fn init(allocator: std.mem.Allocator, ctx_ptr: *anyopaque) !shell_mod.module.ModuleInstance {
            const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
            const state = try allocator.create(State);
            state.* = .{ .ctx = ctx };
            return .{
                .name = "notifications",
                .state = state,
                .vtable = &.{
                    .start = start,
                    .stop = stop,
                    .handle_event = handleEvent,
                    .health = health,
                    .deinit = deinit,
                },
            };
        }

        fn start(state_ptr: *anyopaque) !void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            state.daemon = try gtk_shell_notifications.maybeStart(state.ctx.allocator, state.ctx.resident_mode);
            if (state.daemon) |daemon| {
                notifications_mod.runtime.registerCloser(daemon, closeNotificationViaDaemon);
                const popup = try state.ctx.allocator.create(gtk_shell_notifications_popup.PopupManager);
                popup.* = try gtk_shell_notifications_popup.PopupManager.init(
                    state.ctx.allocator,
                    state.ctx.gtk_app,
                    daemon,
                    state.ctx.surface_mode,
                    state.ctx.placement_policy,
                    state.ctx.show_close_button,
                    state.ctx.show_dbus_actions,
                );
                popup.attach();
                state.popup = popup;
                state.ctx.health_store.setNotifications(.{ .status = .ready, .detail = "daemon active" });
            } else {
                state.ctx.health_store.setNotifications(.{ .status = .degraded, .detail = "daemon disabled or unavailable" });
            }
            state.started = true;
        }

        fn stop(state_ptr: *anyopaque) void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            if (state.popup) |popup| {
                popup.deinit();
                state.ctx.allocator.destroy(popup);
                state.popup = null;
            }
            if (state.daemon) |daemon| {
                notifications_mod.runtime.clearCloser(daemon);
                daemon.deinit();
                state.ctx.allocator.destroy(daemon);
                state.daemon = null;
            }
            state.ctx.health_store.setNotifications(.{ .status = .unknown, .detail = "not started" });
            state.started = false;
        }

        fn handleEvent(_: *anyopaque, _: shell_mod.module.Event) void {}

        fn health(state_ptr: *anyopaque) shell_mod.module.ModuleHealth {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            if (!state.started) return .{ .status = .unknown, .detail = "not started" };
            return if (state.daemon != null)
                .{ .status = .ready, .detail = "daemon active" }
            else
                .{ .status = .degraded, .detail = "daemon disabled or unavailable" };
        }

        fn deinit(allocator: std.mem.Allocator, state_ptr: *anyopaque) void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            allocator.destroy(state);
        }
    };

    const LauncherModule = struct {
        const Context = struct {
            gtk_app: *c.GtkApplication,
            launch: *LaunchContext,
            event_bus: *shell_mod.EventBus,
            health_store: *gtk_shell_control.HealthStore,
        };

        const State = struct {
            ctx: *Context,
            started: bool = false,
        };

        fn factory(ctx: *Context) shell_mod.module.ModuleFactory {
            return .{
                .name = "launcher",
                .context = ctx,
                .init = init,
            };
        }

        fn init(allocator: std.mem.Allocator, ctx_ptr: *anyopaque) !shell_mod.module.ModuleInstance {
            const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
            const state = try allocator.create(State);
            state.* = .{ .ctx = ctx };
            return .{
                .name = "launcher",
                .state = state,
                .vtable = &.{
                    .start = start,
                    .stop = stop,
                    .handle_event = handleEvent,
                    .health = health,
                    .deinit = deinit,
                },
            };
        }

        fn start(state_ptr: *anyopaque) !void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            state.ctx.health_store.setLauncher(.{ .status = .ready, .detail = "gtk loop active" });
            try state.ctx.event_bus.subscribe(.{
                .context = state,
                .on_event = onBusEvent,
            });
            _ = c.g_signal_connect_data(state.ctx.gtk_app, "activate", c.G_CALLBACK(onActivate), state.ctx.launch, null, 0);
            _ = c.g_application_run(@ptrCast(state.ctx.gtk_app), 0, null);
            state.started = true;
        }

        fn stop(state_ptr: *anyopaque) void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            state.ctx.health_store.setLauncher(.{ .status = .unknown, .detail = "not started" });
        }

        fn handleEvent(state_ptr: *anyopaque, event: shell_mod.module.Event) void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            applyControlEvent(state, event);
        }

        fn health(state_ptr: *anyopaque) shell_mod.module.ModuleHealth {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            return if (state.started)
                .{ .status = .ready, .detail = "gtk launcher exited cleanly" }
            else
                .{ .status = .unknown, .detail = "not started" };
        }

        fn deinit(allocator: std.mem.Allocator, state_ptr: *anyopaque) void {
            const state: *State = @ptrCast(@alignCast(state_ptr));
            allocator.destroy(state);
        }

        fn onBusEvent(ctx: *anyopaque, event: shell_mod.module.Event) void {
            const state: *State = @ptrCast(@alignCast(ctx));
            applyControlEvent(state, event);
        }

        fn applyControlEvent(state: *State, event: shell_mod.module.Event) void {
            switch (event) {
                .summon => if (state.ctx.launch.ctx) |ui_ctx| {
                    std.log.info(
                        "ram_event=ui_summon query_hash={d} window_limit={d} visible={}",
                        .{ ui_ctx.result_query_hash, ui_ctx.result_window_limit, c.gtk_widget_get_visible(ui_ctx.window) == GTRUE },
                    );
                    summonExistingUi(ui_ctx);
                } else c.g_application_activate(@ptrCast(state.ctx.gtk_app)),
                .hide => if (state.ctx.launch.ctx) |ui_ctx| {
                    std.log.info(
                        "ram_event=ui_hide request query_hash={d} window_limit={d}",
                        .{ ui_ctx.result_query_hash, ui_ctx.result_window_limit },
                    );
                    gtk_deferred_clear.request(ui_ctx);
                    gtk_shell_lifecycle.captureListState(ui_ctx);
                    c.gtk_widget_set_visible(ui_ctx.window, GFALSE);
                },
                .toggle => if (state.ctx.launch.ctx) |ui_ctx| {
                    if (c.gtk_widget_get_visible(ui_ctx.window) == GTRUE) {
                        std.log.info(
                            "ram_event=ui_toggle_hide request query_hash={d} window_limit={d}",
                            .{ ui_ctx.result_query_hash, ui_ctx.result_window_limit },
                        );
                        gtk_deferred_clear.request(ui_ctx);
                        gtk_shell_lifecycle.captureListState(ui_ctx);
                        c.gtk_widget_set_visible(ui_ctx.window, GFALSE);
                    } else {
                        std.log.info(
                            "ram_event=ui_toggle_show query_hash={d} window_limit={d}",
                            .{ ui_ctx.result_query_hash, ui_ctx.result_window_limit },
                        );
                        summonExistingUi(ui_ctx);
                    }
                } else c.g_application_activate(@ptrCast(state.ctx.gtk_app)),
                else => {},
            }
        }

        fn summonExistingUi(ui_ctx: *UiContext) void {
            c.gtk_window_present(@ptrCast(ui_ctx.window));
            _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(ui_ctx.entry)));
            const text_ptr = c.gtk_editable_get_text(@ptrCast(ui_ctx.entry));
            const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
            if (std.mem.trim(u8, query, " \t\r\n").len == 0) {
                ui_ctx.last_render_hash = 0;
                ui_ctx.last_selected_row_index = -1;
                ui_ctx.last_scroll_position = 0;
                populateResults(ui_ctx, "");
            }
            gtk_shell_startup.afterActivate(ui_ctx);
        }
    };

    fn closeNotificationViaDaemon(ctx: *anyopaque, id: u32) bool {
        const daemon: *notifications_mod.Daemon = @ptrCast(@alignCast(ctx));
        return daemon.closeWithReason(id, 3);
    }
};
