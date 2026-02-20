--[[
    CooldownCompanion - ButtonFrame
    Individual button frames with cooldown animations

    Note: WoW 12.0 "secret value" API blocks direct comparison of cooldown data.
    We pass values directly to SetCooldown and let the internal WoW code handle them.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local tostring = tostring
local tonumber = tonumber
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local select = select
local IsItemInRange = C_Item.IsItemInRange
local IsUsableItem = C_Item.IsUsableItem
local math_floor = math.floor
local string_format = string.format

-- Forward declarations for bar mode functions (defined at end of file)
local FormatBarTime
local UpdateBarDisplay
local SetBarAuraEffect
local DEFAULT_BAR_AURA_COLOR = {0.2, 1.0, 0.2, 1.0}
local DEFAULT_BAR_PANDEMIC_COLOR = {1.0, 0.5, 0.0, 1.0}
local DEFAULT_BAR_CHARGE_COLOR = {1.0, 0.82, 0.0, 1.0}
local UpdateBarFill

-- Scratch cooldown (legacy; kept for potential fallback use).
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

-- Position a region in the icon area of a bar button.
-- inset=0 for backgrounds/bounds, inset=borderSize for the icon texture itself.
local function SetIconAreaPoints(region, button, isVertical, iconReverse, iconSize, inset)
    region:ClearAllPoints()
    local s = iconSize - 2 * inset
    region:SetSize(s, s)
    if isVertical then
        if iconReverse then
            region:SetPoint("BOTTOM", button, "BOTTOM", 0, inset)
        else
            region:SetPoint("TOP", button, "TOP", 0, -inset)
        end
    else
        if iconReverse then
            region:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        else
            region:SetPoint("LEFT", button, "LEFT", inset, 0)
        end
    end
end

-- Position a region in the bar area of a bar button (the non-icon portion).
-- inset=0 for backgrounds/bounds, inset=borderSize for the statusBar.
local function SetBarAreaPoints(region, button, isVertical, iconReverse, barAreaLeft, barAreaTop, inset)
    region:ClearAllPoints()
    if isVertical then
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, barAreaTop + inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -(barAreaTop + inset))
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    else
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(barAreaLeft + inset), inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    end
end

-- Anchor charge/item count text on bar buttons: relative to icon when visible, relative to bar otherwise.
local function AnchorBarCountText(button, showIcon, anchor, xOff, yOff)
    button.count:ClearAllPoints()
    if showIcon then
        button.count:SetPoint(anchor, button.icon, anchor, xOff, yOff)
    else
        button.count:SetPoint(anchor, button, anchor, xOff, yOff)
    end
end

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
        procGlow = {
            button.procGlow and button.procGlow.solidFrame,
            button.procGlow and button.procGlow.procFrame,
            button.procGlow and button.procGlow.pixelFrame,
        },
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

-- Shared edge anchor spec from Utils.lua
local EDGE_ANCHOR_SPEC = ST.EDGE_ANCHOR_SPEC

-- Apply edge positions to 4 border/highlight textures using the shared spec
local function ApplyEdgePositions(textures, button, size)
    for i, spec in ipairs(EDGE_ANCHOR_SPEC) do
        local tex = textures[i]
        tex:ClearAllPoints()
        tex:SetPoint(spec[1], button, spec[2], spec[5] * size, spec[6] * size)
        tex:SetPoint(spec[3], button, spec[4], spec[7] * size, spec[8] * size)
    end
end

-- Apply aspect-ratio-aware texture cropping to an icon.
-- Crops the narrower dimension so the icon image stays undistorted.
local function ApplyIconTexCoord(icon, width, height)
    if width ~= height then
        local texMin, texMax = 0.08, 0.92
        local texRange = texMax - texMin
        local aspectRatio = width / height
        if aspectRatio > 1.0 then
            local crop = (texRange - texRange / aspectRatio) / 2
            icon:SetTexCoord(texMin, texMax, texMin + crop, texMax - crop)
        else
            local crop = (texRange - texRange * aspectRatio) / 2
            icon:SetTexCoord(texMin + crop, texMax - crop, texMin, texMax)
        end
    else
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Shared click-through helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

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

local PixelGlowOnUpdate

-- Hide all glow sub-styles in a container table (solidTextures, procFrame, pixelFrame).
-- Works for procGlow, auraGlow, barAuraEffect, and assistedHighlight containers.
local function HideGlowStyles(container)
    if container.solidTextures then
        for _, tex in ipairs(container.solidTextures) do tex:Hide() end
    end
    if container.procFrame then
        if container.procFrame.ProcStartAnim then container.procFrame.ProcStartAnim:Stop() end
        if container.procFrame.ProcLoop then container.procFrame.ProcLoop:Stop() end
        container.procFrame:Hide()
    end
    if container.pixelFrame then
        container.pixelFrame:SetScript("OnUpdate", nil)
        container.pixelFrame:Hide()
    end
    -- Assisted highlight blizzard flipbook frame
    if container.blizzardFrame then
        if container.blizzardFrame.Flipbook and container.blizzardFrame.Flipbook.Anim then
            container.blizzardFrame.Flipbook.Anim:Stop()
        end
        container.blizzardFrame:Hide()
    end
end

-- Show the selected glow style on a container.
-- style: "solid", "pixel", "glow", or "blizzard"
-- button: the parent button frame (for positioning)
-- color: {r, g, b, a} color table
-- params: {size, thickness, speed} — style-specific parameters
local function ShowGlowStyle(container, style, button, color, params)
    local size = params.size
    local defaultAlpha = params.defaultAlpha or 1
    if style == "solid" then
        ApplyEdgePositions(container.solidTextures, button, size or 2)
        for _, tex in ipairs(container.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
            tex:Show()
        end
    elseif style == "pixel" then
        local pf = container.pixelFrame
        local r, g, b, a = color[1], color[2], color[3], color[4] or defaultAlpha
        for _, px in ipairs(pf.particles) do
            px[1]:SetColorTexture(r, g, b, a)
            px[2]:SetColorTexture(r, g, b, a)
        end
        pf._elapsed = 0
        pf._speed = params.speed or 60
        pf._lineLength = size or 4
        pf._lineThickness = params.thickness or 2
        pf._parentButton = button
        pf:SetScript("OnUpdate", PixelGlowOnUpdate)
        pf:Show()
    elseif style == "glow" then
        FitHighlightFrame(container.procFrame, button, size or 32)
        TintProcGlowFrame(container.procFrame, color)
        container.procFrame:Show()
        -- Skip intro burst, go straight to loop
        if container.procFrame.ProcStartFlipbook then
            container.procFrame.ProcStartFlipbook:SetAlpha(0)
        end
        if container.procFrame.ProcLoopFlipbook then
            container.procFrame.ProcLoopFlipbook:SetAlpha(1)
        end
        if container.procFrame.ProcLoop then
            container.procFrame.ProcLoop:Play()
        end
    elseif style == "blizzard" then
        if container.blizzardFrame then
            container.blizzardFrame:Show()
            if container.blizzardFrame.Flipbook and container.blizzardFrame.Flipbook.Anim then
                container.blizzardFrame.Flipbook.Anim:Play()
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

    -- Determine desired state, including color in cache key for solid/proc styles
    -- so color changes via settings invalidate the cache
    local colorKey
    if show and highlightStyle == "solid" then
        local c = button.style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        colorKey = ST.FormatColorKey(c)
    elseif show and highlightStyle == "proc" then
        local c = button.style.assistedHighlightProcColor or {1, 1, 1, 1}
        colorKey = ST.FormatColorKey(c)
    end
    local desiredState = show and (highlightStyle .. (colorKey or "")) or nil

    -- Skip show/hide if state hasn't changed (prevents animation restarts)
    if hl.currentState == desiredState then return end
    hl.currentState = desiredState

    HideGlowStyles(hl)

    if not show then return end

    -- Map "proc" → "glow" for ShowGlowStyle (assisted highlight uses "proc" as style name
    -- but the visual is the same "glow" proc-style animation)
    if highlightStyle == "solid" then
        local color = button.style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        ShowGlowStyle(hl, "solid", button, color, {size = button.style.assistedHighlightBorderSize or 2})
    elseif highlightStyle == "blizzard" then
        ShowGlowStyle(hl, "blizzard", button, {1, 1, 1, 1}, {})
    elseif highlightStyle == "proc" then
        local color = button.style.assistedHighlightProcColor or {1, 1, 1, 1}
        ShowGlowStyle(hl, "glow", button, color, {size = button.style.assistedHighlightProcOverhang or 32})
    end
end

-- Shared pixel glow OnUpdate animation (used by icon proc glow and bar aura effect)
PixelGlowOnUpdate = function(self, elapsed)
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
end

-- Show or hide proc glow on a button.
-- Supports "solid" (colored border), "pixel" (animated pixel glow), and "glow" (animated proc-style) styles.
-- Tracks state (style + color + size) to avoid restarting animations every tick.
local function SetProcGlow(button, show)
    local pg = button.procGlow
    if not pg then return end

    -- Build a cache key that includes style, color and size so changes trigger an update
    local desiredState
    if show then
        local style = button.style
        local glowStyle = (style and style.procGlowStyle) or "glow"
        local c = (style and style.procGlowColor) or {1, 1, 1, 1}
        local sz, th
        if glowStyle == "solid" then
            sz = (style and style.procGlowSize) or 2
        elseif glowStyle == "pixel" then
            sz = (style and style.procGlowSize) or 4
        else
            sz = (style and style.procGlowSize) or 32
        end
        th = (glowStyle == "pixel") and ((style and style.procGlowThickness) or 2) or 0
        local spd = (glowStyle == "pixel") and ((style and style.procGlowSpeed) or 60) or 0
        desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%d", glowStyle, c[1], c[2], c[3], c[4] or 1, sz, th, spd)
    end
    if button._procGlowActive == desiredState then return end
    button._procGlowActive = desiredState

    HideGlowStyles(pg)

    if not desiredState then return end

    local style = button.style
    local glowStyle = (style and style.procGlowStyle) or "glow"
    local color = (style and style.procGlowColor) or {1, 1, 1, 1}
    local sz
    if glowStyle == "solid" then
        sz = (style and style.procGlowSize) or 2
    elseif glowStyle == "pixel" then
        sz = (style and style.procGlowSize) or 4
    else
        sz = (style and style.procGlowSize) or 32
    end
    ShowGlowStyle(pg, glowStyle, button, color, {
        size = sz,
        thickness = (style and style.procGlowThickness) or 2,
        speed = (style and style.procGlowSpeed) or 60,
    })
end

-- Show or hide aura active glow on a button.
-- Supports "solid" (colored border) and "glow" (animated proc-style) styles.
-- Tracks state (style + color + size) to avoid restarting animations every tick.
local function SetAuraGlow(button, show, pandemicOverride)
    local ag = button.auraGlow
    if not ag then return end

    -- Build cache key from style + color + size + pandemic state
    local desiredState
    if show then
        local bd = button.buttonData
        local btnStyle = button.style
        local glowStyle
        local c
        if pandemicOverride then
            glowStyle = (btnStyle and btnStyle.pandemicGlowStyle) or "solid"
            c = (btnStyle and btnStyle.pandemicGlowColor) or {1, 0.5, 0, 1}
        else
            glowStyle = (btnStyle and btnStyle.auraGlowStyle) or "pixel"
            c = (btnStyle and btnStyle.auraGlowColor) or {1, 0.84, 0, 0.9}
        end
        if glowStyle ~= "none" then
            local sz, th, spd
            if pandemicOverride then
                sz = (btnStyle and btnStyle.pandemicGlowSize) or (glowStyle == "solid" and 2 or glowStyle == "pixel" and 4 or 32)
                th = (glowStyle == "pixel") and ((btnStyle and btnStyle.pandemicGlowThickness) or 2) or 0
                spd = (glowStyle == "pixel") and ((btnStyle and btnStyle.pandemicGlowSpeed) or 60) or 0
            else
                sz = (btnStyle and btnStyle.auraGlowSize) or (glowStyle == "solid" and 2 or glowStyle == "pixel" and 4 or 32)
                th = (glowStyle == "pixel") and ((btnStyle and btnStyle.auraGlowThickness) or 2) or 0
                spd = (glowStyle == "pixel") and ((btnStyle and btnStyle.auraGlowSpeed) or 60) or 0
            end
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%d%s", glowStyle, c[1], c[2], c[3], c[4] or 0.9, sz, th, spd, pandemicOverride and "P" or "")
        end
    end

    if button._auraGlowActive == desiredState then return end
    button._auraGlowActive = desiredState

    HideGlowStyles(ag)

    if not desiredState then return end

    local bd = button.buttonData
    local btnStyle = button.style
    local glowStyle, color
    if pandemicOverride then
        glowStyle = (btnStyle and btnStyle.pandemicGlowStyle) or "solid"
        color = (btnStyle and btnStyle.pandemicGlowColor) or {1, 0.5, 0, 1}
    else
        glowStyle = (btnStyle and btnStyle.auraGlowStyle) or "pixel"
        color = (btnStyle and btnStyle.auraGlowColor) or {1, 0.84, 0, 0.9}
    end
    local size
    if pandemicOverride then
        size = (btnStyle and btnStyle.pandemicGlowSize)
    else
        size = btnStyle and btnStyle.auraGlowSize
    end
    local thickness, speed
    if pandemicOverride then
        thickness = (btnStyle and btnStyle.pandemicGlowThickness) or 2
        speed = (btnStyle and btnStyle.pandemicGlowSpeed) or 60
    else
        thickness = (btnStyle and btnStyle.auraGlowThickness) or 2
        speed = (btnStyle and btnStyle.auraGlowSpeed) or 60
    end
    -- Default size depends on style
    if not size then
        size = (glowStyle == "solid" and 2) or (glowStyle == "pixel" and 4) or 32
    end
    ShowGlowStyle(ag, glowStyle, button, color, {
        size = size,
        thickness = thickness,
        speed = speed,
        defaultAlpha = 0.9,
    })
end

-- Evaluate per-button visibility rules and set hidden/alpha override state.
-- Called inside UpdateButtonCooldown after cooldown fetch and aura tracking are complete.
-- Fast path: if no toggles are enabled, zero overhead.
local function EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive)
    -- Fast path: no visibility toggles enabled
    if not buttonData.hideWhileOnCooldown
       and not buttonData.hideWhileNotOnCooldown
       and not buttonData.hideWhileAuraNotActive
       and not buttonData.hideWhileAuraActive
       and not buttonData.hideWhileZeroCharges
       and not buttonData.hideWhileZeroStacks
       and not buttonData.hideWhileNotEquipped then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = nil
        return
    end

    local shouldHide = false
    local hidReasonAuraNotActive = false
    local hidReasonAuraActive = false

    -- Check hideWhileOnCooldown
    if buttonData.hideWhileOnCooldown then
        if buttonData.hasCharges then
            -- Charged spells: hide when recharging or all charges consumed
            if button._mainCDShown or button._chargeRecharging then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            -- Items: check stored cooldown values (no GCD concept)
            if button._itemCdDuration and button._itemCdDuration > 0 then
                shouldHide = true
            end
        else
            -- Non-charged spells: _durationObj non-nil means active CD (secret-safe nil check)
            if button._durationObj and not isGCDOnly then
                shouldHide = true
            end
        end
    end

    -- Check hideWhileNotOnCooldown (inverse of hideWhileOnCooldown)
    if buttonData.hideWhileNotOnCooldown then
        if buttonData.hasCharges then
            -- Charged spells: hide only at max charges
            if not button._mainCDShown and not button._chargeRecharging then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            if not button._itemCdDuration or button._itemCdDuration == 0 then
                shouldHide = true
            end
        else
            -- Non-charged spells: not on cooldown (or only on GCD)
            if not button._durationObj or isGCDOnly then
                shouldHide = true
            end
        end
    end

    -- Check hideWhileAuraNotActive
    if buttonData.hideWhileAuraNotActive then
        if not auraOverrideActive then
            shouldHide = true
            hidReasonAuraNotActive = true
        end
    end

    -- Check hideWhileAuraActive
    if buttonData.hideWhileAuraActive then
        if auraOverrideActive then
            shouldHide = true
            hidReasonAuraActive = true
        end
    end

    -- Check hideWhileZeroCharges (charge-based items)
    local hidReasonZeroCharges = false
    if buttonData.hideWhileZeroCharges then
        if button._mainCDShown then
            shouldHide = true
            hidReasonZeroCharges = true
        end
    end

    -- Check hideWhileZeroStacks (stack-based items)
    local hidReasonZeroStacks = false
    if buttonData.hideWhileZeroStacks then
        if (button._itemCount or 0) == 0 then
            shouldHide = true
            hidReasonZeroStacks = true
        end
    end

    -- Check hideWhileNotEquipped (equippable items)
    local hidReasonNotEquipped = false
    if buttonData.hideWhileNotEquipped then
        if button._isEquippableNotEquipped then
            shouldHide = true
            hidReasonNotEquipped = true
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is aura-not-active
    -- and useBaselineAlphaFallback is enabled, dim instead of hiding
    if shouldHide and hidReasonAuraNotActive and buttonData.useBaselineAlphaFallback then
        -- Check if any OTHER hide condition also triggered
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            else
                if button._durationObj and not isGCDOnly then
                    otherHide = true
                end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            else
                if not button._durationObj or isGCDOnly then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraActive and auraOverrideActive then
            otherHide = true
        end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is aura-active
    -- and useBaselineAlphaFallbackAuraActive is enabled, dim instead of hiding
    if shouldHide and hidReasonAuraActive and buttonData.useBaselineAlphaFallbackAuraActive then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            else
                if button._durationObj and not isGCDOnly then
                    otherHide = true
                end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            else
                if not button._durationObj or isGCDOnly then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then
            otherHide = true
        end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is zero charges
    -- and useBaselineAlphaFallbackZeroCharges is enabled, dim instead of hiding
    if shouldHide and hidReasonZeroCharges and buttonData.useBaselineAlphaFallbackZeroCharges then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is zero stacks
    -- and useBaselineAlphaFallbackZeroStacks is enabled, dim instead of hiding
    if shouldHide and hidReasonZeroStacks and buttonData.useBaselineAlphaFallbackZeroStacks then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._mainCDShown or button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.hasCharges then
                if not button._mainCDShown and not button._chargeRecharging then otherHide = true end
            elseif buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileNotEquipped and button._isEquippableNotEquipped then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is not-equipped
    -- and useBaselineAlphaFallbackNotEquipped is enabled, dim instead of hiding
    if shouldHide and hidReasonNotEquipped and buttonData.useBaselineAlphaFallbackNotEquipped then
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.type == "item" then
                if button._itemCdDuration and button._itemCdDuration > 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileNotOnCooldown then
            if buttonData.type == "item" then
                if not button._itemCdDuration or button._itemCdDuration == 0 then otherHide = true end
            end
        end
        if buttonData.hideWhileAuraNotActive and not auraOverrideActive then otherHide = true end
        if buttonData.hideWhileAuraActive and auraOverrideActive then otherHide = true end
        if buttonData.hideWhileZeroCharges and button._mainCDShown then otherHide = true end
        if buttonData.hideWhileZeroStacks and (button._itemCount or 0) == 0 then otherHide = true end
        if not otherHide then
            local groupId = button._groupId
            local group = groupId and CooldownCompanion.db.profile.groups[groupId]
            button._visibilityHidden = false
            button._visibilityAlphaOverride = group and group.baselineAlpha or 0.3
            return
        end
    end

    button._visibilityHidden = shouldHide
    button._visibilityAlphaOverride = nil
end

-- Update loss-of-control cooldown on a button.
-- Uses a CooldownFrame to avoid comparing secret values — the raw start/duration
-- go directly to SetCooldown which handles them on the C side.
local function UpdateLossOfControl(button)
    if not button.locCooldown then return end

    if button.style.showLossOfControl and button.buttonData.type == "spell" and not button.buttonData.isPassive then
        local locDuration = C_Spell.GetSpellLossOfControlCooldownDuration(button.buttonData.id)
        if locDuration then
            button.locCooldown:SetCooldownFromDurationObject(locDuration)
        else
            button.locCooldown:SetCooldown(C_Spell.GetSpellLossOfControlCooldown(button.buttonData.id))
        end
    end
end

-- Create a pixel glow frame with particle pairs for animated border effect.
-- parent: parent frame to attach to
-- numParticles: number of particle pairs (default ST.PARTICLE_COUNT = 12)
local function CreatePixelGlowFrame(parent, numParticles)
    numParticles = numParticles or ST.PARTICLE_COUNT
    local pf = CreateFrame("Frame", nil, parent)
    pf:SetAllPoints()
    pf:EnableMouse(false)
    pf:Hide()
    pf.particles = {}
    for i = 1, numParticles do
        local t1 = pf:CreateTexture(nil, "OVERLAY", nil, 3)
        t1:SetColorTexture(1, 1, 1, 1)
        local t2 = pf:CreateTexture(nil, "OVERLAY", nil, 3)
        t2:SetColorTexture(1, 1, 1, 1)
        t2:Hide()
        pf.particles[i] = {t1, t2}
    end
    pf._elapsed = 0
    SetFrameClickThroughRecursive(pf, true, true)
    return pf
end

-- Create a complete glow container with solid border, proc glow, and pixel glow sub-frames.
-- parent: parent button frame
-- overhang: overhang percentage for the proc glow frame (default 32)
-- Returns table {solidFrame, solidTextures, procFrame, pixelFrame}
local function CreateGlowContainer(parent, overhang)
    local container = {}

    -- Solid border: 4 edge textures
    container.solidFrame = CreateFrame("Frame", nil, parent)
    container.solidFrame:SetAllPoints()
    container.solidFrame:EnableMouse(false)
    container.solidTextures = {}
    for i = 1, 4 do
        local tex = container.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:Hide()
        container.solidTextures[i] = tex
    end

    -- Proc-style animated glow
    local procFrame = CreateFrame("Frame", nil, parent, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(procFrame, parent, overhang or 32)
    SetFrameClickThroughRecursive(procFrame, true, true)
    procFrame:Hide()
    container.procFrame = procFrame

    -- Pixel glow
    container.pixelFrame = CreatePixelGlowFrame(parent)

    -- Ensure solid frame is also non-interactive
    SetFrameClickThroughRecursive(container.solidFrame, true, true)

    return container
end

-- Setup tooltip OnEnter/OnLeave scripts on a button frame.
-- Shared between icon-mode (CreateButtonFrame) and bar-mode (CreateBarFrame).
-- Returns the raw Applications FontString text from a viewer frame.
-- The text is a secret value in combat, so return it as-is for pass-through
-- to SetText(). Blizzard sets it to "" when stacks <= 1 and to the count
-- string when stacks > 1.
local function GetViewerAuraStackText(viewerFrame)
    -- BuffIcon viewer items: Applications frame -> Applications FontString
    if viewerFrame.Applications and viewerFrame.Applications.Applications then
        return viewerFrame.Applications.Applications:GetText()
    end
    -- BuffBar viewer items: Icon frame -> Applications FontString
    if viewerFrame.Icon and viewerFrame.Icon.Applications then
        return viewerFrame.Icon.Applications:GetText()
    end
    return ""
end

local function SetupTooltipScripts(button)
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

-- Create the assisted highlight container (solid border + blizzard flipbook + proc glow).
-- Returns the container table with solidFrame, solidTextures, blizzardFrame, procFrame.
local function CreateAssistedHighlight(button, style)
    local hl = {}

    -- Solid border: 4 edge textures
    local highlightSize = style.assistedHighlightBorderSize or 2
    local hlColor = style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
    hl.solidFrame = CreateFrame("Frame", nil, button)
    hl.solidFrame:SetAllPoints()
    hl.solidFrame:EnableMouse(false)
    hl.solidTextures = {}
    for i = 1, 4 do
        local tex = hl.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetColorTexture(unpack(hlColor))
        tex:Hide()
        hl.solidTextures[i] = tex
    end
    ApplyEdgePositions(hl.solidTextures, button, highlightSize)

    -- Blizzard assisted combat highlight (marching ants flipbook)
    local blizzFrame = CreateFrame("Frame", nil, button, "ActionBarButtonAssistedCombatHighlightTemplate")
    FitHighlightFrame(blizzFrame, button, style.assistedHighlightBlizzardOverhang)
    SetFrameClickThroughRecursive(blizzFrame, true, true)
    blizzFrame:Hide()
    hl.blizzardFrame = blizzFrame

    -- Proc glow (spell activation alert flipbook)
    local procFrame = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    FitHighlightFrame(procFrame, button, style.assistedHighlightProcOverhang)
    SetFrameClickThroughRecursive(procFrame, true, true)
    procFrame:Hide()
    hl.procFrame = procFrame

    return hl
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

    ApplyIconTexCoord(button.icon, width, height)

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
    button.assistedHighlight = CreateAssistedHighlight(button, style)

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    local swipeEnabled = style.showCooldownSwipe ~= false
    button.cooldown:SetDrawSwipe(swipeEnabled)
    button.cooldown:SetDrawEdge(swipeEnabled and style.showCooldownSwipeEdge ~= false)
    button.cooldown:SetReverse(swipeEnabled and (style.cooldownSwipeReverse or false))
    button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    button.cooldown:SetHideCountdownNumbers(false) -- Always allow; visibility controlled via text alpha
    -- Recursively disable mouse on cooldown and all its children (CooldownFrameTemplate has children)
    -- Always fully non-interactive: disable both clicks and motion
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Loss of control cooldown frame (red swipe showing lockout duration)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all icon buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)

    -- Proc glow elements (solid border + animated glow + pixel glow)
    button.procGlow = CreateGlowContainer(button, style.procGlowSize or 32)

    -- Aura active glow elements (solid border + animated glow + pixel glow)
    button.auraGlow = CreateGlowContainer(button, 32)

    -- Frame levels: just above cooldown
    local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
    button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.pixelFrame:SetFrameLevel(auraGlowLevel)

    -- Apply custom cooldown text font settings
    local cooldownFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
        region:ClearAllPoints()
        local cdAnchor = style.cooldownTextAnchor or "CENTER"
        local cdXOff = style.cooldownTextXOffset or 0
        local cdYOff = style.cooldownTextYOffset or 0
        region:SetPoint(cdAnchor, cdXOff, cdYOff)
        button._cdTextRegion = region
    end

    -- Stack count text (for items) — on overlay frame so it renders above cooldown swipe
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply custom count text font/anchor settings from effective style
    if buttonData.hasCharges or buttonData.isPassive then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = style.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = style.chargeXOffset or -2
        local chargeYOffset = style.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = CooldownCompanion:FetchFont(buttonData.itemCountFont or "Friz Quadrata TT")
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

    -- Aura stack count text — separate FontString for aura stacks, independent of charge text
    if buttonData.auraTracking or buttonData.isPassive then
        button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.auraStackCount:SetText("")
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)
    end

    -- Keybind text overlay
    button.keybindText = button.overlayFrame:CreateFontString(nil, "OVERLAY")
    do
        local kbFont = CooldownCompanion:FetchFont(style.keybindFont or "Friz Quadrata TT")
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetKeybindText(buttonData)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false

    button._auraInstanceID = nil

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

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
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
        if button.procGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.procGlow.pixelFrame, true, true)
        end
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
        if button.auraGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.auraGlow.pixelFrame, true, true)
        end
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        SetupTooltipScripts(button)
    end

    return button
