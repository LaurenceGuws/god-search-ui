# Release Notes Curation Checklist

Use before any non-dry-run patch cut.

## Checklist
- Replace placeholder bullets in:
  - `Highlights`
  - `New Features`
  - `Improvements`
  - `Fixes`
- Ensure `Verification Summary` is set to real pass/fail outcomes.
- Set rollback baseline to previous stable tag.
- Add at least one known issue if applicable, otherwise write `None known`.
- Re-run:
  - `scripts/release_smoke.sh`
  - `scripts/check_release_helpers.sh`
  - `scripts/check_release_matrix.sh`
- Cut using:
  - `scripts/cut_release_tag.sh --version <tag> --apply --commit-notes --reuse-notes --push`

## Guardrail
Avoid cutting with template-only text such as blank bullets or `pass/fail` placeholders.
