--[[
    CooldownCompanion - GroupFrame
    Container frames for groups of buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

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

function CooldownCompanion:AnchorGroupFrame(frame, anchor)
    frame:ClearAllPoints()
    
    local relativeTo = anchor.relativeTo
    if relativeTo and relativeTo ~= "UIParent" then
        local relativeFrame = _G[relativeTo]
        if relativeFrame then
            frame:SetPoint(anchor.point, relativeFrame, anchor.relativePoint, anchor.x, anchor.y)
            return
        end
    end
    
    -- Default to UIParent
    frame:SetPoint(anchor.point, UIParent, anchor.relativePoint, anchor.x, anchor.y)
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
    local buttonSize = style.buttonSize or ST.BUTTON_SIZE
    local widthRatio = style.iconWidthRatio or 1.0
    local buttonWidth = buttonSize * widthRatio
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
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonSize + spacing))
        else
            col = math.floor((i - 1) / buttonsPerRow)
            row = (i - 1) % buttonsPerRow
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (buttonWidth + spacing), -row * (buttonSize + spacing))
        end

        button:Show()
        table.insert(frame.buttons, button)
    end

    -- Resize the frame to fit buttons
    self:ResizeGroupFrame(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()
end

function CooldownCompanion:ResizeGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local style = group.style or {}
    local buttonSize = style.buttonSize or ST.BUTTON_SIZE
    local widthRatio = style.iconWidthRatio or 1.0
    local buttonWidth = buttonSize * widthRatio
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = style.orientation or "horizontal"
    local buttonsPerRow = style.buttonsPerRow or 12
    local numButtons = #group.buttons

    if numButtons == 0 then
        frame:SetSize(buttonWidth, buttonSize)
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
    local height = rows * buttonSize + (rows - 1) * spacing

    frame:SetSize(math.max(width, buttonWidth), math.max(height, buttonSize))
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

function CooldownCompanion:SetGroupAnchor(groupId, targetFrameName)
    local group = self.db.profile.groups[groupId]
    local frame = self.groupFrames[groupId]
    
    if not group or not frame then return false end
    
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
    
    -- Reposition and resize
    self:PopulateGroupButtons(groupId)
end
