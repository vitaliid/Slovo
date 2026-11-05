# Design

The Claude Design mockup the interface is built from (Slovo_04 Part A). Exported
from claude.ai/design on 2026-11-05. Every size, colour and spacing in
`Presentation.Theme` and `Presentation.ChapterRtf` is taken from here; when the
code and these files disagree, the reason is written down in
`architecture/Slovo_04_Presentation_UI.md`.

| File | What it is |
|---|---|
| `slovo-reading-v2.standalone.html` | **The current mockup.** Opens in any browser, offline (fonts embedded). Use it to look. |
| `slovo-reading-v2.dc.html` | Source of v2: markup with inline CSS and the demo script. Use it to read exact values (search `max-width: 724px`). Needs `support.js` next to it. |
| `slovo-reading-v1.dc.html` | The earlier v1, kept for comparison. |
| `support.js` | Runtime of the `.dc.html` files. |
| `reference/early-concept-*.png` | The first concept screenshots given to the designer. Superseded by v2. |

Left out of the export: `Slovo - Читання.dc.html` (identical to v2) and
`export-v2.dc.html` (v2 with a thumbnail and without Google Fonts preconnects).

What is NOT carried into the program on purpose (Slovo_04 A.1, Part F): the
paper texture, IBM Plex Sans (Segoe UI instead), page markers in the left
margin (MVP puts `[71]` at the start of the paragraph), line height 1.72.
