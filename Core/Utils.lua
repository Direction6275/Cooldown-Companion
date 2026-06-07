--[[
    CooldownCompanion - Utils
    Shared constants, border helpers, color utilities, and config selection helpers
]]

local ADDON_NAME, ST = ...

local InCombatLockdown = InCombatLockdown
local string_format = string.format
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local type = type
local Enum = Enum
local issecretvalue = issecretvalue

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ST.DEFAULT_OVERHANG_PCT = 32
ST.DEFAULT_GLOW_COLOR = {1, 1, 1, 1}
ST.DEFAULT_BG_COLOR = {0.2, 0.2, 0.2, 0.8}
ST.NUM_GLOW_STYLES = 3
ST.BORDER_RENDER_MODE_CUSTOM = "custom"
ST.BORDER_RENDER_MODE_CRISP = "crisp"
ST.DEFAULT_FONT_NAME = ST.DEFAULT_FONT_NAME or "Friz Quadrata TT"
ST.DEFAULT_FONT_OUTLINE = ST.DEFAULT_FONT_OUTLINE or "OUTLINE"

local statusBarInterpolation = Enum and Enum.StatusBarInterpolation
local statusBarTimerDirection = Enum and Enum.StatusBarTimerDirection
ST.STATUS_BAR_INTERPOLATION_SMOOTH = statusBarInterpolation and statusBarInterpolation.ExponentialEaseOut
ST.STATUS_BAR_TIMER_DIRECTION_ELAPSED = statusBarTimerDirection and statusBarTimerDirection.ElapsedTime or 0
ST.STATUS_BAR_TIMER_DIRECTION_REMAINING = statusBarTimerDirection and statusBarTimerDirection.RemainingTime or 1

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
ST.EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top    (full width)
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom (full width)
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, -1,  1,  1}, -- Left   (inset to avoid corner overlap)
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, -1,  0,  1}, -- Right  (inset to avoid corner overlap)
}

--------------------------------------------------------------------------------
-- StatusBar Motion Helpers
--------------------------------------------------------------------------------

local STATUS_BAR_MOTION_TIMER = "timer"
local STATUS_BAR_MOTION_SMOOTH_VALUE = "smoothValue"

function ST.ClearStatusBarMotion(statusBar)
    if not statusBar then return end

    statusBar._cdcStatusBarMotionKind = nil
    statusBar._cdcStatusBarMotionDurationObj = nil
    statusBar._cdcStatusBarMotionDirection = nil
    statusBar._cdcStatusBarMotionValue = nil
    statusBar._cdcStatusBarRangeMin = nil
    statusBar._cdcStatusBarRangeMax = nil
    statusBar._cdcStatusBarRangeInterpolation = nil
end

function ST.SetStatusBarRange(statusBar, minValue, maxValue, interpolation)
    if not statusBar then return false end

    local rangeIsSecret = issecretvalue
        and (issecretvalue(minValue) or issecretvalue(maxValue))
    if not rangeIsSecret
        and statusBar._cdcStatusBarRangeMin == minValue
        and statusBar._cdcStatusBarRangeMax == maxValue
        and statusBar._cdcStatusBarRangeInterpolation == interpolation then
        return true
    end

    if rangeIsSecret then
        statusBar._cdcStatusBarRangeMin = nil
        statusBar._cdcStatusBarRangeMax = nil
        statusBar._cdcStatusBarRangeInterpolation = nil
    else
        statusBar._cdcStatusBarRangeMin = minValue
        statusBar._cdcStatusBarRangeMax = maxValue
        statusBar._cdcStatusBarRangeInterpolation = interpolation
    end

    if interpolation ~= nil then
        statusBar:SetMinMaxValues(minValue, maxValue, interpolation)
    else
        statusBar:SetMinMaxValues(minValue, maxValue)
    end
    return true
end

function ST.SetStatusBarImmediateRange(statusBar, minValue, maxValue)
    return ST.SetStatusBarRange(statusBar, minValue, maxValue, nil)
