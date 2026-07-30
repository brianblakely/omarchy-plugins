import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || homeDir + "/.local/share"
  readonly property string desktopPath: dataHome + "/applications/b.okomart.desktop"
  readonly property string shellConfigPath: homeDir + "/.config/omarchy/shell.json"
  readonly property string desktopSourcePath: localPath(Qt.resolvedUrl("assets/b.okomart.desktop"))
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/bin/okomart" : ""

  // Keep these scripts as single JSON-compatible string literals. The isolated
  // launcher test extracts and executes the exact same text used at runtime.
  readonly property string installScript: "set -euo pipefail\nsource_file=$1\ntarget=$2\nif [[ -L \"$target\" || (-e \"$target\" && ! -f \"$target\") ]]; then\n  printf 'Okomart: refusing to replace non-regular launcher: %s\\n' \"$target\" >&2\n  exit 1\nfi\nif [[ -f \"$target\" ]] && ! grep -Fqx 'X-Okomart-Managed=true' \"$target\"; then\n  printf 'Okomart: refusing to replace an unowned launcher: %s\\n' \"$target\" >&2\n  exit 1\nfi\nmkdir -p -- \"$(dirname -- \"$target\")\"\ntmp=$(mktemp -- \"${target}.tmp.XXXXXX\")\ncleanup() { rm -f -- \"$tmp\"; }\ntrap cleanup EXIT\ninstall -m 0644 -- \"$source_file\" \"$tmp\"\nmv -f -- \"$tmp\" \"$target\"\ntrap - EXIT"
  readonly property string cleanupScript: "set -euo pipefail\ntarget=$1\nconfig=$2\nsleep 0.1\n[[ -f \"$target\" && ! -L \"$target\" ]] || exit 0\ngrep -Fqx 'X-Okomart-Managed=true' \"$target\" || exit 0\nif [[ -e \"$config\" ]]; then\n  command -v jq >/dev/null 2>&1 || exit 0\n  jq -e . \"$config\" >/dev/null 2>&1 || exit 0\n  jq -e --arg id 'b.okomart' 'any((.plugins // [])[]; (.id // \"\") == $id)' \"$config\" >/dev/null 2>&1 && exit 0\nfi\nrm -f -- \"$target\""

  property string launcherState: "starting"
  property string launcherError: ""
  property bool selfRecoveryStarted: false

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
    launcherState = "installing"
    launcherError = ""
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

  Process {
    id: launcherInstaller

    stderr: StdioCollector {
      id: launcherStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.launcherState = "installed"
        root.launcherError = ""
      } else {
        root.launcherState = "error"
        root.launcherError = launcherStderr.text.trim()
        console.warn("Okomart: could not install app launcher:", root.launcherError)
      }
    }
  }

  onHelperPathChanged: recoverSelfUpdate()

  Component.onCompleted: {
    installLauncher()
    recoverSelfUpdate()
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
