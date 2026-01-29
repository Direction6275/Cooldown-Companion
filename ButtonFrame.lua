--[[
    CooldownCompanion - ButtonFrame
    Individual button frames with cooldown animations and glow effects
    
    Note: WoW 12.0 "secret value" API blocks direct comparison of cooldown data.
    We pass values directly to SetCooldown and let the internal WoW code handle them.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Button Frame Pool
local buttonPool = {}

-- Glow functions (using LibCustomGlow if available, otherwise fallback)
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local function ShowPixelGlow(frame, color)
    if LCG then
        LCG.PixelGlow_Start(frame, color, nil, nil, nil, nil, nil, nil, nil, "CooldownCompanionGlow")
    else
        -- Fallback: simple border glow
        if not frame.glowBorder then
            frame.glowBorder = frame:CreateTexture(nil, "OVERLAY")
            frame.glowBorder:SetAllPoints()
            frame.glowBorder:SetColorTexture(1, 1, 0, 0.5)
            frame.glowBorder:SetBlendMode("ADD")
        end
        frame.glowBorder:Show()
    end
end

local function ShowActionGlow(frame, color)
    if LCG then
        LCG.AutoCastGlow_Start(frame, color, nil, nil, nil, nil, "CooldownCompanionGlow")
    else
        ShowPixelGlow(frame, color)
    end
end

local function ShowProcGlow(frame, color)
    if LCG then
        LCG.ButtonGlow_Start(frame, color, nil, "CooldownCompanionGlow")
    else
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(frame)
        else
            ShowPixelGlow(frame, color)
        end
    end
end

local function HideGlow(frame)
    if LCG then
        LCG.PixelGlow_Stop(frame, "CooldownCompanionGlow")
        LCG.AutoCastGlow_Stop(frame, "CooldownCompanionGlow")
        LCG.ButtonGlow_Stop(frame, "CooldownCompanionGlow")
    else
        if frame.glowBorder then
            frame.glowBorder:Hide()
        end
        if ActionButton_HideOverlayGlow then
            ActionButton_HideOverlayGlow(frame)
        end
    end
end

function CooldownCompanion:CreateButtonFrame(parent, index, buttonData, style)
    local width, height
    local maintainAspectRatio = style.maintainAspectRatio

    if maintainAspectRatio then
        -- Use separate width/height when maintaining aspect ratio
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    else
        -- Use buttonSize and widthRatio when stretching
        local size = style.buttonSize or ST.BUTTON_SIZE
        local widthRatio = style.iconWidthRatio or 1.0
        width = size * widthRatio
        height = size
    end

    -- Create main button frame
    local button = CreateFrame("Frame", parent:GetName() .. "Button" .. index, parent)
    button:SetSize(width, height)
    
    -- Background
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))
    
    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    -- Handle aspect ratio via texture cropping
    if maintainAspectRatio and width ~= height then
        -- Crop the icon texture to match frame shape while keeping icon undistorted
        -- Default visible texture range: 0.08 to 0.92 (0.84 of texture)
        local texMin, texMax = 0.08, 0.92
        local texRange = texMax - texMin
        local aspectRatio = width / height

        if aspectRatio > 1.0 then
            -- Frame is wider than tall - crop top/bottom of icon
            local visibleHeight = texRange / aspectRatio
            local cropAmount = (texRange - visibleHeight) / 2
            button.icon:SetTexCoord(texMin, texMax, texMin + cropAmount, texMax - cropAmount)
        else
            -- Frame is taller than wide - crop left/right of icon
            local visibleWidth = texRange * aspectRatio
            local cropAmount = (texRange - visibleWidth) / 2
            button.icon:SetTexCoord(texMin + cropAmount, texMax - cropAmount, texMin, texMax)
        end
    else
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    -- Border frame
    button.border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.border:SetAllPoints()
    button.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = borderSize,
    })
    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.border:SetBackdropBorderColor(unpack(borderColor))
    button.border:EnableMouse(false) -- Never capture mouse on border

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(true)
    button.cooldown:SetDrawSwipe(true)
    button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    button.cooldown:SetHideCountdownNumbers(not style.showCooldownText)
    button.cooldown:EnableMouse(false) -- Never capture mouse on cooldown

    -- Apply custom cooldown text font settings
    local cooldownFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
    end
    
    -- Stack count text (for items)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.count:SetText("")
    
    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style
    
    -- Set icon
    self:UpdateButtonIcon(button)
    
    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end
    
    button.SetGlow = function(self, show)
        CooldownCompanion:SetButtonGlow(self, show)
    end
    
    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateButtonStyle(self, newStyle)
    end
    
    -- Tooltip and clickthrough handling
    -- If tooltips are off OR clickthrough is enabled, disable mouse completely
    -- This allows camera movement (LMB/RMB) to pass through the icons
    local showTooltips = style.showTooltips ~= false
    local enableClickthrough = not showTooltips or style.enableClickthrough

    -- EnableMouse(false) = full click-through, camera works, no tooltips
    -- EnableMouse(true) = captures mouse, tooltips work, blocks camera
    button:EnableMouse(not enableClickthrough)

    button:SetScript("OnEnter", function(self)
        if not self.style.showTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.buttonData.type == "spell" then
            GameTooltip:SetSpellByID(self.buttonData.id)
        elseif self.buttonData.type == "item" then
            GameTooltip:SetItemByID(self.buttonData.id)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    return button
end

function CooldownCompanion:UpdateButtonIcon(button)
    local buttonData = button.buttonData
    local icon
    
    if buttonData.type == "spell" then
        local name, iconId = self:GetSpellInfo(buttonData.id)
        icon = iconId
    elseif buttonData.type == "item" then
        local name, iconId = self:GetItemInfo(buttonData.id)
        icon = iconId
    end
    
    if icon then
        button.icon:SetTexture(icon)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local isOnCooldown = false

    -- Use pcall and avoid ANY Lua operations on returned values
    -- Secret values can only be passed directly to Blizzard functions
    pcall(function()
        if buttonData.type == "spell" then
            local cooldownInfo = C_Spell.GetSpellCooldown(buttonData.id)
            if cooldownInfo then
                -- Pass values directly to SetCooldown - it handles secret values internally
                button.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                -- Check if on cooldown for desaturation (duration > 1.5 to ignore GCD)
                isOnCooldown = cooldownInfo.duration and cooldownInfo.duration > 1.5
            end
        elseif buttonData.type == "item" then
            local start, duration = C_Item.GetItemCooldown(buttonData.id)
            -- Pass values directly without any nil checks on the values themselves
            button.cooldown:SetCooldown(start, duration)
            -- Check if on cooldown for desaturation
            isOnCooldown = duration and duration > 1.5
        end
    end)

    -- Handle desaturation based on cooldown state
    if style.desaturateOnCooldown then
        button.icon:SetDesaturated(isOnCooldown)
    else
        button.icon:SetDesaturated(false)
    end
end

function CooldownCompanion:SetButtonGlow(button, show)
    if show == nil then
        show = button.buttonData.showGlow
    end
    
    if show then
        local glowType = button.buttonData.glowType or "pixel"
        local glowColor = button.buttonData.glowColor or {1, 1, 0, 1}
        
        if glowType == "pixel" then
            ShowPixelGlow(button, glowColor)
        elseif glowType == "action" then
            ShowActionGlow(button, glowColor)
        elseif glowType == "proc" then
            ShowProcGlow(button, glowColor)
        end
    else
        HideGlow(button)
    end
end

function CooldownCompanion:UpdateButtonStyle(button, style)
    local width, height
    local maintainAspectRatio = style.maintainAspectRatio

    if maintainAspectRatio then
        -- Use separate width/height when maintaining aspect ratio
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    else
        -- Use buttonSize and widthRatio when stretching
        local size = style.buttonSize or ST.BUTTON_SIZE
        local widthRatio = style.iconWidthRatio or 1.0
        width = size * widthRatio
        height = size
    end

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE

    -- Store updated style reference
    button.style = style

    button:SetSize(width, height)

    -- Update icon position
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    -- Handle aspect ratio via texture cropping
    if maintainAspectRatio and width ~= height then
        -- Crop the icon texture to match frame shape while keeping icon undistorted
        local texMin, texMax = 0.08, 0.92
        local texRange = texMax - texMin
        local aspectRatio = width / height

        if aspectRatio > 1.0 then
            -- Frame is wider than tall - crop top/bottom of icon
            local visibleHeight = texRange / aspectRatio
            local cropAmount = (texRange - visibleHeight) / 2
            button.icon:SetTexCoord(texMin, texMax, texMin + cropAmount, texMax - cropAmount)
        else
            -- Frame is taller than wide - crop left/right of icon
            local visibleWidth = texRange * aspectRatio
            local cropAmount = (texRange - visibleWidth) / 2
            button.icon:SetTexCoord(texMin + cropAmount, texMax - cropAmount, texMin, texMax)
        end
    else
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Update border
    button.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = borderSize,
    })

    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.border:SetBackdropBorderColor(unpack(borderColor))

    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))

    -- Update cooldown text visibility and font
    button.cooldown:SetHideCountdownNumbers(not style.showCooldownText)

    -- Update cooldown font settings
    local cooldownFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
    end

    -- Update clickthrough based on tooltip settings
    -- If tooltips are off OR clickthrough is enabled, disable mouse completely
    local showTooltips = style.showTooltips ~= false
    local enableClickthrough = not showTooltips or style.enableClickthrough

    -- EnableMouse(false) = full click-through, camera works, no tooltips
    -- EnableMouse(true) = captures mouse, tooltips work, blocks camera
    button:EnableMouse(not enableClickthrough)
end
