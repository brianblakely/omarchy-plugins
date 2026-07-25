# Omastonk

Omastonk is a multi-instance market widget for the Omarchy bar. It shows a selected symbol, current quote, daily direction, and charts ranging from one day to five years.

![Omastonk screenshot](images/omastonk.png)

## Install

Install Omastonk disabled so you can review it before it runs:

```bash
omarchy plugin add https://github.com/brianblakely/omastonk.git --no-enable
```

Review the installed checkout:

```bash
omarchy plugin edit b.omastonk
```

Then enable the first instance in the right bar section:

```bash
omarchy plugin enable b.omastonk --section right
```

Add another instance with an explicit placement:

```bash
omarchy bar plugin add b.omastonk --section right --duplicate
```

## Usage

Omastonk starts without a symbol. Click it to choose a symbol and open its chart; right-click it to edit the symbol. In the chart, use the arrow keys or `HJKL` to switch intervals and `Escape` to close.

Each instance keeps its own symbol, so multiple widgets can track different markets.

## Network and storage

Omastonk runs `curl` against `query1.finance.yahoo.com`. Quotes refresh every minute and charts load on demand.

Each instance writes its symbol and generated `instanceId` to its own bar-layout entry in `~/.config/omarchy/shell.json`. It does not write other files.

Plugins run unsandboxed inside `omarchy-shell`; review the checkout before enabling it.

## Update

```bash
omarchy plugin update b.omastonk
```

## License

[MIT](LICENSE)
