import QtQuick
import QtQuick.Shapes
import qs.Commons
import "assets/MopedPaths.js" as MopedPaths

Item {
  id: root

  property color strokeColor: Color.accent
  property color backgroundColor: Color.background

  readonly property real designWidth: MopedPaths.artWidth
  readonly property real designHeight: MopedPaths.artHeight
  readonly property real artScale: Math.min(
    width / designWidth, height / designHeight)

  implicitWidth: Style.space(168)
  implicitHeight: implicitWidth * designHeight / designWidth
  clip: true
  opacity: 1.0

  Shape {
    x: -MopedPaths.artX * root.artScale
    y: -MopedPaths.artY * root.artScale
    width: MopedPaths.artX + MopedPaths.artWidth
    height: MopedPaths.artY + MopedPaths.artHeight
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
      strokeColor: "transparent"
      strokeWidth: 0
      PathSvg { path: MopedPaths.lineworkPath }
    }
  }

  Accessible.ignored: true
}
