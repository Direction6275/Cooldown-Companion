--[[
    CooldownCompanion - ButtonFrame/Glows
    Glow systems: proc glow, aura glow, pixel glow (via LCG), assisted highlight,
    bar aura effect, and shared glow container creation
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike

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

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_ASSISTED_HL_COLOR = {0.3, 1, 0.3, 0.9}
local DEFAULT_PANDEMIC_COLOR = {1, 0.5, 0, 1}
local DEFAULT_AURA_GLOW_COLOR = {1, 0.84, 0, 0.9}
local DEFAULT_AURA_GLOW_COLOR2 = {0.1, 0.3, 1, 0.9}
local DEFAULT_READY_COLOR = {0.2, 1.0, 0.2, 1}
local DEFAULT_KEY_PRESS_COLOR = {1, 1, 1, 0.4}
local DEFAULT_GLOW_SIZES = {solid = 5, pixel = 8, glow = 30, autocast = 2}
-- ants overhang matches Blizzard's assisted-combat highlight ratio (66px art
-- on a 45px button); dashes size is the line length in px (LCG default 8;
-- thickness is its own key, LCG default 4).
local BAR_AURA_GLOW_SIZES = {solid = 2, pixel = 8, glow = 30, autocast = 2, ants = 23, dashes = 8}
local DEFAULT_AURA_GLOW_DASH_THICKNESS = 4
-- Marching ants flipbook from ActionBarButtonAssistedCombatHighlightTemplate
-- (Blizzard_ActionBar/Shared/ActionButtonComponentTemplate.xml): 30 frames in
-- a 6-row x 5-column sheet over 1 second, looping; 66px art on a 45px button.
local KIT_ANTS_ATLAS = "rotationhelper_ants_flipbook"
-- Dash pool ceiling for the dashes aura glow style. The kit prebuilds this
-- many (write-once regions); the CC-side preview grows its pool lazily.
local MAX_AURA_GLOW_DASHES = 8
-- Dash pool ceiling for the pixel glow style (proc/ready containers grow
-- lazily, so the higher ceiling costs nothing until a user asks for it; the
-- lines slider tops out at 16).
local MAX_PIXEL_DASHES = 16
-- Aura glow speed key semantics per style, in seconds: pulse/colorShift store
-- a cycle duration, dashes stores one full lap around the button. Keyed by
-- both kit names and their normalized preview names.
local AURA_GLOW_SPEED_DEFAULTS = {
    pulse = 0.5, pulsingBorder = 0.5,
    colorShift = 0.8,
    dashes = 2,
}

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

local function NormalizeBarAuraEffectStyle(style)
    if style == "color" then
        return "none"
    end
    return style
end

local function IsBarAuraIndicatorEnabled(style)
    if type(style) ~= "table" then
        return false
    end
    local enabled = rawget(style, "barAuraIndicatorEnabled")
    if enabled ~= nil then
        return enabled == true
    end
    if rawget(style, "barAuraEffect") == nil and style.barAuraIndicatorEnabled ~= nil then
        return style.barAuraIndicatorEnabled == true
    end
    return (style.barAuraEffect or "none") ~= "none"
end

local function GetGlowSize(styleTable, sizeKey, glowStyle, defaults)
    local size = styleTable and styleTable[sizeKey]
    if glowStyle == "solid" or glowStyle == "pulsingBorder" or glowStyle == "colorShift" then
        return size or defaults.solid
    elseif glowStyle == "ants" then
        return size or defaults.ants
    elseif glowStyle == "dashes" then
        return size or defaults.dashes
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

-- Convert user-facing speed (10..200) to a pixel glow lap duration in
-- seconds. Matches the retired LCG PixelGlow timing exactly (frequency was
-- speed/120, lap = 1/frequency), so stored speeds keep their meaning.
local function SpeedToPixelLap(speed)
    return 120 / math_max(speed or 60, 1)
end

local function UsesGlowSpeed(glowStyle)
    return glowStyle == "pixel" or glowStyle == "pulsingBorder"
        or glowStyle == "colorShift" or glowStyle == "dashes"
        or IsLibCustomGlowStyle(glowStyle)
end

local function StopSolidBorderPulse(container)
    local frame = container and container.solidFrame
    if frame and frame._solidPulseAG then
        frame._solidPulseAG:Stop()
    end
    if frame then
        -- Aura-shell entries latch their glow containers to alpha 0
        -- (IconMode SetGlowContainerShellAlpha); restoring a flat 1 here
        -- would resurrect glow edges on an invisible shell button.
        frame:SetAlpha(container._ccShellAlpha or 1)
    end
end

local function StartSolidBorderPulse(container, speed, restart)
    local frame = container and container.solidFrame
    if not frame then return end
    if not frame._solidPulseAG then
        local ag = frame:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local anim = ag:CreateAnimation("Alpha")
        frame._solidPulseAG = ag
        frame._solidPulseAnim = anim
    end
    frame._solidPulseAnim:SetDuration(speed or 0.5)
    frame._solidPulseAnim:SetFromAlpha(1.0)
    frame._solidPulseAnim:SetToAlpha(0.3)
    if restart then
        frame._solidPulseAG:Stop()
        frame._solidPulseAG:Play()
    elseif not frame._solidPulseAG:IsPlaying() then
        frame._solidPulseAG:Play()
    end
end

-- Color shift: per-edge VertexColor bounce on the shared solid border
-- textures. The animation leaves a residual vertex tint when stopped, so the
-- stop path restores plain white before another style reuses the edges.
local function StopColorShift(container)
    if not (container and container._colorShiftAGs) then return end
    for i, ag in ipairs(container._colorShiftAGs) do
        ag:Stop()
        container.solidTextures[i]:SetVertexColor(1, 1, 1, 1)
    end
end

local function StartColorShift(container, colorA, colorB, speed)
    if not (container and container.solidTextures) then return end
    if not container._colorShiftAGs then
        container._colorShiftAGs = {}
        container._colorShiftAnims = {}
        for i, tex in ipairs(container.solidTextures) do
            local ag = tex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            container._colorShiftAGs[i] = ag
            container._colorShiftAnims[i] = ag:CreateAnimation("VertexColor")
        end
    end
    local duration = speed
    if not duration or duration <= 0 or duration > 2 then
        duration = AURA_GLOW_SPEED_DEFAULTS.colorShift
    end
    local startColor = CreateColor(colorA[1], colorA[2], colorA[3], colorA[4] or 0.9)
    local endColor = CreateColor(colorB[1], colorB[2], colorB[3], colorB[4] or 0.9)
    for i, ag in ipairs(container._colorShiftAGs) do
        ag:Stop()
        local anim = container._colorShiftAnims[i]
        anim:SetStartColor(startColor)
        anim:SetEndColor(endColor)
        anim:SetDuration(duration)
        ag:Play()
    end
end

-- Dashes: LibCustomGlow-style pixel glow, including the corner WRAP. Each
-- dash is four line pieces, one per border edge, each clipped by a static
-- WHITE8X8 MaskTexture strip along its edge (mask + translation clipping is
-- P13-validated in combat). A piece travels its edge's line extended by the
-- dash length, so as one piece's tail slides out through its strip boundary
-- at a corner, the next edge's piece slides in through its own boundary at
-- the same speed: the visible total stays one dash length and the dash
-- appears to bend around the corner, exactly like LCG's two-texture crop
-- trick. Between passes a piece detours outside the button (invisible,
-- beyond every strip) back to its start, so each piece is a fixed
-- five-Translation loop: delay/travel/out/back/in, or the straddled variant
-- when a dash's phase puts a piece mid-edge at the loop boundary. All
-- durations are distance-proportional against one shared lap time, keeping
-- the four pieces of a dash in permanent sync. The horizontal strips own the
-- corner squares (strips never overlap), so the pieces never double-draw.
-- Shared by the live kit renderer and its CC-side preview twin: both store
-- dashes as { pieces = { {tex, ag, trs} x4 } } plus a shared 4-mask set.
local function StyleDashPerimeter(dashList, masks, anchorFrame, length, thickness, lap, count, r, g, b, a)
    local w, h = anchorFrame:GetSize()
    local T = math_max(1, thickness or DEFAULT_AURA_GLOW_DASH_THICKNESS)
    local L = math_max(2, length or BAR_AURA_GLOW_SIZES.dashes)

    -- Clip strips, one per border; verticals sit between the horizontals.
    masks[1]:ClearAllPoints()
    masks[1]:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    masks[1]:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, -T)
    masks[2]:ClearAllPoints()
    masks[2]:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", -T, -T)
    masks[2]:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, T)
    masks[3]:ClearAllPoints()
    masks[3]:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, T)
    masks[3]:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    masks[4]:ClearAllPoints()
    masks[4]:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, -T)
    masks[4]:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", T, T)

    -- Dash-center path: inset by half the thickness, clockwise from the
    -- top-left path corner. Coordinates are relative to the anchor TOPLEFT.
    local spanW = math_max(w - T, 1)
    local spanH = math_max(h - T, 1)
    local P = 2 * (spanW + spanH)
    local edges = {
        { sx = T / 2,     sy = -T / 2,       dx = 1,  dy = 0,  len = spanW, ox = 0,  oy = 1,  horizontal = true },
        { sx = w - T / 2, sy = -T / 2,       dx = 0,  dy = -1, len = spanH, ox = 1,  oy = 0 },
        { sx = w - T / 2, sy = -(h - T / 2), dx = -1, dy = 0,  len = spanW, ox = 0,  oy = -1, horizontal = true },
        { sx = T / 2,     sy = -(h - T / 2), dx = 0,  dy = 1,  len = spanH, ox = -1, oy = 0 },
    }
    local arc = 0
    for j = 1, 4 do
        edges[j].c = arc
        arc = arc + edges[j].len
    end

    for i, dash in ipairs(dashList) do
        if i <= count then
            local s0 = (i - 1) * P / count
            for j = 1, 4 do
                local e = edges[j]
                local piece = dash.pieces[j]
                -- Engagement window: the piece is on its extended line while
                -- any part of the dash overlaps this edge (or its corners).
                local winLen = math_min(e.len + L + T, P)
                local d0 = ((e.c - (L + T) / 2) - s0) % P
                local wx = e.sx - e.dx * (L + T) / 2
                local wy = e.sy - e.dy * (L + T) / 2
                local out = 2 * T + 2
                local trs = piece.trs

                piece.ag:Stop()
                piece.tex:SetColorTexture(r, g, b, a)
                if e.horizontal then
                    piece.tex:SetSize(L, T)
                else
                    piece.tex:SetSize(T, L)
                end
                piece.tex:ClearAllPoints()
                if d0 + winLen <= P then
                    -- delay at window start, travel, detour home
                    piece.tex:SetPoint("CENTER", anchorFrame, "TOPLEFT", wx, wy)
                    local rest = math_max(lap * (P - d0 - winLen) / P, 0)
                    trs[1]:SetOffset(0, 0)
                    trs[1]:SetDuration(lap * d0 / P)
                    trs[2]:SetOffset(e.dx * winLen, e.dy * winLen)
                    trs[2]:SetDuration(lap * winLen / P)
                    trs[3]:SetOffset(e.ox * out, e.oy * out)
                    trs[3]:SetDuration(rest * 0.1)
                    trs[4]:SetOffset(-e.dx * winLen, -e.dy * winLen)
                    trs[4]:SetDuration(rest * 0.8)
                    trs[5]:SetOffset(-e.ox * out, -e.oy * out)
                    trs[5]:SetDuration(rest * 0.1)
                else
                    -- window straddles the loop boundary: finish the pass,
                    -- detour home, start the next pass's first part
                    local q = P - d0
                    local rem = winLen - q
                    piece.tex:SetPoint("CENTER", anchorFrame, "TOPLEFT", wx + e.dx * q, wy + e.dy * q)
                    local rest = math_max(lap * (P - winLen) / P, 0)
                    trs[1]:SetOffset(e.dx * rem, e.dy * rem)
                    trs[1]:SetDuration(lap * rem / P)
                    trs[2]:SetOffset(e.ox * out, e.oy * out)
                    trs[2]:SetDuration(rest * 0.1)
                    trs[3]:SetOffset(-e.dx * winLen, -e.dy * winLen)
                    trs[3]:SetDuration(rest * 0.8)
                    trs[4]:SetOffset(-e.ox * out, -e.oy * out)
                    trs[4]:SetDuration(rest * 0.1)
                    trs[5]:SetOffset(e.dx * q, e.dy * q)
                    trs[5]:SetDuration(lap * q / P)
                end
                piece.tex:SetAlpha(1)
                piece.tex:Show()
                piece.ag:Play()
            end
        else
            for j = 1, 4 do
                local piece = dash.pieces[j]
                piece.ag:Stop()
                piece.tex:SetAlpha(0)
                piece.tex:Hide()
            end
        end
    end
