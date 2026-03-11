const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_icons = @import("icons.zig");
const notifications = @import("../../notifications/mod.zig");
const placement_bridge = @import("placement_bridge.zig");
const layer_shell = @import("layer_shell.zig");
const SurfaceMode = @import("../surfaces/mod.zig").SurfaceMode;
const NotificationPolicy = @import("../placement/mod.zig").NotificationPolicy;

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const default_expire_ms: i32 = 5000;

const PopupEntry = struct {
    id: u32,
    row: *c.GtkWidget,
    summary_label: *c.GtkLabel,
    body_label: *c.GtkLabel,
    actions_box: *c.GtkWidget,
    timeout_id: c.guint,
};

const DismissPayload = struct {
    manager: *PopupManager,
    id: u32,
};

const ActionPayload = struct {
    manager: *PopupManager,
    id: u32,
    action_key: ?[*:0]u8,
};

const TimeoutPayload = struct {
    manager: *PopupManager,
    id: u32,
};

pub const PopupManager = struct {
    allocator: std.mem.Allocator,
    daemon: *notifications.Daemon,
    gtk_app: *c.GtkApplication,
    surface_mode: SurfaceMode,
    placement_policy: NotificationPolicy,
    show_close_button: bool,
    show_dbus_actions: bool,
    window: ?*c.GtkWidget,
    list: ?*c.GtkWidget,
    entries: std.ArrayList(PopupEntry),

    pub fn init(
        allocator: std.mem.Allocator,
        gtk_app: *c.GtkApplication,
        daemon: *notifications.Daemon,
        surface_mode: SurfaceMode,
        placement_policy: NotificationPolicy,
        show_close_button: bool,
        show_dbus_actions: bool,
    ) !PopupManager {
        const manager = PopupManager{
            .allocator = allocator,
            .daemon = daemon,
            .gtk_app = gtk_app,
            .surface_mode = surface_mode,
            .placement_policy = placement_policy,
            .show_close_button = show_close_button,
            .show_dbus_actions = show_dbus_actions,
            .window = null,
            .list = null,
            .entries = .empty,
        };

        return manager;
    }

    pub fn attach(self: *PopupManager) void {
        self.daemon.setHooks(.{
            .user_data = self,
            .on_notify = onNotify,
            .on_closed = onClosed,
        });
    }

    pub fn deinit(self: *PopupManager) void {
        self.daemon.clearHooks();
        for (self.entries.items) |*entry| {
            cancelTimeout(&entry.timeout_id);
        }
        self.entries.deinit(self.allocator);
        if (self.window) |window| {
            c.gtk_window_destroy(@ptrCast(window));
            self.window = null;
            self.list = null;
        }
    }

    fn onNotify(user_data: *anyopaque, event: notifications.Daemon.NotifyEvent) void {
        const self: *PopupManager = @ptrCast(@alignCast(user_data));
        self.upsert(event);
    }

    fn onClosed(user_data: *anyopaque, event: notifications.Daemon.ClosedEvent) void {
        const self: *PopupManager = @ptrCast(@alignCast(user_data));
        _ = event.reason;
        self.remove(event.id);
    }

    fn upsert(self: *PopupManager, event: notifications.Daemon.NotifyEvent) void {
        if (!self.ensureWindow()) return;
        const idx = self.findIndex(event.id);
        if (idx) |existing_idx| {
            const entry = &self.entries.items[existing_idx];
            setLabelText(entry.summary_label, displaySummary(event.summary, event.app_name));
            setBodyLabel(entry.body_label, event.body);
            updateActions(self, entry.actions_box, event.id, event.actions);
            rescheduleTimeout(self, entry, event.expire_timeout);
        } else {
            const row = createRow(self, event.id, event.app_name, event.app_icon, event.summary, event.body) catch return;
            updateActions(self, row.actions_box, event.id, event.actions);
            self.entries.append(self.allocator, .{
                .id = event.id,
                .row = row.row,
                .summary_label = row.summary_label,
                .body_label = row.body_label,
                .actions_box = row.actions_box,
                .timeout_id = 0,
            }) catch {
                c.gtk_box_remove(@ptrCast(self.list.?), row.row);
                return;
            };
            rescheduleTimeout(self, &self.entries.items[self.entries.items.len - 1], event.expire_timeout);
        }

        c.gtk_widget_set_visible(self.window.?, GTRUE);
        c.gtk_window_present(@ptrCast(self.window.?));
    }

    fn remove(self: *PopupManager, id: u32) void {
        const idx = self.findIndex(id) orelse return;
        const entry = self.entries.items[idx];
        var timeout_id = entry.timeout_id;
        cancelTimeout(&timeout_id);
        c.gtk_box_remove(@ptrCast(self.list.?), entry.row);
        _ = self.entries.swapRemove(idx);
        if (self.entries.items.len == 0) {
            if (self.window) |window| c.gtk_widget_set_visible(window, GFALSE);
        }
    }

    fn findIndex(self: *PopupManager, id: u32) ?usize {
        for (self.entries.items, 0..) |entry, idx| {
            if (entry.id == id) return idx;
        }
        return null;
    }

    fn rescheduleTimeout(self: *PopupManager, entry: *PopupEntry, expire_timeout: i32) void {
        cancelTimeout(&entry.timeout_id);

        const delay_ms = normalizeExpireTimeout(expire_timeout);
        if (delay_ms <= 0) return;

        const payload: *TimeoutPayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(TimeoutPayload))));
        payload.* = .{ .manager = self, .id = entry.id };
        entry.timeout_id = c.g_timeout_add(@intCast(delay_ms), onTimeout, payload);
    }

    fn normalizeExpireTimeout(expire_timeout: i32) i32 {
        if (expire_timeout == 0) return 0;
        if (expire_timeout < 0) return default_expire_ms;
        return expire_timeout;
    }

    fn onTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
        if (user_data == null) return GFALSE;
        const payload: *TimeoutPayload = @ptrCast(@alignCast(user_data.?));
        defer c.g_free(payload);

        _ = payload.manager.daemon.closeWithReason(payload.id, 1);
        return GFALSE;
    }

    fn createRow(self: *PopupManager, id: u32, app_name: []const u8, app_icon: []const u8, summary: []const u8, body: []const u8) !struct {
        row: *c.GtkWidget,
        summary_label: *c.GtkLabel,
        body_label: *c.GtkLabel,
        actions_box: *c.GtkWidget,
    } {
        const row = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 6);
        c.gtk_widget_add_css_class(row, "gs-notify-row");

        const top = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
        c.gtk_widget_add_css_class(top, "gs-notify-top");

        const icon_widget = gtk_icons.notificationIconWidget(self.allocator, app_icon, app_name);
        c.gtk_widget_set_valign(icon_widget, c.GTK_ALIGN_START);

        const content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 3);
        c.gtk_widget_set_hexpand(content, GTRUE);
        c.gtk_widget_add_css_class(content, "gs-notify-content");

        const header = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_add_css_class(header, "gs-notify-header");

        const summary_label = c.gtk_label_new("");
        setLabelText(@ptrCast(summary_label), displaySummary(summary, app_name));
        c.gtk_label_set_xalign(@ptrCast(summary_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(summary_label), GTRUE);
        c.gtk_label_set_wrap_mode(@ptrCast(summary_label), c.PANGO_WRAP_WORD_CHAR);
        c.gtk_widget_add_css_class(summary_label, "gs-notify-summary");
        c.gtk_widget_set_hexpand(summary_label, GTRUE);

        c.gtk_box_append(@ptrCast(header), summary_label);
        if (self.show_close_button) {
            const close_btn = c.gtk_button_new();
            c.gtk_widget_add_css_class(close_btn, "gs-notify-close");
            c.gtk_widget_set_tooltip_text(close_btn, "Dismiss notification");
            const close_icon = c.gtk_image_new_from_icon_name("window-close-symbolic");
            c.gtk_image_set_pixel_size(@ptrCast(close_icon), 16);
            c.gtk_button_set_child(@ptrCast(close_btn), close_icon);
            const payload: *DismissPayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(DismissPayload))));
            payload.* = .{ .manager = self, .id = id };
            _ = c.g_signal_connect_data(close_btn, "clicked", c.G_CALLBACK(onDismissClicked), payload, onDismissPayloadDestroyed, 0);
            c.gtk_box_append(@ptrCast(header), close_btn);
        }

        const body_label = c.gtk_label_new("");
        c.gtk_label_set_xalign(@ptrCast(body_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(body_label), GTRUE);
        c.gtk_label_set_wrap_mode(@ptrCast(body_label), c.PANGO_WRAP_WORD_CHAR);
        c.gtk_label_set_use_markup(@ptrCast(body_label), GTRUE);
        setBodyLabel(@ptrCast(body_label), body);
        c.gtk_widget_add_css_class(body_label, "gs-notify-body");

        const actions_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
        c.gtk_widget_add_css_class(actions_box, "gs-notify-actions");
        c.gtk_widget_set_visible(actions_box, GFALSE);

        c.gtk_box_append(@ptrCast(content), header);
        c.gtk_box_append(@ptrCast(content), body_label);

        c.gtk_box_append(@ptrCast(top), icon_widget);
        c.gtk_box_append(@ptrCast(top), content);

        c.gtk_box_append(@ptrCast(row), top);
        c.gtk_box_append(@ptrCast(row), actions_box);
        c.gtk_box_append(@ptrCast(self.list.?), row);

        return .{
            .row = @ptrCast(row),
            .summary_label = @ptrCast(summary_label),
            .body_label = @ptrCast(body_label),
            .actions_box = @ptrCast(actions_box),
        };
    }

    fn onDismissClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const payload: *DismissPayload = @ptrCast(@alignCast(user_data.?));
        _ = payload.manager.daemon.closeWithReason(payload.id, 2);
    }

    fn onActionClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const payload: *ActionPayload = @ptrCast(@alignCast(user_data.?));
        const action_key = payload.action_key orelse return;
        payload.manager.daemon.emitActionInvoked(payload.id, std.mem.span(action_key));
        _ = payload.manager.daemon.closeWithReason(payload.id, 2);
    }

    fn onPayloadDestroyed(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
        if (data) |payload| {
            const action_payload: *ActionPayload = @ptrCast(@alignCast(payload));
            if (action_payload.action_key) |ptr| c.g_free(ptr);
            c.g_free(payload);
        }
    }

    fn onDismissPayloadDestroyed(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
        if (data) |payload| c.g_free(payload);
    }

    fn ensureWindow(self: *PopupManager) bool {
        if (self.window != null and self.list != null) return true;

        const window = c.gtk_application_window_new(self.gtk_app);
        c.gtk_window_set_title(@ptrCast(window), "God Search Notifications");
        c.gtk_widget_add_css_class(window, "gs-notify-window");
        const use_layer_notifications = layer_shell.shouldUseLayerShell(self.surface_mode);
        if (use_layer_notifications and !layer_shell.applyNotifications(window, self.placement_policy)) {
            std.log.err("notifications: layer-shell requested but unavailable", .{});
            c.gtk_window_destroy(@ptrCast(window));
            return false;
        }
        placement_bridge.configureNotificationPopupWindow(window, self.placement_policy);
        c.gtk_window_set_resizable(@ptrCast(window), GFALSE);
        c.gtk_window_set_decorated(@ptrCast(window), GFALSE);

        const scroller = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
        c.gtk_widget_set_vexpand(scroller, GFALSE);
        c.gtk_scrolled_window_set_propagate_natural_height(@ptrCast(scroller), GTRUE);
        c.gtk_scrolled_window_set_min_content_height(@ptrCast(scroller), 1);
        c.gtk_scrolled_window_set_max_content_height(@ptrCast(scroller), self.placement_policy.max_height_px);

        const list = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
        c.gtk_widget_set_margin_top(list, 10);
        c.gtk_widget_set_margin_bottom(list, 10);
        c.gtk_widget_set_margin_start(list, 10);
        c.gtk_widget_set_margin_end(list, 10);
        c.gtk_widget_add_css_class(list, "gs-notify-list");

        c.gtk_scrolled_window_set_child(@ptrCast(scroller), list);
        c.gtk_window_set_child(@ptrCast(window), scroller);
        c.gtk_widget_set_visible(window, GFALSE);

        self.window = @ptrCast(window);
        self.list = @ptrCast(list);
        return true;
    }

    fn updateActions(self: *PopupManager, actions_box: *c.GtkWidget, id: u32, actions: []const notifications.Daemon.Action) void {
        clearChildren(actions_box);
        if (!self.show_dbus_actions or actions.len == 0) {
            c.gtk_widget_set_visible(actions_box, GFALSE);
            return;
        }
        const vertical_stack = shouldStackActions(actions);
        c.gtk_orientable_set_orientation(
            @ptrCast(actions_box),
            if (vertical_stack) c.GTK_ORIENTATION_VERTICAL else c.GTK_ORIENTATION_HORIZONTAL,
        );
        for (actions) |action| {
            const button = c.gtk_button_new();
            configureActionButton(button, action);
            c.gtk_widget_add_css_class(button, "gs-notify-action-btn");
            if (vertical_stack) c.gtk_widget_set_hexpand(button, GTRUE);
            const payload: *ActionPayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(ActionPayload))));
            payload.* = .{
                .manager = self,
                .id = id,
                .action_key = c.g_strndup(action.key.ptr, @intCast(action.key.len)),
            };
            _ = c.g_signal_connect_data(button, "clicked", c.G_CALLBACK(onActionClicked), payload, onPayloadDestroyed, 0);
            c.gtk_box_append(@ptrCast(actions_box), button);
        }
        c.gtk_widget_set_visible(actions_box, GTRUE);
    }
};

