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

pub const Backend = struct {
    name: []const u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        list_windows: *const fn (context: *anyopaque, allocator: std.mem.Allocator) anyerror!WindowSnapshot,
        health: *const fn (context: *anyopaque) Health,
        capabilities: *const fn (context: *anyopaque) Capability,
    };

    pub fn listWindows(self: Backend, allocator: std.mem.Allocator) !WindowSnapshot {
        return self.vtable.list_windows(self.context, allocator);
    }

    pub fn health(self: Backend) Health {
        return self.vtable.health(self.context);
    }

    pub fn capabilities(self: Backend) Capability {
        return self.vtable.capabilities(self.context);
    }
};
