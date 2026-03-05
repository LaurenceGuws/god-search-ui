const config = @import("mod.zig");

var package_manager: config.PackageManager = .yay;
var terminal_tool: config.TerminalTool = .kitty;
var grep_include_hidden: bool = false;
var clipboard_tool: config.ClipboardTool = .wl_copy;
var editor_tool: config.EditorTool = .xdg_open;

pub fn apply(settings: config.Settings) void {
    package_manager = settings.tools.package_manager;
    terminal_tool = settings.tools.terminal;
    grep_include_hidden = settings.tools.grep_include_hidden;
    clipboard_tool = settings.tools.clipboard_tool;
    editor_tool = settings.tools.editor_tool;
}

pub fn packageManager() config.PackageManager {
    return package_manager;
}

pub fn terminalTool() config.TerminalTool {
    return terminal_tool;
}

pub fn grepIncludeHidden() bool {
    return grep_include_hidden;
}

pub fn clipboardTool() config.ClipboardTool {
    return clipboard_tool;
}

pub fn editorTool() config.EditorTool {
    return editor_tool;
}
