--[[
    CooldownCompanion - Utils
    Shared constants, border helpers, color utilities, and config selection helpers
]]

local ADDON_NAME, ST = ...

local string_format = string.format
local tonumber = tonumber
local type = type

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ST.DEFAULT_OVERHANG_PCT = 32
ST.DEFAULT_GLOW_COLOR = {1, 1, 1, 1}
ST.DEFAULT_BG_COLOR = {0.2, 0.2, 0.2, 0.8}
ST.NUM_GLOW_STYLES = 3
ST.BORDER_RENDER_MODE_CUSTOM = "custom"
ST.BORDER_RENDER_MODE_CRISP = "crisp"

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
ST.EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top    (full width)
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom (full width)
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, -1,  1,  1}, -- Left   (inset to avoid corner overlap)
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, -1,  0,  1}, -- Right  (inset to avoid corner overlap)
}

--------------------------------------------------------------------------------
-- Border Helpers
--------------------------------------------------------------------------------

local BORDER_EDGE_NAMES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

function ST.GetBorderRenderMode(source, key)
    if type(source) == "table" then
        source = source[key or "borderRenderMode"]
    end
    if source == ST.BORDER_RENDER_MODE_CRISP then
        return ST.BORDER_RENDER_MODE_CRISP
    end
    return ST.BORDER_RENDER_MODE_CUSTOM
end

function ST.IsCrispBorderRenderMode(source, key)
    return ST.GetBorderRenderMode(source, key) == ST.BORDER_RENDER_MODE_CRISP
end

local function GetBorderSize(size, fallback)
    return tonumber(size) or fallback or 1
end

function ST.GetBorderLayoutSize(region, size, mode)
    if ST.IsCrispBorderRenderMode(mode)
        and PixelUtil and PixelUtil.GetNearestPixelSize
        and region and region.GetEffectiveScale then
        return PixelUtil.GetNearestPixelSize(1, region:GetEffectiveScale(), 1)
    end
    return GetBorderSize(size, 1)
end

local function GetEdgeTexture(textures, index)
    return textures[index] or textures[BORDER_EDGE_NAMES[index]]
end

function ST.CreateBorderTextureSet(parent, layer, sublevel)
    local textures = {}
    for index, side in ipairs(BORDER_EDGE_NAMES) do
        local tex = parent:CreateTexture(nil, layer or "OVERLAY", nil, sublevel)
        tex:SetColorTexture(0, 0, 0, 1)
        tex:Hide()
        textures[index] = tex
        textures[side] = tex
    end
    return textures
end

function ST.HideBorderTextures(textures)
    if not textures then return end
    for index = 1, 4 do
        local tex = GetEdgeTexture(textures, index)
        if tex then
            tex:Hide()
        end
    end
end

local function ApplyBorderPoint(tex, point, relativeTo, relativePoint, offsetX, offsetY, crisp)
    if crisp and PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(
            tex,
            point,
            relativeTo,
            relativePoint,
            offsetX,
            offsetY,
            offsetX ~= 0 and 1 or nil,
            offsetY ~= 0 and 1 or nil
        )
    else
        tex:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    end
end

function ST.PositionBorderTexturesBetween(textures, leftFrame, rightFrame, size, mode)
    if not (textures and leftFrame and rightFrame) then return end

    local crisp = ST.IsCrispBorderRenderMode(mode)
    local edgeSize = crisp and 1 or GetBorderSize(size, 1)

    for index, spec in ipairs(ST.EDGE_ANCHOR_SPEC) do
        local tex = GetEdgeTexture(textures, index)
        if tex then
            local firstFrame, secondFrame
            if index == 1 or index == 2 then
                firstFrame, secondFrame = leftFrame, rightFrame
            elseif index == 3 then
                firstFrame, secondFrame = leftFrame, leftFrame
            else
                firstFrame, secondFrame = rightFrame, rightFrame
            end

            tex:ClearAllPoints()
            ApplyBorderPoint(tex, spec[1], firstFrame, spec[2], spec[5] * edgeSize, spec[6] * edgeSize, crisp)
            ApplyBorderPoint(tex, spec[3], secondFrame, spec[4], spec[7] * edgeSize, spec[8] * edgeSize, crisp)
        end
    end
end

function ST.PositionBorderTextures(textures, frame, size, mode)
    ST.PositionBorderTexturesBetween(textures, frame, frame, size, mode)
