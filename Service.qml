import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "b.okomart"
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || homeDir + "/.local/share"
  readonly property string desktopPath: dataHome + "/applications/b.okomart.desktop"
  readonly property string shellConfigPath: homeDir + "/.config/omarchy/shell.json"
  readonly property string desktopSourcePath: localPath(Qt.resolvedUrl("assets/b.okomart.desktop"))
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/bin/okomart" : ""

  // Keep each launcher mutation in one guarded shell so validation and atomic
  // replacement operate on the same resolved target.
  readonly property string installScript: "set -euo pipefail\nsource_file=$1\ntarget=$2\nif [[ -L \"$target\" || (-e \"$target\" && ! -f \"$target\") ]]; then\n  printf 'Okomart: refusing to replace non-regular launcher: %s\\n' \"$target\" >&2\n  exit 1\nfi\nif [[ -f \"$target\" ]] && ! grep -Fqx 'X-Okomart-Managed=true' \"$target\"; then\n  printf 'Okomart: refusing to replace an unowned launcher: %s\\n' \"$target\" >&2\n  exit 1\nfi\nmkdir -p -- \"$(dirname -- \"$target\")\"\ntmp=$(mktemp -- \"${target}.tmp.XXXXXX\")\ncleanup() { rm -f -- \"$tmp\"; }\ntrap cleanup EXIT\ninstall -m 0644 -- \"$source_file\" \"$tmp\"\nmv -f -- \"$tmp\" \"$target\"\ntrap - EXIT"
  readonly property string cleanupScript: "set -euo pipefail\ntarget=$1\nconfig=$2\nsleep 0.1\n[[ -f \"$target\" && ! -L \"$target\" ]] || exit 0\ngrep -Fqx 'X-Okomart-Managed=true' \"$target\" || exit 0\nif [[ -e \"$config\" ]]; then\n  command -v jq >/dev/null 2>&1 || exit 0\n  jq -e . \"$config\" >/dev/null 2>&1 || exit 0\n  jq -e --arg id 'b.okomart' 'any((.plugins // [])[]; (.id // \"\") == $id)' \"$config\" >/dev/null 2>&1 && exit 0\nfi\nrm -f -- \"$target\""

  property bool selfRecoveryStarted: false
  // The service outlives the summoned panel, so it can capture mode changes
  // before Hyprland closes the panel window and the panel loader unloads it.
  property string okomartWindowAddress: ""

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    try {
      return decodeURIComponent(value)
    } catch (error) {
      return value
    }
  }

  function installLauncher() {
    if (!desktopSourcePath || !desktopPath || launcherInstaller.running) return
    launcherInstaller.command = [
      "bash",
      "-c",
      installScript,
      "okomart-launcher-install",
      desktopSourcePath,
      desktopPath
    ]
    launcherInstaller.running = true
  }

  function recoverSelfUpdate() {
    if (selfRecoveryStarted || !helperPath || !sourceDir) return
    selfRecoveryStarted = true
    Quickshell.execDetached([helperPath, "_recover-self-update", sourceDir])
  }

  function eventParts(event, count) {
    try {
      if (event && event.parse) return event.parse(count)
    } catch (error) {
    }
    return String(event && event.data ? event.data : "").split(",")
  }

  function normalizedWindowAddress(value) {
    var address = String(value || "").toLowerCase()
    return address.indexOf("0x") === 0 ? address.slice(2) : address
  }

  function isOkomartWindow(windowClass, title) {
    return String(windowClass || "") === "org.quickshell"
      && String(title || "") === "Okomart"
  }

  function pluginSettings() {
    var settings = ({})
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (!entry || String(entry.id || "") !== pluginId) continue
      for (var key in entry) if (key !== "id") settings[key] = entry[key]
      break
    }
    return settings
  }

  function rememberWindowMode(mode) {
    if (mode !== "floating" && mode !== "tiled") return
    if (!shell || typeof shell.updateEntryInline !== "function") {
      console.warn("Okomart: shell cannot persist window mode:", mode)
      return
    }

    var settings = pluginSettings()
    if (settings.windowMode === mode) return
    settings.windowMode = mode
    if (!shell.updateEntryInline(pluginId, settings))
      console.warn("Okomart: shell.json has no Okomart plugin entry")
  }

  function ensureWindowModeSetting() {
    var mode = pluginSettings().windowMode
    if (mode === "floating" || mode === "tiled") return
    rememberWindowMode("floating")
  }

  function enforceMappedWindowMode() {
    if (!helperPath) return
    // The service receives Hyprland's real map event, so this mode-only pass
    // closes the first-use race even if the panel toplevel predated its rule.
    Quickshell.execDetached([helperPath, "apply-window-mode", "0"])
  }

  function trackActiveOkomartWindow() {
    var toplevel = Hyprland.activeToplevel
    if (!toplevel) return
    var ipc = toplevel.lastIpcObject || ({})
    if (!isOkomartWindow(ipc.class, toplevel.title)) return
    okomartWindowAddress = normalizedWindowAddress(toplevel.address)
    if (typeof ipc.floating === "boolean")
      rememberWindowMode(ipc.floating ? "floating" : "tiled")
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openwindow") {
      var opened = eventParts(event, 4)
      if (isOkomartWindow(opened[2], opened[3])) {
        okomartWindowAddress = normalizedWindowAddress(opened[0])
        ensureWindowModeSetting()
        enforceMappedWindowMode()
      }
    } else if (name === "changefloatingmode") {
      var changed = eventParts(event, 2)
      if (normalizedWindowAddress(changed[0]) !== okomartWindowAddress) return
      if (String(changed[1]) === "1") rememberWindowMode("floating")
      else if (String(changed[1]) === "0") rememberWindowMode("tiled")
    } else if (name === "closewindow") {
      var closed = eventParts(event, 1)
      if (normalizedWindowAddress(closed[0]) === okomartWindowAddress)
        okomartWindowAddress = ""
    }
  }

  Process {
    id: launcherInstaller

    stderr: StdioCollector {
      id: launcherStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("Okomart: could not install app launcher:",
          launcherStderr.text.trim())
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
    function onActiveToplevelChanged() {
      Qt.callLater(root.trackActiveOkomartWindow)
    }
  }

  onHelperPathChanged: recoverSelfUpdate()

  Component.onCompleted: {
    installLauncher()
    recoverSelfUpdate()
    Qt.callLater(trackActiveOkomartWindow)
  }

  Component.onDestruction: {
    // Plugin reloads also destroy services. The detached cleanup re-reads the
    // canonical user config and leaves the entry alone while Okomart remains
    // enabled; disable/removal is the only normal path that removes it. If the
    // shell is not running during removal, this callback cannot run, so the
    // desktop entry also verifies the checkout and self-cleans when invoked.
    Quickshell.execDetached([
      "bash",
      "-c",
      cleanupScript,
      "okomart-launcher-cleanup",
      desktopPath,
      shellConfigPath
    ])
  }
}
