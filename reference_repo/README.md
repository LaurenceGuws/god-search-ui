# Reference Repos Workspace

Use this directory to clone external implementation references for architecture and behavior cross-checks.

Examples:
- notification daemons
- shell daemons
- compositor projects
- launcher implementations

## Rules

1. This folder is intentionally git-ignored by default.
2. Do not commit cloned upstream repositories to this project.
3. When a reference influences decisions, document the takeaway in `docs/vendor/` and link the source URL/commit.
4. Keep ad-hoc notes near the related spec doc, not inside cloned repos.

## Suggested Layout

```text
reference_repo/
  mako/
  dunst/
  swaync/
  wofi/
```

## Typical Workflow

1. Clone reference repo here.
2. Inspect behavior/contracts.
3. Capture decisions and constraints in `docs/vendor/...`.
4. Delete stale clones when no longer needed.
