# Bar Widgets And Settings

Use this reference when changing `barWidget` metadata, settings schema, runtime settings, or QML settings code.

## Bar Widget Metadata

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

## Schema And Plugin Settings

`schema` describes configurable fields. It is metadata for settings UI; it is not the settings storage itself.

Use this mental model:

```text
schema    = describes editable fields
defaults  = suggested/default values
settings  = actual per-instance runtime values
```

For a bar widget, settings are stored inline on that widget's entry in `~/.config/omarchy/shell.json`. There is no separate per-plugin settings file and no required `config` sub-object.

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

## Known Schema Field Types

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

String setting schema:

```json
{
  "key": "format",
  "type": "string",
  "label": "Format",
  "description": "Clock display format.",
  "defaultValue": "HH:mm"
}
```

Integer setting schema:

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

Boolean setting schema:

```json
{
  "key": "showSeconds",
  "type": "boolean",
  "label": "Show seconds",
  "defaultValue": false
}
```

Enum setting schema:

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

Multiselect setting schema:

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

## Reading Settings In QML

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

## Setting Values From The CLI

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

## Saving Settings From QML

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

For `allowMultiple: true` widgets that save settings from their own UI, do not rely on `updateEntryInline` when the setting must change only the clicked instance. In the target shell, `updateEntryInline(moduleName, settings)` matches entries by widget id, so duplicate instances share that id. A more resilient plugin-only pattern is to persist a generated `instanceId` inline on the entry, then use `bar.shell.mutateShellConfig(...)` to find that `instanceId` and update only that entry. The first write may still need to locate the current bar slot section/index to bootstrap `instanceId`, unless the shell exposes a dedicated current-entry save API.

For non-bar plugins, the documented storage model also uses top-level `plugins[]` entries in `shell.json` with settings inline on the entry. However, settings injection is clearly implemented for bar widget slots in the target commit. For third-party portability, prefer the bar-widget settings pattern unless upstream loader behavior has been verified.

## Valid Category Values

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
