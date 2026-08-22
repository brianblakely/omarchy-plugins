import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property color strokeColor: Color.accent
  property real strokeWidth: Math.max(1, Style.spaceReal(2))

  readonly property real designWidth: 180
  readonly property real designHeight: 130
  readonly property real artScale: Math.min(
    width / designWidth, height / designHeight)

  implicitWidth: Style.space(168)
  implicitHeight: implicitWidth * designHeight / designWidth
  opacity: 0.84

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

      // The partially covered wheels follow the tall front tire and the
      // enclosed rear tire of the reference scooter.
      ShapePath {
        id: wheelPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 28 88"
            + " C 32 96 30 111 24 122"
            + " C 20 129 13 128 10 122"
            + " C 6 115 9 101 14 91"
            + " M 25 91"
            + " C 28 98 25 109 21 116"
            + " C 18 120 16 117 16 113"
            + " C 16 107 19 97 22 92"
            + " M 124 103"
            + " C 125 116 133 125 144 125"
            + " C 155 125 162 116 162 104"
            + " M 134 104"
            + " C 135 112 140 117 147 117"
            + " C 154 117 158 111 158 104"
        }
      }

      // Tall leg shield flowing into the open footwell.
      ShapePath {
        id: frontShieldPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 28 68"
            + " C 28 60 34 39 38 33"
            + " C 41 29 50 30 54 34"
            + " C 58 38 55 49 53 61"
            + " C 51 73 54 84 63 91"
            + " C 68 95 73 96 82 96"
            + " L 96 96"
            + " C 104 96 109 92 109 83"
            + " C 110 74 109 69 103 62"
            + " M 42 89"
            + " C 44 98 51 103 61 104"
            + " L 118 105"
        }
      }

      // Rounded front mudguard sits over the narrow front tire.
      ShapePath {
        id: frontFenderPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 10 85"
            + " C 16 72 21 67 28 67"
            + " C 37 67 42 76 42 88"
            + " C 44 91 45 96 42 98"
            + " C 39 95 35 91 29 89"
            + " Z"
        }
      }

      // Enclosed rear cowling and the small braces beneath the bench seat.
      ShapePath {
        id: rearCowlPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 112 104"
            + " C 107 98 106 89 109 79"
            + " C 112 68 121 63 133 63"
            + " C 148 63 160 70 167 82"
            + " C 171 89 172 97 172 104"
            + " Q 172 106 169 106"
            + " L 119 105"
            + " Q 115 105 112 104"
            + " Z"
            + " M 102 58"
            + " C 111 64 113 72 112 82"
            + " M 151 61 L 161 74"
        }
      }

      ShapePath {
        id: benchSeatPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 103 44"
            + " L 151 48"
            + " Q 156 48 156 53"
            + " L 155 58"
            + " Q 155 62 150 61"
            + " L 102 57"
            + " Q 99 57 99 54"
            + " L 100 48"
            + " Q 100 44 103 44"
            + " Z"
        }
      }

      // Split grips, rounded headset, and circular headlamp.
      ShapePath {
        id: handlebarPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 18 5"
            + " L 31 10 L 29 16 L 17 11"
            + " Q 15 10 16 7 Q 16 4 18 5 Z"
            + " M 31 10 L 40 13"
            + " C 44 14 47 14 50 12"
            + " M 29 16 L 39 21"
            + " M 39 21"
            + " C 40 13 44 8 50 7"
            + " C 58 6 65 11 68 18"
            + " C 70 23 72 26 75 27"
            + " L 73 34 L 65 31"
            + " C 61 30 57 33 52 39"
            + " C 48 34 43 31 39 31"
            + " Z"
            + " M 75 27 L 87 32"
            + " Q 89 33 88 35 L 87 39"
            + " Q 86 41 84 40 L 73 34 Z"
        }
      }

      ShapePath {
        id: headlampPath
        fillColor: "transparent"
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
          path: "M 41 19"
            + " C 41 13 45 9 50 9"
            + " C 56 9 60 14 60 20"
            + " C 60 26 56 31 50 31"
            + " C 44 31 41 26 41 19"
            + " Z"
        }
      }

      // Rear vents, kickstand, and the small tail loop complete the profile.
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
            + " M 171 87 L 174 87"
            + " Q 176 87 176 90 L 177 96"
            + " Q 177 98 174 98 L 172 97"
        }
      }
    }
  }

  Accessible.ignored: true
}
