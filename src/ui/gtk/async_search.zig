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
    const payload = allocator.create(AsyncSearchResult) catch {
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
        gtk_async.freeAsyncSearchResult(allocator, payload);
        return false;
    };
    ctx.async_worker_active = GTRUE;
    worker.detach();
    return true;
}

fn asyncRouteSearchWorker(payload: *AsyncSearchResult) void {
    const ctx = payload.ctx;
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;

    const ranked = ctx.service.searchQuery(allocator, payload.query) catch {
        payload.total_len = 0;
        payload.rows = &.{};
        _ = c.g_idle_add(payload.on_ready, payload);
        return;
    };
    defer allocator.free(ranked);

    payload.total_len = ranked.len;
    const limit = @min(ranked.len, 20);
    payload.rows = allocator.alloc(AsyncRenderedRow, limit) catch {
        payload.total_len = 0;
        payload.rows = &.{};
        _ = c.g_idle_add(payload.on_ready, payload);
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

    _ = c.g_idle_add(payload.on_ready, payload);
}
