import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real frameInset: Style.space(22)
  property real roofTop: Style.space(16)
  property real bodyTop: Style.space(184)
  property real splitX: width * 0.4
  property bool wideLayout: true
  property bool awningVisible: true
  property color strokeColor: Color.accent
  property real strokeWidth: Math.max(1, Style.spaceReal(2))

  readonly property real frameLeft: frameInset
  readonly property real frameRight: width - frameInset
  readonly property real frameBottom: height - frameInset
  readonly property real eaveY: bodyTop - Style.space(42)
  readonly property real awningY: bodyTop + Style.space(18)
  readonly property real awningRight: wideLayout ? splitX : frameRight

  function roofPath() {
    var shoulder = Style.space(48)
    var apexX = width / 2
    var trimY = eaveY + Style.space(7)
    return "M " + frameLeft + " " + eaveY
      + " L " + apexX + " " + roofTop
      + " L " + frameRight + " " + eaveY
      + " M " + frameLeft + " " + eaveY
      + " L " + frameLeft + " " + trimY
      + " L " + (frameLeft + shoulder) + " " + trimY
      + " L " + (frameLeft + shoulder) + " " + bodyTop
      + " M " + frameRight + " " + eaveY
      + " L " + frameRight + " " + trimY
      + " L " + (frameRight - shoulder) + " " + trimY
      + " L " + (frameRight - shoulder) + " " + bodyTop
  }

  function facadePath() {
    var path = "M " + frameLeft + " " + bodyTop
      + " L " + frameRight + " " + bodyTop
      + " L " + frameRight + " " + frameBottom
      + " L " + frameLeft + " " + frameBottom
      + " Z"
    if (wideLayout)
      path += " M " + splitX + " " + bodyTop + " L " + splitX + " " + frameBottom
    return path
  }

  function awningPath() {
    if (!awningVisible || awningRight <= frameLeft) return ""
    var span = awningRight - frameLeft
    var targetWidth = Math.max(Style.space(38), span / 10)
    var count = Math.max(3, Math.round(span / targetWidth))
    var step = span / count
    var depth = Style.space(14)
    var path = "M " + frameLeft + " " + bodyTop + " L " + frameLeft + " " + awningY
    for (var i = 0; i < count; i++) {
      var start = frameLeft + i * step
      var middle = start + step / 2
      var end = start + step
      path += " Q " + middle + " " + (awningY + depth) + " " + end + " " + awningY
    }
    path += " L " + awningRight + " " + frameBottom
    return path
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.roofPath() }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.facadePath() }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.awningPath() }
    }
  }
}
