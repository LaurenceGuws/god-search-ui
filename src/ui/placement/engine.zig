const std = @import("std");
const wm_adapter = @import("../../wm/adapter.zig");

pub const Anchor = enum {
    center,
    top_left,
    top_center,
    top_right,
    bottom_left,
    bottom_center,
    bottom_right,
};

pub const Geometry = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const Margins = struct {
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,
    bottom: i32 = 0,
};

pub const Spec = struct {
    anchor: Anchor = .center,
    width: i32,
    height: i32,
    offset_x: i32 = 0,
    offset_y: i32 = 0,
    margins: Margins = .{},
    monitor: wm_adapter.MonitorTarget = .{},
};

pub fn resolve(
    outputs: []const wm_adapter.Output,
    focus_hint: ?wm_adapter.FocusHint,
    work_area_for_output: ?wm_adapter.WorkArea,
    spec: Spec,
) !Geometry {
    if (outputs.len == 0) return error.NoOutputs;
    const idx = wm_adapter.selectOutput(outputs, focus_hint, spec.monitor) orelse return error.NoOutputs;
    const out = outputs[idx];
    const area = work_area_for_output orelse wm_adapter.WorkArea{
        .x = out.x,
        .y = out.y,
        .width = out.width,
        .height = out.height,
    };

    const width = @max(1, @min(spec.width, area.width - spec.margins.left - spec.margins.right));
    const height = @max(1, @min(spec.height, area.height - spec.margins.top - spec.margins.bottom));

    const min_x = area.x + spec.margins.left;
    const max_x = area.x + area.width - spec.margins.right - width;
    const min_y = area.y + spec.margins.top;
    const max_y = area.y + area.height - spec.margins.bottom - height;

    var x = switch (spec.anchor) {
        .center, .top_center, .bottom_center => area.x + @divTrunc(area.width - width, 2),
        .top_left, .bottom_left => area.x + spec.margins.left,
        .top_right, .bottom_right => area.x + area.width - spec.margins.right - width,
    };
    var y = switch (spec.anchor) {
        .center => area.y + @divTrunc(area.height - height, 2),
        .top_left, .top_center, .top_right => area.y + spec.margins.top,
        .bottom_left, .bottom_center, .bottom_right => area.y + area.height - spec.margins.bottom - height,
    };

    x = std.math.clamp(x + spec.offset_x, min_x, max_x);
    y = std.math.clamp(y + spec.offset_y, min_y, max_y);

    return .{ .x = x, .y = y, .width = width, .height = height };
}

test "resolve top-right with margins" {
    const outputs = [_]wm_adapter.Output{
        .{ .name = "DP-1", .x = 0, .y = 0, .width = 1920, .height = 1080 },
    };
    const geometry = try resolve(&outputs, null, null, .{
        .anchor = .top_right,
        .width = 640,
        .height = 420,
        .margins = .{ .top = 24, .right = 24 },
    });

    try std.testing.expectEqual(@as(i32, 1920 - 24 - 640), geometry.x);
    try std.testing.expectEqual(@as(i32, 24), geometry.y);
}

test "resolve clamps custom offset inside work area" {
    const outputs = [_]wm_adapter.Output{
        .{ .name = "DP-1", .x = 0, .y = 0, .width = 1200, .height = 800 },
    };
    const geometry = try resolve(&outputs, null, null, .{
        .anchor = .top_left,
        .width = 1000,
        .height = 700,
        .offset_x = -500,
        .offset_y = -500,
        .margins = .{ .left = 32, .top = 16, .right = 32, .bottom = 16 },
    });

    try std.testing.expectEqual(@as(i32, 32), geometry.x);
    try std.testing.expectEqual(@as(i32, 16), geometry.y);
}
