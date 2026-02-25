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

    if (argValueAfterFlag(args, "--ctl")) |raw_cmd| {
        const cmd = parseControlCommand(raw_cmd) orelse {
            std.process.exit(13);
        };
        const ok = god_search_ui.ipc.control.trySendCommand(allocator, cmd) catch false;
        if (ok) {
            std.process.exit(0);
        }
        std.process.exit(10);
    }

    const ui_mode = hasArg(args, "--ui") or hasArg(args, "--ui-resident") or hasArg(args, "--ui-daemon");
    if (ui_mode) {
        const resident_mode = hasArg(args, "--ui-resident") or hasArg(args, "--ui-daemon");
        const start_hidden = hasArg(args, "--ui-daemon");
        if (!resident_mode and hasArg(args, "--ui")) {
            const summoned = god_search_ui.ipc.control.trySendCommand(allocator, .summon) catch false;
            if (summoned) return;
        }
        var runtime = try setupRuntime(allocator);
        defer runtime.deinit(allocator);
        runtime.rebindProviderContexts();
        try runtime.service.loadHistory(allocator);
        defer runtime.service.saveHistory(allocator) catch |err| {
            logger.err("failed to save history: {s}", .{@errorName(err)});
        };
        logger.info("runtime ready in {d:.2} ms", .{startup_sw.elapsedMs()});
        try god_search_ui.ui.Shell.run(allocator, &runtime.service, &runtime.telemetry, .{
            .resident_mode = resident_mode,
            .start_hidden = start_hidden,
        });
        return;
    }

    logger.info("startup ready in {d:.2} ms", .{startup_sw.elapsedMs()});
    try god_search_ui.bufferedPrint();
}

const Runtime = struct {
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

    fn deinit(self: *Runtime, allocator: std.mem.Allocator) void {
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
};

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
    return null;
}
