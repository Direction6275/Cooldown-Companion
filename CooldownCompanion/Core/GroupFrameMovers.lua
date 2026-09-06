--[[
    CooldownCompanion - GroupFrameMovers
    Panel mover chrome, nudging, resizing, and control visibility.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreatePixelBorders = ST.CreatePixelBorders

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local NUDGE_BTN_SIZE = GF.NUDGE_BTN_SIZE
local IsCursorAnchor = GF.IsCursorAnchor
local IsCursorAnchorLayoutPreviewSelected = GF.IsCursorAnchorLayoutPreviewSelected
local UpdateCoordLabel = GF.UpdateCoordLabel
local CURSOR_ANCHOR_X = GF.CURSOR_ANCHOR_X
local CURSOR_ANCHOR_Y = GF.CURSOR_ANCHOR_Y
local GetContainerState = GF.GetContainerState
local GetGroupButtonSizingOptions = GF.GetGroupButtonSizingOptions
local NormalizeCompactGrowthDirection = GF.NormalizeCompactGrowthDirection
local GetCompactAnchorFixedPoint = GF.GetCompactAnchorFixedPoint
local GetContainerPreviewSelectionState = GF.GetContainerPreviewSelectionState
local ApplySectionSelectionTint = GF.ApplySectionSelectionTint

local moverChromeFadeState = {
    active = false,
    activeMover = nil,
    generation = 0,
}

function CooldownCompanion:ApplyMoverChromeFadeToFrames(header, coordLabel, nudger, resizeGrip, sizeLabel)
    local alpha = moverChromeFadeState.active and 0 or 1
    if header then
        header:SetAlpha(header._moverMenuPinned and 1 or alpha)
    end
    if coordLabel then
        coordLabel:SetAlpha(alpha)
    end
    if nudger then
        local isActiveTool = moverChromeFadeState.active and nudger == moverChromeFadeState.activeMover
        nudger:SetIgnoreParentAlpha(isActiveTool)
        nudger:SetAlpha(isActiveTool and 1 or alpha)
    end
    if resizeGrip then
        local isActiveTool = moverChromeFadeState.active and resizeGrip == moverChromeFadeState.activeMover
        resizeGrip:SetIgnoreParentAlpha(isActiveTool)
        resizeGrip:SetAlpha(isActiveTool and 1 or alpha)
    end
    if sizeLabel then
        sizeLabel:SetAlpha(alpha)
    end
end

function CooldownCompanion:ApplyMoverChromeFadeState()
    for _, frame in pairs(CooldownCompanion.groupFrames or {}) do
        self:ApplyMoverChromeFadeToFrames(
            frame.dragHandle, frame.coordLabel, frame.nudger, frame.resizeGrip, frame.sizeLabel
        )
        if CooldownCompanion.GetAuraTextureMoverChromeForGroupFrame then
            self:ApplyMoverChromeFadeToFrames(
                CooldownCompanion:GetAuraTextureMoverChromeForGroupFrame(frame)
            )
        end
    end

    for _, frame in pairs(CooldownCompanion.containerFrames or {}) do
        -- Fade the whole wrapper, outline included: while dragging or nudging,
        -- only the real panels should remain as alignment references. The
        -- active nudger survives via SetIgnoreParentAlpha below.
        self:ApplyMoverChromeFadeToFrames(frame.dragHandle, frame.coordLabel, frame.nudger)
    end

    if CooldownCompanion.GetIndependentCastBarMoverChrome then
        self:ApplyMoverChromeFadeToFrames(CooldownCompanion:GetIndependentCastBarMoverChrome())
    end
    if CooldownCompanion.GetIndependentResourceStackMoverChrome then
        self:ApplyMoverChromeFadeToFrames(CooldownCompanion:GetIndependentResourceStackMoverChrome())
    end
end

function CooldownCompanion:BeginMoverChromeFade(activeMover)
    moverChromeFadeState.generation = moverChromeFadeState.generation + 1
    moverChromeFadeState.active = true
    moverChromeFadeState.activeMover = activeMover
    self:ApplyMoverChromeFadeState()
end

function CooldownCompanion:EndMoverChromeFade(activeMover)
    if not moverChromeFadeState.active
        or (activeMover and moverChromeFadeState.activeMover ~= activeMover) then
        return
    end

    moverChromeFadeState.generation = moverChromeFadeState.generation + 1
    moverChromeFadeState.active = false
    moverChromeFadeState.activeMover = nil
    self:ApplyMoverChromeFadeState()
end

function CooldownCompanion:EndMoverChromeFadeIfOwnedByContainer(containerId)
    if not moverChromeFadeState.active then
        return
    end

    local activeMover = moverChromeFadeState.activeMover
    if not activeMover then
        self:EndMoverChromeFade()
        return
    end

    local containerFrame = self.containerFrames and self.containerFrames[containerId]
    if activeMover == containerFrame
        or (containerFrame and activeMover == containerFrame.nudger) then
        self:EndMoverChromeFade(activeMover)
        return
    end

    local groups = self.db
        and self.db.profile
        and self.db.profile.groups
        or {}
    for groupId, group in pairs(groups) do
        if group.parentContainerId == containerId then
            local groupFrame = self.groupFrames and self.groupFrames[groupId]
            if groupFrame and groupFrame._containerUnlockPreviewActive == true then
                local textureHost = self.GetAuraTextureHostForGroupFrame
                    and self:GetAuraTextureHostForGroupFrame(groupFrame)
                    or nil
                if activeMover == groupFrame
                    or activeMover == groupFrame.nudger
                    or activeMover == groupFrame.resizeGrip
                    or activeMover._resizeFrame == groupFrame
                    or activeMover == textureHost
                    or (textureHost and activeMover == textureHost.nudger) then
                    self:EndMoverChromeFade(activeMover)
                    return
                end
            end
        end
    end
end

function CooldownCompanion:VerifyMoverChromeHoverFade(pad)
    if not moverChromeFadeState.active or moverChromeFadeState.activeMover ~= pad then
        return false
    end

    if not pad:IsMouseOver() then
        self:EndMoverChromeFade(pad)
        return false
    end

    return true
end

function CooldownCompanion:BeginMoverChromeHoverFade(pad)
    self:BeginMoverChromeFade(pad)
    local generation = moverChromeFadeState.generation
    local function WatchHover()
        if moverChromeFadeState.generation ~= generation
            or not CooldownCompanion:VerifyMoverChromeHoverFade(pad) then
            return
        end

        C_Timer.After(0.25, WatchHover)
    end
    C_Timer.After(0.25, WatchHover)
end

function CooldownCompanion:ResetMoverChromeFade()
    moverChromeFadeState.generation = moverChromeFadeState.generation + 1
    moverChromeFadeState.active = false
    moverChromeFadeState.activeMover = nil
    self:ApplyMoverChromeFadeState()
end

function CooldownCompanion:BeginMoverChromeWheelFade(activeMover)
    self:BeginMoverChromeFade(activeMover)
    local generation = moverChromeFadeState.generation
    C_Timer.After(0.5, function()
        if moverChromeFadeState.active and moverChromeFadeState.generation == generation then
            CooldownCompanion:EndMoverChromeFade(activeMover)
        end
    end)
end

-- 16 fits the corner-bracket glyph at the size it reads well (12px art +
-- inset); the old chat-grabber art sat in a 12px button.
local PANEL_RESIZE_GRIP_SIZE = 16
-- 0 = restyle every frame during a grip drag (owner ruling: smooth resize
-- everywhere in arrange mode; raise if a huge panel ever hitches).
local PANEL_RESIZE_REFRESH_INTERVAL = 0

local function CreateNudger(frame, groupId)
    local NUDGE_GAP = 2

    local nudger = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    nudger.buttons = {}
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", frame.dragHandle, "TOP", 0, 2)
    nudger:SetFrameStrata(frame.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(frame.dragHandle:GetFrameLevel() + 5)
    nudger:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(nudger)
    nudger:SetScript("OnEnter", function(self)
        CooldownCompanion:BeginMoverChromeHoverFade(self)
    end)
    nudger:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then
            CooldownCompanion:EndMoverChromeFade(self)
        end
    end)
    nudger:SetScript("OnHide", function(self)
        CooldownCompanion:EndMoverChromeFade(self)
    end)

    local directions = {
        { atlas = "common-dropdown-icon-back", rotation = -math.pi / 2, anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },   -- up
        { atlas = "common-dropdown-icon-next", rotation = -math.pi / 2, anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },  -- down
        { atlas = "common-dropdown-icon-back", rotation = 0,            anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },          -- left
        { atlas = "common-dropdown-icon-next", rotation = 0,            anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },          -- right
    }

    local function IsCursorPreviewNudge()
        local group = CooldownCompanion.db.profile.groups[groupId]
        return group
            and IsCursorAnchor(group.anchor)
            and IsCursorAnchorLayoutPreviewSelected(CooldownCompanion, groupId)
            or false
    end

    -- A section nudge moves stored offsets, not the frame, so the anchor-side
    -- save on release has nothing to persist.
    local function IsSectionNudge()
        return (CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)) ~= nil
    end

    -- The offset sliders' own range and precision (Layout tab: -100..100,
    -- tenths), so a nudged value is always one the config can show back.
    local function RoundAndClampSectionOffset(value)
        value = math_floor(value * 10 + 0.5) / 10
        return math_max(-100, math_min(100, value))
    end

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        nudger.buttons[#nudger.buttons + 1] = btn
        btn:SetSize(NUDGE_BTN_SIZE, NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        btn.arrow = arrow

        -- Hover highlight
        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
            CooldownCompanion:BeginMoverChromeHoverFade(nudger)
        end)
        btn:SetScript("OnLeave", function(self)
            if nudger.RefreshSectionTint then nudger.RefreshSectionTint() end
            if not IsCursorPreviewNudge() and not IsSectionNudge() then
                CooldownCompanion:SaveGroupPosition(groupId)
            end
            if not nudger:IsMouseOver() then
                CooldownCompanion:EndMoverChromeFade(nudger)
            end
        end)

        local function DoNudge()
            local group = CooldownCompanion.db.profile.groups[groupId]
            if not group then return end
            local gFrame = CooldownCompanion.groupFrames[groupId]
            if gFrame then
                -- A selected SECTION takes the nudge as its own X/Y offset;
                -- the panel does not move (owner grammar: select it, then
                -- adjust it). offsetY is positive-up, matching dir.dy.
                local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
                if section then
                    section.offsetX = RoundAndClampSectionOffset(
                        (tonumber(section.offsetX) or 0) + dir.dx)
                    section.offsetY = RoundAndClampSectionOffset(
                        (tonumber(section.offsetY) or 0) + dir.dy)
                    CooldownCompanion:UpdateGroupStyle(groupId)
                    UpdateCoordLabel(gFrame,
                        tonumber(section.offsetX) or 0,
                        tonumber(section.offsetY) or 0)
                    return
                end

                if IsCursorAnchor(group.anchor)
                    and IsCursorAnchorLayoutPreviewSelected(CooldownCompanion, groupId) then
                    group.anchor.x = math_floor(((group.anchor.x or CURSOR_ANCHOR_X) + dir.dx) * 10 + 0.5) / 10
                    group.anchor.y = math_floor(((group.anchor.y or CURSOR_ANCHOR_Y) + dir.dy) * 10 + 0.5) / 10
                    CooldownCompanion:AnchorGroupFrame(gFrame, group.anchor)
                    UpdateCoordLabel(gFrame, group.anchor.x, group.anchor.y)
                    if CooldownCompanion.UpdateCursorAnchoredFrames then
                        CooldownCompanion:UpdateCursorAnchoredFrames()
                    end
                    return
                end

                gFrame:AdjustPointsOffset(dir.dx, dir.dy)
                -- Read the actual frame position so display stays in sync
                local _, _, _, x, y = gFrame:GetPoint()
                group.anchor.x = math_floor(x * 10 + 0.5) / 10
                group.anchor.y = math_floor(y * 10 + 0.5) / 10
                UpdateCoordLabel(gFrame, x, y)
                if group.parentContainerId and CooldownCompanion.RefreshContainerWrapper then
                    CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
                end
            end
        end

        btn:SetScript("OnMouseDown", function(self)
            CancelCoordinateEdit(frame.coordLabel)
            CancelCoordinateEdit(frame.sizeLabel)
            DoNudge()
            CooldownCompanion:VerifyMoverChromeHoverFade(nudger)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if not IsCursorPreviewNudge() and not IsSectionNudge() then
                CooldownCompanion:SaveGroupPosition(groupId)
            end
        end)
    end

    -- Gold arrows while a section is selected: the nudger is shared chrome,
    -- and the tint is what says it is currently driving the section.
    function nudger.RefreshSectionTint()
        local r, g, b, a = 0.8, 0.8, 0.8, 0.8
        if IsSectionNudge() then
            r, g, b, a = 1, 0.82, 0, 0.9
        end
        for _, button in ipairs(nudger.buttons) do
            button.arrow:SetVertexColor(r, g, b, a)
        end
    end
    nudger.RefreshSectionTint()

    return nudger
end

local function IsGroupPanelResizable(group)
    if not group then
        return false
    end

    local displayMode = group.displayMode
    return displayMode == nil
        or displayMode == "icons"
        or displayMode == "bars"
        or displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
end

local function CanUsePanelResizeInteractions(groupId, group)
    if not IsGroupPanelResizable(group)
        or CooldownCompanion._combatForcedLock
        or InCombatLockdown() then
        return false
    end

    -- The cursor positioning preview owns cursor panels; resize rides the
    -- same gate that grants them drag and nudge.
    if IsCursorAnchor(group.anchor) then
        return IsCursorAnchorLayoutPreviewSelected(CooldownCompanion, groupId)
    end

    if not GetContainerState(groupId) then
        return true
    end

    return group.parentContainerId
        and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)
        and CooldownCompanion:IsContainerPanelSelected(group.parentContainerId, groupId)
        or false
