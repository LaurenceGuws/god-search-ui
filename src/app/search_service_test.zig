const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");
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
