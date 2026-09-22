-- Icon-body geometry and paint shared by live buttons and config slots.
-- No root sizing, texture lookup, visibility, text hosting or runtime state.
local _, ST = ...
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local DEFAULT_BORDER = { 0, 0, 0, 1 }
local DEFAULT_BACKGROUND = { 0, 0, 0, 0.5 }

local function Layout(host, style)
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderMode = ST.GetBorderRenderMode(style)
    local inset = ST.GetEffectiveBorderLayoutSize(host, borderSize, borderMode)
    host.icon:ClearAllPoints()
    host.icon:SetPoint("TOPLEFT", inset, -inset)
    host.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function Paint(host, style, width, height)
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderMode = ST.GetBorderRenderMode(style)
    ApplyIconTexCoord(host.icon, width, height, style.iconZoom)
    -- Preview styles can contain partial color tables. Preserve their channel
    -- defaults without materializing values in the saved/effective style.
    local borderColor = type(style.borderColor) == "table" and style.borderColor or DEFAULT_BORDER
    local r, g, b, a = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0,
        borderColor[4] ~= nil and borderColor[4] or 1
    if host.borderTextures then
        ApplyBorderEdgePositions(host.borderTextures, host, borderSize, borderMode)
        for _, texture in ipairs(host.borderTextures) do
            texture:SetColorTexture(r, g, b, a)
        end
    end
    local background = type(style.backgroundColor) == "table" and style.backgroundColor or DEFAULT_BACKGROUND
    host.bg:SetColorTexture(background[1] or 0, background[2] or 0, background[3] or 0,
        background[4] ~= nil and background[4] or 0.5)
    -- Preview visibility is caller-owned; live paint must not unhide a border.
    return borderSize, borderMode, a
end

ST._IconVisuals = { Layout = Layout, Paint = Paint }
