import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string ruleName: "b-peek-floating-windows"
  readonly property var ruleKeywords: [
    "windowrule[" + ruleName + "]:match:float true",
    "windowrule[" + ruleName + "]:opacity 0.1 override",
    "windowrule[" + ruleName + "]:no_blur on",
    "windowrule[" + ruleName + "]:no_focus on",
    "windowrule[" + ruleName + "]:no_follow_mouse on"
  ]

  property bool enabled: false
  property bool desiredEnabled: false
  property bool ruleInstalled: false
  property bool queued: false
  property bool actionTargetEnabled: false
  property string state: "starting"
  property string lastError: ""
  property string lastOutput: ""
  property string lastChangedAt: ""

  function nowIso() {
    return new Date().toISOString()
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function keywordCommand(keyword) {
    return "hyprctl keyword " + shellQuote(keyword)
  }

  function scriptFor(targetEnabled) {
    var lines = ["set -e"]
    for (var i = 0; i < ruleKeywords.length; i++)
      lines.push(keywordCommand(ruleKeywords[i]))
    lines.push(keywordCommand("windowrule[" + ruleName + "]:enable " + (targetEnabled ? "true" : "false")))
    return lines.join("\n")
  }

  function detachedDisable() {
    Quickshell.execDetached(["bash", "-lc", scriptFor(false)])
  }

  function setState(nextState) {
    state = nextState
    lastChangedAt = nowIso()
  }

  function runApply(targetEnabled) {
    if (actionProcess.running) {
      desiredEnabled = targetEnabled
      queued = true
      return "queued"
    }

    desiredEnabled = targetEnabled
    actionTargetEnabled = targetEnabled
    queued = false
    lastError = ""
    lastOutput = ""
    setState(targetEnabled ? "enabling" : "disabling")
    actionProcess.command = ["bash", "-lc", scriptFor(targetEnabled)]
    actionProcess.running = true
    return targetEnabled ? "enabling" : "disabling"
  }

  function applyDesired() {
    return runApply(desiredEnabled)
  }

  function enable() {
    return runApply(true)
  }

  function disable() {
    return runApply(false)
  }

  function toggle() {
    return runApply(!desiredEnabled)
  }

  function statusJson() {
    return JSON.stringify({
      enabled: enabled,
      desiredEnabled: desiredEnabled,
      state: state,
      running: actionProcess.running,
      queued: queued,
      ruleName: ruleName,
      ruleInstalled: ruleInstalled,
      lastError: lastError,
      lastOutput: lastOutput,
      lastChangedAt: lastChangedAt
    })
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "configreloaded" && desiredEnabled)
      Qt.callLater(applyDesired)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Process {
    id: actionProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastOutput = text
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = text
    }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.enabled = root.actionTargetEnabled
        root.ruleInstalled = true
        root.setState(root.enabled ? "enabled" : "disabled")
        if (!root.queued) root.desiredEnabled = root.actionTargetEnabled
      } else {
        root.setState("error")
      }

      if (root.queued && root.desiredEnabled !== root.enabled) {
        Qt.callLater(root.applyDesired)
      } else {
        root.queued = false
      }
    }
  }

  Component.onCompleted: {
    disable()
  }

  Component.onDestruction: {
    if (enabled || ruleInstalled || actionProcess.running)
      detachedDisable()
  }

  IpcHandler {
    target: "b.peek"

    function status(): string {
      return root.statusJson()
    }

    function debug(): string {
      return root.statusJson()
    }

    function enable(): string {
      return root.enable()
    }

    function disable(): string {
      return root.disable()
    }

    function toggle(): string {
      return root.toggle()
    }
  }
}
