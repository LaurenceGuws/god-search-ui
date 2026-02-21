const std = @import("std");
const search = @import("../search/mod.zig");

pub const ProviderStatus = struct {
    name: []const u8,
    health: search.ProviderHealth,
};

pub const ProviderRegistry = struct {
    providers: []const search.Provider,

    pub fn init(providers: []const search.Provider) ProviderRegistry {
        return .{ .providers = providers };
    }

    pub fn collectAll(self: ProviderRegistry, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        for (self.providers) |provider| {
            provider.collect(allocator, out) catch {};
        }
    }

    pub fn healthSnapshot(self: ProviderRegistry, allocator: std.mem.Allocator) ![]ProviderStatus {
        var snapshot = std.ArrayList(ProviderStatus).empty;
        defer snapshot.deinit(allocator);

        for (self.providers) |provider| {
            try snapshot.append(allocator, .{
                .name = provider.name,
                .health = provider.health(),
            });
        }

        return snapshot.toOwnedSlice(allocator);
    }

    pub fn renderHealthReport(self: ProviderRegistry, allocator: std.mem.Allocator) ![]u8 {
        const statuses = try self.healthSnapshot(allocator);
        defer allocator.free(statuses);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);
        const writer = out.writer(allocator);

        for (statuses) |status| {
            try writer.print("{s}: {s}\n", .{ status.name, healthLabel(status.health) });
        }

        return out.toOwnedSlice(allocator);
    }
};

fn healthLabel(health: search.ProviderHealth) []const u8 {
    return switch (health) {
        .ready => "ready",
        .degraded => "degraded",
        .unavailable => "unavailable",
    };
}

test "registry aggregates provider candidates and reports health" {
    const Fake = struct {
        const Ctx = struct {
            health: search.ProviderHealth,
            title: []const u8,
        };

        fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            const ctx: *Ctx = @ptrCast(@alignCast(context));
            try out.append(allocator, search.Candidate.init(.hint, ctx.title, "Provider", "noop"));
        }

        fn health(context: *anyopaque) search.ProviderHealth {
            const ctx: *Ctx = @ptrCast(@alignCast(context));
            return ctx.health;
        }
    };

    var a = Fake.Ctx{ .health = .ready, .title = "A" };
    var b = Fake.Ctx{ .health = .degraded, .title = "B" };

    const providers = [_]search.Provider{
        .{
            .name = "one",
            .context = &a,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
        .{
            .name = "two",
            .context = &b,
            .vtable = &.{ .collect = Fake.collect, .health = Fake.health },
        },
    };

    const registry = ProviderRegistry.init(&providers);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);
    try registry.collectAll(std.testing.allocator, &list);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);

    const statuses = try registry.healthSnapshot(std.testing.allocator);
    defer std.testing.allocator.free(statuses);
    try std.testing.expectEqual(@as(usize, 2), statuses.len);
    try std.testing.expectEqual(search.ProviderHealth.ready, statuses[0].health);
    try std.testing.expectEqual(search.ProviderHealth.degraded, statuses[1].health);

    const report = try registry.renderHealthReport(std.testing.allocator);
    defer std.testing.allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "one: ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "two: degraded") != null);
}
