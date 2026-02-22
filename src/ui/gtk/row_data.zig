const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");

const c = gtk_types.c;
const UiKind = common_dispatch.kinds.UiKind;

pub fn setActionableData(
    row: *c.GtkListBoxRow,
    allocator: std.mem.Allocator,
    row_kind: UiKind,
    action_text: []const u8,
    title_text: []const u8,
) void {
    const action_z = allocator.dupeZ(u8, action_text) catch return;
    defer allocator.free(action_z);
    const title_z = allocator.dupeZ(u8, title_text) catch return;
    defer allocator.free(title_z);

    c.g_object_set_data(@ptrCast(row), "gs-kind-id", @ptrFromInt(@intFromEnum(row_kind) + 1));
    c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
    c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
}

pub fn kind(row: *c.GtkListBoxRow) UiKind {
    const kind_id_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind-id");
    if (kind_id_ptr != null) {
        const raw = @as(usize, @intFromPtr(kind_id_ptr));
        if (raw > 0) {
            const idx = raw - 1;
            if (idx <= @intFromEnum(UiKind.file_option)) {
                return @enumFromInt(idx);
            }
        }
    }
    return .unknown;
}

pub fn action(row: *c.GtkListBoxRow) ?[]const u8 {
    const ptr = c.g_object_get_data(@ptrCast(row), "gs-action") orelse return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

pub fn title(row: *c.GtkListBoxRow) ?[]const u8 {
    const ptr = c.g_object_get_data(@ptrCast(row), "gs-title") orelse return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

test "row data roundtrip stores and reads kind action and title" {
    const row_widget = c.gtk_list_box_row_new();
    defer c.g_object_unref(row_widget);
    const row: *c.GtkListBoxRow = @ptrCast(@alignCast(row_widget));

    setActionableData(row, std.testing.allocator, .file_option, "nvim /tmp/file", "Open in Editor");

    try std.testing.expectEqual(UiKind.file_option, kind(row));
    try std.testing.expectEqualStrings("nvim /tmp/file", action(row).?);
    try std.testing.expectEqualStrings("Open in Editor", title(row).?);
}

test "row data defaults remain empty before actionable data is set" {
    const row_widget = c.gtk_list_box_row_new();
    defer c.g_object_unref(row_widget);
    const row: *c.GtkListBoxRow = @ptrCast(@alignCast(row_widget));

    try std.testing.expectEqual(UiKind.unknown, kind(row));
    try std.testing.expect(action(row) == null);
    try std.testing.expect(title(row) == null);
}