end

local function RoundAndClampPanelSize(value, minValue, maxValue)
    return math_max(minValue, math_min(maxValue, math_floor(value + 0.5)))
end

local function GetPanelResizeCursorPosition()
    if not (GetCursorPosition and UIParent) then
        return nil, nil
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not (cursorX and cursorY and scale and scale > 0) then
        return nil, nil
    end

    return cursorX / scale, cursorY / scale
end

local function ApplyPanelResizeFromCursor(grip)
    local groupId = grip._resizeGroupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    if not group or not CanUsePanelResizeInteractions(groupId, group) then
        return false
    end

    local cursorX, cursorY = GetPanelResizeCursorPosition()
    if not (cursorX and cursorY) then
        return false
    end

    local style = group.style
    if not style then
        return false
    end

    local dx = (cursorX - grip._resizeStartX) * (grip._resizeSignX or 1)
    local dy = (cursorY - grip._resizeStartY) * (grip._resizeSignY or 1)
    local perButtonDW = dx / (grip._resizeCols * grip._resizeKX)
    local perButtonDH = -dy / (grip._resizeRows * grip._resizeKY)
    local changed = false

    if grip._resizeKind == "square" then
        local newSize = RoundAndClampPanelSize(grip._resizeStartPrimary + ((perButtonDW + perButtonDH) / 2), 10, 150)
        if style.buttonSize ~= newSize then
            style.buttonSize = newSize
            changed = true
        end
    elseif grip._resizeKind == "icon" then
        local newWidth = RoundAndClampPanelSize(grip._resizeStartPrimary + perButtonDW, 10, 150)
        local newHeight = RoundAndClampPanelSize(grip._resizeStartSecondary + perButtonDH, 10, 150)
        if style.iconWidth ~= newWidth then
            style.iconWidth = newWidth
            changed = true
        end
        if style.iconHeight ~= newHeight then
            style.iconHeight = newHeight
            changed = true
        end
    elseif grip._resizeKind == "bar" then
        local newLength
        local newHeight
        if grip._resizeBarFillVertical then
            newLength = RoundAndClampPanelSize(grip._resizeStartPrimary + perButtonDH, 10, 500)
            newHeight = RoundAndClampPanelSize(grip._resizeStartSecondary + perButtonDW, 5, 100)
        else
            newLength = RoundAndClampPanelSize(grip._resizeStartPrimary + perButtonDW, 10, 500)
            newHeight = RoundAndClampPanelSize(grip._resizeStartSecondary + perButtonDH, 5, 100)
        end
        if style.barLength ~= newLength then
            style.barLength = newLength
            changed = true
        end
        if style.barHeight ~= newHeight then
            style.barHeight = newHeight
            changed = true
        end
    end

    return changed
