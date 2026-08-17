import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property bool opened: false
  property var images: []
  property string revision: ""
  property string pluginName: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent

  signal dismissed(int index)

  readonly property int imageCount: Array.isArray(images) ? images.length : 0
  readonly property string currentPath: imageCount > 0
      && carousel.currentIndex >= 0 && carousel.currentIndex < imageCount
    ? String(images[carousel.currentIndex] || "") : ""

  visible: opened
  focus: opened
  z: 900

  function openFor(nextImages, nextRevision, index, nextPluginName) {
    if (!Array.isArray(nextImages) || nextImages.length < 1) return
    images = nextImages.slice()
    revision = String(nextRevision || "")
    pluginName = String(nextPluginName || "Plugin")
    carousel.showInstant(index)
    opened = true
    Qt.callLater(function() {
      if (root.opened) carousel.focusControls()
    })
  }

  function clear() {
    opened = false
    images = []
    revision = ""
    pluginName = ""
  }

  function closeLightbox() {
    if (!opened) return
    var index = carousel.currentIndex
    opened = false
    dismissed(index)
    images = []
    revision = ""
    pluginName = ""
  }

  function openOriginal() {
    if (currentPath === "") return
    var target = currentPath.indexOf("https://") === 0
      || currentPath.indexOf("http://") === 0
      ? currentPath : Util.fileUrl(currentPath)
    Qt.openUrlExternally(target)
  }

  function omitFailedImage(index) {
    if (index < 0 || index >= images.length) return
    var remaining = images.slice()
    remaining.splice(index, 1)
    if (remaining.length < 1) {
      closeLightbox()
      return
    }
    images = remaining
  }

  function focusTargets() {
    return [carousel, openOriginalButton, closeButton]
  }

  function cycleFocus(backward) {
    var targets = focusTargets()
    var current = -1
    for (var i = 0; i < targets.length; i++)
      if (targets[i].activeFocus) current = i
    var next = backward
      ? (current <= 0 ? targets.length - 1 : current - 1)
      : (current < 0 || current >= targets.length - 1 ? 0 : current + 1)
    targets[next].forceActiveFocus()
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (!opened) return
    if (event.key === Qt.Key_Escape) {
      root.closeLightbox()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.cycleFocus(event.key === Qt.Key_Backtab
        || (event.modifiers & Qt.ShiftModifier))
      event.accepted = true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
      carousel.select(carousel.currentIndex - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
      carousel.select(carousel.currentIndex + 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      carousel.select(0)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      carousel.select(root.imageCount - 1)
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.background, 0.86)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeLightbox()
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    anchors.margins: Style.space(16)
    color: root.background
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.space(16)
      anchors.leftMargin: Style.space(18)
      anchors.rightMargin: Style.space(18)
      height: Math.max(titleText.implicitHeight, headerActions.implicitHeight)

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: headerActions.left
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        text: root.pluginName
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Button {
          id: openOriginalButton
          focusable: true
          bordered: true
          enabled: root.currentPath !== ""
          text: "Open Original"
          tooltipText: "Open this screenshot in the default image viewer"
          onClicked: root.openOriginal()
          Accessible.name: "Open current screenshot in the default image viewer"
          Accessible.role: Accessible.Button
        }

        Button {
          id: closeButton
          focusable: true
          bordered: true
          text: "Close"
          onClicked: root.closeLightbox()
          Accessible.name: "Close screenshot viewer"
          Accessible.role: Accessible.Button
        }
      }
    }

    ScreenshotCarousel {
      id: carousel
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.topMargin: Style.space(14)
      anchors.leftMargin: Style.space(18)
      anchors.rightMargin: Style.space(18)
      anchors.bottomMargin: Style.space(18)
      images: root.images
      revision: root.revision
      foreground: root.foreground
      accent: root.accent
      imageInteractive: false
      imageNavigationInteractive: true
      imageHeightOverride: Math.max(1, height - paginationGap - paginationHeight)
      onImageFailed: function(index) { root.omitFailedImage(index) }
    }
  }

  Accessible.name: root.pluginName + " screenshot viewer"
  Accessible.role: Accessible.Pane
}