end

function CooldownCompanion:UpdateButtonIcon(button)
    local buttonData = button.buttonData
    local icon
    local displayId = buttonData.id

    if buttonData.type == "spell" then
        -- Look up viewer child for current override info (icon, display name).
        -- For override spells (ability→buff mapping), viewerAuraFrames may point
        -- to a BuffIcon/BuffBar child whose spellID is the buff, not the ability.
        -- Scan for an Essential/Utility child that tracks the transforming spell.
        local child = CooldownCompanion.viewerAuraFrames[buttonData.id]
        if child and child.cooldownInfo then
            local parentName = child:GetParent() and child:GetParent():GetName()
            if parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer" then
                -- This is a buff viewer — look for a cooldown viewer instead for icon/name
                local cdChild = CooldownCompanion:FindCooldownViewerChild(buttonData.id)
                if cdChild then child = cdChild end
            end
            -- Track the current override for display name and aura lookups
            if child.cooldownInfo.overrideSpellID then
                displayId = child.cooldownInfo.overrideSpellID
            end
            -- Use the base spellID for texture — GetSpellTexture on a base spell
            -- dynamically returns the current override's icon, unlike override IDs
            -- which always return their own static icon.
            local baseSpellId = child.cooldownInfo.spellID
            if baseSpellId then
                icon = C_Spell.GetSpellTexture(baseSpellId)
            end
        end
        -- Fallback: if no viewer child provided an override, ask the Spell API directly
        if displayId == buttonData.id and buttonData.type == "spell" then
            local overrideId = C_Spell.GetOverrideSpell(buttonData.id)
            if overrideId and overrideId ~= buttonData.id then
                displayId = overrideId
            end
        end
        if not icon then
            icon = C_Spell.GetSpellTexture(displayId)
        end
    elseif buttonData.type == "item" then
        icon = C_Item.GetItemIconByID(buttonData.id)
    end

    local prevDisplayId = button._displaySpellId
    button._displaySpellId = displayId

    if icon then
        button.icon:SetTexture(icon)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Update cooldown secrecy when override spell changes (e.g. Command Demon → pet ability)
    if displayId ~= prevDisplayId and buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(displayId)
    end

    -- Update bar name text when the display spell changes (e.g. transform)
    if button.nameText and buttonData.type == "spell" and displayId ~= prevDisplayId then
        local spellName = C_Spell.GetSpellName(displayId)
        if spellName then
            button.nameText:SetText(spellName)
        end
    end
