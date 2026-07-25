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
  readonly property string ruleHandleName: "__b_peek_floating_windows_rule"

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

  function luaQuote(value) {
    return "'" + String(value)
      .replace(/\\/g, "\\\\")
      .replace(/'/g, "\\'")
      .replace(/\n/g, "\\n")
      + "'"
  }

  function ruleLua(targetEnabled) {
    var lines = [
      "do",
      "  local key = " + luaQuote(ruleHandleName),
      "  local rule = rawget(_G, key)",
      "  if rule == nil then",
      "    rule = hl.window_rule({",
      "      name = " + luaQuote(ruleName) + ",",
      "      match = { float = true },",
      "      opacity = '0.1 override',",
      "      no_blur = true,",
      "      no_focus = true,",
      "      no_follow_mouse = true,",
      "    })",
      "    rawset(_G, key, rule)",
      "  end",
      "  rule:set_enabled(" + (targetEnabled ? "true" : "false") + ")",
      "end"
    ]
    return lines.join("\n")
  }

  function detachedDisable() {
    Quickshell.execDetached(["hyprctl", "eval", ruleLua(false)])
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
    actionProcess.command = ["hyprctl", "eval", ruleLua(targetEnabled)]
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
      ruleHandleName: ruleHandleName,
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
