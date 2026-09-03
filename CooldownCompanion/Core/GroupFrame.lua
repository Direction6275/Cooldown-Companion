--[[
    CooldownCompanion - GroupFrame
    Container frames for groups of buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local pairs = pairs
local ipairs = ipairs
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local math_abs = math.abs
local table_insert = table.insert
local table_sort = table.sort
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local issecretvalue = issecretvalue
local select = select
local wipe = wipe

-- Shared click-through and border helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local HideGlowStyles = ST._HideGlowStyles
local EntryRuntime = ST.EntryRuntime
local UnbindDurationText = CooldownCompanion.UnbindDurationText

local function UnregisterKeyPressHighlightButton(button)
    local unregister = ST._UnregisterKeyPressHighlightButton
    if unregister then
        unregister(button)
    end
end

local function RefreshButtonKeybindState(button, buttonData)
    if CooldownCompanion.RefreshResolvedItemKeybindState then
        CooldownCompanion:RefreshResolvedItemKeybindState(button, buttonData)
        return
    end

    local cache = ST._CacheButtonBindingKeys
    if cache then
        cache(button, buttonData)
    end
end

local function ClearButtonVisualState(button)
    local clear = ST._ClearButtonVisualState
    if clear then
        clear(button)
    end
end

local CURSOR_ANCHOR_TARGET = CooldownCompanion:GetCursorAnchorTargetName()
local DEFAULT_CURSOR_ANCHOR = CooldownCompanion:GetDefaultCursorPanelAnchor()
local CURSOR_ANCHOR_POINT = DEFAULT_CURSOR_ANCHOR.point or "BOTTOMLEFT"
local CURSOR_ANCHOR_RELATIVE_POINT = DEFAULT_CURSOR_ANCHOR.relativePoint or "CENTER"
local CURSOR_ANCHOR_X = DEFAULT_CURSOR_ANCHOR.x or 16
local CURSOR_ANCHOR_Y = DEFAULT_CURSOR_ANCHOR.y or 16
local CURSOR_LAYOUT_PREVIEW_ATLAS = "cursor_point_128"
local CURSOR_LAYOUT_PREVIEW_SIZE = 48
local CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH = 118
local CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT = 18
-- Default parking spot: above screen center, clear of the top-center arrange
-- toolbar and roughly where a live cursor hovers.
local CURSOR_LAYOUT_PREVIEW_DEFAULT_Y = 150
local CURSOR_LAYOUT_PREVIEW_TINT = { 0.35, 0.92, 1, 1 }
local SNAP_THRESHOLD = 8
local SNAP_VISIBLE_ALPHA_THRESHOLD = 0.05
-- Guide color per winning target scope: gold = panels touching, cyan = group
-- centered on group, silver = aligned to the screen itself.
local SNAP_GUIDE_COLORS = {
    panel = { 1, 0.82, 0, 0.9 },
    group = { 0.2, 0.8, 1, 0.9 },
    screen = { 0.85, 0.85, 0.85, 0.8 },
}
local SNAP_GUIDE_THICKNESS = 2
local dragSnapGuideOverlay = nil
local dragSnapGuideVertical = nil
local dragSnapGuideHorizontal = nil
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

local function IsCursorAnchor(anchor)
    return CooldownCompanion:IsCursorAnchor(anchor)
end

local function BuildDefaultCursorAnchor()
    return CooldownCompanion:GetDefaultCursorPanelAnchor()
end

-- Return the container frame name for a panel, or nil if not a panel.
local function GetPanelContainerFrameName(groupId)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    if not profile then return nil end
    local group = profile.groups[groupId]
    if group and group.parentContainerId then
        return "CooldownCompanionContainer" .. group.parentContainerId
    end
    return nil
end

-- Resolve lock + alpha for a group frame.
-- Panels normally use their own alpha, unless Group Alpha controls panels
-- anchored directly to their parent container.
-- Legacy groups (no container) use group.locked and group.baselineAlpha directly.
local function GetContainerState(groupId)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    if not profile then return true, 1 end
    local group = profile.groups[groupId]
    if not group then return true, 1 end

    if group.parentContainerId then
        local containerId, container
        if CooldownCompanion.GetPanelContainerAlphaSource then
            containerId, container = CooldownCompanion:GetPanelContainerAlphaSource(groupId)
        end
        if container then
            local alpha = CooldownCompanion.GetContainerAlphaValue
                and CooldownCompanion:GetContainerAlphaValue(containerId, container)
                or container.baselineAlpha
                or 1
            return CooldownCompanion._combatForcedLock or group.locked ~= false, alpha
        end

        if CooldownCompanion._combatForcedLock then
            return true, group.baselineAlpha or 1
        end
        if IsCursorAnchor(group.anchor) then
            return true, group.baselineAlpha or 1
        end
        -- Panel: own lock state (nil/true = locked, false = unlocked), panel's own alpha
        return group.locked ~= false, group.baselineAlpha or 1
    end

    if CooldownCompanion._combatForcedLock then
        return true, group.baselineAlpha or 1
    end

    -- Legacy path (no container)
    return group.locked ~= false, group.baselineAlpha or 1
end

local function IsSecretValue(value)
    if issecretvalue and issecretvalue(value) then
        return true
    end
    return false
end

local function ReadSafeAlphaValue(value)
    if IsSecretValue(value) then
        return nil
    end
    if value == nil then
        return nil
    end
    if type(value) ~= "number" then
        return nil
    end
    return value
end

local function GetGroupAnchorRelativeTo(group)
    local anchor = group and group.anchor
    return type(anchor) == "table" and anchor.relativeTo or anchor
end

local function SetExternalAnchorAlphaSyncActive(frame, active)
    if not frame then return end
    if active then
        frame._inheritsExternalAnchorAlpha = true
    else
        frame._inheritsExternalAnchorAlpha = nil
    end
end

local function IsExternalFrameAnchorTarget(self, group, parentFrame)
    if not (group and group.parentContainerId and parentFrame and group.inheritPanelAlpha ~= false) then
        return false
    end

    local relativeTo = GetGroupAnchorRelativeTo(group)
    if type(relativeTo) ~= "string" or relativeTo == "" or relativeTo == "UIParent" then
        return false
    end

    if self.ParseAddonAnchorFrameName and self:ParseAddonAnchorFrameName(relativeTo) ~= nil then
        return false
    end

    return _G[relativeTo] == parentFrame
end

local function ShouldSyncAnchorAlpha(self, groupId, parentFrame)
    local profile = self.db and self.db.profile
    local group = profile and profile.groups and profile.groups[groupId]

    if group and group.parentContainerId then
        if self:IsPanelAnchoredToPanel(groupId) then
            local inheritsPanelAlpha = self:ShouldInheritPanelAnchorAlpha(groupId)
            return inheritsPanelAlpha, inheritsPanelAlpha, false
        end
        local inheritsExternalAlpha = IsExternalFrameAnchorTarget(self, group, parentFrame)
        return inheritsExternalAlpha, inheritsExternalAlpha, inheritsExternalAlpha
    end

    return true, false, false
end

local function ApplyGroupOwnAlpha(frame)
    if not frame then return end

    local locked, baseAlpha = GetContainerState(frame.groupId)
    local alpha = locked and (baseAlpha or 1) or 1
    if locked then
        local currentAlpha, _, hasRuntimeAlpha = CooldownCompanion:GetPanelCurrentAlphaValue(frame.groupId)
        if hasRuntimeAlpha then
            alpha = currentAlpha
        end
    end

    if ST.IsGroupRuntimeLayoutPreviewActive
        and ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId) then
        frame._naturalAlpha = alpha
        frame:SetAlpha(1)
        return
    end

    frame._naturalAlpha = nil
    frame:SetAlpha(alpha)
end

local function ApplyCurrentAlphaIfPresent(owner, frame, groupId, group)
    local alpha, _, hasRuntimeAlpha = owner:GetPanelCurrentAlphaValue(groupId, group)
    if hasRuntimeAlpha then
        frame:SetAlpha(alpha)
    end
end

local function GetUnlockedPanelAlpha(frame)
    return frame and frame._unlockGhost and 0.4 or 1
end

local function GetAnchorInheritedAlpha(parentFrame)
    if not parentFrame then
        return 1
    end

    local alpha = ReadSafeAlphaValue(parentFrame._naturalAlpha)
    if alpha ~= nil then
        return alpha
    end

    local parentGroupId = parentFrame.groupId
    if parentGroupId and CooldownCompanion.alphaState then
        local state = CooldownCompanion.alphaState[parentGroupId]
        alpha = state and ReadSafeAlphaValue(state.currentAlpha) or nil
        if alpha ~= nil then
            return alpha
        end
    end

    if parentFrame.IsShown then
        local shown = parentFrame:IsShown()
        if IsSecretValue(shown) then
            return nil
        end
        if shown == nil then
            return nil
        end
        if not shown then
            return 0
        end
    end

    if parentFrame.GetEffectiveAlpha then
        alpha = parentFrame:GetEffectiveAlpha()
        if IsSecretValue(alpha) then
            return nil
        end
        if alpha == nil then
            return nil
        end
        return alpha
    end
    if parentFrame.GetAlpha then
        alpha = parentFrame:GetAlpha()
        if IsSecretValue(alpha) then
            return nil
        end
        if alpha == nil then
            return nil
        end
        return alpha
    end
    return 1
end

local function GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    if buttonUsabilityOptions then
        return buttonUsabilityOptions
    end
    if self.GetGroupLayoutButtonUsabilityOptions then
        return self:GetGroupLayoutButtonUsabilityOptions(groupId, group)
    end
    return nil
end

local function GetContainerPreviewSelectionState(groupId)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local containerId = group and group.parentContainerId or nil
    if not containerId then
        return false, false, nil
    end
    if (CooldownCompanion.IsArrangePanelSuppressed
            and CooldownCompanion:IsArrangePanelSuppressed(groupId))
        or (CooldownCompanion.IsArrangeContainerSuppressed
            and CooldownCompanion:IsArrangeContainerSuppressed(containerId)) then
        return false, false, containerId
    end

    local previewActive = CooldownCompanion.IsContainerUnlockPreviewActive
        and CooldownCompanion:IsContainerUnlockPreviewActive(containerId)
        or false
    if not previewActive then
        return false, false, containerId
    end

    local selected = CooldownCompanion.IsContainerPanelSelected
        and CooldownCompanion:IsContainerPanelSelected(containerId, groupId)
        or false
    return true, selected, containerId
end

-- Frame creation anchors before the coord label exists, so a position that
-- arrives early is held on the frame. Call with no coordinates once the label
-- is built to replay it; otherwise the label stays blank until the first move.
local function UpdateCoordLabel(frame, x, y)
    -- ONE owner at a time: while a section is selected, the readout shows
    -- ITS offsets, whatever panel-side refresh (anchoring, drags, chrome
    -- re-shows) tried to write. Deselecting hands the label back to the
    -- panel. Guarded at the sink so no writer can forget the rule.
    local groupId = frame.groupId
    if groupId and CooldownCompanion.GetArrangeSelectedSectionAnchor then
        local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
        if section then
            x = tonumber(section.offsetX) or 0
            y = tonumber(section.offsetY) or 0
        end
    end
    x = x or frame._pendingCoordX
    y = y or frame._pendingCoordY
    if not (x and y) then
        return
    end
    if frame.coordLabel then
        frame._pendingCoordX, frame._pendingCoordY = nil, nil
        frame.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x, y))
    else
        frame._pendingCoordX, frame._pendingCoordY = x, y
    end
end

