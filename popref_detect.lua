--[[--
Locates the region of a PDF page that an internal link points to, using the
MuPDF text lines of the page. Pure logic: works on plain tables so it can be
tested outside KOReader.

Line format (PdfDocument:getPageTextBoxes): array of lines, each line an array
of words {word, x0, y0, x1, y1} plus its own x0, y0, x1, y1. Native page coords.
]]

local Detect = {
    debug = nil, -- optional function(...) receiving trace messages
}

local function dbg(...)
    if Detect.debug then Detect.debug(...) end
end

local CAPTION_KINDS = {
    fig = "figure", figure = "figure", scheme = "figure", chart = "figure", plate = "figure",
    tab = "table", table = "table",
    alg = "algorithm", algorithm = "algorithm", listing = "algorithm",
}

-- Order matters only for ties; the keyword closest to the link wins.
local KEYWORDS = {
    { "%f[%a]figs?%f[%A]", "figure" }, { "%f[%a]figures?%f[%A]", "figure" },
    { "%f[%a]schemes?%f[%A]", "figure" }, { "%f[%a]charts?%f[%A]", "figure" },
    { "%f[%a]tabs?%f[%A]", "table" }, { "%f[%a]tables?%f[%A]", "table" },
    { "%f[%a]algs?%f[%A]", "algorithm" }, { "%f[%a]algorithms?%f[%A]", "algorithm" },
    { "%f[%a]listings?%f[%A]", "algorithm" },
    { "%f[%a]eqs?%f[%A]", "equation" }, { "%f[%a]eqns?%f[%A]", "equation" }, { "%f[%a]equations?%f[%A]", "equation" },
    { "%f[%a]secs?%f[%A]", "section" }, { "%f[%a]sections?%f[%A]", "section" },
    { "%f[%a]chap%f[%A]", "section" }, { "%f[%a]chapters?%f[%A]", "section" },
    { "%f[%a]app%f[%A]", "section" }, { "%f[%a]appendix%f[%A]", "section" }, { "§", "section" },
    { "%f[%a]refs?%f[%A]", "citation" },
    { "%f[%a]thm%f[%A]", "generic" }, { "%f[%a]theorems?%f[%A]", "generic" }, { "%f[%a]lemmas?%f[%A]", "generic" },
    { "%f[%a]def%f[%A]", "generic" }, { "%f[%a]definitions?%f[%A]", "generic" },
    { "%f[%a]prop%f[%A]", "generic" }, { "%f[%a]propositions?%f[%A]", "generic" },
    { "%f[%a]cor%f[%A]", "generic" }, { "%f[%a]corollar[yi]e?s?%f[%A]", "generic" },
    { "%f[%a]remarks?%f[%A]", "generic" }, { "%f[%a]examples?%f[%A]", "generic" },
}

local REF_ENTRY_PATTERNS = { "^%[%d%d?%d?%]", "^%d%d?%d?%.%s", "^%(%d%d?%d?%)%s" }

local function finite(v)
    return type(v) == "number" and v == v and v > -1e6 and v < 1e6
end

