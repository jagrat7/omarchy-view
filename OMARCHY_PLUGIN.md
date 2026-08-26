# Omarchy plugin install

This directory is packaged as a third-party Omarchy shell plugin.

Install it at:

```text
~/.config/omarchy/plugins/omarchy-overview/
```

Then run:

```bash
omarchy plugin rescan
omarchy plugin enable omarchy-overview
```

Open it directly with:

```bash
omarchy-shell overview open
```

For a Hyprland Lua keybind, use:

```lua
hl.unbind("ALT + TAB")
o.bind("ALT + TAB", "Overview", hl.dsp.global("omarchy-overview:next"), { repeating = true })
```

Hold `Alt` to keep the overview open and press `Tab` repeatedly to cycle
through windows in most-recently-used order. Releasing `Alt` focuses the
highlighted window; `Shift+Tab` moves backward, `Enter` confirms, and `Escape`
cancels. The same global shortcut can be bound to `SUPER + TAB` or another
supported modifier combination.

Settings are read inline from `~/.config/omarchy/shell.json`, inside the
`plugins` entry for `omarchy-overview`:

```json
{
  "id": "omarchy-overview",
  "rows": "2",
  "columns": "5",
  "hideEmptyRows": "true",
  "showSpecialWorkspaces": "false",
  "specialWorkspaceColumns": "5",
  "showIcons": "true"
}
```

The plugin follows the same shape as Omarchy panels: it exposes `settings`
and `setting(name, fallback)`, and the overview config reads the fields from
there. Its local `Color` and `Style` wrappers delegate to Omarchy
`qs.Commons`, so it uses the active shell theme.
