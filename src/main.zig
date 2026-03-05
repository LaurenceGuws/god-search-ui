const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    const startup_sw = god_search_ui.app.Stopwatch.start();
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const state = god_search_ui.app.bootstrap();
    const logger = god_search_ui.app.Logger.init(.info);
    logger.info("god-search-ui starting (mode={s})", .{@tagName(state.mode)});

    if (hasArg(args, "--ctl")) {
        const raw_cmd = argValueAfterFlag(args, "--ctl") orelse {
            try printCtlUsage();
            return;
        };
        if (std.mem.eql(u8, raw_cmd, "--help")) {
            try printCtlUsage();
            return;
        }
        const cmd = parseControlCommand(raw_cmd) orelse {
            std.process.exit(13);
        };
        if (cmd == .shell_health or cmd == .wm_event_stats) {
            const response = god_search_ui.ipc.control.executeCommand(allocator, cmd) catch |err| {
                std.log.err("control command failure route={s} err={s}", .{ raw_cmd, @errorName(err) });
                std.process.exit(10);
            };
            defer {
                allocator.free(response.code);
                allocator.free(response.message);
            }
            if (!response.ok) {
                std.log.err(
                    "control command rejected route={s} exit_code={s} elapsed_ns={d} message={s}",
                    .{ raw_cmd, response.code, response.elapsed_ns, response.message },
                );
                std.process.exit(10);
            }
            if (response.message.len > 0) {
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const out = &stdout_writer.interface;
                try out.print("{s}\n", .{response.message});
                try out.flush();
            } else {
                std.log.err("control command returned empty payload route={s}", .{raw_cmd});
                std.process.exit(10);
            }
            std.process.exit(0);
        }
        const response = god_search_ui.ipc.control.executeCommand(allocator, cmd) catch |err| {
            std.log.err("control command failure route={s} err={s}", .{ raw_cmd, @errorName(err) });
            std.process.exit(10);
        };
        defer {
            allocator.free(response.code);
            allocator.free(response.message);
        }
        if (response.ok and std.mem.eql(u8, response.code, "ok")) {
            std.process.exit(0);
        }
        std.log.err(
            "control command rejected route={s} exit_code={s} elapsed_ns={d} message={s}",
            .{ raw_cmd, response.code, response.elapsed_ns, response.message },
        );
        std.process.exit(10);
    }

    if (hasArg(args, "--print-config")) {
        var cfg = god_search_ui.config.load(allocator);
        defer cfg.deinit(allocator);
        god_search_ui.config.runtime_tools.apply(cfg);
        const surface_mode = resolveSurfaceMode(args, cfg);
        try printResolvedConfig(cfg, surface_mode);
        return;
    }

    if (hasArg(args, "--print-outputs")) {
        try god_search_ui.ui.Diagnostics.printOutputs(allocator);
        return;
    }

    if (hasArg(args, "--print-shell-health")) {
        const live = god_search_ui.ipc.control.queryCommandMessage(allocator, .shell_health) catch null;
        if (live) |message| {
            defer allocator.free(message);
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const out = &stdout_writer.interface;
            var it = std.mem.splitScalar(u8, message, ';');
            while (it.next()) |part| {
                if (part.len == 0) continue;
                try out.print("{s}\n", .{part});
            }
            try out.flush();
        } else {
            try god_search_ui.ui.Diagnostics.printShellHealth(allocator);
        }
        return;
    }

    const ui_mode = hasArg(args, "--ui") or hasArg(args, "--ui-resident") or hasArg(args, "--ui-daemon");
    if (ui_mode) {
        var cfg = god_search_ui.config.load(allocator);
        defer cfg.deinit(allocator);
        god_search_ui.config.runtime_tools.apply(cfg);
        const resident_mode = hasArg(args, "--ui-resident") or hasArg(args, "--ui-daemon");
        const start_hidden = hasArg(args, "--ui-daemon");
        if (!god_search_ui.ui.gtk_enabled and resident_mode) {
            std.log.err("--ui-daemon/--ui-resident requires GTK build; run: zig build -Denable_gtk=true", .{});
            std.process.exit(2);
        }
        const surface_mode = resolveSurfaceMode(args, cfg);
        if (resident_mode) {
            const already_running = isCommandOk(allocator, .ping);
            if (already_running) {
                if (!start_hidden) {
                    _ = isCommandOk(allocator, .summon);
                }
                return;
            }
        }
        if (!resident_mode and hasArg(args, "--ui")) {
            const summoned = isCommandOk(allocator, .summon);
            if (summoned) return;
        }
        var runtime = try setupRuntime(allocator);
        defer runtime.deinit(allocator);
        runtime.rebindProviderContexts();
        if (resident_mode and envFlagEnabled("GOD_SEARCH_WM_EVENT_BRIDGE")) {
            runtime.startWmEventBridge(allocator);
        }
        try runtime.service.loadHistory(allocator);
        defer runtime.service.saveHistory(allocator) catch |err| {
            logger.err("failed to save history: {s}", .{@errorName(err)});
        };
        logger.info("runtime ready in {d:.2} ms", .{startup_sw.elapsedMs()});
        try god_search_ui.ui.Shell.run(allocator, &runtime.service, &runtime.telemetry, .{
            .resident_mode = resident_mode,
            .start_hidden = start_hidden,
            .surface_mode = surface_mode,
            .placement_policy = cfg.placement_policy,
            .show_nerd_stats = cfg.ui.show_nerd_stats,
            .notifications_show_close_button = cfg.notification_actions.show_close_button,
            .notifications_show_dbus_actions = cfg.notification_actions.show_dbus_actions,
        });
        return;
    }

    logger.info("startup ready in {d:.2} ms", .{startup_sw.elapsedMs()});
    try god_search_ui.bufferedPrint();
}

