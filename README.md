# popref.koplugin

A [KOReader](https://github.com/koreader/koreader) plugin that shows a preview
popup of the referenced figure, table, algorithm, equation or citation when you
tap an internal link in a PDF, instead of jumping to its page.

Aimed at scientific papers, where following "see Fig. 3" or "[27]" and coming
back is the main friction of reading on an e-reader.

## Features

- Tapping an internal link opens a popup with the cropped target region: the
  figure or table with its caption, the equation, or the bibliography entries.
- Citation ranges and lists (`[3–7]`, `[12, 15]`) show all the cited entries.
- Targets spanning a column or page break are stitched together.
- Optional detection of references without links: tapping a plain-text
  "Figure 2", "Table 1", "Scheme 3" or a numbered citation finds the target by
  scanning the document.
- Among adjacent links (`[27], [28]`), the one closest to the tap is picked
  instead of always the left one.
- Popup buttons: **Close**, **Zoom** (full-screen image viewer) and **Go to**
  (the usual link jump).

Works with PDFs that have a text layer; reflow mode is not supported.

## Installation

Download `popref.koplugin-<version>.zip` from the
[latest release](https://github.com/jaeusamio/popref.koplugin/releases/latest),
extract it into KOReader's `plugins/` directory on your device, then restart
KOReader.

Alternatively, clone the repository into `plugins/`:

```sh
git clone https://github.com/jaeusamio/popref.koplugin.git
```

## Usage

The plugin is enabled by default. Settings live in the reader menu under
**Navigation > Reference popups**:

- **Show popups for links**: toggles the plugin.
- **Detect references without links**: also handle taps on unlinked figure,
  table and citation mentions (off by default).

## Development

- `popref_detect.lua`: target detection on MuPDF text lines; pure Lua, no
  KOReader dependencies.
- `popref_render.lua`: page rendering, cropping and stitching.
- `popref_widget.lua`: the popup.
- `main.lua`: KOReader integration (link hooks, menu, unlinked lookup).

Tests run against a set of real papers through KOReader's busted runner; see
[spec/README.md](spec/README.md).
