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

-- Forward declarations for bar mode functions (defined at end of file)
local FormatBarTime
local UpdateBarDisplay
local SetBarAuraEffect

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

    -- Build a cache key that includes color and size so changes trigger an update
    local desiredState
    if show then
        local c = button.style and button.style.procGlowColor or {1, 1, 1, 1}
        local sz = button.style and button.style.procGlowOverhang or 32
        desiredState = string.format("on%.2f%.2f%.2f%.2f%d", c[1], c[2], c[3], c[4] or 1, sz)
    end
    if button._procGlowActive == desiredState then return end
    button._procGlowActive = desiredState

    if show then
        FitHighlightFrame(frame, button, button.style and button.style.procGlowOverhang or 32)
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

-- Show or hide aura active glow on a button.
-- Supports "solid" (colored border) and "glow" (animated proc-style) styles.
-- Tracks state (style + color + size) to avoid restarting animations every tick.
local function SetAuraGlow(button, show)
    local ag = button.auraGlow
    if not ag then return end

    -- Build cache key from style + color + size
    local desiredState
    if show then
        local bd = button.buttonData
        local style = bd.auraGlowStyle or "none"
        if style ~= "none" then
            local c = bd.auraGlowColor or {1, 0.84, 0, 0.9}
            local sz = bd.auraGlowSize or (style == "solid" and 2 or 32)
            desiredState = string.format("%s%.2f%.2f%.2f%.2f%d", style, c[1], c[2], c[3], c[4] or 0.9, sz)
        end
    end

    if button._auraGlowActive == desiredState then return end
    button._auraGlowActive = desiredState

    -- Hide all styles
    for _, tex in ipairs(ag.solidTextures) do
        tex:Hide()
    end
    if ag.procFrame then
        if ag.procFrame.ProcStartAnim then ag.procFrame.ProcStartAnim:Stop() end
        if ag.procFrame.ProcLoop then ag.procFrame.ProcLoop:Stop() end
        ag.procFrame:Hide()
    end

    if not desiredState then return end

    local bd = button.buttonData
    local style = bd.auraGlowStyle
    local color = bd.auraGlowColor or {1, 0.84, 0, 0.9}
    local size = bd.auraGlowSize

    if style == "solid" then
        size = size or 2
        ApplyEdgePositions(ag.solidTextures, button, size)
        for _, tex in ipairs(ag.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or 0.9)
            tex:Show()
        end
    elseif style == "glow" then
        size = size or 32
        FitHighlightFrame(ag.procFrame, button, size)
        TintProcGlowFrame(ag.procFrame, color)
        ag.procFrame:Show()
        -- Skip intro burst, go straight to loop
        if ag.procFrame.ProcStartFlipbook then
            ag.procFrame.ProcStartFlipbook:SetAlpha(0)
        end
        if ag.procFrame.ProcLoopFlipbook then
            ag.procFrame.ProcLoopFlipbook:SetAlpha(1)
        end
        if ag.procFrame.ProcLoop then
            ag.procFrame.ProcLoop:Play()
        end
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

    -- Aura active glow elements (solid border + animated glow)
    button.auraGlow = {}

    -- Solid border: 4 edge textures
    button.auraGlow.solidFrame = CreateFrame("Frame", nil, button)
    button.auraGlow.solidFrame:SetAllPoints()
    button.auraGlow.solidFrame:EnableMouse(false)
    button.auraGlow.solidTextures = {}
    for i = 1, 4 do
        local tex = button.auraGlow.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:Hide()
        button.auraGlow.solidTextures[i] = tex
    end

    -- Proc-style animated glow
    local auraGlowProcFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(auraGlowProcFrame, button, 32)
    SetFrameClickThroughRecursive(auraGlowProcFrame, true, true)
    auraGlowProcFrame:Hide()
    button.auraGlow.procFrame = auraGlowProcFrame

    -- Frame levels: just above cooldown
    local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
    button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)

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

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraActive = false
    button._auraInstanceID = nil
    button._auraPendingSince = nil
    
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
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
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

    -- Aura tracking: check for active buff and override cooldown swipe
    local auraOverrideActive = false
    if buttonData.auraTracking and button._auraSpellID then
        -- Primary path: GetPlayerAuraBySpellID returns full aura data outside
        -- restricted combat.  The arithmetic is wrapped in pcall because
        -- expirationTime / duration may be secret values during M+/PvP.
        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID)
        if auraData then
            local ok = pcall(function()
                local currentTime = GetTime()
                local timeUntilExpire = auraData.expirationTime - currentTime
                local howMuchTimeHasPassed = auraData.duration - timeUntilExpire
                button.cooldown:SetCooldown(currentTime - howMuchTimeHasPassed, auraData.duration, auraData.timeMod)
            end)
            if ok then
                button._auraInstanceID = auraData.auraInstanceID
                -- Cache full duration (ms) for secret-path heuristic (shared across buttons)
                local _, widgetDurMs = button.cooldown:GetCooldownTimes()
                if widgetDurMs and widgetDurMs > 0 then
                    CooldownCompanion.db.profile.auraDurationCache[button._auraSpellID] = widgetDurMs
                end
                auraOverrideActive = true
                fetchOk = true
            else
                -- Arithmetic failed (secret values) — try the duration object fallback
                local instId = auraData.auraInstanceID
                if instId then
                    local dok, durationObj = pcall(C_UnitAuras.GetAuraDuration, "player", instId)
                    if dok and durationObj then
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        button._auraInstanceID = instId
                        auraOverrideActive = true
                        fetchOk = true
                    end
                end
            end
        elseif button._auraInstanceID then
            local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, "player", button._auraInstanceID)
            if ok and durationObj then
                button.cooldown:SetCooldownFromDurationObject(durationObj)
                auraOverrideActive = true
                fetchOk = true
            else
                button._auraInstanceID = nil
            end
        end
        button._auraActive = auraOverrideActive
    end

    if not auraOverrideActive then
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
    end

    -- Bar mode: update bar display and skip icon-only sections
    if button._isBar then
        UpdateBarDisplay(button, fetchOk)
    end

    if not button._isBar then
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
            if wantDesat and button._auraActive and buttonData.auraNoDesaturate then
                wantDesat = false
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
                -- IsItemInRange is protected during combat lockdown; skip range tinting in combat
                if not InCombatLockdown() then
                    local inRange = IsItemInRange(buttonData.id, "target")
                    -- inRange is nil when no target or item has no range; only tint on explicit false
                    if inRange == false then
                        r, g, b = 1, 0.2, 0.2
                    end
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

        -- Show recharge radial — skip when aura override is active
        if not auraOverrideActive then
            local chargeDuration = C_Spell.GetSpellChargeDuration(buttonData.id)
            if chargeDuration then
                button.cooldown:SetCooldownFromDurationObject(chargeDuration)
            elseif charges then
                pcall(function()
                    button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
                end)
            end
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
        if not atMax then
            cc = buttonData.chargeFontColorMissing or {1, 1, 1, 1}
        else
            cc = buttonData.chargeFontColor or {1, 1, 1, 1}
        end
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end

    if not button._isBar then
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

        -- Aura active glow indicator
        if button.auraGlow then
            local showAuraGlow = false
            if button._auraGlowPreview then
                showAuraGlow = true
            elseif button._auraActive
                and buttonData.auraGlowStyle
                and buttonData.auraGlowStyle ~= "none" then
                showAuraGlow = true
            end
            SetAuraGlow(button, showAuraGlow)
        end
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
    button._auraGlowActive = nil
    button._displaySpellId = nil
    button._spellOutOfRange = nil
    button._itemCount = nil
    button._auraActive = nil
    button._auraInstanceID = nil
    button._auraPendingSince = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)

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

    -- Update aura glow frames
    if button.auraGlow then
        button.auraGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.auraGlow.solidTextures, button, button.buttonData.auraGlowSize or 2)
        FitHighlightFrame(button.auraGlow.procFrame, button, button.buttonData.auraGlowSize or 32)
        SetAuraGlow(button, false)
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
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
        end
    end

    -- Re-set aura glow frame levels after strata order
    if button.auraGlow then
        local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
        button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
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

