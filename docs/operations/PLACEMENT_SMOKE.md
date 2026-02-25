# Placement Smoke

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: no

Quick validation for placement diagnostics and monitor pinning.
For full placement setup/verification order, use `docs/operations/PLACEMENT_OPERATOR_FLOW.md`.

## Run

```bash
scripts/placement_smoke.sh
```

## Expect A Specific Output Name

```bash
scripts/placement_smoke.sh DP-1
```

## What It Checks

1. `--print-outputs` returns current display list.
2. `--print-config` returns resolved runtime policy.
3. Optional expected output name exists in output list.
