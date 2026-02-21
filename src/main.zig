const std = @import("std");
const god_search_ui = @import("god_search_ui");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const state = god_search_ui.app.bootstrap();
    const logger = god_search_ui.app.Logger.init(.info);
    logger.info("god-search-ui starting (mode={s})", .{@tagName(state.mode)});

    if (args.len > 1 and std.mem.eql(u8, args[1], "--ui")) {
        var runtime = try setupRuntime(allocator);
        defer runtime.deinit(allocator);
        try runtime.service.loadHistory(allocator);
        defer runtime.service.saveHistory(allocator) catch {};
        try god_search_ui.ui.Shell.run(allocator, &runtime.service);
        return;
    }

    try god_search_ui.bufferedPrint();
}

const Runtime = struct {
    app_cache_path: []u8,
    history_path: []u8,
    actions: god_search_ui.providers.ActionsProvider = .{},
    apps: god_search_ui.providers.AppsProvider,
    windows: god_search_ui.providers.WindowsProvider = .{},
    dirs: god_search_ui.providers.DirsProvider = .{},
    provider_list: [4]god_search_ui.search.Provider,
    service: god_search_ui.app.SearchService,

    fn deinit(self: *Runtime, allocator: std.mem.Allocator) void {
        self.apps.deinit(allocator);
        self.windows.deinit(allocator);
        self.dirs.deinit(allocator);
        self.service.deinit(allocator);
        allocator.free(self.app_cache_path);
        allocator.free(self.history_path);
    }
};

fn setupRuntime(allocator: std.mem.Allocator) !Runtime {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const app_cache = try std.fmt.allocPrint(allocator, "{s}/.cache/waybar/wofi-app-launcher.tsv", .{home});
    errdefer allocator.free(app_cache);
    const history_path = try std.fmt.allocPrint(allocator, "{s}/.local/state/god-search-ui/history.log", .{home});
    errdefer allocator.free(history_path);

    var apps = god_search_ui.providers.AppsProvider.init(app_cache);
    var windows = god_search_ui.providers.WindowsProvider{};
    var dirs = god_search_ui.providers.DirsProvider{};
    var actions = god_search_ui.providers.ActionsProvider{};

    const provider_list = [4]god_search_ui.search.Provider{
        actions.provider(),
        apps.provider(),
        windows.provider(),
        dirs.provider(),
    };

    const registry = god_search_ui.providers.ProviderRegistry.init(&provider_list);
    var service = god_search_ui.app.SearchService.initWithHistoryPath(registry, history_path);
    service.max_history = 64;

    return .{
        .app_cache_path = app_cache,
        .history_path = history_path,
        .actions = actions,
        .apps = apps,
        .windows = windows,
        .dirs = dirs,
        .provider_list = provider_list,
        .service = service,
    };
}