function ST.UpdateGroupSizeLabel(frame)
    if not (frame and frame.sizeLabel) then
        return
    end

    local group = frame.groupId and CooldownCompanion.db.profile.groups[frame.groupId]
    local style = group and group.style
    if not style then
        return
    end

    local kind
    if group.displayMode == "bars" then
        kind = "bar"
    elseif style.maintainAspectRatio then
        kind = "square"
    else
        kind = "icon"
    end

    if frame.sizeLabel._editing then
        if frame.sizeLabel._sizeKind == kind then
            return
        end
        -- A mode change invalidates the active edit's field schema.
        ST.CancelCoordinateEdit(frame.sizeLabel)
    end
    frame.sizeLabel._sizeKind = kind

    -- With a section selected, the ONE chrome kit speaks for THAT section
    -- (owner ruling 2026-08-29: no second chrome surface -- the gold tint is
    -- the signal): same fields, same kinds (a sectioned panel is an icon
    -- panel by definition), values resolved with the layout's own fallbacks.
    local sectionAnchor, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(frame.groupId)
    if sectionAnchor and kind ~= "bar" then
        if kind == "square" then
            local size = ST.RoundToTenths(tonumber(section.iconWidth)
                or tonumber(section.iconHeight)
                or style.buttonSize or ST.BUTTON_SIZE)
            ST.ConfigureEditableCoordLabel(frame.sizeLabel, "size:", nil, true)
            frame.sizeLabel.text:SetText(("size:%.1f"):format(size))
        else
            local width = ST.RoundToTenths(tonumber(section.iconWidth)
                or style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
            local height = ST.RoundToTenths(tonumber(section.iconHeight)
                or style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
            ST.ConfigureEditableCoordLabel(frame.sizeLabel, "w:", "h:", false)
            frame.sizeLabel.text:SetText(("w:%.1f, h:%.1f"):format(width, height))
        end
        return
    end

    if kind == "bar" then
        local length = ST.RoundToTenths(style.barLength or 180)
        local height = ST.RoundToTenths(style.barHeight or 20)
        ST.ConfigureEditableCoordLabel(frame.sizeLabel, "l:", "h:", false)
        frame.sizeLabel.text:SetText(("l:%.1f, h:%.1f"):format(length, height))
    elseif kind == "square" then
        local size = ST.RoundToTenths(style.buttonSize or ST.BUTTON_SIZE)
        ST.ConfigureEditableCoordLabel(frame.sizeLabel, "size:", nil, true)
        frame.sizeLabel.text:SetText(("size:%.1f"):format(size))
    else
        local width = ST.RoundToTenths(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
        local height = ST.RoundToTenths(style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
        ST.ConfigureEditableCoordLabel(frame.sizeLabel, "w:", "h:", false)
        frame.sizeLabel.text:SetText(("w:%.1f, h:%.1f"):format(width, height))
    end
end

-- The ONE chrome kit changes color instead of growing a second surface
-- (owner ruling 2026-08-29): while a section is selected, the handle bar,
-- both readouts, the grip, and the nudger arrows go gold -- the signal that
-- every control now drives the section. Grey/white is the panel's own state.
local function ApplySectionSelectionTint(frame)
    if not frame then return end
    local selectedAnchor = CooldownCompanion:GetArrangeSelectedSectionAnchor(frame.groupId)
    local selected = selectedAnchor ~= nil
    local r, g, b = 1, 1, 1
    if selected then
        r, g, b = 1, 0.82, 0
    end
    if frame.dragHandle then
        if selected then
            frame.dragHandle:SetBackdropColor(0.35, 0.28, 0.04, 0.85)
        else
            frame.dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        end
        if frame.dragHandle.text then
            -- The bar names what the chrome is driving: the panel, or the
            -- panel's selected section.
            local group = CooldownCompanion.db.profile.groups[frame.groupId]
            local name = (group and group.name) or ""
            if selectedAnchor then
                name = name .. ": "
                    .. ST.PANEL_SECTION_ANCHOR_LABELS[selectedAnchor] .. " Section"
            end
            frame.dragHandle.text:SetText(name)
            frame.dragHandle.text:SetTextColor(r, g, b, 1)
        end
    end
    if frame.coordLabel and frame.coordLabel.text then
        frame.coordLabel.text:SetTextColor(r, g, b, 1)
    end
    if frame.sizeLabel and frame.sizeLabel.text then
        frame.sizeLabel.text:SetTextColor(r, g, b, 1)
    end
    -- Deliberately NOT the panel's corner grip: it is base-cluster-scoped in
    -- every state (the selected section carries its own gold grabber), so it
    -- keeps its plain look as the one grey control while a section is gold.
    if frame.nudger and frame.nudger.RefreshSectionTint then
        frame.nudger.RefreshSectionTint()
    end
end

local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel

local ComputeGroupFrameCoordinates
local ComputeContainerFrameCoordinates

local function StopCoordinateDragUpdates(frame)
    frame._coordDragElapsed = nil
    frame._coordDragUpdater = nil
    frame._coordDragRelativeTo = nil
    frame._coordDragRelativeFrame = nil
    frame._coordDragAnchorState = nil
    frame._coordDragReferenceReady = nil
    frame._coordinateSnapUpdatesPerFrame = nil
    frame:SetScript("OnUpdate", nil)
    if CooldownCompanion.EndDragSnapSession then
        CooldownCompanion:EndDragSnapSession(frame, false)
    end
end

local function CoordinateDragOnUpdate(self, elapsed)
    if not self._dragInProgress then
        StopCoordinateDragUpdates(self)
        return
    end

    CooldownCompanion:UpdateDragSnapSession(self)
    self._coordDragElapsed = (self._coordDragElapsed or 0) + elapsed
    if self._coordDragElapsed < 0.05 then
        return
    end

    self._coordDragElapsed = 0
    self._coordDragUpdater(self)
end

local function StartCoordinateDragUpdates(frame, updater)
    frame._coordDragElapsed = 0
    frame._coordDragUpdater = updater
    frame._coordinateSnapUpdatesPerFrame = true
    frame:SetScript("OnUpdate", CoordinateDragOnUpdate)
end

local function PreviewMapContains(map, groupId)
    if not map then
        return false
    end
    if map[groupId] then
        return true
    end
    local numericId = tonumber(groupId)
    if numericId and map[numericId] then
        return true
    end
    local stringId = tostring(groupId)
    return stringId and map[stringId] == true or false
end

local function GroupIdsEqual(left, right)
    if left == right then
        return true
    end
    if left == nil or right == nil then
        return false
    end
    return tostring(left) == tostring(right)
end

local function IsCursorAnchorLayoutPreviewGroupActive(self, groupId)
    local preview = self and self._cursorAnchorLayoutPreview
    return preview and PreviewMapContains(preview.activeGroupIds, groupId) or false
end

local function IsCursorAnchorLayoutPreviewSelected(self, groupId)
    local preview = self and self._cursorAnchorLayoutPreview
    return preview
        and preview.selectedGroupId == groupId
        and PreviewMapContains(preview.activeGroupIds, groupId)
        or false
end

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then return -width / 2, height / 2 end
    if point == "TOP" then return 0, height / 2 end
    if point == "TOPRIGHT" then return width / 2, height / 2 end
    if point == "LEFT" then return -width / 2, 0 end
    if point == "CENTER" then return 0, 0 end
    if point == "RIGHT" then return width / 2, 0 end
    if point == "BOTTOMLEFT" then return -width / 2, -height / 2 end
    if point == "BOTTOM" then return 0, -height / 2 end
    if point == "BOTTOMRIGHT" then return width / 2, -height / 2 end
    return 0, 0
end

-- Shared with Core/PanelSections.lua so a sectioned panel's anchor-drift
-- compensation measures its hold point with the exact same arithmetic.
ST._GetPanelAnchorOffset = GetAnchorOffset

local function GetFrameSizeInUIParentSpace(frame)
    if not (frame and frame.GetSize) then
        return nil, nil
    end

    local width, height = frame:GetSize()
    if not (width and height) then
        return nil, nil
    end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or nil
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or nil
    if frameScale and uiScale and uiScale > 0 then
        local scaleRatio = frameScale / uiScale
        width = width * scaleRatio
        height = height * scaleRatio
    end

    return width, height
end

local function GetFrameRectInUIParentSpace(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetBottom and frame.GetTop) then
        return nil, nil, nil, nil
    end

    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    if not (left and right and bottom and top) then
        return nil, nil, nil, nil
    end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or nil
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or nil
    if frameScale and uiScale and uiScale > 0 then
        local scaleRatio = frameScale / uiScale
        left = left * scaleRatio
        right = right * scaleRatio
        bottom = bottom * scaleRatio
        top = top * scaleRatio
    end

    return left, right, bottom, top
end

local function HideDragSnapGuides()
    if dragSnapGuideVertical then
        dragSnapGuideVertical:Hide()
    end
    if dragSnapGuideHorizontal then
        dragSnapGuideHorizontal:Hide()
    end
end

local function EnsureDragSnapGuides()
    if dragSnapGuideOverlay then
        return
    end

    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(1000)
    overlay:EnableMouse(false)

    local vertical = overlay:CreateTexture(nil, "OVERLAY")
    vertical:SetColorTexture(SNAP_GUIDE_COLORS.panel[1], SNAP_GUIDE_COLORS.panel[2], SNAP_GUIDE_COLORS.panel[3], SNAP_GUIDE_COLORS.panel[4])
    vertical:SetWidth(SNAP_GUIDE_THICKNESS)
    vertical:Hide()

    local horizontal = overlay:CreateTexture(nil, "OVERLAY")
    horizontal:SetColorTexture(SNAP_GUIDE_COLORS.panel[1], SNAP_GUIDE_COLORS.panel[2], SNAP_GUIDE_COLORS.panel[3], SNAP_GUIDE_COLORS.panel[4])
    horizontal:SetHeight(SNAP_GUIDE_THICKNESS)
    horizontal:Hide()

    dragSnapGuideOverlay = overlay
    dragSnapGuideVertical = vertical
    dragSnapGuideHorizontal = horizontal
end

local function AddDragSnapTarget(targets, value, kind, isCenter, scope, orthoMin, orthoMax)
    targets[#targets + 1] = {
        value = value,
        kind = kind,
        isCenter = isCenter or nil,
        scope = scope,
        orthoMin = orthoMin,
        orthoMax = orthoMax,
    }
end

local function AddDragSnapRectTargets(session, frame, prefix)
    local left, right, bottom, top = GetFrameRectInUIParentSpace(frame)
    if not left then
        return false
    end

    AddDragSnapTarget(session.targetsX, left, prefix .. "Left", nil, nil, bottom, top)
    AddDragSnapTarget(session.targetsX, (left + right) / 2, prefix .. "CenterX", true, "panel", bottom, top)
    AddDragSnapTarget(session.targetsX, right, prefix .. "Right", nil, nil, bottom, top)
    AddDragSnapTarget(session.targetsY, bottom, prefix .. "Bottom", nil, nil, left, right)
    AddDragSnapTarget(session.targetsY, (bottom + top) / 2, prefix .. "CenterY", true, "panel", left, right)
    AddDragSnapTarget(session.targetsY, top, prefix .. "Top", nil, nil, left, right)
    return true
end

local function AddDragSnapCandidate(session, candidateFrame, candidateGroupId, excludeFn)
    if not (candidateFrame and candidateFrame.IsVisible and candidateFrame:IsVisible()) then
        return
    end
    if excludeFn and excludeFn(candidateFrame, candidateGroupId) then
        return
    end
    AddDragSnapRectTargets(session, candidateFrame, "frame")
end

local function GroupFrameRendersVisibleSnapTarget(frame, groupId)
    local isLocked = GetContainerState(groupId)
    if not isLocked then
        return true
    end

    local effectiveAlpha = frame:GetEffectiveAlpha()
    if IsSecretValue(effectiveAlpha) or effectiveAlpha == nil
        or effectiveAlpha <= SNAP_VISIBLE_ALPHA_THRESHOLD then
        return false
    end

    for _, button in ipairs(frame.buttons or {}) do
        local isShown = button:IsShown()
        -- Shell alpha 0 = the button renders nothing CC-side (icon hidden,
        -- every region alpha-0) while button:GetAlpha() still reports 1, so
        -- it must not count as a visible snap target. Dim shells (0.4) and
        -- never-styled buttons (nil) do render.
        if not IsSecretValue(isShown) and isShown and button._auraShellIconAlpha ~= 0 then
            local alpha = button:GetAlpha()
            if not IsSecretValue(alpha) and alpha ~= nil and alpha > SNAP_VISIBLE_ALPHA_THRESHOLD then
                return true
            end
        end
    end
    return false
end

local function SortDragSnapTargets(left, right)
    return left.value < right.value
end

-- Centers snap only to center targets and edges only to edge targets: the
-- cross-pairings (an edge passing a center or vice versa) produce guides no
-- one reads as alignment (owner ruling 2026-08-24). Center scopes are strict:
-- a dragged group's midpoint matches only other groups' midpoints (and screen
-- centerlines), a dragged panel's midpoint only other panels' (and screen).
local function FindNearestDragSnap(targets, firstValue, centerValue, lastValue, dragClass, previousTarget, orthoMin, orthoMax)
    -- 2px hysteresis: the target currently shown keeps its snap until a rival
    -- is decisively closer, so the guide does not hop position and color at
    -- every crossover between near-equal candidates.
    local bestScore, bestDelta, bestTargetValue, bestTarget
    for index = 1, #targets do
        local target = targets[index]
        local targetValue = target.value
        local bonus = target == previousTarget and 2 or 0
        if target.orthoMin ~= nil
            and (target.orthoMin - 40 > orthoMax
                or target.orthoMax + 40 < orthoMin) then
            -- Ortho gate (40px): a target may snap only if its span on the
            -- OTHER axis overlaps the dragged rect's span, give or take —
            -- you snap to what you are beside, not to everything sharing a
            -- coordinate across the screen. Screen lines are exempt (no
            -- orthoMin). Not a file-level constant: the main chunk rides the
            -- 200-local ceiling.
        elseif target.isCenter then
            local scope = target.scope
            if scope == "screen" or scope == dragClass then
                local delta = targetValue - centerValue
                local distance = math_abs(delta)
                if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                    bestScore = distance - bonus
                    bestDelta = delta
                    bestTargetValue = targetValue
                    bestTarget = target
                end
            end
        else
            local delta = targetValue - firstValue
            local distance = math_abs(delta)
            if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                bestScore = distance - bonus
                bestDelta = delta
                bestTargetValue = targetValue
                bestTarget = target
            end

            delta = targetValue - lastValue
            distance = math_abs(delta)
            if distance <= SNAP_THRESHOLD and (bestScore == nil or distance - bonus < bestScore) then
                bestScore = distance - bonus
                bestDelta = delta
                bestTargetValue = targetValue
                bestTarget = target
            end
        end
    end
    return bestDelta, bestTargetValue, bestTarget
end

function CooldownCompanion:BeginDragSnapSession(frame, excludeFn)
    if not frame then
        return
    end

    self:EndDragSnapSession(frame, false)
    local screenLeft, screenRight, screenBottom, screenTop = GetFrameRectInUIParentSpace(UIParent)
    if not screenLeft then
        return
    end

    local session = {
        targetsX = {},
        targetsY = {},
        dragFrame = frame._dragSnapRectFrame or frame,
        dragClass = frame.containerId and "group" or "panel",
        screenLeft = screenLeft,
        screenBottom = screenBottom,
    }
    AddDragSnapTarget(session.targetsX, screenLeft, "screenLeft", nil, "screen")
    AddDragSnapTarget(session.targetsX, (screenLeft + screenRight) / 2, "screenCenterX", true, "screen")
    AddDragSnapTarget(session.targetsX, screenRight, "screenRight", nil, "screen")
    AddDragSnapTarget(session.targetsY, screenBottom, "screenBottom", nil, "screen")
    AddDragSnapTarget(session.targetsY, (screenBottom + screenTop) / 2, "screenCenterY", true, "screen")
    AddDragSnapTarget(session.targetsY, screenTop, "screenTop", nil, "screen")

    -- Group-on-group centering: each other group's panel-union midpoint is a
    -- center target (scope "group"). Union edges are omitted on purpose: they
    -- coincide with outermost panel edges, which are already panel targets.
    -- The union is computed from the member PANELS directly: chrome may be
    -- hidden (drag-solo) while the displays stay visible and snappable.
    if session.dragClass == "group" then
        local unions = {}
        local function AccumulateGroupUnion(cid, rectFrame)
            local l, r, b, t = GetFrameRectInUIParentSpace(rectFrame)
            if not l then
                return
            end
            local u = unions[cid]
            if not u then
                unions[cid] = { l = l, r = r, b = b, t = t }
            else
                if l < u.l then u.l = l end
                if r > u.r then u.r = r end
                if b < u.b then u.b = b end
                if t > u.t then u.t = t end
            end
        end
        for groupId, candidateFrame in pairs(self.groupFrames or {}) do
            local group = self.db and self.db.profile and self.db.profile.groups
                and self.db.profile.groups[groupId]
                or nil
            local cid = group and group.parentContainerId
            if cid and cid ~= frame.containerId then
                -- Texture panels live on their aura texture host, not the
                -- group frame; both contribute so texture-only groups get a
                -- center and mixed groups get the true midpoint.
                if not self:IsStandaloneTexturePanelGroup(group)
                    and GroupFrameRendersVisibleSnapTarget(candidateFrame, groupId) then
                    AccumulateGroupUnion(cid, candidateFrame)
                end
                local textureHost = self.GetAuraTextureHostForGroupFrame
                    and self:GetAuraTextureHostForGroupFrame(candidateFrame)
                    or nil
                if textureHost and textureHost:IsVisible() then
                    AccumulateGroupUnion(cid, textureHost)
                end
            end
        end
        -- No ortho gate on group centers: centering a group on another is a
        -- deliberate ACROSS-a-gap alignment (stacking at a distance), exactly
        -- what the gate would veto. One target per group keeps them quiet.
        for _, u in pairs(unions) do
            AddDragSnapTarget(session.targetsX, (u.l + u.r) / 2, "groupCenterX", true, "group")
            AddDragSnapTarget(session.targetsY, (u.b + u.t) / 2, "groupCenterY", true, "group")
        end
    end

    for groupId, candidateFrame in pairs(self.groupFrames or {}) do
        local group = self.db and self.db.profile and self.db.profile.groups
            and self.db.profile.groups[groupId]
            or nil
        if not (group and self:IsStandaloneTexturePanelGroup(group))
            and GroupFrameRendersVisibleSnapTarget(candidateFrame, groupId) then
            AddDragSnapCandidate(session, candidateFrame, groupId, excludeFn)
        end
        local textureHost = self.GetAuraTextureHostForGroupFrame
            and self:GetAuraTextureHostForGroupFrame(candidateFrame)
            or nil
        AddDragSnapCandidate(session, textureHost, groupId, excludeFn)
    end

    local castBarMover = self.GetIndependentCastBarSnapFrame and self:GetIndependentCastBarSnapFrame() or nil
    AddDragSnapCandidate(session, castBarMover, nil, excludeFn)
    local resourceStackWrapper = self.GetIndependentResourceStackSnapFrame
        and self:GetIndependentResourceStackSnapFrame()
        or nil
    AddDragSnapCandidate(session, resourceStackWrapper, nil, excludeFn)

    table_sort(session.targetsX, SortDragSnapTargets)
    table_sort(session.targetsY, SortDragSnapTargets)
    frame._snapSession = session
    local tracker = frame._dragSnapUpdateTracker
    if not tracker then
        tracker = CreateFrame("Frame", nil, frame)
        tracker._dragFrame = frame
        tracker._onUpdate = function(self)
            local dragFrame = self._dragFrame
            if not (dragFrame and dragFrame._snapSession) then
                self:SetScript("OnUpdate", nil)
                return
            end
            if not dragFrame._coordinateSnapUpdatesPerFrame then
                CooldownCompanion:UpdateDragSnapSession(dragFrame)
            end
        end
        frame._dragSnapUpdateTracker = tracker
    end
    tracker:SetScript("OnUpdate", tracker._onUpdate)
end

function CooldownCompanion:UpdateDragSnapSession(frame)
    local session = frame and frame._snapSession or nil
    if not session then
        return
    end

    if IsShiftKeyDown() then
        session.snapDX = nil
        session.snapDY = nil
        -- Also forget the hysteresis targets: a bypassed snap must not keep
        -- its "currently shown" scoring bonus into the next live update.
        session.lastSnapTargetX = nil
        session.lastSnapTargetY = nil
        HideDragSnapGuides()
        return
    end

    local left, right, bottom, top = GetFrameRectInUIParentSpace(session.dragFrame)
    if not left then
        session.snapDX = nil
        session.snapDY = nil
        session.lastSnapTargetX = nil
        session.lastSnapTargetY = nil
        HideDragSnapGuides()
        return
    end

    local snapDX, snapX, snapTargetX = FindNearestDragSnap(session.targetsX, left, (left + right) / 2, right, session.dragClass, session.lastSnapTargetX, bottom, top)
    local snapDY, snapY, snapTargetY = FindNearestDragSnap(session.targetsY, bottom, (bottom + top) / 2, top, session.dragClass, session.lastSnapTargetY, left, right)
    session.lastSnapTargetX = snapTargetX
    session.lastSnapTargetY = snapTargetY
    session.snapDX = snapDX
    session.snapDY = snapDY

    if snapDX ~= nil or snapDY ~= nil then
        EnsureDragSnapGuides()
    end
    if snapDX ~= nil then
        local color = SNAP_GUIDE_COLORS[snapTargetX and snapTargetX.scope or "panel"] or SNAP_GUIDE_COLORS.panel
        dragSnapGuideVertical:SetColorTexture(color[1], color[2], color[3], color[4])
        dragSnapGuideVertical:ClearAllPoints()
        dragSnapGuideVertical:SetPoint("TOP", dragSnapGuideOverlay, "TOPLEFT", snapX - session.screenLeft, 0)
        dragSnapGuideVertical:SetPoint("BOTTOM", dragSnapGuideOverlay, "BOTTOMLEFT", snapX - session.screenLeft, 0)
        dragSnapGuideVertical:Show()
    elseif dragSnapGuideVertical then
        dragSnapGuideVertical:Hide()
    end
    if snapDY ~= nil then
        local color = SNAP_GUIDE_COLORS[snapTargetY and snapTargetY.scope or "panel"] or SNAP_GUIDE_COLORS.panel
        dragSnapGuideHorizontal:SetColorTexture(color[1], color[2], color[3], color[4])
        dragSnapGuideHorizontal:ClearAllPoints()
        dragSnapGuideHorizontal:SetPoint("LEFT", dragSnapGuideOverlay, "BOTTOMLEFT", 0, snapY - session.screenBottom)
        dragSnapGuideHorizontal:SetPoint("RIGHT", dragSnapGuideOverlay, "BOTTOMRIGHT", 0, snapY - session.screenBottom)
        dragSnapGuideHorizontal:Show()
    elseif dragSnapGuideHorizontal then
        dragSnapGuideHorizontal:Hide()
    end
end

function CooldownCompanion:EndDragSnapSession(frame, apply)
    local session = frame and frame._snapSession or nil
    HideDragSnapGuides()
    local tracker = frame and frame._dragSnapUpdateTracker
    if tracker then
        tracker:SetScript("OnUpdate", nil)
    end
    if not session then
        return nil, nil
    end

    local snapDX, snapDY
    if apply and not IsShiftKeyDown() then
        snapDX = session.snapDX
        snapDY = session.snapDY
    end
    frame._snapSession = nil
    return snapDX, snapDY
end

local function BeginSelfExcludedDragSnapSession(frame)
    CooldownCompanion:BeginDragSnapSession(frame, function(candidateFrame)
        return candidateFrame == frame
    end)
end

local function ApplyEndedDragSnapSession(frame, apply)
    if apply then
        CooldownCompanion:UpdateDragSnapSession(frame)
    end
    local snapDX, snapDY = CooldownCompanion:EndDragSnapSession(frame, apply)
    if snapDX ~= nil or snapDY ~= nil then
        frame:AdjustPointsOffset(snapDX or 0, snapDY or 0)
    end
end

local function RoundPreviewOffset(value)
    return math_floor(((value or 0) * 10) + 0.5) / 10
end

local function ApplyUnsafeAnchorVisualFallback(frame, anchor, relativeFrame)
    if not (frame and anchor and relativeFrame and relativeFrame.GetCenter and relativeFrame.GetSize) then
        return false
    end

    local rcx, rcy = relativeFrame:GetCenter()
    local rw, rh = relativeFrame:GetSize()
    if not (rcx and rcy and rw and rh) then
        return false
    end

    local desiredPoint = anchor.point or "CENTER"
    local desiredRelPoint = anchor.relativePoint or "CENTER"
    local offsetX = anchor.x or 0
    local offsetY = anchor.y or 0
    local rax, ray = GetAnchorOffset(desiredRelPoint, rw, rh)

    frame:ClearAllPoints()
    frame:SetPoint(desiredPoint, UIParent, "BOTTOMLEFT", rcx + rax + offsetX, rcy + ray + offsetY)
    return true
end

local function ParseAddonAnchorFrameName(frameName)
    return CooldownCompanion:ParseAddonAnchorFrameName(frameName)
end

local function WouldFrameDependencyCreateCircularAnchor(self, sourceId, sourceKind, targetFrame, visited, depth)
    if not targetFrame or targetFrame == UIParent then return false end

    depth = depth or 0
    if depth > 24 then return false end

    visited = visited or {}
    if visited[targetFrame] then return false end
    visited[targetFrame] = true

    local targetKind, targetId = ParseAddonAnchorFrameName(targetFrame:GetName())
    if targetKind and targetId and self:WouldCreateCircularAnchor(sourceId, targetId, targetKind, sourceKind) then
        return true
    end

    local pointIndex = 1
    while true do
        local point, relativeFrame = targetFrame:GetPoint(pointIndex)
        if not point then break end
        if relativeFrame
            and relativeFrame ~= targetFrame
            and relativeFrame.GetPoint
            and WouldFrameDependencyCreateCircularAnchor(self, sourceId, sourceKind, relativeFrame, visited, depth + 1) then
            return true
        end
        pointIndex = pointIndex + 1
    end

    return false
end

local function ResolveSafeAnchorTarget(self, sourceId, sourceKind, relativeTo)
    local relativeFrame, anchorState = self:ResolveAddonFrameAnchorTarget(sourceId, sourceKind, relativeTo)
    if not relativeFrame then
        return nil, anchorState
    end

    if WouldFrameDependencyCreateCircularAnchor(self, sourceId, sourceKind or "group", relativeFrame) then
        return nil, "unsafe"
    end

    return relativeFrame, anchorState
end

function CooldownCompanion:IsCursorAnchorLayoutPreviewGroupActive(groupId)
    return IsCursorAnchorLayoutPreviewGroupActive(self, groupId)
end

function CooldownCompanion:IsCursorAnchorLayoutPreviewSelected(groupId)
    return IsCursorAnchorLayoutPreviewSelected(self, groupId)
end

function CooldownCompanion:GetContainerAnchorTargetState(containerId, relativeTo)
    local _, anchorState = ResolveSafeAnchorTarget(self, containerId, "container", relativeTo)
    return anchorState
end

local function NormalizeCompactGrowthDirection(growthDirection)
    if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
        return "start"
    end
    if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
        return "end"
    end
    return "center"
end

local function GetGrowthMultipliers(growthOrigin)
    if growthOrigin == "TOPRIGHT" then return -1, -1, "TOPRIGHT" end
    if growthOrigin == "BOTTOMLEFT" then return 1, 1, "BOTTOMLEFT" end
    if growthOrigin == "BOTTOMRIGHT" then return -1, 1, "BOTTOMRIGHT" end
    return 1, -1, "TOPLEFT"
end

-- Centered growth stores the PINNED EDGE as the growthOrigin ("TOP" =
-- Centered, Down). The edge is only meaningful when its axis matches the
-- panel orientation; a mismatch (import, mode swap) falls back to the
-- corner path, where GetGrowthMultipliers folds it to TOPLEFT. Shared on
-- ST so the config preview lays out with the exact same rule, and kept in
-- a do-block because this chunk rides the 200-local ceiling.
do
    local edges = {
        TOP = "horizontal", BOTTOM = "horizontal",
        LEFT = "vertical", RIGHT = "vertical",
    }
    function ST.GetCenteredGrowthEdge(growthOrigin, orientation)
        return edges[growthOrigin] == orientation and growthOrigin or nil
    end
    function ST.IsCenteredGrowthOrigin(growthOrigin)
        return edges[growthOrigin] ~= nil
    end
end

local FLIP_HORIZONTAL = {
    TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
    BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
}
local FLIP_VERTICAL = {
    TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
    BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
}

local function GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, growthOrigin)
    if not growthOrigin or ST.IsCenteredGrowthOrigin(growthOrigin) then
        -- An ACTIVE centered edge is handled before this is consulted; a
        -- centered value reaching here is axis-mismatched and folds to
        -- TOPLEFT like the multiplier path does.
        growthOrigin = "TOPLEFT"
    end
    if compactGrowthDirection == "start" then
        return growthOrigin
    end
    if compactGrowthDirection == "end" then
        if orientation == "horizontal" then
            return FLIP_HORIZONTAL[growthOrigin]
        else
            return FLIP_VERTICAL[growthOrigin]
        end
    end
    return nil
end

local function GetCompactSlotForIndex(visibleIndex, visibleCount, buttonsPerRow, orientation, compactGrowthDirection)
    local slotIndex = visibleIndex - 1
    if orientation == "horizontal" then
        local row = math_floor(slotIndex / buttonsPerRow)
        local indexInRow = slotIndex % buttonsPerRow
        local totalCols = math_min(visibleCount, buttonsPerRow)
        local col = indexInRow
        if compactGrowthDirection == "end" then
            -- Mirror against the layout's full horizontal span so trailing
            -- partial rows stay right-aligned.
            col = totalCols - 1 - indexInRow
        end
        return row, col
    end

    local col = math_floor(slotIndex / buttonsPerRow)
    local indexInColumn = slotIndex % buttonsPerRow
    local totalRows = math_min(visibleCount, buttonsPerRow)
    local row = indexInColumn
    if compactGrowthDirection == "end" then
        -- Mirror against the layout's full vertical span so trailing partial
        -- columns stay bottom-aligned.
        row = totalRows - 1 - indexInColumn
    end
    return row, col
end

-- Reset per-button glow state when compact layout toggles visibility.
-- Hidden buttons skip visual updates, so caches must be invalidated on transitions.
local function ResetButtonGlowTransitionState(button)
    if not button then return end

    if HideGlowStyles then
        if button.procGlow then
            HideGlowStyles(button.procGlow)
        end
        if button.readyGlow then
            HideGlowStyles(button.readyGlow)
        end
        if button.assistedHighlight then
            HideGlowStyles(button.assistedHighlight)
        end
    end
    if ST._StopCooldownPressFlash then
        ST._StopCooldownPressFlash(button)
    end

    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._readyGlowActive = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = false
    button._barAuraEffectActive = nil
    -- No statusBar alpha reset here: the deleted aura pulse animation was the
    -- only writer it undid, and it would unhide a show-only-while-active
    -- shell's bar on compact re-show. Shell state owns statusBar alpha now.
    if button.assistedHighlight then
        button.assistedHighlight.currentState = nil
    end
end

local function ClearButtonCompactSlotCache(button)
    if not button then return end
    button._compactSlotAnchor = nil
    button._compactSlotX = nil
    button._compactSlotY = nil
end

local function GetButtonPoolKey(group, buttonData, style)
    local displayMode = group and group.displayMode
    if displayMode == "text" then
        return "text"
    elseif displayMode == "bars" then
        return "bars"
    elseif displayMode == "textures" then
        return "textures"
    elseif displayMode == "trigger" then
        return "trigger"
    end
    return "icons"
end

local function GetRuntimeGroupButtonList(self, frame, group)
    if self:IsRotationAssistantGroup(group) then
        local buttonData = self:GetRotationAssistantButtonData(frame)
        local list = frame._rotationAssistantButtonList
        if not list then
            list = {}
            frame._rotationAssistantButtonList = list
        end
        list[1] = buttonData
        for index = 2, #list do
            list[index] = nil
        end
        return list
    end
    return group and group.buttons or {}
end

local function IsRuntimeButtonUsable(self, buttonData, group, opts)
    if buttonData and buttonData._rotationAssistantVirtual == true then
        return (opts and opts.checkLoadConditions == false) or self:IsButtonLoadConditionMet(buttonData, group)
    end
    return self:IsButtonUsable(buttonData, group, opts)
end

local function GetExistingButtonPoolKey(button)
    if button and button._buttonPoolKey then
        return button._buttonPoolKey
    end
    if button and button._isText then
        return "text"
    end
    if button and button._isBar then
        return "bars"
    end
    return "icons"
end

local function GetButtonPool(frame, poolKey)
    frame._buttonFramePools = frame._buttonFramePools or {}
    local pool = frame._buttonFramePools[poolKey]
    if not pool then
        pool = {}
        frame._buttonFramePools[poolKey] = pool
    end
    return pool
end

local function ClearCooldownWidget(widget)
    if not widget then return end
    widget:SetScript("OnUpdate", nil)
    if widget.Clear then
        widget:Clear()
    end
    widget:Hide()
end

local function HideButtonGlowContainer(container)
    if container and HideGlowStyles then
        HideGlowStyles(container)
    elseif container and container.Hide then
        container:Hide()
    end
end

local function ClearButtonPreviewState(button)
    button._procGlowPreview = nil
    button._auraGlowPreview = nil
    button._pandemicPreview = nil
    button._barAuraEffectPreview = nil
    button._readyGlowPreview = nil
    button._keyPressHighlightPreview = nil
    button._textureProcPreview = nil
    button._textureAuraPreview = nil
    button._textureReadyPreview = nil
    button._textureUnusablePreview = nil
    button._forceVisibleByConfig = nil
    button._prevForceVisibleByConfig = nil
end

local function ClearReusableButtonRuntime(button)
    button._resolvedItemId = nil
    button._resolvedItemAvailableQuantity = nil
    button._resolvedItemQuantityKind = nil
    button._resolvedItemMaxCharges = nil
    button._equipmentSlotTrackable = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._spellOutOfRange = nil
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._cooldownDeferred = nil
    button._durationObj = nil
    button._chargeDurationObj = nil
    -- _totemSwipeStyleActive is deliberately NOT cleared here: it is the latch
    -- that owes the swipe-style restore, and the next pass sees the phase gone
    -- and runs the falling edge. (_totemGlowStyleActive is different: its kit
    -- is hidden outright by the caller, so its latch is cleared there.)
    button._totemActive = nil
    button._chargeRecharging = nil
    button._chargeState = nil
    button._currentReadableCharges = nil
    button._chargeCountReadable = nil
    button._chargeText = nil
    button._chargesSpent = nil
    button._sndInitialized = nil
    button._sndPrevCooldownActive = nil
    button._sndPrevAuraActive = nil
    button._sndPrevCharges = nil
    button._sndPrevChargeRecharging = nil
    button._sndPrevChargeCooldownStart = nil
    button._sndTransitionOptions = nil
    button._zeroChargesConfirmed = nil
    button._nilConfirmPending = nil
    button._hideCooldownChargesActive = nil
    button._gcdSwipeDrawActive = nil
    button._displayCountZeroUsabilityFallback = nil
    button._itemCount = nil
    button._auraSpellID = nil
    button._auraUnit = nil
    button._auraActive = false
    button._auraTrackingReady = nil
    button._auraHasTimer = nil
    button._textSecretNameActive = nil
    button._bindingKeyInfos = nil
    button._keyPressHighlightActive = nil
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._visibilityFinalMode = nil
    button._rawVisibilityReasonMode = nil
    button._rawVisibilityHidden = nil
    button._rawVisibilityAlphaOverride = nil
    button._visibilityOverrideSource = nil
    button._visibilityTriggerSuppressed = nil
    button._visibilityReasonBits = nil
    button._rawVisibilityReasonBits = nil
    button._lastVisAlpha = 1
    button._desaturated = nil
    button._iconDesaturationIntent = nil
    button._iconTintIntent = nil
    button._iconFillIntent = nil
    button._iconGlowIntent = nil
    button._barVisualIntent = nil
    button._barVisualApplied = nil
    button._desatCooldownActive = nil
    button._rawDesatCooldownActive = nil
    button._unusableTintActive = nil
    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillColorR = nil
    button._iconFillColorG = nil
    button._iconFillColorB = nil
    button._iconFillColorA = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._auraGlowPandemic = nil
    button._readyGlowActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowTotemDeferred = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._barAuraEffectActive = nil
    button._barGCDSuppressed = nil
    button._barCdColor = nil
    button._barReadyTextColor = nil
    button._barTextMode = nil
    button._barFillSuppressed = nil
    button._cdTextFontMode = nil
    button._barTextColorDirty = true
    button._lastBarTimeText = nil
    button._textVisualIntent = nil
    button._textVisualApplied = nil
    button._textModeSecretArgs = nil
    button._textModeSecretParts = nil
    button._savedOnUpdate = nil
    ClearButtonPreviewState(button)
    ClearButtonVisualState(button)
    if button.count then button.count:SetText("") end
    if button.textString then
        button.textString:SetText("")
        button.textString:SetAlpha(1)
    end
    -- Composite text entries render through pooled run strings beside
    -- textString; put them away with it so the next entry starts blank.
    if button._isText and ST._ResetTextRunStrings then
        ST._ResetTextRunStrings(button)
    end
    if button.nameText then button.nameText:SetText("") end
    if button.timeText then
        UnbindDurationText(button.timeText)
        button.timeText:SetText("")
    end
    if button.statusBar then button.statusBar:SetAlpha(1.0) end
end

local function ResolveReusableButtonEntryState(button, buttonData)
    if CooldownCompanion.IsEntryItemLike and CooldownCompanion.IsEntryItemLike(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true)
            or nil
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    if buttonData and buttonData.type == "spell" then
        if buttonData._cooldownSecrecySpellID ~= buttonData.id then
            buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
            buttonData._cooldownSecrecySpellID = buttonData.id
        end
    end

    button._auraSpellID = CooldownCompanion.ResolveAuraSpellID
        and CooldownCompanion:ResolveAuraSpellID(buttonData)
        or nil
    button._auraUnit = buttonData and buttonData.auraUnit or "player"
    button._auraTrackingReady = nil
end

local function DeactivatePooledButton(self, groupId, button)
    if not button then return end
    UnregisterKeyPressHighlightButton(button)
    if self.ReleaseAuraTextureVisual then
        self:ReleaseAuraTextureVisual(button)
    end
    if self.RemoveButtonFromMasque then
        self:RemoveButtonFromMasque(groupId, button)
    end
    button:SetScript("OnUpdate", nil)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    if button._iconBounds then
        button._iconBounds:SetScript("OnEnter", nil)
        button._iconBounds:SetScript("OnLeave", nil)
    end
    if button.iconFill then
        button.iconFill:SetScript("OnUpdate", nil)
        button.iconFill:Hide()
    end
    button._iconFillOnUpdateInstalled = nil
    ClearCooldownWidget(button.cooldown)
    ClearCooldownWidget(button.locCooldown)
    ClearCooldownWidget(button.iconGCDCooldown)
    HideButtonGlowContainer(button.assistedHighlight)
    HideButtonGlowContainer(button.procGlow)
    HideButtonGlowContainer(button.readyGlow)
    HideButtonGlowContainer(button.keyPressHighlight)
    if ST._StopCooldownPressFlash then
        ST._StopCooldownPressFlash(button)
    end
    HideButtonGlowContainer(button.barAuraEffect)
    -- Totem active phase aura indicator: CC-owned kit regions on the button
    -- itself, so the glow-container hides above do not reach them. Hidden here
    -- (rather than left to the next pass's falling edge) because a released
    -- button may be reused by a different entry before it ticks again, and it
    -- must never inherit a lit indicator. enabled=false ignores the style
    -- table, so nil is the honest argument on both resolvers.
    if button._totemGlowKit then
        button._totemGlowStyleActive = nil
        if button._isBar then
            ST._StyleKitBarGlowRegions(button._totemGlowKit, nil, button, false)
        else
            ST._StyleKitGlowRegions(button._totemGlowKit, nil, button, false)
        end
    end
    ClearReusableButtonRuntime(button)
    button._buttonPoolKey = GetExistingButtonPoolKey(button)
    button:Hide()
    button:ClearAllPoints()
end

-- Rule-1 exact-match HINTS for AcquireButtonFromPool: one map pair per pool key
-- (pools are per display mode), because the two acquisition contexts key on
-- different fields -- combat on _auraSlotHostToken, out of combat on buttonData.
-- Strictly hints: every reader re-tests the rule on the hinted frame and must
-- still find it in the pool, so a stale or missing hint only costs the verbatim
-- scan below and can never change which frame rule 1 picks. Weak keys so a hint
-- left behind by a field that changed while the frame sat pooled cannot keep a
-- deleted entry's table reachable for the session.
local function ReleaseButtonToPool(self, frame, groupId, button)
    DeactivatePooledButton(self, groupId, button)
    local poolKey = button._buttonPoolKey
    local pool = GetButtonPool(frame, poolKey)
    pool[#pool + 1] = button
    local index = frame._buttonPoolIndex
    if not index then
        index = {}
        frame._buttonPoolIndex = index
    end
    local indexEntry = index[poolKey]
    if not indexEntry then
        indexEntry = {
            byData = setmetatable({}, { __mode = "k" }),
            byToken = setmetatable({}, { __mode = "k" }),
        }
        index[poolKey] = indexEntry
    end
    -- Last release wins, which is the frame the descending scan would reach
    -- first if two pooled frames ever carry the same key.
    if button.buttonData ~= nil then
        indexEntry.byData[button.buttonData] = button
    end
    if button._auraSlotHostToken ~= nil then
        indexEntry.byToken[button._auraSlotHostToken] = button
    end
end

local function AcquireButtonFromPool(frame, poolKey, buttonData)
    local pools = frame._buttonFramePools
    local pool = pools and pools[poolKey]
    if not pool or #pool == 0 then return nil end
    local pick
    local inCombat = InCombatLockdown()
    local indexEntry = frame._buttonPoolIndex and frame._buttonPoolIndex[poolKey] or nil
    if indexEntry and buttonData ~= nil then
        local hinted
        if inCombat then
            hinted = indexEntry.byToken[buttonData]
            if hinted and hinted._auraSlotHostToken ~= buttonData then
                hinted = nil
            end
        else
            hinted = indexEntry.byData[buttonData]
            if hinted and hinted.buttonData ~= buttonData then
                hinted = nil
            end
        end
        if hinted then
            for i = 1, #pool do
                if pool[i] == hinted then
                    pick = i
                    break
                end
            end
        end
    end
    if pick ~= nil then
        -- Rule-1 hint hit: the ladders below would reach the same frame first.
    elseif inCombat then
        -- Aura-slot hosts are combat-locked to their entry: the slot subtree
        -- riding a host is forbidden (untouchable) until the OOC rebind pass,
        -- so a mismatched host would show another entry's aura on this button.
        -- Prefer the host already bound to this entry; else any slot-free one;
        -- else force a fresh CC-owned frame (returning nil).
        local free
        for i = #pool, 1, -1 do
            local token = pool[i]._auraSlotHostToken
            if token == buttonData then
                pick = i
                break
            elseif token == nil and not free then
                free = i
            end
        end
        pick = pick or free
        -- Refusing here sends the caller to the deterministic constructors,
        -- which name the new frame from the entry index -- the same name the
        -- refused pooled frame still carries. That is harmless and is not a
        -- duplicate-name error: CreateFrame reassigns the global and no CC
        -- surface resolves button frames by name (anchor parsing is $-anchored
        -- to panel/container names, keybinds resolve action-bar globals, and
        -- Masque keys by frame object). Showing another entry's aura on this
        -- button would be the worse trade. Reviewers have flagged this four
        -- times; the pool re-converges on the next out-of-combat rebind.
        if not pick then return nil end
    else
        -- No aura-slot lock needed out of combat: the rebind pass parks every
        -- record unconditionally before it binds, so no pooled frame can still be
        -- carrying a live slot by the time one is handed out. (An earlier ally-gate
        -- design did leave blocked records bound through a pass, which required a
        -- lock here; that gate was measured unnecessary and removed.)
        --
        -- Prefer the frame that already hosts this entry: repeated repopulates
        -- (config refreshes) then converge on a stable entry<->frame mapping
        -- instead of reversing it each pass, which flip-flopped the statically
        -- composed aura-shell visuals and churned the aura slot rebinds.
        -- Same preference ladder as the combat branch: this entry's own host
        -- first, then a slot-free one, and only then any host. The queued
        -- rebind parks stale records on the NEXT frame, so handing out a host
        -- still bound to another entry would show that entry's aura for a
        -- frame (and through the fight if combat starts in that window).
        local free
        for i = #pool, 1, -1 do
            if pool[i].buttonData == buttonData then
                pick = i
                break
            elseif not free and pool[i]._auraSlotHostToken == nil then
                free = i
            end
        end
        pick = pick or free or #pool
    end
    local button = table.remove(pool, pick)
    -- Whichever rule handed this frame out, it has left the pool: drop every
    -- hint that still points at it, including a displaced fallback pick.
    if indexEntry then
        if button.buttonData ~= nil and indexEntry.byData[button.buttonData] == button then
            indexEntry.byData[button.buttonData] = nil
        end
        if button._auraSlotHostToken ~= nil and indexEntry.byToken[button._auraSlotHostToken] == button then
            indexEntry.byToken[button._auraSlotHostToken] = nil
        end
    end
    button:SetParent(frame)
    return button
end

local function PreparePooledButtonForUse(self, frame, group, button, index, buttonData, style)
    button.buttonData = buttonData
    button.index = index
    button.style = style
    button._groupId = frame.groupId
    if buttonData._rotationAssistantVirtual == true and self.RefreshRotationAssistantButton then
        self:RefreshRotationAssistantButton(button)
    end
    ResolveReusableButtonEntryState(button, buttonData)
    RefreshButtonKeybindState(button, buttonData)
    if button.UpdateStyle then
        button:UpdateStyle(style)
    end
    if self.UpdateButtonIcon then
        self:UpdateButtonIcon(button)
    end
    -- A text entry is auto-sized from a worst-case render of its format, and
    -- {name} resolves through the display identity UpdateButtonIcon just
    -- assigned (ClearReusableButtonRuntime wiped it on release). UpdateStyle
    -- above therefore measured against the SAVED id, so re-measure here; the
    -- ApplyActiveButtonLayout call that follows this loop re-pitches the grid.
    if button._isText and ST._ApplyTextEntryLayout then
        ST._ApplyTextEntryLayout(button)
    end
    if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        button:SetAlpha(0)
        button._lastVisAlpha = 0
    else
        button:SetAlpha(1)
        button._lastVisAlpha = 1
    end
end

local function ForEachGroupButtonFrame(frame, callback)
    if not (frame and callback) then return end
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            callback(button, false, button and button._buttonPoolKey)
        end
    end
    if frame._buttonFramePools then
        for poolKey, pool in pairs(frame._buttonFramePools) do
            for _, button in ipairs(pool) do
                callback(button, true, poolKey)
            end
        end
    end
end

function CooldownCompanion:ReleaseGroupButtonPools(frame)
    if not (frame and frame._buttonFramePools) then return end
    local groupId = frame.groupId
    for poolKey, pool in pairs(frame._buttonFramePools) do
        for _, button in ipairs(pool) do
            button._buttonPoolKey = poolKey
            DeactivatePooledButton(self, groupId, button)
        end
        wipe(pool)
    end
    frame._buttonFramePools = nil
    frame._buttonPoolIndex = nil
end

-- Nudger constants
local NUDGE_BTN_SIZE = 12
-- 16 fits the corner-bracket glyph at the size it reads well (12px art +
-- inset); the old chat-grabber art sat in a 12px button.
local PANEL_RESIZE_GRIP_SIZE = 16
-- 0 = restyle every frame during a grip drag (owner ruling: smooth resize
-- everywhere in arrange mode; raise if a huge panel ever hitches).
local PANEL_RESIZE_REFRESH_INTERVAL = 0

local CreatePixelBorders = ST.CreatePixelBorders
-- Text entries are auto-sized from a measured worst-case render of their
-- format (ButtonFrame/TextMode.lua). Cached per entry: the restyle path
-- measures, layout paths below only read.
-- NOTE: this file's main chunk sits on Lua's 200-local ceiling. This upvalue
-- took over the slot of a retired one rather than adding a slot; nothing new
-- may be localized in this chunk.
local GetTextEntryMetrics = ST._GetTextEntryMetrics

local PropagateFrameStrata

local function PropagateChildFrameStrata(strata, ...)
    for i = 1, select("#", ...) do
        PropagateFrameStrata(select(i, ...), strata)
    end
end

-- Recursively set frame strata on a frame and all its child frames.
-- Textures/FontStrings inherit from their parent frame automatically,
-- but child Frame objects (cooldown widgets, overlay frames, glow containers)
-- may not follow a parent strata change — so we force it explicitly.
-- _ccNoTouch subtrees (aura slot hosts) are skipped entirely: their children
-- are forbidden to addon code in combat, and they inherit strata implicitly.
function PropagateFrameStrata(frame, strata)
    if frame._ccNoTouch then return end
    frame:SetFrameStrata(strata)
    PropagateChildFrameStrata(strata, frame:GetChildren())
end

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

local function GetCursorPositionInUIParentSpace(self)
    if not (GetCursorPosition and UIParent) then
        return nil, nil
    end

    local cursorX, cursorY = GetCursorPosition()
    if not (cursorX and cursorY) then
        return nil, nil
    end

    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if scale and scale > 0 then
        cursorX = cursorX / scale
        cursorY = cursorY / scale
    end

    self._cursorAnchorLastX = cursorX
    self._cursorAnchorLastY = cursorY
    return cursorX, cursorY
end

local function GetFallbackCursorPosition(self)
    local x, y = self._cursorAnchorLastX, self._cursorAnchorLastY
    if x and y then
        return x, y
    end

    if UIParent and UIParent.GetSize then
        local width, height = UIParent:GetSize()
        if width and height then
            return width / 2, height / 2
        end
    end

    return 0, 0
end

local function ApplyCursorAnchorPosition(self, frame, anchor, cursorX, cursorY, resetSized)
    if not (frame and anchor) then
        return false
    end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        frame._anchorDirty = true
        return false
    end

    frame._anchorDirty = nil
    if resetSized then
        frame._hasBeenSized = false
    end

    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    SetExternalAnchorAlphaSyncActive(frame, false)
    frame.anchoredToParent = nil

    if not (cursorX and cursorY) then
        cursorX, cursorY = GetCursorPositionInUIParentSpace(self)
    end
    if not (cursorX and cursorY) then
        cursorX, cursorY = GetFallbackCursorPosition(self)
    end

    local x = anchor.x or CURSOR_ANCHOR_X
    local y = anchor.y or CURSOR_ANCHOR_Y
    frame:ClearAllPoints()
    frame:SetPoint(anchor.point or CURSOR_ANCHOR_POINT, UIParent, "BOTTOMLEFT", cursorX + x, cursorY + y)
    UpdateCoordLabel(frame, x, y)
    return true
end

local function GetCursorAnchoredStandaloneHost(frame, group)
    if not (frame and CooldownCompanion:IsStandaloneTexturePanelGroup(group)) then
        return nil
    end

    local button = frame.buttons and frame.buttons[1] or nil
    return button and button.auraTextureHost or nil
end

local function GetCursorAnchorLayoutPreviewPosition(self, groupId)
    local preview = self._cursorAnchorLayoutPreview
    local frame = preview and preview.frame or nil
    if IsCursorAnchorLayoutPreviewGroupActive(self, groupId) and frame and frame:IsShown() then
        return frame:GetCenter()
    end
    return nil, nil
end

local function GetCursorAnchorLayoutPreviewAnchor(self, groupId, fallbackAnchor)
    local preview = self._cursorAnchorLayoutPreview
    local stagedAnchors = preview and preview.stagedAnchors
    local stagedAnchor = stagedAnchors and stagedAnchors[tostring(groupId)] or nil
    if stagedAnchor and IsCursorAnchorLayoutPreviewGroupActive(self, groupId) then
        return stagedAnchor
    end
    return fallbackAnchor
end

local function BuildCursorAnchorLayoutPreviewGroupMap(self)
    local activeGroupIds = {}
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then
        return activeGroupIds
    end

    for groupId, group in pairs(groups) do
        if IsCursorAnchor(group.anchor)
            and not (self.IsArrangePanelSuppressed and self:IsArrangePanelSuppressed(groupId))
            and not (group.parentContainerId
                and self.IsArrangeContainerSuppressed
                and self:IsArrangeContainerSuppressed(group.parentContainerId))
            and self:CanGroupUseCursorAnchor(group)
            and self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            }) then
            activeGroupIds[groupId] = true
        end
    end

    return activeGroupIds
end

local function SetCursorAnchorLayoutPreviewGroupState(self, groupId, active)
    local frame = self.groupFrames and self.groupFrames[groupId] or nil
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if active and not frame and group and not InCombatLockdown() then
        frame = self:CreateGroupFrame(groupId)
    end
    if not (frame and group) then
        return
    end

    local selected = active and IsCursorAnchorLayoutPreviewSelected(self, groupId)
    local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(group)

    if active then
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:Show()
        end
        frame:SetAlpha(1)
    else
        local isActive = self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
        })
        if not isActive and not (InCombatLockdown() and frame:IsProtected()) then
            frame:Hide()
        else
            ApplyCurrentAlphaIfPresent(self, frame, groupId, group)
        end
    end

    if frame.UpdateCooldowns then
        frame:UpdateCooldowns()
    end
    if self:IsGroupCompactLayoutActive(groupId, group) and self.UpdateGroupLayout then
        self:UpdateGroupLayout(groupId)
    end

    self:SetGroupDragControlsShown(frame, selected and not isStandaloneDisplay)
    if isStandaloneDisplay then
        -- Standalone displays edit through their HOST: it carries the mover
        -- chrome and the click/drag selection route while parked.
        local host = GetCursorAnchoredStandaloneHost(frame, group)
        if host and self.RefreshCursorAnchoredHostControls then
            self:RefreshCursorAnchoredHostControls(host, groupId, group, active == true, selected == true)
        end
    elseif selected then
        UpdateCoordLabel(frame, group.anchor.x or CURSOR_ANCHOR_X, group.anchor.y or CURSOR_ANCHOR_Y)
    end
    self:UpdateGroupClickthrough(groupId)
end

local function ApplyCursorAnchorLayoutPreviewGroupStates(self, previousGroupIds, activeGroupIds)
    local visited = {}
    if previousGroupIds then
        for groupId in pairs(previousGroupIds) do
            visited[groupId] = true
            SetCursorAnchorLayoutPreviewGroupState(self, groupId, activeGroupIds and activeGroupIds[groupId] == true)
        end
    end
    if activeGroupIds then
        for groupId in pairs(activeGroupIds) do
            if not visited[groupId] then
                SetCursorAnchorLayoutPreviewGroupState(self, groupId, true)
            end
        end
    end
end

-- Arrange selection for parked cursor panels: one panel at a time takes the
-- positioning chrome, mirroring container member selection. A click toggles
-- the selection; a drag selects without ever toggling off.
function CooldownCompanion:SelectArrangeCursorPanel(groupId, toggle)
    local preview = self._cursorAnchorLayoutPreview
    if not (self._arrangeModeActive
        and preview
        and PreviewMapContains(preview.activeGroupIds, groupId)) then
        return false
    end

    local previous = preview.selectedGroupId
    if previous == groupId then
        if toggle then
            preview.selectedGroupId = nil
            SetCursorAnchorLayoutPreviewGroupState(self, groupId, true)
            local selectedGroup = self.db.profile.groups[groupId]
            local selectedContainerId = selectedGroup and selectedGroup.parentContainerId
            if selectedContainerId and not self:IsContainerArrangeChromeHidden(selectedContainerId) then
                self:RefreshContainerWrapper(selectedContainerId)
            end
            if self.RefreshArrangePillList then self:RefreshArrangePillList() end
            return false
        end
        return true
    end

    preview.selectedGroupId = groupId
    if previous ~= nil and PreviewMapContains(preview.activeGroupIds, previous) then
        SetCursorAnchorLayoutPreviewGroupState(self, previous, true)
    end
    SetCursorAnchorLayoutPreviewGroupState(self, groupId, true)
    local previousGroup = previous and self.db.profile.groups[previous]
    local previousContainerId = previousGroup and previousGroup.parentContainerId
    local selectedGroup = self.db.profile.groups[groupId]
    local selectedContainerId = selectedGroup and selectedGroup.parentContainerId
    if previousContainerId
        and previousContainerId ~= selectedContainerId
        and not self:IsContainerArrangeChromeHidden(previousContainerId) then
        self:RefreshContainerWrapper(previousContainerId)
    end
    if selectedContainerId and not self:IsContainerArrangeChromeHidden(selectedContainerId) then
        self:RefreshContainerWrapper(selectedContainerId)
    end
    if self.RefreshArrangePillList then self:RefreshArrangePillList() end
    return true
end

local function BeginCursorLayoutPreviewDrag(ownerFrame, dragRegion)
    ownerFrame._dragInProgress = true
    dragRegion:SetScript("OnUpdate", function()
        CooldownCompanion:UpdateCursorAnchoredFrames()
    end)
    ownerFrame:StartMoving()
    CooldownCompanion:BeginMoverChromeFade(ownerFrame)
end

local function EndCursorLayoutPreviewDrag(ownerFrame, dragRegion)
    dragRegion:SetScript("OnUpdate", nil)
    ownerFrame._dragInProgress = nil
    ownerFrame:StopMovingOrSizing()
    local activePreview = CooldownCompanion._cursorAnchorLayoutPreview
    if activePreview then
        activePreview.hasCustomPosition = true
        activePreview.hasDefaultPosition = nil
    end
    CooldownCompanion:UpdateCursorAnchoredFrames()
    CooldownCompanion:EndMoverChromeFade(ownerFrame)
end

local function ComputeCursorAnchorLayoutPreviewPanelCoordinates(self, frame, groupId, group)
    local preview = self._cursorAnchorLayoutPreview
    if not (preview and frame and group and IsCursorAnchor(group.anchor)) then
        return nil, nil
    end
    if not IsCursorAnchorLayoutPreviewSelected(self, groupId) then
        return nil, nil
    end

    local cursorX, cursorY = GetCursorAnchorLayoutPreviewPosition(self, groupId)
    local frameCenterX, frameCenterY = frame:GetCenter()
    local frameWidth, frameHeight = GetFrameSizeInUIParentSpace(frame)
    if not (cursorX and cursorY and frameCenterX and frameCenterY and frameWidth and frameHeight) then
        return nil, nil
    end

    local point = group.anchor.point or CURSOR_ANCHOR_POINT
    local anchorOffsetX, anchorOffsetY = GetAnchorOffset(point, frameWidth, frameHeight)
    local newX = math_floor(((frameCenterX + anchorOffsetX) - cursorX) * 10 + 0.5) / 10
    local newY = math_floor(((frameCenterY + anchorOffsetY) - cursorY) * 10 + 0.5) / 10
    return newX, newY, cursorX, cursorY, point
end

local function SaveCursorAnchorLayoutPreviewPanelPosition(self, groupId)
    local frame = self.groupFrames and self.groupFrames[groupId] or nil
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    -- A standalone display's visible body is its host, so a host drag must be
    -- measured against the host; the alpha-0 group frame never moved.
    local host = GetCursorAnchoredStandaloneHost(frame, group)
    local newX, newY, cursorX, cursorY, point = ComputeCursorAnchorLayoutPreviewPanelCoordinates(
        self,
        host or frame,
        groupId,
        group
    )
    if newX == nil or newY == nil then
        self:UpdateCursorAnchoredFrames()
        return false
    end

    group.anchor.point = point
    group.anchor.relativeTo = CURSOR_ANCHOR_TARGET
    group.anchor.relativePoint = CURSOR_ANCHOR_RELATIVE_POINT
    group.anchor.x = newX
    group.anchor.y = newY

    ApplyCursorAnchorPosition(self, frame, group.anchor, cursorX, cursorY)
    UpdateCoordLabel(frame, newX, newY)
    if host and self.RefreshCursorAnchoredHostControls then
        self:RefreshCursorAnchoredHostControls(host, groupId, group, true, true)
    end
    self:RefreshConfigPanel()
    self:UpdateCursorAnchoredFrames()
    return true
end

local function UpdateGroupDragCoordinate(frame)
    local groupId = frame and frame.groupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId] or nil
    if not group then
        return
    end

    local x, y, anchorState
    if IsCursorAnchor(group.anchor) then
        x, y = ComputeCursorAnchorLayoutPreviewPanelCoordinates(CooldownCompanion, frame, groupId, group)
    else
        x, y, _, _, _, _, anchorState = ComputeGroupFrameCoordinates(
            CooldownCompanion,
            frame,
            groupId,
            group,
            frame._coordDragReferenceReady,
            frame._coordDragRelativeTo,
            frame._coordDragRelativeFrame,
            frame._coordDragAnchorState
        )
    end
    if x ~= nil and y ~= nil and anchorState ~= "unsafe" then
        UpdateCoordLabel(frame, x, y)
    end
