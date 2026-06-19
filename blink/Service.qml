import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.blink"
  readonly property color strokeColor: Color.accent

  property bool showing: false
  property bool queued: false
  property real flashOpacity: 0
  property int targetX: 0
  property int targetY: 0
  property int targetW: 0
  property int targetH: 0
  readonly property int strokeWidth: 2
  property string state: "idle"
  property string lastError: ""
  property string lastWindowJson: ""

  function trim(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "")
  }

  function screenNumber(screen, name, fallback) {
    var value = screen && screen[name] !== undefined ? Number(screen[name]) : Number(fallback)
    return isFinite(value) ? value : Number(fallback || 0)
  }

  function targetOverlapsScreen(screen) {
    if (!showing || targetW <= 0 || targetH <= 0 || !screen) return false

    var sx = screenNumber(screen, "virtualX", 0)
    var sy = screenNumber(screen, "virtualY", 0)
    var sw = screenNumber(screen, "width", 0)
    var sh = screenNumber(screen, "height", 0)

    if (sw <= 0 || sh <= 0) return false
    return targetX < sx + sw
      && targetX + targetW > sx
      && targetY < sy + sh
      && targetY + targetH > sy
  }

  function showBlink() {
    if (targetW <= 0 || targetH <= 0) return

    state = "showing"
    showing = true
    closeTimer.stop()
    flashOpacity = 1
    hideTimer.restart()
  }

  function blink() {
    if (activeWindowProc.running) {
      queued = true
      return "queued"
    }

    state = "querying"
    lastError = ""
    activeWindowProc.running = true
    return "ok"
  }

  function applyActiveWindow(raw) {
    lastWindowJson = trim(raw)

    try {
      var window = JSON.parse(lastWindowJson || "{}")
      var at = window.at || []
      var size = window.size || []
      var x = Math.round(Number(at[0]))
      var y = Math.round(Number(at[1]))
      var w = Math.round(Number(size[0]))
      var h = Math.round(Number(size[1]))

      if (!isFinite(x) || !isFinite(y) || !isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) {
        state = "no-active-window"
        return
      }

      targetX = x
      targetY = y
      targetW = w
      targetH = h
      showBlink()
    } catch (e) {
      state = "parse-error"
      lastError = String(e)
    }
  }

  function scheduleActiveWindowBlink() {
    activeWindowChangeTimer.restart()
  }

  function statusJson() {
    return JSON.stringify({
      state: state,
      showing: showing,
      queued: queued,
      targetX: targetX,
      targetY: targetY,
      targetW: targetW,
      targetH: targetH,
      strokeWidth: strokeWidth,
      lastError: lastError
    })
  }

  Behavior on flashOpacity {
    NumberAnimation {
      duration: 120
      easing.type: Easing.OutQuad
    }
  }

  Timer {
    id: hideTimer
    interval: 160
    repeat: false
    onTriggered: {
      root.state = "fading"
      root.flashOpacity = 0
      closeTimer.restart()
    }
  }

  Timer {
    id: closeTimer
    interval: 140
    repeat: false
    onTriggered: {
      root.showing = false
      root.state = "idle"
    }
  }

  Timer {
    id: activeWindowChangeTimer
    interval: 35
    repeat: false
    onTriggered: root.blink()
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyActiveWindow(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = text
    }

    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state === "querying")
        root.state = "error"

      if (root.queued) {
        root.queued = false
        Qt.callLater(root.blink)
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "activewindow" || name === "activewindowv2") root.scheduleActiveWindowBlink()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel

      required property var modelData

      screen: modelData
      visible: root.targetOverlapsScreen(modelData)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "b-blink"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      readonly property int screenX: root.screenNumber(modelData, "virtualX", 0)
      readonly property int screenY: root.screenNumber(modelData, "virtualY", 0)

      Rectangle {
        x: root.targetX - panel.screenX
        y: root.targetY - panel.screenY
        width: root.targetW
        height: root.targetH
        radius: Math.max(0, Math.min(Style.cornerRadius, width / 2, height / 2))
        color: "transparent"
        opacity: root.flashOpacity
        border.color: root.strokeColor
        border.width: root.strokeWidth
      }
    }
  }

  IpcHandler {
    target: root.pluginId

    function blink(): string { return root.blink() }
    function flash(): string { return root.blink() }
    function show(): string { return root.blink() }
    function status(): string { return root.statusJson() }
    function debug(): string { return root.statusJson() }
  }
}
