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
  readonly property color strokeColor: colorFromToken(themeBorderColorRaw, Color.accent)

  property bool showing: false
  property bool queued: false
  property real flashOpacity: 0
  property int targetX: 0
  property int targetY: 0
  property int targetW: 0
  property int targetH: 0
  property int strokeWidth: 2
  property string themeBorderColorRaw: ""
  property string state: "idle"
  property string lastError: ""
  property string lastWindowJson: ""

  function trim(value) {
    return String(value || "").replace(/^\s+|\s+$/g, "")
  }

  function clamp(value, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return min
    return Math.max(min, Math.min(max, n))
  }

  function padHex(value) {
    var n = clamp(Math.round(Number(value)), 0, 255)
    var h = n.toString(16)
    return h.length < 2 ? "0" + h : h
  }

  function rgbaFromHex(rgb, alphaByte) {
    var h = String(rgb || "").replace(/^#/, "")
    var a = clamp(alphaByte === undefined ? 255 : Number(alphaByte), 0, 255) / 255
    return Qt.rgba(
      parseInt(h.substr(0, 2), 16) / 255,
      parseInt(h.substr(2, 2), 16) / 255,
      parseInt(h.substr(4, 2), 16) / 255,
      a
    )
  }

  function firstColorToken(value) {
    var parts = trim(value).split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return ""
  }

  function colorFromToken(value, fallback) {
    var token = firstColorToken(value)
    var match = token.match(/^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$/)
    if (match) return rgbaFromHex(match[1], match[2] ? parseInt(match[2], 16) : 255)

    match = token.match(/^[Rr][Gg][Bb]\(([0-9A-Fa-f]{6})\)$/)
    if (match) return rgbaFromHex(match[1], 255)

    match = token.match(/^[Rr][Gg][Bb][Aa]\(([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})\)$/)
    if (match) return rgbaFromHex(match[1], parseInt(match[2], 16))

    match = token.match(/^[Rr][Gg][Bb]\(([0-9]+),([0-9]+),([0-9]+)\)$/)
    if (match) return rgbaFromHex(padHex(match[1]) + padHex(match[2]) + padHex(match[3]), 255)

    match = token.match(/^[Rr][Gg][Bb][Aa]\(([0-9]+),([0-9]+),([0-9]+),([0-9.]+)\)$/)
    if (match) return rgbaFromHex(
      padHex(match[1]) + padHex(match[2]) + padHex(match[3]),
      clamp(Number(match[4]), 0, 1) * 255
    )

    try {
      if (token !== "") return Qt.color(token)
    } catch (e) {}

    return fallback
  }

  function valueForKey(raw, key) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*(.+)\s*$/)
      if (!match || match[1] !== key) continue

      var value = trim(match[2])
      var quote = value.charAt(0)
      if (quote === "\"" || quote === "'") {
        var end = value.indexOf(quote, 1)
        return end >= 0 ? value.substring(1, end) : value.substring(1)
      }

      return trim(value.replace(/\s+#.*$/, ""))
    }
    return ""
  }

  function applyThemeColors(raw) {
    themeBorderColorRaw = valueForKey(raw, "active_border_color")
      || valueForKey(raw, "hyprland_active_border")
      || ""
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

  function applyBorderSize(raw) {
    try {
      var option = JSON.parse(raw || "{}")
      var n = Number(option.int)
      if (!isFinite(n)) {
        var match = String(option.css || "").match(/-?\d+(?:\.\d+)?/)
        if (match) n = Number(match[0])
      }
      if (isFinite(n)) strokeWidth = Math.max(1, Math.round(n))
    } catch (e) {}
  }

  function refreshBorderSize() {
    if (!borderSizeProc.running) borderSizeProc.running = true
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
      themeBorderColorRaw: themeBorderColorRaw,
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

  FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyThemeColors(text())
    onFileChanged: reload()
    onLoadFailed: root.themeBorderColorRaw = ""
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

  Process {
    id: borderSizeProc
    command: ["hyprctl", "-j", "getoption", "general:border_size"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBorderSize(text)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name === "configreloaded") root.refreshBorderSize()
      else if (name === "activewindow" || name === "activewindowv2") root.scheduleActiveWindowBlink()
    }
  }

  Component.onCompleted: refreshBorderSize()

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
