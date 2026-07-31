import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property bool opened: false
  property string mode: ""
  property var plugin: null
  property var updates: []
  property bool busy: false
  property string errorText: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color urgent: Color.urgent

  signal canceled()
  signal confirmed()

  visible: opened
  focus: opened
  z: 1000

  readonly property bool destructive: mode === "remove"
  readonly property bool confirmsUpdate:
    mode === "update" || mode === "updates"
  readonly property string title: {
    if (mode === "install") return "Install and enable plugin?"
    if (mode === "remove") return "Remove plugin?"
    if (mode === "update") return "Update plugin?"
    if (mode === "updates") return "Apply plugin updates?"
    if (mode === "results") return "Plugin operation results"
    return "Confirm action"
  }
  readonly property string confirmLabel: {
    if (mode === "install") return "Install & Enable"
    if (mode === "remove") return "Remove"
    if (mode === "update") return "Update"
    if (mode === "updates") return "Update all"
    if (mode === "results") return "Close"
    return "Confirm"
  }
  readonly property var safeUpdates: {
    var out = []
    if (!Array.isArray(updates)) return out
    for (var i = 0; i < updates.length; i++)
      if (updates[i] && updates[i].safeUpdate === true) out.push(updates[i])
    return out
  }
  readonly property var blockedUpdates: {
    var out = []
    if (!Array.isArray(updates)) return out
    for (var i = 0; i < updates.length; i++)
      if (updates[i] && updates[i].safeUpdate !== true) out.push(updates[i])
    return out
  }
  readonly property bool canConfirm: !busy
    && (mode !== "updates" || safeUpdates.length > 0)
    && (mode !== "update" || (plugin && plugin.safeUpdate === true
      && plugin.versionUpdateAvailable === true))
  readonly property bool hasReviewList: mode === "updates" || mode === "results"

  function pluginName(item) {
    return item ? String(item.name || item.id || "plugin") : "plugin"
  }

  function shortCommit(value) {
    var commit = String(value || "")
    return commit ? commit.slice(0, 10) : ""
  }

  function installedReference(item) {
    return String(item && (item.installedVersion || item.currentVersion)
      || shortCommit(item && item.currentCommit) || "current")
  }

  function availableReference(item) {
    return String(item && (item.availableVersion || item.remoteVersion)
      || shortCommit(item && item.availableCommit) || "latest")
  }

  function updateTransition(item) {
    var installedVersion = String(item
      && (item.installedVersion || item.currentVersion) || "")
    var availableVersion = String(item
      && (item.availableVersion || item.remoteVersion) || "")
    var currentCommit = shortCommit(item && item.currentCommit)
    var availableCommit = shortCommit(item && item.availableCommit)
    if (installedVersion && availableVersion && installedVersion !== availableVersion)
      return installedVersion + " → " + availableVersion
    if (currentCommit && availableCommit && currentCommit !== availableCommit)
      return (installedVersion ? installedVersion + " · " : "") + currentCommit
        + " → " + (availableVersion ? availableVersion + " · " : "") + availableCommit
    return installedReference(item) + " → " + availableReference(item)
  }

  function reviewFlickable() {
    return reviewScroll.contentItem
  }

  function scrollReviewTo(position) {
    var flick = reviewFlickable()
    if (!flick || flick.contentY === undefined) return
    var maximum = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maximum, position))
  }

  function scrollReviewBy(delta) {
    var flick = reviewFlickable()
    if (!flick || flick.contentY === undefined) return
    scrollReviewTo(flick.contentY + delta)
  }

  function focusTargets() {
    var out = []
    if (reviewScroll.visible && reviewScroll.enabled) out.push(reviewScroll)
    if (cancelButton.visible && cancelButton.enabled) out.push(cancelButton)
    if (confirmButton.visible && confirmButton.enabled) out.push(confirmButton)
    return out
  }

  function cycleFocus(backward) {
    var targets = focusTargets()
    if (targets.length === 0) {
      root.forceActiveFocus()
      return
    }
    var current = -1
    for (var i = 0; i < targets.length; i++)
      if (targets[i].activeFocus) current = i
    var next = backward
      ? (current <= 0 ? targets.length - 1 : current - 1)
      : (current < 0 || current >= targets.length - 1 ? 0 : current + 1)
    targets[next].forceActiveFocus()
  }

  function detailMessage() {
    if (mode === "install") {
      return "Okomart will clone, validate, and enable " + pluginName(plugin)
        + ". Omarchy plugins run unsandboxed inside the shell. Review the source before continuing.\n\n"
        + String(plugin && (plugin.sourceUrl || plugin.originUrl) || "")
    }
    if (mode === "remove") {
      var kind = plugin ? String(plugin.installType || "") : ""
      if (kind === "development-link" || kind === "symlink")
        return pluginName(plugin) + " is a development link. Okomart will unlink it without deleting its target."
      if (kind === "local" || kind === "non-git")
        return pluginName(plugin) + " is a local folder. Omarchy will disable it and move it to a timestamped backup."
      return "Omarchy will disable and delete the installed checkout for " + pluginName(plugin) + "."
    }
    if (mode === "update") {
      return "Okomart will update only " + pluginName(plugin) + ".\n\n"
        + updateTransition(plugin)
    }
    return ""
  }

  function openFor(nextMode, nextPlugin, nextUpdates) {
    mode = nextMode
    plugin = nextPlugin || null
    updates = nextUpdates || []
    errorText = ""
    opened = true
    Qt.callLater(function() {
      if (root.mode === "results") reviewScroll.forceActiveFocus()
      else cancelButton.forceActiveFocus()
    })
  }

  function closeDialog() {
    opened = false
    mode = ""
    plugin = null
    updates = []
    errorText = ""
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (!opened) return
    if (event.key === Qt.Key_Escape) {
      root.canceled()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.cycleFocus(event.key === Qt.Key_Backtab
        || (event.modifiers & Qt.ShiftModifier))
      event.accepted = true
    } else if (root.hasReviewList && event.key === Qt.Key_PageDown) {
      root.scrollReviewBy(reviewScroll.height * 0.8)
      event.accepted = true
    } else if (root.hasReviewList && event.key === Qt.Key_PageUp) {
      root.scrollReviewBy(-reviewScroll.height * 0.8)
      event.accepted = true
    } else if (root.hasReviewList && event.key === Qt.Key_Home) {
      root.scrollReviewTo(0)
      event.accepted = true
    } else if (root.hasReviewList && event.key === Qt.Key_End) {
      var flick = root.reviewFlickable()
      if (flick) root.scrollReviewTo(flick.contentHeight)
      event.accepted = true
    } else if (reviewScroll.activeFocus
        && (event.key === Qt.Key_Down || event.key === Qt.Key_J)) {
      root.scrollReviewBy(Style.space(42))
      event.accepted = true
    } else if (reviewScroll.activeFocus
        && (event.key === Qt.Key_Up || event.key === Qt.Key_K)) {
      root.scrollReviewBy(-Style.space(42))
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.background, 0.78)

    MouseArea {
      anchors.fill: parent
      enabled: !root.busy
      onClicked: root.canceled()
    }
  }

  BorderSurface {
    id: card
    width: Math.min(parent.width - Style.space(32), Style.space(560))
    height: Math.min(parent.height - Style.space(32),
      root.hasReviewList ? Style.space(520)
        : (root.errorText ? Style.space(390) : Style.space(340)))
    anchors.centerIn: parent
    color: root.background
    borderSpec: root.confirmsUpdate
      ? Border.none()
      : Border.flat(root.destructive ? root.urgent : root.accent,
          Math.max(1, Style.normalBorderWidth))
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: dialogContent
      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(14)

      // Keep the review pane flexible at the window's minimum height. The
      // action-start error is added after the dialog opens, so a fixed review
      // height can otherwise push the buttons beyond the card.
      readonly property int visibleItemCount: 3
        + (detailText.visible ? 1 : 0)
        + (errorMessage.visible ? 1 : 0)
        + (reviewScroll.visible ? 1 : 0)
      readonly property real contentSpacingHeight:
        Math.max(0, visibleItemCount - 1) * spacing
      readonly property real reviewHeightBudget: Math.max(0,
        height
          - titleText.height
          - detailText.height
          - errorMessage.height
          - buttons.height
          - contentSpacingHeight)

      Text {
        id: titleText
        width: parent.width
        text: root.title
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        id: detailText
        visible: root.mode === "install" || root.mode === "remove"
          || root.mode === "update"
        height: visible ? implicitHeight : 0
        width: parent.width
        text: root.detailMessage()
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WrapAnywhere
      }

      Text {
        id: errorMessage
        visible: root.errorText !== ""
        height: visible ? implicitHeight : 0
        width: parent.width
        text: root.errorText
        textFormat: Text.PlainText
        color: root.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      QQC.ScrollView {
        id: reviewScroll
        visible: root.hasReviewList
        activeFocusOnTab: visible
        width: parent.width
        height: visible
          ? Math.min(Style.space(330),
            Math.max(Style.space(110), reviewColumn.implicitHeight),
            dialogContent.reviewHeightBudget)
          : 0
        clip: true
        contentWidth: availableWidth
        QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
        QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
        Accessible.name: root.mode === "results"
          ? "Failed plugin operation details"
          : "Packages included in this update"
        Accessible.role: Accessible.List

        background: Rectangle {
          color: "transparent"
          border.color: reviewScroll.activeFocus
            ? root.accent : Util.alpha(root.foreground, 0.16)
          border.width: reviewScroll.activeFocus
            ? Math.max(1, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)
          radius: Style.cornerRadius
        }

        Column {
          id: reviewColumn
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: root.mode === "updates"
            height: visible ? implicitHeight : 0
            width: parent.width
            text: root.safeUpdates.length === 1
              ? "The following package will be updated:"
              : "The following " + root.safeUpdates.length + " packages will be updated:"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.mode === "updates" ? root.safeUpdates : []

            delegate: Column {
              required property var modelData
              width: reviewColumn.width
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.pluginName(modelData)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.updateTransition(modelData)
                textFormat: Text.PlainText
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: root.mode === "updates" && root.blockedUpdates.length > 0
            height: visible ? implicitHeight : 0
            width: parent.width
            text: "Not updateable automatically"
            color: root.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: root.mode === "updates" ? root.blockedUpdates : []

            delegate: Text {
              required property var modelData
              width: reviewColumn.width
              text: root.pluginName(modelData) + " — "
                + String(modelData.statusText || modelData.updateState || "blocked")
              textFormat: Text.PlainText
              color: root.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Repeater {
            model: root.mode === "results" ? root.updates : []

            delegate: BorderSurface {
              required property var modelData
              width: reviewColumn.width
              implicitHeight: resultRow.implicitHeight + Style.space(16)
              color: Util.alpha(root.urgent, 0.07)
              borderSpec: Border.flat(Util.alpha(root.urgent, 0.48), Math.max(1, Style.normalBorderWidth))
              radius: Style.cornerRadius

              Column {
                id: resultRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(5)

                Text {
                  width: parent.width
                  text: root.pluginName(modelData) + " · "
                    + String(modelData.operation || "operation") + " failed"
                  textFormat: Text.PlainText
                  color: root.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  text: String(modelData.output || "No command output was captured.").trim()
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                }
              }
            }
          }
        }
      }

      Item {
        width: 1
        height: Math.max(0, parent.height
          - titleText.height
          - detailText.height
          - errorMessage.height
          - reviewScroll.height
          - buttons.height
          - parent.contentSpacingHeight)
      }

      Row {
        id: buttons
        anchors.right: parent.right
        spacing: Style.space(10)

        Button {
          id: cancelButton
          visible: root.mode !== "results"
          focusable: true
          bordered: true
          enabled: !root.busy
          text: "Cancel"
          onClicked: root.canceled()
          Accessible.name: "Cancel " + root.title.toLowerCase()
          Accessible.role: Accessible.Button
        }

        Button {
          id: confirmButton
          focusable: true
          bordered: true
          enabled: root.canConfirm
          foreground: root.destructive ? root.urgent : root.foreground
          accent: root.destructive ? root.urgent : root.accent
          text: root.busy ? "Working…" : root.confirmLabel
          onClicked: root.confirmed()
          Accessible.name: root.confirmLabel
          Accessible.role: Accessible.Button
        }
      }
    }
  }

  Accessible.name: root.title
  Accessible.role: Accessible.Dialog
}
