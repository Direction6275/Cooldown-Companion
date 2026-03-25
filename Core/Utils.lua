--[[
    CooldownCompanion - Utils
    Shared constants, border helpers, color utilities, and config selection helpers
]]

local ADDON_NAME, ST = ...

local string_format = string.format

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ST.DEFAULT_OVERHANG_PCT = 32
ST.DEFAULT_GLOW_COLOR = {1, 1, 1, 1}
ST.DEFAULT_BG_COLOR = {0.2, 0.2, 0.2, 0.8}
ST.NUM_GLOW_STYLES = 3

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

-- Create 4 pixel-perfect border textures using PixelUtil (replaces backdrop edgeFile)
function ST.CreatePixelBorders(frame, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(top, 1, 1)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(bottom, 1, 1)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(left, 1, 1)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(right, 1, 1)

    frame.borderTextures = { top, bottom, left, right }
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
