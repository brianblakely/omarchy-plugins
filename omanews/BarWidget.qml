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

  readonly property int maxHeadlineWidth: Number(setting("maxWidth", 360))
  readonly property int headlineLimit: Number(setting("limit", 15))
  readonly property string feedUrl: String(setting("feedUrl", "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en"))
  readonly property string currentHeadline: headlines.length > 0 ? headlines[validIndex(headlineIndex)] : ""
  readonly property string statusText: feedStatus === "loading" ? "News loading" : "News"
  readonly property string displayText: currentHeadline !== "" ? currentHeadline : statusText
  readonly property string tooltip: currentHeadline !== "" ? currentHeadline : (feedStatus === "error" ? "Headlines unavailable" : "")

  function validIndex(index) {
    if (headlines.length <= 0) return 0
    var n = Number(index)
    if (!isFinite(n)) n = 0
    n = Math.round(n) % headlines.length
    return n < 0 ? n + headlines.length : n
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

    headlines = next
    var previousIndex = next.indexOf(previousHeadline)
    headlineIndex = previousIndex >= 0 ? previousIndex : 0
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

    headlineIndex = validIndex(headlineIndex + 1)
    return currentHeadline
  }

  function showPreviousHeadline() {
    if (headlines.length === 0) {
      refresh()
      return ""
    }

    headlineIndex = validIndex(headlineIndex - 1)
    return currentHeadline
  }

  function searchCurrentHeadlineOnX() {
    if (currentHeadline === "") return "no-headline"

    Qt.openUrlExternally("https://x.com/search?q=" + encodeURIComponent(currentHeadline))
    return "ok"
  }

  implicitWidth: root.vertical ? barSize : Math.min(maxHeadlineWidth, labelText.implicitWidth) + Style.space(17)
  implicitHeight: barSize

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

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8.5)
    anchors.rightMargin: Style.space(8.5)
    clip: true

    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: parent.width
      text: root.displayText
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
      elide: root.vertical ? Text.ElideNone : Text.ElideRight
      rotation: root.vertical ? -90 : 0
      transformOrigin: Item.Center
      opacity: root.currentHeadline === "" ? 0.65 : 1

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.showPreviousHeadline()
      else if (mouse.button === Qt.MiddleButton) root.searchCurrentHeadlineOnX()
      else root.showNextHeadline()
    }

    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
