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
    return rankCandidatesWithHistory(allocator, query, candidates, &.{});
}

pub fn rankCandidatesWithHistory(
    allocator: std.mem.Allocator,
    query: query_mod.Query,
    candidates: []const types.Candidate,
    recent_actions: []const []const u8,
) ![]ScoredCandidate {
    var scored = std.ArrayList(ScoredCandidate).empty;
    defer scored.deinit(allocator);

    const needle = try lowerAsciiLossyAlloc(allocator, query.term);
    defer allocator.free(needle);

    for (candidates) |candidate| {
        if (!matchesRoute(query.route, candidate.kind)) continue;
        const score = try candidateScore(allocator, needle, candidate, recent_actions);
        if (score <= 0 and needle.len > 0) continue;
        try scored.append(allocator, .{ .candidate = candidate, .score = score });
    }

    std.mem.sort(ScoredCandidate, scored.items, {}, lessThan);
    return scored.toOwnedSlice(allocator);
}

fn lessThan(_: void, a: ScoredCandidate, b: ScoredCandidate) bool {
    if (a.score != b.score) return a.score > b.score;

    const title_order = std.mem.order(u8, a.candidate.title, b.candidate.title);
    if (title_order != .eq) return title_order == .lt;

    const subtitle_order = std.mem.order(u8, a.candidate.subtitle, b.candidate.subtitle);
    if (subtitle_order != .eq) return subtitle_order == .lt;

    const action_order = std.mem.order(u8, a.candidate.action, b.candidate.action);
    if (action_order != .eq) return action_order == .lt;

    if (a.candidate.kind != b.candidate.kind) {
        return @intFromEnum(a.candidate.kind) < @intFromEnum(b.candidate.kind);
    }

    const icon_order = std.mem.order(u8, a.candidate.icon, b.candidate.icon);
    return icon_order == .lt;
}

fn matchesRoute(route: query_mod.Route, kind: types.CandidateKind) bool {
    return switch (route) {
        .blended => true,
        .apps => kind == .app,
        .windows => kind == .window,
        .workspaces => kind == .workspace,
        .dirs => kind == .dir,
        .files => kind == .file or kind == .dir,
        .grep => kind == .grep,
        .run, .calc => true,
        .web => kind == .web,
    };
}

fn candidateScore(
    allocator: std.mem.Allocator,
    needle: []const u8,
    candidate: types.Candidate,
    recent_actions: []const []const u8,
) !i32 {
    var score: i32 = baseWeight(candidate.kind);
    if (needle.len == 0) {
        score += recencyBoost(candidate.action, recent_actions);
        return score;
    }

    const title = try lowerAsciiLossyAlloc(allocator, candidate.title);
    defer allocator.free(title);
    const subtitle = try lowerAsciiLossyAlloc(allocator, candidate.subtitle);
    defer allocator.free(subtitle);

    if (std.mem.eql(u8, needle, title)) score += 100;
    if (std.mem.startsWith(u8, title, needle)) score += 60;
    if (std.mem.indexOf(u8, title, needle) != null) score += 30;
    if (subtitle.len > 0 and std.mem.indexOf(u8, subtitle, needle) != null) score += 10;

    if (std.mem.indexOf(u8, title, needle) == null and
        (subtitle.len == 0 or std.mem.indexOf(u8, subtitle, needle) == null))
    {
        return 0;
    }
    score += shortQueryBias(needle.len, candidate.kind);
    score += recencyBoost(candidate.action, recent_actions);
    return score;
}

fn lowerAsciiLossyAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    for (input, 0..) |ch, i| {
        out[i] = if (std.ascii.isAscii(ch)) std.ascii.toLower(ch) else ch;
    }
    return out;
}

fn shortQueryBias(needle_len: usize, kind: types.CandidateKind) i32 {
    if (needle_len == 0 or needle_len > 2) return 0;
    return switch (kind) {
        .action => 50,
        .app => 0,
        .window => -5,
        .workspace => -4,
        .dir => -10,
        .file => -8,
        .grep => -6,
        .web => 0,
        .hint => 0,
    };
}

