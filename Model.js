// Musica shared logic: active-player picking, labels, cava parsing,
// output-device rows. Kept in JS so the QML stays declarative.

// The mixer's own sink, which is a filter chain rather than a device: it is not
// an output a user picks a level for, and its volume is the curve's headroom
// rather than loudness. Omarchy's audio panel drops its own tuning sink from
// the lists for the same reason.
var MIXER_SINK = "musica_mixer"

// Ceiling for a level. Past 100% a boosted signal clips in the graph, so this is
// deliberately not unlimited; Omarchy's own audio panel holds streams to the same
// 150%, and its devices to 100%. Ours runs both to 150% because the point of a
// level per app is headroom the user asks for by name.
var MAX_OUTPUT = 1.5

// Every real output device, newest list first. Sinks only: a source is an input,
// and a sink-input is an application's stream, neither of which is an output.
function outputSinks(nodes) {
  var out = []
  for (var i = 0; i < (nodes || []).length; i++) {
    var n = nodes[i]
    if (!n || !n.isSink || n.isStream) continue
    if (String(n.name || "") === MIXER_SINK) continue
    if (!n.audio) continue
    out.push(n)
  }
  return out
}

// A playback stream: something playing into the output, which is what a person
// means by "a voice" -- Spotify, Zen, a browser tab.
function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

// Every application stream, so each one can have its own level. A filter chain's
// own output is a stream too, but it is the processing rather than an
// application -- it belongs to the equalizer tab, not here.
function outputStreams(nodes) {
  var out = []
  for (var i = 0; i < (nodes || []).length; i++) {
    var n = nodes[i]
    if (!n || !isPlaybackStream(n)) continue
    var name = String(n.name || "")
    if (name.indexOf(MIXER_SINK) === 0 || name.indexOf("omarchy_speaker_tuning") === 0) continue
    if (!n.audio) continue
    out.push(n)
  }
  return out
}

// What a stream calls itself. PipeWire hands the application's own name, which
// is the one a person recognizes; the media name is the fallback for the ones
// that do not set it.
function streamLabel(node) {
  if (!node) return "Stream"
  var p = node.properties || {}
  var raw = p["application.name"] || p["media.name"] || node.description || node.name || "Stream"
  return String(raw).trim() || "Stream"
}

// A stream speaks, so it gets a speaker; muted, a struck-through one. The same
// pair omarchy's audio panel uses for its own stream rows.
function streamGlyph(muted) {
  return muted ? "󰝟" : "󰕾"
}

// The name PipeWire hands a device is its driver plumbing. What a person would
// call it is in the nickname the device publishes, and ALSA's is often a whole
// sentence, so the driver prefixes and role suffixes come off.
function outputLabel(node) {
  if (!node) return "Unknown"
  var raw = String(node.nickname || node.description || node.name || "Unknown")
  return raw
    .replace(/^sof-soundwire\s+/i, "")
    .replace(/^built-?in audio\s+/i, "")
    .replace(/^alsa_output\./i, "")
    .replace(/\s*\(hw:\d+,\d+\)\s*$/i, "")
    .replace(/\s*\(default\)\s*$/i, "")
    .replace(/\s+(Output|Input)$/i, "")
    .trim() || "Output"
}

// A device glyph by what it is: a headphone can be told from a speaker by its
// own description, and the transport by the profile it advertises.
function outputGlyph(node) {
  if (!node) return "󰓃"
  var props = node.properties || {}
  var blob = String([
    node.name, node.description, node.nickname,
    props["device.icon-name"] || "",
    props["device.product.name"] || ""
  ].join(" ")).toLowerCase()
  if (blob.indexOf("headphone") !== -1 || blob.indexOf("headset") !== -1
    || blob.indexOf("airpod") !== -1 || blob.indexOf("earbud") !== -1) return "󰋋"
  if (blob.indexOf("bluetooth") !== -1) return "󰂯"
  if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
  return "󰓃"
}

// A device level in the 0..MAX_OUTPUT range the slider uses. Quickshell reports
// linear amplitude, so 150% is 1.5, not 1.15.
function clampOutput(v) {
  var n = Number(v)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(MAX_OUTPUT, n))
}

