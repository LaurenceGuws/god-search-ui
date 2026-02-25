const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_bootstrap = @import("bootstrap.zig");
const ipc_control = @import("../../ipc/control.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const LaunchContext = gtk_bootstrap.LaunchContext;

pub fn maybeStart(
    allocator: std.mem.Allocator,
    resident_mode: bool,
    launch: *LaunchContext,
) !?ipc_control.Server {
    if (!resident_mode) return null;
    var server = try ipc_control.Server.init(allocator, onControlCommand, launch);
    try server.start();
    return server;
}

const ControlInvokePayload = struct {
    launch: *LaunchContext,
    command: ipc_control.Command,
};

fn onControlCommand(command: ipc_control.Command, user_data: *anyopaque) ipc_control.HandlerResult {
    const launch: *LaunchContext = @ptrCast(@alignCast(user_data));
    const payload: *ControlInvokePayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(ControlInvokePayload))));
    payload.* = .{ .launch = launch, .command = command };
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
        .summon => c.g_application_activate(@ptrCast(payload.launch.gtk_app)),
        .hide => if (payload.launch.ctx) |ctx| c.gtk_widget_set_visible(ctx.window, GFALSE),
        .toggle => if (payload.launch.ctx) |ctx| {
            if (c.gtk_widget_get_visible(ctx.window) == GTRUE) {
                c.gtk_widget_set_visible(ctx.window, GFALSE);
            } else {
                c.g_application_activate(@ptrCast(payload.launch.gtk_app));
            }
        } else c.g_application_activate(@ptrCast(payload.launch.gtk_app)),
        else => {},
    }
    return GFALSE;
}
