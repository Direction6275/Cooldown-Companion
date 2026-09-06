--[[
    CooldownCompanion - ContainerFrame
    Group container frames, wrapper geometry, member selection, and movement.

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
local InCombatLockdown = InCombatLockdown
local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel
local CreatePixelBorders = ST.CreatePixelBorders

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local GetFrameSizeInUIParentSpace = GF.GetFrameSizeInUIParentSpace
local IsCursorAnchorLayoutPreviewGroupActive = GF.IsCursorAnchorLayoutPreviewGroupActive
local UpdateCoordLabel = GF.UpdateCoordLabel
local ApplySectionSelectionTint = GF.ApplySectionSelectionTint
local PreviewMapContains = GF.PreviewMapContains
local IsCursorAnchor = GF.IsCursorAnchor
local RoundPreviewOffset = GF.RoundPreviewOffset
local ComputeContainerFrameCoordinates = GF.ComputeContainerFrameCoordinates
local NUDGE_BTN_SIZE = GF.NUDGE_BTN_SIZE
local StartCoordinateDragUpdates = GF.StartCoordinateDragUpdates
local StopCoordinateDragUpdates = GF.StopCoordinateDragUpdates
local ApplyUnsafeAnchorVisualFallback = GF.ApplyUnsafeAnchorVisualFallback

-- GroupFrameCursorAnchor.lua
local PrepareGroupCoordinateDragReference = GF.PrepareGroupCoordinateDragReference
local UpdateGroupDragCoordinate = GF.UpdateGroupDragCoordinate

-- GroupFrameMovers.lua
local SyncGroupControlLevels = GF.SyncGroupControlLevels

-- GroupFrameDragSnap.lua
local BeginSelfExcludedDragSnapSession = GF.BeginSelfExcludedDragSnapSession
local ApplyEndedDragSnapSession = GF.ApplyEndedDragSnapSession

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
    -- A locked parent has no wrapper, but its cursor panel can still be
    -- unlocked independently. Refreshing that wrapper must not deselect the
    -- cursor mover; only explicit hiding or preview teardown owns that state.
    if cursorSelectedGroup and cursorSelectedGroup.parentContainerId == containerId
        and (self._combatForcedLock
            or self:IsArrangeContainerSuppressed(containerId)
            or self:IsContainerArrangeChromeHidden(containerId)
            or not IsCursorAnchorLayoutPreviewGroupActive(self, cursorSelectedGroupId)) then
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
