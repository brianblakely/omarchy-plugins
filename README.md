# Okomart

"Okonomi" roughly translates to "as you like," and refers to the single items
you may order after your
[omakase meal](https://learn.omacom.io/3/omacom/76/omakase-computing).

Okomart (`オコマート`) is a storefront for Omarchy plugins. It lets you browse
the catalog in this repository, inspect plugin metadata and screenshots, and
install, update, or remove plugins without leaving the Omarchy shell.

The repository has two roles:

- Its root is the installable `b.okomart` Omarchy plugin.
- `plugins.txt` is the catalog registry. Each line is the HTTPS `.git` URL of
  one independently published Omarchy plugin repository.

## Install

Plugins run unsandboxed inside the long-lived `omarchy-shell` process. Review
this repository before installing it, then add Okomart from its real Git URL:

```bash
omarchy plugin add https://github.com/brianblakely/omarchy-plugins.git
```

Accept the interactive prompt to enable Okomart. For an unattended installation
from a repository you already trust:

```bash
omarchy plugin add https://github.com/brianblakely/omarchy-plugins.git --enable --yes
```

When enabled, Okomart atomically installs its marked desktop entry at
`${XDG_DATA_HOME:-$HOME/.local/share}/applications/b.okomart.desktop`. Launch
**Okomart** like any other application, or summon it directly:

```bash
omarchy-shell shell summon b.okomart
```

Ordinary shell and plugin reloads retain the desktop entry. When
`omarchy-shell` is running, disabling or removing Okomart removes the launcher
only when it still carries Okomart's ownership marker. Okomart refuses to
overwrite or remove an existing unmarked launcher at the same path.

Omarchy cannot run plugin cleanup code when Okomart is removed while
`omarchy-shell` is stopped or unreachable. In that case the marked launcher may
remain visible until it is selected. Selecting it verifies that
`~/.config/omarchy/plugins/b.okomart/manifest.json` is gone, removes only the
marked regular launcher file, and exits without contacting `omarchy-shell`.

The launcher summons a `FloatingWindow` hosted by the existing Quickshell
process; Okomart therefore shares `omarchy-shell`'s compositor and task-switcher
identity rather than starting a second standalone GUI process.

## Using Okomart

Opening Okomart refreshes this repository's URL registry, checks each registered
repository, and detects catalog additions, removals, and changed plugin commits.
The storefront combines that catalog with third-party plugins already installed
under `~/.config/omarchy/plugins/`.

- Search matches substrings in plugin names, descriptions, and authors.
- The Installed filter limits the list to local plugins.
- Plugin details show manifest metadata, installation state, actions, and any
  images in the plugin's immediate `images/` directory.
- One image is displayed directly. Multiple images form a carousel in natural
  alphanumeric filename order. An absent image directory simply omits the
  screenshot section.
- The Updates button lists safe updates and any detected dirty or diverged
  updates that cannot be applied automatically, then requests confirmation.
- Install and update confirmations freeze the package set and source metadata
  from the catalog snapshot shown. If another refresh replaces that snapshot
  before the action is queued, Okomart refuses the action and asks for a fresh
  review.

Okomart delegates changes to Omarchy's supported commands:

```text
omarchy plugin add <plugin-git-url> --enable --yes
omarchy plugin update <plugin-id> --yes
omarchy plugin remove <plugin-id> --yes
```

It does not use `sudo`, installation hooks, post-install scripts, or automatic
global keybindings.

For safety, Okomart disables uninstalling a Git-managed plugin while its
checkout has local changes. Commit, stash, or discard those changes before
removing it. Omarchy's existing backup behavior remains available for non-Git
local plugin folders.

### Keyboard controls

- `Tab` / `Shift+Tab`: move between controls
- `Up` / `Down`, `Page Up` / `Page Down`, `Home` / `End`: navigate plugins while
  the plugin list is focused
- `Page Up` / `Page Down`, `Home` / `End`: scroll plugin details or a
  confirmation/results list while that pane is focused
- `Enter` / `Space`: activate the focused control
- `/` or `Ctrl+F`: focus search
- `Ctrl+R`: refresh the catalog
- `Left` / `Right`: move through screenshots while the carousel is focused
- `Esc`: close a dialog, return from narrow details, clear search, or close
  Okomart, in that order

## Network, files, and state

Okomart uses Git network access when it refreshes the registry, reads registered
plugin repositories, or checks Git remotes for updates. A failed refresh keeps
the last valid catalog available and shows its stale/offline state.

It reads plugin manifests, immediate `images/` directories, Git metadata,
`~/.config/omarchy/plugins/`, and `~/.config/omarchy/shell.json`. It maintains:

- Disposable catalog trees and depth-one Git mirrors below
  `${XDG_CACHE_HOME:-$HOME/.cache}/okomart/`.
- The last valid catalog index and action results under
  `${XDG_STATE_HOME:-$HOME/.local/state}/okomart`.
- The marker-owned desktop entry under
  `${XDG_DATA_HOME:-$HOME/.local/share}/applications/`.

The launcher and its service use `bash`, `jq`, and standard user-space file
utilities (`grep`, `install`, `mkdir`, `mktemp`, `mv`, `rm`, and `sleep`) to
install the entry atomically, verify ownership and enabled state before
cleanup, and make a launcher left by an offline removal self-cleaning. The
catalog helper additionally uses `git`, `flock`, `realpath`, `find`, `sort`,
`tar`, and common core utilities. It uses `timeout` for bounded Git operations
and plugin mutations; a timed-out mutation is reported as potentially partial
and forces a fresh catalog and installation-state review before retrying.

Plugin mutations run in a locked, detached worker copied under Okomart's state
directory, using `setsid` when available and `nohup` otherwise. This lets an
update safely unload Okomart while work continues. The worker records
per-package output, continues past individual update failures, updates Okomart
itself last, and re-summons the storefront when finished. Actual mutations are
still delegated to the documented `omarchy plugin` commands.

Installed plugins are arbitrary, unsandboxed code. Before approving an install
or update, review its source URL and changes. Okomart's confirmations do not
turn third-party plugins into sandboxed applications. The supported Omarchy add
and update commands resolve a repository's current default-branch `HEAD` when
they run; they do not accept a pinned commit. An upstream repository can
therefore advance after Okomart refreshes its catalog.

## Update and remove

Review and apply Okomart's next fast-forward update:

```bash
omarchy plugin update b.okomart
```

Remove Okomart and disable its shell entry:

```bash
omarchy plugin remove b.okomart
```

## Catalog repositories

`plugins.txt` is the source of truth for this table. The generator clones every
registered URL and requires a root manifest with nonblank `name`, `author`, and
`description` strings. Do not edit the marker-owned table by hand.

<!-- BEGIN GENERATED PLUGIN CATALOG -->
<!-- Generated by scripts/generate-plugin-catalog.mjs from plugins.txt. -->

| Plugin                                                   | Author        | Description                                                                                                                                                                                        |
| -------------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Blink](https://github.com/brianblakely/blink.git)       | Brian Blakely | Blink briefly flashes a border over the active Hyprland window. It runs automatically when the active window changes and can also be triggered on demand.                                          |
| [Omacal](https://github.com/brianblakely/omacal.git)     | Brian Blakely | Omarchy-native day/time label with a mini calendar popup                                                                                                                                           |
| [OmaHUD](https://github.com/brianblakely/omahud.git)     | Brian Blakely | Flashes a discreet Hyprland workspace indicator when you switch workspaces. It's designed for people who hide their Omarchy bar most of the time, and would like help navigating their workspaces. |
| [OmaLED](https://github.com/brianblakely/omaled.git)     | Brian Blakely | Dim the Omarchy bar when not in use                                                                                                                                                                |
| [Omanews](https://github.com/brianblakely/omanews.git)   | Brian Blakely | Omarchy-native headline ticker for the bar                                                                                                                                                         |
| [Omanote](https://github.com/brianblakely/omanote.git)   | Brian Blakely | Omarchy-native secure scratch note for the bar                                                                                                                                                     |
| [Omasnap](https://github.com/brianblakely/omasnap.git)   | Brian Blakely | Screenshot and screen recording overlay for Omarchy                                                                                                                                                |
| [Omastonk](https://github.com/brianblakely/omastonk.git) | Brian Blakely | Omarchy bar widget for a selected market symbol                                                                                                                                                    |
| [Peek](https://github.com/brianblakely/peek.git)         | Brian Blakely | Fades floating Hyprland windows to minimal opacity so you can see and interact with the content underneath                                                                                         |

<!-- END GENERATED PLUGIN CATALOG -->

## Development and validation

Add one canonical public HTTPS URL ending in `.git` per line to `plugins.txt`.
Blank lines and duplicate URLs are invalid. Regenerate the catalog table locally
after changing the registry:

```bash
node scripts/generate-plugin-catalog.mjs
```

Each clone has a 60-second timeout. Set `OKOMART_CATALOG_CLONE_TIMEOUT_SECONDS`
to an integer from 1 through 600 when a different per-repository limit is
needed.

The `Update plugin catalog` workflow runs the same generator after a
`plugins.txt` push and commits only `README.md` when its table changes.

Validate Okomart against the target Omarchy installation:

```bash
omarchy plugin validate .
```

Validate each catalog plugin from its own standalone repository before adding
its URL. Catalog generation validates its documentation metadata, not its QML
entry points or runtime behavior.

Run the complete isolated test suite:

```bash
./tests/all.sh
```

The manifest version is release metadata. Published updates must bump it even
though `omarchy plugin update` delivers commits rather than comparing versions.
