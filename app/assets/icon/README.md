# Owner app icon (#198)

`app-icon-v2.png` is the master: the owner's 2576×2576 RGB artwork (geometric
S on white), saved losslessly from the supplied JPEG without other changes.
iOS and the legacy Android mipmaps use it as given, opaque, margins included;
iOS applies its own mask.

Regenerate from the repository root (Python 3, Pillow and NumPy):

```sh
python3 scripts/regenerate-app-icons.py
```

The wrapper preserves native Xcode settings: flutter_launcher_icons 0.14.4
also rewrites unrelated ASSETCATALOG boolean settings when run directly.

The derivation script removes the white matte without redrawing the S,
unmattes antialiased edges and asserts the result recomposites to the master.
It trims to the mark's bounds and fits it inside a centered circle of diameter
66% of the canvas (with a small resampling margin), so no launcher mask clips
its corners. The adaptive background is solid white. `monochrome.png` uses the
same alpha silhouette with white RGB for Android themed icons.

Optional iOS dark/tinted slots are omitted: flutter_launcher_icons 0.14.4's
appearance-aware catalog produces missing-required-iPhone/iPad-icon and
unassigned-child warnings in Xcode 27.2.

`owner-icon.png` and `opaque.png` are the previous (#192) gold-on-dark artwork,
kept only because `scripts/site-icons.py` derives the website's Apple touch
icon from `opaque.png`; the website is unchanged by #198. Splash and in-app
branding are also separate and unchanged.
