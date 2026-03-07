const std = @import("std");
const tool_check = @import("../providers/tool_check.zig");
const wm = @import("types.zig");

pub const HyprlandBackend = struct {
    const EventRuntime = struct {
        allocator: std.mem.Allocator,
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        socket_fd: std.posix.fd_t,
        thread: ?std.Thread = null,
        handler_context: *anyopaque,
        handler: wm.EventHandler,
        subscription: wm.EventSubscription,
    };

    list_windows_json_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWindowsJsonWithSystemTools,
    list_workspaces_json_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWorkspacesJsonWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,
    had_runtime_failure: bool = false,
    event_runtime: ?*EventRuntime = null,
    event_lock: std.Thread.Mutex = .{},
    next_subscription_token: usize = 1,

    pub fn backend(self: *HyprlandBackend) wm.Backend {
        return .{
            .name = "hyprland",
            .context = self,
            .vtable = &.{
                .list_windows = listWindows,
                .list_workspaces = listWorkspaces,
                .health = health,
                .capabilities = capabilities,
                .subscribe_events = subscribeEvents,
                .unsubscribe_events = unsubscribeEvents,
            },
        };
    }

    fn listWindows(context: *anyopaque, allocator: std.mem.Allocator) !wm.WindowSnapshot {
        const self: *HyprlandBackend = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return error.ToolsUnavailable;

        const json_bytes = self.list_windows_json_fn(allocator) catch |err| {
            self.had_runtime_failure = true;
            std.log.warn("hyprland wm list windows failed: {s}", .{@errorName(err)});
            return err;
        };
        defer allocator.free(json_bytes);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch |err| {
            self.had_runtime_failure = true;
            return err;
        };
        defer parsed.deinit();

        const snapshot = parseClientsJson(allocator, parsed.value) catch |err| {
            self.had_runtime_failure = true;
            return err;
        };
        self.had_runtime_failure = false;
        return snapshot;
    }

    fn health(context: *anyopaque) wm.Health {
        const self: *HyprlandBackend = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return .unavailable;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn listWorkspaces(context: *anyopaque, allocator: std.mem.Allocator) !wm.WorkspaceSnapshot {
        const self: *HyprlandBackend = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return error.ToolsUnavailable;

        const json_bytes = self.list_workspaces_json_fn(allocator) catch |err| {
            self.had_runtime_failure = true;
            std.log.warn("hyprland wm list workspaces failed: {s}", .{@errorName(err)});
            return err;
        };
        defer allocator.free(json_bytes);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch |err| {
            self.had_runtime_failure = true;
            return err;
        };
        defer parsed.deinit();

        var snapshot = parseWorkspacesJson(allocator, parsed.value) catch |err| {
            self.had_runtime_failure = true;
            return err;
        };
        errdefer snapshot.deinit(allocator);

        // Best-effort enrichment: annotate each workspace with a short list of window titles.
        const clients_json_bytes = self.list_windows_json_fn(allocator) catch |err| {
            if (err != error.OutOfMemory) {
                std.log.warn("hyprland wm workspace title preview skipped: {s}", .{@errorName(err)});
            } else {
                self.had_runtime_failure = true;
                return err;
            }
            self.had_runtime_failure = false;
            return snapshot;
        };
        defer allocator.free(clients_json_bytes);

        var clients_parsed = std.json.parseFromSlice(std.json.Value, allocator, clients_json_bytes, .{}) catch |err| {
            if (err == error.OutOfMemory) {
                self.had_runtime_failure = true;
                return err;
            }
            std.log.warn("hyprland wm workspace title preview parse skipped: {s}", .{@errorName(err)});
            self.had_runtime_failure = false;
            return snapshot;
        };
        defer clients_parsed.deinit();

        annotateWorkspaceWindowTitlePreviews(allocator, &snapshot, clients_parsed.value) catch |err| {
            if (err == error.OutOfMemory) {
                self.had_runtime_failure = true;
                return err;
            }
            std.log.warn("hyprland wm workspace title preview annotate skipped: {s}", .{@errorName(err)});
            self.had_runtime_failure = false;
            return snapshot;
        };
        self.had_runtime_failure = false;
        return snapshot;
    }

    fn capabilities(_: *anyopaque) wm.Capability {
        return .{
            .windows = true,
            .workspaces = true,
            .focus_window = true,
            .switch_workspace = true,
            .event_stream = true,
        };
    }

    fn subscribeEvents(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        handler_context: *anyopaque,
        handler: wm.EventHandler,
    ) !?wm.EventSubscription {
        const self: *HyprlandBackend = @ptrCast(@alignCast(context));
        if (!self.has_tools_fn()) return error.ToolsUnavailable;

        self.event_lock.lock();
        defer self.event_lock.unlock();
        if (self.event_runtime != null) return error.AlreadySubscribed;

        const socket_path = try resolveHyprlandEventSocketPath(allocator);
        defer allocator.free(socket_path);
        const socket_fd = try connectUnixStream(socket_path);

        const runtime = try allocator.create(EventRuntime);
        errdefer allocator.destroy(runtime);
        runtime.* = .{
            .allocator = allocator,
            .socket_fd = socket_fd,
            .handler_context = handler_context,
            .handler = handler,
            .subscription = .{ .token = self.next_subscription_token },
        };
        errdefer std.posix.close(runtime.socket_fd);
        self.next_subscription_token += 1;

        runtime.thread = try std.Thread.spawn(.{}, eventLoopThread, .{runtime});
        self.event_runtime = runtime;
        return runtime.subscription;
    }

    fn unsubscribeEvents(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        subscription: wm.EventSubscription,
    ) void {
        _ = allocator;
        const self: *HyprlandBackend = @ptrCast(@alignCast(context));

        self.event_lock.lock();
        const runtime = self.event_runtime orelse {
            self.event_lock.unlock();
            return;
        };
        if (runtime.subscription.token != subscription.token) {
            self.event_lock.unlock();
            return;
        }
        self.event_runtime = null;
        self.event_lock.unlock();

        runtime.stop.store(true, .release);
        std.posix.close(runtime.socket_fd);
        if (runtime.thread) |thread| thread.join();
        runtime.allocator.destroy(runtime);
    }
};

fn eventLoopThread(runtime: *HyprlandBackend.EventRuntime) void {
    var buffer: [4096]u8 = undefined;
    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(runtime.allocator);

    while (!runtime.stop.load(.acquire)) {
        const read_len = std.posix.read(runtime.socket_fd, &buffer) catch break;
        if (read_len == 0) break;

        line_buf.appendSlice(runtime.allocator, buffer[0..read_len]) catch break;
        while (std.mem.indexOfScalar(u8, line_buf.items, '\n')) |idx| {
            const line = line_buf.items[0..idx];
            if (parseEventKind(line)) |kind| {
                runtime.handler(runtime.handler_context, .{ .kind = kind });
            }
            const next_start = idx + 1;
            if (next_start >= line_buf.items.len) {
                line_buf.clearRetainingCapacity();
                break;
            }
            _ = line_buf.replaceRange(runtime.allocator, 0, next_start, &.{}) catch {
                line_buf.clearRetainingCapacity();
                break;
            };
        }
    }
}

fn parseEventKind(line: []const u8) ?wm.EventKind {
    const prefix_end = std.mem.indexOf(u8, line, ">>") orelse return null;
    const name = line[0..prefix_end];

    if (std.mem.eql(u8, name, "workspace") or
        std.mem.eql(u8, name, "workspacev2"))
        return .workspace_switched;

    if (std.mem.eql(u8, name, "createworkspace") or
        std.mem.eql(u8, name, "createworkspacev2") or
        std.mem.eql(u8, name, "destroyworkspace") or
        std.mem.eql(u8, name, "destroyworkspacev2") or
        std.mem.eql(u8, name, "moveworkspace") or
        std.mem.eql(u8, name, "moveworkspacev2") or
        std.mem.eql(u8, name, "renameworkspace") or
        std.mem.eql(u8, name, "activespecial") or
        std.mem.eql(u8, name, "focusedmon"))
        return .workspaces_changed;

    if (std.mem.eql(u8, name, "activewindow") or
        std.mem.eql(u8, name, "activewindowv2"))
        return .focus_window_changed;

    if (std.mem.eql(u8, name, "openwindow") or
        std.mem.eql(u8, name, "closewindow") or
        std.mem.eql(u8, name, "movewindow") or
        std.mem.eql(u8, name, "windowtitle") or
        std.mem.eql(u8, name, "fullscreen") or
        std.mem.eql(u8, name, "changefloatingmode") or
        std.mem.eql(u8, name, "pin"))
        return .windows_changed;

    return null;
}

fn resolveHyprlandEventSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const sig = try std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE");
    defer allocator.free(sig);
    const runtime_dir = std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR") catch
        try std.fmt.allocPrint(allocator, "/run/user/{d}", .{std.posix.getuid()});
    defer allocator.free(runtime_dir);

    return std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket2.sock", .{ runtime_dir, sig });
}

