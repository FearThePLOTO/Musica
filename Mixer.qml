import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Presets.js" as Presets

// Musica sound mixer: a system-wide equalizer in a small floating window, so it
// behaves like any app window -- switchable with the window manager instead of
// covering the screen.
//
// Applying a curve swaps the filter graph inside the running sink, which costs
// nothing audible. A drag still edits locally and commits as it settles, so the
// curve being heard is the one the user is still shaping.
Item {
  id: root

  property var bar: null
  property var hostWidget: null
  property bool open: false

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
    minimumSize: Qt.size(Style.space(520), Style.space(420))

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

          // ---- title ----
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
                text: root.statusLine
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
      }
    }
  }
}
