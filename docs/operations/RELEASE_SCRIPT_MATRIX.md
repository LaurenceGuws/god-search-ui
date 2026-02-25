# Release Script Matrix

Quick reference for release automation scripts.

| Script | Purpose | Safe Default | Apply Mode |
|---|---|---|---|
| `scripts/release_smoke.sh` | End-to-end release sanity checks | `scripts/release_smoke.sh` | `scripts/release_smoke.sh --with-gtk-runtime` |
| `scripts/release_smoke.sh` (CI preset) | CI-friendly smoke preset | `scripts/release_smoke.sh --ci` | `scripts/release_smoke.sh --strict-icon-threshold --icon-threshold=5` |
| `scripts/release_validate.sh` | One-pass operator validation wrapper | `scripts/release_validate.sh` | `scripts/release_validate.sh --ci` |
| `scripts/check_clean_worktree.sh` | Clean-worktree preflight guard | `scripts/check_clean_worktree.sh` | (same command) |
| `scripts/check_release_validate_ci.sh` | CI guard ensuring `release_validate --ci` completes non-interactively | `scripts/check_release_validate_ci.sh` | (same command) |
| `scripts/gen_release_notes.sh` | Draft release notes from template + commits | `scripts/gen_release_notes.sh v0.1.1` | edit generated notes and commit |
| `scripts/lint_release_notes.sh` | Release-notes placeholder/marker lint | `scripts/lint_release_notes.sh docs/release-notes-v0.1.1.md` | (same command) |
| `scripts/cut_release_tag.sh` | Tag cut flow with preflight | `scripts/cut_release_tag.sh --version v0.1.1` | `scripts/cut_release_tag.sh --version v0.1.1 --apply --commit-notes --push` |
| `scripts/publish_release_tag.sh` | Publish existing local tag | `scripts/publish_release_tag.sh --version v0.1.1` | `scripts/publish_release_tag.sh --version v0.1.1 --apply` |
| `scripts/arch_package_smoke.sh` | Arch package build/install smoke | `scripts/arch_package_smoke.sh` | `scripts/arch_package_smoke.sh --install --uninstall` |
| `scripts/check_release_helpers.sh` | CLI contract checks for helpers | `scripts/check_release_helpers.sh` | (same command) |
| `scripts/check_release_matrix.sh` | Release matrix script-existence and order guards | `scripts/check_release_matrix.sh` | (same command) |
| `scripts/check_cut_dryrun_default_safe.sh` | Cut dry-run default-safe notes-path assertions | `scripts/check_cut_dryrun_default_safe.sh` | (same command) |
| `scripts/check_release_docs_contracts.sh` | Meta contract check for release docs/help/matrix | `scripts/check_release_docs_contracts.sh` | (same command) |
| `scripts/check_release_contracts.sh` | One-command alias for all release contract checks | `scripts/check_release_contracts.sh --docs-only` | `scripts/check_release_contracts.sh` |
| `scripts/check_release_contracts_contract.sh` | Contract checks for release-contracts alias CLI/docs sync | `scripts/check_release_contracts_contract.sh` | (same command) |
| `scripts/check_release_contracts_doc.sh` | Consistency checks for `docs/RELEASE_CONTRACTS.md` | `scripts/check_release_contracts_doc.sh` | (same command) |
| `scripts/check_release_smoke_contract.sh` | Release-smoke help/docs contract checks | `scripts/check_release_smoke_contract.sh` | (same command) |
| `scripts/check_release_validate_contract.sh` | Release-validate help/docs contract checks | `scripts/check_release_validate_contract.sh` | (same command) |
| `scripts/check_apps_cache_format.sh` | Apps cache format compatibility guard | `scripts/check_apps_cache_format.sh` | (same command) |
| `scripts/check_icon_theme_env.sh` | Icon-theme environment diagnostics | `scripts/check_icon_theme_env.sh` | (same command) |
| `scripts/check_icondiag_json.sh` | Icon diagnostics JSON schema checks | `scripts/check_icondiag_json.sh` | (same command) |
| `scripts/check_icondiag_threshold.sh` | Icon fallback threshold gate | `MAX_GLYPH_FALLBACK_PCT=5 scripts/check_icondiag_threshold.sh` | lower threshold to tighten gate |

## Recommended Order
1. `scripts/release_smoke.sh`
2. `scripts/release_smoke.sh --ci` (for CI/minimal-host parity)
3. `scripts/release_validate.sh --ci` (single-entrypoint operator preflight)
4. `scripts/gen_release_notes.sh vX.Y.Z`
5. `scripts/lint_release_notes.sh docs/release-notes-vX.Y.Z.md`
6. `scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes --push`

Default-safe note mode:
- if `docs/release-notes-<version>.md` exists, apply mode reuses it.
- pass `--regen-notes` to intentionally overwrite with a fresh generated draft.
Quick dry-run example:
- `scripts/cut_release_tag.sh --version v0.1.2`
- Expected output includes either:
  - `[dry-run] would reuse: docs/release-notes-v0.1.2.md`
  - or regeneration command when notes file does not yet exist.
7. `scripts/publish_release_tag.sh --version vX.Y.Z --apply`

## Related Docs

- `docs/RELEASE_SMOKE_MODES.md`
- `docs/RELEASE_VALIDATE_MODES.md`
- `docs/ICON_DIAGNOSTICS.md`
- `docs/RELEASE_CONTRACTS.md`

Release contracts quick order:
- `scripts/check_release_contracts.sh --docs-only`
- `scripts/release_validate.sh --ci --require-clean`
- `scripts/check_release_validate_ci.sh`