fn connectUnixStream(path: []const u8) !std.posix.fd_t {
    const address = try std.net.Address.initUnix(path);
    const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0);
    errdefer std.posix.close(fd);
    try std.posix.connect(fd, &address.any, address.getOsSockLen());
    return fd;
}

fn hasSystemTools() bool {
    return tool_check.commandExists("hyprctl");
}

fn listWindowsJsonWithSystemTools(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "hyprctl", "clients", "-j" },
        .max_output_bytes = 8 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.WindowQueryFailed;
    }
    return result.stdout;
}

fn listWorkspacesJsonWithSystemTools(allocator: std.mem.Allocator) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "hyprctl", "workspaces", "-j" },
        .max_output_bytes = 4 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.WorkspaceQueryFailed;
    }
    return result.stdout;
}

fn parseClientsJson(allocator: std.mem.Allocator, root: std.json.Value) !wm.WindowSnapshot {
    if (root != .array) return error.InvalidJson;

    var out = std.ArrayList(wm.WindowInfo).empty;
    defer out.deinit(allocator);

    for (root.array.items) |client| {
        const parsed = parseClientObject(client) orelse continue;
        if (!parsed.mapped) continue;
        if (parsed.workspace_id < 0) continue;
        if (parsed.address.len == 0) continue;

        const title_fallback = if (parsed.title.len > 0) parsed.title else parsed.class_name;
        const title = if (title_fallback.len > 0) title_fallback else "Window";
        const class_name = if (parsed.class_name.len > 0) parsed.class_name else "Window";

        try out.append(allocator, .{
            .title = try allocator.dupe(u8, title),
            .class_name = try allocator.dupe(u8, class_name),
            .id = try allocator.dupe(u8, parsed.address),
        });
    }

    return .{ .items = try out.toOwnedSlice(allocator) };
}

