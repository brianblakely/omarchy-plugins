import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir: Quickshell.env("OKOMART_SOURCE_DIR")
  property var createdObjects: []
  property var detailsLayout: null

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

    createdObjects.push(object)
    console.log("OKOMART_LOAD_OK " + kind)
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
          Qt.quit()
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
      if (root.loadDetailsLayout()) root.checkDetailsLayout()
      else Qt.callLater(Qt.quit)
    }
  }
}
