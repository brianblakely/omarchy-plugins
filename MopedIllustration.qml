import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property color strokeColor: Color.accent
  property color backgroundColor: Color.background
  property real strokeWidth: Math.max(1, Style.spaceReal(2))

  readonly property real designWidth: 180
  readonly property real designHeight: 130
  readonly property real artScale: Math.min(
    width / designWidth, height / designHeight)

  implicitWidth: Style.space(168)
  implicitHeight: implicitWidth * designHeight / designWidth
  opacity: 1.0

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

      // Both complete wheels sit behind opaque bodywork, so their upper arcs
      // disappear naturally beneath the fender and rear cowling.
      ShapePath {
        id: wheelPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 27 87"
            + " C 32 94 31 108 25 121"
            + " C 21 128 13 129 9 123"
            + " C 5 117 7 103 13 91"
            + " C 17 84 23 83 27 87 Z"
            + " M 24 91"
            + " C 28 97 26 108 21 117"
            + " C 18 122 14 120 14 114"
            + " C 14 107 18 96 21 91"
            + " C 22 89 23 89 24 91 Z"
            + " M 123 101"
            + " C 123 87 132 77 144 77"
            + " C 156 77 165 88 165 102"
            + " C 165 116 156 126 144 126"
            + " C 132 126 123 115 123 101 Z"
            + " M 134 101"
            + " C 134 92 139 86 146 86"
            + " C 153 86 158 93 158 102"
            + " C 158 111 153 117 146 117"
            + " C 139 117 134 110 134 101 Z"
        }
      }

      // The tail loop is behind the rear shell; the shell fill masks its
      // inner seam while leaving the outside tab visible.
      ShapePath {
        id: tailLoopPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 169 87 L 174 87"
            + " Q 177 87 177 90 L 178 96"
            + " Q 178 99 174 99 L 170 97 Z"
        }
      }

      // One closed path joins the tall leg shield to the lower frame and
      // footwell, eliminating the former collection of floating strokes.
      ShapePath {
        id: stepThroughBodyPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 38 31"
            + " C 34 39 28 59 28 68"
            + " C 35 70 40 79 42 89"
            + " C 44 99 52 104 62 105"
            + " L 118 106"
            + " L 112 97"
            + " L 96 96 L 82 96"
            + " C 73 96 68 94 63 91"
            + " C 54 84 51 73 53 61"
            + " C 55 49 58 38 54 34"
            + " C 50 30 42 29 38 31 Z"
        }
      }

      ShapePath {
        id: frontFenderPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 10 85"
            + " C 16 72 21 67 28 67"
            + " C 37 67 42 76 42 88"
            + " C 44 91 45 96 42 98"
            + " C 39 95 35 91 29 89 Z"
        }
      }

      // The round rear shell covers the rear wheel. Both seat braces terminate
      // exactly on this outline rather than overshooting it.
      ShapePath {
        id: rearCowlPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 112 105"
            + " C 107 98 106 89 109 79"
            + " C 112 68 121 63 133 63"
            + " C 148 63 160 70 167 82"
            + " C 171 89 173 98 172 104"
            + " Q 172 106 169 106"
            + " L 119 105"
            + " Q 115 105 112 105 Z"
            + " M 102 58 C 109 64 112 71 109 79"
            + " M 150 61 L 161 75"
        }
      }

      ShapePath {
        id: benchSeatPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 103 44 L 151 48"
            + " Q 156 48 156 53 L 155 58"
            + " Q 155 62 150 61 L 102 57"
            + " Q 99 57 99 54 L 100 48"
            + " Q 100 44 103 44 Z"
        }
      }

      // The grips and headset are closed pieces with intentional seam lines at
      // the grip joins, matching the reference drawing.
      ShapePath {
        id: handlebarPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 18 5 L 31 10 L 29 16 L 17 11"
            + " Q 15 10 16 7 Q 16 4 18 5 Z"
            + " M 29 10 L 40 13"
            + " C 44 14 47 14 50 12"
            + " C 56 7 64 8 68 18"
            + " C 70 23 72 26 75 27"
            + " L 73 34 L 65 31"
            + " C 61 30 57 33 52 39"
            + " C 48 34 43 31 39 31"
            + " C 39 26 36 21 29 16 Z"
            + " M 75 27 L 87 32"
            + " Q 89 33 88 35 L 87 39"
            + " Q 86 41 84 40 L 73 34 Z"
        }
      }

      ShapePath {
        id: headlampPath
        fillColor: root.backgroundColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 41 19"
            + " C 41 13 45 9 50 9"
            + " C 56 9 60 14 60 20"
            + " C 60 26 56 31 50 31"
            + " C 44 31 41 26 41 19 Z"
        }
      }

      // Only genuinely open details remain transparent.
      ShapePath {
        id: scooterDetailPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 126 91 L 146 92"
            + " M 126 96 L 146 97"
            + " M 126 101 L 146 102"
            + " M 79 104 L 76 121"
            + " L 73 123 L 79 123 L 78 121 L 82 104"
        }
      }
    }
  }

  Accessible.ignored: true
}
