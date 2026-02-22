const std = @import("std");
const search = @import("../search/mod.zig");

pub const ProviderStatus = struct {
    name: []const u8,
    health: search.ProviderHealth,
};

pub const ProviderCollectFailure = struct {
    provider_name: []const u8,
    err: anyerror,
};

pub const CollectReport = struct {
    had_runtime_failure: bool = false,
    runtime_failure_count: usize = 0,
    first_runtime_failure: ?ProviderCollectFailure = null,
};

pub const ProviderRegistry = struct {
    providers: []const search.Provider,

    pub fn init(providers: []const search.Provider) ProviderRegistry {
        return .{ .providers = providers };
    }

    pub fn collectAll(self: ProviderRegistry, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        _ = try self.collectAllWithReport(allocator, out);
    }

    pub fn collectAllWithReport(self: ProviderRegistry, allocator: std.mem.Allocator, out: *search.CandidateList) !CollectReport {
        var report = CollectReport{};
        for (self.providers) |provider| {
            provider.collect(allocator, out) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    report.had_runtime_failure = true;
                    report.runtime_failure_count += 1;
                    if (report.first_runtime_failure == null) {
                        report.first_runtime_failure = .{
                            .provider_name = provider.name,
                            .err = err,
                        };
                    }
                    std.log.warn("provider '{s}' collect failed: {s}", .{ provider.name, @errorName(err) });
                },
            };
        }
        return report;
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

test "registry continues after provider runtime failure" {
    const Fake = struct {
        const OkCtx = struct {
            title: []const u8,
        };

        fn collectOk(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
            const ctx: *OkCtx = @ptrCast(@alignCast(context));
            try out.append(allocator, search.Candidate.init(.hint, ctx.title, "Provider", "noop"));
        }

        fn collectFail(_: *anyopaque, _: std.mem.Allocator, _: *search.CandidateList) !void {
            return error.RuntimeFailure;
        }

        fn healthReady(_: *anyopaque) search.ProviderHealth {
            return .ready;
        }
    };

    var ok = Fake.OkCtx{ .title = "ok" };
    var dummy_ctx: u8 = 0;

    const providers = [_]search.Provider{
        .{
            .name = "broken",
            .context = &dummy_ctx,
            .vtable = &.{ .collect = Fake.collectFail, .health = Fake.healthReady },
        },
        .{
            .name = "healthy",
            .context = &ok,
            .vtable = &.{ .collect = Fake.collectOk, .health = Fake.healthReady },
        },
    };

    const registry = ProviderRegistry.init(&providers);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const report = try registry.collectAllWithReport(std.testing.allocator, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("ok", list.items[0].title);
    try std.testing.expect(report.had_runtime_failure);
    try std.testing.expectEqual(@as(usize, 1), report.runtime_failure_count);
    try std.testing.expectEqualStrings("broken", report.first_runtime_failure.?.provider_name);
    try std.testing.expectEqual(error.RuntimeFailure, report.first_runtime_failure.?.err);
}