end

local function PrepareGroupCoordinateDragReference(frame)
    local groupId = frame and frame.groupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId] or nil
    if not (frame and group) or IsCursorAnchor(group.anchor) then
        return
    end

    local _, _, relativeTo, relativeFrame, _, _, anchorState = ComputeGroupFrameCoordinates(
        CooldownCompanion,
        frame,
        groupId,
        group
    )
    frame._coordDragRelativeTo = relativeTo
    frame._coordDragRelativeFrame = relativeFrame
    frame._coordDragAnchorState = anchorState
    frame._coordDragReferenceReady = true
end

local function StartGroupCoordinateDragUpdates(frame)
    PrepareGroupCoordinateDragReference(frame)
    StartCoordinateDragUpdates(frame, UpdateGroupDragCoordinate)
end

local function ApplyPanelCoordinates(frame, groupId, x, y)
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not (frame and group and group.anchor) then
        return
    end

    group.anchor.x = x
    group.anchor.y = y
    CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
    UpdateCoordLabel(frame, x, y)
    if IsCursorAnchor(group.anchor) and CooldownCompanion.UpdateCursorAnchoredFrames then
        CooldownCompanion:UpdateCursorAnchoredFrames()
    end
    CooldownCompanion:RefreshConfigPanel()
    if group.parentContainerId and CooldownCompanion.RefreshContainerWrapper then
        CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
    end
end

