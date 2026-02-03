--[[
    CooldownCompanion - GroupFrame
    Container frames for groups of buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Helper function to make a frame click-through
-- disableClicks: prevent LMB/RMB clicks (allows camera movement pass-through)
-- disableMotion: prevent OnEnter/OnLeave hover events (disables tooltips)
local function SetFrameClickThrough(frame, disableClicks, disableMotion)
    if not frame then return end

    if disableClicks then
        if frame.SetMouseClickEnabled then
            frame:SetMouseClickEnabled(false)
        end
        if frame.SetPropagateMouseClicks then
            frame:SetPropagateMouseClicks(true)
        end
        if frame.RegisterForClicks then
            frame:RegisterForClicks()
        end
        if frame.RegisterForDrag then
            frame:RegisterForDrag()
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnMouseUp", nil)
    else
        if frame.SetMouseClickEnabled then
            frame:SetMouseClickEnabled(true)
        end
        if frame.SetPropagateMouseClicks then
            frame:SetPropagateMouseClicks(false)
        end
    end

    if disableMotion then
        if frame.SetMouseMotionEnabled then
            frame:SetMouseMotionEnabled(false)
        end
        if frame.SetPropagateMouseMotion then
            frame:SetPropagateMouseMotion(true)
        end
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    else
        if frame.SetMouseMotionEnabled then
            frame:SetMouseMotionEnabled(true)
        end
        if frame.SetPropagateMouseMotion then
            frame:SetPropagateMouseMotion(false)
        end
    end

    if disableClicks and disableMotion then
        frame:EnableMouse(false)
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(10000, 10000, 10000, 10000)
        end
        frame:EnableKeyboard(false)
    elseif not disableClicks and not disableMotion then
        frame:EnableMouse(true)
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(0, 0, 0, 0)
        end
    else
        frame:EnableMouse(true)
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(0, 0, 0, 0)
        end
    end
end

-- Recursively apply click-through to frame and all children
local function SetFrameClickThroughRecursive(frame, disableClicks, disableMotion)
    SetFrameClickThrough(frame, disableClicks, disableMotion)
    for _, child in ipairs({frame:GetChildren()}) do
        SetFrameClickThroughRecursive(child, disableClicks, disableMotion)
    end
end

local function UpdateCoordLabel(frame, x, y)
    if frame.coordLabel then
        frame.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x, y))
    end
end

-- Nudger constants
local NUDGE_BTN_SIZE = 14
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

