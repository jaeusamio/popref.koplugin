require("commonrequire")
local PLUGIN = "plugins/popref.koplugin/"
package.path = PLUGIN .. "?.lua;" .. package.path
local DocumentRegistry = require("document/documentregistry")
local lfs = require("libs/libkoreader-lfs")
local PopRef = dofile(PLUGIN .. "main.lua")
local Cases = dofile(PLUGIN .. "spec/popref_cases.lua")

local PAPERS_DIR = os.getenv("POPREF_PAPERS") or PLUGIN .. "example_papers"
local RECORD = os.getenv("POPREF_RECORD")
local PNG_DIR = os.getenv("POPREF_PNG")
local TOLERANCE = 3

local function paper_path(prefix)
    if lfs.attributes(PAPERS_DIR, "mode") ~= "directory" then return end
    for f in lfs.dir(PAPERS_DIR) do
        if f:sub(1, #prefix) == prefix and f:match("%.pdf$") then return PAPERS_DIR .. "/" .. f end
    end
end

local plugins = {}
local function open(paper)
    if plugins[paper] == nil then
        local path = paper_path(Cases.papers[paper])
        local doc = path and DocumentRegistry:openDocument(path)
        plugins[paper] = doc and PopRef:new{ ui = { document = doc, view = { state = {} } } } or false
    end
    return plugins[paper] or nil
end

local function round(v) return math.floor(v + 0.5) end

local function summary(dest, ref, region)
    local parts = {}
    for _, p in ipairs(region.parts or { region }) do
        table.insert(parts, { round(p.x), round(p.y), round(p.w), round(p.h), p.page_offset or 0 })
    end
    return {
        kind = ref.kind,
        label = ref.label,
        run = ref.run and #ref.run > 1 and table.concat(ref.run, ",") or nil,
        page = dest,
        region = region.kind,
        parts = parts,
    }
end

local function serialize(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local out = {}
    for _, x in ipairs(v) do table.insert(out, serialize(x)) end
    for _, k in ipairs({ "kind", "label", "run", "page", "region", "parts" }) do
        if v[k] ~= nil then table.insert(out, k .. " = " .. serialize(v[k])) end
    end
    return "{ " .. table.concat(out, ", ") .. " }"
end

local function matches(got, want)
    if not want or not got then return got == want end
    for _, k in ipairs({ "kind", "label", "run", "page", "region" }) do
        if got[k] ~= want[k] then return false end
    end
    if #got.parts ~= #want.parts then return false end
    for i, p in ipairs(got.parts) do
        for j = 1, 4 do
            if math.abs(p[j] - want.parts[i][j]) > TOLERANCE then return false end
        end
        if p[5] ~= want.parts[i][5] then return false end
    end
    return true
end

local function save_png(plugin, name, dest, region)
    if not PNG_DIR then return end
    local bb = plugin:render(dest, region, 2)
    bb:writePNG(PNG_DIR .. "/" .. name:gsub("[^%w]+", "_") .. ".png")
    bb:free()
end

local function check(name, c, got)
    if RECORD and not matches(got, c.expect) then
        print(name .. "\n    expect = " .. serialize(got) .. ",")
        return
    end
    assert.is_true(c.expect ~= nil, "no expectation, run with POPREF_RECORD=1")
    if not matches(got, c.expect) then
        assert.are.same(c.expect, got)
    end
end

local function find_word(doc, page, word, nth)
    local n = 0
    for _, l in ipairs(doc:getPageTextBoxes(page) or {}) do
        for _, w in ipairs(l) do
            if w.word:find(word, 1, true) then
                n = n + 1
                if n == (nth or 1) then return w end
            end
        end
    end
end

describe("PopRef plain-text references", function()
    for _, c in ipairs(Cases.taps) do
        local name = string.format("%s p%d %q #%d at %.2f", c.paper, c.page, c.word, c.nth or 1, c.at)
        it(name, function()
            local plugin = open(c.paper)
            if not plugin then return pending("missing paper " .. Cases.papers[c.paper]) end
            local w = find_word(plugin.ui.document, c.page, c.word, c.nth)
            assert.is_truthy(w, "word not found")
            local pos = { x = w.x0 + (w.x1 - w.x0) * c.at, y = (w.y0 + w.y1) / 2, page = c.page }
            local dest, ref = plugin:findUnlinked(pos)
            local got = false
            if dest then
                local region = plugin:locate(c.page, dest, {}, w.y0, ref)
                got = summary(dest, ref, region)
                save_png(plugin, name, dest, region)
            end
            check(name, c, got)
        end)
    end
end)

describe("PopRef links", function()
    for _, c in ipairs(Cases.links) do
        local name = string.format("%s p%d link %d", c.paper, c.page, c.link)
        it(name, function()
            local plugin = open(c.paper)
            if not plugin then return pending("missing paper " .. Cases.papers[c.paper]) end
            local doc = plugin.ui.document
            local links = {}
            for _, l in ipairs(doc:getPageLinks(c.page) or {}) do
                if l.page then table.insert(links, l) end
            end
            local link = links[c.link]
            assert.is_truthy(link, "link not found")
            local ref = plugin:linkRef(c.page, link)
            local dest = link.page + 1
            local region = plugin:locate(c.page, dest, link.pos or {}, link.y0, ref)
            save_png(plugin, name, dest, region)
            check(name, c, summary(dest, ref, region))
        end)
    end
end)
