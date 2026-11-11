# Owner website marks

`owner-white.png` and `owner-black.png` are the supplied transparent artwork,
kept unchanged. `scripts/site-icons.py` crops only transparent padding and
sizes them for the site's header and browser favicons. White is selected for
dark surfaces; black for light surfaces. Apple touch icons use the opaque
gold-on-dark app artwork instead.

The site image build runs this derivation through `scripts/site-images.py`.
The social card uses the white mark on its dark background. Embedded product
screenshots still faithfully show the current in-app branding.
