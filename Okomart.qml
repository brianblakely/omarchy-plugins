import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "OkomartModel.js" as OkomartModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.okomart"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/bin/okomart" : ""

  property bool closingFromHost: false
  property bool cacheLoading: false
  property bool catalogLoaded: false
  property bool refreshing: false
  property bool refreshQueued: false
  property bool refreshQueuedForced: false
  property bool enriching: false
  property bool activatingCatalog: false
  property bool updateChecking: false
  property bool updateCheckQueued: false
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
  property string enrichmentOutput: ""
  property string activationOutput: ""
  property string updateCheckOutput: ""
  property string mediaOutput: ""
  property string windowRuleOutput: ""
  property string actionOutput: ""
  property string actionError: ""
  property string bannerText: ""
  property bool bannerUrgent: false
  property var snapshot: ({})
  property var allPlugins: []
  property var visiblePlugins: []
  property var updateRows: []
  property string pendingGeneration: ""
  property bool pendingReady: false
  property var lazyScreenshots: []
  property string lazyScreenshotRevision: ""
  property string mediaSessionId: ""
  property string mediaRequestKey: ""
  property int mediaRequestSerial: 0
  property color inactiveBorderColor: Qt.rgba(
    0x59 / 255, 0x59 / 255, 0x59 / 255, 0xaa / 255)

  readonly property real outputScale: {
    var scale = Number(window.devicePixelRatio)
    return isFinite(scale) && scale >= 1 ? scale : 1
  }
  readonly property real wideLayoutBreakpoint: Style.space(600)
  readonly property real contentScale: OkomartModel.dpiCompactionScale(
    window.width, wideLayoutBreakpoint, outputScale)
  readonly property real layoutWidth: window.width / contentScale
  readonly property real layoutHeight: window.height / contentScale
  readonly property bool wideLayout: layoutWidth >= wideLayoutBreakpoint
  readonly property bool toolbarSingleRow: layoutWidth >= Style.space(420)
  property int windowSide: Style.space(760)
  readonly property int minimumWindowSide:
    Math.min(windowSide, Style.space(560))
  readonly property real bodyTop: Math.max(Style.space(164), Math.min(Style.space(205), layoutHeight * 0.255))
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
    && snapshot.snapshotId && snapshot.ok === true)

  onWideLayoutChanged: {
    if (wideLayout) narrowShowingDetails = false
    resetLazyScreenshots()
    scheduleLazyScreenshots()
  }
  onNarrowShowingDetailsChanged: {
    resetLazyScreenshots()
    scheduleLazyScreenshots()
  }
  onSelectedIdChanged: {
    resetLazyScreenshots()
    scheduleLazyScreenshots()
  }
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
    screenshotLightbox.clear()
    resetLazyScreenshots()
    if (helperPath) Quickshell.execDetached([helperPath, "cleanup-media", "--all"])
    updatesConfirmed = false
    statusChecking = true
    pendingReady = false
    pendingGeneration = ""
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
    loadCachedSnapshot(true)
    windowOpenPending = true
    prepareFloatingWindow()
  }

  function close() {
    windowOpenPending = false
    initialListFocusPending = false
    initialFocusTimer.stop()
    screenshotLightbox.clear()
    resetLazyScreenshots()
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
    scheduleLazyScreenshots()
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

  function openScreenshotLightbox(index) {
    if (dialog.opened || !selectedPlugin) return
    var images = Array.isArray(lazyScreenshots) ? lazyScreenshots : []
    if (images.length < 1) return
    var revision = String(lazyScreenshotRevision || "")
    var name = String(selectedPlugin.name || selectedPlugin.id || "Plugin")
    screenshotLightbox.openFor(images, revision, index, name)
  }

  function detailsAreOpen() {
    return window.visible && !!selectedPlugin
      && (wideLayout || narrowShowingDetails)
  }

  function nextMediaSessionId() {
    return Date.now().toString(36) + "-" + mediaRequestSerial.toString(36)
  }

  function resetLazyScreenshots() {
    mediaDebounce.stop()
    mediaRequestSerial++
    mediaRequestKey = ""
    lazyScreenshots = []
    lazyScreenshotRevision = ""
    if (mediaProcess.running) mediaProcess.running = false
    if (helperPath && mediaSessionId)
      Quickshell.execDetached([helperPath, "cleanup-media", mediaSessionId])
    mediaSessionId = ""
  }

  function scheduleLazyScreenshots() {
    if (!helperPath || !detailsAreOpen()) return
    mediaSessionId = nextMediaSessionId()
    mediaDebounce.restart()
  }

  function requestLazyScreenshots() {
    if (!detailsAreOpen() || !selectedPlugin || mediaProcess.running) return
    var id = String(selectedPlugin.id || "")
    var installedPath = selectedPlugin.installed === true
      ? String(selectedPlugin.installedPath || "") : ""
    var sourceUrl = String(selectedPlugin.sourceUrl || "")
    var revision = String(selectedPlugin.revision
      || selectedPlugin.catalogCommit || "")
    var key = id + "|" + installedPath + "|" + sourceUrl + "|" + revision
      + "|" + mediaSessionId
    mediaRequestKey = key
    mediaOutput = ""
    mediaProcess.requestKey = key
    mediaProcess.requestPluginId = id
    mediaProcess.command = [helperPath, "screenshots", JSON.stringify({
      id: id,
      installedPath: installedPath,
      sourceUrl: sourceUrl,
      revision: revision
    }), mediaSessionId]
    mediaProcess.running = true
  }

  function applyLazyScreenshots(raw, requestKey, requestPluginId) {
    if (requestKey !== mediaRequestKey || !detailsAreOpen()
        || !selectedPlugin || String(selectedPlugin.id || "") !== requestPluginId)
      return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (!parsed || parsed.ok !== true || !Array.isArray(parsed.images)) return
    lazyScreenshots = parsed.images
    lazyScreenshotRevision = String(parsed.revision || "")
  }

  function omitFailedScreenshot(index) {
    if (index < 0 || index >= lazyScreenshots.length) return
    var remaining = lazyScreenshots.slice()
    remaining.splice(index, 1)
    lazyScreenshots = remaining
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
    if (screenshotLightbox.opened) {
      screenshotLightbox.closeLightbox()
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
    var next = OkomartModel.filterPlugins(allPlugins, query, installedOnly)
    visiblePlugins = next
    selectedId = OkomartModel.resolveSelection(next, selectedId)
    if (!selectedId) narrowShowingDetails = false
  }

  function buildUpdates(data) {
    var rows = []
    var plugins = data && Array.isArray(data.plugins) ? data.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var p = plugins[i]
      if (p.installed && p.versionUpdateAvailable === true) rows.push(p)
    }
    if (data && data.self && data.self.versionUpdateAvailable === true) {
      var selfRow = {}
      for (var key in data.self) selfRow[key] = data.self[key]
      selfRow.id = pluginId
      selfRow.name = "Okomart"
      rows.push(selfRow)
    }
    return rows
  }

  function setSnapshotData(parsed) {
    var previousGeneration = String(snapshot.activeGeneration || snapshot.snapshotId || "")
    var nextGeneration = String(parsed.activeGeneration || parsed.snapshotId || "")
    snapshot = parsed
    allPlugins = Array.isArray(parsed.plugins) ? parsed.plugins : []
    updateRows = buildUpdates(parsed)
    pendingGeneration = parsed.pending && parsed.pending.generation
      ? String(parsed.pending.generation) : ""
    pendingReady = !!(parsed.pending && parsed.pending.ready === true
      && pendingGeneration)
    catalogLoaded = true
    rebuildView()
    if (previousGeneration !== nextGeneration) {
      resetLazyScreenshots()
      Qt.callLater(scheduleLazyScreenshots)
    }
  }

  function loadCachedSnapshot(startBackground, checkAfterLoad, rediscoverScreenshots) {
    if (!helperPath) {
      bannerText = "Okomart could not determine its source directory."
      bannerUrgent = true
      return
    }
    if (cacheProcess.running) {
      cacheProcess.startBackground = cacheProcess.startBackground || startBackground === true
      cacheProcess.checkAfterLoad = cacheProcess.checkAfterLoad || checkAfterLoad === true
      cacheProcess.rediscoverScreenshots = cacheProcess.rediscoverScreenshots
        || rediscoverScreenshots === true
      return
    }
    cacheLoading = true
    cachedOutput = ""
    cacheProcess.startBackground = startBackground === true
    cacheProcess.checkAfterLoad = checkAfterLoad === true
    cacheProcess.rediscoverScreenshots = rediscoverScreenshots === true
    cacheProcess.command = [helperPath, "snapshot", sourceDir]
    cacheProcess.running = true
  }

  function applyCachedSnapshot(raw, startBackground, checkAfterLoad, rediscoverScreenshots) {
    cacheLoading = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (parsed && Array.isArray(parsed.plugins)) {
      setSnapshotData(parsed)
      var catalogErrors = Array.isArray(parsed.catalogErrors) ? parsed.catalogErrors : []
      if (catalogErrors.length > 0 && bannerText === "") {
        bannerText = catalogErrors.length + " catalog refresh "
          + (catalogErrors.length === 1 ? "issue was" : "issues were")
          + " recorded."
        bannerUrgent = true
      }
    }
    if (startBackground) {
      loadActionStatus()
      refresh(false)
      checkUpdates()
    } else {
      maybeStartEnrichment()
      if (checkAfterLoad) checkUpdates()
    }
    if (rediscoverScreenshots) {
      resetLazyScreenshots()
      Qt.callLater(scheduleLazyScreenshots)
    }
  }

  function applySnapshot(raw, exitCode) {
    refreshing = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (exitCode !== 0 || !parsed || parsed.ok !== true) {
      bannerText = refreshError.trim() || "Catalog refresh failed."
      if (parsed && parsed.error) bannerText = String(parsed.error)
      bannerUrgent = true
    } else if (!parsed.changed && !parsed.pending) {
      bannerText = ""
      bannerUrgent = false
    }
    loadCachedSnapshot(false, !!(parsed && parsed.coldPublished === true))

    if (refreshQueued) {
      var forceQueued = refreshQueuedForced
      refreshQueued = false
      refreshQueuedForced = false
      Qt.callLater(function() { root.refresh(forceQueued) })
    }
  }

  function refresh(force) {
    if (!sourceDir || !helperPath) {
      bannerText = "Okomart could not determine its source directory."
      bannerUrgent = true
      return
    }
    if (refreshing) {
      if (force === true) {
        refreshQueued = true
        refreshQueuedForced = true
      }
      return
    }
    refreshing = true
    refreshOutput = ""
    refreshError = ""
    bannerText = ""
    bannerUrgent = false
    refreshProcess.command = force === true
      ? [helperPath, "refresh", sourceDir, "--force"]
      : [helperPath, "refresh", sourceDir]
    refreshProcess.running = true
  }

  function maybeStartEnrichment() {
    if (refreshing || enriching || !pendingGeneration || pendingReady
        || !helperPath) return
    enriching = true
    enrichmentOutput = ""
    enrichmentProcess.generation = pendingGeneration
    enrichmentProcess.command = [helperPath, "enrich", pendingGeneration]
    enrichmentProcess.running = true
  }

  function applyEnrichment(raw, generation) {
    enriching = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (!parsed || parsed.stale === true || String(parsed.generation || "") !== generation
        || generation !== pendingGeneration) {
      Qt.callLater(maybeStartEnrichment)
      return
    }
    loadCachedSnapshot(false)
  }

  function activatePendingCatalog() {
    if (!pendingReady || !pendingGeneration || activatingCatalog || !helperPath) return
    activatingCatalog = true
    activationOutput = ""
    activationProcess.generation = pendingGeneration
    activationProcess.command = [helperPath, "promote", pendingGeneration]
    activationProcess.running = true
  }

  function applyCatalogActivation(raw, generation) {
    activatingCatalog = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    if (!parsed || parsed.stale === true || parsed.promoted !== true
        || String(parsed.generation || "") !== generation
        || generation !== pendingGeneration) return
    pendingReady = false
    loadCachedSnapshot(false, true, true)
  }

  function checkUpdates() {
    if (!helperPath || !snapshotActionable) return
    if (updateCheckProcess.running) {
      updateCheckQueued = true
      return
    }
    updateCheckQueued = false
    updateChecking = true
    updateCheckOutput = ""
    updateCheckProcess.generation = String(snapshot.activeGeneration || snapshot.snapshotId || "")
    updateCheckProcess.command = [helperPath, "check-updates", sourceDir]
    updateCheckProcess.running = true
  }

  function applyUpdateCheck(raw, exitCode, generation) {
    updateChecking = false
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {}
    var currentGeneration = String(snapshot.activeGeneration || snapshot.snapshotId || "")
    var valid = !(exitCode !== 0 || !parsed || parsed.ok !== true || parsed.stale === true
        || String(parsed.activeGeneration || parsed.snapshotId || "") !== generation
        || generation !== currentGeneration)
    if (valid) {
      parsed.pending = snapshot.pending || null
      parsed.catalogErrors = snapshot.catalogErrors || []
      setSnapshotData(parsed)
      updatesConfirmed = OkomartModel.snapshotConfirmsUpdates(parsed, exitCode)
    }
    if (updateCheckQueued) {
      updateCheckQueued = false
      Qt.callLater(checkUpdates)
    }
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
      loadCachedSnapshot(false)
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
      return
    }

    var results = Array.isArray(parsed.results) ? parsed.results : []
    var failedResults = []
    for (var i = 0; i < results.length; i++)
      if (results[i] && results[i].ok === false) failedResults.push(results[i])
    actionInProgress = false
    var reconciledSnapshot = OkomartModel.reconcileActionSnapshot(
      snapshot, results, pluginId)
    if (reconciledSnapshot && Array.isArray(reconciledSnapshot.plugins))
      setSnapshotData(reconciledSnapshot)
    acknowledgeAction(String(parsed.actionId || ""))
    bannerText = failedResults.length > 0
      ? "Plugin operation completed with " + failedResults.length + " failure"
        + (failedResults.length === 1 ? "." : "s.")
      : String(parsed.message || "Plugin operation completed.")
    bannerUrgent = failedResults.length > 0 || parsed.ok === false
    loadCachedSnapshot(false, true, true)
    if (failedResults.length > 0)
      dialog.openFor("results", null, failedResults)
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
    if (!snapshotActionable) {
      bannerText = snapshot && snapshot.error
        ? String(snapshot.error)
        : "Refresh the catalog before changing plugins."
      bannerUrgent = true
      return
    }
    dialog.openFor(mode, plugin, updates)
  }

  function actionIncludesSelf(kind, selectedUpdateIds) {
    return kind === "update-all" && Array.isArray(selectedUpdateIds)
      && selectedUpdateIds.indexOf(pluginId) >= 0
  }

  function beginAction(kind, plugin, selectedUpdateIds) {
    if (actionStarting || actionInProgress || statusChecking || !helperPath
        || !snapshotActionable) return
    actionStarting = true
    actionReplacesOkomart = actionIncludesSelf(kind, selectedUpdateIds)
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
    property bool startBackground: false
    property bool checkAfterLoad: false
    property bool rediscoverScreenshots: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.cachedOutput = text
    }
    onExited: root.applyCachedSnapshot(
      root.cachedOutput, startBackground, checkAfterLoad, rediscoverScreenshots)
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
    id: enrichmentProcess
    property string generation: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.enrichmentOutput = text
    }
    onExited: root.applyEnrichment(root.enrichmentOutput, generation)
  }

  Process {
    id: activationProcess
    property string generation: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activationOutput = text
    }
    onExited: root.applyCatalogActivation(root.activationOutput, generation)
  }

  Process {
    id: updateCheckProcess
    property string generation: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateCheckOutput = text
    }
    onExited: function(exitCode) {
      root.applyUpdateCheck(root.updateCheckOutput, exitCode, generation)
    }
  }

  Process {
    id: mediaProcess
    property string requestKey: ""
    property string requestPluginId: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mediaOutput = text
    }
    onExited: root.applyLazyScreenshots(
      root.mediaOutput, requestKey, requestPluginId)
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

  Timer {
    id: mediaDebounce
    interval: 350
    repeat: false
    onTriggered: root.requestLazyScreenshots()
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
        root.scheduleLazyScreenshots()
      } else {
        root.windowOpenPending = false
        root.resetLazyScreenshots()
        if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function")
          root.shell.hide(root.pluginId)
      }
    }

    FocusScope {
      id: focusScope
      width: parent.width / root.contentScale
      height: parent.height / root.contentScale
      focus: true
      transform: Scale {
        origin.x: 0
        origin.y: 0
        xScale: root.contentScale
        yScale: root.contentScale
      }
      Window.onActiveChanged: root.refreshInactiveBorderColor()

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (!dialog.opened && !screenshotLightbox.opened
            && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          searchField.forceActiveFocus()
          searchField.selectAll()
          event.accepted = true
        } else if (!dialog.opened && !screenshotLightbox.opened
            && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
          root.refresh(true)
          event.accepted = true
        } else if (!dialog.opened && !screenshotLightbox.opened
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

      FocusScope {
        id: catalogSign
        x: storefront.frameLeft + root.headerEdgeInset
        y: root.wideLayout
          ? root.bodyTop - Style.space(50)
          : root.bodyTop - Style.space(124)
        width: root.wideLayout
          ? Math.max(Style.space(180), root.splitX - x - Style.space(28))
          : storefront.frameRight - x - root.headerEdgeInset
        height: signText.implicitHeight + Style.space(10)
        enabled: root.pendingReady && !root.activatingCatalog
        activeFocusOnTab: enabled

        Rectangle {
          id: signGlow
          anchors.fill: signText
          anchors.margins: -Style.space(6)
          radius: Style.cornerRadius
          color: "transparent"
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: Color.accent
          opacity: 0
        }

        SequentialAnimation {
          running: root.pendingReady
          loops: Animation.Infinite
          NumberAnimation {
            target: signGlow
            property: "opacity"
            from: 0.08
            to: 0.72
            duration: 1700
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: signGlow
            property: "opacity"
            from: 0.72
            to: 0.08
            duration: 1700
            easing.type: Easing.InOutSine
          }
        }

        Text {
          id: signText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "オコマート"
          color: root.storefrontColor
          font.family: Style.font.family
          font.pixelSize: root.wideLayout ? Style.font.displayLarge : Style.font.display
          horizontalAlignment: root.wideLayout ? Text.AlignLeft : Text.AlignHCenter
          elide: Text.ElideRight
        }

        HoverHandler {
          enabled: catalogSign.enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
          enabled: catalogSign.enabled
          onTapped: root.activatePendingCatalog()
        }

        Keys.onPressed: function(event) {
          if (enabled && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || event.key === Qt.Key_Space)) {
            root.activatePendingCatalog()
            event.accepted = true
          }
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.pendingReady
          ? "Activate the ready Okomart catalog update"
          : "Okomart storefront sign"
        Accessible.description: root.pendingReady
          ? "Promotes the staged plugin catalog without changing the current search or selection"
          : "No catalog update is ready"
        Accessible.ignored: !root.pendingReady
        Accessible.onPressAction: root.activatePendingCatalog()
      }

      GridLayout {
        id: toolbar
        readonly property real controlHeight: Math.max(
          searchField.implicitHeight,
          filterButton.implicitHeight,
          updatesButton.implicitHeight)

        enabled: !dialog.opened && !screenshotLightbox.opened
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
            && !root.statusChecking && !root.actionInProgress
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
        enabled: !dialog.opened && !screenshotLightbox.opened
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
        enabled: !dialog.opened && !screenshotLightbox.opened
        visible: root.wideLayout || root.narrowShowingDetails
        x: root.wideLayout ? root.splitX + Style.space(18) : storefront.frameLeft + Style.space(18)
        y: root.bodyTop + Style.space(16)
        width: storefront.frameRight - x - Style.space(18)
        height: storefront.frameBottom - y - Style.space(12)
        plugin: root.selectedPlugin
        screenshotImages: root.lazyScreenshots
        screenshotRevision: root.lazyScreenshotRevision
        narrowLayout: !root.wideLayout
        actionsEnabled: root.snapshotActionable && !root.statusChecking
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
        onScreenshotRequested: function(index) { root.openScreenshotLightbox(index) }
        onScreenshotFailed: function(index) { root.omitFailedScreenshot(index) }
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

      ScreenshotLightbox {
        id: screenshotLightbox
        anchors.fill: parent
        onDismissed: function(index) { pluginDetails.restoreScreenshot(index) }
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