-- Create 4 pixel-perfect border textures using PixelUtil (replaces backdrop edgeFile)
local function CreatePixelBorders(frame, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(top, 1, 1)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(bottom, 1, 1)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(left, 1, 1)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(right, 1, 1)

    frame.borderTextures = { top, bottom, left, right }
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
        { rotation = math.pi / 2,   anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },   -- up
        { rotation = -math.pi / 2,  anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },  -- down
        { rotation = math.pi,       anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },          -- left
        { rotation = 0,             anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },          -- right
    }

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        btn:SetSize(NUDGE_BTN_SIZE, NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture("Interface\\CHATFRAME\\ChatFrameExpandArrow")
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
                group.anchor.x = math.floor(x * 10 + 0.5) / 10
                group.anchor.y = math.floor(y * 10 + 0.5) / 10
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
    local group = self.db.profile.groups[groupId]
    if not group then return end
    
    -- Create main container frame
    local frameName = "CooldownCompanionGroup" .. groupId
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame.groupId = groupId
    frame.buttons = {}
    
    -- Set initial size (will be updated when buttons are added)
    frame:SetSize(100, 50)
    
    -- Position the frame
    self:AnchorGroupFrame(frame, group.anchor)
    
    -- Make it movable when unlocked
    frame:SetMovable(true)
    frame:EnableMouse(not group.locked)
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

    if group.locked or #group.buttons == 0 then
        frame.dragHandle:Hide()
    end

    -- Drag scripts
    frame:SetScript("OnDragStart", function(self)
        local g = CooldownCompanion.db.profile.groups[self.groupId]
        if g and not g.locked then
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
        local g = CooldownCompanion.db.profile.groups[groupId]
        if g and not g.locked then
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
    
    -- Create buttons
    self:PopulateGroupButtons(groupId)
    
    -- Show/hide based on enabled state, spec filter, and character visibility
    local specAllowed = true
    if group.specs and next(group.specs) then
        specAllowed = self._currentSpecId and group.specs[self._currentSpecId]
    end
    local charVisible = self:IsGroupVisibleToCurrentChar(groupId)

    if group.enabled and specAllowed and charVisible then
        frame:Show()
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
            -- Target frame doesn't exist - if forceCenter, reset to center
            -- Otherwise use saved position relative to UIParent
            if forceCenter then
                frame:SetAlpha(1)
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
    frame:SetAlpha(1)
    frame:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
    UpdateCoordLabel(frame, anchor.x, anchor.y)
end

function CooldownCompanion:SetupAlphaSync(frame, parentFrame)
    -- Create a hidden frame to handle OnUpdate if needed
    if not frame.alphaSyncFrame then
        frame.alphaSyncFrame = CreateFrame("Frame", nil, frame)
    end

    -- Sync alpha immediately
    frame:SetAlpha(parentFrame:GetEffectiveAlpha())

    -- Sync alpha every frame to match parent's fade animations
    frame.alphaSyncFrame:SetScript("OnUpdate", function(self, delta)
        if frame.anchoredToParent then
            frame:SetAlpha(frame.anchoredToParent:GetEffectiveAlpha())
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
        relFrame = UIParent
        relativeTo = "UIParent"
    end

    local rw, rh = relFrame:GetSize()
    local rcx, rcy = relFrame:GetCenter()

    -- Convert our frame center into an offset from the user's chosen anchor/relativePoint
    local desiredPoint = group.anchor.point
    local desiredRelPoint = group.anchor.relativePoint

    -- Calculate the reference point on relFrame in screen coords
    local function AnchorOffset(pt, w, h)
        -- Returns offset from center for a given anchor point
        if pt == "TOPLEFT" then return -w/2,  h/2
        elseif pt == "TOP" then return 0,  h/2
        elseif pt == "TOPRIGHT" then return  w/2,  h/2
        elseif pt == "LEFT" then return -w/2, 0
        elseif pt == "CENTER" then return 0, 0
        elseif pt == "RIGHT" then return  w/2, 0
        elseif pt == "BOTTOMLEFT" then return -w/2, -h/2
        elseif pt == "BOTTOM" then return 0, -h/2
        elseif pt == "BOTTOMRIGHT" then return  w/2, -h/2
        else return 0, 0
        end
    end

    -- Screen position of our frame's desired anchor point
    local fax, fay = AnchorOffset(desiredPoint, fw, fh)
    local framePtX = cx + fax
    local framePtY = cy + fay

    -- Screen position of the reference frame's desired relative point
    local rax, ray = AnchorOffset(desiredRelPoint, rw, rh)
    local refPtX = rcx + rax
    local refPtY = rcy + ray

    -- The offset is the difference, rounded to 1 decimal place
    local newX = math.floor((framePtX - refPtX) * 10 + 0.5) / 10
    local newY = math.floor((framePtY - refPtY) * 10 + 0.5) / 10

    group.anchor.x = newX
    group.anchor.y = newY
    group.anchor.relativeTo = relativeTo

    -- Re-anchor with the corrected values so WoW doesn't change our anchor point
    frame:ClearAllPoints()
    frame:SetPoint(desiredPoint, relFrame, desiredRelPoint, newX, newY)

    UpdateCoordLabel(frame, newX, newY)
    self:RefreshConfigPanel()
end

function CooldownCompanion:PopulateGroupButtons(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local style = group.style or {}
    local buttonWidth, buttonHeight

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        buttonWidth = size
        buttonHeight = size
    else
        -- Non-square mode: use separate width/height
        buttonWidth = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        buttonHeight = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or "horizontal"
    local buttonsPerRow = style.buttonsPerRow or 12

    -- Clear existing buttons
    for _, button in ipairs(frame.buttons) do
        button:Hide()
        button:SetParent(nil)
    end
    wipe(frame.buttons)

    -- Create new buttons (skip untalented spells)
    local visibleIndex = 0
    for i, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData) then
            visibleIndex = visibleIndex + 1
            local button = self:CreateButtonFrame(frame, i, buttonData, style)

            -- Position the button using visibleIndex for gap-free layout
            local row, col
            if orientation == "horizontal" then
                row = math.floor((visibleIndex - 1) / buttonsPerRow)
                col = (visibleIndex - 1) % buttonsPerRow
                button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonHeight + spacing))
            else
                col = math.floor((visibleIndex - 1) / buttonsPerRow)
                row = (visibleIndex - 1) % buttonsPerRow
                button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonHeight + spacing))
            end

            button:Show()
            table.insert(frame.buttons, button)
        end
    end

    -- Resize the frame to fit visible buttons
    frame.visibleButtonCount = visibleIndex
    self:ResizeGroupFrame(groupId)

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()

    -- Update event-driven range check registrations
    self:UpdateRangeCheckRegistrations()
