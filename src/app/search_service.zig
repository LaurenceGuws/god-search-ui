const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");

pub const SearchService = struct {
    registry: providers.ProviderRegistry,
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
        for (self.history.items) |item| allocator.free(item);
        self.history.deinit(allocator);
        self.cached_candidates.deinit(allocator);
    }

    pub fn searchQuery(self: *SearchService, allocator: std.mem.Allocator, raw_query: []const u8) ![]search.ScoredCandidate {
        const sw = @import("metrics.zig").Stopwatch.start();
        self.last_query_refreshed_cache = false;
        self.last_query_used_stale_cache = false;
        try self.scheduleRefreshIfNeeded();
        if (self.enable_async_refresh) self.startAsyncRefreshWorker() catch {};
        var query_candidates = search.CandidateList.empty;
        defer query_candidates.deinit(allocator);

        const parsed = search.parseQuery(raw_query);
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

    pub fn prewarmProviders(self: *SearchService, allocator: std.mem.Allocator) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        self.cached_candidates.clearRetainingCapacity();
        try self.registry.collectAll(allocator, &self.cached_candidates);
        self.cache_ready = true;
        self.cache_last_refresh_ns = std.time.nanoTimestamp();
        self.refresh_requested = false;
    }

    pub fn invalidateSnapshot(self: *SearchService) void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        self.cache_ready = false;
        self.cache_last_refresh_ns = 0;
        self.refresh_requested = false;
    }

    pub fn drainScheduledRefresh(self: *SearchService, allocator: std.mem.Allocator) !bool {
        self.cache_mu.lock();
        const requested = self.refresh_requested;
        self.cache_mu.unlock();
        if (!requested) return false;
        try self.prewarmProviders(allocator);
        self.last_query_refreshed_cache = true;
        return true;
    }

    fn scheduleRefreshIfNeeded(self: *SearchService) !void {
        self.cache_mu.lock();
        defer self.cache_mu.unlock();
        if (!self.cache_ready) return;
        if (self.cache_ttl_ns == 0) {
            self.refresh_requested = true;
            self.last_query_used_stale_cache = true;
            return;
        }

        const now = std.time.nanoTimestamp();
        const age = now - self.cache_last_refresh_ns;
        if (age <= 0) return;
        if (@as(u64, @intCast(age)) >= self.cache_ttl_ns) {
            self.refresh_requested = true;
            self.last_query_used_stale_cache = true;
        }
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
        if (action.len == 0) return;
        const copy = try allocator.dupe(u8, action);
        try self.history.append(allocator, copy);

        if (self.history.items.len > self.max_history) {
            const oldest = self.history.orderedRemove(0);
            allocator.free(oldest);
        }
    }

    pub fn loadHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        const path = self.history_path orelse return;
        const data = readFileAnyPath(allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer allocator.free(data);

        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            try self.recordSelection(allocator, trimmed);
        }
    }

    pub fn saveHistory(self: *SearchService, allocator: std.mem.Allocator) !void {
        const path = self.history_path orelse return;

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        const writer = out.writer(allocator);

        for (self.history.items) |entry| {
            try writer.print("{s}\n", .{entry});
        }
        try writeFileAnyPath(path, out.items);
    }

    fn historyViewNewestFirst(self: *SearchService, allocator: std.mem.Allocator) ![]const []const u8 {
        var out = std.ArrayList([]const u8).empty;
        defer out.deinit(allocator);

        var idx = self.history.items.len;
        while (idx > 0) : (idx -= 1) {
            try out.append(allocator, self.history.items[idx - 1]);
        }
        return out.toOwnedSlice(allocator);
    }
};

fn readFileAnyPath(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, max_bytes);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

fn writeFileAnyPath(path: []const u8, data: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        try ensureParentDirAbsolute(path);
        const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = data,
    });
}

fn ensureParentDirAbsolute(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try std.fs.makeDirAbsolute(parent);
}

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
