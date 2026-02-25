# UX Roadmap

This roadmap tracks UX stabilization and polish work after `v0.1.2`.

## Goals
- Make launcher feel fast and predictable under real usage.
- Remove prototype behaviors (placeholder flashes, dead selection rows).
- Improve readability/accessibility and theme adaptability.
- Keep keyboard-first workflow strong.

## Phase 1: UX Stability (High Priority)

### 1. Non-blocking action execution
- Problem:
  - UI thread blocks while running commands.
- Target:
  - Launch actions asynchronously; keep input and list responsive.
- Candidate files:
  - `src/ui/gtk_shell.zig`

### 2. Scrolling and row activation correctness
- Problem:
  - Result list is not inside a scroller; headers/info rows can become selected first.
- Target:
  - Use `GtkScrolledWindow` for list container.
  - Ensure selection skips non-activatable rows.
- Candidate files:
  - `src/ui/gtk_shell.zig`

### 3. Debounced search update
- Problem:
  - Full search/render occurs on every keystroke.
- Target:
  - Add short debounce (80-120ms) to smooth typing.
- Candidate files:
  - `src/ui/gtk_shell.zig`
  - `src/app/search_service.zig` (if needed for support)

## Phase 2: UX Clarity (Medium Priority)

### 4. Dedicated status surface
- Problem:
  - Placeholder text currently carries runtime status.
- Target:
  - Add explicit status row/footer for refresh/error/confirmation hints.
- Candidate files:
  - `src/ui/gtk_shell.zig`

### 5. Window sizing and layout adaptivity
- Problem:
  - Window size is fixed and not display-adaptive.
- Target:
  - Introduce adaptive min/default sizing.
  - Improve margins and row spacing consistency.
- Candidate files:
  - `src/ui/gtk_shell.zig`

### 6. Remove startup placeholder flash
- Problem:
  - "Result placeholder" row appears before first render.
- Target:
  - First paint should show real state immediately (results/no-results/error).
- Candidate files:
  - `src/ui/gtk_shell.zig`

## Phase 3: UX Polish (Medium/Low Priority)

### 7. Theme/CSS system pass
- Problem:
  - Hardcoded markup colors and style values.
- Target:
  - Move visual style to CSS/theme variables.
  - Improve light/dark contrast behavior.
- Candidate files:
  - `src/ui/gtk_shell.zig`
  - `assets/` + theme resources (to be introduced)

### 8. Ranking/recency UX tuning
- Problem:
  - Result ordering can still feel noisy in blended lists.
- Target:
  - Tune display order and section weighting for user intent.
- Candidate files:
  - `src/search/rank.zig`
  - `src/app/search_service.zig`

## Validation Criteria
- `scripts/dev.sh check` passes.
- `scripts/release_smoke.sh` passes.
- GTK build passes: `zig build -Denable_gtk=true`.
- Manual keyboard UX smoke:
  - typing remains responsive under rapid input
  - arrows + Enter behave consistently
  - no dead-row activation confusion

## Execution Notes
- Keep slices small and shippable (1-2 UX changes per commit).
- Prioritize Phase 1 before adding new UX features.
- Update `docs/TASK_QUEUE.md` for each accepted slice.
