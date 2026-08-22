import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property var plugins: []
  property string selectedId: ""
  property string emptyText: "No plugins match this search."
  property bool activateOnSingleClick: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real scrollNubRightOffset: 0
  property bool viewportRestorePending: false
  property var viewportAnchor: null
  property int viewportRestoreSerial: 0

  signal selected(string pluginId)
  signal activated(var plugin)
  signal detailsRequested(var plugin)
  signal searchRequested()

  activeFocusOnTab: true
  readonly property real rowHeight: Style.space(76)

  function idFor(plugin) {
    return plugin && plugin.id !== undefined ? String(plugin.id) : ""
  }

  function selectedPlugin() {
    if (!Array.isArray(plugins) || list.currentIndex < 0 || list.currentIndex >= plugins.length)
      return null
    return plugins[list.currentIndex]
  }

  function indexForId(pluginId) {
    var id = String(pluginId || "")
    if (!Array.isArray(plugins)) return -1
    for (var i = 0; i < plugins.length; i++)
      if (idFor(plugins[i]) === id) return i
    return -1
  }

  function captureViewportAnchor() {
    var index = indexForId(selectedId)
    if (index < 0) return null

    var item = index === list.currentIndex
      ? list.currentItem : list.itemAtIndex(index)
    if (!item) {
      return {
        pluginId: String(selectedId),
        hasViewportOffset: false,
        viewportOffset: 0
      }
    }

    var offset = Number(item.y) - Number(list.contentY)
    var itemHeight = Number(item.height)
    return {
      pluginId: String(selectedId),
      hasViewportOffset: isFinite(offset) && isFinite(itemHeight)
        && offset < list.height && offset + itemHeight > 0,
      viewportOffset: offset
    }
  }

  function beginModelReset() {
    if (!viewportRestorePending) viewportAnchor = captureViewportAnchor()
    viewportRestorePending = true
    viewportRestoreSerial += 1
  }

  function restoreViewportAnchor(anchor) {
    var activeIndex = indexForId(selectedId)
    if (activeIndex < 0) {
      list.currentIndex = -1
      return
    }

    if (list.currentIndex !== activeIndex) list.currentIndex = activeIndex
    list.forceLayout()

    var anchorId = anchor && anchor.pluginId !== undefined
      ? String(anchor.pluginId) : ""
    var anchorIndex = indexForId(anchorId)
    if (!anchor || anchor.hasViewportOffset !== true || anchorIndex < 0) {
      list.positionViewAtIndex(activeIndex, ListView.Contain)
      return
    }

    list.positionViewAtIndex(anchorIndex, ListView.Beginning)
    list.forceLayout()
    var anchorItem = list.itemAtIndex(anchorIndex)
    if (!anchorItem) {
      list.positionViewAtIndex(activeIndex, ListView.Contain)
      return
    }

    var minimumContentY = Number(list.originY)
    var maximumContentY = minimumContentY
      + Math.max(0, Number(list.contentHeight) - Number(list.height))
    var desiredContentY = Number(anchorItem.y) - Number(anchor.viewportOffset)
    list.contentY = Math.max(minimumContentY,
      Math.min(maximumContentY, desiredContentY))

    var activeItem = list.itemAtIndex(activeIndex)
    if (!activeItem
        || activeItem.y + activeItem.height <= list.contentY
        || activeItem.y >= list.contentY + list.height)
      list.positionViewAtIndex(activeIndex, ListView.Contain)
  }

  function endModelReset() {
    if (!viewportRestorePending) {
      Qt.callLater(syncCurrentIndex)
      return
    }

    var restoreSerial = viewportRestoreSerial
    var anchor = viewportAnchor
    Qt.callLater(function() {
      if (!viewportRestorePending || restoreSerial !== viewportRestoreSerial)
        return
      restoreViewportAnchor(anchor)
      viewportAnchor = null
      viewportRestorePending = false
    })
  }

  function syncCurrentIndex() {
    var next = indexForId(selectedId)
    if (next < 0 && Array.isArray(plugins) && plugins.length > 0) next = 0
    if (list.currentIndex !== next) list.currentIndex = next
    if (next >= 0) list.positionViewAtIndex(next, ListView.Contain)
  }

  function move(delta) {
    if (!Array.isArray(plugins) || plugins.length === 0) return
    var next = Math.max(0, Math.min(plugins.length - 1, list.currentIndex + delta))
    list.currentIndex = next
    list.positionViewAtIndex(next, ListView.Contain)
  }

  function movePage(delta) {
    var rows = Math.max(1, Math.floor(list.height / (rowHeight + list.spacing)))
    move(delta * rows)
  }

  function focusCurrentItem() {
    syncCurrentIndex()
    list.forceActiveFocus()
  }

  function focusFirstItem() {
    if (Array.isArray(plugins) && plugins.length > 0) {
      list.currentIndex = 0
      list.positionViewAtBeginning()
      var plugin = selectedPlugin()
      var id = idFor(plugin)
      if (id !== selectedId) root.selected(id)
    }
    list.forceActiveFocus()
  }

  onPluginsChanged: {
    if (!viewportRestorePending) Qt.callLater(syncCurrentIndex)
  }
  onSelectedIdChanged: {
    if (indexForId(selectedId) !== list.currentIndex) {
      if (!viewportRestorePending) Qt.callLater(syncCurrentIndex)
    }
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
      move(1); event.accepted = true
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
      if (list.currentIndex <= 0) {
        if (!event.isAutoRepeat) root.searchRequested()
      }
      else move(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
      var detailsPlugin = selectedPlugin()
      if (detailsPlugin) root.detailsRequested(detailsPlugin)
      event.accepted = detailsPlugin !== null
    } else if (event.key === Qt.Key_PageDown) {
      movePage(1); event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      movePage(-1); event.accepted = true
    } else if (event.key === Qt.Key_Home || event.text === "g") {
      if (plugins.length > 0) list.currentIndex = 0
      list.positionViewAtBeginning()
      event.accepted = true
    } else if (event.key === Qt.Key_End || event.text === "G") {
      if (plugins.length > 0) list.currentIndex = plugins.length - 1
      list.positionViewAtEnd()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      var plugin = selectedPlugin()
      if (plugin) root.activated(plugin)
      event.accepted = true
    }
  }

  ListView {
    id: list
    anchors.fill: parent
    focus: true
    clip: true
    model: Array.isArray(root.plugins) ? root.plugins : []
    spacing: Style.space(5)
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true
    cacheBuffer: Math.max(0, height)
    currentIndex: -1

    onCurrentIndexChanged: {
      var plugin = root.selectedPlugin()
      if (!plugin) return
      var id = root.idFor(plugin)
      if (id !== root.selectedId) root.selected(id)
    }

    delegate: CursorSurface {
      id: row
      required property int index
      required property var modelData

      readonly property bool rowSelected: index === list.currentIndex
      readonly property bool installed: !!(modelData && modelData.installed === true)
      readonly property bool disabled: installed
        && typeof modelData.enabled === "boolean" && modelData.enabled === false
      readonly property bool updateAvailable: installed
        && modelData.versionUpdateAvailable === true
      readonly property string pluginId: root.idFor(modelData)
      readonly property string title: String(modelData.name || modelData.id || "Unnamed plugin")
      readonly property string description: String(modelData.description || "No description provided.")

      width: list.width
      height: root.rowHeight
      current: rowSelected
      hasCursor: rowSelected && root.activeFocus
      foreground: root.foreground
      accent: root.accent

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(3)

        Row {
          width: parent.width
          spacing: Style.space(7)

          Row {
            id: stateIndicators
            spacing: Style.space(4)

            Text {
              id: installedIndicator
              visible: row.installed
              text: row.updateAvailable ? "\uf021" : "󰏗"
              textFormat: Text.PlainText
              y: Math.round((parent.height - height) / 2)
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              Accessible.ignored: true
            }

            Text {
              id: disabledIndicator
              visible: row.disabled
              text: "󰅖"
              textFormat: Text.PlainText
              y: Math.round((parent.height - height) / 2)
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              Accessible.ignored: true
            }
          }

          Text {
            width: Math.max(0, parent.width
              - (stateIndicators.width > 0
                ? stateIndicators.width + parent.spacing : 0))
            text: row.title
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: row.rowSelected
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          text: row.description
          textFormat: Text.PlainText
          color: Util.alpha(root.foreground, 0.72)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          list.currentIndex = row.index
          list.forceActiveFocus()
          if (root.activateOnSingleClick || (mouse.button === Qt.LeftButton && mouse.modifiers & Qt.ControlModifier))
            root.activated(row.modelData)
        }
        onDoubleClicked: root.activated(row.modelData)
      }

      Accessible.name: row.title
        + (row.installed ? ", installed" : "")
        + (row.disabled ? ", disabled" : "")
        + (row.updateAvailable ? ", update available" : "")
      Accessible.description: row.description
      Accessible.role: Accessible.ListItem
    }

    Text {
      visible: list.count === 0
      anchors.centerIn: parent
      width: Math.max(0, parent.width - Style.space(32))
      text: root.emptyText
      color: Util.alpha(root.foreground, 0.68)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  QQC.ScrollBar {
    id: pluginListScrollNub
    anchors.top: root.top
    anchors.right: root.right
    anchors.bottom: root.bottom
    anchors.rightMargin: -root.scrollNubRightOffset
    orientation: Qt.Vertical
    position: list.visibleArea.yPosition
    size: list.visibleArea.heightRatio
    policy: list.contentHeight > list.height + 0.5
      ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
    z: 10
    interactive: true
    width: Style.space(10)
    padding: 0
    minimumSize: Math.min(1, Style.space(72) / Math.max(1, list.height))

    onPositionChanged: {
      if (!pressed) return
      var maximumPosition = Math.max(0, 1 - size)
      var nextPosition = Math.max(0, Math.min(maximumPosition, position))
      list.contentY = list.originY + nextPosition * list.contentHeight
    }

    contentItem: Rectangle {
      implicitWidth: Style.space(10)
      implicitHeight: Style.space(72)
      radius: 0
      color: Util.alpha(root.accent, 0.92)
    }

    background: Item {}
    Accessible.name: "Plugin list scroll position"
  }

  Accessible.name: "Plugin list"
  Accessible.role: Accessible.List
}
