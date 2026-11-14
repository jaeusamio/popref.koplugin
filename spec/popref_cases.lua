-- Test cases for popref_spec.lua. Papers are matched by file name prefix in
-- example_papers/ (see spec/README.md for their DOIs).
--
-- taps: plain-text references, tapped at `at` (0..1) across the `nth` word
--   of `page` containing `word`. expect = false: nothing must be detected.
-- links: the `link`-th internal link of `page`, as KOReader lists them.
--
-- expect = { kind, label, run, page, region, parts = { {x, y, w, h, page_offset}, ... } }
-- Rects are native page coords, compared with a tolerance of a few points.
-- Run with POPREF_RECORD=1 to print the current results of cases without
-- an expectation or not matching it.

return {
    papers = {
        dahl = "Dahl and Jensen - 2026",
        gibb = "Gibb - 2026",
        hoque = "Hoque and Glorius - PRISM",
        masaoka = "Masaoka et al. - 2026",
        muellers = "Muellers et al. - 2026",
        reynolds = "Reynolds - 2025",
        wanyan = "Wanyan et al. - 2023",
    },

    taps = {
        -- RSC: superscript citations, "Fig. 1B", "1 A. Author" bibliography
        { paper = "dahl", page = 1, word = "1A).", at = 0.3,
            expect = { kind = "figure", label = "1A", page = 1, region = "figure", parts = { { 293, 482, 268, 250, 0 } } } },
        { paper = "dahl", page = 1, word = "1B).13", at = 0.2,
            expect = { kind = "figure", label = "1B", page = 1, region = "figure", parts = { { 293, 482, 268, 250, 0 } } } },
        { paper = "dahl", page = 1, word = "1B).13", at = 0.9,
            expect = { kind = "citation", label = "13", page = 10, region = "citation", parts = { { 38, 132, 264, 24, 0 } } } },
        { paper = "dahl", page = 1, word = "platforms,20", at = 0.95,
            expect = { kind = "citation", label = "20", run = "20,21,22,23,24", page = 10, region = "citation", parts = { { 38, 407, 264, 167, 0 } } } },
        { paper = "dahl", page = 1, word = "platforms,20", at = 0.3, expect = false },
        { paper = "dahl", page = 1, word = "24", at = 0.5,
            expect = { kind = "citation", label = "24", run = "20,21,22,23,24", page = 10, region = "citation", parts = { { 38, 407, 264, 167, 0 } } } },
        { paper = "dahl", page = 2, word = "Table", at = 0.5,
            expect = { kind = "table", label = "1", page = 3, region = "table", parts = { { 35, 45, 526, 438, 0 } } } },
        { paper = "dahl", page = 5, word = "2A).113", at = 0.9,
            expect = { kind = "citation", label = "113", page = 12, region = "citation", parts = { { 295, 682, 262, 36, 0 } } } },
        { paper = "dahl", page = 6, word = "3A", at = 0.3,
            expect = { kind = "figure", label = "3A", page = 7, region = "figure", parts = { { 38, 35, 523, 555, 0 } } } },
        { paper = "dahl", page = 6, word = "Fig.", nth = 2, at = 0.5,
            expect = { kind = "figure", label = "3B", page = 7, region = "figure", parts = { { 38, 35, 523, 555, 0 } } } },

        -- Nature, three columns: superscripts glued to words, sub/superscript chemistry
        { paper = "gibb", page = 1, word = "arsenic3", at = 0.95,
            expect = { kind = "citation", label = "3", page = 2, region = "citation", parts = { { 385, 651, 181, 16, 0 } } } },
        { paper = "gibb", page = 1, word = "arsenic3", at = 0.2, expect = false },
        { paper = "gibb", page = 1, word = "following4.", at = 0.9,
            expect = { kind = "citation", label = "4", page = 2, region = "citation", parts = { { 385, 667, 181, 8, 0 } } } },
        { paper = "gibb", page = 1, word = "(LUCA)5", at = 0.95,
            expect = { kind = "citation", label = "5", page = 2, region = "citation", parts = { { 385, 675, 181, 8, 0 } } } },
        { paper = "gibb", page = 1, word = "1).", at = 0.3,
            expect = { kind = "figure", label = "1", page = 1, region = "figure", parts = { { 207, 175, 364, 253, 0 } } } },
        { paper = "gibb", page = 1, word = "CaCl2.", at = 0.9, expect = false },
        { paper = "gibb", page = 1, word = "MgCl2,", at = 0.9, expect = false },
        { paper = "gibb", page = 1, word = "O2", at = 0.9, expect = false },
        { paper = "gibb", page = 1, word = "0.40", at = 0.5, expect = false },

        -- thesis: list of figures and appendix lines that look like captions
        { paper = "reynolds", page = 19, word = "Figure", at = 0.5,
            expect = { kind = "figure", label = "1", page = 20, region = "figure", parts = { { 65, 54, 483, 278, 0 } } } },
        { paper = "reynolds", page = 20, word = "Figure", at = 0.5,
            expect = { kind = "figure", label = "1", page = 20, region = "figure", parts = { { 65, 54, 483, 278, 0 } } } },
        { paper = "reynolds", page = 10, word = "[4].", at = 0.5,
            expect = { kind = "citation", label = "4", page = 27, region = "citation", parts = { { 77, 339, 462, 81, 0 } } } },

        -- IEEE: "[1]– [4]" and "[8], [9]" groups, "Fig. N." captions
        { paper = "wanyan", page = 1, word = "[1]–", at = 0.5,
            expect = { kind = "citation", label = "1", run = "1,2,3,4", page = 8, region = "citation", parts = { { 54, 438, 248, 133, 0 } } } },
        { paper = "wanyan", page = 2, word = "Fig.", at = 0.5,
            expect = { kind = "figure", label = "2", page = 2, region = "figure", parts = { { 53, 28, 490, 317, 0 } } } },
        { paper = "wanyan", page = 2, word = "[8],", at = 0.5,
            expect = { kind = "citation", label = "8", run = "8,9", page = 8, region = "citation", parts = { { 54, 653, 248, 34, 0 }, { 305, 72, 238, 25, 0 } } } },
        { paper = "wanyan", page = 2, word = "[9].", at = 0.5,
            expect = { kind = "citation", label = "9", run = "8,9", page = 8, region = "citation", parts = { { 54, 653, 248, 34, 0 }, { 305, 72, 238, 25, 0 } } } },
        { paper = "wanyan", page = 3, word = "[18]–", at = 0.5,
            expect = { kind = "citation", label = "18", run = "18,19,20,21", page = 8, region = "citation", parts = { { 301, 337, 242, 124, 0 } } } },
        { paper = "wanyan", page = 6, word = "5,", at = 0.5,
            expect = { kind = "figure", label = "5", page = 6, region = "figure", parts = { { 53, 81, 249, 270, 0 } } } },
        { paper = "wanyan", page = 1, word = "2023", at = 0.5, expect = false },
    },

    links = {
        -- references in the third column of a three-column page
        { paper = "gibb", page = 1, link = 1,
            expect = { kind = "citation", label = "1", page = 2, region = "citation", parts = { { 385, 627, 181, 16, 0 } } } },
        { paper = "gibb", page = 1, link = 3,
            expect = { kind = "citation", label = "3", page = 2, region = "citation", parts = { { 385, 651, 181, 16, 0 } } } },
        { paper = "gibb", page = 2, link = 3,
            expect = { kind = "citation", label = "9", page = 2, region = "citation", parts = { { 385, 706, 181, 41, 0 } } } },

        { paper = "reynolds", page = 7, link = 6,
            expect = { kind = "figure", label = "A1", page = 30, region = "figure", parts = { { 66, 116, 413, 294, 0 } } } },
        { paper = "reynolds", page = 7, link = 7,
            expect = { kind = "figure", label = "A2", page = 30, region = "figure", parts = { { 66, 406, 413, 311, 0 } } } },
        { paper = "reynolds", page = 9, link = 3,
            expect = { kind = "citation", label = "10", page = 28, region = "citation", parts = { { 83, 132, 461, 60, 0 } } } },
        { paper = "reynolds", page = 9, link = 5,
            expect = { kind = "citation", label = "3", run = "3,4", page = 27, region = "citation", parts = { { 77, 256, 462, 163, 0 } } } },
        { paper = "reynolds", page = 17, link = 1,
            expect = { kind = "citation", label = "18", run = "18,19", page = 29, region = "citation", parts = { { 83, 70, 459, 143, 0 } } } },
        { paper = "reynolds", page = 17, link = 7,
            expect = { kind = "citation", label = "23", page = 29, region = "citation", parts = { { 83, 442, 459, 60, 0 } } } },

        -- Elsevier / Cell Press: superscript citations with destinations, "(Equation N)"
        -- full-width figure whose caption title line is in one column
        { paper = "muellers", page = 3, link = 17,
            expect = { kind = "figure", label = "1", page = 4, region = "figure", parts = { { 45, 98, 502, 384, 0 } } } },
        -- table with its footnote
        { paper = "muellers", page = 4, link = 8,
            expect = { kind = "table", label = "1", page = 5, region = "table", parts = { { 56, 102, 251, 237, 0 } } } },
        -- figure placed after a body line starting "Figure 2A."
        { paper = "muellers", page = 4, link = 9,
            expect = { kind = "figure", label = "2", page = 5, region = "figure", parts = { { 56, 412, 497, 315, 0 } } } },
        -- "(Figure 5; Table 2)": first link
        { paper = "muellers", page = 7, link = 8,
            expect = { kind = "figure", label = "5", page = 8, region = "figure", parts = { { 46, 98, 501, 359, 0 } } } },
        -- "(Figure 5; Table 2)": second link is the table
        { paper = "muellers", page = 7, link = 9,
            expect = { kind = "table", label = "2", page = 8, region = "table", parts = { { 46, 528, 255, 226, 0 } } } },
        -- "(Equation 1)" display
        { paper = "muellers", page = 9, link = 15,
            expect = { kind = "equation", label = "1", page = 10, region = "equation", parts = { { 49, 149, 253, 12, 0 } } } },
        -- unnumbered link text "Equation"
        { paper = "muellers", page = 9, link = 17,
            expect = { kind = "equation", page = 10, region = "equation", parts = { { 49, 196, 253, 12, 0 } } } },
        -- superscript group 6,7
        { paper = "muellers", page = 3, link = 3,
            expect = { kind = "citation", label = "6", run = "6,7", page = 11, region = "citation", parts = { { 309, 524, 245, 59, 0 } } } },
        -- superscript range 18-21 whose link points to 18
        { paper = "muellers", page = 3, link = 21,
            expect = { kind = "citation", label = "21", run = "18,19,20,21", page = 12, region = "citation", parts = { { 50, 308, 251, 122, 0 } } } },
        -- entry with a continuation line starting "3321."
        { paper = "muellers", page = 3, link = 10,
            expect = { kind = "citation", label = "12", run = "11,12", page = 12, region = "citation", parts = { { 305, 698, 249, 37, -1 }, { 50, 100, 251, 38, 0 } } } },
        -- superscript group 28,29 split across columns
        { paper = "muellers", page = 3, link = 28,
            expect = { kind = "citation", label = "28", run = "28,29", page = 12, region = "citation", parts = { { 50, 698, 251, 37, 0 }, { 298, 99, 249, 48, 0 } } } },

        -- Wiley: bracket groups, rotated side text, no destination positions (top of page)
        -- [1, 2]
        { paper = "hoque", page = 1, link = 1,
            expect = { kind = "citation", label = "2", run = "1,2", page = 13, region = "citation", parts = { { 306, 539, 257, 45, 0 } } } },
        -- figure at the top of a page with rotated side text
        { paper = "hoque", page = 2, link = 3,
            expect = { kind = "figure", label = "1A", page = 2, region = "figure", parts = { { 49, 27, 513, 406, 0 } } } },
        -- [8-15]
        { paper = "hoque", page = 2, link = 4,
            expect = { kind = "citation", label = "15", run = "8,9,10,11,12,13,14,15", page = 14, region = "citation", parts = { { 50, 74, 260, 318, 0 } } } },
        -- [27, 28]: one link for both numbers
        { paper = "hoque", page = 2, link = 13,
            expect = { kind = "citation", label = "28", run = "27,28", page = 14, region = "citation", parts = { { 307, 175, 255, 84, 0 } } } },
        -- [32-37]
        { paper = "hoque", page = 3, link = 1,
            expect = { kind = "citation", label = "37", run = "32,33,34,35,36,37", page = 14, region = "citation", parts = { { 307, 404, 255, 270, 0 } } } },
        -- [38-42]: 38 ends page 14, 39-42 on page 15
        { paper = "hoque", page = 3, link = 2,
            expect = { kind = "citation", label = "42", run = "38,39,40,41,42", page = 14, region = "citation", parts = { { 307, 677, 255, 41, 0 }, { 50, 40, 260, 172, 1 } } } },
        -- figure above its caption
        { paper = "hoque", page = 3, link = 7,
            expect = { kind = "figure", label = "2A", page = 4, region = "figure", parts = { { 49, 27, 513, 307, 0 } } } },
        -- almost full-page figure
        { paper = "hoque", page = 3, link = 13,
            expect = { kind = "figure", label = "3A", page = 5, region = "figure", parts = { { 45, 27, 517, 640, 0 } } } },
        -- figure followed by tables on a page without body text
        { paper = "hoque", page = 4, link = 1,
            expect = { kind = "figure", label = "4A", page = 6, region = "figure", parts = { { 49, 27, 513, 219, 0 } } } },
        -- table bounded by the next table caption
        { paper = "hoque", page = 4, link = 8,
            expect = { kind = "table", label = "1", page = 6, region = "table", parts = { { 45, 258, 517, 290, 0 } } } },
        -- last table of the page
        { paper = "hoque", page = 4, link = 9,
            expect = { kind = "table", label = "2", page = 6, region = "table", parts = { { 45, 544, 521, 207, 0 } } } },
        -- Extended Table
        { paper = "hoque", page = 7, link = 1,
            expect = { kind = "table", label = "1", page = 7, region = "table", parts = { { 45, 267, 517, 485, 0 } } } },
        -- table in the right column
        { paper = "hoque", page = 8, link = 5,
            expect = { kind = "table", label = "3", page = 8, region = "table", parts = { { 302, 38, 261, 300, 0 } } } },
        -- [54-60]: entry 55 continues in the right column
        { paper = "hoque", page = 8, link = 11,
            expect = { kind = "citation", label = "60", run = "54,55,56,57,58,59,60", page = 15, region = "citation", parts = { { 50, 647, 260, 74, 0 }, { 302, 40, 260, 250, 0 } } } },
        -- table at the top of the page
        { paper = "hoque", page = 9, link = 4,
            expect = { kind = "table", label = "4", page = 9, region = "table", parts = { { 45, 38, 517, 184, 0 } } } },

        -- ACS: page-only destinations, superscript groups with letters, table notes
        -- page-level destinations: figure found by label
        { paper = "masaoka", page = 1, link = 3,
            expect = { kind = "figure", label = "1", page = 1, region = "figure", parts = { { 46, 557, 262, 190, 0 } } } },
        -- Scheme spanning both columns
        { paper = "masaoka", page = 1, link = 5,
            expect = { kind = "figure", label = "1", page = 2, region = "figure", parts = { { 46, 56, 514, 297, 0 } } } },
        -- Scheme with the caption above
        { paper = "masaoka", page = 3, link = 1,
            expect = { kind = "figure", page = 3, region = "figure", parts = { { 46, 111, 262, 63, 0 } } } },
        -- table followed by a figure in the same column
        { paper = "masaoka", page = 3, link = 4,
            expect = { kind = "table", label = "1", page = 3, region = "table", parts = { { 46, 268, 262, 144, 0 } } } },
        -- figure below a table and its notes
        { paper = "masaoka", page = 3, link = 5,
            expect = { kind = "figure", label = "3", page = 3, region = "figure", parts = { { 46, 430, 262, 109, 0 } } } },
        -- table closed by a rule right above a figure
        { paper = "masaoka", page = 3, link = 14,
            expect = { kind = "table", label = "2", page = 4, region = "table", parts = { { 47, 55, 262, 171, 0 } } } },
        -- figure right below a table
        { paper = "masaoka", page = 3, link = 18,
            expect = { kind = "figure", label = "4", page = 4, region = "figure", parts = { { 47, 224, 262, 172, 0 } } } },
        -- figure in the right column next to another figure
        { paper = "masaoka", page = 5, link = 4,
            expect = { kind = "figure", label = "8", page = 5, region = "figure", parts = { { 298, 52, 262, 144, 0 } } } },
        -- figure with labels inside
        { paper = "masaoka", page = 5, link = 15,
            expect = { kind = "figure", label = "9", page = 6, region = "figure", parts = { { 43, 244, 264, 126, 0 } } } },
        -- full-width table
        { paper = "masaoka", page = 6, link = 2,
            expect = { kind = "table", label = "4", page = 6, region = "table", parts = { { 47, 555, 516, 178, 0 } } } },
        -- "Figures 5-7" is not a superscript
        { paper = "masaoka", page = 4, link = 5,
            expect = { kind = "figure", label = "7", page = 5, region = "figure", parts = { { 42, 52, 266, 275, 0 } } } },
        -- "eq 2" without destination
        { paper = "masaoka", page = 3, link = 22,
            expect = { kind = "equation", label = "2", page = 4, region = "equation", parts = { { 47, 431, 262, 18, 0 } } } },
        -- superscript range 5-9
        { paper = "masaoka", page = 2, link = 8,
            expect = { kind = "citation", label = "5", run = "5,6,7,8,9", page = 9, region = "citation", parts = { { 47, 455, 261, 160, 0 }, { 47, 645, 261, 111, 0 }, { 310, 58, 250, 365, 0 } } } },
        -- superscript 14b in "1d,14b,15,16"
        { paper = "masaoka", page = 2, link = 18,
            expect = { kind = "citation", label = "14b", run = "14,15,16", page = 10, region = "citation", parts = { { 47, 121, 261, 256, 0 } } } },
        -- superscript 10b in "L.10b,12"
        { paper = "masaoka", page = 2, link = 23,
            expect = { kind = "citation", label = "10b", page = 9, region = "citation", parts = { { 310, 423, 250, 101, 0 } } } },
        -- "ref 12"
        { paper = "masaoka", page = 3, link = 13,
            expect = { kind = "citation", label = "12", page = 9, region = "citation", parts = { { 310, 624, 250, 30, 0 } } } },
        -- table note marker after a value "2068.9a"
        { paper = "masaoka", page = 3, link = 24,
            expect = { kind = "note", label = "a", page = 3, region = "note", parts = { { 46, 380, 262, 24, 0 } } } },
        -- table note of the second table on a page
        { paper = "masaoka", page = 6, link = 30,
            expect = { kind = "note", label = "c", page = 6, region = "note", parts = { { 47, 744, 512, 12, 0 } } } },
    },
}
