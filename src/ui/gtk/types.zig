const std = @import("std");
const app_mod = @import("../../app/mod.zig");

pub const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub const CandidateKind = @import("../../search/mod.zig").CandidateKind;
pub const GTRUE: c.gboolean = 1;
pub const GFALSE: c.gboolean = 0;

pub const UiContext = extern struct {
    window: *c.GtkWidget,
    entry: *c.GtkEntry,
    status: *c.GtkLabel,
    list: *c.GtkListBox,
    scroller: *c.GtkScrolledWindow,
    preview_panel: *c.GtkWidget,
    preview_label: *c.GtkLabel,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    pending_power_confirm: c.gboolean,
    search_debounce_id: c.guint,
    status_reset_id: c.guint,
    last_status_hash: u64,
    last_status_tone: u8,
    last_render_hash: u64,
    last_preview_hash: u64,
    preview_enabled: c.gboolean,
    async_search_generation: u64,
    async_spinner_id: c.guint,
    async_ready_id: c.guint,
    async_spinner_phase: u8,
    async_inflight: c.gboolean,
    async_worker_active: c.gboolean,
    async_pending_query_ptr: ?[*]u8,
    async_pending_query_len: usize,
    async_shutdown: c.gboolean,
    async_worker_count: c.guint,
    async_worker_lock: c.GMutex,
    async_worker_cond: c.GCond,
};
