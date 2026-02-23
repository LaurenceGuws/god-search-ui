const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");
const cache_snapshots = @import("search_service/cache_snapshots.zig");
const refresh_worker = @import("search_service/refresh_worker.zig");
const SearchService = @import("search_service.zig").SearchService;

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

test "web route bypasses cached snapshot and still returns web result" {
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
    const ranked = try service.searchQuery(std.testing.allocator, "?g dota 2");
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    try std.testing.expectEqual(search.CandidateKind.web, ranked[0].candidate.kind);
    try std.testing.expect(std.mem.indexOf(u8, ranked[0].candidate.title, "dota 2") != null);
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

test "queryFlagsSnapshot exposes current query flags" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
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

    const initial_flags = service.queryFlagsSnapshot();
    try std.testing.expect(!initial_flags.last_query_used_stale_cache);
    try std.testing.expect(!initial_flags.last_query_refreshed_cache);
    try std.testing.expect(!initial_flags.last_query_had_provider_runtime_failure);

    service.cache_ttl_ns = 0;
    try service.prewarmProviders(std.testing.allocator);
    const ranked = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(ranked);

    const stale_flags = service.queryFlagsSnapshot();
    try std.testing.expect(stale_flags.last_query_used_stale_cache);
    try std.testing.expect(!stale_flags.last_query_refreshed_cache);
    try std.testing.expect(!stale_flags.last_query_had_provider_runtime_failure);

    _ = try service.drainScheduledRefresh(std.testing.allocator);
    const refreshed_flags = service.queryFlagsSnapshot();
    try std.testing.expect(refreshed_flags.last_query_refreshed_cache);
    try std.testing.expect(!refreshed_flags.last_query_had_provider_runtime_failure);
}

test "queryFlagsSnapshot surfaces provider runtime failure from cached snapshot collection" {
    const Fake = struct {
        const OkCtx = struct {
            title: []const u8,
        };

        fn collectOk(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            const ctx: *OkCtx = @ptrCast(@alignCast(context));
            try out.append(allocator, search.Candidate.init(.action, ctx.title, "System", "settings"));
        }

        fn collectFail(_: *anyopaque, _: std.mem.Allocator, _: *search.CandidateList) !void {
            return error.RuntimeFailure;
        }

        fn healthReady(_: *anyopaque) search.ProviderHealth {
            return .ready;
        }
    };

    var ok = Fake.OkCtx{ .title = "Settings" };
    var dummy_ctx: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "broken",
            .context = &dummy_ctx,
            .vtable = &.{ .collect = Fake.collectFail, .health = Fake.healthReady },
        },
        .{
            .name = "healthy",
            .context = &ok,
            .vtable = &.{ .collect = Fake.collectOk, .health = Fake.healthReady },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);

    try service.prewarmProviders(std.testing.allocator);
    const ranked = try service.searchQuery(std.testing.allocator, "set");
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    const flags = service.queryFlagsSnapshot();
    try std.testing.expect(flags.last_query_had_provider_runtime_failure);
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

test "next query reaps finished async refresh thread handle when no new refresh is needed" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
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
    service.enable_async_refresh = true;
    service.cache_ttl_ns = 0;
    try service.prewarmProviders(std.testing.allocator);

    const first = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(first);
    try std.testing.expect(service.refresh_thread != null);

    var attempts: usize = 0;
    while (service.refresh_thread_running and attempts < 200) : (attempts += 1) {
        std.time.sleep(1 * std.time.ns_per_ms);
    }
    try std.testing.expect(!service.refresh_thread_running);
    try std.testing.expect(service.refresh_thread != null);

    service.cache_ttl_ns = 60 * std.time.ns_per_s;
    const second = try service.searchQuery(std.testing.allocator, "");
    defer std.testing.allocator.free(second);

    try std.testing.expect(!service.refresh_thread_running);
    try std.testing.expect(service.refresh_thread == null);
}

