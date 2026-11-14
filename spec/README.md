# Tests

`popref_spec.lua` runs the detection on real papers: taps on plain-text
references and existing internal links, checked against the expectations in
`popref_cases.lua`. It uses KOReader's busted runner, so it needs a KOReader
checkout with the emulator built.

## Setup

1. Symlink the plugin into `<koreader>/plugins/` and the spec into
   `<koreader>/spec/unit/`:

   ```sh
   ln -s "$PWD" <koreader>/plugins/popref.koplugin
   ln -s "$PWD/spec/popref_spec.lua" <koreader>/spec/unit/popref_spec.lua
   ```

2. Put the papers below in `example_papers/` (gitignored). Each file name must
   start with the given prefix, as Zotero names them. Cases of missing papers
   are reported as pending. Another directory can be set with `POPREF_PAPERS`
   (relative to `<koreader>/koreader-emulator-*/koreader/` or absolute).

## Running

From `<koreader>`:

```sh
./kodev test front popref
```

Busted output goes to `base/build/<target>/spec/run/meson-logs/testlog.txt`.

- `POPREF_RECORD=1` prints, for each case without an expectation or not
  matching it, the current result as an `expect = {...}` line to paste into
  `popref_cases.lua`. Check the popup is right before pasting.
- `POPREF_PNG=<dir>` writes the popup image of each case to `<dir>`.

## Papers

| Prefix | Paper | DOI / source |
| --- | --- | --- |
| `Dahl and Jensen - 2026` | How to harness machine learning to make chemical kinetic models more predictive | [10.1039/d6dd00426a](https://doi.org/10.1039/d6dd00426a) |
| `Gibb - 2026` | How expansive and flexible is the matrix of life? | [10.1038/s41557-026-02276-6](https://doi.org/10.1038/s41557-026-02276-6) |
| `Hoque and Glorius - PRISM` | PRISM, a Bidirectional NMR Foundation Model From Peak List to Structure and Back | [10.1002/anie.7185622](https://doi.org/10.1002/anie.7185622) |
| `Masaoka et al. - 2026` | Estimating Effective Steric and Electronic Impacts of Bulky Aryl Groups in Organophosphine Ligands | [10.1021/acs.organomet.6c00373](https://doi.org/10.1021/acs.organomet.6c00373) |
| `Muellers et al. - 2026` | Using NMR to predict molecular reactivity | [10.1016/j.chempr.2026.103302](https://doi.org/10.1016/j.chempr.2026.103302) |
| `Reynolds - 2025` | Using Satellite Image Segmentation to Detect Trails (MSc thesis) | [research.ualr.edu/etd/1256](https://research.ualr.edu/etd/1256) |
| `Wanyan et al. - 2023` | Scalable Label-efficient Footpath Network Generation Using Remote Sensing Data and Self-supervised Learning | [10.1109/DICTA60407.2023.00027](https://doi.org/10.1109/DICTA60407.2023.00027) |
