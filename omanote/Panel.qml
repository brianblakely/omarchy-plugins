import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "b.omanote"
  ipcTarget: "b.omanote"
  manageIpc: false

  property var anchorItem: null
  property var host: null
  property string noteText: ""
  property string savedText: ""
  property string savePath: ""
  property string savingText: ""
  property string lookupOutput: ""
  property string lookupError: ""
  property string storageStatus: "idle"
  property bool loaded: false
  property bool saveQueued: false
  property bool tempWriteFailed: false

  readonly property bool dirty: noteText !== savedText
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property int desiredPanelSize: Style.space(360)
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string statusText: storageStatus === "loading" ? "Loading"
    : storageStatus === "saving" ? "Saving"
    : storageStatus === "error" ? "Storage unavailable"
    : dirty ? "Unsaved" : "Saved"

  function fittedPanelSize(panel) {
    var maxWidth = panel.availableCardWidth > 0 ? panel.availableCardWidth : desiredPanelSize
    var maxHeight = panel.availableCardHeight > 0 ? panel.availableCardHeight : desiredPanelSize
    return Math.round(Math.max(Style.space(220), Math.min(desiredPanelSize, maxWidth, maxHeight)))
  }

  function loadScript() {
    return "command -v secret-tool >/dev/null 2>&1 || { echo 'secret-tool not found' >&2; exit 127; }\n"
      + "secret-tool lookup omarchy-plugin b.omanote field note"
  }

  function storeScript() {
    return "path=$1\n"
      + "if ! command -v secret-tool >/dev/null 2>&1; then\n"
      + "  echo 'secret-tool not found' >&2\n"
      + "  rm -f -- \"$path\"\n"
      + "  exit 127\n"
      + "fi\n"
      + "secret-tool store --label='Omanote note' omarchy-plugin b.omanote field note < \"$path\"\n"
      + "status=$?\n"
      + "rm -f -- \"$path\"\n"
      + "exit \"$status\""
  }

  function clearScript() {
    return "command -v secret-tool >/dev/null 2>&1 || { echo 'secret-tool not found' >&2; exit 127; }\n"
      + "secret-tool clear omarchy-plugin b.omanote field note"
  }

  function tempPath() {
    if (runtimeDir === "") return ""
    return runtimeDir + "/omanote-"
      + Date.now().toString(36)
      + "-"
      + Math.floor(Math.random() * 0x100000000).toString(36)
      + ".txt"
  }

  function focusEditor() {
    noteArea.forceActiveFocus()
    noteArea.cursorPosition = noteArea.text.length
  }

  function open() {
    root.controller.show()
    if (!loaded && !lookupProc.running) loadNote()
    Qt.callLater(focusEditor)
  }

  function close() {
    saveTimer.stop()
    if (dirty) saveNow()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function updateText(value) {
    noteText = String(value || "")
    if (!loaded || storageStatus === "loading") return
    saveTimer.restart()
  }

  function loadNote() {
    lookupOutput = ""
    lookupError = ""
    storageStatus = "loading"
    lookupProc.command = ["bash", "-lc", loadScript(), "omanote-load"]
    lookupProc.running = true
  }

  function applyLoadedText(exitCode) {
    var error = String(lookupError || "").trim()
    if (exitCode === 0 || error === "") {
      var text = exitCode === 0 ? String(lookupOutput || "") : ""
      noteText = text
      savedText = text
      loaded = true
      storageStatus = "ready"
      return
    }

    loaded = true
    storageStatus = "error"
  }

  function saveNow() {
    if (!loaded || storageStatus === "loading") return
    if (!dirty && storageStatus !== "error") return

    if (storeProc.running || clearProc.running) {
      saveQueued = true
      return
    }

    savingText = noteText
    storageStatus = "saving"

    if (savingText === "") {
      clearProc.command = ["bash", "-lc", clearScript(), "omanote-clear"]
      clearProc.running = true
      return
    }

    var path = tempPath()
    if (path === "") {
      storageStatus = "error"
      return
    }

    // Secret-tool needs EOF for multiline stdin. The transient source file
    // lives only in the user's runtime tmpfs and is deleted by storeScript().
    savePath = path
    tempWriteFailed = false
    saveFile.setText(savingText)
    if (tempWriteFailed) {
      storageStatus = "error"
      return
    }

    storeProc.command = ["bash", "-lc", storeScript(), "omanote-store", path]
    storeProc.running = true
  }

  function finishSave(exitCode) {
    savePath = ""

    if (exitCode === 0) {
      savedText = savingText
      storageStatus = noteText === savedText ? "ready" : "saving"
    } else {
      storageStatus = "error"
    }

    savingText = ""

    if (saveQueued || (storageStatus !== "error" && noteText !== savedText)) {
      saveQueued = false
      Qt.callLater(saveNow)
    }
  }

  onOpenedChanged: {
    if (opened) {
      if (!loaded && !lookupProc.running) loadNote()
      Qt.callLater(focusEditor)
    } else if (dirty) {
      saveTimer.stop()
      saveNow()
    }
  }

  Component.onCompleted: loadNote()

  IpcHandler {
    target: root.ipcTarget
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  Timer {
    id: saveTimer
    interval: 650
    repeat: false
    onTriggered: root.saveNow()
  }

  FileView {
    id: saveFile
    path: root.savePath
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onSaveFailed: root.tempWriteFailed = true
  }

  Process {
    id: lookupProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lookupOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lookupError = text
    }
    onExited: function(exitCode) { root.applyLoadedText(exitCode) }
  }

  Process {
    id: storeProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) { root.finishSave(exitCode) }
  }

  Process {
    id: clearProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) { root.finishSave(exitCode) }
  }

  KeyboardPanel {
    id: notePanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: noteArea
    contentWidth: root.fittedPanelSize(notePanel)
    contentHeight: root.fittedPanelSize(notePanel)

    Item {
      anchors.fill: parent

      QQC.ScrollView {
        id: editorScroll
        anchors {
          top: parent.top
          left: parent.left
          right: parent.right
          bottom: footer.top
          bottomMargin: Style.space(10)
        }
        clip: true
        contentWidth: availableWidth
        contentHeight: Math.max(availableHeight, noteArea.implicitHeight)
        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: QQC.ScrollBar.AsNeeded
        }
        QQC.ScrollBar.horizontal: QQC.ScrollBar {
          policy: QQC.ScrollBar.AlwaysOff
        }

        background: Rectangle {
          color: Style.normalFillFor(root.foreground, Color.accent)
          border.color: Style.normalBorderFor(root.foreground, Color.accent)
          border.width: Math.max(1, Style.normalBorderWidth)
          radius: Math.min(Style.cornerRadius, Style.space(6))
        }

        QQC.TextArea {
          id: noteArea
          width: editorScroll.availableWidth
          height: Math.max(editorScroll.availableHeight, implicitHeight)
          text: root.noteText
          placeholderText: root.storageStatus === "error" ? "Keyring unavailable" : ""
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          persistentSelection: true
          color: root.foreground
          selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
          selectedTextColor: root.foreground
          placeholderTextColor: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          background: null
          enabled: root.storageStatus !== "loading"
          onTextChanged: if (text !== root.noteText) root.updateText(text)
          Keys.onEscapePressed: root.close()
        }
      }

      Row {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(statusLabel.implicitHeight, saveButton.implicitHeight)
        spacing: Style.space(8)

        Text {
          id: statusLabel
          width: Math.max(1, parent.width - saveButton.implicitWidth - parent.spacing)
          anchors.verticalCenter: parent.verticalCenter
          text: root.statusText
          color: root.storageStatus === "error" ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }

        Button {
          id: saveButton
          anchors.verticalCenter: parent.verticalCenter
          text: "Save"
          foreground: root.foreground
          accent: Color.accent
          selected: root.dirty
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(4)
          onClicked: {
            saveTimer.stop()
            root.saveNow()
            root.focusEditor()
          }
        }
      }
    }
  }
}
