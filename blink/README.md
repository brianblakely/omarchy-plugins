# Blink

Blink flashes a short, theme-colored inset border over the active Hyprland window. It runs automatically when the active window changes and can also be triggered on demand.

## Install

Install Blink disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/blink.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.blink
```

Then enable it:

```bash
omarchy plugin enable b.blink
```

## Optional shortcut

Global keybindings remain user-owned. Add this to your Hyprland bindings if desired:

```lua
o.bind("SUPER + B", "Blink active window", "omarchy-shell b.blink blink")
```

## Behavior

Blink runs `hyprctl activewindow -j`, listens for Hyprland window events, and creates a transparent overlay on each screen. It does not write files or use the network.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.blink
```

## License

[MIT](LICENSE)
