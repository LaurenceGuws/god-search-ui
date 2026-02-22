const std = @import("std");
const providers = @import("../../providers/mod.zig");
const search = @import("../../search/mod.zig");

pub fn prewarmProviders(
    registry: providers.ProviderRegistry,
    allocator: std.mem.Allocator,
    cached_candidates: *search.CandidateList,
    cache_ready: *bool,
    cache_last_refresh_ns: *i128,
    refresh_requested: *bool,
) !providers.CollectReport {
    cached_candidates.clearRetainingCapacity();
    const report = try registry.collectAllWithReport(allocator, cached_candidates);
    cache_ready.* = true;
    cache_last_refresh_ns.* = std.time.nanoTimestamp();
    refresh_requested.* = false;
    return report;
}

pub fn invalidateSnapshot(cache_ready: *bool, cache_last_refresh_ns: *i128, refresh_requested: *bool) void {
    cache_ready.* = false;
    cache_last_refresh_ns.* = 0;
    refresh_requested.* = false;
}

pub fn scheduleRefreshIfNeeded(
    cache_ready: bool,
    cache_ttl_ns: u64,
    cache_last_refresh_ns: i128,
    refresh_requested: *bool,
    last_query_used_stale_cache: *bool,
) void {
    if (!cache_ready) return;
    if (cache_ttl_ns == 0) {
        refresh_requested.* = true;
        last_query_used_stale_cache.* = true;
        return;
    }

    const now = std.time.nanoTimestamp();
    const age = now - cache_last_refresh_ns;
    if (age <= 0) return;
    if (@as(u64, @intCast(age)) >= cache_ttl_ns) {
        refresh_requested.* = true;
        last_query_used_stale_cache.* = true;
    }
}
