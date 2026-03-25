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
-- string.format was previously used for glow cache keys; replaced with
-- per-field comparisons to eliminate per-tick string allocations.
local math_max = math.max
local math_min = math.min

-- Imports from Helpers
local ApplyEdgePositions = ST._ApplyEdgePositions
local FitHighlightFrame = ST._FitHighlightFrame
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_PANDEMIC_COLOR = ST._DEFAULT_BAR_PANDEMIC_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_ASSISTED_HL_COLOR = {0.3, 1, 0.3, 0.9}
local DEFAULT_PANDEMIC_COLOR = {1, 0.5, 0, 1}
local DEFAULT_AURA_GLOW_COLOR = {1, 0.84, 0, 0.9}
local DEFAULT_READY_COLOR = {0.2, 1.0, 0.2, 1}
local DEFAULT_KEY_PRESS_COLOR = {1, 1, 1, 0.4}
local DEFAULT_GLOW_SIZES = {solid = 5, pixel = 8, glow = 30, autocast = 2}

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
        container._pixelGlowLookupKey = nil
    end

    local lcgStyle = container._lcgStyle
    local lcgTarget = container._lcgTarget
    local lcgKey = container._lcgKey

    container._lcgStyle = nil
    container._lcgTarget = nil
    container._lcgKey = nil
    container._autocastGlowLookupKey = nil

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
    if style == PROC_STYLE_LCG_AUTOCAST then
        container._autocastGlowLookupKey = "_AutoCastGlow" .. (key or "")
    end
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

-- Hide all glow sub-styles in a container table (solidTextures, procFrame, overlayTexture).
-- Works for procGlow, auraGlow, barAuraEffect, assistedHighlight, and keyPressHighlight containers.
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
-- style: "solid", "overlay", "pixel", "glow", "blizzard", or one of the LibCustomGlow proc styles
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
            container._pixelGlowLookupKey = "_PixelGlow" .. key
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
        return container._pixelTarget[container._pixelGlowLookupKey] ~= nil
    end
    -- LCG button / autocast glow: verify LCG frame reference on the target
    if container._lcgStyle and container._lcgTarget then
        if container._lcgStyle == PROC_STYLE_LCG_BUTTON then
            -- Check this container's ownership, not just whether _ButtonGlow
            -- exists (another container may share the same target frame).
            local owners = lcgButtonOwnersByTarget[container._lcgTarget]
            return owners and owners[container] ~= nil
        elseif container._lcgStyle == PROC_STYLE_LCG_AUTOCAST then
            return container._lcgTarget[container._autocastGlowLookupKey] ~= nil
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
        local c = button.style.assistedHighlightColor or DEFAULT_ASSISTED_HL_COLOR
        colorKey = ST.FormatColorKey(c)
    elseif show and highlightStyle == "proc" then
        local c = button.style.assistedHighlightProcColor or DEFAULT_WHITE
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
        local color = button.style.assistedHighlightColor or DEFAULT_ASSISTED_HL_COLOR
        ShowGlowStyle(hl, "solid", button, color, {size = button.style.assistedHighlightBorderSize or 2})
    elseif highlightStyle == "blizzard" then
        ShowGlowStyle(hl, "blizzard", button, {1, 1, 1, 1}, {})
    elseif highlightStyle == "proc" then
        local color = button.style.assistedHighlightProcColor or DEFAULT_WHITE
        ShowGlowStyle(hl, "glow", button, color, {size = button.style.assistedHighlightProcOverhang or 32})
    end
end

