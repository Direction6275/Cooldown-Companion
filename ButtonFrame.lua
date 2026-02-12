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
local pcall = pcall
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
local UpdateBarFill
local EnsureChargeBars

-- Scratch cooldown (legacy; kept for potential fallback use).
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

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
local function PixelGlowOnUpdate(self, elapsed)
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
        local bd = button.buttonData
        local glowStyle = bd.procGlowStyle or "glow"
        local c = bd.procGlowColor or (button.style and button.style.procGlowColor) or {1, 1, 1, 1}
        local sz, th
        if glowStyle == "solid" then
            sz = bd.procGlowSize or 2
        elseif glowStyle == "pixel" then
            sz = bd.procGlowSize or 4
        else
            sz = bd.procGlowSize or (button.style and button.style.procGlowOverhang) or 32
        end
        th = (glowStyle == "pixel") and (bd.procGlowThickness or 2) or 0
        local spd = (glowStyle == "pixel") and (bd.procGlowSpeed or 60) or 0
        desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%d", glowStyle, c[1], c[2], c[3], c[4] or 1, sz, th, spd)
    end
    if button._procGlowActive == desiredState then return end
    button._procGlowActive = desiredState

    HideGlowStyles(pg)

    if not desiredState then return end

    local bd = button.buttonData
    local glowStyle = bd.procGlowStyle or "glow"
    local color = bd.procGlowColor or (button.style and button.style.procGlowColor) or {1, 1, 1, 1}
    local sz
    if glowStyle == "solid" then
        sz = bd.procGlowSize or 2
    elseif glowStyle == "pixel" then
        sz = bd.procGlowSize or 4
    else
        sz = bd.procGlowSize or (button.style and button.style.procGlowOverhang) or 32
    end
    ShowGlowStyle(pg, glowStyle, button, color, {
        size = sz,
        thickness = bd.procGlowThickness or 2,
        speed = bd.procGlowSpeed or 60,
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
        local style
        local c
        if pandemicOverride then
            style = bd.pandemicGlowStyle or bd.auraGlowStyle or "solid"
            c = bd.pandemicGlowColor or {1, 0.5, 0, 1}
        else
            style = bd.auraGlowStyle or "none"
            c = bd.auraGlowColor or {1, 0.84, 0, 0.9}
        end
        if style ~= "none" then
            local sz, th, spd
            if pandemicOverride then
                sz = bd.pandemicGlowSize or bd.auraGlowSize or (style == "solid" and 2 or style == "pixel" and 4 or 32)
                th = (style == "pixel") and (bd.pandemicGlowThickness or bd.auraGlowThickness or 2) or 0
                spd = (style == "pixel") and (bd.pandemicGlowSpeed or bd.auraGlowSpeed or 60) or 0
            else
                sz = bd.auraGlowSize or (style == "solid" and 2 or style == "pixel" and 4 or 32)
                th = (style == "pixel") and (bd.auraGlowThickness or 2) or 0
                spd = (style == "pixel") and (bd.auraGlowSpeed or 60) or 0
            end
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%d%s", style, c[1], c[2], c[3], c[4] or 0.9, sz, th, spd, pandemicOverride and "P" or "")
        end
    end

    if button._auraGlowActive == desiredState then return end
    button._auraGlowActive = desiredState

    HideGlowStyles(ag)

    if not desiredState then return end

    local bd = button.buttonData
    local style, color
    if pandemicOverride then
        style = bd.pandemicGlowStyle or bd.auraGlowStyle or "solid"
        color = bd.pandemicGlowColor or {1, 0.5, 0, 1}
    else
        style = bd.auraGlowStyle
        color = bd.auraGlowColor or {1, 0.84, 0, 0.9}
    end
    local size
    if pandemicOverride then
        size = bd.pandemicGlowSize or bd.auraGlowSize
    else
        size = bd.auraGlowSize
    end
    local thickness, speed
    if pandemicOverride then
        thickness = bd.pandemicGlowThickness or bd.auraGlowThickness or 2
        speed = bd.pandemicGlowSpeed or bd.auraGlowSpeed or 60
    else
        thickness = bd.auraGlowThickness or 2
        speed = bd.auraGlowSpeed or 60
    end
    -- Default size depends on style
    if not size then
        size = (style == "solid" and 2) or (style == "pixel" and 4) or 32
    end
    ShowGlowStyle(ag, style, button, color, {
        size = size,
        thickness = thickness,
        speed = speed,
        defaultAlpha = 0.9,
    })
end

-- Evaluate per-button visibility rules and set hidden/alpha override state.
-- Called inside UpdateButtonCooldown after cooldown fetch and aura tracking are complete.
-- Fast path: if no toggles are enabled, zero overhead.
local function EvaluateButtonVisibility(button, buttonData, isOnGCD, auraOverrideActive)
    -- Fast path: no visibility toggles enabled
    if not buttonData.hideWhileOnCooldown
       and not buttonData.hideWhileAuraNotActive
       and not buttonData.hideWhileAuraActive then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = nil
        return
    end

    local shouldHide = false
    local hidReasonAuraNotActive = false

    -- Check hideWhileOnCooldown
    if buttonData.hideWhileOnCooldown then
        if buttonData.hasCharges then
            -- Charged spells: hide only when all charges consumed
            if button._chargeCount == 0 then
                shouldHide = true
            end
        elseif buttonData.type == "item" then
            -- Items: check cooldown widget directly (no GCD concept)
            local _, widgetDuration = button.cooldown:GetCooldownTimes()
            if widgetDuration and widgetDuration > 0 then
                shouldHide = true
            end
        else
            -- Non-charged spells: _durationObj non-nil means active CD (secret-safe nil check)
            if button._durationObj and not isOnGCD then
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
        end
    end

    -- Baseline alpha fallback: if the ONLY reason we're hiding is aura-not-active
    -- and useBaselineAlphaFallback is enabled, dim instead of hiding
    if shouldHide and hidReasonAuraNotActive and buttonData.useBaselineAlphaFallback then
        -- Check if any OTHER hide condition also triggered
        local otherHide = false
        if buttonData.hideWhileOnCooldown then
            if buttonData.hasCharges then
                if button._chargeCount == 0 then otherHide = true end
            elseif buttonData.type == "item" then
                local _, wd = button.cooldown:GetCooldownTimes()
                if wd and wd > 0 then otherHide = true end
            else
                if button._durationObj and not isOnGCD then
                    otherHide = true
                end
            end
        end
        if buttonData.hideWhileAuraActive and auraOverrideActive then
            otherHide = true
        end
        if not otherHide then
            -- Use baseline alpha fallback instead of hiding
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
    button.cooldown:SetDrawEdge(true)
    button.cooldown:SetDrawSwipe(true)
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
    local locColor = style.lossOfControlColor or {1, 0, 0, 0.5}
    button.locCooldown:SetSwipeColor(locColor[1], locColor[2], locColor[3], locColor[4])
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Proc glow elements (solid border + animated glow + pixel glow)
    button.procGlow = CreateGlowContainer(button, style.procGlowOverhang or 32)

    -- Aura active glow elements (solid border + animated glow + pixel glow)
    button.auraGlow = CreateGlowContainer(button, 32)

    -- Frame levels: just above cooldown
    local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
    button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.pixelFrame:SetFrameLevel(auraGlowLevel)

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

    -- Keybind text overlay
    button.keybindText = button.overlayFrame:CreateFontString(nil, "OVERLAY")
    do
        local kbFont = style.keybindFont or "Fonts\\FRIZQT__.TTF"
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") and 2 or -2
        local yOff = (anchor == "TOPLEFT" or anchor == "TOPRIGHT") and -2 or 2
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

    -- Update bar name text when the display spell changes (e.g. transform)
    if button.nameText and buttonData.type == "spell" and displayId ~= prevDisplayId then
        local spellName = C_Spell.GetSpellName(displayId)
        if spellName then
            button.nameText:SetText(spellName)
        end
    end
end

-- Update charge count state for a spell with hasCharges enabled.
-- Handles secret-value fallback during combat and recharge readback.
-- Returns the raw charges API table (may be nil) for use by callers.
local function UpdateChargeTracking(button, buttonData)
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
        button._nilConfirmPending = nil
        if cdDur and cdDur > 0 then
            buttonData.chargeCooldownDuration = cdDur
        end
    elseif button._chargeCount then
        -- CDR readback: sync recharge start/duration with real values.
        -- Charge COUNT is determined by hard constraints from
        -- GetSpellChargeDuration + GetSpellCooldownDuration state.
        local durationObj = C_Spell.GetSpellChargeDuration(buttonData.id)

        -- Read back charge recharge via DurationObject methods.
        -- HasSecretValues() gates comparisons; during combat (secret),
        -- charge duration readback is skipped but charge COUNT still works.
        local isRealRecharge = false
        if durationObj and not durationObj:HasSecretValues() then
            if not durationObj:IsZero() then
                local totalDur = durationObj:GetTotalDuration()
                if totalDur and totalDur > 2 then
                    isRealRecharge = true
                    local realStart = durationObj:GetStartTime()
                    local realDur = totalDur

                    -- Detect intermediate charge recovery: recharge start
                    -- jumped forward.  CDR doesn't change start, so a jump
                    -- means the old recharge completed and a new one began.
                    if button._chargeCDStart
                       and button._chargeCount < button._chargeMax
                       and realStart > button._chargeCDStart + 0.5 then
                        button._chargeCount = button._chargeCount + 1
                    end

                    button._chargeCDStart = realStart
                    button._chargeCDDuration = realDur
                    buttonData.chargeCooldownDuration = realDur
                end
            end
        end

        if isRealRecharge then
            -- HARD CONSTRAINT: recharge active means count < max.
            if button._chargeCount >= button._chargeMax then
                button._chargeCount = button._chargeMax - 1
            end

            -- CONSTRAINT: spell main cooldown distinguishes 0 vs 1+.
            -- GetSpellCooldownDuration returns a non-secret DurationObject
            -- for the spell's availability cooldown.  For charge spells:
            --   0 charges → spell on cooldown → non-nil, long duration
            --   1+ charges → spell usable → nil (or brief GCD ≤2s)
            local spellCD = C_Spell.GetSpellCooldownDuration(buttonData.id)
            local spellOnCD = false
            if spellCD and not spellCD:HasSecretValues() then
                if not spellCD:IsZero() then
                    local totalDur = spellCD:GetTotalDuration()
                    spellOnCD = totalDur and totalDur > 2
                end
            end
            if spellOnCD then
                button._chargeCount = 0
            elseif button._chargeCount < 1 then
                -- Only raise 0→1 when recharge has significant time
                -- left.  Near the end (<1s), GetSpellCooldownDuration
                -- may report nil slightly before GetSpellChargeDuration,
                -- creating a brief false "spell usable" window.
                local cdEnd = (button._chargeCDStart or 0)
                    + (button._chargeCDDuration or 0)
                if cdEnd - GetTime() > 1 then
                    button._chargeCount = 1
                end
            end

            button._nilConfirmPending = nil
        elseif button._chargeCount < button._chargeMax then
            -- No real recharge active (nil or GCD only).  Require two
            -- consecutive ticks to confirm, then increment by 1 (not
            -- jump to max) to avoid flashing all bars on intermediate
            -- recoveries.
            if not button._nilConfirmPending then
                button._nilConfirmPending = true
            else
                button._nilConfirmPending = nil
                button._chargeCount = button._chargeCount + 1
                if button._chargeCount >= button._chargeMax then
                    button._chargeCDStart = nil
                    button._chargeCDDuration = nil
                else
                    -- Reset recharge start so bar fill doesn't flash
                    -- from stale old-recharge values.  The readback
                    -- corrects to the real start on the next tick.
                    button._chargeCDStart = GetTime()
                end
            end
        else
            button._nilConfirmPending = nil
        end
    end

    -- Display charge text.  Prefer passing the raw API value to SetText
    -- (C-side, handles secret values like print() does).  Fall back to
    -- the Lua-side estimated count only when the API table is nil.
    if not buttonData.showChargeText then
        if button._chargeText ~= "" then
            button._chargeText = ""
            button.count:SetText("")
        end
    else
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
    end

    return charges
end

-- Update icon-mode visuals: GCD suppression, cooldown text, desaturation, and vertex color.
local function UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD)
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

    -- Cooldown/aura text: pick font + visibility based on current state.
    -- Color is reapplied each tick because WoW's CooldownFrame may reset it.
    if button._cdTextRegion then
        local showText, fontColor, wantFont, wantSize, wantOutline
        if button._auraActive then
            showText = style.showAuraText ~= false
            fontColor = style.auraTextFontColor or {0, 0.925, 1, 1}
            wantFont = style.auraTextFont or "Fonts\\FRIZQT__.TTF"
            wantSize = style.auraTextFontSize or 12
            wantOutline = style.auraTextFontOutline or "OUTLINE"
        else
            showText = style.showCooldownText
            fontColor = style.cooldownFontColor or {1, 1, 1, 1}
            wantFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
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
    end

    -- Desaturation: use DurationObject methods (non-secret in 12.0.1) for
    -- spells/auras; GetCooldownTimes() remains safe for items.
    if style.desaturateOnCooldown then
        local wantDesat = false
        if fetchOk and not isOnGCD then
            if button._durationObj then
                wantDesat = true
            elseif buttonData.type == "item" then
                local _, widgetDuration = button.cooldown:GetCooldownTimes()
                wantDesat = widgetDuration and widgetDuration > 0
            end
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
            and (displayId == assistedSpellID or buttonData.id == assistedSpellID)

        SetAssistedHighlight(button, showHighlight)
    end

    -- Proc glow (spell activation overlay)
    if button.procGlow then
        local showProc = false
        if button._procGlowPreview then
            showProc = true
        elseif buttonData.procGlow == true and buttonData.type == "spell" then
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
            if button._inPandemic then
                showAuraGlow = true
                pandemicOverride = true
            elseif buttonData.auraGlowStyle and buttonData.auraGlowStyle ~= "none" then
                showAuraGlow = true
            end
        end
        SetAuraGlow(button, showAuraGlow, pandemicOverride)
    end
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style

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
    local directQueryDefinitive = false  -- true when direct query checked trusted debuff IDs
    if buttonData.auraTracking and button._auraSpellID then
        local auraUnit = button._auraUnit or "player"

        -- Direct aura query on target switch: bypasses CDM viewer frames
        -- which haven't refreshed yet when PLAYER_TARGET_CHANGED fires.
        -- Only definitive when we have trusted debuff IDs (user config or
        -- ABILITY_BUFF_OVERRIDES); fallback ability IDs may not match the
        -- debuff spell ID on the target.
        if CooldownCompanion._targetSwitched and auraUnit == "target" then
            local directAuraData
            if button._parsedAuraIDs then
                -- User-configured or auto-detected buff spell IDs — trusted
                for _, id in ipairs(button._parsedAuraIDs) do
                    directAuraData = C_UnitAuras.GetUnitAuraBySpellID("target", id)
                    if directAuraData then break end
                end
                directQueryDefinitive = true
            else
                -- Try ability/resolved IDs (may not match debuff ID)
                directAuraData = C_UnitAuras.GetUnitAuraBySpellID("target", button._auraSpellID)
                if not directAuraData and buttonData.id ~= button._auraSpellID then
                    directAuraData = C_UnitAuras.GetUnitAuraBySpellID("target", buttonData.id)
                end
                if not directAuraData and button._displaySpellId
                   and button._displaySpellId ~= button._auraSpellID
                   and button._displaySpellId ~= buttonData.id then
                    directAuraData = C_UnitAuras.GetUnitAuraBySpellID("target", button._displaySpellId)
                end
                -- Check hardcoded ability→debuff overrides — these are trusted
                if not directAuraData then
                    local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
                    if overrideBuffs then
                        for buffId in overrideBuffs:gmatch("%d+") do
                            directAuraData = C_UnitAuras.GetUnitAuraBySpellID("target", tonumber(buffId))
                            if directAuraData then break end
                        end
                        directQueryDefinitive = true
                    end
                end
            end

            if directAuraData and directAuraData.auraInstanceID then
                local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, "target", directAuraData.auraInstanceID)
                if ok and durationObj then
                    button._durationObj = durationObj
                    button.cooldown:SetCooldownFromDurationObject(durationObj)
                    button._auraInstanceID = directAuraData.auraInstanceID
                    auraOverrideActive = true
                    fetchOk = true
                end
            end
        end

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
        if not auraOverrideActive and not directQueryDefinitive and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
            local viewerInstId = viewerFrame.auraInstanceID
            if viewerInstId then
                local unit = viewerFrame.auraDataUnit or auraUnit
                local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, viewerInstId)
                if ok and durationObj then
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
                if viewerFrame.auraDataUnit and viewerCooldown then
                    local startMs, durMs = viewerCooldown:GetCooldownTimes()
                    -- Verify the cooldown hasn't elapsed; GetCooldownTimes() returns
                    -- the original start/duration even after the buff expires.
                    -- pcall: during pool cleanup the cooldown widget may hold
                    -- secret values that reject arithmetic.
                    local ok, active = pcall(function()
                        return durMs > 0 and (startMs + durMs) > GetTime() * 1000
                    end)
                    if ok and active then
                        button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                        auraOverrideActive = true
                        fetchOk = true
                    end
                end
                if button._auraInstanceID then
                    button._auraInstanceID = nil
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
           and prevAuraDurationObj then
            -- Direct query with trusted IDs is definitive: no grace needed.
            -- (Either it found the aura, or the target genuinely has none.)
            if directQueryDefinitive then
                button._auraGraceTicks = nil
            else
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
            end
        else
            -- Fresh aura data (or no aura at all): reset grace counter
            button._auraGraceTicks = nil
        end
        button._auraActive = auraOverrideActive

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

    if not auraOverrideActive then
        if buttonData.type == "spell" then
            -- Get isOnGCD (NeverSecret) via GetSpellCooldown.
            -- pcall: SetCooldown fallback may receive secret startTime/duration.
            local cooldownInfo
            pcall(function()
                cooldownInfo = C_Spell.GetSpellCooldown(buttonData.id)
                if cooldownInfo then
                    isOnGCD = cooldownInfo.isOnGCD
                    if not fetchOk then
                        button.cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                    end
                    fetchOk = true
                end
            end)
            -- DurationObject path: HasSecretValues gates IsZero comparison.
            -- Non-secret: use IsZero to filter zero-duration (spell ready).
            -- Secret: fall back to isOnGCD (NeverSecret) as activity signal.
            local spellCooldownDuration = C_Spell.GetSpellCooldownDuration(buttonData.id)
            if spellCooldownDuration then
                local useIt = false
                if not spellCooldownDuration:HasSecretValues() then
                    if not spellCooldownDuration:IsZero() then useIt = true end
                else
                    if isOnGCD then useIt = true end
                end
                if useIt then
                    button._durationObj = spellCooldownDuration
                    button.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                    fetchOk = true
                end
            end
        elseif buttonData.type == "item" then
            local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
            button.cooldown:SetCooldown(cdStart, cdDuration)
            fetchOk = true
        end
    end

    -- Bar mode: GCD suppression flag (checked by UpdateBarFill OnUpdate)
    if button._isBar then
        button._barGCDSuppressed = fetchOk and not style.showGCDSwipe and isOnGCD
    end

    if not button._isBar then
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD)
    end

    -- Charge count tracking (spells with hasCharges enabled)
    local charges
    if buttonData.type == "spell" and buttonData.hasCharges then
        charges = UpdateChargeTracking(button, buttonData)

        -- Show recharge radial — skip for bars and when aura override is active
        if not button._isBar and not auraOverrideActive then
            local chargeDuration = C_Spell.GetSpellChargeDuration(buttonData.id)
            if chargeDuration then
                button._durationObj = chargeDuration
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

    -- Per-button visibility evaluation (after charge tracking so _chargeCount is current)
    EvaluateButtonVisibility(button, buttonData, isOnGCD, auraOverrideActive)

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
    button._chargeCount = nil
    button._chargeMax = nil
    button._chargeCDStart = nil
    button._chargeCDDuration = nil
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

    -- Always allow countdown numbers; visibility controlled via text alpha per-tick
    button.cooldown:SetHideCountdownNumbers(false)

    -- Update cooldown font settings (default state; per-tick logic handles aura mode)
    local cooldownFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    end
    -- Clear cached text mode so per-tick logic re-applies the correct font
    button._cdTextMode = nil

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

    -- Update keybind text overlay
    if button.keybindText then
        local kbFont = style.keybindFont or "Fonts\\FRIZQT__.TTF"
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        button.keybindText:ClearAllPoints()
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = (anchor == "TOPLEFT" or anchor == "BOTTOMLEFT") and 2 or -2
        local yOff = (anchor == "TOPLEFT" or anchor == "TOPRIGHT") and -2 or 2
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
        local locColor = style.lossOfControlColor or {1, 0, 0, 0.5}
        button.locCooldown:SetSwipeColor(locColor[1], locColor[2], locColor[3], locColor[4])
        button.locCooldown:Clear()
    end

    -- Update proc glow frames
    if button.procGlow then
        button.procGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.procGlow.solidTextures, button, button.buttonData.procGlowSize or 2)
        FitHighlightFrame(button.procGlow.procFrame, button, button.buttonData.procGlowSize or (style.procGlowOverhang or 32))
        if button.procGlow.pixelFrame then
            button.procGlow.pixelFrame:SetAllPoints()
        end
        SetProcGlow(button, false)
    end

    -- Update aura glow frames
    if button.auraGlow then
        button.auraGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.auraGlow.solidTextures, button, button.buttonData.auraGlowSize or 2)
        FitHighlightFrame(button.auraGlow.procFrame, button, button.buttonData.auraGlowSize or 32)
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

