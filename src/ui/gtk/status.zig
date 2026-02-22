const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_query = @import("query_helpers.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;
const POWER_CONFIRM_STATUS = "Press Enter again to confirm Power menu";

pub const Hooks = struct {
    select_first: *const fn (*UiContext) void,
};

const StatusTone = enum {
    neutral,
    info,
    success,
    failure,
};

pub fn setStatus(ctx: *UiContext, message: []const u8) void {
    if (!shouldAllowStatusWhilePowerConfirm(ctx.pending_power_confirm, message)) return;
    setStatusWithTone(ctx, message, launchStatusTone(message));
}

pub fn showLaunchFeedback(ctx: *UiContext, message: []const u8, hooks: Hooks) void {
    clearLaunchFeedbackRows(ctx.list);
    appendLaunchFeedbackRow(ctx.list, message);
    setStatusWithTone(ctx, gtk_query.postLaunchStatus(message), launchStatusTone(message));
    scheduleStatusReset(ctx);
    hooks.select_first(ctx);
}

fn scheduleStatusReset(ctx: *UiContext) void {
    if (ctx.status_reset_id != 0) {
        _ = c.g_source_remove(ctx.status_reset_id);
        ctx.status_reset_id = 0;
    }
    const reset_ctx_raw = c.g_malloc0(@sizeOf(StatusResetContext)) orelse return;
    const reset_ctx: *StatusResetContext = @ptrCast(@alignCast(reset_ctx_raw));
    reset_ctx.* = .{
        .ctx = ctx,
        .status_hash = ctx.last_status_hash,
        .status_tone = ctx.last_status_tone,
    };
    ctx.status_reset_id = c.g_timeout_add_full(c.G_PRIORITY_DEFAULT, 1700, onStatusReset, reset_ctx, c.g_free);
}

fn onStatusReset(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const reset_ctx: *StatusResetContext = @ptrCast(@alignCast(user_data.?));
    const ctx = reset_ctx.ctx;
    ctx.status_reset_id = 0;
    if (!shouldRunStatusReset(
        ctx.pending_power_confirm,
        ctx.last_status_hash,
        ctx.last_status_tone,
        reset_ctx.status_hash,
        reset_ctx.status_tone,
    )) return GFALSE;

    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    const query = if (text_ptr != null) std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr))) else "";
    const query_trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (query_trimmed.len == 0) {
        setStatus(ctx, "Esc close | Ctrl+R refresh | @ apps # windows ~ dirs % files & grep > run = calc ? web");
    } else {
        setStatus(ctx, "");
    }
    return GFALSE;
}

const StatusResetContext = struct {
    ctx: *UiContext,
    status_hash: u64,
    status_tone: u8,
};

fn shouldAllowStatusWhilePowerConfirm(pending_power_confirm: c.gboolean, message: []const u8) bool {
    return pending_power_confirm == GFALSE or std.mem.eql(u8, message, POWER_CONFIRM_STATUS);
}

fn shouldRunStatusReset(
    pending_power_confirm: c.gboolean,
    current_hash: u64,
    current_tone: u8,
    scheduled_hash: u64,
    scheduled_tone: u8,
) bool {
    if (pending_power_confirm == GTRUE) return false;
    return current_hash == scheduled_hash and current_tone == scheduled_tone;
}

fn clearLaunchFeedbackRows(list: *c.GtkListBox) void {
    var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child);
        if (c.g_object_get_data(@ptrCast(child), "gs-feedback") != null) {
            c.gtk_list_box_remove(list, child);
        }
        child = next;
    }
}

