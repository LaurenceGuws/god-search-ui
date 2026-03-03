const std = @import("std");
const dispatch = @import("dispatch.zig");
const UiKind = dispatch.kinds.UiKind;

pub const Intent = enum {
    none,
    module_filter,
    dir_menu,
    file_menu,
    run_plan,
};

pub const SelectionDecision = struct {
    record_selection: bool = false,
    intent: Intent = .none,
    plan: ?dispatch.CommandPlan = null,

    pub fn deinit(self: *SelectionDecision, allocator: std.mem.Allocator) void {
        if (self.plan) |*plan| plan.deinit(allocator);
        self.* = .{};
    }
};

pub fn resolveSelection(
    allocator: std.mem.Allocator,
    kind: []const u8,
    action: []const u8,
) !SelectionDecision {
    return resolveSelectionKind(allocator, dispatch.kinds.parse(kind), action);
}

pub fn resolveSelectionKind(
    allocator: std.mem.Allocator,
    parsed_kind: UiKind,
    action: []const u8,
) !SelectionDecision {
    var result = SelectionDecision{
        .record_selection = dispatch.shouldRecordSelectionKind(parsed_kind),
    };

    if (dispatch.isModuleKindEnum(parsed_kind)) {
        result.intent = .module_filter;
        return result;
    }
    if (dispatch.isDirMenuKindEnum(parsed_kind)) {
        result.intent = .dir_menu;
        return result;
    }
    if (dispatch.isFileMenuKindEnum(parsed_kind)) {
        result.intent = .file_menu;
        return result;
    }

    const plan = try dispatch.planCommandKind(allocator, parsed_kind, action);
    result.plan = plan;
    result.intent = .run_plan;
    return result;
}

test "action selection resolves directly to plan when executable" {
    var decision = try resolveSelectionKind(std.testing.allocator, .action, "power");
    defer decision.deinit(std.testing.allocator);

    try std.testing.expect(decision.record_selection);
    try std.testing.expectEqual(Intent.run_plan, decision.intent);
    try std.testing.expect(decision.plan != null);
}

test "module/filter actions resolve to menu intent" {
    var decision = try resolveSelectionKind(std.testing.allocator, .module, "some-module");
    defer decision.deinit(std.testing.allocator);

    try std.testing.expectEqual(Intent.module_filter, decision.intent);
    try std.testing.expect(decision.plan == null);
}