end

local function RefreshConfigPanelIfShown()
    local configState = ST._configState
    local configFrame = configState and configState.configFrame
    local frame = configFrame and configFrame.frame
    if frame and frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function UpdateResizedPanelContainerWrapper(groupId)
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    local containerId = group and group.parentContainerId
    if containerId
        and CooldownCompanion.UpdateContainerWrapperUnion
        and CooldownCompanion.IsContainerUnlockPreviewActive
        and CooldownCompanion:IsContainerUnlockPreviewActive(containerId) then
        CooldownCompanion:UpdateContainerWrapperUnion(containerId)
    end
end

local function EndPanelResizeGesture(grip, applyFinal)
    if not grip._resizeActive then
        grip:SetScript("OnUpdate", nil)
        return
    end

    local groupId = grip._resizeGroupId
    local restylePending = grip._resizeRestylePending
    grip._resizeActive = nil
    grip:SetScript("OnUpdate", nil)

    if applyFinal and groupId then
        ApplyPanelResizeFromCursor(grip)
        CooldownCompanion:UpdateGroupStyle(groupId)
        RefreshConfigPanelIfShown()
    elseif restylePending then
        CooldownCompanion._pendingFullRefresh = true
    end
    ST.UpdateGroupSizeLabel(grip._resizeFrame)

    grip._resizeGroupId = nil
    grip._resizeKind = nil
    grip._resizeStartX = nil
    grip._resizeStartY = nil
    grip._resizeStartPrimary = nil
    grip._resizeStartSecondary = nil
    grip._resizeBarFillVertical = nil
    grip._resizeCols = nil
    grip._resizeRows = nil
    grip._resizeKX = nil
    grip._resizeKY = nil
    grip._resizeSignX = nil
    grip._resizeSignY = nil
    grip._resizeElapsed = nil
    grip._resizeRestylePending = nil
    CooldownCompanion:EndMoverChromeFade(grip)