-- Create/recreate charge sub-bars for multi-charge spells.
-- Each sub-bar is a self-contained StatusBar with its own bg + border + fill.
EnsureChargeBars = function(button, numBars)
    if button._chargeBarCount == numBars then return end

    -- Destroy old sub-bars
    if button.chargeBars then
        for _, bar in ipairs(button.chargeBars) do
            bar:Hide()
            bar:SetParent(nil)
        end
    end

    if numBars <= 1 then
        button.chargeBars = nil
        button._chargeBarCount = 0
        return
    end

    button.chargeBars = {}
    local sb = button.statusBar
    local sbLevel = sb:GetFrameLevel()

    for i = 1, numBars do
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
        bar:SetFrameLevel(sbLevel - 1)
        bar:EnableMouse(false)
        if button._isVertical then bar:SetOrientation("VERTICAL") end
        if button.style and button.style.barReverseFill then bar:SetReverseFill(true) end

        -- Background (BACKGROUND layer = behind fill)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()

        -- Border textures (OVERLAY layer = on top of fill)
        bar.borderTextures = {}
        for j = 1, 4 do
            bar.borderTextures[j] = bar:CreateTexture(nil, "OVERLAY")
        end

        button.chargeBars[i] = bar
    end

    button._chargeBarCount = numBars
    button._chargeBarsDirty = true
