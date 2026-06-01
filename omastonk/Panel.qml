import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "b.omastonk"
  manageIpc: false

  property var anchorItem: null
  property var host: null
  property string draftSymbol: ""

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function normalizeSymbol(value) {
    return String(value || "").trim().toUpperCase().replace(/\s+/g, "")
  }

  function open() {
    draftSymbol = host ? host.symbol : normalizeSymbol(setting("symbol", ""))
    root.controller.show()
    Qt.callLater(function() {
      if (symbolField) {
        symbolField.forceActiveFocus()
        symbolField.selectAll()
      }
    })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function submit() {
    if (host && host.setSymbol) host.setSymbol(draftSymbol)
    root.close()
  }

  function clear() {
    draftSymbol = ""
    if (host && host.setSymbol) host.setSymbol("")
    root.close()
  }

  KeyboardPanel {
    id: symbolPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: symbolField
    contentWidth: symbolPanel.fittedContentWidth(Style.space(280))
    contentHeight: symbolPanel.fittedContentHeight(symbolColumn.implicitHeight)

    Column {
      id: symbolColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: "Symbol"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      TextField {
        id: symbolField
        width: parent.width
        text: root.draftSymbol
        placeholderText: "SPY"
        foreground: root.foreground
        onTextChanged: root.draftSymbol = root.normalizeSymbol(text)
        onAccepted: root.submit()
        Keys.onEscapePressed: root.close()
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: "Clear"
          foreground: root.dim
          onClicked: root.clear()
        }

        Button {
          text: "Save"
          foreground: root.foreground
          accent: Color.accent
          selected: true
          onClicked: root.submit()
        }
      }
    }
  }
}
