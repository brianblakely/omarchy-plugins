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

  readonly property real left: frameInset
  readonly property real right: width - frameInset
  readonly property real bottom: height - frameInset
  readonly property real eaveY: bodyTop - Style.space(42)
  readonly property real supportDepth: Style.space(38)
  readonly property real awningY: bodyTop + Style.space(18)
  readonly property real awningRight: wideLayout ? splitX : right

  function roofPath() {
    var shoulder = Style.space(48)
    var apexX = width / 2
    return "M " + left + " " + eaveY
      + " L " + apexX + " " + roofTop
      + " L " + right + " " + eaveY
      + " L " + right + " " + (eaveY + Style.space(7))
      + " L " + (right - shoulder) + " " + (eaveY + Style.space(7))
      + " L " + (right - shoulder) + " " + bodyTop
      + " M " + (left + shoulder) + " " + bodyTop
      + " L " + (left + shoulder) + " " + (eaveY + Style.space(7))
      + " L " + left + " " + (eaveY + Style.space(7))
      + " Z"
  }

  function facadePath() {
    var path = "M " + left + " " + bodyTop
      + " L " + right + " " + bodyTop
      + " L " + right + " " + bottom
      + " L " + left + " " + bottom
      + " Z"
    if (wideLayout)
      path += " M " + splitX + " " + bodyTop + " L " + splitX + " " + bottom
    return path
  }

  function awningPath() {
    if (!awningVisible || awningRight <= left) return ""
    var span = awningRight - left
    var targetWidth = Math.max(Style.space(38), span / 10)
    var count = Math.max(3, Math.round(span / targetWidth))
    var step = span / count
    var depth = Style.space(14)
    var path = "M " + left + " " + bodyTop + " L " + left + " " + awningY
    for (var i = 0; i < count; i++) {
      var start = left + i * step
      var middle = start + step / 2
      var end = start + step
      path += " Q " + middle + " " + (awningY + depth) + " " + end + " " + awningY
    }
    path += " L " + awningRight + " " + bottom
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