local function BeginCursorAnchorLayoutPreviewPanelDrag(self, frame, groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (frame and group and IsCursorAnchor(group.anchor)) then
        return false
    end
    if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end
    if not IsCursorAnchorLayoutPreviewSelected(self, groupId) then
        return false
    end
    if self._combatForcedLock or (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
        return false
    end

    local preview = self._cursorAnchorLayoutPreview
    if preview then
        preview.draggedGroupId = groupId
    end
    frame._dragCancelPending = nil
    frame._dragInProgress = true
    CancelCoordinateEdit(frame.coordLabel)
    frame:StartMoving()
    self:BeginMoverChromeFade(frame)
    StartGroupCoordinateDragUpdates(frame)
    return true
end

local function EndCursorAnchorLayoutPreviewPanelDrag(self, frame, groupId, cancelSave)
    local preview = self._cursorAnchorLayoutPreview
    if preview and GroupIdsEqual(preview.draggedGroupId, groupId) then
        preview.draggedGroupId = nil
    end
    if frame then
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        StopCoordinateDragUpdates(frame)
        if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
    end
    if cancelSave then
        self:UpdateCursorAnchoredFrames()
        self:EndMoverChromeFade(frame)
        return true
    end
    if not SaveCursorAnchorLayoutPreviewPanelPosition(self, groupId) then
        self:UpdateCursorAnchoredFrames()
    end
    self:EndMoverChromeFade(frame)
    return true
end

-- Host-drag entry points for parked standalone displays (Texture and Trigger
-- panels). The drag mechanics live with the host in AuraTexturesDisplay;
-- these own the preview bookkeeping and the cursor-anchor save, mirroring
-- the ordinary panel drag pair above.
function CooldownCompanion:BeginCursorAnchorLayoutPreviewHostDrag(host, groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (host and group and IsCursorAnchor(group.anchor)) then
        return false
    end
    if not IsCursorAnchorLayoutPreviewSelected(self, groupId) then
        return false
    end
    if self._combatForcedLock or (InCombatLockdown() and host.IsProtected and host:IsProtected()) then
        return false
    end

    local preview = self._cursorAnchorLayoutPreview
    if preview then
        preview.draggedGroupId = groupId
    end
    return true
end

function CooldownCompanion:EndCursorAnchorLayoutPreviewHostDrag(groupId, cancelSave)
    local preview = self._cursorAnchorLayoutPreview
    if preview and GroupIdsEqual(preview.draggedGroupId, groupId) then
        preview.draggedGroupId = nil
    end
    if cancelSave then
        self:UpdateCursorAnchoredFrames()
        return true
    end
    if not SaveCursorAnchorLayoutPreviewPanelPosition(self, groupId) then
        self:UpdateCursorAnchoredFrames()
    end
    return true
end

local function ResetCursorAnchorLayoutPreviewPosition(self)
    local preview = self._cursorAnchorLayoutPreview
    local frame = preview and preview.frame or nil
    if not frame then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, CURSOR_LAYOUT_PREVIEW_DEFAULT_Y)
    preview.hasCustomPosition = nil
    preview.hasDefaultPosition = true
    self:UpdateCursorAnchoredFrames()
    return true
end

local function EnsureCursorAnchorLayoutPreview(self)
    local preview = self._cursorAnchorLayoutPreview
    if preview and preview.frame then
        return preview
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(900)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()

    local dragFrame = CreateFrame("Frame", nil, frame)
    dragFrame:SetSize(CURSOR_LAYOUT_PREVIEW_SIZE, CURSOR_LAYOUT_PREVIEW_SIZE)
    dragFrame:SetPoint("TOPLEFT", frame, "CENTER", -4, 4)
    dragFrame:SetFrameStrata("TOOLTIP")
    dragFrame:SetFrameLevel(901)
    dragFrame:EnableMouse(true)
    dragFrame:RegisterForDrag("LeftButton")
    dragFrame:SetScript("OnDragStart", function(self)
        BeginCursorLayoutPreviewDrag(frame, self)
    end)
    dragFrame:SetScript("OnDragStop", function(self)
        EndCursorLayoutPreviewDrag(frame, self)
    end)
    -- Arrange rests the dummy cursor as the pointer icon alone; the label,
    -- reset, and help reveal on hover, following the quiet-chrome grammar.
    -- The config Layout-tab form keeps its chrome pinned open.
    dragFrame:SetScript("OnEnter", function()
        if not CooldownCompanion._arrangeModeActive or frame._cursorChromeHover then
            return
        end
        frame._cursorChromeHover = true
        frame._cursorHoverGen = (frame._cursorHoverGen or 0) + 1
        local generation = frame._cursorHoverGen
        local activePreview = CooldownCompanion._cursorAnchorLayoutPreview
        if activePreview and activePreview.UpdateChrome then
            activePreview.UpdateChrome()
        end
        local function Watch()
            if frame._cursorHoverGen ~= generation or frame._cursorChromeHover ~= true then
                return
            end
            local watchPreview = CooldownCompanion._cursorAnchorLayoutPreview
            local labelShown = watchPreview and watchPreview.labelFrame and watchPreview.labelFrame:IsShown()
            if frame:IsShown()
                and (dragFrame:IsMouseOver(4, -4, -4, 4)
                    or (labelShown and watchPreview.labelFrame:IsMouseOver(4, -4, -4, 4))) then
                C_Timer.After(0.2, Watch)
                return
            end
            frame._cursorChromeHover = nil
            if watchPreview and watchPreview.UpdateChrome then
                watchPreview.UpdateChrome()
            end
        end
        C_Timer.After(0.2, Watch)
    end)

    local texture = dragFrame:CreateTexture(nil, "OVERLAY")
    texture:SetAtlas(CURSOR_LAYOUT_PREVIEW_ATLAS, false)
    texture:SetSize(CURSOR_LAYOUT_PREVIEW_SIZE, CURSOR_LAYOUT_PREVIEW_SIZE)
    texture:SetAllPoints(dragFrame)
    texture:SetVertexColor(
        CURSOR_LAYOUT_PREVIEW_TINT[1],
        CURSOR_LAYOUT_PREVIEW_TINT[2],
        CURSOR_LAYOUT_PREVIEW_TINT[3],
        CURSOR_LAYOUT_PREVIEW_TINT[4]
    )
    texture:Show()

    local labelFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    labelFrame:SetSize(CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH, CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT)
    labelFrame:SetPoint("TOP", dragFrame, "BOTTOM", 0, -2)
    labelFrame:SetFrameStrata("TOOLTIP")
    labelFrame:SetFrameLevel(902)
    labelFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    labelFrame:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(labelFrame)
    labelFrame:EnableMouse(true)
    labelFrame:RegisterForDrag("LeftButton")
    labelFrame:SetScript("OnDragStart", function(self)
        BeginCursorLayoutPreviewDrag(frame, self)
    end)
    labelFrame:SetScript("OnDragStop", function(self)
        EndCursorLayoutPreviewDrag(frame, self)
    end)

    local label = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", labelFrame, "LEFT", 6, 0)
    label:SetPoint("RIGHT", labelFrame, "RIGHT", -39, 0)
    label:SetJustifyH("CENTER")
    label:SetText("Dummy Cursor")
    label:SetTextColor(
        CURSOR_LAYOUT_PREVIEW_TINT[1],
        CURSOR_LAYOUT_PREVIEW_TINT[2],
        CURSOR_LAYOUT_PREVIEW_TINT[3],
        CURSOR_LAYOUT_PREVIEW_TINT[4]
    )
    labelFrame.label = label

    local resetButton = CreateFrame("Button", nil, labelFrame)
    resetButton:SetSize(16, 16)
    resetButton:SetPoint("RIGHT", labelFrame, "RIGHT", -20, 0)
    resetButton:SetFrameStrata("TOOLTIP")
    resetButton:SetFrameLevel(903)
    resetButton.icon = resetButton:CreateTexture(nil, "OVERLAY")
    resetButton.icon:SetSize(12, 12)
    resetButton.icon:SetPoint("CENTER")
    resetButton.icon:SetAtlas("UI-RefreshButton", false)
    resetButton.icon:SetVertexColor(0.75, 0.95, 1, 0.95)
    resetButton:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset Dummy Cursor")
        GameTooltip:AddLine("Returns this preview cursor to its default position above screen center for this session.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetButton:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.75, 0.95, 1, 0.95)
        GameTooltip:Hide()
    end)
    resetButton:SetScript("OnClick", function()
        ResetCursorAnchorLayoutPreviewPosition(CooldownCompanion)
    end)

    local helpButton
    if ST.CreateRuntimeInfoButton then
        helpButton = ST.CreateRuntimeInfoButton(
            labelFrame,
            labelFrame,
            "RIGHT",
            "RIGHT",
            -3,
            0,
            function(tooltip)
                tooltip:AddLine("Dummy Cursor")
                tooltip:AddLine("Drag this preview cursor to position active cursor panels without using your live cursor.", 1, 1, 1, true)
                tooltip:AddLine(" ")
                tooltip:AddLine("Click a parked panel to select and adjust it.", 1, 1, 1, true)
            end
        )
        if ST.SetRuntimeInfoButtonShown then
            ST.SetRuntimeInfoButtonShown(helpButton, true)
        end
    end

    preview = {
        frame = frame,
        dragFrame = dragFrame,
        helpButton = helpButton,
        labelFrame = labelFrame,
        resetButton = resetButton,
        texture = texture,
    }
    -- resetButton and helpButton are labelFrame children, so the label's
    -- visibility carries the whole chrome block.
    preview.UpdateChrome = function()
        labelFrame:SetShown(
            not CooldownCompanion._arrangeModeActive
                or frame._cursorChromeHover == true
                or frame._dragInProgress == true
        )
    end
    self._cursorAnchorLayoutPreview = preview
    return preview
end

-- groupId names the panel that takes drag/nudge chrome. A nil groupId is the
-- pin-only form used by arrange mode: every active cursor panel parks on the
-- dummy cursor quietly, and clicking or dragging one selects it into the
-- positioning chrome (SelectArrangeCursorPanel).
function CooldownCompanion:ShowCursorAnchorLayoutPreview(groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if groupId ~= nil and not (group and IsCursorAnchor(group.anchor)) then
        self:ClearCursorAnchorLayoutPreview()
        return
    end

    local preview = EnsureCursorAnchorLayoutPreview(self)
    local frame = preview.frame
    local previousActiveGroupIds = preview.activeGroupIds
    local activeGroupIds = BuildCursorAnchorLayoutPreviewGroupMap(self)
    if groupId == nil and next(activeGroupIds) == nil then
        self:ClearCursorAnchorLayoutPreview()
        return
    end
    preview.selectedGroupId = groupId
    preview.activeGroupIds = activeGroupIds
    preview.stagedAnchors = nil
    if not preview.hasCustomPosition and not preview.hasDefaultPosition then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, CURSOR_LAYOUT_PREVIEW_DEFAULT_Y)
        preview.hasDefaultPosition = true
    end
    if ST.SetRuntimeInfoButtonShown then
        ST.SetRuntimeInfoButtonShown(preview.helpButton, true)
    end
    if preview.resetButton then
        preview.resetButton:Show()
    end
    if preview.UpdateChrome then
        preview.UpdateChrome()
    end
    frame:Show()
    ApplyCursorAnchorLayoutPreviewGroupStates(self, previousActiveGroupIds, activeGroupIds)
    -- Preview membership is an alpha force-condition input (it forces its panels
    -- fully visible and stores their natural alpha), so the alpha driver must be
    -- running across the whole preview.
    if self.EnsureAlphaDriverArmed then
        self:EnsureAlphaDriverArmed()
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    self:UpdateCursorAnchoredFrames()
end

-- Slider drags in config may move the explicit dummy-cursor layout preview,
-- but must not write the profile or make the ordinary runtime cursor panels
-- consume an unconfirmed offset. The staged copy lives only as long as that
-- preview surface and is discarded on commit, rebuild, or config close.
function CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(groupId, x, y)
    if not IsCursorAnchorLayoutPreviewGroupActive(self, groupId) then
        return false
    end

    local group = self.db and self.db.profile and self.db.profile.groups
        and self.db.profile.groups[groupId]
    local anchor = group and group.anchor
    if not IsCursorAnchor(anchor) then
        return false
    end

    local preview = self._cursorAnchorLayoutPreview
    preview.stagedAnchors = preview.stagedAnchors or {}
    preview.stagedAnchors[tostring(groupId)] = {
        point = anchor.point,
        relativeTo = anchor.relativeTo,
        relativePoint = anchor.relativePoint,
        x = x,
        y = y,
    }
    self:UpdateCursorAnchoredFrames()
    return true
end

function CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(groupId)
    local preview = self._cursorAnchorLayoutPreview
    local stagedAnchors = preview and preview.stagedAnchors
    if not stagedAnchors then
        return false
    end

    local key = groupId ~= nil and tostring(groupId) or nil
    if key then
        if not stagedAnchors[key] then
            return false
        end
        stagedAnchors[key] = nil
        if not next(stagedAnchors) then
            preview.stagedAnchors = nil
        end
    else
        preview.stagedAnchors = nil
    end

    self:UpdateCursorAnchoredFrames()
    return true
end

function CooldownCompanion:ClearCursorAnchorLayoutPreview()
    local preview = self._cursorAnchorLayoutPreview
    if not preview then
        return
    end

    -- The preview shell is retained after first use. Ordinary config
    -- selection clears preview state frequently, so do not re-run runtime
    -- alpha restoration, ticker ownership, and every cursor-anchor position
    -- when that retained shell is already inactive.
    if not preview.activeGroupIds
        and not preview.selectedGroupId
        and not preview.draggedGroupId
        and not preview.stagedAnchors
        and not (preview.frame and preview.frame:IsShown()) then
        return
    end

    -- While arrange mode holds cursor panels on the dummy cursor, a
    -- config-side clear only drops the selection chrome; the pin itself
    -- stays until arrange mode exits. Combat forced lock bypasses the
    -- demote: cursor panels must follow the real cursor for the fight.
    if self._arrangeModeActive == true
        and not self._combatForcedLock
        and next(BuildCursorAnchorLayoutPreviewGroupMap(self)) ~= nil then
        self:ShowCursorAnchorLayoutPreview(nil)
        return
    end

    local activeGroupIds = preview.activeGroupIds
    preview.selectedGroupId = nil
    preview.activeGroupIds = nil
    preview.draggedGroupId = nil
    preview.stagedAnchors = nil
    if preview.frame then
        preview.frame._dragInProgress = nil
        preview.frame:StopMovingOrSizing()
        preview.frame:Hide()
    end
    if preview.dragFrame then
        preview.dragFrame:SetScript("OnUpdate", nil)
    end
    if preview.labelFrame then
        preview.labelFrame:SetScript("OnUpdate", nil)
    end
    if preview.resetButton then
        preview.resetButton:Hide()
    end
    if ST.SetRuntimeInfoButtonShown then
        ST.SetRuntimeInfoButtonShown(preview.helpButton, false)
    end

    ApplyCursorAnchorLayoutPreviewGroupStates(self, activeGroupIds, nil)
    -- Leaving the preview hands those panels back to their own alpha configs,
    -- which is the same force-condition flip as entering it.
    if self.EnsureAlphaDriverArmed then
        self:EnsureAlphaDriverArmed()
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    self:UpdateCursorAnchoredFrames()
end

function CooldownCompanion:AnchorFrameToCursor(frame, anchor, cursorX, cursorY)
    local previewGroupId = frame and (frame.groupId or (frame._ownerButton and frame._ownerButton._groupId)) or nil
    if not (cursorX and cursorY) then
        cursorX, cursorY = GetCursorAnchorLayoutPreviewPosition(self, previewGroupId)
    end
    return ApplyCursorAnchorPosition(self, frame, anchor or BuildDefaultCursorAnchor(), cursorX, cursorY)
end

-- The cursor-anchor candidate set is pure config (anchor kind + panel
-- membership), so the full-framerate handler works from this list instead of
-- walking every group in the profile. Every caller that is NOT the ticker
-- rebuilds it first, and the handler still re-tests both predicates per
-- candidate, so a stale list can never move a panel that no longer qualifies.
-- One file local (this chunk sits near Lua's 200-local ceiling).
local cursorAnchorTicker = { ids = {}, count = 0 }

function cursorAnchorTicker.Rebuild(addon, groups)
    local ids = cursorAnchorTicker.ids
    local count = 0
    if groups then
        for groupId, group in pairs(groups) do
            if IsCursorAnchor(group.anchor)
                and addon:CanGroupUseCursorAnchor(group) then
                count = count + 1
                ids[count] = groupId
            end
        end
    end
    for index = count + 1, cursorAnchorTicker.count do
        ids[index] = nil
    end
    cursorAnchorTicker.count = count
    return count
end

function cursorAnchorTicker.OnUpdate()
    CooldownCompanion:UpdateCursorAnchoredFrames(true)
end

function CooldownCompanion:UpdateCursorAnchoredFrames(useCandidateList)
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then
        return
    end

    if not useCandidateList then
        cursorAnchorTicker.Rebuild(self, groups)
    end
    if cursorAnchorTicker.count == 0 then
        return
    end

    local cursorX, cursorY = GetCursorPositionInUIParentSpace(self)
    if not (cursorX and cursorY) then
        cursorX, cursorY = GetFallbackCursorPosition(self)
    end

    local preview = self._cursorAnchorLayoutPreview
    local draggedGroupId = preview and preview.draggedGroupId or nil

    for index = 1, cursorAnchorTicker.count do
        local groupId = cursorAnchorTicker.ids[index]
        local group = groups[groupId]
        if group
            and IsCursorAnchor(group.anchor)
            and self:CanGroupUseCursorAnchor(group) then
            local frame = self.groupFrames and self.groupFrames[groupId] or nil
            if frame and frame:IsShown() and not GroupIdsEqual(draggedGroupId, groupId) then
                local previewX, previewY = GetCursorAnchorLayoutPreviewPosition(self, groupId)
                local anchorX = previewX or cursorX
                local anchorY = previewY or cursorY
                local anchor = GetCursorAnchorLayoutPreviewAnchor(self, groupId, group.anchor)
                ApplyCursorAnchorPosition(self, frame, anchor, anchorX, anchorY)
                local host = GetCursorAnchoredStandaloneHost(frame, group)
                if host and host:IsShown() then
                    ApplyCursorAnchorPosition(self, host, anchor, anchorX, anchorY)
                end
            end
        end
    end
end

function CooldownCompanion:RefreshCursorAnchorTicker()
    if not self._cursorAnchorTicker then
        self._cursorAnchorTicker = CreateFrame("Frame")
    end

    local active = false
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    local count = cursorAnchorTicker.Rebuild(self, groups)
    if groups and self.groupFrames then
        for index = 1, count do
            local frame = self.groupFrames[cursorAnchorTicker.ids[index]]
            if frame and frame:IsShown() then
                active = true
                break
            end
        end
    end

    if active then
        self._cursorAnchorTicker:SetScript("OnUpdate", cursorAnchorTicker.OnUpdate)
        self._cursorAnchorTicker:Show()
    else
        self._cursorAnchorTicker:SetScript("OnUpdate", nil)
        self._cursorAnchorTicker:Hide()
    end
end

local function ShouldShowGroupFrameForRuntime(addon, groupId, group)
    return addon:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
        requireButtons = true,
    })
end

function CooldownCompanion:CreateGroupFrame(groupId)
    -- Return existing frame to prevent duplicates (SharedMedia callbacks
    -- can trigger RefreshAllMedia before OnEnable's CreateAllGroupFrames)
    if self.groupFrames[groupId] then
        return self.groupFrames[groupId]
    end

    local group = self.db.profile.groups[groupId]
    if not group then return end

    -- Create main container frame
    local frameName = "CooldownCompanionGroup" .. groupId
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame.groupId = groupId
    frame.buttons = {}
    frame._containerUnlockPreviewActive = group.parentContainerId
        and self:IsContainerUnlockPreviewActive(group.parentContainerId)
        and not self:IsArrangePanelSuppressed(groupId)
        and not self:IsArrangeContainerSuppressed(group.parentContainerId)
        or nil
    frame._panelUnlockPreviewActive = self:IsPanelUnlockPreviewActive(group) or nil
    
    -- Set initial size (will be updated when buttons are added)
    frame:SetSize(100, 50)

    -- Apply per-group frame strata if configured
    local strata = group.frameStrata
    if strata then
        frame:SetFrameStrata(strata)
        frame:SetFixedFrameStrata(true)
    end

    -- Position the frame
    self:AnchorGroupFrame(frame, group.anchor)
    
    -- Resolve locked state from container (or group for legacy)
    local isLocked, baseAlpha = GetContainerState(groupId)
    if self:IsArrangePanelSuppressed(groupId)
        or (group.parentContainerId and self:IsArrangeContainerSuppressed(group.parentContainerId)) then
        isLocked = true
    end

    -- Make it movable when unlocked. Texture panels use direct texture dragging
    -- instead of the standard panel drag handle.
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    frame:SetMovable(true)
    frame:EnableMouse((not isLocked) and (not isTextureMode))
    frame:RegisterForDrag("LeftButton")

    -- Drag handle (visible when unlocked)
    frame.dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.dragHandle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    frame.dragHandle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    frame.dragHandle:SetHeight(15)
    frame.dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(frame.dragHandle)

    frame.dragHandle.text = frame.dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.dragHandle.text:SetPoint("CENTER")
    frame.dragHandle.text:SetText(group.name)
    frame.dragHandle.text:SetTextColor(1, 1, 1, 1)

    -- Pixel nudger (parented to dragHandle, inherits show/hide)
    frame.nudger = CreateNudger(frame, groupId)
    frame.dragHandle.lockButton = ST.CreateMoverLockBadge(frame.dragHandle, 12, function()
        ST.LockPanelFromMover(groupId)
    end)
    frame.dragHandle.lockButton:SetPoint("RIGHT", frame.dragHandle, "RIGHT", -2, 0)
    frame.dragHandle.menuButton = ST.CreateMoverQuickMenuButton(
        frame.dragHandle,
        12,
        function()
            local current = CooldownCompanion.db.profile.groups[groupId]
            return {
                kind = "panel",
                id = groupId,
                containerId = current and current.parentContainerId,
                focusId = current and current.parentContainerId,
            }
        end,
        frame.dragHandle
    )
    frame.dragHandle.menuButton:SetPoint("RIGHT", frame.dragHandle.lockButton, "LEFT", -2, 0)
    -- Symmetric insets matching the badge cluster keep the name centered on the bar
    local headerTextInset = frame.dragHandle.lockButton:GetWidth() + frame.dragHandle.menuButton:GetWidth() + 8
    frame.dragHandle.text:ClearAllPoints()
    frame.dragHandle.text:SetPoint("LEFT", frame.dragHandle, "LEFT", headerTextInset, 0)
    frame.dragHandle.text:SetPoint("RIGHT", frame.dragHandle, "RIGHT", -headerTextInset, 0)
    frame.dragHandle.text:SetJustifyH("CENTER")

    -- Coordinate label (parented to dragHandle so it hides when locked)
    frame.coordLabel = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    frame.coordLabel:SetHeight(15)
    frame.coordLabel:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    frame.coordLabel:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
    frame.coordLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(frame.coordLabel)
    frame.coordLabel.text = frame.coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.coordLabel.text:SetPoint("CENTER")
    frame.coordLabel.text:SetTextColor(1, 1, 1, 1)
    CreateEditableCoordLabel(
        frame.coordLabel,
        function()
            -- A selected section answers with its own offsets; the write half
            -- below mirrors the same branch. Same fields, same "x:, y:" face;
            -- the gold tint is what says whose numbers these are.
            local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
            if section then
                return tonumber(section.offsetX) or 0, tonumber(section.offsetY) or 0
            end
            local currentGroup = CooldownCompanion.db.profile.groups[groupId]
            local anchor = currentGroup and currentGroup.anchor
            if anchor and IsCursorAnchor(anchor) then
                return anchor.x or CURSOR_ANCHOR_X, anchor.y or CURSOR_ANCHOR_Y
            end
            return anchor and anchor.x or 0, anchor and anchor.y or 0
        end,
        function(x, y)
            local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
            if section then
                -- The offset sliders' own range and tenths precision.
                section.offsetX = math_max(-100, math_min(100,
                    math_floor((tonumber(x) or 0) * 10 + 0.5) / 10))
                section.offsetY = math_max(-100, math_min(100,
                    math_floor((tonumber(y) or 0) * 10 + 0.5) / 10))
                CooldownCompanion:UpdateGroupStyle(groupId)
                RefreshConfigPanelIfShown()
                UpdateCoordLabel(frame,
                    tonumber(section.offsetX) or 0,
                    tonumber(section.offsetY) or 0)
                return
            end
            ApplyPanelCoordinates(frame, groupId, x, y)
        end,
        function()
            return frame._dragInProgress == true
        end
    )
    UpdateCoordLabel(frame)

    frame.sizeLabel = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    frame.sizeLabel:SetHeight(15)
    frame.sizeLabel:SetPoint("TOPLEFT", frame.coordLabel, "BOTTOMLEFT", 0, -2)
    frame.sizeLabel:SetPoint("TOPRIGHT", frame.coordLabel, "BOTTOMRIGHT", 0, -2)
    frame.sizeLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.sizeLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(frame.sizeLabel)
    frame.sizeLabel.text = frame.sizeLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.sizeLabel.text:SetPoint("CENTER")
    frame.sizeLabel.text:SetTextColor(1, 1, 1, 1)
    CreateEditableCoordLabel(
        frame.sizeLabel,
        function()
            local currentGroup = CooldownCompanion.db.profile.groups[groupId]
            local style = currentGroup and currentGroup.style
            if not style then
                return 0, 0
            end
            -- A selected section answers with ITS resolved size; the write
            -- half below mirrors the same branch.
            local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
            if section and currentGroup.displayMode ~= "bars" then
                if style.maintainAspectRatio then
                    return tonumber(section.iconWidth) or tonumber(section.iconHeight)
                        or style.buttonSize or ST.BUTTON_SIZE
                end
                return tonumber(section.iconWidth) or style.iconWidth
                        or style.buttonSize or ST.BUTTON_SIZE,
                    tonumber(section.iconHeight) or style.iconHeight
                        or style.buttonSize or ST.BUTTON_SIZE
            end
            if currentGroup.displayMode == "bars" then
                return style.barLength or 180, style.barHeight or 20
            elseif style.maintainAspectRatio then
                return style.buttonSize or ST.BUTTON_SIZE
            end
            return style.iconWidth or style.buttonSize or ST.BUTTON_SIZE,
                style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
        end,
        function(primary, secondary)
            local currentGroup = CooldownCompanion.db.profile.groups[groupId]
            local style = currentGroup and currentGroup.style
            if not style then
                return
            end
            local currentKind
            if currentGroup.displayMode == "bars" then
                currentKind = "bar"
            elseif style.maintainAspectRatio then
                currentKind = "square"
            else
                currentKind = "icon"
            end
            if currentKind ~= frame.sizeLabel._sizeKind
                or (currentKind ~= "square" and secondary == nil) then
                return
            end
            -- The section branch of the getter's answer, committed to the
            -- section's own keys. Selection is re-read at commit time, so an
            -- edit that outlived its selection falls through to the panel.
            local _, section = CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
            if section and currentKind ~= "bar" then
                if currentKind == "square" then
                    section.iconWidth = math_max(10, math_min(150, ST.RoundToTenths(primary)))
                else
                    section.iconWidth = math_max(10, math_min(150, ST.RoundToTenths(primary)))
                    section.iconHeight = math_max(10, math_min(150, ST.RoundToTenths(secondary)))
                end
                CooldownCompanion:UpdateGroupStyle(groupId)
                RefreshConfigPanelIfShown()
                ST.UpdateGroupSizeLabel(frame)
                return
            end
            if currentKind == "bar" then
                style.barLength = math_max(10, math_min(500, ST.RoundToTenths(primary)))
                style.barHeight = math_max(5, math_min(100, ST.RoundToTenths(secondary)))
            elseif currentKind == "square" then
                style.buttonSize = math_max(10, math_min(150, ST.RoundToTenths(primary)))
            else
                style.iconWidth = math_max(10, math_min(150, ST.RoundToTenths(primary)))
                style.iconHeight = math_max(10, math_min(150, ST.RoundToTenths(secondary)))
            end
            CooldownCompanion:UpdateGroupStyle(groupId)
            RefreshConfigPanelIfShown()
            ST.UpdateGroupSizeLabel(frame)
        end,
        function()
            return frame._dragInProgress == true
                or (frame.resizeGrip and frame.resizeGrip._resizeActive == true)
        end,
        { labelA = "w:", labelB = "h:" }
    )
    frame.coordLabel._exclusiveEditLabel = frame.sizeLabel
    frame.sizeLabel._exclusiveEditLabel = frame.coordLabel
    ST.UpdateGroupSizeLabel(frame)

    local isCursorAnchored = IsCursorAnchor(group.anchor)
    -- An Aura Panel is exempt alongside the Rotation Assistant: it holds a
    -- reserved one-cell footprint while empty precisely so it can be placed
    -- before its first aura is added.
    local hasDragEntry = self:IsRotationAssistantGroup(group)
        or ST.IsAuraPanelGroup(group)
        or #group.buttons > 0
    self:SetGroupDragControlsShown(frame, (not isLocked) and hasDragEntry and not isTextureMode and not isCursorAnchored)

    -- Drag scripts (check lock state at drag time)
    frame:SetScript("OnDragStart", function(self)
        self._arrangePanelSurfaceDrag = nil
        CancelCoordinateEdit(self.coordLabel)
        CancelCoordinateEdit(self.sizeLabel)
        local locked = GetContainerState(self.groupId)
        local previewActive, selectedInContainer, containerId = GetContainerPreviewSelectionState(self.groupId)
        local dragGroup = CooldownCompanion.db.profile.groups[self.groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
            -- A drag on a parked-but-unselected panel selects it first.
            if not CooldownCompanion:ActivateArrangePanel(dragGroup.parentContainerId, self.groupId, false) then
                return
            end
            self._arrangePanelSurfaceDrag = true
            BeginCursorAnchorLayoutPreviewPanelDrag(CooldownCompanion, self, self.groupId)
            return
        end
        if CooldownCompanion._combatForcedLock then
            return
        elseif previewActive then
            if not selectedInContainer then
                return
            end
            if containerId and CooldownCompanion.StartContainerMemberPreviewTracking then
                CooldownCompanion:StartContainerMemberPreviewTracking(containerId, self.groupId)
            end
            self._dragCancelPending = nil
            self._dragInProgress = true
            self:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(self)
            BeginSelfExcludedDragSnapSession(self)
        elseif not locked then
            if dragGroup and dragGroup.parentContainerId
                and not CooldownCompanion:ActivateArrangePanel(
                    dragGroup.parentContainerId,
                    self.groupId,
                    false
                ) then
                return
            end
            self._arrangePanelSurfaceDrag = true
            self._dragCancelPending = nil
            self._dragInProgress = true
            self:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(self)
            BeginSelfExcludedDragSnapSession(self)
            StartGroupCoordinateDragUpdates(self)
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        local dragGroup = CooldownCompanion.db.profile.groups[self.groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
            local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
            if self._arrangePanelSurfaceDrag then
                -- A body-drag release also fires the body's OnMouseUp; a title
                -- drag does not consume the next deliberate body click.
                self._arrangeSelectClickSuppressed = true
            end
            self._arrangePanelSurfaceDrag = nil
            EndCursorAnchorLayoutPreviewPanelDrag(CooldownCompanion, self, self.groupId, cancelSave)
            return
        end

        local _, selectedInContainer, containerId = GetContainerPreviewSelectionState(self.groupId)
        local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
        if self._arrangePanelSurfaceDrag then
            self._arrangeSelectClickSuppressed = true
        end
        self._arrangePanelSurfaceDrag = nil
        self._dragCancelPending = nil
        self._dragInProgress = nil
        if not (InCombatLockdown() and self:IsProtected()) then
            self:StopMovingOrSizing()
        end
        ApplyEndedDragSnapSession(self, not cancelSave)
        StopCoordinateDragUpdates(self)
        if selectedInContainer and containerId and CooldownCompanion.StopContainerMemberPreviewTracking then
            CooldownCompanion:StopContainerMemberPreviewTracking(containerId, self.groupId)
        end
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(self)
            return
        end
        CooldownCompanion:SaveGroupPosition(self.groupId)
        CooldownCompanion:EndMoverChromeFade(self)
    end)

    -- Every interactive panel body uses the shared toggle/solo grammar.
    -- SetFrameClickThrough WIPES OnMouseUp scripts whenever the frame goes
    -- clickthrough, so the handler is kept on the frame and re-attached by
    -- UpdateGroupClickthrough's interactive branches.
    frame._arrangeSelectOnMouseUp = function(self, button)
        local suppressed = self._arrangeSelectClickSuppressed
        self._arrangeSelectClickSuppressed = nil
        if suppressed or button ~= "LeftButton" or self._dragInProgress then
            return
        end
        local clickGroup = CooldownCompanion.db.profile.groups[self.groupId]
        if clickGroup and clickGroup.parentContainerId then
            CooldownCompanion:ActivateArrangePanel(clickGroup.parentContainerId, self.groupId, true)
        end
    end
    frame:SetScript("OnMouseUp", frame._arrangeSelectOnMouseUp)

    -- Also allow dragging from the handle
    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        frame._arrangePanelSurfaceDrag = nil
        CancelCoordinateEdit(frame.coordLabel)
        CancelCoordinateEdit(frame.sizeLabel)
        local locked = GetContainerState(groupId)
        local previewActive, selectedInContainer, containerId = GetContainerPreviewSelectionState(groupId)
        local dragGroup = CooldownCompanion.db.profile.groups[groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
            if not CooldownCompanion:ActivateArrangePanel(dragGroup.parentContainerId, groupId, false) then
                return
            end
            BeginCursorAnchorLayoutPreviewPanelDrag(CooldownCompanion, frame, groupId)
            return
        end
        if CooldownCompanion._combatForcedLock then
            return
        elseif previewActive then
            if not selectedInContainer then
                return
            end
            if containerId and CooldownCompanion.StartContainerMemberPreviewTracking then
                CooldownCompanion:StartContainerMemberPreviewTracking(containerId, groupId)
            end
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(frame)
            BeginSelfExcludedDragSnapSession(frame)
        elseif not locked then
            if dragGroup and dragGroup.parentContainerId
                and not CooldownCompanion:ActivateArrangePanel(
                    dragGroup.parentContainerId,
                    groupId,
                    false
                ) then
                return
            end
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(frame)
            BeginSelfExcludedDragSnapSession(frame)
            StartGroupCoordinateDragUpdates(frame)
        end
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        local dragGroup = CooldownCompanion.db.profile.groups[groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
            local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
            EndCursorAnchorLayoutPreviewPanelDrag(CooldownCompanion, frame, groupId, cancelSave)
            return
        end

        local _, selectedInContainer, containerId = GetContainerPreviewSelectionState(groupId)
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
        ApplyEndedDragSnapSession(frame, not cancelSave)
        StopCoordinateDragUpdates(frame)
        if selectedInContainer and containerId and CooldownCompanion.StopContainerMemberPreviewTracking then
            CooldownCompanion:StopContainerMemberPreviewTracking(containerId, groupId)
        end
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(frame)
            return
        end
        CooldownCompanion:SaveGroupPosition(groupId)
        CooldownCompanion:EndMoverChromeFade(frame)
    end)

    -- Update functions
    frame.UpdateCooldowns = function(self)
        for _, button in ipairs(self.buttons) do
            button:UpdateCooldown()
        end
    end
    
    frame.Refresh = function(self)
        CooldownCompanion:RefreshGroupFrame(self.groupId)
    end
    
    -- Store the frame
    self.groupFrames[groupId] = frame

    -- Create Masque group if enabled
    if group.masqueEnabled and self.Masque and not ST.IsAuraPanelGroup(group) then
        self:CreateMasqueGroup(groupId)
    end

    -- Create buttons
    self:PopulateGroupButtons(groupId)
    
    -- Show/hide from runtime activity only. Config selection is mirror-only.
    if ShouldShowGroupFrameForRuntime(self, groupId, group) then
        frame:Show()
        -- Apply current alpha from the alpha fade system so frame doesn't flash at 1.0
        ApplyCurrentAlphaIfPresent(self, frame, groupId, group)
    else
        frame:Hide()
    end

    self:RefreshCursorAnchorTicker()
    if self.RefreshAlphaUpdateDriver and not self._creatingAllGroupFrames then
        self:RefreshAlphaUpdateDriver()
    end

    return frame
end


function CooldownCompanion:AnchorGroupFrame(frame, anchor, forceCenter)
    -- Deferred during combat — ClearAllPoints/SetPoint are protected.
    if InCombatLockdown() and frame:IsProtected() then
        frame._anchorDirty = true
        return
    end

    if IsCursorAnchor(anchor) then
        local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[frame.groupId]
        local canUseCursorAnchor = self:CanGroupUseCursorAnchor(group)
        if not canUseCursorAnchor then
            frame._anchorDirty = nil
            frame:ClearAllPoints()
            frame._hasBeenSized = false
            if frame.alphaSyncFrame then
                frame.alphaSyncFrame:SetScript("OnUpdate", nil)
            end
            SetExternalAnchorAlphaSyncActive(frame, false)
            frame.anchoredToParent = nil
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            UpdateCoordLabel(frame, 0, 0)
            if self.RefreshCursorAnchorTicker then
                self:RefreshCursorAnchorTicker()
            end
            return
        end
        local cursorX, cursorY = GetCursorAnchorLayoutPreviewPosition(self, frame.groupId)
        ApplyCursorAnchorPosition(self, frame, anchor, cursorX, cursorY, true)
        if self.RefreshCursorAnchorTicker then
            self:RefreshCursorAnchorTicker()
        end
        return
    end

    frame._anchorDirty = nil
    frame:ClearAllPoints()

    -- ClearAllPoints removes all anchor points, discarding any offsets that
    -- AdjustPointsOffset added for compact anchor compensation.  Clear the
    -- sized flag so subsequent ResizeGroupFrame calls (from PopulateGroupButtons
    -- or the layout ticker) treat the freshly-set anchor as the baseline —
    -- no compensation relative to the previous size.
    frame._hasBeenSized = false

    -- Stop any existing alpha sync
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    SetExternalAnchorAlphaSyncActive(frame, false)
    frame.anchoredToParent = nil

    local relativeTo = anchor.relativeTo
    if relativeTo and relativeTo ~= "UIParent" then
        local relativeFrame, anchorState = ResolveSafeAnchorTarget(self, frame.groupId, "group", relativeTo)
        if relativeFrame then
            -- Position against the target's ANCHORING BODY: a sectioned panel's
            -- frame spans the union of its base cluster and its sections, and
            -- the base row is what a dependent is glued to. Identity stays the
            -- real frame -- alpha inheritance, validation, and the circular
            -- guard all key on the panel, not on its interior stand-in.
            frame:SetPoint(anchor.point, ST.GetPanelAnchorBodyFrame(relativeFrame),
                anchor.relativePoint, anchor.x, anchor.y)
            UpdateCoordLabel(frame, anchor.x, anchor.y)
            -- Store reference for alpha inheritance
            frame.anchoredToParent = relativeFrame
            -- Set up alpha sync
            self:SetupAlphaSync(frame, relativeFrame)
            return
        else
            -- Unsafe or missing target: use a temporary visual fallback without
            -- rewriting the saved anchor. Panels prefer their container first.
            local containerName = GetPanelContainerFrameName(frame.groupId)
            if containerName then
                local containerFrame = _G[containerName]
                if containerFrame then
                    frame:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", 0, 0)
                    frame.anchoredToParent = containerFrame
                    self:SetupAlphaSync(frame, containerFrame)
                    -- Don't overwrite group.anchor — preserve custom anchor
                    -- for re-anchor pass after all frames are created
                    UpdateCoordLabel(frame, 0, 0)
                    return
                end
            end
            -- If the target is merely missing, allow force-center recovery.
            -- Unsafe external targets should stay preserved until the user
            -- intentionally changes them.
            -- Otherwise use saved position relative to UIParent
            if forceCenter and anchorState ~= "unsafe" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                -- Update the saved anchor to reflect the centered position
                local group = self.db.profile.groups[frame.groupId]
                if group then
                    group.anchor = {
                        point = "CENTER",
                        relativeTo = "UIParent",
                        relativePoint = "CENTER",
                        x = 0,
                        y = 0,
                    }
                end
                UpdateCoordLabel(frame, 0, 0)
                return
            end
        end
    end

    -- Anchor to UIParent using saved position (preserves position across reloads)
    frame:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
    UpdateCoordLabel(frame, anchor.x, anchor.y)
end

function CooldownCompanion:SetupAlphaSync(frame, parentFrame)
    local shouldSync, inheritsAnchorAlpha, inheritsExternalAlpha = ShouldSyncAnchorAlpha(self, frame.groupId, parentFrame)
    if not shouldSync then
        if frame.alphaSyncFrame then
            frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        end
        SetExternalAnchorAlphaSyncActive(frame, false)
        ApplyGroupOwnAlpha(frame)
        return
    end

    -- Create a hidden frame to handle OnUpdate if needed
    if not frame.alphaSyncFrame then
        frame.alphaSyncFrame = CreateFrame("Frame", nil, frame)
    end

    SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)

    if inheritsAnchorAlpha and self.alphaState then
        self.alphaState[frame.groupId] = nil
    end

    -- If this group has baseline alpha < 1, the alpha fade system takes
    -- priority unless panel alpha inheritance is explicitly active.
    local _, baseAlpha = GetContainerState(frame.groupId)
    if baseAlpha < 1 and not inheritsAnchorAlpha then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        SetExternalAnchorAlphaSyncActive(frame, false)
        return
    end

    -- Sync alpha immediately — use parent's natural alpha to avoid config override cascade
    local lastAlpha = GetAnchorInheritedAlpha(parentFrame)
    if lastAlpha ~= nil then
        SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)
        frame:SetAlpha(lastAlpha)
    elseif ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId) then
        lastAlpha = 1
        frame:SetAlpha(1)
    end

    -- Sync alpha at ~30Hz (smooth enough for fade animations, avoids per-frame overhead)
    local accumulator = 0
    local SYNC_INTERVAL = 1 / 30
    frame.alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
        accumulator = accumulator + dt
        if accumulator < SYNC_INTERVAL then return end
        accumulator = 0
        if frame.anchoredToParent then
            -- Skip sync if this panel owns alpha locally or the group is unlocked.
            local locked, bAlpha = GetContainerState(frame.groupId)
            if (bAlpha < 1 and not inheritsAnchorAlpha) or not locked then return end
            -- Read parent's natural alpha to avoid config override cascade
            local alpha = GetAnchorInheritedAlpha(frame.anchoredToParent)
            if alpha == nil then return end
            SetExternalAnchorAlphaSyncActive(frame, inheritsExternalAlpha)
            -- Explicit layout preview: retain natural alpha for downstream
            -- chains while the positioned frame itself stays fully visible.
            if ST.IsGroupRuntimeLayoutPreviewActive(frame.groupId) then
                frame._naturalAlpha = alpha
                if lastAlpha ~= 1 then
                    lastAlpha = 1
                    frame:SetAlpha(1)
                end
                return
            end
            frame._naturalAlpha = nil
            if lastAlpha == nil or alpha ~= lastAlpha then
                lastAlpha = alpha
                frame:SetAlpha(alpha)
            end
        end
    end)
end

ComputeGroupFrameCoordinates = function(
    self,
    frame,
    groupId,
    group,
    useResolvedReference,
    resolvedRelativeTo,
    resolvedRelativeFrame,
    resolvedAnchorState
)
    -- Get the screen-space center of our frame
    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()

    -- Determine the reference frame and its dimensions
    local relativeTo = useResolvedReference and resolvedRelativeTo or group.anchor.relativeTo
    local relFrame = useResolvedReference and resolvedRelativeFrame or nil
    local anchorState = useResolvedReference and resolvedAnchorState or nil
    if not useResolvedReference and relativeTo and relativeTo ~= "UIParent" then
        relFrame, anchorState = ResolveSafeAnchorTarget(self, groupId, "group", relativeTo)
    end
    if anchorState == "unsafe" then
        return nil, nil, relativeTo, nil, nil, nil, anchorState
    end
    if not relFrame then
        -- Panels: try container frame before UIParent
        local containerName = GetPanelContainerFrameName(groupId)
        if containerName then
            relFrame = _G[containerName]
            if relFrame then
                relativeTo = containerName
            end
        end
        if not relFrame then
            relFrame = UIParent
            relativeTo = "UIParent"
        end
    end

    -- Measure -- and hand back for the re-anchor SaveGroupPosition does with it
    -- -- the target's anchoring body, so a stored offset means the same thing
    -- the SetPoint in AnchorGroupFrame will read it as. `relativeTo` keeps
    -- naming the real panel: that name is what gets saved and resolved.
    relFrame = ST.GetPanelAnchorBodyFrame(relFrame)

    local rw, rh = relFrame:GetSize()
    local rcx, rcy = relFrame:GetCenter()

    -- Convert our frame center into an offset from the user's chosen anchor/relativePoint
    local desiredPoint = group.anchor.point
    local desiredRelPoint = group.anchor.relativePoint

    -- Screen position of our frame's desired anchor point
    local fax, fay = GetAnchorOffset(desiredPoint, fw, fh)
    local framePtX = cx + fax
    local framePtY = cy + fay

    -- Screen position of the reference frame's desired relative point
    local rax, ray = GetAnchorOffset(desiredRelPoint, rw, rh)
    local refPtX = rcx + rax
    local refPtY = rcy + ray

    -- The offset is the difference, rounded to 1 decimal place
    local newX = math_floor((framePtX - refPtX) * 10 + 0.5) / 10
    local newY = math_floor((framePtY - refPtY) * 10 + 0.5) / 10
    return newX, newY, relativeTo, relFrame, desiredPoint, desiredRelPoint, anchorState
end

function CooldownCompanion:SaveGroupPosition(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end
    if IsCursorAnchor(group.anchor) then
        return
    end

    local previousRelativeTo = group.anchor.relativeTo
    local newX, newY, relativeTo, relFrame, desiredPoint, desiredRelPoint, anchorState = ComputeGroupFrameCoordinates(
        self,
        frame,
        groupId,
        group
    )
    if anchorState == "unsafe" then
        self:AnchorGroupFrame(frame, group.anchor)
        return
    end

    group.anchor.x = newX
    group.anchor.y = newY
    group.anchor.relativeTo = relativeTo
    if relativeTo ~= previousRelativeTo then
        self:RebuildPanelAlphaDependencyTargets()
    end

    -- Re-anchor with the corrected values so WoW doesn't change our anchor point
    frame:ClearAllPoints()
    frame:SetPoint(desiredPoint, relFrame, desiredRelPoint, newX, newY)

    UpdateCoordLabel(frame, newX, newY)
    self:RefreshConfigPanel()
    local containerId = group.parentContainerId
    if containerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(containerId)
    end
end

-- Compute button width/height from group style (bar mode vs square vs non-square).
-- Returns width, height, isBarMode.
local function GetButtonDimensions(group, buttonUsabilityOptions, groupId)
    local style = group.style or {}
    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    local w, h
    if isTextureMode then
        w, h = 1, 1
    elseif isTextMode then
        if GetTextEntryMetrics then
            -- The grid pitch is the widest/tallest usable entry. Each entry
            -- frame keeps its own measured size (UpdateStyle -> ApplyTextLayout),
            -- so short entries stay short inside a wider pitch. The group-level
            -- format seeds a floor so an entry-less panel still has a size.
            w, h = GetTextEntryMetrics(style, nil, style.textFormat or "{name}  {status}")
            for _, buttonData in ipairs(group.buttons or {}) do
                if CooldownCompanion:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
                    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(style, buttonData)
                    local fmt = buttonData.textFormat or effectiveStyle.textFormat or "{name}  {status}"
                    local buttonWidth, buttonHeight = GetTextEntryMetrics(effectiveStyle, buttonData, fmt)
                    w = math_max(w, buttonWidth)
                    h = math_max(h, buttonHeight)
                end
            end
        else
            w, h = 200, 20
        end
    elseif isBarMode then
        w, h = style.barLength or 180, style.barHeight or 20
        if style.barFillVertical then w, h = h, w end
    elseif style.maintainAspectRatio then
        local size = style.buttonSize or ST.BUTTON_SIZE
        w, h = size, size
    else
        w = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        h = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end
    return w, h, isBarMode
end

-- Zero-based row, col of a 1-based Aura Panel cell.
-- Bars stack in a single column: their entries render through the aura
-- container as a flowed bar list, so buttonsPerRow has no meaning there.
function CooldownCompanion:GetAuraPanelCellSlot(group, slotIndex)
    local style = group.style or {}
    if group.displayMode == "bars" then
        return slotIndex - 1, 0
    end
    local buttonsPerRow = math_max(1, style.buttonsPerRow or 12)
    if ST.GetPanelLayoutOrientation(group.displayMode, style) == "horizontal" then
        return math_floor((slotIndex - 1) / buttonsPerRow), (slotIndex - 1) % buttonsPerRow
    end
    return (slotIndex - 1) % buttonsPerRow, math_floor((slotIndex - 1) / buttonsPerRow)
end

-- The grid an Aura Panel's footprint and its unlock placeholders share.
-- The panel sizes to the FULL expanded grid -- one cell per entry whether that
-- entry's aura is up or not -- because Blizzard's container packs only ACTIVE
-- auras, and a footprint that followed activity would move under the player
-- every time an aura came or went. The extent is walked off GetAuraPanelCellSlot
-- instead of recomputed, so cell placement and cell count can never disagree.
-- An empty panel still owns one cell, which keeps it grabbable while unlocked.
-- Returns cols, rows, cellCount, cellWidth, cellHeight, spacing.
function CooldownCompanion:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions)
    local cellWidth, cellHeight = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local cellCount = self.GetGroupLayoutButtonCount
        and self:GetGroupLayoutButtonCount(groupId, group, {
            buttonUsabilityOptions = buttonSizingOptions,
        })
        or 0
    local cols, rows = 1, 1
    for slotIndex = 1, cellCount do
        local row, col = self:GetAuraPanelCellSlot(group, slotIndex)
        if row + 1 > rows then rows = row + 1 end
        if col + 1 > cols then cols = col + 1 end
    end
    return cols, rows, cellCount, cellWidth, cellHeight, style.buttonSpacing or ST.BUTTON_SPACING
end

-- Unlock affordance only. An Aura Panel materializes no CC buttons, so while it
-- is unlocked it would otherwise be an empty box with nothing to aim at. One dim
-- tile per entry marks the cells the aura container fills once those auras go
-- up. The preview root belongs to the PANEL rather than its drag handle: it must
-- remain visible while drag/nudge chrome fades, and while an unlocked container
-- is showing all of its member panels before one is selected.
function CooldownCompanion:SetAuraPanelPlaceholderPreviewShown(frame, shown)
    if not frame then return end

    shown = shown == true
    frame._auraPanelPlaceholderPreviewShown = shown or nil
    local root = frame._auraPanelPlaceholderRoot
    if root then
        if shown then
            local _, selectedInContainer = GetContainerPreviewSelectionState(frame.groupId)
            ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
        end
        root:SetIgnoreParentAlpha(shown and frame._unlockGhost == true)
        root:SetShown(shown)
    end
    -- The mixed panel's aura-section tiles ride the same switch, so every path
    -- that raises or drops this preview -- drag chrome, container preview, the
    -- combat forced lock -- covers both without knowing which it has.
    ST.SetAuraSectionPlaceholderRootShown(frame, shown)

    -- The placeholders are the complete unlock presentation. Keep the live
    -- aura container bound but hidden so active auras are not double-drawn.
    -- The fan-out is by CHROME frame, so on a mixed panel this reaches that
    -- panel's own section containers and nothing else.
    self:SetAuraPanelChromeSuppressed(frame, shown)
end

function CooldownCompanion:UpdateAuraPanelPlaceholders(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    if not (frame and group) then return end

    local tiles = frame._auraPanelPlaceholders
    if not ST.IsAuraPanelGroup(group) then
        for _, tile in ipairs(tiles or {}) do
            tile:Hide()
        end
        self:SetAuraPanelPlaceholderPreviewShown(frame, false)
        return
    end

    local root = frame._auraPanelPlaceholderRoot
    if not root then
        root = CreateFrame("Frame", nil, frame)
        root:SetAllPoints(frame)
        root:EnableMouse(false)
        frame._auraPanelPlaceholderRoot = root
    end
    local previewShown = frame._auraPanelPlaceholderPreviewShown == true
    local _, selectedInContainer = GetContainerPreviewSelectionState(groupId)
    ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
    root:SetIgnoreParentAlpha(previewShown and frame._unlockGhost == true)
    root:SetShown(previewShown)

    if not tiles then
        tiles = {}
        frame._auraPanelPlaceholders = tiles
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local cellWidth, cellHeight, spacing = select(4, self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions))
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local isBarMode = group.displayMode == "bars"

    local slotIndex = 0
    for _, buttonData in ipairs(group.buttons or {}) do
        if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions) then
            slotIndex = slotIndex + 1
            local tile = tiles[slotIndex]
            if not tile then
                tile = CreateFrame("Frame", nil, root, "BackdropTemplate")
                tile:EnableMouse(false)
                tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                tile:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
                tile.icon = tile:CreateTexture(nil, "ARTWORK")
                tile.icon:SetAlpha(0.6)
                tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY")
                tile.iconBorderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY")
                tile.barBounds = CreateFrame("Frame", nil, tile)
                tile.barBounds:EnableMouse(false)
                tile.iconBounds = CreateFrame("Frame", nil, tile)
                tile.iconBounds:EnableMouse(false)
                tiles[slotIndex] = tile
            end

            local row, col = self:GetAuraPanelCellSlot(group, slotIndex)
            tile:SetSize(cellWidth, cellHeight)
            tile:ClearAllPoints()
            tile:SetPoint(
                growthAnchor,
                frame,
                growthAnchor,
                xMul * col * (cellWidth + spacing),
                yMul * row * (cellHeight + spacing)
            )

            local effectiveStyle = self:GetEffectiveStyle(style, buttonData) or style
            local borderSize = effectiveStyle.borderSize or ST.DEFAULT_BORDER_SIZE
            local borderRenderMode = ST.GetBorderRenderMode(effectiveStyle)
            local effectiveBorderRenderMode = ST.GetEffectiveBorderRenderMode(
                borderRenderMode, nil, borderSize)
            local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(
                tile, borderSize, borderRenderMode)
            local borderColor = effectiveStyle.borderColor or { 0, 0, 0, 1 }

            -- Bar placeholders mirror the live Aura Panel's two chrome regions:
            -- the remaining bar area and, when enabled, its separate icon square.
            -- Icon placeholders keep one border around the whole cell.
            tile.icon:ClearAllPoints()
            tile.barBounds:ClearAllPoints()
            tile.iconBounds:ClearAllPoints()
            local placeholderIconShown = true
            local iconWidth, iconHeight
            if isBarMode then
                local isVertical = style.barFillVertical == true
                local iconSize, iconOffset, iconReverse
                placeholderIconShown, iconSize, iconOffset, iconReverse =
                    ST._GetAuraPanelBarIconGeometry(
                        effectiveStyle, true, isVertical, cellWidth, cellHeight)

                local barWidth, barHeight = cellWidth, cellHeight
                if placeholderIconShown then
                    local step = iconSize + iconOffset
                    tile.iconBounds:SetSize(iconSize, iconSize)
                    if isVertical then
                        local iconEdge, barEdge = "TOP", "BOTTOM"
                        if iconReverse then iconEdge, barEdge = "BOTTOM", "TOP" end
                        tile.iconBounds:SetPoint(iconEdge, tile, iconEdge, 0, 0)
                        barHeight = math_max(cellHeight - step, 1)
                        tile.barBounds:SetPoint(barEdge, tile, barEdge, 0, 0)
                    else
                        local iconEdge, barEdge = "LEFT", "RIGHT"
                        if iconReverse then iconEdge, barEdge = "RIGHT", "LEFT" end
                        tile.iconBounds:SetPoint(iconEdge, tile, iconEdge, 0, 0)
                        barWidth = math_max(cellWidth - step, 1)
                        tile.barBounds:SetPoint(barEdge, tile, barEdge, 0, 0)
                    end

                    local iconSide = math_max(1, iconSize - (2 * borderLayoutSize))
                    tile.icon:SetSize(iconSide, iconSide)
                    tile.icon:SetPoint("CENTER", tile.iconBounds, "CENTER", 0, 0)
                    iconWidth, iconHeight = iconSide, iconSide
                else
                    tile.iconBounds:SetSize(1, 1)
                    tile.iconBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                    tile.barBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                end
                tile.barBounds:SetSize(barWidth, barHeight)

                ST.ApplyBorderTextures(
                    tile.borderTextures, tile.barBounds, borderColor,
                    borderSize, effectiveBorderRenderMode)
                if placeholderIconShown then
                    ST.ApplyBorderTextures(
                        tile.iconBorderTextures, tile.iconBounds, borderColor,
                        borderSize, effectiveBorderRenderMode)
                else
                    ST.HideBorderTextures(tile.iconBorderTextures)
                end
            else
                tile.barBounds:SetSize(1, 1)
                tile.barBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                tile.iconBounds:SetSize(1, 1)
                tile.iconBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                ST.ApplyBorderTextures(
                    tile.borderTextures, tile, borderColor,
                    borderSize, effectiveBorderRenderMode)
                ST.HideBorderTextures(tile.iconBorderTextures)

                tile.icon:SetPoint(
                    "TOPLEFT", tile, "TOPLEFT", borderLayoutSize, -borderLayoutSize)
                tile.icon:SetPoint(
                    "BOTTOMRIGHT", tile, "BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
                iconWidth = math_max(1, cellWidth - (2 * borderLayoutSize))
                iconHeight = math_max(1, cellHeight - (2 * borderLayoutSize))
            end

            if placeholderIconShown then
                if ST._ApplyIconTexCoord then
                    ST._ApplyIconTexCoord(tile.icon, iconWidth, iconHeight, effectiveStyle.iconZoom)
                else
                    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end

            local icon = buttonData.type == "spell" and C_Spell.GetSpellTexture(buttonData.id) or nil
            if placeholderIconShown and icon and not issecretvalue(icon) then
                tile.icon:SetTexture(icon)
                tile.icon:Show()
            else
                tile.icon:Hide()
            end

            tile:Show()
        end
    end

    for extraIndex = slotIndex + 1, #tiles do
        tiles[extraIndex]:Hide()
    end
end

local function ApplyTextGroupHeader(self, frame, group, style, isTextMode)
    local showHeader = isTextMode and style.showTextGroupHeader == true
    local headerHeight = 0

    if showHeader then
        if not frame.textHeader then
            frame.textHeader = frame:CreateFontString(nil, "OVERLAY")
            frame.textHeader:SetJustifyV("TOP")
        end
        local font = self:FetchFont(style.textFont or "Friz Quadrata TT")
        local fontSize = style.textHeaderFontSize or style.textFontSize or 12
        local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
        frame.textHeader:SetFont(font, fontSize, fontOutline)
        local hdrColor = style.textHeaderFontColor or {1, 1, 1, 1}
        frame.textHeader:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
        ST.ApplyFontShadowForOutline(frame.textHeader, fontOutline, style.textShadow == true)
        local align = style.textAlignment or "LEFT"
        frame.textHeader:SetJustifyH(align)
        frame.textHeader:SetText(group.name or "")
        frame.textHeader:ClearAllPoints()
        local growthOrigin = style.growthOrigin or "TOPLEFT"
        -- Raw "BOTTOM" counts only while it is the ACTIVE centered edge; an
        -- axis-mismatched value folds to TOPLEFT in layout, and the header
        -- must land on the same edge the entries grow from.
        local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT"
            or ST.GetCenteredGrowthEdge(growthOrigin, ST.GetPanelLayoutOrientation(group.displayMode, style)) == "BOTTOM")
            and "BOTTOM" or "TOP"
        local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
        local parentAnchor = anchor
        local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
        local yOff = vEdge == "BOTTOM" and 1 or -1
        frame.textHeader:SetPoint(anchor, frame, parentAnchor, xOff, yOff)
        frame.textHeader:SetWidth(frame:GetWidth() - 4)
        frame.textHeader:Show()
        headerHeight = fontSize + 4
    elseif frame.textHeader then
        frame.textHeader:Hide()
    end

    frame._textHeaderHeight = headerHeight
    frame._textHeaderShown = showHeader
    return headerHeight
