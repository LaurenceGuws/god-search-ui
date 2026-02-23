const std = @import("std");
const tool_check = @import("../providers/tool_check.zig");
const wm = @import("types.zig");

pub const HyprlandBackend = struct {
    list_windows_json_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWindowsJsonWithSystemTools,
    list_workspaces_json_fn: *const fn (allocator: std.mem.Allocator) anyerror![]u8 = listWorkspacesJsonWithSystemTools,
    has_tools_fn: *const fn () bool = hasSystemTools,
    had_runtime_failure: bool = false,

    pub fn backend(self: *HyprlandBackend) wm.Backend {
        return .{
            .name = "hyprland",
            .context = self,
            .vtable = &.{
                .list_windows = listWindows,
                .list_workspaces = listWorkspaces,
                .health = health,
                .capabilities = capabilities,
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

        const snapshot = parseWorkspacesJson(allocator, parsed.value) catch |err| {
            self.had_runtime_failure = true;
            return err;
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
        };
    }
};

fn hasSystemTools() bool {
    return tool_check.commandExistsCached("hyprctl");
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
