const std = @import("std");
const providers = @import("../providers/mod.zig");
const search = @import("../search/mod.zig");

pub const SearchService = struct {
    registry: providers.ProviderRegistry,
    history: std.ArrayListUnmanaged([]u8) = .{},
    max_history: usize = 32,

    pub fn init(registry: providers.ProviderRegistry) SearchService {
        return .{ .registry = registry };
    }

    pub fn deinit(self: *SearchService, allocator: std.mem.Allocator) void {
        for (self.history.items) |item| allocator.free(item);
        self.history.deinit(allocator);
    }

    pub fn searchQuery(self: *SearchService, allocator: std.mem.Allocator, raw_query: []const u8) ![]search.ScoredCandidate {
        var candidates = search.CandidateList.empty;
        defer candidates.deinit(allocator);
        try self.registry.collectAll(allocator, &candidates);

        const parsed = search.parseQuery(raw_query);
        const recent = try self.historyViewNewestFirst(allocator);
        defer allocator.free(recent);

        return search.rankCandidatesWithHistory(allocator, parsed, candidates.items, recent);
    }

    pub fn recordSelection(self: *SearchService, allocator: std.mem.Allocator, action: []const u8) !void {
        if (action.len == 0) return;
        const copy = try allocator.dupe(u8, action);
        try self.history.append(allocator, copy);

        if (self.history.items.len > self.max_history) {
            const oldest = self.history.orderedRemove(0);
            allocator.free(oldest);
        }
    }

    fn historyViewNewestFirst(self: *SearchService, allocator: std.mem.Allocator) ![]const []const u8 {
        var out = std.ArrayList([]const u8).empty;
        defer out.deinit(allocator);

        var idx = self.history.items.len;
        while (idx > 0) : (idx -= 1) {
            try out.append(allocator, self.history.items[idx - 1]);
        }
        return out.toOwnedSlice(allocator);
    }
};

test "search service applies history boost through ranking" {
    const Fake = struct {
        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            _ = allocator;
            _ = context;
            try out.append(search.Candidate.init(.action, "Settings", "System", "settings"));
            try out.append(search.Candidate.init(.action, "Power menu", "Session", "power"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            _ = context;
            return .ready;
        }
    };

    var dummy: u8 = 0;
    const source = [_]search.Provider{
        .{
            .name = "fake",
            .context = &dummy,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = providers.ProviderRegistry.init(&source);
    var service = SearchService.init(registry);
    defer service.deinit(std.testing.allocator);

    try service.recordSelection(std.testing.allocator, "power");
    const results = try service.searchQuery(std.testing.allocator, "p");
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Power menu", results[0].candidate.title);
}