end

local function ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    local isTriggerMode = group.displayMode == "trigger"
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local centeredEdge = not ST.IsAuraPanelGroup(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, orientation) or nil
    -- Panel Sections place their own members and park the base cluster on an
    -- interior anchor frame; the loop below then runs its existing arithmetic
    -- against that frame instead of the panel. A panel with no sections gets
    -- nil here and lays out through the exact code it always did.
    local sectionLayout, sectionLists, baseAnchor = ST.PrepareSectionedPanelLayout(
        frame, group, frame.buttons, buttonWidth, buttonHeight, spacing, headerHeight,
        buttonSizingOptions)
    local layoutRef = baseAnchor or frame
    local layoutButtons = sectionLists and sectionLists.base or frame.buttons
    local total = #layoutButtons
    local lineCount = math_ceil(total / buttonsPerRow)
    local visibleIndex = 0

    for _, button in ipairs(layoutButtons) do
        visibleIndex = visibleIndex + 1
        ClearButtonCompactSlotCache(button)
        button:ClearAllPoints()
        if isTriggerMode then
            button:SetPoint("CENTER", layoutRef, "CENTER", 0, 0)
        elseif centeredEdge then
            -- Each button pins its edge midpoint to the frame's, so full lines
            -- land where corner growth puts them and the trailing partial line
            -- centers itself against them.
            local line = math_floor((visibleIndex - 1) / buttonsPerRow)
            local indexInLine = (visibleIndex - 1) % buttonsPerRow
            local itemsInLine = (line == lineCount - 1) and (total - line * buttonsPerRow) or buttonsPerRow
            if orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                button:SetPoint(centeredEdge, layoutRef, centeredEdge,
                    (indexInLine - (itemsInLine - 1) / 2) * (buttonWidth + spacing),
                    edgeYMul * (line * (buttonHeight + spacing) + headerHeight))
            else
                local edgeXMul = centeredEdge == "LEFT" and 1 or -1
                button:SetPoint(centeredEdge, layoutRef, centeredEdge,
                    edgeXMul * line * (buttonWidth + spacing),
                    ((itemsInLine - 1) / 2 - indexInLine) * (buttonHeight + spacing) - headerHeight / 2)
            end
        else
            local row, col
            if orientation == "horizontal" then
                row = math_floor((visibleIndex - 1) / buttonsPerRow)
                col = (visibleIndex - 1) % buttonsPerRow
            else
                col = math_floor((visibleIndex - 1) / buttonsPerRow)
                row = (visibleIndex - 1) % buttonsPerRow
            end
            button:SetPoint(growthAnchor, layoutRef, growthAnchor, xMul * col * (buttonWidth + spacing), yMul * (row * (buttonHeight + spacing) + headerHeight))
        end
    end

    if sectionLayout then
        -- The count stays the panel's materialized total: section members were
        -- placed by PrepareSectionedPanelLayout, not by the base loop above.
        visibleIndex = #frame.buttons
    end
    frame.visibleButtonCount = isTriggerMode and (visibleIndex > 0 and 1 or 0) or visibleIndex
    if group.parentContainerId and not self:IsGroupCompactLayoutActive(groupId, group) and self.GetGroupLayoutButtonCount then
        frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group, {
            buttonUsabilityOptions = buttonSizingOptions,
        })
    else
        frame.layoutButtonCount = nil
    end
    frame._layoutDirty = false
end

local function FinishGroupButtonRefresh(self, groupId, frame, group)
    -- Resize the frame to fit visible buttons
    self:ResizeGroupFrame(groupId)

    -- Reset the sized flag so the next ResizeGroupFrame call skips compact
    -- anchor compensation and treats the current size as a baseline. A
    -- non-compact panel with an ACTIVE centered edge keeps its baseline
    -- instead: it has no follow-up reflow resize to rebuild one, and the
    -- edge must hold across config-driven size changes. Explicit re-anchors
    -- (AnchorGroupFrame) still reset, so a freshly placed frame baselines.
    local style = group.style or {}
    local holdCenteredBaseline = not self:IsGroupCompactLayoutActive(groupId, group)
        and not ST.IsAuraPanelGroup(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, ST.GetPanelLayoutOrientation(group.displayMode, style)) ~= nil
    if not holdCenteredBaseline then
        frame._hasBeenSized = false
    end

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()

    -- Compact mode: apply reflow immediately so newly rebuilt buttons don't
    -- briefly appear before the next ticker-driven layout pass.
    if self:IsGroupCompactLayoutActive(groupId, group) then
        frame._layoutDirty = true
        self:UpdateGroupLayout(groupId)
    end

    -- Propagate group frame strata to all button sub-elements
    local effectiveStrata = group.frameStrata or "MEDIUM"
    for _, button in ipairs(frame.buttons) do
        PropagateFrameStrata(button, effectiveStrata)
    end

    -- Update event-driven range check registrations
    self:UpdateRangeCheckRegistrations()
end

local function IsIconMasqueStyleRefreshUnsafe(self, group)
    local displayMode = group and group.displayMode
    return self.Masque
        and group
        and group.masqueEnabled
        and (displayMode == nil or displayMode == "icons")
end

local function ClearStyleUpdateEntries(entries, visibleCount)
    if not entries then return end
    local count = math_max(entries.count or 0, visibleCount or 0)
    for index = 1, count do
        entries[index] = nil
    end
    entries.count = 0
end

local function GetStyleUpdateEntries(self, groupId, frame, group)
    if IsIconMasqueStyleRefreshUnsafe(self, group) then
        return nil
    end

    local style = group.style or {}
    local isTextMode = group.displayMode == "text"
    local headerShown = isTextMode and style.showTextGroupHeader == true
    if (frame._textHeaderShown == true) ~= headerShown then
        return nil
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local sourceButtons = GetRuntimeGroupButtonList(self, frame, group)
    local entries = frame._styleUpdateEntries
    if not entries then
        entries = {}
        frame._styleUpdateEntries = entries
    end

    local previousCount = entries.count or 0
    local visibleIndex = 0
    -- Filtered exactly the way PopulateGroupButtons filters when it BUILDS the
    -- list: an aura-section member materializes no button, so counting one here
    -- would make the expectation disagree with frame.buttons on every style
    -- update and drop the fast path forever.
    local auraSectionPanel = ST.PanelHasAuraSection(group)
    for sourceIndex, buttonData in ipairs(sourceButtons) do
        if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions)
            and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
            visibleIndex = visibleIndex + 1
            local button = frame.buttons and frame.buttons[visibleIndex]
            if not button then
                ClearStyleUpdateEntries(entries, visibleIndex)
                return nil
            end
            local effectiveStyle = self:GetEffectiveStyle(style, buttonData)
            local poolKey = GetButtonPoolKey(group, buttonData, effectiveStyle)
            if button.buttonData ~= buttonData
                or button.index ~= sourceIndex
                or GetExistingButtonPoolKey(button) ~= poolKey then
                ClearStyleUpdateEntries(entries, visibleIndex)
                return nil
            end

            local entry = entries[visibleIndex]
            if not entry then
                entry = {}
                entries[visibleIndex] = entry
            end
            entry.style = effectiveStyle
        end
    end

    if #(frame.buttons or {}) ~= visibleIndex then
        ClearStyleUpdateEntries(entries, visibleIndex)
        return nil
    end

    for index = visibleIndex + 1, previousCount do
        entries[index] = nil
    end
    entries.count = visibleIndex
    return entries, buttonUsabilityOptions
end

function CooldownCompanion:PopulateGroupButtons(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local isBarMode = group.displayMode == "bars"
    local style = group.style or {}
    local sourceButtons = GetRuntimeGroupButtonList(self, frame, group)

    -- Release existing buttons into bounded per-frame pools.
    for _, button in ipairs(frame.buttons) do
        ReleaseButtonToPool(self, frame, groupId, button)
    end
    wipe(frame.buttons)

    -- Text mode group header
    local isTextMode = group.displayMode == "text"
    local headerHeight = ApplyTextGroupHeader(self, frame, group, style, isTextMode)

    if ST.IsAuraPanelGroup(group) then
        -- An Aura Panel renders every entry through ONE Blizzard aura container
        -- mounted on this frame, so CC creates no buttons for it at all. Drain
        -- the pools instead of leaving the released buttons parked in them:
        -- nothing on this frame will ever acquire from a pool again, so pooled
        -- frames would sit there for the session. Normally there are none --
        -- the subtype is fixed at creation -- so this is defensive.
        self:ReleaseGroupButtonPools(frame)
        -- The counts carry the FULL expanded grid rather than aura activity, so
        -- the footprint holds still while auras come and go.
        local cellCount = select(3, self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions))
        frame.visibleButtonCount = cellCount
        -- There is no frame.buttons list here for the availability sweep's
        -- identity comparison to read, so stamp the equivalent: the ordered
        -- identity of the very entries those cells were just counted from,
        -- under the same usability options the count used.
        -- GroupButtonSetNeedsRebuild diffs against this to decide whether the
        -- panel needs repopulating -- it is the panel's only refresh trigger.
        frame._auraPanelEntrySig = self:GetAuraPanelEntrySignature(group, buttonSizingOptions)
        -- layoutButtonCount reserves container space for entries that did not
        -- materialize; the grid already counts every entry, so it has no work.
        frame.layoutButtonCount = nil
        frame._layoutDirty = false
    else
        -- An aura-only SECTION does to its own members what an Aura Panel does to
        -- a whole panel: they render through Blizzard's container, so CC
        -- materializes no button for them -- and with no button they are never
        -- registered with Masque either, which is what keeps an aura section off
        -- a skin the mixed panel around it still uses.
        local auraSectionPanel = ST.PanelHasAuraSection(group)
        -- Create new buttons (skip untalented spells)
        for i, buttonData in ipairs(sourceButtons) do
            if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions)
                and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
                local effectiveStyle = self:GetEffectiveStyle(style, buttonData)
                local poolKey = GetButtonPoolKey(group, buttonData, effectiveStyle)
                local button = AcquireButtonFromPool(frame, poolKey, buttonData)
                local reusedButton = button ~= nil
                if not button then
                    if group.displayMode == "text" then
                        button = self:CreateTextFrame(frame, i, buttonData, effectiveStyle)
                    elseif isBarMode then
                        button = self:CreateBarFrame(frame, i, buttonData, effectiveStyle)
                    else
                        button = self:CreateButtonFrame(frame, i, buttonData, effectiveStyle)
                        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
                            button:SetAlpha(0)
                            button._lastVisAlpha = 0
                        end
                    end
                end

                button._buttonPoolKey = poolKey
                table_insert(frame.buttons, button)
                if reusedButton then
                    PreparePooledButtonForUse(self, frame, group, button, i, buttonData, effectiveStyle)
                elseif buttonData._rotationAssistantVirtual == true and self.RefreshRotationAssistantButton then
                    self:RefreshRotationAssistantButton(button)
                end

                button:Show()

                -- Add to Masque if enabled (after button is shown and in the list, icons only)
                if group.displayMode == "icons" and group.masqueEnabled then
                    self:AddButtonToMasque(groupId, button)
                end
            end
        end

        -- The mixed panel's own version of the Aura Panel refresh trigger. Its
        -- aura-section members are invisible to the frame.buttons comparison
        -- GroupButtonSetNeedsRebuild makes -- they have no button to compare --
        -- so their ordered identity is carried here instead and diffed on the
        -- next availability sweep. nil while the panel has no aura section, so
        -- an ordinary panel stores nothing and compares nothing.
        frame._auraSectionEntrySig = auraSectionPanel
            and self:GetAuraSectionEntrySignature(group, buttonSizingOptions)
            or nil

        -- The other half of that trigger: the pass that turns the LAST aura
        -- section off. RefreshGroupFrame asks for the rebind by reading the
        -- panel's current state, and by then the state says "no aura sections",
        -- so the records those sections held would stay bound until something
        -- unrelated rebound them. This marker remembers that the panel HAD one,
        -- and RefreshGroupFrame consumes it once and clears it -- so a panel that
        -- never carried an aura section never sets it and never requests a thing.
        if auraSectionPanel then
            frame._auraSectionRebindOwed = true
        end

        ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    end

    FinishGroupButtonRefresh(self, groupId, frame, group)
    -- D3: button population changed — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("populate")
    -- Aura slots bind to materialized buttons: re-run the (coalesced,
    -- OOC-deferred) rebind pass whenever population changes.
    self:RequestAuraRebind("populate")
    -- _hasBeenSized is now true if the compact resize ran (set by
    -- ResizeGroupFrame), or still false if all buttons were visible and no
    -- compact resize was needed. When effective compact layout is off, it stays false
    -- (harmless — ResizeGroupFrame skips compensation for non-compact groups).
    -- Either state is correct: the first ticker-driven resize after this
    -- will either compensate (true) relative to the established compact
    -- baseline, or skip compensation (false) to establish a new baseline
    -- when config-forced visibility clears.
end

function CooldownCompanion:ResizeGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    -- Stamped by whichever layout pass ran last (ApplyActiveButtonLayout, or
    -- UpdateGroupLayout under compact mode), so the footprint and the placement
    -- are measured from one set of numbers and can never disagree.
    local sectionLayout = frame._sectionLayout
    local numButtons = frame.visibleButtonCount
        or (self:IsRotationAssistantGroup(group) and 1)
        or #group.buttons
    if group.parentContainerId and not self:IsGroupCompactLayoutActive(groupId, group) and frame.layoutButtonCount then
        numButtons = math_max(numButtons, frame.layoutButtonCount)
    end

    local targetWidth, targetHeight
    local oldWidth, oldHeight = frame:GetSize()

    -- The section branch wins an empty count. A panel whose only entries live in
    -- AURA sections materializes no buttons at all, so numButtons reads 0 while
    -- the sections still own a real rectangle. For every other sectioned panel
    -- the two branches agree by construction (nothing materialized means every
    -- section line measures nothing, which is layout.isEmpty, whose footprint IS
    -- this one-button rectangle), so nothing else changes shape.
    if numButtons == 0 and not sectionLayout then
        targetWidth, targetHeight = buttonWidth, buttonHeight
    elseif sectionLayout then
        -- A sectioned panel spans the union of its base cluster and every
        -- section that has something visible in it. An all-hidden section
        -- contributes nothing, so the footprint never reserves empty space.
        -- footprintWidth/Height is the union, or -- with nothing visible at all
        -- -- the same one-button rectangle the numButtons == 0 branch above
        -- hands an empty panel, so the two branches cannot disagree.
        targetWidth = math_max(sectionLayout.footprintWidth, 1)
        targetHeight = math_max(sectionLayout.footprintHeight, 1)
    else
        local rows, cols
        if ST.IsAuraPanelGroup(group) then
            -- Aura Panels claim the full expanded grid regardless of which of
            -- their auras happen to be up right now.
            cols, rows = self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions)
        elseif orientation == "horizontal" then
            cols = math_min(numButtons, buttonsPerRow)
            rows = math_ceil(numButtons / buttonsPerRow)
        else
            rows = math_min(numButtons, buttonsPerRow)
            cols = math_ceil(numButtons / buttonsPerRow)
        end

        local width = cols * buttonWidth + (cols - 1) * spacing
        local height = rows * buttonHeight + (rows - 1) * spacing

        -- Add text group header height if active
        local headerH = frame._textHeaderHeight or 0
        height = height + headerH

        targetWidth = math_max(width, buttonWidth)
        targetHeight = math_max(height, buttonHeight)
    end

    -- Group frames become protected when they contain secure action buttons.
    -- Defer resizing during combat and retry from the layout ticker.
    if InCombatLockdown() and frame:IsProtected() then
        frame._sizeDirty = true
        return false
    end

    frame:SetSize(targetWidth, targetHeight)

    -- ApplyTextGroupHeader runs before the layout pass in both
    -- PopulateGroupButtons and UpdateGroupStyle, so its frame:GetWidth() read
    -- is the pre-resize width. That was survivable while text width came from
    -- a slider; auto-sized entries change the width on any format/font/name
    -- change, so re-fit the header here, where the final width is known.
    if frame._textHeaderShown and frame.textHeader then
        frame.textHeader:SetWidth(math_max(1, targetWidth - 4))
    end

    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)
    local fixedPoint
    if not ST.IsAuraPanelGroup(group) then
        -- Centered growth pins the edge midpoint so the panel's primary-axis
        -- center holds still as the frame resizes, the same compensation
        -- compact mode runs for its fixed corner. It wins over the compact
        -- start/center/end alignment, which it supersedes.
        fixedPoint = ST.GetCenteredGrowthEdge(style.growthOrigin, orientation)
    end
    if not fixedPoint and self:IsGroupCompactLayoutActive(groupId, group) then
        fixedPoint = GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, style.growthOrigin)
    end
    local canCompensateAnchor = frame._hasBeenSized and oldWidth > 0 and oldHeight > 0
    if sectionLayout or frame._sectionBaseOffsetX then
        -- A sectioned frame is bigger than its base cluster, so the same
        -- compensation has to hold a point on the CLUSTER still instead of a
        -- point on the frame -- otherwise a section appearing on one side shoves
        -- the base grid across the screen. The trailing condition catches the
        -- pass where the last section went away and the frame collapses back.
        --
        -- It runs off its OWN baseline, not _hasBeenSized. _hasBeenSized is
        -- cleared by every AnchorGroupFrame and by every non-compact
        -- FinishGroupButtonRefresh, and each of those runs immediately before
        -- the resize that a membership or geometry commit ends in -- so gating
        -- on it meant this compensation effectively never fired on an ordinary
        -- corner-growth panel. _sectionSizeBaseline says only "this frame has
        -- been through a real resize, so its rect and its section stamps
        -- describe a genuine previous state", and a re-anchor no longer
        -- invalidates that because the compensation writes its delta into the
        -- saved anchor as well as into the live points.
        local sectionAnchorX, sectionAnchorY = ST.CompensatePanelSectionAnchorDrift(
            frame, group, sectionLayout, fixedPoint,
            frame._sectionSizeBaseline and oldWidth > 0 and oldHeight > 0,
            oldWidth, oldHeight, targetWidth, targetHeight)
        if sectionAnchorX then
            UpdateCoordLabel(frame, sectionAnchorX, sectionAnchorY)
        end
    elseif fixedPoint and canCompensateAnchor then
        local anchorPoint = (group.anchor and group.anchor.point) or "CENTER"
        local oldFixedX, oldFixedY = GetAnchorOffset(fixedPoint, oldWidth, oldHeight)
        local oldAnchorX, oldAnchorY = GetAnchorOffset(anchorPoint, oldWidth, oldHeight)
        local newFixedX, newFixedY = GetAnchorOffset(fixedPoint, targetWidth, targetHeight)
        local newAnchorX, newAnchorY = GetAnchorOffset(anchorPoint, targetWidth, targetHeight)

        local deltaX = (oldFixedX - oldAnchorX) - (newFixedX - newAnchorX)
        local deltaY = (oldFixedY - oldAnchorY) - (newFixedY - newAnchorY)
        if deltaX ~= 0 or deltaY ~= 0 then
            frame:AdjustPointsOffset(deltaX, deltaY)
        end
    end

    frame._hasBeenSized = true
    -- A second, STICKY baseline flag, read only by the sectioned compensation
    -- above. _hasBeenSized answers "may the plain fixed-point compensation
    -- treat the previous size as a baseline", and is reset on purpose whenever
    -- the points are rebuilt from the saved anchor. This one answers the
    -- narrower "has this frame ever been sized for real", which a re-anchor
    -- does not change -- the saved anchor and the live points agree after every
    -- sectioned pass. It is per-frame, so a fresh frame after a /reload starts
    -- without one and its first sectioned resize establishes the baseline
    -- instead of compensating against CreateGroupFrame's placeholder size.
    frame._sectionSizeBaseline = true
    frame._sizeDirty = nil
    -- The one moment a dependent's SetPoint target has to change hands: the
    -- panel frame and its anchoring body are the same frame while there are no
    -- sections and different frames once there are. Between flips the base
    -- anchor child just moves inside the frame and dependents follow for free,
    -- so nothing pays for this on an ordinary resize.
    local anchorBodyActive = ST.IsPanelSectionAnchorBodyActive(frame)
    if anchorBodyActive ~= (frame._sectionAnchorBodyActive == true) then
        frame._sectionAnchorBodyActive = anchorBodyActive or nil
        self:ReanchorPanelSectionDependents(groupId)
    end
    -- Sizing is the one choke point every Aura Panel geometry change passes
    -- through (population, restyle, resize grip, deferred ticker resize), so the
    -- unlock placeholders re-fit here and nowhere else.
    if ST.IsAuraPanelGroup(group) then
        self:UpdateAuraPanelPlaceholders(groupId)
    elseif frame._auraSectionPlaceholders or ST.PanelHasAuraSection(group) then
        -- The aura-section twin, at the same choke point and for the same
        -- reason. Tiles it already has are enough to come back here on the pass
        -- that turned the flag OFF, which is what clears them.
        ST.UpdateAuraSectionPlaceholders(self, groupId, frame, group)
        local _, selectedInContainer = GetContainerPreviewSelectionState(groupId)
        ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
        ST.SetAuraSectionPlaceholderRootShown(frame,
            frame._auraPanelPlaceholderPreviewShown == true)
    end
    -- The section click overlays re-fit at the same choke point, so a wheel or
    -- grip resize mid-gesture keeps them glued to the rects they name.
    ST.UpdateSectionMoverOverlays(self, frame, group)
    return true
