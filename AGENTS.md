This repository is the Okomart Omarchy plugin and its merged catalog of
third-party plugin URLs. Treat this file as the starting map, not the full
reference.

Target Omarchy reference:

- Plugin system source commit: <https://github.com/basecamp/omarchy/commit/248659de5a4ce1364703601a70b56624e9817c46>
- Omarchy shell reference: <https://github.com/basecamp/omarchy/tree/quattro/shell>

## First Rules

When editing this project:

1. Treat the repository root as the installable `b.okomart` plugin. It is also the catalog repository at `https://github.com/brianblakely/omarchy-plugins.git`.
2. Treat each nonblank line in `plugins.txt` as a locally curated canonical
   public HTTPS `.git` URL of one independently published plugin repository.
   Keep URLs unique and do not add embedded plugin source folders.
3. Merge the compatible standalone entries from the HANCORE marketplace
   `registry.json` into the local URLs. Local entries win on overlap; normalize
   and deduplicate GitHub repository URLs before fetching plugin repositories.
   Do not import suites, multi-plugin repositories, manual-install entries, or
   Okomart itself.
4. Keep every catalog plugin self-contained and structurally valid in its own
   standalone repository, with `manifest.json` at that repository's root.
5. Do not invent unsupported `manifest.json` fields.
6. Do not add symlinks, install hooks, post-install scripts, privileged setup, or automatic keybinding mutation.
7. Keep global keybindings user-owned and documented explicitly.
8. Bump the relevant standalone repository's `manifest.json` `version` for
   published plugin changes as release metadata. Current
   `omarchy plugin update` fast-forwards the installed Git checkout; it does
   not compare manifest versions.
9. Validate Okomart changes with `omarchy plugin validate .`. Validate a
   changed or publishable catalog plugin from that plugin's standalone
   repository.
10. Keep README examples copy-pastable and explicit about the real Git URL, plugin id, source review, the interactive enable prompt, and updates. Okomart uses this repository's real URL; do not invent a URL for a catalog plugin before its standalone repository exists.
11. Regenerate the marker-owned README catalog with
    `node scripts/generate-plugin-catalog.mjs` after changing `plugins.txt`.
    The README table contains only `plugins.txt`; the external registry is a
    runtime catalog source and must not feed the README generator. Do not edit
    generated table rows by hand.

## Documentation Map

| Read this | When you need |
| --- | --- |
| [Plugin Structure And Manifest](docs/plugin-structure-and-manifest.md) | Repository layout, filesystem safety, manifest fields, plugin ids, supported kinds, and manifest examples. |
| [Bar Widgets And Settings](docs/bar-widgets-and-settings.md) | `barWidget` metadata, settings schema, inline settings, QML reads/writes, CLI setting commands, and categories. |
| [Keybindings](docs/keybindings.md) | User-owned Hyprland bindings, Omarchy shell IPC, and when to use Quickshell `GlobalShortcut`. |
| [Publishing And Validation](docs/publishing-and-validation.md) | Standalone plugin repositories, install/update commands, refs, versioning, security notes, README install sections, validation, and release checklist. |

## Fast Path

For most plugin edits:

1. Decide whether the change belongs to root Okomart, the local `plugins.txt`
   registry, the external-registry integration, or a plugin's separate
   repository, then inspect the relevant `manifest.json`.
2. Check the relevant doc above before changing manifest fields, settings, keybindings, or publishing instructions.
3. Keep behavior documented if the plugin runs commands, reads or writes files, uses network access, registers shortcuts, or needs user configuration.
4. Run `omarchy plugin validate .` for Okomart. Validate each changed catalog
   plugin in its own checkout before calling it publishable.

## When Unsure

Do not guess whether a manifest feature, schema field, category, keybinding method, or settings behavior is supported. Inspect the target Omarchy version first, then update these docs and the plugin implementation together.
