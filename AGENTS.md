This file gives coding agents the project rules for creating, validating, documenting, and publishing third-party Omarchy plugins. It is based on Omarchy commit `1bb439476af2a7b2bdee03c682ae002655c3523c`, which introduced plugin sources, discovery, installation, updating, removal, validation, plugin settings metadata, and shell IPC workflows.

Source reference: <https://github.com/basecamp/omarchy/commit/1bb439476af2a7b2bdee03c682ae002655c3523c>

Omarchy shell reference: <https://github.com/basecamp/omarchy/tree/omarchy-4/shell>

## Working principles for agents

When editing this project:

1. Treat Omarchy plugins as Git-published source folders, not package artifacts.
2. Keep every plugin self-contained in its own top-level directory.
3. Do not invent unsupported manifest fields.
4. Validate each plugin with `omarchy plugin validate ./<plugin-folder>` before considering it publishable.
5. Prefer explicit, user-owned keybinding instructions over automatic keybinding mutation.
6. Never add install hooks, post-install scripts, or privileged setup requirements to the plugin publishing flow.
7. Bump the manifest `version` whenever a published change should be picked up by `omarchy plugin update`.
8. Keep README examples copy-pastable and explicit about source id, plugin id, review, enablement, and updates.

## Repository structure

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

## Filesystem safety rules

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

## Manifest requirements

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

### Valid plugin ids

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

## Supported plugin kinds

The supported kinds in this Omarchy plugin system are:

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

## Bar widget manifest example

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

## Panel manifest example

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

## Service plus bar widget manifest example

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

## Bar widget metadata

A `barWidget` metadata block may include fields such as:

```json
"barWidget": {
  "displayName": "Cool Clock",
  "description": "Shows the current time.",
  "category": "Time",
  "allowMultiple": false,
  "defaults": {},
  "schema": []
}
```

Meaning:

- `displayName`: Human-facing widget name.
- `description`: Human-facing description.
- `category`: UI grouping metadata for the widget picker/settings surface.
- `allowMultiple`: Whether more than one instance of the widget should be allowed in the bar.
- `defaults`: Default settings values for the widget.
- `schema`: Settings UI metadata describing editable fields.

## `schema` and plugin settings

`schema` describes configurable fields. It is metadata for settings UI; it is not the settings storage itself.

Use this mental model:

```text
schema    = describes editable fields
defaults  = suggested/default values
settings  = actual per-instance runtime values
```

For a bar widget, settings are stored inline on that widget’s entry in `~/.config/omarchy/shell.json`. There is no separate per-plugin settings file and no required `config` sub-object.

Example bar layout entry:

```json
{
  "id": "acme.cool-clock",
  "format": "HH:mm",
  "showSeconds": false
}
```

For that instance, the settings object exposed to the widget is effectively:

```json
{
  "format": "HH:mm",
  "showSeconds": false
}
```

The bar model copies all entry keys except `id` into the widget settings object.

### Known schema field types

The first-party manifests in the target commit use these schema field `type` values:

| Type | Use |
| --- | --- |
| `string` | Text input values. |
| `integer` | Numeric values, commonly with `min`, `max`, `step`, and `defaultValue`. |
| `boolean` | True/false toggles. |
| `enum` | One value from a fixed options list. |
| `multiselect` | Multiple values from a fixed options list. |
| `path` | Filesystem path-style input. |

These are the known practical values from the commit. Do not assume additional types unless upstream code is verified.

### String setting schema

```json
{
  "key": "format",
  "type": "string",
  "label": "Format",
  "description": "Clock display format.",
  "defaultValue": "HH:mm"
}
```

### Integer setting schema

```json
{
  "key": "refreshIntervalSec",
  "type": "integer",
  "label": "Refresh interval",
  "description": "How often to refresh, in seconds.",
  "min": 5,
  "max": 300,
  "step": 5,
  "defaultValue": 30
}
```

### Boolean setting schema

```json
{
  "key": "showSeconds",
  "type": "boolean",
  "label": "Show seconds",
  "defaultValue": false
}
```

### Enum setting schema

```json
{
  "key": "mode",
  "type": "enum",
  "label": "Mode",
  "defaultValue": "compact",
  "options": [
    { "value": "compact", "label": "Compact" },
    { "value": "detailed", "label": "Detailed" }
  ]
}
```

### Multiselect setting schema

```json
{
  "key": "items",
  "type": "multiselect",
  "label": "Items",
  "options": [
    { "value": "cpu", "label": "CPU" },
    { "value": "memory", "label": "Memory" },
    { "value": "network", "label": "Network" }
  ]
}
```