fn cancelTimeout(timeout_id: *c.guint) void {
    if (timeout_id.* == 0) return;
    _ = c.g_source_remove(timeout_id.*);
    timeout_id.* = 0;
}

fn clearChildren(box: *c.GtkWidget) void {
    var child = c.gtk_widget_get_first_child(box);
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child);
        c.gtk_box_remove(@ptrCast(box), child);
        child = next;
    }
}

fn setBodyLabel(label: *c.GtkLabel, body: []const u8) void {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    c.gtk_widget_set_visible(@ptrCast(@alignCast(label)), if (trimmed.len == 0) GFALSE else GTRUE);
    if (trimmed.len == 0) {
        c.gtk_label_set_text(label, "");
        return;
    }
    // Basic heuristic: treat body as markup only when it contains tag-like delimiters.
    // Otherwise keep plain text behavior to avoid accidental markup parsing errors.
    if (std.mem.indexOfScalar(u8, trimmed, '<') != null and std.mem.indexOfScalar(u8, trimmed, '>') != null) {
        setLabelMarkup(label, trimmed);
    } else {
        setLabelText(label, trimmed);
    }
}

fn setLabelText(label: *c.GtkLabel, value: []const u8) void {
    if (value.len == 0) {
        c.gtk_label_set_text(label, "");
        return;
    }
    const value_z = c.g_strndup(value.ptr, @intCast(value.len)) orelse return;
    defer c.g_free(value_z);
    c.gtk_label_set_text(label, value_z);
}

