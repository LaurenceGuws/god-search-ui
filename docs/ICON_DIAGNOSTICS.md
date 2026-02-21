# Icon Diagnostics

Headless mode supports icon diagnostics for app-result icon resolution:

- `:icondiag` (human-readable)
- `:icondiag --json` (machine-readable)

## JSON Output

Single-line JSON object fields:

- `apps_total`: total app candidates in empty-query snapshot
- `with_icon_metadata`: app candidates with explicit icon metadata
- `with_command_token_icon`: app candidates using command-token fallback
- `likely_glyph_fallback`: app candidates likely using glyph fallback
- `metadata_coverage_pct`: percentage with explicit icon metadata
- `glyph_fallback_pct`: percentage likely using glyph fallback
- `glyph_fallback_samples`: up to 5 sample rows (`"<title> (<action>)"`)

## Interpretation

- High `metadata_coverage_pct` means cache generator is providing icon metadata.
- Non-zero `likely_glyph_fallback` indicates rows missing both icon metadata and a derivable command token.
- `glyph_fallback_samples` helps identify rows to fix in cache generation.

## Suggested Thresholds

- healthy metadata coverage: `>= 70%`
- investigate fallback: `glyph_fallback_pct > 5%`

These thresholds are heuristics, not hard failures.

## Threshold Gate Script

Use:
```bash
MAX_GLYPH_FALLBACK_PCT=5 scripts/check_icondiag_threshold.sh
```

- exits `0` when `glyph_fallback_pct <= MAX_GLYPH_FALLBACK_PCT`
- exits non-zero when threshold is exceeded

You can run the same gate via release smoke strict mode:
```bash
scripts/release_smoke.sh --strict-icon-threshold --icon-threshold=5
```
