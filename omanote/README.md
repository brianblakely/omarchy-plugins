# Omanote

Omanote adds a secure multiline scratch note to the Omarchy bar and saves changes automatically.

![Omanote screenshot](images/omanote.png)

## Install

Omanote requires `secret-tool`, provided by the `libsecret` package.

Install Omanote disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/omanote.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.omanote
```

Then enable it in the right bar section:

```bash
omarchy plugin enable b.omanote --section right
```

## Optional shortcuts

Global keybindings remain user-owned. Add any of these to your Hyprland bindings:

```lua
o.bind("SUPER + F8", "Toggle Omanote", "omarchy-shell shell toggle b.omanote")
o.bind("SUPER + ALT + F8", "Open Omanote", "omarchy-shell shell summon b.omanote")
o.bind("SUPER + CTRL + F8", "Close Omanote", "omarchy-shell shell hide b.omanote")
```

## Storage and behavior

Omanote runs `bash` and `secret-tool`. It stores the note with the desktop Secret Service using the attributes `omarchy-plugin=b.omanote` and `field=note`.

Automatic saves briefly stage the note in a randomly named file under `$XDG_RUNTIME_DIR`, pipe it into `secret-tool store`, and delete the runtime file immediately afterward. Note contents are never stored in `~/.config/omarchy/shell.json`. Omanote does not use the network.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.omanote
```

## License

[MIT](LICENSE)
