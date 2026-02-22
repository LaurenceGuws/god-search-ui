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
) ![]search.ScoredCandidate {
    if (cache_snapshot.len > 0) {
        return search.rankCandidatesWithHistory(allocator, parsed, cache_snapshot, recent);
    }
    try registry.collectAll(allocator, query_candidates);
    return search.rankCandidatesWithHistory(allocator, parsed, query_candidates.items, recent);
}
