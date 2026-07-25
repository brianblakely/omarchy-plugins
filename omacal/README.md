# Omacal

Omacal is a configurable Omarchy clock with a mini calendar, ISO week number, moon phase, locale-aware week start, and horizontal and vertical display formats.

![Omacal screenshot](images/omacal.png)

## Install

Install Omacal disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/omacal.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.omacal
```

Then enable it in the center section:

```bash
omarchy plugin enable b.omacal --section center
```

To replace the default clock, remove it:

```bash
omarchy bar plugin remove omarchy.clock
```

Then set `"centerAnchor": "b.omacal"` in the `bar` object in `~/.config/omarchy/shell.json`.

## Usage

Click the clock to toggle the calendar. Right-click it to open Omarchy's timezone menu.

Inside the calendar:

* Use the arrow keys or `HJKL` to browse months and years.
* Press `Enter` to return to today.
* Press `Escape` to close the calendar.

The bar settings UI exposes the first day of the week, calendar title format, horizontal and vertical clock formats, and flash duration.

## Optional shortcuts

Global keybindings remain user-owned. Add any of these to your Hyprland bindings:

```lua
hl.unbind("SUPER + CTRL + ALT + T")
o.bind("SUPER + CTRL + ALT + T", "Flash mini calendar", "omarchy-shell b.omacal flash")
o.bind("SUPER + F9", "Toggle mini calendar", "omarchy-shell shell toggle b.omacal")
o.bind("SUPER + ALT + F9", "Open mini calendar", "omarchy-shell shell summon b.omacal")
o.bind("SUPER + CTRL + F9", "Close mini calendar", "omarchy-shell shell hide b.omacal")
```

## Behavior

Omacal does not write files or use the network. Right-clicking the widget runs `omarchy-menu-timezone`.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.omacal
```

## License

[MIT](LICENSE)
