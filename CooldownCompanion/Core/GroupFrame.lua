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
local table_insert = table.insert
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local issecretvalue = issecretvalue
local select = select
local wipe = wipe

-- Shared click-through and border helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local HideGlowStyles = ST._HideGlowStyles
local EntryRuntime = ST.EntryRuntime
local UnbindDurationText = CooldownCompanion.UnbindDurationText or function() end

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
local CURSOR_LAYOUT_PREVIEW_TOP_OFFSET = -120
local CURSOR_LAYOUT_PREVIEW_TINT = { 0.35, 0.92, 1, 1 }

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
    return group.locked or false, group.baselineAlpha or 1
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

    if ST.IsGroupConfigSelected and ST.IsGroupConfigSelected(frame.groupId) then
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

local function IsSourceButtonInPreviewScope(self, groupId, sourceIndex, opts)
    if self.IsButtonInConfigPreviewScope then
        return self:IsButtonInConfigPreviewScope(groupId, sourceIndex, opts)
    end
    return true
end

local function GetContainerPreviewSelectionState(groupId)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local containerId = group and group.parentContainerId or nil
    if not containerId then
        return false, false, nil
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

local function UpdateCoordLabel(frame, x, y)
    if frame.coordLabel then
        frame.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x, y))
    end
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

local FLIP_HORIZONTAL = {
    TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
    BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
}
local FLIP_VERTICAL = {
    TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT",
    BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT",
}

local function GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, growthOrigin)
    growthOrigin = growthOrigin or "TOPLEFT"
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
        if button.auraGlow then
            HideGlowStyles(button.auraGlow)
        end
        if button.readyGlow then
            HideGlowStyles(button.readyGlow)
        end
        if button.assistedHighlight then
            HideGlowStyles(button.assistedHighlight)
        end
        if button.barAuraEffect then
            HideGlowStyles(button.barAuraEffect)
        end
    end

    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._readyGlowActive = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = false
    button._barAuraEffectActive = nil
    button._barPulseActive = nil
    button._barColorShiftActive = nil
    if button.statusBar then button.statusBar:SetAlpha(1.0) end
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
    button._readyGlowPreview = nil
    button._keyPressHighlightPreview = nil
    button._barAuraActivePreview = nil
    button._textureProcPreview = nil
    button._textureAuraPreview = nil
    button._texturePandemicPreview = nil
    button._textureReadyPreview = nil
    button._textureUnusablePreview = nil
    button._textureIndicatorPreviewDirty = false
    button._triggerEffectsPreview = nil
    button._auraTexturePreviewSelection = nil
    button._conditionalPreviewKind = nil
    button._conditionalPreviewStartTime = nil
    button._conditionalPreviewDuration = nil
    button._conditionalPreviewRemaining = nil
    button._conditionalPreviewLoop = nil
    button._conditionalPreviewLoopStartTime = nil
    button._conditionalPreviewLoopDuration = nil
    button._conditionalPreviewDomain = nil
    button._conditionalAuraPreview = nil
    button._conditionalAuraDurationTextPreview = nil
    button._conditionalAuraStackTextPreview = nil
    button._conditionalPandemicPreview = nil
    button._conditionalUnusablePreview = nil
    button._conditionalOutOfRangePreview = nil
    button._conditionalReadyPreview = nil
    button._conditionalLocPreview = nil
    button._conditionalBarAuraActivePreview = nil
    button._conditionalVisualPreview = nil
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
    button._spellTexBaseline = nil
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
    button._auraDurationObj = nil
    button._auraCooldownStart = nil
    button._auraCooldownDuration = nil
    button._auraPrimarySwipeActive = nil
    button._auraTrackingReady = nil
    button._showingAuraIcon = false
    button._auraViewerFrame = nil
    button._activeAuraSpellID = nil
    button._activeAuraSpellIDFromFallback = nil
    button._activeAuraIcon = nil
    button._activeAuraIconAvailable = nil
    button._lastViewerTexId = nil
    button._auraInstanceID = nil
    button._viewerBar = nil
    button._viewerAuraVisualsActive = nil
    button._auraDisplayName = nil
    button._auraNameOverrideActive = nil
    button._auraStackText = nil
    button._auraHasTimer = nil
    button._textSecretNameActive = nil
    EntryRuntime.ReleaseTrackedAuraScratch(button)
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
    button._unusableTintActive = nil
    button._iconFillActive = nil
    button._iconFillMode = nil
    button._iconFillAuraActive = nil
    button._iconFillColorR = nil
    button._iconFillColorG = nil
    button._iconFillColorB = nil
    button._iconFillColorA = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._auraGlowPandemic = nil
    button._readyGlowActive = nil
    button._readyGlowStartTime = nil
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = nil
    button._readyGlowMaxChargesSpellID = nil
    button._barAuraEffectActive = nil
    button._barPulseActive = nil
    button._barColorShiftActive = nil
    button._barAuraStackDisplay = nil
    button._barAuraStackValue = nil
    button._barAuraStackValueAvailable = nil
    button._barAuraStackValueSecret = nil
    button._barAuraStackValueDirty = nil
    button._barAuraStackMax = nil
    button._barAuraStackMode = nil
    button._barAuraVisualSettings = nil
    button._barGCDSuppressed = nil
    button._barCdColor = nil
    button._barAuraColor = nil
    button._barReadyTextColor = nil
    button._barTextMode = nil
    button._barTextColorDirty = true
    button._lastBarTimeText = nil
    button._textVisualIntent = nil
    button._textVisualApplied = nil
    button._textModeSecretArgs = nil
    button._textModeSecretParts = nil
    button._savedOnUpdate = nil
    button._inPandemic = nil
    if EntryRuntime and EntryRuntime.ClearAuraPandemicRuntimeState then
        EntryRuntime.ClearAuraPandemicRuntimeState(button)
    end
    ClearButtonPreviewState(button)
    ClearButtonVisualState(button)
    if button.count then button.count:SetText("") end
    if button.auraStackCount then button.auraStackCount:SetText("") end
    if button.textString then
        button.textString:SetText("")
        button.textString:SetAlpha(1)
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
    HideButtonGlowContainer(button.auraGlow)
    HideButtonGlowContainer(button.readyGlow)
    HideButtonGlowContainer(button.keyPressHighlight)
    HideButtonGlowContainer(button.barAuraEffect)
    ClearReusableButtonRuntime(button)
    button._buttonPoolKey = GetExistingButtonPoolKey(button)
    button._pooled = true
    button:Hide()
    button:ClearAllPoints()
