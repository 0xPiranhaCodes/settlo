# Canvas reference renders

`scripts/render-canvas.sh` renders every `design/canvas/*.dc.html` artboard at
390x844 and 360x800 with a locally installed headless Chrome or Chromium. The
committed output is grouped by logical pixel width in `390/` and `360/`.

The canvas runtime's `./support.js` is not present in this repository. The
renderer therefore removes that one script tag from a temporary copy and
captures the remaining static HTML. It waits for `document.fonts.ready` and
checks that Figtree and IBM Plex Serif loaded before capture. These images do
not include behavior, runtime-injected content, platform chrome, Flutter text
rasterization, or native safe-area differences, so app golden comparisons may
show small anti-aliasing and platform-metric differences even when layout and
tokens match.

Run from any directory:

```sh
scripts/render-canvas.sh
```

Set `CHROME_BIN=/path/to/chrome` when Chrome is not in a standard location.