end

-- Update charge count state for a spell with hasCharges enabled.
-- Returns the raw charges API table (may be nil) for use by callers.
local function UpdateChargeTracking(button, buttonData)
    local charges = C_Spell.GetSpellCharges(buttonData.id)

    -- Try to read current charges as plain number (works outside restricted)
    local cur = tonumber(C_Spell.GetSpellDisplayCount(buttonData.id))

    -- Update persisted maxCharges when readable
    if cur and cur > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = cur
    end
    local mx = buttonData.maxCharges  -- Cached from outside combat

    -- Recharge DurationObject for multi-charge spells.
    -- GetSpellChargeDuration returns nil for maxCharges=1 (Blizzard doesn't treat
    -- single-charge as charge spells for duration purposes).
    if mx and mx > 1 then
        button._chargeDurationObj = C_Spell.GetSpellChargeDuration(buttonData.id)
    end

    -- Display charge text via secret-safe widget methods
    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    else
        if cur then
            -- Plain number: use directly (can optimize with comparison)
            if button._chargeText ~= cur then
                button._chargeText = cur
                button.count:SetText(cur)
            end
        else
            -- Secret: pass directly to SetText (C-level renders it)
            -- Can't compare secrets, so always call SetText
            button._chargeText = nil
            button.count:SetText(C_Spell.GetSpellDisplayCount(buttonData.id))
        end
    end

    return charges
end

