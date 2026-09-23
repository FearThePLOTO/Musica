// Musica shared logic: active-player picking, labels, cava parsing.
// Kept in JS so BarWidget.qml and Panel.qml stay declarative.

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