end

local function UpdatePanelResizeGesture(grip, elapsed)
    if not grip._resizeActive then
        return
    end

    grip._resizeElapsed = grip._resizeElapsed + elapsed
    if ApplyPanelResizeFromCursor(grip) then
        grip._resizeRestylePending = true
    end

    if grip._resizeElapsed >= PANEL_RESIZE_REFRESH_INTERVAL then
        grip._resizeElapsed = 0
        if grip._resizeRestylePending then
            grip._resizeRestylePending = nil
            CooldownCompanion:UpdateGroupStyle(grip._resizeGroupId)
        end
        ST.UpdateGroupSizeLabel(grip._resizeFrame)
    end
end

local function BeginPanelResizeGesture(grip)
    local frame = grip._resizeFrame
    local groupId = frame and frame.groupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    if not group or not CanUsePanelResizeInteractions(groupId, group) then
        return
    end

    CancelCoordinateEdit(frame.coordLabel)
    CancelCoordinateEdit(frame.sizeLabel)
    local cursorX, cursorY = GetPanelResizeCursorPosition()
    if not (cursorX and cursorY) then
        return
    end

    local style = group.style
    if not style then
        return
    end

    grip._resizeGroupId = groupId
    grip._resizeStartX = cursorX
    grip._resizeStartY = cursorY
    grip._resizeElapsed = 0
    grip._resizeRestylePending = nil

    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    local numButtons = frame.visibleButtonCount
        or (CooldownCompanion:IsRotationAssistantGroup(group) and 1)
        or #group.buttons
    if group.parentContainerId and not CooldownCompanion:IsGroupCompactLayoutActive(groupId, group) and frame.layoutButtonCount then
        numButtons = math_max(numButtons, frame.layoutButtonCount)
    end
    -- On a sectioned panel the counts above include the section members, but the
    -- panel-wide size keys this drag scales drive the BASE CLUSTER only (each
    -- section owns its own icon size), so the grid to measure is the base one.
    if frame._sectionLayout then
        numButtons = math_max(1, frame._sectionLayout.baseCount)
    end
    if ST.IsAuraPanelGroup(group) then
        -- The drag scales per cell, so it has to read the same expanded grid
        -- ResizeGroupFrame lays out -- notably the single bar column, which the
        -- buttonsPerRow math below would wrap.
        grip._resizeCols, grip._resizeRows = CooldownCompanion:GetAuraPanelGridMetrics(
            groupId,
            group,
            GetGroupButtonSizingOptions(CooldownCompanion, groupId, group, nil)
        )
    elseif orientation == "horizontal" then
        grip._resizeCols = math_max(1, math_min(numButtons, buttonsPerRow))
        grip._resizeRows = math_max(1, math_ceil(numButtons / buttonsPerRow))
    else
        grip._resizeRows = math_max(1, math_min(numButtons, buttonsPerRow))
        grip._resizeCols = math_max(1, math_ceil(numButtons / buttonsPerRow))
    end

    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)
    local factorPoint
    if not ST.IsAuraPanelGroup(group) then
        factorPoint = ST.GetCenteredGrowthEdge(style.growthOrigin, orientation)
    end
    if not factorPoint and CooldownCompanion:IsGroupCompactLayoutActive(groupId, group) then
        factorPoint = GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, style.growthOrigin)
    end
    factorPoint = factorPoint or ((group.anchor and group.anchor.point) or "CENTER")
    if factorPoint:find("LEFT", 1, true) then
        grip._resizeKX = 1
    elseif factorPoint:find("RIGHT", 1, true) then
        grip._resizeKX = 0
    else
        grip._resizeKX = 0.5
    end
    if factorPoint:find("TOP", 1, true) then
        grip._resizeKY = 1
    elseif factorPoint:find("BOTTOM", 1, true) then
        grip._resizeKY = 0
    else
        grip._resizeKY = 0.5
    end
    if grip._resizeKX == 0 then
        grip._resizeKX = 1
    end
    if grip._resizeKY == 0 then
        grip._resizeKY = 1
    end
    -- A parked cursor panel extends away from its anchored point, so the
    -- factors and delta signs come from that anchor: the grip sits on the
    -- movable corner and dragging it outward always grows the panel.
    grip._resizeSignX = 1
    grip._resizeSignY = 1
    if IsCursorAnchor(group.anchor) then
        local point = group.anchor.point or "CENTER"
        grip._resizeKX = (point:find("LEFT", 1, true) or point:find("RIGHT", 1, true)) and 1 or 0.5
        grip._resizeKY = (point:find("TOP", 1, true) or point:find("BOTTOM", 1, true)) and 1 or 0.5
        if point:find("RIGHT", 1, true) then
            grip._resizeSignX = -1
        end
        if point:find("BOTTOM", 1, true) then
            grip._resizeSignY = -1
        end
    end

    if group.displayMode == "bars" then
        grip._resizeKind = "bar"
        grip._resizeStartPrimary = style.barLength or 180
        grip._resizeStartSecondary = style.barHeight or 20
        grip._resizeBarFillVertical = style.barFillVertical and true or nil
    elseif style.maintainAspectRatio then
        grip._resizeKind = "square"
        grip._resizeStartPrimary = style.buttonSize or ST.BUTTON_SIZE
        grip._resizeStartSecondary = nil
        grip._resizeBarFillVertical = nil
    else
        grip._resizeKind = "icon"
        grip._resizeStartPrimary = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        grip._resizeStartSecondary = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
        grip._resizeBarFillVertical = nil
    end

    grip._resizeActive = true
    CooldownCompanion:BeginMoverChromeFade(grip)
    grip:SetScript("OnUpdate", UpdatePanelResizeGesture)
