import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property var images: []
  property string revision: ""
  property int currentIndex: 0
  property color foreground: Color.foreground
  property color accent: Color.accent

  readonly property int imageCount: Array.isArray(images) ? images.length : 0
  readonly property string currentPath: imageCount > 0
    ? String(images[Math.max(0, Math.min(currentIndex, imageCount - 1))] || "")
    : ""

  visible: imageCount > 0
  implicitHeight: visible ? Math.max(Style.space(230), width * 0.56) : 0
  activeFocusOnTab: imageCount > 1

  function select(index) {
    if (imageCount < 1) return
    currentIndex = (index + imageCount) % imageCount
  }

  function versionedSource(path) {
    if (!path) return ""
    var base = Util.fileUrl(path)
    return revision ? base + "?revision=" + encodeURIComponent(revision) : base
  }

  onImagesChanged: currentIndex = 0

  Keys.onLeftPressed: function(event) {
    if (imageCount > 1) select(currentIndex - 1)
    event.accepted = imageCount > 1
  }
  Keys.onRightPressed: function(event) {
    if (imageCount > 1) select(currentIndex + 1)
    event.accepted = imageCount > 1
  }
  Keys.onHomePressed: function(event) {
    if (imageCount > 1) currentIndex = 0
    event.accepted = imageCount > 1
  }
  Keys.onEndPressed: function(event) {
    if (imageCount > 1) currentIndex = imageCount - 1
    event.accepted = imageCount > 1
  }

  BorderSurface {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.38)
    borderSpec: Border.flat(Util.alpha(root.activeFocus ? root.accent : root.foreground, root.activeFocus ? 0.9 : 0.24), Math.max(1, Style.normalBorderWidth))
    radius: Style.cornerRadius

    Image {
      id: preview
      anchors.fill: parent
      anchors.margins: Style.space(10)
      source: root.versionedSource(root.currentPath)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      smooth: true
      sourceSize.width: Math.max(1, Math.round(width * Screen.devicePixelRatio))
      sourceSize.height: Math.max(1, Math.round(height * Screen.devicePixelRatio))
    }

    Button {
      id: previousButton
      visible: root.imageCount > 1
      focusable: true
      bordered: true
      text: "‹"
      fontSize: Style.font.display
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      onClicked: root.select(root.currentIndex - 1)
      Accessible.name: "Previous plugin screenshot"
      Accessible.role: Accessible.Button
    }

    Button {
      id: nextButton
      visible: root.imageCount > 1
      focusable: true
      bordered: true
      text: "›"
      fontSize: Style.font.display
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      onClicked: root.select(root.currentIndex + 1)
      Accessible.name: "Next plugin screenshot"
      Accessible.role: Accessible.Button
    }

    BorderSurface {
      visible: root.imageCount > 1
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(10)
      width: counter.implicitWidth + Style.space(14)
      height: counter.implicitHeight + Style.space(6)
      color: Util.alpha(Color.background, 0.82)
      borderSpec: Border.flat(Util.alpha(root.foreground, 0.25), Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius

      Text {
        id: counter
        anchors.centerIn: parent
        text: (root.currentIndex + 1) + " / " + root.imageCount
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Accessible.name: imageCount > 1
    ? "Plugin screenshot " + (currentIndex + 1) + " of " + imageCount
    : "Plugin screenshot"
  Accessible.role: Accessible.Pane
}
