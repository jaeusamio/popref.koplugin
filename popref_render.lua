local Blitbuffer = require("ffi/blitbuffer")
local ffi = require("ffi")
require("ffi/mupdf")
local W = ffi.loadlib("wrap-mupdf")

local Render = {}

local FZ_STEXT_CLIP = 64

-- Drops the text lines of a MuPDF page that are clipped away, such as a
-- whole other page embedded under a figure: getPageText reports them too.
function Render.visibleLines(page, lines)
    local opts = ffi.new("fz_stext_options")
    opts.flags = FZ_STEXT_CLIP
    local tp = W.mupdf_new_stext_page_from_page(page.ctx, page.page, opts)
    if tp == nil then return lines end
    -- chars bucketed by their left edge, which is also the left edge of the
    -- word they start in getPageText
    local chars = {}
    local block = tp.first_block
    while block ~= nil do
        if block.type == W.FZ_STEXT_BLOCK_TEXT then
            local l = block.u.t.first_line
            while l ~= nil do
                local ch = l.first_char
                while ch ~= nil do
                    local q = ch.quad
                    local x = math.min(q.ul.x, q.ll.x)
                    local k = math.floor(x)
                    chars[k] = chars[k] or {}
                    table.insert(chars[k], { x = x, y = (q.ul.y + q.ll.y + q.ur.y + q.lr.y) / 4 })
                    ch = ch.next
                end
                l = l.next
            end
        end
        block = block.next
    end
    W.fz_drop_stext_page(page.ctx, tp)
    local function visible(w)
        for k = math.floor(w.x0) - 1, math.floor(w.x0) + 1 do
            for _, c in ipairs(chars[k] or {}) do
                if math.abs(c.x - w.x0) < 0.05 and c.y > w.y0 and c.y < w.y1 then return true end
            end
        end
    end
    local out = {}
    for _, l in ipairs(lines) do
        local n = 0
        for _, w in ipairs(l) do
            if visible(w) then n = n + 1 end
        end
        if n * 2 >= #l then table.insert(out, l) end
    end
    return out
end

-- Renders a native-coords rect of a MuPDF page into a new BlitBuffer.
function Render.region(page, draw_context, rect, zoom)
    draw_context:setZoom(zoom)
    return page:draw_new(draw_context, math.ceil(rect.w * zoom), math.ceil(rect.h * zoom),
        math.floor(rect.x * zoom), math.floor(rect.y * zoom))
end

local function ink(bb, x, y)
    return bb:getPixel(x, y):getColor8().a < 200
end

-- Crops white margins, keeping `pad` pixels around the content. Frees bb if it
-- returns a new buffer.
function Render.trim(bb, pad)
    local w, h = bb:getWidth(), bb:getHeight()
    local step = 2
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1, step do
        for x = 0, w - 1, step do
            if ink(bb, x, y) then
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
            end
        end
    end
    if x1 < 0 then return bb end
    x0 = math.max(0, x0 - pad)
    y0 = math.max(0, y0 - pad)
    x1 = math.min(w - 1, x1 + step + pad)
    y1 = math.min(h - 1, y1 + step + pad)
    local nw, nh = x1 - x0 + 1, y1 - y0 + 1
    if nw >= w - 2 and nh >= h - 2 then return bb end
    local out = Blitbuffer.new(nw, nh, bb:getType())
    out:blitFrom(bb, 0, 0, x0, y0, nw, nh)
    bb:free()
    return out
end

-- Stacks buffers vertically on white, left aligned. Frees the inputs.
function Render.stack(bbs, gap)
    if #bbs == 1 then return bbs[1] end
    local w, h = 0, gap * (#bbs - 1)
    for _, b in ipairs(bbs) do
        w, h = math.max(w, b:getWidth()), h + b:getHeight()
    end
    local out = Blitbuffer.new(w, h, bbs[1]:getType())
    out:fill(Blitbuffer.COLOR_WHITE)
    local y = 0
    for _, b in ipairs(bbs) do
        out:blitFrom(b, 0, y, 0, 0, b:getWidth(), b:getHeight())
        y = y + b:getHeight() + gap
        b:free()
    end
    return out
end

-- Renders the whole page at 1px per point and returns the ink-coverage callback
-- expected by Detect.region, plus a function freeing the buffer.
function Render.inkMap(page, draw_context, w, h)
    draw_context:setZoom(1)
    local bb = page:draw_new(draw_context, math.ceil(w), math.ceil(h), 0, 0)
    local bw, bh = bb:getWidth(), bb:getHeight()
    local function rows(x0, y0, x1, y1)
        local out = {}
        local base = math.floor(y0)
        x0, x1 = math.max(0, math.floor(x0)), math.min(bw - 1, math.ceil(x1))
        local samples = math.floor((x1 - x0) / 2) + 1
        for y = math.max(0, base), math.min(bh - 1, math.ceil(y1)) do
            local n = 0
            for x = x0, x1, 2 do
                if ink(bb, x, y) then n = n + 1 end
            end
            if n > 0 then out[y - base] = n / samples end
        end
        return out
    end
    return rows, function() bb:free() end
end

return Render
