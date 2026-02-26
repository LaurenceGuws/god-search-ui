const std = @import("std");

pub const Capability = struct {
    windows: bool = false,
    workspaces: bool = false,
    focus_window: bool = false,
    switch_workspace: bool = false,
    event_stream: bool = false,
};

pub const Health = enum {
    ready,
    degraded,
    unavailable,
};

pub const WindowInfo = struct {
    title: []u8,
    class_name: []u8,
    id: []u8,

    pub fn deinit(self: *WindowInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.class_name);
        allocator.free(self.id);
        self.* = undefined;
    }
};

pub const WindowSnapshot = struct {
    items: []WindowInfo,

    pub fn deinit(self: *WindowSnapshot, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = .{ .items = &.{} };
    }
};

pub const WorkspaceInfo = struct {
    id: i32,
    name: []u8,
    monitor_name: []u8,
    window_count: u32,
    window_titles_preview: ?[]u8 = null,

    pub fn deinit(self: *WorkspaceInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.monitor_name);
        if (self.window_titles_preview) |preview| allocator.free(preview);
        self.* = undefined;
    }
};

pub const WorkspaceSnapshot = struct {
    items: []WorkspaceInfo,

    pub fn deinit(self: *WorkspaceSnapshot, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = .{ .items = &.{} };
    }
};

pub const EventKind = enum {
    windows_changed,
    workspaces_changed,
    focus_window_changed,
    workspace_switched,
};

pub const Event = struct {
    kind: EventKind,
};

pub const EventHandler = *const fn (context: *anyopaque, event: Event) void;

pub const EventSubscription = struct {
    token: usize = 0,
};

pub const Backend = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        list_windows: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!WindowSnapshot,
        list_workspaces: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!WorkspaceSnapshot,
        health: *const fn (context: *anyopaque) Health,
        capabilities: *const fn (context: *anyopaque) Capability,
        subscribe_events: *const fn (
            context: *anyopaque,
            allocator: std.mem.Allocator,
            handler_context: *anyopaque,
            handler: EventHandler,
        ) anyerror!?EventSubscription = defaultSubscribeEvents,
        unsubscribe_events: *const fn (
            context: *anyopaque,
            allocator: std.mem.Allocator,
            subscription: EventSubscription,
        ) void = defaultUnsubscribeEvents,
    };

    pub fn listWindows(self: Backend, allocator: std.mem.Allocator) !WindowSnapshot {
        return self.vtable.list_windows(self.context, allocator);
    }

    pub fn health(self: Backend) Health {
        return self.vtable.health(self.context);
    }

    pub fn listWorkspaces(self: Backend, allocator: std.mem.Allocator) !WorkspaceSnapshot {
        return self.vtable.list_workspaces(self.context, allocator);
    }

    pub fn capabilities(self: Backend) Capability {
        return self.vtable.capabilities(self.context);
    }

    pub fn supportsEventStream(self: Backend) bool {
        return self.capabilities().event_stream;
    }

    pub fn subscribeEvents(
        self: Backend,
        allocator: std.mem.Allocator,
        handler_context: *anyopaque,
        handler: EventHandler,
    ) !?EventSubscription {
        return self.vtable.subscribe_events(self.context, allocator, handler_context, handler);
    }

    pub fn unsubscribeEvents(self: Backend, allocator: std.mem.Allocator, subscription: EventSubscription) void {
        self.vtable.unsubscribe_events(self.context, allocator, subscription);
    }
};

fn defaultSubscribeEvents(
    _: *anyopaque,
    _: std.mem.Allocator,
    _: *anyopaque,
    _: EventHandler,
) anyerror!?EventSubscription {
    return null;
}

fn defaultUnsubscribeEvents(_: *anyopaque, _: std.mem.Allocator, _: EventSubscription) void {}

fn testStubListWindows(_: *anyopaque, allocator: std.mem.Allocator) !WindowSnapshot {
    _ = allocator;
    return .{ .items = &.{} };
}

fn testStubListWorkspaces(_: *anyopaque, allocator: std.mem.Allocator) !WorkspaceSnapshot {
    _ = allocator;
    return .{ .items = &.{} };
}

fn testStubHealth(_: *anyopaque) Health {
    return .ready;
}

fn testStubCapabilities(_: *anyopaque) Capability {
    return .{ .windows = true, .workspaces = true };
}

fn testEventHandler(_: *anyopaque, _: Event) void {}

test "backend event subscription defaults to unsupported/null" {
    var fake_ctx: u8 = 0;
    const backend = Backend{
        .name = "fake",
        .context = &fake_ctx,
        .vtable = &.{
            .list_windows = testStubListWindows,
            .list_workspaces = testStubListWorkspaces,
            .health = testStubHealth,
            .capabilities = testStubCapabilities,
        },
    };

    try std.testing.expect(!backend.supportsEventStream());
    const sub = try backend.subscribeEvents(std.testing.allocator, &fake_ctx, testEventHandler);
    try std.testing.expect(sub == null);
}
