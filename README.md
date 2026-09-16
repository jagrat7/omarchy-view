# Omarchy Overview Plugin

A Hyprland workspace overview plugin with live window previews, seamless theme integration, and app icon resolution for [Omarchy Shell](https://github.com/AyushKr2003/omarchy-dotfiles).

![Omarchy Overview Screenshot](preview.png)

> 💡 **Credits & Attribution**: This plugin is based on [AyushKr2003/omarchy-overview](https://github.com/AyushKr2003/omarchy-overview), which adapted [Shanu-Kumawat/quickshell-overview](https://github.com/Shanu-Kumawat/quickshell-overview.git) for Omarchy.

---

## Installation

### Via `omarchy plugin` (Recommended)

Install directly from GitHub using the Omarchy plugin CLI:

```bash
omarchy plugin add https://github.com/jagrat7/omarchy-view.git
```

---

### Manual Installation

Clone or copy this folder directly into your Omarchy plugins directory:

```bash
mkdir -p ~/.config/omarchy/plugins/omarchy-overview
cp -r . ~/.config/omarchy/plugins/omarchy-overview/
```

Then rescan and enable the plugin:

```bash
omarchy plugin rescan
omarchy plugin enable omarchy-overview
```

---

## Uninstallation

### Via `omarchy plugin` (Recommended)

Remove the plugin using the Omarchy CLI:

```bash
omarchy plugin remove omarchy-overview
```

---

### Manual Uninstallation

```bash
omarchy plugin disable omarchy-overview
rm -rf ~/.config/omarchy/plugins/omarchy-overview
omarchy plugin rescan
```

---

## Keybinding & Usage

### Open via Shell IPC

```bash
omarchy-shell overview open
```

### Hyprland Keybinding (`bindings.lua`)

Add the following binding to your `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("ALT + TAB")
o.bind("ALT + TAB", "Overview", hl.dsp.global("omarchy-overview:next"), { repeating = true })
```

The same global shortcut can be assigned to another modifier such as
`SUPER + TAB`. Hold the modifier to keep the overview open, press `Tab`
repeatedly to cycle through windows in most-recently-used order, and release
the modifier to focus the highlighted window. While the overview is open,
`Shift+Tab` cycles backward. Use the arrow keys or `H`/`J`/`K`/`L` to move
between workspaces in the displayed grid; navigation wraps at the grid edges.
The number keys jump directly to a workspace in the current group (`1`-`9`,
with `0` selecting the tenth workspace). Releasing the modifier after choosing
a workspace focuses its most-recent window, or leaves an empty workspace
active. `Enter` confirms the highlighted window and `Escape` cancels window
selection.

---

## Configuration

Settings are read inline from `~/.config/omarchy/shell.json` inside the `plugins` array entry:

```json
{
  "id": "omarchy-overview",
  "rows": 2,
  "columns": 5,
  "hideEmptyRows": true,
  "showSpecialWorkspaces": false,
  "specialWorkspaceColumns": 5,
  "showIcons": true
}
```

### Available Settings Schema

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `rows` | `integer` | `2` | Number of workspace grid rows. |
| `columns` | `integer` | `5` | Number of workspace grid columns. |
| `hideEmptyRows` | `boolean` | `true` | Hides empty rows automatically. |
| `showSpecialWorkspaces` | `boolean` | `false` | Includes special scratchpad workspaces. |
| `specialWorkspaceColumns` | `integer` | `5` | Columns count for special workspaces. |
| `showIcons` | `boolean` | `true` | Display resolution-matched app icons in the top-left of window previews. |

---

## Features & Omarchy Integration

- **Live Window Previews**: Renders real-time Hyprland window thumbnails across workspaces.
- **Scrolling Layout Support**: Expands scrolling workspaces horizontally to reveal off-screen tape windows, with a bounded maximum width.
- **Keyboard Window Switching**: Cycles through app windows with `Tab` / `Shift+Tab`, with commit-on-modifier-release behavior.
- **Keyboard Workspace Navigation**: Moves through the workspace grid with arrow keys or `H`/`J`/`K`/`L`, with direct number-key selection.
- **Dynamic App Icon Resolution**: Resolves standard GUI apps, webapps/PWAs (Chrome/Brave/Edge), and terminal TUI apps (Yazi, Neovim, btop, ranger) matching `omarchy.menu`.
- **Theme Integration**: Follows active Omarchy shell theme tokens (`qs.Commons.Color` & `qs.Commons.Style`).
- **HiDPI Scaling**: Automatically scales icon rendering by `Screen.devicePixelRatio` for sharp rendering.

---

## Credits

- Maintained by [jagrat7](https://github.com/jagrat7).
- Adapted for Omarchy shell plugin architecture, IPC, and icon library integration by [AyushKr2003](https://github.com/AyushKr2003) ([omarchy-overview](https://github.com/AyushKr2003/omarchy-overview)).
- Original Quickshell Overview by [Shanu-Kumawat/quickshell-overview](https://github.com/Shanu-Kumawat/quickshell-overview.git).

---

## License

This project is licensed under the [MIT License](LICENSE).
