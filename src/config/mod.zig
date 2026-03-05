const std = @import("std");

pub const PackageManager = enum {
    yay,
    pacman,

    pub fn command(self: PackageManager) []const u8 {
        return switch (self) {
            .yay => "yay",
            .pacman => "pacman",
        };
    }
};

pub const TerminalTool = enum {
    kitty,
    alacritty,
    footclient,
    foot,
    wezterm,
    gnome_terminal,
    konsole,
    xfce4_terminal,
    tilix,
    xterm,

    pub fn command(self: TerminalTool) []const u8 {
        return switch (self) {
            .kitty => "kitty",
            .alacritty => "alacritty",
            .footclient => "footclient",
            .foot => "foot",
            .wezterm => "wezterm",
            .gnome_terminal => "gnome-terminal",
            .konsole => "konsole",
            .xfce4_terminal => "xfce4-terminal",
            .tilix => "tilix",
            .xterm => "xterm",
        };
    }

    pub fn shellExecWithCommand(self: TerminalTool) []const u8 {
        return switch (self) {
            .kitty, .alacritty, .footclient, .foot, .wezterm, .xterm => "{term} -e sh -lc \"$install_cmd\"",
            .gnome_terminal, .konsole, .xfce4_terminal, .tilix => "{term} -- sh -lc \"$install_cmd\"",
        };
    }
};

pub const ClipboardTool = enum {
    wl_copy,
    xclip,

    pub fn command(self: ClipboardTool) []const u8 {
        return switch (self) {
            .wl_copy => "wl-copy",
            .xclip => "xclip -selection clipboard",
        };
    }
};

pub const EditorTool = enum {
    nvim,
    vim,
    vi,
    helix,
    hx,
    kak,
    nano,
    code,
    codium,
    code_insiders,
    subl,
    xdg_open,

    pub fn command(self: EditorTool) []const u8 {
        return switch (self) {
            .nvim => "nvim",
            .vim => "vim",
            .vi => "vi",
            .helix => "helix",
            .hx => "hx",
            .kak => "kak",
            .nano => "nano",
            .code => "code",
            .codium => "codium",
            .code_insiders => "code-insiders",
            .subl => "subl",
            .xdg_open => "xdg-open",
        };
    }
};

pub const Settings = struct {
    pub const UiPolicy = struct {
        show_nerd_stats: bool = true,
    };

    pub const NotificationActionsPolicy = struct {
        show_close_button: bool = true,
        show_dbus_actions: bool = true,
    };

    pub const ToolsPolicy = struct {
        package_manager: PackageManager = .yay,
        terminal: TerminalTool = .kitty,
        grep_include_hidden: bool = false,
        clipboard_tool: ClipboardTool = .wl_copy,
        editor_tool: EditorTool = .xdg_open,
    };

    surface_mode: ?@import("../ui/surfaces/mod.zig").SurfaceMode = null,
    placement_policy: @import("../ui/placement/mod.zig").RuntimePolicy = .{},
    ui: UiPolicy = .{},
    notification_actions: NotificationActionsPolicy = .{},
    tools: ToolsPolicy = .{},
    launcher_monitor_name: ?[]u8 = null,
    notifications_monitor_name: ?[]u8 = null,

    pub fn applyPlacementOverrides(self: *Settings) void {
        if (self.launcher_monitor_name) |name| {
            self.placement_policy.launcher.window.monitor = .{
                .policy = .by_name,
                .output_name = name,
            };
        }
        if (self.notifications_monitor_name) |name| {
            self.placement_policy.notifications.window.monitor = .{
                .policy = .by_name,
                .output_name = name,
            };
        }
    }

    pub fn deinit(self: *Settings, allocator: std.mem.Allocator) void {
        if (self.launcher_monitor_name) |name| allocator.free(name);
        if (self.notifications_monitor_name) |name| allocator.free(name);
        self.* = .{};
    }
};

const impl = @import("lua_config.zig");
pub const runtime_tools = @import("runtime_tools.zig");

pub fn load(allocator: std.mem.Allocator) Settings {
    return impl.load(allocator);
}
