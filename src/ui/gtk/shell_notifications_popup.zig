const std = @import("std");
const gtk_types = @import("types.zig");
const notifications = @import("../../notifications/mod.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const default_expire_ms: i32 = 5000;

const PopupEntry = struct {
    id: u32,
    row: *c.GtkWidget,
    summary_label: *c.GtkLabel,
    body_label: *c.GtkLabel,
    timeout_id: c.guint,
};

const DismissPayload = struct {
    manager: *PopupManager,
    id: u32,
};

const TimeoutPayload = struct {
    manager: *PopupManager,
    id: u32,
};

pub const PopupManager = struct {
    allocator: std.mem.Allocator,
    daemon: *notifications.Daemon,
    gtk_app: *c.GtkApplication,
    window: ?*c.GtkWidget,
    list: ?*c.GtkWidget,
    entries: std.ArrayList(PopupEntry),

    pub fn init(allocator: std.mem.Allocator, gtk_app: *c.GtkApplication, daemon: *notifications.Daemon) !PopupManager {
        const manager = PopupManager{
            .allocator = allocator,
            .daemon = daemon,
            .gtk_app = gtk_app,
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
            c.gtk_label_set_text(entry.body_label, toCStr(event.body));
            rescheduleTimeout(self, entry, event.expire_timeout);
        } else {
            const row = createRow(self, event.id, event.summary, event.body) catch return;
            self.entries.append(self.allocator, .{
                .id = event.id,
                .row = row.row,
                .summary_label = row.summary_label,
                .body_label = row.body_label,
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
        _ = c.g_signal_connect_data(close_btn, "clicked", c.G_CALLBACK(onDismissClicked), payload, onPayloadDestroyed, 0);

        c.gtk_box_append(@ptrCast(header), summary_label);
        c.gtk_box_append(@ptrCast(header), close_btn);

        const body_label = c.gtk_label_new(toCStr(body));
        c.gtk_label_set_xalign(@ptrCast(body_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(body_label), GTRUE);
        c.gtk_widget_add_css_class(body_label, "gs-notify-body");

        c.gtk_box_append(@ptrCast(row), header);
        c.gtk_box_append(@ptrCast(row), body_label);
        c.gtk_box_append(@ptrCast(self.list.?), row);

        return .{
            .row = @ptrCast(row),
            .summary_label = @ptrCast(summary_label),
            .body_label = @ptrCast(body_label),
        };
    }

    fn onDismissClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        const payload: *DismissPayload = @ptrCast(@alignCast(user_data.?));
        _ = payload.manager.daemon.closeWithReason(payload.id, 2);
    }

    fn onPayloadDestroyed(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
        if (data) |payload| c.g_free(payload);
    }

    fn ensureWindow(self: *PopupManager) bool {
        if (self.window != null and self.list != null) return true;

        const window = c.gtk_application_window_new(self.gtk_app);
        c.gtk_window_set_title(@ptrCast(window), "God Search Notifications");
        c.gtk_window_set_default_size(@ptrCast(window), 380, 360);
        c.gtk_window_set_resizable(@ptrCast(window), GFALSE);
        c.gtk_window_set_decorated(@ptrCast(window), GFALSE);

        const frame = c.gtk_frame_new(null);
        c.gtk_widget_add_css_class(frame, "gs-notify-frame");

        const scroller = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
        c.gtk_widget_set_vexpand(scroller, GTRUE);

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
};

fn toCStr(value: []const u8) [*:0]const u8 {
    if (value.len == 0) return "";
    return @ptrCast(value.ptr);
}
