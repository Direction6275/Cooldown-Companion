--[[
    CooldownCompanion - ButtonFrame
    Individual button frames with cooldown animations

    Note: WoW 12.0 "secret value" API blocks direct comparison of cooldown data.
    We pass values directly to SetCooldown and let the internal WoW code handle them.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Button Frame Pool
local buttonPool = {}

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
local EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, 0,  1,  0}, -- Left
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 0,  0,  0}, -- Right
}

-- Apply edge positions to 4 border/highlight textures using the shared spec
local function ApplyEdgePositions(textures, button, size)
    for i, spec in ipairs(EDGE_ANCHOR_SPEC) do
        local tex = textures[i]
        tex:ClearAllPoints()
        tex:SetPoint(spec[1], button, spec[2], spec[5] * size, spec[6] * size)
        tex:SetPoint(spec[3], button, spec[4], spec[7] * size, spec[8] * size)
    end
end

-- Helper function to make a frame click-through
-- disableClicks: prevent LMB/RMB clicks (allows camera movement pass-through)
-- disableMotion: prevent OnEnter/OnLeave hover events (disables tooltips)
local function SetFrameClickThrough(frame, disableClicks, disableMotion)
    if not frame then return end
    local inCombat = InCombatLockdown()

    if disableClicks then
        -- Disable mouse click interaction for camera pass-through
        -- SetMouseClickEnabled and SetPropagateMouseClicks are protected in combat
        if not inCombat then
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
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnMouseUp", nil)
    else
        if not inCombat then
            if frame.SetMouseClickEnabled then
                frame:SetMouseClickEnabled(true)
            end
            if frame.SetPropagateMouseClicks then
                frame:SetPropagateMouseClicks(false)
            end
        end
    end

    if disableMotion then
        -- Disable mouse motion (hover) events
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(false)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(true)
            end
        end
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    else
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(true)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(false)
            end
        end
    end

    -- EnableMouse must be true if we want motion events (tooltips)
    -- Only fully disable if both clicks and motion are disabled
    if not inCombat then
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
end

-- Recursively apply click-through to frame and all children
local function SetFrameClickThroughRecursive(frame, disableClicks, disableMotion)
    SetFrameClickThrough(frame, disableClicks, disableMotion)
    -- Apply to all child frames
    for _, child in ipairs({frame:GetChildren()}) do
        SetFrameClickThroughRecursive(child, disableClicks, disableMotion)
    end
end

-- Fit a Blizzard highlight template frame to a button.
-- The flipbook texture must overhang the button edges to create the border effect.
-- Original template: 45x45 frame, 66x66 texture => ~23% overhang per side.
local function FitHighlightFrame(frame, button, overhangPct)
    local w, h = button:GetSize()
    local overhang = math.max(w, h) * (overhangPct or 32) / 100

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", button, "CENTER")
    frame:SetSize(w, h)

    -- Resize child regions (flipbook textures) to overhang the frame edges
    for _, region in ipairs({frame:GetRegions()}) do
        if region.ClearAllPoints then
            region:ClearAllPoints()
            region:SetPoint("CENTER", frame, "CENTER")
            region:SetSize(w + overhang * 2, h + overhang * 2)
        end
    end
    -- Also handle textures nested inside child frames
    for _, child in ipairs({frame:GetChildren()}) do
        child:ClearAllPoints()
        child:SetPoint("CENTER", frame, "CENTER")
        child:SetSize(w + overhang * 2, h + overhang * 2)
        for _, region in ipairs({child:GetRegions()}) do
            if region.ClearAllPoints then
                region:ClearAllPoints()
                region:SetAllPoints(child)
            end
        end
    end
end

