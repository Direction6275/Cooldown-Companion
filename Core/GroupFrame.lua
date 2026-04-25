--[[
    CooldownCompanion - GroupFrame
    Container frames for groups of buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local pairs = pairs
local ipairs = ipairs
local math_abs = math.abs
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local table_insert = table.insert
local InCombatLockdown = InCombatLockdown

-- Shared click-through and border helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive
local HideGlowStyles = ST._HideGlowStyles

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
-- Panels use their OWN group.locked (nil = locked); alpha comes from the panel itself.
-- Legacy groups (no container) use group.locked and group.baselineAlpha directly.
local function GetContainerState(groupId)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    if not profile then return true, 1 end
    local group = profile.groups[groupId]
    if not group then return true, 1 end
    if CooldownCompanion._combatForcedLock then
        return true, group.baselineAlpha or 1
    end

    if group.parentContainerId then
        -- Panel: own lock state (nil/true = locked, false = unlocked), panel's own alpha
        return group.locked ~= false, group.baselineAlpha or 1
    end

    -- Legacy path (no container)
    return group.locked or false, group.baselineAlpha or 1
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
    if type(frameName) ~= "string" then return nil end

    local groupId = frameName:match("^CooldownCompanionGroup(%d+)$")
    if groupId then
        return "group", tonumber(groupId)
    end

    local containerId = frameName:match("^CooldownCompanionContainer(%d+)$")
    if containerId then
        return "container", tonumber(containerId)
    end
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
    if not relativeTo or relativeTo == "UIParent" then
        return nil, "ui-parent"
    end

    local relativeFrame = _G[relativeTo]
    if not relativeFrame then
        return nil, "missing"
    end

    if WouldFrameDependencyCreateCircularAnchor(self, sourceId, sourceKind or "group", relativeFrame) then
        return nil, "unsafe"
    end

    return relativeFrame, "ok"
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

-- Nudger constants
local NUDGE_BTN_SIZE = 12
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

local CreatePixelBorders = ST.CreatePixelBorders
local GetEffectiveTextHeight = ST._GetEffectiveTextHeight

-- Recursively set frame strata on a frame and all its child frames.
-- Textures/FontStrings inherit from their parent frame automatically,
-- but child Frame objects (cooldown widgets, overlay frames, glow containers)
-- may not follow a parent strata change — so we force it explicitly.
local function PropagateFrameStrata(frame, strata)
    frame:SetFrameStrata(strata)
    for _, child in pairs({frame:GetChildren()}) do
        PropagateFrameStrata(child, strata)
    end
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
            -- Cancel any hold-to-repeat timers
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            CooldownCompanion:SaveGroupPosition(groupId)
        end)

        local function DoNudge()
            local group = CooldownCompanion.db.profile.groups[groupId]
            if not group then return end
            local gFrame = CooldownCompanion.groupFrames[groupId]
            if gFrame then
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
            -- Start hold-to-repeat after delay
            self.nudgeDelayTimer = C_Timer.NewTimer(NUDGE_REPEAT_DELAY, function()
                self.nudgeTicker = C_Timer.NewTicker(NUDGE_REPEAT_INTERVAL, function()
                    DoNudge()
                end)
            end)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            CooldownCompanion:SaveGroupPosition(groupId)
        end)
    end

    return nudger
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
    if frame.nudger then
        frame.nudger:SetFrameStrata(strata)
        frame.nudger:SetFrameLevel(baseLevel + 5)
        for buttonIndex, btn in ipairs(frame.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 6 + buttonIndex)
        end
    end
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
    local isTextureMode = group.displayMode == "textures" or group.displayMode == "trigger"
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

    if isLocked or #group.buttons == 0 or isTextureMode then
        frame.dragHandle:Hide()
    end

    -- Drag scripts (check lock state at drag time)
    frame:SetScript("OnDragStart", function(self)
        local locked = GetContainerState(self.groupId)
        local previewActive, selectedInContainer, containerId = GetContainerPreviewSelectionState(self.groupId)
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

    -- Create Masque group if active
    if self:IsGroupMasqueActive(groupId, group) then
        self:CreateMasqueGroup(groupId)
    end

    -- Create buttons
    self:PopulateGroupButtons(groupId)
    
    -- Show/hide based on enabled state, spec filter, hero talent filter, character visibility, and load conditions
    if self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
        requireButtons = false,
    }) then
        frame:Show()
        -- Apply current alpha from the alpha fade system so frame doesn't flash at 1.0
        local alphaState = self.alphaState and self.alphaState[groupId]
        if alphaState and alphaState.currentAlpha then
            frame:SetAlpha(alphaState.currentAlpha)
        end
    else
        frame:Hide()
    end

    return frame
