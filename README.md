# Omarchy Plugins

* [Omacal](#omacal) - Drop-in clock replacement with mini calendar
* [Omasnap](#omasnap) - Screenshot and screen recording overlay
* [Omastonk](#omastonk) - Stock tickers in the Omarchy bar, with charts
* [Omanote](#omanote) - Secure scratch note in the Omarchy bar
* [Omanews](#omanews) - Headlines in the Omarchy bar, with instant access to commentary
* [OmaLED](#omaled) - Dim the Omarchy bar when not in use
* [Peek](#peek) - Peek behind floating windows
* [Blink](#blink) - Briefly flash an indicating border over the active window

## Compatibility and publishing

These plugins target Omarchy `quattro` at commit
[`248659de`](https://github.com/basecamp/omarchy/commit/248659de5a4ce1364703601a70b56624e9817c46).

Current Omarchy installs one plugin Git repository at a time and requires
`manifest.json` at that repository's root. This repository is a development
and catalog workspace whose immediate child folders are the individual plugin
source roots; the monorepo itself cannot be passed to `omarchy plugin add`.

Each plugin folder must be published or mirrored as its own Git repository
before it can have a truthful `omarchy plugin add` command.

The old source-catalog commands (`plugin source add`, `plugin available`,
`--from`, and `--review`) no longer exist. Once standalone repository URLs are
published, document their exact URLs here; Omarchy will initially leave the
plugin disabled for review unless the user explicitly enables it, and
`omarchy plugin update <plugin-id>` will fast-forward its installed Git
checkout.

## Omacal

Omacal is a drop-in replacement for the default Omarchy clock that adds a mini calendar. The calendar supports keyboard controls (including vim bindings) for browsing month and year.

![Omacal screenshot](images/omacal.png)

Set `"centerAnchor": "b.omacal"` in `~/.config/omarchy/shell.json` after
installing and enabling the plugin.

### Shortcuts

```lua
hl.unbind("SUPER + CTRL + ALT + T")
o.bind("SUPER + CTRL + ALT + T", "Flash mini calendar", "omarchy-shell b.omacal flash")
o.bind("SUPER + F9", "Toggle mini calendar", "omarchy-shell shell toggle b.omacal")
o.bind("SUPER + ALT + F9", "Open mini calendar", "omarchy-shell shell summon b.omacal")
o.bind("SUPER + CTRL + F9", "Close mini calendar", "omarchy-shell shell hide b.omacal")
```

Right-clicking the clock will allow you to change timezone, exactly like the default Omarchy clock.

## Omasnap

Omasnap is a screenshot and recording tool inspired by [macOS](https://support.apple.com/en-us/102646) and [Spectacle](https://apps.kde.org/spectacle/). It saves to `~/Pictures` by default.

`SPACE` captures the screen, `ENTER` captures the focused window, and `arrow keys` or `HJKL` create and adjust a region by 1px. Hold `SHIFT` to grow the addressed side, or `SHIFT + CTRL` to shrink it. Using the mouse, click the Omarchy Bar to capture the entire screen, click a window to capture it, or drag a region.

Omasnap reads Hyprland's monitor and window state, stores plugin settings
inline in `~/.config/omarchy/shell.json`, and records recent capture state
under `$XDG_STATE_HOME/omasnap`. It runs Omarchy's screen-recording tool plus
`grim`, `slurp`, and `wl-copy`. Recording uses `gpu-screen-recorder`; webcam
overlay recording also uses `v4l2-ctl` and `mpv`. Omasnap does not use the
network.

### Shortcuts

```lua
hl.unbind("PRINT")
o.bind("SUPER + SHIFT + F3", "Omasnap capture screen", "omarchy-shell b.omasnap captureScreen")
o.bind("SUPER + SHIFT + CTRL + F3", "Omasnap capture window", "omarchy-shell b.omasnap captureWindow")
o.bind("SUPER + SHIFT + F4", "Omasnap capture to file", "omarchy-shell b.omasnap captureToFile")
o.bind("SUPER + SHIFT + CTRL + F4", "Omasnap capture to clipboard", "omarchy-shell b.omasnap captureToClipboard")
o.bind("SUPER + SHIFT + F5", "Omasnap", "omarchy-shell b.omasnap show")
o.bind("SUPER + SHIFT + F6", "Omasnap record", "omarchy-shell b.omasnap record")
o.bind("SUPER + SHIFT + CTRL + F6", "Omasnap stop recording", "omarchy-shell b.omasnap stopRecording")
```

## Omastonk

Omastonk is a bar widget for a selected market symbol. It starts with no selected symbol; click the widget to enter one. Each widget instance stores its symbol inline on that bar entry in `~/.config/omarchy/shell.json`, so multiple Omastonk instances can track different symbols.

After a symbol is set, click the bar widget to display the chart panel, which supports keyboard controls (including vim bindings) for switching intervals. Right-click the bar widget to change symbol.

Omastonk uses `curl` to request quote and chart data from Yahoo Finance.

![Omastonk screenshot](images/omastonk.png)

## Omanote

Omanote displays a note icon in the Omarchy bar. Click it or activate a binding to open a scratch note panel.

The note is stored securely with the desktop Secret Service through `secret-tool`, using the attributes `omarchy-plugin=b.omanote` and `field=note`. During automatic saves, Omanote writes the note to a short-lived file in `$XDG_RUNTIME_DIR`, pipes that file into `secret-tool store`, and deletes the runtime file immediately after the keyring store command exits. No note text is stored in `~/.config/omarchy/shell.json`.

Omanote runs `bash` and `secret-tool`. It does not use the network.

![Omanote screenshot](images/omanote.png)

### Shortcuts

```lua
o.bind("SUPER + F8", "Toggle Omanote", "omarchy-shell shell toggle b.omanote")
o.bind("SUPER + ALT + F8", "Open Omanote", "omarchy-shell shell summon b.omanote")
o.bind("SUPER + CTRL + F8", "Close Omanote", "omarchy-shell shell hide b.omanote")
```

## Omanews

Omanews is a headline ticker for the Omarchy bar. It displays top headlines from Google News; additional headlines every 10 minutes. Left-click advances to the next headline, right-click goes to the previous headline, and middle-click opens an X search for the current headline.

Omanews uses `curl` to read Google News RSS and opens X searches in the
default browser.

![Omanews screenshot](images/omanews.png)

### Shortcuts

```lua
o.bind("SUPER + F10", "Next headline", "omarchy-shell b.omanews next")
o.bind("SUPER + ALT + F10", "Previous headline", "omarchy-shell b.omanews previous")
o.bind("SUPER + CTRL + F10", "Search headline on X", "omarchy-shell b.omanews search")
```

## OmaLED

OmaLED heavily dims the Omarchy bar when not in use. The bar will un-dim when the mouse cursor touches the bar or its shortcut is triggered.

**NOTE:** OmaLED will not work when the Omarchy bar's background is transparent
(double-click the bar's background to turn transparency off).

OmaLED polls `hyprctl cursorpos` while its hover overlay is active. Its IPC
settings update the plugin's inline entry in `~/.config/omarchy/shell.json`;
it does not use the network.

![OmaLED screenshot](images/omaled.png)

### Shortcuts

```lua
o.bind("SUPER + CTRL + F11", "Toggle OmaLED", "omarchy-shell b.omaled toggle")
```

## Peek

Fade out floating windows and interact with content below. Bind one of the shortcuts below to use Peek.

Peek runs `hyprctl eval` to install and toggle a runtime Hyprland window rule.
It does not write files or use the network.

![Peek disabled screenshot](images/peek1.png)
![Peek enabled screenshot](images/peek2.png)

### Shortcuts

```lua
o.bind("SUPER + GRAVE", "Toggle floating window peek", "omarchy-shell b.peek toggle")
o.bind("SUPER + ALT + GRAVE", "Enable floating window peek", "omarchy-shell b.peek enable")
o.bind("SUPER + CTRL + GRAVE", "Disable floating window peek", "omarchy-shell b.peek disable")
```

## Blink

Intended for Hyprland setups that remove borders and gaps to maintain a sleek, fullscreen experience. Blink flashes an inset border over the active Hyprland window and then quickly fades it out. It flashes when the active window changes or when triggered by shortcut.

Blink reads active-window state with `hyprctl`; it does not write files or use
the network.

### Shortcuts

```lua
o.bind("SUPER + B", "Blink active window", "omarchy-shell b.blink blink")
```
