const std = @import("std");

pub const Event = union(enum) {
    summon,
    hide,
    refresh,
    custom: []const u8,
};

pub const HealthStatus = enum {
    unknown,
    ready,
    degraded,
    failed,
};

pub const ModuleHealth = struct {
    status: HealthStatus = .unknown,
    detail: []const u8 = "",
};

pub const ModuleHealthEntry = struct {
    name: []const u8,
    health: ModuleHealth,
};

pub const ModuleInstance = struct {
    name: []const u8,
    state: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        start: *const fn (state: *anyopaque) anyerror!void,
        stop: *const fn (state: *anyopaque) void,
        handle_event: *const fn (state: *anyopaque, event: Event) void,
        health: *const fn (state: *anyopaque) ModuleHealth,
        deinit: *const fn (allocator: std.mem.Allocator, state: *anyopaque) void,
    };

    pub fn start(self: *ModuleInstance) !void {
        try self.vtable.start(self.state);
    }

    pub fn stop(self: *ModuleInstance) void {
        self.vtable.stop(self.state);
    }

    pub fn handleEvent(self: *ModuleInstance, event: Event) void {
        self.vtable.handle_event(self.state, event);
    }

    pub fn health(self: *const ModuleInstance) ModuleHealth {
        return self.vtable.health(self.state);
    }

    pub fn deinit(self: *ModuleInstance, allocator: std.mem.Allocator) void {
        self.vtable.deinit(allocator, self.state);
    }
};

pub const ModuleFactory = struct {
    name: []const u8,
    context: *anyopaque,
    init: *const fn (allocator: std.mem.Allocator, context: *anyopaque) anyerror!ModuleInstance,
};
