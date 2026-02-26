const std = @import("std");
const gtk_types = @import("types.zig");
const ipc_control = @import("../../ipc/control.zig");
const shell_mod = @import("../../shell/mod.zig");
const wm_mod = @import("../../wm/mod.zig");

const c = gtk_types.c;
const GFALSE = gtk_types.GFALSE;

pub const ControlContext = struct {
    event_bus: *shell_mod.EventBus,
    health_store: *HealthStore,
};

pub const HealthStore = struct {
    lock: std.Thread.Mutex = .{},
    launcher: shell_mod.module.ModuleHealth = .{ .status = .unknown, .detail = "not started" },
    notifications: shell_mod.module.ModuleHealth = .{ .status = .unknown, .detail = "not started" },

    pub fn setLauncher(self: *HealthStore, health: shell_mod.module.ModuleHealth) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.launcher = health;
    }

    pub fn setNotifications(self: *HealthStore, health: shell_mod.module.ModuleHealth) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.notifications = health;
    }

    pub fn snapshotAlloc(self: *HealthStore, allocator: std.mem.Allocator) ![]u8 {
        self.lock.lock();
        const launcher = self.launcher;
        const notifications = self.notifications;
        self.lock.unlock();

        const l = shell_mod.module.ModuleHealthEntry{ .name = "launcher", .health = launcher };
        const n = shell_mod.module.ModuleHealthEntry{ .name = "notifications", .health = notifications };
        const l_line = try shell_mod.health.formatEntry(allocator, l);
        defer allocator.free(l_line);
        const n_line = try shell_mod.health.formatEntry(allocator, n);
        defer allocator.free(n_line);

        return std.fmt.allocPrint(allocator, "{s};{s}", .{ l_line, n_line });
    }
};

pub fn maybeStart(
    allocator: std.mem.Allocator,
    resident_mode: bool,
    control_ctx: *ControlContext,
) !?ipc_control.Server {
    if (!resident_mode) return null;
    var server = try ipc_control.Server.init(allocator, onControlCommand, onControlQuery, control_ctx);
    try server.start();
    return server;
}

const ControlInvokePayload = struct {
    event_bus: *shell_mod.EventBus,
    command: ipc_control.Command,
};

fn onControlCommand(command: ipc_control.Command, user_data: *anyopaque) ipc_control.HandlerResult {
    const control_ctx: *ControlContext = @ptrCast(@alignCast(user_data));
    const payload: *ControlInvokePayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(ControlInvokePayload))));
    payload.* = .{ .event_bus = control_ctx.event_bus, .command = command };
    if (c.g_idle_add(onControlInvokeIdle, payload) == 0) {
        c.g_free(payload);
        return .{ .ok = false, .code = "rejected", .message = "Failed to queue command" };
    }
    return .{ .ok = true, .code = "ok", .message = "accepted" };
}

fn onControlQuery(allocator: std.mem.Allocator, command: ipc_control.Command, user_data: *anyopaque) !?[]u8 {
    const control_ctx: *ControlContext = @ptrCast(@alignCast(user_data));
    return switch (command) {
        .shell_health => try control_ctx.health_store.snapshotAlloc(allocator),
        .wm_event_stats => try wm_mod.event_stats.snapshotAlloc(allocator),
        else => null,
    };
}

fn onControlInvokeIdle(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const payload: *ControlInvokePayload = @ptrCast(@alignCast(user_data.?));
    defer c.g_free(payload);

    switch (payload.command) {
        .summon => payload.event_bus.emit(.summon),
        .hide => payload.event_bus.emit(.hide),
        .toggle => payload.event_bus.emit(.toggle),
        else => {},
    }
    return GFALSE;
}
