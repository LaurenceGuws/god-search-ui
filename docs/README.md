# Docs System

This repository uses a categorized docs layout with canonical locations and compatibility symlinks in `docs/` root.

## Categories

1. `docs/architecture/`
- long-lived system design, protocol specs, implementation locks

2. `docs/roadmaps/`
- future-facing plans and phased execution tracks

3. `docs/operations/`
- runbooks, packaging, integration, release operations

4. `docs/project/`
- active queue/logs/templates for execution management

5. `docs/releases/`
- release notes and release-notes templates/checklists

6. `docs/vendor/`
- upstream specs/artifacts stored locally (source of truth for external standards)

7. `docs/archive/`
- historical one-off plans/tasks no longer actively maintained

## Governance Rules

1. Every new internal doc must live in a category folder, not docs root.
2. `docs/` root entries are compatibility symlinks only.
3. For each topic, define one canonical doc and reference it from related docs.
4. If implementation behavior changes, update canonical docs in the same PR.
5. External protocol requirements must be sourced from `docs/vendor/` artifacts, not generated summaries.

## Required Header For New Internal Docs

```md
Status: draft|active|deprecated
Owner: <team-or-person>
Last-Reviewed: YYYY-MM-DD
Canonical: yes|no
```

Use `docs/DOC_TEMPLATE.md` when creating new docs.

Execution gate for active DE work:
- `docs/project/DE_EXECUTION_CHECKPOINTS.md`

## Transition Note

Legacy scripts/tools that reference `docs/<name>.md` remain functional through symlinks.
New references should use canonical categorized paths.
