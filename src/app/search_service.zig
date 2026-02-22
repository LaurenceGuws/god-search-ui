const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");
const history_access = @import("search_service/history_access.zig");
const cache_read = @import("search_service/cache_read.zig");
const cache_refresh = @import("search_service/cache_refresh.zig");
const cache_coordinator = @import("search_service/cache_coordinator.zig");
const cache_snapshots = @import("search_service/cache_snapshots.zig");
const dynamic_generations = @import("search_service/dynamic_generations.zig");
const dynamic_query_engine = @import("search_service/dynamic_query_engine.zig");
const dynamic_routes = @import("search_service/dynamic_routes.zig");
const query_dispatch = @import("search_service/query_dispatch.zig");
const query_metrics_access = @import("search_service/query_metrics_access.zig");
const query_refresh_gate = @import("search_service/query_refresh_gate.zig");
const query_engine = @import("search_service/query_engine.zig");
const refresh_worker = @import("search_service/refresh_worker.zig");

pub const SearchService = struct {
    pub const QueryFlagsSnapshot = query_metrics_access.QueryFlagsSnapshot;

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
        if (self.refresh_thread) |t| {
            t.join();
            self.refresh_thread = null;
        }
        self.refresh_thread_running = false;

        self.cache_mu.lock();
        cache_snapshots.clearGenerations(&self.cached_rank_generations, allocator);
        self.cache_ready = false;
        self.refresh_requested = false;
        self.cache_last_refresh_ns = 0;
        self.cache_mu.unlock();

        dynamic_generations.clear(&self.dynamic_generations, allocator);
        history_access.deinitHistory(&self.history, allocator);
        self.cached_candidates.deinit(allocator);
    }

    pub fn searchQuery(self: *SearchService, allocator: std.mem.Allocator, raw_query: []const u8) ![]search.ScoredCandidate {
        const sw = @import("metrics.zig").Stopwatch.start();
        query_metrics_access.resetFlags(
            &self.query_mu,
            &self.last_query_refreshed_cache,
            &self.last_query_used_stale_cache,
        );

        const dispatch = query_dispatch.parseAndClassify(raw_query);
        if (dispatch.use_dynamic) {
            const ranked_dynamic = try self.searchDynamicRoute(allocator, dispatch.parsed);
            query_metrics_access.setElapsed(&self.query_mu, &self.last_query_elapsed_ns, sw.elapsedNs());
            return ranked_dynamic;
        }

        try self.prepareRefreshForStaticQuery();
        var query_candidates = search.CandidateList.empty;
        defer query_candidates.deinit(allocator);

        const recent = try self.historySnapshotNewestFirstOwned(allocator);
        defer history_access.freeSnapshot(allocator, recent);

        self.cache_mu.lock();
        const cache_view = cache_read.readViewLocked(self.cache_ready, &self.cached_rank_generations);
        self.cache_mu.unlock();
        if (cache_view.ready) {
            const ranked_cache_or_collect = try query_engine.rankFromCacheOrCollect(
                allocator,
                self.registry,
                dispatch.parsed,
                recent,
                cache_view.snapshot,
                &query_candidates,
            );
            query_metrics_access.setElapsed(&self.query_mu, &self.last_query_elapsed_ns, sw.elapsedNs());
            return ranked_cache_or_collect;
        }

        const ranked = try query_engine.rankFromCacheOrCollect(
            allocator,
            self.registry,
            dispatch.parsed,
            recent,
            &.{},
            &query_candidates,
        );
        query_metrics_access.setElapsed(&self.query_mu, &self.last_query_elapsed_ns, sw.elapsedNs());
        return ranked;
    }

    fn searchDynamicRoute(self: *SearchService, allocator: std.mem.Allocator, query: search.Query) ![]search.ScoredCandidate {
        // Dynamic route candidates reference owned strings stored in retained generations.
        // We keep a bounded number of generations to cap long-session memory growth.
        const recent = try self.historySnapshotNewestFirstOwned(allocator);
        defer history_access.freeSnapshot(allocator, recent);
        return dynamic_query_engine.rankDynamicRoute(
            &self.dynamic_mu,
            &self.dynamic_tool_state,
            &self.dynamic_generations,
            self.dynamic_generation_keep,
            allocator,
            query,
            recent,
        );
    }

    pub fn prewarmProviders(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        try cache_coordinator.prewarmLocked(
            self.registry,
            allocator,
            &self.cached_candidates,
            &self.cache_ready,
            &self.cache_last_refresh_ns,
            &self.refresh_requested,
            &self.cached_rank_generations,
            self.cache_generation_keep,
        );
    }

    pub fn invalidateSnapshot(self: *SearchService) void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        cache_coordinator.invalidateLocked(&self.cache_ready, &self.cache_last_refresh_ns, &self.refresh_requested);
    }

    pub fn drainScheduledRefresh(self: *SearchService, allocator: std.mem.Allocator) !bool {
        self.cache_mu.lock();
        const requested = self.refresh_requested;
        self.cache_mu.unlock();
        if (!cache_coordinator.shouldDrain(requested)) return false;
        try self.prewarmProviders(allocator);
        query_metrics_access.markRefreshed(&self.query_mu, &self.last_query_refreshed_cache);
        return true;
    }

    fn prepareRefreshForStaticQuery(self: *SearchService) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        if (!query_refresh_gate.scheduleAndShouldStartWorker(
            self.cache_ready,
            self.cache_ttl_ns,
            self.cache_last_refresh_ns,
            &self.refresh_requested,
            &self.last_query_used_stale_cache,
            self.enable_async_refresh,
            self.refresh_thread_running,
        )) return;
        refresh_worker.markRunning(&self.refresh_thread_running);
        errdefer refresh_worker.markStopped(&self.refresh_thread_running);
        self.refresh_thread = try std.Thread.spawn(.{}, refreshWorkerMain, .{self});
    }

    fn refreshWorkerMain(self: *SearchService) void {
        _ = self.drainScheduledRefresh(std.heap.page_allocator) catch {};
        self.cache_mu.lock();
        refresh_worker.markStopped(&self.refresh_thread_running);
        self.cache_mu.unlock();
    }

    pub fn recordSelection(self: *SearchService, allocator: std.mem.Allocator, action: []const u8) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_access.recordLocked(&self.history, self.max_history, allocator, action);
    }

    pub fn loadHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_access.loadLocked(&self.history, self.max_history, self.history_path, allocator);
    }

    pub fn saveHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        try history_access.saveLocked(self.history.items, self.history_path, allocator);
    }

    pub fn queryFlagsSnapshot(self: *SearchService) QueryFlagsSnapshot {
        return query_metrics_access.readFlags(
            &self.query_mu,
            &self.last_query_refreshed_cache,
            &self.last_query_used_stale_cache,
        );
    }

    fn historySnapshotNewestFirstOwned(self: *SearchService, allocator: std.mem.Allocator) ![]const []const u8 {
        self.query_mu.lock();
        defer self.query_mu.unlock();
        return history_access.snapshotNewestFirstOwnedLocked(self.history.items, allocator);
    }
};

test {
    _ = @import("search_service_test.zig");
}