end

-- Position charge sub-bars side-by-side relative to the button frame.
-- Each bar spans full button height with its own bg, border, and fill.
local function LayoutChargeBars(button)
    if not button.chargeBars then return end
    local style = button.style
    local showIcon = style.showBarIcon ~= false
    local barHeight = style.barHeight or 20
    local barLength = style.barLength or 180
    local iconSize = barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local numBars = #button.chargeBars
    local gap = button.buttonData and button.buttonData.barChargeGap or 2

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local bgColor = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    local borderColor = style.borderColor or {0, 0, 0, 1}

    if button._isVertical then
        -- Vertical: stack sub-bars top-to-bottom
        local startY = showIcon and (iconSize + iconOffset) or 0
        local totalHeight = barLength - startY
        local subBarHeight = (totalHeight - (numBars - 1) * gap) / numBars
        if subBarHeight < 1 then subBarHeight = 1 end

        for i, bar in ipairs(button.chargeBars) do
            bar:ClearAllPoints()
            bar:SetSize(barHeight, subBarHeight)
            local yOffset = startY + (i - 1) * (subBarHeight + gap)
            bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -yOffset)

            bar.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
            ApplyEdgePositions(bar.borderTextures, bar, borderSize)
            for _, tex in ipairs(bar.borderTextures) do
                tex:SetColorTexture(unpack(borderColor))
            end
        end
    else
        -- Horizontal: stack sub-bars left-to-right
        local startX = showIcon and (iconSize + iconOffset) or 0
        local totalWidth = barLength - startX
        local subBarWidth = (totalWidth - (numBars - 1) * gap) / numBars
        if subBarWidth < 1 then subBarWidth = 1 end

        for i, bar in ipairs(button.chargeBars) do
            bar:ClearAllPoints()
            bar:SetSize(subBarWidth, barHeight)
            local xOffset = startX + (i - 1) * (subBarWidth + gap)
            bar:SetPoint("TOPLEFT", button, "TOPLEFT", xOffset, 0)

            bar.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
            ApplyEdgePositions(bar.borderTextures, bar, borderSize)
            for _, tex in ipairs(bar.borderTextures) do
                tex:SetColorTexture(unpack(borderColor))
            end
        end
    end
    button._chargeBarsDirty = false
