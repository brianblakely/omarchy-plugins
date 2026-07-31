import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "OkomartModel.js" as OkomartModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.okomart"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/bin/okomart" : ""

  property bool closingFromHost: false
  property bool cacheLoading: false
  property bool catalogLoaded: false
  property bool refreshing: false
  property bool refreshQueued: false
  property bool statusChecking: false
  property bool updatesConfirmed: false
  property bool installedOnly: false
  property bool narrowShowingDetails: false
  property bool initialListFocusPending: false
  property int initialListFocusAttempts: 0
  property bool windowOpenPending: false
  property bool actionStarting: false
  property bool actionInProgress: false
  property bool actionReplacesOkomart: false
  property string query: ""
  property string selectedId: ""
  property string cachedOutput: ""
  property string inactiveBorderOutput: ""
  property string refreshOutput: ""
  property string refreshError: ""
  property string windowRuleOutput: ""
  property string actionOutput: ""
  property string actionError: ""
  property string bannerText: ""
  property bool bannerUrgent: false
  property var snapshot: ({})
  property var allPlugins: []
  property var visiblePlugins: []
  property var updateRows: []
  property var pendingActionPlugin: null
  property color inactiveBorderColor: Qt.rgba(
    0x59 / 255, 0x59 / 255, 0x59 / 255, 0xaa / 255)

  readonly property bool wideLayout: window.width >= Style.space(600)
  readonly property bool toolbarSingleRow: window.width >= Style.space(420)
  property int windowSide: Style.space(760)
  readonly property int minimumWindowSide:
    Math.min(windowSide, Style.space(560))
  readonly property real bodyTop: Math.max(Style.space(164), Math.min(Style.space(205), window.height * 0.255))
  readonly property real headerEdgeInset:
    wideLayout ? Style.space(82) : Style.space(42)
  readonly property real splitX: storefront.frameLeft
    + Math.max(Style.space(292), Math.min(Style.space(420),
      (storefront.frameRight - storefront.frameLeft) * 0.405))
  readonly property var selectedPlugin: {
    for (var i = 0; i < visiblePlugins.length; i++)
      if (String(visiblePlugins[i].id || "") === selectedId) return visiblePlugins[i]
    return null
  }
  readonly property int safeUpdateCount: {
    var count = 0
    for (var i = 0; i < updateRows.length; i++)
      if (updateRows[i] && updateRows[i].safeUpdate === true) count++
    return count
  }
  readonly property bool hasConfirmedUpdates:
    updatesConfirmed && updateRows.length > 0
  property color storefrontColor:
    focusScope.Window.active ? Color.accent : inactiveBorderColor

  Behavior on storefrontColor {
    ColorAnimation {
      duration: 539
      easing.type: Easing.BezierSpline
      easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
    }
  }

  readonly property bool snapshotActionable: !!(snapshot
    && snapshot.snapshotId && snapshot.ok !== false)

  onWideLayoutChanged: if (wideLayout) narrowShowingDetails = false
  onWindowSideChanged: Qt.callLater(applyCurrentWindowSize)
  onQueryChanged: rebuildView()
  onInstalledOnlyChanged: rebuildView()

  function runtimeVersion(_arg) {
    return manifest && manifest.version ? String(manifest.version) : ""
  }

  function refreshInactiveBorderColor() {
    if (inactiveBorderProcess.running) return
    inactiveBorderOutput = ""
    inactiveBorderProcess.running = true
  }

  function applyInactiveBorderColor(raw, exitCode) {
    if (exitCode !== 0) return
    var components = OkomartModel.hyprlandColorComponents(raw)
    if (!Array.isArray(components) || components.length !== 4) return
    inactiveBorderColor = Qt.rgba(
      components[0] / 255,
      components[1] / 255,
      components[2] / 255,
      components[3] / 255)
  }

  function activeBarGeometry() {
    var activeBar = shell && shell.bar ? shell.bar : null
    if (!activeBar || activeBar.barHidden === true)
      return { position: "none", size: 0 }

    var position = String(activeBar.position
      || (shell.barConfig && shell.barConfig.position) || "top").toLowerCase()
    if (["top", "bottom", "left", "right"].indexOf(position) < 0)
      position = "top"

    var fallback = position === "left" || position === "right"
      ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    var size = Number(activeBar.barSize)
    if (!isFinite(size) || size < 0) size = fallback
    return { position: position, size: Math.max(0, Math.round(size)) }
  }

  function open(payloadJson) {
    closingFromHost = false
    updatesConfirmed = false
    refreshInactiveBorderColor()
    initialListFocusPending = true
    initialListFocusAttempts = 0
    selectedId = ""
    window.maximized = false
    window.fullscreen = false
    window.implicitWidth = windowSide
    window.implicitHeight = windowSide
    window.width = windowSide
    window.height = windowSide
    narrowShowingDetails = false
    if (catalogLoaded) loadActionStatus()
    else loadCachedSnapshot()
    windowOpenPending = true
    prepareFloatingWindow()
  }

  function close() {
    windowOpenPending = false
    initialListFocusPending = false
    initialFocusTimer.stop()
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function prepareFloatingWindow() {
    if (!windowOpenPending) return
    if (!helperPath) {
      failWindowPreparation("Okomart's window helper is unavailable.")
      return
    }
    if (windowRuleProcess.running) return

    windowRuleOutput = ""
    var barGeometry = activeBarGeometry()
    windowRuleProcess.command = [
      helperPath,
      "prepare-window",
      barGeometry.position,
      String(barGeometry.size)
    ]
    windowRuleProcess.running = true
  }

  function applyWindowRule(raw, exitCode) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    var preparedWidth = Math.round(Number(parsed && parsed.width))
    var preparedHeight = Math.round(Number(parsed && parsed.height))
    if (exitCode === 0 && parsed && parsed.ok === true
        && parsed.prepared === true
        && preparedWidth > 0 && preparedWidth === preparedHeight) {
      windowSide = preparedWidth
      applyCurrentWindowSize()
      showPreparedWindow()
      return
    }

    var reason = parsed && parsed.error
      ? String(parsed.error) : "Could not prepare Okomart's floating window."
    failWindowPreparation(reason)
  }

  function failWindowPreparation(reason) {
    if (!windowOpenPending) return
    windowOpenPending = false
    console.warn("Okomart: " + reason)
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function showPreparedWindow() {
    if (!windowOpenPending) return
    windowOpenPending = false
    window.visible = true
    Qt.callLater(focusInitialPluginList)
  }

  function applyCurrentWindowSize() {
    window.implicitWidth = windowSide
    window.implicitHeight = windowSide
    if (!window.visible) return
    window.width = windowSide
    window.height = windowSide
  }

  function focusInitialPluginList() {
    if (!initialListFocusPending || !window.visible) return
    initialListFocusAttempts++
    pluginList.focusFirstItem()
    if (pluginList.activeFocus || initialListFocusAttempts >= 20) {
      initialListFocusPending = false
      initialFocusTimer.stop()
    }
  }

  function focusPluginListFromSearch() {
    initialListFocusPending = false
    initialFocusTimer.stop()
    if (!wideLayout) narrowShowingDetails = false
    Qt.callLater(pluginList.focusCurrentItem)
  }

  function focusPluginDetailsFromSearch() {
    initialListFocusPending = false
    initialFocusTimer.stop()
    if (!selectedPlugin) {
      focusPluginListFromSearch()
      return
    }
    if (!wideLayout) narrowShowingDetails = true
    Qt.callLater(pluginDetails.focusViewport)
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else window.visible = false
  }

  function closeFromKeyboard() {
    if (dialog.opened) {
      if (!actionStarting) dialog.closeDialog()
      return
    }
    if (!wideLayout && narrowShowingDetails) {
      narrowShowingDetails = false
      Qt.callLater(pluginList.focusCurrentItem)
      return
    }
    if (query !== "") {
      query = ""
      searchField.forceActiveFocus()
      return
    }
    requestClose()
  }

  function rebuildView() {
    var filter = installedOnly ? "installed" : "all"
    var next
    try {
      next = OkomartModel.filterPlugins(allPlugins, query, filter)
    } catch (e) {
      next = Array.isArray(allPlugins) ? allPlugins.slice() : []
    }
    visiblePlugins = next

    var nextId = ""
    try {
      var resolved = OkomartModel.resolveSelection(next, selectedId)
      nextId = typeof resolved === "string" ? resolved
        : (resolved && resolved.id ? String(resolved.id) : "")
    } catch (e2) {
      nextId = selectedId
    }
    if (!nextId && next.length > 0) nextId = String(next[0].id || "")
    selectedId = nextId
    if (!nextId) narrowShowingDetails = false
  }

  function buildUpdates(data) {
    if (data && Array.isArray(data.updates)) {
      var declaredRows = []
      for (var declaredIndex = 0; declaredIndex < data.updates.length; declaredIndex++) {
        var declared = data.updates[declaredIndex]
        if (declared && declared.versionUpdateAvailable === true)
          declaredRows.push(declared)
      }
      return declaredRows
    }
    var rows = []
    var plugins = data && Array.isArray(data.plugins) ? data.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var p = plugins[i]
      if (p && p.installed && p.versionUpdateAvailable === true) rows.push(p)
    }
    if (data && data.self) {
      if (data.self.versionUpdateAvailable === true) {
        var selfRow = {}
        for (var key in data.self) selfRow[key] = data.self[key]
        selfRow.id = selfRow.id || pluginId
        selfRow.name = selfRow.name || "Okomart"
        selfRow.self = true
        rows.push(selfRow)
      }
    }
    return rows
  }

  function setSnapshotData(parsed) {
    var displayPlugins = []
    for (var pluginIndex = 0; pluginIndex < parsed.plugins.length; pluginIndex++) {
      var plugin = parsed.plugins[pluginIndex]
      if (!plugin) continue
      var changedId = String(plugin.id || "")
      if (changedId === pluginId) continue
      if (Array.isArray(plugin.images))
        plugin.images = OkomartModel.supportedScreenshots(plugin.images)
      displayPlugins.push(plugin)
    }
    snapshot = parsed
    allPlugins = displayPlugins
    updateRows = buildUpdates(parsed)
    catalogLoaded = true
    rebuildView()
  }

  function loadCachedSnapshot() {
    if (!helperPath) {
      bannerText = "Okomart could not determine its source directory."
      bannerUrgent = true
      return
    }
    if (cacheProcess.running) return
    cacheLoading = true
    cachedOutput = ""
    cacheProcess.command = [helperPath, "cached"]
    cacheProcess.running = true
  }

  function applyCachedSnapshot(raw) {
    cacheLoading = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (parsed && parsed.ok !== false && Array.isArray(parsed.plugins))
      setSnapshotData(parsed)
    loadActionStatus()
  }

  function applySnapshot(raw, exitCode) {
    refreshing = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    var confirmsUpdates = OkomartModel.snapshotConfirmsUpdates(parsed, exitCode)

    if (!parsed || !Array.isArray(parsed.plugins)) {
      bannerText = refreshError.trim() || "Catalog refresh failed."
      bannerUrgent = true
    } else {
      setSnapshotData(parsed)
      var catalogErrors = Array.isArray(parsed.catalogErrors) ? parsed.catalogErrors : []
      if (parsed.stale) {
        bannerText = parsed.error
          ? "Showing the last catalog snapshot: " + parsed.error
          : "Showing the last catalog snapshot."
        bannerUrgent = true
      } else if (parsed.ok === false || exitCode !== 0) {
        bannerText = String(parsed.error || refreshError.trim()
          || "Catalog refresh failed.")
        bannerUrgent = true
      } else if (catalogErrors.length > 0) {
        bannerText = catalogErrors.length + " invalid catalog "
          + (catalogErrors.length === 1 ? "entry was" : "entries were")
          + " hidden."
        bannerUrgent = true
      } else {
        bannerText = ""
        bannerUrgent = false
      }
    }

    if (refreshQueued) {
      refreshQueued = false
      updatesConfirmed = false
      Qt.callLater(refresh)
    } else {
      updatesConfirmed = confirmsUpdates
    }
  }

  function refresh() {
    if (!sourceDir || !helperPath) {
      bannerText = "Okomart could not determine its source directory."
      bannerUrgent = true
      return
    }
    if (refreshing) {
      refreshQueued = true
      return
    }
    if (actionStarting || actionInProgress) return
    if (dialog.opened && dialog.mode !== "results") return
    updatesConfirmed = false
    refreshing = true
    refreshOutput = ""
    refreshError = ""
    bannerText = ""
    bannerUrgent = false
    refreshProcess.command = [helperPath, "snapshot", sourceDir]
    refreshProcess.running = true
  }

  function loadActionStatus() {
    if (!helperPath || statusProcess.running) return
    statusChecking = true
    statusProcess.output = ""
    statusProcess.command = [helperPath, "status"]
    statusProcess.running = true
  }

  function applyActionStatus(raw) {
    statusChecking = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (!parsed) {
      refresh()
      return
    }
    if (parsed.running === true) {
      actionInProgress = true
      bannerText = String(parsed.message || "Plugin operation in progress…")
      bannerUrgent = false
      actionPoll.restart()
      return
    }
    if (!parsed.action || parsed.acknowledged === true) {
      actionInProgress = false
      refresh()
      return
    }

    var state = String(parsed.state || parsed.status || "")
    var results = Array.isArray(parsed.results) ? parsed.results : []
    if (state === "running" || state === "started") {
      actionInProgress = true
      bannerText = "Plugin operation in progress…"
      bannerUrgent = false
      actionPoll.restart()
      return
    }
    var failedResults = []
    for (var i = 0; i < results.length; i++)
      if (results[i] && results[i].ok === false) failedResults.push(results[i])
    if (parsed.running === false || state === "complete"
        || state === "completed" || state === "success") {
      actionInProgress = false
      acknowledgeAction(String(parsed.actionId || ""))
      bannerText = failedResults.length > 0
        ? "Plugin operation completed with " + failedResults.length + " failure"
          + (failedResults.length === 1 ? "." : "s.")
        : String(parsed.message || "Plugin operation completed.")
      bannerUrgent = failedResults.length > 0 || parsed.ok === false
      refresh()
      if (failedResults.length > 0)
        dialog.openFor("results", null, failedResults)
    } else if (state === "failed" || parsed.ok === false) {
      actionInProgress = false
      bannerText = String(parsed.error || parsed.message || "Plugin operation failed.")
      bannerUrgent = true
    }
  }

  function acknowledgeAction(actionId) {
    if (!helperPath || !actionId) return
    Quickshell.execDetached([helperPath, "ack", actionId])
  }

  function openActionDialog(mode, plugin, updates) {
    if (actionInProgress) {
      bannerText = "Wait for the current plugin operation to finish."
      bannerUrgent = true
      return
    }
    if (statusChecking) {
      bannerText = "Checking for an existing plugin operation…"
      bannerUrgent = false
      return
    }
    if (refreshing) {
      bannerText = "Wait for the catalog refresh to finish before changing plugins."
      bannerUrgent = true
      return
    }
    if (!snapshotActionable) {
      bannerText = snapshot && snapshot.error
        ? String(snapshot.error)
        : "Refresh the catalog before changing plugins."
      bannerUrgent = true
      return
    }
    dialog.openFor(mode, plugin, updates)
  }

  function actionIncludesSelf(kind, plugin, selectedUpdateIds) {
    if (kind === "update")
      return !!(plugin && String(plugin.id || "") === pluginId)
    if (kind === "update-all" && Array.isArray(selectedUpdateIds))
      return selectedUpdateIds.indexOf(pluginId) >= 0
    return kind === "update-all" && !!(snapshot && snapshot.self
      && snapshot.self.safeUpdate === true)
  }

  function beginAction(kind, plugin, selectedUpdateIds) {
    if (actionStarting || actionInProgress || statusChecking || refreshing || !helperPath
        || !snapshotActionable) return
    actionStarting = true
    actionReplacesOkomart = actionIncludesSelf(kind, plugin, selectedUpdateIds)
    pendingActionPlugin = plugin || null
    actionOutput = ""
    actionError = ""
    var command = [helperPath, "action", sourceDir, kind,
      plugin && plugin.id ? String(plugin.id) : "",
      String(snapshot.snapshotId)]
    if (kind === "update-all")
      command.push(JSON.stringify(Array.isArray(selectedUpdateIds)
        ? selectedUpdateIds : []))
    actionProcess.command = command
    actionProcess.running = true
  }

  function actionStarted(raw, exitCode) {
    actionStarting = false
    dialog.busy = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (exitCode !== 0 || !parsed || parsed.ok === false) {
      actionInProgress = false
      actionReplacesOkomart = false
      var startError = (parsed && (parsed.error || parsed.message))
        ? String(parsed.error || parsed.message)
        : (actionError.trim() || "Could not start plugin operation.")
      dialog.errorText = startError
      bannerText = startError
      bannerUrgent = true
      return
    }
    var replaceOkomart = actionReplacesOkomart
    actionReplacesOkomart = false
    updatesConfirmed = false
    dialog.closeDialog()
    actionInProgress = true
    if (replaceOkomart) {
      // The worker is detached now. Retire this loaded component so the
      // worker's final summon cannot reopen the pre-update panel instance.
      requestClose()
      return
    }
    bannerText = "Plugin operation started…"
    bannerUrgent = false
    actionPoll.restart()
  }

  Process {
    id: inactiveBorderProcess
    command: ["hyprctl", "-j", "getoption", "general:col.inactive_border"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inactiveBorderOutput = text
    }
    onExited: function(exitCode) {
      root.applyInactiveBorderColor(root.inactiveBorderOutput, exitCode)
    }
  }

  Process {
    id: windowRuleProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.windowRuleOutput = text
    }
    onExited: function(exitCode) {
      root.applyWindowRule(root.windowRuleOutput, exitCode)
    }
  }

  Process {
    id: cacheProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.cachedOutput = text
    }
    onExited: root.applyCachedSnapshot(root.cachedOutput)
  }

  Process {
    id: refreshProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.refreshOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.refreshError = text
    }
    onExited: function(exitCode) { root.applySnapshot(root.refreshOutput, exitCode) }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionError = text
    }
    onExited: function(exitCode) { root.actionStarted(root.actionOutput, exitCode) }
  }

  Process {
    id: statusProcess
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: statusProcess.output = text
    }
    onExited: root.applyActionStatus(output)
  }

  Timer {
    id: actionPoll
    interval: 800
    repeat: false
    onTriggered: root.loadActionStatus()
  }

  Timer {
    id: initialFocusTimer
    interval: 50
    repeat: true
    onTriggered: root.focusInitialPluginList()
  }

  FloatingWindow {
    id: window
    title: "Okomart"
    color: Color.background
    implicitWidth: root.windowSide
    implicitHeight: root.windowSide
    minimumSize: Qt.size(root.minimumWindowSide, root.minimumWindowSide)
    maximized: false
    fullscreen: false

    onVisibleChanged: {
      if (visible) {
        if (root.initialListFocusPending) initialFocusTimer.restart()
      } else {
        root.windowOpenPending = false
        if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function")
          root.shell.hide(root.pluginId)
      }
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Window.onActiveChanged: root.refreshInactiveBorderColor()

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (!dialog.opened
            && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          searchField.forceActiveFocus()
          searchField.selectAll()
          event.accepted = true
        } else if (!dialog.opened
            && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
          root.refresh()
          event.accepted = true
        } else if (!dialog.opened
            && event.key === Qt.Key_Slash && !searchField.activeFocus) {
          searchField.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.closeFromKeyboard()
          event.accepted = true
        }
      }

      StorefrontFrame {
        id: storefront
        anchors.fill: parent
        bodyTop: root.bodyTop
        splitX: root.splitX
        wideLayout: root.wideLayout
        awningVisible: root.wideLayout || !root.narrowShowingDetails
        strokeColor: root.storefrontColor
      }

      Text {
        id: brand
        x: storefront.frameLeft + root.headerEdgeInset
        y: root.wideLayout
          ? root.bodyTop - Style.space(50)
          : root.bodyTop - Style.space(124)
        width: root.wideLayout
          ? Math.max(Style.space(180), root.splitX - x - Style.space(28))
          : storefront.frameRight - x - root.headerEdgeInset
        text: "オコマート"
        color: root.storefrontColor
        font.family: Style.font.family
        font.pixelSize: root.wideLayout ? Style.font.displayLarge : Style.font.display
        horizontalAlignment: root.wideLayout ? Text.AlignLeft : Text.AlignHCenter
        elide: Text.ElideRight
      }

      GridLayout {
        id: toolbar
        readonly property real controlHeight: Math.max(
          searchField.implicitHeight,
          filterButton.implicitHeight,
          updatesButton.implicitHeight)

        enabled: !dialog.opened
        columns: root.toolbarSingleRow ? 3 : 2
        columnSpacing: Style.space(8)
        rowSpacing: Style.space(8)
        anchors.right: parent.right
        anchors.rightMargin: storefront.frameInset + root.headerEdgeInset
        y: root.toolbarSingleRow ? root.bodyTop - Style.space(45) : root.bodyTop - Style.space(70)

        TextField {
          id: searchField
          Layout.columnSpan: root.toolbarSingleRow ? 1 : 2
          Layout.preferredWidth: Style.space(150)
          Layout.minimumWidth: Style.space(150)
          Layout.maximumWidth: Style.space(150)
          Layout.preferredHeight: toolbar.controlHeight
          Layout.alignment: Qt.AlignVCenter
          placeholderText: "Search plugins…"
          text: root.query
          activeFocusOnTab: true
          Accessible.name: "Search plugins by title, description, or author"
          Accessible.role: Accessible.EditableText
          onTextChanged: if (text !== root.query) root.query = text
          Keys.onDownPressed: function(event) {
            root.focusPluginDetailsFromSearch()
            event.accepted = true
          }
          Keys.onLeftPressed: function(event) {
            if (text.length === 0) {
              root.focusPluginListFromSearch()
              event.accepted = true
            } else {
              event.accepted = false
            }
          }
          Keys.onRightPressed: function(event) {
            if (text.length === 0) {
              filterButton.forceActiveFocus()
              event.accepted = true
            } else {
              event.accepted = false
            }
          }
        }

        Button {
          id: filterButton
          Layout.preferredHeight: toolbar.controlHeight
          Layout.alignment: Qt.AlignVCenter
          focusable: true
          bordered: true
          selected: root.installedOnly
          iconText: root.installedOnly ? "󰈲" : "󱓯"
          tooltipText: root.installedOnly ? "Show all plugins" : "Show installed plugins only"
          onClicked: root.installedOnly = !root.installedOnly
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
              searchField.forceActiveFocus()
              event.accepted = true
            } else if ((event.key === Qt.Key_Right || event.key === Qt.Key_L)
                && updatesButton.visible) {
              updatesButton.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
              root.focusPluginListFromSearch()
              event.accepted = true
            }
          }
          Accessible.name: root.installedOnly ? "Installed filter on" : "Installed filter off"
          Accessible.role: Accessible.Button
        }

        Button {
          id: updatesButton
          Layout.preferredHeight: toolbar.controlHeight
          Layout.alignment: Qt.AlignVCenter
          visible: root.hasConfirmedUpdates
          focusable: true
          bordered: true
          selected: true
          enabled: root.snapshotActionable
            && !root.statusChecking && !root.refreshing && !root.actionInProgress
          iconText: "\uf021"
          tooltipText: root.safeUpdateCount > 0
            ? "Review " + root.safeUpdateCount + " plugin "
              + (root.safeUpdateCount === 1 ? "update" : "updates")
            : "Review detected plugin updates"
          onClicked: root.openActionDialog("updates", null, root.updateRows)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
              filterButton.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
              root.focusPluginListFromSearch()
              event.accepted = true
            }
          }
          Accessible.name: root.safeUpdateCount > 0
            ? root.safeUpdateCount + " plugin "
              + (root.safeUpdateCount === 1 ? "update" : "updates") + " available"
            : "Review detected plugin updates"
          Accessible.role: Accessible.Button
        }
      }

      PluginList {
        id: pluginList
        focus: true
        enabled: !dialog.opened
        visible: root.wideLayout || !root.narrowShowingDetails
        x: storefront.frameLeft + Style.space(13)
        y: storefront.awningY + Style.space(20)
        width: root.wideLayout
          ? root.splitX - x - Style.space(13)
          : storefront.frameRight - x - Style.space(13)
        height: storefront.frameBottom - y - Style.space(10)
        plugins: root.visiblePlugins
        selectedId: root.selectedId
        emptyText: root.catalogLoaded
          ? "No plugins match this search."
          : (root.cacheLoading || root.refreshing
            ? "Loading plugins…" : "No cached plugins available.")
        activateOnSingleClick: !root.wideLayout
        onSelected: function(pluginId) { root.selectedId = pluginId }
        onActivated: function(plugin) {
          root.selectedId = String(plugin.id || "")
          if (!root.wideLayout) {
            root.narrowShowingDetails = true
            Qt.callLater(pluginDetails.focusFirstControl)
          }
        }
        onDetailsRequested: function(plugin) {
          root.selectedId = String(plugin.id || "")
          if (!root.wideLayout) root.narrowShowingDetails = true
          Qt.callLater(pluginDetails.focusFirstAction)
        }
        onSearchRequested: searchField.forceActiveFocus()
      }

      PluginDetails {
        id: pluginDetails
        enabled: !dialog.opened
        visible: root.wideLayout || root.narrowShowingDetails
        x: root.wideLayout ? root.splitX + Style.space(18) : storefront.frameLeft + Style.space(18)
        y: root.bodyTop + Style.space(16)
        width: storefront.frameRight - x - Style.space(18)
        height: storefront.frameBottom - y - Style.space(12)
        plugin: root.selectedPlugin
        catalogRevision: String(root.snapshot.catalogCommit || "")
        narrowLayout: !root.wideLayout
        actionsEnabled: root.snapshotActionable && !root.statusChecking && !root.refreshing
          && !root.actionStarting && !root.actionInProgress
        onBackRequested: {
          root.narrowShowingDetails = false
          Qt.callLater(pluginList.focusCurrentItem)
        }
        onInstallRequested: function(plugin) { root.openActionDialog("install", plugin, []) }
        onRemoveRequested: function(plugin) { root.openActionDialog("remove", plugin, []) }
        onUpdateRequested: function(plugin) { root.openActionDialog("update", plugin, []) }
        onPluginListRequested: root.focusPluginListFromSearch()
        onSearchRequested: searchField.forceActiveFocus()
      }

      BorderSurface {
        id: statusBanner
        visible: root.bannerText !== ""
        z: 50
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(32)
        width: Math.min(parent.width - Style.space(40), statusText.implicitWidth + Style.space(28))
        height: statusText.implicitHeight + Style.space(14)
        color: Util.alpha(Color.background, 0.94)
        borderSpec: Border.flat(root.bannerUrgent ? Color.urgent : Color.accent, Math.max(1, Style.normalBorderWidth))
        radius: Style.cornerRadius

        Text {
          id: statusText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, statusBanner.width - Style.space(20))
          text: root.bannerText
          textFormat: Text.PlainText
          color: root.bannerUrgent ? Color.urgent : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      ActionDialog {
        id: dialog
        anchors.fill: parent
        selfPluginId: root.pluginId
        busy: root.actionStarting
        onCanceled: {
          if (!root.actionStarting) closeDialog()
        }
        onConfirmed: function(selectedUpdateIds) {
          if (mode === "results") {
            closeDialog()
            return
          }
          busy = true
          if (mode === "install") root.beginAction("install", plugin)
          else if (mode === "remove") root.beginAction("remove", plugin)
          else if (mode === "update") root.beginAction("update", plugin)
          else if (mode === "updates")
            root.beginAction("update-all", null, selectedUpdateIds)
        }
      }
    }
  }
}
