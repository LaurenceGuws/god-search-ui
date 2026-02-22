const cache_refresh = @import("cache_refresh.zig");
const refresh_worker = @import("refresh_worker.zig");

pub fn scheduleAndShouldStartWorker(
    cache_ready: bool,
    cache_ttl_ns: u64,
    cache_last_refresh_ns: i128,
    refresh_requested: *bool,
    last_query_used_stale_cache: *bool,
    enable_async_refresh: bool,
    refresh_thread_running: bool,
) bool {
    cache_refresh.scheduleRefreshIfNeeded(
        cache_ready,
        cache_ttl_ns,
        cache_last_refresh_ns,
        refresh_requested,
        last_query_used_stale_cache,
    );
    return refresh_worker.shouldStart(enable_async_refresh, refresh_requested.*, refresh_thread_running);
}
