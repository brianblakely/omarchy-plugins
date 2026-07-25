# Keybindings

Use this reference when documenting or implementing shortcuts for panels, overlays, menus, services, or bar widgets.

## Global Keybindings

Plugins do not declare global keybindings in `manifest.json`. Do not add fields such as `shortcuts`, `keybindings`, or `accelerators` unless upstream Omarchy explicitly adds support.

The installer does not automatically mutate Hyprland config. Key ownership should remain with the user.

## Preferred Pattern: Hyprland Binding To Omarchy IPC

For a panel, overlay, menu, or popup-owning bar widget, document an optional binding that calls shell IPC:

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

The shell lifecycle target is stable across plugin rescans and bar reloads:

```bash
omarchy-shell shell summon acme.quick-notes
omarchy-shell shell hide acme.quick-notes
omarchy-shell shell toggle acme.quick-notes
```

Panel, overlay, and menu entry points should expose `open()` and `close()`. Exposing a boolean `opened` property also lets `toggle` read the component's live state instead of relying only on the shell's requested-open state.

## Popup Bar Widgets

For a plugin whose only UI kind is `bar-widget`, the same shell commands route to a live widget in the active bar. This avoids binding directly to one of the per-monitor widget instances.

The bar-widget root must expose all three members:

```qml
import QtQuick
import qs.Ui

BarWidget {
  id: root

  readonly property bool opened: popupLoader.item
    ? popupLoader.item.opened === true
    : false

  function open() {
    if (popupLoader.item && typeof popupLoader.item.open === "function")
      popupLoader.item.open()
  }

  function close() {
    if (popupLoader.item && typeof popupLoader.item.close === "function")
      popupLoader.item.close()
  }

  Loader {
    id: popupLoader
    source: "Popup.qml"
  }
}
```

The widget must be enabled and present in the active bar layout for the shell to find it. The bar-widget lifecycle route does not deliver a payload. A plugin that also declares `panel`, `overlay`, or `menu` uses that loader entry point instead of this bar-widget route.

Optional user binding:

```lua
o.bind("SUPER + N", "Quick Notes", "omarchy-shell shell toggle acme.quick-notes")
```

Do not use a widget-local `IpcHandler` as the primary open/close/toggle endpoint. An IPC target selects one matching handler, while bar widgets have live instances on every monitor and are recreated when the bar or plugin reloads.

## Custom IPC From Bar Widgets

Use a singleton `service` entry point when a custom IPC action represents one shell-wide side effect. When a direct bar-widget IPC action changes visible state on every monitor, relay it through the `BarWidget.broadcast(method)` helper:

```qml
IpcHandler {
  target: "acme.status"

  function refresh(): void {
    root.broadcast("refresh")
  }
}
```

`broadcast()` calls the named no-argument method on every live instance with the same widget id, including duplicate layout entries. Do not use it for opening a URL, starting a process, performing a shared write, returning a query result, or an action intended for only the clicked widget.

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