local function median(t)
    if #t == 0 then return nil end
    table.sort(t)
    return t[math.ceil(#t / 2)]
end

local function line_text(line)
    if line.text then return line.text end
    local words = {}
    for _, w in ipairs(line) do
        table.insert(words, w.word)
    end
    line.text = table.concat(words, " ")
    return line.text
end

local function escape(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function base_label(s)
    return (s:lower():gsub("(%d)%a$", "%1"))
end

local function same_label(a, b)
    return a and b and base_label(a) == base_label(b)
end

-- "Figure 3: ...", "Fig. 3. ...", "TABLE II", "Fig. 3 Results ...", "Extended Data Fig. 2"
-- but not "Figure 3 shows ...".
local function parse_caption(text)
    text = text:gsub("^[Ee][Xx][Tt][Ee][Nn][Dd][Ee][Dd]%s+", ""):gsub("^[Dd][Aa][Tt][Aa]%s+", "")
    local kw, num, rest = text:match("^(%a+)%.?%s*(%w[%w%.]*)(.*)$")
    local kind = kw and CAPTION_KINDS[kw:lower()]
    if not kind or not num:match("^[%d%u]") then return end
    local dotted = num:match("%.$")
    num = num:gsub("%.$", "")
    if not (dotted or rest == "" or rest:match("^%s*[:|%-]") or rest:match("^%s*\226\128[\147\148]")
            or rest:match("^%s+%u")) then
        return
    end
    return kind, num
end

local function is_ref_entry(text)
    for _, p in ipairs(REF_ENTRY_PATTERNS) do
        if text:match(p) then return true end
    end
end

local DASHES = { "\226\128\147", "\226\128\148", "\226\136\146" } -- en dash, em dash, minus

local function normalize_dashes(text)
    for _, d in ipairs(DASHES) do
        text = text:gsub(d, "-")
    end
    return text
end

--- Integers cited by a group such as "[27, 28]", "[32–37]" or "5−9,12".
function Detect.citedNumbers(group)
    local out, seen = {}, {}
    local function add(n)
        if n < 1000 and not seen[n] then
            seen[n] = true
            table.insert(out, n)
        end
    end
    for item in normalize_dashes(group or ""):gmatch("[^,;]+") do
        local a, b = item:match("(%d+)%s*%-%s*(%d+)")
        a, b = tonumber(a), tonumber(b)
        if a and b and b > a and b - a <= 30 then
            for n = a, b do add(n) end
        else
            for n in item:gmatch("%d+") do add(tonumber(n)) end
        end
    end
    table.sort(out)
    return out
end

-- Consecutive run of `numbers` containing `n`, at most `max` long.
local function consecutive_run(numbers, n, max)
    local set = {}
    for _, v in ipairs(numbers) do set[v] = true end
    if not set[n] then return { n } end
    local lo, hi = n, n
    while set[lo - 1] and hi - lo + 1 < max do lo = lo - 1 end
    while set[hi + 1] and hi - lo + 1 < max do hi = hi + 1 end
    local run = {}
    for v = lo, hi do table.insert(run, v) end
    return run
end

local function norm_text(text)
    return (text:gsub("%d", ""):gsub("%s+", " "))
end

-- Drops rotated side text and running headers/footers (lines repeated at the
-- same height on a neighbouring page).
local function clean_lines(lines, page, neighbor)
    local heights = {}
    for _, l in ipairs(lines) do
        table.insert(heights, l.y1 - l.y0)
    end
    local lh = median(heights) or 10
    local repeated = {}
    for _, n in ipairs(neighbor or {}) do
        if n.y1 < page.h * 0.15 or n.y0 > page.h * 0.85 then
            table.insert(repeated, n)
        end
    end
    local kept = {}
    local top, bottom = page.h * 0.03, page.h * 0.97
    for _, l in ipairs(lines) do
        local h = l.y1 - l.y0
        local drop = h > 3 * lh
        if not drop and (l.y1 < page.h * 0.15 or l.y0 > page.h * 0.85) and not parse_caption(line_text(l)) then
            local t = norm_text(line_text(l))
            for _, n in ipairs(repeated) do
                if math.abs(n.y0 - l.y0) < 2 and norm_text(line_text(n)) == t then
                    drop = true
                    if l.y1 < page.h * 0.15 then
                        top = math.max(top, l.y1)
                    else
                        bottom = math.min(bottom, l.y0)
                    end
                    break
                end
            end
        end
        if not drop then table.insert(kept, l) end
    end
    return kept, lh, top, bottom
end

local function layout(lines, page, lh, top, bottom)
    local widths = {}
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, l in ipairs(lines) do
        local w = l.x1 - l.x0
        if w > page.w * 0.25 then table.insert(widths, w) end
        x0, y0 = math.min(x0, l.x0), math.min(y0, l.y0)
        x1, y1 = math.max(x1, l.x1), math.max(y1, l.y1)
    end
    local colw = median(widths) or page.w * 0.8
    return {
        colw = colw,
        two_col = colw < (x1 - x0) * 0.6,
        x0 = x0, y0 = y0, x1 = x1, y1 = y1,
        mid = (x0 + x1) / 2,
        lh = lh,
        -- page body limits, below running header and above footer
        top = top + lh * 0.3,
        bottom = bottom - lh * 0.3,
    }
end

local function column_of(lay, line, x)
    if not lay.two_col then return lay.x0, lay.x1 end
    local tol = lay.lh
    if line then
        if line.x1 <= lay.mid + tol then return lay.x0, lay.mid end
        if line.x0 >= lay.mid - tol then return lay.mid, lay.x1 end
        return lay.x0, lay.x1
    end
    if not x then return lay.x0, lay.x1 end
    if x < lay.mid then return lay.x0, lay.mid end
    return lay.mid, lay.x1
end

-- Merge lines of an x-range that share a baseline into rows.
local function build_rows(lines, cx0, cx1)
    local sel = {}
    for _, l in ipairs(lines) do
        local cx = (l.x0 + l.x1) / 2
        if cx >= cx0 and cx <= cx1 then table.insert(sel, l) end
    end
    table.sort(sel, function(a, b) return a.y0 < b.y0 end)
    local rows = {}
    for _, l in ipairs(sel) do
        local r = rows[#rows]
        local cy = (l.y0 + l.y1) / 2
        if r and cy >= r.y0 and cy <= r.y1 then
            table.insert(r.segs, l)
            r.x0, r.x1 = math.min(r.x0, l.x0), math.max(r.x1, l.x1)
            r.y0, r.y1 = math.min(r.y0, l.y0), math.max(r.y1, l.y1)
        else
            table.insert(rows, { segs = { l }, x0 = l.x0, y0 = l.y0, x1 = l.x1, y1 = l.y1 })
        end
    end
    for _, r in ipairs(rows) do
        table.sort(r.segs, function(a, b) return a.x0 < b.x0 end)
        local parts = {}
        for _, s in ipairs(r.segs) do
            table.insert(parts, line_text(s))
            if not r.caption and s.is_caption then r.caption = s end
        end
        r.text = table.concat(parts, " ")
    end
    return rows
end

-- Last row of the caption block starting at idx: following rows aligned with it.
local function caption_end(rows, idx, lay)
    local last = idx
    local x0 = rows[idx].caption and rows[idx].caption.x0 or rows[idx].x0
    while rows[last + 1] and last - idx < 15
            and rows[last + 1].y0 - rows[last].y1 < lay.lh * 0.8
            and math.abs(rows[last + 1].x0 - x0) < lay.lh
            and not rows[last + 1].caption do
        last = last + 1
    end
    return last
end

local function mark_captions(rows, lay)
    for i, r in ipairs(rows) do
        if r.caption then
            for j = i, caption_end(rows, i, lay) do
                rows[j].in_caption = i
            end
        end
    end
end

local function row_index(rows, line)
    for i, r in ipairs(rows) do
        for _, s in ipairs(r.segs) do
            if s == line then return i end
        end
    end
end

-- hyperref raises anchors by ~one baselineskip, so the target line is the
-- first one whose bottom lies clearly below the destination point.
local function first_row_below(rows, y, lh)
    for i, r in ipairs(rows) do
        if r.y1 > y + lh * 0.6 then return i end
    end
end

local function is_prose(row, lay)
    if row.in_caption then return false end
    for _, s in ipairs(row.segs) do
        if s.x1 - s.x0 >= lay.colw * 0.85 and s.y1 - s.y0 >= lay.lh * 0.9 then return true end
    end
end

-- Body paragraph = two consecutive prose rows with normal line spacing.
local function prose_pair(rows, i, j, lay)
    local a, b = rows[i], rows[j]
    return a and b and is_prose(a, lay) and is_prose(b, lay)
        and math.abs(b.y0 - a.y1) < lay.lh * 0.8
end

local function paragraph_end(rows, i, lay)
    while rows[i + 1] and rows[i + 1].y0 - rows[i].y1 < lay.lh * 0.8 and not rows[i + 1].in_caption do
        i = i + 1
    end
    return i
end

-- Bottom y of whatever bounds the float above row idx: body text or another caption.
local function boundary_up(rows, idx, lay)
    for i = idx - 1, 1, -1 do
        local r = rows[i]
        if r.in_caption and r.in_caption ~= rows[idx].in_caption then return r.y1 end
        if i > 1 and prose_pair(rows, i - 1, i, lay) then
            return rows[paragraph_end(rows, i, lay)].y1
        end
    end
end

-- Top y of whatever bounds the float below row idx. A paragraph glued to the
-- float and followed by a large gap is a float footnote, not body text.
local function boundary_down(rows, idx, lay)
    local i = idx + 1
    while rows[i] do
        local r = rows[i]
        if r.caption then return r.y0 end
        if prose_pair(rows, i, i + 1, lay) then
            local last = paragraph_end(rows, i, lay)
            local glued = r.y0 - rows[i - 1].y1 < lay.lh * 1.2 and not is_prose(rows[i - 1], lay)
            local detached = not rows[last + 1] or rows[last + 1].y0 - rows[last].y1 > lay.lh * 1.5
            if not (glued and detached) then return r.y0 end
            i = last
        end
        i = i + 1
    end
end

-- Whether the caption (with its continuation lines) spans both columns.
local function caption_spans(lines, cap, lay)
    if not lay.two_col then return true end
    local bottom = cap.y1
    for _ = 1, 4 do
        local found
        for _, l in ipairs(lines) do
            local cy = (l.y0 + l.y1) / 2
            -- "FIGURE 1 | text..." where the label is a separate short line
            local same_row = cap.x1 - cap.x0 < lay.colw * 0.5 and cy >= cap.y0 and cy <= cap.y1
                and l.x0 >= cap.x1 - 1 and l.x0 - cap.x1 < 3 * lay.lh
            local next_row = l.y0 > bottom - 0.3 * lay.lh and l.y0 < bottom + 0.8 * lay.lh
                and math.abs(l.x0 - cap.x0) < lay.lh
            if same_row or next_row then
                if l.x1 > lay.mid + lay.lh and cap.x0 < lay.mid - lay.lh then return true end
                if next_row then found = l end
            end
        end
        if not found then break end
        bottom = found.y1
    end
end

-- Walks from `from` towards `to` (either direction) over the ink rows of the
-- x-range. Returns the edge of the first blank band that comes after some ink
-- and separates us from another float: text rows beyond a gap of 2.2 lines,
-- or another caption beyond a gap of 1.2 lines (0.7 when the gap touches a
-- horizontal rule, which closes tables in many journals).
local function ink_split(ink, rows, own, cx0, cx1, from, to, lh)
    if not ink then return end
    local step = to > from and 1 or -1
    local profile = ink(cx0, math.min(from, to), cx1, math.max(from, to))
    local base = math.floor(math.min(from, to))
    local function cov(y) return profile[y - base] or 0 end
    local function is_rule(y)
        if not y then return false end
        for d = -1, 1 do
            local c = cov(y + d)
            if c >= 0.8 and cov(y + d - 3) < 0.5 and cov(y + d + 3) < 0.5 then return true end
        end
        return false
    end
    local seen_ink, blank_start, blank, last_ink = false, nil, 0, nil
    for y = math.floor(from), math.floor(to), step do
        if cov(y) > 0 then
            local ruled = is_rule(last_ink) or is_rule(y + step)
            if seen_ink and blank >= lh * (ruled and 0.7 or 1.2) then
                for i, r in ipairs(rows) do
                    local beyond = step > 0 and r.y0 >= y - 1 or step < 0 and r.y1 <= y + 1
                    local within = step > 0 and r.y0 < to or step < 0 and r.y1 > to
                    if beyond and (r.caption and i ~= own or within and blank >= lh * 2.2) then
                        return blank_start
                    end
                end
            end
            seen_ink, blank, last_ink = true, 0, y
        elseif seen_ink then
            if blank == 0 then blank_start = y end
            blank = blank + 1
        end
    end
end

local function float_region(lines, lay, cap, kind, dest, ink)
    local cx0, cx1 = column_of(lay, cap)
    if caption_spans(lines, cap, lay) then cx0, cx1 = lay.x0, lay.x1 end
    local rows = build_rows(lines, cx0, cx1)
    mark_captions(rows, lay)
    local cidx = row_index(rows, cap)
    local cap_last = caption_end(rows, cidx, lay)
    local cap_top, cap_bottom = rows[cidx].y0, rows[cap_last].y1
    local up = boundary_up(rows, cidx, lay)
    local down = boundary_down(rows, cap_last, lay)
    -- shifted inwards to cancel the outer padding added by Detect.region
    up = up and up + lay.lh * 0.6 or lay.top + lay.lh * 0.5
    down = down and down - lay.lh * 0.6 or lay.bottom - lay.lh * 0.5
    dbg("float", kind, "cols", cx0, cx1, "caption", cap_top, cap_bottom, "limits", up, down, "lh", lay.lh)
    local above = cap_top - up > 2 * lay.lh
    local below = down - cap_bottom > 2 * lay.lh
    local use_above
    if kind == "figure" then
        use_above = above or not below
    else
        use_above = above and not below
    end

    local top, bottom
    if use_above then
        top, bottom = up, cap_bottom
        if dest.y and dest.y < cap_top - 2 * lay.lh then
            top = math.max(top, dest.y)
        end
        local split = ink_split(ink, rows, cidx, cx0, cx1, cap_top - 2, top, lay.lh)
        dbg("above", top, "split", split)
        top = split or top
    elseif kind == "algorithm" then
        top = cap_top
        local last = cap_last
        while rows[last + 1] and rows[last + 1].y0 - rows[last].y1 < lay.lh * 1.5 and not rows[last + 1].caption do
            last = last + 1
        end
        bottom = rows[last].y1
    else
        top, bottom = cap_top, down
        bottom = ink_split(ink, rows, cidx, cx0, cx1, cap_bottom + 2, bottom, lay.lh) or bottom
    end

    -- A float in one column is really full width when the other column holds
    -- no body text next to it.
    if lay.two_col and (cx1 - cx0) < (lay.x1 - lay.x0) * 0.75 then
        local ox0, ox1 = lay.x0, lay.mid
        if cx0 < lay.mid - lay.lh then ox0, ox1 = lay.mid, lay.x1 end
        local other = build_rows(lines, ox0, ox1)
        mark_captions(other, lay)
        local reach = (lay.bottom - lay.top) * 0.25
        local prose
        for _, r in ipairs(other) do
            if r.y1 > top and r.y0 < bottom and is_prose(r, lay)
                    or r.caption and r.y1 > top - reach and r.y0 < bottom + reach then
                prose = true
                break
            end
        end
        if not prose then cx0, cx1 = lay.x0, lay.x1 end
    end
    return cx0, cx1, top, bottom
end

local function citation_region(rows, idx, lay)
    local first = rows[idx]
    local indent = lay.lh * 0.4
    local first_gap
    local hanging
    local last = idx
    for i = idx + 1, math.min(#rows, idx + 15) do
        local r, prev = rows[i], rows[i - 1]
        local gap = r.y0 - prev.y1
        if gap > lay.lh * 1.2 then break end
        if first_gap and gap > first_gap + lay.lh * 0.25 then break end
        local flush = r.x0 <= first.x0 + indent
        if flush and (hanging or is_ref_entry(r.text)) then break end
        if i == idx + 1 then
            first_gap = gap
            hanging = not flush
        end
        last = i
    end
    return first.y0, rows[last].y1
end

local function eq_number_pattern(label)
    return "%(%s*[%a%.]*%s*" .. escape(label) .. "%s*%)%s*$"
end

local function equation_region(rows, idx, label, lay)
    local last = idx
    if label then
        local pat = eq_number_pattern(label)
        for i = idx, math.min(#rows, idx + 8) do
            if rows[i].text:match(pat) then
                last = i
                break
            end
        end
    end
    return rows[idx].y0, rows[last].y1
end

local function generic_region(rows, idx, page)
    local top = rows[idx].y0
    local last = idx
    while rows[last + 1] and last - idx < 10 and rows[last + 1].y1 - top < page.h * 0.25 do
        last = last + 1
    end
    return top, rows[last].y1
end

-- "Figure 2A. Notably, ..." at the start of a body line is not a caption: it
-- follows a full-width line at normal line spacing.
local function mid_paragraph(lines, l, lay)
    local prev
    for _, p in ipairs(lines) do
        if p.y1 <= l.y0 + 1 and p.x0 < l.x1 and p.x1 > l.x0 and (not prev or p.y1 > prev.y1) then
            prev = p
        end
    end
    return prev and l.y0 - prev.y1 < lay.lh * 0.6 and prev.x1 - prev.x0 >= lay.colw * 0.85
end

local function mark_caption_lines(lines, lay)
    for _, l in ipairs(lines) do
        l.is_caption = parse_caption(line_text(l)) ~= nil and not mid_paragraph(lines, l, lay)
    end
end

local function find_caption(lines, kind, label, dest, lay)
    local best, best_score
    for _, l in ipairs(lines) do
        local ckind, num = parse_caption(line_text(l))
        if l.is_caption and (not kind or kind == ckind) and (not label or same_label(num, label)) then
            local score = 0
            if dest.y then
                local d = l.y0 - dest.y
                score = -(d < -2 * lay.lh and 500 - d or d * 0.1)
            end
            if not best_score or score > best_score then
                best, best_score = l, score
            end
        end
    end
    return best
end

local function closest_to(cands, dest)
    if not dest.y then return cands[1] end
    local best, best_d
    for _, l in ipairs(cands) do
        local d = math.abs(l.y0 - dest.y)
        if not best_d or d < best_d then best, best_d = l, d end
    end
    return best
end

local function entry_patterns(n)
    return { "^%[" .. n .. "%]", "^" .. n .. "%.%s", "^%(" .. n .. "%)" }
end

-- Bibliography entry for any of the numbers in the link text. A valid
-- destination wins over the label: with ranges like "18-21" the link text
-- may not tell which entry the link points to.
local function find_ref_entry(lines, numbers, dest, lay)
    local pats = {}
    for _, n in ipairs(numbers) do
        for _, p in ipairs(entry_patterns(n)) do table.insert(pats, p) end
    end
    local cx0, cx1 = column_of(lay, nil, dest.x)
    local cands, near = {}, {}
    for _, l in ipairs(lines) do
        local t = line_text(l)
        local cx = (l.x0 + l.x1) / 2
        if cx < cx0 or cx > cx1 then t = "" end
        for _, p in ipairs(pats) do
            if t:match(p) then
                table.insert(cands, l)
                break
            end
        end
        if dest.y and is_ref_entry(t) and l.y0 > dest.y - lay.lh and l.y0 < dest.y + 2.5 * lay.lh then
            table.insert(near, l)
        end
    end
    if not dest.y then
        -- prefer the last number of the link text, the usual citation anchor
        local last = numbers[#numbers]
        for _, l in ipairs(cands) do
            local t = line_text(l)
            for _, p in ipairs(entry_patterns(last)) do
                if t:match(p) then return l end
            end
        end
        return cands[1]
    end
    local best = closest_to(cands, dest)
    if best and math.abs(best.y0 - dest.y) < 3 * lay.lh then return best end
    return closest_to(near, dest)
end

local function column_key(lay, l)
    local col = lay.two_col and (l.x0 + l.x1) / 2 > lay.mid and 1 or 0
    return col * 1e5 + l.y0
end

-- Entry lines for each number, picking the match closest in reading order
-- to the entry that was located from the link itself (`known`, optional).
local function find_entries(lines, lay, numbers, known, known_n)
    local out = {}
    for _, n in ipairs(numbers) do
        if n == known_n then
            table.insert(out, known)
        else
            local best, best_d
            for _, l in ipairs(lines) do
                local t = line_text(l)
                for _, p in ipairs(entry_patterns(n)) do
                    if t:match(p) then
                        -- without a known entry, the first one in reading order
                        local d = known and math.abs(column_key(lay, l) - column_key(lay, known)) or column_key(lay, l)
                        if not best_d or d < best_d then best, best_d = l, d end
                        break
                    end
                end
            end
            if best then table.insert(out, best) end
        end
    end
    table.sort(out, function(a, b) return column_key(lay, a) < column_key(lay, b) end)
    return out
end

local function find_line(lines, pattern)
    for _, l in ipairs(lines) do
        if line_text(l):match(pattern) then return l end
    end
end

-- Table note "aThe same..." (at a line start or after a sentence). With the
-- marker on the same page, the closest note below it: notes follow their table.
local function find_note(lines, label, source_y)
    local best
    for _, l in ipairs(lines) do
        local t = line_text(l)
        if t:match("^" .. label .. "%s?%u") or t:match("%.%s" .. label .. "%u") then
            local below = source_y and l.y0 > source_y
            if not best or below and (not best.below or l.y0 < best.line.y0) then
                best = { line = l, below = below }
            end
        end
    end
    return best and best.line
end

-- Last row of the block starting at idx: rows closer than max_gap.
local function block_end(rows, idx, lay, max_gap, max_rows)
    local last = idx
    while rows[last + 1] and last - idx < max_rows and rows[last + 1].y0 - rows[last].y1 < max_gap do
        last = last + 1
    end
    return last
end

local function find_equation(lines, label, dest)
    local pat = eq_number_pattern(label)
    local cands = {}
    for _, l in ipairs(lines) do
        if line_text(l):match(pat) then table.insert(cands, l) end
    end
    return closest_to(cands, dest)
end

local function nearest_line(lines, dest, lay)
    if not dest.y then return end
    local cx0, cx1 = column_of(lay, nil, dest.x)
    local best
    for _, l in ipairs(lines) do
        local cx = (l.x0 + l.x1) / 2
        if cx >= cx0 and cx <= cx1 and l.y1 > dest.y + lay.lh * 0.6 and (not best or l.y0 < best.y0) then
            best = l
        end
    end
    return best
end

local function extract_label(text)
    local label
    for tok in text:gmatch("[%w%.]+") do
        local l = tok:match("^(%u?%d+[%.%d]*%a?)")
        if l then label = l:gsub("%.$", "") end
    end
    if label then return label end
    local last = text:match("([%w]+)[^%w]*$")
    if last and (last:match("^[IVXLC]+$") or last:match("^%u$")) then return last end
end

--[[--
Classifies the link from the text around it on the source page.

@param info from Detect.textAt
@treturn string kind: figure|table|algorithm|equation|section|citation|note|generic|nil
@treturn string label: "3", "A.2", "12"...
@treturn table all integers in the link text (citation ranges)
@treturn table|nil consecutive cited numbers around the link ("[32-37]", "[27, 28]")
]]
function Detect.classify(info)
    local lt = info.text or ""
    local ctx = ((info.before or "") .. " " .. lt):lower()
    local label = extract_label(lt)

    local numbers = {}
    for n in lt:gmatch("%d+") do table.insert(numbers, n) end
    local cited = Detect.citedNumbers(info.group or lt)
    local run = numbers[1] and consecutive_run(cited, tonumber(numbers[1]), 10) or nil
    if lt:match("^%s*%[") then return "citation", label, numbers, run end

    local kind, pos = nil, 0
    for _, kw in ipairs(KEYWORDS) do
        local from = 1
        while true do
            local s, e = ctx:find(kw[1], from)
            if not s then break end
            if s > pos then kind, pos = kw[2], s end
            from = e + 1
        end
    end
    if info.note then return "note", info.text, {} end
    if info.superscript then return "citation", label, numbers, run end
    if kind then return kind, label, numbers, kind == "citation" and run or nil end
    -- author-year: "Smith et al.", "Smith (2020)"
    if lt:match("%a%a") and (lt:match("%d%d%d%d") or lt:lower():match("et al")) or ctx:match("%[%s*[%w,%s]*$") then
        return "citation", label, numbers, run
    end
    if lt:match("^%s*%(") then return "equation", label, numbers end
    return nil, label, numbers, run
end

-- Cuts halfway to the neighbouring lines, line boxes may touch.
local function cut_to_neighbours(rows, top, bottom, lay)
    local m = lay.lh * 0.2
    local new_top, new_bottom = top - m, bottom + m
    for _, r in ipairs(rows) do
        if r.y1 <= top + 1 then new_top = math.max(new_top, (r.y1 + top) / 2) end
        if r.y0 >= bottom - 1 then new_bottom = math.min(new_bottom, (r.y0 + bottom) / 2) end
    end
    return new_top, new_bottom
end

local function entry_number(line)
    return tonumber(line_text(line):match("^[%[%(]?(%d+)"))
end

-- Rows at the top of the given column until the next entry starts: the tail
-- of an entry broken across columns or pages.
local function continuation_rows(lines, lay, cx0, cx1)
    local rows = build_rows(lines, cx0, cx1)
    local last = 0
    while rows[last + 1] and last < 10 and not is_ref_entry(rows[last + 1].text) do
        last = last + 1
    end
    if last > 0 then
        return rows, cut_to_neighbours(rows, rows[1].y0, rows[last].y1, lay)
    end
end

-- Bibliography entries of one page: one part per run of adjacent entries in a
-- column. An entry ending at the bottom of the left column continues at the
-- top of the right one. Returns the parts, tagged with `page_offset`, and
-- whether the last entry runs off the end of the page.
local function entries_parts(lines, lay, page, entries, page_offset)
    local parts = {}
    local pad = lay.lh * 0.5
    local spill = false
    local function add(x0, x1, top, bottom)
        x0, x1 = math.max(0, x0 - pad), math.min(page.w, x1 + pad)
        local last = parts[#parts]
        if last and last.x == x0 and top - (last.y + last.h) < lay.lh then
            last.h = math.max(last.h, bottom - last.y)
        else
            table.insert(parts, { x = x0, y = top, w = x1 - x0, h = bottom - top, page_offset = page_offset })
        end
    end
    for i, e in ipairs(entries) do
        local cx0, cx1 = column_of(lay, e)
        local rows = build_rows(lines, cx0, cx1)
        local top, bottom = citation_region(rows, row_index(rows, e), lay)
        local at_end = rows[#rows].y1 <= bottom + 1
        top, bottom = cut_to_neighbours(rows, top, bottom, lay)
        add(cx0, cx1, top, bottom)
        if at_end and lay.two_col and cx1 <= lay.mid + 1 then
            local next_rows, t, b = continuation_rows(lines, lay, lay.mid, lay.x1)
            if next_rows then add(lay.mid, lay.x1, t, b) end
        elseif at_end and i == #entries then
            spill = true
        end
    end
    return parts, spill
end

local function prepare(lines, page, neighbor)
    local lh, top, bottom
    lines, lh, top, bottom = clean_lines(lines or {}, page, neighbor)
    if #lines == 0 then return end
    local lay = layout(lines, page, lh, top, bottom)
    mark_caption_lines(lines, lay)
    return lines, lay
end

-- Entries of the run, continuing on the next page for the numbers that come
-- after the last one found on this page.
local function entries_region(lines, lay, page, run, anchor, next_page)
    local known_n = entry_number(anchor)
    local entries = #run > 1 and find_entries(lines, lay, run, anchor, known_n) or { anchor }
    local parts, spill = entries_parts(lines, lay, page, entries, 0)
    local count = #entries
    local last_n = entry_number(entries[#entries]) or known_n or 0
    local missing = {}
    for _, n in ipairs(run) do
        if n > last_n then table.insert(missing, n) end
    end
    if next_page and (spill or #missing > 0) then
        local nlines, nlay = prepare(next_page.lines, next_page.page, lines)
        if nlines then
            local cx0, cx1 = column_of(nlay, nil, nlay.x0)
            if spill then
                local rows, t, b = continuation_rows(nlines, nlay, cx0, cx1)
                if rows then
                    table.insert(parts, { x = math.max(0, cx0 - nlay.lh * 0.5), y = t,
                        w = cx1 - cx0 + nlay.lh, h = b - t, page_offset = 1 })
                end
            end
            if #missing > 0 then
                local first = find_entries(nlines, nlay, { missing[1] }, nil, nil)[1]
                if first then
                    local more = find_entries(nlines, nlay, missing, first, missing[1])
                    local nparts = entries_parts(nlines, nlay, next_page.page, more, 1)
                    for _, p in ipairs(nparts) do table.insert(parts, p) end
                    count = count + #more
                end
            end
        end
    end
    local first = parts[1]
    return { kind = "citation", x = first.x, y = first.y, w = first.w, h = first.h, parts = parts,
        count = count > 1 and count or nil }
end

--[[--
@param lines page text lines
@param page {w, h} native page size
@param dest {x, y} destination point (fields may be nil)
@param kind, label from Detect.classify
@param opts optional {
    neighbor = text lines of an adjacent page, used to drop running headers,
    numbers = integers of the link text (from Detect.classify),
    run = consecutive cited numbers to show together (from Detect.classify),
    next_page = {lines, page} of the following page, where a run of references may continue,
    source_y = y of the link when it is on the destination page itself,
    ink = function(x0, y0, x1, y1) -> {[y - floor(y0)] = fraction of the row covered by ink}, 1pt per row,
}
@treturn table|nil {kind, x, y, w, h} in native page coords, plus
    `parts` (list of rects to stack, each with `page_offset` 0 or 1 relative
    to the destination page) and `count` when several entries are shown
]]
function Detect.region(lines, page, dest, kind, label, opts)
    opts = opts or {}
    -- x=0 with y at the very top is how page-level destinations come out
    dest = {
        x = finite(dest.x) and dest.x > 0 and dest.x or nil,
        y = finite(dest.y) and dest.y > page.h * 0.05 and dest.y or nil,
    }
    local lh, top_limit, bottom_limit
    lines, lh, top_limit, bottom_limit = clean_lines(lines or {}, page, opts.neighbor)
    if #lines == 0 then
        local y = dest.y or 0
        return { kind = "generic", x = 0, y = y, w = page.w, h = dest.y and math.min(page.h * 0.35, page.h - y) or page.h }
    end
    local lay = layout(lines, page, lh, top_limit, bottom_limit)
    mark_caption_lines(lines, lay)
    local whole = { kind = "generic", x = lay.x0 - lh, y = lay.y0 - lh, w = lay.x1 - lay.x0 + 2 * lh, h = lay.y1 - lay.y0 + 2 * lh }

    local anchor
    if kind == "figure" or kind == "table" or kind == "algorithm" or not kind then
        local cap = (kind or label) and find_caption(lines, kind, label, dest, lay)
        if cap then
            anchor = cap
            kind = parse_caption(line_text(cap))
        elseif kind then
            kind = "generic"
        end
    end
    if not anchor and (kind == "citation" or not kind) then
        anchor = find_ref_entry(lines, opts.numbers or {}, dest, lay)
        if anchor then kind = "citation" end
    end
    if kind == "note" and label then
        anchor = find_note(lines, label, opts.source_y)
    end
    local numbered
    if not anchor and kind == "equation" and label then
        anchor = find_equation(lines, label, dest)
        numbered = anchor ~= nil
    end
    anchor = anchor or nearest_line(lines, dest, lay)
    if not anchor then return whole end
    if not kind then
        kind = is_ref_entry(line_text(anchor)) and "citation" or "generic"
    end

    local cx0, cx1, top, bottom
    if kind == "figure" or kind == "table" or kind == "algorithm" then
        cx0, cx1, top, bottom = float_region(lines, lay, anchor, kind, dest, opts.ink)
    else
        cx0, cx1 = column_of(lay, anchor)
        local rows = build_rows(lines, cx0, cx1)
        local idx = row_index(rows, anchor)
        if kind == "note" then
            top, bottom = rows[idx].y0, rows[block_end(rows, idx, lay, lay.lh * 0.8, 6)].y1
        elseif kind == "citation" then
            return entries_region(lines, lay, page, opts.run or {}, anchor, opts.next_page)
        elseif kind == "equation" then
            if numbered then
                -- multi-line displays: centred rows right above the numbered one
                while idx > 1 and rows[idx].y0 - rows[idx - 1].y1 < lay.lh * 0.8 and not is_prose(rows[idx - 1], lay)
                        and rows[idx - 1].x0 > cx0 + 2 * lay.lh do
                    idx = idx - 1
                end
            elseif dest.y then
                if anchor.y0 > dest.y + lay.lh then
                    idx = first_row_below(rows, dest.y, lay.lh) or idx
                end
                -- skip the lead-in line when the display with its number follows
                for i = idx, math.min(#rows, idx + 2) do
                    if rows[i].text:match("%(%s*[%a%.]*%s*[%w%.]+%s*%)%s*$") and not is_prose(rows[i], lay) then
                        idx = i
                        break
                    end
                end
            end
            top, bottom = equation_region(rows, idx, label, lay)
        else
            top, bottom = generic_region(rows, idx, page)
        end
        top, bottom = cut_to_neighbours(rows, top, bottom, lay)
    end

    local pad = lay.lh * 0.5
    -- text crops: stay clear of the neighbouring lines
    local pad_y = (kind == "figure" or kind == "table" or kind == "algorithm") and pad or 0
    local x0 = math.max(0, cx0 - pad)
    local x1 = math.min(page.w, cx1 + pad)
    local y0 = math.max(0, top - pad_y)
    local y1 = math.min(page.h, bottom + pad_y)
    if y1 - y0 < lay.lh then return whole end
    return { kind = kind, x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- Index range of the bracketed group ("[27," ... "28].") around words i..j.
local function bracket_group(words, i, j)
    local first, last
    for k = i, math.max(1, i - 5), -1 do
        local w = words[k].word
        if k < i and w:find("]", 1, true) then break end
        if w:find("[", 1, true) then first = k break end
    end
    for k = j, math.min(#words, j + 5) do
        local w = words[k].word
        if k > j and w:find("[", 1, true) then break end
        if w:find("]", 1, true) then last = k break end
    end
    return first, last
end

-- Links of the same row laid end to end with `rect` inside `word`, in reading
-- order: every number of a superscript group ("14b,15,16") has its own link.
local function link_chain(links, rect, word)
    local h = rect.y1 - rect.y0
    local row = {}
    for _, l in ipairs(links or {}) do
        if l.page and math.abs(l.y0 - rect.y0) < h * 0.3 and l.x0 >= word.x0 - 1 and l.x1 <= word.x1 + 1 then
            table.insert(row, l)
        end
    end
    table.sort(row, function(a, b) return a.x0 < b.x0 end)
    local ti
    for k, l in ipairs(row) do
        if math.abs(l.x0 - rect.x0) < 0.5 and math.abs(l.x1 - rect.x1) < 0.5 then ti = k end
    end
    if not ti then return 1, 1 end
    local lo, hi = ti, ti
    while row[lo - 1] and row[lo].x0 - row[lo - 1].x1 < h * 0.6 do lo = lo - 1 end
    while row[hi + 1] and row[hi + 1].x0 - row[hi].x1 < h * 0.6 do hi = hi + 1 end
    return hi - lo + 1, ti - lo + 1
end

-- Superscript citations sit inside a word ("reactions.5−9", "1d,14b,15,16"):
-- the trailing items of the word, one per link of the chain (two for a
-- range), are the cited labels. Returns the cited group, the tapped label and
-- the text before the group.
local function superscript_at(word, rect, links)
    local text = normalize_dashes(word.word)
    local trailing = text:match("[%)%.;:,]*$")
    text = text:sub(1, #text - #trailing)
    -- table note marker after a value ("2068.9a"): only the letters are linked
    local note = text:match("%d%.%d+(%l+)$")
    if note then return note, note, text:sub(1, #text - #note), true end
    -- a link about one character wide over trailing lowercase letters ("175e",
    -- "LAuCla") is a note marker; a citation link covers the digits too ("10a")
    local cw = (word.y1 - word.y0) * 0.33
    local mid_from_end = (word.x1 - (rect.x0 + rect.x1) / 2) / cw - #trailing
    local letters = text:match("(%l+)$")
    if letters and mid_from_end + (rect.x1 - rect.x0) / cw / 2 <= #letters + 0.3 then
        local k = math.max(1, math.min(#letters, math.ceil(mid_from_end)))
        local letter = text:sub(#text - k + 1, #text - k + 1)
        return letter, letter, text:sub(1, #text - k), true
    end
    local n_links, tapped_index = link_chain(links, rect, word)

    local items = {}
    for pos, item in text:gmatch("()([^,]+)") do
        table.insert(items, { pos = pos, text = item })
    end
    local labels, used, start = {}, {}, nil
    for k = #items, 1, -1 do
        local item = items[k]
        local a, b = item.text:match("(%d+%a?)%s*%-%s*(%d+%a?)$")
        local label = not a and item.text:match("(%d+%a?)$")
        if not a and not label then break end
        if a then
            table.insert(labels, 1, b)
            table.insert(labels, 1, a)
            table.insert(used, 1, a .. "-" .. b)
            start = item.pos + item.text:find(a, 1, true) - 1
        else
            table.insert(labels, 1, label)
            table.insert(used, 1, label)
            start = item.pos + #item.text - #label
        end
        if #labels >= n_links then break end
    end
    if #labels == 0 then return end

    -- superscript digit width ~ a third of the line height
    local from_end = (word.x1 - (rect.x0 + rect.x1) / 2) / ((word.y1 - word.y0) * 0.33) - #trailing
    -- the link is over the start of the word ("2)" of "2).18"), not the superscript
    if from_end > #text - start + 2 then return end
    local tapped = labels[#labels - n_links + tapped_index] or labels[#labels]
    return table.concat(used, ","), tapped, text:sub(1, start - 1)
end

--[[--
Text around a link on its source page.

@param lines text lines of the page
@param rect the link
@param links all links of the page (optional), to resolve superscript groups

@treturn table {
    text = words covered by the link,
    before = up to two words preceding it,
    group = the whole citation group around it ("[27, 28]", "5-9"),
    superscript = true when the link sits inside a word (superscript citation),
    note = true for a table note marker ("2068.9a"),
}
]]
function Detect.textAt(lines, rect, links)
    local info = { text = "", before = "", group = "" }
    if not lines then return info end
    local hit, before, partial, partial_before = {}, nil, nil, nil
    -- how much of the link box each word covers: a superscript link overlaps
    -- the line above as well, the word it really belongs to covers it most
    local link_area = math.max(1, (rect.x1 - rect.x0) * (rect.y1 - rect.y0))
    local partial_cover = 0
    for _, l in ipairs(lines) do
        if l.y1 >= rect.y0 and l.y0 <= rect.y1 then
            local first, last
            for k, w in ipairs(l) do
                local ix = math.min(w.x1, rect.x1) - math.max(w.x0, rect.x0)
                local iy = math.min(w.y1, rect.y1) - math.max(w.y0, rect.y0)
                local cover = math.max(0, ix) * math.max(0, iy) / link_area
                if ix > 0 and iy > 0 and cover > partial_cover then
                    partial, partial_cover = w, cover
                    partial_before = { l[k - 2] and l[k - 2].word or "", l[k - 1] and l[k - 1].word or "" }
                end
                if ix > (w.x1 - w.x0) * 0.4 and iy > (w.y1 - w.y0) * 0.4 then
                    if #hit == 0 then
                        before = { l[k - 2] and l[k - 2].word or "", l[k - 1] and l[k - 1].word or "" }
                        first = k
                    end
                    last = k
                    table.insert(hit, w.word)
                end
            end
            if first and info.group == "" then
                local gs, ge = bracket_group(l, first, last)
                if gs and ge then
                    local g = {}
                    for k = gs, ge do table.insert(g, l[k].word) end
                    info.group = table.concat(g, " ")
                end
            end
        end
    end
    local tail, tapped, prefix
    -- `partial` is the word covering most of the link; a link much narrower
    -- than it is a superscript inside the word
    if partial and rect.x1 - rect.x0 < (partial.x1 - partial.x0) * 0.6 then
        tail, tapped, prefix, info.note = superscript_at(partial, rect, links)
    end
    if #hit > 0 and not tail then
        info.text = table.concat(hit, " ")
        info.before = table.concat(before, " ")
        if info.group == "" then info.group = info.text end
        return info
    end
    if partial then
        if tail then
            info.text, info.group = tapped, tail
            info.before = table.concat(partial_before, " ") .. " " .. prefix
            -- a bare number group ("5–7," after "Figures") is not a superscript
            info.superscript = prefix ~= ""
        else
            info.text, info.group = partial.word, partial.word
            info.before = table.concat(partial_before, " ")
        end
    end
    return info
end

return Detect