fn appendLaunchFeedbackRow(list: *c.GtkListBox, message: []const u8) void {
    const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
    defer std.heap.page_allocator.free(msg_z);

    const label = c.gtk_label_new(msg_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-info");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), label);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.g_object_set_data_full(@ptrCast(row), "gs-feedback", c.g_strdup("1"), c.g_free);
    c.gtk_list_box_append(@ptrCast(list), row);
}

fn setStatusWithTone(ctx: *UiContext, message: []const u8, tone: StatusTone) void {
    const status_hash = std.hash.Wyhash.hash(0, message);
    const tone_code = statusToneCode(tone);
    if (ctx.last_status_hash == status_hash and ctx.last_status_tone == tone_code) return;

    const status_widget: *c.GtkWidget = @ptrCast(@alignCast(ctx.status));
    c.gtk_widget_remove_css_class(status_widget, "gs-status-info");
    c.gtk_widget_remove_css_class(status_widget, "gs-status-success");
    c.gtk_widget_remove_css_class(status_widget, "gs-status-failure");
    c.gtk_widget_remove_css_class(status_widget, "gs-status-searching");
    if (std.mem.indexOf(u8, message, "Searching") != null) {
        c.gtk_widget_add_css_class(status_widget, "gs-status-searching");
    }
    switch (tone) {
        .info => c.gtk_widget_add_css_class(status_widget, "gs-status-info"),
        .success => c.gtk_widget_add_css_class(status_widget, "gs-status-success"),
        .failure => c.gtk_widget_add_css_class(status_widget, "gs-status-failure"),
        .neutral => {},
    }
    const prefix = statusPrefix(tone);
    if (prefix.len > 0) {
        const composed = std.fmt.allocPrint(std.heap.page_allocator, "{s} {s}", .{ prefix, message }) catch return;
        defer std.heap.page_allocator.free(composed);
        const msg_z = std.heap.page_allocator.dupeZ(u8, composed) catch return;
        defer std.heap.page_allocator.free(msg_z);
        c.gtk_label_set_text(ctx.status, msg_z.ptr);
    } else {
        const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
        defer std.heap.page_allocator.free(msg_z);
        c.gtk_label_set_text(ctx.status, msg_z.ptr);
    }
    ctx.last_status_hash = status_hash;
    ctx.last_status_tone = tone_code;
}

fn launchStatusTone(message: []const u8) StatusTone {
    if (std.mem.indexOf(u8, message, "Searching") != null) return .info;
    if (std.mem.indexOf(u8, message, "Refresh") != null) return .info;
    if (std.mem.indexOf(u8, message, "fallback") != null) return .info;
    if (std.mem.indexOf(u8, message, "failed") != null) return .failure;
    if (std.mem.indexOf(u8, message, "launched") != null) return .success;
    if (std.mem.indexOf(u8, message, "opened") != null) return .success;
    if (std.mem.indexOf(u8, message, "focused") != null) return .success;
    return .neutral;
}

fn statusToneCode(tone: StatusTone) u8 {
    return switch (tone) {
        .neutral => 0,
        .info => 1,
        .success => 2,
        .failure => 3,
    };
}

fn statusPrefix(tone: StatusTone) []const u8 {
    return switch (tone) {
        .neutral => "",
        .info => "[i]",
        .success => "[ok]",
        .failure => "[!]",
    };
}

test "launchStatusTone classifies known status messages" {
    try std.testing.expectEqual(StatusTone.info, launchStatusTone("Searching..."));
    try std.testing.expectEqual(StatusTone.info, launchStatusTone("Refresh complete"));
    try std.testing.expectEqual(StatusTone.info, launchStatusTone("using fallback provider"));
    try std.testing.expectEqual(StatusTone.failure, launchStatusTone("launch failed"));
    try std.testing.expectEqual(StatusTone.success, launchStatusTone("launched kitty"));
    try std.testing.expectEqual(StatusTone.success, launchStatusTone("opened file"));
    try std.testing.expectEqual(StatusTone.success, launchStatusTone("focused window"));
    try std.testing.expectEqual(StatusTone.neutral, launchStatusTone("idle"));
}

test "statusPrefix maps tone markers" {
    try std.testing.expectEqualStrings("", statusPrefix(.neutral));
    try std.testing.expectEqualStrings("[i]", statusPrefix(.info));
    try std.testing.expectEqualStrings("[ok]", statusPrefix(.success));
    try std.testing.expectEqualStrings("[!]", statusPrefix(.failure));
}

test "launchStatusTone keeps failure precedence over success tokens" {
    try std.testing.expectEqual(StatusTone.failure, launchStatusTone("opened but failed"));
}

test "power confirm only allows power confirmation prompt status updates" {
    try std.testing.expect(shouldAllowStatusWhilePowerConfirm(GFALSE, "Searching..."));
    try std.testing.expect(shouldAllowStatusWhilePowerConfirm(GTRUE, POWER_CONFIRM_STATUS));
    try std.testing.expect(!shouldAllowStatusWhilePowerConfirm(GTRUE, "Searching..."));
}

test "status reset guard rejects stale or blocked timer callbacks" {
    try std.testing.expect(shouldRunStatusReset(GFALSE, 10, 2, 10, 2));
    try std.testing.expect(!shouldRunStatusReset(GTRUE, 10, 2, 10, 2));
    try std.testing.expect(!shouldRunStatusReset(GFALSE, 11, 2, 10, 2));
    try std.testing.expect(!shouldRunStatusReset(GFALSE, 10, 1, 10, 2));
}
