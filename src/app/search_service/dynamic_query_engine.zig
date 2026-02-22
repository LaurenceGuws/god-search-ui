const std = @import("std");
const search = @import("../../search/mod.zig");
const dynamic_routes = @import("dynamic_routes.zig");
const dynamic_generations = @import("dynamic_generations.zig");

pub fn rankDynamicRoute(
    dynamic_mu: *std.Thread.Mutex,
    dynamic_tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    generation_keep: usize,
    allocator: std.mem.Allocator,
    query: search.Query,
    recent: []const []const u8,
) ![]search.ScoredCandidate {
    var dynamic_candidates = search.CandidateList.empty;
    defer dynamic_candidates.deinit(allocator);
    const term = std.mem.trim(u8, query.term, " \t\r\n");
    if (term.len == 0) return allocator.alloc(search.ScoredCandidate, 0);
    {
        dynamic_mu.lock();
        defer dynamic_mu.unlock();

        const generation = try dynamic_generations.begin(generations, allocator);
        dynamic_routes.collectForRoute(dynamic_tool_state, generation, allocator, query, &dynamic_candidates) catch {};
        dynamic_generations.prune(generations, generation_keep, allocator);
    }
    return search.rankCandidatesWithHistory(allocator, query, dynamic_candidates.items, recent);
}