end

function ST.SetStatusBarSmoothRange(statusBar, minValue, maxValue)
    return ST.SetStatusBarRange(statusBar, minValue, maxValue, ST.STATUS_BAR_INTERPOLATION_SMOOTH)
end

function ST.SetStatusBarImmediateValue(statusBar, value)
    if not statusBar then return false end

    ST.ClearStatusBarMotion(statusBar)
    statusBar:SetValue(value)
    return true
end

function ST.SetStatusBarSmoothValue(statusBar, value)
    if not statusBar then return false end

    local valueIsSecret = issecretvalue and issecretvalue(value)
    if statusBar._cdcStatusBarMotionKind == STATUS_BAR_MOTION_SMOOTH_VALUE
        and not valueIsSecret
        and statusBar._cdcStatusBarMotionValue == value then
        return true
    end

    statusBar._cdcStatusBarMotionKind = STATUS_BAR_MOTION_SMOOTH_VALUE
    statusBar._cdcStatusBarMotionDurationObj = nil
    statusBar._cdcStatusBarMotionDirection = nil
    if valueIsSecret then
        statusBar._cdcStatusBarMotionValue = nil
    else
        statusBar._cdcStatusBarMotionValue = value
    end

    local interpolation = ST.STATUS_BAR_INTERPOLATION_SMOOTH
    if interpolation ~= nil then
        statusBar:SetValue(value, interpolation)
    else
        statusBar:SetValue(value)
    end
    return true
end

function ST.SetStatusBarTimerDuration(statusBar, durationObj, direction)
    if not (statusBar and durationObj and statusBar.SetTimerDuration) then
        return false
    end

    direction = direction or ST.STATUS_BAR_TIMER_DIRECTION_ELAPSED
    if statusBar._cdcStatusBarMotionKind == STATUS_BAR_MOTION_TIMER
        and statusBar._cdcStatusBarMotionDurationObj == durationObj
        and statusBar._cdcStatusBarMotionDirection == direction then
        return true
    end

    statusBar._cdcStatusBarMotionKind = STATUS_BAR_MOTION_TIMER
    statusBar._cdcStatusBarMotionDurationObj = durationObj
    statusBar._cdcStatusBarMotionDirection = direction
    statusBar._cdcStatusBarMotionValue = nil

    statusBar:SetTimerDuration(durationObj, ST.STATUS_BAR_INTERPOLATION_SMOOTH, direction)
    return true
end

function ST.SetStatusBarElapsedDuration(statusBar, durationObj)
    return ST.SetStatusBarTimerDuration(statusBar, durationObj, ST.STATUS_BAR_TIMER_DIRECTION_ELAPSED)
end

function ST.SetStatusBarRemainingDuration(statusBar, durationObj)
    return ST.SetStatusBarTimerDuration(statusBar, durationObj, ST.STATUS_BAR_TIMER_DIRECTION_REMAINING)
end

--------------------------------------------------------------------------------
-- Unusable Visual Helpers
--------------------------------------------------------------------------------

ST.UNUSABLE_VISUAL_MODE_DIM = "dim"
ST.UNUSABLE_VISUAL_MODE_DESATURATE = "desaturate"
ST.UNUSABLE_VISUAL_MODE_BOTH = "both"
ST.UNUSABLE_VISUAL_MODE_NONE = "none"

function ST.GetUnusableVisualMode(source)
    if type(source) == "table" then
        source = source.unusableVisualMode
    end
    if source == ST.UNUSABLE_VISUAL_MODE_DESATURATE then
        return ST.UNUSABLE_VISUAL_MODE_DESATURATE
    elseif source == ST.UNUSABLE_VISUAL_MODE_BOTH then
        return ST.UNUSABLE_VISUAL_MODE_BOTH
    elseif source == ST.UNUSABLE_VISUAL_MODE_NONE then
        return ST.UNUSABLE_VISUAL_MODE_NONE
    end
    return ST.UNUSABLE_VISUAL_MODE_DIM
