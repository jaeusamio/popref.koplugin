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
        checked_func = function() return G_reader_settings:nilOrTrue("popref_enabled") end,
        callback = function() G_reader_settings:flipNilOrTrue("popref_enabled") end,
    }
end

function PopRef:locate(src_page, dest_page, target)
    local doc = self.ui.document
    local info = Detect.textAt(doc:getPageTextBoxes(src_page), target, doc:getPageLinks(src_page))
    local kind, label, numbers, run = Detect.classify(info)
    local dims = doc:getNativePageDimensions(dest_page)
    local neighbor = dest_page < doc:getPageCount() and dest_page + 1 or dest_page - 1
    local page = doc._document:openPage(dest_page)
    local ink, free_ink = Render.inkMap(page, DrawContext.new(), dims.w, dims.h)
    page:close()
    local ok, region = pcall(Detect.region, doc:getPageTextBoxes(dest_page), { w = dims.w, h = dims.h },
        target.pos or {}, kind, label, {
            neighbor = neighbor >= 1 and doc:getPageTextBoxes(neighbor) or nil,
            numbers = numbers,
            run = run,
            source_y = src_page == dest_page and target.y0 or nil,
            next_page = dest_page < doc:getPageCount() and {
                lines = doc:getPageTextBoxes(dest_page + 1),
                page = doc:getNativePageDimensions(dest_page + 1),
            } or nil,
            ink = ink,
        })
    free_ink()
    if not ok then error(region) end
    logger.dbg("PopRef:", info, "->", kind, label, run, region)
    return region, kind, label, run
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

function PopRef:showPopup(link)
    local src_page = link.pos.page
    local dest_page = link.link.page + 1
    local ok, region, kind, label, run = pcall(self.locate, self, src_page, dest_page, link.link)
    if not ok then
        logger.warn("PopRef: failed to locate link target:", region)
        return false
    end
    if not region then return false end

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
        link_box = self.ui.view:pageToScreenTransform(src_page, doc:nativeToPageRectTransform(src_page, link.lbox)),
        goto_callback = function() self.ui.link:onGotoLink(link.link) end,
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
