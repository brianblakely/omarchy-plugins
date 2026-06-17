import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.omasnap"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/omasnap" : Qt.resolvedUrl("omasnap").toString().replace(/^file:\/\//, "")

  readonly property var pluginSettings: currentSettings()
  readonly property string captureMode: setting("captureMode", "selection")
  readonly property string outputMode: setting("outputMode", "file-and-clipboard")
  readonly property string saveLocation: setting("saveLocation", "pictures")
  readonly property int timerSeconds: clampInt(setting("timerSeconds", 0), 0, 60)
  readonly property bool includeCursor: setting("includeCursor", false) === true
  readonly property bool showThumbnail: setting("showThumbnail", true) !== false
  readonly property bool rememberSelection: setting("rememberSelection", true) !== false
  readonly property bool recordDesktopAudio: setting("recordDesktopAudio", false) === true
  readonly property bool recordMicrophoneAudio: setting("recordMicrophoneAudio", false) === true
  readonly property bool recordWebcam: setting("recordWebcam", false) === true
  readonly property string editorCommand: setting("editorCommand", "tensaku-edit")

  property bool recording: false
  property string lastStatus: "{}"

  function clampInt(value, min, max) {
    var parsed = parseInt(value, 10)
    if (!isFinite(parsed)) parsed = min
    return Math.max(min, Math.min(max, parsed))
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

  function boolArg(name, value) {
    return "--" + name + "=" + (value === true ? "true" : "false")
  }

  function commonArgs(outputOverride) {
    return [
      "--output-mode=" + String(outputOverride || outputMode),
      "--save-location=" + String(saveLocation || "pictures"),
      "--timer=" + String(timerSeconds),
      boolArg("cursor", includeCursor),
      boolArg("thumbnail", showThumbnail),
      boolArg("remember", rememberSelection),
      "--editor=" + String(editorCommand || "tensaku-edit")
    ]
  }

  function recordingArgs() {
    var args = commonArgs("")
    if (recordDesktopAudio) args.push("--desktop-audio")
    if (recordMicrophoneAudio) args.push("--microphone-audio")
    if (recordWebcam) args.push("--webcam")
    return args
  }

  function runDetached(args) {
    if (!helperPath) return "missing-helper"
    Quickshell.execDetached(["bash", helperPath].concat(args))
    return "ok"
  }

  function show() {
    if (shell && typeof shell.summon === "function")
      return shell.summon(pluginId, "{}") ? "ok" : "unknown"
    return "unknown"
  }

  function hide() {
    if (shell && typeof shell.hide === "function") {
      shell.hide(pluginId)
      return "ok"
    }
    return "unknown"
  }

  function toggle() {
    if (shell && typeof shell.toggle === "function") {
      shell.toggle(pluginId, "{}")
      return "ok"
    }
    return "unknown"
  }

  function showTargetPicker(action, regionOnly) {
    if (shell && typeof shell.summon === "function") {
      var payload = JSON.stringify({
        action: String(action || "file"),
        regionOnly: regionOnly === true
      })
      return shell.summon(pluginId, payload) ? "ok" : "unknown"
    }
    return "unknown"
  }

  function showRegionPicker(action) {
    return showTargetPicker(action || "file", true)
  }

  function screenshot(mode, outputOverride) {
    saveSettings({ captureMode: String(mode || captureMode || "selection") })
    hide()
    return runDetached(["screenshot", String(mode || captureMode || "selection")].concat(commonArgs(outputOverride || "")))
  }

  function screenshotGeometry(geometry, screenName, outputOverride) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    saveSettings({ captureMode: "selection" })
    hide()

    var args = ["screenshot", "selection", "--geometry=" + selectedGeometry]
    if (screenName) args.push("--screen-name=" + String(screenName))
    return runDetached(args.concat(commonArgs(outputOverride || "")))
  }

  function recordGeometry(geometry, screenName) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    saveSettings({ captureMode: "record-selection" })
    hide()

    var args = ["record", "selection", "--geometry=" + selectedGeometry]
    if (screenName) args.push("--screen-name=" + String(screenName))
    return runDetached(args.concat(recordingArgs()))
  }

  function record(mode) {
    var target = String(mode || "selection")
    saveSettings({ captureMode: target === "screen" ? "record-screen" : "record-selection" })
    hide()
    return runDetached(["record", target].concat(recordingArgs()))
  }

  function stopRecording() {
    hide()
    return runDetached(["stop-recording"])
  }

  function toggleRecording() {
    hide()
    return runDetached(["toggle-recording", "selection"].concat(recordingArgs()))
  }

  function captureToFile() {
    return showTargetPicker("file")
  }

  function captureToClipboard() {
    return showTargetPicker("clipboard")
  }

  function recordPicker() {
    return showTargetPicker("record")
  }

  function captureSelection() {
    return showRegionPicker("file")
  }

  function copySelection() {
    return showRegionPicker("clipboard")
  }

  function recordSelection() {
    return showRegionPicker("record")
  }

  function openLast() {
    return runDetached(["open-last"])
  }

  function statusJson() {
    return JSON.stringify({
      recording: recording,
      captureMode: captureMode,
      outputMode: outputMode,
      saveLocation: saveLocation,
      timerSeconds: timerSeconds,
      includeCursor: includeCursor,
      showThumbnail: showThumbnail,
      rememberSelection: rememberSelection,
      recordDesktopAudio: recordDesktopAudio,
      recordMicrophoneAudio: recordMicrophoneAudio,
      recordWebcam: recordWebcam,
      helperPath: helperPath,
      lastStatus: lastStatus
    })
  }

  function refreshStatus() {
    if (statusProc.running || !helperPath) return
    statusProc.command = ["bash", helperPath, "status"]
    statusProc.running = true
  }

  function setCaptureMode(value) {
    var next = String(value || "selection")
    saveSettings({ captureMode: next })
    return next
  }

  function setOutputMode(value) {
    var next = String(value || "file-and-clipboard")
    saveSettings({ outputMode: next })
    return next
  }

  function setSaveLocation(value) {
    var next = String(value || "pictures")
    saveSettings({ saveLocation: next })
    return next
  }

  function setTimer(value) {
    var next = clampInt(value, 0, 60)
    saveSettings({ timerSeconds: next })
    return String(next)
  }

  function setIncludeCursor(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ includeCursor: next })
    return next ? "true" : "false"
  }

  function setShowThumbnail(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ showThumbnail: next })
    return next ? "true" : "false"
  }

  function setRememberSelection(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ rememberSelection: next })
    return next ? "true" : "false"
  }

  function setRecordDesktopAudio(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordDesktopAudio: next })
    return next ? "true" : "false"
  }

  function setRecordMicrophoneAudio(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordMicrophoneAudio: next })
    return next ? "true" : "false"
  }

  function setRecordWebcam(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordWebcam: next })
    return next ? "true" : "false"
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastStatus = String(text || "{}").trim() || "{}"
        try {
          var parsed = JSON.parse(root.lastStatus)
          root.recording = parsed.recording === true
        } catch (e) {
          root.recording = false
        }
      }
    }
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "show"
    description: "Show Omasnap"
    onPressed: root.show()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-screen"
    description: "Omasnap capture screen"
    onPressed: root.screenshot("screen")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-selection"
    description: "Omasnap capture selection"
    onPressed: root.captureSelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-window"
    description: "Omasnap capture window"
    onPressed: root.screenshot("window")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "copy-screen"
    description: "Omasnap copy screen"
    onPressed: root.screenshot("screen", "clipboard")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "copy-selection"
    description: "Omasnap copy selection"
    onPressed: root.copySelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "record-screen"
    description: "Omasnap record screen"
    onPressed: root.record("screen")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "record-selection"
    description: "Omasnap record selection"
    onPressed: root.recordSelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "stop-recording"
    description: "Omasnap stop recording"
    onPressed: root.stopRecording()
  }

  IpcHandler {
    target: root.pluginId

    function show(): string { return root.show() }
    function hide(): string { return root.hide() }
    function toggle(): string { return root.toggle() }
    function status(): string { root.refreshStatus(); return root.statusJson() }
    function debug(): string { root.refreshStatus(); return root.statusJson() }

    function screenshot(mode: string): string { return root.screenshot(mode || "selection") }
    function record(mode: string): string { return String(mode || "") === "" ? root.recordPicker() : root.record(mode) }

    function captureToFile(): string { return root.captureToFile() }
    function captureToClipboard(): string { return root.captureToClipboard() }

    function captureScreen(): string { return root.screenshot("screen") }
    function captureDisplay(): string { return root.screenshot("display") }
    function captureSelection(): string { return root.captureSelection() }
    function captureWindow(): string { return root.screenshot("window") }
    function captureActiveWindow(): string { return root.screenshot("active-window") }
    function captureLastSelection(): string { return root.screenshot("last") }

    function copyScreen(): string { return root.screenshot("screen", "clipboard") }
    function copySelection(): string { return root.copySelection() }
    function copyWindow(): string { return root.screenshot("window", "clipboard") }

    function recordScreen(): string { return root.record("screen") }
    function recordSelection(): string { return root.recordSelection() }
    function stopRecording(): string { return root.stopRecording() }
    function toggleRecording(): string { return root.toggleRecording() }
    function openLast(): string { return root.openLast() }

    function outputMode(value: string): string { return root.setOutputMode(value) }
    function saveLocation(value: string): string { return root.setSaveLocation(value) }
    function timer(value: string): string { return root.setTimer(value) }
    function cursor(value: string): string { return root.setIncludeCursor(value) }
    function thumbnail(value: string): string { return root.setShowThumbnail(value) }
    function remember(value: string): string { return root.setRememberSelection(value) }
    function desktopAudio(value: string): string { return root.setRecordDesktopAudio(value) }
    function microphoneAudio(value: string): string { return root.setRecordMicrophoneAudio(value) }
    function webcam(value: string): string { return root.setRecordWebcam(value) }
  }
}
