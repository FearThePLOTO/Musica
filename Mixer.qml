import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Presets.js" as Presets

// Musica sound console: a system-wide equalizer and per-output levels in one
// small floating window, so it behaves like any app window -- switchable with
// the window manager instead of covering the screen.
//
// Three tabs, one per job: the equalizer, the output devices, and the plugin's
// settings. Applying a curve swaps the filter graph inside the running sink,
// which costs nothing audible, so a drag commits as it settles and the curve
// being heard is the one the user is still shaping.
Item {
  id: root

  property var bar: null
  property var hostWidget: null
  property bool open: false

  // Which tab is showing. Kept for the life of the window rather than stored:
  // it is a place in the UI, not a preference about the user.
  property string tab: "mixer"

  readonly property var tabs: [
    { key: "mixer", label: "Equalizer" },
    { key: "outputs", label: "Outputs" },
    { key: "settings", label: "Settings" }
  ]

  readonly property color ink: root.bar ? root.bar.foreground : Color.foreground
  readonly property color accent: root.bar ? root.bar.urgent : Color.accent
  readonly property color surface: root.bar ? root.bar.background : "#1e1e1e"

  readonly property var hostGains: root.hostWidget ? root.hostWidget.mixerGains() : Presets.flat
  readonly property string mode: root.hostWidget ? root.hostWidget.mixerMode : "normal"
  readonly property bool on: root.hostWidget ? root.hostWidget.mixerOn : false
  readonly property bool running: root.hostWidget ? root.hostWidget.mixerRunning : false
  // What is playing through the mixer is the host, not the setting. A host left
  // behind by a settings reset shows up here as on, and one click clears it.
  readonly property bool active: root.on || root.running
  readonly property bool busy: root.hostWidget ? root.hostWidget.mixerBusy : false
  readonly property string problem: root.hostWidget ? root.hostWidget.mixerError : ""

  // A drag works on a draft so nothing is written per pixel; the settled draft is
  // committed once, and that commit is what reaches the audio.
  property var draft: null
  readonly property var curve: root.draft !== null ? root.draft : root.hostGains

  readonly property var useModes: {
    var out = []
    for (var i = 0; i < Presets.use.length; i++) out.push(Presets.use[i])
    out.push({ key: "custom", label: "Custom" })
    return out
  }

  readonly property string statusLine: {
    if (root.problem !== "") return root.problem
    if (root.busy) return "Applying…"
    if (!root.active) return "Off — audio goes straight to the output"
    // The poll is the difference between "on" and "on, but the host is gone".
    if (!root.running) return "On · " + Presets.labelFor(root.mode) + " · starting"
    return "On · " + Presets.labelFor(root.mode) + " · every app plays through the mixer"
  }

  // ---- outputs: one level per device --------------------------------------
  // Read live from the PipeWire service rather than polled, so a level moved by
  // the volume keys lands here without the console asking for it.
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var outputs: Model.outputSinks(root.nodes)
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property string defaultSinkName: root.defaultSink ? String(root.defaultSink.name || "") : ""

  // Which device the level actually lands on. With the mixer on, the default
  // output is the mix itself, so loudness lives on the device underneath it --
  // the same resolution Omarchy's volume keys make, so the console and the keys
  // can never disagree about what is loud.
  function physicalSinkFor(name) {
    if (name === "" || name === Model.MIXER_SINK) {
      if (root.hostWidget && typeof root.hostWidget.mixerTarget === "function")
        return root.hostWidget.mixerTarget()
      return ""
    }
    return name
  }

  readonly property bool mixerHidesDefault: root.active && root.defaultSinkName === Model.MIXER_SINK

  function isCurrent(node) {
    if (!node) return false
    if (root.mixerHidesDefault) {
      var target = root.physicalSinkFor(root.defaultSinkName)
      return target !== "" && String(node.name || "") === target
    }
    return String(node.name || "") === root.defaultSinkName
  }

  function percent(node) {
    if (!node || !node.audio) return 0
    return Math.round(Model.clampOutput(node.audio.volume) * 100)
  }

  // Unmute on raise, so dragging a muted device up is not silent: the same rule
  // omarchy-audio-output-volume follows on a volume key.
  function setLevel(node, value) {
    if (!node || !node.audio) return
    node.audio.volume = Model.clampOutput(value)
    if (node.audio.volume > 0 && node.audio.muted) node.audio.muted = false
  }

  function toggleMute(node) {
    if (!node || !node.audio) return
    node.audio.muted = !node.audio.muted
  }

  function chooseDefault(node) {
    if (!node || !node.audio) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-output-set-default",
        String(node.id),
        String(node.name)
      ])
    }
    // Naming it here too keeps the mixer following this switch when it is on.
    if (root.hostWidget && typeof root.hostWidget.rememberMixerTarget === "function")
      root.hostWidget.rememberMixerTarget(String(node.name || ""))
  }

  // Settings live on the bar widget's inline shell.json entry, so the console
  // reads and writes them through the host rather than keeping its own copy.
  function setting(key, fallback) {
    if (!root.hostWidget || typeof root.hostWidget.setting !== "function") return fallback
    return root.hostWidget.setting(key, fallback)
  }

  function saveSetting(key, value) {
    if (!root.hostWidget || typeof root.hostWidget.rememberSetting !== "function") return
    root.hostWidget.rememberSetting(key, value)
  }

  function choose(key) {
    if (!root.hostWidget) return
    root.draft = null
    // Picking Custom keeps whatever curve is on screen; anything else loads that
    // preset. Both apply immediately, so the click is audible.
    if (key === "custom") root.hostWidget.applyMixer("custom", root.curve)
    else root.hostWidget.applyMixer(key)
  }

  function edit(index, value) {
    var next = Presets.clampGain(value)
    if (root.draft === null) root.draft = root.curve.slice(0)
    root.draft[index] = next
    settle.restart()
  }

  function commit() {
    if (root.draft === null || !root.hostWidget) return
    var next = root.draft.slice(0)
    root.draft = null
    // Editing a preset's fader turns it into Custom from where it stood.
    root.hostWidget.applyMixer("custom", next)
  }

  function toggle() {
    if (!root.hostWidget) return
    root.draft = null
    if (root.active) root.hostWidget.stopMixer()
    else root.hostWidget.applyMixer(root.mode)
  }

  function reset() {
    if (!root.hostWidget) return
    root.draft = null
    root.hostWidget.applyMixer("normal", Presets.flat)
  }

  onOpenChanged: {
    if (!root.open) return
    root.draft = null
    // The window is instantiated hidden, so the keys only work once it is on
    // screen and the surface can take focus.
    Qt.callLater(function() {
      if (root.open) keyCatcher.forceActiveFocus()
    })
  }

  Timer {
    id: settle
    // A change is one graph swap and a helper run, so it is cheap enough to hear
    // the curve move under the drag instead of only at the end of it.
    interval: 180
    repeat: false
    onTriggered: root.commit()
  }

  // A real toplevel, so the window manager treats it as an open app: it floats,
  // takes no tile, and Super can find it. The float rule that makes it float is
  // registered by BarWidget before the window is shown; without it the window
  // manager would tile it like any other Quickshell window.
  FloatingWindow {
    id: win

    title: "Sound mixer"
    visible: root.open
    // The bar's own background is translucent, which reads fine over a scrim but
    // not behind a grid of numbers over an arbitrary desktop.
    color: Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 1)
    implicitWidth: Style.space(720)
    implicitHeight: body.implicitHeight + Style.space(32)
    // Tall enough for the faders, so switching tabs does not jump the window.
    minimumSize: Qt.size(Style.space(520), Style.space(560))

    FocusScope {
      id: keyCatcher

      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.open = false

      Rectangle {
        id: card

        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: root.bar ? Qt.alpha(root.bar.barForeground, 0.18) : "#444444"

        Column {
          id: body

          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          // ---- title + close ----
          Row {
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width - closeButton.width - Style.space(10)
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Sound mixer"
                color: root.ink
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                // The status is about the equalizer, so the other tabs leave it
                // blank rather than hidden: the row still holds its height and
                // the tab bar does not jump when the tab changes.
                text: root.tab === "mixer" ? root.statusLine : ""
                color: root.ink
                opacity: root.problem !== "" ? 0.95 : 0.6
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }

            Rectangle {
              id: closeButton

              width: 30
              height: 30
              radius: Style.space(9)
              color: closeHover.containsMouse ? Qt.alpha(root.ink, 0.12) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                // md-close
                text: "\u{F0156}"
                font.pixelSize: 15
                color: root.ink
              }

              MouseArea {
                id: closeHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = false
              }
            }
          }

          // ---- tabs: which job this window is doing ----
          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.tabs

              Button {
                required property var modelData
                width: (tabRow.width - Style.space(6) * (root.tabs.length - 1)) / root.tabs.length
                text: modelData.label
                bordered: true
                selected: root.tab === modelData.key
                foreground: root.ink
                accent: root.accent
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onClicked: root.tab = modelData.key
              }
            }

            id: tabRow
          }

          // ---- equalizer ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.tab === "mixer"

          // ---- modes ----
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "Mode"
                color: root.ink
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: "click to apply"
                color: root.ink
                opacity: 0.45
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.useModes

                Button {
                  required property var modelData
                  text: modelData.label
                  bordered: true
                  selected: root.mode === modelData.key
                  foreground: root.ink
                  accent: root.accent
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  onClicked: root.choose(modelData.key)
                }
              }

              Item { width: Style.space(8); height: Style.space(2) }

              Repeater {
                model: Presets.classics

                Button {
                  required property var modelData
                  text: modelData.label
                  bordered: true
                  selected: root.mode === modelData.key
                  foreground: root.ink
                  accent: root.accent
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  onClicked: root.choose(modelData.key)
                }
              }
            }
          }

          // ---- faders ----
          Rectangle {
            width: parent.width
            height: faderRow.implicitHeight + Style.space(20)
            radius: Style.space(12)
            color: root.bar ? Qt.alpha(root.bar.barForeground, 0.06) : "#262626"

            Row {
              id: faderRow

              x: Style.space(10)
              y: Style.space(10)
              width: parent.width - Style.space(20)
              spacing: Style.space(4)

              Repeater {
                model: Presets.bandLabels

                Item {
                  id: cell

                  required property int index
                  required property string modelData

                  // Sized by what is in it, so the block above can measure it
                  // instead of the two measuring each other.
                  width: (faderRow.width - Style.space(4) * (Presets.bandLabels.length - 1)) / Presets.bandLabels.length
                  height: column.implicitHeight

                  readonly property real gain: Number(root.curve[index]) || 0

                  Column {
                    id: column

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: (cell.gain > 0 ? "+" : "") + cell.gain.toFixed(1)
                      color: root.ink
                      opacity: Math.abs(cell.gain) < 0.05 ? 0.4 : 1
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Item {
                      width: 24
                      height: 132

                      PanelSlider {
                        width: 132
                        height: 24
                        anchors.centerIn: parent
                        // Vertical, so the ten bands read like the sliders they are.
                        rotation: -90
                        bar: root.bar
                        minimum: Presets.minGain
                        maximum: Presets.maxGain
                        value: cell.gain
                        onMoved: function(value) { root.edit(cell.index, value) }
                        onReleased: function(value) { root.edit(cell.index, value) }
                        onRightClicked: root.edit(cell.index, 0)
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: cell.modelData
                      color: root.ink
                      opacity: 0.55
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          // ---- enable + reset ----
          Row {
            width: parent.width
            spacing: Style.space(10)

            Toggle {
              width: parent.width - resetButton.width - Style.space(10)
              label: "Equalizer"
              description: root.active ? "Playing every app through the mixer" : "Bypassed"
              checked: root.active
              foreground: root.ink
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.toggle()
            }

            Button {
              id: resetButton

              text: "Reset"
              bordered: true
              foreground: root.ink
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.reset()
            }
          }
          }

          // ---- outputs: one level per device ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.tab === "outputs"

            Text {
              textFormat: Text.PlainText
              text: root.mixerHidesDefault
                ? "Levels land on the device under the mixer"
                : "Pick an output, then set its level"
              color: root.ink
              opacity: 0.6
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.outputs

              Rectangle {
                required property var modelData

                id: outputRow

                readonly property bool current: root.isCurrent(outputRow.modelData)
                readonly property bool muted: outputRow.modelData.audio ? outputRow.modelData.audio.muted : false

                width: parent.width
                height: Style.space(52)
                radius: Style.space(12)
                color: outputRow.current
                  ? (root.bar ? Qt.alpha(root.bar.urgent, 0.16) : "#3a2f33")
                  : (root.bar ? Qt.alpha(root.bar.barForeground, 0.06) : "#262626")

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: levelSlider.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    text: Model.outputGlyph(outputRow.modelData)
                    color: root.ink
                    opacity: outputRow.muted ? 0.4 : 1
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Capped so a long device name cannot squeeze the fader out
                    // of the row; the name elides instead.
                    width: Math.min(parent.width - Style.space(32), Style.space(220))
                    text: Model.outputLabel(outputRow.modelData)
                    color: root.ink
                    opacity: outputRow.muted ? 0.5 : 1
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: outputRow.current
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                // Left of the slider is the pick: this row is the output, the
                // fader is its loudness.
                MouseArea {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: levelSlider.left
                  anchors.rightMargin: Style.space(10)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.chooseDefault(outputRow.modelData)
                }

                Text {
                  id: levelText

                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(46)
                  horizontalAlignment: Text.AlignRight
                  // The dragged value while dragging, so the number tracks the
                  // thumb instead of lagging a round trip through PipeWire.
                  text: (outputRow.modelData.audio
                    && (levelSlider.dragging ? levelSlider.liveValue : outputRow.modelData.audio.volume) >= 0
                    ? Math.round(Model.clampOutput(levelSlider.dragging ? levelSlider.liveValue : outputRow.modelData.audio.volume) * 100) : 0) + "%"
                  color: root.ink
                  opacity: outputRow.muted ? 0.5 : 0.8
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: outputRow.current
                }

                PanelSlider {
                  id: levelSlider

                  // Fills what is left between the name and the number, so the
                  // row reads as one control at any window width.
                  anchors.right: levelText.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(Style.space(120), outputRow.width - levelText.width - Style.space(260))
                  height: Style.space(24)
                  minimum: 0
                  maximum: Model.MAX_OUTPUT
                  step: 0.01
                  // A notch at 100%, so the unity mark is findable on a track
                  // that runs to 150.
                  tickCount: 4
                  value: outputRow.modelData.audio ? Model.clampOutput(outputRow.modelData.audio.volume) : 0
                  opacity: outputRow.muted ? 0.5 : 1
                  onMoved: function(v) { root.setLevel(outputRow.modelData, v) }
                  onReleased: function(v) { root.setLevel(outputRow.modelData, v) }
                  onRightClicked: root.toggleMute(outputRow.modelData)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.outputs.length === 0
                || root.outputs.every(function(n) { return !n.ready })
              text: "Waiting for audio devices…"
              color: root.ink
              opacity: 0.6
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            // 0% and 150% both show up as a level, so the range is stated rather
            // than left to be discovered by clipping.
            Text {
              textFormat: Text.PlainText
              text: "Up to 150% — past 100% a loud master can clip"
              color: root.ink
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          // ---- settings ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.tab === "settings"

            // Segmented switch: live cava bars or the song name.
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Bar look"
                color: root.ink
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                readonly property string mode: root.setting("barMode", "cava")

                Repeater {
                  model: [
                    { key: "cava", label: "Cava bars" },
                    { key: "song", label: "Song name" }
                  ]

                  Button {
                    required property var modelData
                    width: (parent.width - Style.space(6)) / 2
                    text: modelData.label
                    bordered: true
                    selected: parent.mode === modelData.key
                    foreground: root.ink
                    accent: root.accent
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onClicked: root.saveSetting("barMode", modelData.key)
                  }
                }
              }
            }

            // Track-change toast. Takes effect immediately: the watcher reads
            // the setting live, no restart involved.
            Rectangle {
              width: parent.width
              height: Style.space(52)
              radius: Style.space(12)
              color: root.bar ? Qt.alpha(root.bar.barForeground, 0.06) : "#262626"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(70)
                text: "Track toast"
                color: root.ink
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              Toggle {
                id: toastToggle

                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(44)
                height: Style.space(26)
                label: ""
                description: ""
                checked: !!root.setting("toast", true)
                foreground: root.ink
                accent: root.accent
                // The row is clickable too, but only outside the switch: the
                // switch has its own click, and an overlay would swallow it.
                onClicked: root.saveSetting("toast", !root.setting("toast", true))
              }

              MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: toastToggle.left
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveSetting("toast", !root.setting("toast", true))
              }
            }

            // Toast spot: under the bar icon, or top-center under the clock.
            // The toast reads it live, so it moves on click.
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Toast spot"
                color: root.ink
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                readonly property string mode: root.setting("toastPos", "icon")

                Repeater {
                  model: [
                    { key: "icon", label: "Near icon" },
                    { key: "center", label: "Top center" }
                  ]

                  Button {
                    required property var modelData
                    width: (parent.width - Style.space(6)) / 2
                    text: modelData.label
                    bordered: true
                    selected: parent.mode === modelData.key
                    foreground: root.ink
                    accent: root.accent
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    onClicked: root.saveSetting("toastPos", modelData.key)
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Everything here takes effect immediately"
              color: root.ink
              opacity: 0.45
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }
        }
      }
    }
  }
}
