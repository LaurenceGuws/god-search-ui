const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_row_data = @import("row_data.zig");
const c = gtk_types.c;
const UiContext = gtk_types.UiContext;

const IndexExistsFn = *const fn (?*anyopaque, i32) bool;
const IndexActionableFn = *const fn (?*anyopaque, i32) bool;

const DeltaStep = struct {
    step: i32,
    moves: i32,
};

fn deltaStep(delta: i32) ?DeltaStep {
    if (delta == 0) return null;
    return .{
        .step = if (delta > 0) 1 else -1,
        .moves = @intCast(@abs(delta)),
    };
}

fn firstActionableIndex(ctx: ?*anyopaque, exists_fn: IndexExistsFn, actionable_fn: IndexActionableFn) ?i32 {
    var idx: i32 = 0;
    while (exists_fn(ctx, idx)) : (idx += 1) {
        if (actionable_fn(ctx, idx)) return idx;
    }
    return null;
}

fn lastActionableIndex(ctx: ?*anyopaque, exists_fn: IndexExistsFn, actionable_fn: IndexActionableFn) ?i32 {
    var idx: i32 = 0;
    while (exists_fn(ctx, idx)) : (idx += 1) {}
    idx -= 1;
    while (idx >= 0) : (idx -= 1) {
        if (actionable_fn(ctx, idx)) return idx;
    }
    return null;
}

fn actionableDeltaIndex(
    ctx: ?*anyopaque,
    exists_fn: IndexExistsFn,
    actionable_fn: IndexActionableFn,
    start_idx: i32,
    step: i32,
    target_moves: i32,
) ?i32 {
    if (target_moves <= 0) return null;
    var idx = start_idx;
    if (idx < 0) return null;
    var last_actionable: ?i32 = null;

    var moved: i32 = 0;
    while (idx >= 0) : (idx += step) {
        if (!exists_fn(ctx, idx)) return last_actionable;
        if (actionable_fn(ctx, idx)) {
            last_actionable = idx;
            moved += 1;
            if (moved >= target_moves) return idx;
        }
    }
    return last_actionable;
}

fn clampF64(value: f64, min: f64, max: f64) f64 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

fn scrollTarget(top: f64, bottom: f64, value: f64, page_size: f64, upper: f64) ?f64 {
    const unclamped = if (top < value)
        top
    else if (bottom > (value + page_size))
        (bottom - page_size)
    else
        return null;

    const max_value = @max(0.0, upper - page_size);
    return clampF64(unclamped, 0.0, max_value);
}

fn gtkIndexExists(ctx_ptr: ?*anyopaque, idx: i32) bool {
    const ctx: *UiContext = @ptrCast(@alignCast(ctx_ptr orelse return false));
    return c.gtk_list_box_get_row_at_index(ctx.list, idx) != null;
}

fn gtkIndexActionable(ctx_ptr: ?*anyopaque, idx: i32) bool {
    const ctx: *UiContext = @ptrCast(@alignCast(ctx_ptr orelse return false));
    const row = c.gtk_list_box_get_row_at_index(ctx.list, idx) orelse return false;
    return gtk_row_data.action(row) != null;
}

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
    const info = deltaStep(delta) orelse return;
    const selected = c.gtk_list_box_get_selected_row(ctx.list);
    if (selected == null) {
        if (delta > 0) {
            selectFirstActionableRow(ctx);
        } else {
            selectLastActionableRow(ctx);
        }
        return;
    }

    const start_idx: i32 = c.gtk_list_box_row_get_index(selected) + info.step;
    const target_idx = actionableDeltaIndex(ctx, gtkIndexExists, gtkIndexActionable, start_idx, info.step, info.moves) orelse return;
    const target = c.gtk_list_box_get_row_at_index(ctx.list, target_idx) orelse return;
    c.gtk_list_box_select_row(ctx.list, target);
    ensureSelectedRowVisible(ctx);
}

pub fn selectFirstActionableRow(ctx: *UiContext) void {
    const idx = firstActionableIndex(ctx, gtkIndexExists, gtkIndexActionable) orelse {
        c.gtk_list_box_select_row(ctx.list, null);
        return;
    };
    const row = c.gtk_list_box_get_row_at_index(ctx.list, idx) orelse {
        c.gtk_list_box_select_row(ctx.list, null);
        return;
    };
    c.gtk_list_box_select_row(ctx.list, row);
    ensureSelectedRowVisible(ctx);
}