end

local function ReleaseButtonToPool(self, frame, groupId, button)
    DeactivatePooledButton(self, groupId, button)
    local pool = GetButtonPool(frame, button._buttonPoolKey)
    pool[#pool + 1] = button
end

local function AcquireButtonFromPool(frame, poolKey, buttonData)
    local pools = frame._buttonFramePools
    local pool = pools and pools[poolKey]
    if not pool or #pool == 0 then return nil end
    local pick
    if InCombatLockdown() then
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
        if not pick then return nil end
    else
        -- Prefer the frame that already hosts this entry: repeated repopulates
        -- (config refreshes) then converge on a stable entry<->frame mapping
        -- instead of reversing it each pass, which flip-flopped the statically
        -- composed aura-shell visuals and churned the aura slot rebinds.
        for i = #pool, 1, -1 do
            if pool[i].buttonData == buttonData then
                pick = i
                break
            end
        end
        pick = pick or #pool
    end
    local button = table.remove(pool, pick)
    button._pooled = nil
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
end

-- Nudger constants
local NUDGE_BTN_SIZE = 12

local CreatePixelBorders = ST.CreatePixelBorders
local GetEffectiveTextHeight = ST._GetEffectiveTextHeight

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
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            if not IsCursorPreviewNudge() then
                CooldownCompanion:SaveGroupPosition(groupId)
            end
        end)

        local function DoNudge()
            local group = CooldownCompanion.db.profile.groups[groupId]
            if not group then return end
            local gFrame = CooldownCompanion.groupFrames[groupId]
            if gFrame then
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
            DoNudge()
        end)

        btn:SetScript("OnMouseUp", function(self)
            if not IsCursorPreviewNudge() then
                CooldownCompanion:SaveGroupPosition(groupId)
            end
        end)
    end

    return nudger
end

local function AddPanelDragHelpTooltipLines(tooltip, isContainerPreview, isCursorPreview)
    if isCursorPreview then
        tooltip:AddLine("Cursor Offset")
        tooltip:AddLine("Drag this panel to set its saved offset from the dummy cursor.", 1, 1, 1, true)
        tooltip:AddLine(" ")
        tooltip:AddLine("Use the arrow pad to nudge the saved cursor offset by 1 pixel.", 1, 1, 1, true)
        tooltip:AddLine(" ")
        tooltip:AddLine("Position coordinates are shown below while editing.", 1, 1, 1, false)
        return
    end

    tooltip:AddLine("Panel Controls")
    tooltip:AddLine("Drag anywhere on the panel to move it.", 1, 1, 1, false)
    tooltip:AddLine(" ")
    tooltip:AddLine("Use the arrow pad to nudge by 1 pixel.", 1, 1, 1, false)
    tooltip:AddLine(" ")
    if not isContainerPreview then
        tooltip:AddLine("Middle-click the header to lock this panel.", 1, 1, 1, false)
        tooltip:AddLine(" ")
    end
    tooltip:AddLine("Position coordinates are shown below while unlocked.", 1, 1, 1, false)
end

local function CreatePanelDragHelpButton(frame, groupId)
    if not (frame and frame.dragHandle and ST.CreateRuntimeInfoButton) then
        return nil
    end

    return ST.CreateRuntimeInfoButton(
        frame.dragHandle,
        frame.dragHandle,
        "RIGHT",
        "RIGHT",
        -4,
        0,
        function(tooltip)
            local previewActive = GetContainerPreviewSelectionState(groupId)
            local cursorPreviewActive = CooldownCompanion.IsCursorAnchorLayoutPreviewSelected
                and CooldownCompanion:IsCursorAnchorLayoutPreviewSelected(groupId)
                or false
            AddPanelDragHelpTooltipLines(tooltip, previewActive, cursorPreviewActive)
        end
    )
end

local function SyncGroupControlLevels(frame, raiseAboveWrapper)
    if not frame then
        return
    end

    local strata = raiseAboveWrapper and "FULLSCREEN_DIALOG" or frame:GetFrameStrata()
    local baseLevel = raiseAboveWrapper and 90 or ((frame:GetFrameLevel() or 1) + 5)

    if frame.dragHandle then
        frame.dragHandle:SetFrameStrata(strata)
        frame.dragHandle:SetFrameLevel(baseLevel)
    end
    if frame.coordLabel then
        frame.coordLabel:SetFrameStrata(strata)
        frame.coordLabel:SetFrameLevel(baseLevel + 1)
    end
    if frame.dragHelpButton then
        frame.dragHelpButton:SetFrameStrata(strata)
        frame.dragHelpButton:SetFrameLevel(baseLevel + 2)
    end
    if frame.nudger then
        frame.nudger:SetFrameStrata(strata)
        frame.nudger:SetFrameLevel(baseLevel + 5)
        for buttonIndex, btn in ipairs(frame.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 6 + buttonIndex)
        end
    end
end

function CooldownCompanion:SetGroupDragControlsShown(frame, shown)
    if not frame then
        return
    end

    if frame.dragHandle then
        frame.dragHandle:SetShown(shown)
    end
    if frame.coordLabel then
        frame.coordLabel:SetShown(shown)
    end
    if ST.SetRuntimeInfoButtonShown then
        ST.SetRuntimeInfoButtonShown(frame.dragHelpButton, shown)
    end
    if frame.nudger then
        frame.nudger:SetShown(shown)
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

local function BuildCursorAnchorLayoutPreviewGroupMap(self)
    local activeGroupIds = {}
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then
        return activeGroupIds
    end

    for groupId, group in pairs(groups) do
        if IsCursorAnchor(group.anchor)
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
    if group.compactLayout and self.UpdateGroupLayout then
        self:UpdateGroupLayout(groupId)
    end

    self:SetGroupDragControlsShown(frame, selected and not isStandaloneDisplay)
    if selected then
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

