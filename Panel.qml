import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Musica now-playing card: wide rounded popup anchored to the bar icon.
// Art on top, title / artist · album, source chip, prev + pill play + next.
// Keys (when open): Space play/pause, n next, p previous, Esc close, Tab hop.
Panel {
  id: root
  moduleName: "io.github.feartheploto.musica"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var player: null

  readonly property string art: Model.artOf(player)
  readonly property string title: Model.titleOf(player)
  readonly property string sub: Model.artistAlbum(player)
  readonly property string source: Model.sourceOf(player)
  readonly property bool playing: player ? !!player.isPlaying : false
  readonly property bool hasMedia: title !== "" || Model.artistOf(player) !== ""

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function togglePlaying() {
    if (hostWidget && typeof hostWidget.togglePlaying === "function") hostWidget.togglePlaying()
  }

  function nextTrack() {
    if (hostWidget && typeof hostWidget.nextTrack === "function") hostWidget.nextTrack()
  }

  function prevTrack() {
    if (hostWidget && typeof hostWidget.prevTrack === "function") hostWidget.prevTrack()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.togglePlaying()
      onTextKey: function(t) {
        if (t === "n") root.nextTrack()
        else if (t === "p") root.prevTrack()
        else if (t === " ") root.togglePlaying()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- artwork ----
        Item {
          width: parent.width
          height: 168

          Rectangle {
            anchors.fill: parent
            radius: Style.space(12)
            color: root.bar ? Qt.alpha(root.bar.barForeground, 0.08) : "#333333"

            Text {
              anchors.centerIn: parent
              text: "󰝚"
              font.pixelSize: 48
              color: root.barForeground
              opacity: 0.5
            }
          }

          Image {
            anchors.fill: parent
            source: root.art
            visible: root.art !== "" && status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            smooth: true
            layer.enabled: true
          }
        }

        // ---- track ----
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: root.hasMedia ? (root.title || "Unknown title") : "Nothing playing"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            width: parent.width
            text: root.hasMedia ? (root.sub || "Unknown artist") : "Start Spotify, YouTube, anything MPRIS"
            color: root.barForeground
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            visible: root.source !== ""
            width: parent.width
            text: "via " + root.source
            color: root.barForeground
            opacity: 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }

        // ---- controls ----
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(16)

          // prev
          Rectangle {
            id: prevBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: "transparent"
            border.width: 1
            border.color: root.barForeground
            opacity: 0.85

            Text {
              anchors.centerIn: parent
              text: "󰒮"
              font.pixelSize: 20
              color: root.barForeground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.prevTrack()
            }
          }

          // play / pause pill
          Rectangle {
            id: playBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 84
            height: 48
            radius: 24
            color: root.bar ? root.bar.urgent : "#e58aa5"

            Text {
              anchors.centerIn: parent
              text: root.playing ? "󰏤" : "󰐊"
              font.pixelSize: 24
              color: root.bar ? root.bar.background : "white"
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePlaying()
            }
          }

          // next
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: "transparent"
            border.width: 1
            border.color: root.barForeground
            opacity: 0.85

            Text {
              anchors.centerIn: parent
              text: "󰒭"
              font.pixelSize: 20
              color: root.barForeground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.nextTrack()
            }
          }
        }
      }
    }
  }
}
