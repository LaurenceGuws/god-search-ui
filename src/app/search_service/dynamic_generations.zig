const std = @import("std");
const dynamic_routes = @import("dynamic_routes.zig");

pub fn begin(
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    allocator: std.mem.Allocator,
) !*std.ArrayListUnmanaged([]u8) {
    try generations.append(allocator, .{});
    return &generations.items[generations.items.len - 1];
}

pub fn prune(
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    keep: usize,
    allocator: std.mem.Allocator,
) void {
    while (generations.items.len > keep) {
        var oldest = generations.orderedRemove(0);
        dynamic_routes.clearOwned(&oldest, allocator);
    }
}

pub fn clear(
    generations: *std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)),
    allocator: std.mem.Allocator,
) void {
    for (generations.items) |*generation| {
        dynamic_routes.clearOwned(generation, allocator);
    }
    generations.deinit(allocator);
}

test "begin appends a new generation and returns it" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)){};
    defer clear(&generations, allocator);

    const first = try begin(&generations, allocator);
    try first.append(allocator, try allocator.dupe(u8, "one"));

    try std.testing.expectEqual(@as(usize, 1), generations.items.len);
    try std.testing.expectEqual(@as(usize, 1), generations.items[0].items.len);
}

test "prune removes oldest generations and preserves newest" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)){};
    defer clear(&generations, allocator);

    const first = try begin(&generations, allocator);
    try first.append(allocator, try allocator.dupe(u8, "oldest"));
    const second = try begin(&generations, allocator);
    try second.append(allocator, try allocator.dupe(u8, "newest"));

    prune(&generations, 1, allocator);
    try std.testing.expectEqual(@as(usize, 1), generations.items.len);
    try std.testing.expectEqualStrings("newest", generations.items[0].items[0]);
}

test "clear releases all generations and resets list" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]u8)){};

    const first = try begin(&generations, allocator);
    try first.append(allocator, try allocator.dupe(u8, "a"));
    const second = try begin(&generations, allocator);
    try second.append(allocator, try allocator.dupe(u8, "b"));

    clear(&generations, allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}
