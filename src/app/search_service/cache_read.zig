const std = @import("std");
const search = @import("../../search/mod.zig");
const cache_snapshots = @import("cache_snapshots.zig");

pub const CacheReadView = struct {
    ready: bool,
    snapshot: []const search.Candidate,
};

pub fn readViewLocked(
    cache_ready: bool,
    cached_rank_generations: *const std.ArrayListUnmanaged([]search.Candidate),
) CacheReadView {
    return .{
        .ready = cache_ready,
        .snapshot = cache_snapshots.latest(cached_rank_generations.items),
    };
}
