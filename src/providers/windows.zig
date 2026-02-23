const std = @import("std");
const search = @import("../search/mod.zig");
const wm_mod = @import("../wm/mod.zig");

pub const WindowsProvider = struct {
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    hyprland_backend: wm_mod.HyprlandBackend = .{},
    backend_override: ?wm_mod.Backend = null,

    pub fn deinit(self: *WindowsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
    }

    pub fn provider(self: *WindowsProvider) search.Provider {
        return .{
            .name = "windows",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *WindowsProvider = @ptrCast(@alignCast(context));
        const wm_backend = self.backend();
        if (!wm_backend.capabilities().windows) {
            return;
        }
        if (wm_backend.health() == .unavailable) return;

        var snapshot = wm_backend.listWindows(allocator) catch |err| {
            std.log.warn("windows provider query failed: {s}", .{@errorName(err)});
            return;
        };
        defer snapshot.deinit(allocator);
        self.rotateOwnedStringsForCollect(allocator);

        for (snapshot.items) |row| {
            const kept_title = try self.keepString(allocator, row.title);
            const kept_class = try self.keepString(allocator, row.class_name);
            const kept_address = try self.keepString(allocator, row.id);
            try out.append(allocator, search.Candidate.init(.window, kept_title, kept_class, kept_address));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *WindowsProvider = @ptrCast(@alignCast(context));
        return switch (self.backend().health()) {
            .ready => .ready,
            .degraded => .degraded,
            .unavailable => .unavailable,
        };
    }

    fn keepString(self: *WindowsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *WindowsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(
            std.ArrayListUnmanaged([]u8),
            &self.owned_strings_current,
            &self.owned_strings_previous,
        );
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *WindowsProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }

    fn backend(self: *WindowsProvider) wm_mod.Backend {
        return self.backend_override orelse self.hyprland_backend.backend();
    }
};

test "windows provider parses command rows into candidates" {
    const Fake = struct {
        var health_state: wm_mod.Health = .ready;
        fn listWindows(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WindowSnapshot {
            var items = try allocator.alloc(wm_mod.WindowInfo, 2);
            items[0] = .{
                .title = try allocator.dupe(u8, "Terminal"),
                .class_name = try allocator.dupe(u8, "kitty"),
                .id = try allocator.dupe(u8, "0xabc"),
            };
            items[1] = .{
                .title = try allocator.dupe(u8, "Browser"),
                .class_name = try allocator.dupe(u8, "zen"),
                .id = try allocator.dupe(u8, "0xdef"),
            };
            return .{ .items = items };
        }

        fn health(_: *anyopaque) wm_mod.Health {
            return health_state;
        }

        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .windows = true };
        }
    };
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = Fake.listWindows,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WindowsProvider{
        .backend_override = fake_backend,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.ready, provider.health());
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.window, list.items[0].kind);
    try std.testing.expectEqualStrings("Terminal", list.items[0].title);
    try std.testing.expectEqualStrings("kitty", list.items[0].subtitle);
    try std.testing.expectEqualStrings("0xabc", list.items[0].action);
}

test "windows provider reports unavailable when tools are unavailable" {
    const Fake = struct {
        fn listWindows(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WindowSnapshot {
            _ = allocator;
            return .{ .items = &.{} };
        }

        fn health(_: *anyopaque) wm_mod.Health {
            return .unavailable;
        }

        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .windows = true };
        }
    };
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = Fake.listWindows,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WindowsProvider{
        .backend_override = fake_backend,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.unavailable, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "windows provider runtime query failure degrades health while keeping UX graceful" {
    const Fake = struct {
        var health_state: wm_mod.Health = .ready;
        fn listWindows(_: *anyopaque, _: std.mem.Allocator) !wm_mod.WindowSnapshot {
            health_state = .degraded;
            return error.WindowQueryFailed;
        }

        fn health(_: *anyopaque) wm_mod.Health {
            return health_state;
        }

        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .windows = true };
        }
    };
    Fake.health_state = .ready;
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = Fake.listWindows,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WindowsProvider{
        .backend_override = fake_backend,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
}

test "windows provider keeps prior generations alive on transient failure" {
    const Fake = struct {
        var mode: u8 = 0;
        var health_state: wm_mod.Health = .ready;

        fn oneWindowSnapshot(allocator: std.mem.Allocator, title: []const u8, class_name: []const u8, id: []const u8) !wm_mod.WindowSnapshot {
            var items = try allocator.alloc(wm_mod.WindowInfo, 1);
            items[0] = .{
                .title = try allocator.dupe(u8, title),
                .class_name = try allocator.dupe(u8, class_name),
                .id = try allocator.dupe(u8, id),
            };
            return .{ .items = items };
        }

        fn listWindows(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WindowSnapshot {
            return switch (mode) {
                0 => oneWindowSnapshot(allocator, "Terminal", "kitty", "0xaaa"),
                1 => oneWindowSnapshot(allocator, "Browser", "zen", "0xbbb"),
                else => blk: {
                    health_state = .degraded;
                    break :blk error.WindowQueryFailed;
                },
            };
        }

        fn health(_: *anyopaque) wm_mod.Health {
            return health_state;
        }

        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .windows = true };
        }
    };
    Fake.mode = 0;
    Fake.health_state = .ready;
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = Fake.listWindows,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WindowsProvider{
        .backend_override = fake_backend,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_title = list.items[0].title;
    const first_action = list.items[0].action;

    list.clearRetainingCapacity();
    Fake.mode = 1;
    try provider.collect(std.testing.allocator, &list);
    const second_title = list.items[0].title;
    const second_action = list.items[0].action;

    const total_before_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 6), total_before_failure);

    list.clearRetainingCapacity();
    Fake.mode = 2;
    try provider.collect(std.testing.allocator, &list);

    const total_after_failure = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(total_before_failure, total_after_failure);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqualStrings("Terminal", first_title);
    try std.testing.expectEqualStrings("0xaaa", first_action);
    try std.testing.expectEqualStrings("Browser", second_title);
    try std.testing.expectEqualStrings("0xbbb", second_action);
}

test "windows provider maps hyprland backend runtime parse without jq escapes dependency" {
    const FakeHypr = struct {
        fn hasTools() bool {
            return true;
        }

        fn listJson(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\[
                \\ {"mapped":true,"workspace":{"id":1},"title":"Title\\tTabbed\\nName","class":"zen","address":"0xabc"}
                \\]
            );
        }
    };

    var provider_impl = WindowsProvider{
        .hyprland_backend = .{
            .list_windows_json_fn = FakeHypr.listJson,
            .has_tools_fn = FakeHypr.hasTools,
        },
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Title\tTabbed\nName", list.items[0].title);
    try std.testing.expectEqualStrings("zen", list.items[0].subtitle);
    try std.testing.expectEqualStrings("0xabc", list.items[0].action);
}

test "windows provider rotates owned strings across collects with bounded growth" {
    const Fake = struct {
        fn hasTools() bool {
            return true;
        }

        fn listWindows(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\Terminal\tkitty\t0xabc
                \\Browser\tzen\t0xdef
                \\
            );
        }
    };

    var provider_impl = WindowsProvider{
        .list_windows_fn = Fake.listWindows,
        .has_tools_fn = Fake.hasTools,
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 6), first_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const second_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 12), second_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const third_total = provider_impl.owned_strings_current.items.len + provider_impl.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 12), third_total);
}
