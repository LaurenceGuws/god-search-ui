const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");
const history_store = @import("search_service/history_store.zig");
const cache_refresh = @import("search_service/cache_refresh.zig");
const dynamic_routes = @import("search_service/dynamic_routes.zig");

pub const SearchService = struct {
    registry: providers.ProviderRegistry,
    query_mu: std.Thread.Mutex = .{},
    history_path: ?[]const u8 = null,
    history: std.ArrayListUnmanaged([]u8) = .{},
    cache_mu: std.Thread.Mutex = .{},
    cached_candidates: search.CandidateList = .empty,
    cache_ready: bool = false,
    cache_last_refresh_ns: i128 = 0,
    cache_ttl_ns: u64 = 30 * std.time.ns_per_s,
    enable_async_refresh: bool = false,
    refresh_requested: bool = false,
    refresh_thread_running: bool = false,
    refresh_thread: ?std.Thread = null,
    dynamic_owned: std.ArrayListUnmanaged([]u8) = .{},
    max_history: usize = 32,
    last_query_elapsed_ns: u64 = 0,
    last_query_refreshed_cache: bool = false,
    last_query_used_stale_cache: bool = false,

    pub fn init(registry: providers.ProviderRegistry) SearchService {
        return .{ .registry = registry };
    }

    pub fn initWithHistoryPath(registry: providers.ProviderRegistry, history_path: []const u8) SearchService {
        return .{
            .registry = registry,
            .history_path = history_path,
        };
    }

    pub fn deinit(self: *SearchService, allocator: std.mem.Allocator) void {
        if (self.refresh_thread) |t| t.join();
        dynamic_routes.clearOwned(&self.dynamic_owned, allocator);
        for (self.history.items) |item| allocator.free(item);
        self.history.deinit(allocator);
        self.cached_candidates.deinit(allocator);
    }

    pub fn searchQuery(self: *SearchService, allocator: std.mem.Allocator, raw_query: []const u8) ![]search.ScoredCandidate {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        const sw = @import("metrics.zig").Stopwatch.start();
        self.last_query_refreshed_cache = false;
        self.last_query_used_stale_cache = false;

        const parsed = search.parseQuery(raw_query);
        if (parsed.route == .files or parsed.route == .grep) {
            const ranked_dynamic = try self.searchDynamicRoute(allocator, parsed);
            self.last_query_elapsed_ns = sw.elapsedNs();
            return ranked_dynamic;
        }

        try self.scheduleRefreshIfNeeded();
        if (self.enable_async_refresh) self.startAsyncRefreshWorker() catch {};
        var query_candidates = search.CandidateList.empty;
        defer query_candidates.deinit(allocator);

        const recent = try self.historyViewNewestFirst(allocator);
        defer allocator.free(recent);

        self.cache_mu.lock();
        if (self.cache_ready) {
            const ranked_cached = search.rankCandidatesWithHistory(allocator, parsed, self.cached_candidates.items, recent) catch |err| {
                self.cache_mu.unlock();
                return err;
            };
            self.cache_mu.unlock();
            self.last_query_elapsed_ns = sw.elapsedNs();
            return ranked_cached;
        }
        self.cache_mu.unlock();

        try self.registry.collectAll(allocator, &query_candidates);
        const ranked = try search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
        self.last_query_elapsed_ns = sw.elapsedNs();
        return ranked;
    }

    fn searchDynamicRoute(self: *SearchService, allocator: std.mem.Allocator, query: search.Query) ![]search.ScoredCandidate {
        // Dynamic route candidates are copied by async GTK workers after this call returns.
        // Clearing shared dynamic-owned buffers here can invalidate slices still in use.
        // Keep them alive for process lifetime and release in deinit.
        var dynamic_candidates = search.CandidateList.empty;
        defer dynamic_candidates.deinit(allocator);
        const term = std.mem.trim(u8, query.term, " \t\r\n");
        if (term.len == 0) return allocator.alloc(search.ScoredCandidate, 0);
        dynamic_routes.collectForRoute(&self.dynamic_owned, allocator, query, &dynamic_candidates) catch {};

        const recent = try self.historyViewNewestFirst(allocator);
        defer allocator.free(recent);
        return search.rankCandidatesWithHistory(allocator, query, dynamic_candidates.items, recent);
    }

    pub fn prewarmProviders(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        try cache_refresh.prewarmProviders(
            self.registry,
            allocator,
            &self.cached_candidates,
            &self.cache_ready,
            &self.cache_last_refresh_ns,
            &self.refresh_requested,
        );
    }

    pub fn invalidateSnapshot(self: *SearchService) void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        cache_refresh.invalidateSnapshot(&self.cache_ready, &self.cache_last_refresh_ns, &self.refresh_requested);
    }

    pub fn drainScheduledRefresh(self: *SearchService, allocator: std.mem.Allocator) !bool {
        self.cache_mu.lock();
        const requested = self.refresh_requested;
        self.cache_mu.unlock();
        if (!requested) return false;
        try self.prewarmProviders(allocator);
        self.query_mu.lock();
        self.last_query_refreshed_cache = true;
        self.query_mu.unlock();
        return true;
    }

    fn scheduleRefreshIfNeeded(self: *SearchService) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        cache_refresh.scheduleRefreshIfNeeded(
            self.cache_ready,
            self.cache_ttl_ns,
            self.cache_last_refresh_ns,
            &self.refresh_requested,
            &self.last_query_used_stale_cache,
        );
    }

    fn startAsyncRefreshWorker(self: *SearchService) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        if (!self.enable_async_refresh) return;
        if (!self.refresh_requested) return;
        if (self.refresh_thread_running) return;
        self.refresh_thread_running = true;
        self.refresh_thread = try std.Thread.spawn(.{}, refreshWorkerMain, .{self});
    }

    fn refreshWorkerMain(self: *SearchService) void {
        _ = self.drainScheduledRefresh(std.heap.page_allocator) catch {};
        self.cache_mu.lock();
        self.refresh_thread_running = false;
        self.cache_mu.unlock();
    }

    pub fn recordSelection(self: *SearchService, allocator: std.mem.Allocator, action: []const u8) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_store.recordSelection(&self.history, self.max_history, allocator, action);
    }

    pub fn loadHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_store.loadHistory(&self.history, self.max_history, self.history_path, allocator);
    }

    pub fn saveHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_store.saveHistory(self.history.items, self.history_path, allocator);
    }

    fn historyViewNewestFirst(self: *SearchService, allocator: std.mem.Allocator) ![]const []const u8 {
        return history_store.historyViewNewestFirst(self.history.items, allocator);
    }
};

