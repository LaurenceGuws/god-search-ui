const std = @import("std");
const notifications_state = @import("state.zig");

const log = std.log.scoped(.notifications);

const c = @cImport({
    @cInclude("gio/gio.h");
});

const service_name: [*:0]const u8 = "org.freedesktop.Notifications";
const interface_name: [*:0]const u8 = "org.freedesktop.Notifications";
const object_path: [*:0]const u8 = "/org/freedesktop/Notifications";

const server_name: [*:0]const u8 = "god-search-ui";
const server_vendor: [*:0]const u8 = "god-search-ui";
const server_version: [*:0]const u8 = "0.1.3-dev";
const server_spec_version: [*:0]const u8 = "1.3";

const introspection_xml: [*:0]const u8 =
    \\<node>
    \\<interface name='org.freedesktop.Notifications'>
    \\<method name='GetCapabilities'>
    \\<arg type='as' name='caps' direction='out'/>
    \\</method>
    \\<method name='Notify'>
    \\<arg type='s' name='app_name' direction='in'/>
    \\<arg type='u' name='replaces_id' direction='in'/>
    \\<arg type='s' name='app_icon' direction='in'/>
    \\<arg type='s' name='summary' direction='in'/>
    \\<arg type='s' name='body' direction='in'/>
    \\<arg type='as' name='actions' direction='in'/>
    \\<arg type='a{sv}' name='hints' direction='in'/>
    \\<arg type='i' name='expire_timeout' direction='in'/>
    \\<arg type='u' name='id' direction='out'/>
    \\</method>
    \\<method name='CloseNotification'>
    \\<arg type='u' name='id' direction='in'/>
    \\</method>
    \\<method name='GetServerInformation'>
    \\<arg type='s' name='name' direction='out'/>
    \\<arg type='s' name='vendor' direction='out'/>
    \\<arg type='s' name='version' direction='out'/>
    \\<arg type='s' name='spec_version' direction='out'/>
    \\</method>
    \\<signal name='NotificationClosed'>
    \\<arg type='u' name='id'/>
    \\<arg type='u' name='reason'/>
    \\</signal>
    \\<signal name='ActionInvoked'>
    \\<arg type='u' name='id'/>
    \\<arg type='s' name='action_key'/>
    \\</signal>
    \\<signal name='ActivationToken'>
    \\<arg type='u' name='id'/>
    \\<arg type='s' name='activation_token'/>
    \\</signal>
    \\</interface>
    \\</node>
;

const vtable = c.GDBusInterfaceVTable{
    .method_call = onMethodCall,
    .get_property = null,
    .set_property = null,
};

pub const Daemon = struct {
    allocator: std.mem.Allocator,
    state: notifications_state.Store,
    owner_id: c.guint = 0,
    registration_id: c.guint = 0,
    node_info: ?*c.GDBusNodeInfo = null,
    connection: ?*c.GDBusConnection = null,

    pub fn init(allocator: std.mem.Allocator) !Daemon {
        var gerr: ?*c.GError = null;
        const node = c.g_dbus_node_info_new_for_xml(introspection_xml, &gerr);
        if (node == null) {
            logGError("failed to parse notifications introspection XML", gerr);
            return error.NotificationsIntrospectionFailed;
        }
        return .{
            .allocator = allocator,
            .state = notifications_state.Store.init(allocator),
            .node_info = node,
        };
    }

    pub fn start(self: *Daemon) !void {
        if (self.owner_id != 0) return;
        self.owner_id = c.g_bus_own_name(
            c.G_BUS_TYPE_SESSION,
            service_name,
            c.G_BUS_NAME_OWNER_FLAGS_NONE,
            onBusAcquired,
            onNameAcquired,
            onNameLost,
            self,
            null,
        );
        if (self.owner_id == 0) return error.NotificationsBusOwnFailed;
    }

    pub fn deinit(self: *Daemon) void {
        if (self.registration_id != 0 and self.connection != null) {
            _ = c.g_dbus_connection_unregister_object(self.connection.?, self.registration_id);
            self.registration_id = 0;
        }
        if (self.owner_id != 0) {
            c.g_bus_unown_name(self.owner_id);
            self.owner_id = 0;
        }
        if (self.connection) |conn| {
            c.g_object_unref(conn);
            self.connection = null;
        }
        if (self.node_info) |node| {
            c.g_dbus_node_info_unref(node);
            self.node_info = null;
        }
        self.state.deinit();
    }
};

