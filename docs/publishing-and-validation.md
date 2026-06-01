# Publishing And Validation

Use this reference when updating installation docs, source ids, versioning, validation, security notes, or release checklists.

## Publishing A Source Repository

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

## Source Ids

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

## Refs And Branches

A source can be pinned with `--ref`:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --ref main
```

or:

```bash
omarchy plugin source add https://github.com/acme/omarchy-plugins.git --as acme --ref v1
```

The source command uses a shallow clone and passes `--branch <ref>` when a ref is supplied. Prefer documenting branch or tag names rather than raw commit hashes.

## Versioning And Updates

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

## Install Behavior And Security Model

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

## Recommended README Install Section

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

## Pre-Publish Checklist

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
