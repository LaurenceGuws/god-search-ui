const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_async = @import("async_state.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiContext = gtk_types.UiContext;
const AsyncSearchResult = gtk_async.AsyncSearchResult;
const AsyncRenderedRow = gtk_async.AsyncRenderedRow;
const max_async_rows: usize = 20;

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
        .allocator = allocator,
        .generation = generation,
        .ready_source_id = 0,
        .total_len = 0,
        .query = query_owned,
        .rows = &.{},
        .search_error = null,
        .on_ready = on_ready,
    };
    const worker = std.Thread.spawn(.{}, asyncRouteSearchWorker, .{payload}) catch {
        finishWorkerTracking(ctx);
        gtk_async.freeAsyncSearchResult(payload);
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
        gtk_async.freeAsyncSearchResult(payload);
        return;
    }

    const ranked = ctx.service.searchQuery(allocator, payload.query) catch |err| {
        markPayloadSearchFailure(payload, err);
        dispatchOrFreePayload(ctx, payload);
        return;
    };
    defer allocator.free(ranked);

    payload.search_error = null;
    payload.total_len = ranked.len;
    const limit = @min(ranked.len, max_async_rows);
    payload.rows = allocator.alloc(AsyncRenderedRow, limit) catch {
        markPayloadSearchFailure(payload, error.OutOfMemory);
        dispatchOrFreePayload(ctx, payload);
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

    dispatchOrFreePayload(ctx, payload);
}

fn markPayloadSearchFailure(payload: *AsyncSearchResult, err: anyerror) void {
    payload.search_error = err;
    payload.total_len = 0;
    payload.rows = &.{};
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

fn dispatchOrFreePayload(ctx: *UiContext, payload: *AsyncSearchResult) void {
    if (isAsyncShuttingDown(ctx)) {
        gtk_async.freeAsyncSearchResult(payload);
        return;
    }
    const source_id = c.g_idle_add_full(
        c.G_PRIORITY_DEFAULT_IDLE,
        payload.on_ready,
        payload,
        @ptrCast(&onAsyncPayloadDestroy),
    );
    if (source_id == 0) {
        gtk_async.freeAsyncSearchResult(payload);
    } else {
        payload.ready_source_id = source_id;
        setAsyncReadySourceId(ctx, source_id);
    }
}

fn onAsyncPayloadDestroy(user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null) return;
    const payload: *AsyncSearchResult = @ptrCast(@alignCast(user_data.?));
    gtk_async.freeAsyncSearchResult(payload);
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

pub fn setAsyncReadySourceId(ctx: *UiContext, source_id: c.guint) void {
    c.g_mutex_lock(&ctx.async_worker_lock);
    ctx.async_ready_id = source_id;
    c.g_mutex_unlock(&ctx.async_worker_lock);
}

pub fn takeAsyncReadySourceId(ctx: *UiContext) c.guint {
    c.g_mutex_lock(&ctx.async_worker_lock);
    const source_id = ctx.async_ready_id;
    ctx.async_ready_id = 0;
    c.g_mutex_unlock(&ctx.async_worker_lock);
    return source_id;
}

pub fn clearAsyncReadySourceIdIf(ctx: *UiContext, source_id: c.guint) void {
    c.g_mutex_lock(&ctx.async_worker_lock);
    if (ctx.async_ready_id == source_id) {
        ctx.async_ready_id = 0;
    }
    c.g_mutex_unlock(&ctx.async_worker_lock);
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

test "mark payload search failure stores error and clears rows" {
    var ctx = std.mem.zeroes(UiContext);
    var rows = [_]AsyncRenderedRow{};
    var payload = AsyncSearchResult{
        .ctx = &ctx,
        .generation = 1,
        .ready_source_id = 0,
        .total_len = 7,
        .query = &.{},
        .rows = rows[0..],
        .search_error = null,
        .on_ready = testNoopIdle,
    };

    markPayloadSearchFailure(&payload, error.OutOfMemory);

    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), payload.search_error);
    try std.testing.expectEqual(@as(usize, 0), payload.total_len);
    try std.testing.expectEqual(@as(usize, 0), payload.rows.len);
}

fn testNoopIdle(_: ?*anyopaque) callconv(.c) c.gboolean {
    return GFALSE;
}

test "startAsyncRouteSearch replaces pending query while worker is active" {
    var allocator = std.testing.allocator;
    var ctx = std.mem.zeroes(UiContext);
    initTestAsyncCtx(&ctx, &allocator);
    defer deinitTestAsyncCtx(&ctx);

    ctx.async_worker_active = GTRUE;
    const spinner = testSpinnerCounterCallbacks();

    startAsyncRouteSearch(&ctx, allocator, "first", spinner, testNoopIdle);
    startAsyncRouteSearch(&ctx, allocator, "second", spinner, testNoopIdle);

    try std.testing.expectEqual(@as(u64, 2), ctx.async_search_generation);
    try std.testing.expectEqual(@as(u8, 2), ctx.async_spinner_phase);
    try std.testing.expectEqual(@as(c.guint, 0), ctx.async_spinner_id);
    try expectPendingQuery(&ctx, "second");
}