end

function ST.UnusableVisualUsesDimTint(source)
    local mode = ST.GetUnusableVisualMode(source)
    return mode == ST.UNUSABLE_VISUAL_MODE_DIM or mode == ST.UNUSABLE_VISUAL_MODE_BOTH
end

function ST.UnusableVisualUsesDesaturation(source)
    local mode = ST.GetUnusableVisualMode(source)
    return mode == ST.UNUSABLE_VISUAL_MODE_DESATURATE or mode == ST.UNUSABLE_VISUAL_MODE_BOTH
end

function ST.SetUnusableVisualMode(styleTable, useDimTint, useDesaturation)
    if type(styleTable) ~= "table" then
        return
    end
    if useDimTint and useDesaturation then
        styleTable.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_BOTH
    elseif useDimTint then
        styleTable.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_DIM
    elseif useDesaturation then
        styleTable.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_DESATURATE
    else
        styleTable.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_NONE
    end
end

--------------------------------------------------------------------------------
-- Border Helpers
--------------------------------------------------------------------------------

local BORDER_EDGE_NAMES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function GetBorderSize(size, fallback)
    return tonumber(size) or fallback or 1
end

function ST.GetBorderRenderMode(source, key)
    if type(source) == "table" then
        source = source[key or "borderRenderMode"]
    end
    if source == ST.BORDER_RENDER_MODE_CRISP then
        return ST.BORDER_RENDER_MODE_CRISP
    end
    return ST.BORDER_RENDER_MODE_CUSTOM
end

function ST.IsProfileOnePixelBordersEnabled()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    return db and db.profileOnePixelBorders == true
end

function ST.IsBorderThicknessLocked()
    return ST.IsProfileOnePixelBordersEnabled()
end

function ST.IsProfileWideFontEnabled()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    return db and db.profileWideFontEnabled == true
end

function ST.IsFontPickerLocked()
    return ST.IsProfileWideFontEnabled()
end

function ST.GetProfileWideFontName()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    local name = db and db.profileWideFontName
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

function ST.GetProfileWideFontOutline()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    local outline = db and db.profileWideFontOutline
    if type(outline) == "string" then
        return outline
    end
    return nil
end

function ST.GetEffectiveFontName(localFontName)
    if ST.IsProfileWideFontEnabled() then
        return ST.GetProfileWideFontName() or ST.DEFAULT_FONT_NAME
    end
    if type(localFontName) == "string" and localFontName ~= "" then
        return localFontName
    end
    return ST.DEFAULT_FONT_NAME
end

function ST.GetEffectiveFontOutline(localOutline)
    if ST.IsProfileWideFontEnabled() then
        local profileOutline = ST.GetProfileWideFontOutline()
        if profileOutline ~= nil then
            return profileOutline
        end
        return ST.DEFAULT_FONT_OUTLINE
    end
    if type(localOutline) == "string" then
        return localOutline
    end
    return ST.DEFAULT_FONT_OUTLINE
end

function ST.IsProfileWideBarTextureEnabled()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    return db and db.profileWideBarTextureEnabled == true
end

function ST.IsBarTexturePickerLocked()
    return ST.IsProfileWideBarTextureEnabled()
end

function ST.GetProfileWideBarTextureName()
    local addon = ST.Addon
    local db = addon and addon.db and addon.db.profile
    local name = db and db.profileWideBarTextureName
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

function ST.GetEffectiveBarTextureName(localTextureName)
    if ST.IsProfileWideBarTextureEnabled() then
        return ST.GetProfileWideBarTextureName() or "Solid"
    end
    if type(localTextureName) == "string" and localTextureName ~= "" then
        return localTextureName
    end
    return "Solid"
end

