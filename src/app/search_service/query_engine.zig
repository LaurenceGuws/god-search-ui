const std = @import("std");
const providers = @import("../../providers/mod.zig");
const search = @import("../../search/mod.zig");

pub fn rankFromCacheOrCollect(
    allocator: std.mem.Allocator,
    registry: providers.ProviderRegistry,
    parsed: search.Query,
    recent: []const []const u8,
    cache_snapshot: []const search.Candidate,
    query_candidates: *search.CandidateList,
    had_provider_runtime_failure: *bool,
) ![]search.ScoredCandidate {
    if (cache_snapshot.len > 0) {
        return rankFromCacheSnapshot(allocator, parsed, recent, cache_snapshot, had_provider_runtime_failure);
    }
    return collectAndRank(allocator, registry, parsed, recent, query_candidates, had_provider_runtime_failure);
}

pub fn rankFromCacheSnapshot(
    allocator: std.mem.Allocator,
    parsed: search.Query,
    recent: []const []const u8,
    cache_snapshot: []const search.Candidate,
    had_provider_runtime_failure: *bool,
) ![]search.ScoredCandidate {
    had_provider_runtime_failure.* = false;
    return search.rankCandidatesWithHistory(allocator, parsed, cache_snapshot, recent);
}

pub fn collectAndRank(
    allocator: std.mem.Allocator,
    registry: providers.ProviderRegistry,
    parsed: search.Query,
    recent: []const []const u8,
    query_candidates: *search.CandidateList,
    had_provider_runtime_failure: *bool,
) ![]search.ScoredCandidate {
    if (parsed.route == .web) {
        had_provider_runtime_failure.* = false;
        try providers.appendWebRouteCandidates(allocator, parsed, query_candidates);
        var rank_query = parsed;
        if (providers.parseWebCommand(parsed.term)) |cmd| {
            switch (cmd) {
                .bookmark => |b| rank_query.term = b.query,
                .search => {},
            }
        }
        return search.rankCandidatesWithHistory(allocator, rank_query, query_candidates.items, recent);
    }

    const report = try registry.collectAllWithReport(allocator, query_candidates);
    had_provider_runtime_failure.* = report.had_runtime_failure;
    return search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
}

test "collectAndRank web route bypasses registry providers and emits web result" {
    const Fake = struct {
        fn collectFail(_: *anyopaque, _: std.mem.Allocator, _: *search.CandidateList) !void {
            return error.ShouldNotBeCalled;
        }

        fn healthReady(_: *anyopaque) search.ProviderHealth {
            return .ready;
        }
    };

    var dummy: u8 = 0;
    const fake_providers = [_]search.Provider{
        .{
            .name = "broken-if-called",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collectFail, .health = Fake.healthReady },
        },
    };
    const registry = providers.ProviderRegistry.init(&fake_providers);

    var query_candidates = search.CandidateList.empty;
    defer query_candidates.deinit(std.testing.allocator);
    var had_failure = true;
    const ranked = try collectAndRank(
        std.testing.allocator,
        registry,
        search.parseQuery("? dota 2"),
        &.{},
        &query_candidates,
        &had_failure,
    );
    defer std.testing.allocator.free(ranked);

    try std.testing.expect(!had_failure);
    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    try std.testing.expectEqual(search.CandidateKind.web, ranked[0].candidate.kind);
    try std.testing.expectEqualStrings("dota 2", ranked[0].candidate.action);
}

test "collectAndRank web selector row renders parsed query and preserves executable payload" {
    const Fake = struct {
        fn collectFail(_: *anyopaque, _: std.mem.Allocator, _: *search.CandidateList) !void {
            return error.ShouldNotBeCalled;
        }

        fn healthReady(_: *anyopaque) search.ProviderHealth {
            return .ready;
        }
    };

    var dummy: u8 = 0;
    const fake_providers = [_]search.Provider{
        .{
            .name = "broken-if-called",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collectFail, .health = Fake.healthReady },
        },
    };
    const registry = providers.ProviderRegistry.init(&fake_providers);

    var query_candidates = search.CandidateList.empty;
    defer query_candidates.deinit(std.testing.allocator);
    var had_failure = true;
    const ranked = try collectAndRank(
        std.testing.allocator,
        registry,
        search.parseQuery("?W Zig language"),
        &.{},
        &query_candidates,
        &had_failure,
    );
    defer std.testing.allocator.free(ranked);

    try std.testing.expect(!had_failure);
    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    try std.testing.expectEqual(search.CandidateKind.web, ranked[0].candidate.kind);
    try std.testing.expectEqualStrings("Search Wikipedia", ranked[0].candidate.title);
    try std.testing.expectEqualStrings("Zig language", ranked[0].candidate.subtitle);
    try std.testing.expectEqualStrings("W Zig language", ranked[0].candidate.action);
}
