// Musica sound mixer presets.
//
// Bands are the 10-band graphic equalizer grid Winamp used, which is also the
// grid its presets are specified on. The classic values below are Winamp's
// original presets, converted with Winamp's own scale: a stored value of 33 is
// 0 dB, 64 is +12 dB and 1 is -12 dB.
//
//   dB = (v - 33) * 12 / (v >= 33 ? 31 : 32)
//
// The five use presets are Musica's own. They are shaped for what is playing
// (dialogue, quiet hours, a film) rather than for a genre, and are not anyone's
// published curve.
//
// This file carries the curves, not the equalizer: the band filter graph, its Q
// values and the headroom a curve needs all live in scripts/musica-mixer, which
// is what actually renders and applies them.

.pragma library

var bands = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
var bandLabels = ["60", "170", "310", "600", "1k", "3k", "6k", "12k", "14k", "16k"]

var minGain = -12
var maxGain = 12

var use = [
  { key: "normal", label: "Normal", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { key: "music", label: "Music", gains: [2.5, 1.5, 0, -1, -1, 1, 2, 2.5, 2, 1.5] },
  { key: "movie", label: "Movie", gains: [3, 1, -1.5, -2, 1, 3.5, 2.5, 1, 0, 0] },
  { key: "voice", label: "Voice", gains: [-4, -2, -1, 1, 3, 4, 2.5, 0.5, 0, 0] },
  { key: "night", label: "Night", gains: [-4, -3, -1, 1, 1.5, 1, -2, -3, -3, -3] }
]

var classics = [
  { key: "laptop", label: "Laptop", gains: [2.7, 6.6, 3.1, -2.6, -1.9, 0.8, 2.7, 5.8, 7.7, 8.9] },
  { key: "rock", label: "Rock", gains: [4.6, 2.7, -3.8, -5.2, -2.6, 2.3, 5.4, 6.6, 6.6, 6.6] },
  { key: "pop", label: "Pop", gains: [-1.5, 2.7, 4.3, 4.6, 3.1, -1.1, -1.9, -1.9, -1.5, -1.5] },
  { key: "classical", label: "Classical", gains: [0, 0, 0, 0, 0, 0, -4.9, -4.9, -4.9, -6.4] },
  { key: "club", label: "Club", gains: [0, 0, 1.9, 3.5, 3.5, 3.5, 1.9, 0, 0, 0] },
  { key: "dance", label: "Dance", gains: [5.8, 4.3, 1.2, -0.4, -0.4, -4.1, -4.9, -4.9, -0.4, -0.4] },
  { key: "techno", label: "Techno", gains: [4.6, 3.5, 0, -3.8, -3.4, 0, 4.6, 5.8, 5.8, 5.4] },
  { key: "soft", label: "Soft", gains: [2.7, 0.8, -1.1, -1.9, -1.1, 2.3, 5, 5.8, 6.6, 7.4] }
]

var flat = use[0].gains

function preset(key) {
  var i
  for (i = 0; i < use.length; i++) if (use[i].key === key) return use[i]
  for (i = 0; i < classics.length; i++) if (classics[i].key === key) return classics[i]
  return null
}

function labelFor(key) {
  if (key === "custom") return "Custom"
  var p = preset(key)
  return p ? p.label : "Normal"
}

// A stored mode that no longer exists (a preset renamed between versions) falls
// back to Normal rather than leaving the mixer with no curve.
function modeKey(key) {
  var k = String(key || "")
  return k === "custom" || preset(k) ? k : "normal"
}

function clampGain(v) {
  var n = Number(v)
  if (!isFinite(n)) return 0
  return Math.max(minGain, Math.min(maxGain, Math.round(n * 10) / 10))
}

// Anything coming back from shell.json is untrusted: pad, drop junk, clamp.
function sanitizeCustom(list) {
  var out = []
  for (var i = 0; i < bands.length; i++) {
    out.push(list && list.length > i ? clampGain(list[i]) : 0)
  }
  return out
}

function gainsFor(key, custom) {
  if (key === "custom") return sanitizeCustom(custom)
  var p = preset(key)
  return p ? p.gains.slice(0) : flat.slice(0)
}