-- Item charge tracking (e.g. Hellstone): simpler than spells, no secret values.
-- Reads charge count via C_Item.GetItemCount with includeUses, updates text display.
local function UpdateItemChargeTracking(button, buttonData)
    local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)

    -- Update persisted maxCharges upward when observable
    if chargeCount > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = chargeCount
    end

    -- Display charge text with change detection
    local showChargeText = button.style and button.style.showChargeText
    if not showChargeText then
        button.count:SetText("")
    elseif button._chargeText ~= chargeCount then
        button._chargeText = chargeCount
        button.count:SetText(chargeCount)
    end
end

-- Icon tinting: out-of-range red > unusable dimming > normal white.
-- Shared by icon-mode and bar-mode display paths.
local function UpdateIconTint(button, buttonData, style)
    if buttonData.isPassive then
        if button._vertexR ~= 1 or button._vertexG ~= 1 or button._vertexB ~= 1 then
            button._vertexR, button._vertexG, button._vertexB = 1, 1, 1
            button.icon:SetVertexColor(1, 1, 1)
        end
        return
    end
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
            local isUsable = C_Spell.IsSpellUsable(buttonData.id)
            if not isUsable then
                r, g, b = 0.4, 0.4, 0.4
            end
        elseif buttonData.type == "item" then
            local usable, noMana = IsUsableItem(buttonData.id)
            if not usable then
                r, g, b = 0.4, 0.4, 0.4
            end
        end
    end
    if button._vertexR ~= r or button._vertexG ~= g or button._vertexB ~= b then
        button._vertexR, button._vertexG, button._vertexB = r, g, b
        button.icon:SetVertexColor(r, g, b)
    end
end