-- Set or clear aura glow preview on a specific button.
function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraGlowPreview = show or nil
            return
        end
    end
end

-- Clear all aura glow previews across every group.
function CooldownCompanion:ClearAllAuraGlowPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._auraGlowPreview = nil
        end
    end
end

-- Set or clear bar aura effect preview on a specific button.
function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barAuraEffectPreview = show or nil
            button._barAuraEffectActive = nil -- force re-evaluate
            return
        end
    end
end

-- Invalidate bar aura effect cache on a specific button so the next tick re-applies.
function CooldownCompanion:InvalidateBarAuraEffect(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barAuraEffectActive = nil
            return
        end
    end
end

-- Invalidate aura glow cache on a specific button so the next tick re-applies.
-- Used by config sliders to update glow appearance without recreating buttons.
function CooldownCompanion:InvalidateAuraGlow(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraGlowActive = nil
            return
        end
    end
end

-- Invalidate proc glow cache on all buttons in a group.
-- Used by the proc glow size/color sliders to update without recreating buttons.
function CooldownCompanion:InvalidateGroupProcGlow(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._procGlowActive = nil
    end
end

--------------------------------------------------------------------------------
-- Bar Display Mode
--------------------------------------------------------------------------------

-- Format remaining seconds for bar time text display
FormatBarTime = function(seconds)
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
    elseif seconds >= 10 then
        return string.format("%d", math.floor(seconds))
    elseif seconds > 0 then
        return string.format("%.1f", seconds)
    end
    return ""
end

-- Update bar-specific display elements (fill, time text, icon desaturation)
UpdateBarDisplay = function(button, fetchOk)
    local style = button.style
    local startMs, durationMs = button.cooldown:GetCooldownTimes()
    local now = GetTime() * 1000

    -- Bar fill and color
    local onCooldown = durationMs and durationMs > 0
    if onCooldown then
        local elapsed = now - startMs
        local remaining = (durationMs - elapsed) / 1000
        local fraction
        if button._auraActive then
            -- Aura: drain from full to empty
            fraction = 1 - (elapsed / durationMs)
            if fraction < 0 then fraction = 0 end
        else
            -- Cooldown: fill from empty to full
            fraction = elapsed / durationMs
            if fraction > 1 then fraction = 1 end
        end
        button.statusBar:SetValue(fraction)

        -- Time text
        if style.showCooldownText then
            if remaining > 0 then
                button.timeText:SetText(FormatBarTime(remaining))
            else
                button.timeText:SetText("")
            end
        else
            button.timeText:SetText("")
        end
    else
        button.statusBar:SetValue(1)
        -- Ready text
        if style.showBarReadyText then
            button.timeText:SetText(style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
        end
    end

    -- Time text color: switch between cooldown and ready colors
    local wantReadyTextColor = not onCooldown and style.showBarReadyText
    if button._barReadyTextColor ~= wantReadyTextColor then
        button._barReadyTextColor = wantReadyTextColor
        if wantReadyTextColor then
            local rc = style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
            button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
        else
            local cc = style.cooldownFontColor or {1, 1, 1, 1}
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
        end
    end

    -- Bar color: switch between ready and cooldown colors
    local wantCdColor = onCooldown and style.barCooldownColor
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    -- Icon desaturation
    if style.desaturateOnCooldown then
        local wantDesat = false
        if fetchOk then
            wantDesat = durationMs and durationMs > 0
        end
        if wantDesat and button._auraActive and button.buttonData.auraNoDesaturate then
            wantDesat = false
        end
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

    -- Bar aura color: override bar fill when aura is active
    local wantAuraColor = button._auraActive and button.buttonData.barAuraColor
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color (cd or ready) by invalidating _barCdColor cache
            button._barCdColor = nil
        end
    end
    if wantAuraColor then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect
    SetBarAuraEffect(button, button._auraActive or button._barAuraEffectPreview)

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

-- Apply bar-specific aura effect (solid border, pixel glow, proc glow)
SetBarAuraEffect = function(button, show)
    local ae = button.barAuraEffect
    if not ae then return end

    local desiredState
    if show then
        local bd = button.buttonData
        local effect = bd.barAuraEffect or "none"
        if effect ~= "none" then
            local c = bd.barAuraEffectColor or {1, 0.84, 0, 0.9}
            local sz = bd.barAuraEffectSize or (effect == "solid" and 2 or effect == "pixel" and 4 or 32)
            local th = (effect == "pixel") and (bd.barAuraEffectThickness or 2) or 0
            desiredState = string.format("%s%.2f%.2f%.2f%.2f%d%d", effect, c[1], c[2], c[3], c[4] or 0.9, sz, th)
        end
    end

    if button._barAuraEffectActive == desiredState then return end
    button._barAuraEffectActive = desiredState

    -- Hide all styles
    for _, tex in ipairs(ae.solidTextures) do
        tex:Hide()
    end
    if ae.procFrame then
        if ae.procFrame.ProcStartAnim then ae.procFrame.ProcStartAnim:Stop() end
        if ae.procFrame.ProcLoop then ae.procFrame.ProcLoop:Stop() end
        ae.procFrame:Hide()
    end
    if ae.pixelFrame then
        ae.pixelFrame:SetScript("OnUpdate", nil)
        ae.pixelFrame:Hide()
    end

    if not desiredState then return end

    local bd = button.buttonData
    local effect = bd.barAuraEffect
    local color = bd.barAuraEffectColor or {1, 0.84, 0, 0.9}
    local size = bd.barAuraEffectSize

    if effect == "solid" then
        size = size or 2
        ApplyEdgePositions(ae.solidTextures, button, size)
        for _, tex in ipairs(ae.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or 0.9)
            tex:Show()
        end
    elseif effect == "pixel" then
        local pf = ae.pixelFrame
        local particles = pf.particles
        local lineLength = size or 4
        local lineThickness = bd.barAuraEffectThickness or 2
        local r, g, b, a = color[1], color[2], color[3], color[4] or 0.9
        for _, px in ipairs(particles) do
            px[1]:SetColorTexture(r, g, b, a)
            px[2]:SetColorTexture(r, g, b, a)
        end
        pf._elapsed = 0
        pf._speed = bd.barAuraEffectSpeed or 60 -- pixels per second
        pf._lineLength = lineLength
        pf._lineThickness = lineThickness
        pf._parentButton = button
        pf:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = self._elapsed + elapsed
            local btn = self._parentButton
            local w, h = btn:GetSize()
            local perimeter = 2 * (w + h)
            local numParticles = #self.particles
            local spacing = perimeter / numParticles
            local offset = (self._elapsed * self._speed) % perimeter
            local ll = self._lineLength
            local lt = self._lineThickness

            -- Edge boundaries: top=0..w, right=w..w+h, bottom=w+h..2w+h, left=2w+h..perimeter
            local wh = w + h
            local ww = 2 * w + h
            local edgeBounds = {w, wh, ww, perimeter}
            local edgeStarts = {0, w, wh, ww}

            for i, px in ipairs(self.particles) do
                local center = (offset + (i - 1) * spacing) % perimeter
                local sPos = (center - ll / 2) % perimeter
                local ePos = sPos + ll

                -- Find which edge sPos is on
                local sEdge
                if sPos < w then sEdge = 0
                elseif sPos < wh then sEdge = 1
                elseif sPos < ww then sEdge = 2
                else sEdge = 3 end

                local sLocal = sPos - edgeStarts[sEdge + 1]
                local sEdgeBound = edgeBounds[sEdge + 1]

                if ePos <= sEdgeBound then
                    -- Entirely on one edge
                    local eLocal = ePos - edgeStarts[sEdge + 1]
                    local segLen = eLocal - sLocal
                    px[1]:ClearAllPoints()
                    if sEdge == 0 then
                        px[1]:SetSize(segLen, lt)
                        px[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", sLocal, 0)
                    elseif sEdge == 1 then
                        px[1]:SetSize(lt, segLen)
                        px[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -sLocal)
                    elseif sEdge == 2 then
                        px[1]:SetSize(segLen, lt)
                        px[1]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -sLocal, 0)
                    else
                        px[1]:SetSize(lt, segLen)
                        px[1]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, sLocal)
                    end
                    px[1]:Show()
                    px[2]:Hide()
                else
                    -- Crosses a corner: split into two segments
                    local edgeLen = sEdgeBound - edgeStarts[sEdge + 1]
                    local firstLen = edgeLen - sLocal
                    local nextEdge = (sEdge + 1) % 4
                    local secondLen = ePos - sEdgeBound
                    if secondLen > perimeter then secondLen = secondLen - perimeter end

                    -- First segment: from sLocal to end of current edge
                    px[1]:ClearAllPoints()
                    if firstLen > 0 then
                        if sEdge == 0 then
                            px[1]:SetSize(firstLen, lt)
                            px[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                        elseif sEdge == 1 then
                            px[1]:SetSize(lt, firstLen)
                            px[1]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                        elseif sEdge == 2 then
                            px[1]:SetSize(firstLen, lt)
                            px[1]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                        else
                            px[1]:SetSize(lt, firstLen)
                            px[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        end
                        px[1]:Show()
                    else
                        px[1]:Hide()
                    end

                    -- Second segment: from start of next edge
                    px[2]:ClearAllPoints()
                    if secondLen > 0 then
                        if nextEdge == 0 then
                            px[2]:SetSize(secondLen, lt)
                            px[2]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                        elseif nextEdge == 1 then
                            px[2]:SetSize(lt, secondLen)
                            px[2]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
                        elseif nextEdge == 2 then
                            px[2]:SetSize(secondLen, lt)
                            px[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                        else
                            px[2]:SetSize(lt, secondLen)
                            px[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
                        end
                        px[2]:Show()
                    else
                        px[2]:Hide()
                    end
                end
            end
        end)
        pf:Show()
    elseif effect == "glow" then
        size = size or 32
        FitHighlightFrame(ae.procFrame, button, size)
        TintProcGlowFrame(ae.procFrame, color)
        ae.procFrame:Show()
        if ae.procFrame.ProcStartFlipbook then
            ae.procFrame.ProcStartFlipbook:SetAlpha(0)
        end
        if ae.procFrame.ProcLoopFlipbook then
            ae.procFrame.ProcLoopFlipbook:SetAlpha(1)
        end
        if ae.procFrame.ProcLoop then
            ae.procFrame.ProcLoop:Play()
        end
    end
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = style.showBarIcon ~= false

    local iconSize = barHeight
    local barAreaLeft = showIcon and iconSize or 0

    -- Main bar frame
    local button = CreateFrame("Frame", parent:GetName() .. "Bar" .. index, parent)
    button:SetSize(barLength, barHeight)
    button._isBar = true

    -- Background
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon (left side, square)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize - borderSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- StatusBar (right of icon)
    button.statusBar = CreateFrame("StatusBar", nil, button)
    button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + borderSize, -borderSize)
    button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
    button.statusBar:SetMinMaxValues(0, 1)
    button.statusBar:SetValue(1)
    button.statusBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    local barColor = style.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Name text (left-aligned on status bar)
    button.nameText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local nameFont = style.barNameFont or "Fonts\\FRIZQT__.TTF"
    local nameFontSize = style.barNameFontSize or 10
    local nameFontOutline = style.barNameFontOutline or "OUTLINE"
    button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
    local nameColor = style.barNameFontColor or {1, 1, 1, 1}
    button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
    button.nameText:SetPoint("LEFT", 3, 0)
    button.nameText:SetJustifyH("LEFT")
    if style.showBarNameText ~= false then
        button.nameText:SetText(buttonData.name or "")
    end

    -- Time text (right-aligned on status bar)
    button.timeText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local cdFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cdFontSize = style.cooldownFontSize or 12
    local cdFontOutline = style.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    button.timeText:SetPoint("RIGHT", -3, 0)
    button.timeText:SetJustifyH("RIGHT")

    -- Truncate name text so it doesn't overlap time text
    button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)

    -- Border textures
    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button, borderSize)

    -- Hidden cooldown frame for GetCooldownTimes() reads
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Charge/item count text (overlay)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply charge/item count font settings
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

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraActive = false
    button._auraInstanceID = nil
    button._auraPendingSince = nil

    -- Aura effect frames (solid border, pixel glow, proc glow)
    button.barAuraEffect = {}
    button.barAuraEffect.solidFrame = CreateFrame("Frame", nil, button)
    button.barAuraEffect.solidFrame:SetAllPoints()
    button.barAuraEffect.solidFrame:EnableMouse(false)
    button.barAuraEffect.solidTextures = {}
    for i = 1, 4 do
        local tex = button.barAuraEffect.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:Hide()
        button.barAuraEffect.solidTextures[i] = tex
    end
    local barAuraProcFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(barAuraProcFrame, button, 32)
    SetFrameClickThroughRecursive(barAuraProcFrame, true, true)
    barAuraProcFrame:Hide()
    button.barAuraEffect.procFrame = barAuraProcFrame
    -- Pixel glow frame with particle textures (2 textures each for corner wrapping)
    local pixelFrame = CreateFrame("Frame", nil, button)
    pixelFrame:SetAllPoints()
    pixelFrame:EnableMouse(false)
    pixelFrame:Hide()
    pixelFrame.particles = {}
    local NUM_PIXELS = 12
    for i = 1, NUM_PIXELS do
        local t1 = pixelFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        t1:SetColorTexture(1, 1, 1, 1)
        local t2 = pixelFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        t2:SetColorTexture(1, 1, 1, 1)
        t2:Hide()
        pixelFrame.particles[i] = {t1, t2}
    end
    pixelFrame._elapsed = 0
    button.barAuraEffect.pixelFrame = pixelFrame
    SetFrameClickThroughRecursive(button.barAuraEffect.solidFrame, true, true)
    SetFrameClickThroughRecursive(button.barAuraEffect.procFrame, true, true)
    SetFrameClickThroughRecursive(pixelFrame, true, true)

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false then
        local displayName = buttonData.name
        if buttonData.type == "spell" then
            local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
            if spellName then displayName = spellName end
        elseif buttonData.type == "item" then
            local itemName = C_Item.GetItemNameByID(buttonData.id)
            if itemName then displayName = itemName end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateBarStyle(self, newStyle)
    end

    -- Click-through
    local showTooltips = style.showTooltips == true
    SetFrameClickThroughRecursive(button, true, not showTooltips)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    -- Tooltip scripts
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

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = newStyle.showBarIcon ~= false
    local iconSize = barHeight
    local barAreaLeft = showIcon and iconSize or 0

    button.style = newStyle

    -- Invalidate cached state
    button._desaturated = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._chargeText = nil
    button._chargeCount = nil
    button._chargeMax = nil
    button._chargeCDStart = nil
    button._chargeCDDuration = nil
    button._displaySpellId = nil
    button._itemCount = nil
    button._auraActive = nil
    button._auraInstanceID = nil
    button._auraPendingSince = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._barCdColor = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil

    button:SetSize(barLength, barHeight)

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize - borderSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Update status bar
    button.statusBar:ClearAllPoints()
    button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + borderSize, -borderSize)
    button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button, borderSize)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    -- Update name text font
    if newStyle.showBarNameText ~= false then
        local nameFont = newStyle.barNameFont or "Fonts\\FRIZQT__.TTF"
        local nameFontSize = newStyle.barNameFontSize or 10
        local nameFontOutline = newStyle.barNameFontOutline or "OUTLINE"
        button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
        local nameColor = newStyle.barNameFontColor or {1, 1, 1, 1}
        button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
        button.nameText:Show()
    else
        button.nameText:Hide()
    end

    -- Update time text font
    local cdFont = newStyle.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cdFontSize = newStyle.cooldownFontSize or 12
    local cdFontOutline = newStyle.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = newStyle.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])

    -- Update charge/item count font
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

    -- Update spell name text
    self:UpdateButtonIcon(button)
    if newStyle.showBarNameText ~= false then
        local displayName = button.buttonData.name
        if button.buttonData.type == "spell" then
            local spellName = C_Spell.GetSpellName(button._displaySpellId or button.buttonData.id)
            if spellName then displayName = spellName end
        elseif button.buttonData.type == "item" then
            local itemName = C_Item.GetItemNameByID(button.buttonData.id)
            if itemName then displayName = itemName end
        end
        button.nameText:SetText(displayName or "")
    end

    -- Update click-through
    local showTooltips = newStyle.showTooltips == true
    SetFrameClickThroughRecursive(button, true, not showTooltips)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end

    -- Tooltip scripts
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