fn onBusAcquired(connection: ?*c.GDBusConnection, _: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    if (connection == null or user_data == null) return;
    const self: *Daemon = @ptrCast(@alignCast(user_data.?));

    if (self.connection) |existing| {
        c.g_object_unref(existing);
    }
    self.connection = @ptrCast(c.g_object_ref(connection));

    const node_info = self.node_info orelse return;
    const iface = c.g_dbus_node_info_lookup_interface(node_info, interface_name);
    if (iface == null) return;

    var gerr: ?*c.GError = null;
    self.registration_id = c.g_dbus_connection_register_object(
        connection,
        object_path,
        iface,
        &vtable,
        self,
        null,
        &gerr,
    );
    if (self.registration_id == 0) {
        logGError("failed to register notifications object", gerr);
    }
}

fn onNameAcquired(_: ?*c.GDBusConnection, name: [*c]const u8, _: ?*anyopaque) callconv(.c) void {
    if (name != null) {
        log.info("owned dbus name: {s}", .{std.mem.span(name)});
    }
}

fn onNameLost(_: ?*c.GDBusConnection, name: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    if (name != null) {
        log.warn("lost dbus name: {s}", .{std.mem.span(name)});
    }
    if (user_data == null) return;
    const self: *Daemon = @ptrCast(@alignCast(user_data.?));
    self.registration_id = 0;
}

fn onMethodCall(
    _: ?*c.GDBusConnection,
    _: [*c]const u8,
    _: [*c]const u8,
    _: [*c]const u8,
    method_name: [*c]const u8,
    parameters: ?*c.GVariant,
    invocation: ?*c.GDBusMethodInvocation,
    user_data: ?*anyopaque,
) callconv(.c) void {
    if (invocation == null or user_data == null) return;
    const self: *Daemon = @ptrCast(@alignCast(user_data.?));
    const method = std.mem.span(method_name);

    if (std.mem.eql(u8, method, "GetCapabilities")) {
        handleGetCapabilities(invocation.?);
        return;
    }
    if (std.mem.eql(u8, method, "GetServerInformation")) {
        handleGetServerInformation(invocation.?);
        return;
    }
    if (std.mem.eql(u8, method, "Notify")) {
        handleNotify(self, parameters, invocation.?);
        return;
    }
    if (std.mem.eql(u8, method, "CloseNotification")) {
        handleCloseNotification(self, parameters, invocation.?);
        return;
    }

    c.g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.DBus.Error.UnknownMethod",
        "Unknown method",
    );
}

fn handleGetCapabilities(invocation: *c.GDBusMethodInvocation) void {
    var capabilities = [_]?[*:0]const u8{
        "body",
        "body-markup",
        null,
    };
    const caps = c.g_variant_new_strv(@ptrCast(&capabilities[0]), 2);
    var tuple_items = [_]?*c.GVariant{caps};
    c.g_dbus_method_invocation_return_value(invocation, c.g_variant_new_tuple(@ptrCast(&tuple_items[0]), 1));
}

fn handleGetServerInformation(invocation: *c.GDBusMethodInvocation) void {
    c.g_dbus_method_invocation_return_value(
        invocation,
        c.g_variant_new("(ssss)", server_name, server_vendor, server_version, server_spec_version),
    );
}