end


function CooldownCompanion:AnchorGroupFrame(frame, anchor, forceCenter)
    -- Deferred during combat — ClearAllPoints/SetPoint are protected.
    if InCombatLockdown() and frame:IsProtected() then
        frame._anchorDirty = true
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
    -- Create a hidden frame to handle OnUpdate if needed
    if not frame.alphaSyncFrame then
        frame.alphaSyncFrame = CreateFrame("Frame", nil, frame)
    end

    -- If this group has baseline alpha < 1, the alpha fade system takes priority
    local _, baseAlpha = GetContainerState(frame.groupId)
    if baseAlpha < 1 then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
        return
    end

    -- Sync alpha immediately — use parent's natural alpha to avoid config override cascade
    local lastAlpha = parentFrame._naturalAlpha or parentFrame:GetEffectiveAlpha()
    frame:SetAlpha(lastAlpha)

    -- Sync alpha at ~30Hz (smooth enough for fade animations, avoids per-frame overhead)
    local accumulator = 0
    local SYNC_INTERVAL = 1 / 30
    frame.alphaSyncFrame:SetScript("OnUpdate", function(self, dt)
        accumulator = accumulator + dt
        if accumulator < SYNC_INTERVAL then return end
        accumulator = 0
        if frame.anchoredToParent then
            -- Skip sync if alpha system is active or group is unlocked
            local locked, bAlpha = GetContainerState(frame.groupId)
            if bAlpha < 1 or not locked then return end
            -- Read parent's natural alpha to avoid config override cascade
            local alpha = frame.anchoredToParent._naturalAlpha or frame.anchoredToParent:GetEffectiveAlpha()
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
            if alpha ~= lastAlpha then
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

    -- Get the screen-space center of our frame
    local cx, cy = frame:GetCenter()
    local fw, fh = frame:GetSize()

    -- Determine the reference frame and its dimensions
    local relativeTo = group.anchor.relativeTo
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
local function GetButtonDimensions(group)
    local style = group.style or {}
    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local isTextureMode = group.displayMode == "textures" or group.displayMode == "trigger"
    local w, h
    if isTextureMode then
        w, h = 1, 1
    elseif isTextMode then
        w = style.textWidth or 200
        if GetEffectiveTextHeight then
            local maxHeight = GetEffectiveTextHeight(style, style.textFormat or "{name}  {status}")
            for _, buttonData in ipairs(group.buttons or {}) do
                if CooldownCompanion:IsButtonUsable(buttonData) then
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

function CooldownCompanion:PopulateGroupButtons(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local buttonsPerRow = style.buttonsPerRow or 12
    local isTriggerMode = group.displayMode == "trigger"

    -- Clear existing buttons, including buttons left registered from an earlier Masque-active state.
    for _, button in ipairs(frame.buttons) do
        if CooldownCompanion.ReleaseAuraTextureVisual then
            CooldownCompanion:ReleaseAuraTextureVisual(button)
        end
        if self:IsGroupMasqueActive(groupId, group) or button._masqueStaticId then
            self:RemoveButtonFromMasque(groupId, button)
        end
        button:Hide()
        button:SetParent(nil)
    end
    wipe(frame.buttons)

    -- Text mode group header
    local isTextMode = group.displayMode == "text"
    local headerHeight = 0
    if isTextMode and style.showTextGroupHeader then
        if not frame.textHeader then
            frame.textHeader = frame:CreateFontString(nil, "OVERLAY")
            frame.textHeader:SetJustifyV("TOP")
        end
        local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
        local fontSize = style.textHeaderFontSize or style.textFontSize or 12
        local fontOutline = style.textFontOutline or "OUTLINE"
        frame.textHeader:SetFont(font, fontSize, fontOutline)
        local hdrColor = style.textHeaderFontColor or {1, 1, 1, 1}
        frame.textHeader:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
        if style.textShadow then
            frame.textHeader:SetShadowColor(0, 0, 0, 0.8)
            frame.textHeader:SetShadowOffset(1, -1)
        else
            frame.textHeader:SetShadowColor(0, 0, 0, 0)
            frame.textHeader:SetShadowOffset(0, 0)
        end
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

    -- Create new buttons (skip untalented spells)
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local visibleIndex = 0
    for i, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData) then
            visibleIndex = visibleIndex + 1
            local effectiveStyle = self:GetEffectiveStyle(style, buttonData)
            local button
            if group.displayMode == "text" then
                button = self:CreateTextFrame(frame, i, buttonData, effectiveStyle)
            elseif isBarMode then
                button = self:CreateBarFrame(frame, i, buttonData, effectiveStyle)
            else
                button = self:CreateButtonFrame(frame, i, buttonData, effectiveStyle)
                if group.displayMode == "textures" or isTriggerMode then
                    button:SetAlpha(0)
                    button._lastVisAlpha = 0
                end
            end

            if isTriggerMode then
                button:SetPoint("CENTER", frame, "CENTER", 0, 0)
            else
                -- Position the button using visibleIndex for gap-free layout
                local yOffset = headerHeight
                local row, col
                if orientation == "horizontal" then
                    row = math_floor((visibleIndex - 1) / buttonsPerRow)
                    col = (visibleIndex - 1) % buttonsPerRow
                else
                    col = math_floor((visibleIndex - 1) / buttonsPerRow)
                    row = (visibleIndex - 1) % buttonsPerRow
                end
                button:SetPoint(growthAnchor, frame, growthAnchor, xMul * col * (buttonWidth + spacing), yMul * (row * (buttonHeight + spacing) + yOffset))
            end

            button:Show()
            table_insert(frame.buttons, button)

            -- Add to Masque if enabled (after button is shown and in the list, icons only)
            if self:IsGroupMasqueActive(groupId, group) then
                self:AddButtonToMasque(groupId, button)
            end
        end
    end

    -- Resize the frame to fit visible buttons
    frame.visibleButtonCount = isTriggerMode and (visibleIndex > 0 and 1 or 0) or visibleIndex
    frame._layoutDirty = false
    frame._lastVisibleCount = visibleIndex
    self:ResizeGroupFrame(groupId)

    -- Reset the sized flag so the next ResizeGroupFrame call skips compact
    -- anchor compensation and treats the current size as a baseline.
    -- Callers that just called AnchorGroupFrame need this because the
    -- anchor was freshly set; other callers (e.g., UpdateGroupStyle)
    -- accept a baseline reset because the full button set was just rebuilt.
    frame._hasBeenSized = false

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()

    -- Compact mode: apply reflow immediately so newly rebuilt buttons don't
    -- briefly appear before the next ticker-driven layout pass.
    if group.compactLayout then
        frame._layoutDirty = true
        self:UpdateGroupLayout(groupId)
    end
    -- _hasBeenSized is now true if the compact resize ran (set by
    -- ResizeGroupFrame), or still false if all buttons were visible and no
    -- compact resize was needed.  When compactLayout is off, it stays false
    -- (harmless — ResizeGroupFrame skips compensation for non-compact groups).
    -- Either state is correct: the first ticker-driven resize after this
    -- will either compensate (true) relative to the established compact
    -- baseline, or skip compensation (false) to establish a new baseline
    -- when config-forced visibility clears.

    -- Propagate group frame strata to all button sub-elements
    local effectiveStrata = group.frameStrata or "MEDIUM"
    for _, button in ipairs(frame.buttons) do
        PropagateFrameStrata(button, effectiveStrata)
    end

    -- Update event-driven range check registrations
    self:UpdateRangeCheckRegistrations()
end

function CooldownCompanion:ResizeGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local buttonsPerRow = style.buttonsPerRow or 12
    local numButtons = frame.visibleButtonCount or #group.buttons

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
        frame._layoutDirty = false
        return
    end

    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local buttonsPerRow = style.buttonsPerRow or 12
    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)

    local maxVis = (group.maxVisibleButtons and group.maxVisibleButtons > 0) and group.maxVisibleButtons or #frame.buttons

    local visibleButtons = {}
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
        button:ClearAllPoints()
        local row, col = GetCompactSlotForIndex(
            visibleIndex,
            visibleCount,
            buttonsPerRow,
            orientation,
            compactGrowthDirection
        )
        button:SetPoint(growthAnchor, frame, growthAnchor, xMul * col * (buttonWidth + spacing), yMul * (row * (buttonHeight + spacing) + headerH))
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

        -- Keep Masque runtime state aligned without changing the saved user preference.
        local masqueActive = self:IsGroupMasqueActive(groupId, group)
        if masqueActive and not self.MasqueGroups[self:GetMasqueStaticId(groupId)] then
            self:CreateMasqueGroup(groupId)
        elseif not masqueActive and self.Masque and self._masqueGroupKeys and self._masqueGroupKeys[groupId] then
            self:DeactivateGroupMasqueRuntime(groupId)
        end

        self:PopulateGroupButtons(groupId)
    end

    -- Resolve locked/alpha from container
    local isLocked, baseAlpha = GetContainerState(groupId)

    -- Update drag handle text and lock state
    local hasButtons = #group.buttons > 0
    local isTextureMode = group.displayMode == "textures" or group.displayMode == "trigger"
    local containerPreviewActive = group.parentContainerId and self:IsContainerUnlockPreviewActive(group.parentContainerId)
    local selectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)
    if frame.dragHandle then
        if frame.dragHandle.text then
            frame.dragHandle.text:SetText(group.name)
        end
        if containerPreviewActive then
            if selectedInContainer and hasButtons and not isTextureMode then
                frame.dragHandle:Show()
            else
                frame.dragHandle:Hide()
            end
        elseif isLocked or not hasButtons or isTextureMode then
            frame.dragHandle:Hide()
        else
            frame.dragHandle:Show()
        end
    end
    self:UpdateGroupClickthrough(groupId)

    -- Update visibility — unload if disabled, no buttons, wrong spec/hero, wrong character, or load conditions
    local isActive = CooldownCompanion:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
        requireButtons = true,
    })
    if isActive then
        if InCombatLockdown() and frame:IsProtected() then
            if not frame:IsShown() then
                self._pendingVisibilityRefresh = true
            end
        else
            frame:Show()
        end
        -- Force 100% alpha while unlocked for easier positioning
        if containerPreviewActive or not isLocked then
            frame:SetAlpha(1)
        -- Apply current alpha from the alpha fade system so frame doesn't flash at 1.0
        else
            local alphaState = CooldownCompanion.alphaState and CooldownCompanion.alphaState[groupId]
            if alphaState and alphaState.currentAlpha then
                frame:SetAlpha(alphaState.currentAlpha)
            end
        end
    else
        self:UnloadGroup(groupId)
    end

    if isActive
        and (group.displayMode == "textures" or group.displayMode == "trigger")
        and self.UpdateAuraTextureVisual
        and frame
        and frame.buttons
        and frame.buttons[1] then
        self:UpdateAuraTextureVisual(frame.buttons[1])
    end

    if group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
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

