const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_async_search = @import("async_search.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_status = @import("status.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

pub fn startAsyncRouteSearch(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_trimmed: []const u8,
    on_async_search_ready: *const fn (?*anyopaque) callconv(.c) c.gboolean,
) void {
    gtk_async_search.startAsyncRouteSearch(
        ctx,
        allocator,
        query_trimmed,
        .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner },
        on_async_search_ready,
    );
}

pub fn cancelAsyncRouteSearch(ctx: *UiContext) void {
    gtk_async_search.cancelAsyncRouteSearch(ctx, .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner });
}

pub fn launchPendingAsyncQuery(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    on_async_search_ready: *const fn (?*anyopaque) callconv(.c) c.gboolean,
) bool {
    return gtk_async_search.launchPendingAsyncQuery(
        ctx,
        allocator,
        .{ .begin = beginAsyncSpinner, .end = endAsyncSpinner },
        on_async_search_ready,
    );
}

pub fn endAsyncSpinner(ctx: *UiContext) void {
    ctx.async_inflight = GFALSE;
    if (ctx.async_spinner_id != 0) {
        _ = c.g_source_remove(ctx.async_spinner_id);
        ctx.async_spinner_id = 0;
    }
    gtk_widgets.clearAsyncRows(ctx.list);
}

fn beginAsyncSpinner(ctx: *UiContext) void {
    ctx.async_inflight = GTRUE;
    if (ctx.async_spinner_id != 0) {
        _ = c.g_source_remove(ctx.async_spinner_id);
        ctx.async_spinner_id = 0;
    }
    ctx.async_spinner_phase = 0;
    updateAsyncSpinnerFrame(ctx);
    ctx.async_spinner_id = c.g_timeout_add(120, onAsyncSpinnerTick, ctx);
}

fn onAsyncSpinnerTick(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.async_inflight == GFALSE) {
        ctx.async_spinner_id = 0;
        return GFALSE;
    }
    updateAsyncSpinnerFrame(ctx);
    return GTRUE;
}

fn updateAsyncSpinnerFrame(ctx: *UiContext) void {
    const frames = [_][]const u8{ "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⠋", "⠙" };
    const frame = frames[ctx.async_spinner_phase % frames.len];
    ctx.async_spinner_phase +%= 1;

    var status_buf: [40]u8 = undefined;
    const status_msg = std.fmt.bufPrint(&status_buf, "{s} Searching...", .{frame}) catch "Searching...";
    gtk_widgets.clearAsyncRows(ctx.list);
    gtk_widgets.appendAsyncRow(ctx.list, frame, "Searching modules...");
    if (ctx.pending_power_confirm == GFALSE) gtk_status.setStatus(ctx, status_msg);
}
