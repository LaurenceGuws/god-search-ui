const std = @import("std");
const gtk_types = @import("types.zig");
const CandidateKind = gtk_types.CandidateKind;
const UiContext = gtk_types.UiContext;

pub const AsyncRenderedRow = struct {
    kind: CandidateKind,
    score: i32,
    title: []u8,
    subtitle: []u8,
    action: []u8,
    icon: []u8,
};

pub const AsyncSearchResult = struct {
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    generation: u64,
    total_len: usize,
    query: []u8,
    rows: []AsyncRenderedRow,
    search_error: ?anyerror,
    on_ready: *const fn (?*anyopaque) callconv(.c) gtk_types.c.gboolean,
};

pub fn queuePendingAsyncQuery(ctx: *UiContext, allocator: std.mem.Allocator, query_owned: []u8) void {
    if (ctx.async_pending_query_ptr) |ptr| {
        const prev = ptr[0..ctx.async_pending_query_len];
        allocator.free(prev);
    }
    ctx.async_pending_query_ptr = query_owned.ptr;
    ctx.async_pending_query_len = query_owned.len;
}

pub fn takePendingAsyncQuery(ctx: *UiContext) ?[]u8 {
    const ptr = ctx.async_pending_query_ptr orelse return null;
    const slice = ptr[0..ctx.async_pending_query_len];
    ctx.async_pending_query_ptr = null;
    ctx.async_pending_query_len = 0;
    return slice;
}

pub fn freePendingAsyncQuery(ctx: *UiContext) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    if (ctx.async_pending_query_ptr) |ptr| {
        allocator.free(ptr[0..ctx.async_pending_query_len]);
        ctx.async_pending_query_ptr = null;
        ctx.async_pending_query_len = 0;
    }
}

pub fn freeAsyncSearchResult(payload: *AsyncSearchResult) void {
    const allocator = payload.allocator;
    allocator.free(payload.query);
    for (payload.rows) |row| {
        if (row.title.len > 0) allocator.free(row.title);
        if (row.subtitle.len > 0) allocator.free(row.subtitle);
        if (row.action.len > 0) allocator.free(row.action);
        if (row.icon.len > 0) allocator.free(row.icon);
    }
    if (payload.rows.len > 0) allocator.free(payload.rows);
    allocator.destroy(payload);
}
