# Owner app icon (#192)

`owner-icon.png` is the owner's unmodified 1024×1024 RGBA artwork.
The original is fully opaque, but carries an alpha channel. `opaque.png`
flattens it onto `#0A0B0D` and stores RGB for iOS/App Store compatibility.

Regenerate from the repository root (Python 3, Pillow and NumPy):

```sh
python3 scripts/derive-app-icon.py
(cd app && dart run flutter_launcher_icons)
```

The script removes the solid background without redrawing the S, unmattes
antialiased edges, and preserves its gold shading. The Android foreground
fits inside a centered circle of diameter 66% of the canvas (with a small
resampling margin). The launcher generator adds no further inset.
`monochrome.png` uses the same alpha silhouette with white RGB.

Optional iOS dark/tinted slots are omitted: flutter_launcher_icons 0.14.4's
appearance-aware catalog produces missing-required-iPhone/iPad-icon and
unassigned-child warnings in Xcode 27.2. The standard catalog includes every
legacy size, and the same opaque gold-on-dark art works in light and dark
home-screen modes. No hand-maintained catalog patch is required.

Splash and in-app branding remain separate and unchanged. Website icons use
the owner's separate white/black artwork under `design/brand/website/`.
