# Canvas reference renders

`scripts/render-canvas.sh` renders every `design/canvas/*.dc.html` artboard at
390x844 with a locally installed headless Chrome or Chromium. The committed
pixel references live in `390/`; they were rendered with Google Chrome
157.0.8103.39.

The canvas runtime's `./support.js` is not present in this repository. The
renderer therefore removes that one script tag from a temporary copy and
captures the remaining static HTML. It waits for `document.fonts.ready` and
checks that Figtree and IBM Plex Serif loaded before capture. These images do
not include behavior, runtime-injected content, platform chrome, Flutter text
rasterization, or native safe-area differences, so app golden comparisons may
show small anti-aliasing and platform-metric differences even when layout and
tokens match.

There are deliberately no 360x800 canvas references. Canvas artboards are
fixed at 390x844, so a 360x800 browser capture only crops the right and bottom
edges; it does not model Flutter reflow. At 360x800, app tests instead assert
that the screen has no overflow or clipping and preserves the 390 hierarchy.
The app's own 360 golden still detects regressions against the accepted compact
layout.

Run from any directory:

```sh
scripts/render-canvas.sh
```

Set `CHROME_BIN=/path/to/chrome` when Chrome is not in a standard location.
