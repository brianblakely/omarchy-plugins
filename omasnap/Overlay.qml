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
  property bool hasSelection: false
  property int selectionX: 0
  property int selectionY: 0
  property int selectionW: 1
  property int selectionH: 1
  property string selectionScreenName: ""
  property string pointerAction: ""
  property int pointerStartX: 0
  property int pointerStartY: 0
  property int pointerSelectionX: 0
  property int pointerSelectionY: 0
  property int pointerSelectionW: 1
  property int pointerSelectionH: 1
  property int pointerAnchorX: 0
  property int pointerAnchorY: 0

  readonly property var captureModes: [
    { value: "screen", label: "Screen", icon: "󰍹" },
    { value: "window", label: "Window", icon: "󰖲" },
    { value: "selection", label: "Selection", icon: "󰆞" },
    { value: "record-screen", label: "Record Screen", icon: "󰑋" },
    { value: "record-selection", label: "Record Selection", icon: "󰻂" }
  ]

  readonly property bool recordingMode: selectedMode === "record-screen" || selectedMode === "record-selection"
  readonly property bool recording: service && service.recording === true
  readonly property bool regionEditor: selectedMode === "selection"
  readonly property int minimumSelectionSize: 1

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }

    if (payload.mode) selectedMode = String(payload.mode)
    else if (service && service.captureMode) selectedMode = service.captureMode

    opened = true
    if (service && typeof service.refreshStatus === "function") service.refreshStatus()
    if (regionEditor && service && service.rememberSelection !== true) hasSelection = false
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

  function runSelected(screenName) {
    if (!service) return

    if (recording) {
      service.stopRecording()
      return
    }

    if (selectedMode === "selection" && hasSelection && typeof service.screenshotGeometry === "function")
      service.screenshotGeometry(selectionGeometry(), screenName || selectionScreenName || "")
    else if (selectedMode === "record-screen") service.record("screen")
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

  function panelScreenName(panel) {
    return panel && panel.screen && panel.screen.name ? String(panel.screen.name) : ""
  }

  function clamp(value, min, max) {
    value = Math.round(Number(value) || 0)
    min = Math.round(Number(min) || 0)
    max = Math.round(Number(max) || 0)
    if (max < min) max = min
    return Math.max(min, Math.min(max, value))
  }

  function setSelection(x, y, width, height, maxWidth, maxHeight) {
    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var nextW = clamp(width, minimumSelectionSize, maxW)
    var nextH = clamp(height, minimumSelectionSize, maxH)

    selectionX = clamp(x, 0, maxW - nextW)
    selectionY = clamp(y, 0, maxH - nextH)
    selectionW = nextW
    selectionH = nextH
    hasSelection = true
  }

  function setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, activeEdge) {
    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var l = clamp(left, 0, maxW - minimumSelectionSize)
    var t = clamp(top, 0, maxH - minimumSelectionSize)
    var r = clamp(right, minimumSelectionSize, maxW)
    var b = clamp(bottom, minimumSelectionSize, maxH)

    if (r - l < minimumSelectionSize) {
      if (String(activeEdge || "").indexOf("w") >= 0) l = Math.max(0, r - minimumSelectionSize)
      else r = Math.min(maxW, l + minimumSelectionSize)
    }
    if (b - t < minimumSelectionSize) {
      if (String(activeEdge || "").indexOf("n") >= 0) t = Math.max(0, b - minimumSelectionSize)
      else b = Math.min(maxH, t + minimumSelectionSize)
    }

    setSelection(l, t, r - l, b - t, maxW, maxH)
  }

  function ensureSelection(maxWidth, maxHeight, screenName) {
    if (screenName !== undefined) selectionScreenName = String(screenName || "")
    if (hasSelection) {
      setSelection(selectionX, selectionY, selectionW, selectionH, maxWidth, maxHeight)
      return
    }

    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var nextW = Math.max(minimumSelectionSize, Math.round(maxW * 0.5))
    var nextH = Math.max(minimumSelectionSize, Math.round(maxH * 0.5))
    setSelection(Math.round((maxW - nextW) / 2), Math.round((maxH - nextH) / 2), nextW, nextH, maxW, maxH)
  }

  function selectionGeometry() {
    if (!hasSelection) return ""
    return Math.round(selectionX) + "," + Math.round(selectionY) + " " + Math.round(selectionW) + "x" + Math.round(selectionH)
  }

  function beginPointer(action, x, y, maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")
    pointerAction = String(action || "")
    pointerStartX = clamp(x, 0, maxWidth)
    pointerStartY = clamp(y, 0, maxHeight)
    pointerSelectionX = selectionX
    pointerSelectionY = selectionY
    pointerSelectionW = selectionW
    pointerSelectionH = selectionH
    pointerAnchorX = pointerStartX
    pointerAnchorY = pointerStartY

    if (pointerAction === "draw")
      setSelection(pointerStartX, pointerStartY, minimumSelectionSize, minimumSelectionSize, maxWidth, maxHeight)
    else
      ensureSelection(maxWidth, maxHeight, screenName)
  }

  function updatePointer(x, y, maxWidth, maxHeight) {
    if (pointerAction === "") return

    var px = clamp(x, 0, maxWidth)
    var py = clamp(y, 0, maxHeight)
    var dx = px - pointerStartX
    var dy = py - pointerStartY

    if (pointerAction === "draw") {
      setSelectionEdges(Math.min(pointerAnchorX, px), Math.min(pointerAnchorY, py),
        Math.max(pointerAnchorX, px), Math.max(pointerAnchorY, py), maxWidth, maxHeight, "se")
      return
    }

    if (pointerAction === "move") {
      setSelection(pointerSelectionX + dx, pointerSelectionY + dy, pointerSelectionW, pointerSelectionH, maxWidth, maxHeight)
      return
    }

    var left = pointerSelectionX
    var top = pointerSelectionY
    var right = pointerSelectionX + pointerSelectionW
    var bottom = pointerSelectionY + pointerSelectionH

    if (pointerAction.indexOf("w") >= 0) left += dx
    if (pointerAction.indexOf("e") >= 0) right += dx
    if (pointerAction.indexOf("n") >= 0) top += dy
    if (pointerAction.indexOf("s") >= 0) bottom += dy

    setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, pointerAction)
  }

  function finishPointer() {
    pointerAction = ""
  }

  function keyDirection(key) {
    if (key === Qt.Key_Left || key === Qt.Key_H) return "left"
    if (key === Qt.Key_Right || key === Qt.Key_L) return "right"
    if (key === Qt.Key_Up || key === Qt.Key_K) return "up"
    if (key === Qt.Key_Down || key === Qt.Key_J) return "down"
    return ""
  }

  function moveSelection(direction, maxWidth, maxHeight) {
    var dx = direction === "left" ? -1 : (direction === "right" ? 1 : 0)
    var dy = direction === "up" ? -1 : (direction === "down" ? 1 : 0)
    setSelection(selectionX + dx, selectionY + dy, selectionW, selectionH, maxWidth, maxHeight)
  }

  function resizeSelectionByKey(direction, grow, maxWidth, maxHeight) {
    var left = selectionX
    var top = selectionY
    var right = selectionX + selectionW
    var bottom = selectionY + selectionH
    var edge = ""

    if (direction === "left") {
      left += grow ? -1 : 1
      edge = "w"
    } else if (direction === "right") {
      right += grow ? 1 : -1
      edge = "e"
    } else if (direction === "up") {
      top += grow ? -1 : 1
      edge = "n"
    } else if (direction === "down") {
      bottom += grow ? 1 : -1
      edge = "s"
    }

    setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, edge)
  }

  function handleSelectionKey(event, maxWidth, maxHeight, screenName) {
    var direction = keyDirection(event.key)
    if (direction === "") return false

    ensureSelection(maxWidth, maxHeight, screenName)
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (shift) resizeSelectionByKey(direction, !ctrl, maxWidth, maxHeight)
    else moveSelection(direction, maxWidth, maxHeight)
    return true
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

    readonly property string currentScreenName: root.panelScreenName(panel)

    onVisibleChanged: {
      if (visible && root.regionEditor)
        Qt.callLater(function() { root.ensureSelection(panel.width, panel.height, panel.currentScreenName) })
    }
    onWidthChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
    onHeightChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)

    Connections {
      target: root
      function onSelectedModeChanged() {
        if (panel.visible && root.regionEditor)
          Qt.callLater(function() { root.ensureSelection(panel.width, panel.height, panel.currentScreenName) })
      }
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: 0.72
      visible: !root.regionEditor
    }

    MouseArea {
      anchors.fill: parent
      visible: !root.regionEditor
      onClicked: root.dismiss()
    }

    component ResizeHandle: Rectangle {
      required property string edge
      property int cursor: Qt.ArrowCursor

      width: Math.max(10, Style.space(10))
      height: width
      radius: width / 2
      color: Color.menu.background
      border.color: Color.accent
      border.width: Math.max(1, Style.normalBorderWidth)
      z: 2

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: parent.cursor
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
          var point = mapToItem(selectionLayer, mouse.x, mouse.y)
          keyCatcher.forceActiveFocus()
          root.beginPointer(parent.edge, point.x, point.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          var point = mapToItem(selectionLayer, mouse.x, mouse.y)
          root.updatePointer(point.x, point.y, selectionLayer.width, selectionLayer.height)
        }
        onReleased: root.finishPointer()
      }
    }

    Item {
      id: selectionLayer
      anchors.fill: parent
      visible: root.regionEditor

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
        opacity: 0.72
        visible: !root.hasSelection
      }

      Rectangle {
        x: 0
        y: 0
        width: parent.width
        height: root.hasSelection ? root.selectionY : parent.height
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: 0
        y: root.selectionY
        width: root.selectionX
        height: root.selectionH
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: root.selectionX + root.selectionW
        y: root.selectionY
        width: Math.max(0, parent.width - x)
        height: root.selectionH
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: 0
        y: root.selectionY + root.selectionH
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
          keyCatcher.forceActiveFocus()
          root.beginPointer("draw", mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          root.updatePointer(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height)
        }
        onReleased: root.finishPointer()
      }

      Rectangle {
        id: selectionBox
        x: root.selectionX
        y: root.selectionY
        width: root.selectionW
        height: root.selectionH
        visible: root.hasSelection
        color: Util.alpha(Color.accent, 0.10)
        border.color: Color.accent
        border.width: Math.max(1, Style.normalBorderWidth)

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.SizeAllCursor
          acceptedButtons: Qt.LeftButton
          onPressed: function(mouse) {
            var point = mapToItem(selectionLayer, mouse.x, mouse.y)
            keyCatcher.forceActiveFocus()
            root.beginPointer("move", point.x, point.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
            mouse.accepted = true
          }
          onPositionChanged: function(mouse) {
            var point = mapToItem(selectionLayer, mouse.x, mouse.y)
            root.updatePointer(point.x, point.y, selectionLayer.width, selectionLayer.height)
          }
          onReleased: root.finishPointer()
        }

        ResizeHandle {
          edge: "nw"
          cursor: Qt.SizeFDiagCursor
          x: -width / 2
          y: -height / 2
        }

        ResizeHandle {
          edge: "n"
          cursor: Qt.SizeVerCursor
          x: selectionBox.width / 2 - width / 2
          y: -height / 2
        }

        ResizeHandle {
          edge: "ne"
          cursor: Qt.SizeBDiagCursor
          x: selectionBox.width - width / 2
          y: -height / 2
        }

        ResizeHandle {
          edge: "e"
          cursor: Qt.SizeHorCursor
          x: selectionBox.width - width / 2
          y: selectionBox.height / 2 - height / 2
        }

        ResizeHandle {
          edge: "se"
          cursor: Qt.SizeFDiagCursor
          x: selectionBox.width - width / 2
          y: selectionBox.height - height / 2
        }

        ResizeHandle {
          edge: "s"
          cursor: Qt.SizeVerCursor
          x: selectionBox.width / 2 - width / 2
          y: selectionBox.height - height / 2
        }

        ResizeHandle {
          edge: "sw"
          cursor: Qt.SizeBDiagCursor
          x: -width / 2
          y: selectionBox.height - height / 2
        }

        ResizeHandle {
          edge: "w"
          cursor: Qt.SizeHorCursor
          x: -width / 2
          y: selectionBox.height / 2 - height / 2
        }
      }
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
            if (root.regionEditor) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
            root.runSelected(panel.currentScreenName)
            event.accepted = true
          } else if (root.regionEditor && root.handleSelectionKey(event, panel.width, panel.height, panel.currentScreenName)) {
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
            onClicked: {
              if (root.regionEditor) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
              root.runSelected(panel.currentScreenName)
            }
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
