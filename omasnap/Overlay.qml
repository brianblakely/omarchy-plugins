import QtQuick
import Quickshell
import Quickshell.Io
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
  property string pickerAction: ""
  property string targetKind: ""
  property bool regionLocked: false
  property bool regionOnlyPicker: false
  property bool freezeCapturePending: false
  property string freezeImagePath: ""
  property string freezeImageSource: ""
  property var pickerClients: []
  property var pickerMonitors: []

  readonly property var captureModes: [
    { value: "screen", label: "Screen", shortLabel: "Screen", icon: "󰍹" },
    { value: "window", label: "Window", shortLabel: "Window", icon: "󰖲" },
    { value: "selection", label: "Selection", shortLabel: "Area", icon: "󰆞" },
    { value: "record-screen", label: "Record Screen", shortLabel: "Rec Screen", icon: "󰑋" },
    { value: "record-selection", label: "Record Selection", shortLabel: "Rec Area", icon: "󰻂" }
  ]

  readonly property bool recordingMode: selectedMode === "record-screen" || selectedMode === "record-selection"
  readonly property bool recording: service && service.recording === true
  readonly property bool pickerMode: pickerAction !== ""
  readonly property bool regionEditor: selectedMode === "selection" || pickerMode
  readonly property bool showSelectionFrame: hasSelection && (!pickerMode || targetKind === "region")
  readonly property int minimumSelectionSize: 1

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }

    if (payload.action) {
      pickerAction = normalizePickerAction(payload.action)
      selectedMode = "selection"
      hasSelection = false
      targetKind = ""
      regionLocked = false
      regionOnlyPicker = payload.regionOnly === true || String(payload.target || "") === "region"
      refreshPickerTargets()
    } else {
      pickerAction = ""
      regionOnlyPicker = false
      if (payload.mode) selectedMode = String(payload.mode)
      else if (service && service.captureMode) selectedMode = service.captureMode
    }

    if (service && typeof service.refreshStatus === "function") service.refreshStatus()
    if (regionEditor && service && service.rememberSelection !== true) hasSelection = false
    if (regionEditor) captureFreezeAndOpen()
    else showOverlay()
  }

  function close() {
    opened = false
    pickerAction = ""
    targetKind = ""
    regionLocked = false
    regionOnlyPicker = false
    freezeCapturePending = false
    if (freezeCaptureProc.running) freezeCaptureProc.running = false
    finishPointer()
    clearFreezeImage()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function setMode(mode) {
    var wasRegionEditor = regionEditor
    selectedMode = String(mode || "selection")
    if (service && typeof service.setCaptureMode === "function")
      service.setCaptureMode(selectedMode)

    if (opened && !pickerMode) {
      if (!wasRegionEditor && regionEditor) captureFreezeAndOpen()
      else if (wasRegionEditor && !regionEditor) clearFreezeImage()
    }
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

  function normalizePickerAction(action) {
    var value = String(action || "file").toLowerCase()
    if (value === "clipboard" || value === "copy") return "clipboard"
    if (value === "record" || value === "recording") return "record"
    return "file"
  }

  function freezeCommand() {
    return "set -e; dir=\"${XDG_RUNTIME_DIR:-/tmp}\"; path=\"$dir/omasnap-freeze-$(date +%s%N)-$$.png\"; screen=\"\"; if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then screen=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -1); fi; if [ -n \"$screen\" ]; then grim -o \"$screen\" \"$path\" >/dev/null 2>&1; else grim \"$path\" >/dev/null 2>&1; fi; printf '%s\\n' \"$path\""
  }

  function fileUrl(path) {
    return path === "" ? "" : "file://" + path
  }

  function clearFreezeImage() {
    var oldPath = freezeImagePath
    freezeImagePath = ""
    freezeImageSource = ""
    if (oldPath !== "")
      Quickshell.execDetached(["rm", "-f", "--", oldPath])
  }

  function showOverlay() {
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function captureFreezeAndOpen() {
    if (freezeCaptureProc.running) freezeCaptureProc.running = false
    opened = false
    clearFreezeImage()
    freezeCapturePending = true
    Qt.callLater(function() {
      if (!freezeCapturePending) return
      freezeCaptureProc.command = ["bash", "-lc", freezeCommand()]
      freezeCaptureProc.running = true
      freezeCaptureFallback.restart()
    })
  }

  function finishFreezeCapture(path) {
    if (!freezeCapturePending) return

    var nextPath = String(path || "").replace(/^\s+|\s+$/g, "")
    freezeCapturePending = false
    if (nextPath !== "") {
      freezeImagePath = nextPath
      freezeImageSource = fileUrl(nextPath)
    }
    showOverlay()
  }

  function refreshPickerTargets() {
    if (!pickerMode || pickerTargetsProc.running) return
    pickerTargetsProc.running = true
  }

  function panelScreenName(panel) {
    return panel && panel.screen && panel.screen.name ? String(panel.screen.name) : ""
  }

  function activeBarPosition() {
    if (shell && shell.bar && shell.bar.position) return String(shell.bar.position)
    if (shell && shell.barConfig && shell.barConfig.position) return String(shell.barConfig.position)
    return "top"
  }

  function activeBarHidden() {
    return shell && shell.bar && shell.bar.barHidden === true
  }

  function activeBarSize() {
    if (shell && shell.bar && shell.bar.barSize) return Math.max(1, Math.round(Number(shell.bar.barSize) || 1))
    var position = activeBarPosition()
    return (position === "left" || position === "right") ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  }

  function isPointInBar(x, y, maxWidth, maxHeight) {
    if (activeBarHidden()) return false

    var position = activeBarPosition()
    var size = activeBarSize()
    if (position === "bottom") return y >= Math.max(0, maxHeight - size)
    if (position === "left") return x <= size
    if (position === "right") return x >= Math.max(0, maxWidth - size)
    return y <= size
  }

  function monitorForScreen(screenName) {
    var name = String(screenName || "")
    var fallback = null
    for (var i = 0; i < pickerMonitors.length; i++) {
      var monitor = pickerMonitors[i]
      if (!monitor) continue
      if (name !== "" && String(monitor.name || "") === name) return monitor
      if (monitor.focused === true) fallback = monitor
    }
    return fallback
  }

  function monitorOffset(screenName) {
    var monitor = monitorForScreen(screenName)
    return {
      x: monitor ? Math.round(Number(monitor.x) || 0) : 0,
      y: monitor ? Math.round(Number(monitor.y) || 0) : 0
    }
  }

  function monitorWorkspaceId(screenName) {
    var monitor = monitorForScreen(screenName)
    return monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : NaN
  }

  function localToGlobal(x, y, screenName) {
    var offset = monitorOffset(screenName)
    return { x: Math.round(x + offset.x), y: Math.round(y + offset.y) }
  }

  function globalRectToLocal(rect, screenName, maxWidth, maxHeight) {
    var offset = monitorOffset(screenName)
    var x = Math.round(Number(rect.x) || 0) - offset.x
    var y = Math.round(Number(rect.y) || 0) - offset.y
    var width = Math.round(Number(rect.width) || 0)
    var height = Math.round(Number(rect.height) || 0)
    var left = clamp(x, 0, maxWidth)
    var top = clamp(y, 0, maxHeight)
    var right = clamp(x + width, 0, maxWidth)
    var bottom = clamp(y + height, 0, maxHeight)
    return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) }
  }

  function clientRect(client) {
    if (!client || !client.at || !client.size) return null
    return {
      x: Math.round(Number(client.at[0]) || 0),
      y: Math.round(Number(client.at[1]) || 0),
      width: Math.round(Number(client.size[0]) || 0),
      height: Math.round(Number(client.size[1]) || 0)
    }
  }

  function clientAt(x, y, maxWidth, maxHeight, screenName) {
    var point = localToGlobal(x, y, screenName)
    var workspaceId = monitorWorkspaceId(screenName)

    for (var i = pickerClients.length - 1; i >= 0; i--) {
      var client = pickerClients[i]
      if (!client || client.mapped === false || client.hidden === true || client.minimized === true) continue
      if (client.workspace && isFinite(workspaceId) && Number(client.workspace.id) !== workspaceId) continue

      var rect = clientRect(client)
      if (!rect || rect.width <= 0 || rect.height <= 0) continue
      if (point.x >= rect.x && point.x < rect.x + rect.width && point.y >= rect.y && point.y < rect.y + rect.height)
        return client
    }

    return null
  }

  function setTargetFromClient(client, maxWidth, maxHeight, screenName) {
    var rect = clientRect(client)
    if (!rect) return false
    var local = globalRectToLocal(rect, screenName, maxWidth, maxHeight)
    setSelection(local.x, local.y, local.width, local.height, maxWidth, maxHeight)
    selectionScreenName = String(screenName || "")
    targetKind = "window"
    regionLocked = false
    return true
  }

  function setScreenTarget(maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")
    setSelection(0, 0, maxWidth, maxHeight, maxWidth, maxHeight)
    targetKind = "screen"
    regionLocked = false
  }

  function updatePickerHover(x, y, maxWidth, maxHeight, screenName) {
    if (!pickerMode || pointerAction !== "" || regionLocked) return
    if (regionOnlyPicker) return

    if (isPointInBar(x, y, maxWidth, maxHeight)) {
      setScreenTarget(maxWidth, maxHeight, screenName)
      return
    }

    var client = clientAt(x, y, maxWidth, maxHeight, screenName)
    if (client && setTargetFromClient(client, maxWidth, maxHeight, screenName)) return

    targetKind = ""
    hasSelection = false
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

  function beginPickerPointer(x, y, maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")

    if (regionOnlyPicker) {
      targetKind = "region"
      regionLocked = true
      beginPointer("draw", x, y, maxWidth, maxHeight, screenName)
      return
    }

    pointerAction = "pending"
    pointerStartX = clamp(x, 0, maxWidth)
    pointerStartY = clamp(y, 0, maxHeight)
    pointerAnchorX = pointerStartX
    pointerAnchorY = pointerStartY
    pointerSelectionX = selectionX
    pointerSelectionY = selectionY
    pointerSelectionW = selectionW
    pointerSelectionH = selectionH
    regionLocked = false

    if (isPointInBar(pointerStartX, pointerStartY, maxWidth, maxHeight)) {
      setScreenTarget(maxWidth, maxHeight, screenName)
      return
    }

    var client = clientAt(pointerStartX, pointerStartY, maxWidth, maxHeight, screenName)
    if (client && setTargetFromClient(client, maxWidth, maxHeight, screenName)) return

    targetKind = ""
    hasSelection = false
  }

  function updatePointer(x, y, maxWidth, maxHeight) {
    if (pointerAction === "") return

    var px = clamp(x, 0, maxWidth)
    var py = clamp(y, 0, maxHeight)
    var dx = px - pointerStartX
    var dy = py - pointerStartY

    if (pointerAction === "pending") {
      if (dx === 0 && dy === 0) return
      pointerAction = "draw"
      targetKind = "region"
      regionLocked = true
      setSelection(pointerStartX, pointerStartY, minimumSelectionSize, minimumSelectionSize, maxWidth, maxHeight)
    }

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

  function finishPickerPointer(maxWidth, maxHeight, screenName) {
    var action = pointerAction
    finishPointer()

    if (action === "draw") {
      if (hasSelection) {
        targetKind = "region"
        regionLocked = true
      }
      return
    }

    if (action === "pending") {
      if (targetKind === "screen" || targetKind === "window") captureCurrentTarget(screenName)
    }
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
    if (pickerMode) {
      targetKind = "region"
      regionLocked = true
    }
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (shift) resizeSelectionByKey(direction, !ctrl, maxWidth, maxHeight)
    else moveSelection(direction, maxWidth, maxHeight)
    return true
  }

  function captureScreenTarget(screenName) {
    if (!service) return
    if (pickerAction === "record") service.record("screen")
    else service.screenshot("screen", pickerAction === "clipboard" ? "clipboard" : "file")
  }

  function captureCurrentTarget(screenName) {
    if (!service || !pickerMode) return

    if (targetKind === "screen") {
      captureScreenTarget(screenName)
      return
    }

    if ((targetKind === "window" || targetKind === "region") && hasSelection) {
      var geometry = selectionGeometry()
      if (pickerAction === "record" && typeof service.recordGeometry === "function")
        service.recordGeometry(geometry, screenName || selectionScreenName || "")
      else if (typeof service.screenshotGeometry === "function")
        service.screenshotGeometry(geometry, screenName || selectionScreenName || "", pickerAction === "clipboard" ? "clipboard" : "file")
    }
  }

  function captureFocusedWindowOrRegion(screenName, maxWidth, maxHeight) {
    if (targetKind === "screen" || targetKind === "window" || targetKind === "region") {
      captureCurrentTarget(screenName)
      return
    }

    var workspaceId = monitorWorkspaceId(screenName)
    for (var i = pickerClients.length - 1; i >= 0; i--) {
      var client = pickerClients[i]
      if (!client || client.focused !== true) continue
      if (client.workspace && isFinite(workspaceId) && Number(client.workspace.id) !== workspaceId) continue
      if (setTargetFromClient(client, maxWidth, maxHeight, screenName)) {
        captureCurrentTarget(screenName)
        return
      }
    }
  }

  component MenuButton: Rectangle {
    id: menuButton

    property string text: ""
    property string iconText: ""
    property bool checked: false
    property bool emphasized: false
    property bool showSwitch: false

    signal clicked()

    readonly property bool highlighted: checked || emphasized
    readonly property color activeText: Color.menu.selectedText
    readonly property color idleText: Color.menu.text
    readonly property color selectedBorder: Color.menu.selectedBorder.a > 0
      ? Color.menu.selectedBorder
      : Style.selectedBorderFor(idleText, activeText)

    width: implicitWidth
    height: implicitHeight
    implicitWidth: buttonRow.implicitWidth + Style.spacing.controlPaddingX * 2
    implicitHeight: Math.max(Style.spacing.controlHeight, buttonRow.implicitHeight + Style.spacing.controlPaddingY * 2)
    radius: Style.cornerRadius
    color: buttonMouse.pressed ? Style.pressedFillFor(idleText, activeText)
      : buttonMouse.containsMouse ? Style.hoverFillFor(idleText, activeText)
      : highlighted ? Color.menu.selectedBackground
      : Style.normalFillFor(idleText, activeText)
    border.color: highlighted ? selectedBorder
      : buttonMouse.containsMouse ? Style.hoverBorderFor(idleText, activeText)
      : Style.normalBorderFor(idleText, activeText)
    border.width: highlighted ? Math.max(1, Style.selectedBorderWidth, Style.normalBorderWidth)
      : Style.normalBorderWidth

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      id: buttonRow
      anchors.centerIn: parent
      spacing: Style.spacing.controlGap

      Rectangle {
        visible: menuButton.checked && !menuButton.showSwitch
        width: Style.space(5)
        height: width
        radius: width / 2
        color: menuButton.activeText
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: menuButton.iconText !== ""
        text: menuButton.iconText
        color: menuButton.highlighted ? menuButton.activeText : menuButton.idleText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.icon
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: menuButton.text !== ""
        text: menuButton.text
        color: menuButton.highlighted ? menuButton.activeText : menuButton.idleText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        font.bold: menuButton.highlighted
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        id: switchTrack
        visible: menuButton.showSwitch
        width: Style.space(26)
        height: Math.max(Style.space(12), Math.round(Style.spacing.controlHeight * 0.42))
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: menuButton.checked
          ? Util.alpha(menuButton.activeText, 0.32)
          : Style.normalFillFor(menuButton.idleText, menuButton.activeText)
        border.color: menuButton.checked
          ? menuButton.activeText
          : Style.normalBorderFor(menuButton.idleText, menuButton.activeText)
        border.width: Math.max(1, Style.normalBorderWidth)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          width: Math.max(Style.space(7), switchTrack.height - Style.space(5))
          height: width
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          x: menuButton.checked ? switchTrack.width - width - Style.space(2) : Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          color: menuButton.checked ? menuButton.activeText : Qt.darker(menuButton.idleText, 1.35)

          Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
      }
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: menuButton.clicked()
    }
  }

  component CompactDropdown: Item {
    id: compactDropdown

    property string label: ""
    property string value: ""
    property var options: []
    property int controlWidth: Style.space(130)

    signal changed(string value)

    width: implicitWidth
    height: implicitHeight
    implicitWidth: dropdownRow.implicitWidth
    implicitHeight: dropdownRow.implicitHeight

    Row {
      id: dropdownRow
      spacing: Style.spacing.xs

      Text {
        text: compactDropdown.label
        color: Qt.darker(Color.menu.text, 1.35)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Dropdown {
        width: compactDropdown.controlWidth
        label: compactDropdown.label
        value: compactDropdown.value
        options: compactDropdown.options
        showLabel: false
        foreground: Color.menu.text
        background: Color.menu.background
        popupBorder: Color.menu.border
        accent: Color.menu.selectedText
        onChanged: function(value) { compactDropdown.changed(value) }
      }
    }
  }

  Process {
    id: pickerTargetsProc
    command: [
      "bash",
      "-lc",
      "printf '{\"monitors\":'; hyprctl monitors -j 2>/dev/null || printf '[]'; printf ',\"clients\":'; hyprctl clients -j 2>/dev/null || printf '[]'; printf '}'"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.pickerMonitors = Array.isArray(parsed.monitors) ? parsed.monitors : []
          root.pickerClients = Array.isArray(parsed.clients) ? parsed.clients : []
        } catch (e) {
          root.pickerMonitors = []
          root.pickerClients = []
        }
      }
    }
  }

  Process {
    id: freezeCaptureProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishFreezeCapture(String(text || ""))
    }
  }

  Timer {
    id: freezeCaptureFallback
    interval: 1200
    repeat: false
    onTriggered: {
      if (!root.freezeCapturePending) return
      if (freezeCaptureProc.running) freezeCaptureProc.running = false
      root.finishFreezeCapture("")
    }
  }

  Timer {
    interval: 700
    running: root.opened && root.pickerMode
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPickerTargets()
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
      if (visible && root.regionEditor && !root.pickerMode)
        Qt.callLater(function() { root.ensureSelection(panel.width, panel.height, panel.currentScreenName) })
    }
    onWidthChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
    onHeightChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)

    Connections {
      target: root
      function onSelectedModeChanged() {
        if (panel.visible && root.regionEditor && !root.pickerMode)
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
        enabled: root.pointerAction === ""
        hoverEnabled: true
        cursorShape: parent.cursor
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
          var point = mapToItem(selectionLayer, mouse.x, mouse.y)
          keyCatcher.forceActiveFocus()
          if (root.pickerMode) root.targetKind = "region"
          if (root.pickerMode) root.regionLocked = true
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

      Image {
        anchors.fill: parent
        source: root.freezeImageSource
        visible: root.freezeImageSource !== ""
        fillMode: Image.Stretch
        asynchronous: true
        cache: false
        smooth: false
      }

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
        hoverEnabled: root.pickerMode
        preventStealing: true
        onPressed: function(mouse) {
          keyCatcher.forceActiveFocus()
          if (root.pickerMode) root.beginPickerPointer(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          else root.beginPointer("draw", mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          if (root.pointerAction !== "") root.updatePointer(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height)
          else root.updatePickerHover(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
        }
        onReleased: {
          if (root.pickerMode) root.finishPickerPointer(selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          else root.finishPointer()
        }
      }

      Rectangle {
        id: selectionBox
        x: root.selectionX
        y: root.selectionY
        width: root.selectionW
        height: root.selectionH
        visible: root.showSelectionFrame
        color: Util.alpha(Color.accent, 0.10)
        border.color: Color.accent
        border.width: Math.max(1, Style.normalBorderWidth)

        MouseArea {
          anchors.fill: parent
          enabled: root.pointerAction === ""
          cursorShape: Qt.SizeAllCursor
          acceptedButtons: Qt.LeftButton
          preventStealing: true
          onPressed: function(mouse) {
            var point = mapToItem(selectionLayer, mouse.x, mouse.y)
            keyCatcher.forceActiveFocus()
            if (root.pickerMode) root.targetKind = "region"
            if (root.pickerMode) root.regionLocked = true
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

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (root.pickerMode && event.key === Qt.Key_Space) {
          root.captureScreenTarget(panel.currentScreenName)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.pickerMode) root.captureFocusedWindowOrRegion(panel.currentScreenName, panel.width, panel.height)
          else {
            if (root.regionEditor) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
            root.runSelected(panel.currentScreenName)
          }
          event.accepted = true
        } else if (root.regionEditor && root.handleSelectionKey(event, panel.width, panel.height, panel.currentScreenName)) {
          event.accepted = true
        } else if (!root.pickerMode && event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
          root.setMode(root.captureModes[event.key - Qt.Key_1].value)
          event.accepted = true
        }
      }
    }

    BorderSurface {
      id: toolbar
      visible: !root.pickerMode
      readonly property int preferredWidth: root.recordingMode || root.recording ? Style.space(760) : Style.space(700)
      width: Math.max(1, Math.min(panel.width - Style.gapsOut * 2, preferredWidth))
      height: content.implicitHeight + padding * 2 + borderTop + borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(Style.gapsOut, Style.space(14))
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
      padding: Style.spacing.xxl
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: toolbar.contentLeftInset
        anchors.rightMargin: toolbar.contentRightInset
        anchors.topMargin: toolbar.contentTopInset
        spacing: Style.spacing.sm

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Flow {
            width: Math.max(1, parent.width - actionButtons.width - parent.spacing)
            spacing: Style.spacing.xs

            Repeater {
              model: root.captureModes

              MenuButton {
                text: modelData.shortLabel || modelData.label
                iconText: modelData.icon
                checked: root.selectedMode === modelData.value
                onClicked: root.setMode(modelData.value)
              }
            }
          }

          Row {
            id: actionButtons
            width: implicitWidth
            height: implicitHeight
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            MenuButton {
              text: root.recording ? "Stop" : (root.recordingMode ? "Record" : "Capture")
              iconText: root.recording ? "󰓛" : (root.recordingMode ? "󰑋" : "")
              emphasized: true
              onClicked: {
                if (root.regionEditor) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
                root.runSelected(panel.currentScreenName)
              }
            }

            MenuButton {
              text: "Open"
              iconText: "󰈙"
              onClicked: if (service) service.openLast()
            }

            PanelActionButton {
              id: closeButton
              iconText: "󰅖"
              tooltipText: "Close"
              size: Style.spacing.controlHeight
              bordered: true
              foreground: Color.menu.text
              hoverColor: Color.menu.selectedText
              onClicked: root.dismiss()
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.xs

          CompactDropdown {
            label: "Save"
            controlWidth: Style.space(132)
            value: service ? service.outputMode : "file-and-clipboard"
            options: [
              { value: "file-and-clipboard", label: "File + Clipboard" },
              { value: "file", label: "File" },
              { value: "clipboard", label: "Clipboard" },
              { value: "editor", label: "Editor" }
            ]
            onChanged: function(value) { if (service) service.setOutputMode(value) }
          }

          CompactDropdown {
            label: "To"
            controlWidth: Style.space(108)
            value: service ? service.saveLocation : "pictures"
            options: [
              { value: "pictures", label: "Pictures" },
              { value: "desktop", label: "Desktop" },
              { value: "documents", label: "Documents" },
              { value: "downloads", label: "Downloads" }
            ]
            onChanged: function(value) { if (service) service.setSaveLocation(value) }
          }

          CompactDropdown {
            label: "Delay"
            controlWidth: Style.space(82)
            value: service ? String(service.timerSeconds) : "0"
            options: [
              { value: "0", label: "None" },
              { value: "5", label: "5 sec" },
              { value: "10", label: "10 sec" }
            ]
            onChanged: function(value) { if (service) service.setTimer(value) }
          }

          MenuButton {
            text: "Pointer"
            iconText: "󰆿"
            checked: service && service.includeCursor
            showSwitch: true
            onClicked: root.toggleBoolean("cursor")
          }

          MenuButton {
            text: "Thumbnail"
            iconText: "󰋩"
            checked: !service || service.showThumbnail
            showSwitch: true
            onClicked: root.toggleBoolean("thumbnail")
          }

          MenuButton {
            text: "Remember"
            iconText: "󰆓"
            checked: !service || service.rememberSelection
            showSwitch: true
            onClicked: root.toggleBoolean("remember")
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.xs
          visible: root.recordingMode || root.recording

          MenuButton {
            text: "Desktop"
            iconText: "󰓃"
            checked: service && service.recordDesktopAudio
            showSwitch: true
            onClicked: root.toggleBoolean("desktopAudio")
          }

          MenuButton {
            text: "Mic"
            iconText: "󰍬"
            checked: service && service.recordMicrophoneAudio
            showSwitch: true
            onClicked: root.toggleBoolean("microphoneAudio")
          }

          MenuButton {
            text: "Webcam"
            iconText: "󰄀"
            checked: service && service.recordWebcam
            showSwitch: true
            onClicked: root.toggleBoolean("webcam")
          }
        }

      }
    }
  }
}
