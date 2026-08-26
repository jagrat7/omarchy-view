# Repository agent instructions

## Runtime layout

This repository is symlinked to:

```text
~/.config/omarchy/plugins/omarchy-overview
```

Edit files in this repository, not through the symlink. The running Omarchy
Shell disables Quickshell's file watcher, so restart the shell after changing
plugin code.

## Required verification

Run these checks after changing the plugin:

```bash
# Validate the plugin manifest and directory structure.
omarchy plugin validate /home/jagrat/dev/omarchy/omarchy-overview

# Validate edited QML files. Warnings from the existing project/import context
# are acceptable, but the command must exit successfully.
/usr/lib/qt6/bin/qmllint \
  modules/overview/Overview.qml \
  modules/overview/OverviewWidget.qml \
  modules/overview/OverviewWindow.qml \
  services/HyprlandData.qml

# Validate JSON and the patch itself.
jq empty manifest.json
git diff --check
```

Reload the linked plugin and verify the live shell:

```bash
omarchy restart shell
omarchy-shell shell ping
omarchy-shell shell listPlugins
hyprctl globalshortcuts
```

`omarchy-shell shell ping` must return `ok`, and `listPlugins` must contain an
enabled `omarchy-overview` entry. `hyprctl globalshortcuts` must list
`omarchy-overview:next` and `omarchy-overview:previous`. If an agent sandbox
reports that the shell is not running while `quickshell list --all` shows an
instance, rerun the Omarchy commands with desktop-session/escalated access;
sandbox IPC can produce a false negative.