--------------------------------------------------------------------------------
-- Glow Setter Factory
--
-- All glow setters (proc, aura, ready, KPH, bar aura effect) share an identical
-- structure: fetch params → off-path sentinel check → per-field cache comparison
-- → cache update → HideGlowStyles → ShowGlowStyle. The factory produces a
-- closure with all config baked in as upvalues (zero per-tick allocation).
--
-- 53 upvalues per closure (well under Lua 5.1's 60 limit). Cache comparison
-- uses upvalue string keys for button[field] lookups — same cost as literal
-- field access (both are interned-string hash lookups).
--------------------------------------------------------------------------------
local function MakeGlowSetter(cfg)
    -- Config → local upvalues (consumed once at load time)
    local containerKey     = cfg.containerKey
    local hasPandemic      = cfg.hasPandemic
    local normalize        = cfg.normalizeStyle
    local noneIsOff        = cfg.noneIsOff
    local fullParams       = cfg.fullParams
    local useGetGlowSize   = cfg.useGetGlowSize
    local defaultAlpha     = cfg.defaultAlpha or 1
    local includeFreqScale = cfg.includeFrequencyScale
    local optsDefaultAlpha = cfg.optsDefaultAlpha

    -- Style keys: normal path
    local styleKey    = cfg.styleKey
    local colorKey    = cfg.colorKey
    local sizeKey     = cfg.sizeKey
    local thKey       = cfg.thicknessKey
    local spdKey      = cfg.speedKey
    local lnKey       = cfg.linesKey
    local defStyle    = cfg.defaultStyle
    local defColor    = cfg.defaultColor
    local lcgKey      = cfg.lcgKey

    -- Style keys: pandemic path (nil when hasPandemic is false)
    local panStyleKey = cfg.pandemicStyleKey
    local panColorKey = cfg.pandemicColorKey
    local panSizeKey  = cfg.pandemicSizeKey
    local panThKey    = cfg.pandemicThicknessKey
    local panSpdKey   = cfg.pandemicSpeedKey
    local panLnKey    = cfg.pandemicLinesKey
    local panDefStyle = cfg.pandemicDefaultStyle
    local panDefColor = cfg.pandemicDefaultColor
    local panLcgKey   = cfg.pandemicLcgKey

    -- Cache field names on button (must match existing names for Preview.lua compat)
    local cActive   = cfg.cacheActive
    local cStyle    = cfg.cacheStyle
    local cR        = cfg.cacheR
    local cG        = cfg.cacheG
    local cB        = cfg.cacheB
    local cA        = cfg.cacheA
    local cSz       = cfg.cacheSz
    local cTh       = cfg.cacheTh
    local cSpd      = cfg.cacheSpd
    local cLn       = cfg.cacheLn
    local cPandemic = cfg.cachePandemic

    -- Defaults for full-params path
    local defThickness = cfg.defaultThickness or 4
    local defSpeed     = cfg.defaultSpeed or 50
    local defLines     = cfg.defaultLines or 8

    -- KPH-specific: size only applies for "solid" style
    local sizeOnlyForSolid = cfg.sizeOnlyForSolid
    local defSize          = cfg.defaultSize

    -- The actual glow setter closure. Signature: (button, show [, pandemicOverride])
    return function(button, show, pandemicOverride)
        local container = button[containerKey]
        if not container then return end

        local glowStyle, color, sz, th, spd, ln, usesSpeed, resolvedLcgKey

        if show then
            local btnStyle = button.style

            -- Resolve style and color based on pandemic branching
            if hasPandemic and pandemicOverride then
                glowStyle = (btnStyle and btnStyle[panStyleKey]) or panDefStyle
                color = (btnStyle and btnStyle[panColorKey]) or panDefColor
                resolvedLcgKey = panLcgKey
            else
                glowStyle = (btnStyle and btnStyle[styleKey]) or defStyle
                color = (btnStyle and btnStyle[colorKey]) or defColor
                resolvedLcgKey = lcgKey
            end

            -- Apply normalization if configured
            if normalize then
                glowStyle = normalize(glowStyle)
            end

            -- "none" style means off
            if noneIsOff and glowStyle == "none" then
                glowStyle = nil
            end

            if glowStyle then
                -- Resolve size
                if useGetGlowSize then
                    local sk = (hasPandemic and pandemicOverride) and panSizeKey or sizeKey
                    sz = GetGlowSize(btnStyle, sk, glowStyle, DEFAULT_GLOW_SIZES)
                elseif sizeOnlyForSolid then
                    sz = (glowStyle == "solid") and ((btnStyle and btnStyle[sizeKey]) or defSize) or 0
                end

                -- Resolve full params (thickness, speed, lines) if supported
                if fullParams then
                    usesSpeed = UsesGlowSpeed(glowStyle)
                    local tk, sk2, lk
                    if hasPandemic and pandemicOverride then
                        tk, sk2, lk = panThKey, panSpdKey, panLnKey
                    else
                        tk, sk2, lk = thKey, spdKey, lnKey
                    end
                    th = (glowStyle == "pixel") and ((btnStyle and btnStyle[tk]) or defThickness) or 0
                    spd = usesSpeed and ((btnStyle and btnStyle[sk2]) or defSpeed) or 0
                    ln = (glowStyle == "pixel") and ((btnStyle and btnStyle[lk]) or defLines) or 0
                end
            end
        end

        -- Off path: == nil (not "not") so external false-invalidation falls through
        if not glowStyle then
            if button[cActive] == nil then return end
            button[cActive] = nil
            HideGlowStyles(container)
            return
        end

        -- On path: compare individual cached fields
        local ca = color[4] or defaultAlpha
        if button[cActive]
           and button[cStyle] == glowStyle
           and button[cR] == color[1] and button[cG] == color[2]
           and button[cB] == color[3] and button[cA] == ca
           and (not cSz or button[cSz] == sz)
           and (not cTh or button[cTh] == th)
           and (not cSpd or button[cSpd] == spd)
           and (not cLn or button[cLn] == ln)
           and (not cPandemic or button[cPandemic] == pandemicOverride)
           and IsGlowAnimationAlive(container) then
            return
        end

        -- Update cache
        button[cActive] = true
        button[cStyle] = glowStyle
        button[cR] = color[1]
        button[cG] = color[2]
        button[cB] = color[3]
        button[cA] = ca
        if cSz then button[cSz] = sz end
        if cTh then button[cTh] = th end
        if cSpd then button[cSpd] = spd end
        if cLn then button[cLn] = ln end
        if cPandemic then button[cPandemic] = pandemicOverride end

        HideGlowStyles(container)

        -- Build opts table (state-change path only, so allocation is OK)
        local opts = { size = sz, key = resolvedLcgKey }
        if fullParams then
            opts.thickness = th
            opts.speed = spd
            if glowStyle == "pixel" then opts.lines = ln end
        end
        if includeFreqScale and usesSpeed then
            opts.frequency = SpeedToGlowFrequency(spd)
            opts.scale = math_min(math_max(sz, 0.2), 3)
        end
        if optsDefaultAlpha then
            opts.defaultAlpha = optsDefaultAlpha
        end

        ShowGlowStyle(container, glowStyle, button, color, opts)
    end
end

--------------------------------------------------------------------------------
-- Glow Setter Instances (factory calls, executed once at load time)
--------------------------------------------------------------------------------

local SetProcGlow = MakeGlowSetter({
    containerKey       = "procGlow",
    hasPandemic        = false,
    normalizeStyle     = NormalizeGlowStyle,
    noneIsOff          = false,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultAlpha       = 1,
    includeFrequencyScale = true,
    styleKey           = "procGlowStyle",       defaultStyle = "glow",
    colorKey           = "procGlowColor",       defaultColor = DEFAULT_WHITE,
    sizeKey            = "procGlowSize",
    thicknessKey       = "procGlowThickness",
    speedKey           = "procGlowSpeed",
    linesKey           = "procGlowLines",
    lcgKey             = PROC_GLOW_LCG_KEY,
    cacheActive = "_procGlowActive",  cacheStyle = "_procGlowStyle",
    cacheR = "_procGlowR",  cacheG = "_procGlowG",
    cacheB = "_procGlowB",  cacheA = "_procGlowA",
    cacheSz = "_procGlowSz", cacheTh = "_procGlowTh",
    cacheSpd = "_procGlowSpd", cacheLn = "_procGlowLn",
})

local SetAuraGlow = MakeGlowSetter({
    containerKey       = "auraGlow",
    hasPandemic        = true,
    normalizeStyle     = NormalizeGlowStyle,
    noneIsOff          = true,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultAlpha       = 0.9,
    includeFrequencyScale = true,
    optsDefaultAlpha   = 0.9,
    styleKey           = "auraGlowStyle",       defaultStyle = "pixel",
    colorKey           = "auraGlowColor",       defaultColor = DEFAULT_AURA_GLOW_COLOR,
    sizeKey            = "auraGlowSize",
    thicknessKey       = "auraGlowThickness",
    speedKey           = "auraGlowSpeed",
    linesKey           = "auraGlowLines",
    lcgKey             = AURA_GLOW_LCG_KEY,
    pandemicStyleKey     = "pandemicGlowStyle",     pandemicDefaultStyle = "solid",
    pandemicColorKey     = "pandemicGlowColor",     pandemicDefaultColor = DEFAULT_PANDEMIC_COLOR,
    pandemicSizeKey      = "pandemicGlowSize",
    pandemicThicknessKey = "pandemicGlowThickness",
    pandemicSpeedKey     = "pandemicGlowSpeed",
    pandemicLinesKey     = "pandemicGlowLines",
    pandemicLcgKey       = PANDEMIC_GLOW_LCG_KEY,
    cacheActive = "_auraGlowActive",  cacheStyle = "_auraGlowStyle",
    cacheR = "_auraGlowR",  cacheG = "_auraGlowG",
    cacheB = "_auraGlowB",  cacheA = "_auraGlowA",
    cacheSz = "_auraGlowSz", cacheTh = "_auraGlowTh",
    cacheSpd = "_auraGlowSpd", cacheLn = "_auraGlowLn",
    cachePandemic = "_auraGlowPandemic",
})

local SetReadyGlow = MakeGlowSetter({
    containerKey       = "readyGlow",
    hasPandemic        = false,
    normalizeStyle     = NormalizeGlowStyle,
    noneIsOff          = false,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultAlpha       = 1,
    includeFrequencyScale = true,
    styleKey           = "readyGlowStyle",      defaultStyle = "solid",
    colorKey           = "readyGlowColor",      defaultColor = DEFAULT_READY_COLOR,
    sizeKey            = "readyGlowSize",
    thicknessKey       = "readyGlowThickness",
    speedKey           = "readyGlowSpeed",
    linesKey           = "readyGlowLines",
    lcgKey             = READY_GLOW_LCG_KEY,
    cacheActive = "_readyGlowActive",  cacheStyle = "_readyGlowStyle",
    cacheR = "_readyGlowR",  cacheG = "_readyGlowG",
    cacheB = "_readyGlowB",  cacheA = "_readyGlowA",
    cacheSz = "_readyGlowSz", cacheTh = "_readyGlowTh",
    cacheSpd = "_readyGlowSpd", cacheLn = "_readyGlowLn",
})

-- Normalize key press highlight style: only "solid" and "overlay" are valid.
-- Legacy profiles with pixel/glow/lcgButton/lcgAutoCast fall back to "solid".
local function NormalizeKPHStyle(style)
    if style == "solid" or style == "overlay" then return style end
    return "solid"
end

local SetKeyPressHighlight = MakeGlowSetter({
    containerKey       = "keyPressHighlight",
    hasPandemic        = false,
    normalizeStyle     = NormalizeKPHStyle,
    noneIsOff          = false,
    fullParams         = false,
    useGetGlowSize     = false,
    sizeOnlyForSolid   = true,
    defaultSize        = 5,
    defaultAlpha       = 1,
    includeFrequencyScale = false,
    styleKey           = "keyPressHighlightStyle",  defaultStyle = "solid",
    colorKey           = "keyPressHighlightColor",  defaultColor = DEFAULT_KEY_PRESS_COLOR,
    sizeKey            = "keyPressHighlightSize",
    cacheActive = "_keyPressHighlightActive", cacheStyle = "_kphStyle",
    cacheR = "_kphR",  cacheG = "_kphG",
    cacheB = "_kphB",  cacheA = "_kphA",
    cacheSz = "_kphSz",
})

-- Create a complete glow container with solid border and proc glow sub-frames.
-- Pixel glow is handled by LibCustomGlow (frames created/pooled by the library).
-- parent: parent button frame
-- overhang: overhang percentage for the proc glow frame (default 32)
-- withOverlay: if true, also create a full-button overlay texture (only KPH needs this)
-- Returns table {solidFrame, solidTextures, procFrame[, overlayTexture]}
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
    local hlColor = style.assistedHighlightColor or DEFAULT_ASSISTED_HL_COLOR
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

local SetBarAuraEffect = MakeGlowSetter({
    containerKey       = "barAuraEffect",
    hasPandemic        = true,
    noneIsOff          = true,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultAlpha       = 0.9,
    includeFrequencyScale = false,
    optsDefaultAlpha   = 0.9,
    styleKey           = "barAuraEffect",           defaultStyle = "none",
    colorKey           = "barAuraEffectColor",      defaultColor = DEFAULT_AURA_GLOW_COLOR,
    sizeKey            = "barAuraEffectSize",
    thicknessKey       = "barAuraEffectThickness",
    speedKey           = "barAuraEffectSpeed",
    linesKey           = "barAuraEffectLines",
    lcgKey             = BAR_AURA_EFFECT_LCG_KEY,
    pandemicStyleKey     = "pandemicBarEffect",         pandemicDefaultStyle = "none",
    pandemicColorKey     = "pandemicBarEffectColor",     pandemicDefaultColor = DEFAULT_PANDEMIC_COLOR,
    pandemicSizeKey      = "pandemicBarEffectSize",
    pandemicThicknessKey = "pandemicBarEffectThickness",
    pandemicSpeedKey     = "pandemicBarEffectSpeed",
    pandemicLinesKey     = "pandemicBarEffectLines",
    pandemicLcgKey       = PANDEMIC_BAR_EFFECT_LCG_KEY,
    cacheActive = "_barAuraEffectActive", cacheStyle = "_baeEffect",
    cacheR = "_baeR",  cacheG = "_baeG",
    cacheB = "_baeB",  cacheA = "_baeA",
    cacheSz = "_baeSz", cacheTh = "_baeTh",
    cacheSpd = "_baeSpd", cacheLn = "_baeLn",
    cachePandemic = "_baePandemic",
})

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