end

local function CreatePanelResizeGrip(frame)
    local grip = CreateFrame("Button", nil, frame.dragHandle)
    grip._resizeFrame = frame
    grip:SetSize(PANEL_RESIZE_GRIP_SIZE, PANEL_RESIZE_GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameStrata(frame.dragHandle:GetFrameStrata())
    grip:SetFrameLevel(frame.dragHandle:GetFrameLevel() + 4)
    -- The house corner bracket (owner ruling 2026-08-29: one quiet resize
    -- glyph everywhere, replacing the stock chat grabber). Re-mirrored by
    -- RepositionPanelResizeGrip when a cursor panel moves the corner.
    ST.ApplyCornerBracketGrip(grip, "RIGHT", "BOTTOM")

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            BeginPanelResizeGesture(self)
        end
    end)
    grip:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            EndPanelResizeGesture(self, not CooldownCompanion._combatForcedLock and not InCombatLockdown())
        end
    end)
    grip:SetScript("OnHide", function(self)
        GameTooltip:Hide()
        EndPanelResizeGesture(self, not CooldownCompanion._combatForcedLock and not InCombatLockdown())
    end)
    grip:SetScript("OnEnter", function(self)
        -- White at rest, gold on hover (owner ruling) -- the same feedback
        -- the section grabber gives.
        ST.SetCornerBracketGripColor(self, 1, 0.82, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Mouse wheel over the panel also resizes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        ST.SetCornerBracketGripColor(self, 1, 1, 1)
        GameTooltip:Hide()
    end)

    return grip
end

local function OnUnlockedPanelMouseWheel(frame, delta)
    local groupId = frame.groupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    if not group
        or not CanUsePanelResizeInteractions(groupId, group)
        or not delta
        or delta == 0 then
        return
    end

    local style = group.style
    if not style then
        return
    end

    CancelCoordinateEdit(frame.coordLabel)
    CancelCoordinateEdit(frame.sizeLabel)
    CooldownCompanion:BeginMoverChromeWheelFade(frame)
    local step = delta > 0 and 1 or -1
    local changed = false

    -- A selected SECTION captures the wheel: the panel's own size keys stay
    -- untouched and the section's stored icon size moves instead (owner
    -- ruling 2026-08-28: panel-level resize drives the base cluster only).
    -- Current values resolve exactly the way ResolvePanelSectionGeometry
    -- resolves them, so the first wheel tick moves from what is on screen.
    local sectionAnchor, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
    if sectionAnchor and group.displayMode ~= "bars" then
        if style.maintainAspectRatio then
            local current = math_floor((tonumber(section.iconWidth)
                or tonumber(section.iconHeight)
                or style.buttonSize or ST.BUTTON_SIZE) + 0.5)
            local newSize = RoundAndClampPanelSize(current + step, 10, 150)
            if section.iconWidth ~= newSize then
                section.iconWidth = newSize
                changed = true
            end
        else
            local currentWidth = math_floor((tonumber(section.iconWidth)
                or style.iconWidth or style.buttonSize or ST.BUTTON_SIZE) + 0.5)
            local currentHeight = math_floor((tonumber(section.iconHeight)
                or style.iconHeight or style.buttonSize or ST.BUTTON_SIZE) + 0.5)
            local newWidth = RoundAndClampPanelSize(currentWidth + step, 10, 150)
            local newHeight = RoundAndClampPanelSize(currentHeight + step, 10, 150)
            if section.iconWidth ~= newWidth then
                section.iconWidth = newWidth
                changed = true
            end
            if section.iconHeight ~= newHeight then
                section.iconHeight = newHeight
                changed = true
            end
        end
        if changed then
            CooldownCompanion:UpdateGroupStyle(groupId)
        end
        ST.UpdateGroupSizeLabel(frame)
        return
    end

    if group.displayMode == "bars" then
        -- barHeight is thickness: screen height for horizontal fill and screen
        -- width after GetButtonDimensions transposes a vertical-fill bar.
        local current = math_floor((style.barHeight or 20) + 0.5)
        local newHeight = RoundAndClampPanelSize(current + step, 5, 100)
        if style.barHeight ~= newHeight then
            style.barHeight = newHeight
            changed = true
        end
    elseif style.maintainAspectRatio then
        local current = math_floor((style.buttonSize or ST.BUTTON_SIZE) + 0.5)
        local newSize = RoundAndClampPanelSize(current + step, 10, 150)
        if style.buttonSize ~= newSize then
            style.buttonSize = newSize
            changed = true
        end
    else
        local currentWidth = math_floor((style.iconWidth or style.buttonSize or ST.BUTTON_SIZE) + 0.5)
        local currentHeight = math_floor((style.iconHeight or style.buttonSize or ST.BUTTON_SIZE) + 0.5)
        local newWidth = RoundAndClampPanelSize(currentWidth + step, 10, 150)
        local newHeight = RoundAndClampPanelSize(currentHeight + step, 10, 150)
        if style.iconWidth ~= newWidth then
            style.iconWidth = newWidth
            changed = true
        end
        if style.iconHeight ~= newHeight then
            style.iconHeight = newHeight
            changed = true
        end
    end

    if changed then
        CooldownCompanion:UpdateGroupStyle(groupId)
    end
    ST.UpdateGroupSizeLabel(frame)
