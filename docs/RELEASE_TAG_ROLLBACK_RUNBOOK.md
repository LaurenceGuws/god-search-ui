# Release Tagging and Rollback Runbook

Use this runbook for local release cutovers.

Automation helper (dry-run by default):
```bash
scripts/cut_release_tag.sh --version v0.1.0
```

Notes:
- Dry-run mode performs preflight checks and prints planned commands only.
- Release notes draft file is generated only with `--apply`.
- Use `--commit-notes` if tag should point to the commit that contains release notes.

## Inputs
- `VERSION` (example: `v0.1.0`)
- `PREV_REF` previous known-good tag/commit

## 1. Preflight
```bash
git status --short
scripts/release_smoke.sh
```

Working tree must be clean before tagging.

## 2. Generate Draft Notes
```bash
scripts/gen_release_notes.sh v0.1.0 docs/release-notes-v0.1.0.md
```

Edit and finalize release notes file as needed.

## 3. Create Annotated Tag
```bash
git tag -a v0.1.0 -m "god-search-ui v0.1.0"
git show v0.1.0 --no-patch
```

## 4. Push Commit and Tag
```bash
git push origin main
git push origin v0.1.0
```

Or use helper (dry-run default):
```bash
scripts/publish_release_tag.sh --version v0.1.0
scripts/publish_release_tag.sh --version v0.1.0 --apply
```

If `origin` is not configured, dry-run still prints planned commands; `--apply` requires a valid `origin`.

## 5. Verify Tag Targets Expected Commit
```bash
git rev-parse v0.1.0
git rev-parse HEAD
```

These SHAs should match for a straight cut from `main`.

## Rollback (Tag Only)
If tag points to wrong commit and was not consumed:
```bash
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
```

Then re-create correct tag.

## Rollback (Code)
Preferred rollback is a forward fix:
```bash
git switch main
git revert --no-edit BAD_COMMIT_SHA
git push origin main
```

If an emergency hard rollback is explicitly approved by maintainers, return local branch to previous known-good ref:
```bash
git switch main
git reset --hard PREV_REF
```

Push only if coordinated with collaborators:
```bash
git push --force-with-lease origin main
```

## Post-Rollback Validation
```bash
scripts/release_smoke.sh
```