## Reading settings in QML

Bar widgets should use the `BarWidget` base item when practical. It provides `bar`, `moduleName`, `settings`, and a helper function `setting(name, fallback)`.

Example:

```qml
import QtQuick
import qs.Ui

BarWidget {
  id: root

  readonly property string format: setting("format", "HH:mm")
  readonly property bool showSeconds: setting("showSeconds", false) === true

  Text {
    text: root.showSeconds ? "12:34:56" : "12:34"
  }
}
```

## Setting values from the CLI

For bar widgets, settings can be changed with:

```bash
omarchy plugin bar set acme.cool-clock format HH:mm
omarchy plugin bar set acme.cool-clock showSeconds false --json
```

Use `--json` for booleans, numbers, arrays, and objects. Without `--json`, the value is stored as a string.

Array example:

```bash
omarchy plugin bar set acme.system items '["cpu","memory","network"]' --json
```

Object example:

```bash
omarchy plugin bar set acme.widget options '{"compact":true,"limit":5}' --json
```

## Saving settings from QML

A widget can persist updated settings by calling:

```qml
bar.shell.updateEntryInline(moduleName, settings)
```

Example:

```qml
import QtQuick
import qs.Ui

BarWidget {
  id: root

  function saveSettings(format, showSeconds) {
    const next = {
      format: String(format || "HH:mm"),
      showSeconds: showSeconds === true
    }

    root.settings = next

    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, next)
  }
}
```

`updateEntryInline` rewrites the inline entry in `shell.json`, preserving `id` and replacing the other keys with the supplied settings object.

For non-bar plugins, the documented storage model also uses top-level `plugins[]` entries in `shell.json` with settings inline on the entry. However, settings injection is clearly implemented for bar widget slots in the target commit. For third-party portability, prefer the bar-widget settings pattern unless upstream loader behavior has been verified.

## Valid `category` values

`category` is not validated against a fixed enum in the target commit. Omarchy reads it as metadata and falls back to `"Plugin"` when omitted.

Use existing first-party categories for UI consistency:

```text
AI
Audio
Compositor
Info
Layout
Media
Network
Status
System
Time
Plugin
```

Recommended behavior:

- Use `Time` for clocks, calendars, timers, or date display.
- Use `System` for CPU, memory, battery, power, or host information.
- Use `Network` for network, VPN, Bluetooth, or connectivity UI.
- Use `Media` for playback controls or now-playing UI.
- Use `Audio` for microphone, volume, and audio-device UI.
- Use `Status` for status indicators.
- Use `Info` for weather or passive informational widgets.
- Use `AI` for model or AI-assistant usage widgets.
- Use `Layout` for spacers or layout-only widgets.
- Omit `category` or use `Plugin` for generic third-party widgets that do not fit another category.

Example:

```json
"barWidget": {
  "displayName": "Cool Clock",
  "category": "Time",
  "allowMultiple": false
}
```

## Global keybindings

Plugins do not declare global keybindings in `manifest.json`. Do not add fields such as `shortcuts`, `keybindings`, or `accelerators` unless upstream Omarchy explicitly adds support.

The installer does not automatically mutate Hyprland config. Key ownership should remain with the user.

### Recommended pattern: document a Hyprland binding to Omarchy IPC

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

### Alternative pattern: Quickshell `GlobalShortcut`

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

## Publishing a source repository

Users add a trusted plugin source with:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme
```

They can browse available plugins with:

```bash
omarchy plugin available
```

They can install a plugin with review and enablement:

```bash
omarchy plugin add acme.cool-clock --from acme --review --enable
```

Non-interactive example:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --yes
omarchy plugin add acme.cool-clock --from acme --enable --yes
```

When `omarchy plugin add` runs with `--yes` or non-interactively and no enable flag is provided, it installs without enabling by default. Include `--enable` in unattended install docs when the intended result is an enabled plugin.

If the same plugin id exists in multiple trusted sources, users must pass `--from <source-id>` to disambiguate.

## Source ids

A source id is the local name users assign to a plugin source repo with `--as`.

Good source ids:

```text
acme
acme-plugins
jane.omarchy
```

Rules:

- Lowercase only.
- Start with a lowercase letter or digit.
- Contain only lowercase letters, digits, `.`, `_`, and `-`.
- Must not contain `..`.
- Must not contain `/`.

Invalid source ids:

```text
Acme
acme/plugins
../acme
```

