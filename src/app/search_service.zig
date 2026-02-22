const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");
const history_store = @import("search_service/history_store.zig");
const cache_refresh = @import("search_service/cache_refresh.zig");
const cache_snapshots = @import("search_service/cache_snapshots.zig");
const dynamic_generations = @import("search_service/dynamic_generations.zig");
const dynamic_routes = @import("search_service/dynamic_routes.zig");
const query_metrics = @import("search_service/query_metrics.zig");

pub const SearchService = struct {
    registry: providers.ProviderRegistry,
    query_mu: std.Thread.Mutex = .{},
    history_path: ?[]const u8 = null,
    history: std.ArrayListUnmanaged([]u8) = .{},
    cache_mu: std.Thread.Mutex = .{},
    cached_candidates: search.CandidateList = .empty,
    cached_rank_generations: std.ArrayListUnmanaged([]search.Candidate) = .{},
    cache_generation_keep: usize = 4,
    cache_ready: bool = false,
    cache_last_refresh_ns: i128 = 0,
    cache_ttl_ns: u64 = 30 * std.time.ns_per_s,
    enable_async_refresh: bool = false,
    refresh_requested: bool = false,
    refresh_thread_running: bool = false,
    refresh_thread: ?std.Thread = null,
    dynamic_mu: std.Thread.Mutex = .{},
    dynamic_tool_state: dynamic_routes.ToolState = .{},
    dynamic_generations: std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)) = .{},
    dynamic_generation_keep: usize = 12,
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
        cache_snapshots.clearGenerations(&self.cached_rank_generations, allocator);
        dynamic_generations.clear(&self.dynamic_generations, allocator);
        for (self.history.items) |item| allocator.free(item);
        self.history.deinit(allocator);
        self.cached_candidates.deinit(allocator);
    }

    pub fn searchQuery(self: *SearchService, allocator: std.mem.Allocator, raw_query: []const u8) ![]search.ScoredCandidate {
        const sw = @import("metrics.zig").Stopwatch.start();
        self.resetQueryMetrics();

        const parsed = search.parseQuery(raw_query);
        if (parsed.route == .files or parsed.route == .grep) {
            const ranked_dynamic = try self.searchDynamicRoute(allocator, parsed);
            self.setQueryElapsed(sw.elapsedNs());
            return ranked_dynamic;
        }

        try self.scheduleRefreshIfNeeded();
        if (self.enable_async_refresh) self.startAsyncRefreshWorker() catch {};
        var query_candidates = search.CandidateList.empty;
        defer query_candidates.deinit(allocator);

        const recent = try self.historySnapshotNewestFirstOwned(allocator);
        defer history_store.freeOwnedHistorySnapshot(allocator, recent);

        self.cache_mu.lock();
        if (self.cache_ready) {
            const cache_snapshot = cache_snapshots.latest(self.cached_rank_generations.items);
            if (cache_snapshot.len == 0) {
                self.cache_mu.unlock();
                try self.registry.collectAll(allocator, &query_candidates);
                const ranked_fallback = try search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
                self.setQueryElapsed(sw.elapsedNs());
                return ranked_fallback;
            }
            self.cache_mu.unlock();
            const ranked_cached = try search.rankCandidatesWithHistory(allocator, parsed, cache_snapshot, recent);
            self.setQueryElapsed(sw.elapsedNs());
            return ranked_cached;
        }
        self.cache_mu.unlock();

        try self.registry.collectAll(allocator, &query_candidates);
        const ranked = try search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
        self.setQueryElapsed(sw.elapsedNs());
        return ranked;
    }

    fn searchDynamicRoute(self: *SearchService, allocator: std.mem.Allocator, query: search.Query) ![]search.ScoredCandidate {
        // Dynamic route candidates reference owned strings stored in retained generations.
        // We keep a bounded number of generations to cap long-session memory growth.
        var dynamic_candidates = search.CandidateList.empty;
        defer dynamic_candidates.deinit(allocator);
        const term = std.mem.trim(u8, query.term, " \t\r\n");
        if (term.len == 0) return allocator.alloc(search.ScoredCandidate, 0);
        {
            self.dynamic_mu.lock();
            defer self.dynamic_mu.unlock();

            const generation = try dynamic_generations.begin(&self.dynamic_generations, allocator);
            dynamic_routes.collectForRoute(&self.dynamic_tool_state, generation, allocator, query, &dynamic_candidates) catch {};
            dynamic_generations.prune(&self.dynamic_generations, self.dynamic_generation_keep, allocator);
        }

        const recent = try self.historySnapshotNewestFirstOwned(allocator);
        defer history_store.freeOwnedHistorySnapshot(allocator, recent);
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
        const snapshot = try cache_snapshots.cloneCandidatesOwned(allocator, self.cached_candidates.items);
        try self.cached_rank_generations.append(allocator, snapshot);
        cache_snapshots.pruneGenerations(&self.cached_rank_generations, self.cache_generation_keep, allocator);
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
        query_metrics.markRefreshed(&self.last_query_refreshed_cache);
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

    fn historySnapshotNewestFirstOwned(self: *SearchService, allocator: std.mem.Allocator) ![]const []const u8 {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        return history_store.historySnapshotNewestFirstOwned(self.history.items, allocator);
    }

    fn setQueryElapsed(self: *SearchService, elapsed_ns: u64) void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        query_metrics.setElapsed(&self.last_query_elapsed_ns, elapsed_ns);
    }

    fn resetQueryMetrics(self: *SearchService) void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        query_metrics.resetFlags(&self.last_query_refreshed_cache, &self.last_query_used_stale_cache);
    }
};

test {
    _ = @import("search_service_test.zig");
}
