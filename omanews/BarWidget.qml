import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "b.omanews"

  property var headlines: []
  property int headlineIndex: 0
  property string feedOutput: ""
  property string feedStatus: "idle"
  property bool tickerBlocked: false
  property real tickerBlockUntil: 0
  property real hoveredWidth: 0

  readonly property int maxHeadlineWidth: Number(setting("maxWidth", 360))
  readonly property int headlineLimit: Number(setting("limit", 15))
  readonly property string feedUrl: String(setting("feedUrl", "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"))
  readonly property string currentHeadline: headlines.length > 0 ? headlines[validIndex(headlineIndex)] : ""
  readonly property string statusText: feedStatus === "loading" ? "News loading" : "News"
  readonly property string displayText: currentHeadline !== "" ? currentHeadline : statusText
  readonly property string tooltip: currentHeadline !== "" ? currentHeadline : (feedStatus === "error" ? "Headlines unavailable" : "")
  readonly property real tickerGap: Style.space(5)
  readonly property string tickerSeparator: "\u25cf"
  readonly property real tickerDistance: labelText.implicitWidth + tickerGap + separatorLabel.implicitWidth + tickerGap
  readonly property real naturalHeadlineWidth: Math.min(maxHeadlineWidth, labelText.implicitWidth) + Style.space(17)
  readonly property int tickerDuration: Math.max(1800, Math.round(wordCount(displayText) * 60000 / 200))
  readonly property bool tickerHovered: hoverArea.containsMouse
  readonly property bool tickerAvailable: currentHeadline !== ""
    && !vertical
    && tickerClip.width > 0
    && labelText.implicitWidth > tickerClip.width
  readonly property bool tickerRunning: tickerHovered && tickerAvailable && !tickerBlocked

  function validIndex(index) {
    if (headlines.length <= 0) return 0
    var n = Number(index)
    if (!isFinite(n)) n = 0
    n = Math.round(n) % headlines.length
    return n < 0 ? n + headlines.length : n
  }

  function wordCount(value) {
    var text = String(value || "").trim()
    return text === "" ? 0 : text.split(/\s+/).length
  }

  function decodeEntity(entity) {
    var value = String(entity || "")
    if (value === "amp") return "&"
    if (value === "apos") return "'"
    if (value === "quot") return "\""
    if (value === "lt") return "<"
    if (value === "gt") return ">"

    if (value.charAt(0) === "#") {
      var code = value.charAt(1).toLowerCase() === "x"
        ? parseInt(value.slice(2), 16)
        : parseInt(value.slice(1), 10)
      if (!isFinite(code) || code <= 0) return "&" + value + ";"
      if (code <= 0xffff) return String.fromCharCode(code)
      code -= 0x10000
      return String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff))
    }

    return "&" + value + ";"
  }

  function decodeXmlText(value) {
    var text = String(value || "")
      .replace(/^<!\[CDATA\[/, "")
      .replace(/\]\]>$/, "")
      .replace(/<[^>]+>/g, "")

    return text.replace(/&([^;\s]+);/g, function(match, entity) {
      return decodeEntity(entity)
    }).replace(/\s+/g, " ").trim()
  }

  function titleFromItem(item) {
    var match = String(item || "").match(/<title[^>]*>([\s\S]*?)<\/title>/i)
    return match && match[1] ? decodeXmlText(match[1]) : ""
  }

  function parseHeadlines(raw) {
    var text = String(raw || "")
    var next = []
    var seen = {}
    var itemRegex = /<item\b[\s\S]*?<\/item>/gi
    var match

    while ((match = itemRegex.exec(text)) !== null && next.length < headlineLimit) {
      var title = titleFromItem(match[0])
      var key = title.toLowerCase()
      if (title !== "" && !seen[key]) {
        seen[key] = true
        next.push(title)
      }
    }

    return next
  }

  function applyFeed(raw) {
    var previousHeadline = currentHeadline
    var next = parseHeadlines(raw)

    if (next.length === 0) {
      feedStatus = "error"
      return
    }

    var nextIndex = next.indexOf(previousHeadline)
    if (nextIndex < 0) nextIndex = 0
    if (next[nextIndex] !== previousHeadline) blockTickerScroll()

    headlines = next
    headlineIndex = nextIndex
    feedStatus = "ready"
  }

  function refresh() {
    if (feedProc.running || feedUrl === "") return "busy"

    feedOutput = ""
    feedStatus = "loading"
    feedProc.command = ["curl", "-fsSL", "--compressed", "--max-time", "8", "-A", "Mozilla/5.0", feedUrl]
    feedProc.running = true
    return "ok"
  }

  function showNextHeadline() {
    if (headlines.length === 0) {
      refresh()
      return ""
    }

    var currentIndex = validIndex(headlineIndex)
    var nextIndex = validIndex(currentIndex + 1)
    if (nextIndex !== currentIndex) blockTickerScroll()

    headlineIndex = nextIndex
    return currentHeadline
  }

  function showPreviousHeadline() {
    if (headlines.length === 0) {
      refresh()
      return ""
    }

    var currentIndex = validIndex(headlineIndex)
    var nextIndex = validIndex(currentIndex - 1)
    if (nextIndex !== currentIndex) blockTickerScroll()

    headlineIndex = nextIndex
    return currentHeadline
  }

  function searchCurrentHeadlineOnX() {
    if (currentHeadline === "") return "no-headline"

    Qt.openUrlExternally("https://x.com/search?q=" + encodeURIComponent(currentHeadline))
    return "ok"
  }

  function resetTickerScroll() {
    tickerRow.x = 0
  }

  function blockTickerScroll() {
    tickerBlockTimer.stop()
    resetTickerScroll()
    if (tickerHovered) hoveredWidth = Math.max(hoveredWidth, width, naturalHeadlineWidth)

    tickerBlockUntil = Date.now() + 2000
    tickerBlocked = true
    tickerBlockTimer.interval = 2000
    tickerBlockTimer.restart()
  }

  function clearTickerBlock() {
    tickerHoverExitTimer.stop()
    tickerBlockTimer.stop()
    tickerBlockUntil = 0
    tickerBlocked = false
    if (!tickerHovered) hoveredWidth = 0
    resetTickerScroll()
  }

  function clearTickerBlockIfStillExited() {
    if (!tickerHovered) clearTickerBlock()
  }

  implicitWidth: root.vertical ? barSize : Math.max(naturalHeadlineWidth, hoveredWidth)
  implicitHeight: barSize

  onNaturalHeadlineWidthChanged: {
    if (tickerHovered) hoveredWidth = Math.max(hoveredWidth, naturalHeadlineWidth)
  }

  onCurrentHeadlineChanged: {
    blockTickerScroll()
  }

  onTickerRunningChanged: {
    if (!tickerRunning) resetTickerScroll()
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "b.omanews"

    function headline(): string {
      return root.currentHeadline
    }

    function next(): string {
      return root.showNextHeadline()
    }

    function nextHeadline(): string {
      return root.showNextHeadline()
    }

    function previous(): string {
      return root.showPreviousHeadline()
    }

    function previousHeadline(): string {
      return root.showPreviousHeadline()
    }

    function search(): string {
      return root.searchCurrentHeadlineOnX()
    }

    function open(): string {
      return root.searchCurrentHeadlineOnX()
    }

    function refresh(): string {
      return root.refresh()
    }
  }

  Process {
    id: feedProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.feedOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyFeed(root.feedOutput)
      else if (root.headlines.length === 0) root.feedStatus = "error"
      else root.feedStatus = "ready"

      root.feedOutput = ""
    }
  }

  Timer {
    interval: 10 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: tickerBlockTimer
    interval: 2000
    repeat: false
    onTriggered: {
      var remaining = root.tickerBlockUntil - Date.now()
      if (remaining > 0) {
        interval = Math.max(1, Math.ceil(remaining))
        restart()
        return
      }

      root.tickerBlockUntil = 0
      root.tickerBlocked = false
      interval = 2000
    }
  }

  Timer {
    id: tickerHoverExitTimer
    interval: 80
    repeat: false
    onTriggered: root.clearTickerBlockIfStillExited()
  }

  Item {
    id: tickerClip
    anchors.fill: parent
    anchors.leftMargin: Style.space(8.5)
    anchors.rightMargin: Style.space(8.5)
    clip: true

    Item {
      id: tickerRow
      anchors.verticalCenter: parent.verticalCenter
      width: root.tickerRunning ? root.tickerDistance + repeatedLabel.implicitWidth : parent.width
      height: labelText.implicitHeight

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        width: root.tickerRunning ? implicitWidth : tickerClip.width
        text: root.displayText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        elide: root.tickerRunning || root.vertical ? Text.ElideNone : Text.ElideRight
        rotation: root.vertical ? -90 : 0
        transformOrigin: Item.Center
        opacity: root.currentHeadline === "" ? 0.65 : 1

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      Text {
        id: separatorLabel
        anchors.verticalCenter: parent.verticalCenter
        x: labelText.implicitWidth + root.tickerGap
        visible: root.tickerRunning
        text: root.tickerSeparator
        color: Qt.rgba(labelText.color.r, labelText.color.g, labelText.color.b, 0.45)
        font.family: labelText.font.family
        font.pixelSize: Math.round(labelText.font.pixelSize * 1.25)
        opacity: labelText.opacity
      }

      Text {
        id: repeatedLabel
        anchors.verticalCenter: parent.verticalCenter
        x: root.tickerDistance
        visible: root.tickerRunning
        text: root.displayText
        color: labelText.color
        font.family: labelText.font.family
        font.pixelSize: labelText.font.pixelSize
        opacity: labelText.opacity
      }

      NumberAnimation on x {
        from: 0
        to: -root.tickerDistance
        duration: root.tickerDuration
        loops: Animation.Infinite
        running: root.tickerRunning
      }
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.showPreviousHeadline()
      else if (mouse.button === Qt.MiddleButton) root.searchCurrentHeadlineOnX()
      else root.showNextHeadline()
    }

    onEntered: {
      tickerHoverExitTimer.stop()
      root.hoveredWidth = Math.max(root.hoveredWidth, root.width, root.naturalHeadlineWidth)
      if (root.bar) root.bar.showTooltip(root, root.tooltip)
    }

    onExited: {
      tickerHoverExitTimer.restart()
      if (root.bar) root.bar.hideTooltip(root)
    }
  }
}
