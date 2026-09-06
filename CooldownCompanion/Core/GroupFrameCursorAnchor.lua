--[[
    CooldownCompanion - GroupFrameCursorAnchor
    Cursor anchoring, Arrange cursor preview, and its drag/ticker lifecycle.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local math_floor = math.floor
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreatePixelBorders = ST.CreatePixelBorders

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local SetExternalAnchorAlphaSyncActive = GF.SetExternalAnchorAlphaSyncActive
local CURSOR_ANCHOR_X = GF.CURSOR_ANCHOR_X
local CURSOR_ANCHOR_Y = GF.CURSOR_ANCHOR_Y
local CURSOR_ANCHOR_POINT = GF.CURSOR_ANCHOR_POINT
local UpdateCoordLabel = GF.UpdateCoordLabel
local IsCursorAnchorLayoutPreviewGroupActive = GF.IsCursorAnchorLayoutPreviewGroupActive
local IsCursorAnchor = GF.IsCursorAnchor
local PreviewMapContains = GF.PreviewMapContains
local IsCursorAnchorLayoutPreviewSelected = GF.IsCursorAnchorLayoutPreviewSelected
local ApplyCurrentAlphaIfPresent = GF.ApplyCurrentAlphaIfPresent
local GetFrameSizeInUIParentSpace = GF.GetFrameSizeInUIParentSpace
local GetAnchorOffset = ST._GetPanelAnchorOffset
local CURSOR_ANCHOR_TARGET = GF.CURSOR_ANCHOR_TARGET
local CURSOR_ANCHOR_RELATIVE_POINT = GF.CURSOR_ANCHOR_RELATIVE_POINT
local ComputeGroupFrameCoordinates = GF.ComputeGroupFrameCoordinates
local StartCoordinateDragUpdates = GF.StartCoordinateDragUpdates
local GroupIdsEqual = GF.GroupIdsEqual
local StopCoordinateDragUpdates = GF.StopCoordinateDragUpdates
local CURSOR_LAYOUT_PREVIEW_DEFAULT_Y = GF.CURSOR_LAYOUT_PREVIEW_DEFAULT_Y
local CURSOR_LAYOUT_PREVIEW_SIZE = GF.CURSOR_LAYOUT_PREVIEW_SIZE
local CURSOR_LAYOUT_PREVIEW_ATLAS = GF.CURSOR_LAYOUT_PREVIEW_ATLAS
local CURSOR_LAYOUT_PREVIEW_TINT = GF.CURSOR_LAYOUT_PREVIEW_TINT
local CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH = GF.CURSOR_LAYOUT_PREVIEW_LABEL_WIDTH
local CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT = GF.CURSOR_LAYOUT_PREVIEW_LABEL_HEIGHT
local BuildDefaultCursorAnchor = GF.BuildDefaultCursorAnchor

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

local function IsCursorAnchorLayoutPreviewEligible(self, groupId, group)
    return group ~= nil
        and not self._combatForcedLock
        and not InCombatLockdown()
        and IsCursorAnchor(group.anchor)
        and (self._arrangeModeActive == true or group.locked == false)
        and not self:IsArrangePanelSuppressed(groupId)
        and not (group.parentContainerId and self:IsArrangeContainerSuppressed(group.parentContainerId))
        and self:CanGroupUseCursorAnchor(group)
        and self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
        })
end

local function BuildCursorAnchorLayoutPreviewGroupMap(self)
    local activeGroupIds = {}
    local profile = self.db and self.db.profile
    for groupId, group in pairs(profile and profile.groups or {}) do
        if IsCursorAnchorLayoutPreviewEligible(self, groupId, group) then
            activeGroupIds[groupId] = true
        end
    end
    return activeGroupIds
end

-- Release the shared mover selection before dropping its cursor membership.
-- A panel changing to another anchor keeps its selection in that mover instead.
local function ClearInactiveCursorPreviewSelection(self, activeGroupIds)
    local selectedGroupId = self._arrangeSelectedPanelId
    local preview = self._cursorAnchorLayoutPreview
    local group = selectedGroupId and self.db.profile.groups[selectedGroupId]
    if selectedGroupId
        and PreviewMapContains(preview and preview.activeGroupIds, selectedGroupId)
        and not PreviewMapContains(activeGroupIds, selectedGroupId)
        and (not group or IsCursorAnchor(group.anchor)) then
        -- The old panel may already be dormant. Do not reapply its active
        -- preview just to deselect it; that would recreate an unloaded frame.
        preview.selectedGroupId = nil
        self:ClearArrangeMoverSelection()
    end
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
    if self._combatForcedLock or InCombatLockdown()
        or not (preview and PreviewMapContains(preview.activeGroupIds, groupId)) then
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

