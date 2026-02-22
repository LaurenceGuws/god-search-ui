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
    const report = try registry.collectAllWithReport(allocator, query_candidates);
    had_provider_runtime_failure.* = report.had_runtime_failure;
    return search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
}
