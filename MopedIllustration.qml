import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property color strokeColor: Color.accent
  property real strokeWidth: Math.max(1, Style.spaceReal(2))

  readonly property real designWidth: 180
  readonly property real designHeight: 112
  readonly property real artScale: Math.min(
    width / designWidth, height / designHeight)

  implicitWidth: Style.space(168)
  implicitHeight: implicitWidth * designHeight / designWidth
  opacity: 0.82

  Item {
    id: drawing
    anchors.centerIn: parent
    width: root.designWidth
    height: root.designHeight
    scale: root.artScale

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
        PathSvg {
          path: "M 22 82 A 21 21 0 1 0 64 82 A 21 21 0 1 0 22 82"
            + " M 116 82 A 21 21 0 1 0 158 82 A 21 21 0 1 0 116 82"
            + " M 38 82 A 5 5 0 1 0 48 82 A 5 5 0 1 0 38 82"
            + " M 132 82 A 5 5 0 1 0 142 82 A 5 5 0 1 0 132 82"
        }
      }

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 35 63 C 40 49 53 40 69 39"
            + " L 86 39 C 97 40 104 48 103 58"
            + " C 103 64 99 69 94 74 L 66 74"
            + " C 59 74 55 77 53 82"
            + " M 66 74 L 102 74 C 110 74 114 78 116 82"
            + " M 95 73 C 106 64 111 53 115 39 L 126 40 L 137 82"
            + " M 118 69 C 124 59 144 58 153 72"
            + " M 58 38 C 64 32 77 31 90 34"
            + " C 94 35 94 39 90 40 L 62 40 C 59 40 57 39 58 38"
            + " M 115 40 C 118 30 125 25 136 26 L 148 30"
            + " M 128 26 L 132 20"
            + " M 39 48 L 31 45 L 27 50"
        }
      }

      ShapePath {
        fillColor: "transparent"
        strokeColor: Util.alpha(root.strokeColor, 0.68)
        strokeWidth: Math.max(1, root.strokeWidth * 0.72)
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 112 43 A 5 5 0 1 0 122 43 A 5 5 0 1 0 112 43"
            + " M 67 57 L 88 57 L 94 69 L 72 69 Z"
            + " M 76 63 A 4 4 0 1 0 84 63 A 4 4 0 1 0 76 63"
            + " M 80 67 C 83 82 98 89 113 86"
            + " M 92 75 L 101 100 L 109 100"
            + " M 43 61 C 48 55 55 51 63 50"
            + " M 31 82 L 43 82 L 53 75"
            + " M 126 82 L 137 82 L 146 76"
            + " M 22 106 L 158 106"
        }
      }
    }
  }

  Accessible.ignored: true
}