test "search service applies history boost through ranking" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
            try out.append(allocator, search.Candidate.init(.action, "Power menu", "Session", "power"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);

    try service.recordSelection(std.testing.allocator, "power");
    const results = try service.searchQuery(std.testing.allocator, "p");
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Power menu", results[0].candidate.title);
}

test "prewarm cache avoids repeated provider collection" {
    const Fake = struct {
        var collect_calls: usize = 0;

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            collect_calls += 1;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    Fake.collect_calls = 0;
    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);

    try service.prewarmProviders(std.testing.allocator);
    const a = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(a);
    const b = try service.searchQuery(std.testing.allocator, "set");
    defer std.testing.allocator.free(b);
    try std.testing.expectEqual(@as(usize, 1), Fake.collect_calls);
}

test "invalidateSnapshot forces provider recollection" {
    const Fake = struct {
        var collect_calls: usize = 0;

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            collect_calls += 1;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    Fake.collect_calls = 0;
    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);
    try service.prewarmProviders(std.testing.allocator);
    const a = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(a);
    service.invalidateSnapshot();
    const b = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(b);
    try std.testing.expectEqual(@as(usize, 2), Fake.collect_calls);
}

test "stale refresh marks last_query_refreshed_cache" {
    const Fake = struct {
        var collect_calls: usize = 0;

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            collect_calls += 1;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    Fake.collect_calls = 0;
    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);
    service.cache_ttl_ns = 0;
    try service.prewarmProviders(std.testing.allocator);
    const ranked = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(ranked);

    try std.testing.expect(service.last_query_used_stale_cache);
    try std.testing.expect(!service.last_query_refreshed_cache);
    try std.testing.expect(service.refresh_requested);
    const refreshed = try service.drainScheduledRefresh(std.testing.allocator);
    try std.testing.expect(refreshed);
    try std.testing.expect(!service.refresh_requested);
    try std.testing.expectEqual(@as(usize, 2), Fake.collect_calls);
}

test "history load and save roundtrip" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = allocator;
            _ = context;
            _ = out;
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "history.log",
        .data =
        \\settings
        \\power
        \\
        ,
    });

    const history_path = try tmp.dir.realpathAlloc(std.testing.allocator, "history.log");
    defer std.testing.allocator.free(history_path);

    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.initWithHistoryPath(registry, history_path);
    defer service.deinit(std.testing.allocator);

    try service.loadHistory(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), service.history.items.len);
    try std.testing.expectEqualStrings("power", service.history.items[1]);

    try service.recordSelection(std.testing.allocator, "notifications");
    try service.saveHistory(std.testing.allocator);

    const persisted = try std.fs.cwd().readFileAlloc(std.testing.allocator, history_path, 1024);
    defer std.testing.allocator.free(persisted);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "notifications\n") != null);
}

test "optional async refresh worker can execute scheduled refresh" {
    const Fake = struct {
        var collect_calls: usize = 0;

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            collect_calls += 1;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    Fake.collect_calls = 0;
    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);
    service.enable_async_refresh = true;
    service.cache_ttl_ns = 0;
    try service.prewarmProviders(std.testing.allocator);
    const ranked = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(ranked);
    std.time.sleep(20 * std.time.ns_per_ms);
    try std.testing.expect(Fake.collect_calls >= 2);
}