pub fn selectLastActionableRow(ctx: *UiContext) void {
    const idx = lastActionableIndex(ctx, gtkIndexExists, gtkIndexActionable) orelse {
        c.gtk_list_box_select_row(ctx.list, null);
        return;
    };
    const row = c.gtk_list_box_get_row_at_index(ctx.list, idx) orelse {
        c.gtk_list_box_select_row(ctx.list, null);
        return;
    };
    c.gtk_list_box_select_row(ctx.list, row);
    ensureSelectedRowVisible(ctx);
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
    const upper = c.gtk_adjustment_get_upper(adjustment);
    const target = scrollTarget(top, bottom, value, page_size, upper) orelse return;
    c.gtk_adjustment_set_value(adjustment, target);
}

const NavFixture = struct {
    actionable: []const bool,
};

fn fixtureIndexExists(ctx_ptr: ?*anyopaque, idx: i32) bool {
    const fixture: *const NavFixture = @ptrCast(@alignCast(ctx_ptr orelse return false));
    if (idx < 0) return false;
    const uidx: usize = @intCast(idx);
    return uidx < fixture.actionable.len;
}

fn fixtureIndexActionable(ctx_ptr: ?*anyopaque, idx: i32) bool {
    const fixture: *const NavFixture = @ptrCast(@alignCast(ctx_ptr orelse return false));
    if (idx < 0) return false;
    const uidx: usize = @intCast(idx);
    if (uidx >= fixture.actionable.len) return false;
    return fixture.actionable[uidx];
}

test "deltaStep computes direction and move count" {
    try std.testing.expect(deltaStep(0) == null);
    try std.testing.expectEqual(@as(i32, 1), deltaStep(3).?.step);
    try std.testing.expectEqual(@as(i32, 3), deltaStep(3).?.moves);
    try std.testing.expectEqual(@as(i32, -1), deltaStep(-2).?.step);
    try std.testing.expectEqual(@as(i32, 2), deltaStep(-2).?.moves);
}

test "first and last actionable index ignore non-actionable rows and handle empty" {
    const empty_fixture = NavFixture{ .actionable = &.{} };
    try std.testing.expect(firstActionableIndex(@constCast(&empty_fixture), fixtureIndexExists, fixtureIndexActionable) == null);
    try std.testing.expect(lastActionableIndex(@constCast(&empty_fixture), fixtureIndexExists, fixtureIndexActionable) == null);

    const mixed_fixture = NavFixture{ .actionable = &.{ false, false, true, false, true, false } };
    try std.testing.expectEqual(@as(i32, 2), firstActionableIndex(@constCast(&mixed_fixture), fixtureIndexExists, fixtureIndexActionable).?);
    try std.testing.expectEqual(@as(i32, 4), lastActionableIndex(@constCast(&mixed_fixture), fixtureIndexExists, fixtureIndexActionable).?);
}

test "actionableDeltaIndex moves by actionable rows for both directions" {
    const fixture = NavFixture{ .actionable = &.{ false, true, false, true, false, true, false } };

    try std.testing.expectEqual(
        @as(i32, 3),
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 2, 1, 1).?,
    );
    try std.testing.expectEqual(
        @as(i32, 5),
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 2, 1, 2).?,
    );
    try std.testing.expectEqual(
        @as(i32, 1),
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 4, -1, 1).?,
    );
    try std.testing.expectEqual(
        @as(i32, 5),
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 2, 1, 5).?,
    );
    try std.testing.expectEqual(
        @as(i32, 1),
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 4, -1, 8).?,
    );
    try std.testing.expect(
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, 6, 1, 1) == null,
    );
    try std.testing.expect(
        actionableDeltaIndex(@constCast(&fixture), fixtureIndexExists, fixtureIndexActionable, -1, -1, 1) == null,
    );
}

test "scrollTarget computes and clamps adjustment target" {
    try std.testing.expect(scrollTarget(12.0, 28.0, 10.0, 25.0, 100.0) == null);

    const above_target = scrollTarget(-8.0, 2.0, 10.0, 20.0, 100.0).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), above_target, 0.0001);

    const below_target = scrollTarget(95.0, 130.0, 30.0, 20.0, 100.0).?;
    try std.testing.expectApproxEqAbs(@as(f64, 80.0), below_target, 0.0001);

    const inside_bounds = scrollTarget(45.0, 75.0, 30.0, 20.0, 200.0).?;
    try std.testing.expectApproxEqAbs(@as(f64, 55.0), inside_bounds, 0.0001);
}
