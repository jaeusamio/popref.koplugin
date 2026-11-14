local CanvasContext = require("document/canvascontext")
local Device = require("device")
local DrawContext = require("ffi/drawcontext")
local Geom = require("ui/geometry")
local ImageViewer = require("ui/widget/imageviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Detect = require("popref_detect")
local PopRefWidget = require("popref_widget")
local Render = require("popref_render")
local Screen = Device.screen

Detect.debug = function(...) logger.dbg("PopRef:", ...) end

local KIND_NAMES = {
    figure = _("Figure"),
    table = _("Table"),
    algorithm = _("Algorithm"),
    equation = _("Equation"),
    citation = _("Reference"),
    section = _("Section"),
    note = _("Note"),
}

local PopRef = WidgetContainer:extend{
    name = "popref",
    is_doc_only = true,
}

function PopRef:init()
    if not self.ui.paging or not self.ui.link or not self.ui.document.getPageTextBoxes then return end
    self.ui.menu:registerToMainMenu(self)

    local orig_show_link_box = self.ui.link.showLinkBox
    self.ui.link.showLinkBox = function(reader_link, link, ...)
        if G_reader_settings:nilOrTrue("popref_enabled")
                and link and link.lbox and link.link and link.link.page
                and self:showPopup(link) then
            return true
        end
        return orig_show_link_box(reader_link, link, ...)
    end

    local orig_on_tap = self.ui.link.onTap
    self.ui.link.onTap = function(reader_link, arg, ges)
        if orig_on_tap(reader_link, arg, ges) then return true end
        if G_reader_settings:nilOrTrue("popref_enabled") and G_reader_settings:isTrue("popref_unlinked") then
            return self:showUnlinked(ges)
        end
    end

    -- KOReader takes the first link whose enlarged box contains the tap, so
    -- with adjacent links ("[27], [28]") the left one always wins. Prefer the
    -- link closest to the tap among those within reach.
    local doc = self.ui.document
    local orig_get_link = doc.getLinkFromPosition
    doc.getLinkFromPosition = function(d, pageno, pos)
        local link, lbox = orig_get_link(d, pageno, pos)
        if not link or d.configurable.text_wrap == 1 then return link, lbox end
        local best, best_dist
        for _, l in ipairs(d:getPageLinks(pageno) or {}) do
            local dx = math.max(l.x0 - pos.x, 0, pos.x - l.x1)
            local dy = math.max(l.y0 - pos.y, 0, pos.y - l.y1)
            if not best_dist or dx * dx + dy * dy < best_dist then
                best, best_dist = l, dx * dx + dy * dy
            end
        end
        if best == link then return link, lbox end
        local offset, len = CanvasContext:scaleBySize(5), CanvasContext:scaleBySize(10)
        return best, Geom:new{ x = best.x0 - offset, y = best.y0 - offset, w = best.x1 - best.x0 + len, h = best.y1 - best.y0 + len }
    end
end

function PopRef:addToMainMenu(menu_items)
    menu_items.popref = {
        text = _("Reference popups"),
        sorting_hint = "navi",
        sub_item_table = {
            {
                text = _("Show popups for links"),
                checked_func = function() return G_reader_settings:nilOrTrue("popref_enabled") end,
                callback = function() G_reader_settings:flipNilOrTrue("popref_enabled") end,
            },
            {
                text = _("Detect references without links"),
                help_text = _("Tapping a figure, scheme or table mention, or a numbered citation, shows a popup even when the document has no link there."),
                enabled_func = function() return G_reader_settings:nilOrTrue("popref_enabled") end,
                checked_func = function() return G_reader_settings:isTrue("popref_unlinked") end,
                callback = function() G_reader_settings:flipNilOrFalse("popref_unlinked") end,
            },
        },
    }
end

function PopRef:textBoxes(pageno)
    self.text_cache = self.text_cache or {}
    if not self.text_cache[pageno] then
        local doc = self.ui.document
        local page = doc._document:openPage(pageno)
        self.text_cache[pageno] = Render.visibleLines(page, doc:getPageTextBoxes(pageno) or {})
        page:close()
    end
    return self.text_cache[pageno]
end

function PopRef:locate(src_page, dest_page, dest, source_y, ref)
    local doc = self.ui.document
    local dims = doc:getNativePageDimensions(dest_page)
    local neighbor = dest_page < doc:getPageCount() and dest_page + 1 or dest_page - 1
    local page = doc._document:openPage(dest_page)
    local ink, free_ink = Render.inkMap(page, DrawContext.new(), dims.w, dims.h)
    page:close()
    local ok, region = pcall(Detect.region, self:textBoxes(dest_page), { w = dims.w, h = dims.h },
        dest, ref.kind, ref.label, {
            neighbor = neighbor >= 1 and self:textBoxes(neighbor) or nil,
            numbers = ref.numbers,
            run = ref.run,
            source_y = src_page == dest_page and source_y or nil,
            prev_page = dest_page > 1 and {
                lines = self:textBoxes(dest_page - 1),
                page = doc:getNativePageDimensions(dest_page - 1),
            } or nil,
            next_page = dest_page < doc:getPageCount() and {
                lines = self:textBoxes(dest_page + 1),
                page = doc:getNativePageDimensions(dest_page + 1),
            } or nil,
            ink = ink,
        })
    free_ink()
    if not ok then error(region) end
    logger.dbg("PopRef:", ref, region)
    return region
end

-- Size of the rendered region at zoom 1: parts are stacked vertically.
local function region_size(region)
    if not region.parts then return region.w, region.h end
    local w, h = 0, 0
    for _, p in ipairs(region.parts) do
        w, h = math.max(w, p.w), h + p.h
    end
    return w, h
end

function PopRef:render(pageno, region, zoom)
    local doc = self.ui.document
    local dc = DrawContext.new()
    local gamma = self.ui.view.state.gamma
    if gamma and gamma ~= doc.GAMMA_NO_GAMMA then
        dc:setGamma(gamma)
    end
    local bbs = {}
    for _, rect in ipairs(region.parts or { region }) do
        local page = doc._document:openPage(pageno + (rect.page_offset or 0))
        table.insert(bbs, Render.trim(Render.region(page, dc, rect, zoom), math.ceil(4 * zoom)))
        page:close()
    end
    return Render.stack(bbs, math.ceil(6 * zoom))
end

function PopRef:linkRef(src_page, link)
    local info = Detect.textAt(self:textBoxes(src_page), link, self.ui.document:getPageLinks(src_page))
    logger.dbg("PopRef:", info)
    local kind, label, numbers, run = Detect.classify(info)
    return { kind = kind, label = label, numbers = numbers, run = run }
end

function PopRef:showPopup(link)
    local src_page = link.pos.page
    local ok, ref = pcall(self.linkRef, self, src_page, link.link)
    if not ok then
        logger.warn("PopRef: failed to read link text:", ref)
        return false
    end
    return self:present(src_page, link.link.page + 1, link.link.pos or {}, link.lbox, ref,
        function() self.ui.link:onGotoLink(link.link) end)
end

-- Page of the caption or bibliography entry `ref` points to, scanning the
-- document: the first matching caption, the last page holding the entry.
function PopRef:findTarget(ref)
    local doc = self.ui.document
    local n = doc:getPageCount()
    if ref.kind == "citation" then
        local want = ref.run and ref.run[1] or tonumber(ref.numbers[1])
        if not want then return end
        for p = n, 1, -1 do
            local count, found = Detect.refEntries(doc:getPageTextBoxes(p), doc:getNativePageDimensions(p), want)
            if found and count >= 3 then
                ref.numbers = { want }
                return p
            end
        end
        return
    end
    for p = 1, n do
        if Detect.hasCaption(doc:getPageTextBoxes(p), doc:getNativePageDimensions(p), ref.kind, ref.label) then
            return p
        end
    end
end

function PopRef:findUnlinked(pos)
    local lines = self:textBoxes(pos.page)
    local line, k = Detect.wordAt(lines, pos)
    if not line then return end
    local page = self.ui.document._document:openPage(pos.page)
    local chars = Render.chars(page, line)
    page:close()
    local kind, label, numbers, run = Detect.refAt(line, k, pos.x, chars)
    if kind ~= "figure" and kind ~= "table" and kind ~= "algorithm" and kind ~= "citation" then return end
    local ref = { kind = kind, label = label, numbers = numbers, run = run }
    self.targets = self.targets or {}
    local key = kind .. "|" .. tostring(run and run[1] or label)
    if self.targets[key] == nil then
        local page_no = self:findTarget(ref)
        self.targets[key] = page_no and { page = page_no, numbers = ref.numbers } or false
    end
    local target = self.targets[key]
    if not target then return end
    ref.numbers = target.numbers
    local w = line[k]
    return target.page, ref, Geom:new{ x = w.x0, y = w.y0, w = w.x1 - w.x0, h = w.y1 - w.y0 }
end

function PopRef:showUnlinked(ges)
    if self.ui.document.configurable.text_wrap == 1 then return end
    local pos = self.ui.view:screenToPageTransform(ges.pos)
    if not pos then return end
    local ok, dest_page, ref, box = pcall(self.findUnlinked, self, pos)
    if not ok then
        logger.warn("PopRef: failed to detect reference:", dest_page)
        return
    end
    if not dest_page then return end
    return self:present(pos.page, dest_page, {}, box, ref,
        function() self.ui.link:onGotoLink({ page = dest_page - 1 }) end)
end

function PopRef:present(src_page, dest_page, dest, src_box, ref, goto_callback)
    local ok, region = pcall(self.locate, self, src_page, dest_page, dest, src_box.y, ref)
    if not ok then
        logger.warn("PopRef: failed to locate link target:", region)
        return false
    end
    if not region then return false end
    local kind, label, run = ref.kind, ref.label, ref.run

    local max_w, max_h = PopRefWidget.maxImageSize()
    local w, h = region_size(region)
    local zoom = math.min(max_w / w, max_h / h, 4)
    local doc = self.ui.document
    local name = KIND_NAMES[kind] or KIND_NAMES[region.kind]
    local title
    if region.count and run and region.count == #run then
        title = T(_("References %1–%2 – page %3"), run[1], run[#run], dest_page)
    elseif region.count then
        title = T(_("References – page %1"), dest_page)
    elseif name and label then
        title = T(_("%1 %2 – page %3"), name, label, dest_page)
    elseif name then
        title = T(_("%1 – page %2"), name, dest_page)
    else
        title = T(_("Page %1"), dest_page)
    end

    UIManager:show(PopRefWidget:new{
        title = title,
        image = self:render(dest_page, region, zoom),
        link_box = self.ui.view:pageToScreenTransform(src_page, doc:nativeToPageRectTransform(src_page, src_box)),
        goto_callback = goto_callback,
        zoom_callback = function() self:showZoomed(dest_page, region) end,
    })
    return true
end

function PopRef:showZoomed(pageno, region)
    local w, h = region_size(region)
    local zoom = 1.5 * math.min(Screen:getWidth() / w, Screen:getHeight() / h)
    local max_pixels = 8e6
    if w * h * zoom * zoom > max_pixels then
        zoom = math.sqrt(max_pixels / (w * h))
    end
    UIManager:show(ImageViewer:new{
        image = self:render(pageno, region, zoom),
        image_disposable = true,
        with_title_bar = false,
        fullscreen = true,
    })
end

return PopRef