fn handleNotify(self: *Daemon, parameters: ?*c.GVariant, invocation: *c.GDBusMethodInvocation) void {
    const payload = parameters orelse {
        returnInvalidArgs(invocation, "Notify expects parameters");
        return;
    };

    if (c.g_variant_n_children(payload) != 8) {
        returnInvalidArgs(invocation, "Notify expects 8 arguments");
        return;
    }

    const app_name_variant = c.g_variant_get_child_value(payload, 0);
    defer c.g_variant_unref(app_name_variant);
    const replaces_id_variant = c.g_variant_get_child_value(payload, 1);
    defer c.g_variant_unref(replaces_id_variant);
    const _app_icon_variant = c.g_variant_get_child_value(payload, 2);
    defer c.g_variant_unref(_app_icon_variant);
    const summary_variant = c.g_variant_get_child_value(payload, 3);
    defer c.g_variant_unref(summary_variant);
    const body_variant = c.g_variant_get_child_value(payload, 4);
    defer c.g_variant_unref(body_variant);
    const actions_variant = c.g_variant_get_child_value(payload, 5);
    defer c.g_variant_unref(actions_variant);
    const hints_variant = c.g_variant_get_child_value(payload, 6);
    defer c.g_variant_unref(hints_variant);
    const expire_timeout_variant = c.g_variant_get_child_value(payload, 7);
    defer c.g_variant_unref(expire_timeout_variant);

    if (c.g_variant_is_of_type(hints_variant, c.G_VARIANT_TYPE("a{sv}")) == 0) {
        returnInvalidArgs(invocation, "Notify hints must be a{sv}");
        return;
    }

    const app_name = c.g_variant_get_string(app_name_variant, null);
    const summary = c.g_variant_get_string(summary_variant, null);
    const body = c.g_variant_get_string(body_variant, null);
    const replaces_id = c.g_variant_get_uint32(replaces_id_variant);
    const expire_timeout = c.g_variant_get_int32(expire_timeout_variant);
    const has_actions = c.g_variant_n_children(actions_variant) > 0;

    const id = self.state.notify(.{
        .app_name = std.mem.span(app_name),
        .summary = std.mem.span(summary),
        .body = std.mem.span(body),
        .replaces_id = replaces_id,
        .expire_timeout = expire_timeout,
        .has_actions = has_actions,
    }) catch {
        c.g_dbus_method_invocation_return_dbus_error(
            invocation,
            "org.freedesktop.DBus.Error.NoMemory",
            "Unable to persist notification",
        );
        return;
    };

    c.g_dbus_method_invocation_return_value(invocation, c.g_variant_new("(u)", id));
}

fn handleCloseNotification(self: *Daemon, parameters: ?*c.GVariant, invocation: *c.GDBusMethodInvocation) void {
    const payload = parameters orelse {
        returnInvalidArgs(invocation, "CloseNotification expects parameters");
        return;
    };

    if (c.g_variant_n_children(payload) != 1) {
        returnInvalidArgs(invocation, "CloseNotification expects one argument");
        return;
    }

    const id_variant = c.g_variant_get_child_value(payload, 0);
    defer c.g_variant_unref(id_variant);
    const notification_id = c.g_variant_get_uint32(id_variant);

    if (self.state.close(notification_id)) {
        emitNotificationClosed(self, notification_id, 3);
    }

    c.g_dbus_method_invocation_return_value(invocation, c.g_variant_new("()"));
}

fn emitNotificationClosed(self: *Daemon, id: u32, reason: u32) void {
    const conn = self.connection orelse return;
    _ = c.g_dbus_connection_emit_signal(
        conn,
        null,
        object_path,
        interface_name,
        "NotificationClosed",
        c.g_variant_new("(uu)", id, reason),
        null,
    );
}

fn returnInvalidArgs(invocation: *c.GDBusMethodInvocation, message: [*:0]const u8) void {
    c.g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.DBus.Error.InvalidArgs",
        message,
    );
}

fn logGError(context: []const u8, gerr: ?*c.GError) void {
    if (gerr) |err| {
        defer c.g_error_free(err);
        if (err.message != null) {
            log.err("{s}: {s}", .{ context, std.mem.span(err.message) });
            return;
        }
    }
    log.err("{s}", .{context});
}
