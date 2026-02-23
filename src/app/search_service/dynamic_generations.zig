const std = @import("std");
const dynamic_routes = @import("dynamic_routes.zig");

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
    allocator: std.mem.Allocator,
    retain: bool,
) void {
    const idx = indexOfGeneration(generations.items, id) orelse {
        prune(generations, keep, allocator);
        return;
    };

    var should_remove = false;
    {
        const generation = &generations.items[idx];
        if (generation.pins > 0) generation.pins -= 1;
        if (!retain) {
            dynamic_routes.clearOwned(&generation.owned, allocator);
            should_remove = generation.pins == 0;
        }
    }

    if (should_remove) {
        _ = generations.orderedRemove(idx);
    }

    prune(generations, keep, allocator);
}

pub fn prune(
    generations: *std.ArrayListUnmanaged(Generation),
    keep: usize,
    allocator: std.mem.Allocator,
) void {
    var unpinned: usize = 0;
    for (generations.items) |generation| {
        if (generation.pins == 0) unpinned += 1;
    }

    var idx: usize = 0;
    while (unpinned > keep and idx < generations.items.len) {
        if (generations.items[idx].pins != 0) {
            idx += 1;
            continue;
        }
        var removed = generations.orderedRemove(idx);
        dynamic_routes.clearOwned(&removed.owned, allocator);
        unpinned -= 1;
    }
}

pub fn clear(
    generations: *std.ArrayListUnmanaged(Generation),
    allocator: std.mem.Allocator,
) void {
    for (generations.items) |*generation| {
        dynamic_routes.clearOwned(&generation.owned, allocator);
    }
    generations.deinit(allocator);
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

    finishPinned(&generations, first.id, 1, allocator, true);

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

    finishPinned(&generations, first.id, 2, allocator, false);

    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}

test "prune removes oldest unpinned generations and preserves pinned" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(Generation){};
    defer clear(&generations, allocator);

    const first = try beginPinned(&generations, allocator);
    try first.owned.append(allocator, try allocator.dupe(u8, "oldest"));
    finishPinned(&generations, first.id, 10, allocator, true);

    const second = try beginPinned(&generations, allocator);
    try second.owned.append(allocator, try allocator.dupe(u8, "pinned"));

    const third = try beginPinned(&generations, allocator);
    try third.owned.append(allocator, try allocator.dupe(u8, "newest"));
    finishPinned(&generations, third.id, 10, allocator, true);

    prune(&generations, 1, allocator);

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
    finishPinned(&generations, first.id, 10, allocator, true);

    const second = try beginPinned(&generations, allocator);
    try second.owned.append(allocator, try allocator.dupe(u8, "b"));
    finishPinned(&generations, second.id, 10, allocator, true);

    clear(&generations, allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}
