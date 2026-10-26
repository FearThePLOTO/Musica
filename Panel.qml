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

  // The mixer console itself lives in Mixer.qml, owned by the host widget.
  readonly property bool mixerOpen: root.hostWidget ? root.hostWidget.mixerOpened === true : false
  readonly property bool mixerOn: root.hostWidget ? root.hostWidget.mixerOn === true : false

  // Content ink that stays readable on the popup surface on any theme.
  // barForeground belongs to the bar STRIP (light on Everforest) while
  // the card is dark, so built-ins use bar.foreground for panel content.
  readonly property color ink: root.bar ? root.bar.foreground : Color.foreground

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

  // A player with nothing to skip to (a browser video) gets dim, dead buttons.
  readonly property bool canPrev: player !== null && !!player.canGoPrevious
  readonly property bool canNext: player !== null && !!player.canGoNext

  // Some players freeze Position after a seek; the clock keeps the bar
  // alive from the last trusted value while the player stays quiet.
  property real anchorPos: 0
  property real anchorMs: 0

  // True while our clock outranks the player after a previous: the player
  // may keep reporting where the song used to be.
  // ponytail: a seek in another app within seconds of a previous stays on
  // our clock until the two land within 2 s; upgrade when Seeked is observable.
  property bool clockOwns: false

  // Bumped each tick: Date.now() is not a dependency, this is.
  property int clockTick: 0

  // Never anchor on the player's stale pre-restart position.
  function reanchor() {
    if (clockOwns) return
    anchorPos = player ? player.position : 0
    anchorMs = Date.now()
  }

  // Our own clock: anchor plus playing time, capped at the length.
  readonly property real clockPos: {
    var tick = clockTick
    var p = anchorPos + (playing ? (Date.now() - anchorMs) / 1000 : 0)
    var end = player && player.length > 0 ? player.length : 0
    return end > 0 ? Math.max(0, Math.min(p, end)) : Math.max(0, p)
  }

  // The clock survives players that go quiet; a paused player is exact.
  readonly property real shownPos: {
    if (!player) return 0
    if (seeking && canSeekBar) return seekRatio * player.length
    if (!canSeekBar) return player.position
    if (playing) return clockPos
    return clockOwns ? clockPos : player.position
  }

  onPlayerChanged: {
    pinOwner = null
    clockOwns = false
    reanchor()
    wave.requestPaint()
  }

  // A track change within the same player pins the clock at zero; a player
  // swap keeps the plain re-anchor (the new player may be mid-song).
  property var pinOwner: null
  readonly property int trackKey: player ? player.uniqueId : 0
  onTrackKeyChanged: {
    if (player === pinOwner) pinAtZero()
    else {
      clockOwns = false
      reanchor()
      wave.requestPaint()
    }
    pinOwner = player
  }

  function open() {
    root.controller.show()
  }

  function close() {
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

  // Skip or restart: pin the clock at zero and hand it back when the
  // player's own value lands there. Works for prev-restart (no track
  // change to notice) and next alike.
  function pinAtZero() {
    anchorPos = 0
    anchorMs = Date.now()
    clockOwns = true
    if (player) player.positionChanged()
    wave.requestPaint()
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
      root.clockTick++
      if (root.player) {
        // Fresh values land on our clock (within 2 s); stale ones do not.
        var ahead = root.player.position - root.clockPos
        if (root.clockOwns) {
          if (ahead > -2 && ahead < 2) root.clockOwns = false
        } else if (ahead > 0.5 || ahead < -2) {
          root.anchorPos = root.player.position
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

  onPlayingChanged: {
    wave.requestPaint()
    // A pause freezes the clock on the time played; resume anchors there.
    if (playing) {
      if (!clockOwns) anchorPos = player ? player.position : 0
    } else {
      anchorPos += (Date.now() - anchorMs) / 1000
    }
    anchorMs = Date.now()
  }
  onSeekRatioChanged: wave.requestPaint()

  // The position binding goes stale while the card is closed (Quickshell
  // only pushes position on jumps, and our 1s poker sleeps with the card).
  // Poke on open so the wave lands on the live spot instantly instead of
  // sitting on the old one until the first timer tick.
  onOpenedChanged: {
    if (opened) {
      root.seeking = false
      root.reanchor()
      // Re-read the slept-on clock now, not a second from now.
      root.clockTick++
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
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: !tabIcon.visible
                  text: Model.initialOf(modelData)
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.ink
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

          // One logo opens the console, which holds the equalizer, the output
          // levels and the settings. Lit while it is open, softly lit while the
          // equalizer is shaping the output.
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 10
            color: root.mixerOpen
              ? (root.bar ? Qt.alpha(root.bar.urgent, 0.25) : "#444444")
              : (root.mixerOn ? (root.bar ? Qt.alpha(root.bar.urgent, 0.15) : "#333333") : "transparent")
            scale: logoHover.containsMouse ? (logoHover.pressed ? 0.9 : 1.15) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Image {
              anchors.centerIn: parent
              width: 24
              height: 24
              source: "assets/logo.png"
              fillMode: Image.PreserveAspectFit
              smooth: true
              asynchronous: true
              opacity: logoHover.containsMouse || root.mixerOpen || root.mixerOn ? 1 : 0.75
            }

            MouseArea {
              id: logoHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.hostWidget) root.hostWidget.openMixer()
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
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰝚"
              font.pixelSize: 56
              color: root.ink
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
            textFormat: Text.PlainText
            width: parent.width
            text: root.hasMedia ? (root.title || "Unknown title") : "Nothing playing"
            color: root.ink
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.hasMedia ? (root.sub || "Unknown artist") : "Start Spotify, Zen, anything MPRIS"
            color: root.ink
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            textFormat: Text.PlainText
            visible: root.source !== ""
            width: parent.width
            text: "via " + root.source
            color: root.ink
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
              readonly property real ny: height * 0.60
              readonly property var amps: (root.hostWidget && root.hostWidget.levels) ? root.hostWidget.levels : []
              readonly property real energy: {
                var s = 0
                for (var i = 0; i < amps.length; i++) s += amps[i]
                var avg = amps.length > 0 ? s / amps.length : 0
                if (!root.playing) return 0.12
                return Math.max(0.15, Math.min(1, avg * 2.2))
              }

              // Both layers share one envelope: ramp in from the start,
              // die flat at the thumb.
              function smooth01(t) {
                return t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t)
              }

              function cavaAt(x) {
                var w = width
                var n = amps.length
                var a = 0
                if (n > 1) {
                  var ci = Math.max(0, Math.min(n - 1, (x / w) * (n - 1)))
                  var i0 = Math.floor(ci)
                  var i1 = Math.min(n - 1, i0 + 1)
                  a = amps[i0] + (amps[i1] - amps[i0]) * (ci - i0)
                }
                return a
              }

              function env(x, px) {
                var inW = Math.min(48, px * 0.4)
                var outW = Math.min(56, px * 0.3)
                return smooth01(x / inW) * smooth01((px - x) / outW)
              }

              function topY(x, px, back) {
                var e = energy * env(x, px)
                if (back) // slower, bigger swell behind the front
                  return ny - (Math.sin(x * 0.028 + phase * 0.6 + 2.4) * 5
                    + Math.sin(x * 0.055 + phase * 0.9 + 4.6) * 2.5
                    + cavaAt(x) * 3) * e
                return ny - (Math.sin(x * 0.045 + phase) * 4
                  + Math.sin(x * 0.11 + phase * 1.6) * 2.5
                  + cavaAt(x) * 10) * e
              }

              function waveBody(ctx, x1, px, back) {
                ctx.beginPath()
                if (px < 12) { // sliver: the knob disk covers it anyway
                  ctx.moveTo(0, ny)
                  ctx.lineTo(px, ny)
                  ctx.lineTo(px, ny + 10)
                  ctx.lineTo(0, ny + 10)
                } else {
                  // hot fill of the band: crests carry the top edge, the cap
                  // rounds the start, the knob hides the right shoulder
                  ctx.moveTo(5, ny)
                  for (var x = 11; x < x1; x += 6) ctx.lineTo(x, topY(x, px, back))
                  ctx.lineTo(x1, topY(x1, px, back))
                  for (var x2 = x1; x2 > 5; x2 -= 6) ctx.lineTo(x2, ny + 10)
                  ctx.lineTo(5, ny + 10)
                  ctx.arc(5, ny + 5, 5, Math.PI / 2, Math.PI * 1.5)
                }
                ctx.closePath()
                ctx.fill()
              }

              onPaint: {
                var ctx = getContext("2d")
                var w = width
                if (w <= 0) return
                ctx.clearRect(0, 0, w, height)
                var hot = root.bar ? root.bar.urgent : "#e58aa5"
                var px = w * seekHit.ratio
                ctx.lineCap = "round"
                // clip the bar to rounded corners at both ends
                ctx.save()
                ctx.beginPath()
                ctx.moveTo(5, 0)
                ctx.lineTo(w - 5, 0)
                ctx.quadraticCurveTo(w, 0, w, 5)
                ctx.lineTo(w, height - 5)
                ctx.quadraticCurveTo(w, height, w - 5, height)
                ctx.lineTo(5, height)
                ctx.quadraticCurveTo(0, height, 0, height - 5)
                ctx.lineTo(0, 5)
                ctx.quadraticCurveTo(0, 0, 5, 0)
                ctx.clip()
                // unplayed track, before the fills go over it
                ctx.strokeStyle = root.bar ? Qt.alpha(root.ink, root.canSeekBar ? 0.3 : 0.15) : "#555555"
                ctx.lineWidth = 10
                ctx.beginPath()
                ctx.moveTo(6, ny + 5)
                ctx.lineTo(w - 6, ny + 5)
                ctx.stroke()
                if (px > 0) {
                  ctx.fillStyle = Qt.alpha(hot, 0.6)
                  waveBody(ctx, px, px, true)
                  ctx.fillStyle = hot
                  waveBody(ctx, px, px, false)
                }
                // knob: always visible
                ctx.beginPath()
                ctx.arc(Math.max(8, Math.min(w - 8, px)), ny + 5, 8, 0, 2 * Math.PI)
                ctx.fillStyle = hot
                ctx.fill()
                ctx.restore()
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
              textFormat: Text.PlainText
              width: 40
              text: root.canSeekBar ? Model.fmtTime(root.shownPos) : "--:--"
              color: root.ink
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Item { width: parent.width - 80; height: 1 }

            Text {
              textFormat: Text.PlainText
              width: 40
              horizontalAlignment: Text.AlignRight
              text: root.canSeekBar ? Model.fmtTime(root.player.length) : "--:--"
              color: root.ink
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
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: ""
              font.pixelSize: 22
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5")
                : (shuffleHover.containsMouse ? Qt.lighter(root.ink, 1.4) : root.ink)
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
            opacity: root.hasMedia && root.canPrev ? 1 : 0.35
            scale: prevHover.containsMouse ? (prevHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰒮"
              font.pixelSize: 28
              color: prevHover.containsMouse ? Qt.lighter(root.ink, 1.4) : root.ink
            }

            MouseArea {
              id: prevHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hasMedia && root.canPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
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
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.playing ? "󰏤" : "󰐊"
              font.pixelSize: 30
              color: playHover.containsMouse ? (root.bar ? root.bar.urgent : "#e58aa5") : root.ink
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
            opacity: root.hasMedia && root.canNext ? 1 : 0.35
            scale: nextHover.containsMouse ? (nextHover.pressed ? 0.9 : 1.18) : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: "󰒭"
              font.pixelSize: 28
              color: nextHover.containsMouse ? Qt.lighter(root.ink, 1.4) : root.ink
            }

            MouseArea {
              id: nextHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hasMedia && root.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor
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
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: parent.one ? "󰑘" : "󰑖"
              font.pixelSize: 22
              color: parent.on ? (root.bar ? root.bar.urgent : "#e58aa5")
                : (repeatHover.containsMouse ? Qt.lighter(root.ink, 1.4) : root.ink)
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
