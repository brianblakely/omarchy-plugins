# Keybindings

Use this reference when documenting or implementing shortcuts for panels, overlays, menus, services, or bar widgets.

## Global Keybindings

Plugins do not declare global keybindings in `manifest.json`. Do not add fields such as `shortcuts`, `keybindings`, or `accelerators` unless upstream Omarchy explicitly adds support.

The installer does not automatically mutate Hyprland config. Key ownership should remain with the user.

## Preferred Pattern: Hyprland Binding To Omarchy IPC

For a panel, overlay, or menu plugin, document an optional binding that calls shell IPC:

```lua
o.bind("SUPER + N", "Quick Notes", "omarchy-shell shell toggle acme.quick-notes")
```

This works well for summonable plugins such as:

```json
{
  "schemaVersion": 1,
  "id": "acme.quick-notes",
  "name": "Quick Notes",
  "version": "1.0.0",
  "kinds": ["panel"],
  "entryPoints": {
    "panel": "Panel.qml"
  }
}
```

Equivalent lower-level Hyprland Lua style:

```lua
hl.bind(
  "SUPER + N",
  hl.dsp.exec_cmd("omarchy-shell shell toggle acme.quick-notes"),
  { description = "Quick Notes" }
)
```

## Alternative Pattern: Quickshell GlobalShortcut

Use a Quickshell `GlobalShortcut` only when the plugin itself needs to receive the shortcut in QML, for example to handle press/release state or route multiple actions through an always-loaded service.

Important model:

```text
Plugin registers:  appid:name
User binds:        key chord -> appid:name
```

Put `GlobalShortcut` in a component that is already loaded. Preferred locations:

- A `service` plugin.
- A bar widget, if the shortcut only matters while the widget is on the bar.
- A panel/menu/overlay only when `keepLoaded: true` is appropriate.

Recommended service plus panel manifest:

```json
{
  "schemaVersion": 1,
  "id": "acme.quick-notes",
  "name": "Quick Notes",
  "version": "1.0.0",
  "kinds": ["service", "panel"],
  "entryPoints": {
    "service": "Service.qml",
    "panel": "Panel.qml"
  }
}
```

`Service.qml` example:

```qml
import QtQuick
import Quickshell.Hyprland

Item {
  id: root

  property var shell

  readonly property string pluginId: "acme.quick-notes"

  GlobalShortcut {
    appid: "acme.quick-notes"
    name: "toggle"
    description: "Toggle Quick Notes"

    onPressed: {
      if (root.shell)
        root.shell.toggle(root.pluginId, "{}")
    }
  }
}
```

User binding for that endpoint:

```lua
o.bind(
  "SUPER + N",
  "Quick Notes",
  hl.dsp.global("acme.quick-notes:toggle")
)
```

Plain Hyprland-style equivalent:

```conf
bind = SUPER, N, global, acme.quick-notes:toggle
```

Prefer the Omarchy IPC binding for normal plugins. Use `GlobalShortcut` only when the plugin needs QML-level shortcut handling.