fn setLabelMarkup(label: *c.GtkLabel, value: []const u8) void {
    if (value.len == 0) {
        c.gtk_label_set_markup(label, "");
        return;
    }
    const value_z = c.g_strndup(value.ptr, @intCast(value.len)) orelse return;
    defer c.g_free(value_z);
    c.gtk_label_set_markup(label, value_z);
}

fn displaySummary(summary: []const u8, app_name: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, summary, " \t\r\n");
    if (trimmed.len > 0) return trimmed;
    const app_trimmed = std.mem.trim(u8, app_name, " \t\r\n");
    if (app_trimmed.len > 0) return app_trimmed;
    return "Notification";
}

fn displayActionLabel(action: notifications.Daemon.Action) []const u8 {
    const label = std.mem.trim(u8, action.label, " \t\r\n");
    if (label.len > 0) return label;
    const key = std.mem.trim(u8, action.key, " \t\r\n");
    if (key.len == 0 or std.mem.eql(u8, key, "default")) return "Open";
    if (std.mem.eql(u8, key, "dismiss")) return "Dismiss";
    return prettifyActionKey(key);
}

fn actionIconName(action: notifications.Daemon.Action) [*:0]const u8 {
    const key = std.mem.trim(u8, action.key, " \t\r\n");
    if (std.mem.eql(u8, key, "dismiss")) return "window-close-symbolic";
    if (std.mem.indexOf(u8, key, "reply") != null) return "mail-reply-sender-symbolic";
    if (std.mem.indexOf(u8, key, "open") != null) return "external-link-symbolic";
    if (std.mem.indexOf(u8, key, "view") != null) return "document-open-symbolic";
    return "emblem-ok-symbolic";
}

