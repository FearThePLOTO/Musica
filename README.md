# Musica

Now-playing card for the Omarchy bar with a **live mini-cava spectrum as the
bar icon**. Talks MPRIS directly, so it follows Spotify, browser YouTube,
and anything else that exposes the standard Linux media interface.

v1: bar icon + wide card (art, title, artist · album, source, prev / play /
next) + global keybinds. Ricing options and progress/seek come next.

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
- Card keys: `Space` play/pause, `n` next, `p` previous, `Esc` close, `Tab` hop panels
- Keybinds (opt-in, installed by the plugin itself):
  ```sh
  ./scripts/musica-keybinds install   # SUPER+ALT+P / N / B
  ./scripts/musica-keybinds remove
  ```
  Direct IPC also works: `omarchy-shell musica playPause|next|previous|toggle`

## Requirements

- Omarchy Quattro
- `cava` (optional — without it the bar shows a flat resting icon)
- Any MPRIS player (Spotify, browser, …)

## Remove

```sh
omarchy plugin remove io.github.feartheploto.musica
./scripts/musica-keybinds remove
```