function CooldownCompanion:SetGroupAnchor(groupId, targetFrameName, forceCenter)
    local group = self.db.profile.groups[groupId]
    local frame = self.groupFrames[groupId]

    if not group or not frame then return false end

    -- Block self-anchoring
    local selfFrameName = "CooldownCompanionGroup" .. groupId
    if targetFrameName == selfFrameName then
        self:Print("Cannot anchor a group to itself.")
        return false
    end

    -- Block circular anchor chains (check both group and container targets)
    local tgId = targetFrameName and targetFrameName:match("^CooldownCompanionGroup(%d+)$")
    if tgId then
        tgId = tonumber(tgId)
        if tgId and self:WouldCreateCircularAnchor(groupId, tgId) then
            self:Print("Cannot anchor: would create a circular reference.")
            return false
        end
    end
    local tcId = targetFrameName and targetFrameName:match("^CooldownCompanionContainer(%d+)$")
    if tcId then
        tcId = tonumber(tcId)
        if tcId and self:WouldCreateCircularAnchor(groupId, tcId, "container") then
            self:Print("Cannot anchor: would create a circular reference.")
            return false
        end
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
        self:AnchorGroupFrame(frame, group.anchor)
        return true
    end

    group.anchor = {
        point = "TOPLEFT",
        relativeTo = targetFrameName,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -5,
    }

    self:AnchorGroupFrame(frame, group.anchor)
    return true