end

function ST.LockPanelFromMover(groupId)
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then
        return
    end

    -- Close this panel's mover without touching its owning group. The shared
    -- setter adds the session suppression that container and cursor previews
    -- need in addition to the ordinary panel's saved independent lock flag.
    local selected = CooldownCompanion._arrangeSelectedPanelId == groupId
    local cursorPreview = CooldownCompanion._cursorAnchorLayoutPreview
    selected = selected or (cursorPreview and cursorPreview.selectedGroupId == groupId or false)
    if not selected and group.parentContainerId and CooldownCompanion.IsContainerPanelSelected then
        selected = CooldownCompanion:IsContainerPanelSelected(group.parentContainerId, groupId)
    end
    if selected and CooldownCompanion.ClearArrangeMoverSelection then
        CooldownCompanion:ClearArrangeMoverSelection()
    end
    CooldownCompanion:SetPanelLocked(groupId, true)
    CooldownCompanion:CaptureArrangePanelRecord(groupId)
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:Print(group.name .. " locked.")
    CooldownCompanion:CheckArrangeModeAutoExit()
end

-- Both placeholder roots take the same rule: an Aura Panel owns the first, a
-- mixed panel carrying an aura section owns the second, and no panel ever owns
-- both (a panel is one or the other). Written out twice rather than through a
-- helper because this file rides its file-scope local ceiling.
function ST._SyncAuraPanelPlaceholderLevels(frame, raiseAboveWrapper)
    if not frame then
        return
    end

    local root = frame._auraPanelPlaceholderRoot
    if root then
        if raiseAboveWrapper then
            root:SetFrameStrata("FULLSCREEN_DIALOG")
            root:SetFrameLevel(89)
        else
            root:SetFrameStrata(frame:GetFrameStrata())
            root:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
        end
    end

    root = frame._auraSectionPlaceholderRoot
    if root then
        if raiseAboveWrapper then
            root:SetFrameStrata("FULLSCREEN_DIALOG")
            root:SetFrameLevel(89)
        else
            root:SetFrameStrata(frame:GetFrameStrata())
            root:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
        end
    end
