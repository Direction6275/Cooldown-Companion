--[[
    CooldownCompanion - GroupFrameShared
    Shared panel state, coordinate geometry, compact-layout math, and anchor resolution.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local math_floor = math.floor
local math_min = math.min
local issecretvalue = issecretvalue
local select = select

local GF = {}
ST._GroupFrame = GF

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
-- ST so the config preview lays out with the exact same rule. The do-block
-- keeps the edge lookup private to that helper.
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

-- Nudger constants
local NUDGE_BTN_SIZE = 12

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

ComputeContainerFrameCoordinates = function(frame)
    local cx, cy = frame:GetCenter()
    if not cx then return nil, nil end
    local ucx, ucy = UIParent:GetCenter()
    if not ucx then return nil, nil end

    local newX = math_floor((cx - ucx) * 10 + 0.5) / 10
    local newY = math_floor((cy - ucy) * 10 + 0.5) / 10
    return newX, newY
end

-- Private helpers consumed by later GroupFrame files.
GF.GetFrameRectInUIParentSpace = GetFrameRectInUIParentSpace
GF.GetContainerState = GetContainerState
GF.IsSecretValue = IsSecretValue
GF.NUDGE_BTN_SIZE = NUDGE_BTN_SIZE
GF.IsCursorAnchor = IsCursorAnchor
GF.IsCursorAnchorLayoutPreviewSelected = IsCursorAnchorLayoutPreviewSelected
GF.UpdateCoordLabel = UpdateCoordLabel
GF.CURSOR_ANCHOR_X = CURSOR_ANCHOR_X
GF.CURSOR_ANCHOR_Y = CURSOR_ANCHOR_Y
GF.GetGroupButtonSizingOptions = GetGroupButtonSizingOptions
GF.NormalizeCompactGrowthDirection = NormalizeCompactGrowthDirection
GF.GetCompactAnchorFixedPoint = GetCompactAnchorFixedPoint
GF.GetContainerPreviewSelectionState = GetContainerPreviewSelectionState
GF.ApplySectionSelectionTint = ApplySectionSelectionTint
GF.SetExternalAnchorAlphaSyncActive = SetExternalAnchorAlphaSyncActive
GF.CURSOR_ANCHOR_POINT = CURSOR_ANCHOR_POINT
GF.IsCursorAnchorLayoutPreviewGroupActive = IsCursorAnchorLayoutPreviewGroupActive
GF.PreviewMapContains = PreviewMapContains
GF.ApplyCurrentAlphaIfPresent = ApplyCurrentAlphaIfPresent
GF.GetFrameSizeInUIParentSpace = GetFrameSizeInUIParentSpace
GF.CURSOR_ANCHOR_TARGET = CURSOR_ANCHOR_TARGET
GF.CURSOR_ANCHOR_RELATIVE_POINT = CURSOR_ANCHOR_RELATIVE_POINT
GF.ComputeGroupFrameCoordinates = ComputeGroupFrameCoordinates
GF.StartCoordinateDragUpdates = StartCoordinateDragUpdates
GF.GroupIdsEqual = GroupIdsEqual
GF.StopCoordinateDragUpdates = StopCoordinateDragUpdates
GF.CURSOR_LAYOUT_PREVIEW_DEFAULT_Y = CURSOR_LAYOUT_PREVIEW_DEFAULT_Y
GF.CURSOR_LAYOUT_PREVIEW_SIZE = CURSOR_LAYOUT_PREVIEW_SIZE
GF.CURSOR_LAYOUT_PREVIEW_ATLAS = CURSOR_LAYOUT_PREVIEW_ATLAS
GF.CURSOR_LAYOUT_PREVIEW_TINT = CURSOR_LAYOUT_PREVIEW_TINT
GF.CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH = CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH
GF.CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT = CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT
GF.BuildDefaultCursorAnchor = BuildDefaultCursorAnchor
GF.ResolveSafeAnchorTarget = ResolveSafeAnchorTarget
GF.GetPanelContainerFrameName = GetPanelContainerFrameName
GF.ShouldSyncAnchorAlpha = ShouldSyncAnchorAlpha
GF.ApplyGroupOwnAlpha = ApplyGroupOwnAlpha
GF.GetAnchorInheritedAlpha = GetAnchorInheritedAlpha
GF.ParseAddonAnchorFrameName = ParseAddonAnchorFrameName
GF.WouldFrameDependencyCreateCircularAnchor = WouldFrameDependencyCreateCircularAnchor
GF.GetGrowthMultipliers = GetGrowthMultipliers
GF.PropagateFrameStrata = PropagateFrameStrata
GF.GetCompactSlotForIndex = GetCompactSlotForIndex
GF.RoundPreviewOffset = RoundPreviewOffset
GF.ComputeContainerFrameCoordinates = ComputeContainerFrameCoordinates
GF.ApplyUnsafeAnchorVisualFallback = ApplyUnsafeAnchorVisualFallback
GF.GetUnlockedPanelAlpha = GetUnlockedPanelAlpha
