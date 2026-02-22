const std = @import("std");

pub fn shouldStart(enable_async_refresh: bool, refresh_requested: bool, refresh_thread_running: bool) bool {
    if (!enable_async_refresh) return false;
    if (!refresh_requested) return false;
    if (refresh_thread_running) return false;
    return true;
}

pub fn markRunning(refresh_thread_running: *bool) void {
    refresh_thread_running.* = true;
}

pub fn markStopped(refresh_thread_running: *bool) void {
    refresh_thread_running.* = false;
}
