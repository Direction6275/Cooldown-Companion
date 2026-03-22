--[[
    CooldownCompanion - ButtonFrame/Glows
    Glow systems: proc glow, aura glow, pixel glow (via LCG), assisted highlight,
    bar aura effect, and shared glow container creation
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local ipairs = ipairs
local next = next
local pairs = pairs
local unpack = unpack
local string_format = string.format
local math_max = math.max
local math_min = math.min

-- Imports from Helpers
local ApplyEdgePositions = ST._ApplyEdgePositions
local FitHighlightFrame = ST._FitHighlightFrame
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Optional external glow library used for pixel glow and extra proc glow styles.
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local PROC_STYLE_LCG_BUTTON = "lcgButton"
local PROC_STYLE_LCG_AUTOCAST = "lcgAutoCast"
local PROC_GLOW_LCG_KEY = "CooldownCompanionProc"
local AURA_GLOW_LCG_KEY = "CooldownCompanionAura"
local PANDEMIC_GLOW_LCG_KEY = "CooldownCompanionPandemic"
local READY_GLOW_LCG_KEY = "CooldownCompanionReady"
local BAR_AURA_EFFECT_LCG_KEY = "CooldownCompanionBarAura"
local PANDEMIC_BAR_EFFECT_LCG_KEY = "CooldownCompanionPandemicBar"

local function IsLibCustomGlowStyle(style)
    return style == PROC_STYLE_LCG_BUTTON or style == PROC_STYLE_LCG_AUTOCAST
end

-- Legacy profile compatibility: lcgProc was removed because it duplicated Blizzard glow.
local function NormalizeGlowStyle(style)
    if style == "lcgProc" then
        return "glow"
    end
    return style
end

local function GetGlowSize(styleTable, sizeKey, glowStyle, defaults)
    local size = styleTable and styleTable[sizeKey]
    if glowStyle == "solid" then
        return size or defaults.solid
    elseif glowStyle == "pixel" then
        return size or defaults.pixel
    elseif glowStyle == PROC_STYLE_LCG_AUTOCAST then
        -- AutoCast scale looks best in 0.2..3. Keep old/invalid values from
        -- inflating particles by falling back to a safe default.
        if size and size >= 0.2 and size <= 3 then
            return size
        end
        return defaults.autocast or 1
    end
    return size or defaults.glow
end

-- Convert user-facing speed (10..200) to LCG AutoCast/ButtonGlow frequency.
local function SpeedToGlowFrequency(speed)
    return math_max(speed or 60, 1) / 480
end

-- Convert user-facing speed to LCG PixelGlow frequency (4x faster than AutoCast).
local function SpeedToPixelFrequency(speed)
    return math_max(speed or 60, 1) / 120
end

local function UsesGlowSpeed(glowStyle)
    return glowStyle == "pixel" or IsLibCustomGlowStyle(glowStyle)
end

-- ButtonGlow_Stop is frame-scoped (no key), so keep per-target ownership to
-- avoid one channel stopping another channel's active lcgButton glow.
local lcgButtonOwnersByTarget = setmetatable({}, {__mode = "k"})
local lcgButtonOwnerSequence = 0

local function AcquireLCGButtonOwner(target, container, color, frequency, frameLevel)
    if not (target and container) then return end
    local owners = lcgButtonOwnersByTarget[target]
    if not owners then
        owners = setmetatable({}, {__mode = "k"})
        lcgButtonOwnersByTarget[target] = owners
    end
    lcgButtonOwnerSequence = lcgButtonOwnerSequence + 1
    owners[container] = {
        order = lcgButtonOwnerSequence,
        color = {color[1], color[2], color[3], color[4]},
        frequency = frequency,
        frameLevel = frameLevel,
    }
end

local function ReleaseLCGButtonOwner(target, container)
    local owners = target and lcgButtonOwnersByTarget[target]
    if not owners then return nil end
    owners[container] = nil
    local fallbackOwner
    local fallbackOrder = -1
    for _, owner in pairs(owners) do
        if owner and owner.order and owner.order > fallbackOrder then
            fallbackOrder = owner.order
            fallbackOwner = owner
        end
    end
    if fallbackOwner then
        return fallbackOwner
    end
    lcgButtonOwnersByTarget[target] = nil
    return nil
end

local function StopLibCustomGlow(container)
    if not container then return end

    -- Stop LCG pixel glow (tracked separately from _lcgStyle)
    if container._pixelTarget then
        if LCG and LCG.PixelGlow_Stop then
            LCG.PixelGlow_Stop(container._pixelTarget, container._pixelKey or "")
        end
        container._pixelTarget = nil
        container._pixelKey = nil
    end

    local lcgStyle = container._lcgStyle
    local lcgTarget = container._lcgTarget
    local lcgKey = container._lcgKey

    container._lcgStyle = nil
    container._lcgTarget = nil
    container._lcgKey = nil

    if not (LCG and lcgStyle and lcgTarget) then return end

    if lcgStyle == PROC_STYLE_LCG_BUTTON and LCG.ButtonGlow_Stop then
        local fallbackOwner = ReleaseLCGButtonOwner(lcgTarget, container)
        if fallbackOwner and LCG.ButtonGlow_Start then
            LCG.ButtonGlow_Start(
                lcgTarget,
                fallbackOwner.color,
                fallbackOwner.frequency or 0.25,
                fallbackOwner.frameLevel or 8
            )
        else
            LCG.ButtonGlow_Stop(lcgTarget)
        end
    elseif lcgStyle == PROC_STYLE_LCG_AUTOCAST and LCG.AutoCastGlow_Stop then
        LCG.AutoCastGlow_Stop(lcgTarget, lcgKey)
    end
end

local function StartLibCustomGlow(container, style, button, color, params)
    if not (LCG and container and button and IsLibCustomGlowStyle(style)) then
        return false
    end

    local key = params.key or PROC_GLOW_LCG_KEY
    local frameLevel = params.frameLevel or 8

    if style == PROC_STYLE_LCG_BUTTON and LCG.ButtonGlow_Start then
        local frequency = params.frequency or 0.25
        LCG.ButtonGlow_Start(button, color, frequency, frameLevel)
        AcquireLCGButtonOwner(button, container, color, frequency, frameLevel)
    elseif style == PROC_STYLE_LCG_AUTOCAST and LCG.AutoCastGlow_Start then
        LCG.AutoCastGlow_Start(button, color, 4, params.frequency or 0.25, params.scale or 2, 0, 0, key, frameLevel)
    else
        return false
    end

    container._lcgStyle = style
    container._lcgTarget = button
    container._lcgKey = key
    return true
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

-- Hide all glow sub-styles in a container table (solidTextures, procFrame).
-- Works for procGlow, auraGlow, barAuraEffect, and assistedHighlight containers.
-- LCG pixel glow is stopped via StopLibCustomGlow.
local function HideGlowStyles(container)
    StopLibCustomGlow(container)
    if container.solidTextures then
        for _, tex in ipairs(container.solidTextures) do tex:Hide() end
    end
    if container.procFrame then
        if container.procFrame.ProcStartAnim then container.procFrame.ProcStartAnim:Stop() end
        if container.procFrame.ProcLoop then container.procFrame.ProcLoop:Stop() end
        container.procFrame:Hide()
    end
    if container.overlayTexture then container.overlayTexture:Hide() end
    -- Assisted highlight blizzard flipbook frame
    if container.blizzardFrame then
        if container.blizzardFrame.Flipbook and container.blizzardFrame.Flipbook.Anim then
            container.blizzardFrame.Flipbook.Anim:Stop()
        end
        container.blizzardFrame:Hide()
    end
end

-- Show the selected glow style on a container.
-- style: "solid", "pixel", "glow", "blizzard", or one of the LibCustomGlow proc styles
-- button: the parent button frame (for positioning)
-- color: {r, g, b, a} color table
-- params: {size, thickness, speed, lines, frequency, scale, key, frameLevel, defaultAlpha} — style-specific parameters
local function ShowGlowStyle(container, style, button, color, params)
    local size = params.size
    local defaultAlpha = params.defaultAlpha or 1
    StopLibCustomGlow(container)
    if IsLibCustomGlowStyle(style) then
        if StartLibCustomGlow(container, style, button, color, params) then
            return
        end
        -- Library unavailable (or failed start): fall back to built-in proc glow.
        style = "glow"
    end
    if style == "solid" then
        ApplyEdgePositions(container.solidTextures, button, size or 2)
        for _, tex in ipairs(container.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
            tex:Show()
        end
    elseif style == "pixel" then
        if LCG and LCG.PixelGlow_Start then
            local key = params.key or ""
            local frequency = SpeedToPixelFrequency(params.speed)
            -- Derive frame level from the container's solidFrame so pixel glow
            -- respects ApplyStrataOrder positioning (icon mode) while staying
            -- reasonable in bar mode where no strata ordering is applied.
            local relativeLevel = 1
            if container.solidFrame then
                relativeLevel = math_max(container.solidFrame:GetFrameLevel() - button:GetFrameLevel(), 1)
            end
            LCG.PixelGlow_Start(button, color, params.lines or 8, frequency,
                size or 8, params.thickness or 4, 0, 0, false, key, relativeLevel)
            container._pixelTarget = button
            container._pixelKey = key
        else
            -- Fallback to solid border if LCG unavailable
            ApplyEdgePositions(container.solidTextures, button, size or 8)
            for _, tex in ipairs(container.solidTextures) do
                tex:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
                tex:Show()
            end
        end
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
    elseif style == "overlay" then
        if container.overlayTexture then
            container.overlayTexture:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
            container.overlayTexture:Show()
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

-- Check whether the underlying animation for the active glow sub-style is still
-- alive.  Cache-match safety net: returns false when an animation's ownership
-- key was removed or playback stopped, so the caller can restart instead of
-- trusting the cached "active" state.
local function IsGlowAnimationAlive(container)
    -- LCG pixel glow: verify LCG still owns the frame on the target
    if container._pixelTarget then
        return container._pixelTarget["_PixelGlow" .. (container._pixelKey or "")] ~= nil
    end
    -- LCG button / autocast glow: verify LCG frame reference on the target
    if container._lcgStyle and container._lcgTarget then
        if container._lcgStyle == PROC_STYLE_LCG_BUTTON then
            -- Check this container's ownership, not just whether _ButtonGlow
            -- exists (another container may share the same target frame).
            local owners = lcgButtonOwnersByTarget[container._lcgTarget]
            return owners and owners[container] ~= nil
        elseif container._lcgStyle == PROC_STYLE_LCG_AUTOCAST then
            return container._lcgTarget["_AutoCastGlow" .. (container._lcgKey or "")] ~= nil
        else
            return false  -- unknown LCG style; assume dead to force restart
        end
    end
    -- CC proc flipbook: check ProcLoop is still playing (visible frames only;
    -- hidden frames have their AnimationGroup auto-paused by WoW and will resume)
    if container.procFrame and container.procFrame:IsShown() then
        if not container.procFrame:IsVisible() then return true end
        return not container.procFrame.ProcLoop or container.procFrame.ProcLoop:IsPlaying()
    end
    -- Blizzard flipbook (assisted highlight): same visible-only check
    if container.blizzardFrame and container.blizzardFrame:IsShown() then
        if not container.blizzardFrame:IsVisible() then return true end
        local anim = container.blizzardFrame.Flipbook and container.blizzardFrame.Flipbook.Anim
        if not anim then return true end
        return anim:IsPlaying()
    end
    -- Overlay is static — without this check, the cache safety net would treat it
    -- as "dead" and restart ShowGlowStyle every tick.
    if container.overlayTexture and container.overlayTexture:IsShown() then
        return true
    end
    -- Solid border: not animated, cannot die.  Positively identify it via
    -- visible solidTextures rather than relying on "nothing else matched."
    if container.solidTextures and container.solidTextures[1]
        and container.solidTextures[1]:IsShown() then
        return true
    end
    -- No recognized sub-style matched — assume dead to force restart.
    return false
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

    -- Skip if state unchanged, unless the animation died and needs a restart.
    if hl.currentState == desiredState and (not desiredState or IsGlowAnimationAlive(hl)) then return end
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

-- Show or hide proc glow on a button.
-- Supports built-in styles and LibCustomGlow styles.
-- Tracks state (style + color + size) to avoid restarting animations every tick.
local function SetProcGlow(button, show)
    local pg = button.procGlow
    if not pg then return end

    -- Build a cache key that includes style, color and size so changes trigger an update
    local desiredState
    if show then
        local style = button.style
        local glowStyle = NormalizeGlowStyle((style and style.procGlowStyle) or "glow")
        local c = (style and style.procGlowColor) or {1, 1, 1, 1}
        local sz = GetGlowSize(style, "procGlowSize", glowStyle, {
            solid = 5, pixel = 8, glow = 30, autocast = 2,
        })
        local th
        local usesSpeed = UsesGlowSpeed(glowStyle)
        th = (glowStyle == "pixel") and ((style and style.procGlowThickness) or 4) or 0
        local spd = usesSpeed and ((style and style.procGlowSpeed) or 50) or 0
        local ln = (glowStyle == "pixel") and ((style and style.procGlowLines) or 8) or 0
        desiredState = string_format("%s%.2f%.2f%.2f%.2f%.2f%.2f%.2f%d", glowStyle, c[1], c[2], c[3], c[4] or 1, sz, th, spd, ln)
    end
    if button._procGlowActive == desiredState and (not desiredState or IsGlowAnimationAlive(pg)) then return end
    button._procGlowActive = desiredState

    HideGlowStyles(pg)

    if not desiredState then return end

    local style = button.style
    local glowStyle = NormalizeGlowStyle((style and style.procGlowStyle) or "glow")
    local color = (style and style.procGlowColor) or {1, 1, 1, 1}
    local sz = GetGlowSize(style, "procGlowSize", glowStyle, {
        solid = 5, pixel = 8, glow = 30, autocast = 2,
    })
    local usesSpeed = UsesGlowSpeed(glowStyle)
    local procThickness = (glowStyle == "pixel") and ((style and style.procGlowThickness) or 4) or 0
    local procSpeed = usesSpeed and ((style and style.procGlowSpeed) or 50) or 0
    local procLines = (glowStyle == "pixel") and ((style and style.procGlowLines) or 8) or nil
    ShowGlowStyle(pg, glowStyle, button, color, {
        size = sz,
        thickness = procThickness,
        speed = procSpeed,
        lines = procLines,
        frequency = usesSpeed and SpeedToGlowFrequency(procSpeed) or nil,
        scale = math_min(math_max(sz, 0.2), 3),
        key = PROC_GLOW_LCG_KEY,
    })
end

-- Show or hide aura active glow on a button.
-- Supports built-in styles and LibCustomGlow styles.
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
            glowStyle = NormalizeGlowStyle((btnStyle and btnStyle.pandemicGlowStyle) or "solid")
            c = (btnStyle and btnStyle.pandemicGlowColor) or {1, 0.5, 0, 1}
        else
            glowStyle = NormalizeGlowStyle((btnStyle and btnStyle.auraGlowStyle) or "pixel")
            c = (btnStyle and btnStyle.auraGlowColor) or {1, 0.84, 0, 0.9}
        end
        if glowStyle ~= "none" then
            local sizeKey, thicknessKey, speedKey, linesKey
            if pandemicOverride then
                sizeKey = "pandemicGlowSize"
                thicknessKey = "pandemicGlowThickness"
                speedKey = "pandemicGlowSpeed"
                linesKey = "pandemicGlowLines"
            else
                sizeKey = "auraGlowSize"
                thicknessKey = "auraGlowThickness"
                speedKey = "auraGlowSpeed"
                linesKey = "auraGlowLines"
            end
            local sz = GetGlowSize(btnStyle, sizeKey, glowStyle, {
                solid = 5, pixel = 8, glow = 30, autocast = 2,
            })
            local th = (glowStyle == "pixel") and ((btnStyle and btnStyle[thicknessKey]) or 4) or 0
            local spd = UsesGlowSpeed(glowStyle) and ((btnStyle and btnStyle[speedKey]) or 50) or 0
            local ln = (glowStyle == "pixel") and ((btnStyle and btnStyle[linesKey]) or 8) or 0
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%.2f%.2f%.2f%d%s", glowStyle, c[1], c[2], c[3], c[4] or 0.9, sz, th, spd, ln, pandemicOverride and "P" or "")
        end
    end

    if button._auraGlowActive == desiredState and (not desiredState or IsGlowAnimationAlive(ag)) then return end
    button._auraGlowActive = desiredState

    HideGlowStyles(ag)

    if not desiredState then return end

    local bd = button.buttonData
    local btnStyle = button.style
    local glowStyle, color
    if pandemicOverride then
        glowStyle = NormalizeGlowStyle((btnStyle and btnStyle.pandemicGlowStyle) or "solid")
        color = (btnStyle and btnStyle.pandemicGlowColor) or {1, 0.5, 0, 1}
    else
        glowStyle = NormalizeGlowStyle((btnStyle and btnStyle.auraGlowStyle) or "pixel")
        color = (btnStyle and btnStyle.auraGlowColor) or {1, 0.84, 0, 0.9}
    end
    local sizeKey, thicknessKey, speedKey, linesKey, glowKey
    if pandemicOverride then
        sizeKey = "pandemicGlowSize"
        thicknessKey = "pandemicGlowThickness"
        speedKey = "pandemicGlowSpeed"
        linesKey = "pandemicGlowLines"
        glowKey = PANDEMIC_GLOW_LCG_KEY
    else
        sizeKey = "auraGlowSize"
        thicknessKey = "auraGlowThickness"
        speedKey = "auraGlowSpeed"
        linesKey = "auraGlowLines"
        glowKey = AURA_GLOW_LCG_KEY
    end
    local size = GetGlowSize(btnStyle, sizeKey, glowStyle, {
        solid = 5, pixel = 8, glow = 30, autocast = 2,
    })
    local thickness = (glowStyle == "pixel") and ((btnStyle and btnStyle[thicknessKey]) or 4) or 0
    local usesSpeed = UsesGlowSpeed(glowStyle)
    local speed = usesSpeed and ((btnStyle and btnStyle[speedKey]) or 50) or 0
    local lines = (glowStyle == "pixel") and ((btnStyle and btnStyle[linesKey]) or 8) or nil
    ShowGlowStyle(ag, glowStyle, button, color, {
        size = size,
        thickness = thickness,
        speed = speed,
        lines = lines,
        frequency = usesSpeed and SpeedToGlowFrequency(speed) or nil,
        scale = math_min(math_max(size, 0.2), 3),
        key = glowKey,
        defaultAlpha = 0.9,
    })
end

-- Show or hide ready glow on a button (glow while off cooldown).
-- Follows the same caching pattern as SetProcGlow.
local function SetReadyGlow(button, show)
    local rg = button.readyGlow
    if not rg then return end

    local desiredState
    if show then
        local style = button.style
        local glowStyle = NormalizeGlowStyle((style and style.readyGlowStyle) or "solid")
        local c = (style and style.readyGlowColor) or {0.2, 1.0, 0.2, 1}
        local sz = GetGlowSize(style, "readyGlowSize", glowStyle, {
            solid = 5, pixel = 8, glow = 30, autocast = 2,
        })
        local th = (glowStyle == "pixel") and ((style and style.readyGlowThickness) or 4) or 0
        local usesSpeed = UsesGlowSpeed(glowStyle)
        local spd = usesSpeed and ((style and style.readyGlowSpeed) or 50) or 0
        local ln = (glowStyle == "pixel") and ((style and style.readyGlowLines) or 8) or 0
        desiredState = string_format("%s%.2f%.2f%.2f%.2f%.2f%.2f%.2f%d", glowStyle, c[1], c[2], c[3], c[4] or 1, sz, th, spd, ln)
    end
    if button._readyGlowActive == desiredState and (not desiredState or IsGlowAnimationAlive(rg)) then return end
    button._readyGlowActive = desiredState

    HideGlowStyles(rg)

    if not desiredState then return end

    local style = button.style
    local glowStyle = NormalizeGlowStyle((style and style.readyGlowStyle) or "solid")
    local color = (style and style.readyGlowColor) or {0.2, 1.0, 0.2, 1}
    local sz = GetGlowSize(style, "readyGlowSize", glowStyle, {
        solid = 5, pixel = 8, glow = 30, autocast = 2,
    })
    local usesSpeed = UsesGlowSpeed(glowStyle)
    local readyThickness = (glowStyle == "pixel") and ((style and style.readyGlowThickness) or 4) or 0
    local readySpeed = usesSpeed and ((style and style.readyGlowSpeed) or 50) or 0
    local readyLines = (glowStyle == "pixel") and ((style and style.readyGlowLines) or 8) or nil
    ShowGlowStyle(rg, glowStyle, button, color, {
        size = sz,
        thickness = readyThickness,
        speed = readySpeed,
        lines = readyLines,
        frequency = usesSpeed and SpeedToGlowFrequency(readySpeed) or nil,
        scale = math_min(math_max(sz, 0.2), 3),
        key = READY_GLOW_LCG_KEY,
    })
end

-- Normalize key press highlight style: only "solid" and "overlay" are valid.
-- Legacy profiles with pixel/glow/lcgButton/lcgAutoCast fall back to "solid".
local function NormalizeKPHStyle(style)
    if style == "solid" or style == "overlay" then return style end
    return "solid"
end

-- Show or hide key press highlight on a button (glow while keybind is held).
-- Only supports "solid" (border) and "overlay" (full-button wash) styles.
-- Follows the same caching pattern as SetProcGlow / SetReadyGlow.
local function SetKeyPressHighlight(button, show)
    local kph = button.keyPressHighlight
    if not kph then return end

    local desiredState
    if show then
        local style = button.style
        local glowStyle = NormalizeKPHStyle((style and style.keyPressHighlightStyle) or "solid")
        local c = (style and style.keyPressHighlightColor) or {1, 1, 1, 0.4}
        local sz = (glowStyle == "solid") and ((style and style.keyPressHighlightSize) or 5) or 0
        desiredState = string_format("%s%.2f%.2f%.2f%.2f%.2f", glowStyle, c[1], c[2], c[3], c[4] or 1, sz)
    end
    if button._keyPressHighlightActive == desiredState and (not desiredState or IsGlowAnimationAlive(kph)) then return end
    button._keyPressHighlightActive = desiredState

    HideGlowStyles(kph)

    if not desiredState then return end

    local style = button.style
    local glowStyle = NormalizeKPHStyle((style and style.keyPressHighlightStyle) or "solid")
    local color = (style and style.keyPressHighlightColor) or {1, 1, 1, 0.4}
    local sz = (glowStyle == "solid") and ((style and style.keyPressHighlightSize) or 5) or 0
    ShowGlowStyle(kph, glowStyle, button, color, {size = sz})
end

-- Create a complete glow container with solid border and proc glow sub-frames.
-- Pixel glow is handled by LibCustomGlow (frames created/pooled by the library).
-- parent: parent button frame
-- overhang: overhang percentage for the proc glow frame (default 32)
-- withOverlay: if true, also create a full-button overlay texture (only KPH needs this)
local function CreateGlowContainer(parent, overhang, withOverlay)
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
    -- Clear the template's OnHide which explicitly Stop()s ProcLoop.  Without it,
    -- WoW's frame system will auto-pause/resume the AnimationGroup across parent
    -- hide/show cycles.  CC already stops ProcLoop in HideGlowStyles when needed.
    procFrame:SetScript("OnHide", nil)
    procFrame:Hide()
    container.procFrame = procFrame

    -- Full-button overlay texture (only needed by key press highlight)
    if withOverlay then
        container.overlayTexture = container.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        container.overlayTexture:SetAllPoints(container.solidFrame)
        container.overlayTexture:Hide()
    end

    -- Ensure solid frame is also non-interactive
    SetFrameClickThroughRecursive(container.solidFrame, true, true)

    return container
end

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

-- Setup tooltip OnEnter/OnLeave scripts on a button frame.
-- Shared between icon-mode (CreateButtonFrame) and style refreshes.
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
    -- Clear OnHide (see CreateGlowContainer for rationale)
    procFrame:SetScript("OnHide", nil)
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
            local sz, th, ln
            if pandemicOverride then
                sz = (btnStyle and btnStyle.pandemicBarEffectSize) or (effect == "solid" and 5 or effect == "pixel" and 8 or 30)
                th = (effect == "pixel") and ((btnStyle and btnStyle.pandemicBarEffectThickness) or 4) or 0
                ln = (effect == "pixel") and ((btnStyle and btnStyle.pandemicBarEffectLines) or 8) or 0
            else
                sz = (btnStyle and btnStyle.barAuraEffectSize) or (effect == "solid" and 5 or effect == "pixel" and 8 or 30)
                th = (effect == "pixel") and ((btnStyle and btnStyle.barAuraEffectThickness) or 4) or 0
                ln = (effect == "pixel") and ((btnStyle and btnStyle.barAuraEffectLines) or 8) or 0
            end
            local spd = (pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectSpeed) or 50) or (btnStyle and btnStyle.barAuraEffectSpeed)) or 50
            desiredState = string_format("%s%.2f%.2f%.2f%.2f%d%d%d%.2f%s", effect, c[1], c[2], c[3], c[4] or 0.9, sz, th, ln, spd, pandemicOverride and "P" or "")
        end
    end

    if button._barAuraEffectActive == desiredState and (not desiredState or IsGlowAnimationAlive(ae)) then return end
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
        size = (effect == "solid" and 5) or (effect == "pixel" and 8) or 30
    end
    local thickness = (pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectThickness) or 4) or (btnStyle and btnStyle.barAuraEffectThickness)) or 4
    local speed = (pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectSpeed) or 50) or (btnStyle and btnStyle.barAuraEffectSpeed)) or 50
    local lines = (effect == "pixel") and ((pandemicOverride and ((btnStyle and btnStyle.pandemicBarEffectLines) or 8) or (btnStyle and btnStyle.barAuraEffectLines)) or 8) or nil
    ShowGlowStyle(ae, effect, button, color, {
        size = size,
        thickness = thickness,
        speed = speed,
        lines = lines,
        key = pandemicOverride and PANDEMIC_BAR_EFFECT_LCG_KEY or BAR_AURA_EFFECT_LCG_KEY,
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
ST._SetReadyGlow = SetReadyGlow
ST._SetKeyPressHighlight = SetKeyPressHighlight
