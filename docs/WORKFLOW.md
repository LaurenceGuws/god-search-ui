# Workflow + Docs Guide

This repo uses a strict pre-MVP execution loop so progress stays durable and easy to hand off.

## Implementation Loop
1. Read `AGENTS.md`.
2. Read `docs/AGENT_HANDOFF.md`.
3. Read active entries in `workstreams/*_todo.yaml` and the canonical design/ops docs they reference.
4. Implement one scoped slice only.
5. Update the todo entry status, evidence, and notes.
6. Run the required build/tests/smokes for that slice.
7. When user feedback confirms health (for example: "looks good", "nice", "working"), create a small checkpoint commit immediately.

## Document Ownership
- `AGENTS.md`: execution rules and commit cadence.
- `docs/INDEX.md`: canonical doc map.
- `docs/AGENT_HANDOFF.md`: high-level current focus and next entrypoints.
- `workstreams/*_todo.yaml`: source of truth for task state.
- `docs/architecture/*`: architecture intent and contracts.
- `docs/operations/*`: operator runbooks and smoke/troubleshooting steps.

## Progress Rules
- Progress details live in workstream todos, not handoff docs.
- Keep todos concise and evidence-backed.
- If a doc contradicts code, fix or delete the doc in the same slice.
- Do not add release-process ceremony before MVP.