end

local function SyncGroupControlLevels(frame, raiseAboveWrapper)
    if not frame then
        return
    end

    local strata = raiseAboveWrapper and "FULLSCREEN_DIALOG" or frame:GetFrameStrata()
    local baseLevel = raiseAboveWrapper and 90 or ((frame:GetFrameLevel() or 1) + 5)

    -- Explicit ordering against the section overlays, which join this band
    -- at baseLevel + 3 (ST.UpdateSectionMoverOverlays): every interactive
    -- chrome piece sits ABOVE them, so a section that overlaps a label, the
    -- grip, or the nudger can never intercept their mouse.
    if frame.dragHandle then
        frame.dragHandle:SetFrameStrata(strata)
        frame.dragHandle:SetFrameLevel(baseLevel)
    end
    if frame.coordLabel then
        frame.coordLabel:SetFrameStrata(strata)
        frame.coordLabel:SetFrameLevel(baseLevel + 4)
    end
    if frame.sizeLabel then
        frame.sizeLabel:SetFrameStrata(strata)
        frame.sizeLabel:SetFrameLevel(baseLevel + 5)
    end
    if frame.resizeGrip then
        frame.resizeGrip:SetFrameStrata(strata)
        frame.resizeGrip:SetFrameLevel(baseLevel + 6)
    end
    if frame.nudger then
        frame.nudger:SetFrameStrata(strata)
        frame.nudger:SetFrameLevel(baseLevel + 7)
        for buttonIndex, btn in ipairs(frame.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 8 + buttonIndex)
        end
    end
    ST._SyncAuraPanelPlaceholderLevels(frame, raiseAboveWrapper)
end

-- The resize grip lives on the panel's movable corner. Ordinary panels keep
-- the BOTTOMRIGHT default; a parked cursor panel's anchored point is fixed at
-- the dummy cursor, so the opposite corner is the one that tracks resizes.
function CooldownCompanion:RepositionPanelResizeGrip(frame)
    local grip = frame.resizeGrip
    if not grip then
        return
    end
    local group = frame.groupId and self.db.profile.groups[frame.groupId]
    local xSide, ySide = "RIGHT", "BOTTOM"
    if group and IsCursorAnchor(group.anchor) then
        local point = group.anchor.point or "CENTER"
        if point:find("RIGHT", 1, true) then
            xSide = "LEFT"
        end
        if point:find("BOTTOM", 1, true) then
            ySide = "TOP"
        end
    end
    if grip._cornerX == xSide and grip._cornerY == ySide then
        return
    end
    grip._cornerX = xSide
    grip._cornerY = ySide
    local corner = ySide .. xSide
    grip:ClearAllPoints()
    grip:SetPoint(corner, frame, corner,
        xSide == "LEFT" and 1 or -1,
        ySide == "TOP" and -1 or 1)
    -- The bracket's L opens toward the corner it lives on.
    ST.ApplyCornerBracketGrip(grip, xSide, ySide)
end