local function BeginCursorLayoutPreviewDrag(ownerFrame, dragRegion)
    ownerFrame._dragInProgress = true
    dragRegion:SetScript("OnUpdate", function()
        CooldownCompanion:UpdateCursorAnchoredFrames()
    end)
    ownerFrame:StartMoving()
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
end

local function SaveCursorAnchorLayoutPreviewPanelPosition(self, groupId)
    local preview = self._cursorAnchorLayoutPreview
    local frame = self.groupFrames and self.groupFrames[groupId] or nil
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (preview and frame and group and IsCursorAnchor(group.anchor)) then
        return false
    end
    if not IsCursorAnchorLayoutPreviewSelected(self, groupId) then
        return false
    end

    local cursorX, cursorY = GetCursorAnchorLayoutPreviewPosition(self, groupId)
    local frameCenterX, frameCenterY = frame:GetCenter()
    local frameWidth, frameHeight = GetFrameSizeInUIParentSpace(frame)
    if not (cursorX and cursorY and frameCenterX and frameCenterY and frameWidth and frameHeight) then
        self:UpdateCursorAnchoredFrames()
        return false
    end

    local point = group.anchor.point or CURSOR_ANCHOR_POINT
    local anchorOffsetX, anchorOffsetY = GetAnchorOffset(point, frameWidth, frameHeight)
    local newX = math_floor(((frameCenterX + anchorOffsetX) - cursorX) * 10 + 0.5) / 10
    local newY = math_floor(((frameCenterY + anchorOffsetY) - cursorY) * 10 + 0.5) / 10

    group.anchor.point = point
    group.anchor.relativeTo = CURSOR_ANCHOR_TARGET
    group.anchor.relativePoint = CURSOR_ANCHOR_RELATIVE_POINT
    group.anchor.x = newX
    group.anchor.y = newY

    ApplyCursorAnchorPosition(self, frame, group.anchor, cursorX, cursorY)
    UpdateCoordLabel(frame, newX, newY)
    self:RefreshConfigPanel()
    self:UpdateCursorAnchoredFrames()
    return true
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
    frame:StartMoving()
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
        if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
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
    frame:SetPoint("TOP", UIParent, "TOP", 0, CURSOR_LAYOUT_PREVIEW_TOP_OFFSET)
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
        GameTooltip:AddLine("Returns this preview cursor to its default top-center position for this session.", 1, 1, 1, true)
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
    self._cursorAnchorLayoutPreview = preview
    return preview
end

function CooldownCompanion:ShowCursorAnchorLayoutPreview(groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (group and IsCursorAnchor(group.anchor)) then
        self:ClearCursorAnchorLayoutPreview()
        return
    end

    local preview = EnsureCursorAnchorLayoutPreview(self)
    local frame = preview.frame
    local previousActiveGroupIds = preview.activeGroupIds
    local activeGroupIds = BuildCursorAnchorLayoutPreviewGroupMap(self)
    preview.selectedGroupId = groupId
    preview.activeGroupIds = activeGroupIds
    if not preview.hasCustomPosition and not preview.hasDefaultPosition then
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, CURSOR_LAYOUT_PREVIEW_TOP_OFFSET)
        preview.hasDefaultPosition = true
    end
    if ST.SetRuntimeInfoButtonShown then
        ST.SetRuntimeInfoButtonShown(preview.helpButton, true)
    end
    if preview.resetButton then
        preview.resetButton:Show()
    end
    frame:Show()
    ApplyCursorAnchorLayoutPreviewGroupStates(self, previousActiveGroupIds, activeGroupIds)
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    self:UpdateCursorAnchoredFrames()
end

function CooldownCompanion:ClearCursorAnchorLayoutPreview()
    local preview = self._cursorAnchorLayoutPreview
    if not preview then
        return
    end

    local activeGroupIds = preview.activeGroupIds
    preview.selectedGroupId = nil
    preview.activeGroupIds = nil
    preview.draggedGroupId = nil
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

function CooldownCompanion:UpdateCursorAnchoredFrames()
    local profile = self.db and self.db.profile
    local groups = profile and profile.groups
    if not groups then
        return
    end

    local cursorX, cursorY = GetCursorPositionInUIParentSpace(self)
    if not (cursorX and cursorY) then
        cursorX, cursorY = GetFallbackCursorPosition(self)
    end

    local preview = self._cursorAnchorLayoutPreview
    local draggedGroupId = preview and preview.draggedGroupId or nil

    for groupId, group in pairs(groups) do
        if IsCursorAnchor(group.anchor)
            and self:CanGroupUseCursorAnchor(group) then
            local frame = self.groupFrames and self.groupFrames[groupId] or nil
            if frame and frame:IsShown() and not GroupIdsEqual(draggedGroupId, groupId) then
                local previewX, previewY = GetCursorAnchorLayoutPreviewPosition(self, groupId)
                local anchorX = previewX or cursorX
                local anchorY = previewY or cursorY
                ApplyCursorAnchorPosition(self, frame, group.anchor, anchorX, anchorY)
                local host = GetCursorAnchoredStandaloneHost(frame, group)
                if host and host:IsShown() then
                    ApplyCursorAnchorPosition(self, host, group.anchor, anchorX, anchorY)
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
    if groups and self.groupFrames then
        for groupId, group in pairs(groups) do
            local frame = self.groupFrames[groupId]
            if IsCursorAnchor(group.anchor)
                and self:CanGroupUseCursorAnchor(group)
                and frame
                and frame:IsShown() then
                active = true
                break
            end
        end
    end

    if active then
        self._cursorAnchorTicker:SetScript("OnUpdate", function()
            CooldownCompanion:UpdateCursorAnchoredFrames()
        end)
        self._cursorAnchorTicker:Show()
    else
        self._cursorAnchorTicker:SetScript("OnUpdate", nil)
        self._cursorAnchorTicker:Hide()
    end
end