-- Show or hide assisted highlight on a button based on the selected style.
-- Tracks current state to avoid restarting animations every tick.
local function SetAssistedHighlight(button, show)
    local hl = button.assistedHighlight
    if not hl then return end
    local highlightStyle = button.style and button.style.assistedHighlightStyle or "blizzard"

    -- Determine desired state, including color in cache key for solid style
    -- so color changes via settings invalidate the cache
    local colorKey
    if show and highlightStyle == "solid" then
        local c = button.style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        colorKey = string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4])
    end
    local desiredState = show and (highlightStyle .. (colorKey or "")) or nil

    -- Skip show/hide if state hasn't changed (prevents animation restarts)
    if hl.currentState == desiredState then return end
    hl.currentState = desiredState

    -- Hide all styles (only hide parent frames, not individual textures —
    -- template animations control alpha on child textures internally)
    for _, tex in ipairs(hl.solidTextures or {}) do
        tex:Hide()
    end
    if hl.blizzardFrame then
        if hl.blizzardFrame.Flipbook and hl.blizzardFrame.Flipbook.Anim then
            hl.blizzardFrame.Flipbook.Anim:Stop()
        end
        hl.blizzardFrame:Hide()
    end
    if hl.procFrame then
        if hl.procFrame.ProcStartAnim then hl.procFrame.ProcStartAnim:Stop() end
        if hl.procFrame.ProcLoop then hl.procFrame.ProcLoop:Stop() end
        hl.procFrame:Hide()
    end

    if not show then return end

    -- Show the selected style
    if highlightStyle == "solid" then
        local color = button.style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        for _, tex in ipairs(hl.solidTextures) do
            tex:SetColorTexture(unpack(color))
            tex:Show()
        end
    elseif highlightStyle == "blizzard" then
        if hl.blizzardFrame then
            hl.blizzardFrame:Show()
            if hl.blizzardFrame.Flipbook and hl.blizzardFrame.Flipbook.Anim then
                hl.blizzardFrame.Flipbook.Anim:Play()
            end
        end
    elseif highlightStyle == "proc" then
        if hl.procFrame then
            hl.procFrame:Show()
            -- Skip the intro burst (ProcStartAnim) and go straight to the loop
            if hl.procFrame.ProcStartFlipbook then
                hl.procFrame.ProcStartFlipbook:SetAlpha(0)
            end
            if hl.procFrame.ProcLoopFlipbook then
                hl.procFrame.ProcLoopFlipbook:SetAlpha(1)
            end
            if hl.procFrame.ProcLoop then
                hl.procFrame.ProcLoop:Play()
            end
        end
    end
end

-- Show or hide loss-of-control overlay on a button.
-- Caches state to avoid redundant show/hide calls.
local function UpdateLossOfControl(button)
    local style = button.style
    local buttonData = button.buttonData
    if not button.locOverlay then return end
    local showLoc = false
    if style.showLossOfControl and buttonData.type == "spell" then
        local ok, start, duration = pcall(C_Spell.GetSpellLossOfControlCooldown, buttonData.id)
        if ok and duration and duration > 0 then
            showLoc = true
        end
    end
    if button._locActive ~= showLoc then
        button._locActive = showLoc
        if showLoc then
            button.locOverlay:Show()
        else
            button.locOverlay:Hide()
        end
    end
end

-- Show or hide proc glow on a button.
-- Tracks state to avoid restarting animations each tick.
local function SetProcGlow(button, show)
    local frame = button.procGlow
    if not frame then return end
    if button._procGlowActive == show then return end
    button._procGlowActive = show
    if show then
        frame:Show()
        -- Skip the intro burst and go straight to the loop
        if frame.ProcStartFlipbook then
            frame.ProcStartFlipbook:SetAlpha(0)
        end
        if frame.ProcLoopFlipbook then
            frame.ProcLoopFlipbook:SetAlpha(1)
        end
        if frame.ProcLoop then
            frame.ProcLoop:Play()
        end
    else
        if frame.ProcStartAnim then frame.ProcStartAnim:Stop() end
        if frame.ProcLoop then frame.ProcLoop:Stop() end
        frame:Hide()
    end
end

-- Format a duration in seconds to a compact string (e.g. "8", "1m", "2h")
local function FormatAuraDuration(remaining)
    if remaining >= 3600 then
        return math.floor(remaining / 3600) .. "h"
    elseif remaining >= 60 then
        return math.floor(remaining / 60) .. "m"
    else
        return math.floor(remaining + 0.5) .. ""
    end
end

