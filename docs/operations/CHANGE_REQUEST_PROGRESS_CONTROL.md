# Change Request: Progress Control + Iteration Loop

Status: proposed  
Owner: shell  
Last-Reviewed: 2026-03-03  
Canonical: yes

## Problem

Current execution loops are weakly controlled:
1. Progress state is spread across chat context and ad-hoc notes.
2. No durable session handoff artifact for next iteration.
3. No single source of truth for task status transitions.
4. Commit cadence is inconsistent around healthy checkpoints.

Result: context drift, repeated rediscovery, and unstable iteration quality.

## Target State

Adopt a strict loop model equivalent to the `zide` process controls:
1. high-level handoff docs only
2. task/status source of truth in structured todo files
3. explicit workflow rules and doc ownership
4. checkpoint-driven small commits
5. doc-drift cleanup by default

## Proposed Artifacts

1. `docs/WORKFLOW.md`
- Defines implementation loop and document ownership rules.

2. `docs/INDEX.md`
- Minimal map of canonical docs + where status lives.

3. `docs/AGENT_HANDOFF.md`
- High-level current focus, constraints, and next entrypoints.
- No detailed progress logs.

4. `docs/AGENT_HOVER.md` (optional)
- Short high-level context snapshot (remove if redundant).

5. `workstreams/*_todo.yaml`
- Single source of truth for progress state.
- One file per work area (e.g., `ui_todo.yaml`, `control_plane_todo.yaml`).

6. `scripts/check_workflow_contract.sh`
- Guards:
  - required docs exist
  - required todo files parse and use valid statuses
  - no forbidden references to removed release docs

## Workflow Contract

Every implementation turn follows:
1. Read `AGENTS.md`.
2. Read `docs/AGENT_HANDOFF.md`.
3. Read active `workstreams/*_todo.yaml` entries and canonical docs.
4. Implement one scoped slice.
5. Update todo status + evidence fields.
6. Run required tests/smokes for that slice.
7. If user confirms health ("looks good", "nice", "working"), checkpoint commit immediately.

## Todo Schema (Minimum)

```yaml
id: CP-01
title: Control plane smoke stabilization
status: in_progress   # todo|in_progress|blocked|done
owner: shell
scope:
  - src/ipc/control.zig
acceptance:
  - "--ctl ping returns 0 with daemon up"
evidence:
  tests:
    - "scripts/control_plane_smoke.sh"
  last_run: "2026-03-03"
notes: "short notes only"
```

## Checkpoint Commit Policy

Mandatory rules:
1. Small commit per healthy checkpoint.
2. No large mixed commits crossing unrelated slices.
3. Commit message includes slice id (`CP-01`, `UI-03`, etc.).
4. Todo entry must be updated before commit.

## Doc Drift Policy

1. If doc contradicts code, fix or delete the doc.
2. Keep one canonical doc per topic.
3. No long-form progress logs in docs.
4. No release-process docs before MVP gate is explicitly opened.

## Rollout Plan

Phase 1: Foundation
1. Add `docs/WORKFLOW.md`, `docs/INDEX.md`, `docs/AGENT_HANDOFF.md`.
2. Add initial `workstreams/control_plane_todo.yaml` and `workstreams/ui_todo.yaml`.

Phase 2: Enforcement
1. Add `scripts/check_workflow_contract.sh`.
2. Wire check into local `scripts/dev.sh check`.

Phase 3: Migration
1. Move remaining actionable status from old docs into todo files.
2. Delete stale/duplicative docs after migration.

## Acceptance Criteria

1. A new agent can start from handoff + todo without chat history.
2. Each active slice has explicit status and acceptance checks.
3. Healthy checkpoints consistently produce small commits.
4. Docs remain under 10 canonical files in pre-MVP mode.
5. No references to deleted release/roadmap artifacts remain.

## Requested Decision

Approve this change request to implement the workflow artifacts and enforcement in the next iteration slice.
