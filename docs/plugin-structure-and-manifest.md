# Plugin Structure And Manifest

Use this reference when creating or changing plugin folders, entry points, manifest fields, plugin ids, or plugin kinds.

## Repository Structure

An installable Omarchy plugin is one Git repository with `manifest.json` at the repository root. `omarchy plugin add <git-url>` clones that repository and validates its root as one plugin.

This repository is a development/catalog monorepo. Each immediate child of `plugins/` is kept self-contained so it can be validated here and published or mirrored as the root of its own Git repository:

```text
omarchy-plugins/
  README.md
  AGENTS.md

  plugins/
    cool-clock/
      manifest.json
      Widget.qml

    quick-notes/
      manifest.json
      Panel.qml

    media-helper/
      manifest.json
      Service.qml
      BarWidget.qml
```

The monorepo itself is not a valid argument to `omarchy plugin add`: its root intentionally has no `manifest.json`, and the current installer does not select a subdirectory from a remote repository. Public releases therefore need one real Git repository per plugin, with the contents of the corresponding folder under `plugins/` placed at that repository's root. Do not document a per-plugin URL until that repository actually exists.

Installed plugins live at `~/.config/omarchy/plugins/<id>/`. The destination name is determined by `manifest.id`, not by the remote repository name or this monorepo's source-folder name. Prefer source-folder and repository names that clearly correspond to the plugin, but do not rely on them as identity.

## Filesystem Safety

Do not include symlinks anywhere inside a plugin folder. The validator rejects symlinks.

Entry points must be relative paths that stay inside the plugin folder. They must not be absolute paths, must not contain `..`, must not contain newlines, and must point to existing files.

Valid:

```json
"entryPoints": {
  "barWidget": "Widget.qml"
}
```

Valid:

```json
"entryPoints": {
  "panel": "ui/Panel.qml"
}
```

Invalid:

```json
"entryPoints": {
  "panel": "/home/me/Panel.qml"
}
```

Invalid:

```json
"entryPoints": {
  "panel": "../Panel.qml"
}
```

## Manifest Requirements

Every plugin needs a `manifest.json`.

Required fields:

```text
schemaVersion
id
name
version
kinds
entryPoints
```

Rules:

- `schemaVersion` must be the JSON number `1`, not the string `"1"`.
- `id` must be a valid plugin id.
- `name` must be present.
- `version` must be present.
- `kinds` must be a non-empty array.
- `entryPoints` must be an object.
- Every declared entry point must resolve to an existing file inside the plugin directory.

## Valid Plugin Ids

Use namespaced ids such as:

```text
acme.cool-clock
jane.weather
my-org.clipboard-tools
```

A plugin id must:

- Be non-empty.
- Start with an ASCII letter or digit.
- Contain only ASCII letters, digits, `.`, `_`, and `-`.
- Not contain `/`.
- Not contain `..`.
- Not use the reserved `omarchy.*` namespace for third-party plugins.
- Not collide with shipped first-party plugin ids.

Invalid ids:

```text
omarchy.cool-clock
../cool-clock
cool/clock
.cool-clock
```

## Supported Plugin Kinds

| Kind | Use |
| --- | --- |
| `bar-widget` | A widget that can be placed in an Omarchy bar section. |
| `panel` | A persistent or summoned floating window. |
| `overlay` | A fullscreen overlay. |
| `menu` | A summoned menu surface. |
| `service` | A headless singleton with no UI. |
| `bar` | A complete bar implementation that can replace the built-in `omarchy.bar`. |

Use `bar-widget` when adding something to the active bar. Use `bar` only when implementing the complete bar host. One `bar` plugin is active at a time through `bar.id` in `shell.json`; an unavailable or invalid selection falls back to `omarchy.bar`.

Panels, overlays, and menus are generally loaded when summoned. A plugin that must stay alive between summons can use `keepLoaded: true`. A `service` plugin is the preferred always-loaded place for background behavior.

Entry-point QML files are `Item`-based components, not `ShellRoot`s. The host injects supported properties after loading when the entry point declares them:

- Service and panel/overlay/menu entry points may declare `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, and `barWidgetRegistry`.
- A panel/overlay/menu entry point paired with a service may also declare `service`.
- A bar-widget entry point receives `bar`, `moduleName`, and `settings` from the active bar. It can reach the host shell through `bar.shell` when available.
- A full `bar` entry point may declare `omarchyPath`, `shell`, `manifest`, `pluginRegistry`, `barWidgetRegistry`, and `barConfig`.

Do not mark host-injected properties as `required` on dynamically loaded third-party entry points; the host assigns them after the component loads.

## Bar Widget Manifest Example

```json
{
  "schemaVersion": 1,
  "id": "acme.cool-clock",
  "name": "Cool Clock",
  "version": "1.0.0",
  "author": "Acme",
  "description": "A compact configurable clock for the Omarchy bar.",
  "license": "MIT",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "Widget.qml"
  },
  "barWidget": {
    "displayName": "Cool Clock",
    "description": "Shows the current time with a configurable format.",
    "category": "Time",
    "allowMultiple": false,
    "defaults": {
      "format": "HH:mm",
      "showSeconds": false
    },
    "schema": [
      {
        "key": "format",
        "type": "string",
        "label": "Format",
        "defaultValue": "HH:mm"
      },
      {
        "key": "showSeconds",
        "type": "boolean",
        "label": "Show seconds",
        "defaultValue": false
      }
    ]
  }
}
```

## Panel Manifest Example

```json
{
  "schemaVersion": 1,
  "id": "acme.quick-notes",
  "name": "Quick Notes",
  "version": "1.0.0",
  "author": "Acme",
  "description": "A summoned notes panel.",
  "license": "MIT",
  "kinds": ["panel"],
  "keepLoaded": true,
  "entryPoints": {
    "panel": "Panel.qml"
  }
}
```

## Service Plus Bar Widget Manifest Example

```json
{
  "schemaVersion": 1,
  "id": "acme.media-helper",
  "name": "Media Helper",
  "version": "1.0.0",
  "author": "Acme",
  "description": "A background media service with a bar widget.",
  "license": "MIT",
  "kinds": ["service", "bar-widget"],
  "keepLoaded": true,
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Media Helper",
    "description": "Shows current playback status.",
    "category": "Media",
    "allowMultiple": false
  }
}
```
