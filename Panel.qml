import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Musica now-playing card v2: source tabs on top (Zen, Spotify, ...),
// wide art, Spotify-style seek bar, shuffle + repeat that stay dull
// on players without support, and a gear opening a small settings popup.
// Keys (when open): Space play/pause, n next, p prev, s cycle source,
// Esc close, Tab hop.
Panel {
  id: root
  moduleName: "io.github.feartheploto.musica"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool settingsOpen: false

  readonly property var players: hostWidget ? hostWidget.players : []
  readonly property var tabs: Model.tabPlayers(players)
  readonly property var player: hostWidget ? hostWidget.player : null

  // Tabs always show whenever a source exists. No toggle, no auto-switch:
  // every tab is independent, selection only changes on click.
  readonly property bool tabsVisible: tabs.length > 0

  readonly property string title: Model.titleOf(player)
  readonly property string sub: Model.artistAlbum(player)
  readonly property string source: Model.sourceOf(player)
  readonly property bool playing: player ? !!player.isPlaying : false
  readonly property bool hasMedia: title !== "" || Model.artistOf(player) !== ""

  // Artwork fallback chain: MPRIS art, then derived (YouTube thumb),
  // then the placeholder box. Walks forward on load errors.
  readonly property var artSources: Model.artSources(player)
  property int artTry: 0
  readonly property string art: artTry < artSources.length ? artSources[artTry] : ""
  onArtSourcesChanged: root.artTry = 0

  // ---- seek ----
  property bool seeking: false
  property real seekRatio: 0
  readonly property bool canSeekBar: player !== null && !!player.canSeek
    && !!player.positionSupported && !!player.lengthSupported && player.length > 0
  readonly property real shownPos: seeking && canSeekBar
    ? seekRatio * player.length
    : (player ? player.position : 0)

  function open() {
    root.controller.show()
  }

  function close() {
    root.settingsOpen = false
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

  function cycleSource() {
    if (hostWidget && typeof hostWidget.cycleSource === "function") hostWidget.cycleSource()
  }

  function toggleShuffle() {
    var p = root.player
    if (p && p.shuffleSupported) p.shuffle = !p.shuffle
  }

  function cycleLoop() {
    var p = root.player
    if (!p || !p.loopSupported) return
    if (p.loopState === MprisLoopState.None) p.loopState = MprisLoopState.Playlist
    else if (p.loopState === MprisLoopState.Playlist) p.loopState = MprisLoopState.Track
    else p.loopState = MprisLoopState.None
  }

  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    var cur = root.settings || {}
    for (var k in cur) if (k !== "id") entry[k] = cur[k]
    entry[key] = value
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // App icon for a tab: desktop entry -> themed icon, else "" (letter tile).
  function appIcon(p) {
    var id = p ? String(p.desktopEntry || "") : ""
    if (id === "") return ""
    try {
      var e = DesktopEntries.byId(id)
      if (e && e.icon) {
        var found = Quickshell.iconPath(e.icon, true)
        if (found && found.length > 0) return found
      }
    } catch (err) {}
    return ""
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Keep the seek bar alive while playing. Quickshell only pushes
  // position on jumps, so we poke it: 1s ticks, cheap and smooth enough.
  Timer {
    id: posTimer
    running: root.opened && root.playing && root.canSeekBar && !root.seeking
    interval: 1000
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
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
        else if (t === "s") root.cycleSource()
        else if (t === " ") root.togglePlaying()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- source tabs + gear ----
        Item {
          width: parent.width
          height: 34

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            visible: root.tabsVisible

            Repeater {
              model: root.tabs

              delegate: Rectangle {
                required property var modelData
                readonly property bool selected: Model.busOf(modelData) === Model.busOf(root.player)
                readonly property bool live: !!modelData.isPlaying
                width: 34
                height: 34
                radius: 10
                color: selected
                  ? (root.bar ? Qt.alpha(root.bar.urgent, 0.25) : "#444444")
                  : (root.bar ? Qt.alpha(root.bar.barForeground, 0.07) : "#222222")
                border.width: selected ? 1 : 0
                border.color: root.bar ? root.bar.urgent : "white"

                Image {
                  id: tabIcon
                  anchors.centerIn: parent
                  width: 20
                  height: 20
                  source: root.appIcon(modelData)
                  visible: source !== "" && status === Image.Ready
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }

                Text {
                  anchors.centerIn: parent
                  visible: !tabIcon.visible
                  text: Model.initialOf(modelData)
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.barForeground
                }

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 3
                  width: 5
                  height: 5
                  radius: 2.5
                  visible: live
                  color: root.bar ? root.bar.urgent : "white"
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hostWidget) root.hostWidget.selectPlayer(Model.busOf(modelData))
                }
              }
            }
          }

          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 10
            color: root.settingsOpen
              ? (root.bar ? Qt.alpha(root.bar.urgent, 0.25) : "#444444")
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: "󰒓"
              font.pixelSize: 18
              color: root.barForeground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }
        }

        // ---- settings popup: one option, bar look ----
        Rectangle {
          width: parent.width
          height: settingsCol.implicitHeight + Style.space(16)
          radius: Style.space(10)
          visible: root.settingsOpen
          color: root.bar ? Qt.alpha(root.bar.barForeground, 0.07) : "#222222"

          Column {
            id: settingsCol
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "Bar look"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            // Segmented switch: live cava bars or the song name.
            Row {
              width: parent.width
              spacing: Style.space(6)
              readonly property string mode: root.hostWidget ? String(root.hostWidget.setting("barMode", "cava")) : "cava"

              Repeater {
                model: [
                  { key: "cava", label: "Cava bars" },
                  { key: "song", label: "Song name" }
                ]

                delegate: Rectangle {
                  required property var modelData
                  readonly property bool picked: parent.mode === modelData.key
                  width: (settingsCol.width - 16 - 6) / 2
                  height: 34
                  radius: 9
                  color: picked
                    ? (root.bar ? root.bar.urgent : "#e58aa5")
                    : (root.bar ? Qt.alpha(root.bar.barForeground, 0.12) : "#333333")

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: picked ? (root.bar ? root.bar.background : "white") : root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: picked
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.saveSetting("barMode", modelData.key)
                  }
                }
              }
            }
          }
        }

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
            id: cardArt
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
            text: root.hasMedia ? (root.sub || "Unknown artist") : "Start Spotify, Zen, anything MPRIS"
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

        // ---- seek: elapsed ---●--- total ----
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.hasMedia

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            text: root.canSeekBar ? Model.fmtTime(root.shownPos) : "--:--"
            color: root.barForeground
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Item {
            id: seekHit
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 88
            height: 20

            readonly property real ratio: root.canSeekBar && root.player.length > 0
              ? Math.max(0, Math.min(1, root.shownPos / root.player.length))
              : 0

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 4
              radius: 2
              color: root.bar ? Qt.alpha(root.bar.barForeground, root.canSeekBar ? 0.25 : 0.12) : "#444444"
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * seekHit.ratio
              height: 4
              radius: 2
              color: root.bar ? root.bar.urgent : "#e58aa5"
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              x: parent.width * seekHit.ratio - 5
              width: 10
              height: 10
              radius: 5
              color: root.bar ? root.bar.urgent : "#e58aa5"
              visible: root.canSeekBar && (seekArea.containsMouse || root.seeking)
            }

            MouseArea {
              id: seekArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.canSeekBar ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: root.canSeekBar

              function jump(mouse) {
                var r = Math.max(0, Math.min(1, mouse.x / width))
                root.seeking = true
                root.seekRatio = r
              }

              onPressed: function(mouse) { jump(mouse) }
              onPositionChanged: function(mouse) { if (pressed) jump(mouse) }
              onReleased: function(mouse) {
                if (root.player && root.canSeekBar)
                  root.player.position = root.seekRatio * root.player.length
                root.seeking = false
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: root.canSeekBar ? Model.fmtTime(root.player.length) : "--:--"
            color: root.barForeground
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- controls: shuffle prev [play] next repeat ----
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(12)

          // shuffle
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 44
            readonly property bool supported: root.player !== null && !!root.player.shuffleSupported
            readonly property bool on: supported && !!root.player.shuffle
            opacity: supported ? 1 : 0.35

            Text {
              anchors.centerIn: parent
              text: ""
              font.pixelSize: 18
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5") : root.barForeground
              font.bold: parent.on
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: parent.supported ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.toggleShuffle()
            }
          }

          // prev
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: "transparent"
            border.width: 1
            border.color: root.barForeground
            opacity: root.hasMedia ? 0.85 : 0.35

            Text {
              anchors.centerIn: parent
              text: "󰒮"
              font.pixelSize: 20
              color: root.barForeground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.prevTrack()
            }
          }

          // play / pause pill
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 84
            height: 48
            radius: 24
            color: root.bar ? root.bar.urgent : "#e58aa5"
            opacity: root.hasMedia ? 1 : 0.5

            Text {
              anchors.centerIn: parent
              text: root.playing ? "󰏤" : "󰐊"
              font.pixelSize: 24
              color: root.bar ? root.bar.background : "white"
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
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
            opacity: root.hasMedia ? 0.85 : 0.35

            Text {
              anchors.centerIn: parent
              text: "󰒭"
              font.pixelSize: 20
              color: root.barForeground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.nextTrack()
            }
          }

          // repeat: None -> all -> one -> None, dull when unsupported
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 44
            readonly property bool supported: root.player !== null && !!root.player.loopSupported
            readonly property bool one: supported && root.player.loopState === MprisLoopState.Track
            readonly property bool all: supported && root.player.loopState === MprisLoopState.Playlist
            readonly property bool on: one || all
            opacity: supported ? 1 : 0.35

            Text {
              anchors.centerIn: parent
              text: parent.one ? "󰑘" : "󰑖"
              font.pixelSize: 18
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5") : root.barForeground
              font.bold: parent.on
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: parent.supported ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.cycleLoop()
            }
          }
        }
      }
    }
  }
}