fn parseWorkspacesJson(allocator: std.mem.Allocator, root: std.json.Value) !wm.WorkspaceSnapshot {
    if (root != .array) return error.InvalidJson;

    var out = std.ArrayList(wm.WorkspaceInfo).empty;
    defer out.deinit(allocator);

    for (root.array.items) |workspace| {
        const parsed = parseWorkspaceObject(workspace) orelse continue;
        if (parsed.id <= 0) continue;

        const name = if (parsed.name.len > 0) parsed.name else "Workspace";
        try out.append(allocator, .{
            .id = parsed.id,
            .name = try allocator.dupe(u8, name),
            .monitor_name = try allocator.dupe(u8, parsed.monitor_name),
            .window_count = parsed.window_count,
        });
    }

    std.mem.sort(wm.WorkspaceInfo, out.items, {}, lessWorkspaceById);
    return .{ .items = try out.toOwnedSlice(allocator) };
}

fn annotateWorkspaceWindowTitlePreviews(
    allocator: std.mem.Allocator,
    snapshot: *wm.WorkspaceSnapshot,
    clients_root: std.json.Value,
) !void {
    if (clients_root != .array) return error.InvalidJson;

    for (snapshot.items) |*workspace| {
        if (workspace.window_titles_preview != null) continue;
        const preview = try buildWorkspaceWindowTitlePreview(allocator, workspace.id, clients_root.array.items);
        if (preview) |owned| workspace.window_titles_preview = owned;
    }
}