end

local function CreateDashMasks(parent)
    local masks = {}
    for j = 1, 4 do
        local mask = parent:CreateMaskTexture()
        mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        masks[j] = mask
    end
    return masks
end

local function CreateDashRegions(parent, dashList, masks, count)
    for i = #dashList + 1, count do
        local pieces = {}
        for j = 1, 4 do
            local tex = parent:CreateTexture(nil, "OVERLAY", nil, 2)
            tex:SetAlpha(0)
            tex:AddMaskTexture(masks[j])
            local ag = tex:CreateAnimationGroup()
            ag:SetLooping("REPEAT")
            local trs = {}
            for o = 1, 5 do
                local tr = ag:CreateAnimation("Translation")
                tr:SetOrder(o)
                trs[o] = tr
            end
            pieces[j] = { tex = tex, ag = ag, trs = trs }
        end
        dashList[i] = { pieces = pieces }
    end
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

local function PrepareProcGlowLoop(frame, color, resetLoopAlpha)
    if not frame then return end

    TintProcGlowFrame(frame, color)
    if frame.ProcAltGlow then
        frame.ProcAltGlow:Hide()
    end
    if frame.ProcStartAnim then
        frame.ProcStartAnim:Stop()
    end
    if frame.ProcStartFlipbook then
        frame.ProcStartFlipbook:Show()
        frame.ProcStartFlipbook:SetAlpha(0)
    end
    if frame.ProcLoopFlipbook then
        frame.ProcLoopFlipbook:Show()
        frame.ProcLoopFlipbook:SetAlpha(resetLoopAlpha and 0 or 1)
    end