fn isCommandOk(allocator: std.mem.Allocator, cmd: god_search_ui.ipc.control.Command) bool {
    const response = god_search_ui.ipc.control.executeCommand(allocator, cmd) catch return false;
    defer {
        allocator.free(response.code);
        allocator.free(response.message);
    }
    return response.ok and std.mem.eql(u8, response.code, "ok");
}

fn printCtlUsage() !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &stdout_writer.interface;
    try out.print(
        \\Usage: god-search-ui --ctl <command>
        \\Commands: ping, summon, hide, toggle, version, shell_health, wm_event_stats
        \\
    , .{});
    try out.flush();
}

const Runtime = struct {
    const WmEventBridge = struct {
        backend: ?god_search_ui.wm.Backend = null,
        subscription: ?god_search_ui.wm.EventSubscription = null,
        service: ?*god_search_ui.app.SearchService = null,
        windows: ?*god_search_ui.providers.WindowsProvider = null,
        workspaces: ?*god_search_ui.providers.WorkspacesProvider = null,
        event_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        refresh_scheduled_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        refresh_skipped_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        refresh_failed_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        log_every_event: bool = false,

        fn start(
            self: *WmEventBridge,
            allocator: std.mem.Allocator,
            service: *god_search_ui.app.SearchService,
            windows: *god_search_ui.providers.WindowsProvider,
            workspaces: *god_search_ui.providers.WorkspacesProvider,
            backend: god_search_ui.wm.Backend,
        ) void {
            self.service = service;
            self.windows = windows;
            self.workspaces = workspaces;
            self.backend = backend;
            self.log_every_event = envFlagEnabled("GOD_SEARCH_WM_EVENT_LOG_EVERY");
            if (!backend.supportsEventStream()) return;

            const maybe_sub = backend.subscribeEvents(allocator, self, onWmEvent) catch return;
            if (maybe_sub) |sub| {
                self.subscription = sub;
                // Event-driven invalidation mode to reduce periodic refresh churn.
                service.cache_ttl_ns = 24 * 60 * 60 * std.time.ns_per_s;
            }
        }

        fn stop(self: *WmEventBridge, allocator: std.mem.Allocator) void {
            const backend = self.backend orelse return;
            const sub = self.subscription orelse return;
            backend.unsubscribeEvents(allocator, sub);
            self.subscription = null;
        }

        fn onWmEvent(ctx: *anyopaque, event: god_search_ui.wm.Event) void {
            const self: *WmEventBridge = @ptrCast(@alignCast(ctx));
            const service = self.service orelse return;
            const allocator = std.heap.page_allocator;

            switch (event.kind) {
                .windows_changed, .focus_window_changed => {
                    if (self.windows) |windows| _ = windows.refreshSnapshot(allocator) catch {};
                },
                .workspaces_changed, .workspace_switched => {
                    if (self.workspaces) |workspaces| _ = workspaces.refreshSnapshot(allocator) catch {};
                },
            }
            const result = service.scheduleRefreshFromEvent();
            god_search_ui.wm.event_stats.record(switch (result) {
                .scheduled => .scheduled,
                .skipped_running => .skipped_running,
                .failed_spawn => .failed_spawn,
            });
            switch (result) {
                .scheduled => _ = self.refresh_scheduled_count.fetchAdd(1, .monotonic),
                .skipped_running => _ = self.refresh_skipped_count.fetchAdd(1, .monotonic),
                .failed_spawn => _ = self.refresh_failed_count.fetchAdd(1, .monotonic),
            }

            const events = self.event_count.fetchAdd(1, .monotonic) + 1;
            if (self.log_every_event) {
                std.log.info(
                    "wm-event refresh: kind={s} result={s} events={d} scheduled={d} skipped={d} failed={d}",
                    .{
                        @tagName(event.kind),
                        eventRefreshResultLabel(result),
                        events,
                        self.refresh_scheduled_count.load(.monotonic),
                        self.refresh_skipped_count.load(.monotonic),
                        self.refresh_failed_count.load(.monotonic),
                    },
                );
            }
            if (events % 32 == 0 or result == .failed_spawn) {
                std.log.info(
                    "wm-event refresh stats: events={d} scheduled={d} skipped={d} failed={d}",
                    .{
                        events,
                        self.refresh_scheduled_count.load(.monotonic),
                        self.refresh_skipped_count.load(.monotonic),
                        self.refresh_failed_count.load(.monotonic),
                    },
                );
            }
        }
    };

    app_cache_path: []u8,
    history_path: []u8,
    telemetry_path: []u8,
    actions: god_search_ui.providers.ActionsProvider = .{},
    apps: god_search_ui.providers.AppsProvider,
    windows: god_search_ui.providers.WindowsProvider = .{},
    workspaces: god_search_ui.providers.WorkspacesProvider = .{},
    dirs: god_search_ui.providers.DirsProvider = .{},
    provider_list: [5]god_search_ui.search.Provider,
    service: god_search_ui.app.SearchService,
    telemetry: god_search_ui.app.TelemetrySink,
    wm_event_bridge: WmEventBridge = .{},

    fn deinit(self: *Runtime, allocator: std.mem.Allocator) void {
        self.wm_event_bridge.stop(allocator);
        self.apps.deinit(allocator);
        self.windows.deinit(allocator);
        self.workspaces.deinit(allocator);
        self.dirs.deinit(allocator);
        self.service.deinit(allocator);
        allocator.free(self.app_cache_path);
        allocator.free(self.history_path);
        allocator.free(self.telemetry_path);
    }

    fn rebindProviderContexts(self: *Runtime) void {
        self.provider_list = .{
            self.actions.provider(),
            self.apps.provider(),
            self.windows.provider(),
            self.workspaces.provider(),
            self.dirs.provider(),
        };
        const registry = god_search_ui.providers.ProviderRegistry.init(&self.provider_list);
        self.service = god_search_ui.app.SearchService.initWithHistoryPath(registry, self.history_path);
        self.service.max_history = 64;
        self.service.cache_ttl_ns = 30 * std.time.ns_per_s;
        self.service.enable_async_refresh = useAsyncRefresh();
        self.telemetry = god_search_ui.app.TelemetrySink.init(self.telemetry_path);
    }

    fn startWmEventBridge(self: *Runtime, allocator: std.mem.Allocator) void {
        self.wm_event_bridge.start(
            allocator,
            &self.service,
            &self.windows,
            &self.workspaces,
            self.windows.hyprland_backend.backend(),
        );
    }
};

