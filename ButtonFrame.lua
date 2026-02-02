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

-- Returns true if the given item ID is equippable (trinkets, weapons, armor, etc.)
-- Caches result on buttonData to avoid repeated API calls.
local function IsItemEquippable(buttonData)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(buttonData.id)
    return equipLoc ~= nil and equipLoc ~= "" and not equipLoc:find("NON_EQUIP")
end
CooldownCompanion.IsItemEquippable = IsItemEquippable

-- Apply configurable strata (frame level) ordering to button sub-elements.
-- order: array of 4 keys {"cooldown","chargeText","procGlow","assistedHighlight"} or nil for default.
-- Index 1 = lowest layer (baseLevel+1), index 4 = highest (baseLevel+4).
-- Loss of Control is always baseLevel+5 (above all configurable elements).
local function ApplyStrataOrder(button, order)
    if not order or #order ~= 4 then
        order = ST.DEFAULT_STRATA_ORDER
    end
    local baseLevel = button:GetFrameLevel()

    -- Map element keys to their frames
    local frameMap = {
        cooldown = {button.cooldown},
        chargeText = {button.overlayFrame},
        procGlow = {button.procGlow},
        assistedHighlight = {
            button.assistedHighlight and button.assistedHighlight.solidFrame,
            button.assistedHighlight and button.assistedHighlight.blizzardFrame,
            button.assistedHighlight and button.assistedHighlight.procFrame,
        },
    }

    for i, key in ipairs(order) do
        local frames = frameMap[key]
        if frames then
            for _, frame in ipairs(frames) do
                if frame then
                    frame:SetFrameLevel(baseLevel + i)
                end
            end
        end
    end

    -- LoC always on top
    if button.locCooldown then
        button.locCooldown:SetFrameLevel(baseLevel + 5)
    end
end

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
local EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top    (full width)
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom (full width)
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, -1,  1,  1}, -- Left   (inset to avoid corner overlap)
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, -1,  0,  1}, -- Right  (inset to avoid corner overlap)
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
-- Per-axis overhang keeps the border flush with non-square icons.
local function FitHighlightFrame(frame, button, overhangPct)
    local w, h = button:GetSize()
    local pct = (overhangPct or 32) / 100
    local overhangW = w * pct
    local overhangH = h * pct

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", button, "CENTER")
    frame:SetSize(w, h)

    -- Resize child regions (flipbook textures) to overhang the frame edges
    for _, region in ipairs({frame:GetRegions()}) do
        if region.ClearAllPoints then
            region:ClearAllPoints()
            region:SetPoint("CENTER", frame, "CENTER")
            region:SetSize(w + overhangW * 2, h + overhangH * 2)
        end
    end
    -- Also handle textures nested inside child frames
    for _, child in ipairs({frame:GetChildren()}) do
        child:ClearAllPoints()
        child:SetPoint("CENTER", frame, "CENTER")
        child:SetSize(w + overhangW * 2, h + overhangH * 2)
        for _, region in ipairs({child:GetRegions()}) do
            if region.ClearAllPoints then
                region:ClearAllPoints()
                region:SetAllPoints(child)
            end
        end
    end
end

-- Apply a vertex color tint to a proc glow frame (ActionButtonSpellAlertTemplate).
-- The tint is multiplicative with the base golden texture, so warm colors work
-- best.  White {1,1,1,1} = default golden glow.
local function TintProcGlowFrame(frame, color)
    if not frame then return end
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    if frame.ProcStartFlipbook then
        frame.ProcStartFlipbook:SetVertexColor(r, g, b, a)
    end
    if frame.ProcLoopFlipbook then
        frame.ProcLoopFlipbook:SetVertexColor(r, g, b, a)
    end
end

-- Show or hide assisted highlight on a button based on the selected style.
-- Tracks current state to avoid restarting animations every tick.
local function SetAssistedHighlight(button, show)
    local hl = button.assistedHighlight
    if not hl then return end
    local highlightStyle = button.style and button.style.assistedHighlightStyle or "blizzard"

    -- Determine desired state, including color in cache key for solid/proc styles
    -- so color changes via settings invalidate the cache
    local colorKey
    if show and highlightStyle == "solid" then
        local c = button.style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        colorKey = string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4])
    elseif show and highlightStyle == "proc" then
        local c = button.style.assistedHighlightProcColor or {1, 1, 1, 1}
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
            TintProcGlowFrame(hl.procFrame, button.style.assistedHighlightProcColor or {1, 1, 1, 1})
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

