# Publishing And Validation

Use this reference when publishing a plugin repository, documenting installation and updates, changing versions, validating a release, or writing security notes.

## Publishing Model

The installable unit is one Git repository containing one plugin. Its `manifest.json` must be at the repository root:

```text
cool-clock/
  .git/
  manifest.json
  Widget.qml
  README.md
```

`omarchy plugin add <git-url>` clones that repository and validates its root. The command cannot select a plugin subdirectory from a remote monorepo.

This repository is the one intentional dual-purpose case:

- The root is the installable `b.okomart` plugin, published at
  `https://github.com/brianblakely/omarchy-plugins.git`.
- `plugins.txt` lists locally curated installable plugin repositories by their
  canonical public HTTPS `.git` URLs.
- Okomart also imports compatible standalone repositories from the HANCORE
  marketplace registry, with local URLs taking precedence when the sources
  overlap.

Installing Okomart does not install or embed a catalog repository. The current
CLI still cannot select a plugin subdirectory from a remote repository. Publish
catalog installation commands only with the real standalone URL from the
merged catalog; do not substitute the Okomart catalog URL, sparse-checkout
recipe, synthetic source id, or undocumented subdirectory syntax.

## Install And Enable

Current Omarchy accepts a Git URL directly:

```bash
omarchy plugin add <plugin-git-url>
```

In an interactive terminal, Omarchy confirms the clone and then asks whether to enable the plugin. Review the repository before installing it, then accept the enable prompt when the plugin should run immediately.

Enabling a bar widget during installation adds it to the right bar section. Move it afterward when another placement is required:

```bash
omarchy bar plugin move <plugin-id> --section center
```

Enabling a `bar` plugin selects it as the active full-bar implementation. It can also be selected later with:

```bash
omarchy bar use <plugin-id>
```

For an unattended, trusted install that should run immediately:

```bash
omarchy plugin add <plugin-git-url> --enable --yes
```

With `--yes` or without an interactive terminal, `add` defaults to disabled unless `--enable` is supplied.

The current CLI has no source registry, source id, available-plugin catalog, `--from`, `--review`, or add-time `--ref` option.

## Updates

Common update commands are:

```bash
omarchy plugin update <plugin-id>
omarchy plugin update --all
```

For each Git-managed plugin, update fetches `origin`'s current `HEAD`, compares it with the installed commit, shows the diff and asks for confirmation in an interactive run, then performs a fast-forward-only merge. It validates the updated checkout and rolls back the merge if validation fails. After one or more successful updates, the shell rescans plugins.

Use `--yes` only when intentionally skipping diff review:

```bash
omarchy plugin update <plugin-id> --yes
omarchy plugin update --all --yes
```

Local divergence or a non-fast-forward update is rejected. The normal update command follows the remote's current `HEAD`; it does not maintain a catalog ref or select a subdirectory. An author who documents a manually pinned ref must also document that its maintenance is ordinary Git work inside the installed checkout and is outside the standard update flow.

## Versioning

The manifest `version` remains required release metadata. Use predictable versions such as:

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

Bump `manifest.json` for a published change users should receive, as required by this repository's release policy. Current Omarchy delivery is Git-commit based: `plugin update` compares and fast-forwards commits, not manifest versions.

## Install Behavior And Security Model

The installer:

- Clones the repository into a hidden staging directory.
- Validates the repository root.
- Moves the checkout to `~/.config/omarchy/plugins/<manifest-id>/`.
- Rescans the shell.
- Enables the plugin only when requested or confirmed.

It does not run plugin code during the clone/validation step, execute install hooks, or require `sudo`.

Do not design a plugin that needs a post-install script to become structurally valid. Put every required QML file and asset inside the repository, and do not include symlinks.

Once enabled, plugins run unsandboxed inside the long-lived `omarchy-shell` process. Document meaningful behavior clearly in the plugin README, especially:

- External commands executed.
- Files read or written.
- Network access.
- Background services.
- IPC or global-shortcut endpoints.
- User configuration required outside the plugin repository.

Plugin rescans and configuration watching normally reload plugin-backed UI. Do not tell users to restart the shell unless the plugin actually requires it and that behavior has been verified against the current checkout.

## Validation

Validate a published repository from its root:

```bash
omarchy plugin validate .
```

Validate Okomart from this repository root:

```bash
omarchy plugin validate .
```

Validate each locally curated catalog plugin from the root of its standalone
repository before adding its URL to `plugins.txt`. Externally sourced entries
must satisfy the HANCORE registry's one-root-plugin contract before Okomart
imports them. For local `plugins.txt` entries, the README generator requires
nonblank `name`, `author`, and `description` strings, but that metadata check is
not a substitute for `omarchy plugin validate .`. External entries are not
included in the README table.

