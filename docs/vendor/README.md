# Vendor References

This directory is for locally stored upstream specs/standards, not generated interpretation docs.

## Policy

1. Store official documents verbatim whenever possible (HTML, PDF, TXT, XML, etc.).
2. Keep a source manifest next to artifacts with:
   - upstream URL
   - fetch date (UTC)
   - version/revision identifier if available
3. Do not create summary/speculation files as substitutes for upstream specs.
4. Implementation notes belong in project docs (`docs/`), while source-of-truth protocol text lives in `docs/vendor/`.

## Suggested Layout

```text
docs/vendor/
  notifications/
    SOURCES.txt
    notification-spec-latest.html
  ipc/
    SOURCES.txt
  wayland/
    SOURCES.txt
  README.md
```

## Fetching

Use `scripts/fetch_vendor_spec.sh` to download and track upstream artifacts with metadata.
The fetch script requires `pandoc` for HTML-to-`*.md`/`*.txt` conversion.

Prerequisites (Arch):
```bash
yay -S pandoc-bin
```

Example fetches:
```bash
scripts/fetch_vendor_spec.sh \
  https://specifications.freedesktop.org/notification-spec/latest/ \
  docs/vendor/notifications/notification-spec-latest.html \
  docs/vendor/notifications/SOURCES.txt

scripts/fetch_vendor_spec.sh \
  https://dbus.freedesktop.org/doc/dbus-specification.html \
  docs/vendor/ipc/dbus-specification.html \
  docs/vendor/ipc/SOURCES.txt
```

Expected result for HTML targets:
1. Original artifact: `*.html`
2. Grep-friendly derivative: `*.txt`
3. Markdown derivative: `*.md`
4. Manifest append in `SOURCES.txt` with fetched timestamp
