This repository contains third-party Omarchy plugin source folders. Treat this file as the starting map, not the full reference.

Target Omarchy reference:

- Plugin system source commit: <https://github.com/basecamp/omarchy/commit/1bb439476af2a7b2bdee03c682ae002655c3523c>
- Omarchy shell reference: <https://github.com/basecamp/omarchy/tree/omarchy-4/shell>

## First Rules

When editing this project:

1. Treat each plugin as a Git-published source folder, not as a package artifact.
2. Keep each plugin self-contained in one immediate top-level directory.
3. Do not invent unsupported `manifest.json` fields.
4. Do not add symlinks, install hooks, post-install scripts, privileged setup, or automatic keybinding mutation.
5. Keep global keybindings user-owned and documented explicitly.
6. Bump `manifest.json` `version` for published changes users should receive through `omarchy plugin update`.
7. Validate each plugin you change or intend to publish with `omarchy plugin validate ./<plugin-folder>`.
8. Keep README examples copy-pastable and explicit about source id, plugin id, review, enablement, and updates.

## Documentation Map

| Read this | When you need |
| --- | --- |
| [Plugin Structure And Manifest](docs/plugin-structure-and-manifest.md) | Repository layout, filesystem safety, manifest fields, plugin ids, supported kinds, and manifest examples. |
| [Bar Widgets And Settings](docs/bar-widgets-and-settings.md) | `barWidget` metadata, settings schema, inline settings, QML reads/writes, CLI setting commands, and categories. |
| [Keybindings](docs/keybindings.md) | User-owned Hyprland bindings, Omarchy shell IPC, and when to use Quickshell `GlobalShortcut`. |
| [Publishing And Validation](docs/publishing-and-validation.md) | Source ids, install/update commands, refs, versioning, security notes, README install sections, validation, and release checklist. |

## Fast Path

For most plugin edits:

1. Inspect the plugin folder and `manifest.json`.
2. Check the relevant doc above before changing manifest fields, settings, keybindings, or publishing instructions.
3. Keep behavior documented if the plugin runs commands, reads or writes files, uses network access, registers shortcuts, or needs user configuration.
4. Run `omarchy plugin validate ./<plugin-folder>` for each changed plugin before calling it publishable.

## When Unsure

Do not guess whether a manifest feature, schema field, category, keybinding method, or settings behavior is supported. Inspect the target Omarchy version first, then update these docs and the plugin implementation together.
