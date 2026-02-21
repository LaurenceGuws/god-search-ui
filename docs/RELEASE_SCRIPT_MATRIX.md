# Release Script Matrix

Quick reference for release automation scripts.

| Script | Purpose | Safe Default | Apply Mode |
|---|---|---|---|
| `scripts/release_smoke.sh` | End-to-end release sanity checks | `scripts/release_smoke.sh` | `scripts/release_smoke.sh --with-gtk-runtime` |
| `scripts/gen_release_notes.sh` | Draft release notes from template + commits | `scripts/gen_release_notes.sh v0.1.1` | edit generated notes and commit |
| `scripts/cut_release_tag.sh` | Tag cut flow with preflight | `scripts/cut_release_tag.sh --version v0.1.1` | `scripts/cut_release_tag.sh --version v0.1.1 --apply --commit-notes --push` |
| `scripts/publish_release_tag.sh` | Publish existing local tag | `scripts/publish_release_tag.sh --version v0.1.1` | `scripts/publish_release_tag.sh --version v0.1.1 --apply` |
| `scripts/arch_package_smoke.sh` | Arch package build/install smoke | `scripts/arch_package_smoke.sh` | `scripts/arch_package_smoke.sh --install --uninstall` |
| `scripts/check_release_helpers.sh` | CLI contract checks for helpers | `scripts/check_release_helpers.sh` | (same command) |

## Recommended Order
1. `scripts/release_smoke.sh`
2. `scripts/gen_release_notes.sh vX.Y.Z`
3. `scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes`
4. `scripts/publish_release_tag.sh --version vX.Y.Z --apply`