fn recencyBoost(action: []const u8, recent_actions: []const []const u8) i32 {
    for (recent_actions, 0..) |recent, idx| {
        if (!std.mem.eql(u8, recent, action)) continue;
        const decay = @as(i32, @intCast(idx)) * 5;
        const bonus = 40 - decay;
        return if (bonus > 0) bonus else 0;
    }
    return 0;
}

fn baseWeight(kind: types.CandidateKind) i32 {
    return switch (kind) {
        .app => 100,
        .window => 90,
        .workspace => 88,
        .dir => 80,
        .file => 78,
        .grep => 76,
        .web => 72,
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

test "empty apps route keeps app-only scoring order" {
    const candidates = [_]types.Candidate{
        .init(.app, "Firefox", "Browser", "firefox"),
        .init(.action, "Focus Firefox", "Window action", "focus-firefox"),
        .init(.app, "Alacritty", "Terminal", "alacritty"),
    };

    const query = query_mod.parse("@ ");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqual(types.CandidateKind.app, ranked[0].candidate.kind);
    try std.testing.expectEqual(types.CandidateKind.app, ranked[1].candidate.kind);
    try std.testing.expectEqualStrings("Alacritty", ranked[0].candidate.title);
    try std.testing.expectEqualStrings("Firefox", ranked[1].candidate.title);
}

test "files route includes file and directory candidates" {
    const candidates = [_]types.Candidate{
        .init(.file, "main.zig", "/tmp/main.zig", "/tmp/main.zig"),
        .init(.dir, "src", "/tmp/src", "/tmp/src"),
        .init(.app, "kitty", "Terminal", "kitty"),
    };

    const query = query_mod.parse("% ");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqual(types.CandidateKind.dir, ranked[0].candidate.kind);
    try std.testing.expectEqual(types.CandidateKind.file, ranked[1].candidate.kind);
}

test "recency history boosts repeated action candidates" {
    const candidates = [_]types.Candidate{
        .init(.action, "Settings", "System", "settings"),
        .init(.action, "Power menu", "Session", "power"),
    };
    const history = [_][]const u8{"power"};
    const query = query_mod.parse("p");
    const ranked = try rankCandidatesWithHistory(std.testing.allocator, query, &candidates, &history);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 1), ranked.len);
    try std.testing.expectEqualStrings("Power menu", ranked[0].candidate.title);
}

test "short blended query prefers actions over broad app matches" {
    const candidates = [_]types.Candidate{
        .init(.app, "Redis Desktop Manager", "Database GUI", "redis-desktop"),
        .init(.action, "Restart Waybar", "Session", "waybar-restart"),
    };

    const query = query_mod.parse("re");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqual(types.CandidateKind.action, ranked[0].candidate.kind);
    try std.testing.expectEqualStrings("Restart Waybar", ranked[0].candidate.title);
}

test "rankCandidates propagates canonicalization alloc failure" {
    var zero_buf: [0]u8 = .{};
    var fba = std.heap.FixedBufferAllocator.init(&zero_buf);
    const candidates = [_]types.Candidate{};

    const query = query_mod.parse("a");
    try std.testing.expectError(
        error.OutOfMemory,
        rankCandidates(fba.allocator(), query, &candidates),
    );
}

test "rankCandidates propagates candidate canonicalization alloc failure" {
    var failing_state = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 1,
    });
    const failing_allocator = failing_state.allocator();
    const candidates = [_]types.Candidate{
        .init(.app, "alpha", "subtitle", "alpha"),
    };

    const query = query_mod.parse("a");
    try std.testing.expectError(
        error.OutOfMemory,
        rankCandidates(failing_allocator, query, &candidates),
    );
    try std.testing.expect(failing_state.has_induced_failure);
}

test "equal score and title uses deterministic tie-breakers" {
    const candidates = [_]types.Candidate{
        .init(.app, "Alpha", "Same", "z-action"),
        .init(.app, "Alpha", "Same", "a-action"),
    };

    const query = query_mod.parse("");
    const ranked = try rankCandidates(std.testing.allocator, query, &candidates);
    defer std.testing.allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqualStrings("a-action", ranked[0].candidate.action);
    try std.testing.expectEqualStrings("z-action", ranked[1].candidate.action);
}