The current validator checks:

- Valid JSON and numeric `schemaVersion: 1`.
- Required `id`, `name`, `version`, `kinds`, and `entryPoints` fields.
- A non-empty kinds array and an entry-points object.
- A valid, non-reserved id that does not collide with first-party plugins.
- Safe relative entry-point paths that exist inside the plugin.
- The absence of symlinks anywhere outside Git internals.

Validation proves structural compatibility; it does not prove that QML loads successfully or that runtime behavior is safe. Exercise the plugin in the current shell as part of release testing.

When validating against a source checkout instead of the installed Omarchy version, run that checkout's command and point `OMARCHY_PATH` at it:

```bash
PATH=/path/to/omarchy/bin:$PATH \
  OMARCHY_PATH=/path/to/omarchy \
  /path/to/omarchy/bin/omarchy-plugin validate .
```

Use the same command from a catalog plugin's standalone checkout when validating
that plugin against a source Omarchy checkout.

## Recommended README Install Section

Use the actual per-plugin Git URL and manifest id when filling in this template:

````markdown
## Install

Review the repository, then add the plugin:

```bash
omarchy plugin add <actual-plugin-git-url>
```

Accept the prompt to enable the plugin during installation.

For an unattended install from a repository you already trust:

```bash
omarchy plugin add <actual-plugin-git-url> --enable --yes
```

## Update

Review and apply the next fast-forward update:

```bash
omarchy plugin update acme.cool-clock
```

Or update all Git-managed plugins:

```bash
omarchy plugin update --all
```

## Validate from source

```bash
omarchy plugin validate .
```

## Security

This plugin runs unsandboxed inside `omarchy-shell` when enabled. Review its
source and the documented command, file, and network behavior before installing it.
````

Replace every angle-bracket placeholder before publishing. The finished plugin
README should contain a real URL and copy-pastable commands. The catalog URL is
correct only for Okomart itself; use each plugin's standalone URL from the
merged catalog for catalog plugins.

## Pre-Publish Checklist

Before announcing or tagging a release, verify:

- [ ] The published repository has one plugin manifest at its root. For
      Okomart, `plugins.txt` contains URL references rather than additional
      plugin manifests.
- [ ] A catalog plugin remains self-contained and valid in its standalone
      repository.
- [ ] The actual public repository URL exists. Only Okomart uses the catalog
      repository URL as its install URL.
- [ ] A locally curated catalog URL is a unique canonical public HTTPS URL
      ending in `.git`, recorded as one nonblank `plugins.txt` line.
- [ ] An externally sourced URL is a compatible root plugin entry in the
      HANCORE marketplace registry and remains unique after normalization with
      the local list.
- [ ] `node scripts/generate-plugin-catalog.mjs` succeeds and the marker-owned
      README table is current.
- [ ] The plugin contains no symlinks, install hooks, post-install scripts, or privileged setup.
- [ ] `schemaVersion` is the JSON number `1`.
- [ ] `id`, `name`, `version`, `kinds`, and `entryPoints` are present.
- [ ] The plugin id is namespaced, does not start with `omarchy.`, and contains neither `/` nor `..`.
- [ ] `kinds` lists only host kinds the plugin actually implements; use `bar-widget` for a component and `bar` only for a complete bar.
- [ ] Every entry point is a safe relative path to an existing file inside the repository.
- [ ] Bar-widget settings use `defaults`, `schema`, and inline shell settings where appropriate.
- [ ] A popup-owning bar-widget root exposes `opened`, `open()`, and `close()` for shell lifecycle routing.
- [ ] Direct bar-widget IPC broadcasts display-state changes that must reach every monitor, without duplicating external side effects.
- [ ] Global keybindings remain user-owned and are documented with current shell IPC or an intentional `GlobalShortcut`.
- [ ] Commands, file access, network access, background behavior, and required user configuration are documented.
- [ ] The manifest `version` has been bumped for the published change.
- [ ] `omarchy plugin validate .` succeeds in the plugin's published
      standalone repository.
- [ ] Runtime QML and every documented action have been exercised against the current Omarchy checkout.
- [ ] A clean user can review the source, add the real Git URL, accept the interactive enable prompt, and update the plugin by id.
- [ ] Automated docs use `--enable --yes` only where immediate execution is intended and trusted.
- [ ] The README does not mention removed source ids, `plugin available`, `--from`, `--review`, or add-time `--ref`.
- [ ] A shell restart is documented only if current runtime testing proves it necessary.
