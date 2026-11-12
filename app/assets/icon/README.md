# SabkiJeb app icon (#203)

`sabkijeb-logo.png` is the master: the owner's 1254×1254 RGB logo (cream
check with a marigold tip in a jade pocket, on deep forest green), committed
losslessly as supplied. It is full bleed: it brings its own background.

Regenerate from the repository root (Python 3, Pillow and NumPy):

```sh
python3 scripts/regenerate-app-icons.py
```

This runs `scripts/derive-app-icon.py --full-bleed --margin 0` and then
flutter_launcher_icons 0.14.4. The wrapper preserves native Xcode settings,
because flutter_launcher_icons also rewrites unrelated ASSETCATALOG boolean
settings when run directly.

What `--full-bleed` derives:

- `app-icon.png`: the logo at 1024, opaque RGB, used for iOS (which applies
  its own mask) and the legacy Android mipmaps. `--margin` pads it with the
  background colour; it is 0 here.
- Adaptive background: the logo's border median, `#01351B`.
- `adaptive-foreground.png`: the check and pocket lifted off the background
  with colour-to-alpha against `#01351B`, so it recomposites over the adaptive
  background without a halo (asserted within 3/255 near the mark). Away from
  the mark only lighter pixels count, so the vignette stays behind and the
  glow is kept. The whole cutout, glow included, fits a centred circle of
  66% diameter.
- `monochrome.png`: the solid check-and-pocket silhouette in white, without
  the glow, at the same scale, for Android themed icons.
- `packages/core/assets/brand/sabkijeb_mark.png` (1x/2x/3x, 30pt): the whole
  logo clipped to a circle, the in-app mark on Home and the auth screens.

Optional iOS dark/tinted slots are omitted: flutter_launcher_icons 0.14.4's
appearance-aware catalog produces missing-required-iPhone/iPad-icon and
unassigned-child warnings in Xcode 27.2.

Without `--full-bleed`, the script keeps its #198 mode for the white-matte
`app-icon-v2.png` (geometric S). `owner-icon.png` and `opaque.png` are the
#192 artwork, kept because `scripts/site-icons.py` derives the website's Apple
touch icon from `opaque.png`. The website and the splash screen are not part
of #203.
