-- MissingAura.lua
-- The Missing Aura Glow: a CC-owned glow parked at the aura display band's
-- own frame level, so the Blizzard-driven slot button (band + 1) occludes it
-- exactly while the aura runs and reveals it when the aura ends (12.1
-- two-layer compositing). No aura state is ever read; occlusion is the
-- entire mechanism. The tint half of the missing-state presentation lives in
-- the ordinary tint pipeline (ButtonFrame/Tracking.lua, "aura-missing").
--
-- The glow vocabulary is WITHIN-FOOTPRINT styles only (border/overlay): an
-- overhanging style (proc flipbook, ants, autocast) would leak around the
-- active aura display's edges, and no aura state exists to turn it off.
--
-- Icon hosts only: bar hosts have no aura display band under CC's control at
-- a knowable rect (the kit owns the bar's active visual), so the stored keys
-- are inert there — same rule as auraKeepSpellCooldownSwipe on non-icon
-- hosts. Aura Panels materialize no CC buttons at all, so the section is
-- panel-denied config-side (Core/Defaults.lua).

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- "pulse" is the aura-menu spelling; the CC renderer's branch name is
-- pulsingBorder. Anything outside this map renders nothing.
local MISSING_GLOW_RENDER_STYLE = {
    solid = "solid",
    pulse = "pulsingBorder",
    colorShift = "colorShift",
    dashes = "dashes",
    overlay = "overlay",
}

local function NormalizeMissingGlowStyle(style)
    return MISSING_GLOW_RENDER_STYLE[style] or "none"
end

-- Show/refresh the glow latch. renderStyle is a ShowGlowStyle branch name or
-- "none". Latched on the host so animated styles are not restarted per tick;
-- the style-time applier resets the latch so config edits re-render.
local function SetMissingAuraGlow(host, renderStyle, style)
    if host._ccGlowRenderStyle == renderStyle then return end
    host._ccGlowRenderStyle = renderStyle
    local container = host.glow
    if renderStyle == "none" then
        if container then
            ST._HideGlowStyles(container)
        end
        return
    end
    if not container then
        container = ST._CreateGlowContainer(host)
        -- Pin the sub-frames to the host's own level: a child frame above it
        -- would land inside the aura display band and draw over the active
        -- aura.
        container.solidFrame:SetFrameLevel(host:GetFrameLevel())
        container.procFrame:SetFrameLevel(host:GetFrameLevel())
        host.glow = container
    end
    ST._HideGlowStyles(container)
    local color = style.missingAuraGlowColor or {1, 0.35, 0.35, 0.9}
    ST._ShowGlowStyle(container, renderStyle, host, color, {
        size = style.missingAuraGlowSize,
        thickness = style.missingAuraGlowThickness,
        speed = style.missingAuraGlowSpeed,
        lines = style.missingAuraGlowLines,
        color2 = style.missingAuraGlowColor2,
    })
end

local function IsMissingGlowHost(button, buttonData, style)
    return button ~= nil
        and buttonData ~= nil
        and style ~= nil
        and not button._isBar
        and not button._isText
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and NormalizeMissingGlowStyle(style.missingAuraGlowStyle) ~= "none"
        -- Keep-swipe entries opt out of the icon takeover, so nothing ever
        -- occludes the glow while the aura runs — it would misreport
        -- "missing". Same exclusion the missing tint carries (Tracking.lua).
        and not CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
end

-- Style-time applier, called at the end of UpdateButtonStyle (icon hosts).
-- Builds the host frame on first need, re-levels it under the aura display,
-- and resets the glow latch so the next tick re-renders from the new style.
local function ApplyMissingAuraGlowStyle(button, buttonData, style)
    local host = button.missingAuraGlowHost
    if not IsMissingGlowHost(button, buttonData, style) then
        if host then
            SetMissingAuraGlow(host, "none")
            host:Hide()
        end
        return
    end

    if not host then
        host = CreateFrame("Frame", nil, button)
        button.missingAuraGlowHost = host
    end

    -- The host wears the ICON rect, not the full button: the aura display is
    -- anchored to button.icon (EnsureAuraLayer), so anything outside that
    -- inset — the CC border ring — is never occluded, and a border-hugging
    -- glow on the full rect leaves its outer sliver visible while the aura
    -- runs. Explicit size rather than icon-anchored points: the dashes
    -- renderer reads the host's size the same tick it is styled, and a
    -- freshly point-anchored frame can still report a stale rect.
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local inset = ST.GetEffectiveBorderLayoutSize(button, borderSize, ST.GetBorderRenderMode(style))
    local width, height = button:GetSize()
    host:ClearAllPoints()
    host:SetPoint("CENTER", button, "CENTER", 0, 0)
    host:SetSize(math.max((width or 0) - 2 * inset, 1), math.max((height or 0) - 2 * inset, 1))

    -- The aura display band's own level: the slot button rides at band + 1,
    -- so occlusion is structural and follows a reordered strata stack.
    local levels, top = ST._ResolveStrataLevels(button, style.strataOrder)
    host:SetFrameLevel(levels.auraDisplay or top)
    if host.glow then
        host.glow.solidFrame:SetFrameLevel(host:GetFrameLevel())
        host.glow.procFrame:SetFrameLevel(host:GetFrameLevel())
    end

    -- Shell composition: a hidden shell rests invisible and a dimmed shell
    -- rests dim, so the glow follows the same alpha the entry's own regions
    -- wear (unlock exposure lifts it with the rest, via the same decision).
    host:SetAlpha(CooldownCompanion:GetAuraShellAlpha(button, buttonData))
    host:Show()

    -- Reset the latch so the next tick re-renders from the new style values.
    SetMissingAuraGlow(host, "none")

    -- UpdateButtonStyle's click-through sweep ran before this applier and
    -- re-enables motion on children when tooltips are on; this frame is pure
    -- visuals and must never take hover.
    ST.SetFrameClickThroughRecursive(host, true, true)
end

-- Per-tick updater, called from UpdateIconModeGlows. One nil test on buttons
-- without the feature; a latched no-op write on the rest.
local function UpdateMissingAuraGlowRuntime(button, buttonData, style, inCombat)
    local host = button.missingAuraGlowHost
    if not host then return end
    local renderStyle = "none"
    if IsMissingGlowHost(button, buttonData, style)
        and (style.missingAuraGlowCombatOnly ~= true or inCombat) then
        renderStyle = NormalizeMissingGlowStyle(style.missingAuraGlowStyle)
    end
    SetMissingAuraGlow(host, renderStyle, style)
end

-- Host-generic renderer for the config preview mirror: same latch and
-- vocabulary as the live path, on any CC-owned host frame. Unlike live —
-- where UpdateButtonStyle resets the latch on every restyle — the mirror
-- re-runs its effect pass with no style-time reset, so this variant keys a
-- value signature (preview-only cost) and forces a re-render when any glow
-- key changed. style may be nil when hiding.
local function SetMissingAuraGlowOnHost(host, style, shown)
    local renderStyle = "none"
    if shown and style then
        renderStyle = NormalizeMissingGlowStyle(style.missingAuraGlowStyle)
    end
    if renderStyle ~= "none" then
        local c = style.missingAuraGlowColor
        local c2 = style.missingAuraGlowColor2
        -- The host carries an explicit size (the preview caller sets it), so
        -- its dimensions belong in the signature: a resized mirror must
        -- re-render rather than trust a rect-dependent cached render.
        local w, h = host:GetSize()
        local sig = table.concat({renderStyle, w or 0, h or 0,
            c and (c[1] or 1) or 1, c and (c[2] or 1) or 1,
            c and (c[3] or 1) or 1, c and (c[4] or 1) or 1,
            c2 and (c2[1] or 1) or 1, c2 and (c2[2] or 1) or 1,
            c2 and (c2[3] or 1) or 1, c2 and (c2[4] or 1) or 1,
            style.missingAuraGlowSize or 2, style.missingAuraGlowThickness or 3,
            style.missingAuraGlowSpeed or 0.5, style.missingAuraGlowLines or 5}, "|")
        if host._ccGlowPreviewSig ~= sig then
            host._ccGlowPreviewSig = sig
            host._ccGlowRenderStyle = nil
        end
    else
        host._ccGlowPreviewSig = nil
    end
    SetMissingAuraGlow(host, renderStyle, style)
end

-- Exports
ST._ApplyMissingAuraGlowStyle = ApplyMissingAuraGlowStyle
ST._UpdateMissingAuraGlowRuntime = UpdateMissingAuraGlowRuntime
ST._SetMissingAuraGlowOnHost = SetMissingAuraGlowOnHost
