# Peek

Peek fades floating Hyprland windows to ten percent opacity so you can see and interact with the content underneath.

![Peek disabled](images/peek1.png)
![Peek enabled](images/peek2.png)

## Install

Install Peek disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/peek.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.peek
```

Then enable it:

```bash
omarchy plugin enable b.peek
```

## Optional shortcuts

Global keybindings remain user-owned. Add any of these to your Hyprland bindings:

```lua
o.bind("SUPER + GRAVE", "Toggle floating window peek", "omarchy-shell b.peek toggle")
o.bind("SUPER + ALT + GRAVE", "Enable floating window peek", "omarchy-shell b.peek enable")
o.bind("SUPER + CTRL + GRAVE", "Disable floating window peek", "omarchy-shell b.peek disable")
```

## Behavior

Peek runs `hyprctl eval` to install and toggle a named runtime Hyprland Lua window rule. The rule changes floating-window opacity, blur, focus, and follow-mouse behavior. Peek reapplies the rule after a Hyprland config reload and disables it when unloaded. It does not write files or use the network.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.peek
```

## License

[MIT](LICENSE)
