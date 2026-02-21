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