function ST.GetEffectiveBorderRenderMode(source, key, size)
    local configuredMode = ST.GetBorderRenderMode(source, key)
    if not ST.IsProfileOnePixelBordersEnabled() then
        return configuredMode
    end

    -- Preserve size-zero hidden borders for existing custom-thickness surfaces.
    if configuredMode == ST.BORDER_RENDER_MODE_CUSTOM and GetBorderSize(size, 1) <= 0 then
        return ST.BORDER_RENDER_MODE_CUSTOM
    end

    return ST.BORDER_RENDER_MODE_CRISP
end

function ST.IsCrispBorderRenderMode(source, key)
    return ST.GetBorderRenderMode(source, key) == ST.BORDER_RENDER_MODE_CRISP
end

function ST.IsEffectiveCrispBorderRenderMode(source, key, size)
    return ST.GetEffectiveBorderRenderMode(source, key, size) == ST.BORDER_RENDER_MODE_CRISP
end

local function GetOnePhysicalPixelSize(region)
    return PixelUtil.GetNearestPixelSize(0, region:GetEffectiveScale(), 1)
end

function ST.GetBorderLayoutSize(region, size, mode)
    if ST.IsCrispBorderRenderMode(mode) then
        return GetOnePhysicalPixelSize(region)
    end
    return GetBorderSize(size, 1)
end

function ST.GetEffectiveBorderLayoutSize(region, size, source, key)
    return ST.GetBorderLayoutSize(region, size, ST.GetEffectiveBorderRenderMode(source, key, size))
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
    if crisp then
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
    local customEdgeSize = GetBorderSize(size, 1)

    for index, spec in ipairs(ST.EDGE_ANCHOR_SPEC) do
        local tex = GetEdgeTexture(textures, index)
        if tex then
            local edgeSize = crisp and GetOnePhysicalPixelSize(tex) or customEdgeSize
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
-- Runtime Info Buttons
--------------------------------------------------------------------------------

function ST.SetRuntimeInfoButtonShown(button, shown)
    if not button then
        return
    end

    button._cdcDesiredShown = shown == true
    local visible = button._cdcDesiredShown
    button:SetShown(visible)
    if not InCombatLockdown or not InCombatLockdown() then
        if button.EnableMouse then
            button:EnableMouse(visible)
        end
        if button.SetMouseClickEnabled then
            button:SetMouseClickEnabled(visible)
        end
        if button.SetMouseMotionEnabled then
            button:SetMouseMotionEnabled(visible)
        end
    end
end

function ST.CreateRuntimeInfoButton(parentFrame, anchorFrame, anchorPoint, anchorRelPoint, xOff, yOff, buildTooltip)
    local button = CreateFrame("Button", nil, parentFrame)
    button:SetSize(16, 16)
    button:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, xOff, yOff)
    if parentFrame.GetFrameStrata and button.SetFrameStrata then
        button:SetFrameStrata(parentFrame:GetFrameStrata())
    end
    if parentFrame.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((parentFrame:GetFrameLevel() or 1) + 1)
    end

    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("QuestRepeatableTurnin")
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(buildTooltip) == "function" then
            buildTooltip(GameTooltip, self)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    ST.SetRuntimeInfoButtonShown(button, false)
    return button
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
-- (or its parent container) is selected in the Config panel, or because it is
-- part of an active cursor Layout preview.
-- Used by: alpha fade system, alpha sync ticker, button force-visible.
function ST.IsGroupConfigSelected(groupId)
    local CS = ST._configState
    if not CS then return false end
    local configFrame = CS.configFrame
    if not configFrame or not configFrame.frame or not configFrame.frame:IsShown() then
        return false
    end

    local addon = ST.Addon
    if addon
        and addon.IsCursorAnchorLayoutPreviewGroupActive
        and addon:IsCursorAnchorLayoutPreviewGroupActive(groupId) then
        return true
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

    local addon = ST.Addon
    if addon
        and addon.IsCursorAnchorLayoutPreviewGroupActive
        and addon:IsCursorAnchorLayoutPreviewGroupActive(groupId) then
        return true
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
