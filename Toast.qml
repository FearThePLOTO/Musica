import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Musica track-change toast: passive overlay, deliberately NOT a
// KeyboardPanel. KeyboardPanels grab exclusive keyboard focus and eat
// outside clicks for dismissal — correct for the card, a screen freeze
// for a toast. This is a bare PanelWindow: no focus ever, click-through
// everywhere except the card itself (mask), zero input impact.
Item {
  id: root

  property var bar: null
  property var hostWidget: null
  property var anchorItem: null

  // Same readable-on-any-theme ink as the card.
  readonly property color ink: root.bar ? root.bar.foreground : Color.foreground

  readonly property var player: hostWidget ? hostWidget.player : null
  readonly property string title: Model.titleOf(player)
  readonly property string sub: Model.artistAlbum(player)

  readonly property var artSources: Model.artSources(player)
  property int artTry: 0
  readonly property string art: artTry < artSources.length ? artSources[artTry] : ""
  onArtSourcesChanged: root.artTry = 0

  // Spot picked in settings: right side near the icon, or top center.
  readonly property bool centered: hostWidget
    ? String(hostWidget.setting("toastPos", "icon")) === "center"
    : false

  readonly property bool barBottom: bar ? bar.position === "bottom" : false
  readonly property int cardW: 300
  readonly property int edgeGap: (bar ? bar.barSize : 28) + 8
  readonly property int sideGap: 12

  property bool shown: false

  function show() {
    shown = true
    hideTimer.restart()
  }

  function hide() {
    hideTimer.stop()
    shown = false
  }

  function activate() {
    var p = root.player
    if (p && p.canRaise) {
      try { p.raise(); } catch (err) {}
    } else if (root.hostWidget && typeof root.hostWidget.open === "function") {
      root.hostWidget.open()
    }
    root.hide()
  }

  Timer {
    id: hideTimer
    interval: 3500
    repeat: false
    onTriggered: root.shown = false
  }

  PanelWindow {
    id: win
    visible: root.shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "musica-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: !root.barBottom
      bottom: root.barBottom
      left: true
      right: true
    }
    implicitHeight: cardBox.height + root.edgeGap + 8

    // Only the card rect takes clicks. Everything else passes through.
    mask: Region {
      x: root.centered ? (win.width - root.cardW) / 2 : win.width - root.cardW - root.sideGap
      y: root.barBottom ? 8 : root.edgeGap
      width: root.cardW
      height: cardBox.height
    }

    Item {
      id: cardBox
      x: root.centered ? (parent.width - root.cardW) / 2 : parent.width - root.cardW - root.sideGap
      y: root.barBottom ? 8 : root.edgeGap
      width: root.cardW
      height: toastRow.implicitHeight + 20

      Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.bar ? root.bar.background : "#1e1e1e"
        border.width: 1
        border.color: root.bar ? Qt.alpha(root.bar.barForeground, 0.15) : "#444444"
      }

      Row {
        id: toastRow
        anchors.fill: parent
        anchors.margins: 10
        spacing: Style.space(10)

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: 48
          height: 48

          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: root.bar ? Qt.alpha(root.bar.barForeground, 0.08) : "#333333"

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰝚"
              font.pixelSize: 22
              color: root.bar ? root.ink : "white"
              opacity: 0.5
            }
          }

          Image {
            anchors.fill: parent
            source: root.art
            visible: root.art !== "" && status !== Image.Error
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            onStatusChanged: {
              if (status === Image.Error && root.artTry < root.artSources.length)
                root.artTry = root.artTry + 1
            }
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 58
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.title !== "" ? root.title : "Unknown title"
            color: root.bar ? root.ink : "white"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.sub !== "" ? root.sub : "Unknown artist"
            color: root.bar ? root.ink : "white"
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
      }
    }
  }
}
