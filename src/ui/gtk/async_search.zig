const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_async = @import("async_state.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;
const AsyncSearchResult = gtk_async.AsyncSearchResult;
const AsyncRenderedRow = gtk_async.AsyncRenderedRow;

pub const SpinnerCallbacks = struct {
    begin: *const fn (*UiContext) void,
    end: *const fn (*UiContext) void,
};

pub fn startAsyncRouteSearch(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    query_trimmed: []const u8,
    spinner: SpinnerCallbacks,
    on_ready: *const fn (?*anyopaque) callconv(.c) c.gboolean,
) void {
    if (isAsyncShuttingDown(ctx)) return;
    ctx.async_search_generation += 1;
    const generation = ctx.async_search_generation;
    const query_copy = allocator.dupe(u8, query_trimmed) catch return;
    spinner.begin(ctx);

    if (ctx.async_worker_active == GTRUE) {
        gtk_async.queuePendingAsyncQuery(ctx, allocator, query_copy);
        return;
    }
    if (!spawnAsyncRouteSearchWorker(ctx, allocator, generation, query_copy, on_ready)) {
        allocator.free(query_copy);
        spinner.end(ctx);
    }
}

pub fn cancelAsyncRouteSearch(ctx: *UiContext, spinner: SpinnerCallbacks) void {
    ctx.async_search_generation += 1;
    gtk_async.freePendingAsyncQuery(ctx);
    spinner.end(ctx);
}

pub fn launchPendingAsyncQuery(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    spinner: SpinnerCallbacks,
    on_ready: *const fn (?*anyopaque) callconv(.c) c.gboolean,
) bool {
    if (isAsyncShuttingDown(ctx)) return false;
    const query_owned = gtk_async.takePendingAsyncQuery(ctx) orelse return false;
    const generation = ctx.async_search_generation;
    if (!spawnAsyncRouteSearchWorker(ctx, allocator, generation, query_owned, on_ready)) {
        allocator.free(query_owned);
        spinner.end(ctx);
        return false;
    }
    return true;
}

fn spawnAsyncRouteSearchWorker(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    generation: u64,
    query_owned: []u8,
    on_ready: *const fn (?*anyopaque) callconv(.c) c.gboolean,
) bool {
    if (!startWorkerTracking(ctx)) {
        return false;
    }
    const payload = allocator.create(AsyncSearchResult) catch {
        finishWorkerTracking(ctx);
        return false;
    };
    payload.* = .{
        .ctx = ctx,
        .generation = generation,
        .total_len = 0,
        .query = query_owned,
        .rows = &.{},
        .on_ready = on_ready,
    };
    const worker = std.Thread.spawn(.{}, asyncRouteSearchWorker, .{payload}) catch {
        finishWorkerTracking(ctx);
        gtk_async.freeAsyncSearchResult(allocator, payload);
        return false;
    };
    ctx.async_worker_active = GTRUE;
    worker.detach();
    return true;
}

fn asyncRouteSearchWorker(payload: *AsyncSearchResult) void {
    const ctx = payload.ctx;
    defer finishWorkerTracking(ctx);
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;

    if (isAsyncShuttingDown(ctx)) {
        gtk_async.freeAsyncSearchResult(allocator, payload);
        return;
    }

    const ranked = ctx.service.searchQuery(allocator, payload.query) catch {
        dispatchOrFreePayload(ctx, allocator, payload);
        return;
    };
    defer allocator.free(ranked);

    payload.total_len = ranked.len;
    const limit = @min(ranked.len, 20);
    payload.rows = allocator.alloc(AsyncRenderedRow, limit) catch {
        payload.total_len = 0;
        payload.rows = &.{};
        dispatchOrFreePayload(ctx, allocator, payload);
        return;
    };

    for (ranked[0..limit], 0..) |row, idx| {
        payload.rows[idx] = .{
            .kind = row.candidate.kind,
            .score = row.score,
            .title = allocator.dupe(u8, row.candidate.title) catch "",
            .subtitle = allocator.dupe(u8, row.candidate.subtitle) catch "",
            .action = allocator.dupe(u8, row.candidate.action) catch "",
            .icon = allocator.dupe(u8, row.candidate.icon) catch "",
        };
    }

    dispatchOrFreePayload(ctx, allocator, payload);
}

pub fn beginAsyncShutdown(ctx: *UiContext) void {
    c.g_mutex_lock(&ctx.async_worker_lock);
    ctx.async_shutdown = GTRUE;
    while (ctx.async_worker_count != 0) {
        c.g_cond_wait(&ctx.async_worker_cond, &ctx.async_worker_lock);
    }
    c.g_mutex_unlock(&ctx.async_worker_lock);
}

pub fn isAsyncShuttingDown(ctx: *UiContext) bool {
    c.g_mutex_lock(&ctx.async_worker_lock);
    const shutting_down = ctx.async_shutdown == GTRUE;
    c.g_mutex_unlock(&ctx.async_worker_lock);
    return shutting_down;
}

fn dispatchOrFreePayload(ctx: *UiContext, allocator: std.mem.Allocator, payload: *AsyncSearchResult) void {
    if (isAsyncShuttingDown(ctx)) {
        gtk_async.freeAsyncSearchResult(allocator, payload);
        return;
    }
    const source_id = c.g_idle_add(payload.on_ready, payload);
    if (source_id == 0) {
        gtk_async.freeAsyncSearchResult(allocator, payload);
    }
}

fn startWorkerTracking(ctx: *UiContext) bool {
    c.g_mutex_lock(&ctx.async_worker_lock);
    defer c.g_mutex_unlock(&ctx.async_worker_lock);
    if (ctx.async_shutdown == GTRUE) return false;
    ctx.async_worker_count += 1;
    return true;
}

fn finishWorkerTracking(ctx: *UiContext) void {
    c.g_mutex_lock(&ctx.async_worker_lock);
    if (ctx.async_worker_count > 0) {
        ctx.async_worker_count -= 1;
    }
    const no_workers_left = ctx.async_worker_count == 0;
    c.g_mutex_unlock(&ctx.async_worker_lock);
    if (no_workers_left) {
        c.g_cond_signal(&ctx.async_worker_cond);
    }
}

test "worker tracking rejects new workers during shutdown" {
    var ctx = std.mem.zeroes(UiContext);
    c.g_mutex_init(&ctx.async_worker_lock);
    defer c.g_mutex_clear(&ctx.async_worker_lock);
    c.g_cond_init(&ctx.async_worker_cond);
    defer c.g_cond_clear(&ctx.async_worker_cond);

    try std.testing.expect(startWorkerTracking(&ctx));
    finishWorkerTracking(&ctx);
    beginAsyncShutdown(&ctx);
    try std.testing.expect(!startWorkerTracking(&ctx));
}

test "worker tracking increments and decrements count" {
    var ctx = std.mem.zeroes(UiContext);
    c.g_mutex_init(&ctx.async_worker_lock);
    defer c.g_mutex_clear(&ctx.async_worker_lock);
    c.g_cond_init(&ctx.async_worker_cond);
    defer c.g_cond_clear(&ctx.async_worker_cond);

    try std.testing.expect(startWorkerTracking(&ctx));
    c.g_mutex_lock(&ctx.async_worker_lock);
    try std.testing.expectEqual(@as(c.guint, 1), ctx.async_worker_count);
    c.g_mutex_unlock(&ctx.async_worker_lock);

    finishWorkerTracking(&ctx);
    c.g_mutex_lock(&ctx.async_worker_lock);
    try std.testing.expectEqual(@as(c.guint, 0), ctx.async_worker_count);
    c.g_mutex_unlock(&ctx.async_worker_lock);
}
