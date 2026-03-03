const std = @import("std");
const dynamic_routes = @import("dynamic_routes.zig");

pub const PruneReport = struct {
    removed_generations: usize = 0,
    removed_items: usize = 0,
    removed_bytes: usize = 0,
};

pub const Metrics = struct {
    generation_count: usize = 0,
    owned_item_count: usize = 0,
    owned_bytes: usize = 0,
};

pub const Generation = struct {
    id: u64,
    owned: std.ArrayListUnmanaged([]u8) = .{},
    pins: usize = 0,
};

pub const BeginPinned = struct {
    id: u64,
    owned: *std.ArrayListUnmanaged([]u8),
};

var next_generation_id = std.atomic.Value(u64).init(1);

pub fn beginPinned(
    generations: *std.ArrayListUnmanaged(Generation),
    allocator: std.mem.Allocator,
) !BeginPinned {
    const id = next_generation_id.fetchAdd(1, .monotonic);
    try generations.append(allocator, .{ .id = id, .pins = 1 });
    const generation = &generations.items[generations.items.len - 1];
    return .{ .id = id, .owned = &generation.owned };
}

pub fn finishPinned(
    generations: *std.ArrayListUnmanaged(Generation),
    id: u64,
    keep: usize,
    max_owned_bytes: usize,
    allocator: std.mem.Allocator,
    retain: bool,
) PruneReport {
    const idx = indexOfGeneration(generations.items, id) orelse {
        return prune(generations, keep, max_owned_bytes, allocator);
    };

    var should_remove = false;
    var report = PruneReport{};
    {
        const generation = &generations.items[idx];
        if (generation.pins > 0) generation.pins -= 1;
        if (!retain) {
            dynamic_routes.clearOwned(&generation.owned, allocator);
            should_remove = generation.pins == 0;
        }
    }

    if (should_remove) {
        var removed = generations.orderedRemove(idx);
        const removed_items = removed.owned.items.len;
        const removed_bytes = generationBytes(&removed);
        dynamic_releaseGeneration(&removed, allocator);
        report = PruneReport{
            .removed_generations = 1,
            .removed_items = removed_items,
            .removed_bytes = removed_bytes,
        };
    }

    const pruned = prune(generations, keep, max_owned_bytes, allocator);
    report.removed_generations += pruned.removed_generations;
    report.removed_items += pruned.removed_items;
    report.removed_bytes += pruned.removed_bytes;
    return report;
}

pub fn prune(
    generations: *std.ArrayListUnmanaged(Generation),
    keep: usize,
    max_owned_bytes: usize,
    allocator: std.mem.Allocator,
) PruneReport {
    var report = PruneReport{};
    if (keep == 0 and generations.items.len == 0) return report;

    var unpinned: usize = 0;
    for (generations.items) |generation| {
        if (generation.pins == 0) unpinned += 1;
    }
    const max_bytes = if (max_owned_bytes == 0)
        std.math.maxInt(usize)
    else
        max_owned_bytes;

    var total_bytes = metrics(generations.items).owned_bytes;

    var idx: usize = 0;
    while ((unpinned > keep or total_bytes > max_bytes) and idx < generations.items.len) {
        if (generations.items[idx].pins != 0) {
            idx += 1;
            continue;
        }
        var removed = generations.orderedRemove(idx);
        const removed_items = removed.owned.items.len;
        const removed_bytes = generationBytes(&removed);
        report.removed_generations += 1;
        report.removed_items += removed_items;
        report.removed_bytes += removed_bytes;
        if (total_bytes >= removed_bytes) {
            total_bytes -= removed_bytes;
        } else {
            total_bytes = 0;
        }
        unpinned -= 1;
        dynamic_releaseGeneration(&removed, allocator);
    }

    return report;
}

pub fn clear(
    generations: *std.ArrayListUnmanaged(Generation),
    allocator: std.mem.Allocator,
) void {
    for (generations.items) |*generation| {
        dynamic_releaseGeneration(generation, allocator);
    }
    generations.deinit(allocator);
}

fn dynamic_releaseGeneration(generation: *Generation, allocator: std.mem.Allocator) void {
    dynamic_routes.clearOwned(&generation.owned, allocator);
    generation.owned.deinit(allocator);
}

pub fn metrics(generations: []const Generation) Metrics {
    var out = Metrics{
        .generation_count = generations.len,
        .owned_item_count = 0,
        .owned_bytes = 0,
    };
    for (generations) |generation| {
        out.owned_item_count += generation.owned.items.len;
        out.owned_bytes += generationBytes(&generation);
    }
    return out;
}

fn generationBytes(generation: *const Generation) usize {
    var total: usize = 0;
    for (generation.owned.items) |item| {
        total += item.len;
    }
    return total;
}

fn indexOfGeneration(items: []Generation, id: u64) ?usize {
    for (items, 0..) |item, idx| {
        if (item.id == id) return idx;
    }
    return null;
}

test "beginPinned appends a pinned generation and returns it" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "one"));

    try std.testing.expectEqual(@as(usize, 1), generations.items.len);
    try std.testing.expectEqual(@as(usize, 1), generations.items[0].pins);
    try std.testing.expectEqual(@as(usize, 1), generations.items[0].owned.items.len);
}

test "finishPinned with retain keeps generation and unpins" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "kept"));

    finishPinned(&generations, first.id, 1, 0, allocator, true);

    try std.testing.expectEqual(@as(usize, 1), generations.items.len);
    try std.testing.expectEqual(@as(usize, 0), generations.items[0].pins);
    try std.testing.expectEqualStrings("kept", generations.items[0].owned.items[0]);
}

test "finishPinned without retain drops failed generation" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "discard"));

    finishPinned(&generations, first.id, 2, 0, allocator, false);

    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}

test "prune removes oldest unpinned when byte cap exceeded" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "small"));
    finishPinned(&generations, first.id, 10, 100, allocator, true);

    const second = try beginPinned(&generations, allocator);
    try second.owned.append(allocator, try allocator.dupe(u8, "bigger-entry"));
    finishPinned(&generations, second.id, 10, 100, allocator, true);

    const report = prune(&generations, 10, 5, allocator);
    const stats = metrics(generations.items);

    try std.testing.expect(report.removed_generations >= 1);
    try std.testing.expect(stats.generation_count <= 1);
    try std.testing.expect(stats.owned_bytes < 1000);
}

test "prune removes oldest unpinned generations and preserves pinned" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "oldest"));
    finishPinned(&generations, first.id, 10, 0, allocator, true);

    const second = try beginPinned(&generations, allocator);
    try second.owned.append(allocator, try allocator.dupe(u8, "pinned"));

    const third = try beginPinned(&generations, allocator);
    try third.owned.append(allocator, try allocator.dupe(u8, "newest"));
    finishPinned(&generations, third.id, 10, 0, allocator, true);

    _ = prune(&generations, 1, std.math.maxInt(usize), allocator);

    try std.testing.expectEqual(@as(usize, 2), generations.items.len);
    try std.testing.expectEqualStrings("pinned", generations.items[0].owned.items[0]);
    try std.testing.expectEqual(@as(usize, 1), generations.items[0].pins);
    try std.testing.expectEqualStrings("newest", generations.items[1].owned.items[0]);
}

test "clear releases all generations and resets list" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "a"));
    finishPinned(&generations, first.id, 10, 0, allocator, true);

    const second = try beginPinned(&generations, allocator);
    try second.owned.append(allocator, try allocator.dupe(u8, "b"));
    finishPinned(&generations, second.id, 10, 0, allocator, true);

    clear(&generations, allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}