-- Eligibility can disappear during a drag, after the runtime frame was moved
-- to the dormant cache. Cancel that gesture without saving its partial offset.
function CooldownCompanion:CancelCursorAnchorLayoutPreviewDrag()
    local preview = self._cursorAnchorLayoutPreview
    local groupId = preview and preview.draggedGroupId
    if groupId == nil then return end
    local frame = self.groupFrames and self.groupFrames[groupId]
        or self._dormantFrames and self._dormantFrames[groupId]
    local button = frame and frame.buttons and frame.buttons[1]
    local host = button and button.auraTextureHost
    if host and host._cursorAnchorDrag then
        host._cursorAnchorDrag = nil
        host._isDragging = nil
        host._arrangePanelSurfaceDrag = nil
        host._dragCancelPending = true
        if not (InCombatLockdown() and host:IsProtected()) then
            host:StopMovingOrSizing()
        end
        self:EndCursorAnchorLayoutPreviewHostDrag(groupId, true)
        self:EndMoverChromeFade(host)
    else
        EndCursorAnchorLayoutPreviewPanelDrag(self, frame, groupId, true)
    end
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
-- pin-only form: unlocked cursor panels park on the dummy cursor, and clicking
-- or dragging one selects its positioning chrome (SelectArrangeCursorPanel).
-- Only explicit individual unlocks or Arrange Mode can create this preview.
function CooldownCompanion:ShowCursorAnchorLayoutPreview(groupId)
    local activeGroupIds = BuildCursorAnchorLayoutPreviewGroupMap(self)
    local currentPreview = self._cursorAnchorLayoutPreview
    if currentPreview and currentPreview.draggedGroupId
        and not PreviewMapContains(activeGroupIds, currentPreview.draggedGroupId) then
        self:CancelCursorAnchorLayoutPreviewDrag()
    end
    ClearInactiveCursorPreviewSelection(self, activeGroupIds)
    if next(activeGroupIds) == nil then
        self:ClearCursorAnchorLayoutPreview()
        return
    end

    local preview = EnsureCursorAnchorLayoutPreview(self)
    local frame = preview.frame
    local previousActiveGroupIds = preview.activeGroupIds
    preview.selectedGroupId = PreviewMapContains(activeGroupIds, groupId) and groupId or nil
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

-- Runtime refreshes own preview membership, including when no preview exists
-- yet. A one-panel refresh checks only that panel unless membership changed;
-- unchanged refreshes leave selection, staged offsets, and mover chrome alone.
function CooldownCompanion:RefreshCursorAnchorLayoutPreview(groupId)
    local preview = self._cursorAnchorLayoutPreview
    local previous = preview and preview.activeGroupIds
    if groupId ~= nil then
        local group = self.db.profile.groups[groupId]
        if IsCursorAnchorLayoutPreviewEligible(self, groupId, group)
            == PreviewMapContains(previous, groupId) then
            return false
        end
    end

    local current = BuildCursorAnchorLayoutPreviewGroupMap(self)
    local changed = false
    for id in pairs(current) do
        if not PreviewMapContains(previous, id) then changed = true; break end
    end
    if not changed then
        for id in pairs(previous or {}) do
            if not PreviewMapContains(current, id) then changed = true; break end
        end
    end
    if not changed then return false end

    self:ShowCursorAnchorLayoutPreview(preview and preview.selectedGroupId)
    self:RefreshUnlockToolbar()
    return true
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

function CooldownCompanion:ClearCursorAnchorLayoutPreview(force)
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

    -- Config selection and closing settings do not end an explicit unlock.
    -- Combat and lock-all teardown hand panels back to the real cursor.
    if not force and next(BuildCursorAnchorLayoutPreviewGroupMap(self)) ~= nil then
        local selectedGroupId = preview.selectedGroupId
        -- Keep an explicit toolbar selection through the config refresh that
        -- follows a Navigator unlock, including during global Arrange Mode.
        if self._arrangeModeActive and self._arrangeSelectedPanelId ~= selectedGroupId then
            selectedGroupId = nil
        end
        self:ShowCursorAnchorLayoutPreview(selectedGroupId)
        return
    end

    self:CancelCursorAnchorLayoutPreviewDrag()
    ClearInactiveCursorPreviewSelection(self, nil)
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
-- Ticker state and callbacks share this one table.
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

-- Private helpers consumed by later GroupFrame files.
GF.GetCursorAnchorLayoutPreviewPosition = GetCursorAnchorLayoutPreviewPosition
GF.ApplyCursorAnchorPosition = ApplyCursorAnchorPosition
GF.PrepareGroupCoordinateDragReference = PrepareGroupCoordinateDragReference
GF.UpdateGroupDragCoordinate = UpdateGroupDragCoordinate
GF.ApplyPanelCoordinates = ApplyPanelCoordinates
GF.BeginCursorAnchorLayoutPreviewPanelDrag = BeginCursorAnchorLayoutPreviewPanelDrag
GF.StartGroupCoordinateDragUpdates = StartGroupCoordinateDragUpdates
GF.EndCursorAnchorLayoutPreviewPanelDrag = EndCursorAnchorLayoutPreviewPanelDrag
