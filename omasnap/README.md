# Omasnap

Omasnap is a screenshot and screen-recording overlay inspired by macOS and Spectacle. It saves screenshots to the configured XDG directory, Pictures by default, and recordings to Videos by default.

## Install

Install Omasnap disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/omasnap.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.omasnap
```

Then enable it:

```bash
omarchy plugin enable b.omasnap
```

## Usage

* Press `Space` to capture the screen.
* Press `Enter` to capture the focused window.
* Use the arrow keys or `HJKL` to move a region by one pixel.
* Hold `Shift` to grow the addressed edge.
* Hold `Shift+Ctrl` to shrink the addressed edge.
* With the mouse, click the bar to select the screen, click a window to select it, or drag a region.

## Optional shortcuts

Global keybindings remain user-owned. Add any of these to your Hyprland bindings:

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

## Commands and files

Core capture uses `bash`, `grim`, `jq`, and `hyprctl`. Selection and clipboard features use `slurp` and `wl-copy`. Recording uses `omarchy-capture-screenrecording` and `gpu-screen-recorder`; webcam recording also uses `v4l2-ctl` and `mpv`.

Optional integrations include `hyprpicker`, `omarchy-notification-send` or `notify-send`, `xdg-open`, and the configured screenshot editor (`tensaku-edit` by default).

Omasnap stores plugin settings inline in `~/.config/omarchy/shell.json` and recent capture state in `${XDG_STATE_HOME:-$HOME/.local/state}/omasnap/state.json`. It creates short-lived freeze images under `$XDG_RUNTIME_DIR` or `/tmp` and uses `/tmp/omarchy-screenrecord-filename` while recording. Its keep-loaded service polls recording status every 1.5 seconds. Omasnap does not use the network.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.omasnap
```

## License

[MIT](LICENSE)
