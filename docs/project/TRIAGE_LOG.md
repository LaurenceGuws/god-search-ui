# Triage Log

## 2026-02-21 - SSH key permission warning on initial remote push
- Title: SSH key permissions warning with `.pub` path used as identity file.
- Date: 2026-02-21
- Reporter: local operator session
- Affected version/tag: release operations around `v0.1.0-rc2`

### Impact
- Severity: low
- User-facing impact: initial `git push` failed until SSH setup was corrected.
- Frequency: one observed case in this workspace.

### Reproduction
1. Configure remote and push from fresh workspace.
2. SSH config references `/home/home/.ssh/keys/home.pub` as key path.
3. Run `git push`.

### Expected vs Actual
- Expected: push authenticates via valid private key.
- Actual: warning/error indicates unprotected key file and auth failure.

### Scope
- Area: release
- Regression from previous tag?: no (environment/config issue)
- Related commits/tags: `v0.1.0-rc2`, `v0.1.0`

### Proposed Fix
- Candidate change: document SSH key sanity check in release runbook.
- Risk level: low
- Verification plan: run `ssh -T git@github.com` before first push in new workspace.

### Resolution
- Fixed in: operator environment (subsequent push succeeded)
- Verification evidence: successful `git push -u origin main` and tag pushes.
- Notes: keep this as known operational setup footgun.

## 2026-02-21 - Curated notes overwritten during apply cut without reuse flag
- Title: `cut_release_tag.sh` apply path can overwrite curated release notes unless reuse mode is used.
- Date: 2026-02-21
- Reporter: release maintenance cycle
- Affected version/tag: `v0.1.1` cut workflow

### Impact
- Severity: medium
- User-facing impact: curated notes can be replaced by template-generated content during release.
- Frequency: observed once during `v0.1.1` apply cut.

### Reproduction
1. Manually curate `docs/release-notes-v0.1.1.md`.
2. Run `scripts/cut_release_tag.sh --version v0.1.1 --apply --commit-notes --push`.
3. Observe regenerated template content replaces curation.

### Expected vs Actual
- Expected: curated notes are preserved by default or strongly guarded.
- Actual: notes are regenerated unless reuse mode is explicitly provided.

### Scope
- Area: release
- Regression from previous tag?: no
- Related commits/tags: `v0.1.1`, `7764338`

### Proposed Fix
- Candidate change: for `v0.1.2`, require explicit `--regen-notes` to regenerate on apply and default to reuse when notes file exists.
- Risk level: medium
- Verification plan: apply-cut dry-run should indicate chosen note mode; lint should fail if placeholders remain.

### Resolution
- Fixed in: partial mitigation in `v0.1.1` cycle (`--reuse-notes` support + curation checklist/lint).
- Verification evidence: helper/docs updated; lint + precut gate pass.
- Notes: good first functional candidate for `v0.1.2`.
