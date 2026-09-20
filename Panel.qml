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

  // Dead-reckoning anchor: some browser players freeze their Position
  // after a seek until playback restarts. We track our own clock from
  // the last value we trust, so the wave never sticks on a dead number.
  property real anchorPos: 0
  property real anchorMs: 0

  function reanchor() {
    anchorPos = player ? player.position : 0
    anchorMs = Date.now()
  }

  // While playing, believe whichever is ahead: the server when it moves
  // on its own, otherwise our clock. Capped at the track length.
  readonly property real shownPos: {
    if (!player) return 0
    if (seeking && canSeekBar) return seekRatio * player.length
    if (canSeekBar && playing && !seeking) {
      var est = anchorPos + (Date.now() - anchorMs) / 1000
      var end = player.length > 0 ? player.length : est
      return Math.max(0, Math.min(Math.max(player.position, est), end))
    }
    return player.position
  }

  onPlayerChanged: reanchor()

  function open() {
    root.controller.show()
  }

  function close() {
    root.settingsOpen = false
    // A drag abandoned via Esc never sees onReleased: drop the stale
    // seek state so the bar can't stick on reopen. No commit, just cancel.
    root.seeking = false
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
    onTriggered: {
      if (root.player) {
        // Re-anchor when the server moves on its own; otherwise the
        // dead-reckoning clock keeps the wave alive.
        var s = root.player.position
        if (s > root.anchorPos + 0.5 || s < root.anchorPos - 2) {
          root.anchorPos = s
          root.anchorMs = Date.now()
        }
        root.player.positionChanged()
      }
      wave.requestPaint()
    }
  }

  // Wave motion: advances the phase ~16fps while music plays.
  // The shape itself is coupled to the bar's live cava levels.
  Timer {
    id: waveTimer
    running: root.opened && root.playing && root.hasMedia
    interval: 60
    repeat: true
    onTriggered: {
      wave.phase += 0.35
      wave.requestPaint()
    }
  }

  onPlayingChanged: wave.requestPaint()
  onSeekRatioChanged: wave.requestPaint()

  // The position binding goes stale while the card is closed (Quickshell
  // only pushes position on jumps, and our 1s poker sleeps with the card).
  // Poke on open so the wave lands on the live spot instantly instead of
  // sitting on the old one until the first timer tick.
  onOpenedChanged: {
    if (opened) {
      root.seeking = false
      root.reanchor()
      if (root.player) root.player.positionChanged()
      wave.requestPaint()
    }
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
                scale: tabHover.containsMouse ? (tabHover.pressed ? 0.92 : 1.12) : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
                  id: tabHover
                  anchors.fill: parent
                  hoverEnabled: true
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
            scale: gearHover.containsMouse ? (gearHover.pressed ? 0.9 : 1.15) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: "󰒓"
              font.pixelSize: 18
              color: root.barForeground
            }

            MouseArea {
              id: gearHover
              anchors.fill: parent
              hoverEnabled: true
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

        // ---- artwork: big square, whole image, round corners ----
        Item {
          width: parent.width
          height: 224

          Rectangle {
            anchors.fill: parent
            radius: Style.space(14)
            color: root.bar ? Qt.alpha(root.bar.barForeground, 0.08) : "#333333"

            Text {
              anchors.centerIn: parent
              text: "󰝚"
              font.pixelSize: 56
              color: root.barForeground
              opacity: 0.5
            }
          }

          Image {
            id: cardArt
            anchors.fill: parent
            anchors.margins: 2
            source: root.art
            visible: root.art !== "" && status !== Image.Error
            fillMode: Image.PreserveAspectFit
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

        // ---- seek: live wave bar, times below ----
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: root.hasMedia

          Item {
            id: seekHit
            width: parent.width
            height: 36

            readonly property real ratio: root.canSeekBar && root.player.length > 0
              ? Math.max(0, Math.min(1, root.shownPos / root.player.length))
              : 0

            Canvas {
              id: wave
              anchors.fill: parent
              property real phase: 0
              readonly property var amps: (root.hostWidget && root.hostWidget.levels) ? root.hostWidget.levels : []
              readonly property real energy: {
                var s = 0
                for (var i = 0; i < amps.length; i++) s += amps[i]
                var avg = amps.length > 0 ? s / amps.length : 0
                if (!root.playing) return 0.12
                return Math.max(0.15, Math.min(1, avg * 2.2))
              }

              function topY(x) {
                var w = width
                var n = amps.length
                var a = 0
                if (n > 1) {
                  var ci = Math.max(0, Math.min(n - 1, (x / w) * (n - 1)))
                  var i0 = Math.floor(ci)
                  var i1 = Math.min(n - 1, i0 + 1)
                  a = amps[i0] + (amps[i1] - amps[i0]) * (ci - i0)
                }
                return height * 0.60
                  - Math.sin(x * 0.045 + phase) * 4 * energy
                  - Math.sin(x * 0.11 + phase * 1.6) * 2.5 * energy
                  - a * 10 * energy
              }

              function waveFill(ctx, x0, x1, style) {
                var h = height
                var base = h - 2
                var step = 6
                ctx.beginPath()
                ctx.moveTo(x0, base)
                ctx.lineTo(x0, topY(x0))
                for (var x = x0 + step; x < x1; x += step) ctx.lineTo(x, topY(x))
                ctx.lineTo(x1, topY(x1))
                ctx.lineTo(x1, base)
                ctx.closePath()
                ctx.fillStyle = style
                ctx.fill()
              }

              onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                ctx.clearRect(0, 0, w, h)
                var dim = root.bar ? Qt.alpha(root.bar.barForeground, root.canSeekBar ? 0.20 : 0.10) : "#444444"
                var hot = root.bar ? root.bar.urgent : "#e58aa5"
                waveFill(ctx, 0, w, dim)
                var px = w * seekHit.ratio
                if (px > 0) {
                  ctx.save()
                  ctx.beginPath()
                  ctx.rect(0, 0, px, h)
                  ctx.clip()
                  waveFill(ctx, 0, w, hot)
                  ctx.restore()
                  var kx = Math.max(8, Math.min(w - 8, px))
                  var ky = Math.max(8, Math.min(h - 8, (topY(kx) + h - 2) / 2))
                  ctx.beginPath()
                  ctx.arc(kx, ky, 8, 0, 2 * Math.PI)
                  ctx.fillStyle = hot
                  ctx.fill()
                }
              }
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
                wave.requestPaint()
              }

              onPressed: function(mouse) { jump(mouse) }
              onPositionChanged: function(mouse) { if (pressed) jump(mouse) }
              onReleased: function(mouse) {
                if (root.player && root.canSeekBar) {
                  var target = root.seekRatio * root.player.length
                  root.player.position = target
                  root.anchorPos = target
                  root.anchorMs = Date.now()
                  root.player.positionChanged()
                }
                root.seeking = false
              }
            }
          }

          Row {
            width: parent.width

            Text {
              width: 40
              text: root.canSeekBar ? Model.fmtTime(root.shownPos) : "--:--"
              color: root.barForeground
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Item { width: parent.width - 80; height: 1 }

            Text {
              width: 40
              horizontalAlignment: Text.AlignRight
              text: root.canSeekBar ? Model.fmtTime(root.player.length) : "--:--"
              color: root.barForeground
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- controls: bare glyphs with hover life ----
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(20)

          // shuffle
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 44
            readonly property bool supported: root.player !== null && !!root.player.shuffleSupported
            readonly property bool on: supported && !!root.player.shuffle
            opacity: supported ? 1 : 0.35
            scale: shuffleHover.containsMouse ? (shuffleHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: ""
              font.pixelSize: 22
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5")
                : (shuffleHover.containsMouse ? "white" : root.barForeground)
            }

            MouseArea {
              id: shuffleHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: parent.supported ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.toggleShuffle()
            }
          }

          // prev
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 44
            opacity: root.hasMedia ? 1 : 0.35
            scale: prevHover.containsMouse ? (prevHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: "󰒮"
              font.pixelSize: 28
              color: prevHover.containsMouse ? "white" : root.barForeground
            }

            MouseArea {
              id: prevHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.prevTrack()
            }
          }

          // play / pause
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 44
            opacity: root.hasMedia ? 1 : 0.35
            scale: playHover.containsMouse ? (playHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: root.playing ? "󰏤" : "󰐊"
              font.pixelSize: 30
              color: playHover.containsMouse ? (root.bar ? root.bar.urgent : "#e58aa5") : "white"
            }

            MouseArea {
              id: playHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.togglePlaying()
            }
          }

          // next
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 44
            opacity: root.hasMedia ? 1 : 0.35
            scale: nextHover.containsMouse ? (nextHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: "󰒭"
              font.pixelSize: 28
              color: nextHover.containsMouse ? "white" : root.barForeground
            }

            MouseArea {
              id: nextHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.nextTrack()
            }
          }

          // repeat: None -> all -> one -> None, dull when unsupported
          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 44
            readonly property bool supported: root.player !== null && !!root.player.loopSupported
            readonly property bool one: supported && root.player.loopState === MprisLoopState.Track
            readonly property bool all: supported && root.player.loopState === MprisLoopState.Playlist
            readonly property bool on: one || all
            opacity: supported ? 1 : 0.35
            scale: repeatHover.containsMouse ? (repeatHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              anchors.centerIn: parent
              text: parent.one ? "󰑘" : "󰑖"
              font.pixelSize: 22
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5")
                : (repeatHover.containsMouse ? "white" : root.barForeground)
            }

            MouseArea {
              id: repeatHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: parent.supported ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.cycleLoop()
            }
          }
        }
      }
    }
  }
}