fn buildWorkspaceWindowTitlePreview(
    allocator: std.mem.Allocator,
    workspace_id: i32,
    clients: []const std.json.Value,
) !?[]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var shown: usize = 0;
    var total: usize = 0;

    for (clients) |client| {
        const parsed = parseClientObject(client) orelse continue;
        if (!parsed.mapped) continue;
        if (parsed.workspace_id != workspace_id) continue;

        const title_fallback = if (parsed.title.len > 0) parsed.title else parsed.class_name;
        const title = if (title_fallback.len > 0) title_fallback else "Window";
        total += 1;

        if (shown < 3) {
            if (shown > 0) try out.appendSlice(allocator, ", ");
            try out.appendSlice(allocator, title);
            shown += 1;
        }
    }

    if (total == 0) return null;
    if (total > shown) try std.fmt.format(out.writer(allocator), " (+{d})", .{total - shown});
    const owned = try out.toOwnedSlice(allocator);
    return owned;
}

fn lessWorkspaceById(_: void, a: wm.WorkspaceInfo, b: wm.WorkspaceInfo) bool {
    if (a.id != b.id) return a.id < b.id;
    return std.mem.order(u8, a.name, b.name) == .lt;
}

const ParsedClient = struct {
    mapped: bool,
    workspace_id: i64,
    title: []const u8,
    class_name: []const u8,
    address: []const u8,
};

fn parseClientObject(value: std.json.Value) ?ParsedClient {
    if (value != .object) return null;
    const obj = value.object;

    const mapped = switch (obj.get("mapped") orelse return null) {
        .bool => |b| b,
        else => false,
    };

    const workspace_id: i64 = blk: {
        const ws = obj.get("workspace") orelse break :blk -1;
        if (ws != .object) break :blk -1;
        const id_val = ws.object.get("id") orelse break :blk -1;
        break :blk switch (id_val) {
            .integer => |v| v,
            else => -1,
        };
    };

    const title = if (obj.get("title")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";
    const class_name = if (obj.get("class")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";
    const address = if (obj.get("address")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";

    return .{
        .mapped = mapped,
        .workspace_id = workspace_id,
        .title = title,
        .class_name = class_name,
        .address = address,
    };
}

const ParsedWorkspace = struct {
    id: i32,
    name: []const u8,
    monitor_name: []const u8,
    window_count: u32,
};

fn parseWorkspaceObject(value: std.json.Value) ?ParsedWorkspace {
    if (value != .object) return null;
    const obj = value.object;

    const id: i32 = blk: {
        const id_val = obj.get("id") orelse break :blk -1;
        break :blk switch (id_val) {
            .integer => |v| std.math.cast(i32, v) orelse -1,
            else => -1,
        };
    };

    const name = if (obj.get("name")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";

    const monitor_name = if (obj.get("monitor")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";

    const window_count: u32 = blk: {
        const count_val = obj.get("windows") orelse break :blk 0;
        break :blk switch (count_val) {
            .integer => |v| std.math.cast(u32, if (v < 0) 0 else v) orelse 0,
            else => 0,
        };
    };

    return .{
        .id = id,
        .name = name,
        .monitor_name = monitor_name,
        .window_count = window_count,
    };
}

test "parseClientsJson filters unmapped and invalid workspace clients" {
    const json =
        \\[
        \\  {"mapped":true,"workspace":{"id":1},"title":"Term","class":"kitty","address":"0xabc"},
        \\  {"mapped":false,"workspace":{"id":1},"title":"Ignore","class":"x","address":"0xdef"},
        \\  {"mapped":true,"workspace":{"id":-1},"title":"Ignore2","class":"x","address":"0x123"}
        \\]
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    var snapshot = try parseClientsJson(std.testing.allocator, parsed.value);
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), snapshot.items.len);
    try std.testing.expectEqualStrings("Term", snapshot.items[0].title);
    try std.testing.expectEqualStrings("kitty", snapshot.items[0].class_name);
    try std.testing.expectEqualStrings("0xabc", snapshot.items[0].id);
}

test "parseClientsJson falls back title and class labels" {
    const json =
        \\[
        \\  {"mapped":true,"workspace":{"id":2},"title":"","class":"","address":"0xabc"}
        \\]
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    var snapshot = try parseClientsJson(std.testing.allocator, parsed.value);
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), snapshot.items.len);
    try std.testing.expectEqualStrings("Window", snapshot.items[0].title);
    try std.testing.expectEqualStrings("Window", snapshot.items[0].class_name);
}

test "parseWorkspacesJson filters invalid ids and sorts by id" {
    const json =
        \\[
        \\  {"id":3,"name":"3","monitor":"HDMI-A-1","windows":1},
        \\  {"id":-99,"name":"special:scratch","monitor":"HDMI-A-1","windows":2},
        \\  {"id":1,"name":"dev","monitor":"eDP-1","windows":4}
        \\]
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    var snapshot = try parseWorkspacesJson(std.testing.allocator, parsed.value);
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), snapshot.items.len);
    try std.testing.expectEqual(@as(i32, 1), snapshot.items[0].id);
    try std.testing.expectEqualStrings("dev", snapshot.items[0].name);
    try std.testing.expectEqualStrings("eDP-1", snapshot.items[0].monitor_name);
    try std.testing.expectEqual(@as(u32, 4), snapshot.items[0].window_count);
    try std.testing.expectEqual(@as(i32, 3), snapshot.items[1].id);
}

