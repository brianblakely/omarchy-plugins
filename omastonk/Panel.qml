import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "b.omastonk"
  manageIpc: false

  property var anchorItem: null
  property var host: null
  property string draftSymbol: ""
  property bool editing: true
  property int intervalIndex: 6
  property var chartPoints: []
  property string chartStatus: "idle"
  property string chartOutput: ""
  property string requestedChartKey: ""

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.65)
  readonly property bool intervalDown: chartPoints.length > 1 && chartPoints[chartPoints.length - 1] < chartPoints[0]
  readonly property color chartColor: intervalDown ? Color.bar.active : Color.bar.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string symbol: host ? host.symbol : normalizeSymbol(setting("symbol", ""))
  readonly property var intervalOptions: [
    { label: "5Y", range: "5y", interval: "1wk" },
    { label: "1Y", range: "1y", interval: "1d" },
    { label: "YTD", range: "ytd", interval: "1d" },
    { label: "6M", range: "6mo", interval: "1d" },
    { label: "1M", range: "1mo", interval: "1d" },
    { label: "5D", range: "5d", interval: "15m" },
    { label: "1D", range: "1d", interval: "5m" }
  ]
  readonly property int chartPanelWidth: Math.ceil(intervalSizer.implicitWidth + Style.space(30))
  readonly property var selectedInterval: intervalOptions[Math.max(0, Math.min(intervalIndex, intervalOptions.length - 1))]
  readonly property string selectedIntervalLabel: selectedInterval ? selectedInterval.label : "1D"
  readonly property string chartStatusText: chartStatus === "loading" ? "Loading" : (chartStatus === "error" ? "No data" : "")

  function normalizeSymbol(value) {
    return String(value || "").trim().toUpperCase().replace(/\s+/g, "")
  }

  function numericValue(value) {
    if (value === undefined || value === null || value === "") return NaN
    var number = Number(value)
    return isFinite(number) ? number : NaN
  }

  function clampIntervalIndex(value) {
    var max = intervalOptions.length - 1
    return Math.max(0, Math.min(max, Math.round(Number(value) || 0)))
  }

  function chartKey() {
    return symbol + "|" + selectedIntervalLabel
  }

  function chartUrl() {
    var option = selectedInterval || intervalOptions[0]
    return "https://query1.finance.yahoo.com/v8/finance/chart/"
      + encodeURIComponent(symbol)
      + "?range=" + encodeURIComponent(option.range)
      + "&interval=" + encodeURIComponent(option.interval)
  }

  function open() {
    draftSymbol = symbol
    editing = symbol === ""
    root.controller.show()
    Qt.callLater(function() {
      if (root.editing) focusSymbolField()
      else {
        keyCatcher.forceActiveFocus()
        refreshChart(true)
      }
    })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function focusSymbolField() {
    if (!symbolField) return
    symbolField.forceActiveFocus()
    symbolField.selectAll()
  }

  function editSymbol() {
    draftSymbol = symbol
    editing = true
    Qt.callLater(focusSymbolField)
  }

  function cancelEdit() {
    if (symbol === "") {
      root.close()
      return
    }

    draftSymbol = symbol
    editing = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submit() {
    var next = normalizeSymbol(draftSymbol)
    draftSymbol = next
    if (host && host.setSymbol) host.setSymbol(next)

    if (next === "") {
      chartPoints = []
      chartStatus = "idle"
      editing = true
      Qt.callLater(focusSymbolField)
      return
    }

    editing = false
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      refreshChart(true)
    })
  }

  function clear() {
    draftSymbol = ""
    if (host && host.setSymbol) host.setSymbol("")
    chartPoints = []
    chartStatus = "idle"
    editing = true
    Qt.callLater(focusSymbolField)
  }

  function selectInterval(index) {
    var next = clampIntervalIndex(index)
    if (next === intervalIndex) return
    intervalIndex = next
    refreshChart(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function moveInterval(delta) {
    selectInterval(intervalIndex + delta)
  }

  function refreshChart(force) {
    if (editing || symbol === "" || chartProc.running) return
    if (!force && chartStatus === "ready" && requestedChartKey === chartKey()) return

    chartPoints = []
    chartOutput = ""
    requestedChartKey = chartKey()
    chartStatus = "loading"
    chartProc.command = ["curl", "-fsS", "--max-time", "8", "-A", "Mozilla/5.0", chartUrl()]
    chartProc.running = true
  }

  function applyChart(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      chartPoints = []
      chartStatus = "error"
      return
    }

    try {
      var parsed = JSON.parse(text)
      var chart = parsed && parsed.chart ? parsed.chart : null
      var result = chart && chart.result && chart.result.length > 0 ? chart.result[0] : null
      var quote = result && result.indicators && result.indicators.quote && result.indicators.quote.length > 0
        ? result.indicators.quote[0]
        : null
      var close = quote && Array.isArray(quote.close) ? quote.close : []
      var points = []

      for (var i = 0; i < close.length; i++) {
        var value = numericValue(close[i])
        if (isFinite(value)) points.push(value)
      }

      chartPoints = points
      chartStatus = points.length > 1 ? "ready" : "error"
    } catch (e) {
      chartPoints = []
      chartStatus = "error"
    }
  }

  onSymbolChanged: {
    draftSymbol = symbol
    if (!opened) return
    editing = symbol === ""
    if (symbol !== "") Qt.callLater(function() { refreshChart(true) })
  }

  onChartPointsChanged: chartCanvas.requestPaint()
  onChartColorChanged: chartCanvas.requestPaint()
  onIntervalIndexChanged: chartCanvas.requestPaint()

  Process {
    id: chartProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.chartOutput = text
    }
    onExited: function(exitCode) {
      if (root.requestedChartKey !== root.chartKey()) {
        root.chartOutput = ""
        if (root.opened && !root.editing && root.symbol !== "") Qt.callLater(function() { root.refreshChart(true) })
        return
      }

      if (exitCode === 0) root.applyChart(root.chartOutput)
      else root.chartStatus = "error"
      root.chartOutput = ""
    }
  }

  Row {
    id: intervalSizer
    opacity: 0
    height: 0
    enabled: false
    spacing: Style.space(6)

    Repeater {
      model: root.intervalOptions

      Button {
        required property var modelData
        text: modelData.label
        selected: true
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
      }
    }
  }

  KeyboardPanel {
    id: symbolPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.editing ? symbolField : keyCatcher
    contentWidth: symbolPanel.fittedContentWidth(root.editing ? Style.space(280) : root.chartPanelWidth)
    contentHeight: symbolPanel.fittedContentHeight(root.editing ? editorColumn.implicitHeight : chartColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onMoveRequested: function(dx, dy) {
        if (dx < 0) root.moveInterval(-1)
        else if (dx > 0) root.moveInterval(1)
      }
      onCloseRequested: root.close()

      Column {
        id: chartColumn
        visible: !root.editing
        width: parent.width
        spacing: Style.space(10)

        Row {
          id: headerRow
          width: parent.width
          height: editButton.implicitHeight
          spacing: Style.space(8)

          Text {
            id: symbolTitle
            width: Math.min(implicitWidth, Math.max(1, parent.width - editButton.implicitWidth - priceLabel.implicitWidth - parent.spacing * 3))
            height: parent.height
            text: root.symbol
            color: root.chartColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }

          Button {
            id: editButton
            text: "Edit"
            foreground: root.dim
            onClicked: root.editSymbol()
          }

          Item {
            width: Math.max(0, parent.width - symbolTitle.width - editButton.implicitWidth - priceLabel.implicitWidth - parent.spacing * 3)
            height: parent.height
          }

          Text {
            id: priceLabel
            height: parent.height
            text: host ? host.priceText : ""
            color: root.chartColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(152)
          color: "transparent"
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          border.width: Math.max(1, Style.spacing.hairline)
          radius: Math.min(Style.cornerRadius, Style.space(6))

          Canvas {
            id: chartCanvas
            anchors.fill: parent
            anchors.margins: Style.space(10)

            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)

              var points = root.chartPoints || []
              if (points.length < 2) return

              var min = points[0]
              var max = points[0]
              for (var i = 1; i < points.length; i++) {
                min = Math.min(min, points[i])
                max = Math.max(max, points[i])
              }

              if (max === min) {
                max += 1
                min -= 1
              }

              var pad = Style.space(2)
              var drawW = Math.max(1, width - pad * 2)
              var drawH = Math.max(1, height - pad * 2)

              ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              ctx.lineWidth = 1
              ctx.beginPath()
              for (var grid = 1; grid < 4; grid++) {
                var gy = pad + drawH * grid / 4
                ctx.moveTo(pad, gy)
                ctx.lineTo(width - pad, gy)
              }
              ctx.stroke()

              ctx.strokeStyle = root.chartColor
              ctx.fillStyle = Qt.rgba(root.chartColor.r, root.chartColor.g, root.chartColor.b, 0.16)
              ctx.lineWidth = 0.5
              ctx.lineJoin = "round"
              ctx.lineCap = "round"
              ctx.beginPath()

              for (var p = 0; p < points.length; p++) {
                var x = pad + (points.length === 1 ? 0 : p * drawW / (points.length - 1))
                var y = pad + (1 - (points[p] - min) / (max - min)) * drawH
                if (p === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
              }

              ctx.stroke()
              ctx.lineTo(width - pad, height - pad)
              ctx.lineTo(pad, height - pad)
              ctx.closePath()
              ctx.fill()
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.chartStatusText !== ""
            text: root.chartStatusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Row {
          id: intervalRow
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.intervalOptions

            Button {
              required property var modelData
              required property int index

              text: modelData.label
              selected: index === root.intervalIndex
              foreground: index === root.intervalIndex ? root.chartColor : root.dim
              accent: root.chartColor
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(5)
              onClicked: root.selectInterval(index)
            }
          }
        }
      }

      Column {
        id: editorColumn
        visible: root.editing
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Symbol"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        TextField {
          id: symbolField
          width: parent.width
          text: root.draftSymbol
          placeholderText: "SPY"
          foreground: root.foreground
          onTextChanged: root.draftSymbol = root.normalizeSymbol(text)
          onAccepted: root.submit()
          Keys.onEscapePressed: root.cancelEdit()
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Clear"
            foreground: root.dim
            onClicked: root.clear()
          }

          Button {
            text: "Save"
            foreground: root.foreground
            accent: Color.accent
            selected: true
            onClicked: root.submit()
          }
        }
      }
    }
  }
}
