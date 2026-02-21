# Troubleshooting Runbook

Use this runbook when `god-search-ui` behaves unexpectedly.

## 1) Baseline Health Checks

Run in project root:
```bash
scripts/dev.sh check
zig build
zig build run -- --ui
```

For GTK mode:
```bash
zig build -Denable_gtk=true
zig build run -Denable_gtk=true -- --ui
```

## 2) Common Failures

### A. GTK build fails (`gtk/gtk.h` not found or C import errors)

Symptoms:
- C import failure in `src/ui/gtk_shell.zig`
- missing headers/libraries

Actions:
1. Ensure GTK dev packages and `pkg-config` are installed.
2. Re-run:
   ```bash
   zig build -Denable_gtk=true
   ```
3. If still failing, verify `pkg-config --cflags --libs gtk4` works on host.

### B. Crash on search query

Symptoms:
- segfault while searching

Actions:
1. Rebuild and run under debug:
   ```bash
   zig build run -- --ui
   ```
2. Capture stack trace and last commit hash.
3. Inspect recent provider context/runtime wiring changes (`src/main.zig`).
4. Add blocker entry in `docs/BLOCKERS.md` with repro steps.

### C. Empty results unexpectedly

Symptoms:
- query returns no results though apps/windows/dirs exist

Actions:
1. Force snapshot refresh:
   - headless: `:refresh`
   - GTK: `Ctrl+R`
2. Check provider prerequisites:
   - apps cache file exists (`~/.cache/waybar/wofi-app-launcher.tsv`)
   - `hyprctl` + `jq` for windows
   - `zoxide` for dirs
3. Inspect provider health behavior in `src/providers/*`.

### D. Action execution fails

Symptoms:
- Enter does nothing or action fails silently

Actions:
1. Inspect telemetry log:
   - `~/.local/state/god-search-ui/telemetry.log`
2. Check recorded status (`ok`/`error`) and detail field.
3. Manually run failing command from telemetry detail.

### E. History/telemetry files not updating

Symptoms:
- no new lines in `history.log` or `telemetry.log`

Actions:
1. Confirm user write access to:
   - `~/.local/state/god-search-ui/`
2. Confirm process exits cleanly (history save is deferred on shutdown).
3. Re-run one query and exit with `:q`, then re-check files.

## 3) Recovery / Rollback

If launcher is unstable in GTK mode:
1. Restore shell-based keybind fallback in Hypr.
2. Keep GTK bound on a secondary key for debugging.
3. Open blocker entry with:
   - exact command
   - stack trace
   - failing commit hash

## 4) Escalation Checklist

Before escalating to code fix, capture:
- output of `scripts/dev.sh check`
- output of failing run command
- last 3 commit hashes (`git log --oneline -3`)
- whether issue reproduces in headless mode, GTK mode, or both
