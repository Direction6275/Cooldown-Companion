--[[
    CooldownCompanion - GroupFrame
    Panel frame creation, refresh lifecycle, click-through, and anchor pick indicators.

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
local SetFrameClickThrough = ST.SetFrameClickThrough
local CancelCoordinateEdit = ST.CancelCoordinateEdit
local CreateEditableCoordLabel = ST.CreateEditableCoordLabel
local CreatePixelBorders = ST.CreatePixelBorders

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local GetContainerState = GF.GetContainerState
local IsCursorAnchor = GF.IsCursorAnchor
local CURSOR_ANCHOR_X = GF.CURSOR_ANCHOR_X
local CURSOR_ANCHOR_Y = GF.CURSOR_ANCHOR_Y
local UpdateCoordLabel = GF.UpdateCoordLabel
local GetContainerPreviewSelectionState = GF.GetContainerPreviewSelectionState
local StopCoordinateDragUpdates = GF.StopCoordinateDragUpdates
local ApplyCurrentAlphaIfPresent = GF.ApplyCurrentAlphaIfPresent
local IsCursorAnchorLayoutPreviewSelected = GF.IsCursorAnchorLayoutPreviewSelected
local IsCursorAnchorLayoutPreviewGroupActive = GF.IsCursorAnchorLayoutPreviewGroupActive
local GetUnlockedPanelAlpha = GF.GetUnlockedPanelAlpha

-- GroupFrameMovers.lua
local CreateNudger = GF.CreateNudger
local RefreshConfigPanelIfShown = GF.RefreshConfigPanelIfShown
local CanUsePanelResizeInteractions = GF.CanUsePanelResizeInteractions
local SyncGroupControlLevels = GF.SyncGroupControlLevels
local OnUnlockedPanelMouseWheel = GF.OnUnlockedPanelMouseWheel

-- GroupFrameCursorAnchor.lua
local ApplyPanelCoordinates = GF.ApplyPanelCoordinates
local BeginCursorAnchorLayoutPreviewPanelDrag = GF.BeginCursorAnchorLayoutPreviewPanelDrag
local StartGroupCoordinateDragUpdates = GF.StartGroupCoordinateDragUpdates
local EndCursorAnchorLayoutPreviewPanelDrag = GF.EndCursorAnchorLayoutPreviewPanelDrag

-- GroupFrameDragSnap.lua
local BeginSelfExcludedDragSnapSession = GF.BeginSelfExcludedDragSnapSession
local ApplyEndedDragSnapSession = GF.ApplyEndedDragSnapSession

-- GroupFrameButtonPool.lua
local ForEachGroupButtonFrame = GF.ForEachGroupButtonFrame

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
    self:RefreshCursorAnchorLayoutPreview(groupId)
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
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
