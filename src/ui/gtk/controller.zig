const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_nav = @import("navigation.zig");
const gtk_query = @import("query_helpers.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiKind = common_dispatch.kinds.UiKind;

pub const InputHooks = struct {
    refresh_snapshot: *const fn (*UiContext) void,
};

pub const StatusHooks = struct {
    set_status: *const fn (*UiContext, []const u8) void,
};

pub fn handleKeyPressed(ctx: *UiContext, keyval: c.guint, state: c.GdkModifierType, hooks: InputHooks) c.gboolean {
    switch (keyval) {
        c.GDK_KEY_Escape => {
            c.gtk_window_close(@ptrCast(ctx.window));
            return GTRUE;
        },
        c.GDK_KEY_l, c.GDK_KEY_L => {
            if ((state & c.GDK_CONTROL_MASK) != 0) {
                _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(ctx.entry)));
                return GTRUE;
            }
            return GFALSE;
        },
        c.GDK_KEY_r, c.GDK_KEY_R => {
            if ((state & c.GDK_CONTROL_MASK) != 0) {
                hooks.refresh_snapshot(ctx);
                return GTRUE;
            }
            return GFALSE;
        },
        c.GDK_KEY_Down => {
            gtk_nav.selectActionableDelta(ctx, 1);
            return GTRUE;
        },
        c.GDK_KEY_Up => {
            gtk_nav.selectActionableDelta(ctx, -1);
            return GTRUE;
        },
        c.GDK_KEY_Page_Down => {
            gtk_nav.selectActionableDelta(ctx, 5);
            return GTRUE;
        },
        c.GDK_KEY_Page_Up => {
            gtk_nav.selectActionableDelta(ctx, -5);
            return GTRUE;
        },
        c.GDK_KEY_Home => {
            gtk_nav.selectFirstActionableRow(ctx);
            return GTRUE;
        },
        c.GDK_KEY_End => {
            gtk_nav.selectLastActionableRow(ctx);
            return GTRUE;
        },
        c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
            gtk_nav.activateSelectedRow(ctx);
            return GTRUE;
        },
        else => return GFALSE,
    }
}

pub fn handleEntryActivate(ctx: *UiContext) void {
    gtk_nav.activateSelectedRow(ctx);
}

pub fn handleResultsAdjustmentChanged(ctx: *UiContext) void {
    gtk_nav.updateScrollbarActiveClass(ctx);
}

pub fn updateEntryRouteIcon(ctx: *UiContext, query: []const u8) void {
    const entry: *c.GtkEntry = @ptrCast(@alignCast(ctx.entry));
    const route_icon = gtk_query.routeIconForLeadingPrefix(query);
    if (route_icon) |icon_name| {
        const icon_z = std.heap.page_allocator.dupeZ(u8, icon_name) catch return;
        defer std.heap.page_allocator.free(icon_z);
        c.gtk_entry_set_icon_from_icon_name(entry, c.GTK_ENTRY_ICON_PRIMARY, icon_z.ptr);
        c.gtk_entry_set_icon_sensitive(entry, c.GTK_ENTRY_ICON_PRIMARY, GTRUE);
        c.gtk_entry_set_icon_activatable(entry, c.GTK_ENTRY_ICON_PRIMARY, GFALSE);
        return;
    }
    c.gtk_entry_set_icon_from_icon_name(entry, c.GTK_ENTRY_ICON_PRIMARY, null);
}

pub fn handleRowSelected(ctx: *UiContext, row: *c.GtkListBoxRow, hooks: StatusHooks) void {
    if (ctx.pending_power_confirm == GTRUE) return;
    if (ctx.service.last_query_used_stale_cache or ctx.service.last_query_refreshed_cache) return;

    const title_ptr = c.g_object_get_data(@ptrCast(row), "gs-title");
    if (title_ptr == null) return;
    const title = std.mem.span(@as([*:0]const u8, @ptrCast(title_ptr)));
    const kind_label = common_dispatch.kinds.statusLabel(kindFromRow(row));
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const msg = std.fmt.allocPrint(allocator_ptr.*, "Enter launch {s}: {s}", .{ kind_label, title }) catch return;
    defer allocator_ptr.*.free(msg);
    hooks.set_status(ctx, msg);
}

fn kindFromRow(row: *c.GtkListBoxRow) UiKind {
    const kind_id_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind-id");
    if (kind_id_ptr != null) {
        const raw = @as(usize, @intFromPtr(kind_id_ptr));
        if (raw > 0) {
            const idx = raw - 1;
            if (idx <= @intFromEnum(UiKind.file_option)) {
                return @enumFromInt(idx);
            }
        }
    }
    const kind_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind");
    if (kind_ptr == null) return .unknown;
    return common_dispatch.kinds.parse(std.mem.span(@as([*:0]const u8, @ptrCast(kind_ptr))));
}
