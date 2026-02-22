const std = @import("std");
const providers = @import("../../providers/mod.zig");
const search = @import("../../search/mod.zig");
const cache_refresh = @import("cache_refresh.zig");
const cache_snapshots = @import("cache_snapshots.zig");

pub fn prewarmLocked(
    registry: providers.ProviderRegistry,
    allocator: std.mem.Allocator,
    cached_candidates: *search.CandidateList,
    cache_ready: *bool,
    cache_last_refresh_ns: *i128,
    refresh_requested: *bool,
    cached_rank_generations: *std.ArrayListUnmanaged([]search.Candidate),
    cache_generation_keep: usize,
) !providers.CollectReport {
    const report = try cache_refresh.prewarmProviders(
        registry,
        allocator,
        cached_candidates,
        cache_ready,
        cache_last_refresh_ns,
        refresh_requested,
    );
    const snapshot = try cache_snapshots.cloneCandidatesOwned(allocator, cached_candidates.items);
    try cached_rank_generations.append(allocator, snapshot);
    cache_snapshots.pruneGenerations(cached_rank_generations, cache_generation_keep, allocator);
    return report;
}

pub fn invalidateLocked(cache_ready: *bool, cache_last_refresh_ns: *i128, refresh_requested: *bool) void {
    cache_refresh.invalidateSnapshot(cache_ready, cache_last_refresh_ns, refresh_requested);
}

pub fn shouldDrain(refresh_requested: bool) bool {
    return refresh_requested;
}
