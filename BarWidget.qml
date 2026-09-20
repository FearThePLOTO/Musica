import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Musica bar widget: a live mini-cava spectrum as the bar icon.
// Talks MPRIS directly (any player: Spotify, browser YouTube, ...).
// Left click opens the card, middle click toggles play, wheel skips tracks.
BarWidget {
  id: root
  moduleName: "io.github.feartheploto.musica"

  // ---- now playing (direct MPRIS, no dependency on omarchy.media) ----
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Model.pickPlayer(players)
  readonly property bool hasMedia: player !== null && (player.trackTitle || player.trackArtist)
  readonly property bool isPlaying: player ? !!player.isPlaying : false
  readonly property string tip: hasMedia
    ? (Model.titleOf(player) + (Model.artistOf(player) ? " — " + Model.artistOf(player) : ""))
    : "Musica — nothing playing"

  // ---- transport (also the IPC surface used by keybinds) ----
  function togglePlaying() {
    var p = root.player
    if (!p) return
    if (p.canTogglePlaying) p.togglePlaying()
    else if (p.isPlaying && p.canPause) p.pause()
    else if (!p.isPlaying && p.canPlay) p.play()
  }

  function nextTrack() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  function prevTrack() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  // ---- popup shape contract (Bar.findPanelWidget needs open/close/opened) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = clickArea
    if ("hostWidget" in target) target.hostWidget = root
    if ("player" in target) target.player = Qt.binding(function() { return root.player })
  }

  // ---- mini cava state ----
  readonly property int barCount: 6
  readonly property int cavaMax: 1000
  property bool hasCava: false
  property var levels: [0, 0, 0, 0, 0, 0]

  function cavaConfig() {
    return "CFG=\"${XDG_RUNTIME_DIR:-/tmp}/musica-cava.conf\"; "
      + "printf '%s\\n' '[general]' 'bars = " + root.barCount + "' 'framerate = 30' "
      + "'[input]' 'method = pipewire' 'source = auto' "
      + "'[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' "
      + "'ascii_max_range = " + root.cavaMax + "' 'bar_delimiter = 59' 'channels = mono' > \"$CFG\"; "
      + "exec cava -p \"$CFG\" 2>/dev/null"
  }

  function applyCavaLine(line) {
    var next = Model.parseLevels(line, root.barCount, root.cavaMax)
    // Freeze to a flat resting line when silent instead of the last peak.
    var live = false
    for (var i = 0; i < next.length; i++) {
      if (next[i] > 0.02) { live = true; break }
    }
    if (!live) next = [0.02, 0.02, 0.02, 0.02, 0.02, 0.02]
    root.levels = Model.smoothLevels(root.levels, next, 0.55)
  }

  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  onBarChanged: injectPanel()
  onPlayerChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Keybind + media-key surface: `omarchy-shell musica playPause|next|previous`
  // plus open/close/toggle for the card. See scripts/musica-keybinds.
  IpcHandler {
    target: "musica"

    function playPause(): string { root.togglePlaying(); return "ok" }
    function next(): string { root.nextTrack(); return "ok" }
    function previous(): string { root.prevTrack(); return "ok" }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function ping(): string { return "ok" }
  }

  Process {
    id: cavaProbe
    running: true
    command: ["bash", "-lc", "command -v cava >/dev/null 2>&1 && printf 1 || printf 0"]
    stdout: SplitParser {
      onRead: function(data) { root.hasCava = String(data).trim() === "1" }
    }
  }

  Process {
    id: cavaProc
    running: root.hasCava && root.isPlaying
    command: ["bash", "-lc", root.cavaConfig()]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (root.isPlaying) root.applyCavaLine(line)
      }
    }
    onExited: {
      if (root.hasCava && root.isPlaying) cavaRestart.restart()
    }
  }

  Timer {
    id: cavaRestart
    interval: 1200
    repeat: false
    onTriggered: {
      if (root.hasCava && root.isPlaying && !cavaProc.running) cavaProc.running = true
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 3

    Repeater {
      model: root.barCount

      Rectangle {
        required property int index
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        radius: 1.5
        height: root.isPlaying && root.hasCava
          ? Math.max(4, Math.round(root.levels[index] * 16))
          : 4
        color: root.isPlaying ? root.bar.urgent : root.bar.barForeground
        opacity: root.isPlaying ? 1 : 0.45

        Behavior on height {
          enabled: root.isPlaying
          NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }
        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }

  MouseArea {
    id: clickArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.togglePlaying()
      else root.togglePanel()
    }
    onWheel: function(wheel) {
      if (wheel.angleDelta.y > 0) root.prevTrack()
      else if (wheel.angleDelta.y < 0) root.nextTrack()
    }
    onEntered: if (root.bar) root.bar.showTooltip(clickArea, root.tip)
    onExited: if (root.bar) root.bar.hideTooltip(clickArea)
  }
}
