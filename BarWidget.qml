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

  // Card tab selection, shared with Panel.qml via hostWidget. Empty = auto.
  property string selectedBus: ""

  readonly property var player: Model.playerByBus(players, selectedBus) || Model.pickPlayer(players)
  readonly property bool hasMedia: player !== null && (player.trackTitle || player.trackArtist)
  readonly property bool isPlaying: player ? !!player.isPlaying : false
  readonly property string tip: hasMedia
    ? (Model.titleOf(player) + (Model.artistOf(player) ? " — " + Model.artistOf(player) : ""))
    : "Musica — nothing playing"

  function selectPlayer(bus) {
    selectedBus = String(bus || "")
  }

  // Jump selection to the next known source. Manual only (card `s` key,
  // keybind, IPC) — never automatic. Every tab is independent.
  function cycleSource() {
    var tabs = Model.tabPlayers(players)
    if (tabs.length < 2) return
    var cur = Model.busOf(player)
    for (var i = 0; i < tabs.length; i++) {
      if (Model.busOf(tabs[i]) === cur) {
        selectedBus = Model.busOf(tabs[(i + 1) % tabs.length])
        return
      }
    }
    selectedBus = Model.busOf(tabs[0])
  }

  // Bar look, chosen in the card's settings popup: "cava" mini-spectrum
  // or "song" now-playing label. Persisted on the shell.json entry.
  readonly property string barMode: String(setting("barMode", "cava"))
  readonly property bool songMode: barMode === "song"
  readonly property string songLabel: hasMedia
    ? (Model.titleOf(player) + (Model.artistOf(player) ? "  ·  " + Model.artistOf(player) : ""))
    : "Musica"

  // ---- transport (also the IPC surface used by keybinds) ----
  function togglePlaying() {
    var p = root.player
    if (!p) return
    if (p.canTogglePlaying) p.togglePlaying()
    else if (p.isPlaying && p.canPause) p.pause()
    else if (!p.isPlaying && p.canPlay) p.play()
    pokeToast()
  }

  function nextTrack() {
    if (root.player && root.player.canGoNext) root.player.next()
    pokeToast()
  }

  function prevTrack() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
    pokeToast()
  }

  // Toast trigger shared by actions and the track watcher. Silent when
  // the toast is off, the card is open, or nothing is playing. Showing
  // restarts the hide timer, so rapid skips refresh instead of freezing.
  function pokeToast() {
    if (!root.toastOn || root.opened || !root.hasMedia) return
    if (toastLoader.item && typeof toastLoader.item.show === "function") toastLoader.item.show()
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
  }

  function injectToast() {
    var target = toastLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = clickArea
    if ("hostWidget" in target) target.hostWidget = root
  }

  // ---- track-change toast: fire on a new signature, never twice ----
  readonly property bool toastOn: !!root.setting("toast", true)
  property string lastToastSig: ""

  function trackSig(p) {
    if (!p) return ""
    return Model.busOf(p) + "|" + (p.trackTitle || "") + "|" + (p.trackArtist || "")
  }

  function toastTick() {
    if (!root.toastOn || root.opened) return
    var sig = root.trackSig(root.player)
    if (sig === "" || sig === root.lastToastSig) return
    var priming = (root.lastToastSig === "")
    root.lastToastSig = sig
    if (priming) return
    pokeToast()
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

  implicitWidth: (root.songMode ? songText.width : row.implicitWidth) + Style.space(14)
  implicitHeight: barSize

  onBarChanged: {
    injectPanel()
    injectToast()
  }
  onPlayerChanged: {
    injectPanel()
    toastTick()
  }

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

  Loader {
    id: toastLoader
    active: true
    source: Qt.resolvedUrl("Toast.qml")
    visible: false
    onLoaded: {
      root.injectToast()
      Qt.callLater(root.injectToast)
    }
  }

  // Track watcher for the toast: title/artist/play flips re-check the
  // signature. Stays quiet while the card is open or the toast is off.
  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onTrackTitleChanged() { root.toastTick() }
      function onTrackArtistChanged() { root.toastTick() }
      function onIsPlayingChanged() { root.toastTick() }
    }
  }

  // Keybind + media-key surface: `omarchy-shell musica playPause|next|previous`
  // plus open/close/toggle for the card. See scripts/musica-keybinds.
  IpcHandler {
    target: "musica"

    function playPause(): string { root.togglePlaying(); return "ok" }
    function next(): string { root.nextTrack(); return "ok" }
    function previous(): string { root.prevTrack(); return "ok" }
    function cycleSource(): string { root.cycleSource(); return "ok" }
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
    running: root.hasCava && root.isPlaying && !root.songMode
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
    visible: !root.songMode

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

  Text {
    id: songText
    anchors.centerIn: parent
    width: Math.min(implicitWidth, 180)
    visible: root.songMode
    text: root.songLabel
    textFormat: Text.PlainText
    elide: Text.ElideRight
    maximumLineCount: 1
    color: root.bar.barForeground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
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
