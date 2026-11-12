# Owner website mark

`sabkijeb-logo.png` is the owner's SabkiJeb logo (1254 x 1254, opaque), kept
unchanged. `scripts/site-icons.py` resizes it for the header mark, the browser
favicons (`site/favicon.ico` and `images/favicon.png`, with rounded corners)
and the opaque Apple touch icon. One mark serves light and dark pages.

The site image build runs this derivation through `scripts/site-images.py`,
which also places the mark on the social card.
