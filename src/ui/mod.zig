const build_options = @import("build_options");

pub const placement = @import("placement/mod.zig");
pub const surfaces = @import("surfaces/mod.zig");
pub const Shell = if (build_options.enable_gtk)
    @import("gtk_shell.zig").Shell
else
    @import("stub_shell.zig").Shell;
