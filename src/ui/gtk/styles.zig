const gtk_types = @import("types.zig");
const c = gtk_types.c;

pub fn installCss(window: *c.GtkWidget) void {
    const css =
        ".gs-status { color: #8b93a8; font-size: 0.92em; }\n" ++
        ".gs-status-info { color: #80a6d8; }\n" ++
        ".gs-status-success { color: #87c97f; }\n" ++
        ".gs-status-failure { color: #e58a8a; }\n" ++
        ".gs-status-searching { color: #c6e0ff; font-size: 1.02em; font-weight: 700; }\n" ++
        ".gs-preview-panel { background: rgba(14, 18, 28, 0.75); border: 1px solid rgba(164, 192, 255, 0.18); border-radius: 10px; }\n" ++
        ".gs-preview-scroll, .gs-preview-scroll > viewport { background: transparent; border: none; box-shadow: none; }\n" ++
        ".gs-preview-inner { padding: 12px; }\n" ++
        ".gs-preview-title { color: #8fa6d8; font-weight: 700; }\n" ++
        ".gs-preview-body { color: #d5ddf1; line-height: 1.25; }\n" ++
        ".gs-preview-text-scroll, .gs-preview-text-scroll > viewport { background: rgba(7, 10, 16, 0.68); border: 1px solid rgba(164, 192, 255, 0.12); border-radius: 8px; box-shadow: none; }\n" ++
        ".gs-preview-text-scroll scrollbar slider { min-width: 4px; min-height: 20px; }\n" ++
        ".gs-preview-text { background: transparent; color: #dce6ff; padding: 8px; font-family: monospace; font-size: 12px; }\n" ++
        ".gs-preview-text text { background: transparent; color: #dce6ff; }\n" ++
        ".gs-header { color: #8b93a8; }\n" ++
        ".gs-info { color: #9aa1b5; }\n" ++
        ".gs-async-search { color: #aeb8cc; }\n" ++
        ".gs-legend { color: #7c8498; font-size: 0.88em; }\n" ++
        ".gs-separator { margin-top: 4px; margin-bottom: 4px; opacity: 0.3; }\n" ++
        ".gs-results-scroll, .gs-results-scroll > viewport { background: transparent; border: none; box-shadow: none; }\n" ++
        ".gs-results-scroll junction { background: transparent; border: none; box-shadow: none; }\n" ++
        ".gs-results-scroll undershoot { background-image: none; background: transparent; }\n" ++
        ".gs-results-scroll scrollbar { min-width: 4px; border: none; box-shadow: none; background: transparent; margin: 0; padding: 0; }\n" ++
        ".gs-results-scroll scrollbar separator { min-width: 0; min-height: 0; background: transparent; }\n" ++
        ".gs-results-scroll scrollbar trough { background: transparent; border: none; box-shadow: none; border-radius: 0; margin: 0; padding: 0; }\n" ++
        ".gs-results-scroll scrollbar slider { min-width: 4px; min-height: 20px; background: rgba(140, 170, 235, 0.20); border: none; box-shadow: none; border-radius: 3px; margin: 0; }\n" ++
        ".gs-results > row { background: transparent; background-color: transparent; background-image: none; border: none; padding: 4px 8px; border-radius: 8px; }\n" ++
        ".gs-results > row:selected,\n" ++
        ".gs-results > row:selected:focus,\n" ++
        ".gs-results > row:selected:backdrop,\n" ++
        ".gs-results > row:hover,\n" ++
        ".gs-results > row:focus,\n" ++
        ".gs-results > row:active { background: transparent; background-color: transparent; background-image: none; border: none; box-shadow: none; outline: none; }\n" ++
        ".gs-results > row > box { border-radius: 8px; }\n" ++
        ".gs-results.gs-scroll-active > row > box { margin-right: 4px; }\n" ++
        ".gs-results.gs-scroll-active .gs-kind-icon { margin-left: -2px; }\n" ++
        ".gs-results > row.gs-actionable-row { transition: background-color 130ms ease, border-color 130ms ease, opacity 120ms ease; }\n" ++
        ".gs-results > row.gs-meta-row { padding-top: 2px; padding-bottom: 2px; }\n" ++
        ".gs-results > row.gs-actionable-row:hover > box,\n" ++
        ".gs-results > row.gs-actionable-row:selected > box,\n" ++
        ".gs-results > row.gs-actionable-row:selected:focus > box,\n" ++
        ".gs-results > row.gs-actionable-row:focus > box,\n" ++
        ".gs-results > row.gs-actionable-row:active > box {\n" ++
        "  background: rgba(140, 170, 235, 0.20);\n" ++
        "  border: 1px solid rgba(164, 192, 255, 0.55);\n" ++
        "  border-radius: 8px;\n" ++
        "  outline: none;\n" ++
        "  box-shadow: none;\n" ++
        "}\n" ++
        ".gs-results > row.gs-actionable-row:selected .gs-candidate-primary { color: #f5f8ff; }\n" ++
        ".gs-results > row.gs-actionable-row:selected .gs-candidate-secondary { color: #d6def1; }\n" ++
        ".gs-kind-icon { color: #a9b1c7; font-size: 2.35em; margin-left: 6px; margin-right: 8px; }\n" ++
        ".gs-candidate-primary { color: #e8ecf7; transition: color 120ms ease; }\n" ++
        ".gs-candidate-secondary { color: #9aa1b5; font-size: 0.92em; transition: color 120ms ease; }\n" ++
        ".gs-entry-layout > .gs-candidate-content { min-width: 0; }\n" ++
        ".gs-primary-row { min-height: 20px; }\n" ++
        ".gs-chip { font-size: 0.72em; font-weight: 700; letter-spacing: 0.03em; padding: 2px 8px; border-radius: 999px; }\n" ++
        ".gs-chip-module-key { min-width: 1.8em; font-size: 0.78em; }\n" ++
        ".gs-chip-app { color: #7fb0ff; background: rgba(127, 176, 255, 0.16); }\n" ++
        ".gs-chip-window { color: #78d2c7; background: rgba(120, 210, 199, 0.16); }\n" ++
        ".gs-chip-dir { color: #ddb26f; background: rgba(221, 178, 111, 0.16); }\n" ++
        ".gs-chip-file { color: #8bc3ff; background: rgba(139, 195, 255, 0.16); }\n" ++
        ".gs-chip-grep { color: #b8a6ff; background: rgba(184, 166, 255, 0.16); }\n" ++
        ".gs-chip-action { color: #f18cb6; background: rgba(241, 140, 182, 0.16); }\n" ++
        ".gs-chip-hint { color: #9aa1b5; background: rgba(154, 161, 181, 0.16); }\n" ++
        ".gs-notify-frame { background: rgba(9, 13, 20, 0.88); border: 1px solid rgba(132, 160, 228, 0.32); border-radius: 10px; }\n" ++
        ".gs-notify-list { background: transparent; }\n" ++
        ".gs-notify-row { background: rgba(30, 38, 56, 0.82); border: 1px solid rgba(132, 160, 228, 0.20); border-radius: 8px; padding: 10px; }\n" ++
        ".gs-notify-summary { color: #e8ecf7; font-weight: 700; }\n" ++
        ".gs-notify-body { color: #bec9df; }\n" ++
        ".gs-notify-close { min-width: 26px; min-height: 26px; padding: 0 8px; font-size: 0.82em; }\n";

    const provider = c.gtk_css_provider_new();
    defer c.g_object_unref(provider);
    c.gtk_css_provider_load_from_data(provider, css.ptr, @intCast(css.len));

    const display = c.gtk_widget_get_display(window);
    if (display != null) {
        c.gtk_style_context_add_provider_for_display(
            display,
            @ptrCast(provider),
            c.GTK_STYLE_PROVIDER_PRIORITY_USER,
        );
    }
}