test "concurrent query and drainScheduledRefresh does not deadlock" {
    const Fake = struct {
        var collect_calls: usize = 0;

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            collect_calls += 1;
            std.time.sleep(1 * std.time.ns_per_ms);
            try out.append(allocator, search.Candidate.init(.action, "Settings", "System", "settings"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    const Workers = struct {
        fn queryLoop(service: *SearchService, failed: *std.atomic.Value(bool)) void {
            var i: usize = 0;
            while (i < 80) : (i += 1) {
                const results = service.searchQuery(std.heap.page_allocator, "set") catch {
                    failed.store(true, .release);
                    return;
                };
                std.heap.page_allocator.free(results);
            }
        }

        fn refreshLoop(service: *SearchService, failed: *std.atomic.Value(bool)) void {
            var i: usize = 0;
            while (i < 80) : (i += 1) {
                service.invalidateSnapshot();
                _ = service.drainScheduledRefresh(std.heap.page_allocator) catch {
                    failed.store(true, .release);
                    return;
                };
            }
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
    var failed = std.atomic.Value(bool).init(false);
    const t1 = try std.Thread.spawn(.{}, Workers.queryLoop, .{ &service, &failed });
    const t2 = try std.Thread.spawn(.{}, Workers.refreshLoop, .{ &service, &failed });
    t1.join();
    t2.join();

    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expect(Fake.collect_calls > 0);
}

test "cached ranking holds cache generation lock against concurrent refresh churn" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = context;
            var i: usize = 0;
            while (i < 40_000) : (i += 1) {
                try out.append(allocator, search.Candidate.init(.action, "Entry", "System", "entry-action"));
            }
        }

        fn health(_: *anyopaque) search.ProviderHealth {
            return .ready;
        }
    };

    const Workers = struct {
        fn queryWorker(service: *SearchService, done: *std.atomic.Value(bool), failed: *std.atomic.Value(bool)) void {
            const ranked = service.searchQuery(std.heap.page_allocator, "entry") catch {
                failed.store(true, .release);
                return;
            };
            std.heap.page_allocator.free(ranked);
            done.store(true, .release);
        }

        fn refreshWorker(service: *SearchService, done: *std.atomic.Value(bool), failed: *std.atomic.Value(bool)) void {
            service.invalidateSnapshot();
            service.prewarmProviders(std.heap.page_allocator) catch {
                failed.store(true, .release);
                return;
            };
            done.store(true, .release);
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
    service.cache_generation_keep = 1;

    try service.prewarmProviders(std.testing.allocator);
    var query_done = std.atomic.Value(bool).init(false);
    var refresh_done = std.atomic.Value(bool).init(false);
    var failed = std.atomic.Value(bool).init(false);

    const query_thread = try std.Thread.spawn(.{}, Workers.queryWorker, .{ &service, &query_done, &failed });
    std.time.sleep(1 * std.time.ns_per_ms);
    const refresh_thread = try std.Thread.spawn(.{}, Workers.refreshWorker, .{ &service, &refresh_done, &failed });

    std.time.sleep(2 * std.time.ns_per_ms);
    try std.testing.expect(!refresh_done.load(.acquire));

    query_thread.join();
    refresh_thread.join();

    try std.testing.expect(query_done.load(.acquire));
    try std.testing.expect(refresh_done.load(.acquire));
    try std.testing.expect(!failed.load(.acquire));
}

test "cache generation clear releases backing storage and is idempotent" {
    var generations: std.ArrayListUnmanaged([]search.Candidate) = .{};

    var snapshot = try std.testing.allocator.alloc(search.Candidate, 1);
    snapshot[0] = .{
        .kind = .action,
        .title = try std.testing.allocator.dupe(u8, "Settings"),
        .subtitle = try std.testing.allocator.dupe(u8, "System"),
        .action = try std.testing.allocator.dupe(u8, "settings"),
        .icon = try std.testing.allocator.dupe(u8, ""),
    };

    try generations.append(std.testing.allocator, snapshot);
    try std.testing.expect(generations.capacity > 0);

    cache_snapshots.clearGenerations(&generations, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
    try std.testing.expectEqual(@as(usize, 0), generations.capacity);

    cache_snapshots.clearGenerations(&generations, std.testing.allocator);
}

test "refresh worker running flag can be rolled back after spawn failure" {
    var running = false;
    refresh_worker.markRunning(&running);
    refresh_worker.markStopped(&running);
    try std.testing.expect(!running);
}
