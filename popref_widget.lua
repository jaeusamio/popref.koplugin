local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local Screen = Device.screen

local PopRefWidget = InputContainer:extend{
    title = nil,
    image = nil, -- BlitBuffer, freed on close
    link_box = nil, -- screen Geom of the tapped link, popup avoids covering it
    goto_callback = nil,
    zoom_callback = nil,
}

function PopRefWidget.maxImageSize()
    local w = Screen:getWidth() - 2 * Screen:scaleBySize(8) - 2 * Size.border.window - 2 * Size.padding.default
    return w, math.floor(Screen:getHeight() * 0.55)
end

function PopRefWidget:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local inner_w = screen_w - 2 * Screen:scaleBySize(8) - 2 * Size.border.window

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.Tap = {
        GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h } },
    }

    local buttons = ButtonTable:new{
        width = inner_w,
        zero_sep = true,
        show_parent = self,
        buttons = { {
            { text = _("Close"), callback = function() self:onClose() end },
            { text = _("Zoom"), callback = function() self.zoom_callback() end },
            {
                text = _("Go to"),
                callback = function()
                    self:onClose()
                    self.goto_callback()
                end,
            },
        } },
    }

    self.image_widget = ImageWidget:new{
        image = self.image,
        image_disposable = false,
        original_in_nightmode = false,
    }

    local title = CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = Size.item.height_default },
        TextWidget:new{
            text = self.title,
            face = Font:getFace("x_smallinfofont"),
            max_width = inner_w - 2 * Size.padding.large,
        },
    }
    local separator = function()
        return LineWidget:new{ dimen = Geom:new{ w = inner_w, h = Size.line.thin }, background = Blitbuffer.COLOR_GRAY }
    end

    self.frame = FrameContainer:new{
        padding = 0,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            title,
            separator(),
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = self.image:getHeight() + 2 * Size.padding.default },
                self.image_widget,
            },
            separator(),
            buttons,
        },
    }

    local size = self.frame:getSize()
    local x = math.floor((screen_w - size.w) / 2)
    local margin = Screen:scaleBySize(8)
    local y
    local lb = self.link_box
    if lb and lb.y + lb.h + margin + size.h <= screen_h then
        y = lb.y + lb.h + margin
    elseif lb and lb.y - margin - size.h >= 0 then
        y = lb.y - margin - size.h
    elseif lb and lb.y < screen_h / 2 then
        y = screen_h - size.h
    else
        y = 0
    end
    self.region = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self.frame.overlap_offset = { x, y }
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        self.frame,
    }
end

function PopRefWidget:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.region, true
    end)
    return true
end

function PopRefWidget:onCloseWidget()
    self.image_widget:free()
    if self.image then
        self.image:free()
        self.image = nil
    end
    UIManager:setDirty(nil, function()
        return "partial", self.region
    end)
end

function PopRefWidget:onTap(_, ges)
    if ges.pos:notIntersectWith(self.region) then
        return self:onClose()
    end
    if self.image_widget.dimen and ges.pos:intersectWith(self.image_widget.dimen) then
        self.zoom_callback()
    end
    return true
end

function PopRefWidget:onClose()
    UIManager:close(self)
    return true
end

return PopRefWidget