fn configureActionButton(button: *c.GtkWidget, action: notifications.Daemon.Action) void {
    const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
    c.gtk_widget_add_css_class(content, "gs-notify-action-content");
    c.gtk_widget_set_halign(content, c.GTK_ALIGN_START);
    const icon = c.gtk_image_new_from_icon_name(actionIconName(action));
    c.gtk_image_set_pixel_size(@ptrCast(icon), 15);
    c.gtk_widget_add_css_class(icon, "gs-notify-action-icon");
    const label = c.gtk_label_new("");
    const label_text = displayActionLabel(action);
    setLabelText(@ptrCast(label), label_text);
    c.gtk_label_set_wrap(@ptrCast(label), GTRUE);
    c.gtk_label_set_wrap_mode(@ptrCast(label), c.PANGO_WRAP_WORD_CHAR);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-notify-action-label");
    c.gtk_box_append(@ptrCast(content), icon);
    c.gtk_box_append(@ptrCast(content), label);
    c.gtk_button_set_child(@ptrCast(button), content);
    const tooltip_z = c.g_strndup(label_text.ptr, @intCast(label_text.len)) orelse return;
    defer c.g_free(tooltip_z);
    c.gtk_widget_set_tooltip_text(button, tooltip_z);
}

fn shouldStackActions(actions: []const notifications.Daemon.Action) bool {
    return actions.len > 3;
}

fn prettifyActionKey(key: []const u8) []const u8 {
    if (std.mem.eql(u8, key, "reply")) return "Reply";
    if (std.mem.eql(u8, key, "archive")) return "Archive";
    if (std.mem.eql(u8, key, "mark-read")) return "Mark Read";
    if (std.mem.eql(u8, key, "mark_read")) return "Mark Read";
    if (std.mem.eql(u8, key, "open")) return "Open";
    return key;
}
