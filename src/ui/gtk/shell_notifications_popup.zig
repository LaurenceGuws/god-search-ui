const std = @import("std");
const gtk_types = @import("types.zig");
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
    window: ?*c.GtkWidget,
    list: ?*c.GtkWidget,
    entries: std.ArrayList(PopupEntry),

    pub fn init(
        allocator: std.mem.Allocator,
        gtk_app: *c.GtkApplication,
        daemon: *notifications.Daemon,
        surface_mode: SurfaceMode,
        placement_policy: NotificationPolicy,
    ) !PopupManager {
        const manager = PopupManager{
            .allocator = allocator,
            .daemon = daemon,
            .gtk_app = gtk_app,
            .surface_mode = surface_mode,
            .placement_policy = placement_policy,
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
        for (self.entries.items) |entry| {
            if (entry.timeout_id != 0) {
                _ = c.g_source_remove(entry.timeout_id);
            }
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
            c.gtk_label_set_text(entry.summary_label, toCStr(event.summary));
            setBodyLabel(entry.body_label, event.body);
            updateActions(self, entry.actions_box, event.id, event.actions);
            rescheduleTimeout(self, entry, event.expire_timeout);
        } else {
            const row = createRow(self, event.id, event.summary, event.body) catch return;
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
        if (entry.timeout_id != 0) {
            _ = c.g_source_remove(entry.timeout_id);
        }
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
        if (entry.timeout_id != 0) {
            _ = c.g_source_remove(entry.timeout_id);
            entry.timeout_id = 0;
        }

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

    fn createRow(self: *PopupManager, id: u32, summary: []const u8, body: []const u8) !struct {
        row: *c.GtkWidget,
        summary_label: *c.GtkLabel,
        body_label: *c.GtkLabel,
        actions_box: *c.GtkWidget,
    } {
        const row = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 6);
        c.gtk_widget_add_css_class(row, "gs-notify-row");

        const header = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);

        const summary_label = c.gtk_label_new(toCStr(summary));
        c.gtk_label_set_xalign(@ptrCast(summary_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(summary_label), GTRUE);
        c.gtk_widget_add_css_class(summary_label, "gs-notify-summary");
        c.gtk_widget_set_hexpand(summary_label, GTRUE);

        const close_btn = c.gtk_button_new_with_label("x");
        c.gtk_widget_add_css_class(close_btn, "gs-notify-close");
        const payload: *DismissPayload = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(DismissPayload))));
        payload.* = .{ .manager = self, .id = id };
        _ = c.g_signal_connect_data(close_btn, "clicked", c.G_CALLBACK(onDismissClicked), payload, onDismissPayloadDestroyed, 0);

        c.gtk_box_append(@ptrCast(header), summary_label);
        c.gtk_box_append(@ptrCast(header), close_btn);

        const body_label = c.gtk_label_new(toCStr(body));
        c.gtk_label_set_xalign(@ptrCast(body_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(body_label), GTRUE);
        c.gtk_label_set_use_markup(@ptrCast(body_label), GTRUE);
        setBodyLabel(@ptrCast(body_label), body);
        c.gtk_widget_add_css_class(body_label, "gs-notify-body");

        const actions_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 6);
        c.gtk_widget_add_css_class(actions_box, "gs-notify-actions");
        c.gtk_widget_set_visible(actions_box, GFALSE);

        c.gtk_box_append(@ptrCast(row), header);
        c.gtk_box_append(@ptrCast(row), body_label);
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
        // Keep notifications anchored by layer-shell whenever runtime support exists,
        // independent from launcher surface mode.
        _ = if (layer_shell.shouldUseLayerShell(.auto))
            layer_shell.applyNotifications(window)
        else
            false;
        placement_bridge.configureNotificationPopupWindow(window, self.placement_policy);
        c.gtk_window_set_resizable(@ptrCast(window), GFALSE);
        c.gtk_window_set_decorated(@ptrCast(window), GFALSE);

        const frame = c.gtk_frame_new(null);
        c.gtk_widget_add_css_class(frame, "gs-notify-frame");

        const scroller = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
        c.gtk_widget_set_vexpand(scroller, GFALSE);
        c.gtk_scrolled_window_set_max_content_height(@ptrCast(scroller), self.placement_policy.max_height_px);

        const list = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
        c.gtk_widget_set_margin_top(list, 10);
        c.gtk_widget_set_margin_bottom(list, 10);
        c.gtk_widget_set_margin_start(list, 10);
        c.gtk_widget_set_margin_end(list, 10);
        c.gtk_widget_add_css_class(list, "gs-notify-list");

        c.gtk_scrolled_window_set_child(@ptrCast(scroller), list);
        c.gtk_frame_set_child(@ptrCast(frame), scroller);
        c.gtk_window_set_child(@ptrCast(window), frame);
        c.gtk_widget_set_visible(window, GFALSE);

        self.window = @ptrCast(window);
        self.list = @ptrCast(list);
        return true;
    }

    fn updateActions(self: *PopupManager, actions_box: *c.GtkWidget, id: u32, actions: []const notifications.Daemon.Action) void {
        clearChildren(actions_box);
        if (actions.len == 0) {
            c.gtk_widget_set_visible(actions_box, GFALSE);
            return;
        }
        for (actions) |action| {
            const button = c.gtk_button_new_with_label(toCStr(action.label));
            c.gtk_widget_add_css_class(button, "gs-notify-action-btn");
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

fn toCStr(value: []const u8) [*:0]const u8 {
    if (value.len == 0) return "";
    return @ptrCast(value.ptr);
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
    // Basic heuristic: treat body as markup only when it contains tag-like delimiters.
    // Otherwise keep plain text behavior to avoid accidental markup parsing errors.
    if (std.mem.indexOfScalar(u8, body, '<') != null and std.mem.indexOfScalar(u8, body, '>') != null) {
        c.gtk_label_set_markup(label, toCStr(body));
    } else {
        c.gtk_label_set_text(label, toCStr(body));
    }
}