// Prefer the player that is actually playing, then one with metadata,
// then whatever is around. Mirrors the built-in omarchy.media policy.
function pickPlayer(players) {
  if (!players || players.length === 0) return null
  var i, p
  for (i = 0; i < players.length; i++) {
    p = players[i]
    if (p && p.isPlaying) return p
  }
  for (i = 0; i < players.length; i++) {
    p = players[i]
    if (p && (p.trackTitle || p.trackArtist)) return p
  }
  return players[0] || null
}

function titleOf(player) {
  if (!player) return ""
  return String(player.trackTitle || "").trim()
}

function artistOf(player) {
  if (!player) return ""
  return String(player.trackArtist || "").trim()
}

function albumOf(player) {
  if (!player) return ""
  return String(player.trackAlbum || "").trim()
}

function artistAlbum(player) {
  var artist = artistOf(player)
  var album = albumOf(player)
  if (artist && album) return artist + "  ·  " + album
  return artist || album || ""
}

function sourceOf(player) {
  if (!player) return ""
  return String(player.identity || player.desktopEntry || "").trim()
}

function artOf(player) {
  if (!player) return ""
  return String(player.trackArtUrl || "")
}

// Raw MPRIS metadata map (xesam:url lives here for browsers).
function metaOf(player) {
  if (!player) return {}
  try {
    var md = player.metadata
    if (md) return md
  } catch (err) {}
  return {}
}

function pageUrl(player) {
  var md = metaOf(player)
  var keys = ["xesam:url", "xesam:urls", "mpris:url"]
  for (var i = 0; i < keys.length; i++) {
    var v = md[keys[i]]
    if (v) return String(v)
  }
  return ""
}

// Browsers (Zen/Firefox) give no artUrl but do give the page URL.
// For YouTube that is enough for a real thumbnail.
function youTubeThumb(page) {
  var m = String(page || "").match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?[^#]*v=|embed\/|shorts\/|live\/))([\w-]{6,})/)
  if (m && m[1]) return "https://i.ytimg.com/vi/" + m[1] + "/hqdefault.jpg"
  return ""
}

// Ordered artwork candidates, first hit wins. The card walks this
// list whenever an Image fails, so dead file:// paths and missing
// browser art degrade instead of breaking.
function artSources(player) {
  var out = []
  var direct = artOf(player)
  if (direct !== "") out.push(direct)
  var thumb = youTubeThumb(pageUrl(player))
  if (thumb !== "" && out.indexOf(thumb) < 0) out.push(thumb)
  return out
}

// Parse one cava raw-ascii line ("12;45;900;...") into 0..1 levels.
// maxRange must match ascii_max_range in the generated cava config.
function parseLevels(line, count, maxRange) {
  var out = []
  var i
  for (i = 0; i < count; i++) out.push(0)
  if (!line) return out
  var parts = String(line).split(";")
  for (i = 0; i < count && i < parts.length; i++) {
    var v = parseFloat(parts[i])
    if (!isNaN(v)) out[i] = Math.max(0, Math.min(1, v / maxRange))
  }
  return out
}

// One-pole smoothing so tiny bars don't jump. prev may be shorter.
function smoothLevels(prev, next, keep) {
  var out = []
  for (var i = 0; i < next.length; i++) {
    var p = (prev && i < prev.length) ? prev[i] : 0
    out.push(p * keep + next[i] * (1 - keep))
  }
  return out
}

// Stable per-instance key for a player. Empty when none.
function busOf(p) {
  if (!p) return ""
  return String(p.dbusName || "")
}

// Find a player by bus name, or null.
function playerByBus(players, bus) {
  if (!players || !bus) return null
  for (var i = 0; i < players.length; i++) {
    if (players[i] && busOf(players[i]) === bus) return players[i]
  }
  return null
}

// Players worth showing a tab for: playing now or have track metadata.
// Passive stubs with neither stay out of the way.
function tabPlayers(players) {
  var out = []
  if (!players) return out
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (p && (p.isPlaying || p.trackTitle || p.trackArtist)) out.push(p)
  }
  return out
}

function shortName(player) {
  var s = sourceOf(player)
  return s !== "" ? s : "Player"
}

function initialOf(player) {
  var s = shortName(player)
  return s.length > 0 ? s.charAt(0).toUpperCase() : "?"
}

// Seconds -> m:ss. Guards NaN/negative from half-dead players.
function fmtTime(sec) {
  var s = Math.max(0, Math.floor(Number(sec) || 0))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}
