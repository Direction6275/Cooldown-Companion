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

    if group.parentContainerId then
        -- Panel: own lock state (nil/true = locked, false = unlocked), panel's own alpha
        return group.locked ~= false, group.baselineAlpha or 1
    end

    -- Legacy path (no container)
    return group.locked or false, group.baselineAlpha or 1
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
        if button.assistedHighlight then
            HideGlowStyles(button.assistedHighlight)
        end
        if button.barAuraEffect then
            HideGlowStyles(button.barAuraEffect)
        end
    end

    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._barAuraEffectActive = nil
    if button.assistedHighlight then
        button.assistedHighlight.currentState = nil
    end
end

-- Nudger constants
local NUDGE_BTN_SIZE = 12
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

local CreatePixelBorders = ST.CreatePixelBorders

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

    -- Make it movable when unlocked
    frame:SetMovable(true)
    frame:EnableMouse(not isLocked)
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

    if isLocked or #group.buttons == 0 then
        frame.dragHandle:Hide()
    end

    -- Drag scripts (check lock state at drag time)
    frame:SetScript("OnDragStart", function(self)
        local locked = GetContainerState(self.groupId)
        if not locked then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CooldownCompanion:SaveGroupPosition(self.groupId)
    end)

    -- Also allow dragging from the handle
    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        local locked = GetContainerState(groupId)
        if not locked then
            frame:StartMoving()
        end
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
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
    frame:ClearAllPoints()

    -- Stop any existing alpha sync
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end
    frame.anchoredToParent = nil

    local relativeTo = anchor.relativeTo
    if relativeTo and relativeTo ~= "UIParent" then
        local relativeFrame = _G[relativeTo]
        if relativeFrame then
            frame:SetPoint(anchor.point, relativeFrame, anchor.relativePoint, anchor.x, anchor.y)
            UpdateCoordLabel(frame, anchor.x, anchor.y)
            -- Store reference for alpha inheritance
            frame.anchoredToParent = relativeFrame
            -- Set up alpha sync
            self:SetupAlphaSync(frame, relativeFrame)
            return
        else
            -- Target frame doesn't exist — panels fall back to container before UIParent
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
            -- If forceCenter, reset to center
            -- Otherwise use saved position relative to UIParent
            if forceCenter then
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
    if relativeTo and relativeTo ~= "UIParent" then
        relFrame = _G[relativeTo]
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
end

-- Compute button width/height from group style (bar mode vs square vs non-square).
-- Returns width, height, isBarMode.
local function GetButtonDimensions(group)
    local style = group.style or {}
    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local w, h
    if isTextMode then
        w, h = style.textWidth or 200, style.textHeight or 20
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

    -- Clear existing buttons (remove from Masque first if enabled)
    for _, button in ipairs(frame.buttons) do
        if group.masqueEnabled then
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
            end

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

            button:Show()
            table_insert(frame.buttons, button)

            -- Add to Masque if enabled (after button is shown and in the list, icons only)
            if not isBarMode and group.displayMode ~= "text" and group.masqueEnabled then
                self:AddButtonToMasque(groupId, button)
            end
        end
    end

    -- Resize the frame to fit visible buttons
    frame.visibleButtonCount = visibleIndex
    frame._layoutDirty = false
    frame._lastVisibleCount = visibleIndex
    self:ResizeGroupFrame(groupId)

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
    
    if not group then
        self:UnloadGroup(groupId)
        return
    end
    
    if not frame then
        frame = self:CreateGroupFrame(groupId)
    else
        -- Apply per-group frame strata before populating buttons
        local strata = group.frameStrata
        if strata then
            frame:SetFrameStrata(strata)
            frame:SetFixedFrameStrata(true)
        else
            frame:SetFrameStrata("MEDIUM")
            frame:SetFixedFrameStrata(false)
        end

        self:AnchorGroupFrame(frame, group.anchor)
        self:PopulateGroupButtons(groupId)
    end

    -- Resolve locked/alpha from container
    local isLocked, baseAlpha = GetContainerState(groupId)

    -- Update drag handle text and lock state
    local hasButtons = #group.buttons > 0
    if frame.dragHandle then
        if frame.dragHandle.text then
            frame.dragHandle.text:SetText(group.name)
        end
        if isLocked or not hasButtons then
            frame.dragHandle:Hide()
        else
            frame.dragHandle:Show()
        end
    end
    self:UpdateGroupClickthrough(groupId)

    -- Update visibility — hide if disabled, no buttons, wrong spec/hero, wrong character, or load conditions
    if CooldownCompanion:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
        requireButtons = true,
    }) then
        frame:Show()
        -- Force 100% alpha while unlocked for easier positioning
        if not isLocked then
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
end

