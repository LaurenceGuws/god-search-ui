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
    generations: *std.ArrayListUnmanaged(dynamic_generations.Generation),
    generation_keep: usize,
    generation_keep_bytes: usize,
    allocator: std.mem.Allocator,
    query: search.Query,
    recent: []const []const u8,
) ![]search.ScoredCandidate {
    return rankDynamicRouteWithCollector(
        dynamic_mu,
        dynamic_tool_state,
        generations,
        generation_keep,
        generation_keep_bytes,
        allocator,
        query,
        recent,
        dynamic_routes.collectForRoute,
    );
}

pub fn rankDynamicRouteWithCollector(
    dynamic_mu: *std.Thread.Mutex,
    dynamic_tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(dynamic_generations.Generation),
    generation_keep: usize,
    generation_keep_bytes: usize,
    allocator: std.mem.Allocator,
    query: search.Query,
    recent: []const []const u8,
    collector: DynamicCollector,
) ![]search.ScoredCandidate {
    var dynamic_candidates = search.CandidateList.empty;
    defer dynamic_candidates.deinit(allocator);
    const term = std.mem.trim(u8, query.term, " \t\r\n");
    if (term.len == 0 and query.route != .notifications) return allocator.alloc(search.ScoredCandidate, 0);

    const keep = @max(generation_keep, @as(usize, 1));
    const keep_bytes = if (generation_keep_bytes == 0) std.math.maxInt(usize) else generation_keep_bytes;
    const query_hash = hashQuery(query);

    var generation: dynamic_generations.BeginPinned = undefined;
    {
        dynamic_mu.lock();
        defer dynamic_mu.unlock();

        generation = try dynamic_generations.beginPinned(generations, allocator);
        const started_at = std.time.nanoTimestamp();
        collector(dynamic_tool_state, generation.owned, allocator, query, &dynamic_candidates) catch |err| {
            std.log.err("dynamic collector failed for route {s}: {s}", .{ @tagName(query.route), @errorName(err) });
            _ = dynamic_generations.finishPinned(generations, generation.id, keep, keep_bytes, allocator, false);
            return err;
        };
        _ = dynamic_generations.prune(generations, keep, keep_bytes, allocator);
        std.log.debug(
            "dynamic collect route={s} query_hash={d} emitted={d} elapsed_ns={d}",
            .{
                @tagName(query.route),
                query_hash,
                dynamic_candidates.items.len,
                std.time.nanoTimestamp() - started_at,
            },
        );
    }

    var keep_generation = false;
    var prune_report = dynamic_generations.PruneReport{};
    defer {
        dynamic_mu.lock();
        const finished = dynamic_generations.finishPinned(
            generations,
            generation.id,
            keep,
            keep_bytes,
            allocator,
            keep_generation,
        );
        prune_report.removed_generations += finished.removed_generations;
        prune_report.removed_items += finished.removed_items;
        prune_report.removed_bytes += finished.removed_bytes;
        dynamic_mu.unlock();
        const after = dynamic_generations.metrics(generations.items);
        std.log.info(
            "dynamic route complete route={s} query_hash={d} query_term_len={d} emitted={d} generation_count={d} owned_items={d} owned_bytes={d} pruned_generations={d} pruned_items={d} pruned_bytes={d}",
            .{
                @tagName(query.route),
                query_hash,
                query.term.len,
                dynamic_candidates.items.len,
                after.generation_count,
                after.owned_item_count,
                after.owned_bytes,
                prune_report.removed_generations,
                prune_report.removed_items,
                prune_report.removed_bytes,
            },
        );
    }

    const ranked = try search.rankCandidatesWithHistory(allocator, query, dynamic_candidates.items, recent);
    keep_generation = true;
    std.log.info(
        "dynamic route ranked route={s} query_hash={d} ranked={d}",
        .{ @tagName(query.route), query_hash, ranked.len },
    );
    return ranked;
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
        try testAppendSynthetic(dynamic_owned, allocator, 40_000, out);
        churn_slow_collected.store(true, .release);
        return;
    }
    try testAppendSynthetic(dynamic_owned, allocator, 2, out);
}

fn slowChurnWorker(
    dynamic_mu: *std.Thread.Mutex,
    tool_state: *dynamic_routes.ToolState,
    generations: *std.ArrayListUnmanaged(dynamic_generations.Generation),
) void {
    const ranked = rankDynamicRouteWithCollector(
        dynamic_mu,
        tool_state,
        generations,
        1,
        0,
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
    generations: *std.ArrayListUnmanaged(dynamic_generations.Generation),
) void {
    const ranked = rankDynamicRouteWithCollector(
        dynamic_mu,
        tool_state,
        generations,
        1,
        0,
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

test "rankDynamicRoute releases generation lock before ranking under churn" {
    const allocator = std.testing.allocator;
    churn_slow_collected.store(false, .release);
    churn_slow_done.store(false, .release);
    churn_fast_done.store(false, .release);
    churn_failed.store(false, .release);

    var dynamic_mu = std.Thread.Mutex{};
    var tool_state = dynamic_routes.ToolState{};
    var generations = std.ArrayListUnmanaged(dynamic_generations.Generation){};
    defer dynamic_generations.clear(&generations, allocator);

    const slow = try std.Thread.spawn(.{}, slowChurnWorker, .{ &dynamic_mu, &tool_state, &generations });
    while (!churn_slow_collected.load(.acquire)) {
        std.time.sleep(200 * std.time.ns_per_us);
    }

    const fast = try std.Thread.spawn(.{}, fastChurnWorker, .{ &dynamic_mu, &tool_state, &generations });
    std.time.sleep(2 * std.time.ns_per_ms);
    try std.testing.expect(churn_fast_done.load(.acquire));

    slow.join();
    fast.join();

    try std.testing.expect(churn_slow_done.load(.acquire));
    try std.testing.expect(churn_fast_done.load(.acquire));
    try std.testing.expect(!churn_failed.load(.acquire));
}

fn failingCollector(
    _: *dynamic_routes.ToolState,
    _: *std.ArrayListUnmanaged([]u8),
    _: std.mem.Allocator,
    _: search.Query,
    _: *search.CandidateList,
) !void {
    return error.TestCollectorFailure;
}

test "rankDynamicRouteWithCollector propagates collector errors" {
    const allocator = std.testing.allocator;
    var dynamic_mu = std.Thread.Mutex{};
    var tool_state = dynamic_routes.ToolState{};
    var generations = std.ArrayListUnmanaged(dynamic_generations.Generation){};
    defer dynamic_generations.clear(&generations, allocator);

    try std.testing.expectError(
        error.TestCollectorFailure,
        rankDynamicRouteWithCollector(
            &dynamic_mu,
            &tool_state,
            &generations,
            2,
            0,
            allocator,
            search.parseQuery("% fail"),
            &.{},
            failingCollector,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}

fn hashQuery(query: search.Query) u64 {
    var hasher = std.hash.Wyhash.init(0);
    var route_buf: [16]u8 = undefined;
    std.mem.writeInt(u64, route_buf[0..8], @intFromEnum(query.route), .little);
    hasher.update(route_buf[0..8]);
    hasher.update(query.term);
    return hasher.final();
}