end

local function PlayProcGlowLoop(frame)
    if not frame then return end
    if frame.ProcLoop then
        if not frame.ProcLoop:IsPlaying() then
            frame.ProcLoop:Play()
        end
    elseif frame.ProcLoopFlipbook then
        frame.ProcLoopFlipbook:SetAlpha(1)
    end
end

-- Hide all glow sub-styles in a container table (solidTextures, procFrame, overlayTexture).
-- Works for procGlow, auraGlow, barAuraEffect, assistedHighlight, and keyPressHighlight containers.
-- LCG button/autocast glow is stopped via StopLibCustomGlow.
local function HideGlowStyles(container)
    StopLibCustomGlow(container)
    if container.solidTextures then
        StopSolidBorderPulse(container)
        StopColorShift(container)
        for _, tex in ipairs(container.solidTextures) do tex:Hide() end
    end
    if container.antsFlip then
        container.antsAG:Stop()
        container.antsFlip:Hide()
    end
    if container.dashes then
        for _, d in ipairs(container.dashes) do
            for _, piece in ipairs(d.pieces) do
                piece.ag:Stop()
                piece.tex:Hide()
            end
        end
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
    -- Clear any residual vertex tint before another style reuses the edges.
    StopColorShift(container)
    if IsLibCustomGlowStyle(style) then
        if StartLibCustomGlow(container, style, button, color, params) then
            return
        end
        -- Library unavailable (or failed start): fall back to built-in proc glow.
        style = "glow"
    end
    if style == "solid" or style == "pulsingBorder" then
        ApplyEdgePositions(container.solidTextures, button, size or 2)
        for _, tex in ipairs(container.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
            tex:Show()
        end
        if style == "pulsingBorder" then
            StartSolidBorderPulse(container, params.speed, true)
        else
            StopSolidBorderPulse(container)
        end
    elseif style == "pixel" then
        -- CC-owned dash engine (same machinery as the dashes style): regions
        -- live on solidFrame, so ApplyStrataOrder positioning and shell alpha
        -- stamping apply — unlike the retired LCG renderer, which parented to
        -- the button and ignored both.
        local count = math_min(math_max(params.lines or 8, 1), MAX_PIXEL_DASHES)
        container.dashes = container.dashes or {}
        container.dashMasks = container.dashMasks or CreateDashMasks(container.solidFrame)
        CreateDashRegions(container.solidFrame, container.dashes, container.dashMasks, count)
        local lap = SpeedToPixelLap(params.speed)
        StyleDashPerimeter(container.dashes, container.dashMasks, button, size or 8, params.thickness, lap, count,
            color[1], color[2], color[3], color[4] or defaultAlpha)
    elseif style == "glow" then
        FitHighlightFrame(container.procFrame, button, size or 32)
        PrepareProcGlowLoop(container.procFrame, color, true)
        container.procFrame:Show()
        PlayProcGlowLoop(container.procFrame)
    elseif style == "colorShift" then
        ApplyEdgePositions(container.solidTextures, button, size or 2)
        for _, tex in ipairs(container.solidTextures) do
            -- Base texture stays white so the VertexColor animation owns the
            -- full color range.
            tex:SetColorTexture(1, 1, 1, 1)
            tex:Show()
        end
        StopSolidBorderPulse(container)
        StartColorShift(container, color, params.color2 or DEFAULT_AURA_GLOW_COLOR2, params.speed)
    elseif style == "ants" then
        if not container.antsFlip then
            local flip = container.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            flip:SetAtlas(KIT_ANTS_ATLAS)
            local ag = flip:CreateAnimationGroup()
            ag:SetLooping("REPEAT")
            local anim = ag:CreateAnimation("FlipBook")
            anim:SetDuration(1)
            anim:SetFlipBookRows(6)
            anim:SetFlipBookColumns(5)
            anim:SetFlipBookFrames(30)
            container.antsFlip = flip
            container.antsAG = ag
        end
        local w, h = button:GetSize()
        local pct = (size or 23) / 100
        container.antsFlip:ClearAllPoints()
        container.antsFlip:SetPoint("CENTER", button, "CENTER", 0, 0)
        container.antsFlip:SetSize(w + w * pct * 2, h + h * pct * 2)
        container.antsFlip:SetVertexColor(color[1], color[2], color[3], color[4] or defaultAlpha)
        container.antsFlip:Show()
        container.antsAG:Play()
    elseif style == "dashes" then
        local count = params.lines or 2
        count = math_min(math_max(count, 1), MAX_AURA_GLOW_DASHES)
        container.dashes = container.dashes or {}
        container.dashMasks = container.dashMasks or CreateDashMasks(container.solidFrame)
        CreateDashRegions(container.solidFrame, container.dashes, container.dashMasks, count)
        local lap = params.speed
        if not lap or lap <= 0 or lap > 2 then
            lap = AURA_GLOW_SPEED_DEFAULTS.dashes
        end
        StyleDashPerimeter(container.dashes, container.dashMasks, button, size or 8, params.thickness, lap, count,
            color[1], color[2], color[3], color[4] or defaultAlpha)
    elseif style == "overlay" then
        if not container.overlayTexture then
            container.overlayTexture = container.solidFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            container.overlayTexture:SetAllPoints(container.solidFrame)
            container.overlayTexture:Hide()
        end
        container.overlayTexture:SetColorTexture(color[1], color[2], color[3], color[4] or defaultAlpha)
        container.overlayTexture:Show()
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
    -- Marching ants flipbook (same visible-only rule as the proc flipbook)
    if container.antsFlip and container.antsFlip:IsShown() then
        if not container.antsFlip:IsVisible() then return true end
        return container.antsAG:IsPlaying()
    end
    -- Traveling dashes: all pieces share one lifecycle, the first suffices
    if container.dashes and container.dashes[1]
        and container.dashes[1].pieces[1].tex:IsShown() then
        local piece = container.dashes[1].pieces[1]
        if not piece.tex:IsVisible() then return true end
        return piece.ag:IsPlaying()
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

local function TryUpdateGlowStyleInPlace(container, style, button, color, params)
    if style == "solid" or style == "pulsingBorder" then
        ApplyEdgePositions(container.solidTextures, button, params.size or 2)
        for _, tex in ipairs(container.solidTextures) do
            tex:SetColorTexture(color[1], color[2], color[3], color[4] or params.defaultAlpha or 1)
            tex:Show()
        end
        if style == "pulsingBorder" then
            StartSolidBorderPulse(container, params.speed, false)
        else
            StopSolidBorderPulse(container)
        end
        return true
    elseif style == "glow" and container.procFrame and container.procFrame:IsShown() then
        FitHighlightFrame(container.procFrame, button, params.size or 32)
        PrepareProcGlowLoop(container.procFrame, color, false)
        container.procFrame:Show()
        PlayProcGlowLoop(container.procFrame)
        return true
    elseif style == "overlay" and container.overlayTexture and container.overlayTexture:IsShown() then
        container.overlayTexture:SetColorTexture(color[1], color[2], color[3], color[4] or params.defaultAlpha or 1)
        container.overlayTexture:Show()
        return true
    end

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
-- ~58 upvalues per closure (Lua 5.1 caps at 60 — almost no headroom left;
-- the next field added to this factory likely needs to fold existing
-- upvalues into a table first). Cache comparison
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
    local defaultSizes     = cfg.defaultSizes or DEFAULT_GLOW_SIZES

    -- Style keys: normal path
    local styleKey    = cfg.styleKey
    local colorKey    = cfg.colorKey
    local color2Key   = cfg.color2Key
    local defColor2   = cfg.defaultColor2
    local cC2         = cfg.cacheColor2
    local defSpeeds   = cfg.defaultSpeeds
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

        local glowStyle, color, color2, sz, th, spd, ln, usesSpeed, resolvedLcgKey

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
                -- Second color (color shift only)
                if color2Key and glowStyle == "colorShift" then
                    color2 = (btnStyle and btnStyle[color2Key]) or defColor2
                end

                -- Resolve size
                if useGetGlowSize then
                    local sk = (hasPandemic and pandemicOverride) and panSizeKey or sizeKey
                    sz = GetGlowSize(btnStyle, sk, glowStyle, defaultSizes)
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
                    th = (glowStyle == "pixel" or glowStyle == "dashes")
                        and ((btnStyle and btnStyle[tk]) or defThickness) or 0
                    spd = usesSpeed and ((btnStyle and btnStyle[sk2])
                        or (defSpeeds and defSpeeds[glowStyle]) or defSpeed) or 0
                    ln = (glowStyle == "pixel" or glowStyle == "dashes")
                        and ((btnStyle and btnStyle[lk]) or defLines) or 0
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
        local c2sig = color2 and ST.FormatColorKey(color2) or false
        if button[cActive]
           and button[cStyle] == glowStyle
           and button[cR] == color[1] and button[cG] == color[2]
           and button[cB] == color[3] and button[cA] == ca
           and (not cSz or button[cSz] == sz)
           and (not cTh or button[cTh] == th)
           and (not cSpd or button[cSpd] == spd)
           and (not cLn or button[cLn] == ln)
           and (not cC2 or button[cC2] == c2sig)
           and (not cPandemic or button[cPandemic] == pandemicOverride)
           and IsGlowAnimationAlive(container) then
            return
        end

        -- Build opts table (state-change path only, so allocation is OK)
        local opts = { size = sz, key = resolvedLcgKey, color2 = color2 }
        if fullParams then
            opts.thickness = th
            opts.speed = spd
            if glowStyle == "pixel" or glowStyle == "dashes" then opts.lines = ln end
        end
        if includeFreqScale and usesSpeed then
            opts.frequency = SpeedToGlowFrequency(spd)
            opts.scale = math_min(math_max(sz, 0.2), 3)
        end
        if optsDefaultAlpha then
            opts.defaultAlpha = optsDefaultAlpha
        end

        local updateInPlace = button[cActive]
            and button[cStyle] == glowStyle
            and IsGlowAnimationAlive(container)

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
        if cC2 then button[cC2] = c2sig end
        if cPandemic then button[cPandemic] = pandemicOverride end

        if updateInPlace and TryUpdateGlowStyleInPlace(container, glowStyle, button, color, opts) then
            return
        end

        HideGlowStyles(container)
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

-- 12.1: the live aura glow is kit-rendered on the aura slot button (see the
-- Kit glow section below); this CC-side setter only serves the config
-- preview. The kit-only styles (overlay/ants/colorShift/dashes) have exact
-- CC-side twins in ShowGlowStyle; the rest translate to the equivalent
-- legacy renderers (dead LCG styles to the pulse border, old pixel to its
-- dashes lookalike) so preview matches the kit.
local function NormalizeAuraGlowPreviewStyle(style)
    if style == "none" or style == "solid" or style == "overlay"
        or style == "ants" or style == "colorShift" or style == "dashes" then
        return style
    end
    if style == "glow" or style == "proc" then
        return "glow"
    end
    if style == "pixel" then
        return "dashes"
    end
    return "pulsingBorder"
end

local SetAuraGlow = MakeGlowSetter({
    containerKey       = "auraGlow",
    hasPandemic        = true,
    normalizeStyle     = NormalizeAuraGlowPreviewStyle,
    noneIsOff          = true,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultAlpha       = 0.9,
    includeFrequencyScale = true,
    optsDefaultAlpha   = 0.9,
    defaultSpeed       = 0.5,
    -- Matches the kit glow's fallbacks (border 2, overhang 30) so the preview
    -- renders the same size the slot kit does when no size is stored.
    defaultSizes       = BAR_AURA_GLOW_SIZES,
    defaultSpeeds      = AURA_GLOW_SPEED_DEFAULTS,
    styleKey           = "auraGlowStyle",       defaultStyle = "pulse",
    colorKey           = "auraGlowColor",       defaultColor = DEFAULT_AURA_GLOW_COLOR,
    color2Key          = "auraGlowColor2",      defaultColor2 = DEFAULT_AURA_GLOW_COLOR2,
    cacheColor2        = "_auraGlowC2",
    sizeKey            = "auraGlowSize",
    thicknessKey       = "auraGlowDashThickness",
    speedKey           = "auraGlowSpeed",
    linesKey           = "auraGlowDashCount",
    defaultLines       = 2,
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

local function ShowButtonTooltip(button, tooltip)
    if not (button and tooltip and button.buttonData) then return false end

    local buttonData = button.buttonData
    if buttonData.type == "spell" then
        tooltip:SetSpellByID(button._displaySpellId or buttonData.id)
        return true
    elseif IsEntryItemLike(buttonData) then
        local itemID = button._resolvedItemId or buttonData.id
        if itemID then
            tooltip:SetItemByID(itemID)
            return true
        end
    end

    return false
end

-- Setup tooltip OnEnter/OnLeave scripts on a button frame.
-- Shared between icon-mode (CreateButtonFrame) and style refreshes.
local function SetupTooltipScripts(button)
    button:SetScript("OnEnter", function(self)
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        ShowButtonTooltip(self, GameTooltip)
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

------------------------------------------------------------------------
-- Kit glow (12.1 aura display)
--
-- The aura glow renders as children of the Blizzard-driven aura slot button:
-- built once at kit-build time, styled at OOC bind time, shown/hidden by
-- Blizzard with the aura itself (zero state reads, zero combat writes).
-- OnUpdate scripts never run on the forbidden subtree, so every animated
-- style is AnimationGroup-driven (P3-validated working in combat). The LCG
-- styles (pixel/lcgButton/lcgAutoCast) are impossible there: they reparent
-- pooled frames INTO the target, which is forbidden (V9b) — never route
-- LCG or ShowGlowStyle at a kit.
--
-- These builders are pure: no stored refs, no CC-button coupling. The SOLE
-- caller is AuraDisplay.lua's bind path (single-writer rule). The config
-- preview does NOT use them: it renders equivalent visuals through the
-- CC-side legacy renderers via NormalizeAuraGlowPreviewStyle above.
------------------------------------------------------------------------

-- Proc-swirl flipbook parameters from ActionButtonSpellAlertTemplate
-- (Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml, ProcLoop):
-- 30 frames in a 6-row x 5-column sheet over 1 second, looping.
local KIT_PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"

-- Map a stored aura glow style to a kit-renderable one. "pixel" (the old
-- default) renders as its dashes lookalike, the LCG styles died with 12.1
-- and render as the pulse border; legacy "glow"/"pulsingBorder" map to
-- their renamed equivalents.
local function NormalizeKitGlowStyle(style)
    if style == "none" or style == "solid" or style == "proc"
        or style == "overlay" or style == "ants"
        or style == "colorShift" or style == "dashes" then
        return style
    end
    if style == "glow" then
        return "proc"
    end
    if style == "pixel" then
        return "dashes"
    end
    return "pulse"
end

local function BuildKitGlowRegions(parent)
    local host = CreateFrame("Frame", nil, parent)
    host:EnableMouse(false)
    host:SetAlpha(0)

    local glowKit = { host = host, edges = {} }
    for i = 1, 4 do
        glowKit.edges[i] = host:CreateTexture(nil, "OVERLAY")
    end

    -- Pulse: alpha bounce on the host (same shape as StartSolidBorderPulse).
    local pulseAG = host:CreateAnimationGroup()
    pulseAG:SetLooping("BOUNCE")
    local pulseAnim = pulseAG:CreateAnimation("Alpha")
    pulseAnim:SetFromAlpha(1.0)
    pulseAnim:SetToAlpha(0.3)
    glowKit.pulseAG = pulseAG
    glowKit.pulseAnim = pulseAnim

    -- Proc: flipbook loop; the AnimationGroup lives on the texture itself so
    -- the FlipBook animation needs no target plumbing.
    local flip = host:CreateTexture(nil, "ARTWORK")
    flip:SetAtlas(KIT_PROC_ATLAS)
    flip:SetAlpha(0)
    local flipAG = flip:CreateAnimationGroup()
    flipAG:SetLooping("REPEAT")
    local flipAnim = flipAG:CreateAnimation("FlipBook")
    flipAnim:SetDuration(1)
    flipAnim:SetFlipBookRows(6)
    flipAnim:SetFlipBookColumns(5)
    flipAnim:SetFlipBookFrames(30)
    glowKit.flip = flip
    glowKit.flipAG = flipAG

    -- Marching ants: second flipbook, same sheet layout as proc.
    local ants = host:CreateTexture(nil, "ARTWORK")
    ants:SetAtlas(KIT_ANTS_ATLAS)
    ants:SetAlpha(0)
    local antsAG = ants:CreateAnimationGroup()
    antsAG:SetLooping("REPEAT")
    local antsAnim = antsAG:CreateAnimation("FlipBook")
    antsAnim:SetDuration(1)
    antsAnim:SetFlipBookRows(6)
    antsAnim:SetFlipBookColumns(5)
    antsAnim:SetFlipBookFrames(30)
    glowKit.ants = ants
    glowKit.antsAG = antsAG

    -- Color shift: per-edge VertexColor bounce (P12-validated in combat).
    -- Colors and duration are set at style time.
    glowKit.csAGs = {}
    glowKit.csAnims = {}
    for i = 1, 4 do
        local ag = glowKit.edges[i]:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        glowKit.csAGs[i] = ag
        glowKit.csAnims[i] = ag:CreateAnimation("VertexColor")
    end

    -- Overlay: static color fill over the button rect.
    local overlay = host:CreateTexture(nil, "ARTWORK")
    overlay:SetAllPoints(host)
    overlay:SetAlpha(0)
    glowKit.overlay = overlay

    -- Dashes: masked line pieces wrapping the button perimeter (Translations
    -- P12-validated, mask clipping P13-validated, both in combat). The kit
    -- is write-once, so the full pool is prebuilt; routes and strip
    -- geometry are set at style time when the button size is known.
    glowKit.dashMasks = CreateDashMasks(host)
    glowKit.dashes = {}
    CreateDashRegions(host, glowKit.dashes, glowKit.dashMasks, MAX_AURA_GLOW_DASHES)

    return glowKit
end

-- Style a kit glow from the effective style. anchorFrame is the CC host
-- button: anchoring kit regions TO an outside frame is the validated
-- direction (kit.bg precedent). Live kits call this at OOC bind time only.
-- Position and size a flipbook texture over the anchor with a percentage
-- overhang, then tint it. 4-arg SetVertexColor overwrites region alpha, so
-- it must come after any SetAlpha and carry the color's own alpha (Phase 2
-- gotcha).
local function StyleKitFlipbook(tex, anchorFrame, pct, r, g, b, a)
    local w, h = anchorFrame:GetSize()
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
    tex:SetSize(w + w * pct * 2, h + h * pct * 2)
    tex:SetVertexColor(r, g, b, a)
end

local function StyleKitGlowRegions(glowKit, styleTable, anchorFrame, enabled)
    local host = glowKit.host
    local kitStyle = enabled
        and NormalizeKitGlowStyle((styleTable and styleTable.auraGlowStyle) or "pulse")
        or "none"

    -- Full reset: stop every animation and blank every sub-visual, then the
    -- active branch lights only its own. The VertexColor anims leave a
    -- residual vertex tint on the edges, so restore white here (before the
    -- SetAlpha, per the Phase 2 gotcha).
    glowKit.pulseAG:Stop()
    glowKit.flipAG:Stop()
    glowKit.antsAG:Stop()
    for i = 1, 4 do
        glowKit.csAGs[i]:Stop()
        glowKit.edges[i]:SetVertexColor(1, 1, 1, 1)
        glowKit.edges[i]:SetAlpha(0)
    end
    glowKit.flip:SetAlpha(0)
    glowKit.ants:SetAlpha(0)
    glowKit.overlay:SetAlpha(0)
    for _, d in ipairs(glowKit.dashes) do
        for _, piece in ipairs(d.pieces) do
            piece.ag:Stop()
            piece.tex:SetAlpha(0)
        end
    end

    if kitStyle == "none" then
        host:SetAlpha(0)
        return
    end

    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    host:SetAlpha(1)

    local color = (styleTable and styleTable.auraGlowColor) or DEFAULT_AURA_GLOW_COLOR
    local r, g, b, a = color[1], color[2], color[3], color[4] or 0.9
    local size = styleTable and styleTable.auraGlowSize
    local speed = styleTable and styleTable.auraGlowSpeed
    -- Speed keys store seconds (0.1..2.0); guard against legacy pixel-scale
    -- values (10..200) with the style's own default.
    if not speed or speed <= 0 or speed > 2 then
        speed = AURA_GLOW_SPEED_DEFAULTS[kitStyle]
    end

    if kitStyle == "proc" then
        -- The closing SetVertexColor already raises the region alpha to the
        -- color's own alpha; a trailing SetAlpha would clobber it.
        StyleKitFlipbook(glowKit.flip, anchorFrame, (size or BAR_AURA_GLOW_SIZES.glow) / 100, r, g, b, a)
        glowKit.flipAG:Play()
        return
    end

    if kitStyle == "ants" then
        StyleKitFlipbook(glowKit.ants, anchorFrame, (size or BAR_AURA_GLOW_SIZES.ants) / 100, r, g, b, a)
        glowKit.antsAG:Play()
        return
    end

    if kitStyle == "overlay" then
        glowKit.overlay:SetColorTexture(r, g, b, a)
        glowKit.overlay:SetAlpha(1)
        return
    end

    if kitStyle == "dashes" then
        local count = (styleTable and styleTable.auraGlowDashCount) or 2
        count = math_min(math_max(count, 1), MAX_AURA_GLOW_DASHES)
        StyleDashPerimeter(glowKit.dashes, glowKit.dashMasks, anchorFrame,
            size or BAR_AURA_GLOW_SIZES.dashes,
            (styleTable and styleTable.auraGlowDashThickness) or DEFAULT_AURA_GLOW_DASH_THICKNESS,
            speed or AURA_GLOW_SPEED_DEFAULTS.dashes,
            count, r, g, b, a)
        return
    end

    -- solid / pulse / colorShift: 4-edge border around the host button.
    ApplyEdgePositions(glowKit.edges, anchorFrame, size or BAR_AURA_GLOW_SIZES.solid)
    for _, tex in ipairs(glowKit.edges) do
        if kitStyle == "colorShift" then
            -- Base texture stays white so the VertexColor animation owns the
            -- full color range.
            tex:SetColorTexture(1, 1, 1, 1)
        else
            tex:SetColorTexture(r, g, b, a)
        end
        tex:SetAlpha(1)
        tex:Show()
    end
    if kitStyle == "pulse" then
        glowKit.pulseAnim:SetDuration(speed or AURA_GLOW_SPEED_DEFAULTS.pulse)
        glowKit.pulseAG:Play()
    elseif kitStyle == "colorShift" then
        local color2 = (styleTable and styleTable.auraGlowColor2) or DEFAULT_AURA_GLOW_COLOR2
        local startColor = CreateColor(r, g, b, a)
        local endColor = CreateColor(color2[1], color2[2], color2[3], color2[4] or 0.9)
        for i = 1, 4 do
            local anim = glowKit.csAnims[i]
            anim:SetStartColor(startColor)
            anim:SetEndColor(endColor)
            anim:SetDuration(speed or AURA_GLOW_SPEED_DEFAULTS.colorShift)
            glowKit.csAGs[i]:Play()
        end
    end
end

local SetBarAuraEffect = MakeGlowSetter({
    containerKey       = "barAuraEffect",
    hasPandemic        = true,
    normalizeStyle     = NormalizeBarAuraEffectStyle,
    noneIsOff          = true,
    fullParams         = true,
    useGetGlowSize     = true,
    defaultSizes        = BAR_AURA_GLOW_SIZES,
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
ST._ShowButtonTooltip = ShowButtonTooltip
ST._SetupTooltipScripts = SetupTooltipScripts
ST.IsBarAuraIndicatorEnabled = IsBarAuraIndicatorEnabled
ST._SetBarAuraEffect = SetBarAuraEffect
ST._BuildKitGlowRegions = BuildKitGlowRegions
ST._StyleKitGlowRegions = StyleKitGlowRegions
ST._StyleDashPerimeter = StyleDashPerimeter
ST._CreateDashMasks = CreateDashMasks
ST._CreateDashRegions = CreateDashRegions
ST._SetReadyGlow = SetReadyGlow
ST._SetKeyPressHighlight = SetKeyPressHighlight
