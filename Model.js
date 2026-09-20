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
  return players[0]
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
