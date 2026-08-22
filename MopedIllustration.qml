import QtQuick
import QtQuick.Shapes
import qs.Commons
import "assets/MopedPaths.js" as MopedPaths

Item {
  id: root

  property color strokeColor: Color.accent
  property color backgroundColor: Color.background
  property real strokeWidth: Math.max(1, Style.spaceReal(2))

  // The source encodes its blue bands at roughly six SVG units. Expand those
  // bands only by the amount needed to reach Okomart's live interface stroke.
  readonly property real encodedLineWidth: 6
  readonly property real sourcePadding: 4
  readonly property real designWidth: MopedPaths.artWidth + sourcePadding * 2
  readonly property real designHeight: MopedPaths.artHeight + sourcePadding * 2
  readonly property real artScale: Math.min(
    width / designWidth, height / designHeight)
  readonly property real lineworkStrokeWidth:
    artScale > 0
      ? Math.max(0, strokeWidth / artScale - encodedLineWidth)
      : 0

  implicitWidth: Style.space(168)
  implicitHeight: implicitWidth * designHeight / designWidth
  clip: true
  opacity: 1.0

  Shape {
    x: -(MopedPaths.artX - root.sourcePadding) * root.artScale
    y: -(MopedPaths.artY - root.sourcePadding) * root.artScale
    width: MopedPaths.artX + MopedPaths.artWidth + root.sourcePadding
    height: MopedPaths.artY + MopedPaths.artHeight + root.sourcePadding
    scale: root.artScale
    transformOrigin: Item.TopLeft
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.backgroundColor
      fillRule: ShapePath.OddEvenFill
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { path: MopedPaths.bodyworkPath }
    }

    ShapePath {
      fillColor: root.strokeColor
      fillRule: ShapePath.OddEvenFill
      strokeColor: root.strokeColor
      strokeWidth: root.lineworkStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: MopedPaths.lineworkPath }
    }
  }

  Accessible.ignored: true
}