end

-- Lightweight OnUpdate: interpolates bar fill + time text between ticker updates.
UpdateBarFill = function(button)
    -- Charge sub-bar path: drive individual sub-bars from _chargeCount/_chargeCDStart/_chargeCDDuration
    if button.chargeBars and button._chargeBarCount > 0 and not button._auraActive then
        if button._chargeBarsDirty then
            LayoutChargeBars(button)
        end
        local chargeCount = button._chargeCount or 0
        local chargeMax = button._chargeMax or button._chargeBarCount
        local cdStart = button._chargeCDStart
        local cdDur = button._chargeCDDuration
        local now = GetTime()

        -- Compute recharge fraction for the recharging charge
        local rechargeFraction = 0
        local remaining = 0
        if cdStart and cdDur and cdDur > 0 and chargeCount < chargeMax then
            local elapsed = now - cdStart
            rechargeFraction = elapsed / cdDur
            if rechargeFraction > 1 then rechargeFraction = 1 end
            if rechargeFraction < 0 then rechargeFraction = 0 end
            remaining = cdDur - elapsed
            if remaining < 0 then remaining = 0 end
        end

        local reverseCharges = button.buttonData and button.buttonData.barReverseCharges
        local numBars = button._chargeBarCount
        for i, bar in ipairs(button.chargeBars) do
            local ci = reverseCharges and (numBars - i + 1) or i
            if ci <= chargeCount then
                bar:SetValue(1) -- available
            elseif ci == chargeCount + 1 then
                bar:SetValue(rechargeFraction) -- recharging
            else
                bar:SetValue(0) -- spent
            end
        end

        -- Time text: show recharge remaining (charge bars are suppressed when _auraActive, so this is defensive)
        local showTimeText = button._auraActive
            and (button.style.showAuraText ~= false)
            or (not button._auraActive and button.style.showCooldownText)
        if showTimeText then
            -- Switch font/color when mode changes
            local mode = button._auraActive and "aura" or "cd"
            if button._barTextMode ~= mode then
                button._barTextMode = mode
                if button._auraActive then
                    local f = button.style.auraTextFont or "Fonts\\FRIZQT__.TTF"
                    local s = button.style.auraTextFontSize or 12
                    local o = button.style.auraTextFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                else
                    local f = button.style.cooldownFont or "Fonts\\FRIZQT__.TTF"
                    local s = button.style.cooldownFontSize or 12
                    local o = button.style.cooldownFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                end
            end
            if remaining > 0 then
                local cc = button._auraActive
                    and (button.style.auraTextFontColor or {0, 0.925, 1, 1})
                    or (button.style.cooldownFontColor or {1, 1, 1, 1})
                button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
                button.timeText:SetText(FormatBarTime(remaining))
            elseif chargeCount >= chargeMax then
                if button.style.showBarReadyText then
                    local rc = button.style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
                    button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
                    button.timeText:SetText(button.style.barReadyText or "Ready")
                else
                    button.timeText:SetText("")
                end
            else
                local cc = button.style.cooldownFontColor or {1, 1, 1, 1}
                button.timeText:SetTextColor(cc[1], cc[2], cc[3], cc[4])
                button.timeText:SetText("")
            end
        elseif chargeCount >= chargeMax and button.style.showBarReadyText then
            local rc = button.style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
            button.timeText:SetTextColor(rc[1], rc[2], rc[3], rc[4])
            button.timeText:SetText(button.style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
        end

        -- Anchor cooldown text to the recharging sub-bar when enabled
        if button.buttonData.barCdTextOnRechargeBar and button.chargeBars then
            local targetBar
            if chargeCount < chargeMax then
                local logicalBar = chargeCount + 1
                targetBar = reverseCharges and (numBars - logicalBar + 1) or logicalBar
            else
                targetBar = 0 -- all full → anchor back to statusBar
            end
            if button._timeTextAnchoredBar ~= targetBar then
                button._timeTextAnchoredBar = targetBar
                local st = button.style
                local cdOX = st.barCdTextOffsetX or 0
                local cdOY = st.barCdTextOffsetY or 0
                local nmOX = st.barNameTextOffsetX or 0
                local nmOY = st.barNameTextOffsetY or 0
                button.timeText:ClearAllPoints()
                if button._isVertical then
                    if targetBar > 0 and button.chargeBars[targetBar] then
                        button.timeText:SetPoint("TOP", button.chargeBars[targetBar], "TOP", cdOX, -3 + cdOY)
                        button.nameText:ClearAllPoints()
                        button.nameText:SetPoint("BOTTOM", button.statusBar, "BOTTOM", nmOX, 3 + nmOY)
                    else
                        button.timeText:SetPoint("TOP", button.statusBar, "TOP", cdOX, -3 + cdOY)
                        button.nameText:ClearAllPoints()
                        button.nameText:SetPoint("BOTTOM", button.statusBar, "BOTTOM", nmOX, 3 + nmOY)
                    end
                else
                    if targetBar > 0 and button.chargeBars[targetBar] then
                        button.timeText:SetPoint("RIGHT", button.chargeBars[targetBar], "RIGHT", -3 + cdOX, cdOY)
                        -- Detach name truncation from timeText so it doesn't follow
                        button.nameText:ClearAllPoints()
                        button.nameText:SetPoint("LEFT", button.statusBar, "LEFT", 3 + nmOX, nmOY)
                        button.nameText:SetPoint("RIGHT", button.statusBar, "RIGHT", -3, 0)
                    else
                        button.timeText:SetPoint("RIGHT", button.statusBar, "RIGHT", -3 + cdOX, cdOY)
                        -- Restore name truncation against timeText
                        button.nameText:ClearAllPoints()
                        button.nameText:SetPoint("LEFT", button.statusBar, "LEFT", 3 + nmOX, nmOY)
                        button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
                    end
                end
            end
        elseif button._timeTextAnchoredBar and button._timeTextAnchoredBar ~= 0 then
            -- Option disabled — reset back to statusBar
            button._timeTextAnchoredBar = 0
            local st = button.style
            local cdOX = st.barCdTextOffsetX or 0
            local cdOY = st.barCdTextOffsetY or 0
            local nmOX = st.barNameTextOffsetX or 0
            local nmOY = st.barNameTextOffsetY or 0
            button.timeText:ClearAllPoints()
            if button._isVertical then
                button.timeText:SetPoint("TOP", button.statusBar, "TOP", cdOX, -3 + cdOY)
                button.nameText:ClearAllPoints()
                button.nameText:SetPoint("BOTTOM", button.statusBar, "BOTTOM", nmOX, 3 + nmOY)
            else
                button.timeText:SetPoint("RIGHT", button.statusBar, "RIGHT", -3 + cdOX, cdOY)
                button.nameText:ClearAllPoints()
                button.nameText:SetPoint("LEFT", button.statusBar, "LEFT", 3 + nmOX, nmOY)
                button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
            end
        end

        return -- skip single-bar path
    end

    -- Reset text anchor if previously on a charge bar
    if button._timeTextAnchoredBar and button._timeTextAnchoredBar ~= 0 then
        button._timeTextAnchoredBar = 0
        local st = button.style
        local cdOX = st.barCdTextOffsetX or 0
        local cdOY = st.barCdTextOffsetY or 0
        local nmOX = st.barNameTextOffsetX or 0
        local nmOY = st.barNameTextOffsetY or 0
        button.timeText:ClearAllPoints()
        if button._isVertical then
            button.timeText:SetPoint("TOP", button.statusBar, "TOP", cdOX, -3 + cdOY)
            button.nameText:ClearAllPoints()
            button.nameText:SetPoint("BOTTOM", button.statusBar, "BOTTOM", nmOX, 3 + nmOY)
        else
            button.timeText:SetPoint("RIGHT", button.statusBar, "RIGHT", -3 + cdOX, cdOY)
            button.nameText:ClearAllPoints()
            button.nameText:SetPoint("LEFT", button.statusBar, "LEFT", 3 + nmOX, nmOY)
            button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
        end
    end

    -- Single-bar path
    -- DurationObject percent methods return secret values during combat in 12.0.1,
    -- but SetValue() accepts secrets (C-side widget method).  HasSecretValues gates
    -- expiry detection and time text formatting.
    -- Items use SetCooldown() so GetCooldownTimes() remains non-secret for them.
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
        -- Items: GetCooldownTimes() is safe (no DurationObject tainting)
        local startMs, durationMs = button.cooldown:GetCooldownTimes()
        local now = GetTime() * 1000
        onCooldown = durationMs and durationMs > 0
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
                    local f = button.style.auraTextFont or "Fonts\\FRIZQT__.TTF"
                    local s = button.style.auraTextFontSize or 12
                    local o = button.style.auraTextFontOutline or "OUTLINE"
                    button.timeText:SetFont(f, s, o)
                else
                    local f = button.style.cooldownFont or "Fonts\\FRIZQT__.TTF"
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
        button.statusBar:SetValue(1)
        if button.style.showBarReadyText then
            button.timeText:SetText(button.style.barReadyText or "Ready")
        else
            button.timeText:SetText("")
        end
    end
end

-- Update bar-specific display elements (colors, desaturation, aura effects).
-- Bar fill + time text are handled by the per-button OnUpdate for smooth interpolation.
UpdateBarDisplay = function(button, fetchOk)
    local style = button.style

    -- Lazy create/destroy charge sub-bars
    local hasChargeBars = button._chargeMax and button._chargeMax > 1 and not button._auraActive
    local wantCount = hasChargeBars and button._chargeMax or 0
    if wantCount ~= (button._chargeBarCount or 0) then
        EnsureChargeBars(button, wantCount)
    end

    -- Determine onCooldown via nil-checks (secret-safe).
    -- _durationObj is non-nil only when UpdateButtonCooldown found an active CD/aura.
    local onCooldown
    if button.chargeBars and button._chargeBarCount > 0 then
        -- For charge sub-bars, "on cooldown" means any charge is missing
        onCooldown = button._chargeCount and button._chargeMax
            and button._chargeCount < button._chargeMax
    elseif button._durationObj then
        onCooldown = not button._barGCDSuppressed
    elseif button.buttonData.type == "item" then
        local _, durationMs = button.cooldown:GetCooldownTimes()
        onCooldown = durationMs and durationMs > 0
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

    -- Charge sub-bar colors and statusBar transparency
    if button.chargeBars and button._chargeBarCount > 0 then
        local readyColor = style.barColor or {0.2, 0.6, 1.0, 1.0}
        local cdColor = style.barCooldownColor or readyColor
        local chargeCount = button._chargeCount or 0
        local reverseCharges = button.buttonData and button.buttonData.barReverseCharges
        local numBars = button._chargeBarCount
        for i, bar in ipairs(button.chargeBars) do
            local ci = reverseCharges and (numBars - i + 1) or i
            if ci <= chargeCount then
                bar:SetStatusBarColor(readyColor[1], readyColor[2], readyColor[3], readyColor[4])
            else
                bar:SetStatusBarColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
            end
            bar:Show()
        end
        -- Make main statusBar transparent so sub-bars show through; text stays visible
        button.statusBar:SetStatusBarColor(0, 0, 0, 0)
        button._barCdColor = "charge-sub-bars"

        -- Hide bar area bg/border when charge sub-bars are active (they have their own)
        if not button._chargeBarsBgActive then
            button._chargeBarsBgActive = true
            button.bg:Hide()
            for _, tex in ipairs(button.borderTextures) do tex:Hide() end
        end
    else
        -- Hide charge sub-bars if they exist (aura override case)
        if button.chargeBars then
            for _, bar in ipairs(button.chargeBars) do
                bar:Hide()
            end
        end

        -- Restore bar area bg/border when charge bars are inactive
        if button._chargeBarsBgActive then
            button._chargeBarsBgActive = false
            button.bg:Show()
            local borderSz = style.borderSize or ST.DEFAULT_BORDER_SIZE
            ApplyEdgePositions(button.borderTextures, button._barBounds, borderSz)
            for _, tex in ipairs(button.borderTextures) do tex:Show() end
        end

        -- Bar color: switch between ready and cooldown colors
        local wantCdColor = onCooldown and style.barCooldownColor or nil
        if button._barCdColor ~= wantCdColor then
            button._barCdColor = wantCdColor
            local c = wantCdColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
            button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
        end
    end

    -- Icon desaturation
    if style.desaturateOnCooldown then
        local wantDesat = false
        if fetchOk then
            if button.chargeBars and button._chargeBarCount > 0 then
                wantDesat = button._chargeCount and button._chargeMax
                    and button._chargeCount < button._chargeMax
            elseif button._durationObj then
                wantDesat = true
            elseif button.buttonData.type == "item" then
                local _, durationMs = button.cooldown:GetCooldownTimes()
                wantDesat = durationMs and durationMs > 0
            end
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

    -- Bar aura color: override bar fill when aura is active (pandemic overrides aura color)
    local wantAuraColor
    if button._pandemicPreview then
        wantAuraColor = button.buttonData.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
    elseif button._auraActive then
        if button._inPandemic then
            wantAuraColor = button.buttonData.barPandemicColor or DEFAULT_BAR_PANDEMIC_COLOR
        else
            wantAuraColor = button.buttonData.barAuraColor or DEFAULT_BAR_AURA_COLOR
        end
    end
    if button._barAuraColor ~= wantAuraColor then
        button._barAuraColor = wantAuraColor
        if not wantAuraColor then
            -- Reset to normal color immediately (don't wait for next tick)
            button._barCdColor = nil
            if button.chargeBars and button._chargeBarCount > 0 then
                -- Sub-bars will be re-shown on next tick
                button.statusBar:SetStatusBarColor(0, 0, 0, 0)
            else
                local resetColor = onCooldown and style.barCooldownColor or nil
                local c = resetColor or style.barColor or {0.2, 0.6, 1.0, 1.0}
                button.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
            end
        end
    end
    if wantAuraColor then
        button.statusBar:SetStatusBarColor(wantAuraColor[1], wantAuraColor[2], wantAuraColor[3], wantAuraColor[4])
    end

    -- Bar aura effect (pandemic overrides effect color)
    local barAuraEffectPandemic = button._pandemicPreview or (button._auraActive and button._inPandemic and button.buttonData.pandemicGlow)
    SetBarAuraEffect(button, button._auraActive or button._barAuraEffectPreview or button._pandemicPreview, barAuraEffectPandemic or false)

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
        local effect
        if pandemicOverride then
            effect = bd.pandemicBarEffect or bd.barAuraEffect or "none"
        else
            effect = bd.barAuraEffect or "none"
        end
        if effect ~= "none" then
            local c
            if pandemicOverride then
                c = bd.pandemicGlowColor or {1, 0.5, 0, 1}
            else
                c = bd.barAuraEffectColor or {1, 0.84, 0, 0.9}
            end
            local sz, th
            if pandemicOverride then
                sz = bd.pandemicBarEffectSize or (effect == "solid" and 2 or effect == "pixel" and 4 or 32)
                th = (effect == "pixel") and (bd.pandemicBarEffectThickness or 2) or 0
            else
                sz = bd.barAuraEffectSize or (effect == "solid" and 2 or effect == "pixel" and 4 or 32)
                th = (effect == "pixel") and (bd.barAuraEffectThickness or 2) or 0
            end
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%s", effect, c[1], c[2], c[3], c[4] or 0.9, sz, th, pandemicOverride and "P" or "")
        end
    end

    if button._barAuraEffectActive == desiredState then return end
    button._barAuraEffectActive = desiredState

    HideGlowStyles(ae)

    if not desiredState then return end

    local bd = button.buttonData
    local effect
    if pandemicOverride then
        effect = bd.pandemicBarEffect or bd.barAuraEffect
    else
        effect = bd.barAuraEffect
    end
    local color
    if pandemicOverride then
        color = bd.pandemicGlowColor or {1, 0.5, 0, 1}
    else
        color = bd.barAuraEffectColor or {1, 0.84, 0, 0.9}
    end
    local size
    if pandemicOverride then
        size = bd.pandemicBarEffectSize
    else
        size = bd.barAuraEffectSize
    end
    -- Default size depends on effect style
    if not size then
        size = (effect == "solid" and 2) or (effect == "pixel" and 4) or 32
    end
    local thickness = (pandemicOverride and bd.pandemicBarEffectThickness or bd.barAuraEffectThickness) or 2
    local speed = (pandemicOverride and bd.pandemicBarEffectSpeed or bd.barAuraEffectSpeed) or 60
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

    local iconSize = barHeight
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
        if isVertical then
            button.bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -barAreaTop)
            button.bg:SetPoint("BOTTOMRIGHT")
        else
            button.bg:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft, 0)
            button.bg:SetPoint("BOTTOMRIGHT")
        end
    else
        button.bg:SetAllPoints()
    end
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    if showIcon then
        if isVertical then
            button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
            button.icon:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", -borderSize, -(iconSize - borderSize))
        else
            button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize - borderSize, borderSize)
        end
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- Hidden 1x1 icon (still needed for UpdateButtonIcon)
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Charge sub-bars (created lazily in UpdateBarDisplay when charge count is known)
    button.chargeBars = nil
    button._chargeBarCount = 0
    button._chargeBarsBgActive = false

    -- Icon background + border (always shown when icon visible)
    button.iconBg = button:CreateTexture(nil, "BACKGROUND")
    if isVertical then
        button.iconBg:SetPoint("TOPLEFT", 0, 0)
        button.iconBg:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, -iconSize)
    else
        button.iconBg:SetPoint("TOPLEFT", 0, 0)
        button.iconBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize, 0)
    end
    button.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    if not showIcon then button.iconBg:Hide() end

    button._iconBounds = CreateFrame("Frame", nil, button)
    button._iconBounds:EnableMouse(false)
    if isVertical then
        button._iconBounds:SetPoint("TOPLEFT", 0, 0)
        button._iconBounds:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, -iconSize)
    else
        button._iconBounds:SetPoint("TOPLEFT", 0, 0)
        button._iconBounds:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize, 0)
    end

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
        if isVertical then
            button._barBounds:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -barAreaTop)
            button._barBounds:SetPoint("BOTTOMRIGHT")
        else
            button._barBounds:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft, 0)
            button._barBounds:SetPoint("BOTTOMRIGHT")
        end
    else
        button._barBounds:SetAllPoints()
    end

    -- StatusBar
    button.statusBar = CreateFrame("StatusBar", nil, button)
    if isVertical then
        button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", borderSize, -(barAreaTop + borderSize))
        button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + borderSize, -borderSize)
        button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
    end
    button.statusBar:SetMinMaxValues(0, 1)
    button.statusBar:SetValue(1)
    button.statusBar:SetReverseFill(style.barReverseFill or false)
    button.statusBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    local barColor = style.barColor or {0.2, 0.6, 1.0, 1.0}
    button.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    button.statusBar:EnableMouse(false)

    -- Name text
    button.nameText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local nameFont = style.barNameFont or "Fonts\\FRIZQT__.TTF"
    local nameFontSize = style.barNameFontSize or 10
    local nameFontOutline = style.barNameFontOutline or "OUTLINE"
    button.nameText:SetFont(nameFont, nameFontSize, nameFontOutline)
    local nameColor = style.barNameFontColor or {1, 1, 1, 1}
    button.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    if isVertical then
        button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        button.nameText:SetJustifyH("CENTER")
    else
        button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
        button.nameText:SetJustifyH("LEFT")
    end
    if style.showBarNameText ~= false or buttonData.customName then
        button.nameText:SetText(buttonData.customName or buttonData.name or "")
    else
        button.nameText:Hide()
    end

    -- Time text
    button.timeText = button.statusBar:CreateFontString(nil, "OVERLAY")
    local cdFont = style.cooldownFont or "Fonts\\FRIZQT__.TTF"
    local cdFontSize = style.cooldownFontSize or 12
    local cdFontOutline = style.cooldownFontOutline or "OUTLINE"
    button.timeText:SetFont(cdFont, cdFontSize, cdFontOutline)
    local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
    button.timeText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    if isVertical then
        button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        button.timeText:SetJustifyH("CENTER")
    else
        button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
        button.timeText:SetJustifyH("RIGHT")
    end

    -- Truncate name text so it doesn't overlap time text (horizontal only)
    if not isVertical then
        button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
    end

    -- Border textures (around bar area, not full button)
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button._barBounds, borderSize)

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

    -- Apply charge/item count font settings and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if buttonData.hasCharges then
        local chargeFont = buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = buttonData.chargeFontSize or 12
        local chargeFontOutline = buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = buttonData.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor = buttonData.chargeAnchor or defAnchor
        local chargeXOffset = buttonData.chargeXOffset or defXOff
        local chargeYOffset = buttonData.chargeYOffset or defYOff
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF"
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

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Bar fill interpolation OnUpdate
    button._barFillElapsed = 0
    local barInterval = style.barUpdateInterval or 0.025
    button:SetScript("OnUpdate", function(self, elapsed)
        -- Detect aura expiry via HasSecretValues + GetRemainingDuration.
        -- Non-secret (out of combat): instant expiry detection.
        -- Secret (in combat): skip; UpdateButtonCooldown handles expiry next tick.
        if self._auraActive and self._durationObj then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil
                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    -- If charge sub-bars exist, make statusBar transparent so sub-bars show
                    if self._chargeMax and self._chargeMax > 1 then
                        self.statusBar:SetStatusBarColor(0, 0, 0, 0)
                        self._barCdColor = nil
                    else
                        local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                        self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    end
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
    local iconSize = barHeight
    local iconOffset = showIcon and (newStyle.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = showIcon and (iconSize + iconOffset) or 0

    button.style = newStyle
    button._isVertical = isVertical

    -- Update bar fill OnUpdate interval
    local barInterval = newStyle.barUpdateInterval or 0.025
    button._barFillElapsed = 0
    button:SetScript("OnUpdate", function(self, elapsed)
        if self._auraActive and self._durationObj then
            if not self._durationObj:HasSecretValues() then
                if self._durationObj:GetRemainingDuration() <= 0 then
                    self._durationObj = nil

                    self._auraActive = false
                    self._inPandemic = false
                    self._barAuraColor = nil
                    if self._chargeMax and self._chargeMax > 1 then
                        self.statusBar:SetStatusBarColor(0, 0, 0, 0)
                        self._barCdColor = nil
                    else
                        local c = self.style.barColor or {0.2, 0.6, 1.0, 1.0}
                        self.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4])
                    end
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
    button._chargeCount = nil
    button._chargeMax = nil
    button._chargeCDStart = nil
    button._chargeCDDuration = nil
    button._nilConfirmPending = nil
    button._displaySpellId = nil
    button._itemCount = nil
    button._auraActive = nil

    button._auraInstanceID = nil
    button._inPandemic = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._barCdColor = nil
    button._barReadyTextColor = nil
    button._barAuraColor = nil
    button._barAuraEffectActive = nil
    button._timeTextAnchoredBar = nil

    if isVertical then
        button:SetSize(barHeight, barLength)
    else
        button:SetSize(barLength, barHeight)
    end

    -- Update icon
    button.icon:ClearAllPoints()
    if showIcon then
        if isVertical then
            button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
            button.icon:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", -borderSize, -(iconSize - borderSize))
        else
            button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize - borderSize, borderSize)
        end
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon:SetAlpha(1)
    else
        button.icon:SetPoint("TOPLEFT", 0, 0)
        button.icon:SetSize(1, 1)
        button.icon:SetAlpha(0)
    end

    -- Force sub-bar rebuild on next tick
    button._chargeBarCount = 0

    -- Restore bar area bg/border (charge bars may have altered these)
    button._chargeBarsBgActive = false
    button.bg:ClearAllPoints()
    if showIcon then
        if isVertical then
            button.bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -barAreaTop)
            button.bg:SetPoint("BOTTOMRIGHT")
        else
            button.bg:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft, 0)
            button.bg:SetPoint("BOTTOMRIGHT")
        end
    else
        button.bg:SetAllPoints()
    end
    button.bg:Show()

    -- Icon bg + border: always shown when icon visible
    if button.iconBg then
        button.iconBg:ClearAllPoints()
        if isVertical then
            button.iconBg:SetPoint("TOPLEFT", 0, 0)
            button.iconBg:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, -iconSize)
        else
            button.iconBg:SetPoint("TOPLEFT", 0, 0)
            button.iconBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize, 0)
        end
        if showIcon then button.iconBg:Show() else button.iconBg:Hide() end
    end
    if button._iconBounds then
        button._iconBounds:ClearAllPoints()
        if isVertical then
            button._iconBounds:SetPoint("TOPLEFT", 0, 0)
            button._iconBounds:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, -iconSize)
        else
            button._iconBounds:SetPoint("TOPLEFT", 0, 0)
            button._iconBounds:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", iconSize, 0)
        end
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
            if isVertical then
                button._barBounds:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -barAreaTop)
                button._barBounds:SetPoint("BOTTOMRIGHT")
            else
                button._barBounds:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft, 0)
                button._barBounds:SetPoint("BOTTOMRIGHT")
            end
        else
            button._barBounds:SetAllPoints()
        end
    end

    -- Update status bar
    button.statusBar:ClearAllPoints()
    if isVertical then
        button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", borderSize, -(barAreaTop + borderSize))
        button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
        button.statusBar:SetOrientation("VERTICAL")
    else
        button.statusBar:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + borderSize, -borderSize)
        button.statusBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -borderSize, borderSize)
        button.statusBar:SetOrientation("HORIZONTAL")
    end
    button.statusBar:SetReverseFill(newStyle.barReverseFill or false)
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

    -- Update time text font (default state; per-tick logic handles aura mode)
    local cdFont = newStyle.cooldownFont or "Fonts\\FRIZQT__.TTF"
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
    button.nameText:ClearAllPoints()
    button.timeText:ClearAllPoints()
    if isVertical then
        button.nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        button.nameText:SetJustifyH("CENTER")
        button.timeText:SetPoint("TOP", cdOffX, -3 + cdOffY)
        button.timeText:SetJustifyH("CENTER")
    else
        button.nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
        button.nameText:SetJustifyH("LEFT")
        button.timeText:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
        button.timeText:SetJustifyH("RIGHT")
        -- Truncate name text so it doesn't overlap time text
        button.nameText:SetPoint("RIGHT", button.timeText, "LEFT", -4, 0)
    end

    -- Update charge/item count font and anchor to icon or bar center
    local defAnchor = showIcon and "BOTTOMRIGHT" or "BOTTOM"
    local defXOff = showIcon and -2 or 0
    local defYOff = 2
    if button.buttonData and button.buttonData.hasCharges then
        local chargeFont = button.buttonData.chargeFont or "Fonts\\FRIZQT__.TTF"
        local chargeFontSize = button.buttonData.chargeFontSize or 12
        local chargeFontOutline = button.buttonData.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = button.buttonData.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])
        local chargeAnchor = button.buttonData.chargeAnchor or defAnchor
        local chargeXOffset = button.buttonData.chargeXOffset or defXOff
        local chargeYOffset = button.buttonData.chargeYOffset or defYOff
        AnchorBarCountText(button, showIcon, chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = button.buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF"
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