end

function CooldownCompanion:UpdateGroupStyle(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local groupStyle = group.style or {}

    -- Update all buttons with per-button effective style
    for _, button in ipairs(frame.buttons) do
        local effectiveStyle = self:GetEffectiveStyle(groupStyle, button.buttonData)
        button:UpdateStyle(effectiveStyle)
    end

    -- Update group frame clickthrough
    self:UpdateGroupClickthrough(groupId)

    -- Reposition and resize
    self:PopulateGroupButtons(groupId)
end

function CooldownCompanion:UpdateGroupClickthrough(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local isLocked = GetContainerState(groupId)
    local isTextureMode = group.displayMode == "textures" or group.displayMode == "trigger"
    local containerPreviewActive = group.parentContainerId and self:IsContainerUnlockPreviewActive(group.parentContainerId)
    local isSelectedInContainer = containerPreviewActive and self:IsContainerPanelSelected(group.parentContainerId, groupId)

    SyncGroupControlLevels(frame, isSelectedInContainer and not isTextureMode)

    if containerPreviewActive then
        SetFrameClickThrough(frame, true, true)
        if frame.dragHandle then
            if isSelectedInContainer and not isTextureMode then
                SetFrameClickThrough(frame.dragHandle, false, false)
                frame.dragHandle:EnableMouse(true)
                frame.dragHandle:RegisterForDrag("LeftButton")
                frame.dragHandle:SetScript("OnMouseUp", nil)
            else
                SetFrameClickThrough(frame.dragHandle, true, true)
            end
        end
        if frame.nudger then
            if isSelectedInContainer and not isTextureMode then
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
    if isLocked or isTextureMode then
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
    self:StartContainerMemberPreviewTracking(containerId, groupId)

    if group.displayMode == "textures" or group.displayMode == "trigger" then
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

    if group.displayMode == "textures" or group.displayMode == "trigger" then
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
    local isStandaloneDisplay = group and (group.displayMode == "textures" or group.displayMode == "trigger")

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

    if self._combatForcedLock or container.locked ~= false or not self:IsContainerVisibleToCurrentChar(containerId) then
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

    local previewPanels = self.GetContainerUnlockPreviewPanels and self:GetContainerUnlockPreviewPanels(containerId) or {}
    local allPanels = self.GetPanels and self:GetPanels(containerId) or previewPanels
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
        local isStandaloneDisplay = rect.group and (rect.group.displayMode == "textures" or rect.group.displayMode == "trigger")

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
        local isStandaloneDisplay = group and (group.displayMode == "textures" or group.displayMode == "trigger")

        if groupFrame and not isStandaloneDisplay then
            SyncGroupControlLevels(groupFrame, isSelected)
            if groupFrame.dragHandle then
                if isSelected then
                    groupFrame.dragHandle:Show()
                elseif self:IsContainerUnlockPreviewActive(containerId) then
                    groupFrame.dragHandle:Hide()
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
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
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
            self.nudgeDelayTimer = C_Timer.NewTimer(NUDGE_REPEAT_DELAY, function()
                self.nudgeTicker = C_Timer.NewTicker(NUDGE_REPEAT_INTERVAL, function()
                    DoNudge()
                end)
            end)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
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
    local container = self.db.profile.groupContainers[containerId]
    if not container then return false end
    if container.isGlobal then return true end
    return container.createdBy == self.db.keys.char
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