local function ShouldShowGroupFrameForRuntimeOrPreview(addon, groupId, group)
    if addon:IsGroupEligibleForConfigPreview(groupId, {
        group = group,
    }) then
        return true
    end

    if addon.IsGroupSuppressedForOtherClassBrowse
        and addon:IsGroupSuppressedForOtherClassBrowse(groupId, group) then
        return false
    end

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
    frame.dragHelpButton = CreatePanelDragHelpButton(frame, groupId)

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

    local isCursorAnchored = IsCursorAnchor(group.anchor)
    local hasDragEntry = self:IsRotationAssistantGroup(group) or #group.buttons > 0
    self:SetGroupDragControlsShown(frame, (not isLocked) and hasDragEntry and not isTextureMode and not isCursorAnchored)

    -- Drag scripts (check lock state at drag time)
    frame:SetScript("OnDragStart", function(self)
        local locked = GetContainerState(self.groupId)
        local previewActive, selectedInContainer, containerId = GetContainerPreviewSelectionState(self.groupId)
        local dragGroup = CooldownCompanion.db.profile.groups[self.groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
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
        elseif not locked then
            self._dragCancelPending = nil
            self._dragInProgress = true
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        local dragGroup = CooldownCompanion.db.profile.groups[self.groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
            local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
            EndCursorAnchorLayoutPreviewPanelDrag(CooldownCompanion, self, self.groupId, cancelSave)
            return
        end

        local _, selectedInContainer, containerId = GetContainerPreviewSelectionState(self.groupId)
        local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
        self._dragCancelPending = nil
        self._dragInProgress = nil
        if not (InCombatLockdown() and self:IsProtected()) then
            self:StopMovingOrSizing()
        end
        if selectedInContainer and containerId and CooldownCompanion.StopContainerMemberPreviewTracking then
            CooldownCompanion:StopContainerMemberPreviewTracking(containerId, self.groupId)
        end
        if cancelSave then
            return
        end
        CooldownCompanion:SaveGroupPosition(self.groupId)
    end)

    -- Also allow dragging from the handle
    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        local locked = GetContainerState(groupId)
        local previewActive, selectedInContainer, containerId = GetContainerPreviewSelectionState(groupId)
        local dragGroup = CooldownCompanion.db.profile.groups[groupId]
        if dragGroup and IsCursorAnchor(dragGroup.anchor) then
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
        elseif not locked then
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
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
        if selectedInContainer and containerId and CooldownCompanion.StopContainerMemberPreviewTracking then
            CooldownCompanion:StopContainerMemberPreviewTracking(containerId, groupId)
        end
        if cancelSave then
            return
        end
        CooldownCompanion:SaveGroupPosition(groupId)
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
    if group.masqueEnabled and self.Masque then
        self:CreateMasqueGroup(groupId)
    end

    -- Create buttons
    self:PopulateGroupButtons(groupId)
    
    -- Show/hide based on runtime activity, plus selected config previews.
    if ShouldShowGroupFrameForRuntimeOrPreview(self, groupId, group) then
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
            frame:SetPoint(anchor.point, relativeFrame, anchor.relativePoint, anchor.x, anchor.y)
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
    elseif ST.IsGroupConfigSelected(frame.groupId) then
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
            -- Config-selected: store natural alpha for further downstream chains, force own frame to full
            if ST.IsGroupConfigSelected(frame.groupId) then
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

function CooldownCompanion:SaveGroupPosition(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end
    if IsCursorAnchor(group.anchor) then
        return
    end

    -- Get the screen-space center of our frame
    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()

    -- Determine the reference frame and its dimensions
    local relativeTo = group.anchor.relativeTo
    local previousRelativeTo = relativeTo
    local relFrame
    local anchorState
    if relativeTo and relativeTo ~= "UIParent" then
        relFrame, anchorState = ResolveSafeAnchorTarget(self, groupId, "group", relativeTo)
    end
    if anchorState == "unsafe" then
        self:AnchorGroupFrame(frame, group.anchor)
        return
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
        w = style.textWidth or 200
        if GetEffectiveTextHeight then
            local maxHeight = GetEffectiveTextHeight(style, style.textFormat or "{name}  {status}")
            for sourceIndex, buttonData in ipairs(group.buttons or {}) do
                if IsSourceButtonInPreviewScope(CooldownCompanion, groupId, sourceIndex, buttonUsabilityOptions)
                    and CooldownCompanion:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
                    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(style, buttonData)
                    local fmt = buttonData.textFormat or effectiveStyle.textFormat or "{name}  {status}"
                    local buttonHeight = GetEffectiveTextHeight(effectiveStyle, fmt)
                    w = math_max(w, effectiveStyle.textWidth or 200)
                    maxHeight = math_max(maxHeight, buttonHeight)
                end
            end
            h = maxHeight
        else
            h = style.textHeight or 20
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
        local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT") and "BOTTOM" or "TOP"
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
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local buttonsPerRow = style.buttonsPerRow or 12
    local isTriggerMode = group.displayMode == "trigger"
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local visibleIndex = 0

    for _, button in ipairs(frame.buttons) do
        visibleIndex = visibleIndex + 1
        ClearButtonCompactSlotCache(button)
        button:ClearAllPoints()
        if isTriggerMode then
            button:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            local row, col
            if orientation == "horizontal" then
                row = math_floor((visibleIndex - 1) / buttonsPerRow)
                col = (visibleIndex - 1) % buttonsPerRow
            else
                col = math_floor((visibleIndex - 1) / buttonsPerRow)
                row = (visibleIndex - 1) % buttonsPerRow
            end
            button:SetPoint(growthAnchor, frame, growthAnchor, xMul * col * (buttonWidth + spacing), yMul * (row * (buttonHeight + spacing) + headerHeight))
        end
    end

    frame.visibleButtonCount = isTriggerMode and (visibleIndex > 0 and 1 or 0) or visibleIndex
    if group.parentContainerId and not group.compactLayout and self.GetGroupLayoutButtonCount then
        frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group, {
            buttonUsabilityOptions = buttonSizingOptions,
        })
    else
        frame.layoutButtonCount = nil
    end
    frame._layoutDirty = false
    frame._lastVisibleCount = visibleIndex
end

local function FinishGroupButtonRefresh(self, groupId, frame, group)
    -- Resize the frame to fit visible buttons
    self:ResizeGroupFrame(groupId)

    -- Reset the sized flag so the next ResizeGroupFrame call skips compact
    -- anchor compensation and treats the current size as a baseline.
    frame._hasBeenSized = false

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    if self.ApplyConfigPreviewsToGroup then
        self:ApplyConfigPreviewsToGroup(groupId)
    end

    -- Initial cooldown update
    frame:UpdateCooldowns()

    -- Compact mode: apply reflow immediately so newly rebuilt buttons don't
    -- briefly appear before the next ticker-driven layout pass.
    if group.compactLayout then
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
    for sourceIndex, buttonData in ipairs(sourceButtons) do
        if IsSourceButtonInPreviewScope(self, groupId, sourceIndex, buttonUsabilityOptions)
            and IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions) then
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

    -- Create new buttons (skip untalented spells)
    for i, buttonData in ipairs(sourceButtons) do
        if IsSourceButtonInPreviewScope(self, groupId, i, buttonUsabilityOptions)
            and IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions) then
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

    ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    FinishGroupButtonRefresh(self, groupId, frame, group)
    -- D3: button population changed — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("populate")
    -- Aura slots bind to materialized buttons: re-run the (coalesced,
    -- OOC-deferred) rebind pass whenever population changes.
    self:RequestAuraRebind("populate")
    -- _hasBeenSized is now true if the compact resize ran (set by
    -- ResizeGroupFrame), or still false if all buttons were visible and no
    -- compact resize was needed.  When compactLayout is off, it stays false
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
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local buttonsPerRow = style.buttonsPerRow or 12
    local numButtons = frame.visibleButtonCount
        or (self:IsRotationAssistantGroup(group) and 1)
        or #group.buttons
    if group.parentContainerId and not group.compactLayout and frame.layoutButtonCount then
        numButtons = math_max(numButtons, frame.layoutButtonCount)
    end

    local targetWidth, targetHeight
    local oldWidth, oldHeight = frame:GetSize()

    if numButtons == 0 then
        targetWidth, targetHeight = buttonWidth, buttonHeight
    else
        local rows, cols
        if orientation == "horizontal" then
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

    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)
    local fixedPoint = group.compactLayout and GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, style.growthOrigin) or nil
    local canCompensateAnchor = frame._hasBeenSized and oldWidth > 0 and oldHeight > 0
    if fixedPoint and canCompensateAnchor then
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
    frame._sizeDirty = nil
    return true
