--[[
    CooldownCompanion - ButtonFrame/Glows
    Glow systems: proc glow, aura glow, assisted highlight, bar aura effect,
    pixel glow animation, and shared glow container creation
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local ipairs = ipairs
local unpack = unpack
local string_format = string.format

-- Imports from Helpers
local ApplyEdgePositions = ST._ApplyEdgePositions
local FitHighlightFrame = ST._FitHighlightFrame
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

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

-- Apply bar-specific aura effect (solid border, pixel glow, proc glow)
local function SetBarAuraEffect(button, show, pandemicOverride)
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

-- Exports
ST._SetAssistedHighlight = SetAssistedHighlight
ST._SetProcGlow = SetProcGlow
ST._SetAuraGlow = SetAuraGlow
ST._HideGlowStyles = HideGlowStyles
ST._ShowGlowStyle = ShowGlowStyle
ST._CreateGlowContainer = CreateGlowContainer
ST._CreateAssistedHighlight = CreateAssistedHighlight
ST._GetViewerAuraStackText = GetViewerAuraStackText
ST._SetupTooltipScripts = SetupTooltipScripts
ST._SetBarAuraEffect = SetBarAuraEffect
