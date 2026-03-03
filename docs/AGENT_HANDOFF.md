# Agent Handoff

## Current Focus
- Stabilize pre-MVP execution with strict progress tracking and checkpoint commits.
- Keep UI and control-plane workstream state accurate in `workstreams/*_todo.yaml`.
- Maintain the new generic preview model and improve popup/readability quality without adding process bloat.

## Constraints
- Follow `AGENTS.md` and `docs/WORKFLOW.md` each turn.
- Keep docs minimal and canonical.
- Do not reintroduce CI/release machinery before MVP ask.

## Where To Continue
1. Pick one active item from `workstreams/ui_todo.yaml` or `workstreams/control_plane_todo.yaml`.
2. Implement a narrow slice with tests/smokes.
3. Update evidence in the todo item.
4. Commit at user-confirmed healthy checkpoint.

## Quick Verification
- `zig build -Doptimize=ReleaseFast -Denable_gtk=true -Denable_layer_shell=true`
- `zig build test`
- `./re-run.sh`