-- Show or hide proc glow on a button.
-- Tracks state (including color) to avoid restarting animations every tick.
local function SetProcGlow(button, show)
    local frame = button.procGlow
    if not frame then return end

    -- Build a cache key that includes color so tint changes trigger an update
    local desiredState
    if show then
        local c = button.style and button.style.procGlowColor or {1, 1, 1, 1}
        desiredState = string.format("on%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4] or 1)
    end
    if button._procGlowActive == desiredState then return end
    button._procGlowActive = desiredState

    if show then
        TintProcGlowFrame(frame, button.style and button.style.procGlowColor or {1, 1, 1, 1})
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

-- Update loss-of-control cooldown on a button.
-- Uses a CooldownFrame to avoid comparing secret values — the raw start/duration
-- go directly to SetCooldown which handles them on the C side.
local function UpdateLossOfControl(button)
    if not button.locCooldown then return end

    if button.style.showLossOfControl and button.buttonData.type == "spell" then
        local locDuration = C_Spell.GetSpellLossOfControlCooldownDuration(button.buttonData.id)
        if locDuration then
            button.locCooldown:SetCooldownFromDurationObject(locDuration)
        else
            pcall(function()
                button.locCooldown:SetCooldown(C_Spell.GetSpellLossOfControlCooldown(button.buttonData.id))
            end)
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
    local baseLevel = button:GetFrameLevel()

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
    button.assistedHighlight.solidFrame = CreateFrame("Frame", nil, button)
    button.assistedHighlight.solidFrame:SetAllPoints()
    button.assistedHighlight.solidFrame:EnableMouse(false)
    button.assistedHighlight.solidTextures = {}
    for i = 1, 4 do
        local tex = button.assistedHighlight.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
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

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(true)
    button.cooldown:SetDrawSwipe(true)
    button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    button.cooldown:SetHideCountdownNumbers(not style.showCooldownText)
    -- Recursively disable mouse on cooldown and all its children (CooldownFrameTemplate has children)
    -- Always fully non-interactive: disable both clicks and motion
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Loss of control cooldown frame (red swipe showing lockout duration)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    local locColor = style.lossOfControlColor or {1, 0, 0, 0.5}
    button.locCooldown:SetSwipeColor(locColor[1], locColor[2], locColor[3], locColor[4])
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Proc glow frame (spell activation alert, separate from assisted highlight)
    local procGlowFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(procGlowFrame, button, style.procGlowOverhang or 32)
    SetFrameClickThroughRecursive(procGlowFrame, true, true)
    procGlowFrame:Hide()
    button.procGlow = procGlowFrame

    -- Apply custom cooldown text font settings
    local cooldownFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
        button._cdTextRegion = region
    end

    -- Stack count text (for items) — on overlay frame so it renders above cooldown swipe
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply custom count text font/anchor settings from per-button data
    if buttonData.hasCharges then
        local chargeFont = buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = buttonData.chargeFontSize or 12
        local chargeFontOutline = buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = buttonData.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = buttonData.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = buttonData.chargeXOffset or -2
        local chargeYOffset = buttonData.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF"
        local itemFontSize = buttonData.itemCountFontSize or 12
        local itemFontOutline = buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])

        local itemAnchor = buttonData.itemCountAnchor or "BOTTOMRIGHT"
        local itemXOffset = buttonData.itemCountXOffset or -2
        local itemYOffset = buttonData.itemCountYOffset or 2
        button.count:SetPoint(itemAnchor, itemXOffset, itemYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)

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
    local showTooltips = style.showTooltips == true
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            if self.buttonData.type == "spell" then
                GameTooltip:SetSpellByID(self._displaySpellId or self.buttonData.id)
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
    local displayId = buttonData.id

    if buttonData.type == "spell" then
        displayId = C_Spell.GetOverrideSpell(buttonData.id) or buttonData.id
        icon = C_Spell.GetSpellTexture(displayId)
    elseif buttonData.type == "item" then
        icon = C_Item.GetItemIconByID(buttonData.id)
    end

    button._displaySpellId = displayId

    if icon then
        button.icon:SetTexture(icon)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style

    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD
    if buttonData.type == "spell" then
        local spellCooldownDuration = C_Spell.GetSpellCooldownDuration(buttonData.id)
        if spellCooldownDuration then
            button.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
            fetchOk = true
        end
        pcall(function()
            local cooldownInfo = C_Spell.GetSpellCooldown(buttonData.id)
            if cooldownInfo then
                isOnGCD = cooldownInfo.isOnGCD
                if not fetchOk then
                    button.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                end
                fetchOk = true
            end
        end)
    elseif buttonData.type == "item" then
        local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
        button.cooldown:SetCooldown(cdStart, cdDuration)
        fetchOk = true
    end

    -- GCD suppression (isOnGCD is NeverSecret, always readable)
    if fetchOk then
        local suppressGCD = not style.showGCDSwipe and isOnGCD

        if suppressGCD then
            button.cooldown:Hide()
        else
            if not button.cooldown:IsShown() then
                button.cooldown:Show()
            end
        end
    end

    -- Cooldown text color: reapply each tick because WoW's CooldownFrame
    -- may reset the internal countdown FontString color during its update.
    if button._cdTextRegion and style.cooldownFontColor then
        local cc = style.cooldownFontColor
        button._cdTextRegion:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end

    -- Desaturation: driven entirely by the cooldown widget's own state.
    -- GetCooldownTimes() returns non-secret values even during restricted
    -- combat, so we can always reliably check if the widget has an active
    -- cooldown. This replaces all previous state-tracking approaches.
    if style.desaturateOnCooldown then
        local wantDesat = false
        if fetchOk and not isOnGCD then
            local _, widgetDuration = button.cooldown:GetCooldownTimes()
            wantDesat = widgetDuration and widgetDuration > 0
        end
        -- When isOnGCD is true, wantDesat stays false. This clears
        -- desaturation the moment GCD takes over from a real cooldown,
        -- and is a no-op after a fresh cast (already un-desaturated).
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    else
        if button._desaturated ~= false then
            button._desaturated = false
            button.icon:SetDesaturated(false)
        end
    end

    -- Icon tinting priority: out-of-range red > unusable dimming > normal white
    local r, g, b = 1, 1, 1
    if style.showOutOfRange then
        if buttonData.type == "spell" then
            if button._spellOutOfRange then
                r, g, b = 1, 0.2, 0.2
            end
        elseif buttonData.type == "item" then
            local inRange = IsItemInRange(buttonData.id, "target")
            -- inRange is nil when no target or item has no range; only tint on explicit false
            if inRange == false then
                r, g, b = 1, 0.2, 0.2
            end
        end
    end
    if r == 1 and g == 1 and b == 1 and style.showUnusable then
        if buttonData.type == "spell" then
            local isUsable, insufficientPower = C_Spell.IsSpellUsable(buttonData.id)
            if insufficientPower then
                local uc = style.unusableColor or {0.3, 0.3, 0.6}
                r, g, b = uc[1], uc[2], uc[3]
            end
        elseif buttonData.type == "item" then
            local usable, noMana = IsUsableItem(buttonData.id)
            if not usable then
                local uc = style.unusableColor or {0.3, 0.3, 0.6}
                r, g, b = uc[1], uc[2], uc[3]
            end
        end
    end
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b then
        button._vertexR, button._vertexG, button._vertexB = r, g, b
        button.icon:SetVertexColor(r, g, b)
    end

    -- Charge count (spells with hasCharges enabled only)
    -- For restricted spells the charge fields are "secret values" during
    -- combat — they look like numbers but reject Lua arithmetic/comparison.
    -- C-side widget methods (SetText, SetCooldown) can handle them just
    -- like print() can, so we pass API values directly to the UI and only
    -- fall back to Lua-side estimation when the API call itself fails.
    if buttonData.type == "spell" and buttonData.hasCharges then
        local charges
        pcall(function()
            charges = C_Spell.GetSpellCharges(buttonData.id)
        end)

        -- Try to read charge values as normal Lua numbers (works out of
        -- combat and for non-restricted spells during combat).
        local countOk, cur, mx, cdStart, cdDur
        if charges then
            countOk, cur, mx, cdStart, cdDur = pcall(function()
                if charges.maxCharges > 1 then
                    return charges.currentCharges, charges.maxCharges,
                           charges.cooldownStartTime, charges.cooldownDuration
                end
            end)
        end

        if countOk and cur ~= nil then
            -- API fully readable as Lua numbers — update all caches
            button._chargeCount = cur
            button._chargeMax = mx
            button._chargeCDStart = cdStart
            button._chargeCDDuration = cdDur
            if cdDur and cdDur > 0 then
                buttonData.chargeCooldownDuration = cdDur
            end
        elseif button._chargeCount then
            -- Values unreadable as Lua numbers: estimate for comparison-
            -- dependent logic (desaturation, radial gating)
            if button._chargeCount < button._chargeMax
               and button._chargeCDStart and button._chargeCDDuration
               and button._chargeCDDuration > 0 then
                local now = GetTime()
                while button._chargeCount < button._chargeMax
                      and now >= button._chargeCDStart + button._chargeCDDuration do
                    button._chargeCount = button._chargeCount + 1
                    button._chargeCDStart = button._chargeCDStart + button._chargeCDDuration
                end
            end
        end

        -- Display charge text.  Prefer passing the raw API value to SetText
        -- (C-side, handles secret values like print() does).  Fall back to
        -- the Lua-side estimated count only when the API table is nil.
        local textSet = false
        if charges then
            textSet = pcall(function()
                button.count:SetText(charges.currentCharges)
            end)
        end
        if not textSet then
            local displayText = button._chargeCount or ""
            if button._chargeText ~= displayText then
                button._chargeText = displayText
                button.count:SetText(displayText)
            end
        end

        -- Show recharge radial via Duration Object (not secret-restricted).
        -- Falls back to legacy charge timing when Duration Object unavailable.
        local chargeDuration = C_Spell.GetSpellChargeDuration(buttonData.id)
        if chargeDuration then
            button.cooldown:SetCooldownFromDurationObject(chargeDuration)
        elseif charges then
            pcall(function()
                button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
            end)
        end
    end

    -- Item count display (inventory quantity for non-equipment tracked items)
    if buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local count = C_Item.GetItemCount(buttonData.id)
        if button._itemCount ~= count then
            button._itemCount = count
            if count and count > 1 then
                button.count:SetText(count)
            else
                button.count:SetText("")
            end
        end
    end

    -- Charge text color: applied after charge tracking so _chargeCount is current.
    if buttonData.chargeFontColor or buttonData.chargeFontColorMissing then
        local atMax = button._chargeCount and button._chargeMax
            and button._chargeCount >= button._chargeMax
        local cc
        if not atMax and buttonData.chargeFontColorMissing then
            cc = buttonData.chargeFontColorMissing
        else
            cc = buttonData.chargeFontColor or {1, 1, 1, 1}
        end
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end

    -- Loss of control overlay
    UpdateLossOfControl(button)

    -- Assisted highlight glow
    if button.assistedHighlight then
        local assistedSpellID = CooldownCompanion.assistedSpellID
        local displayId = button._displaySpellId or buttonData.id
        local showHighlight = style.showAssistedHighlight
            and buttonData.type == "spell"
            and assistedSpellID
            and (displayId == assistedSpellID or buttonData.id == assistedSpellID)

        SetAssistedHighlight(button, showHighlight)
    end

    -- Proc glow (spell activation overlay)
    if button.procGlow then
        local showProc = false
        if button._procGlowPreview then
            showProc = true
        elseif buttonData.procGlow == true and buttonData.type == "spell" then
            showProc = C_SpellActivationOverlay.IsSpellOverlayed(buttonData.id) or false
        end
        SetProcGlow(button, showProc)
    end
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
    button._chargeCount = nil
    button._chargeMax = nil
    button._chargeCDStart = nil
    button._chargeCDDuration = nil
    button._procGlowActive = nil
    button._displaySpellId = nil
    button._spellOutOfRange = nil
    button._itemCount = nil

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
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    end

    -- Update count text font/anchor settings from per-button data
    button.count:ClearAllPoints()
    if button.buttonData and button.buttonData.hasCharges then
        local chargeFont = button.buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = button.buttonData.chargeFontSize or 12
        local chargeFontOutline = button.buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = button.buttonData.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = button.buttonData.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = button.buttonData.chargeXOffset or -2
        local chargeYOffset = button.buttonData.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = button.buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF"
        local itemFontSize = button.buttonData.itemCountFontSize or 12
        local itemFontOutline = button.buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = button.buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])

        local itemAnchor = button.buttonData.itemCountAnchor or "BOTTOMRIGHT"
        local itemXOffset = button.buttonData.itemCountXOffset or -2
        local itemYOffset = button.buttonData.itemCountYOffset or 2
        button.count:SetPoint(itemAnchor, itemXOffset, itemYOffset)
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

    -- Update loss of control cooldown frame
    if button.locCooldown then
        local locColor = style.lossOfControlColor or {1, 0, 0, 0.5}
        button.locCooldown:SetSwipeColor(locColor[1], locColor[2], locColor[3], locColor[4])
        button.locCooldown:Clear()
    end

    -- Update proc glow frame
    if button.procGlow then
        FitHighlightFrame(button.procGlow, button, style.procGlowOverhang or 32)
        SetProcGlow(button, false)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips == true
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            if self.buttonData.type == "spell" then
                GameTooltip:SetSpellByID(self._displaySpellId or self.buttonData.id)
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

-- Set or clear proc glow preview on a specific button.
-- Used by the config panel to show what the glow looks like.
function CooldownCompanion:SetProcGlowPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._procGlowPreview = show or nil
            return
        end
    end
end

-- Clear all proc glow previews across every group.
function CooldownCompanion:ClearAllProcGlowPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._procGlowPreview = nil
        end
    end
end
