import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.omasnap"
  property string selectedMode: service ? service.captureMode : "selection"

  readonly property var captureModes: [
    { value: "screen", label: "Screen", icon: "󰍹" },
    { value: "window", label: "Window", icon: "󰖲" },
    { value: "selection", label: "Selection", icon: "󰆞" },
    { value: "record-screen", label: "Record Screen", icon: "󰑋" },
    { value: "record-selection", label: "Record Selection", icon: "󰻂" }
  ]

  readonly property bool recordingMode: selectedMode === "record-screen" || selectedMode === "record-selection"
  readonly property bool recording: service && service.recording === true

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }

    if (payload.mode) selectedMode = String(payload.mode)
    else if (service && service.captureMode) selectedMode = service.captureMode

    opened = true
    if (service && typeof service.refreshStatus === "function") service.refreshStatus()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function setMode(mode) {
    selectedMode = String(mode || "selection")
    if (service && typeof service.setCaptureMode === "function")
      service.setCaptureMode(selectedMode)
  }

  function runSelected() {
    if (!service) return

    if (recording) {
      service.stopRecording()
      return
    }

    if (selectedMode === "record-screen") service.record("screen")
    else if (selectedMode === "record-selection") service.record("selection")
    else service.screenshot(selectedMode)
  }

  function toggleBoolean(name) {
    if (!service) return
    if (name === "cursor") service.setIncludeCursor(!service.includeCursor)
    else if (name === "thumbnail") service.setShowThumbnail(!service.showThumbnail)
    else if (name === "remember") service.setRememberSelection(!service.rememberSelection)
    else if (name === "desktopAudio") service.setRecordDesktopAudio(!service.recordDesktopAudio)
    else if (name === "microphoneAudio") service.setRecordMicrophoneAudio(!service.recordMicrophoneAudio)
    else if (name === "webcam") service.setRecordWebcam(!service.recordWebcam)
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "b-omasnap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: 0.72
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: toolbar
      width: Math.min(panel.width - Style.gapsOut * 2, Style.space(930))
      height: content.implicitHeight + Style.spacing.panelPadding * 2 + borderTop + borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(Style.gapsOut, Style.space(28))
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
      padding: Style.spacing.panelPadding
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.runSelected()
            event.accepted = true
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
            root.setMode(root.captureModes[event.key - Qt.Key_1].value)
            event.accepted = true
          }
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: toolbar.contentLeftInset
        anchors.rightMargin: toolbar.contentRightInset
        anchors.topMargin: toolbar.contentTopInset
        spacing: Style.spacing.md

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Text {
            width: parent.width - closeButton.width - parent.spacing
            text: "Omasnap"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelActionButton {
            id: closeButton
            iconText: "󰅖"
            tooltipText: "Close"
            foreground: Color.menu.text
            onClicked: root.dismiss()
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            model: root.captureModes

            Button {
              text: modelData.label
              iconText: modelData.icon
              selected: root.selectedMode === modelData.value
              foreground: Color.menu.text
              fontFamily: Style.font.menuFamily
              bordered: true
              onClicked: root.setMode(modelData.value)
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm

          Dropdown {
            width: Style.space(170)
            label: "Save"
            value: service ? service.outputMode : "file-and-clipboard"
            foreground: Color.menu.text
            background: Color.menu.background
            popupBorder: Color.menu.border
            options: [
              { value: "file-and-clipboard", label: "File + Clipboard" },
              { value: "file", label: "File" },
              { value: "clipboard", label: "Clipboard" },
              { value: "editor", label: "Editor" }
            ]
            onChanged: function(value) { if (service) service.setOutputMode(value) }
          }

          Dropdown {
            width: Style.space(150)
            label: "Location"
            value: service ? service.saveLocation : "pictures"
            foreground: Color.menu.text
            background: Color.menu.background
            popupBorder: Color.menu.border
            options: [
              { value: "pictures", label: "Pictures" },
              { value: "desktop", label: "Desktop" },
              { value: "documents", label: "Documents" },
              { value: "downloads", label: "Downloads" }
            ]
            onChanged: function(value) { if (service) service.setSaveLocation(value) }
          }

          Dropdown {
            width: Style.space(110)
            label: "Timer"
            value: service ? String(service.timerSeconds) : "0"
            foreground: Color.menu.text
            background: Color.menu.background
            popupBorder: Color.menu.border
            options: [
              { value: "0", label: "None" },
              { value: "5", label: "5 sec" },
              { value: "10", label: "10 sec" }
            ]
            onChanged: function(value) { if (service) service.setTimer(value) }
          }

          Button {
            text: "Pointer"
            iconText: "󰆿"
            selected: service && service.includeCursor
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("cursor")
          }

          Button {
            text: "Thumbnail"
            iconText: "󰋩"
            selected: !service || service.showThumbnail
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("thumbnail")
          }

          Button {
            text: "Remember"
            iconText: "󰆓"
            selected: !service || service.rememberSelection
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("remember")
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.recordingMode || root.recording

          Button {
            text: "Desktop Audio"
            iconText: "󰓃"
            selected: service && service.recordDesktopAudio
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("desktopAudio")
          }

          Button {
            text: "Microphone"
            iconText: "󰍬"
            selected: service && service.recordMicrophoneAudio
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("microphoneAudio")
          }

          Button {
            text: "Webcam"
            iconText: "󰄀"
            selected: service && service.recordWebcam
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: root.toggleBoolean("webcam")
          }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Button {
            text: root.recording ? "Stop Recording" : (root.recordingMode ? "Record" : "Capture")
            iconText: root.recording ? "󰓛" : (root.recordingMode ? "󰑋" : "")
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            selected: true
            horizontalPadding: Style.spacing.lg
            onClicked: root.runSelected()
          }

          Button {
            text: "Open Last"
            iconText: "󰈙"
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            bordered: true
            onClicked: if (service) service.openLast()
          }
        }
      }
    }
  }
}