-- Update icon-mode visuals: GCD suppression, cooldown text, desaturation, and vertex color.
local function UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, gcdJustEnded)
    -- GCD suppression (isOnGCD is NeverSecret, always readable)
    -- Passives never suppress — always show cooldown widget for aura swipe
    if fetchOk and not buttonData.isPassive then
        local suppressGCD = not style.showGCDSwipe and isOnGCD

        if suppressGCD then
            button.cooldown:Hide()
        else
            if not button.cooldown:IsShown() then
                button.cooldown:Show()
            end
        end
    end

    -- Cooldown/aura text: pick font + visibility based on current state.
    -- Color is reapplied each tick because WoW's CooldownFrame may reset it.
    if button._cdTextRegion then
        local showText, fontColor, wantFont, wantSize, wantOutline
        if button._auraActive then
            showText = style.showAuraText ~= false
            fontColor = style.auraTextFontColor or {0, 0.925, 1, 1}
            wantFont = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
            wantSize = style.auraTextFontSize or 12
            wantOutline = style.auraTextFontOutline or "OUTLINE"
        elseif buttonData.isPassive then
            -- Inactive passive aura: no text (cooldown frame hidden)
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        else
            showText = style.showCooldownText
            fontColor = style.cooldownFontColor or {1, 1, 1, 1}
            wantFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
            wantSize = style.cooldownFontSize or 12
            wantOutline = style.cooldownFontOutline or "OUTLINE"
        end
        if showText then
            local cc = fontColor
            button._cdTextRegion:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            -- Only call SetFont when mode changes to avoid per-tick overhead
            local mode = button._auraActive and "aura" or "cd"
            if button._cdTextMode ~= mode then
                button._cdTextMode = mode
                button._cdTextRegion:SetFont(wantFont, wantSize, wantOutline)
            end
        else
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        end
        -- Properly hide/show countdown numbers via API (alpha=0 alone is unreliable
        -- because WoW's CooldownFrame animation resets text color each tick)
        local wantHide = not showText
        if button._cdTextHidden ~= wantHide then
            button._cdTextHidden = wantHide
            button.cooldown:SetHideCountdownNumbers(wantHide)
        end
    end

    -- Desaturation: aura-tracked buttons desaturate when aura absent;
    -- cooldown buttons desaturate based on DurationObject / item CD state.
    if buttonData.auraTracking then
        local wantDesat
        if buttonData.isPassive then
            wantDesat = not button._auraActive
        else
            wantDesat = buttonData.desaturateWhileAuraNotActive and not button._auraActive
        end
        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and fetchOk and not isOnGCD and not gcdJustEnded then
            if buttonData.hasCharges then
                if buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    elseif style.desaturateOnCooldown or buttonData.desaturateWhileZeroCharges
        or buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        local wantDesat = false
        if style.desaturateOnCooldown and fetchOk and not isOnGCD and not gcdJustEnded then
            if buttonData.hasCharges then
                if buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and buttonData.desaturateWhileZeroCharges and button._mainCDShown then
            wantDesat = true
        end
        if not wantDesat and buttonData.desaturateWhileZeroStacks and (button._itemCount or 0) == 0 then
            wantDesat = true
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
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

    UpdateIconTint(button, buttonData, style)
end

-- Update icon-mode glow effects: loss of control, assisted highlight, proc glow, aura glow.
local function UpdateIconModeGlows(button, buttonData, style)
    -- Loss of control overlay
    UpdateLossOfControl(button)

    -- Assisted highlight glow
    if button.assistedHighlight then
        local assistedSpellID = CooldownCompanion.assistedSpellID
        local displayId = button._displaySpellId or buttonData.id
        local showHighlight = style.showAssistedHighlight
            and buttonData.type == "spell"
            and assistedSpellID
            and (displayId == assistedSpellID
                 or buttonData.id == assistedSpellID
                 or C_Spell.GetOverrideSpell(buttonData.id) == assistedSpellID)

        SetAssistedHighlight(button, showHighlight)
    end

    -- Proc glow (spell activation overlay)
    if button.procGlow then
        local showProc = false
        if button._procGlowPreview then
            showProc = true
        elseif style.procGlowStyle ~= "none" and buttonData.type == "spell"
               and not buttonData.isPassive and not buttonData.auraTracking then
            showProc = CooldownCompanion.procOverlaySpells[buttonData.id] or false
        end
        SetProcGlow(button, showProc)
    end

    -- Aura active glow indicator
    if button.auraGlow then
        local showAuraGlow = false
        local pandemicOverride = false
        if button._pandemicPreview then
            showAuraGlow = true
            pandemicOverride = true
        elseif button._auraGlowPreview then
            showAuraGlow = true
        elseif button._auraActive then
            if button._inPandemic and style.showPandemicGlow ~= false then
                showAuraGlow = true
                pandemicOverride = true
            elseif buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
                showAuraGlow = true
            end
        end
        SetAuraGlow(button, showAuraGlow, pandemicOverride)
    end
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local isGCDOnly = false

    -- For transforming spells (e.g. Command Demon → pet ability), use the
    -- current override spell for cooldown queries. _displaySpellId is set
    -- by UpdateButtonIcon on SPELL_UPDATE_ICON and creation.
    local cooldownSpellId = button._displaySpellId or buttonData.id

    -- Clear per-tick DurationObject; set below if cooldown/aura active.
    -- Used by bar fill, desaturation, visibility checks instead of
    -- GetCooldownTimes() which returns secret values after
    -- SetCooldownFromDurationObject() in 12.0.1.
    -- Save previous aura DurationObject for one-tick grace period on target switch.
    local prevAuraDurationObj = button._auraActive and button._durationObj or nil
    button._durationObj = nil

    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD

    -- Aura tracking: check for active buff/debuff and override cooldown swipe
    local auraOverrideActive = false
    if buttonData.auraTracking and button._auraSpellID then
        local auraUnit = button._auraUnit or "player"

        -- Viewer-based aura tracking: Blizzard's cooldown viewer frames run
        -- untainted code that matches spell IDs to auras during combat and
        -- stores auraInstanceID + auraDataUnit as plain readable properties.
        -- Requires the Blizzard Cooldown Manager to be visible with this spell.
        local viewerFrame
        -- Try each override ID (comma-separated), prefer one with active aura.
        -- Cache parsed IDs on the button to avoid per-tick gmatch allocation.
        if buttonData.auraSpellID then
            local ids = button._parsedAuraIDs
            if not ids or button._parsedAuraIDsRaw ~= buttonData.auraSpellID then
                ids = {}
                for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
                    ids[#ids + 1] = tonumber(id)
                end
                button._parsedAuraIDs = ids
                button._parsedAuraIDsRaw = buttonData.auraSpellID
            end
            for _, numId in ipairs(ids) do
                local f = CooldownCompanion.viewerAuraFrames[numId]
                if f then
                    if f.auraInstanceID then
                        viewerFrame = f
                        break
                    elseif not viewerFrame then
                        viewerFrame = f
                    end
                end
            end
        end
        -- Fall back to resolved aura ID, then ability ID, then current override form.
        -- _displaySpellId tracks the current override (e.g. Solar → Lunar Eclipse)
        -- and is always present in the viewer map after BuildViewerAuraMap.
        if not viewerFrame then
            viewerFrame = CooldownCompanion.viewerAuraFrames[button._auraSpellID]
                or CooldownCompanion.viewerAuraFrames[buttonData.id]
                or (button._displaySpellId and CooldownCompanion.viewerAuraFrames[button._displaySpellId])
        end
        if not auraOverrideActive and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
            local viewerInstId = viewerFrame.auraInstanceID
            if viewerInstId then
                local unit = viewerFrame.auraDataUnit or auraUnit
                local durationObj = C_UnitAuras.GetAuraDuration(unit, viewerInstId)
                if durationObj then
                    button._durationObj = durationObj
                    button.cooldown:SetCooldownFromDurationObject(durationObj)
                    button._auraInstanceID = viewerInstId
                    auraOverrideActive = true
                    fetchOk = true
                end
            else
                -- No auraInstanceID — fall back to reading the viewer's cooldown widget.
                -- Covers spells where the viewer tracks the buff duration internally
                -- (auraDataUnit set by GetAuraData) but doesn't expose auraInstanceID.
                local viewerCooldown = viewerFrame.Cooldown
                if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                    if not viewerCooldown:HasSecretValues() then
                        -- Plain values: safe to do ms->s arithmetic
                        local startMs, durMs = viewerCooldown:GetCooldownTimes()
                        if durMs > 0 and (startMs + durMs) > GetTime() * 1000 then
                            button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                            auraOverrideActive = true
                            fetchOk = true
                        end
                    else
                        -- Secret values: can't convert ms->s. Mark aura active;
                        -- grace period covers continuity from previous tick's display.
                        auraOverrideActive = true
                        fetchOk = true
                    end
                    if button._auraInstanceID then
                        button._auraInstanceID = nil
                    end
                end
                -- Fallback 2: GetTotemInfo pass-through for totem/summoning
                -- spells (TrackedBar category). These appear in BuffBar
                -- viewer but have no auraInstanceID, auraDataUnit, or
                -- Cooldown widget. GetTotemInfo returns secret start/duration
                -- values that SetCooldown accepts directly — no arithmetic.
                -- Read preferredTotemUpdateSlot directly from the viewer
                -- frame (plain number set by CDM) rather than caching it,
                -- since the slot may not be populated at BuildViewerAuraMap time.
                if not auraOverrideActive then
                    local totemSlot = viewerFrame.preferredTotemUpdateSlot
                    if totemSlot and viewerFrame:IsVisible() then
                        local _, _, startTime, duration = GetTotemInfo(totemSlot)
                        button.cooldown:SetCooldown(startTime, duration)
                        auraOverrideActive = true
                        fetchOk = true
                        if button._auraInstanceID then
                            button._auraInstanceID = nil
                        end
                    end
                end
            end
        end
        -- Grace period: if aura data is momentarily unavailable (target switch,
        -- ~250-430ms) but we had an active aura DurationObject last tick, keep
        -- aura state alive.  Restoring _durationObj preserves bar fill, color,
        -- and time text.
        -- Fast path: if we can read the old DurationObject (non-secret), check
        -- expiry directly — clears instantly when the aura has genuinely ended.
        -- Slow path (combat, HasSecretValues=true): bounded tick counter.
        if not auraOverrideActive and button._auraActive
           and prevAuraDurationObj and not buttonData.isPassive then
            local expired = false
            if not prevAuraDurationObj:HasSecretValues() then
                expired = prevAuraDurationObj:GetRemainingDuration() <= 0
            end
            if not expired then
                button._auraGraceTicks = (button._auraGraceTicks or 0) + 1
                if button._auraGraceTicks <= 3 then
                    button._durationObj = prevAuraDurationObj
                    auraOverrideActive = true
                else
                    button._auraGraceTicks = nil
                end
            else
                button._auraGraceTicks = nil
            end
        else
            -- Fresh aura data (or no aura at all): reset grace counter
            button._auraGraceTicks = nil
        end
        button._auraActive = auraOverrideActive

        -- Read aura stack text from viewer frame (combat-safe, secret pass-through)
        if buttonData.auraTracking or buttonData.isPassive then
            if auraOverrideActive and viewerFrame then
                button._auraStackText = GetViewerAuraStackText(viewerFrame)
            else
                button._auraStackText = ""
            end
        end

        -- Pandemic window check: read Blizzard's PandemicIcon from the viewer frame.
        -- Blizzard calculates the exact per-spell pandemic window internally and
        -- shows/hides PandemicIcon accordingly.  Use IsVisible() so that a
        -- PandemicIcon whose parent viewer item was hidden (e.g. aura expired
        -- before OnUpdate could clean it up) is not treated as active.
        local inPandemic = false
        if button._pandemicPreview then
            inPandemic = true
        elseif auraOverrideActive and buttonData.pandemicGlow and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if pi and pi:IsVisible() then
                inPandemic = true
            end
        end
        button._inPandemic = inPandemic
    end

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    if not auraOverrideActive then
        if buttonData.type == "spell" and not buttonData.isPassive then
            -- Get isOnGCD (NeverSecret) via GetSpellCooldown.
            -- SetCooldown accepts secret startTime/duration values.
            local cooldownInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
            if cooldownInfo then
                isOnGCD = cooldownInfo.isOnGCD
                if not fetchOk then
                    button.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                end
                fetchOk = true
            end
            -- GCD-only detection: compare spell's cooldown against GCD reference (61304).
            -- More reliable than isOnGCD at GCD boundaries (Blizzard CooldownViewer pattern).
            if cooldownInfo then
                local gcdInfo = CooldownCompanion._gcdInfo
                if gcdInfo then
                    if buttonData._cooldownSecrecy == 0 then
                        -- NeverSecret: direct comparison is safe
                        isGCDOnly = (cooldownInfo.startTime == gcdInfo.startTime
                            and cooldownInfo.duration == gcdInfo.duration)
                    else
                        -- Secret cooldown: both signals must agree to avoid false positives.
                        -- isOnGCD (NeverSecret) = Blizzard's per-spell GCD flag.
                        -- _gcdActive = widget-level GCD signal (covers boundary where
                        -- isOnGCD lingers true after GCD ends).
                        isGCDOnly = isOnGCD and CooldownCompanion._gcdActive
                    end
                end
            end
            -- DurationObject path: HasSecretValues gates IsZero comparison.
            -- Non-secret: use IsZero to filter zero-duration (spell ready).
            -- Secret: fall back to isOnGCD (NeverSecret) as activity signal.
            local spellCooldownDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            if spellCooldownDuration then
                local useIt = false
                if not spellCooldownDuration:HasSecretValues() then
                    if not spellCooldownDuration:IsZero() then useIt = true end
                else
                    -- Secret values: can't call IsZero() to check if spell is ready.
                    -- GetSpellCooldownDuration returns non-nil even for ready spells
                    -- during combat.  Use scratchCooldown as a C++ level signal:
                    -- SetCooldown() auto-shows it only when duration > 0 (handles
                    -- secrets internally).  button.cooldown:IsShown() is unreliable
                    -- — force-shown by UpdateIconModeVisuals, not auto-hidden by
                    -- SetCooldown(0,0).
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                    useIt = scratchCooldown:IsShown()
                    scratchCooldown:Hide()
                end
                if useIt then
                    button._durationObj = spellCooldownDuration
                    if not spellCooldownDuration:HasSecretValues() then
                        button.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                    end
                    fetchOk = true
                end
            end
        elseif buttonData.type == "item" then
            local isEquippable = IsItemEquippable(buttonData)
            if isEquippable and not C_Item.IsEquippedItem(buttonData.id) then
                button._isEquippableNotEquipped = true
                -- Suppress cooldown display: static desaturated icon
                button.cooldown:SetCooldown(0, 0)
                button._itemCdStart = 0
                button._itemCdDuration = 0
            else
                button._isEquippableNotEquipped = false
                local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
                button.cooldown:SetCooldown(cdStart, cdDuration)
                button._itemCdStart = cdStart
                button._itemCdDuration = cdDuration
            end
            fetchOk = true
        end
    end

    -- Store raw GCD state for bar desaturation guard
    local gcdJustEnded = (button._wasOnGCD == true) and not isOnGCD
    button._wasOnGCD = isOnGCD or false
    button._isOnGCD = isOnGCD or false
    button._gcdJustEnded = gcdJustEnded

    -- Bar mode: GCD suppression flag (checked by UpdateBarFill OnUpdate).
    -- Skip for charge spells: their _durationObj is the recharge cycle, never the GCD.
    if button._isBar then
        button._barGCDSuppressed = fetchOk and not style.showGCDSwipe and isOnGCD
            and not buttonData.hasCharges and not buttonData.isPassive
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Skip during aura override: button.cooldown shows the aura, not the main CD.
    if buttonData.hasCharges and not auraOverrideActive then
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif button._isBar then
            -- Bar mode: button.cooldown is not reused for recharge animation.
            -- For secret spells, require both GCD signals to agree before filtering,
            -- preventing false negatives at GCD boundaries.
            if buttonData._cooldownSecrecy == 0 then
                button._mainCDShown = button.cooldown:IsShown() and not isOnGCD
            else
                button._mainCDShown = button.cooldown:IsShown()
                    and not (isOnGCD and CooldownCompanion._gcdActive)
            end
        else
            -- Icon mode: prefer scratchCooldown when DurationObject values are plain.
            -- button.cooldown:IsShown() is unreliable because UpdateIconModeVisuals
            -- force-shows it and SetCooldown(0,0) does not auto-hide.
            local mainCDDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            if mainCDDuration and not mainCDDuration:HasSecretValues() then
                scratchCooldown:Hide()
                scratchCooldown:SetCooldownFromDurationObject(mainCDDuration)
                button._mainCDShown = scratchCooldown:IsShown() and not isOnGCD
                scratchCooldown:Hide()
            elseif mainCDDuration then
                -- Secret values (combat): SetCooldownFromDurationObject fails with
                -- secrets, but SetCooldown accepts them.  Use scratchCooldown
                -- (button.cooldown:IsShown() is unreliable — force-shown by
                -- UpdateIconModeVisuals, not auto-hidden by SetCooldown(0,0)).
                local ci = C_Spell.GetSpellCooldown(cooldownSpellId)
                if ci then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(ci.startTime, ci.duration)
                    button._mainCDShown = scratchCooldown:IsShown() and not isOnGCD
                    scratchCooldown:Hide()
                else
                    button._mainCDShown = false
                end
            else
                button._mainCDShown = false
            end
        end
    end

    if not button._isBar then
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, gcdJustEnded)
    end

    local charges
    if buttonData.hasCharges then
      if buttonData.type == "spell" then
        charges = UpdateChargeTracking(button, buttonData)

        -- Bar mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD. Save and clear the main CD, let the charge block
        -- set _durationObj from the recharge, then restore the main CD for GCD
        -- display only when showGCDSwipe is on and no recharge is active.
        local mainDurationObj
        if button._isBar and not auraOverrideActive then
            mainDurationObj = button._durationObj
            button._durationObj = nil
        end

        -- Always detect charge recharging state (needed for text/bar color even during aura override).
        -- Charge DurationObjects may report non-zero even at full charges (stale data);
        -- scratchCooldown auto-show is the ground truth.
        if button._chargeDurationObj then
            if not button._chargeDurationObj:HasSecretValues() then
                scratchCooldown:Hide()
                scratchCooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                button._chargeRecharging = scratchCooldown:IsShown()
                scratchCooldown:Hide()
            else
                -- Secret values (combat): SetCooldownFromDurationObject fails.
                -- Probe scratchCooldown with charge timing data instead
                -- (SetCooldown accepts secrets; IsShown returns plain bool).
                -- Uses charge-specific timing, not the main cooldown (which
                -- includes GCD for on-GCD charge spells like Fire Breath).
                if charges then
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
                    button._chargeRecharging = scratchCooldown:IsShown()
                    scratchCooldown:Hide()
                else
                    button._chargeRecharging = false
                end
            end
        else
            button._chargeRecharging = false
        end

        if not auraOverrideActive and button._chargeDurationObj then
            if not button._isBar then
                -- Icon mode: always set _durationObj, show recharge radial
                button._durationObj = button._chargeDurationObj
                if not button._chargeDurationObj:HasSecretValues() then
                    button.cooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                elseif charges then
                    -- Secret: SetCooldownFromDurationObject fails; use SetCooldown
                    button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
                end
            elseif button._chargeRecharging then
                -- Bar mode: only set _durationObj if actually recharging
                button._durationObj = button._chargeDurationObj
            end
        elseif not button._isBar and not auraOverrideActive and charges then
            -- Icon mode fallback
            button.cooldown:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
        end

        -- Bar mode: if no recharge active, restore main CD for GCD display
        if button._isBar and not button._durationObj
           and mainDurationObj and isOnGCD and style.showGCDSwipe then
            button._durationObj = mainDurationObj
        end

      elseif buttonData.type == "item" then
        UpdateItemChargeTracking(button, buttonData)

        -- Detect recharging via stored item cooldown values
        button._chargeRecharging = (button._itemCdDuration and button._itemCdDuration > 0) or false
      end
    end

    -- Item count display (inventory quantity for non-equipment tracked items)
    if buttonData.type == "item" and not buttonData.hasCharges and not IsItemEquippable(buttonData) then
        local count = C_Item.GetItemCount(buttonData.id)
        if button._itemCount ~= count then
            button._itemCount = count
            if count and count >= 1 then
                button.count:SetText(count)
            else
                button.count:SetText("")
            end
        end
    end

    -- Aura stack count display (aura-tracking spells with stackable auras)
    -- Text is a secret value in combat — pass through directly to SetText.
    -- Blizzard sets it to "" when stacks <= 1 and the count string when > 1.
    if button.auraStackCount and (buttonData.auraTracking or buttonData.isPassive)
       and (style.showAuraStackText ~= false) then
        if button._auraActive then
            button.auraStackCount:SetText(button._auraStackText or "")
        else
            button.auraStackCount:SetText("")
        end
    end

    -- Charge text color: three-state (zero / partial / max) via flags, combat-safe.
    if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
        local cc
        if button._mainCDShown then
            cc = style.chargeFontColorZero or {1, 1, 1, 1}
        elseif button._chargeRecharging then
            cc = style.chargeFontColorMissing or {1, 1, 1, 1}
        else
            cc = style.chargeFontColor or {1, 1, 1, 1}
        end
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end

    -- Per-button visibility evaluation (after charge tracking)
    EvaluateButtonVisibility(button, buttonData, isGCDOnly, auraOverrideActive)

    -- Track if hidden state changed (for compact layout dirty flag)
    if button._visibilityHidden ~= button._prevVisibilityHidden then
        button._prevVisibilityHidden = button._visibilityHidden
        local groupFrame = button:GetParent()
        if groupFrame then groupFrame._layoutDirty = true end
    end

    -- Apply visibility alpha or early-return for hidden buttons
    local group = button._groupId and CooldownCompanion.db.profile.groups[button._groupId]
    if not group or not group.compactLayout then
        -- Non-compact mode: alpha=0 for hidden, restore for visible
        if button._visibilityHidden then
            button.cooldown:Hide()  -- prevent stale IsShown() across ticks
            if button._lastVisAlpha ~= 0 then
                button:SetAlpha(0)
                button._lastVisAlpha = 0
            end
            return  -- Skip all visual updates
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    else
        -- Compact mode: Show/Hide handled by UpdateGroupLayout
        if button._visibilityHidden then
            -- Prevent stale IsShown() across ticks. SetCooldown(0,0) does not
            -- auto-hide the CooldownFrame; without this, bar mode _mainCDShown
            -- and icon mode force-show both read stale true on next tick.
            button.cooldown:Hide()
            return  -- Skip visual updates for hidden buttons
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    end

    -- Bar mode: update bar display after charges are resolved
    if button._isBar then
        UpdateBarDisplay(button, fetchOk)
    end

    if not button._isBar then
        UpdateIconModeGlows(button, buttonData, style)
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
    button._nilConfirmPending = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._displaySpellId = nil
    button._spellOutOfRange = nil
    button._itemCount = nil
    button._auraActive = nil

    button._auraInstanceID = nil
    button._inPandemic = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1

    button:SetSize(width, height)

    -- Update icon position
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    ApplyIconTexCoord(button.icon, width, height)

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

    -- Countdown number visibility is controlled per-tick via SetHideCountdownNumbers
    button.cooldown:SetHideCountdownNumbers(false)
    local swipeEnabled = style.showCooldownSwipe ~= false
    button.cooldown:SetDrawSwipe(swipeEnabled)
    button.cooldown:SetDrawEdge(swipeEnabled and style.showCooldownSwipeEdge ~= false)
    button.cooldown:SetReverse(swipeEnabled and (style.cooldownSwipeReverse or false))

    -- Update cooldown font settings (default state; per-tick logic handles aura mode)
    local cooldownFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
        region:ClearAllPoints()
        local cdAnchor = style.cooldownTextAnchor or "CENTER"
        local cdXOff = style.cooldownTextXOffset or 0
        local cdYOff = style.cooldownTextYOffset or 0
        region:SetPoint(cdAnchor, cdXOff, cdYOff)
    end
    -- Clear cached text mode so per-tick logic re-applies the correct font
    button._cdTextMode = nil
    button._cdTextHidden = nil

    -- Update count text font/anchor settings from effective style
    button.count:ClearAllPoints()
    if button.buttonData and (button.buttonData.hasCharges or button.buttonData.isPassive) then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = style.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = style.chargeXOffset or -2
        local chargeYOffset = style.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = CooldownCompanion:FetchFont(button.buttonData.itemCountFont or "Friz Quadrata TT")
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

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)
    end

    -- Update keybind text overlay
    if button.keybindText then
        local kbFont = CooldownCompanion:FetchFont(style.keybindFont or "Friz Quadrata TT")
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        button.keybindText:ClearAllPoints()
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetKeybindText(button.buttonData)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
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
        button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
        button.locCooldown:Clear()
    end

    -- Update proc glow frames
    if button.procGlow then
        button.procGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.procGlow.solidTextures, button, style.procGlowSize or 2)
        FitHighlightFrame(button.procGlow.procFrame, button, style.procGlowSize or 32)
        if button.procGlow.pixelFrame then
            button.procGlow.pixelFrame:SetAllPoints()
        end
        SetProcGlow(button, false)
    end

    -- Update aura glow frames
    if button.auraGlow then
        button.auraGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.auraGlow.solidTextures, button, button.style.auraGlowSize or 2)
        FitHighlightFrame(button.auraGlow.procFrame, button, button.style.auraGlowSize or 32)
        if button.auraGlow.pixelFrame then
            button.auraGlow.pixelFrame:SetAllPoints()
        end
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
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
        if button.procGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.procGlow.pixelFrame, true, true)
        end
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
        if button.auraGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.auraGlow.pixelFrame, true, true)
        end
    end

    -- Re-set aura glow frame levels after strata order
    if button.auraGlow then
        local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
        button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.pixelFrame:SetFrameLevel(auraGlowLevel)
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
            if not show then
                -- Call directly — cache still holds old state so the
                -- mismatch will trigger the hide path inside SetBarAuraEffect
                SetBarAuraEffect(button, button._auraActive)
            else
                button._barAuraEffectActive = nil -- force re-evaluate on next tick
            end
            return
        end
    end
