import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir: Quickshell.env("OKOMART_SOURCE_DIR")
  property var createdObjects: []
  property var detailsLayout: null
  property var pluginListContext: null
  property var screenshotCarouselContext: null
  property var panelEntry: null
  property var serviceEntry: null

  function manifestData() {
    return {
      schemaVersion: 1,
      id: "b.okomart",
      name: "Okomart",
      version: "test",
      kinds: ["service", "panel"],
      entryPoints: {
        service: "Service.qml",
        panel: "Okomart.qml"
      },
      __sourceDir: sourceDir
    }
  }

  function loadEntry(fileName, kind) {
    var url = encodeURI("file://" + sourceDir + "/" + fileName)
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("OKOMART_LOAD_ERROR " + kind + ": " + component.errorString())
      return
    }

    var object = component.createObject(host)
    if (!object) {
      console.error("OKOMART_CREATE_ERROR " + kind + ": " + component.errorString())
      return
    }

    if ("manifest" in object) object.manifest = manifestData()
    if ("shell" in object) object.shell = mockShell
    if (kind === "panel") panelEntry = object
    if (kind === "service") serviceEntry = object

    createdObjects.push(object)
    console.log("OKOMART_LOAD_OK " + kind)
  }

  function checkWindowModeEvents() {
    if (!serviceEntry) {
      console.error("OKOMART_WINDOW_MODE_ERROR service entry is unavailable")
      return false
    }

    var writesBefore = mockShell.windowModeWrites
    serviceEntry.handleHyprlandEvent({
      name: "openwindow",
      data: "0xABC,1,org.quickshell,Okomart"
    })
    if (serviceEntry.okomartWindowAddress !== "abc") {
      console.error("OKOMART_WINDOW_MODE_ERROR open event did not track Okomart")
      return false
    }
    var firstEntry = mockShell.shellConfig.plugins[0]
    if (firstEntry.windowMode !== "floating"
        || firstEntry.otherSetting !== "preserved"
        || mockShell.windowModeWrites !== writesBefore + 1) {
      console.error("OKOMART_WINDOW_MODE_ERROR first open did not persist the default mode")
      return false
    }
    serviceEntry.handleHyprlandEvent({
      name: "changefloatingmode",
      data: "abc,0"
    })
    var tiledEntry = mockShell.shellConfig.plugins[0]
    if (tiledEntry.windowMode !== "tiled"
        || tiledEntry.otherSetting !== "preserved"
        || mockShell.windowModeWrites !== writesBefore + 2) {
      console.error("OKOMART_WINDOW_MODE_ERROR tiled mode was not persisted inline")
      return false
    }
    serviceEntry.handleHyprlandEvent({
      name: "changefloatingmode",
      data: "0xABC,1"
    })
    if (mockShell.shellConfig.plugins[0].windowMode !== "floating"
        || mockShell.windowModeWrites !== writesBefore + 3) {
      console.error("OKOMART_WINDOW_MODE_ERROR latest mode did not win")
      return false
    }
    serviceEntry.handleHyprlandEvent({
      name: "changefloatingmode",
      data: "abc,1"
    })
    if (mockShell.windowModeWrites !== writesBefore + 3) {
      console.error("OKOMART_WINDOW_MODE_ERROR unchanged mode was written again")
      return false
    }
    serviceEntry.handleHyprlandEvent({ name: "closewindow", data: "abc" })
    if (serviceEntry.okomartWindowAddress !== "") {
      console.error("OKOMART_WINDOW_MODE_ERROR close event retained the window")
      return false
    }
    serviceEntry.handleHyprlandEvent({
      name: "openwindow",
      data: "0xDEF,1,org.quickshell,Okomart"
    })
    if (serviceEntry.okomartWindowAddress !== "def"
        || mockShell.shellConfig.plugins[0].windowMode !== "floating"
        || mockShell.windowModeWrites !== writesBefore + 3) {
      console.error("OKOMART_WINDOW_MODE_ERROR reopen changed the persisted mode")
      return false
    }
    serviceEntry.handleHyprlandEvent({ name: "closewindow", data: "def" })
    console.log("OKOMART_WINDOW_MODE_OK")
    return true
  }

  function loadDetailsLayout() {
    var url = encodeURI("file://" + sourceDir + "/PluginDetails.qml")
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("OKOMART_LAYOUT_LOAD_ERROR: " + component.errorString())
      return false
    }

    detailsLayout = component.createObject(host, {
      width: 400,
      height: 360,
      plugin: {
        id: "test.layout",
        name: "Layout test plugin",
        description: "Checks the responsive moped clearance.",
        author: "Okomart",
        version: "1.0.0",
        catalog: true,
        installed: false,
        sourceUrl: "https://example.com/test.layout.git"
      }
    })
    if (!detailsLayout) {
      console.error("OKOMART_LAYOUT_CREATE_ERROR: " + component.errorString())
      return false
    }

    createdObjects.push(detailsLayout)
    detailsLayout.screenshotImages = [sourceDir + "/assets/moped-source.svg"]
    return true
  }

  function pluginRows(prependCount) {
    var rows = []
    for (var added = 0; added < prependCount; added++) {
      rows.push({
        id: "test.new-" + added,
        name: "New plugin " + added,
        description: "Inserted ahead of the active row."
      })
    }
    for (var index = 0; index < 12; index++) {
      rows.push({
        id: "test.plugin-" + index,
        name: "Plugin " + index,
        description: "Viewport context test row " + index + "."
      })
    }
    return rows
  }

  function loadPluginListContext() {
    var url = encodeURI("file://" + sourceDir + "/PluginList.qml")
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("OKOMART_LIST_CONTEXT_ERROR: " + component.errorString())
      return false
    }

    pluginListContext = component.createObject(host, {
      width: 360,
      height: 300
    })
    if (!pluginListContext) {
      console.error("OKOMART_LIST_CONTEXT_ERROR: " + component.errorString())
      return false
    }

    createdObjects.push(pluginListContext)
    pluginListContext.plugins = pluginRows(0)
    pluginListContext.selectedId = "test.plugin-8"
    return true
  }

  function loadScreenshotCarouselContext() {
    var url = encodeURI("file://" + sourceDir + "/ScreenshotCarousel.qml")
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("OKOMART_CAROUSEL_CONTEXT_ERROR: " + component.errorString())
      return false
    }

    screenshotCarouselContext = component.createObject(host, {
      width: 360,
      height: 260
    })
    if (!screenshotCarouselContext) {
      console.error("OKOMART_CAROUSEL_CONTEXT_ERROR: " + component.errorString())
      return false
    }

    createdObjects.push(screenshotCarouselContext)
    screenshotCarouselContext.images = [
      sourceDir + "/assets/moped-source.svg",
      sourceDir + "/preview.png",
      sourceDir + "/assets/moped-source.svg",
      sourceDir + "/preview.png"
    ]
    return true
  }

  function checkScreenshotCarouselContext() {
    var outgoing = screenshotCarouselContext.imageForIndex(0)
    var outgoingSource = outgoing ? String(outgoing.source) : ""
    if (!outgoing || outgoingSource === "") {
      console.error("OKOMART_CAROUSEL_CONTEXT_ERROR outgoing screenshot was not loaded: images="
        + screenshotCarouselContext.imageCount + ", loaded="
        + JSON.stringify(screenshotCarouselContext.loadedIndices)
        + ", outgoing=" + outgoing + ", source=" + outgoingSource)
      Qt.quit()
      return
    }

    screenshotCarouselContext.select(2)
    var retained = screenshotCarouselContext.imageForIndex(0)
    var incoming = screenshotCarouselContext.imageForIndex(2)
    if (retained !== outgoing || String(retained.source) !== outgoingSource) {
      console.error("OKOMART_CAROUSEL_CONTEXT_ERROR selection rebuilt the outgoing screenshot")
      Qt.quit()
      return
    }
    if (!incoming || String(incoming.source) === "") {
      console.error("OKOMART_CAROUSEL_CONTEXT_ERROR selected screenshot was not preloaded")
      Qt.quit()
      return
    }
    console.log("OKOMART_CAROUSEL_CONTEXT_OK")
    root.checkPluginListContext()
  }

  function failPluginListContext(message) {
    console.error("OKOMART_LIST_CONTEXT_ERROR " + message)
    Qt.quit()
  }

  function detailsSnapshot(generation, firstName) {
    return {
      ok: true,
      snapshotId: generation,
      activeGeneration: generation,
      pending: null,
      plugins: [
        {
          id: "test.details-1",
          name: firstName,
          description: "The active details row.",
          sourceUrl: "https://example.com/test.details-1.git"
        },
        {
          id: "test.details-2",
          name: "Second plugin",
          description: "A different details row.",
          sourceUrl: "https://example.com/test.details-2.git"
        }
      ]
    }
  }

  function failDetailsContext(message) {
    console.error("OKOMART_DETAILS_CONTEXT_ERROR " + message)
    Qt.quit()
  }

  function checkDetailsContext() {
    panelEntry.setSnapshotData(detailsSnapshot("details-generation-1", "Original name"))
    Qt.callLater(function() {
      var original = panelEntry.selectedPlugin
      if (!original || original.id !== "test.details-1") {
        failDetailsContext("initial selection did not populate details")
        return
      }

      panelEntry.lazyScreenshots = ["kept-image"]
      panelEntry.lazyScreenshotRevision = "kept-revision"
      panelEntry.setSnapshotData(detailsSnapshot("details-generation-2", "Updated name"))
      Qt.callLater(function() {
        if (panelEntry.selectedPlugin !== original
            || panelEntry.selectedPlugin.name !== "Original name") {
          failDetailsContext("list replacement refreshed the active plugin object")
          return
        }
        if (panelEntry.lazyScreenshots.length !== 1
            || panelEntry.lazyScreenshots[0] !== "kept-image"
            || panelEntry.lazyScreenshotRevision !== "kept-revision") {
          failDetailsContext("list replacement refreshed active plugin media")
          return
        }

        panelEntry.selectedId = "test.details-2"
        Qt.callLater(function() {
          if (!panelEntry.selectedPlugin
              || panelEntry.selectedPlugin === original
              || panelEntry.selectedPlugin.id !== "test.details-2") {
            failDetailsContext("an actual selection change did not refresh details")
            return
          }
          if (panelEntry.lazyScreenshots.length !== 0
              || panelEntry.lazyScreenshotRevision !== "") {
            failDetailsContext("an actual selection change retained stale media")
            return
          }
          console.log("OKOMART_DETAILS_CONTEXT_OK")
          Qt.quit()
        })
      })
    })
  }

  function checkPluginListContext() {
    pluginListContext.syncCurrentIndex()
    Qt.callLater(function() {
      var requestedOffset = 31
      pluginListContext.restoreViewportAnchor({
        pluginId: "test.plugin-8",
        hasViewportOffset: true,
        viewportOffset: requestedOffset
      })
      var before = pluginListContext.captureViewportAnchor()
      if (!before || before.pluginId !== "test.plugin-8"
          || before.hasViewportOffset !== true
          || Math.abs(before.viewportOffset - requestedOffset) > 0.75) {
        failPluginListContext("could not establish the initial viewport anchor: "
          + JSON.stringify(before) + ", selected="
          + pluginListContext.selectedId + ", rows="
          + pluginListContext.plugins.length + ", index="
          + pluginListContext.indexForId("test.plugin-8") + ", first="
          + JSON.stringify(pluginListContext.plugins[0]) + ", firstId="
          + pluginListContext.idFor(pluginListContext.plugins[0]) + ", ninthId="
          + pluginListContext.idFor(pluginListContext.plugins[8]))
        return
      }

      pluginListContext.beginModelReset()
      pluginListContext.plugins = pluginRows(1)
      pluginListContext.endModelReset()
      var immediate = pluginListContext.captureViewportAnchor()
      if (!immediate || immediate.pluginId !== before.pluginId
          || immediate.hasViewportOffset !== true
          || Math.abs(immediate.viewportOffset - before.viewportOffset) > 0.75) {
        failPluginListContext("viewport restoration was deferred past the model reset: "
          + JSON.stringify(immediate))
        return
      }
      pluginListContext.beginModelReset()
      pluginListContext.plugins = pluginRows(3)
      pluginListContext.endModelReset()
      Qt.callLater(function() {
        var after = pluginListContext.captureViewportAnchor()
        if (!after || after.pluginId !== before.pluginId
            || after.hasViewportOffset !== true
            || Math.abs(after.viewportOffset - before.viewportOffset) > 0.75) {
          failPluginListContext("active row moved after rows were inserted ahead of it")
          return
        }
        if (pluginListContext.indexForId("test.plugin-8") !== 11) {
          failPluginListContext("fixture did not move the active row")
          return
        }
        console.log("OKOMART_LIST_CONTEXT_OK")
        root.checkDetailsContext()
      })
    })
  }

  function checkDetailsLayout() {
    Qt.callLater(function() {
      Qt.callLater(function() {
        if (detailsLayout.mopedHasRoom) {
          console.error("OKOMART_LAYOUT_ERROR moped visible in short pane: height="
            + detailsLayout.height + " screenshotBottom="
            + detailsLayout.screenshotContentBottom + " clearance="
            + detailsLayout.mopedRequiredClearance + " hasPlugin="
            + detailsLayout.hasPlugin + " screenshots="
            + detailsLayout.screenshots.length)
          Qt.quit()
          return
        }

        detailsLayout.height = 1200
        Qt.callLater(function() {
          if (!detailsLayout.mopedHasRoom) {
            console.error("OKOMART_LAYOUT_ERROR moped hidden in tall pane")
            Qt.quit()
            return
          }
          console.log("OKOMART_MOPED_LAYOUT_OK")
          root.checkScreenshotCarouselContext()
        })
      })
    })
  }

  Window {
    visible: true
    width: 400
    height: 1200

    Item {
      id: host
      anchors.fill: parent
    }
  }

  QtObject {
    id: mockShell

    property var shellConfig: ({
      version: 1,
      plugins: [{ id: "b.okomart", otherSetting: "preserved" }]
    })
    property int windowModeWrites: 0

    function updateEntryInline(moduleName, settings) {
      if (moduleName !== "b.okomart") return false
      var next = { id: moduleName }
      for (var key in settings) if (key !== "id") next[key] = settings[key]
      shellConfig = { version: 1, plugins: [next] }
      windowModeWrites += 1
      return true
    }

    function hide(pluginId) {
      return true
    }
  }

  Timer {
    interval: 1
    running: true
    repeat: false

    onTriggered: {
      root.loadEntry("Service.qml", "service")
      root.loadEntry("Okomart.qml", "panel")
      if (root.checkWindowModeEvents()
          && root.loadDetailsLayout() && root.loadPluginListContext()
          && root.loadScreenshotCarouselContext())
        root.checkDetailsLayout()
      else Qt.callLater(Qt.quit)
    }
  }
}
