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
   - apps cache format:
     - `category<TAB>name<TAB>exec` (legacy)
     - `category<TAB>name<TAB>exec<TAB>icon` (preferred for app icons)
   - `hyprctl` + `jq` for windows
   - `zoxide` for dirs
3. Inspect provider health behavior in `src/providers/*`.

If app icons are missing but apps still launch:
1. Confirm cache has a 4th icon column for affected rows.
2. Use icon names that exist in current icon theme.
3. Rebuild cache and trigger refresh (`Ctrl+R` in GTK or `:refresh` in headless).
   - If GTK shows fallback warning in status line, run headless diagnostics next.
4. Run headless icon diagnostics:
   ```bash
   printf ':icondiag\n:q\n' | zig build run -- --ui
   ```
5. For automation/alerts, use JSON diagnostics:
   ```bash
   printf ':icondiag --json\n:q\n' | zig build run -- --ui
   ```

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

### F. Release validation preset fails (`scripts/release_validate.sh --ci`)

Symptoms:
- release validation exits non-zero
- expected completion markers are missing

Actions:
1. Run with full output:
   ```bash
   scripts/release_validate.sh --ci --require-clean
   ```
2. Confirm output includes all markers:
   - `release smoke checks passed`
   - `release docs contract checks passed`
   - `release validation passed`
3. If failure occurs in smoke stage, rerun sub-check directly:
   - `scripts/release_smoke.sh --ci`
4. If failure occurs in docs contract stage, rerun:
   - `scripts/check_release_docs_contracts.sh`
5. If CI guard times out, increase timeout temporarily:
   - `RELEASE_VALIDATE_TIMEOUT_SECS=600 scripts/check_release_validate_ci.sh`
6. If local workspace is intentionally dirty during iteration, explicitly allow it:
   - `RELEASE_VALIDATE_ALLOW_DIRTY=1 scripts/release_validate.sh --ci --require-clean`

### G. `--print-shell-health` shows offline snapshot while daemon is running

Symptoms:
- `god-search-ui --print-shell-health` prints `diagnostic snapshot (offline)` lines
- expected live `status=ready` module lines are missing

Actions:
1. Confirm daemon control socket responds:
   ```bash
   god-search-ui --ctl ping
   ```
2. If ping fails, start daemon and retry:
   ```bash
   god-search-ui --ui-daemon
   god-search-ui --print-shell-health
   ```
3. If ping succeeds but output stays offline, verify you are using the same runtime socket namespace:
   - check `XDG_RUNTIME_DIR` in both shells
4. Run contract smoke to validate fallback + live path end-to-end:
   ```bash
   scripts/check_shell_health_contract.sh
   ```

### H. Control-plane commands fail (`--ctl ping` exits 10)

Symptoms:
- `god-search-ui --ctl ping` exits `10`
- summon/hide/toggle commands do nothing

Actions:
1. Check current control-plane socket namespace:
   ```bash
   echo "${XDG_RUNTIME_DIR:-<unset>}"
   ```
2. Start a daemon in the same shell/session:
   ```bash
   god-search-ui --ui-daemon
   god-search-ui --ctl ping
   ```
3. If failure persists, run isolated smoke:
   ```bash
   scripts/control_plane_smoke.sh
   ```
4. If smoke passes but your normal shell fails, you likely have a runtime-dir mismatch between shells/sessions.

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
