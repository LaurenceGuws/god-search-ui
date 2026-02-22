const std = @import("std");
const search = @import("../../search/mod.zig");
const dynamic_routes = @import("dynamic_routes.zig");
const dynamic_generations = @import("dynamic_generations.zig");

pub const DynamicCollector = *const fn (
    tool_state: *dynamic_routes.ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    query: search.Query,
    out: *search.CandidateList,
) anyerror!void;

pub fn rankDynamicRoute(
    dynamic_mu: *std.Thread.Mutex,
    dynamic_tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    generation_keep: usize,
    allocator: std.mem.Allocator,
    query: search.Query,
    recent: []const []const u8,
) ![]search.ScoredCandidate {
    return rankDynamicRouteWithCollector(
        dynamic_mu,
        dynamic_tool_state,
        generations,
        generation_keep,
        allocator,
        query,
        recent,
        dynamic_routes.collectForRoute,
    );
}

pub fn rankDynamicRouteWithCollector(
    dynamic_mu: *std.Thread.Mutex,
    dynamic_tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    generation_keep: usize,
    allocator: std.mem.Allocator,
    query: search.Query,
    recent: []const []const u8,
    collector: DynamicCollector,
) ![]search.ScoredCandidate {
    var dynamic_candidates = search.CandidateList.empty;
    defer dynamic_candidates.deinit(allocator);
    const term = std.mem.trim(u8, query.term, " \t\r\n");
    if (term.len == 0) return allocator.alloc(search.ScoredCandidate, 0);

    dynamic_mu.lock();
    defer dynamic_mu.unlock();

    const generation = try dynamic_generations.begin(generations, allocator);
    collector(dynamic_tool_state, generation, allocator, query, &dynamic_candidates) catch {};
    const keep = @max(generation_keep, @as(usize, 1));
    dynamic_generations.prune(generations, keep, allocator);
    return search.rankCandidatesWithHistory(allocator, query, dynamic_candidates.items, recent);
}

var churn_slow_collected = std.atomic.Value(bool).init(false);
var churn_slow_done = std.atomic.Value(bool).init(false);
var churn_fast_done = std.atomic.Value(bool).init(false);
var churn_failed = std.atomic.Value(bool).init(false);

fn testKeepDynamicString(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) ![]const u8 {
    const copy = try allocator.dupe(u8, value);
    try dynamic_owned.append(allocator, copy);
    return copy;
}

fn testAppendSynthetic(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    count: usize,
    out: *search.CandidateList,
) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const title = try std.fmt.allocPrint(allocator, "entry-{d}", .{i});
        defer allocator.free(title);
        const action = try std.fmt.allocPrint(allocator, "/tmp/entry-{d}", .{i});
        defer allocator.free(action);
        const kept_title = try testKeepDynamicString(dynamic_owned, allocator, title);
        const kept_action = try testKeepDynamicString(dynamic_owned, allocator, action);
        try out.append(allocator, search.Candidate.init(.file, kept_title, kept_action, kept_action));
    }
}

fn churnCollector(
    _: *dynamic_routes.ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    query: search.Query,
    out: *search.CandidateList,
) !void {
    if (std.mem.eql(u8, query.term, "slow")) {
        churn_slow_collected.store(true, .release);
        try testAppendSynthetic(dynamic_owned, allocator, 12_000, out);
        return;
    }
    try testAppendSynthetic(dynamic_owned, allocator, 2, out);
}

fn slowChurnWorker(
    dynamic_mu: *std.Thread.Mutex,
    tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
) void {
    const ranked = rankDynamicRouteWithCollector(
        dynamic_mu,
        tool_state,
        generations,
        1,
        std.heap.page_allocator,
        search.parseQuery("% slow"),
        &.{},
        churnCollector,
    ) catch {
        churn_failed.store(true, .release);
        return;
    };
    std.heap.page_allocator.free(ranked);
    churn_slow_done.store(true, .release);
}

fn fastChurnWorker(
    dynamic_mu: *std.Thread.Mutex,
    tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
) void {
    const ranked = rankDynamicRouteWithCollector(
        dynamic_mu,
        tool_state,
        generations,
        1,
        std.heap.page_allocator,
        search.parseQuery("% fast"),
        &.{},
        churnCollector,
    ) catch {
        churn_failed.store(true, .release);
        return;
    };
    std.heap.page_allocator.free(ranked);
    churn_fast_done.store(true, .release);
}

test "rankDynamicRoute keeps generation lock through ranking under churn" {
    const allocator = std.testing.allocator;
    churn_slow_collected.store(false, .release);
    churn_slow_done.store(false, .release);
    churn_fast_done.store(false, .release);
    churn_failed.store(false, .release);

    var dynamic_mu = std.Thread.Mutex{};
    var tool_state = dynamic_routes.ToolState{};
    var generations = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)){};
    defer dynamic_generations.clear(&generations, allocator);

    const slow = try std.Thread.spawn(.{}, slowChurnWorker, .{ &dynamic_mu, &tool_state, &generations });
    while (!churn_slow_collected.load(.acquire)) {
        std.time.sleep(200 * std.time.ns_per_us);
    }

    const fast = try std.Thread.spawn(.{}, fastChurnWorker, .{ &dynamic_mu, &tool_state, &generations });
    std.time.sleep(2 * std.time.ns_per_ms);
    try std.testing.expect(!churn_fast_done.load(.acquire));

    slow.join();
    fast.join();

    try std.testing.expect(churn_slow_done.load(.acquire));
    try std.testing.expect(churn_fast_done.load(.acquire));
    try std.testing.expect(!churn_failed.load(.acquire));
}