-- Update aura duration reverse swipe and time text on a button.
local function UpdateAuraDuration(button)
    local style = button.style
    local buttonData = button.buttonData
    if not button.auraCooldown then return end
    if buttonData.type ~= "spell" then
        if button._auraExpTime ~= 0 then
            button._auraExpTime = 0
            button.auraCooldown:Hide()
            button.auraDurationText:SetText("")
        end
        return
    end

    -- Determine if aura tracking is enabled for this button
    local enabled
    if buttonData.auraEnabled == true then
        enabled = true
    elseif buttonData.auraEnabled == false then
        enabled = false
    else
        enabled = style.showAuraDuration
    end

    if not enabled then
        if button._auraExpTime ~= 0 then
            button._auraExpTime = 0
            button.auraCooldown:Hide()
            button.auraDurationText:SetText("")
        end
        return
    end

    local auraSpellId = buttonData.auraSpellId or buttonData.id
    local auraUnit = buttonData.auraUnit or "player"
    local auraData

    if auraUnit == "player" then
        local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, auraSpellId)
        if ok then auraData = result end
    else
        -- Iterate target auras to find matching spellId
        pcall(function()
            for i = 1, 40 do
                local data = C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
                if not data then break end
                if data.spellId == auraSpellId then
                    auraData = data
                    return
                end
            end
            for i = 1, 40 do
                local data = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
                if not data then break end
                if data.spellId == auraSpellId then
                    auraData = data
                    return
                end
            end
        end)
    end

    if auraData and auraData.duration and auraData.duration > 0 and auraData.expirationTime then
        local expTime = auraData.expirationTime
        if button._auraExpTime ~= expTime then
            button._auraExpTime = expTime
            button.auraCooldown:SetCooldown(expTime - auraData.duration, auraData.duration)
            button.auraCooldown:Show()
        end
        -- Update time text every tick
        if style.showAuraDurationText ~= false then
            local remaining = expTime - GetTime()
            if remaining < 0 then remaining = 0 end
            local text = FormatAuraDuration(remaining)
            if button._auraDurText ~= text then
                button._auraDurText = text
                button.auraDurationText:SetText(text)
            end
        else
            if button._auraDurText ~= "" then
                button._auraDurText = ""
                button.auraDurationText:SetText("")
            end
        end
    else
        if button._auraExpTime ~= 0 then
            button._auraExpTime = 0
            button.auraCooldown:Hide()
        end
        if button._auraDurText ~= "" then
            button._auraDurText = ""
            button.auraDurationText:SetText("")
        end
    end
end

