const std = @import("std");

var lock: std.Thread.Mutex = .{};
var active_issue_id: u32 = 0;

pub fn show(issue: []const u8, hint: []const u8) void {
    const detail = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}\n{s}",
        .{ issue, hint },
    ) catch return;
    defer std.heap.page_allocator.free(detail);

    lock.lock();
    const replace_id = active_issue_id;
    lock.unlock();

    const maybe_id = if (replace_id != 0)
        runNotifyWithReplace("god-search-ui config issue", detail, "critical", 0, replace_id)
    else
        runNotify("god-search-ui config issue", detail, "critical", 0);

    if (maybe_id) |id| {
        lock.lock();
        active_issue_id = id;
        lock.unlock();
    }
}

pub fn clearIfActive() void {
    lock.lock();
    const id = active_issue_id;
    lock.unlock();
    if (id == 0) return;

    _ = runNotifyWithReplace(
        "god-search-ui config",
        "Config is valid. Issue cleared.",
        "low",
        1200,
        id,
    );

    lock.lock();
    active_issue_id = 0;
    lock.unlock();
}

fn runNotify(title: []const u8, body: []const u8, urgency: []const u8, timeout_ms: i32) ?u32 {
    const timeout = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{timeout_ms}) catch return null;
    defer std.heap.page_allocator.free(timeout);
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "notify-send", "-p", "-u", urgency, "-t", timeout, title, body },
    }) catch return null;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) return null;
    return parseNotifyId(result.stdout);
}

fn runNotifyWithReplace(title: []const u8, body: []const u8, urgency: []const u8, timeout_ms: i32, replace_id: u32) ?u32 {
    const timeout = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{timeout_ms}) catch return null;
    defer std.heap.page_allocator.free(timeout);
    const replace = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{replace_id}) catch return null;
    defer std.heap.page_allocator.free(replace);

    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "notify-send", "-p", "-u", urgency, "-t", timeout, "-r", replace, title, body },
    }) catch return null;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) return null;
    return parseNotifyId(result.stdout);
}

fn parseNotifyId(stdout: []const u8) ?u32 {
    const trimmed = std.mem.trim(u8, stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(u32, trimmed, 10) catch null;
}
