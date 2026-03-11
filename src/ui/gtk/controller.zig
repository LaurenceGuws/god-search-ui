const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_nav = @import("navigation.zig");
const gtk_query = @import("query_helpers.zig");
const gtk_row_data = @import("row_data.zig");
const gtk_preview = @import("preview.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

pub const InputHooks = struct {
    refresh_snapshot: *const fn (*UiContext) void,
    reload_config: *const fn (*UiContext) void,
    toggle_preview: *const fn (*UiContext) void,
    set_status: *const fn (*UiContext, []const u8) void,
    hide_session: *const fn (*UiContext) void,
};

pub const StatusHooks = struct {
    set_status: *const fn (*UiContext, []const u8) void,
};

pub const ScrollHooks = struct {
    poll_more: *const fn (*UiContext) void,
};

pub fn handleKeyPressed(ctx: *UiContext, keyval: c.guint, state: c.GdkModifierType, hooks: InputHooks) c.gboolean {
    if (captureStartupKey(ctx, keyval, state)) {
        return GTRUE;
    }
    if (redirectPrintableKeyToEntry(ctx, keyval, state)) {
        return GTRUE;
    }
    switch (keyval) {
        c.GDK_KEY_Escape => {
            if (ctx.resident_mode == GTRUE) {
                hooks.hide_session(ctx);
            } else {
                c.gtk_window_close(@ptrCast(ctx.window));
            }
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
                if ((state & c.GDK_SHIFT_MASK) != 0) {
                    hooks.reload_config(ctx);
                    return GTRUE;
                }
                hooks.refresh_snapshot(ctx);
                return GTRUE;
            }
            return GFALSE;
        },
        c.GDK_KEY_p, c.GDK_KEY_P => {
            if ((state & c.GDK_CONTROL_MASK) != 0) {
                hooks.toggle_preview(ctx);
                hooks.set_status(ctx, if (ctx.preview_enabled == GTRUE) "Preview panel enabled" else "Preview panel hidden");
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

pub fn enableStartupKeyQueue(ctx: *UiContext) void {
    ctx.startup_key_queue_active = GTRUE;
    ctx.startup_key_queue_len = 0;
}

pub fn flushAndDisableStartupKeyQueue(ctx: *UiContext) void {
    if (ctx.startup_key_queue_len > 0) {
        _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(ctx.entry)));
        var idx: usize = 0;
        const queued_len: usize = @intCast(ctx.startup_key_queue_len);
        while (idx < queued_len) : (idx += 1) {
            const codepoint: u21 = @intCast(ctx.startup_key_queue[idx]);
            insertCodepointIntoEntry(ctx, codepoint);
        }
    }
    disableStartupKeyQueue(ctx);
}

pub fn disableStartupKeyQueue(ctx: *UiContext) void {
    ctx.startup_key_queue_active = GFALSE;
    ctx.startup_key_queue_len = 0;
}

fn captureStartupKey(ctx: *UiContext, keyval: c.guint, state: c.GdkModifierType) bool {
    if (ctx.startup_key_queue_active == GFALSE) return false;
    const codepoint = printableCodepointFromKeyForStartup(keyval, state) orelse return false;

    if (isEntryFocused(ctx)) {
        flushAndDisableStartupKeyQueue(ctx);
        return false;
    }

    queueStartupCodepoint(ctx, codepoint);
    _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(ctx.entry)));
    return true;
}

fn queueStartupCodepoint(ctx: *UiContext, codepoint: u21) void {
    if (ctx.startup_key_queue_len < @as(u8, @intCast(ctx.startup_key_queue.len))) {
        const queue_idx: usize = @intCast(ctx.startup_key_queue_len);
        ctx.startup_key_queue[queue_idx] = codepoint;
        ctx.startup_key_queue_len += 1;
        return;
    }

    insertCodepointIntoEntry(ctx, codepoint);
}

fn redirectPrintableKeyToEntry(ctx: *UiContext, keyval: c.guint, state: c.GdkModifierType) bool {
    if (ctx.startup_key_queue_active == GTRUE) return false;
    const codepoint = printableCodepointFromKey(keyval, state) orelse return false;
    if (isEntryFocused(ctx)) return false;

    insertCodepointIntoEntry(ctx, codepoint);
    _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(ctx.entry)));
    return true;
}

fn printableCodepointFromKey(keyval: c.guint, state: c.GdkModifierType) ?u21 {
    const disallowed = c.GDK_CONTROL_MASK | c.GDK_ALT_MASK | c.GDK_META_MASK | c.GDK_SUPER_MASK;
    return printableCodepointFromKeyWithMask(keyval, state, disallowed);
}

fn printableCodepointFromKeyForStartup(keyval: c.guint, state: c.GdkModifierType) ?u21 {
    // During immediate post-launch typing, some compositors may still report SUPER/META
    // on the first printable key right after the launcher chord is released.
    const disallowed = c.GDK_CONTROL_MASK | c.GDK_ALT_MASK;
    return printableCodepointFromKeyWithMask(keyval, state, disallowed);
}

fn printableCodepointFromKeyWithMask(keyval: c.guint, state: c.GdkModifierType, disallowed: c.GdkModifierType) ?u21 {
    if ((state & disallowed) != 0) return null;

    const codepoint: u21 = @intCast(c.gdk_keyval_to_unicode(keyval));
    if (codepoint == 0) return null;
    if (c.g_unichar_isprint(codepoint) == 0) return null;
    if (!std.unicode.utf8ValidCodepoint(codepoint)) return null;
    return codepoint;
}

fn isEntryFocused(ctx: *UiContext) bool {
    const focused = c.gtk_window_get_focus(@ptrCast(ctx.window));
    return focused != null and focused == @as(*c.GtkWidget, @ptrCast(@alignCast(ctx.entry)));
}

fn insertCodepointIntoEntry(ctx: *UiContext, codepoint: u21) void {
    var utf8_buf: [4]u8 = undefined;
    const encoded_len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch return;
    const editable: *c.GtkEditable = @ptrCast(@alignCast(ctx.entry));
    var cursor_pos: c_int = -1;
    c.gtk_editable_insert_text(
        editable,
        utf8_buf[0..encoded_len].ptr,
        @as(c_int, @intCast(encoded_len)),
        &cursor_pos,
    );
}

pub fn handleEntryActivate(ctx: *UiContext) void {
    gtk_nav.activateSelectedRow(ctx);
}

pub fn handleResultsAdjustmentChanged(ctx: *UiContext, hooks: ScrollHooks) void {
    gtk_nav.updateScrollbarActiveClass(ctx);
    hooks.poll_more(ctx);
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
    gtk_preview.updateForRow(ctx, row);
    if (ctx.pending_power_confirm == GTRUE) return;
    const query_flags = ctx.service.queryFlagsSnapshot();
    if (query_flags.last_query_had_provider_runtime_failure or
        query_flags.last_query_used_stale_cache or
        query_flags.last_query_refreshed_cache)
    {
        return;
    }

    const title = gtk_row_data.title(row) orelse return;
    const kind_label = common_dispatch.kinds.statusLabel(gtk_row_data.kind(row));
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const msg = std.fmt.allocPrint(allocator_ptr.*, "Enter launch {s}: {s}", .{ kind_label, title }) catch return;
    defer allocator_ptr.*.free(msg);
    hooks.set_status(ctx, msg);
}
