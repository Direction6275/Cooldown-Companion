-- Bar-body presentation for caller-owned live buttons and preview slots.
-- Callers own size, visibility, text, timers, layers and interaction. Dimensions
-- describe this host, never a live frame inspected by a config preview.
local _, ST = ...
local Addon = ST.Addon
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord

local DEFAULT_BAR_COLOR = { 0.2, 0.6, 1.0, 1.0 }
local DEFAULT_BACKGROUND = { 0.1, 0.1, 0.1, 0.8 }
local DEFAULT_BORDER = { 0, 0, 0, 1 }

local function Apply(host, style, width, height)
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderMode = ST.GetBorderRenderMode(style)
    local inset = ST.GetEffectiveBorderLayoutSize(host, borderSize, borderMode)
    local showIcon = style.showBarIcon ~= false
    local vertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)
    local iconSize = (style.barIconSizeOverride and style.barIconSize) or style.barHeight or 20
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local iconArea = showIcon and (iconSize + iconOffset) or 0

    if showIcon then
        SetIconAreaPoints(host.icon, host, vertical, iconReverse, iconSize, inset)
        ApplyIconTexCoord(host.icon, iconSize, iconSize, style.iconZoom)
    end
    if host.iconBg then
        SetIconAreaPoints(host.iconBg, host, vertical, iconReverse, iconSize, 0)
    end
    if host._iconBounds then
        SetIconAreaPoints(host._iconBounds, host, vertical, iconReverse, iconSize, 0)
    end

    host.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(host.bg, host, vertical, iconReverse, iconArea, iconArea, 0)
    else
        host.bg:SetAllPoints()
    end
    if host._barBounds then
        host._barBounds:ClearAllPoints()
        if showIcon then
            SetBarAreaPoints(host._barBounds, host, vertical, iconReverse, iconArea, iconArea, 0)
        else
            host._barBounds:SetAllPoints()
        end
        host._barBounds._ccKitRectW = vertical and width or math.max(1, width - iconArea)
        host._barBounds._ccKitRectH = vertical and math.max(1, height - iconArea) or height
    end

    SetBarAreaPoints(host.statusBar, host, vertical, iconReverse, iconArea, iconArea, inset)
    host.statusBar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    host.statusBar:SetReverseFill(style.barReverseFill or false)
    host.statusBar:SetStatusBarTexture(Addon:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    host.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    if host.barTextFrame then
        SetBarAreaPoints(host.barTextFrame, host, vertical, iconReverse, iconArea, iconArea, inset)
    end

    local background = style.barBgColor or DEFAULT_BACKGROUND
    host.bg:SetColorTexture(background[1], background[2], background[3], background[4])
    if host.iconBg then
        host.iconBg:SetColorTexture(background[1], background[2], background[3], background[4])
    end
    local borderColor = style.borderColor or DEFAULT_BORDER
    if host.borderTextures then
        ApplyBorderEdgePositions(host.borderTextures, host._barBounds or host, borderSize, borderMode)
        for _, texture in ipairs(host.borderTextures) do
            texture:SetColorTexture(unpack(borderColor))
        end
    end
    if host.iconBorderTextures then
        ApplyBorderEdgePositions(host.iconBorderTextures, host._iconBounds, borderSize, borderMode)
        for _, texture in ipairs(host.iconBorderTextures) do
            texture:SetColorTexture(unpack(borderColor))
        end
    end
end

ST._BarVisuals = { Apply = Apply }
