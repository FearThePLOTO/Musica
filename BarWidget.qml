import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Presets.js" as Presets

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

  // Content ink matching the card: readable on any theme.
  readonly property color ink: root.bar ? root.bar.foreground : Color.foreground

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

  // ---- sound mixer: one system-wide equalizer sink -------------------------
  // Curves live in Presets.js, the filter graph in scripts/musica-mixer, which
  // owns the bands, their Q values and the headroom a curve needs. Applying a curve
  // swaps the graph inside the sink that is already playing, so the console can
  // commit as a drag settles and every call here is cheap and idempotent.
  readonly property bool mixerOn: !!root.setting("mixerOn", false)
  readonly property string mixerMode: Presets.modeKey(root.setting("mixerMode", "normal"))
  readonly property var mixerCustom: Presets.sanitizeCustom(root.setting("mixerGains", null))
  readonly property bool mixerOpened: mixerLoader.item ? mixerLoader.item.open === true : false
  property bool mixerBusy: false
  property bool mixerRunning: false
  property string mixerError: ""
  property var mixerQueue: null
  // Last device the mix fed, from the status poll or a switch made in the
  // console. Empty until the mixer has reported once.
  property string mixerTargetName: ""

  // Plugin-relative, so a dev copy and an installed copy each resolve their own.
  readonly property string mixerScript: Qt.resolvedUrl("scripts/musica-mixer").toString().replace(/^file:\/\//, "")

  function mixerGains() {
    return Presets.gainsFor(root.mixerMode, root.mixerCustom)
  }

  // Same write as the card's settings popup: this widget's inline shell.json entry.
  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    var cur = root.settings || {}
    for (var k in cur) if (k !== "id") entry[k] = cur[k]
    entry[key] = value
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // A curve commits as a drag settles, and three writes per commit would rewrite
  // shell.json several times a second to store what it already holds.
  function rememberSetting(key, value) {
    if (JSON.stringify(root.setting(key, null)) === JSON.stringify(value)) return
    root.saveSetting(key, value)
  }

  function mixerArgs(mode, gains) {
    var curve = Presets.gainsFor(mode, gains === undefined || gains === null ? root.mixerCustom : gains)
    return ["apply"].concat(curve.map(function (g) { return String(g) }))
  }

  // Apply now and remember it, so the curve you picked is the curve you come
  // back to after a shell restart.
  function applyMixer(mode, gains) {
    if (gains !== undefined && gains !== null) root.rememberSetting("mixerGains", Presets.sanitizeCustom(gains))
    root.rememberSetting("mixerMode", mode)
    root.rememberSetting("mixerOn", true)
    root.runMixer(root.mixerArgs(mode, gains))
  }

  function stopMixer() {
    root.rememberSetting("mixerOn", false)
    root.runMixer(["off"])
  }

  // One helper run at a time. A newer request replaces a queued one: they all say
  // "the mixer should be this", so only the last one matters.
  function runMixer(args) {
    if (root.mixerScript === "") return
    if (mixerProc.running) {
      root.mixerQueue = args
      return
    }
    root.mixerError = ""
    root.mixerBusy = true
    mixerProc.command = ["bash", root.mixerScript].concat(args)
    mixerProc.running = true
  }

  function refreshMixer() {
    if (!mixerStatus.running) mixerStatus.running = true
  }

  // A shell restart or a theme switch must not leave audio in a stale state:
  // re-apply what was on, and clear what a previous shell left behind.
  function restoreMixer() {
    var remembered = root.setting("mixerOn", null)
    if (remembered === null) return
    if (remembered) root.runMixer(root.mixerArgs(root.mixerMode))
    else root.runMixer(["off"])
  }

  // The device the mix feeds. The helper knows it and the status poll reports
  // it, so the console reads it from there rather than tracking it twice.
  function mixerTarget() {
    return root.mixerTargetName
  }

  function rememberMixerTarget(name) {
    root.mixerTargetName = name
  }

  // Switching output -- headphones, HDMI -- has to move the mix with it, or the
  // equalizer keeps feeding the device it was built for while new streams play
  // straight past it. Debounced because the signal also fires on every settle of
  // a switch, and each pass re-reads the default sink.
  readonly property var defaultSink: Pipewire.defaultAudioSink
  onDefaultSinkChanged: {
    if (!root.mixerOn) return
    var name = root.defaultSink ? String(root.defaultSink.name || "") : ""
    if (name === "" || name === "musica_mixer") return
    followSink.restart()
  }

  Timer {
    id: followSink
    interval: 700
    repeat: false
    onTriggered: {
      if (!root.mixerOn) return
      var name = root.defaultSink ? String(root.defaultSink.name || "") : ""
      if (name === "" || name === "musica_mixer") return
      root.runMixer(root.mixerArgs(root.mixerMode))
    }
  }

  // Quickshell toplevels are tiled by default, and every window this shell opens
  // shares one class, so the console can only be recognized by its title. The rule
  // is registered before the window is shown and again at startup, since a rule
  // registered after a window maps never reaches it.
  Process {
    id: floatMixer
    command: ["hyprctl", "eval", "if mixer_float_rule then mixer_float_rule:set_enabled(false) end; mixer_float_rule = nil; mixer_float_rule = hl.window_rule({ match = { title = \"^Sound mixer$\" }, float = true, center = true })"]
  }

  function openMixer() {
    // The console takes the card's place rather than stacking on it.
    root.close()
    // The window maps on the next frame, so the rule has to be in place first.
    floatMixer.running = true
    if (mixerLoader.item) mixerLoader.item.open = true
    root.refreshMixer()
  }

  function closeMixer() {
    if (mixerLoader.item) mixerLoader.item.open = false
  }

  // ---- popup shape contract (Bar.findPanelWidget needs open/close/opened) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    root.closeMixer()
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

  function injectMixer() {
    var target = mixerLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
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
    injectMixer()
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

  Loader {
    id: mixerLoader
    active: true
    source: Qt.resolvedUrl("Mixer.qml")
    visible: false
    onLoaded: {
      root.injectMixer()
      Qt.callLater(root.injectMixer)
    }
  }

  Process {
    id: mixerProc
    stderr: SplitParser {
      onRead: function(line) {
        // The helper's first line is the summary; the rest is detail.
        var s = String(line).trim()
        if (s !== "" && root.mixerError === "") root.mixerError = s
      }
    }
    onExited: {
      root.mixerBusy = false
      if (root.mixerQueue !== null) {
        var next = root.mixerQueue
        root.mixerQueue = null
        root.runMixer(next)
      } else {
        root.refreshMixer()
      }
    }
  }

  Process {
    id: mixerStatus
    command: ["bash", root.mixerScript, "status"]
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line).trim()
        if (s === "active=yes") root.mixerRunning = true
        else if (s === "active=no") root.mixerRunning = false
        else if (s.indexOf("target=") === 0) root.mixerTargetName = s.slice(7)
      }
    }
  }

  // Polled only while the console is up: it is the difference between "on" and
  // "on, but the host is gone".
  Timer {
    interval: 1500
    repeat: true
    running: root.mixerOpened
    onTriggered: root.refreshMixer()
  }

  Timer {
    id: mixerStartup
    interval: 1500
    repeat: false
    onTriggered: root.restoreMixer()
  }

  Component.onCompleted: {
    mixerStartup.start()
    // Registered here as well as before each open, so the console is floating
    // the first time it is used rather than only after it has been opened once.
    floatMixer.running = true
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
  // plus open/close/toggle for the card and mixer for the sound console.
  // See scripts/musica-keybinds.
  IpcHandler {
    target: "musica"

    function playPause(): string { root.togglePlaying(); return "ok" }
    function next(): string { root.nextTrack(); return "ok" }
    function previous(): string { root.prevTrack(); return "ok" }
    function cycleSource(): string { root.cycleSource(); return "ok" }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function mixer(): void { root.openMixer() }
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
    color: root.bar ? root.ink : Color.foreground
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
