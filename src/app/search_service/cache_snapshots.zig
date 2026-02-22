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
    generations.deinit(allocator);
    generations.* = .{};
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

test "cloneCandidatesOwned deep copies candidate fields" {
    const allocator = std.testing.allocator;
    const source = [_]search.Candidate{
        search.Candidate.initWithIcon(.file, "Alpha", "/tmp/a", "open-a", "icon-a"),
        search.Candidate.initWithIcon(.grep, "Beta", "/tmp/b:2", "open-b:2", "icon-b"),
    };

    const cloned = try cloneCandidatesOwned(allocator, &source);
    defer freeCandidatesOwned(allocator, cloned);

    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expect(cloned[0].title.ptr != source[0].title.ptr);
    try std.testing.expect(cloned[0].subtitle.ptr != source[0].subtitle.ptr);
    try std.testing.expect(cloned[0].action.ptr != source[0].action.ptr);
    try std.testing.expect(cloned[0].icon.ptr != source[0].icon.ptr);

    var mutable_title = @constCast(cloned[0].title);
    mutable_title[0] = 'X';
    try std.testing.expectEqualStrings("Alpha", source[0].title);
    try std.testing.expectEqualStrings("Xlpha", cloned[0].title);
}

test "cloneCandidatesOwned handles allocation failures without leaks" {
    const Harness = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const source = [_]search.Candidate{
                search.Candidate.initWithIcon(
                    .file,
                    "very-long-title-for-allocation-pressure",
                    "very-long-subtitle-for-allocation-pressure",
                    "very-long-action-for-allocation-pressure",
                    "very-long-icon-for-allocation-pressure",
                ),
            };
            const cloned = try cloneCandidatesOwned(allocator, &source);
            defer freeCandidatesOwned(allocator, cloned);
        }
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, Harness.run, .{});
}

test "latest returns empty for no generations and newest otherwise" {
    const empty = latest(&.{});
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    var g1 = [_]search.Candidate{search.Candidate.init(.action, "one", "s", "a")};
    var g2 = [_]search.Candidate{search.Candidate.init(.action, "two", "s", "a")};
    const sets = [_][]search.Candidate{ g1[0..], g2[0..] };

    const newest = latest(sets[0..]);
    try std.testing.expectEqualStrings("two", newest[0].title);
}

test "pruneGenerations removes oldest snapshots" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged([]search.Candidate){};
    defer {
        clearGenerations(&generations, allocator);
        generations.deinit(allocator);
    }

    const s1 = [_]search.Candidate{search.Candidate.initWithIcon(.action, "old", "s1", "a1", "i1")};
    const s2 = [_]search.Candidate{search.Candidate.initWithIcon(.action, "new", "s2", "a2", "i2")};
    try generations.append(allocator, try cloneCandidatesOwned(allocator, &s1));
    try generations.append(allocator, try cloneCandidatesOwned(allocator, &s2));

    pruneGenerations(&generations, 1, allocator);
    try std.testing.expectEqual(@as(usize, 1), generations.items.len);
    try std.testing.expectEqualStrings("new", generations.items[0][0].title);
}

test "clearGenerations frees snapshots and keeps container reusable" {
    const allocator = std.testing.allocator;
    var generations = std.ArrayListUnmanaged([]search.Candidate){};
    defer generations.deinit(allocator);

    const s1 = [_]search.Candidate{search.Candidate.initWithIcon(.action, "first", "s", "a", "i")};
    try generations.append(allocator, try cloneCandidatesOwned(allocator, &s1));

    clearGenerations(&generations, allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);

    const s2 = [_]search.Candidate{search.Candidate.initWithIcon(.action, "second", "s", "a", "i")};
    try generations.append(allocator, try cloneCandidatesOwned(allocator, &s2));
    try std.testing.expectEqual(@as(usize, 1), generations.items.len);

    clearGenerations(&generations, allocator);
    try std.testing.expectEqual(@as(usize, 0), generations.items.len);
}
