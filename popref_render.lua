local Blitbuffer = require("ffi/blitbuffer")

local Render = {}

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
