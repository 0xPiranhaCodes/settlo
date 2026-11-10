# 0014 Statements and exports: pdf on device, share_plus to share

## Status
Proposed (10 Nov 2026), with Download statement and export (#108).

## Context
Loan detail's **Download statement** and Profile › **Export** produce a loan statement PDF, and a space's expenses as CSV with a summary PDF, from what the user can already see (context pack; canvas Loan and Profile). They are made on the device, so nothing new is sent to a server, and handed to the system share sheet. The Flutter SDK cannot write a PDF or open the share sheet. `share_plus` is approved by [0001](0001-stack.md); a PDF library is not, and [0005](0005-dependency-policy.md) asks for an ADR. Neither was in the lockfile.

## Decision
- **`pdf`** (`^3.13.1`, Apache-2.0) in `packages/core`. Each document is first built as a plain `Statement` (facts, totals in paise, table rows marked counted or not), and then `statementPdf` lays it out (`lib/export/`). It is pure Dart: no native code and no platform channel. It brings in `barcode` (Apache-2.0), `bidi` (MIT), `qr` (BSD-3-Clause) and `path_parsing` (MIT); `archive`, `crypto`, `image` and `xml` were already in the lockfile. The PDF embeds the bundled Figtree and IBM Plex Serif ([0006](0006-fonts.md)), so ₹ and the type match the app and nothing is fetched.
- **`share_plus`** (`^13.3.1`, BSD-3-Clause) in `packages/platform`, behind `shareFilesProvider`, which tests override. It brings in `share_plus_platform_interface`, `cross_file` (BSD-3-Clause), `win32` and `ffi_leak_tracker` (BSD-3-Clause; Windows only, not built for iOS or Android). Exports are written as files, never in memory, to a private `exports/` folder in the app cache. That needs **`path_provider`** (`^2.1.6`, BSD-3-Clause) in `packages/platform`, which was already in the lockfile through `supabase_flutter`. Its tests fake `SharePlatform`, so `share_plus_platform_interface` is also a dev dependency of `packages/platform`; it is already in the lockfile.
- CSV is written by hand (RFC 4180 quoting, a UTF-8 byte order mark, CRLF). It needs about 20 lines, so no `csv` package.
- **Privacy.** Exports name people, never their numbers. A member known only by number appears as `Member n`, and a loan's other party as `The other party`. In every exported name and free-text field, a phone-like run (10 or more digits, allowing `+`, spaces and hyphens) is replaced by `••••`. This covers labels, the space name, descriptions, categories, references and dispute reasons. Amounts and dates are built by the export itself and are left alone.
- **Retention.** `exports/` holds nothing but exports. It is emptied before each export and at app start, and deleted at once when the user dismisses the share sheet. After a completed share the files stay until the next export or app start, because the receiving app may still be reading them.
- **Scripts the PDF fonts cannot draw.** The `pdf` package does not shape complex scripts, and Figtree has no Indic glyphs. So any text run the bundled font cannot cover, such as a Devanagari name, is laid out by Flutter's text engine on the UI isolate (`TextPainter`, which shapes it correctly). It is saved as a PNG at four times 10pt and placed inline as an image at the text's size. If drawing fails, the PDF shows `Name in another script`. The CSV always keeps the real text.
- **Off the UI isolate.** The CSV is streamed to its file line by line, and the PDF bytes are built in `Isolate.run`. The isolate gets plain data: the ledger, the `Statement`, the font bytes and the name images drawn beforehand. A 5,000-expense space is tested for page breaks and an unblocked UI isolate.

## Alternatives considered
- **`printing`** (same author as `pdf`). Its share and print sheet and its rasteriser need native plugins (pdfium on some platforms), and share_plus is already approved.
- **`syncfusion_flutter_pdf`.** Commercial licence terms.
- **Rendering with Flutter and saving an image.** The PDF would have no selectable text, and amounts could not be searched or copied.
- **Server-side generation (Edge Function).** It would send ledgers off the device, and would not work offline.

## Consequences
- 10 new packages in the lockfile. `pdf` adds roughly 1 MB of Dart to the app before tree shaking; share_plus adds a small native plugin on iOS and Android.
- **Tests check the `Statement`, not the rendered PDF:** rows, totals and disputed exclusion in paise, the IST stamp, and names only. A smoke test checks that the bytes are a PDF with the expected page count. The ubuntu-24.04 runner has no PDF rasteriser, and CI gets no new system packages, so there is no golden of a rendered page. Adding `poppler-utils` to CI would allow one later.
- A name drawn as an image cannot be selected or searched in the PDF; amounts and Latin text still can. The image always prints in the ink colour, even in a muted row.
- Tests register Noto Sans Devanagari (OFL 1.1, `app/test/fonts/`, test only), because the test engine has no system fonts. A Linux golden of the drawn name then shows real shaping.
