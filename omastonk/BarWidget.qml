import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "b.omastonk"

  property real quotePrice: NaN
  property real quoteChange: 0
  property string quoteStatus: "idle"
  property string quoteOutput: ""
  property string requestedSymbol: ""

  readonly property string symbol: normalizeSymbol(setting("symbol", ""))
  readonly property bool quoteReady: quoteStatus === "ready" && isFinite(quotePrice)
  readonly property bool priceDown: quoteReady && quoteChange < 0
  readonly property string trendGlyph: quoteReady ? (priceDown ? "\u25BC" : "\u25B2") : ""
  readonly property string priceText: quoteReady ? formatPrice(quotePrice) : (quoteStatus === "loading" ? "..." : "?")
  readonly property string labelText: symbol === "" ? "$" : symbol + " " + priceText + (trendGlyph === "" ? "" : " " + trendGlyph)

  function normalizeSymbol(value) {
    return String(value || "").trim().toUpperCase().replace(/\s+/g, "")
  }

  function numericValue(value) {
    if (value === undefined || value === null || value === "") return NaN
    var number = Number(value)
    return isFinite(number) ? number : NaN
  }

  function formatPrice(value) {
    var number = Number(value)
    if (!isFinite(number)) return "?"

    var absolute = Math.abs(number)
    var decimals = absolute >= 1 ? 2 : 4
    return number.toFixed(decimals)
  }

  function quoteUrl() {
    return "https://query1.finance.yahoo.com/v8/finance/chart/"
      + encodeURIComponent(symbol)
      + "?range=1d&interval=1m"
  }

  function resetQuote() {
    quotePrice = NaN
    quoteChange = 0
    quoteStatus = symbol === "" ? "idle" : "loading"
    quoteOutput = ""
  }

  function refresh() {
    if (symbol === "" || quoteProc.running) return

    quoteOutput = ""
    requestedSymbol = symbol
    quoteStatus = "loading"
    quoteProc.command = ["curl", "-fsS", "--max-time", "6", "-A", "Mozilla/5.0", quoteUrl()]
    quoteProc.running = true
  }

  function applyQuote(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      quoteStatus = "error"
      return
    }

    try {
      var parsed = JSON.parse(text)
      var chart = parsed && parsed.chart ? parsed.chart : null
      if (chart && chart.error) {
        quoteStatus = "error"
        return
      }

      var result = chart && chart.result && chart.result.length > 0 ? chart.result[0] : null
      var meta = result && result.meta ? result.meta : null
      var price = numericValue(meta ? meta.regularMarketPrice : NaN)
      var previous = numericValue(meta ? meta.chartPreviousClose : NaN)
      if (!isFinite(previous)) previous = numericValue(meta ? meta.previousClose : NaN)
      if (!isFinite(price)) {
        quoteStatus = "error"
        return
      }

      quotePrice = price
      quoteChange = isFinite(previous) ? price - previous : 0
      quoteStatus = "ready"
    } catch (e) {
      quoteStatus = "error"
    }
  }

  function slotHost() {
    var item = root.parent
    while (item) {
      if ("region" in item && "entry" in item) return item
      item = item.parent
    }
    return null
  }

  function siblingSlotIndex(host, section) {
    var itemParent = host ? host.parent : null
    if (!itemParent || !itemParent.children) return -1

    var index = 0
    for (var i = 0; i < itemParent.children.length; i++) {
      var child = itemParent.children[i]
      if (!child || !("entry" in child) || String(child.region || "") !== section) continue
      if (child === host) return index
      index++
    }

    return -1
  }

  function currentLayoutLocation() {
    var host = slotHost()
    if (!host || !bar || !bar.layoutConfig) return null

    var section = String(host.region || "")
    var entries = bar.layoutConfig[section]
    if (!Array.isArray(entries)) return null

    for (var i = 0; i < entries.length; i++) {
      if (entries[i] === host.entry) return { section: section, index: i }
    }

    var siblingIndex = siblingSlotIndex(host, section)
    if (siblingIndex >= 0 && siblingIndex < entries.length)
      return { section: section, index: siblingIndex }

    return null
  }

  function saveInstanceSettings(next) {
    root.settings = next

    var location = currentLayoutLocation()
    if (location && bar && bar.shell && typeof bar.shell.mutateShellConfig === "function") {
      bar.shell.mutateShellConfig(function(config) {
        if (!config.bar) config.bar = {}
        if (!config.bar.layout) config.bar.layout = { left: [], center: [], right: [] }

        var entries = config.bar.layout[location.section]
        if (!Array.isArray(entries) || location.index < 0 || location.index >= entries.length) return

        var current = entries[location.index]
        var currentId = typeof current === "string" ? current : String(current && current.id ? current.id : "")
        if (currentId !== root.moduleName) return

        var updated = { id: currentId }
        for (var key in next) {
          if (key !== "id") updated[key] = next[key]
        }
        entries[location.index] = updated
      })
      return
    }

  }

  function setSymbol(value) {
    var nextSymbol = normalizeSymbol(value)
    if (nextSymbol === symbol) return

    var next = {}
    for (var key in settings) {
      if (key !== "id") next[key] = settings[key]
    }
    next.symbol = nextSymbol
    saveInstanceSettings(next)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("host" in target) target.host = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onSymbolChanged: {
    resetQuote()
    if (symbol !== "") Qt.callLater(refresh)
  }

  Component.onCompleted: {
    resetQuote()
    if (symbol !== "") Qt.callLater(refresh)
  }

  Process {
    id: quoteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.quoteOutput = text
    }
    onExited: function(exitCode) {
      if (root.requestedSymbol !== root.symbol) {
        root.quoteOutput = ""
        root.requestedSymbol = ""
        if (root.symbol !== "") Qt.callLater(root.refresh)
        return
      }

      if (exitCode === 0) root.applyQuote(root.quoteOutput)
      else if (root.symbol !== "") root.quoteStatus = "error"
      root.quoteOutput = ""
      root.requestedSymbol = ""
    }
  }

  Timer {
    interval: 60 * 1000
    running: root.symbol !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.labelText
    foreground: Color.bar.text
    activeColor: Color.bar.active
    active: root.priceDown
    horizontalMargin: 8.5
    verticalPadding: 6
    tooltipText: root.symbol === "" ? "Set symbol" : ""
    onPressed: root.togglePanel()
  }
}