function CooldownCompanion:SetGroupDragControlsShown(frame, shown)
    if not frame then
        return
    end

    shown = not not shown
    local group = frame.groupId and CooldownCompanion.db.profile.groups[frame.groupId]
    local containerPreviewActive = frame.groupId and GetContainerPreviewSelectionState(frame.groupId) or false
    if frame.dragHandle then
        frame.dragHandle:SetIgnoreParentAlpha(shown and frame._unlockGhost == true)
        frame.dragHandle:SetShown(shown)
        if frame.dragHandle.lockButton then
            frame.dragHandle.lockButton:SetShown(shown)
        end
    end
    if frame.coordLabel then
        frame.coordLabel:SetShown(shown)
    end
    if frame.nudger then
        frame.nudger:SetShown(shown)
    end
    -- Cursor panels resize through the positioning preview's selection gate,
    -- same as their drag; other panels keep the plain resizable check.
    local resizeShown = shown
        and IsGroupPanelResizable(group)
        and (not IsCursorAnchor(group.anchor)
            or IsCursorAnchorLayoutPreviewSelected(CooldownCompanion, frame.groupId))
        or false
    if resizeShown and not frame.resizeGrip then
        frame.resizeGrip = CreatePanelResizeGrip(frame)
    end
    if frame.resizeGrip then
        if resizeShown then
            CooldownCompanion:RepositionPanelResizeGrip(frame)
        end
        frame.resizeGrip:SetShown(resizeShown)
    end
    if frame.sizeLabel then
        if resizeShown then
            ST.UpdateGroupSizeLabel(frame)
        end
        frame.sizeLabel:SetShown(resizeShown)
    end
    if shown then
        ApplySectionSelectionTint(frame)
    end
    CooldownCompanion:ApplyMoverChromeFadeToFrames(
        frame.dragHandle, frame.coordLabel, frame.nudger, frame.resizeGrip, frame.sizeLabel
    )

    -- Aura Panels replace their live container with a full-cell preview while
    -- they can be arranged. A container preview needs that preview on EVERY
    -- member, not only the selected member whose drag controls are showing.
    -- Presentation only -- the aura container stays bound so combat can restore
    -- it without an out-of-combat rebind.
    -- A mixed panel's AURA SECTION is the same trade in miniature and reads the
    -- same flag: its cluster is empty air without the tiles, and on a panel
    -- whose entries all sit in sections there would be nothing to grab at all.
    local auraPreviewShown = (ST.IsAuraPanelGroup(group) or ST.PanelHasAuraSection(group))
        and not CooldownCompanion._combatForcedLock
        and (shown == true or containerPreviewActive)
        or false
    CooldownCompanion:SetAuraPanelPlaceholderPreviewShown(frame, auraPreviewShown)

    -- Section click targets ride the same wide gate the aura placeholder
    -- preview does: every member of an active container preview shows its
    -- sections, not only the selected one -- unlock-all must reveal what is
    -- addressable (owner finding, P3 validation). Clicking one on an
    -- unselected panel selects the panel AND the section in one gesture
    -- (ActivateArrangeSection piggybacks the panel activation).
    ST.SetSectionMoverOverlaysShown(CooldownCompanion, frame, group,
        (shown == true or containerPreviewActive)
            and not CooldownCompanion._combatForcedLock)
end

-- Independently unlocked panels sit outside a container preview, so toolbar
-- solo changes update only their mover chrome. Runtime displays and panel
-- contents stay untouched.
function CooldownCompanion:RefreshIndependentPanelMoverChrome(groupId)
    local group = self.db and self.db.profile and self.db.profile.groups
        and self.db.profile.groups[groupId]
    if not group
        or (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
        or (group.parentContainerId
            and self:IsContainerUnlockPreviewActive(group.parentContainerId)) then
        return
    end

    local shown = self:IsUnlockToolbarPanelEligible(groupId, group)
        and (self._arrangeSoloContainerId == nil
            or self._arrangeSelectedPanelId == groupId)
        or false
    if self:IsStandaloneTexturePanelGroup(group) then
        if self.SetIndependentStandalonePanelMoverShown then
            self:SetIndependentStandalonePanelMoverShown(groupId, shown)
        end
        return
    end

    local frame = self.groupFrames and self.groupFrames[groupId]
    if frame then
        self:SetGroupDragControlsShown(frame, shown)
        self:UpdateGroupClickthrough(groupId)
    end
end

function CooldownCompanion:RefreshAllIndependentPanelMoverChrome()
    for groupId, group in pairs(self.db.profile.groups or {}) do
        if group and group.locked == false then
            self:RefreshIndependentPanelMoverChrome(groupId)
        end
    end
end

-- Private helpers consumed by later GroupFrame files.
GF.UpdateResizedPanelContainerWrapper = UpdateResizedPanelContainerWrapper
GF.SyncGroupControlLevels = SyncGroupControlLevels
GF.CreateNudger = CreateNudger
GF.RefreshConfigPanelIfShown = RefreshConfigPanelIfShown
GF.CanUsePanelResizeInteractions = CanUsePanelResizeInteractions
GF.OnUnlockedPanelMouseWheel = OnUnlockedPanelMouseWheel
