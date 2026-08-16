# Plugin Structure And Manifest

Use this reference when creating or changing plugin folders, entry points, manifest fields, plugin ids, or plugin kinds.

## Repository Structure

An installable Omarchy plugin is one Git repository with `manifest.json` at the repository root. `omarchy plugin add <git-url>` clones that repository and validates its root as one plugin.

This repository deliberately has two layers. Its root is the installable
`b.okomart` plugin and the repository also acts as Okomart's local catalog.
`plugins.txt` lists locally curated, independently installable plugin
repositories by URL:

```text
omarchy-plugins/
  manifest.json
  Service.qml
  Okomart.qml
  plugins.txt
  README.md
  AGENTS.md
  scripts/
    generate-plugin-catalog.mjs
```

The root repository is a valid argument to `omarchy plugin add` because it is
exactly one plugin: Okomart. Installing it does not install the catalog entries.
The installer still cannot select a subdirectory from a remote repository.
Every locally curated catalog entry therefore needs its own real Git URL in
`plugins.txt`, and its manifest must remain at that repository's root. Do not
add or document a per-plugin URL until that standalone repository actually
exists.

The local registry format is deliberately small and strict: one canonical
public HTTPS URL ending in `.git` per line, no blank lines, and no duplicates.
Okomart merges those URLs with the compatible entries from the HANCORE
marketplace's public
[`registry.json`](https://raw.githubusercontent.com/HANCORE-linux/omarchy-plugin-marketplace/refs/heads/main/registry.json).
It imports only `plugin-source` entries that describe one root plugin and do
not declare manual installation, and it excludes shell suites, multi-plugin
repositories, nested manifests, and Okomart itself. HANCORE GitHub repository
root URLs are normalized to HTTPS `.git` clone URLs.

The local list is merged first, so it wins when both sources name the same
GitHub repository. GitHub repository identity is compared case-insensitively
after clone-URL normalization, and each effective URL is fetched only once.
Actual installation uses that deduplicated standalone URL.

The marker-owned README catalog documents only the locally curated
`plugins.txt` entries; external runtime entries are intentionally not mirrored
into the README. `node scripts/generate-plugin-catalog.mjs` clones each local
URL, reads the root manifest's `name`, `author`, and `description`, validates
those fields, escapes them for a Markdown table, and replaces only the
generated region.

Installed plugins live at `~/.config/omarchy/plugins/<id>/`. The destination
name is determined by `manifest.id`, not by the remote repository or local
checkout directory name. Prefer repository names that clearly correspond to
the plugin, but do not rely on them as identity.

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