end

function CooldownCompanion:ResizeGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local style = group.style or {}
    local buttonWidth, buttonHeight

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        buttonWidth = size
        buttonHeight = size
    else
        -- Non-square mode: use separate width/height
        buttonWidth = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        buttonHeight = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or "horizontal"
    local buttonsPerRow = style.buttonsPerRow or 12
    local numButtons = frame.visibleButtonCount or #group.buttons

    if numButtons == 0 then
        frame:SetSize(buttonWidth, buttonHeight)
        return
    end

    local rows, cols
    if orientation == "horizontal" then
        cols = math.min(numButtons, buttonsPerRow)
        rows = math.ceil(numButtons / buttonsPerRow)
    else
        rows = math.min(numButtons, buttonsPerRow)
        cols = math.ceil(numButtons / buttonsPerRow)
    end

    local width = cols * buttonWidth + (cols - 1) * spacing
    local height = rows * buttonHeight + (rows - 1) * spacing

    frame:SetSize(math.max(width, buttonWidth), math.max(height, buttonHeight))
end

function CooldownCompanion:RefreshGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    
    if not group then
        if frame then
            frame:Hide()
        end
        return
    end
    
    if not frame then
        frame = self:CreateGroupFrame(groupId)
    else
        self:AnchorGroupFrame(frame, group.anchor)
        self:PopulateGroupButtons(groupId)
    end
    
    -- Update drag handle text and lock state
    local hasButtons = #group.buttons > 0
    if frame.dragHandle then
        if frame.dragHandle.text then
            frame.dragHandle.text:SetText(group.name)
        end
        if group.locked or not hasButtons then
            frame.dragHandle:Hide()
        else
            frame.dragHandle:Show()
        end
    end
    self:UpdateGroupClickthrough(groupId)

    -- Update visibility — hide if disabled, no buttons, wrong spec, or wrong character
    local specAllowed = true
    if group.specs and next(group.specs) then
        specAllowed = CooldownCompanion._currentSpecId
            and group.specs[CooldownCompanion._currentSpecId]
    end
    local charVisible = CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)

    if group.enabled and #group.buttons > 0 and specAllowed and charVisible then
        frame:Show()
    else
        frame:Hide()
    end
end

function CooldownCompanion:SetGroupAnchor(groupId, targetFrameName, forceCenter)
    local group = self.db.profile.groups[groupId]
    local frame = self.groupFrames[groupId]

    if not group or not frame then return false end

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

    local style = group.style or {}

    -- Update all buttons
    for _, button in ipairs(frame.buttons) do
        button:UpdateStyle(style)
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

    -- When locked: group container is always fully non-interactive
    -- When unlocked: enable everything for dragging
    if group.locked then
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
                        g.locked = true
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
