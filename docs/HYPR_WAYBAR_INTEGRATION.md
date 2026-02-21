# Hypr + Waybar Integration

This guide wires `god-search-ui` into the existing Hyprland + Waybar flow.

## 1. Install Binary

After packaging or local build, ensure `god-search-ui` is in `PATH`.

Example local check:
```bash
god-search-ui --ui
```

## 2. Hyprland Keybind

Add to your Hypr keymap module:

```ini
# Super+Space: God Search
bind = $mainMod, SPACE, exec, god-search-ui --ui
```

Suggested fallback (if GTK mode is unavailable) is to keep your existing shell launcher binding on another key.

## 3. Waybar Launcher Button

In `config.jsonc`, point left launcher to the binary:

```jsonc
"custom/wofi": {
  "class": "custom-wofi",
  "format": " ",
  "tooltip": "God Search",
  "on-click": "god-search-ui --ui"
}
```

## 4. Optional User Service

If you want preloaded startup behavior, use a user service.

Template provided in repo:
- `packaging/systemd/god-search-ui.service`

Install to:
- `~/.config/systemd/user/god-search-ui.service`

Unit content:

```ini
[Unit]
Description=God Search UI
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/god-search-ui --ui
Restart=on-failure
RestartSec=1

[Install]
WantedBy=default.target
```

Enable it:
```bash
systemctl --user daemon-reload
systemctl --user enable --now god-search-ui.service
```

## 5. Validation

1. Press `Super+Space` and verify window appears.
2. Search for an app and hit Enter.
3. Verify telemetry output file updates:
   - `~/.local/state/god-search-ui/telemetry.log`

## Notes

- GTK UI requires building with `-Denable_gtk=true`.
- If GTK mode is unavailable, headless mode still works for command-line iteration.

## Apps Cache Format (Optional Icon Column)

Apps provider cache supports:
- legacy: `category<TAB>name<TAB>exec`
- extended: `category<TAB>name<TAB>exec<TAB>icon`

The 4th `icon` column is optional. When present, GTK rows use it first for app icon lookup.

Example:
```tsv
Utilities	Kitty	kitty	kitty
Internet	Firefox	firefox	firefox
```
