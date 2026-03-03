const std = @import("std");
const app_mod = @import("../../app/mod.zig");
const search_mod = @import("../../search/mod.zig");

pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub const CandidateKind = @import("../../search/mod.zig").CandidateKind;
pub const GTRUE: c.gboolean = 1;
pub const GFALSE: c.gboolean = 0;

pub const UiContext = extern struct {
    launch_ctx: *anyopaque,
    window: *c.GtkWidget,
    entry: *c.GtkEntry,
    status: *c.GtkLabel,
    list: *c.GtkListBox,
    scroller: *c.GtkScrolledWindow,
    preview_panel: *c.GtkWidget,
    preview_title: *c.GtkLabel,
    preview_toggle_button: *c.GtkWidget,
    preview_text_scroller: *c.GtkWidget,
    preview_text_view: *c.GtkTextView,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    resident_mode: c.gboolean,
    pending_power_confirm: c.gboolean,
    clear_query_on_close: c.gboolean,
    search_debounce_id: c.guint,
    status_reset_id: c.guint,
    last_status_hash: u64,
    last_status_tone: u8,
    last_render_hash: u64,
    last_preview_hash: u64,
    preview_enabled: c.gboolean,
    preview_dir_tree_mode: c.gboolean,
    async_search_generation: u64,
    async_spinner_id: c.guint,
    async_ready_id: c.guint,
    startup_idle_id: c.guint,
    async_spinner_phase: u8,
    async_inflight: c.gboolean,
    async_worker_active: c.gboolean,
    async_pending_query_ptr: ?[*]u8,
    async_pending_query_len: usize,
    async_shutdown: c.gboolean,
    async_worker_count: c.guint,
    launch_start_ns: i128,
    focus_ready_logged: c.gboolean,
    first_keypress_logged: c.gboolean,
    first_input_logged: c.gboolean,
    last_selected_row_index: c.gint,
    last_scroll_position: c.gdouble,
    last_query_text: ?[*]u8,
    last_query_len: usize,
    startup_key_queue_id: c.guint,
    startup_key_queue_active: c.gboolean,
    startup_key_queue_len: u8,
    startup_key_queue: [24]u32,
    async_cached_query_hash: u64,
    async_cached_total_len: usize,
    async_cached_rows_ptr: ?[*]search_mod.ScoredCandidate,
    async_cached_rows_len: usize,
    result_query_hash: u64,
    result_window_limit: u32,
    async_worker_lock: c.GMutex,
    async_worker_cond: c.GCond,
};