function CooldownCompanion:WouldCreateCircularAnchor(sourceGroupId, targetId, targetKind)
    local groups = self.db.profile.groups
    if not groups then return false end
    local containers = self.db.profile.groupContainers or {}
    local visited = {}
    -- Track both the kind and id to avoid conflating group/container ID spaces
    local currentKind = targetKind or "group"
    local currentId = targetId
    while currentId do
        if currentKind == "group" and currentId == sourceGroupId then return true end
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

    -- When locked: group container is always fully non-interactive
    -- When unlocked: enable everything for dragging
    if isLocked then
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

local function CreateContainerNudger(frame, containerId)
    local NUDGE_GAP = 2

    local nudger = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", frame.dragHandle, "TOP", 0, 2)
    nudger:SetFrameStrata(frame.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(frame.dragHandle:GetFrameLevel() + 5)
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
            local cFrame = CooldownCompanion.containerFrames[containerId]
            if cFrame then
                cFrame:AdjustPointsOffset(dir.dx, dir.dy)
                local _, _, _, x, y = cFrame:GetPoint()
                container.anchor.x = math_floor(x * 10 + 0.5) / 10
                container.anchor.y = math_floor(y * 10 + 0.5) / 10
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

    -- Drag handle (visible when unlocked)
    frame.dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.dragHandle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -40, 2)
    frame.dragHandle:SetSize(80, 15)
    frame.dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.dragHandle:SetBackdropColor(0.15, 0.35, 0.55, 0.9)
    CreatePixelBorders(frame.dragHandle)

    frame.dragHandle.text = frame.dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.dragHandle.text:SetPoint("CENTER")
    frame.dragHandle.text:SetText(container.name)
    frame.dragHandle.text:SetTextColor(1, 1, 1, 1)

    -- Pixel nudger
    frame.nudger = CreateContainerNudger(frame, containerId)

    -- Coordinate label
    frame.coordLabel = CreateFrame("Frame", nil, frame.dragHandle, "BackdropTemplate")
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
        if c and not c.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CooldownCompanion:SaveContainerPosition(self.containerId)
    end)

    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        local c = CooldownCompanion.db.profile.groupContainers[containerId]
        if c and not c.locked then
            frame:StartMoving()
        end
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        CooldownCompanion:SaveContainerPosition(containerId)
    end)

    -- Middle-click to lock
    frame.dragHandle:SetScript("OnMouseUp", function(_, btn)
        if btn == "MiddleButton" then
            local c = CooldownCompanion.db.profile.groupContainers[containerId]
            if c then
                c.locked = true
                frame.dragHandle:Hide()
                CooldownCompanion:RefreshConfigPanel()
                CooldownCompanion:Print(c.name .. " locked.")
            end
        end
    end)

    self.containerFrames[containerId] = frame
    frame:Show()
    return frame
end

function CooldownCompanion:AnchorContainerFrame(frame, anchor)
    frame:ClearAllPoints()

    local relativeTo = anchor.relativeTo
    if relativeTo and relativeTo ~= "UIParent" then
        local relativeFrame = _G[relativeTo]
        if relativeFrame then
            frame:SetPoint(anchor.point, relativeFrame, anchor.relativePoint, anchor.x, anchor.y)
            UpdateCoordLabel(frame, anchor.x, anchor.y)
            return
        end
    end

    frame:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
    UpdateCoordLabel(frame, anchor.x, anchor.y)
end

function CooldownCompanion:SaveContainerPosition(containerId)
    local frame = self.containerFrames[containerId]
    local container = self.db.profile.groupContainers[containerId]
    if not frame or not container then return end

    local cx, cy = frame:GetCenter()
    if not cx then return end

    local relativeTo = container.anchor.relativeTo
    local relFrame
    if relativeTo and relativeTo ~= "UIParent" then
        relFrame = _G[relativeTo]
    end
    if not relFrame then
        relFrame = UIParent
        relativeTo = "UIParent"
    end

    local rw, rh = relFrame:GetSize()
    local rcx, rcy = relFrame:GetCenter()
    local fw, fh = frame:GetSize()

    local desiredPoint = container.anchor.point
    local desiredRelPoint = container.anchor.relativePoint

    local fax, fay = GetAnchorOffset(desiredPoint, fw, fh)
    local framePtX = cx + fax
    local framePtY = cy + fay

    local rax, ray = GetAnchorOffset(desiredRelPoint, rw, rh)
    local refPtX = rcx + rax
    local refPtY = rcy + ray

    local newX = math_floor((framePtX - refPtX) * 10 + 0.5) / 10
    local newY = math_floor((framePtY - refPtY) * 10 + 0.5) / 10

    container.anchor.x = newX
    container.anchor.y = newY
    container.anchor.relativeTo = relativeTo

    frame:ClearAllPoints()
    frame:SetPoint(desiredPoint, relFrame, desiredRelPoint, newX, newY)

    UpdateCoordLabel(frame, newX, newY)
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