end

-- Compact layout reflow: reposition visible buttons to fill gaps left by hidden ones.
-- Only runs when compactLayout is enabled and _layoutDirty is true.
function CooldownCompanion:UpdateGroupLayout(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    if not frame or not group then return end

    if not group.compactLayout then
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
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
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
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    for visibleIndex, button in ipairs(visibleButtons) do
        local row, col = GetCompactSlotForIndex(
            visibleIndex,
            visibleCount,
            buttonsPerRow,
            orientation,
            compactGrowthDirection
        )
        local x = xMul * col * (buttonWidth + spacing)
        local y = yMul * (row * (buttonHeight + spacing) + headerH)
        if button._compactSlotAnchor ~= growthAnchor
            or button._compactSlotX ~= x
            or button._compactSlotY ~= y then
            button:ClearAllPoints()
            button:SetPoint(growthAnchor, frame, growthAnchor, x, y)
            button._compactSlotAnchor = growthAnchor
            button._compactSlotX = x
            button._compactSlotY = y
        end
    end

    if frame.visibleButtonCount ~= visibleCount then
        frame.visibleButtonCount = visibleCount
        self:ResizeGroupFrame(groupId)
    end

    frame._layoutDirty = false
end

function CooldownCompanion:RefreshGroupFrame(groupId)
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
            if (group.displayMode == nil or group.displayMode == "icons") and group.masqueEnabled then
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

        self:PopulateGroupButtons(groupId)
    end

    -- Resolve locked/alpha from container
    local isLocked, baseAlpha = GetContainerState(groupId)

    -- Update drag handle text and lock state
    local hasButtons = self:IsRotationAssistantGroup(group) or #group.buttons > 0
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    local isCursorAnchored = IsCursorAnchor(group.anchor)
    local isCursorLayoutPreviewSelected = isCursorAnchored
        and IsCursorAnchorLayoutPreviewSelected(self, groupId)
        or false
    local containerPreviewActive = group.parentContainerId and self:IsContainerUnlockPreviewActive(group.parentContainerId)
    local selectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)
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
                    and ((containerPreviewActive and selectedInContainer) or (not containerPreviewActive and not isLocked))
                )
            )
    )
    self:UpdateGroupClickthrough(groupId)

    -- Update visibility: runtime-active groups show normally; selected config
    -- previews can also show without becoming runtime-visible.
    local isActive = ShouldShowGroupFrameForRuntimeOrPreview(CooldownCompanion, groupId, group)
    if isActive then
        if InCombatLockdown() and frame:IsProtected() then
            if not frame:IsShown() then
                self._pendingVisibilityRefresh = true
            end
        else
            frame:Show()
        end
        -- Force 100% alpha while unlocked for easier positioning
        if IsCursorAnchorLayoutPreviewGroupActive(self, groupId) or containerPreviewActive or not isLocked then
            frame:SetAlpha(1)
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
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    if InCombatLockdown() and frame:IsProtected() then
        self._pendingFullRefresh = true
        return
    end

    local entries, buttonUsabilityOptions = GetStyleUpdateEntries(self, groupId, frame, group)
    if not entries then
        self:PopulateGroupButtons(groupId)
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
    local isCursorLayoutPreviewSelected = isCursorAnchored
        and IsCursorAnchorLayoutPreviewSelected(self, groupId)
        or false
    local containerPreviewActive = group.parentContainerId and self:IsContainerUnlockPreviewActive(group.parentContainerId)
    local isSelectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)

    SyncGroupControlLevels(
        frame,
        (isCursorLayoutPreviewSelected or (isSelectedInContainer and not isCursorAnchored)) and not isTextureMode
    )

    if isCursorLayoutPreviewSelected and not isTextureMode then
        SetFrameClickThrough(frame, false, false)
        frame:RegisterForDrag("LeftButton")
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

    if containerPreviewActive then
        SetFrameClickThrough(frame, true, true)
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
        if frame.dragHandle then
            SetFrameClickThrough(frame.dragHandle, false, false)
            frame.dragHandle:EnableMouse(true)
            frame.dragHandle:RegisterForDrag("LeftButton")
            frame.dragHandle:SetScript("OnMouseUp", function(_, btn)
                if btn == "MiddleButton" then
                    local g = CooldownCompanion.db.profile.groups[groupId]
                    if g then
                        -- Lock this specific group/panel
                        g.locked = nil
                        CooldownCompanion:RefreshGroupFrame(groupId)
                        CooldownCompanion:RefreshConfigPanel()
                        CooldownCompanion:Print(g.name .. " locked.")
                    end
                end
            end)
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
local CONTAINER_WRAPPER_BORDER_SIZE = 2
local CONTAINER_WRAPPER_LABEL_OFFSET = 2
local CONTAINER_WRAPPER_HEADER_HEIGHT = 27
local CONTAINER_WRAPPER_HEADER_FONT_SIZE = 14
local CONTAINER_WRAPPER_HEADER_GAP = 4
local CONTAINER_PANEL_LABEL_HEIGHT = 15
local CONTAINER_PANEL_LABEL_MIN_WIDTH = 70
local CONTAINER_MEMBER_DRAG_REFRESH_INTERVAL = 0.05
local CONTAINER_WRAPPER_FALLBACK_WIDTH = 120
local CONTAINER_WRAPPER_FALLBACK_HEIGHT = 18

