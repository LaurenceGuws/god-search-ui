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
