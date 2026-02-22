const std = @import("std");
const providers_mod = @import("../../providers/mod.zig");
const search = @import("../../search/mod.zig");
const kinds = @import("kinds.zig");

pub const CommandPlan = struct {
    command: ?[]const u8 = null,
    owned_command: ?[]u8 = null,
    telemetry_kind: []const u8 = "",
    telemetry_ok_detail: []const u8 = "",
    error_message: []const u8 = "",
    close_on_success: bool = false,
    unknown_action: bool = false,

    pub fn deinit(self: *CommandPlan, allocator: std.mem.Allocator) void {
        if (self.owned_command) |buf| allocator.free(buf);
        self.* = .{};
    }
};

pub fn shouldRecordSelection(kind: []const u8) bool {
    return switch (kinds.parse(kind)) {
        .dir_option, .file_option, .module => false,
        else => true,
    };
}

pub fn shouldRecordCandidate(kind: search.CandidateKind) bool {
    return switch (kind) {
        .file_option, .dir_option, .module => false,
        else => true,
    };
}

pub fn requiresConfirmation(kind: []const u8, action: []const u8) bool {
    return kinds.parse(kind) == .action and providers_mod.requiresConfirmation(action);
}

pub fn isDirMenuKind(kind: []const u8) bool {
    return kinds.parse(kind) == .dir;
}

pub fn isFileMenuKind(kind: []const u8) bool {
    const parsed = kinds.parse(kind);
    return parsed == .file or parsed == .grep;
}

pub fn isModuleKind(kind: []const u8) bool {
    return kinds.parse(kind) == .module;
}

pub fn planCommand(allocator: std.mem.Allocator, kind: []const u8, action: []const u8) !CommandPlan {
    switch (kinds.parse(kind)) {
        .action => {
            const cmd = providers_mod.resolveActionCommand(action) orelse {
                return .{
                    .telemetry_kind = "action",
                    .error_message = "Action failed: unknown action",
                    .unknown_action = true,
                };
            };
            return .{
                .command = cmd,
                .telemetry_kind = "action",
                .telemetry_ok_detail = cmd,
                .error_message = "Action failed to launch",
                .close_on_success = true,
            };
        },
        .dir_option => {
            return .{
                .command = action,
                .telemetry_kind = "dir",
                .telemetry_ok_detail = "option-command",
                .error_message = "Directory action failed",
                .close_on_success = true,
            };
        },
        .file_option => {
            return .{
                .command = action,
                .telemetry_kind = "file",
                .telemetry_ok_detail = "option-command",
                .error_message = "File action failed",
                .close_on_success = true,
            };
        },
        .app => {
            if (std.mem.eql(u8, action, "__drun__")) return .{};
            return .{
                .command = action,
                .telemetry_kind = "app",
                .telemetry_ok_detail = action,
                .error_message = "App failed to launch",
                .close_on_success = true,
            };
        },
        .window => {
            const cmd = try std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow \"address:{s}\"", .{action});
            return .{
                .command = cmd,
                .owned_command = cmd,
                .telemetry_kind = "window",
                .telemetry_ok_detail = cmd,
                .error_message = "Window focus failed",
                .close_on_success = true,
            };
        },
        else => {},
    }
    return .{};
}