test "cancelAsyncRouteSearch clears pending query and ends spinner" {
    var allocator = std.testing.allocator;
    var ctx = std.mem.zeroes(UiContext);
    initTestAsyncCtx(&ctx, &allocator);
    defer deinitTestAsyncCtx(&ctx);
    const spinner = testSpinnerCounterCallbacks();

    const pending = try allocator.dupe(u8, "queued");
    gtk_async.queuePendingAsyncQuery(&ctx, allocator, pending);
    ctx.async_search_generation = 41;

    cancelAsyncRouteSearch(&ctx, spinner);

    try std.testing.expectEqual(@as(u64, 42), ctx.async_search_generation);
    try std.testing.expectEqual(@as(u8, 0), ctx.async_spinner_phase);
    try std.testing.expectEqual(@as(c.guint, 1), ctx.async_spinner_id);
    try std.testing.expectEqual(@as(?[*]u8, null), ctx.async_pending_query_ptr);
    try std.testing.expectEqual(@as(usize, 0), ctx.async_pending_query_len);
}

test "launchPendingAsyncQuery clears pending and ends spinner when spawn fails" {
    var backing_allocator = std.testing.allocator;
    var failing_state = std.testing.FailingAllocator.init(backing_allocator, .{
        .fail_index = 1,
    });
    const failing_allocator = failing_state.allocator();

    var ctx = std.mem.zeroes(UiContext);
    initTestAsyncCtx(&ctx, &backing_allocator);
    defer deinitTestAsyncCtx(&ctx);
    const spinner = testSpinnerCounterCallbacks();

    const pending = try failing_allocator.dupe(u8, "queued");
    gtk_async.queuePendingAsyncQuery(&ctx, failing_allocator, pending);
    ctx.async_search_generation = 9;

    try std.testing.expect(!launchPendingAsyncQuery(&ctx, failing_allocator, spinner, testNoopIdle));

    try std.testing.expect(failing_state.has_induced_failure);
    try std.testing.expectEqual(@as(c.gboolean, GFALSE), ctx.async_worker_active);
    try std.testing.expectEqual(@as(c.guint, 0), getAsyncWorkerCount(&ctx));
    try std.testing.expectEqual(@as(u8, 0), ctx.async_spinner_phase);
    try std.testing.expectEqual(@as(c.guint, 1), ctx.async_spinner_id);
    try std.testing.expectEqual(@as(?[*]u8, null), ctx.async_pending_query_ptr);
    try std.testing.expectEqual(@as(usize, 0), ctx.async_pending_query_len);
    try std.testing.expectEqual(@as(u64, 9), ctx.async_search_generation);
}

test "async ready source id helpers synchronize writes and conditional clears" {
    var ctx = std.mem.zeroes(UiContext);
    c.g_mutex_init(&ctx.async_worker_lock);
    defer c.g_mutex_clear(&ctx.async_worker_lock);

    try std.testing.expectEqual(@as(c.guint, 0), takeAsyncReadySourceId(&ctx));

    setAsyncReadySourceId(&ctx, 44);
    clearAsyncReadySourceIdIf(&ctx, 12);
    try std.testing.expectEqual(@as(c.guint, 44), takeAsyncReadySourceId(&ctx));

    setAsyncReadySourceId(&ctx, 77);
    clearAsyncReadySourceIdIf(&ctx, 77);
    try std.testing.expectEqual(@as(c.guint, 0), takeAsyncReadySourceId(&ctx));
}

fn initTestAsyncCtx(ctx: *UiContext, allocator: *std.mem.Allocator) void {
    ctx.* = std.mem.zeroes(UiContext);
    ctx.allocator = @ptrCast(allocator);
    c.g_mutex_init(&ctx.async_worker_lock);
    c.g_cond_init(&ctx.async_worker_cond);
}

fn deinitTestAsyncCtx(ctx: *UiContext) void {
    gtk_async.freePendingAsyncQuery(ctx);
    c.g_mutex_clear(&ctx.async_worker_lock);
    c.g_cond_clear(&ctx.async_worker_cond);
}

fn testSpinnerCounterCallbacks() SpinnerCallbacks {
    return .{
        .begin = testCountSpinnerBegin,
        .end = testCountSpinnerEnd,
    };
}

fn testCountSpinnerBegin(ctx: *UiContext) void {
    ctx.async_spinner_phase +%= 1;
}

fn testCountSpinnerEnd(ctx: *UiContext) void {
    ctx.async_spinner_id += 1;
}

fn expectPendingQuery(ctx: *UiContext, expected: []const u8) !void {
    const ptr = ctx.async_pending_query_ptr orelse {
        return std.testing.expect(false);
    };
    try std.testing.expectEqual(expected.len, ctx.async_pending_query_len);
    try std.testing.expectEqualStrings(expected, ptr[0..ctx.async_pending_query_len]);
}

fn getAsyncWorkerCount(ctx: *UiContext) c.guint {
    c.g_mutex_lock(&ctx.async_worker_lock);
    defer c.g_mutex_unlock(&ctx.async_worker_lock);
    return ctx.async_worker_count;
}