end

-- Compact layout reflow: reposition visible buttons to fill gaps left by hidden ones.
-- Only runs when compact layout is effective and _layoutDirty is true.
function CooldownCompanion:UpdateGroupLayout(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    if not frame or not group then return end

    if not self:IsGroupCompactLayoutActive(groupId, group) then
        for _, button in ipairs(frame.buttons) do
            ClearButtonCompactSlotCache(button)
        end
        frame._layoutDirty = false
        return
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)

    local maxVis = (group.maxVisibleButtons and group.maxVisibleButtons > 0) and group.maxVisibleButtons or #frame.buttons

    local visibleButtons = frame._compactVisibleButtons
    if visibleButtons then
        wipe(visibleButtons)
    else
        visibleButtons = {}
        frame._compactVisibleButtons = visibleButtons
    end
    for _, button in ipairs(frame.buttons) do
        local forceVisible = button._forceVisibleByConfig
        local shouldHide = (not forceVisible) and (button._visibilityHidden or #visibleButtons >= maxVis)
        local wasShown = button:IsShown()
        if shouldHide then
            if wasShown then
                ResetButtonGlowTransitionState(button)
            end
            button:Hide()
        else
            button:Show()
            table_insert(visibleButtons, button)
        end
    end

    local visibleCount = #visibleButtons
    local headerH = frame._textHeaderHeight or 0
    -- Sections split the pass: the base grid packs only its own visible members,
    -- and each section independently collapses its own line toward its anchor.
    -- Hidden members drop out of a section's line exactly the way they drop out
    -- of a base row here.
    local sectionLayout, sectionLists, baseAnchor = ST.PrepareSectionedPanelLayout(
        frame, group, visibleButtons, buttonWidth, buttonHeight, spacing, headerH,
        buttonSizingOptions)
    local layoutRef = baseAnchor or frame
    local layoutButtons = sectionLists and sectionLists.base or visibleButtons
    local layoutCount = #layoutButtons
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    -- A centered growth edge fully specifies the arrangement, so it wins over
    -- the compact start/center/end alignment (owner ruling 2026-08-16): each
    -- packed line centers itself against the frame's edge midpoint.
    local centeredEdge = ST.GetCenteredGrowthEdge(style.growthOrigin, orientation)
    local lineCount = centeredEdge and math_ceil(layoutCount / buttonsPerRow) or 0
    for visibleIndex, button in ipairs(layoutButtons) do
        local x, y
        if centeredEdge then
            local line = math_floor((visibleIndex - 1) / buttonsPerRow)
            local indexInLine = (visibleIndex - 1) % buttonsPerRow
            local itemsInLine = (line == lineCount - 1) and (layoutCount - line * buttonsPerRow) or buttonsPerRow
            if orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                x = (indexInLine - (itemsInLine - 1) / 2) * (buttonWidth + spacing)
                y = edgeYMul * (line * (buttonHeight + spacing) + headerH)
            else
                local edgeXMul = centeredEdge == "LEFT" and 1 or -1
                x = edgeXMul * line * (buttonWidth + spacing)
                y = ((itemsInLine - 1) / 2 - indexInLine) * (buttonHeight + spacing) - headerH / 2
            end
        else
            local row, col = GetCompactSlotForIndex(
                visibleIndex,
                layoutCount,
                buttonsPerRow,
                orientation,
                compactGrowthDirection
            )
            x = xMul * col * (buttonWidth + spacing)
            y = yMul * (row * (buttonHeight + spacing) + headerH)
        end
        local anchor = centeredEdge or growthAnchor
        if button._compactSlotAnchor ~= anchor
            or button._compactSlotX ~= x
            or button._compactSlotY ~= y then
            button:ClearAllPoints()
            button:SetPoint(anchor, layoutRef, anchor, x, y)
            button._compactSlotAnchor = anchor
            button._compactSlotX = x
            button._compactSlotY = y
        end
    end

    -- With sections in play the footprint can change while the total visible
    -- count does not (a section member hides as a base member appears), so the
    -- union is compared against the frame's real size too.
    -- Compared with a half-pixel tolerance: GetSize hands back float32 of what
    -- was set, while the union is computed in doubles (centered lines halve an
    -- odd pitch), so an exact test would report a change on a footprint that
    -- did not move and re-resize the frame every pass.
    local footprintChanged = false
    if sectionLayout then
        local currentWidth, currentHeight = frame:GetSize()
        -- Compared against the same footprintWidth/Height ResizeGroupFrame sizes
        -- from, empty panel included, or an all-hidden sectioned panel would
        -- measure 1x1 here against a one-button frame and ask for a resize on
        -- every single pass.
        footprintChanged = math_abs(currentWidth - math_max(sectionLayout.footprintWidth, 1)) > 0.5
            or math_abs(currentHeight - math_max(sectionLayout.footprintHeight, 1)) > 0.5
    end
    if frame.visibleButtonCount ~= visibleCount or footprintChanged then
        frame.visibleButtonCount = visibleCount
        self:ResizeGroupFrame(groupId)
    end

    frame._layoutDirty = false
end

function CooldownCompanion:RefreshGroupFrame(groupId)
    -- Layout-only controls route here without UpdateGroupStyle; the config
    -- mirror renders saved settings, so notify it before the combat
    -- deferral can return early. The helper self-gates on the wide view.
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(groupId)
    end

    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    -- Defer during combat when the frame is protected or would need creation.
    -- Unprotected frames can safely refresh during combat.
    if InCombatLockdown() and (not frame or frame:IsProtected()) then
        self._pendingFullRefresh = true
        return
    end

    if not group then
        self:UnloadGroup(groupId)
        self:DiscardDormantFrame(groupId)
        return
    end
    
    -- Recover dormant frame shell if available (buttons will be repopulated below)
    if not frame and self._dormantFrames and self._dormantFrames[groupId] then
        frame = self._dormantFrames[groupId]
        self._dormantFrames[groupId] = nil
        self.groupFrames[groupId] = frame
    end

    if not frame then
        frame = self:CreateGroupFrame(groupId)
    else
        -- Apply per-group frame strata before populating buttons.
        -- Deferred during combat — protected frame restriction.
        if InCombatLockdown() and frame:IsProtected() then
            frame._strataDirty = true
        else
            local strata = group.frameStrata
            if strata then
                frame:SetFrameStrata(strata)
                frame:SetFixedFrameStrata(true)
            else
                frame:SetFrameStrata("MEDIUM")
                frame:SetFixedFrameStrata(false)
            end
            frame._strataDirty = nil
        end

        self:AnchorGroupFrame(frame, group.anchor)

        -- Keep runtime Masque state aligned with saved group settings. This
        -- also resolves style-copy changes that were deferred during combat.
        if self.Masque then
            -- Aura Panels never reach the skinning call: they materialize no
            -- buttons, so a Masque group for one could only ever sit empty.
            if (group.displayMode == nil or group.displayMode == "icons")
                and group.masqueEnabled
                and not ST.IsAuraPanelGroup(group) then
                if not self.MasqueGroups[groupId] then
                    self:CreateMasqueGroup(groupId)
                end
            elseif self.MasqueGroups[groupId] then
                ForEachGroupButtonFrame(frame, function(button)
                    self:RemoveButtonFromMasque(groupId, button)
                end)
                self:DeleteMasqueGroup(groupId)
            end
        end

        frame._containerUnlockPreviewActive = group.parentContainerId
            and self:IsContainerUnlockPreviewActive(group.parentContainerId)
            and not self:IsArrangePanelSuppressed(groupId)
            and not self:IsArrangeContainerSuppressed(group.parentContainerId)
            or nil
        frame._panelUnlockPreviewActive = self:IsPanelUnlockPreviewActive(group) or nil
        self:PopulateGroupButtons(groupId)
    end

    -- Resolve locked/alpha from container
    local isLocked, baseAlpha = GetContainerState(groupId)
    if self:IsArrangePanelSuppressed(groupId)
        or (group.parentContainerId and self:IsArrangeContainerSuppressed(group.parentContainerId)) then
        isLocked = true
    end

    -- Update drag handle text and lock state. An empty Aura Panel is exempt for
    -- the same reason the Rotation Assistant is: its one reserved cell is what
    -- the owner arranges before adding auras.
    local hasButtons = self:IsRotationAssistantGroup(group)
        or ST.IsAuraPanelGroup(group)
        or #group.buttons > 0
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    local isCursorAnchored = IsCursorAnchor(group.anchor)
    local isCursorLayoutPreviewSelected = isCursorAnchored
        and IsCursorAnchorLayoutPreviewSelected(self, groupId)
        or false
    local containerPreviewActive = frame._containerUnlockPreviewActive == true
    local panelPreviewActive = frame._panelUnlockPreviewActive == true
    local independentPanelMoverShown = not panelPreviewActive
        or self._arrangeSoloContainerId == nil
        or self._arrangeSelectedPanelId == groupId
    local selectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)
    local isActive = ShouldShowGroupFrameForRuntime(self, groupId, group)
    if (containerPreviewActive or panelPreviewActive) and isActive then
        local normallyActive = self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
            ignoreUnlockPreview = true,
        })
        frame._unlockGhost = not normallyActive or nil
    else
        frame._unlockGhost = nil
    end
    if frame.dragHandle and frame.dragHandle.text then
        frame.dragHandle.text:SetText(group.name)
    end
    self:SetGroupDragControlsShown(
        frame,
        hasButtons
            and not isTextureMode
            and (
                isCursorLayoutPreviewSelected
                or (
                    not isCursorAnchored
                    and ((containerPreviewActive and selectedInContainer)
                        or (not containerPreviewActive and not isLocked and independentPanelMoverShown))
                )
            )
    )
    self:UpdateGroupClickthrough(groupId)

    -- Update visibility from runtime state. Arrange/unlock and the explicit
    -- cursor positioning preview are handled by the active-state checks above.
    if isActive then
        if InCombatLockdown() and frame:IsProtected() then
            if not frame:IsShown() then
                self._pendingVisibilityRefresh = true
            end
        else
            frame:Show()
        end
        -- Keep unlocked panels fully visible, except unlock ghosts.
        if IsCursorAnchorLayoutPreviewGroupActive(self, groupId) or containerPreviewActive or not isLocked then
            frame:SetAlpha(GetUnlockedPanelAlpha(frame))
        -- Apply current alpha from the alpha fade system so frame doesn't flash at 1.0
        else
            ApplyCurrentAlphaIfPresent(CooldownCompanion, frame, groupId, group)
        end
    else
        self:UnloadGroup(groupId)
    end

    if isActive
        and CooldownCompanion:IsStandaloneTexturePanelGroup(group)
        and self.UpdateAuraTextureVisual
        and frame
        and frame.buttons
        and frame.buttons[1] then
        self:UpdateAuraTextureVisual(frame.buttons[1])
    end

    -- An Aura Panel's entries live in the panel's own aura container, which the
    -- aura pass owns end to end. The frame's size, anchor and visibility have
    -- all settled by here, so ask for the (coalesced, OOC-deferred) rebind last.
    -- It runs on the deactivating path too, so the container can let go of a
    -- panel that just unloaded.
    -- A mixed panel carrying an aura SECTION owes the same request for the same
    -- reason: that cluster's entries live in a container of their own, mounted on
    -- a host frame whose rectangle the layout pass above has just moved.
    -- The marker covers the refresh that took the last aura section AWAY -- the
    -- flag switched off, the cluster flattened, its final member deleted. By the
    -- time the question is asked here the panel no longer admits it owed
    -- anything, and its records would sit bound (invisible, the host is hidden,
    -- but wrong) until an unrelated rebind released them.
    if ST.IsAuraPanelGroup(group) or ST.PanelHasAuraSection(group)
        or frame._auraSectionRebindOwed then
        self:RequestAuraRebind("aura-panel", groupId)
    end
    if not ST.PanelHasAuraSection(group) then
        frame._auraSectionRebindOwed = nil
    end

    if group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

function CooldownCompanion:WouldCreateCircularAnchor(sourceId, targetId, targetKind, sourceKind)
    local groups = self.db.profile.groups
    if not groups then return false end
    local containers = self.db.profile.groupContainers or {}
    local visited = {}
    -- Track both the kind and id to avoid conflating group/container ID spaces
    sourceKind = sourceKind or "group"
    local currentKind = targetKind or "group"
    local currentId = targetId
    while currentId do
        if currentKind == sourceKind and currentId == sourceId then return true end
        local visitKey = currentKind .. ":" .. currentId
        if visited[visitKey] then return false end
        visited[visitKey] = true
        -- Look up anchor chain in the appropriate table
        local relTo
        if currentKind == "group" then
            local g = groups[currentId]
            if g and g.anchor and g.anchor.relativeTo then
                relTo = g.anchor.relativeTo
            end
        else
            local c = containers[currentId]
            if c and c.anchor and c.anchor.relativeTo then
                relTo = c.anchor.relativeTo
            end
        end
        if not relTo then break end
        -- Determine next node in the chain
        local nextGroupId = relTo:match("^CooldownCompanionGroup(%d+)$")
        if nextGroupId then
            currentKind = "group"
            currentId = tonumber(nextGroupId)
        else
            local nextContainerId = relTo:match("^CooldownCompanionContainer(%d+)$")
            if nextContainerId then
                currentKind = "container"
                currentId = tonumber(nextContainerId)
            else
                break  -- anchored to a non-addon frame, chain ends
            end
        end
    end
    return false
end

--- Re-point everything anchored to this panel after its sectioned state flipped.
--- The anchoring body changed frames, and an anchor to the outgoing one would
--- keep resolving positionally -- a hidden base anchor still reports its last
--- rectangle -- so a dependent left pointing at it would sit at a stale spot
--- rather than visibly break. Both directions run the same pass; AnchorGroupFrame
--- and AnchorContainerFrame each re-resolve the body and each carry their own
--- combat deferral, so a protected dependent simply comes back dirty.
--- Unit frames are not touched here: FrameAnchoring owns their protected-frame
--- discipline and re-applies off its own RefreshGroupFrame hook.
function CooldownCompanion:ReanchorPanelSectionDependents(groupId)
    local profile = self.db and self.db.profile
    if not profile then return end

    local targetFrameName = "CooldownCompanionGroup" .. tostring(groupId)
    for dependentId, dependentGroup in pairs(profile.groups or {}) do
        if dependentId ~= groupId
            and dependentGroup
            and dependentGroup.anchor
            and dependentGroup.anchor.relativeTo == targetFrameName then
            local dependentFrame = self.groupFrames and self.groupFrames[dependentId]
            if dependentFrame then
                self:AnchorGroupFrame(dependentFrame, dependentGroup.anchor)
            end
        end
    end

    for containerId, container in pairs(profile.groupContainers or {}) do
        if container
            and container.anchor
            and container.anchor.relativeTo == targetFrameName then
            local containerFrame = self.containerFrames and self.containerFrames[containerId]
            if containerFrame then
                self:AnchorContainerFrame(containerFrame, container.anchor)
            end
        end
    end

    -- Texture and Trigger panels place a HOST frame, not the panel frame, and
    -- keep their anchor in their own display settings rather than group.anchor,
    -- so neither pass above sees them. Their one re-anchor path is the display
    -- refresh.
    if self.ReanchorStandaloneDisplayDependents then
        self:ReanchorStandaloneDisplayDependents(targetFrameName)
    end
end

function CooldownCompanion:GetDirectAnchorDependents(groupId, panelOnly)
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then return {} end

    local targetFrameName = "CooldownCompanionGroup" .. tostring(groupId)
    local dependents = {}
    for dependentId, dependentGroup in pairs(groups) do
        if dependentId ~= groupId
            and dependentGroup
            and dependentGroup.anchor
            and dependentGroup.anchor.relativeTo == targetFrameName
            and (not panelOnly or dependentGroup.parentContainerId) then
            dependents[#dependents + 1] = {
                name = dependentGroup.name or ((dependentGroup.parentContainerId and "Panel " or "Group ") .. dependentId),
            }
        end
    end

    if not panelOnly then
        for containerId, container in pairs(profile.groupContainers or {}) do
            if container
                and container.anchor
                and container.anchor.relativeTo == targetFrameName then
                dependents[#dependents + 1] = {
                    name = container.name or ("Group " .. containerId),
                }
            end
        end
    end

    return dependents
end

