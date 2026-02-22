const std = @import("std");
const search = @import("../../search/mod.zig");

pub fn cloneCandidatesOwned(allocator: std.mem.Allocator, source: []const search.Candidate) ![]search.Candidate {
    var out = try allocator.alloc(search.Candidate, source.len);
    errdefer allocator.free(out);

    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const row = source[idx];
        const title = allocator.dupe(u8, row.title) catch |err| {
            freeCandidatesOwnedPartial(allocator, out[0..idx]);
            return err;
        };
        const subtitle = allocator.dupe(u8, row.subtitle) catch |err| {
            allocator.free(title);
            freeCandidatesOwnedPartial(allocator, out[0..idx]);
            return err;
        };
        const action = allocator.dupe(u8, row.action) catch |err| {
            allocator.free(title);
            allocator.free(subtitle);
            freeCandidatesOwnedPartial(allocator, out[0..idx]);
            return err;
        };
        const icon = allocator.dupe(u8, row.icon) catch |err| {
            allocator.free(title);
            allocator.free(subtitle);
            allocator.free(action);
            freeCandidatesOwnedPartial(allocator, out[0..idx]);
            return err;
        };
        out[idx] = .{
            .kind = row.kind,
            .title = title,
            .subtitle = subtitle,
            .action = action,
            .icon = icon,
        };
    }
    return out;
}

pub fn latest(generations: []const []search.Candidate) []const search.Candidate {
    if (generations.len == 0) return &.{};
    return generations[generations.len - 1];
}

pub fn pruneGenerations(
    generations: *std.ArrayListUnmanaged([]search.Candidate),
    keep: usize,
    allocator: std.mem.Allocator,
) void {
    while (generations.items.len > keep) {
        const oldest = generations.orderedRemove(0);
        freeCandidatesOwned(allocator, oldest);
    }
}

pub fn clearGenerations(generations: *std.ArrayListUnmanaged([]search.Candidate), allocator: std.mem.Allocator) void {
    for (generations.items) |snapshot| freeCandidatesOwned(allocator, snapshot);
    generations.clearRetainingCapacity();
}

fn freeCandidatesOwned(allocator: std.mem.Allocator, rows: []const search.Candidate) void {
    freeCandidatesOwnedPartial(allocator, rows);
    allocator.free(rows);
}

fn freeCandidatesOwnedPartial(allocator: std.mem.Allocator, rows: []const search.Candidate) void {
    for (rows) |row| {
        allocator.free(@constCast(row.title));
        allocator.free(@constCast(row.subtitle));
        allocator.free(@constCast(row.action));
        allocator.free(@constCast(row.icon));
    }
}