end

-- Set or clear pandemic preview on a specific button.
function CooldownCompanion:SetPandemicPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._pandemicPreview = show or nil
            if not show then
                -- Call directly — cache still holds old state so the
                -- mismatch will trigger the hide path inside SetBarAuraEffect
                SetBarAuraEffect(button, button._auraActive)
            else
                button._barAuraEffectActive = nil -- force re-evaluate on next tick
            end
            return
        end
    end
end

-- Clear all pandemic previews across every group.
function CooldownCompanion:ClearAllPandemicPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._pandemicPreview = nil
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

-- Invalidate proc glow cache on a specific button so the next tick re-applies.
-- Used by per-button config sliders to update glow appearance without recreating buttons.
function CooldownCompanion:InvalidateProcGlow(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._procGlowActive = nil
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Display Mode
--------------------------------------------------------------------------------

-- Format remaining seconds for bar time text display
FormatBarTime = function(seconds)
    if seconds >= 60 then
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    elseif seconds >= 10 then
        return string_format("%d", math_floor(seconds))
    elseif seconds > 0 then
        return string_format("%.1f", seconds)
    end
    return ""
end

-- Lightweight OnUpdate: interpolates bar fill + time text between ticker updates.
UpdateBarFill = function(button)
    -- Single-bar path
    -- DurationObject percent methods return secret values during combat in 12.0.1,
    -- but SetValue() accepts secrets (C-side widget method).  HasSecretValues gates
    -- expiry detection and time text formatting.
    -- Items use stored C_Item.GetItemCooldown values (_itemCdStart/_itemCdDuration).
    local onCooldown = false
    local itemRemaining = 0

    if button._durationObj and not button._barGCDSuppressed then
        onCooldown = true
        -- SetValue accepts secret values; fraction animates natively in the engine
        if button._auraActive then
            button.statusBar:SetValue(button._durationObj:GetRemainingPercent())   -- drain: 1→0
        else
            button.statusBar:SetValue(button._durationObj:GetElapsedPercent())     -- fill: 0→1
        end
    elseif button.buttonData.type == "item" then
        -- Items: use stored C_Item.GetItemCooldown values (avoids hidden-widget staleness)
        local startMs = (button._itemCdStart or 0) * 1000
        local durationMs = (button._itemCdDuration or 0) * 1000
        local now = GetTime() * 1000
        onCooldown = durationMs > 0
        if onCooldown and button._barGCDSuppressed then onCooldown = false end
        if onCooldown then
            local elapsed = now - startMs
            itemRemaining = (durationMs - elapsed) / 1000
            if button._auraActive then
                local frac = 1 - (elapsed / durationMs)
                if frac < 0 then frac = 0 end
                button.statusBar:SetValue(frac)
            else
                local frac = elapsed / durationMs
                if frac > 1 then frac = 1 end
                button.statusBar:SetValue(frac)
            end
        end
    end

    if onCooldown then
        local showTimeText = button._auraActive
            and (button.style.showAuraText ~= false)
            or (not button._auraActive and button.style.showCooldownText)
        if showTimeText then
            -- Switch font/color when mode changes
            local mode = button._auraActive and "aura" or "cd"
            if button._barTextMode ~= mode then
                button._barTextMode = mode
                if button._auraActive then
                    local f = CooldownCompanion:FetchFont(button.style.auraTextFont or "Friz Quadrata TT")
                    local s = button.style.auraTextFontSize or 12
                    local o = button.style.auraTextFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                else
                    local f = CooldownCompanion:FetchFont(button.style.cooldownFont or "Friz Quadrata TT")
                    local s = button.style.cooldownFontSize or 12
                    local o = button.style.cooldownFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                end
            end
            local cc = button._auraActive
                and (button.style.auraTextFontColor or {0, 0.925, 1, 1})
                or (button.style.cooldownFontColor or {1, 1, 1, 1})
            button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            -- Time text: HasSecretValues() returns a non-secret boolean.
            -- Non-secret: full FormatBarTime formatting ("1:30", "45", etc.)
            -- Secret: pass secret number to C++ SetFormattedText ("%.1f" format)
            if button._durationObj then
                local remaining = button._durationObj:GetRemainingDuration()
                if not button._durationObj:HasSecretValues() then
                    if remaining > 0 then
                        button.timeText:SetText(FormatBarTime(remaining))
                    else
                        button.timeText:SetText("")
                    end
                else
                    button.timeText:SetFormattedText("%.1f", remaining)
                end
            else
                if itemRemaining > 0 then
                    button.timeText:SetText(FormatBarTime(itemRemaining))
                else
                    button.timeText:SetText("")
                end
            end
        end
    else
        if button.buttonData.isPassive then
            button.statusBar:SetValue(0)
            button.timeText:SetText("")
        else
        button.statusBar:SetValue(1)
        if button.style.showBarReadyText then
            if button._barTextMode ~= "ready" then
                button._barTextMode = "ready"
                local f = CooldownCompanion:FetchFont(button.style.barReadyFont or "Friz Quadrata TT")
                local s = button.style.barReadyFontSize or 12
                local o = button.style.barReadyFontOutline or "OUTLINE"
                button.timeText:SetFont(f, s, o)
            end
            button.timeText:SetText(button.style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
        end
        end
    end
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
UpdateBarDisplay = function(button, fetchOk)
    local style = button.style

    -- Determine onCooldown via nil-checks (secret-safe).
    -- _durationObj is non-nil only when UpdateButtonCooldown found an active CD/aura.
    local onCooldown
    if button._durationObj then
        onCooldown = not button._barGCDSuppressed
    elseif button.buttonData.type == "item" then
        onCooldown = button._itemCdDuration and button._itemCdDuration > 0
        if onCooldown and button._barGCDSuppressed then
            onCooldown = false
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

    -- Bar color: switch between ready, cooldown, and partial charge colors.
    -- Aura-tracked buttons always use the base bar color (aura color override handles active state).
    local wantCdColor
    if onCooldown and not button.buttonData.isPassive then
        if button.buttonData.hasCharges and not button._mainCDShown then
            wantCdColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
        else
            wantCdColor = style.barCooldownColor
        end
    end
    if button._barCdColor ~= wantCdColor then
        button._barCdColor = wantCdColor
        local c = wantCdColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
        button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end

    -- Icon desaturation: aura-tracked buttons desaturate when aura absent;
    -- cooldown buttons desaturate based on DurationObject / item CD state.
    if button.buttonData.auraTracking then
        local wantDesat
        if button.buttonData.isPassive then
            wantDesat = not button._auraActive
        else
            wantDesat = button.buttonData.desaturateWhileAuraNotActive and not button._auraActive
        end
        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and fetchOk and not button._isOnGCD and not button._gcdJustEnded then
            if button.buttonData.hasCharges then
                if button.buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif button.buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    elseif style.desaturateOnCooldown or button.buttonData.desaturateWhileZeroCharges
        or button.buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        local wantDesat = false
        if style.desaturateOnCooldown and fetchOk and not button._isOnGCD and not button._gcdJustEnded then
            if button.buttonData.hasCharges then
                if button.buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif button.buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button.buttonData.desaturateWhileZeroCharges and button._mainCDShown then
            wantDesat = true
        end
        if not wantDesat and button.buttonData.desaturateWhileZeroStacks and (button._itemCount or 0) == 0 then
            wantDesat = true
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
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

    -- Icon tinting (out-of-range red / unusable dimming)
    UpdateIconTint(button, button.buttonData, style)

    -- Loss of control overlay on bar icon
    UpdateLossOfControl(button)

    -- Bar aura color: override bar fill when aura is active (pandemic overrides aura color)
    local wantAuraColor
    if button._pandemicPreview then
        wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
    elseif button._auraActive then
        if button._inPandemic and style.showPandemicGlow ~= false then
            wantAuraColor = (button.style and button.style.barPandemicColor) or DEFAULT_BAR_PANDEMIC_COLOR
        elseif button.buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
            wantAuraColor = (button.style and button.style.barAuraColor) or DEFAULT_BAR_AURA_COLOR
        end
    end
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color immediately (don't wait for next tick)
            button._barCdColor = nil
            local resetColor
            if onCooldown then
                if button.buttonData.hasCharges and not button._mainCDShown then
                    resetColor = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR
                else
                    resetColor = style.barCooldownColor
                end
            end
            local c = resetColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
            button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
        end
    end
    if wantAuraColor then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect (pandemic overrides effect color)
    local barAuraEffectPandemic = button._pandemicPreview or (button._auraActive and button._inPandemic and button.buttonData.pandemicGlow and style.showPandemicGlow ~= false)
    local barAuraEffectShow = button._barAuraEffectPreview or button._pandemicPreview
        or (button._auraActive and (barAuraEffectPandemic or button.buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none"))
    SetBarAuraEffect(button, barAuraEffectShow, barAuraEffectPandemic or false)

    -- Keep the cooldown widget hidden — SetCooldown auto-shows it
    if button.cooldown:IsShown() then
        button.cooldown:Hide()
    end
end

-- Apply bar-specific aura effect (solid border, pixel glow, proc glow)
SetBarAuraEffect = function(button, show, pandemicOverride)
    local ae = button.barAuraEffect
    if not ae then return end

    local desiredState
    if show then
        local bd = button.buttonData
        local btnStyle = button.style
        local effect
        if pandemicOverride then
            effect = (btnStyle and btnStyle.pandemicBarEffect) or "none"
        else
            effect = (btnStyle and btnStyle.barAuraEffect) or "none"
        end
        if effect ~= "none" then
            local c
            if pandemicOverride then
                c = (btnStyle and btnStyle.pandemicBarEffectColor) or {1, 0.5, 0, 1}
            else
                c = (btnStyle and btnStyle.barAuraEffectColor) or {1, 0.84, 0, 0.9}
            end
            local sz, th
            if pandemicOverride then
                sz = (btnStyle and btnStyle.pandemicBarEffectSize) or (effect == "solid" and 2 or effect == "pixel" and 4 or 32)
                th = (effect == "pixel") and ((btnStyle and btnStyle.pandemicBarEffectThickness) or 2) or 0
            else
                sz = (btnStyle and btnStyle.barAuraEffectSize) or (effect == "solid" and 2 or effect == "pixel" and 4 or 32)
                th = (effect == "pixel") and ((btnStyle and btnStyle.barAuraEffectThickness) or 2) or 0
            end
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%s", effect, c[1], c[2], c[3], c[4] or 0.9, sz, th, pandemicOverride and "P" or "")
        end
    end

    if button._barAuraEffectActive == desiredState then return end
    button._barAuraEffectActive = desiredState

    HideGlowStyles(ae)

    if not desiredState then return end

    local bd = button.buttonData
    local btnStyle = button.style
    local effect
    if pandemicOverride then
        effect = (btnStyle and btnStyle.pandemicBarEffect) or "none"
    else
        effect = (btnStyle and btnStyle.barAuraEffect) or "none"
    end
    local color
    if pandemicOverride then
        color = (btnStyle and btnStyle.pandemicBarEffectColor) or {1, 0.5, 0, 1}
    else
        color = (btnStyle and btnStyle.barAuraEffectColor) or {1, 0.84, 0, 0.9}
    end
    local size
    if pandemicOverride then
        size = btnStyle and btnStyle.pandemicBarEffectSize
    else
        size = btnStyle and btnStyle.barAuraEffectSize
    end
    -- Default size depends on effect style
    if not size then
        size = (effect == "solid" and 2) or (effect == "pixel" and 4) or 32
    end
    local thickness = (pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectThickness) or 2) or (btnStyle and btnStyle.barAuraEffectThickness)) or 2
    local speed = (pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectSpeed) or 60) or (btnStyle and btnStyle.barAuraEffectSpeed)) or 60
    ShowGlowStyle(ae, effect, button, color, {
        size = size,
        thickness = thickness,
        speed = speed,
        defaultAlpha = 0.9,
    })
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    local barLength = style.barLength or 180
    local barHeight = style.barHeight or 20
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)

    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    -- Main bar frame
    local button = CreateFrame("Frame", parent:GetName() .. "Bar" .. index, parent)
    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end
    button._isBar = true
    button._isVertical = isVertical

    -- Background — covers bar area only when icon is shown (icon has its own iconBg)
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Icon background + border (always shown when icon visible)
    button.iconBg = button:CreateTexture(nil, "BACKGROUND")
    SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
    button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if not showIcon then button.iconBg:Hide() end

    button._iconBounds = CreateFrame("Frame", nil, button)
    button._iconBounds:EnableMouse(false)
    SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)

    button.iconBorderTextures = {}
    local borderColor = style.borderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        if not showIcon then tex:Hide() end
        button.iconBorderTextures[i] = tex
    end
    ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)

    -- Bar area bounds (for border positioning separate from icon)
    button._barBounds = CreateFrame("Frame", nil, button)
    button._barBounds:EnableMouse(false)
    if showIcon then
        SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button._barBounds:SetAllPoints()
    end

    -- StatusBar
    button.statusBar = CreateFrame("StatusBar", nil, button)
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    end
    button.statusBar:SetMinMaxValues(0, 1)
    button.statusBar:SetValue(1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(style.barTexture or "Solid"))
    local barColor = style.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Name text
    button.nameText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local nameFont = CooldownCompanion:FetchFont(style.barNameFont or "Friz Quadrata TT")
    local nameFontSize = style.barNameFontSize or 10
    local nameFontOutline = style.barNameFontOutline or "OUTLINE"
    button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
    local nameColor = style.barNameFontColor or {1, 1, 1, 1}
    button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        button.nameText:SetText(buttonData.customName or buttonData.name or "")
    else
        button.nameText:Hide()
    end

    -- Time text
    button.timeText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local cdFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cdFontSize = style.cooldownFontSize or 12
    local cdFontOutline = style.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    if isVertical then
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
    end

    -- Truncate name text so it doesn't overlap time text (horizontal only, opposite sides)
    if not isVertical and nameReverse == timeReverse then
        if nameReverse then
            button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
        else
            button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
        end
    end

    -- Border textures (around bar area, not full button)
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button._barBounds, borderSize)

    -- Loss of control cooldown frame (red swipe over the bar icon)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Hidden cooldown frame for GetCooldownTimes() reads
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all bar buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)

    -- Charge/item count text (overlay)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply charge/item count font settings and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if buttonData.hasCharges or buttonData.isPassive then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = style.chargeAnchor or defAnchor
            chargeXOffset = style.chargeXOffset or defXOff
            chargeYOffset = style.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = CooldownCompanion:FetchFont(buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = buttonData.itemCountFontSize or 12
        local itemFontOutline = buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])
        local itemAnchor = buttonData.itemCountAnchor or defAnchor
        local itemXOffset = buttonData.itemCountXOffset or defXOff
        local itemYOffset = buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end

    -- Aura stack count text — separate FontString for aura stacks, independent of charge text
    if buttonData.auraTracking or buttonData.isPassive then
        button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.auraStackCount:SetText("")
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Bar fill interpolation OnUpdate
    button._barFillElapsed = 0
    local barInterval = style.barUpdateInterval or 0.025
    button:SetScript("OnUpdate", function(self, elapsed)
        -- Detect aura expiry via HasSecretValues + GetRemainingDuration.
        -- Non-secret (out of combat): instant expiry detection.
        -- Secret (in combat): skip; UpdateButtonCooldown handles expiry next tick.
        -- Skip when cooldowns are dirty (target switch / UNIT_AURA just fired,
        -- ticker hasn't processed yet — old DurationObject may be invalidated)
        -- or grace period active (holdover DurationObject from previous target).
        if self._auraActive and self._durationObj
           and not self._auraGraceTicks and not CooldownCompanion._cooldownsDirty then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil
                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                    self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    SetBarAuraEffect(self, false)
                end
            end
        end
        self._barFillElapsed = self._barFillElapsed + elapsed
        if self._barFillElapsed >= barInterval then
            self._barFillElapsed = 0
            UpdateBarFill(self)
        end
    end)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false

    button._auraInstanceID = nil

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Aura effect frames (solid border, pixel glow, proc glow)
    button.barAuraEffect = CreateGlowContainer(button, 32)

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Set name text from resolved spell/item name
    if style.showBarNameText ~= false or buttonData.customName then
        local displayName = buttonData.customName or buttonData.name
        if not buttonData.customName then
            if buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                if spellName then displayName = spellName end
            elseif buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(buttonData.id)
                if itemName then displayName = itemName end
            end
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
        SetupTooltipScripts(button)
    end

    return button
end

function CooldownCompanion:UpdateBarStyle(button, newStyle)
    local barLength = newStyle.barLength or 180
    local barHeight = newStyle.barHeight or 20
    local borderSize = newStyle.borderSize or ST.DEFAULT_BORDER_SIZE
    local showIcon = newStyle.showBarIcon ~= false
    local isVertical = newStyle.barFillVertical or false
    local iconReverse = showIcon and (newStyle.barIconReverse or false)
    local iconSize = (newStyle.barIconSizeOverride and newStyle.barIconSize) or barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    button._isVertical = isVertical

    -- Update bar fill OnUpdate interval
    local barInterval = newStyle.barUpdateInterval or 0.025
    button._barFillElapsed = 0
    button:SetScript("OnUpdate", function(self, elapsed)
        if self._auraActive and self._durationObj
           and not self._auraGraceTicks and not CooldownCompanion._cooldownsDirty then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil

                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                    self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    SetBarAuraEffect(self, false)
                end
            end
        end
        self._barFillElapsed = self._barFillElapsed + elapsed
        if self._barFillElapsed >= barInterval then
            self._barFillElapsed = 0
            UpdateBarFill(self)
        end
    end)

    -- Invalidate cached state
    button._desaturated = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._chargeText = nil
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._itemCount = nil
    button._auraActive = nil

    button._auraInstanceID = nil
    button._inPandemic = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._chargeRecharging = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        SetIconAreaPoints(button.icon, button, isVertical, iconReverse, iconSize, borderSize)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    button.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(button.bg, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        button.bg:SetAllPoints()
    end
    button.bg:Show()

    -- Icon bg + border: always shown when icon visible
    if button.iconBg then
        SetIconAreaPoints(button.iconBg, button, isVertical, iconReverse, iconSize, 0)
        if showIcon then button.iconBg:Show() else button.iconBg:Hide() end
    end
    if button._iconBounds then
        SetIconAreaPoints(button._iconBounds, button, isVertical, iconReverse, iconSize, 0)
    end
    if button.iconBorderTextures then
        ApplyEdgePositions(button.iconBorderTextures, button._iconBounds, borderSize)
        for _, tex in ipairs(button.iconBorderTextures) do
            if showIcon then tex:Show() else tex:Hide() end
        end
    end

    -- Bar area bounds
    if button._barBounds then
        button._barBounds:ClearAllPoints()
        if showIcon then
            SetBarAreaPoints(button._barBounds, button, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
        else
            button._barBounds:SetAllPoints()
        end
    end

    -- Update status bar
    SetBarAreaPoints(button.statusBar, button, isVertical, iconReverse, barAreaLeft, barAreaTop, borderSize)
    if isVertical then
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
    button.statusBar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(newStyle.barTexture or "Solid"))
    local barColor = newStyle.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])

    -- Update background
    local bgColor = newStyle.barBgColor or {0.1, 0.1, 0.1, 0.8}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if button.iconBg then
        button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end

    -- Update border
    local borderColor = newStyle.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button._barBounds or button, borderSize)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
            tex:Show()
        end
    end
    if button.iconBorderTextures then
        for _, tex in ipairs(button.iconBorderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    -- Update name text font and position
    local hasCustomName = button.buttonData and button.buttonData.customName
    if newStyle.showBarNameText ~= false or hasCustomName then
        local nameFont = CooldownCompanion:FetchFont(newStyle.barNameFont or "Friz Quadrata TT")
        local nameFontSize = newStyle.barNameFontSize or 10
        local nameFontOutline = newStyle.barNameFontOutline or "OUTLINE"
        button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
        local nameColor = newStyle.barNameFontColor or {1, 1, 1, 1}
        button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
        button.nameText:Show()
    else
        button.nameText:Hide()
    end

    -- Update time text font (default state; per-tick logic handles aura mode)
    local cdFont = CooldownCompanion:FetchFont(newStyle.cooldownFont or "Friz Quadrata TT")
    local cdFontSize = newStyle.cooldownFontSize or 12
    local cdFontOutline = newStyle.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = newStyle.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    -- Clear cached text mode so per-tick logic re-applies the correct font
    button._barTextMode = nil

    -- Re-anchor name and time text for orientation
    local nameOffX = newStyle.barNameTextOffsetX or 0
    local nameOffY = newStyle.barNameTextOffsetY or 0
    local cdOffX = newStyle.barCdTextOffsetX or 0
    local cdOffY = newStyle.barCdTextOffsetY or 0
    local nameReverse = newStyle.barNameTextReverse
    local timeReverse = newStyle.barTimeTextReverse
    button.nameText:ClearAllPoints()
    button.timeText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            button.nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        button.nameText:SetJustifyH("CENTER")
        if timeReverse then
            button.timeText:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        button.timeText:SetJustifyH("CENTER")
    else
        if nameReverse then
            button.nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("RIGHT")
        else
            button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            button.nameText:SetJustifyH("LEFT")
        end
        if timeReverse then
            button.timeText:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("LEFT")
        else
            button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            button.timeText:SetJustifyH("RIGHT")
        end
        -- Truncate name text so it doesn't overlap time text (opposite sides only)
        if nameReverse == timeReverse then
            if nameReverse then
                button.nameText:SetPoint("LEFT", button.timeText, "RIGHT", 4, 0)
            else
                button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
            end
        end
    end

    -- Update charge/item count font and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if button.buttonData and (button.buttonData.hasCharges or button.buttonData.isPassive) then
        local chargeFont = CooldownCompanion:FetchFont(newStyle.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = newStyle.chargeFontSize or 12
        local chargeFontOutline = newStyle.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = newStyle.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor, chargeXOffset, chargeYOffset
        if showIcon then
            chargeAnchor = newStyle.chargeAnchor or defAnchor
            chargeXOffset = newStyle.chargeXOffset or defXOff
            chargeYOffset = newStyle.chargeYOffset or defYOff
        else
            chargeAnchor = "CENTER"
            chargeXOffset = 0
            chargeYOffset = 0
        end
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = CooldownCompanion:FetchFont(button.buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = button.buttonData.itemCountFontSize or 12
        local itemFontOutline = button.buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = button.buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])
        local itemAnchor = button.buttonData.itemCountAnchor or defAnchor
        local itemXOffset = button.buttonData.itemCountXOffset or defXOff
        local itemYOffset = button.buttonData.itemCountYOffset or defYOff
        AnchorBarCountText(button, showIcon, itemAnchor, itemXOffset, itemYOffset)
    else
        AnchorBarCountText(button, showIcon, defAnchor, defXOff, defYOff)
    end

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        local asFont = CooldownCompanion:FetchFont(newStyle.auraStackFont or "Friz Quadrata TT")
        local asFontSize = newStyle.auraStackFontSize or 12
        local asFontOutline = newStyle.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = newStyle.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = newStyle.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = newStyle.auraStackXOffset or 2
        local asYOff = newStyle.auraStackYOffset or 2
        if showIcon then
            button.auraStackCount:SetPoint(asAnchor, button.icon, asAnchor, asXOff, asYOff)
        else
            button.auraStackCount:SetPoint(asAnchor, button, asAnchor, asXOff, asYOff)
        end
    end

    -- Update spell name text
    self:UpdateButtonIcon(button)
    if newStyle.showBarNameText ~= false or (button.buttonData and button.buttonData.customName) then
        local displayName = button.buttonData.customName or button.buttonData.name
        if not button.buttonData.customName then
            if button.buttonData.type == "spell" then
                local spellName = C_Spell.GetSpellName(button._displaySpellId or button.buttonData.id)
                if spellName then displayName = spellName end
            elseif button.buttonData.type == "item" then
                local itemName = C_Item.GetItemNameByID(button.buttonData.id)
                if itemName then displayName = itemName end
            end
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
