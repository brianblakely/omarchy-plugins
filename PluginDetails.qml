import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "OkomartModel.js" as OkomartModel

FocusScope {
  id: root

  property var plugin: null
  property string catalogRevision: ""
  property bool narrowLayout: false
  property bool actionsEnabled: true
  property bool actionFocusPending: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent

  signal backRequested()
  signal installRequested(var plugin)
  signal removeRequested(var plugin)
  signal updateRequested(var plugin)
  signal pluginListRequested()
  signal searchRequested()
  signal screenshotRequested(int index)

  readonly property bool hasPlugin: plugin !== null && plugin !== undefined
  readonly property bool installed: hasPlugin && plugin.installed === true
  readonly property var screenshots: hasPlugin && Array.isArray(plugin.images) ? plugin.images : []
  readonly property string normalizedUpdateState:
    hasPlugin ? OkomartModel.updateState(plugin) : ""
  readonly property string removalBlockReason:
    hasPlugin ? OkomartModel.removalBlockReason(plugin) : ""
  readonly property bool removalAllowed:
    hasPlugin && OkomartModel.canRemovePlugin(plugin)
  readonly property bool updateAvailable:
    installed && plugin.safeUpdate === true

  activeFocusOnTab: true

  function detailsFlickable() {
    return detailsScroll.contentItem
  }

  function scrollTo(position) {
    var flick = detailsFlickable()
    if (!flick || flick.contentY === undefined) return
    var maximum = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maximum, position))
  }

  function scrollBy(delta) {
    var flick = detailsFlickable()
    if (!flick || flick.contentY === undefined) return
    scrollTo(flick.contentY + delta)
  }

  function itemFullyVisible(item) {
    var flick = detailsFlickable()
    if (!item || !item.visible || !flick || flick.contentY === undefined)
      return false
    var target = flick.contentItem || flick
    var point = item.mapToItem(target, 0, 0)
    var viewportTop = flick.contentY
    var viewportBottom = viewportTop + flick.height
    return point.y >= viewportTop - 0.5
      && point.y + item.height <= viewportBottom + 0.5
  }

  function focusScreenshotControlsIfVisible() {
    if (screenshots.length <= 1 || !itemFullyVisible(screenshotsView))
      return false
    screenshotsView.focusControls()
    return true
  }

  function scrollDownAndMaybeFocus(delta) {
    scrollBy(delta)
    Qt.callLater(function() {
      root.focusScreenshotControlsIfVisible()
    })
  }

  function ensureVisible(item) {
    var flick = detailsFlickable()
    if (!item || !flick || flick.contentY === undefined) return
    var target = flick.contentItem || flick
    var point = item.mapToItem(target, 0, 0)
    var margin = Style.space(12)
    var top = point.y
    var bottom = top + item.height
    if (top < flick.contentY + margin) scrollTo(top - margin)
    else if (bottom > flick.contentY + flick.height - margin)
      scrollTo(bottom + margin - flick.height)
  }

  function resetScroll() {
    var flick = detailsScroll.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
    screenshotsView.reset()
  }

  function restoreScreenshot(index) {
    screenshotsView.showInstant(index)
    Qt.callLater(function() {
      root.ensureVisible(screenshotsView)
      screenshotsView.focusControls()
    })
  }

  function focusFirstControl() {
    if (narrowLayout && backButton.visible) {
      backButton.forceActiveFocus()
      return
    }
    root.forceActiveFocus()
  }

  function focusViewport() {
    actionFocusPending = false
    root.forceActiveFocus()
  }

  function actionHasFocus() {
    return installButton.activeFocus
      || removeButton.activeFocus
      || updateButton.activeFocus
  }

  function firstActionButton() {
    var actions = [installButton, removeButton, updateButton]
    for (var i = 0; i < actions.length; i++)
      if (actions[i].visible && actions[i].enabled) return actions[i]
    return null
  }

  function focusFirstAction() {
    var action = firstActionButton()
    if (action !== null) {
      actionFocusPending = false
      action.forceActiveFocus()
      return true
    }
    var hasAction = installButton.visible
      || (removeButton.visible && removalAllowed)
      || updateButton.visible
    actionFocusPending = !actionsEnabled && hasAction
    root.forceActiveFocus()
    return hasAction
  }

  function value(value, fallback) {
    if (arguments.length >= 2) return OkomartModel.metadataValue(value, fallback)
    return OkomartModel.metadataValue(value)
  }

  function versionText() {
    return hasPlugin ? OkomartModel.pluginVersionText(plugin) : ""
  }

  function sourceText() {
    if (!hasPlugin) return ""
    return value(plugin.installedSourceUrl || plugin.sourceUrl,
      plugin.installed === true ? "Installed source" : "Not declared")
  }

  function sourceUrl() {
    return hasPlugin ? OkomartModel.clickableSourceUrl(plugin) : ""
  }

  function openSourceUrl(url) {
    if (url !== "" && url === sourceUrl()) Qt.openUrlExternally(url)
  }

  function updateText() {
    return hasPlugin ? OkomartModel.updateDetailText(plugin) : ""
  }

  onPluginChanged: Qt.callLater(resetScroll)
  onActionsEnabledChanged: if (actionsEnabled && actionFocusPending)
    Qt.callLater(focusFirstAction)
  onActiveFocusChanged: if (!activeFocus) actionFocusPending = false

  Keys.priority: Keys.AfterItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
      pluginListRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
      scrollDownAndMaybeFocus(Style.space(42))
      event.accepted = true
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
      var currentFlick = detailsFlickable()
      if (!currentFlick || currentFlick.contentY <= 0.5) {
        if (actionHasFocus()) searchRequested()
        else if (!focusFirstAction()) searchRequested()
      } else {
        scrollBy(-Style.space(42))
      }
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      scrollDownAndMaybeFocus(detailsScroll.height * 0.8)
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      scrollBy(-detailsScroll.height * 0.8)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      scrollTo(0)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      var flick = detailsFlickable()
      if (flick) {
        scrollTo(flick.contentHeight)
        Qt.callLater(function() {
          root.focusScreenshotControlsIfVisible()
        })
      }
      event.accepted = true
    }
  }

  QQC.ScrollView {
    id: detailsScroll
    anchors.fill: parent
    clip: true
    contentWidth: availableWidth
    contentHeight: detailsColumn.implicitHeight
    QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
    QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded

    Column {
      id: detailsColumn
      width: detailsScroll.availableWidth
      spacing: Style.space(14)

      Row {
        visible: root.hasPlugin
        width: parent.width
        spacing: Style.space(10)

        Button {
          id: backButton
          visible: root.narrowLayout
          focusable: true
          bordered: true
          text: "Back"
          onClicked: root.backRequested()
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() {
            root.ensureVisible(backButton)
          })
          Accessible.name: "Back to plugin list"
          Accessible.role: Accessible.Button
        }

        Text {
          width: Math.max(0, parent.width - (root.narrowLayout ? parent.children[0].width + parent.spacing : 0))
          text: root.hasPlugin ? root.value(root.plugin.name || root.plugin.id, "Unnamed plugin") : ""
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: true
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: root.hasPlugin
        width: parent.width
        text: root.hasPlugin ? root.value(root.plugin.description, "No description provided.") : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Row {
        visible: root.hasPlugin && (root.installed || root.plugin.catalog)
        spacing: Style.space(10)

        Button {
          id: installButton
          visible: root.hasPlugin && !root.installed && root.plugin.catalog
          enabled: root.actionsEnabled
          focusable: true
          bordered: true
          text: "Install"
          onClicked: root.installRequested(root.plugin)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
              root.pluginListRequested()
              event.accepted = true
            }
          }
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() {
            root.ensureVisible(installButton)
          })
          Accessible.name: root.hasPlugin
            ? "Install " + root.value(root.plugin.name || root.plugin.id, "plugin")
            : "Install plugin"
          Accessible.role: Accessible.Button
        }

        Button {
          id: removeButton
          visible: root.hasPlugin && root.installed
          enabled: root.actionsEnabled && root.removalAllowed
          focusable: root.removalAllowed
          bordered: true
          foreground: root.urgent
          accent: root.urgent
          tooltipText: root.removalBlockReason
          text: {
            if (!root.hasPlugin) return "Remove"
            if (root.plugin.installType === "development-link") return "Unlink"
            if (root.plugin.installType === "local")
              return "Remove (backup)"
            return "Uninstall"
          }
          onClicked: root.removeRequested(root.plugin)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
              root.pluginListRequested()
              event.accepted = true
            }
          }
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() {
            root.ensureVisible(removeButton)
          })
          Accessible.name: root.hasPlugin
            ? "Remove " + root.value(root.plugin.name || root.plugin.id, "plugin")
            : "Remove plugin"
          Accessible.description: root.removalBlockReason
          Accessible.role: Accessible.Button
        }

        Button {
          id: updateButton
          visible: root.updateAvailable
          enabled: root.actionsEnabled
          focusable: true
          bordered: true
          selected: true
          text: "Update"
          onClicked: root.updateRequested(root.plugin)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
              root.pluginListRequested()
              event.accepted = true
            }
          }
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() {
            root.ensureVisible(updateButton)
          })
          Accessible.name: root.hasPlugin
            ? "Update " + root.value(root.plugin.name || root.plugin.id, "plugin")
            : "Update plugin"
          Accessible.role: Accessible.Button
        }
      }

      BorderSurface {
        visible: root.hasPlugin
        width: parent.width
        implicitHeight: metadata.implicitHeight + Style.space(24)
        color: Util.alpha(root.foreground, 0.035)
        borderSpec: Border.flat(Util.alpha(root.foreground, 0.16), Math.max(1, Style.normalBorderWidth))
        radius: Style.cornerRadius

        Column {
          id: metadata
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(8)

          Repeater {
            model: root.hasPlugin ? [
              { label: "Author", value: root.value(root.plugin.author) },
              { label: "Version", value: root.versionText() },
              { label: "Source", value: root.sourceText() }
            ] : []

            delegate: Row {
              id: detailRow

              required property var modelData
              readonly property string linkUrl:
                modelData.label === "Source" ? root.sourceUrl() : ""

              width: metadata.width
              spacing: Style.space(10)

              Text {
                width: Style.space(74)
                text: modelData.label
                color: Util.alpha(root.foreground, 0.66)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: detailValue

                width: Math.max(0, parent.width - Style.space(84))
                text: modelData.value
                textFormat: Text.PlainText
                color: detailRow.linkUrl !== "" ? root.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.underline: detailRow.linkUrl !== ""
                  && (activeFocus || sourceMouse.containsMouse)
                wrapMode: Text.WrapAnywhere
                activeFocusOnTab: detailRow.linkUrl !== ""

                Keys.onReturnPressed: root.openSourceUrl(detailRow.linkUrl)
                Keys.onEnterPressed: root.openSourceUrl(detailRow.linkUrl)
                Keys.onSpacePressed: root.openSourceUrl(detailRow.linkUrl)

                MouseArea {
                  id: sourceMouse
                  anchors.left: parent.left
                  anchors.top: parent.top
                  width: Math.min(parent.width, parent.contentWidth)
                  height: parent.height
                  enabled: detailRow.linkUrl !== ""
                  hoverEnabled: enabled
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    detailValue.forceActiveFocus()
                    root.openSourceUrl(detailRow.linkUrl)
                  }
                }

                Accessible.name: detailRow.linkUrl !== ""
                  ? "Open plugin source " + text : text
                Accessible.description: detailRow.linkUrl !== ""
                  ? "Opens in the default browser" : ""
                Accessible.role: detailRow.linkUrl !== ""
                  ? Accessible.Link : Accessible.StaticText
              }
            }
          }
        }
      }

      Text {
        visible: root.hasPlugin && root.updateText() !== ""
        width: parent.width
        text: root.updateText()
        textFormat: Text.PlainText
        color: {
          var normalized = root.normalizedUpdateState
          return normalized === "dirty" || normalized === "diverged"
            || normalized === "offline" || normalized === "unknown"
            ? root.urgent : root.accent
        }
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        visible: root.hasPlugin && root.plugin.validationError
        width: parent.width
        text: root.hasPlugin ? String(root.plugin.validationError || "") : ""
        textFormat: Text.PlainText
        color: root.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Column {
        visible: root.screenshots.length > 0
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.screenshots.length > 1 ? "Screenshots" : "Screenshot"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        ScreenshotCarousel {
          id: screenshotsView
          width: parent.width
          images: root.screenshots
          // Registry entries can advance independently of the catalog
          // repository, so bust the image cache with the plugin commit.
          revision: root.hasPlugin
            ? String(root.plugin.catalogCommit || root.catalogRevision)
            : root.catalogRevision
          foreground: root.foreground
          accent: root.accent
          onImageActivated: function(index) { root.screenshotRequested(index) }
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() {
            root.ensureVisible(screenshotsView)
          })
        }
      }

      Item { width: 1; height: Style.space(2) }
    }

    Text {
      visible: !root.hasPlugin
      width: Math.max(0, detailsScroll.availableWidth - Style.space(20))
      anchors.centerIn: parent
      text: "Select a plugin to see its details."
      color: Util.alpha(root.foreground, 0.68)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  Accessible.name: root.hasPlugin
    ? "Details for " + root.value(root.plugin.name || root.plugin.id, "plugin")
    : "Plugin details"
  Accessible.role: Accessible.Pane
}
