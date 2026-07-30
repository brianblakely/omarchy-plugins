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

  Keys.onPressed: function(event) {
    if (imageCount <= 1) return
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
      select(currentIndex - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
      select(currentIndex + 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      currentIndex = 0
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      currentIndex = imageCount - 1
      event.accepted = true
    }
  }

  Item {
    id: carouselContent
    anchors.fill: parent

    Image {
      id: preview
      anchors.fill: parent
      source: root.versionedSource(root.currentPath)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: false
      smooth: true
      sourceSize.width: Math.max(1, Math.round(width * Screen.devicePixelRatio))
      sourceSize.height: Math.max(1, Math.round(height * Screen.devicePixelRatio))
    }

    Row {
      id: paginationControls
      visible: root.imageCount > 1
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      spacing: Style.space(6)

      Button {
        id: previousButton
        width: Style.space(24)
        height: Style.space(24)
        focusable: true
        bordered: true
        horizontalPadding: 0
        verticalPadding: 0
        text: "‹"
        fontSize: Style.font.title
        onClicked: root.select(root.currentIndex - 1)
        Accessible.name: "Previous plugin screenshot"
        Accessible.role: Accessible.Button
      }

      Row {
        id: pageDots
        height: Style.space(24)
        spacing: Style.space(3)

        Repeater {
          model: root.imageCount

          delegate: Item {
            required property int index
            width: Style.space(12)
            height: Style.space(24)

            Rectangle {
              anchors.centerIn: parent
              width: index === root.currentIndex ? Style.space(8) : Style.space(6)
              height: width
              radius: width / 2
              color: index === root.currentIndex
                ? root.accent : Util.alpha(root.foreground, 0.52)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.select(index)
            }

            Accessible.name: "Show plugin screenshot " + (index + 1)
            Accessible.role: Accessible.RadioButton
          }
        }
      }

      Button {
        id: nextButton
        width: Style.space(24)
        height: Style.space(24)
        focusable: true
        bordered: true
        horizontalPadding: 0
        verticalPadding: 0
        text: "›"
        fontSize: Style.font.title
        onClicked: root.select(root.currentIndex + 1)
        Accessible.name: "Next plugin screenshot"
        Accessible.role: Accessible.Button
      }
    }
  }

  Accessible.name: imageCount > 1
    ? "Plugin screenshot " + (currentIndex + 1) + " of " + imageCount
    : "Plugin screenshot"
  Accessible.role: Accessible.Pane
}
