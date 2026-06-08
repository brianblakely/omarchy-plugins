import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.omaled"
  readonly property var pluginSettings: currentSettings()
  readonly property bool effectEnabled: setting("enabled", true) !== false
  readonly property real shadeOpacity: clamp(Number(setting("opacity", 0.94)), 0, 1)
  readonly property color shadeColor: colorValue(setting("color", "#000000"), "#000000")
  readonly property string barPosition: normalizePosition(shell && shell.barConfig ? shell.barConfig.position : "top")
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int fallbackBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int shadeSize: liveBarSize()
  readonly property bool barTransparent: shell && shell.bar
    && ((("requestedTransparent" in shell.bar) && shell.bar.requestedTransparent === true)
      || (("transparent" in shell.bar) && shell.bar.transparent === true))
  readonly property bool barHidden: shell && shell.bar && ("barHidden" in shell.bar) && shell.bar.barHidden === true
  readonly property bool effectActive: effectEnabled && !barHidden && shadeOpacity > 0 && shadeSize > 0
  readonly property bool paintOverlay: effectActive && !barTransparent
  readonly property bool dimSuppressed: hoverGraceActive
  readonly property real overlayOpacity: dimSuppressed ? 0 : shadeOpacity

  property bool cursorOverBar: false
  property bool hoverGraceActive: false
  property real cursorX: 0
  property real cursorY: 0
  property string cursorRaw: ""
  property var hoverPanels: []

  function normalizePosition(value) {
    var next = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(next) ? next : "top"
  }

  function clamp(value, min, max) {
    if (!isFinite(value)) return min
    return Math.max(min, Math.min(max, value))
  }

  function colorValue(value, fallback) {
    try {
      return Qt.color(String(value || fallback))
    } catch (e) {
      return Qt.color(fallback)
    }
  }

  function liveBarSize() {
    if (shell && shell.bar && ("barSize" in shell.bar)) {
      var size = Number(shell.bar.barSize)
      if (isFinite(size) && size > 0) return Math.round(size)
    }
    return fallbackBarSize
  }

  function screenNumber(screen, name, fallback) {
    var value = screen && screen[name] !== undefined ? Number(screen[name]) : Number(fallback)
    return isFinite(value) ? value : Number(fallback || 0)
  }

  function cursorInsideScreenBar(x, y, screen) {
    if (!screen) return false

    var sx = screenNumber(screen, "virtualX", 0)
    var sy = screenNumber(screen, "virtualY", 0)
    var sw = screenNumber(screen, "width", 0)
    var sh = screenNumber(screen, "height", 0)
    var size = Math.max(1, shadeSize)

    if (sw <= 0 || sh <= 0) return false

    if (barPosition === "top")
      return x >= sx && x < sx + sw && y >= sy && y < sy + size
    if (barPosition === "bottom")
      return x >= sx && x < sx + sw && y >= sy + sh - size && y < sy + sh
    if (barPosition === "left")
      return x >= sx && x < sx + size && y >= sy && y < sy + sh
    if (barPosition === "right")
      return x >= sx + sw - size && x < sx + sw && y >= sy && y < sy + sh

    return false
  }

  function cursorInsideAnyBar(x, y) {
    var panels = hoverPanels || []
    var count = panels.length || 0

    for (var i = 0; i < count; i++) {
      var panel = panels[i]
      if (panel && cursorInsideScreenBar(x, y, panel.screen)) return true
    }

    return false
  }

  function registerHoverPanel(panel) {
    if (!panel || hoverPanels.indexOf(panel) !== -1) return

    var next = hoverPanels.slice()
    next.push(panel)
    hoverPanels = next
  }

  function unregisterHoverPanel(panel) {
    var next = []
    var panels = hoverPanels || []
    for (var i = 0; i < panels.length; i++) {
      if (panels[i] !== panel) next.push(panels[i])
    }
    hoverPanels = next
  }

  function pollCursor() {
    if (!paintOverlay || cursorProc.running) return
    cursorProc.running = true
  }

  function applyCursorPosition(raw) {
    cursorRaw = String(raw || "").trim()
    var values = cursorRaw.match(/-?\d+(?:\.\d+)?/g)
    if (!values || values.length < 2) {
      cursorOverBar = false
      return
    }

    var x = Number(values[0])
    var y = Number(values[1])
    var inside = isFinite(x) && isFinite(y) && cursorInsideAnyBar(x, y)

    cursorX = x
    cursorY = y
    cursorOverBar = inside
    if (inside) {
      hoverGraceActive = true
      hoverGraceTimer.restart()
    }
  }

  function currentSettings() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (entry && String(entry.id || "") === pluginId) return entry
    }
    return {}
  }

  function setting(name, fallback) {
    var value = pluginSettings ? pluginSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function saveSettings(nextValues) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false

    var next = {}
    var current = pluginSettings || {}
    for (var key in current) {
      if (key !== "id") next[key] = current[key]
    }
    for (var nkey in nextValues) {
      if (nkey !== "id") next[nkey] = nextValues[nkey]
    }

    return shell.updateEntryInline(pluginId, next)
  }

  function setEffectEnabled(value) {
    saveSettings({ enabled: value === true })
    return value === true ? "enabled" : "disabled"
  }

  function setOpacity(rawValue) {
    var parsed = Number(rawValue)
    if (!isFinite(parsed)) return "invalid"

    var next = clamp(parsed, 0, 1)
    saveSettings({ opacity: next })
    return String(next)
  }

  function setColor(rawValue) {
    var next = String(rawValue || "").trim()
    if (next === "") return "invalid"

    try {
      Qt.color(next)
    } catch (e) {
      return "invalid"
    }

    saveSettings({ color: next })
    return next
  }

  function statusJson() {
    return JSON.stringify({
      enabled: effectEnabled,
      opacity: shadeOpacity,
      color: String(setting("color", "#000000")),
      barPosition: barPosition,
      barSize: shadeSize,
      barTransparent: barTransparent,
      barHidden: barHidden,
      mode: paintOverlay ? "overlay" : (effectActive && barTransparent ? "transparent-pass-through" : "off"),
      cursorOverBar: cursorOverBar,
      cursorX: cursorX,
      cursorY: cursorY,
      hoverPanelCount: hoverPanels.length || 0,
      undimmed: dimSuppressed,
      visible: paintOverlay
    })
  }

  onPaintOverlayChanged: {
    if (paintOverlay) {
      pollCursor()
    } else {
      cursorOverBar = false
      hoverGraceActive = false
      hoverGraceTimer.stop()
    }
  }

  Timer {
    id: hoverGraceTimer
    interval: 2500
    onTriggered: root.hoverGraceActive = false
  }

  Timer {
    interval: 250
    running: root.paintOverlay
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollCursor()
  }

  Process {
    id: cursorProc
    command: ["bash", "-lc", "hyprctl cursorpos 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCursorPosition(text)
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      visible: root.paintOverlay
      color: "transparent"
      implicitWidth: root.barVertical ? root.shadeSize : 0
      implicitHeight: root.barVertical ? 0 : root.shadeSize
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "b-omaled"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Component.onCompleted: root.registerHoverPanel(this)
      Component.onDestruction: root.unregisterHoverPanel(this)

      anchors {
        top: root.barPosition === "top" || root.barVertical
        bottom: root.barPosition === "bottom" || root.barVertical
        left: root.barPosition === "left" || !root.barVertical
        right: root.barPosition === "right" || !root.barVertical
      }

      Rectangle {
        anchors.fill: parent
        color: root.shadeColor
        opacity: root.overlayOpacity
      }
    }
  }

  IpcHandler {
    target: root.pluginId

    function status(): string {
      return root.statusJson()
    }

    function debug(): string {
      return root.statusJson()
    }

    function enable(): string {
      return root.setEffectEnabled(true)
    }

    function disable(): string {
      return root.setEffectEnabled(false)
    }

    function toggle(): string {
      return root.setEffectEnabled(!root.effectEnabled)
    }

    function opacity(value: string): string {
      return root.setOpacity(value)
    }

    function color(value: string): string {
      return root.setColor(value)
    }
  }
}