function CooldownCompanion:CreateButtonFrame(parent, index, buttonData, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
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

    -- Handle aspect ratio via texture cropping (always crop to prevent stretching)
    if width ~= height then
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
    
    -- Loss of control overlay (red tint, above icon)
    button.locOverlay = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.locOverlay:SetAllPoints(button.icon)
    button.locOverlay:SetColorTexture(unpack(style.lossOfControlColor or {1, 0, 0, 0.5}))
    button.locOverlay:Hide()

    -- Border using textures (not BackdropTemplate which captures mouse)
    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.borderTextures = {}

    -- Create 4 edge textures for border using shared anchor spec
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button, borderSize)

    -- Assisted highlight overlays (multiple styles, all hidden by default)
    button.assistedHighlight = {}

    -- Solid border: 4 edge textures
    local highlightSize = style.assistedHighlightBorderSize or 2
    local hlColor = style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
    button.assistedHighlight.solidTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetColorTexture(unpack(hlColor))
        tex:Hide()
        button.assistedHighlight.solidTextures[i] = tex
    end
    ApplyEdgePositions(button.assistedHighlight.solidTextures, button, highlightSize)

    -- Blizzard assisted combat highlight (marching ants flipbook)
    local blizzFrame = CreateFrame("Frame", nil, button, "ActionBarButtonAssistedCombatHighlightTemplate")
    FitHighlightFrame(blizzFrame, button, style.assistedHighlightBlizzardOverhang)
    SetFrameClickThroughRecursive(blizzFrame, true, true)
    blizzFrame:Hide()
    button.assistedHighlight.blizzardFrame = blizzFrame

    -- Proc glow (spell activation alert flipbook)
    local procFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(procFrame, button, style.assistedHighlightProcOverhang)
    SetFrameClickThroughRecursive(procFrame, true, true)
    procFrame:Hide()
    button.assistedHighlight.procFrame = procFrame

    -- Proc glow frame (spell activation, separate from assisted highlight)
    local procGlowFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(procGlowFrame, button, style.procGlowOverhang or 32)
    SetFrameClickThroughRecursive(procGlowFrame, true, true)
    procGlowFrame:Hide()
    button.procGlow = procGlowFrame

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(true)
    button.cooldown:SetDrawSwipe(true)
    button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    button.cooldown:SetHideCountdownNumbers(not style.showCooldownText)
    -- Clear desaturation when cooldown expires (C-side callback, works during combat)
    button.cooldown:SetScript("OnCooldownDone", function()
        if button.style and button.style.desaturateOnCooldown then
            button._desaturated = false
            button.icon:SetDesaturated(false)
        end
    end)
    -- Recursively disable mouse on cooldown and all its children (CooldownFrameTemplate has children)
    -- Always fully non-interactive: disable both clicks and motion
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Aura duration reverse swipe (above cooldown swipe)
    local name = button:GetName()
    button.auraCooldown = CreateFrame("Cooldown", name.."AuraCooldown", button, "CooldownFrameTemplate")
    button.auraCooldown:SetAllPoints(button.icon)
    button.auraCooldown:SetDrawEdge(true)
    button.auraCooldown:SetDrawSwipe(true)
    button.auraCooldown:SetSwipeColor(unpack(style.auraDurationSwipeColor or {0.1, 0.6, 0.1, 0.4}))
    button.auraCooldown:SetReverse(true)
    button.auraCooldown:SetHideCountdownNumbers(true)
    button.auraCooldown:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.auraCooldown:Hide()
    SetFrameClickThroughRecursive(button.auraCooldown, true, true)

    -- Aura duration text (top-left)
    button.auraDurationText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.auraDurationText:SetFont("Fonts\\FRIZQT__.TTF", style.auraDurationFontSize or 10, "OUTLINE")
    button.auraDurationText:SetPoint("TOPLEFT", 2, -2)
    button.auraDurationText:SetTextColor(0.5, 1, 0.5, 1)
    button.auraDurationText:SetText("")

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
    button.count:SetText("")

    -- Apply custom charge text font/anchor settings from per-button data
    if buttonData.hasCharges then
        local chargeFont = buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = buttonData.chargeFontSize or 12
        local chargeFontOutline = buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)

        local chargeAnchor = buttonData.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = buttonData.chargeXOffset or -2
        local chargeYOffset = buttonData.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    
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
    
    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateButtonStyle(self, newStyle)
    end
    
    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips ~= false
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.assistedHighlight then
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow, true, true)
    end
    if button.auraCooldown then
        SetFrameClickThroughRecursive(button.auraCooldown, true, true)
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
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
    end

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

    -- Fetch cooldown values once.
    -- In WoW 12.0+, cooldown fields may be "secret values" during combat that
    -- error on comparison but can be passed directly to SetCooldown (C-side).
    -- We capture raw values first, then attempt comparisons separately.
    local cdStart, cdDuration, fetchOk, isOnGCD, isRealCD
    pcall(function()
        if buttonData.type == "spell" then
            local cooldownInfo = C_Spell.GetSpellCooldown(buttonData.id)
            if cooldownInfo then
                cdStart = cooldownInfo.startTime
                cdDuration = cooldownInfo.duration
                isOnGCD = cooldownInfo.isOnGCD
                fetchOk = true
            end
        elseif buttonData.type == "item" then
            cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
            fetchOk = true
        end
    end)

    -- Determine real-CD vs GCD status (may fail with secret values; that's OK)
    if fetchOk then
        pcall(function()
            if buttonData.type == "spell" then
                isRealCD = cdDuration > 0 and not isOnGCD
            elseif buttonData.type == "item" then
                isRealCD = cdDuration and cdDuration > 1.5
            end
        end)
    end

    if fetchOk then
        -- GCD suppression (wrapped for secret-value safety)
        local suppressGCD = false
        if style.showGCDSwipe == false then
            pcall(function()
                suppressGCD = isOnGCD and true or false
            end)
        end

        if suppressGCD then
            button.cooldown:Hide()
        else
            if not button.cooldown:IsShown() then
                button.cooldown:Show()
            end
            button.cooldown:SetCooldown(cdStart, cdDuration)
        end
    end

    -- Desaturation: reuse cooldown data from the single fetch above.
    -- During combat, cooldown values may be secret so isRealCD stays nil.
    -- In that case we keep the current desaturation state. Spells cast during
    -- combat are desaturated via OnSpellCast -> DesaturateSpellOnCast instead.
    if style.desaturateOnCooldown then
        if fetchOk and isRealCD ~= nil then
            local wantDesat = isRealCD
            if button._desaturated ~= wantDesat then
                button._desaturated = wantDesat
                button.icon:SetDesaturated(wantDesat)
            end
        end
        -- If isRealCD is nil (secret values), keep current desaturation state
    else
        if button._desaturated ~= false then
            button._desaturated = false
            button.icon:SetDesaturated(false)
        end
    end

    -- Icon tinting priority: out-of-range red > unusable dimming > normal white
    local r, g, b = 1, 1, 1
    if style.showOutOfRange and buttonData.type == "spell" then
        local inRange = C_Spell.IsSpellInRange(buttonData.id, "target")
        if inRange == false then
            r, g, b = 1, 0.2, 0.2
        end
    end
    if r == 1 and g == 1 and b == 1 and style.showUnusable and buttonData.type == "spell" then
        local ok, isUsable, insufficientPower = pcall(C_Spell.IsSpellUsable, buttonData.id)
        if ok and insufficientPower then
            local uc = style.unusableColor or {0.3, 0.3, 0.6}
            r, g, b = uc[1], uc[2], uc[3]
        end
    end
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b then
        button._vertexR, button._vertexG, button._vertexB = r, g, b
        button.icon:SetVertexColor(r, g, b)
    end

    -- Charge count (spells with hasCharges enabled only)
    -- Wrapped in pcall because charge fields are secret values during combat
    if buttonData.type == "spell" and buttonData.hasCharges then
        local ok, text = pcall(function()
            local charges = C_Spell.GetSpellCharges(buttonData.id)
            if charges and charges.maxCharges > 1 then
                return charges.currentCharges
            end
        end)
        if ok then
            local newText = text or ""
            if button._chargeText ~= newText then
                button._chargeText = newText
                button.count:SetText(newText)
            end
        end
        -- If pcall failed (secret values), keep current text
    end

    -- Loss of control overlay
    UpdateLossOfControl(button)

    -- Assisted highlight glow
    if button.assistedHighlight then
        local assistedSpellID = CooldownCompanion.assistedSpellID
        local showHighlight = style.showAssistedHighlight
            and buttonData.type == "spell"
            and assistedSpellID
            and buttonData.id == assistedSpellID

        SetAssistedHighlight(button, showHighlight)
    end

    -- Proc glow (spell activation overlay, separate from assisted highlight)
    if button.procGlow then
        local showProc = false
        if style.showProcGlow ~= false and buttonData.type == "spell" then
            local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, buttonData.id)
            if ok then showProc = overlayed or false end
        end
        SetProcGlow(button, showProc)
    end

    -- Aura duration reverse swipe + time text
    UpdateAuraDuration(button)