end

function ST.ApplyBorderTexturesBetween(textures, leftFrame, rightFrame, color, size, mode)
    if not (textures and leftFrame and rightFrame) then return end

    if not ST.IsCrispBorderRenderMode(mode) and GetBorderSize(size, 1) <= 0 then
        ST.HideBorderTextures(textures)
        return
    end

    local r, g, b, a = 0, 0, 0, 1
    if color then
        r = color[1] or r
        g = color[2] or g
        b = color[3] or b
        if color[4] ~= nil then
            a = color[4]
        end
    end

    for index = 1, 4 do
        local tex = GetEdgeTexture(textures, index)
        if tex then
            tex:SetColorTexture(r, g, b, a)
        end
    end

    ST.PositionBorderTexturesBetween(textures, leftFrame, rightFrame, size, mode)

    for index = 1, 4 do
        local tex = GetEdgeTexture(textures, index)
        if tex then
            tex:Show()
        end
    end
end

function ST.ApplyBorderTextures(textures, frame, color, size, mode)
    ST.ApplyBorderTexturesBetween(textures, frame, frame, color, size, mode)
end

-- Create 4 one-physical-pixel border textures using Blizzard PixelUtil.
function ST.CreatePixelBorders(frame, r, g, b, a)
    local textures = ST.CreateBorderTextureSet(frame, "BORDER")
    ST.ApplyBorderTextures(textures, frame, { r or 0, g or 0, b or 0, a or 1 }, 1, ST.BORDER_RENDER_MODE_CRISP)
    frame.borderTextures = textures
    return textures
end

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------

-- Format a color table {r, g, b, a} into a cache key string.
-- Replaces repeated string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4]) calls.
function ST.FormatColorKey(c)
    return string_format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4] or 1)
end

--------------------------------------------------------------------------------
-- Config Selection Helpers
--------------------------------------------------------------------------------

-- Returns true when a group/panel frame should be at full alpha because it
-- (or its parent container) is selected in the Config panel.
-- Used by: alpha fade system, alpha sync ticker, button force-visible.
function ST.IsGroupConfigSelected(groupId)
    local CS = ST._configState
    if not CS then return false end
    local configFrame = CS.configFrame
    if not configFrame or not configFrame.frame or not configFrame.frame:IsShown() then
        return false
    end

    -- Direct panel/group selection
    if CS.selectedGroup == groupId then return true end

    -- Multi-panel selection
    if CS.selectedPanels and CS.selectedPanels[groupId] then return true end

    -- Container selected, no specific panel → all panels in that container
    if CS.selectedContainer and not CS.selectedGroup then
        local db = ST.Addon.db
        local group = db and db.profile.groups[groupId]
        if group and group.parentContainerId == CS.selectedContainer then
            return true
        end
    end

    return false
end

-- Returns true when this runtime button should be force-visible because its
-- group/panel is selected in the Config panel.  Active only while the config
-- frame is shown.
--
-- Force-visible rules:
--   1. Container selected, no panel/button selected → ALL buttons in ALL panels
--   2. Panel header selected, no button selected → ALL buttons in that panel
--   3. Individual button(s) selected within panel → only those buttons
--   4. Multi-selected panels (Ctrl+click) → ALL buttons in each panel
function ST.IsConfigButtonForceVisible(button)
    if not button then return false end

    local groupId = button._groupId
    if not groupId then return false end
    local index = button.index
    if not index then return false end

    local CS = ST._configState
    if not CS then return false end
    local configFrame = CS.configFrame
    if not configFrame or not configFrame.frame or not configFrame.frame:IsShown() then
        return false
    end

    -- Single-selected panel: check for individual button selection
    if CS.selectedGroup == groupId then
        if CS.selectedButton then
            return CS.selectedButton == index
        end
        if next(CS.selectedButtons) then
            return CS.selectedButtons[index] or false
        end
        -- No button selected → header-only, force-show ALL buttons
        return true
    end

    -- Multi-selected panels → all buttons
    if CS.selectedPanels and CS.selectedPanels[groupId] then
        return true
    end

    -- Container selected, no specific panel → all buttons in all panels
    if CS.selectedContainer and not CS.selectedGroup then
        local db = ST.Addon.db
        local group = db and db.profile.groups[groupId]
        if group and group.parentContainerId == CS.selectedContainer then
            return true
        end
    end

    return false
end