test "parseWorkspacesJson applies default name" {
    const json =
        \\[
        \\  {"id":2,"name":"","monitor":"eDP-1","windows":0}
        \\]
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    var snapshot = try parseWorkspacesJson(std.testing.allocator, parsed.value);
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), snapshot.items.len);
    try std.testing.expectEqualStrings("Workspace", snapshot.items[0].name);
}

test "annotateWorkspaceWindowTitlePreviews groups client titles by workspace" {
    const workspaces_json =
        \\[
        \\  {"id":1,"name":"dev","monitor":"eDP-1","windows":4},
        \\  {"id":2,"name":"www","monitor":"HDMI-A-1","windows":1}
        \\]
    ;
    const clients_json =
        \\[
        \\  {"mapped":true,"workspace":{"id":1},"title":"Terminal","class":"kitty","address":"0x1"},
        \\  {"mapped":true,"workspace":{"id":1},"title":"Editor","class":"code","address":"0x2"},
        \\  {"mapped":true,"workspace":{"id":1},"title":"Docs","class":"zen","address":"0x3"},
        \\  {"mapped":true,"workspace":{"id":1},"title":"Music","class":"spotify","address":"0x4"},
        \\  {"mapped":true,"workspace":{"id":2},"title":"Browser","class":"zen","address":"0x5"}
        \\]
    ;
    var ws_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, workspaces_json, .{});
    defer ws_parsed.deinit();
    var clients_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, clients_json, .{});
    defer clients_parsed.deinit();

    var snapshot = try parseWorkspacesJson(std.testing.allocator, ws_parsed.value);
    defer snapshot.deinit(std.testing.allocator);
    try annotateWorkspaceWindowTitlePreviews(std.testing.allocator, &snapshot, clients_parsed.value);

    try std.testing.expectEqualStrings("Terminal, Editor, Docs (+1)", snapshot.items[0].window_titles_preview.?);
    try std.testing.expectEqualStrings("Browser", snapshot.items[1].window_titles_preview.?);
}

test "parseEventKind maps hyprland socket2 events to wm event kinds" {
    try std.testing.expectEqual(wm.EventKind.workspace_switched, parseEventKind("workspace>>2").?);
    try std.testing.expectEqual(wm.EventKind.workspaces_changed, parseEventKind("createworkspacev2>>3").?);
    try std.testing.expectEqual(wm.EventKind.focus_window_changed, parseEventKind("activewindowv2>>0xabc").?);
    try std.testing.expectEqual(wm.EventKind.windows_changed, parseEventKind("openwindow>>0xabc,2,kitty,Terminal").?);
    try std.testing.expect(parseEventKind("submap>>resize") == null);
}
