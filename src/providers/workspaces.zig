const std = @import("std");
const search = @import("../search/mod.zig");
const wm_mod = @import("../wm/mod.zig");

pub const WorkspacesProvider = struct {
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    snapshot_mu: std.Thread.Mutex = .{},
    snapshot_items: []wm_mod.WorkspaceInfo = &.{},
    snapshot_ready: bool = false,
    hyprland_backend: wm_mod.HyprlandBackend = .{},
    backend_override: ?wm_mod.Backend = null,

    pub fn deinit(self: *WorkspacesProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
        self.clearSnapshot(allocator);
    }

    pub fn provider(self: *WorkspacesProvider) search.Provider {
        return .{
            .name = "workspaces",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *WorkspacesProvider = @ptrCast(@alignCast(context));
        const wm_backend = self.backend();
        if (!wm_backend.capabilities().workspaces) return;
        if (wm_backend.health() == .unavailable) return;

        self.snapshot_mu.lock();
        const has_snapshot = self.snapshot_ready;
        self.snapshot_mu.unlock();
        if (has_snapshot) {
            self.refreshSnapshot(allocator) catch |err| {
                std.log.warn("workspaces provider query failed: {s}", .{@errorName(err)});
            };
        } else {
            self.refreshSnapshot(allocator) catch |err| {
                std.log.warn("workspaces provider query failed: {s}", .{@errorName(err)});
                return;
            };
        }

        self.rotateOwnedStringsForCollect(allocator);

        self.snapshot_mu.lock();
        defer self.snapshot_mu.unlock();
        for (self.snapshot_items) |row| {
            const title = try self.keepString(allocator, row.name);
            const subtitle_tmp = try formatWorkspaceSubtitle(allocator, row);
            defer allocator.free(subtitle_tmp);
            const subtitle = try self.keepString(allocator, subtitle_tmp);
            const action_tmp = try std.fmt.allocPrint(allocator, "{d}", .{row.id});
            defer allocator.free(action_tmp);
            const action = try self.keepString(allocator, action_tmp);
            const icon = try self.keepString(allocator, workspaceIconName(row.window_count));
            try out.append(allocator, search.Candidate.initWithIcon(.workspace, title, subtitle, action, icon));
        }
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *WorkspacesProvider = @ptrCast(@alignCast(context));
        return switch (self.backend().health()) {
            .ready => .ready,
            .degraded => .degraded,
            .unavailable => .unavailable,
        };
    }

    fn keepString(self: *WorkspacesProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *WorkspacesProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(std.ArrayListUnmanaged([]u8), &self.owned_strings_current, &self.owned_strings_previous);
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *WorkspacesProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }

    fn backend(self: *WorkspacesProvider) wm_mod.Backend {
        return self.backend_override orelse self.hyprland_backend.backend();
    }

    pub fn refreshSnapshot(self: *WorkspacesProvider, allocator: std.mem.Allocator) !void {
        var fresh = try self.backend().listWorkspaces(allocator);
        errdefer fresh.deinit(allocator);

        self.snapshot_mu.lock();
        defer self.snapshot_mu.unlock();
        self.clearSnapshotLocked(allocator);
        self.snapshot_items = fresh.items;
        self.snapshot_ready = true;
        fresh.items = &.{};
    }

    fn clearSnapshot(self: *WorkspacesProvider, allocator: std.mem.Allocator) void {
        self.snapshot_mu.lock();
        defer self.snapshot_mu.unlock();
        self.clearSnapshotLocked(allocator);
    }

    fn clearSnapshotLocked(self: *WorkspacesProvider, allocator: std.mem.Allocator) void {
        for (self.snapshot_items) |*row| row.deinit(allocator);
        if (self.snapshot_items.len > 0) allocator.free(self.snapshot_items);
        self.snapshot_items = &.{};
        self.snapshot_ready = false;
    }
};

fn formatWorkspaceSubtitle(allocator: std.mem.Allocator, row: wm_mod.WorkspaceInfo) ![]u8 {
    const count_label = if (row.window_count == 1) "window" else "windows";
    const preview = if (row.window_titles_preview) |s| std.mem.trim(u8, s, " \t\r\n") else "";

    if (row.monitor_name.len == 0) {
        if (preview.len > 0) {
            return std.fmt.allocPrint(allocator, "{d} {s} | {s}", .{ row.window_count, count_label, preview });
        }
        return std.fmt.allocPrint(allocator, "{d} {s}", .{ row.window_count, count_label });
    }
    if (preview.len > 0) {
        return std.fmt.allocPrint(allocator, "{s} | {d} {s} | {s}", .{ row.monitor_name, row.window_count, count_label, preview });
    }
    return std.fmt.allocPrint(allocator, "{s} | {d} {s}", .{ row.monitor_name, row.window_count, count_label });
}

fn workspaceIconName(window_count: u32) []const u8 {
    if (window_count == 0) return "view-grid-symbolic";
    if (window_count == 1) return "window-symbolic";
    return "view-app-grid-symbolic";
}

fn testStubListWindows(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WindowSnapshot {
    _ = allocator;
    return .{ .items = &.{} };
}

test "workspaces provider maps workspace snapshot into candidates" {
    const Fake = struct {
        var health_state: wm_mod.Health = .ready;
        fn listWorkspaces(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WorkspaceSnapshot {
            var items = try allocator.alloc(wm_mod.WorkspaceInfo, 2);
            items[0] = .{
                .id = 1,
                .name = try allocator.dupe(u8, "dev"),
                .monitor_name = try allocator.dupe(u8, "eDP-1"),
                .window_count = 4,
                .window_titles_preview = try allocator.dupe(u8, "Terminal, Editor, Docs (+1)"),
            };
            items[1] = .{
                .id = 2,
                .name = try allocator.dupe(u8, "www"),
                .monitor_name = try allocator.dupe(u8, "HDMI-A-1"),
                .window_count = 1,
                .window_titles_preview = try allocator.dupe(u8, "Browser"),
            };
            return .{ .items = items };
        }
        fn health(_: *anyopaque) wm_mod.Health {
            return health_state;
        }
        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .workspaces = true };
        }
    };
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = testStubListWindows,
            .list_workspaces = Fake.listWorkspaces,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WorkspacesProvider{ .backend_override = fake_backend };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    try provider_impl.provider().collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(search.CandidateKind.workspace, list.items[0].kind);
    try std.testing.expectEqualStrings("dev", list.items[0].title);
    try std.testing.expectEqualStrings("eDP-1 | 4 windows | Terminal, Editor, Docs (+1)", list.items[0].subtitle);
    try std.testing.expectEqualStrings("1", list.items[0].action);
    try std.testing.expectEqualStrings("view-app-grid-symbolic", list.items[0].icon);
    try std.testing.expectEqualStrings("window-symbolic", list.items[1].icon);
    try std.testing.expectEqualStrings("HDMI-A-1 | 1 window | Browser", list.items[1].subtitle);
}

test "workspaces provider reports unavailable when backend tools are unavailable" {
    const Fake = struct {
        fn listWorkspaces(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WorkspaceSnapshot {
            _ = allocator;
            return .{ .items = &.{} };
        }
        fn health(_: *anyopaque) wm_mod.Health {
            return .unavailable;
        }
        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .workspaces = true };
        }
    };
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = testStubListWindows,
            .list_workspaces = Fake.listWorkspaces,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WorkspacesProvider{ .backend_override = fake_backend };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqual(search.ProviderHealth.unavailable, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "workspaces provider maps hyprland backend workspace json" {
    const FakeHypr = struct {
        fn hasTools() bool {
            return true;
        }
        fn listJson(allocator: std.mem.Allocator) ![]u8 {
            return allocator.dupe(u8,
                \\[
                \\ {"id":2,"name":"www","monitor":"HDMI-A-1","windows":1},
                \\ {"id":1,"name":"dev","monitor":"eDP-1","windows":3}
                \\]
            );
        }
    };

    var provider_impl = WorkspacesProvider{
        .hyprland_backend = .{
            .list_workspaces_json_fn = FakeHypr.listJson,
            .has_tools_fn = FakeHypr.hasTools,
        },
    };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    try provider_impl.provider().collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("dev", list.items[0].title);
    try std.testing.expectEqualStrings("1", list.items[0].action);
    try std.testing.expectEqualStrings("www", list.items[1].title);
}

test "workspaces provider refreshes snapshot on subsequent collects" {
    const Fake = struct {
        var mode: u8 = 0;

        fn listWorkspaces(_: *anyopaque, allocator: std.mem.Allocator) !wm_mod.WorkspaceSnapshot {
            var items = try allocator.alloc(wm_mod.WorkspaceInfo, 1);
            if (mode == 0) {
                items[0] = .{
                    .id = 1,
                    .name = try allocator.dupe(u8, "dev"),
                    .monitor_name = try allocator.dupe(u8, "eDP-1"),
                    .window_count = 1,
                    .window_titles_preview = try allocator.dupe(u8, "Terminal"),
                };
            } else {
                items[0] = .{
                    .id = 2,
                    .name = try allocator.dupe(u8, "www"),
                    .monitor_name = try allocator.dupe(u8, "HDMI-A-1"),
                    .window_count = 2,
                    .window_titles_preview = try allocator.dupe(u8, "Browser, Docs"),
                };
            }
            return .{ .items = items };
        }

        fn health(_: *anyopaque) wm_mod.Health {
            return .ready;
        }

        fn capabilities(_: *anyopaque) wm_mod.Capability {
            return .{ .workspaces = true };
        }
    };
    Fake.mode = 0;
    var fake_ctx: u8 = 0;
    const fake_backend = wm_mod.Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = testStubListWindows,
            .list_workspaces = Fake.listWorkspaces,
            .health = Fake.health,
            .capabilities = Fake.capabilities,
        },
    };

    var provider_impl = WorkspacesProvider{ .backend_override = fake_backend };
    defer provider_impl.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = provider_impl.provider();
    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqualStrings("dev", list.items[0].title);

    list.clearRetainingCapacity();
    Fake.mode = 1;
    try provider.collect(std.testing.allocator, &list);
    try std.testing.expectEqualStrings("www", list.items[0].title);
}
