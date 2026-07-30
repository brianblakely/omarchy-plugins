import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir: Quickshell.env("OKOMART_SOURCE_DIR")
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var createdObjects: []

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

    var object = component.createObject(host, {
      manifest: manifestData(),
      omarchyPath: omarchyPath,
      shell: mockShell
    })
    if (!object) {
      console.error("OKOMART_CREATE_ERROR " + kind + ": " + component.errorString())
      return
    }

    createdObjects.push(object)
    console.log("OKOMART_LOAD_OK " + kind)
  }

  Item {
    id: host
  }

  QtObject {
    id: mockShell

    function hide(pluginId) {
      return true
    }

    function serviceFor(pluginId) {
      return null
    }

    function summon(pluginId, payloadJson) {
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
      Qt.callLater(Qt.quit)
    }
  }
}
