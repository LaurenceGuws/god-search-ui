const std = @import("std");
const query_mod = @import("query.zig");
const types = @import("types.zig");

pub const ScoredCandidate = struct {
    candidate: types.Candidate,
    score: i32,
};

pub fn rankCandidates(
    allocator: std.mem.Allocator,
    query: query_mod.Query,
    candidates: []const types.Candidate,
) ![]ScoredCandidate {
    var scored = std.ArrayList(ScoredCandidate).empty;
    defer scored.deinit(allocator);

    const needle = std.ascii.allocLowerString(allocator, query.term) catch "";
    defer if (needle.len > 0) allocator.free(needle);

    for (candidates) |candidate| {
        if (!matchesRoute(query.route, candidate.kind)) continue;
        const score = candidateScore(needle, candidate);
        if (score <= 0 and needle.len > 0) continue;
        try scored.append(allocator, .{ .candidate = candidate, .score = score });
    }

    std.mem.sort(ScoredCandidate, scored.items, {}, lessThan);
    return scored.toOwnedSlice(allocator);
}

fn lessThan(_: void, a: ScoredCandidate, b: ScoredCandidate) bool {
    if (a.score != b.score) return a.score > b.score;
    return std.mem.order(u8, a.candidate.title, b.candidate.title) == .lt;
}

fn matchesRoute(route: query_mod.Route, kind: types.CandidateKind) bool {
    return switch (route) {
        .blended => true,
        .apps => kind == .app,
        .windows => kind == .window,
        .dirs => kind == .dir,
        .run, .calc, .web => true,
    };
}

fn candidateScore(needle: []const u8, candidate: types.Candidate) i32 {
    var score: i32 = baseWeight(candidate.kind);
    if (needle.len == 0) return score;

    const title = std.ascii.allocLowerString(std.heap.page_allocator, candidate.title) catch return 0;
    defer std.heap.page_allocator.free(title);
    const subtitle = std.ascii.allocLowerString(std.heap.page_allocator, candidate.subtitle) catch "";
    defer if (subtitle.len > 0) std.heap.page_allocator.free(subtitle);

    if (std.mem.eql(u8, needle, title)) score += 100;
    if (std.mem.startsWith(u8, title, needle)) score += 60;
    if (std.mem.indexOf(u8, title, needle) != null) score += 30;
    if (subtitle.len > 0 and std.mem.indexOf(u8, subtitle, needle) != null) score += 10;

    if (std.mem.indexOf(u8, title, needle) == null and
        (subtitle.len == 0 or std.mem.indexOf(u8, subtitle, needle) == null))
    {
        return 0;
    }
    return score;
}

fn baseWeight(kind: types.CandidateKind) i32 {
    return switch (kind) {
        .app => 100,
        .window => 90,
        .dir => 80,
        .action => 70,
        .hint => 10,
    };
}

test "exact match outranks prefix match" {
    const candidates = [_]types.Candidate{
        .init(.app, "kitty", "Terminal", "kitty"),
        .init(.app, "kitty-manager", "Terminal", "km"),
    };

    const query = query_mod.parse("kitty");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqualStrings("kitty", ranked[0].candidate.title);
}

test "route filter limits result kinds" {
    const candidates = [_]types.Candidate{
        .init(.app, "kitty", "Terminal", "kitty"),
        .init(.window, "Terminal", "kitty", "0xabc"),
    };

    const query = query_mod.parse("@ term");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    try std.testing.expectEqual(types.CandidateKind.app, ranked[0].candidate.kind);
}
