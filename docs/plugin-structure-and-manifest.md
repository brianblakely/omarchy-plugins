# Plugin Structure And Manifest

Use this reference when creating or changing plugin folders, entry points, manifest fields, plugin ids, or plugin kinds.

## Repository Structure

An Omarchy plugin source repository may contain one or more plugins. Each plugin must be an immediate child directory of the repository root, and each plugin directory must contain its own `manifest.json`.

Recommended shape:

```text
omarchy-plugins/
  README.md
  AGENTS.md

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

Omarchy discovers plugins by scanning immediate child folders of each trusted source clone for `<folder>/manifest.json`. Do not put a plugin manifest at the repository root, and do not bury plugin manifests in nested subdirectories.

The installed plugin directory is determined by `manifest.id`, not by the source folder name. Prefer folder names that match the plugin id or a clear slug, but do not rely on the folder name as identity.

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
| `bar` | Reserved for the first-party Omarchy bar host. |

Third-party plugins should use `bar-widget`, not `bar`. Treat `bar` as reserved for `omarchy.bar`.

Panels, overlays, and menus are generally loaded when summoned. A plugin that must stay alive between summons can use `keepLoaded: true`. A `service` plugin is the preferred always-loaded place for background behavior.

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
