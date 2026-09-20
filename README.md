# Musica

Now-playing card for the Omarchy bar with a **live mini-cava spectrum as the
bar icon**. Talks MPRIS directly, so it follows Spotify, browser YouTube,
and anything else that exposes the standard Linux media interface.

v1: bar icon + wide card (art, title, artist · album, source, prev / play /
next) + global keybinds. Ricing options and progress/seek come next.

v2: source tabs with app icons, Spotify-style seek bar, shuffle + repeat
(dull on players without support), settings popup with the bar-look
switch (cava bars vs song name, persisted to shell.json). Tabs are
always shown and fully independent — nothing auto-switches sources.

UI pass: wave seek bar coupled to live cava, hover animations on every
button, big fitted artwork.

Toast: cover-left mini card on track change AND on skip/prev/play/pause
(selected tab only, silent while the card is open), click raises the
player app. Toggle plus spot (near icon vs top center) in settings,
both instant, no restart. Note: with built-in omarchy.media still
enabled its own text OSD fires too — ours covers our tab only.

## Install (local test)

```sh
# copy this repo as the plugin (repo root IS the plugin: manifest.json lives here)
cp -r /home/ploto/Work/Coding/Omarchy/Musica ~/.config/omarchy/plugins/io.github.feartheploto.musica
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.feartheploto.musica
omarchy bar put io.github.feartheploto.musica --section right
```

Or once pushed: `omarchy plugin add https://github.com/FearThePLOTO/Musica.git --enable`

## Use

- Left click: open/close the card · middle click: play/pause · scroll: prev/next
- Tabs (top, when 2+ sources): click to switch source; dot = playing
- Seek bar: drag to move; dull when the player can't seek
- Card keys: `Space` play/pause, `n` next, `p` previous, `s` cycle source,
  `Esc` close, `Tab` hop panels
- Keybinds (opt-in, installed by the plugin itself):
  ```sh
  ./scripts/musica-keybinds install   # SUPER+ALT+P / N / B / S
  ./scripts/musica-keybinds remove
  ```
  Direct IPC also works: `omarchy-shell musica playPause|next|previous|cycleSource|toggle`

## Requirements

- Omarchy Quattro
- `cava` (optional — without it the bar shows a flat resting icon)
- Any MPRIS player (Spotify, browser, …)

Artwork tries MPRIS art first, then a derived thumbnail (YouTube watch
URLs from browsers that expose no art, e.g. Zen), then the placeholder.

## Remove

```sh
omarchy plugin remove io.github.feartheploto.musica
./scripts/musica-keybinds remove
```