Use a stable `--as` value in documentation so users get predictable commands:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme
omarchy plugin add acme.cool-clock --from acme
```

## Refs and branches

A source can be pinned with `--ref`:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --ref main
```

or:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --ref v1
```

The source command uses a shallow clone and passes `--branch <ref>` when a ref is supplied. Prefer documenting branch or tag names rather than raw commit hashes.

## Versioning and updates

Omarchy update detection compares the installed manifest `version` to the source manifest `version` using version sorting.

Use predictable version strings such as:

```text
1.0.0
1.0.1
1.1.0
2.0.0
```

or date-style versions:

```text
2026.06.01
2026.06.15
```

When publishing any change that users should receive through `omarchy plugin update`, update the manifest `version`.

Common user update commands:

```bash
omarchy plugin update acme.cool-clock
```

```bash
omarchy plugin update --all
```

Updates reinstall from the trusted source folder. Enabled state is preserved. Enabled plugins may require an Omarchy shell restart to fully reload.

## Install behavior and security model

The installer validates the manifest, copies plugin files, rescans plugins, and toggles enabled state through shell IPC. It does not run plugin code during installation, does not run install hooks, and does not require `sudo`.

Do not design a plugin that needs a post-install script to become structurally valid. Put all required QML and assets inside the plugin folder.

Once enabled, plugins run unsandboxed inside the long-lived `omarchy-shell` process. Document meaningful behavior clearly in the plugin README, especially:

- External commands executed.
- Files read or written.
- Network access.
- Background services.
- Global shortcut endpoints.
- User configuration changes required outside the plugin folder.

## Validation

Validate each plugin directory before publishing:

```bash
omarchy plugin validate ./cool-clock
omarchy plugin validate ./quick-notes
omarchy plugin validate ./media-helper
```

Validation should succeed for every plugin folder in the repository.

CI-style loop from the repository root:

```bash
set -euo pipefail

for manifest in ./*/manifest.json; do
  plugin_dir="$(dirname "$manifest")"
  omarchy plugin validate "$plugin_dir"
done
```

## Recommended README install section

Use a README section like this for each public plugin source:

````markdown
# Acme Omarchy Plugins

## Plugins

### acme.cool-clock

A compact configurable clock for the Omarchy bar.

Kinds: `bar-widget`
Version: `1.0.0`

## Install

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme
omarchy plugin available
omarchy plugin add acme.cool-clock --from acme --review --enable
```

For unattended installs:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --yes
omarchy plugin add acme.cool-clock --from acme --enable --yes
```

## Update

```bash
omarchy plugin update acme.cool-clock
```

or update all installed plugins with available updates:

```bash
omarchy plugin update --all
```

## Optional keybinding

```lua
o.bind("SUPER + N", "Quick Notes", "omarchy-shell shell toggle acme.quick-notes")
```

## Validate from source

```bash
omarchy plugin validate ./cool-clock
```

## Notes

Plugins run inside `omarchy-shell`. Review plugin files before enabling.
````

## Pre-publish checklist

Before announcing or tagging a release, verify:

- [ ] The repository has one immediate top-level folder per plugin.
- [ ] Each plugin folder contains `manifest.json`.
- [ ] No plugin folder contains symlinks.
- [ ] `schemaVersion` is the JSON number `1`.
- [ ] `id`, `name`, `version`, `kinds`, and `entryPoints` are present.
- [ ] The plugin id is namespaced and does not start with `omarchy.`.
- [ ] The plugin id does not contain `/` or `..`.
- [ ] `kinds` contains only kinds the plugin actually implements.
- [ ] Third-party bar widgets use `bar-widget`, not `bar`.
- [ ] Every entry point is a safe relative path to an existing file inside the plugin folder.
- [ ] Bar widget settings are represented by `defaults`, `schema`, and inline shell settings.
- [ ] `category` uses an existing category where possible, or falls back to `Plugin` by omission.
- [ ] Global keybindings are documented as user-owned Hyprland bindings or registered `GlobalShortcut` endpoints.
- [ ] No install hook or post-install script is required.
- [ ] Any published behavior involving external commands, files, or network access is documented.
- [ ] The manifest `version` has been bumped for user-visible publishable changes.
- [ ] `omarchy plugin validate ./<plugin-folder>` exits successfully for each plugin.
- [ ] A clean user can run source add, available, add with review, enable, and update successfully.

## Default agent response when unsure

When unsure whether a manifest feature, schema field, category, keybinding method, or settings behavior is supported, do not guess. Inspect the target Omarchy version first, then update this file and the plugin implementation together.
