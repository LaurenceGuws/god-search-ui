const std = @import("std");
const gtk_types = @import("types.zig");
const c = gtk_types.c;
const UiContext = gtk_types.UiContext;

pub fn updateScrollbarActiveClass(ctx: *UiContext) void {
    const vadj = c.gtk_scrolled_window_get_vadjustment(ctx.scroller);
    if (vadj == null) return;
    const upper = c.gtk_adjustment_get_upper(vadj);
    const page = c.gtk_adjustment_get_page_size(vadj);
    const active = (upper - page) > 1.0;
    if (active) {
        c.gtk_widget_add_css_class(@ptrCast(@alignCast(ctx.list)), "gs-scroll-active");
    } else {
        c.gtk_widget_remove_css_class(@ptrCast(@alignCast(ctx.list)), "gs-scroll-active");
    }
}

pub fn activateSelectedRow(ctx: *UiContext) void {
    var row = c.gtk_list_box_get_selected_row(ctx.list);
    if (row == null) {
        selectFirstActionableRow(ctx);
        row = c.gtk_list_box_get_selected_row(ctx.list);
    }
    if (row != null) c.g_signal_emit_by_name(ctx.list, "row-activated", row);
}

pub fn selectActionableDelta(ctx: *UiContext, delta: i32) void {
    if (delta == 0) return;
    const step: i32 = if (delta > 0) 1 else -1;
    const target_moves: i32 = @intCast(@abs(delta));
    const selected = c.gtk_list_box_get_selected_row(ctx.list);
    if (selected == null) {
        if (delta > 0) {
            selectFirstActionableRow(ctx);
        } else {
            selectLastActionableRow(ctx);
        }
        return;
    }

    var idx: i32 = c.gtk_list_box_row_get_index(selected) + step;
    if (idx < 0) return;

    var moved: i32 = 0;
    while (idx >= 0) : (idx += step) {
        const target = c.gtk_list_box_get_row_at_index(ctx.list, idx);
        if (target == null) return;
        if (c.g_object_get_data(@ptrCast(target), "gs-action") != null) {
            moved += 1;
            if (moved >= target_moves) {
                c.gtk_list_box_select_row(ctx.list, target);
                ensureSelectedRowVisible(ctx);
                return;
            }
        }
    }
}

pub fn selectFirstActionableRow(ctx: *UiContext) void {
    var idx: i32 = 0;
    while (true) : (idx += 1) {
        const row = c.gtk_list_box_get_row_at_index(ctx.list, idx);
        if (row == null) break;
        if (c.g_object_get_data(@ptrCast(row), "gs-action") != null) {
            c.gtk_list_box_select_row(ctx.list, row);
            ensureSelectedRowVisible(ctx);
            return;
        }
    }
    c.gtk_list_box_select_row(ctx.list, null);
}

pub fn selectLastActionableRow(ctx: *UiContext) void {
    var idx: i32 = 0;
    while (c.gtk_list_box_get_row_at_index(ctx.list, idx) != null) : (idx += 1) {}
    idx -= 1;
    while (idx >= 0) : (idx -= 1) {
        const row = c.gtk_list_box_get_row_at_index(ctx.list, idx);
        if (row == null) break;
        if (c.g_object_get_data(@ptrCast(row), "gs-action") != null) {
            c.gtk_list_box_select_row(ctx.list, row);
            ensureSelectedRowVisible(ctx);
            return;
        }
    }
    c.gtk_list_box_select_row(ctx.list, null);
}

pub fn ensureSelectedRowVisible(ctx: *UiContext) void {
    const row = c.gtk_list_box_get_selected_row(ctx.list);
    if (row == null) return;

    const adjustment = c.gtk_scrolled_window_get_vadjustment(ctx.scroller);
    if (adjustment == null) return;

    var alloc: c.GtkAllocation = undefined;
    c.gtk_widget_get_allocation(@ptrCast(row), &alloc);
    const top = @as(f64, @floatFromInt(alloc.y));
    const bottom = @as(f64, @floatFromInt(alloc.y + alloc.height));
    const value = c.gtk_adjustment_get_value(adjustment);
    const page_size = c.gtk_adjustment_get_page_size(adjustment);

    if (top < value) {
        c.gtk_adjustment_set_value(adjustment, top);
    } else if (bottom > (value + page_size)) {
        c.gtk_adjustment_set_value(adjustment, bottom - page_size);
    }
}
