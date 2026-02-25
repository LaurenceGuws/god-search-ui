const std = @import("std");
const gtk_types = @import("types.zig");
const ipc_control = @import("../../ipc/control.zig");
const shell_mod = @import("../../shell/mod.zig");

const c = gtk_types.c;
const GFALSE = gtk_types.GFALSE;

pub fn maybeStart(
    allocator: std.mem.Allocator,
    resident_mode: bool,
    event_bus: *shell_mod.EventBus,
) !?ipc_control.Server {
    if (!resident_mode) return null;
    var server = try ipc_control.Server.init(allocator, onControlCommand, event_bus);
    try server.start();
    return server;
}

const ControlInvokePayload = struct {
    event_bus: *shell_mod.EventBus,
    command: ipc_control.Command,
};

fn onControlCommand(command: ipc_control.Command, user_data: *anyopaque) ipc_control.HandlerResult {
    const event_bus: *shell_mod.EventBus = @ptrCast(@alignCast(user_data));
    const payload: *ControlInvokePayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(ControlInvokePayload))));
    payload.* = .{ .event_bus = event_bus, .command = command };
    if (c.g_idle_add(onControlInvokeIdle, payload) == 0) {
        c.g_free(payload);
        return .rejected;
    }
    return .ok;
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