local function GetRelativeFrameRect(referenceFrame, targetFrame)
    if not (referenceFrame and targetFrame and referenceFrame.GetCenter and targetFrame.GetCenter) then
        return nil
    end

    local refX, refY = referenceFrame:GetCenter()
    local targetX, targetY = targetFrame:GetCenter()
    local width, height = GetFrameSizeInUIParentSpace(targetFrame)
    if not (refX and refY and targetX and targetY and width and height) then
        return nil
    end

    return {
        left = targetX - (width / 2) - refX,
        right = targetX + (width / 2) - refX,
        bottom = targetY - (height / 2) - refY,
        top = targetY + (height / 2) - refY,
        centerX = targetX - refX,
        centerY = targetY - refY,
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
    overlay:SetBackdropColor(0.2, 0.8, 1, 0)
    overlay:RegisterForDrag("LeftButton")
    overlay:EnableMouse(true)

    overlay:SetScript("OnEnter", function(self)
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[self.containerId]
        if not (self.containerId and self.groupId and containerFrame) then
            return
        end
        if containerFrame._containerHoveredGroupId ~= self.groupId then
            containerFrame._containerHoveredGroupId = self.groupId
            CooldownCompanion:RefreshContainerWrapper(self.containerId)
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
        CooldownCompanion:SelectContainerPanel(self.containerId, self.groupId)
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
        overlay:Hide()
    end
end

local function EnsureContainerWrapperBorder(wrapper, r, g, b, a)
    if not wrapper then
        return
    end

    local borderTextures = wrapper._containerWrapperBorderTextures
    if not borderTextures then
        borderTextures = {}
        for i = 1, 4 do
            borderTextures[i] = wrapper:CreateTexture(nil, "BORDER")
        end
        wrapper._containerWrapperBorderTextures = borderTextures
    end

    if wrapper.borderTextures then
        for _, texture in ipairs(wrapper.borderTextures) do
            texture:Hide()
        end
    end

    local size = CONTAINER_WRAPPER_BORDER_SIZE
    local top = borderTextures[1]
    local bottom = borderTextures[2]
    local left = borderTextures[3]
    local right = borderTextures[4]

    for _, texture in ipairs(borderTextures) do
        texture:SetColorTexture(r, g, b, a)
        texture:Show()
    end

    PixelUtil.SetPoint(top, "BOTTOMLEFT", wrapper, "TOPLEFT", -size, 0)
    PixelUtil.SetPoint(top, "BOTTOMRIGHT", wrapper, "TOPRIGHT", size, 0)
    PixelUtil.SetHeight(top, size, 1)

    PixelUtil.SetPoint(bottom, "TOPLEFT", wrapper, "BOTTOMLEFT", -size, 0)
    PixelUtil.SetPoint(bottom, "TOPRIGHT", wrapper, "BOTTOMRIGHT", size, 0)
    PixelUtil.SetHeight(bottom, size, 1)

    PixelUtil.SetPoint(left, "TOPRIGHT", wrapper, "TOPLEFT", 0, size)
    PixelUtil.SetPoint(left, "BOTTOMRIGHT", wrapper, "BOTTOMLEFT", 0, -size)
    PixelUtil.SetWidth(left, size, 1)

    PixelUtil.SetPoint(right, "TOPLEFT", wrapper, "TOPRIGHT", 0, size)
    PixelUtil.SetPoint(right, "BOTTOMLEFT", wrapper, "BOTTOMRIGHT", 0, -size)
    PixelUtil.SetWidth(right, size, 1)
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
    tracker._elapsed = 0
    tracker:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < CONTAINER_MEMBER_DRAG_REFRESH_INTERVAL then
            return
        end

        self._elapsed = 0
        CooldownCompanion:RefreshContainerWrapper(containerId)
    end)
end

function CooldownCompanion:StopContainerMemberPreviewTracking(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    frame._containerDraggingGroupId = nil
    local tracker = frame._containerMemberDragTracker
    if tracker then
        tracker._elapsed = 0
        tracker:SetScript("OnUpdate", nil)
    end
end

function CooldownCompanion:ClearContainerUnlockState(containerId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then
        return
    end

    frame._containerSelectedGroupId = nil
    frame._containerHoveredGroupId = nil
    self:StopContainerMemberPreviewTracking(containerId)
    HideContainerMemberOverlays(frame)
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
end

function CooldownCompanion:SelectContainerPanel(containerId, groupId)
    local frame = self.containerFrames and self.containerFrames[containerId]
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not (frame and group and group.parentContainerId == containerId) then
        return
    end

    if not self:IsGroupVisibleInUnlockPreview(groupId, {
        group = group,
        checkCharVisibility = true,
    }) then
        self:SelectContainerWrapper(containerId)
        return
    end

    if frame._containerSelectedGroupId == groupId and frame._containerHoveredGroupId == groupId then
        return
    end

    frame._containerSelectedGroupId = groupId
    frame._containerHoveredGroupId = groupId
    self:RefreshContainerWrapper(containerId)
end

function CooldownCompanion:StartContainerPreviewMemberDrag(containerId, groupId)
    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if self._combatForcedLock or not (containerId and group and group.parentContainerId == containerId) then
        return false
    end

    self:SelectContainerPanel(containerId, groupId)
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

local function GetContainerMemberDisplayRect(self, containerFrame, groupId, group)
    local groupFrame = self.groupFrames and self.groupFrames[groupId]
    local rect = nil
    local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(group)

    if isStandaloneDisplay then
        local driverButton = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
        local host = driverButton and driverButton.auraTextureHost or nil
        if host and host:IsShown() then
            rect = GetRelativeFrameRect(containerFrame, host)
        end
    end

    if not rect and not isStandaloneDisplay and groupFrame and groupFrame:IsShown() then
        rect = GetRelativeFrameRect(containerFrame, groupFrame)
    end

    if rect then
        rect.groupId = groupId
        rect.group = group
        rect.label = group.name or ("Panel " .. groupId)
    end

    return rect
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
    HideContainerPanelLabels(frame)
    UpdateContainerWrapperLevels(frame)

    local allPanels = self.GetPanels and self:GetPanels(containerId) or nil
    local suppressedForOtherClassBrowse = self.IsContainerSuppressedForOtherClassBrowse
        and self:IsContainerSuppressedForOtherClassBrowse(containerId, allPanels)
    if self._combatForcedLock
        or container.locked ~= false
        or not self:IsContainerVisibleToCurrentChar(containerId)
        or suppressedForOtherClassBrowse then
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

    local previewPanels = self.GetContainerUnlockPreviewPanels and self:GetContainerUnlockPreviewPanels(containerId, allPanels) or {}
    allPanels = allPanels or previewPanels
    local previewRects = {}
    local previewedGroupIds = {}
    local minLeft, maxRight, minBottom, maxTop = nil, nil, nil, nil

    for _, panelInfo in ipairs(previewPanels) do
        local rect = GetContainerMemberDisplayRect(self, frame, panelInfo.groupId, panelInfo.group)
        if rect then
            previewRects[#previewRects + 1] = rect
            previewedGroupIds[rect.groupId] = true
            minLeft = minLeft and math_min(minLeft, rect.left) or rect.left
            maxRight = maxRight and math_max(maxRight, rect.right) or rect.right
            minBottom = minBottom and math_min(minBottom, rect.bottom) or rect.bottom
            maxTop = maxTop and math_max(maxTop, rect.top) or rect.top
        end
    end

    if frame._containerSelectedGroupId and not previewedGroupIds[frame._containerSelectedGroupId] then
        frame._containerSelectedGroupId = nil
    end
    if frame._containerHoveredGroupId and not previewedGroupIds[frame._containerHoveredGroupId] then
        frame._containerHoveredGroupId = nil
    end

    local selectedGroupId = frame._containerSelectedGroupId
    local hoveredGroupId = frame._containerHoveredGroupId
    local headerWidth = 96

    if header then
        local titleText = header.text or wrapper.text
        if titleText then
            titleText:SetText(container.name or "Group")
            headerWidth = math_max(96, math_floor((titleText:GetStringWidth() or 0) + 24.5))
        end
    end

    if #previewRects == 0 then
        HideContainerMemberOverlays(frame)
        local fallbackWidth = math_max(headerWidth, CONTAINER_WRAPPER_FALLBACK_WIDTH)
        local fallbackHalfWidth = RoundPreviewOffset(fallbackWidth / 2)
        local fallbackHalfHeight = RoundPreviewOffset(CONTAINER_WRAPPER_FALLBACK_HEIGHT / 2)

        wrapper:ClearAllPoints()
        wrapper:SetPoint("BOTTOMLEFT", frame, "CENTER", -fallbackHalfWidth, -fallbackHalfHeight)
        wrapper:SetPoint("TOPRIGHT", frame, "CENTER", fallbackHalfWidth, fallbackHalfHeight)
        wrapper:SetShown(true)
        if header then
            header:SetWidth(headerWidth)
            header:Show()
        end
        if frame.coordLabel then
            frame.coordLabel:SetShown(true)
        end
        if frame.nudger then
            frame.nudger:SetShown(true)
        end
        frame._isRefreshingContainerWrapper = nil
        return
    end

    local padding = CONTAINER_WRAPPER_PADDING
    wrapper:ClearAllPoints()
    wrapper:SetPoint("BOTTOMLEFT", frame, "CENTER", RoundPreviewOffset(minLeft - padding), RoundPreviewOffset(minBottom - padding))
    wrapper:SetPoint("TOPRIGHT", frame, "CENTER", RoundPreviewOffset(maxRight + padding), RoundPreviewOffset(maxTop + padding))
    wrapper:SetShown(true)

    if header then
        header:SetWidth(headerWidth)
        header:Show()
    end

    if frame.coordLabel then
        frame.coordLabel:SetShown(selectedGroupId == nil)
    end
    if frame.nudger then
        frame.nudger:SetShown(selectedGroupId == nil)
    end

    local usedOverlayIndices = {}
    for labelIndex, rect in ipairs(previewRects) do
        local isSelected = selectedGroupId == rect.groupId
        local isHovered = hoveredGroupId == rect.groupId
        local isStandaloneDisplay = CooldownCompanion:IsStandaloneTexturePanelGroup(rect.group)

        local overlay = EnsureContainerMemberOverlay(frame, labelIndex)
        usedOverlayIndices[labelIndex] = true
        overlay.containerId = containerId
        overlay.groupId = rect.groupId
        overlay:ClearAllPoints()
        overlay:SetPoint("BOTTOMLEFT", frame, "CENTER", RoundPreviewOffset(rect.left), RoundPreviewOffset(rect.bottom))
        overlay:SetPoint("TOPRIGHT", frame, "CENTER", RoundPreviewOffset(rect.right), RoundPreviewOffset(rect.top))
        overlay:SetShown(true)

        local fillAlpha = 0
        local borderAlpha = 0
        if not isStandaloneDisplay then
            if isSelected then
                fillAlpha = 0.12
                borderAlpha = 0.95
            elseif isHovered then
                fillAlpha = 0.08
                borderAlpha = 0.75
            end
        end
        overlay:SetBackdropColor(0.15, 0.45, 0.65, fillAlpha)
        EnsureContainerWrapperBorder(overlay, 0.2, 0.8, 1, borderAlpha)

        local showLabel = hoveredGroupId ~= nil and isHovered and not isSelected

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

    if frame._containerMemberOverlays then
        for overlayIndex, overlay in pairs(frame._containerMemberOverlays) do
            if not usedOverlayIndices[overlayIndex] then
                overlay._dragging = nil
                overlay._suppressClick = nil
                overlay.groupId = nil
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
            SyncGroupControlLevels(groupFrame, isSelected and not isCursorAnchored)
            if self:IsContainerUnlockPreviewActive(containerId) then
                self:SetGroupDragControlsShown(groupFrame, isSelected and not isCursorAnchored)
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
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            CooldownCompanion:SaveContainerPosition(containerId)
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
            DoNudge()
        end)

        btn:SetScript("OnMouseUp", function(self)
            CooldownCompanion:SaveContainerPosition(containerId)
        end)
    end

    return nudger
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
    EnsureContainerWrapperBorder(frame.dragHandle, 0.2, 0.8, 1, 0.95)

    frame.dragHandle.header = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    frame.dragHandle.header:SetHeight(CONTAINER_WRAPPER_HEADER_HEIGHT)
    frame.dragHandle.header:SetPoint("BOTTOM", frame.dragHandle, "TOP", 0, CONTAINER_WRAPPER_HEADER_GAP)
    frame.dragHandle.header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.dragHandle.header:SetBackdropColor(0.15, 0.35, 0.55, 0.92)
    CreatePixelBorders(frame.dragHandle.header)

    frame.dragHandle.text = frame.dragHandle.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.dragHandle.text:SetPoint("CENTER")
    do
        local fontPath, _, fontFlags = frame.dragHandle.text:GetFont()
        if fontPath then
            frame.dragHandle.text:SetFont(fontPath, CONTAINER_WRAPPER_HEADER_FONT_SIZE, fontFlags)
        end
    end
    frame.dragHandle.text:SetText(container.name)
    frame.dragHandle.text:SetTextColor(1, 1, 1, 1)
    frame.dragHandle.header.text = frame.dragHandle.text

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

    -- Start hidden (drag handle shows only when unlocked)
    if container.locked then
        frame.dragHandle:Hide()
    end

    -- Drag scripts
    frame:SetScript("OnDragStart", function(self)
        local c = CooldownCompanion.db.profile.groupContainers[self.containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(self.containerId) then
            CooldownCompanion:SelectContainerWrapper(self.containerId)
            self._dragCancelPending = nil
            self._dragInProgress = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        local cancelSave = self._dragCancelPending == true or CooldownCompanion._combatForcedLock
        self._dragCancelPending = nil
        self._dragInProgress = nil
        if not (InCombatLockdown() and self:IsProtected()) then
            self:StopMovingOrSizing()
        end
        if cancelSave then
            return
        end
        CooldownCompanion:SaveContainerPosition(self.containerId)
    end)

    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        local c = CooldownCompanion.db.profile.groupContainers[containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(containerId) then
            frame.dragHandle._suppressClick = true
            CooldownCompanion:SelectContainerWrapper(containerId)
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
        end
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
        if cancelSave then
            return
        end
        CooldownCompanion:SaveContainerPosition(containerId)
    end)
    frame.dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        if frame.dragHandle._suppressClick then
            frame.dragHandle._suppressClick = nil
            return
        end
        CooldownCompanion:SelectContainerWrapper(containerId)
    end)

    frame.dragHandle.header:EnableMouse(true)
    frame.dragHandle.header:RegisterForDrag("LeftButton")
    frame.dragHandle.header:SetScript("OnDragStart", function()
        local c = CooldownCompanion.db.profile.groupContainers[containerId]
        if c and not CooldownCompanion._combatForcedLock and CooldownCompanion:IsContainerUnlockPreviewActive(containerId) then
            frame.dragHandle.header._suppressClick = true
            CooldownCompanion:SelectContainerWrapper(containerId)
            frame._dragCancelPending = nil
            frame._dragInProgress = true
            frame:StartMoving()
        end
    end)
    frame.dragHandle.header:SetScript("OnDragStop", function()
        local cancelSave = frame._dragCancelPending == true or CooldownCompanion._combatForcedLock
        frame._dragCancelPending = nil
        frame._dragInProgress = nil
        if not (InCombatLockdown() and frame:IsProtected()) then
            frame:StopMovingOrSizing()
        end
        if cancelSave then
            return
        end
        CooldownCompanion:SaveContainerPosition(containerId)
    end)

    -- Middle-click to lock
    frame.dragHandle.header:SetScript("OnMouseUp", function(_, btn)
        if btn == "MiddleButton" then
            local c = CooldownCompanion.db.profile.groupContainers[containerId]
            if c then
                if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
                    CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId)
                end
                c.locked = true
                CooldownCompanion:UpdateContainerDragHandle(containerId, true)
                CooldownCompanion:RefreshContainerPanels(containerId)
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:Print(c.name .. " locked.")
            end
            return
        end

        if btn == "LeftButton" then
            if frame.dragHandle.header._suppressClick then
                frame.dragHandle.header._suppressClick = nil
                return
            end
            CooldownCompanion:SelectContainerWrapper(containerId)
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
                frame:SetPoint(anchor.point or "CENTER", relativeFrame, anchor.relativePoint or "CENTER", rawX, rawY)
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

function CooldownCompanion:SaveContainerPosition(containerId)
    local frame = self.containerFrames[containerId]
    local container = self.db.profile.groupContainers[containerId]
    if not frame or not container then return end
    container.anchor = self:NormalizeContainerAnchor(container.anchor)
    local oldX = tonumber(container.anchor.x) or 0
    local oldY = tonumber(container.anchor.y) or 0

    local cx, cy = frame:GetCenter()
    if not cx then return end
    local ucx, ucy = UIParent:GetCenter()
    if not ucx then return end

    local newX = math_floor((cx - ucx) * 10 + 0.5) / 10
    local newY = math_floor((cy - ucy) * 10 + 0.5) / 10

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
