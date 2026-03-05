const config = @import("mod.zig");

var package_manager: config.PackageManager = .yay;
var terminal_tool: config.TerminalTool = .kitty;

pub fn apply(settings: config.Settings) void {
    package_manager = settings.tools.package_manager;
    terminal_tool = settings.tools.terminal;
}

pub fn packageManager() config.PackageManager {
    return package_manager;
}

pub fn terminalTool() config.TerminalTool {
    return terminal_tool;
}