fn eventRefreshResultLabel(result: god_search_ui.app.SearchService.EventRefreshResult) []const u8 {
    return switch (result) {
        .scheduled => "scheduled",
        .skipped_running => "skipped_running",
        .failed_spawn => "failed_spawn",
    };
}

fn envFlagEnabled(name: []const u8) bool {
    const raw = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(raw);
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (std.mem.eql(u8, trimmed, "1")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "true")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "on")) return true;
    return false;
}

fn setupRuntime(allocator: std.mem.Allocator) !Runtime {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const app_cache = try std.fmt.allocPrint(allocator, "{s}/.cache/waybar/wofi-app-launcher.tsv", .{home});
    errdefer allocator.free(app_cache);
    const history_path = try std.fmt.allocPrint(allocator, "{s}/.local/state/god-search-ui/history.log", .{home});
    errdefer allocator.free(history_path);
    const telemetry_path = try std.fmt.allocPrint(allocator, "{s}/.local/state/god-search-ui/telemetry.log", .{home});
    errdefer allocator.free(telemetry_path);

    var runtime = Runtime{
        .app_cache_path = app_cache,
        .history_path = history_path,
        .telemetry_path = telemetry_path,
        .actions = .{},
        .apps = god_search_ui.providers.AppsProvider.init(app_cache),
        .windows = .{},
        .workspaces = .{},
        .dirs = .{},
        .provider_list = undefined,
        .service = undefined,
        .telemetry = undefined,
    };

    runtime.provider_list = .{
        runtime.actions.provider(),
        runtime.apps.provider(),
        runtime.windows.provider(),
        runtime.workspaces.provider(),
        runtime.dirs.provider(),
    };

    const registry = god_search_ui.providers.ProviderRegistry.init(&runtime.provider_list);
    runtime.service = god_search_ui.app.SearchService.initWithHistoryPath(registry, history_path);
    runtime.service.max_history = 64;
    runtime.service.cache_ttl_ns = 30 * std.time.ns_per_s;
    runtime.service.enable_async_refresh = useAsyncRefresh();
    runtime.telemetry = god_search_ui.app.TelemetrySink.init(telemetry_path);

    return runtime;
}