local function FormatDependentAnchorNames(dependents)
    local names = {}
    for _, dependent in ipairs(dependents or {}) do
        names[#names + 1] = dependent.name
        if #names >= 3 then
            break
        end
    end

    local text = table.concat(names, ", ")
    if dependents and #dependents > #names then
        text = text .. ", +" .. tostring(#dependents - #names) .. " more"
    end
    return text
end

local function RefreshGroupAnchorInteractionState(self, groupId, frame, group)
    if frame and group and frame.buttons then
        local groupStyle = group.style or {}
        for _, button in ipairs(frame.buttons) do
            if button.UpdateStyle then
                local effectiveStyle = self:GetEffectiveStyle(groupStyle, button.buttonData)
                button:UpdateStyle(effectiveStyle)
            end
        end
    end
    if self.UpdateGroupClickthrough then
        self:UpdateGroupClickthrough(groupId)
    end
end

local function FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
    self:AnchorGroupFrame(frame, group.anchor)
    self:RebuildPanelAlphaDependencyTargets()
    RefreshGroupAnchorInteractionState(self, groupId, frame, group)
    self:RefreshCursorAnchorTicker()
    if (wasCursorAnchored or IsCursorAnchor(group.anchor)) and self.EvaluateBarsAndFramesRuntime then
        self:EvaluateBarsAndFramesRuntime("cursor-anchor-changed")
    end
end

-- Shared with Core/GroupManagement.lua so a Panel Template's Group-relative
-- offset finishes with the exact sequence a container re-anchor runs here.
ST._FinishGroupAnchorChange = FinishGroupAnchorChange

function CooldownCompanion:SetGroupAnchor(groupId, targetFrameName, forceCenter)
    local group = self.db.profile.groups[groupId]
    local frame = self.groupFrames[groupId]

    if not group or not frame then return false end
    local wasCursorAnchored = IsCursorAnchor(group.anchor)

    -- Block self-anchoring
    local selfFrameName = "CooldownCompanionGroup" .. groupId
    if targetFrameName == selfFrameName then
        self:Print("Cannot anchor a group to itself.")
        return false
    end

    if targetFrameName == CURSOR_ANCHOR_TARGET then
        if not self:CanGroupUseCursorAnchor(group) then
            self:Print("Only panels can anchor to the cursor.")
            return false
        end

        local dependents = self:GetDirectAnchorDependents(groupId)
        if self.GetExternalAnchorDependents then
            for _, dependent in ipairs(self:GetExternalAnchorDependents(groupId)) do
                dependents[#dependents + 1] = dependent
            end
        end
        if #dependents > 0 then
            self:Print("Cannot anchor to Cursor while other panels, groups, bars, or frames anchor to this panel: " .. FormatDependentAnchorNames(dependents) .. ".")
            return false
        end

        group.anchor = BuildDefaultCursorAnchor()
        group.locked = nil
        FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
        self:SetGroupDragControlsShown(frame, false)
        return true
    end

    local validationOptions = self.GetGroupAnchorValidationOptions
        and self:GetGroupAnchorValidationOptions(groupId)
        or {
            domain = "panel",
            sourceGroupId = groupId,
            sourceKind = "group",
        }
    local targetOk = self:ValidateAddonFrameAnchorTarget(targetFrameName, validationOptions)
    if not targetOk then
        self:Print(self:GetInvalidAnchorTargetReason(targetFrameName, validationOptions))
        return false
    end

    -- Panels: redirect UIParent to their container frame
    local containerFrameName = GetPanelContainerFrameName(groupId)
    if containerFrameName and targetFrameName == "UIParent" then
        targetFrameName = containerFrameName
        forceCenter = true
    end

    -- Handle UIParent (free positioning)
    if targetFrameName == "UIParent" then
        if forceCenter then
            -- Explicitly un-anchoring - center the frame
            group.anchor = {
                point = "CENTER",
                relativeTo = "UIParent",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
            }
        end
        -- If not forceCenter, keep current anchor settings (just relativeTo changes)
        group.anchor.relativeTo = "UIParent"
        self:AnchorGroupFrame(frame, group.anchor, forceCenter)
        self:RebuildPanelAlphaDependencyTargets()
        RefreshGroupAnchorInteractionState(self, groupId, frame, group)
        self:RefreshCursorAnchorTicker()
        if wasCursorAnchored and self.EvaluateBarsAndFramesRuntime then
            self:EvaluateBarsAndFramesRuntime("cursor-anchor-changed")
        end
        return true
    end

    local targetFrame = _G[targetFrameName]
    if not targetFrame then
        self:Print("Frame '" .. targetFrameName .. "' not found.")
        return false
    end

    local targetKind = ParseAddonAnchorFrameName(targetFrameName)
    if not targetKind and WouldFrameDependencyCreateCircularAnchor(self, groupId, "group", targetFrame) then
        self:Print("Cannot anchor: target frame depends on a Cooldown Companion frame.")
        return false
    end

    -- Panel anchored to its own container: reset to default position
    if containerFrameName and targetFrameName == containerFrameName then
        group.anchor = {
            point = "CENTER",
            relativeTo = containerFrameName,
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        }
        FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
        return true
    end

    group.anchor = {
        point = "TOPLEFT",
        relativeTo = targetFrameName,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -5,
    }

    FinishGroupAnchorChange(self, groupId, frame, group, wasCursorAnchored)
    return true
end

function CooldownCompanion:UpdateGroupStyle(groupId)
    -- The config's pinned mirror renders from saved settings, so it rides
    -- every style update — before the frame guard, because the mirror must
    -- refresh even when the group has no materialized live frame. No-op
    -- unless the config's wide view is showing this panel.
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(groupId)
    end

    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    if InCombatLockdown() and frame:IsProtected() then
        self._pendingFullRefresh = true
        return
    end
    ST.UpdateGroupSizeLabel(frame)

    local entries, buttonUsabilityOptions = GetStyleUpdateEntries(self, groupId, frame, group)
    if not entries then
        self:PopulateGroupButtons(groupId)
        UpdateResizedPanelContainerWrapper(groupId)
        return
    end

    local style = group.style or {}
    local isTextMode = group.displayMode == "text"
    local headerHeight = ApplyTextGroupHeader(self, frame, group, style, isTextMode)

    for visibleIndex = 1, entries.count do
        local entry = entries[visibleIndex]
        local button = frame.buttons[visibleIndex]
        if button.UpdateStyle then
            button:UpdateStyle(entry.style)
        end
        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
            button:SetAlpha(0)
            button._lastVisAlpha = 0
        end
    end

    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    FinishGroupButtonRefresh(self, groupId, frame, group)

    -- The frame has its final size now, so the container unlock preview's
    -- border can re-fit on the same tick — config size sliders restyle
    -- through here, and the border must track them as tightly as it tracks
    -- the mover grip.
    UpdateResizedPanelContainerWrapper(groupId)

    -- Style-only fast path skips PopulateGroupButtons, but the aura slot kit
    -- consumes style keys at bind time — re-request the (coalesced) rebind so
    -- the composed aura visuals track style edits too. The groupId scopes the
    -- in-combat defer note to edits that actually touch an aura display.
    self:RequestAuraRebind("style", groupId)
end

function CooldownCompanion:UpdateGroupClickthrough(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local isLocked = GetContainerState(groupId)
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    local isCursorAnchored = IsCursorAnchor(group.anchor)
    if self:IsArrangePanelSuppressed(groupId)
        or (group.parentContainerId and self:IsArrangeContainerSuppressed(group.parentContainerId)) then
        isLocked = true
    end
    local isCursorLayoutPreviewSelected = isCursorAnchored
        and IsCursorAnchorLayoutPreviewSelected(self, groupId)
        or false
    local containerPreviewActive = group.parentContainerId
        and self:IsContainerUnlockPreviewActive(group.parentContainerId)
        and not self:IsArrangePanelSuppressed(groupId)
        and not self:IsArrangeContainerSuppressed(group.parentContainerId)
        or false
    local independentPanelSoloHidden = not containerPreviewActive
        and group.locked == false
        and self._arrangeSoloContainerId ~= nil
        and self._arrangeSelectedPanelId ~= groupId
        or false
    if independentPanelSoloHidden then
        isLocked = true
    end
    local isSelectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)
    -- Exempt with the Rotation Assistant: an empty Aura Panel still lays out one
    -- reserved cell, so the wheel has a real cell to scale.
    local hasResizeEntry = self:IsRotationAssistantGroup(group)
        or ST.IsAuraPanelGroup(group)
        or #group.buttons > 0
    local resizeWheelEnabled = hasResizeEntry
        and not independentPanelSoloHidden
        and (isCursorLayoutPreviewSelected or not containerPreviewActive or isSelectedInContainer)
        and CanUsePanelResizeInteractions(groupId, group)

    SyncGroupControlLevels(
        frame,
        (isCursorLayoutPreviewSelected or (isSelectedInContainer and not isCursorAnchored)) and not isTextureMode
    )
    if resizeWheelEnabled then
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", OnUnlockedPanelMouseWheel)
    else
        frame:EnableMouseWheel(false)
        frame:SetScript("OnMouseWheel", nil)
    end

    if isCursorLayoutPreviewSelected and not isTextureMode then
        SetFrameClickThrough(frame, false, false)
        frame:RegisterForDrag("LeftButton")
        -- Clickthrough transitions wipe OnMouseUp; restore the selection
        -- handler alongside the drag registration.
        frame:SetScript("OnMouseUp", frame._arrangeSelectOnMouseUp)
        if frame.dragHandle then
            SetFrameClickThrough(frame.dragHandle, false, false)
            frame.dragHandle:EnableMouse(true)
            frame.dragHandle:RegisterForDrag("LeftButton")
            frame.dragHandle:SetScript("OnMouseUp", nil)
        end
        if frame.nudger then
            SetFrameClickThrough(frame.nudger, false, false)
            frame.nudger:EnableMouse(true)
        end
        return
    end

    -- A parked-but-unselected cursor panel stays clickable in arrange so a
    -- click or drag can select it; its chrome stays down until then.
    if isCursorAnchored
        and not isTextureMode
        and self._arrangeModeActive
        and IsCursorAnchorLayoutPreviewGroupActive(self, groupId) then
        SetFrameClickThrough(frame, false, false)
        frame:RegisterForDrag("LeftButton")
        -- Clickthrough transitions wipe OnMouseUp; restore the selection
        -- handler alongside the drag registration.
        frame:SetScript("OnMouseUp", frame._arrangeSelectOnMouseUp)
        if frame.dragHandle then
            SetFrameClickThrough(frame.dragHandle, true, true)
        end
        if frame.nudger then
            SetFrameClickThrough(frame.nudger, true, true)
        end
        return
    end

    if containerPreviewActive then
        if resizeWheelEnabled then
            SetFrameClickThrough(frame, true, false)
        else
            SetFrameClickThrough(frame, true, true)
        end
        if frame.dragHandle then
            if isSelectedInContainer and not isTextureMode and not isCursorAnchored then
                SetFrameClickThrough(frame.dragHandle, false, false)
                frame.dragHandle:EnableMouse(true)
                frame.dragHandle:RegisterForDrag("LeftButton")
                frame.dragHandle:SetScript("OnMouseUp", nil)
            else
                SetFrameClickThrough(frame.dragHandle, true, true)
            end
        end
        if frame.nudger then
            if isSelectedInContainer and not isTextureMode and not isCursorAnchored then
                SetFrameClickThrough(frame.nudger, false, false)
                frame.nudger:EnableMouse(true)
            else
                SetFrameClickThrough(frame.nudger, true, true)
            end
        end
        return
    end

    -- When locked: group container is always fully non-interactive
    -- Texture panels also keep the backing group frame non-interactive while
    -- unlocked, because dragging and hovering are handled by the separate
    -- visible texture host instead of the hidden 1x1 anchor frame.
    if isLocked or isTextureMode or isCursorAnchored then
        SetFrameClickThrough(frame, true, true)
        if frame.dragHandle then
            SetFrameClickThrough(frame.dragHandle, true, true)
        end
        if frame.nudger then
            SetFrameClickThrough(frame.nudger, true, true)
        end
    else
        SetFrameClickThrough(frame, false, false)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnMouseUp", frame._arrangeSelectOnMouseUp)
        if frame.dragHandle then
            SetFrameClickThrough(frame.dragHandle, false, false)
            frame.dragHandle:EnableMouse(true)
            frame.dragHandle:RegisterForDrag("LeftButton")
            frame.dragHandle:SetScript("OnMouseUp", nil)
        end
        if frame.nudger then
            SetFrameClickThrough(frame.nudger, false, false)
            frame.nudger:EnableMouse(true)
        end
    end
end

------------------------------------------------------------------------
-- Container Frames (invisible anchor frames for the Group → Panel hierarchy)
------------------------------------------------------------------------

local CONTAINER_WRAPPER_PADDING = 10
local CONTAINER_WRAPPER_LABEL_OFFSET = 2
local CONTAINER_WRAPPER_HEADER_HEIGHT = 27
local CONTAINER_WRAPPER_HEADER_FONT_SIZE = 14
local CONTAINER_WRAPPER_HEADER_GAP = 4
local CONTAINER_PANEL_LABEL_HEIGHT = 15
local CONTAINER_PANEL_LABEL_MIN_WIDTH = 70
local CONTAINER_MEMBER_COORD_REFRESH_INTERVAL = 0.05
local CONTAINER_WRAPPER_FALLBACK_WIDTH = 120
local CONTAINER_WRAPPER_FALLBACK_HEIGHT = 18
local CONTAINER_MOVER_COLORS = {
    memberR = 0.6,
    memberG = 0.8,
    memberB = 1,
    memberHoverAlpha = 0.10,
    memberSelectedAlpha = 0.18,
    wrapperBorderAlpha = 0.7,
}

local function GetRelativeFrameRectValues(referenceFrame, targetFrame)
    if not (referenceFrame and targetFrame and referenceFrame.GetCenter and targetFrame.GetCenter) then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end

    local refX, refY = referenceFrame:GetCenter()
    local targetX, targetY = targetFrame:GetCenter()
    local width, height = GetFrameSizeInUIParentSpace(targetFrame)
    if not (refX and refY and targetX and targetY and width and height) then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end

    return targetX - (width / 2) - refX,
        targetX + (width / 2) - refX,
        targetY - (height / 2) - refY,
        targetY + (height / 2) - refY,
        targetX - refX,
        targetY - refY,
        width,
        height
end

local function GetRelativeFrameRect(referenceFrame, targetFrame)
    local left, right, bottom, top, centerX, centerY, width, height = GetRelativeFrameRectValues(referenceFrame, targetFrame)
    if not left then
        return nil
    end

    return {
        left = left,
        right = right,
        bottom = bottom,
        top = top,
        centerX = centerX,
        centerY = centerY,
        width = width,
        height = height,
    }
end

local function EnsureContainerPanelLabel(frame, index)
    frame._containerPanelLabels = frame._containerPanelLabels or {}
    local labelFrame = frame._containerPanelLabels[index]
    if labelFrame then
        return labelFrame
    end

    labelFrame = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    labelFrame:SetHeight(CONTAINER_PANEL_LABEL_HEIGHT)
    labelFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    labelFrame:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
    labelFrame:EnableMouse(false)
    CreatePixelBorders(labelFrame, 0, 0, 0, 1)

    labelFrame.text = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFrame.text:SetPoint("CENTER")
    labelFrame.text:SetTextColor(1, 1, 1, 1)

    frame._containerPanelLabels[index] = labelFrame
    return labelFrame
end

local function HideContainerPanelLabels(frame)
    if not frame or not frame._containerPanelLabels then
        return
    end

    for _, labelFrame in pairs(frame._containerPanelLabels) do
        labelFrame:Hide()
    end
end

local function EnsureContainerMemberOverlay(frame, index)
    frame._containerMemberOverlays = frame._containerMemberOverlays or {}
    local overlay = frame._containerMemberOverlays[index]
    if overlay then
        return overlay
    end

    overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    overlay:SetBackdropColor(CONTAINER_MOVER_COLORS.memberR, CONTAINER_MOVER_COLORS.memberG, CONTAINER_MOVER_COLORS.memberB, 0)
    overlay:RegisterForDrag("LeftButton")
    overlay:EnableMouse(true)

    overlay:SetScript("OnEnter", function(self)
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[self.containerId]
        if not (self.containerId and self.groupId and containerFrame) then
            return
        end
        CooldownCompanion:BeginContainerChromeHoverWatch(self.containerId)
        if containerFrame._containerHoveredGroupId ~= self.groupId then
            containerFrame._containerHoveredGroupId = self.groupId
            CooldownCompanion:RefreshContainerWrapper(self.containerId)
            if CooldownCompanion.RefreshArrangePillList then
                CooldownCompanion:RefreshArrangePillList()
            end
        end
    end)

    overlay:SetScript("OnLeave", function(self)
        if self._dragging then
            return
        end
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[self.containerId]
        if not containerFrame then
            return
        end
        if containerFrame._containerHoveredGroupId == self.groupId then
            containerFrame._containerHoveredGroupId = nil
            CooldownCompanion:RefreshContainerWrapper(self.containerId)
            if CooldownCompanion.RefreshArrangePillList then
                CooldownCompanion:RefreshArrangePillList()
            end
        end
    end)

    overlay:SetScript("OnDragStart", function(self)
        self._suppressClick = true
        self._dragging = CooldownCompanion:StartContainerPreviewMemberDrag(self.containerId, self.groupId) or nil
    end)

    overlay:SetScript("OnDragStop", function(self)
        if self._dragging then
            CooldownCompanion:StopContainerPreviewMemberDrag(self.containerId, self.groupId)
        end
        self._dragging = nil
    end)

    overlay:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        if self._suppressClick then
            self._suppressClick = nil
            return
        end
        CooldownCompanion:ActivateArrangePanel(self.containerId, self.groupId, true)
    end)

    frame._containerMemberOverlays[index] = overlay
    return overlay
end

local function HideContainerMemberOverlays(frame)
    if not frame or not frame._containerMemberOverlays then
        return
    end

    for _, overlay in pairs(frame._containerMemberOverlays) do
        overlay._dragging = nil
        overlay._suppressClick = nil
        overlay.groupId = nil
        for _, texture in ipairs(overlay._containerWrapperBorderTextures or {}) do
            texture:Hide()
        end
        overlay:Hide()
    end
end

local function EnsureContainerWrapperBorder(wrapper, r, g, b, a)
    if not wrapper then
        return
    end

    local borderTextures = wrapper._containerWrapperBorderTextures
    if not borderTextures then
        borderTextures = ST.CreateBorderTextureSet(wrapper, "BORDER")
        wrapper._containerWrapperBorderTextures = borderTextures
    end

    ST.ApplyBorderTextures(borderTextures, wrapper, { r, g, b, a }, 1, ST.BORDER_RENDER_MODE_CRISP)
end

local function HideContainerWrapperBorder(wrapper)
    if not (wrapper and wrapper._containerWrapperBorderTextures) then
        return
    end
    for _, texture in ipairs(wrapper._containerWrapperBorderTextures) do
        texture:Hide()
    end
end

function CooldownCompanion:GetContainerSelectedGroupId(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    return frame and frame._containerSelectedGroupId or nil
end

function CooldownCompanion:IsContainerPanelSelected(containerId, groupId)
    return groupId ~= nil and self:GetContainerSelectedGroupId(containerId) == groupId
end

function CooldownCompanion:IsContainerPanelHovered(containerId, groupId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    return groupId ~= nil and frame and frame._containerHoveredGroupId == groupId or false
end

function CooldownCompanion:StartContainerMemberPreviewTracking(containerId, groupId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    local tracker = frame._containerMemberDragTracker
    if not tracker then
        tracker = CreateFrame("Frame", nil, frame)
        frame._containerMemberDragTracker = tracker
    end

    frame._containerDraggingGroupId = groupId
    local groupFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if groupFrame then
        PrepareGroupCoordinateDragReference(groupFrame)
    end
    tracker._elapsed = 0
    tracker:SetScript("OnUpdate", function(self, elapsed)
        CooldownCompanion:UpdateContainerWrapperUnion(containerId)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < CONTAINER_MEMBER_COORD_REFRESH_INTERVAL then
            return
        end

        self._elapsed = 0
        local groupFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
        if groupFrame and groupFrame._dragInProgress then
            UpdateGroupDragCoordinate(groupFrame)
        end
    end)
end

function CooldownCompanion:StopContainerMemberPreviewTracking(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    local groupId = frame._containerDraggingGroupId
    frame._containerDraggingGroupId = nil
    local groupFrame = groupId and CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if groupFrame then
        CooldownCompanion:EndDragSnapSession(groupFrame, false)
        groupFrame._coordDragRelativeTo = nil
        groupFrame._coordDragRelativeFrame = nil
        groupFrame._coordDragAnchorState = nil
        groupFrame._coordDragReferenceReady = nil
    end
    local textureHost = groupFrame and self.GetAuraTextureHostForGroupFrame
        and self:GetAuraTextureHostForGroupFrame(groupFrame)
        or nil
    if textureHost then
        self:EndDragSnapSession(textureHost, false)
    end
    local tracker = frame._containerMemberDragTracker
    if tracker then
        tracker._elapsed = 0
        tracker:SetScript("OnUpdate", nil)
    end
    if groupFrame then
        self:EndMoverChromeFade(groupFrame)
    end
    if textureHost then
        self:EndMoverChromeFade(textureHost)
    end
end

function CooldownCompanion:ClearContainerUnlockState(containerId)
    self:EndMoverChromeFadeIfOwnedByContainer(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    local selectedGroupId = frame._containerSelectedGroupId
    local hoveredGroupId = frame._containerHoveredGroupId
    frame._containerSelectedGroupId = nil
    frame._containerHoveredGroupId = nil
    if selectedGroupId and self._arrangeSelectedPanelId == selectedGroupId then
        self._arrangeSelectedPanelId = nil
    end
    local cursorPreview = self._cursorAnchorLayoutPreview
    local cursorSelectedGroupId = cursorPreview and cursorPreview.selectedGroupId
    local cursorSelectedGroup = cursorSelectedGroupId
        and self.db.profile.groups[cursorSelectedGroupId]
        or nil
    if cursorSelectedGroup and cursorSelectedGroup.parentContainerId == containerId then
        if self._arrangeSelectedPanelId == cursorSelectedGroupId then
            self._arrangeSelectedPanelId = nil
        end
        self:SelectArrangeCursorPanel(cursorSelectedGroupId, true)
    end
    self:StopContainerMemberPreviewTracking(containerId)
    HideContainerMemberOverlays(frame)

    -- Only the selected panel can have container-owned drag controls showing,
    -- while a hovered standalone panel can own an outline. Clear that chrome
    -- directly instead of rebuilding every runtime panel in the container.
    local group = selectedGroupId and self.db.profile.groups[selectedGroupId] or nil
    local groupFrame = selectedGroupId and self.groupFrames and self.groupFrames[selectedGroupId] or nil
    local isStandaloneDisplay = group and self:IsStandaloneTexturePanelGroup(group)
    if groupFrame and not isStandaloneDisplay then
        if not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group)) then
            SyncGroupControlLevels(groupFrame, false)
            self:SetGroupDragControlsShown(groupFrame, false)
        end
        self:UpdateGroupClickthrough(selectedGroupId)
    elseif isStandaloneDisplay and self.UpdateGroupedStandalonePreviewSelection then
        self:UpdateGroupedStandalonePreviewSelection(selectedGroupId)
    end

    if hoveredGroupId ~= selectedGroupId and self.UpdateGroupedStandalonePreviewSelection then
        local hoveredGroup = hoveredGroupId and self.db.profile.groups[hoveredGroupId] or nil
        if hoveredGroup and self:IsStandaloneTexturePanelGroup(hoveredGroup) then
            self:UpdateGroupedStandalonePreviewSelection(hoveredGroupId)
        end
    end
end

-- Unlock-toolbar chrome reveal: while several movers are available at once, a
-- container rests as outline + header only; its nudger and coordinate label
-- show while the container is hovered or focused. An individually unlocked
-- container keeps full chrome until the user makes a toolbar selection.
-- The session-only per-container filter can tuck a
-- container's whole mover away mid-arrange (wrapper, header, overlays, hover
-- reveal) while its real displays stay on screen. Never touches
-- container.locked; wiped on entering and leaving arrange mode.
function CooldownCompanion:IsContainerArrangeChromeHidden(containerId)
    if not self:IsUnlockToolbarActive() then
        return false
    end
    local hiddenSet = self._arrangeChromeHidden
    if hiddenSet ~= nil and hiddenSet[containerId] == true then
        return true
    end
    -- Solo layer: while one group is soloed from the pill list, every other
    -- group's chrome hides without touching the manual checkbox flags.
    local solo = self._arrangeSoloContainerId
    return solo ~= nil and solo ~= containerId
end

-- Solo one container's chrome from the pill list (nil releases the solo and
-- restores whatever the manual flags say). The solo target becomes the
-- focused container so its controls pin open.
function CooldownCompanion:SetArrangeSoloContainer(containerId)
    if not self:IsUnlockToolbarActive() then
        return
    end
    if self._arrangeSoloContainerId == containerId then
        return
    end
    self._arrangeSoloContainerId = containerId
    if containerId then
        self._arrangeFocusContainerId = containerId
    end

    -- Effective hidden state changed for every arranged container: refresh
    -- their mover presentation without rebuilding the runtime panels.
    for cid, container in pairs(self.db.profile.groupContainers or {}) do
        if container.locked == false then
            self:UpdateContainerDragHandle(cid, self:IsContainerArrangeChromeHidden(cid))
        end
    end
    self:RefreshAllIndependentPanelMoverChrome()
    -- The solo also decides the independent bar movers' effective hidden state.
    self:RefreshArrangeSpecialMoverChrome("cast")
    self:RefreshArrangeSpecialMoverChrome("resource")
    if self.RefreshArrangePillList then
        self:RefreshArrangePillList()
    end
end

function CooldownCompanion:SetContainerArrangeChromeHidden(containerId, hidden)
    if not self:IsUnlockToolbarActive() then
        return
    end
    -- "cast"/"resource" ride the same map and solo slot as container ids.
    local isSpecialMover = self:IsArrangeSpecialMoverId(containerId)
    local container = not isSpecialMover and self.db.profile.groupContainers[containerId] or nil
    if not isSpecialMover and not container then
        return
    end

    hidden = hidden and true or nil
    self._arrangeChromeHidden = self._arrangeChromeHidden or {}
    if self._arrangeChromeHidden[containerId] == hidden then
        return
    end
    -- Manually hiding the soloed group would leave every group hidden with no
    -- visible way back; release the solo (restoring the others) first.
    if hidden and self._arrangeSoloContainerId == containerId then
        self:SetArrangeSoloContainer(nil)
    end
    self._arrangeChromeHidden[containerId] = hidden
    if hidden and self._arrangeFocusContainerId == containerId then
        self._arrangeFocusContainerId = nil
    end

    -- Mirror the lock presentation without writing the profile: hiding takes
    -- the suppressed-chrome path, showing rebuilds the unlock preview.
    if isSpecialMover then
        self:RefreshArrangeSpecialMoverChrome(containerId)
    else
        self:UpdateContainerDragHandle(containerId, hidden ~= nil or container.locked ~= false)
    end
end

function CooldownCompanion:IsContainerArrangeChromeRevealed(containerId, frame)
    if not self:IsUnlockToolbarActive() then
        return true
    end
    if not self._arrangeModeActive
        and self._arrangeFocusContainerId == nil
        and self._arrangeSoloContainerId == nil then
        return true
    end
    frame = frame or (self.containerFrames and self.containerFrames[containerId])
    return self._arrangeFocusContainerId == containerId
        or (frame ~= nil and frame._arrangeChromeHover == true)
end

function CooldownCompanion:FocusArrangeContainer(containerId)
    if not self:IsUnlockToolbarActive() then
        return
    end
    local previous = self._arrangeFocusContainerId
    if previous == containerId then
        return
    end
    self._arrangeFocusContainerId = containerId
    if containerId ~= nil then
        self._arrangeTreeRevealEntry = {
            kind = self:IsArrangeSpecialMoverId(containerId) and "special" or "root",
            id = containerId,
        }
    end
    if previous then
        self:RefreshContainerWrapper(previous)
    end
    if containerId then
        self:RefreshContainerWrapper(containerId)
    end
    -- Focus also pins the independent bar movers' revealed chrome.
    self:RefreshArrangeSpecialMoverChrome("cast")
    self:RefreshArrangeSpecialMoverChrome("resource")
    if self.RefreshArrangePillList then
        self:RefreshArrangePillList()
    end
end

function CooldownCompanion:IsContainerChromePointerOver(frame)
    -- 4px of grace bridges the small gaps between the wrapper, header, nudger
    -- and coordinate label so crossing between them keeps the reveal alive.
    local wrapper = frame.dragHandle
    if wrapper and wrapper:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    if wrapper and wrapper.header and wrapper.header:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    if frame.nudger and frame.nudger:IsShown() and frame.nudger:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    if frame.coordLabel and frame.coordLabel:IsShown() and frame.coordLabel:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    return false
end

function CooldownCompanion:BeginContainerChromeHoverWatch(containerId)
    if not self:IsUnlockToolbarActive() or self:IsContainerArrangeChromeHidden(containerId) then
        return
    end
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame or frame._arrangeChromeHover then
        return
    end
    frame._arrangeChromeHover = true
    frame._arrangeHoverGen = (frame._arrangeHoverGen or 0) + 1
    local generation = frame._arrangeHoverGen
    self:RefreshContainerWrapper(containerId)
    local function Watch()
        if frame._arrangeHoverGen ~= generation or frame._arrangeChromeHover ~= true then
            return
        end
        if CooldownCompanion:IsUnlockToolbarActive() and CooldownCompanion:IsContainerChromePointerOver(frame) then
            C_Timer.After(0.2, Watch)
            return
        end
        frame._arrangeChromeHover = nil
        CooldownCompanion:RefreshContainerWrapper(containerId)
    end
    C_Timer.After(0.2, Watch)
end

function CooldownCompanion:SelectContainerWrapper(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    if frame._containerSelectedGroupId == nil then
        return
    end

    frame._containerSelectedGroupId = nil
    self:RefreshContainerWrapper(containerId)
    if self.RefreshArrangePillList then self:RefreshArrangePillList() end
end

function CooldownCompanion:SelectContainerPanel(containerId, groupId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (frame and group and group.parentContainerId == containerId) then
        return false
    end

    self:FocusArrangeContainer(containerId)

    if not self:IsGroupVisibleInUnlockPreview(groupId, {
        group = group,
        checkCharVisibility = true,
    }) then
        self:SelectContainerWrapper(containerId)
        return false
    end

    if frame._containerSelectedGroupId == groupId and frame._containerHoveredGroupId == groupId then
        return true
    end

    frame._containerSelectedGroupId = groupId
    frame._containerHoveredGroupId = groupId
    self:RefreshContainerWrapper(containerId)
    if self.RefreshArrangePillList then self:RefreshArrangePillList() end
    return true
end

local function ClearArrangeSectionSelectionState(self)
    local sectionGroupId = self._arrangeSectionGroupId
    if sectionGroupId == nil then return end
    -- Cancel any in-flight typed edit BEFORE the keys move: the commit
    -- callbacks re-read the selection at commit time, so an edit that
    -- outlived this transition would write to the wrong owner.
    local editFrame = self.groupFrames and self.groupFrames[sectionGroupId]
    if editFrame then
        CancelCoordinateEdit(editFrame.coordLabel)
        CancelCoordinateEdit(editFrame.sizeLabel)
    end
    self._arrangeSectionGroupId = nil
    self._arrangeSectionAnchor = nil
    local frame = self.groupFrames and self.groupFrames[sectionGroupId]
    if frame then
        local group = self.db.profile.groups[sectionGroupId]
        ST.UpdateSectionMoverOverlays(self, frame, group)
        ST.UpdateGroupSizeLabel(frame)
        -- The readouts go back to speaking for the panel.
        local anchor = group and group.anchor
        UpdateCoordLabel(frame, (anchor and anchor.x) or 0, (anchor and anchor.y) or 0)
        ApplySectionSelectionTint(frame)
    end
end

--- Public face of the section-selection clear, for the arrange teardowns
--- that live in GroupOperations (toolbar shutdown, the combat forced lock):
--- every path that drops the panel selection must drop the section with it,
--- canceling its in-flight edits and repainting its chrome.
function CooldownCompanion:ClearArrangeSectionSelection()
    ClearArrangeSectionSelectionState(self)
end

local function ClearArrangePanelSelectionState(self)
    self._arrangeSelectedPanelId = nil
    ClearArrangeSectionSelectionState(self)
    local preview = self._cursorAnchorLayoutPreview
    if preview and preview.selectedGroupId then
        self:SelectArrangeCursorPanel(preview.selectedGroupId, true)
    end
    for containerId, frame in pairs(self.containerFrames or {}) do
        if frame._containerSelectedGroupId or frame._containerHoveredGroupId then
            frame._containerSelectedGroupId = nil
            frame._containerHoveredGroupId = nil
            self:RefreshContainerWrapper(containerId)
        end
    end
end

function CooldownCompanion:ClearArrangeMoverSelection()
    ClearArrangePanelSelectionState(self)
    if self._arrangeSoloContainerId ~= nil then
        self:SetArrangeSoloContainer(nil)
    end
    self:FocusArrangeContainer(nil)
    self._arrangeTreeRevealEntry = nil
    self:RefreshArrangePillList()
end

-- One selection grammar for every panel surface. Clicks toggle the active
-- panel; drags pass toggle=false so they can select/solo without ever turning
-- the panel off on release.
function CooldownCompanion:ActivateArrangePanel(containerId, groupId, toggle)
    if not self:IsUnlockToolbarActive() then return false end
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (group and group.parentContainerId == containerId) then return false end
    if self:IsArrangePanelSuppressed(groupId)
        or self:IsArrangeContainerSuppressed(containerId) then
        return false
    end

    local cursorAnchored = self:IsGroupCursorAnchored(group)
    local containerUnlocked = self:IsContainerUnlockPreviewActive(containerId)
    local panelUnlocked = self:IsUnlockToolbarPanelEligible(groupId, group)
    local selected = self._arrangeSelectedPanelId == groupId
    if cursorAnchored then
        local preview = self._cursorAnchorLayoutPreview
        if not (preview and PreviewMapContains(preview.activeGroupIds, groupId)) then
            return false
        end
        selected = selected or (preview and preview.selectedGroupId == groupId or false)
    elseif containerUnlocked then
        local frame = self.containerFrames and self.containerFrames[containerId]
        if not (frame and self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            checkCharVisibility = true,
        })) then
            return false
        end
        selected = selected or (frame and frame._containerSelectedGroupId == groupId or false)
    elseif not panelUnlocked then
        return false
    end

    if selected and self._arrangeSoloContainerId == containerId then
        if toggle then
            self:ClearArrangeMoverSelection()
            return false
        end
        return true
    end

    ClearArrangePanelSelectionState(self)
    local activated
    if cursorAnchored then
        activated = self:SelectArrangeCursorPanel(groupId, false)
    elseif containerUnlocked then
        activated = self:SelectContainerPanel(containerId, groupId)
    else
        self:FocusArrangeContainer(containerId)
        activated = true
    end
    if not activated then return false end

    self._arrangeSelectedPanelId = groupId
    self:SetArrangeSoloContainer(containerId)
    self:RefreshAllIndependentPanelMoverChrome()
    self._arrangeTreeRevealEntry = { kind = "panel", id = groupId }
    self:RefreshArrangePillList()
    return true
end

--- The selected section for one panel, validated against the profile: the
--- anchor and its live section table, or nil. Selection is (groupId, anchor)
--- on the addon, one at a time, riding on top of the panel selection.
function CooldownCompanion:GetArrangeSelectedSectionAnchor(groupId)
    if groupId == nil or self._arrangeSectionGroupId ~= groupId then return nil end
    local anchor = self._arrangeSectionAnchor
    local group = self.db and self.db.profile and self.db.profile.groups
        and self.db.profile.groups[groupId]
    local sections = group and group.sections
    local section = type(sections) == "table" and anchor and sections[anchor] or nil
    if type(section) ~= "table" then return nil end
    return anchor, section
end

--- Select one SECTION of one panel. Rides the panel grammar: activating a
--- section first activates its panel (never toggling the panel off), and
--- everything that clears the panel selection clears the section with it.
--- While a section is selected, the panel's mouse wheel and size label write
--- that section's stored icon size instead of the panel style's (owner
--- ruling 2026-08-28: panel-level resize drives the base cluster only).
function CooldownCompanion:ActivateArrangeSection(groupId, anchor, toggle)
    local group = self.db and self.db.profile and self.db.profile.groups
        and self.db.profile.groups[groupId]
    if not (group and ST.PANEL_SECTION_ANCHOR_SET[anchor]) then return false end

    local wasSelected = self._arrangeSectionGroupId == groupId
        and self._arrangeSectionAnchor == anchor
    -- Piggyback the panel activation when the arrange toolbar is up. A panel
    -- unlocked outside it already has its chrome (and these overlays) shown,
    -- so the section stays addressable either way.
    if self:IsUnlockToolbarActive()
        and not self:ActivateArrangePanel(group.parentContainerId, groupId, false) then
        return false
    end

    local frame = self.groupFrames and self.groupFrames[groupId]
    -- Cancel any in-flight typed edit before the target changes hands (the
    -- commit callbacks re-read the selection at commit time).
    if frame then
        CancelCoordinateEdit(frame.coordLabel)
        CancelCoordinateEdit(frame.sizeLabel)
    end

    if toggle and wasSelected then
        self._arrangeSectionGroupId = nil
        self._arrangeSectionAnchor = nil
    else
        self._arrangeSectionGroupId = groupId
        self._arrangeSectionAnchor = anchor
        -- Reveal the section's own tree row, not the panel row the piggyback
        -- activation stamped a moment ago.
        self._arrangeTreeRevealEntry = { kind = "section", id = anchor, groupId = groupId }
    end
    if self.RefreshArrangePillList then self:RefreshArrangePillList() end

    if frame then
        ST.UpdateSectionMoverOverlays(self, frame, group)
        ST.UpdateGroupSizeLabel(frame)
        -- The readouts follow the selection: section values while one is
        -- selected, the panel's own otherwise.
        local _, selectedSection = self:GetArrangeSelectedSectionAnchor(groupId)
        if selectedSection then
            UpdateCoordLabel(frame,
                tonumber(selectedSection.offsetX) or 0,
                tonumber(selectedSection.offsetY) or 0)
        else
            local anchor2 = group.anchor
            UpdateCoordLabel(frame, (anchor2 and anchor2.x) or 0, (anchor2 and anchor2.y) or 0)
        end
        ApplySectionSelectionTint(frame)
    end
    return true
end

function CooldownCompanion:StartContainerPreviewMemberDrag(containerId, groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if self._combatForcedLock or not (containerId and group and group.parentContainerId == containerId) then
        return false
    end

    if not self:ActivateArrangePanel(containerId, groupId, false) then
        return false
    end
    if IsCursorAnchor(group.anchor) then
        return false
    end
    self:StartContainerMemberPreviewTracking(containerId, groupId)

    if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        if self.StartGroupedStandalonePreviewHostDrag and self:StartGroupedStandalonePreviewHostDrag(groupId, containerId) then
            return true
        end
        self:StopContainerMemberPreviewTracking(containerId)
        return false
    end

    local groupFrame = self.groupFrames and self.groupFrames[groupId]
    if not groupFrame or (InCombatLockdown() and groupFrame:IsProtected()) then
        self:StopContainerMemberPreviewTracking(containerId)
        return false
    end

    groupFrame._dragCancelPending = nil
    groupFrame._dragInProgress = true
    groupFrame:StartMoving()
    self:BeginMoverChromeFade(groupFrame)
    BeginSelfExcludedDragSnapSession(groupFrame)
    return true
end

function CooldownCompanion:StopContainerPreviewMemberDrag(containerId, groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (containerId and group and group.parentContainerId == containerId) then
        self:StopContainerMemberPreviewTracking(containerId)
        return
    end

    if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        if self.StopGroupedStandalonePreviewHostDrag then
            self:StopGroupedStandalonePreviewHostDrag(groupId, containerId)
        end
        self:StopContainerMemberPreviewTracking(containerId)
        return
    end

    local groupFrame = self.groupFrames and self.groupFrames[groupId]
    local cancelSave = (groupFrame and groupFrame._dragCancelPending == true) or self._combatForcedLock
    if groupFrame and not (InCombatLockdown() and groupFrame:IsProtected()) then
        groupFrame:StopMovingOrSizing()
    end
    if groupFrame then
        ApplyEndedDragSnapSession(groupFrame, not cancelSave)
        groupFrame._dragCancelPending = nil
        groupFrame._dragInProgress = nil
    end
    self:StopContainerMemberPreviewTracking(containerId)
    if cancelSave then
        return
    end
    self:SaveGroupPosition(groupId)
end

local function UpdateContainerWrapperLevels(frame)
    if not (frame and frame.dragHandle) then
        return
    end

    local wrapper = frame.dragHandle
    local strata = "FULLSCREEN_DIALOG"
    local baseLevel = 60

    wrapper:SetFrameStrata(strata)
    wrapper:SetFrameLevel(baseLevel)

    if wrapper.header then
        wrapper.header:SetFrameStrata(strata)
        wrapper.header:SetFrameLevel(baseLevel + 1)
    end

    if frame.coordLabel then
        frame.coordLabel:SetFrameStrata(strata)
        frame.coordLabel:SetFrameLevel(baseLevel + 2)
    end

    if frame._containerPanelLabels then
        for _, labelFrame in pairs(frame._containerPanelLabels) do
            labelFrame:SetFrameStrata(strata)
            labelFrame:SetFrameLevel(baseLevel + 3)
        end
    end

    if frame._containerMemberOverlays then
        for overlayIndex, overlay in pairs(frame._containerMemberOverlays) do
            overlay:SetFrameStrata(strata)
            overlay:SetFrameLevel(baseLevel + 10 + overlayIndex)
        end
    end

    if frame.nudger then
        frame.nudger:SetFrameStrata(strata)
        frame.nudger:SetFrameLevel(baseLevel + 4)
        for buttonIndex, btn in ipairs(frame.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 5 + buttonIndex)
        end
    end
end

local function GetContainerMemberDisplayFrame(self, groupId, group)
    local groupFrame = self.groupFrames and self.groupFrames[groupId]
    local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(group)

    if isStandaloneDisplay then
        local driverButton = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
        local host = driverButton and driverButton.auraTextureHost or nil
        if host and host:IsShown() then
            return host
        end
    end

    if not isStandaloneDisplay and groupFrame and groupFrame:IsShown() then
        return groupFrame
    end

    return nil
end

local function GetContainerMemberDisplayRect(self, containerFrame, groupId, group)
    local displayFrame = GetContainerMemberDisplayFrame(self, groupId, group)
    local rect = displayFrame and GetRelativeFrameRect(containerFrame, displayFrame) or nil

    if rect then
        rect.groupId = groupId
        rect.group = group
        rect.label = group.name or ("Panel " .. groupId)
        rect.displayFrame = displayFrame
    end

    return rect
end

local function GetContainerPanelSoloSelection(self, containerId, frame)
    local selectedGroupId = frame and frame._containerSelectedGroupId or nil
    if selectedGroupId then
        return selectedGroupId
    end

    -- Cursor-anchored panels use their own preview selection state rather than
    -- the container member overlay, but selecting one from the arrange tree
    -- should still suppress its owning container's outer mover chrome.
    local preview = self._cursorAnchorLayoutPreview
    local cursorGroupId = preview and preview.selectedGroupId or nil
    local cursorGroup = cursorGroupId and self.db.profile.groups[cursorGroupId] or nil
    if cursorGroup and cursorGroup.parentContainerId == containerId then
        return cursorGroupId
    end

    return nil
end

function CooldownCompanion:UpdateContainerWrapperUnion(containerId, previewRects, headerWidth)
    local frame = self.containerFrames and self.containerFrames[containerId]
    local wrapper = frame and frame.dragHandle
    if not wrapper then
        return 0, nil, nil, CONTAINER_WRAPPER_PADDING
    end

    previewRects = previewRects or frame._containerWrapperPreviewRects
    headerWidth = headerWidth or frame._containerWrapperHeaderWidth or 96
    if not previewRects then
        return 0, nil, nil, CONTAINER_WRAPPER_PADDING
    end

    local minLeft, maxRight, minBottom, maxTop = nil, nil, nil, nil
    local visibleRectCount = 0
    for _, rect in ipairs(previewRects) do
        local left, right, bottom, top, centerX, centerY, width, height = GetRelativeFrameRectValues(frame, rect.displayFrame)
        if left then
            rect.left = left
            rect.right = right
            rect.bottom = bottom
            rect.top = top
            rect.centerX = centerX
            rect.centerY = centerY
            rect.width = width
            rect.height = height
            visibleRectCount = visibleRectCount + 1
            minLeft = minLeft and math_min(minLeft, left) or left
            maxRight = maxRight and math_max(maxRight, right) or right
            minBottom = minBottom and math_min(minBottom, bottom) or bottom
            maxTop = maxTop and math_max(maxTop, top) or top
        end
    end

    frame._containerWrapperPreviewRects = previewRects
    frame._containerWrapperHeaderWidth = headerWidth
    wrapper:ClearAllPoints()
    if visibleRectCount == 0 then
        local fallbackWidth = math_max(headerWidth, CONTAINER_WRAPPER_FALLBACK_WIDTH)
        local fallbackHalfWidth = RoundPreviewOffset(fallbackWidth / 2)
        local fallbackHalfHeight = RoundPreviewOffset(CONTAINER_WRAPPER_FALLBACK_HEIGHT / 2)
        wrapper:SetPoint("BOTTOMLEFT", frame, "CENTER", -fallbackHalfWidth, -fallbackHalfHeight)
        wrapper:SetPoint("TOPRIGHT", frame, "CENTER", fallbackHalfWidth, fallbackHalfHeight)
    else
        local padding = CONTAINER_WRAPPER_PADDING
        wrapper:SetPoint("BOTTOMLEFT", frame, "CENTER", RoundPreviewOffset(minLeft - padding), RoundPreviewOffset(minBottom - padding))
        wrapper:SetPoint("TOPRIGHT", frame, "CENTER", RoundPreviewOffset(maxRight + padding), RoundPreviewOffset(maxTop + padding))
    end
    wrapper:SetShown(GetContainerPanelSoloSelection(self, containerId, frame) == nil)

    -- Keep the snap proxy on the panels' bounding box (wrapper minus padding).
    -- The empty-container fallback box is too small to inset, so match it.
    local snapRect = frame._dragSnapRectFrame
    if snapRect then
        snapRect:ClearAllPoints()
        if visibleRectCount == 0 then
            snapRect:SetAllPoints(wrapper)
        else
            snapRect:SetPoint("TOPLEFT", wrapper, "TOPLEFT", CONTAINER_WRAPPER_PADDING, -CONTAINER_WRAPPER_PADDING)
            snapRect:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -CONTAINER_WRAPPER_PADDING, CONTAINER_WRAPPER_PADDING)
        end
    end

    return visibleRectCount, minLeft, minBottom, CONTAINER_WRAPPER_PADDING
end

function CooldownCompanion:RefreshContainerWrapper(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    local container = self.db and self.db.profile and self.db.profile.groupContainers and self.db.profile.groupContainers[containerId]
    if not (frame and container and frame.dragHandle) or frame._isRefreshingContainerWrapper then
        return
    end

    frame._isRefreshingContainerWrapper = true
    local wrapper = frame.dragHandle
    local header = wrapper.header
    -- Same fade target as ApplyMoverChromeFadeState: the WRAPPER. Fading the
    -- header here would zero its own alpha, which the end-of-fade restore
    -- (wrapper-level) never puts back.
    self:ApplyMoverChromeFadeToFrames(wrapper, frame.coordLabel, frame.nudger)
    HideContainerPanelLabels(frame)
    UpdateContainerWrapperLevels(frame)

    if self._combatForcedLock
        or container.locked ~= false
        or self:IsContainerArrangeChromeHidden(containerId)
        or not self:IsContainerVisibleToCurrentChar(containerId) then
        if self.UpdateContainerDragHandle then
            self:UpdateContainerDragHandle(containerId, true)
        else
            self:ClearContainerUnlockState(containerId)
            wrapper:Hide()
            if header then
                header:Hide()
            end
            if frame.coordLabel then
                frame.coordLabel:Hide()
            end
            if frame.nudger then
                frame.nudger:Hide()
            end
        end
        frame._isRefreshingContainerWrapper = nil
        return
    end

    -- Below the locked-container return above: GetPanels walks every group and
    -- allocates, and no reader of it is reachable before that return.
    local allPanels = self.GetPanels and self:GetPanels(containerId) or nil
    local previewPanels = self.GetContainerUnlockPreviewPanels and self:GetContainerUnlockPreviewPanels(containerId, allPanels) or {}
    allPanels = allPanels or previewPanels
    local previewRects = {}
    local previewedGroupIds = {}

    for _, panelInfo in ipairs(previewPanels) do
        local rect = GetContainerMemberDisplayRect(self, frame, panelInfo.groupId, panelInfo.group)
        if rect then
            rect.panelSuppressed = self:IsArrangePanelSuppressed(rect.groupId)
            previewRects[#previewRects + 1] = rect
            if not rect.panelSuppressed then
                previewedGroupIds[rect.groupId] = true
            end
        end
    end

    if frame._containerSelectedGroupId and not previewedGroupIds[frame._containerSelectedGroupId] then
        frame._containerSelectedGroupId = nil
    end
    if frame._containerHoveredGroupId and not previewedGroupIds[frame._containerHoveredGroupId] then
        frame._containerHoveredGroupId = nil
    end

    local selectedGroupId = GetContainerPanelSoloSelection(self, containerId, frame)
    local hoveredGroupId = frame._containerHoveredGroupId
    local revealChrome = self:IsContainerArrangeChromeRevealed(containerId, frame)
    local headerWidth = 96

    if header then
        local titleText = header.text or wrapper.text
        if titleText then
            titleText:SetText(container.name or "Group")
            -- Left inset + name + quick menu + lock badge + right inset.
            local lockWidth = frame.dragHandle.lockButton and frame.dragHandle.lockButton:GetWidth() or 16
            local menuWidth = frame.dragHandle.menuButton and frame.dragHandle.menuButton:GetWidth() or 0
            headerWidth = math_max(
                96,
                math_floor((titleText:GetStringWidth() or 0) + 10 + 8 + menuWidth + 2 + lockWidth + 4 + 0.5)
            )
        end
    end

    local visibleRectCount, minLeft, minBottom, padding = self:UpdateContainerWrapperUnion(containerId, previewRects, headerWidth)
    if visibleRectCount == 0 then
        HideContainerMemberOverlays(frame)
        if header then
            header:SetWidth(headerWidth)
            header:Show()
        end
        if frame.coordLabel then
            frame.coordLabel:SetShown(revealChrome)
        end
        if frame.nudger then
            frame.nudger:SetShown(revealChrome)
        end
        frame._isRefreshingContainerWrapper = nil
        return
    end

    if header then
        header:SetWidth(headerWidth)
        header:Show()
    end

    if frame.coordLabel then
        frame.coordLabel:SetShown(selectedGroupId == nil and revealChrome)
    end
    if frame.nudger then
        frame.nudger:SetShown(selectedGroupId == nil and revealChrome)
    end

    local usedOverlayIndices = {}
    for labelIndex, rect in ipairs(previewRects) do
        if not rect.panelSuppressed then
            local isHovered = hoveredGroupId == rect.groupId
            local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(rect.group)

            local overlay = EnsureContainerMemberOverlay(frame, labelIndex)
            usedOverlayIndices[labelIndex] = true
            overlay.containerId = containerId
            overlay.groupId = rect.groupId
            overlay:ClearAllPoints()
            overlay:SetPoint("BOTTOMLEFT", rect.displayFrame, "BOTTOMLEFT", 0, 0)
            overlay:SetPoint("TOPRIGHT", rect.displayFrame, "TOPRIGHT", 0, 0)
            overlay:SetShown(true)

            local fillAlpha = 0
            if selectedGroupId == nil and not isStandaloneDisplay then
                if isHovered then
                    fillAlpha = CONTAINER_MOVER_COLORS.memberHoverAlpha
                end
            end
            overlay:SetBackdropColor(
                CONTAINER_MOVER_COLORS.memberR,
                CONTAINER_MOVER_COLORS.memberG,
                CONTAINER_MOVER_COLORS.memberB,
                fillAlpha
            )
            HideContainerWrapperBorder(overlay)

            local showLabel = selectedGroupId == nil and hoveredGroupId ~= nil and isHovered

            if showLabel then
                local labelFrame = EnsureContainerPanelLabel(frame, labelIndex)
                labelFrame.text:SetText(rect.label)
                labelFrame:SetWidth(math_max(CONTAINER_PANEL_LABEL_MIN_WIDTH, math_floor((labelFrame.text:GetStringWidth() or 0) + 16.5)))
                labelFrame:ClearAllPoints()
                labelFrame:SetPoint(
                    "BOTTOM",
                    wrapper,
                    "BOTTOMLEFT",
                    RoundPreviewOffset(rect.centerX - minLeft + padding),
                    RoundPreviewOffset(rect.top - minBottom + padding + CONTAINER_WRAPPER_LABEL_OFFSET)
                )
                labelFrame:Show()
            end
        end
    end

    if frame._containerMemberOverlays then
        for overlayIndex, overlay in pairs(frame._containerMemberOverlays) do
            if not usedOverlayIndices[overlayIndex] then
                overlay._dragging = nil
                overlay._suppressClick = nil
                overlay.groupId = nil
                HideContainerWrapperBorder(overlay)
                overlay:Hide()
            end
        end
    end

    for _, panelInfo in ipairs(allPanels) do
        local group = panelInfo.group
        local groupId = panelInfo.groupId
        local groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
        local isSelected = selectedGroupId == groupId and previewedGroupIds[groupId]
        local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
        local isCursorAnchored = group and IsCursorAnchor(group.anchor)

        if groupFrame and not isStandaloneDisplay then
            -- Cursor-anchored panels are owned by the cursor positioning
            -- preview, not the container mover: leave their chrome alone.
            if not isCursorAnchored then
                SyncGroupControlLevels(groupFrame, isSelected)
                if self:IsContainerUnlockPreviewActive(containerId) then
                    self:SetGroupDragControlsShown(groupFrame, isSelected)
                end
            end
            self:UpdateGroupClickthrough(groupId)
        elseif isStandaloneDisplay and self.UpdateGroupedStandalonePreviewSelection then
            self:UpdateGroupedStandalonePreviewSelection(groupId)
        end
    end

    frame._isRefreshingContainerWrapper = nil
end

function CooldownCompanion:RefreshAllContainerWrappers()
    if not self.containerFrames then
        return
    end

    for containerId in pairs(self.containerFrames) do
        self:RefreshContainerWrapper(containerId)
    end
end

local function UpdateContainerDragCoordinate(frame)
    local x, y = ComputeContainerFrameCoordinates(frame)
    if x ~= nil and y ~= nil then
        UpdateCoordLabel(frame, x, y)
    end
end

local function BeginContainerDragSnapSession(frame)
    local containerId = frame and frame.containerId
    CooldownCompanion:BeginDragSnapSession(frame, function(candidateFrame, candidateGroupId)
        if candidateFrame == frame or candidateFrame == frame.dragHandle then
            return true
        end
        local group = candidateGroupId
            and CooldownCompanion.db.profile.groups[candidateGroupId]
            or nil
        return group and group.parentContainerId == containerId or false
    end)
end

local function ApplyContainerCoordinates(frame, containerId, x, y)
    local container = CooldownCompanion.db.profile.groupContainers[containerId]
    if not (frame and container) then
        return
    end

    container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
    local oldX = tonumber(container.anchor.x) or 0
    local oldY = tonumber(container.anchor.y) or 0
    container.anchor.x = x
    container.anchor.y = y
    container.anchor.point = "CENTER"
    container.anchor.relativeTo = "UIParent"
    container.anchor.relativePoint = "CENTER"
    CooldownCompanion:AnchorContainerFrame(frame, container.anchor)
    if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
        CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId, x - oldX, y - oldY)
    end
    UpdateCoordLabel(frame, x, y)
    if CooldownCompanion.RefreshContainerWrapper then
        CooldownCompanion:RefreshContainerWrapper(containerId)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function CreateContainerNudger(frame, containerId)
    local NUDGE_GAP = 2

    local nudgerAnchor = frame.dragHandle.header or frame.dragHandle
    local nudger = CreateFrame("Frame", nil, nudgerAnchor, "BackdropTemplate")
    nudger.buttons = {}
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", nudgerAnchor, "TOP", 0, 2)
    nudger:SetFrameStrata(nudgerAnchor:GetFrameStrata())
    nudger:SetFrameLevel(nudgerAnchor:GetFrameLevel() + 5)
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
        { atlas = "common-dropdown-icon-back", rotation = -math.pi / 2, anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },
        { atlas = "common-dropdown-icon-next", rotation = -math.pi / 2, anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },
        { atlas = "common-dropdown-icon-back", rotation = 0,            anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },
        { atlas = "common-dropdown-icon-next", rotation = 0,            anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },
    }

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

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
            CooldownCompanion:BeginMoverChromeHoverFade(nudger)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            CooldownCompanion:SaveContainerPosition(containerId)
            if not nudger:IsMouseOver() then
                CooldownCompanion:EndMoverChromeFade(nudger)
            end
        end)

        local function DoNudge()
            local container = CooldownCompanion.db.profile.groupContainers[containerId]
            if not container then return end
            container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
            local cFrame = CooldownCompanion.containerFrames[containerId]
            if cFrame then
                local oldX = tonumber(container.anchor.x) or 0
                local oldY = tonumber(container.anchor.y) or 0
                cFrame:AdjustPointsOffset(dir.dx, dir.dy)
                local _, _, _, x, y = cFrame:GetPoint()
                container.anchor.x = math_floor(x * 10 + 0.5) / 10
                container.anchor.y = math_floor(y * 10 + 0.5) / 10
                if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
                    CooldownCompanion:SyncGroupedStandalonePreviewSettings(
                        containerId,
                        container.anchor.x - oldX,
                        container.anchor.y - oldY
                    )
                end
                UpdateCoordLabel(cFrame, x, y)
            end
        end

        btn:SetScript("OnMouseDown", function(self)
            CancelCoordinateEdit(frame.coordLabel)
            CooldownCompanion:FocusArrangeContainer(containerId)
            DoNudge()
            CooldownCompanion:VerifyMoverChromeHoverFade(nudger)
        end)

        btn:SetScript("OnMouseUp", function(self)
            CooldownCompanion:SaveContainerPosition(containerId)
        end)
    end

    return nudger
end

function ST.LockContainerFromMover(containerId)
    local container = CooldownCompanion.db.profile.groupContainers[containerId]
    if not container then
        return
    end

    if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
        CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId)
    end
    if CooldownCompanion._arrangeFocusContainerId == containerId then
        CooldownCompanion._arrangeFocusContainerId = nil
    end
    CooldownCompanion:SetContainerLocked(containerId, true)
    CooldownCompanion:CaptureArrangeContainerRecord(containerId)
    CooldownCompanion:RefreshConfigPanel()
    CooldownCompanion:Print(container.name .. " locked.")
    CooldownCompanion:CheckArrangeModeAutoExit()
end

function CooldownCompanion:CreateContainerFrame(containerId)
    -- Prevent duplicates
    if self.containerFrames[containerId] then
        return self.containerFrames[containerId]
    end

    local container = self.db.profile.groupContainers[containerId]
    if not container then return end
    container.anchor = self:NormalizeContainerAnchor(container.anchor)

    local frameName = "CooldownCompanionContainer" .. containerId
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame.containerId = containerId

    -- Container frames are invisible — just an anchor point.
    -- Size is minimal; panels anchor to it but define their own size.
    frame:SetSize(1, 1)

    -- Position the frame
    self:AnchorContainerFrame(frame, container.anchor)

    -- Make it movable when unlocked
    frame:SetMovable(true)
    frame:EnableMouse(not container.locked)
    frame:RegisterForDrag("LeftButton")

    -- Wrapper outline (visible when unlocked)
    frame.dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.dragHandle:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.dragHandle:SetSize(1, 1)
    frame.dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.dragHandle:SetBackdropColor(0.15, 0.35, 0.55, 0.08)
    EnsureContainerWrapperBorder(frame.dragHandle, 0.2, 0.8, 1, CONTAINER_MOVER_COLORS.wrapperBorderAlpha)
    -- Snap guides align to the panels' bounding box, not the outline: the
    -- wrapper rect is the panel union plus padding, and entries are what
    -- players actually line up.
    local snapRect = CreateFrame("Frame", nil, frame.dragHandle)
    snapRect:SetPoint("TOPLEFT", frame.dragHandle, "TOPLEFT", CONTAINER_WRAPPER_PADDING, -CONTAINER_WRAPPER_PADDING)
    snapRect:SetPoint("BOTTOMRIGHT", frame.dragHandle, "BOTTOMRIGHT", -CONTAINER_WRAPPER_PADDING, CONTAINER_WRAPPER_PADDING)
    snapRect:EnableMouse(false)
    frame._dragSnapRectFrame = snapRect

    frame.dragHandle.header = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    frame.dragHandle.header:SetHeight(CONTAINER_WRAPPER_HEADER_HEIGHT)
    frame.dragHandle.header:SetPoint("BOTTOM", frame.dragHandle, "TOP", 0, CONTAINER_WRAPPER_HEADER_GAP)
    frame.dragHandle.header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.dragHandle.header:SetBackdropColor(0.15, 0.35, 0.55, 0.92)
    CreatePixelBorders(frame.dragHandle.header)

    frame.dragHandle.text = frame.dragHandle.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Title-bar layout: name left, lock badge right
    frame.dragHandle.text:SetPoint("LEFT", frame.dragHandle.header, "LEFT", 10, 0)
    do
        local fontPath, _, fontFlags = frame.dragHandle.text:GetFont()
        if fontPath then
            frame.dragHandle.text:SetFont(fontPath, CONTAINER_WRAPPER_HEADER_FONT_SIZE, fontFlags)
        end
    end
    frame.dragHandle.text:SetText(container.name)
    frame.dragHandle.text:SetTextColor(1, 1, 1, 1)
    frame.dragHandle.header.text = frame.dragHandle.text

    frame.dragHandle.lockButton = ST.CreateMoverLockBadge(frame.dragHandle.header, 18, function()
        ST.LockContainerFromMover(containerId)
    end)
    frame.dragHandle.lockButton:SetPoint("RIGHT", frame.dragHandle.header, "RIGHT", -4, 0)
    frame.dragHandle.menuButton = ST.CreateMoverQuickMenuButton(
        frame.dragHandle.header,
        16,
        function()
            return { kind = "container", id = containerId, focusId = containerId }
        end,
        frame.dragHandle
    )
    frame.dragHandle.menuButton:SetPoint("RIGHT", frame.dragHandle.lockButton, "LEFT", -2, 0)
    frame.dragHandle.text:SetPoint("RIGHT", frame.dragHandle.menuButton, "LEFT", -4, 0)

    -- Pixel nudger
    frame.nudger = CreateContainerNudger(frame, containerId)

    -- Coordinate label
    frame.coordLabel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.coordLabel:SetHeight(15)
    frame.coordLabel:SetPoint("TOPLEFT", frame.dragHandle, "BOTTOMLEFT", 0, -2)
    frame.coordLabel:SetPoint("TOPRIGHT", frame.dragHandle, "BOTTOMRIGHT", 0, -2)
    frame.coordLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    CreatePixelBorders(frame.coordLabel)
    frame.coordLabel.text = frame.coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.coordLabel.text:SetPoint("CENTER")
    frame.coordLabel.text:SetTextColor(1, 1, 1, 1)
    CreateEditableCoordLabel(
        frame.coordLabel,
        function()
            local currentContainer = CooldownCompanion.db.profile.groupContainers[containerId]
            local anchor = currentContainer and currentContainer.anchor
            return anchor and anchor.x or 0, anchor and anchor.y or 0
        end,
        function(x, y)
            ApplyContainerCoordinates(frame, containerId, x, y)
        end,
        function()
            return frame._dragInProgress == true
        end
    )
    -- Starting a coordinate edit is an explicit interaction: pin the container
    -- so the label cannot hover-hide mid-edit.
    frame.coordLabel:HookScript("OnMouseDown", function()
        CooldownCompanion:FocusArrangeContainer(containerId)
    end)
    UpdateCoordLabel(frame)

    -- Start hidden (drag handle shows only when unlocked)
    if container.locked then
        frame.dragHandle:Hide()
    end

    -- Drag scripts
    frame:SetScript("OnDragStart", function(self)
        CancelCoordinateEdit(self.coordLabel)
        local c = CooldownCompanion.db.profile.groupContainers[self.containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(self.containerId) then
            CooldownCompanion:SelectContainerWrapper(self.containerId)
            self._dragCancelPending = nil
            self._dragInProgress = true
            self:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(self)
            BeginContainerDragSnapSession(self)
            StartCoordinateDragUpdates(self, UpdateContainerDragCoordinate)
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
        self._dragCancelPending = nil
        self._dragInProgress = nil
        if not (InCombatLockdown() and self:IsProtected()) then
            self:StopMovingOrSizing()
        end
        ApplyEndedDragSnapSession(self, not cancelSave)
        StopCoordinateDragUpdates(self)
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(self)
            return
        end
        CooldownCompanion:SaveContainerPosition(self.containerId)
        CooldownCompanion:EndMoverChromeFade(self)
    end)

    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnEnter", function()
        CooldownCompanion:BeginContainerChromeHoverWatch(containerId)
    end)
    frame.dragHandle:SetScript("OnDragStart", function()
        CancelCoordinateEdit(frame.coordLabel)
        local c = CooldownCompanion.db.profile.groupContainers[containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(containerId) then
            frame.dragHandle._suppressClick = true
            CooldownCompanion:SelectContainerWrapper(containerId)
            CooldownCompanion:SetArrangeSoloContainer(containerId)
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(frame)
            BeginContainerDragSnapSession(frame)
            StartCoordinateDragUpdates(frame, UpdateContainerDragCoordinate)
        end
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        -- Preserve suppression through this release cycle, but do not let a
        -- missing OnMouseUp consume the player's next intentional click.
        C_Timer.After(0, function()
            frame.dragHandle._suppressClick = nil
        end)
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
        ApplyEndedDragSnapSession(frame, not cancelSave)
        StopCoordinateDragUpdates(frame)
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(frame)
            return
        end
        CooldownCompanion:SaveContainerPosition(containerId)
        CooldownCompanion:EndMoverChromeFade(frame)
    end)
    frame.dragHandle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and frame.dragHandle._suppressClick then
            frame.dragHandle._suppressClick = nil
        end
    end)

    frame.dragHandle.header:EnableMouse(true)
    frame.dragHandle.header:RegisterForDrag("LeftButton")
    frame.dragHandle.header:SetScript("OnEnter", function()
        CooldownCompanion:BeginContainerChromeHoverWatch(containerId)
    end)
    frame.dragHandle.header:SetScript("OnDragStart", function()
        CancelCoordinateEdit(frame.coordLabel)
        local c = CooldownCompanion.db.profile.groupContainers[containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(containerId) then
            frame.dragHandle.header._suppressClick = true
            CooldownCompanion:SelectContainerWrapper(containerId)
            CooldownCompanion:SetArrangeSoloContainer(containerId)
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
            CooldownCompanion:BeginMoverChromeFade(frame)
            BeginContainerDragSnapSession(frame)
            StartCoordinateDragUpdates(frame, UpdateContainerDragCoordinate)
        end
    end)
    frame.dragHandle.header:SetScript("OnDragStop", function()
        -- Preserve suppression through this release cycle, but do not let a
        -- missing OnMouseUp consume the player's next intentional click.
        C_Timer.After(0, function()
            frame.dragHandle.header._suppressClick = nil
        end)
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
        ApplyEndedDragSnapSession(frame, not cancelSave)
        StopCoordinateDragUpdates(frame)
        if cancelSave then
            CooldownCompanion:EndMoverChromeFade(frame)
            return
        end
        CooldownCompanion:SaveContainerPosition(containerId)
        CooldownCompanion:EndMoverChromeFade(frame)
    end)

    frame.dragHandle.header:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" and frame.dragHandle.header._suppressClick then
            frame.dragHandle.header._suppressClick = nil
        end
    end)

    self.containerFrames[containerId] = frame
    UpdateContainerWrapperLevels(frame)
    self:RefreshContainerWrapper(containerId)
    frame:Show()
    return frame
end

function CooldownCompanion:AnchorContainerFrame(frame, anchor)
    -- Deferred during combat — ClearAllPoints/SetPoint are protected.
    if InCombatLockdown() and frame:IsProtected() then
        frame._anchorDirty = true
        return
    end
    frame._anchorDirty = nil
    local normalizedAnchor, _, deferred = self:NormalizeContainerAnchor(anchor)
    if not deferred then
        anchor = normalizedAnchor
    else
        local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
        local anchorState = self.GetContainerAnchorTargetState and self:GetContainerAnchorTargetState(frame.containerId, relativeTo) or nil
        local rawX = tonumber(anchor and anchor.x) or 0
        local rawY = tonumber(anchor and anchor.y) or 0

        if anchorState == "ok" then
            local relativeFrame = relativeTo and _G[relativeTo]
            if relativeFrame then
                frame:ClearAllPoints()
                -- Same rule as a panel dependent: a sectioned panel's base row
                -- is the body a container anchored to it hangs off.
                frame:SetPoint(anchor.point or "CENTER", ST.GetPanelAnchorBodyFrame(relativeFrame),
                    anchor.relativePoint or "CENTER", rawX, rawY)
                UpdateCoordLabel(frame, rawX, rawY)
                return
            end
        elseif anchorState == "unsafe" then
            local unsafeFrame = relativeTo and _G[relativeTo]
            if ApplyUnsafeAnchorVisualFallback(frame, anchor, unsafeFrame) then
                UpdateCoordLabel(frame, rawX, rawY)
                return
            end
        elseif anchorState == "missing" then
            frame:ClearAllPoints()
            frame:SetPoint(anchor.point or "CENTER", UIParent, anchor.relativePoint or "CENTER", rawX, rawY)
            UpdateCoordLabel(frame, rawX, rawY)
            return
        end
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(anchor.x) or 0, tonumber(anchor.y) or 0)
    UpdateCoordLabel(frame, tonumber(anchor.x) or 0, tonumber(anchor.y) or 0)
end

ComputeContainerFrameCoordinates = function(frame)
    local cx, cy = frame:GetCenter()
    if not cx then return nil, nil end
    local ucx, ucy = UIParent:GetCenter()
    if not ucx then return nil, nil end

    local newX = math_floor((cx - ucx) * 10 + 0.5) / 10
    local newY = math_floor((cy - ucy) * 10 + 0.5) / 10
    return newX, newY
end

function CooldownCompanion:SaveContainerPosition(containerId)
    local frame = self.containerFrames[containerId]
    local container = self.db.profile.groupContainers[containerId]
    if not frame or not container then return end
    container.anchor = self:NormalizeContainerAnchor(container.anchor)
    local oldX = tonumber(container.anchor.x) or 0
    local oldY = tonumber(container.anchor.y) or 0

    local newX, newY = ComputeContainerFrameCoordinates(frame)
    if newX == nil or newY == nil then return end

    container.anchor.x = newX
    container.anchor.y = newY
    container.anchor.point = "CENTER"
    container.anchor.relativeTo = "UIParent"
    container.anchor.relativePoint = "CENTER"

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", newX, newY)

    if self.SyncGroupedStandalonePreviewSettings then
        self:SyncGroupedStandalonePreviewSettings(containerId, newX - oldX, newY - oldY)
    end
    UpdateCoordLabel(frame, newX, newY)
    if self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(containerId)
    end
    self:RefreshConfigPanel()
end

function CooldownCompanion:IsContainerVisibleToCurrentChar(containerId)
    if not (self.ResolveContainerClassScope and self.db and self.db.profile and self.db.profile.groupContainers) then
        return false
    end
    local container = self.db.profile.groupContainers[containerId]
    if type(container) == "table" then
        if container.isGlobal == true then
            return true
        end
        local currentCharKey = self.db.keys and self.db.keys.char
        local currentCharInfo = currentCharKey
            and self.db.global
            and self.db.global.characterInfo
            and self.db.global.characterInfo[currentCharKey]
        if container.createdBy == currentCharKey
            and type(currentCharInfo) == "table"
            and (currentCharInfo.classFilename or currentCharInfo.classID) then
            return true
        end
    end
    local scope = self:ResolveContainerClassScope(containerId)
    return scope.runtimeVisible == true
end

function CooldownCompanion:CreateAllContainerFrames()
    local containers = self.db.profile.groupContainers
    if not containers then return end
    for containerId, _ in pairs(containers) do
        if self:IsContainerVisibleToCurrentChar(containerId) then
            self:CreateContainerFrame(containerId)
        end
    end
end

------------------------------------------------------------------------
-- Pick-mode indicators: pulsing green border + name label on eligible groups
------------------------------------------------------------------------
function CooldownCompanion:ShowPickModeIndicators(sourceGroupId)
    if not self._pickIndicators then self._pickIndicators = {} end
    local groups = self.db.profile.groups
    if not groups then return end

    -- Helper to create/show an indicator on a frame
    local function ShowIndicator(key, frame, labelText, sourceId, isCircular)
        if not frame or not frame:IsShown() or isCircular then return end
        local indicator = self._pickIndicators[key]
        if not indicator then
            indicator = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            indicator:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 14,
            })
            indicator:SetBackdropBorderColor(0, 1, 0, 0.8)
            indicator:EnableMouse(false)

            local label = indicator:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("BOTTOM", indicator, "TOP", 0, 2)
            label:SetTextColor(0.2, 1, 0.2, 1)
            indicator.label = label

            local ag = indicator:CreateAnimationGroup()
            local pulse = ag:CreateAnimation("Alpha")
            pulse:SetFromAlpha(0.4)
            pulse:SetToAlpha(1.0)
            pulse:SetDuration(0.6)
            ag:SetLooping("BOUNCE")
            indicator.pulseAnim = ag

            self._pickIndicators[key] = indicator
        end

        indicator:SetFrameStrata("FULLSCREEN_DIALOG")
        indicator:SetFrameLevel(101)
        indicator.label:SetText(labelText)
        indicator:SetAllPoints(frame)
        indicator:Show()
        indicator.pulseAnim:Play()
    end

    -- Show indicators on group frames
    for groupId, group in pairs(groups) do
        if groupId ~= sourceGroupId then
            ShowIndicator(
                "group:" .. groupId,
                self.groupFrames[groupId],
                group.name or ("Group " .. groupId),
                sourceGroupId,
                self:WouldCreateCircularAnchor(sourceGroupId, groupId)
            )
        end
    end

    -- Show indicators on container frames
    local containers = self.db.profile.groupContainers
    if containers and self.containerFrames then
        for containerId, container in pairs(containers) do
            ShowIndicator(
                "container:" .. containerId,
                self.containerFrames[containerId],
                container.name or ("Container " .. containerId),
                sourceGroupId,
                self:WouldCreateCircularAnchor(sourceGroupId, containerId, "container")
            )
        end
    end
end

function CooldownCompanion:ClearPickModeIndicators()
    if not self._pickIndicators then return end
    for _, indicator in pairs(self._pickIndicators) do
        if indicator.pulseAnim then
            indicator.pulseAnim:Stop()
        end
        indicator:Hide()
    end
end