end

function CooldownCompanion:UpdateButtonStyle(button, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE

    -- Store updated style reference
    button.style = style

    -- Invalidate cached widget state so next tick reapplies everything
    button._desaturated = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._chargeText = nil
    button._locActive = nil
    button._procGlowActive = nil
    button._auraExpTime = nil
    button._auraDurText = nil

    button:SetSize(width, height)

    -- Update icon position
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    -- Handle aspect ratio via texture cropping (always crop to prevent stretching)
    if width ~= height then
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

    -- Update border textures
    local borderColor = style.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button, borderSize)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

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

    -- Update charge text font/anchor settings from per-button data
    button.count:ClearAllPoints()
    if button.buttonData and button.buttonData.hasCharges then
        local chargeFont = button.buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = button.buttonData.chargeFontSize or 12
        local chargeFontOutline = button.buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)

        local chargeAnchor = button.buttonData.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = button.buttonData.chargeXOffset or -2
        local chargeYOffset = button.buttonData.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end

    -- Update highlight overlay positions and hide all
    if button.assistedHighlight then
        local highlightSize = style.assistedHighlightBorderSize or 2
        ApplyEdgePositions(button.assistedHighlight.solidTextures, button, highlightSize)
        if button.assistedHighlight.blizzardFrame then
            FitHighlightFrame(button.assistedHighlight.blizzardFrame, button, style.assistedHighlightBlizzardOverhang)
        end
        if button.assistedHighlight.procFrame then
            FitHighlightFrame(button.assistedHighlight.procFrame, button, style.assistedHighlightProcOverhang)
        end
        button.assistedHighlight.currentState = nil -- reset so next tick re-applies
        SetAssistedHighlight(button, false)
    end

    -- Update loss of control overlay color
    if button.locOverlay then
        button.locOverlay:SetColorTexture(unpack(style.lossOfControlColor or {1, 0, 0, 0.5}))
        button.locOverlay:Hide()
    end

    -- Update proc glow frame
    if button.procGlow then
        FitHighlightFrame(button.procGlow, button, style.procGlowOverhang or 32)
        if button.procGlow.ProcStartAnim then button.procGlow.ProcStartAnim:Stop() end
        if button.procGlow.ProcLoop then button.procGlow.ProcLoop:Stop() end
        button.procGlow:Hide()
    end

    -- Update aura duration overlay
    if button.auraCooldown then
        button.auraCooldown:SetSwipeColor(unpack(style.auraDurationSwipeColor or {0.1, 0.6, 0.1, 0.4}))
        button.auraCooldown:Hide()
    end
    if button.auraDurationText then
        button.auraDurationText:SetFont("Fonts\\FRIZQT__.TTF", style.auraDurationFontSize or 10, "OUTLINE")
        button.auraDurationText:SetText("")
    end

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips ~= false
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.assistedHighlight then
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow, true, true)
    end
    if button.auraCooldown then
        SetFrameClickThroughRecursive(button.auraCooldown, true, true)
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
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
    end
end
