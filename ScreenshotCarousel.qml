import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

FocusScope {
  id: root

  property var images: []
  property string revision: ""
  property int currentIndex: 0
  property int displayedIndex: 0
  property int incomingIndex: -1
  property int pendingIndex: -1
  property bool maskReady: false
  property real revealProgress: 1
  property bool transitionReady: false
  property bool imageInteractive: true
  property bool imageNavigationInteractive: false
  property real imageHeightOverride: -1
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal imageActivated(int index)
  signal imageFailed(int index)

  readonly property int imageCount: Array.isArray(images) ? images.length : 0
  readonly property int loadCenterIndex: pendingIndex >= 0 ? pendingIndex : currentIndex
  readonly property var loadedIndices: {
    if (imageCount < 1) return []
    var center = ((loadCenterIndex % imageCount) + imageCount) % imageCount
    if (imageCount === 1) return [center]
    if (imageCount === 2) return [center, (center + 1) % imageCount]
    return [
      (center - 1 + imageCount) % imageCount,
      center,
      (center + 1) % imageCount
    ]
  }
  readonly property real imageHeight: imageHeightOverride >= 0
    ? imageHeightOverride : Math.max(Style.space(230), width * 0.56)
  readonly property real paginationHeight: imageCount > 1 ? Style.space(20) : 0
  readonly property real paginationGap: imageCount > 1 ? Style.space(8) : 0

  visible: imageCount > 0
  implicitHeight: visible ? imageHeight + paginationGap + paginationHeight : 0
  activeFocusOnTab: imageCount > 1

  function select(index) {
    if (imageCount < 1) return
    var targetIndex = (index + imageCount) % imageCount
    if (targetIndex === currentIndex) {
      pendingIndex = -1
      return
    }
    pendingIndex = targetIndex
    var targetImage = imageForIndex(targetIndex)
    if (!targetImage || targetImage.status !== Image.Ready) {
      return
    }
    transitionTo(targetIndex)
  }

  function imageForIndex(index) {
    for (var slot = 0; slot < imageRepeater.count; slot++) {
      var candidate = imageRepeater.itemAt(slot)
      if (candidate && candidate.imageIndex === index) return candidate
    }
    return null
  }

  function imageBecameReady(index) {
    if (pendingIndex !== index) return
    transitionTo(index)
  }

  function transitionTo(index) {
    revealAnimation.stop()

    if (index === displayedIndex) {
      currentIndex = index
      pendingIndex = -1
      incomingIndex = -1
      maskReady = false
      revealProgress = 1
      return
    }

    maskReady = false
    revealProgress = 0
    incomingIndex = index
    currentIndex = index
    pendingIndex = -1
    maybeStartReveal()
  }

  function maybeStartReveal() {
    if (incomingIndex < 0 || revealProgress !== 0 || maskReady) return
    var incomingImage = imageForIndex(incomingIndex)
    if (!incomingImage || incomingImage.status !== Image.Ready) return
    Qt.callLater(function() {
      if (root.incomingIndex < 0 || root.revealProgress !== 0 || root.maskReady) return
      var readyImage = root.imageForIndex(root.incomingIndex)
      if (!readyImage || readyImage.status !== Image.Ready) return
      root.maskReady = true
      revealAnimation.restart()
    })
  }

  function showInstant(index) {
    if (transitionReady) revealAnimation.stop()
    var requestedIndex = Math.round(Number(index))
    if (!isFinite(requestedIndex)) requestedIndex = 0
    var targetIndex = imageCount > 0
      ? ((requestedIndex % imageCount) + imageCount) % imageCount : 0
    pendingIndex = -1
    incomingIndex = -1
    currentIndex = targetIndex
    displayedIndex = targetIndex
    maskReady = false
    revealProgress = 1
  }

  function reset() {
    showInstant(0)
  }

  function focusControls() {
    root.forceActiveFocus()
  }

  function versionedSource(path) {
    if (!path) return ""
    var value = String(path)
    var base = value.indexOf("https://") === 0 || value.indexOf("http://") === 0
      ? value : Util.fileUrl(value)
    return revision ? base + "?revision=" + encodeURIComponent(revision) : base
  }

  onImagesChanged: reset()

  Component.onCompleted: transitionReady = true

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

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingIndex >= 0) {
        root.displayedIndex = root.incomingIndex
        root.currentIndex = root.incomingIndex
        root.incomingIndex = -1
      }
      root.maskReady = false
      root.revealProgress = 1
    }
  }

  Item {
    id: carouselContent
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.imageHeight

    Repeater {
      id: imageRepeater
      model: root.loadedIndices

      delegate: Image {
        required property var modelData
        readonly property int imageIndex: Number(modelData)
        anchors.fill: parent
        visible: imageIndex === root.displayedIndex
          || (imageIndex === root.incomingIndex
            && status === Image.Ready
            && (root.revealProgress >= 1 || root.maskReady))
        z: imageIndex === root.incomingIndex ? 1 : 0
        source: root.versionedSource(String(root.images[imageIndex] || ""))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        sourceSize.width: Math.max(1, Math.round(width * Screen.devicePixelRatio))
        sourceSize.height: Math.max(1, Math.round(height * Screen.devicePixelRatio))
        layer.enabled: imageIndex === root.incomingIndex && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }
        onStatusChanged: {
          if (status === Image.Ready) {
            root.imageBecameReady(imageIndex)
            root.maybeStartReveal()
          } else if (status === Image.Error) {
            root.imageFailed(imageIndex)
          }
        }
      }
    }

    Item {
      id: revealMask
      anchors.fill: parent
      visible: false
      layer.enabled: true

      readonly property real slant: -0.18
      readonly property real centerTop: width / 2 - slant * height / 2
      readonly property real centerBottom: width / 2 + slant * height / 2
      readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
      readonly property real spread: reach * root.revealProgress

      Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "white"
          strokeColor: "transparent"
          startX: revealMask.centerTop - revealMask.spread; startY: 0
          PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
          PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
          PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
          PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.imageInteractive && root.imageCount > 0
      acceptedButtons: Qt.LeftButton
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.imageActivated(root.currentIndex)

      Accessible.name: "View screenshot " + (root.currentIndex + 1) + " larger"
      Accessible.role: Accessible.Button
      Accessible.ignored: !enabled
      Accessible.onPressAction: root.imageActivated(root.currentIndex)
    }

    MouseArea {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: parent.width / 2
      enabled: root.imageNavigationInteractive && root.imageCount > 1
      acceptedButtons: Qt.LeftButton
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.select(root.currentIndex - 1)

      Accessible.name: "Show previous screenshot"
      Accessible.role: Accessible.Button
      Accessible.ignored: !enabled
      Accessible.onPressAction: root.select(root.currentIndex - 1)
    }

    MouseArea {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: parent.width / 2
      enabled: root.imageNavigationInteractive && root.imageCount > 1
      acceptedButtons: Qt.LeftButton
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.select(root.currentIndex + 1)

      Accessible.name: "Show next screenshot"
      Accessible.role: Accessible.Button
      Accessible.ignored: !enabled
      Accessible.onPressAction: root.select(root.currentIndex + 1)
    }
  }

  Row {
    visible: root.imageCount > 1
    anchors.top: carouselContent.bottom
    anchors.topMargin: root.paginationGap
    anchors.horizontalCenter: parent.horizontalCenter
    height: root.paginationHeight
    spacing: Style.space(5)

    Repeater {
      model: root.imageCount

      delegate: Item {
        required property int index
        width: Style.space(18)
        height: root.paginationHeight

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(10)
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
        Accessible.checked: index === root.currentIndex
        Accessible.onPressAction: root.select(index)
      }
    }
  }

  Accessible.name: imageCount > 1
    ? "Plugin screenshot " + (currentIndex + 1) + " of " + imageCount
    : "Plugin screenshot"
  Accessible.role: Accessible.Pane
}