fn useAsyncRefresh() bool {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "GOD_SEARCH_ASYNC_REFRESH") catch return false;
    defer std.heap.page_allocator.free(value);
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return false;
    if (std.mem.eql(u8, trimmed, "1")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "true")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
    return false;
}

fn hasArg(args: []const []const u8, needle: []const u8) bool {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, needle)) return true;
    }
    return false;
}

fn argValueAfterFlag(args: []const []const u8, flag: []const u8) ?[]const u8 {
    if (args.len < 3) return null;
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) return args[i + 1];
    }
    return null;
}

fn parseControlCommand(value: []const u8) ?god_search_ui.ipc.control.Command {
    if (std.mem.eql(u8, value, "ping")) return .ping;
    if (std.mem.eql(u8, value, "summon")) return .summon;
    if (std.mem.eql(u8, value, "hide")) return .hide;
    if (std.mem.eql(u8, value, "toggle")) return .toggle;
    if (std.mem.eql(u8, value, "version")) return .version;
    if (std.mem.eql(u8, value, "shell_health")) return .shell_health;
    if (std.mem.eql(u8, value, "wm_event_stats")) return .wm_event_stats;
    return null;
}

fn resolveSurfaceMode(args: []const []const u8, cfg: god_search_ui.config.Settings) god_search_ui.ui.surfaces.SurfaceMode {
    _ = args;
    return cfg.surface_mode orelse .layer_shell;
}

fn printResolvedConfig(cfg: god_search_ui.config.Settings, surface_mode: god_search_ui.ui.surfaces.SurfaceMode) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const out = &stdout_writer.interface;

    const launcher = cfg.placement_policy.launcher;
    const notifications = cfg.placement_policy.notifications;
    const launcher_monitor_name = launcher.window.monitor.output_name orelse "";
    const notify_monitor_name = notifications.window.monitor.output_name orelse "";

    try out.print(
        \\{{
        \\  "surface_mode": "{s}",
        \\  "placement": {{
        \\    "launcher": {{
        \\      "anchor": "{s}",
        \\      "monitor_policy": "{s}",
        \\      "monitor_name": "{s}",
        \\      "margins": {{"top": {d}, "right": {d}, "bottom": {d}, "left": {d}}},
        \\      "width_percent": {d},
        \\      "height_percent": {d},
        \\      "min_width_percent": {d},
        \\      "min_height_percent": {d},
        \\      "min_width_px": {d},
        \\      "min_height_px": {d},
        \\      "max_width_px": {d},
        \\      "max_height_px": {d}
        \\    }},
        \\    "notifications": {{
        \\      "anchor": "{s}",
        \\      "monitor_policy": "{s}",
        \\      "monitor_name": "{s}",
        \\      "margins": {{"top": {d}, "right": {d}, "bottom": {d}, "left": {d}}},
        \\      "width_percent": {d},
        \\      "height_percent": {d},
        \\      "min_width_px": {d},
        \\      "min_height_px": {d},
        \\      "max_width_px": {d},
        \\      "max_height_px": {d}
        \\    }}
        \\  }},
        \\  "notifications": {{
        \\    "actions": {{
        \\      "show_close_button": {s},
        \\      "show_dbus_actions": {s}
        \\    }}
        \\  }}
        \\}}
        \\
    , .{
        @tagName(surface_mode),
        @tagName(launcher.window.anchor),
        @tagName(launcher.window.monitor.policy),
        launcher_monitor_name,
        launcher.window.margins.top,
        launcher.window.margins.right,
        launcher.window.margins.bottom,
        launcher.window.margins.left,
        launcher.width_percent,
        launcher.height_percent,
        launcher.min_width_percent,
        launcher.min_height_percent,
        launcher.min_width_px,
        launcher.min_height_px,
        launcher.max_width_px,
        launcher.max_height_px,

        @tagName(notifications.window.anchor),
        @tagName(notifications.window.monitor.policy),
        notify_monitor_name,
        notifications.window.margins.top,
        notifications.window.margins.right,
        notifications.window.margins.bottom,
        notifications.window.margins.left,
        notifications.width_percent,
        notifications.height_percent,
        notifications.min_width_px,
        notifications.min_height_px,
        notifications.max_width_px,
        notifications.max_height_px,
        if (cfg.notification_actions.show_close_button) "true" else "false",
        if (cfg.notification_actions.show_dbus_actions) "true" else "false",
    });

    try out.flush();
}
