--[[
    CooldownCompanion - GroupFrame
    Container frames for groups of buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Helper function to make a frame fully click-through
-- Uses multiple methods for maximum compatibility across WoW versions
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end

    if clickThrough then
        -- Disable all mouse interaction
        frame:EnableMouse(false)
        -- These methods may not exist in all WoW versions
        if frame.SetMouseClickEnabled then
            frame:SetMouseClickEnabled(false)
        end
        if frame.SetMouseMotionEnabled then
            frame:SetMouseMotionEnabled(false)
        end
        -- Unregister any click/drag events
        if frame.RegisterForClicks then
            frame:RegisterForClicks()
        end
        if frame.RegisterForDrag then
            frame:RegisterForDrag()
        end
        -- Push hit rect outside frame bounds (makes frame effectively non-interactive)
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(10000, 10000, 10000, 10000)
        end
        -- Disable keyboard interaction too
        frame:EnableKeyboard(false)
    else
        -- Enable mouse interaction
        frame:EnableMouse(true)
        if frame.SetMouseClickEnabled then
            frame:SetMouseClickEnabled(true)
        end
        if frame.SetMouseMotionEnabled then
            frame:SetMouseMotionEnabled(true)
        end
        -- Reset hit rect to normal
        if frame.SetHitRectInsets then
            frame:SetHitRectInsets(0, 0, 0, 0)
        end
    end
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
    frame:EnableMouse(not self.db.profile.locked)
    frame:RegisterForDrag("LeftButton")
    
    -- Drag handle (visible when unlocked)
    frame.dragHandle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.dragHandle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 15)
    frame.dragHandle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 15)
    frame.dragHandle:SetHeight(15)
    frame.dragHandle:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    frame.dragHandle:SetBackdropBorderColor(0, 0, 0, 1)
    
    frame.dragHandle.text = frame.dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.dragHandle.text:SetPoint("CENTER")
    frame.dragHandle.text:SetText(group.name)
    frame.dragHandle.text:SetTextColor(1, 1, 1, 1)
    
    if self.db.profile.locked then
        frame.dragHandle:Hide()
    end
    
    -- Drag scripts
    frame:SetScript("OnDragStart", function(self)
        if not CooldownCompanion.db.profile.locked then
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
        if not CooldownCompanion.db.profile.locked then
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
    
    -- Show/hide based on enabled state
    if group.enabled then
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
                return
            end
        end
    end

    -- Anchor to UIParent using saved position (preserves position across reloads)
    frame:SetAlpha(1)
    frame:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
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
    
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    
    group.anchor = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
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

    -- Create new buttons
    for i, buttonData in ipairs(group.buttons) do
        local button = self:CreateButtonFrame(frame, i, buttonData, style)

        -- Position the button (use width for horizontal spacing, height for vertical)
        local row, col
        if orientation == "horizontal" then
            row = math.floor((i - 1) / buttonsPerRow)
            col = (i - 1) % buttonsPerRow
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonHeight + spacing))
        else
            col = math.floor((i - 1) / buttonsPerRow)
            row = (i - 1) % buttonsPerRow
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonHeight + spacing))
        end

        button:Show()
        table.insert(frame.buttons, button)
    end

    -- Resize the frame to fit buttons
    self:ResizeGroupFrame(groupId)

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()
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
    local numButtons = #group.buttons

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
        self:PopulateGroupButtons(groupId)
    end
    
    -- Update drag handle text
    if frame.dragHandle and frame.dragHandle.text then
        frame.dragHandle.text:SetText(group.name)
    end
    
    -- Update visibility
    if group.enabled then
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

    local style = group.style or {}

    -- Determine if group should be clickthrough
    -- Clickthrough if: tooltips off OR (tooltips on AND enableClickthrough is true)
    local showTooltips = style.showTooltips ~= false
    local isClickthrough = not showTooltips or style.enableClickthrough

    -- When locked and clickthrough: disable mouse completely for camera passthrough
    -- When unlocked: always enable mouse for dragging (drag handle is backup)
    if self.db.profile.locked and isClickthrough then
        SetFrameClickThrough(frame, true)
    else
        SetFrameClickThrough(frame, false)
        -- Re-register for drag when not click-through
        frame:RegisterForDrag("LeftButton")
    end
end
