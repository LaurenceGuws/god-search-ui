const std = @import("std");

pub const Capability = struct {
    windows: bool = false,
    workspaces: bool = false,
    focus_window: bool = false,
    switch_workspace: bool = false,
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

    pub fn deinit(self: *WorkspaceInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.monitor_name);
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

pub const Backend = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        list_windows: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!WindowSnapshot,
        list_workspaces: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!WorkspaceSnapshot,
        health: *const fn (context: *anyopaque) Health,
        capabilities: *const fn (context: *anyopaque) Capability,
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
};
