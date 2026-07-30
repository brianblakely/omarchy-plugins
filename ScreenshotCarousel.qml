import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property var images: []
  property string revision: ""
  property int currentIndex: 0
  property int pendingIndex: -1
  property color foreground: Color.foreground
  property color accent: Color.accent

  readonly property int imageCount: Array.isArray(images) ? images.length : 0

  visible: imageCount > 0
  implicitHeight: visible ? Math.max(Style.space(230), width * 0.56) : 0
  activeFocusOnTab: imageCount > 1

  function select(index) {
    if (imageCount < 1) return
    var targetIndex = (index + imageCount) % imageCount
    var targetImage = imageRepeater.itemAt(targetIndex)
    if (!targetImage || targetImage.status !== Image.Ready) {
      pendingIndex = targetIndex
      return
    }
    pendingIndex = -1
    currentIndex = targetIndex
  }

  function imageBecameReady(index) {
    if (pendingIndex !== index) return
    pendingIndex = -1
    currentIndex = index
  }

  function focusControls() {
    if (imageCount > 1) previousButton.forceActiveFocus()
    else root.forceActiveFocus()
  }

  function versionedSource(path) {
    if (!path) return ""
    var base = Util.fileUrl(path)
    return revision ? base + "?revision=" + encodeURIComponent(revision) : base
  }

  onImagesChanged: {
    pendingIndex = -1
    currentIndex = 0
  }

  Keys.onPressed: function(event) {
    if (imageCount <= 1) return
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
      select(currentIndex - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
      select(currentIndex + 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      select(0)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      select(imageCount - 1)
      event.accepted = true
    }
  }

  Item {
    id: carouselContent
    anchors.fill: parent

    Repeater {
      id: imageRepeater
      model: root.imageCount

      delegate: Image {
        required property int index
        anchors.fill: parent
        visible: index === root.currentIndex
        source: root.versionedSource(String(root.images[index] || ""))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        sourceSize.width: Math.max(1, Math.round(width * Screen.devicePixelRatio))
        sourceSize.height: Math.max(1, Math.round(height * Screen.devicePixelRatio))
        onStatusChanged: if (status === Image.Ready)
          root.imageBecameReady(index)
      }
    }

    Row {
      id: paginationControls
      z: 1
      visible: root.imageCount > 1
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      spacing: Style.space(6)

      Rectangle {
        width: Style.space(24)
        height: Style.space(24)
        radius: Style.cornerRadius
        color: Color.background

        Button {
          id: previousButton
          anchors.fill: parent
          focusable: true
          bordered: true
          background: "transparent"
          foreground: root.foreground
          horizontalPadding: 0
          verticalPadding: 0
          text: "‹"
          fontSize: Style.font.title
          onClicked: root.select(root.currentIndex - 1)
          Accessible.name: "Previous plugin screenshot"
          Accessible.role: Accessible.Button
        }
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

      Rectangle {
        width: Style.space(24)
        height: Style.space(24)
        radius: Style.cornerRadius
        color: Color.background

        Button {
          id: nextButton
          anchors.fill: parent
          focusable: true
          bordered: true
          background: "transparent"
          foreground: root.foreground
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
  }

  Accessible.name: imageCount > 1
    ? "Plugin screenshot " + (currentIndex + 1) + " of " + imageCount
    : "Plugin screenshot"
  Accessible.role: Accessible.Pane
}
