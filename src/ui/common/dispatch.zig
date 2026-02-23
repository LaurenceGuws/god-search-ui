const std = @import("std");
const providers_mod = @import("../../providers/mod.zig");
const search = @import("../../search/mod.zig");
pub const kinds = @import("kinds.zig");

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
    return shouldRecordSelectionKind(kinds.parse(kind));
}

pub fn shouldRecordSelectionKind(kind: kinds.UiKind) bool {
    return switch (kind) {
        .dir_option, .file_option, .module => false,
        else => true,
    };
}

pub fn shouldRecordCandidate(kind: search.CandidateKind) bool {
    return switch (kind) {
        .dir, .file, .grep, .hint => false,
        else => true,
    };
}

pub fn requiresConfirmation(kind: []const u8, action: []const u8) bool {
    return requiresConfirmationKind(kinds.parse(kind), action);
}

pub fn requiresConfirmationKind(kind: kinds.UiKind, action: []const u8) bool {
    return kind == .action and providers_mod.requiresConfirmation(action);
}

pub fn isDirMenuKind(kind: []const u8) bool {
    return isDirMenuKindEnum(kinds.parse(kind));
}

pub fn isDirMenuKindEnum(kind: kinds.UiKind) bool {
    return kind == .dir;
}

pub fn isFileMenuKind(kind: []const u8) bool {
    return isFileMenuKindEnum(kinds.parse(kind));
}

pub fn isFileMenuKindEnum(kind: kinds.UiKind) bool {
    return kind == .file or kind == .grep;
}

pub fn isModuleKind(kind: []const u8) bool {
    return isModuleKindEnum(kinds.parse(kind));
}

pub fn isModuleKindEnum(kind: kinds.UiKind) bool {
    return kind == .module;
}

pub fn planCommand(allocator: std.mem.Allocator, kind: []const u8, action: []const u8) !CommandPlan {
    return planCommandKind(allocator, kinds.parse(kind), action);
}

pub fn planCommandKind(allocator: std.mem.Allocator, kind: kinds.UiKind, action: []const u8) !CommandPlan {
    switch (kind) {
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
            const target = try std.fmt.allocPrint(allocator, "address:{s}", .{action});
            defer allocator.free(target);
            const target_q = try shellSingleQuote(allocator, target);
            defer allocator.free(target_q);
            const cmd = try std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow {s}", .{target_q});
            return .{
                .command = cmd,
                .owned_command = cmd,
                .telemetry_kind = "window",
                .telemetry_ok_detail = cmd,
                .error_message = "Window focus failed",
                .close_on_success = true,
            };
        },
        .web => {
            const term = std.mem.trim(u8, action, " \t\r\n");
            if (term.len == 0) return .{};
            const encoded = try percentEncodeQuery(allocator, term);
            defer allocator.free(encoded);
            const url = try std.fmt.allocPrint(allocator, "https://duckduckgo.com/?q={s}", .{encoded});
            defer allocator.free(url);
            const url_q = try shellSingleQuote(allocator, url);
            defer allocator.free(url_q);
            const cmd = try std.fmt.allocPrint(allocator, "xdg-open {s}", .{url_q});
            return .{
                .command = cmd,
                .owned_command = cmd,
                .telemetry_kind = "web",
                .telemetry_ok_detail = "duckduckgo",
                .error_message = "Web search failed to launch",
                .close_on_success = true,
            };
        },
        else => {},
    }
    return .{};
}

fn shellSingleQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return out.toOwnedSlice(allocator);
}

fn percentEncodeQuery(allocator: std.mem.Allocator, term: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (term) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_' or ch == '~') {
            try out.append(allocator, ch);
            continue;
        }
        const hex = [_]u8{
            '%',
            toUpperHex(ch >> 4),
            toUpperHex(ch & 0x0f),
        };
        try out.appendSlice(allocator, &hex);
    }
    return out.toOwnedSlice(allocator);
}

fn toUpperHex(nibble: u8) u8 {
    return if (nibble < 10) ('0' + nibble) else ('A' + (nibble - 10));
}

test "window focus command shell-quotes metacharacters in address" {
    var plan = try planCommandKind(std.testing.allocator, .window, "0xabc;touch /tmp/pwn $(id)");
    defer plan.deinit(std.testing.allocator);

    try std.testing.expect(plan.command != null);
    try std.testing.expectEqualStrings(
        "hyprctl dispatch focuswindow 'address:0xabc;touch /tmp/pwn $(id)'",
        plan.command.?,
    );
}

test "window focus command escapes apostrophes in address" {
    var plan = try planCommandKind(std.testing.allocator, .window, "win'42");
    defer plan.deinit(std.testing.allocator);

    try std.testing.expect(plan.command != null);
    try std.testing.expectEqualStrings(
        "hyprctl dispatch focuswindow 'address:win'\\''42'",
        plan.command.?,
    );
}

test "web command percent-encodes query and quotes url" {
    var plan = try planCommandKind(std.testing.allocator, .web, "dota 2 + mmr");
    defer plan.deinit(std.testing.allocator);

    try std.testing.expect(plan.command != null);
    try std.testing.expectEqualStrings(
        "xdg-open 'https://duckduckgo.com/?q=dota%202%20%2B%20mmr'",
        plan.command.?,
    );
    try std.testing.expectEqualStrings("web", plan.telemetry_kind);
}
