--[[
    CooldownCompanion - ResourceBarPreview
    Rendering for the config preview canvas, plus the unlock-to-position
    assist for an independent stack out in the world.

    THE FIDELITY PRINCIPLE (owner ruling 2026-07-26). The config preview is
    an accurate reflection of what the live display looks like — reflecting
    the CONFIGURATION, not the live moment. Like the panel mirror, it does
    not track whether a spell happens to be on cooldown or what the current
    resource value is this second; transient state belongs to the explicit
    preview states in the command center.

    At rest that means READY state, rendered through the real display code
    with real game data:
      * Resources render FULL against their real maximums, with the real
        text formats (no fabricated 65/100 or 650K/1M).
      * Spell custom bars render ready: full fill, no duration text, and a
        charge readout only when the spell actually has charges.
      * Aura custom bars render their aura-ABSENT look — for a stacks-mode
        bar that is the real capacity blocks (see
        RB.ApplyCustomBarAbsentStackVisuals), not a continuous fill.

    Values pass straight to the C-level widget APIs and SetFormattedText, so
    a secret maximum in combat is carried through rather than read.

    On top of the resting look sit the preview STATES, which the command
    center arms one at a time. Those are the sanctioned fabrications — an
    aura that is not running, a cast that is not being cast — and they render
    on the config canvas only.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local EntryRuntime = ST.EntryRuntime

local math_min = math.min
local math_floor = math.floor
local CreateFrame = CreateFrame

local RB = ST._RB
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
local RESOURCE_OVERLAY_TINT_ALPHA = RB.RESOURCE_OVERLAY_TINT_ALPHA
local RESOURCE_OVERLAY_HOLDER_LEVEL = RB.RESOURCE_OVERLAY_HOLDER_LEVEL
local PREVIEW_FILL = RB.CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL
local PREVIEW_STACKS = RB.CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
local PREVIEW_DURATION = RB.CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION
-- How wounded the player is while a health-effect preview runs. The effect
-- bars are sized as shares of the real maximum, so this leaves them room.
local HEALTH_EFFECT_PREVIEW_FILL = 0.65

local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry
local GetResourceDisplayValue = RB.GetResourceDisplayValue
local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local GetResourceColors = RB.GetResourceColors
local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
local SetSegmentedText = RB.SetSegmentedText
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue

local FormatTime = CooldownCompanion.FormatTime
local UnbindDurationText = CooldownCompanion.UnbindDurationText or function() end
local SetAuraStackCountText = EntryRuntime.SetAuraStackCountText
local NormalizeCustomAuraStackTextFormat = RB.NormalizeCustomAuraStackTextFormat
local IsSpellCustomBarConfig = RB.IsSpellCustomBarConfig
local IsSpellCustomBarAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay

-- Ready state for a charge spell: its real maximum charges, or nil when the
-- spell has none (the old renderer showed a hardcoded "1 / 2" on every spell
-- bar, charges or not). Config-time, out of combat: a plain data read.
local function GetReadyChargeCount(cabConfig)
    local baseSpellID = cabConfig and tonumber(cabConfig.spellID)
    if not baseSpellID then return nil end
    local runtimeSpellID = C_Spell.GetOverrideSpell(baseSpellID)
    if not runtimeSpellID or runtimeSpellID == 0 then
        runtimeSpellID = baseSpellID
    end
    local charges = C_Spell.GetSpellCharges(runtimeSpellID)
    local maxCharges = charges and tonumber(charges.maxCharges)
    if maxCharges and maxCharges > 1 then
        return maxCharges
    end
    return nil
end

-- Stack capacity for everything the canvas draws on one bar: the capacity
-- blocks, the stand-in's lit run, and its stack text. ONE resolver, because
-- the blocks and the text used to come from different ones and could
-- disagree — blocks from a fresh resolve, text from the runtime cache.
--
-- Config time is out of combat, so the fresh resolve is the truth; the
-- cache is the in-combat safety net the live rebind pass owns, and it can
-- be a talent or a spec change behind. It is only the fallback here, for a
-- bar the config shows that no live slot is currently running.
function RB.GetCustomBarStandInStackMax(barInfo, settings)
    local cabConfig = barInfo and barInfo.cabConfig
    local max = RB.ResolveCustomBarStackMax
        and RB.ResolveCustomBarStackMax(cabConfig, settings)
    if not max then
        max = RB.GetCustomBarCachedStackMax(barInfo)
    end
    return tonumber(max) or 1
end

-- How many capacity blocks the stand-in lights, or nil when this bar does
-- not render as blocks. The canvas asks so it can hand the count to the
-- block layout, which is the only thing that can paint them: on a block bar
-- the blocks ARE the bar and a status-bar fill just covers them.
function RB.GetCustomBarStandInLitStacks(barInfo, settings, maxStacks)
    local frame = barInfo and barInfo.frame
    local cabConfig = barInfo and barInfo.cabConfig
    if not (frame and cabConfig and frame._barAuraActivePreview) then
        return nil
    end
    if not RB.WantsCustomBarStackBlocks then return nil end
    local max = RB.WantsCustomBarStackBlocks(barInfo, {
        includeShell = true,
        maxStacks = maxStacks or RB.GetCustomBarStandInStackMax(barInfo, settings),
    })
    if not max then return nil end
    return math_min(PREVIEW_STACKS, max), max
end

-- The canvas regions the resource overlay stand-in draws with, built on
-- demand and reused. They hang off a child frame rather than the bar
-- itself because a segmented resource's segments are child FRAMES: frame
-- level beats draw layer, so a texture on the bar would sit behind them
-- however high its draw layer.
local function EnsureResourceAuraOverlayStandIn(frame)
    local layer = frame._ccResourceAuraPreview
    if not layer then
        local host = CreateFrame("Frame", nil, frame)
        host:EnableMouse(false)
        local tint = host:CreateTexture(nil, "ARTWORK", nil, 0)
        tint:SetAllPoints(host)
        tint:Hide()
        -- A StatusBar, like the kit's lane, so orientation and reverse fill
        -- come from the widget instead of being recomputed here.
        local lane = CreateFrame("StatusBar", nil, host)
        lane:SetMinMaxValues(0, 1)
        lane:Hide()
        layer = { host = host, tint = tint, lane = lane }
        frame._ccResourceAuraPreview = layer
    end
    return layer
end

local function HideResourceAuraOverlayStandIn(layer)
    if not layer then return end
    layer.tint:Hide()
    layer.lane:Hide()
    layer.host:Hide()
end

function RB.CreateResourceBarPreviewModule(deps)
    local HealthBar = deps.HealthBar
    local HEALTH_EFFECTS = deps.HEALTH_EFFECTS
    local GetUnlockAssistActive = deps.GetUnlockAssistActive
    local SetUnlockAssistActive = deps.SetUnlockAssistActive
    local GetMWMaxStacks = deps.GetMWMaxStacks
    local GetResourceBarSettings = deps.GetResourceBarSettings or RB.GetResourceBarSettings
    local ApplySegmentedPreviewColors = deps.ApplySegmentedPreviewColors
    local ClearCustomAuraBarIndicatorState = deps.ClearCustomAuraBarIndicatorState
    local UpdateCustomAuraBarIndicatorVisuals = deps.UpdateCustomAuraBarIndicatorVisuals
    local AnimateCustomAuraBarIndicator = deps.AnimateCustomAuraBarIndicator

    -- Reached through the module body, not the file scope: the aura host
    -- publishes these when ResourceBar.lua builds it, which is after this
    -- file loads but before this module is created.
    local GetResourceOverlayHolderInset = RB.GetResourceOverlayHolderInset
    local GetResourceOverlayTrackingMode = RB.GetResourceOverlayTrackingMode
    local ResolveResourceOverlayStackMax = RB.ResolveResourceOverlayStackMax

    ------------------------------------------------------------------------
    -- The Active Aura stand-in
    --
    -- What a custom bar shows while its command-center preview runs. The
    -- values are invented (no aura is running), which is exactly why this is
    -- a preview STATE and not the resting look: fill, duration, stacks and
    -- the aura effects, rendered onto whichever frame the caller owns.
    --
    -- The config canvas is the only caller — previews never touch the live
    -- display (owner ruling 2026-07-26).
    ------------------------------------------------------------------------

    local function ApplyCustomBarAuraStandIn(barInfo, settings)
        local bar = barInfo.frame
        local cabConfig = barInfo.cabConfig
        if not (bar and cabConfig and bar._barAuraActivePreview) then
            return false
        end

        local isSpellBar = IsSpellCustomBarConfig(cabConfig)
        if isSpellBar and cabConfig.auraTracking ~= true then
            return false
        end

        -- "Stacks" here means the bar fills against a stack count rather than
        -- against a duration: a spell bar set to the aura stack display, or a
        -- pure aura bar in any tracking mode other than "active".
        local stacksMode = isSpellBar
            and IsSpellCustomBarAuraStackDisplay(cabConfig)
            or (not isSpellBar and cabConfig.trackingMode ~= "active")

        local barColor = cabConfig.barColor or {0.5, 0.5, 1, 1}
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)

        local standInMax = RB.GetCustomBarStandInStackMax(barInfo, settings)
        local blockStacks, blockMax = RB.GetCustomBarStandInLitStacks(barInfo, settings, standInMax)
        local maxStacks = 1
        local stacks = 1
        if blockStacks then
            -- Capacity blocks: the lit run is painted onto the blocks
            -- themselves by the absent-state pass (the canvas hands it the
            -- count), because a status-bar fill would draw over them. This is
            -- the CC stand-in for what the kit's atlas fill does on a live
            -- bar, which likewise never uses this status bar.
            maxStacks = blockMax
            stacks = blockStacks
            SetStatusBarSmoothRange(bar, 0, 1)
            SetStatusBarImmediateValue(bar, 0)
        elseif stacksMode then
            maxStacks = standInMax
            stacks = math_min(PREVIEW_STACKS, maxStacks)
            SetStatusBarSmoothRange(bar, 0, maxStacks)
            SetStatusBarImmediateValue(bar, stacks)
        else
            SetStatusBarSmoothRange(bar, 0, 1)
            SetStatusBarImmediateValue(bar, PREVIEW_FILL)
        end

        if bar.text and bar.text:IsShown() then
            UnbindDurationText(bar.text)
            bar.text:SetText(FormatTime(PREVIEW_DURATION, cabConfig))
        elseif bar.text then
            UnbindDurationText(bar.text)
        end

        if bar.stackText and bar.stackText:IsShown() then
            if stacksMode then
                SetAuraStackCountText(
                    bar.stackText,
                    stacks,
                    maxStacks,
                    NormalizeCustomAuraStackTextFormat(cabConfig.stackTextFormat)
                )
            else
                -- A duration-mode aura bar has one application to report, the
                -- same "current" readout the live bar gives it.
                SetAuraStackCountText(bar.stackText, PREVIEW_STACKS, maxStacks, "current")
            end
        end

        -- Glow, pulse and colour shift. Self-gating on tracking mode, and it
        -- reads the preview flag off the frame for the aura-active legs.
        if UpdateCustomAuraBarIndicatorVisuals then
            UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig)
        end
        return true
    end

    -- Per-frame leg of the stand-in: the pulse and colour-shift animations,
    -- which are time-driven rather than state-driven. The canvas ticks this;
    -- the live stack has its own driver.
    function RB.AnimatePreviewBarAura(barInfo)
        local bar = barInfo and barInfo.frame
        if not (bar and bar._barAuraActivePreview and AnimateCustomAuraBarIndicator) then
            return
        end
        AnimateCustomAuraBarIndicator(bar)
    end

    -- The low-health alert is a pulse, so its preview only reads as itself
    -- while something re-runs the effect pass. Same call the resting render
    -- makes; UpdateEffectBars takes the alpha from the clock.
    function RB.IsHealthEffectPreviewAnimated()
        return HEALTH_EFFECTS.preview.lowHealthAlert == true
    end

    -- Resolved once at build time, not per tick: HealthBar.GetConfig runs
    -- through GetResourceDisplayConfig, which deep-copies the whole health
    -- resource table. The canvas ticker is unthrottled, so calling it per
    -- frame meant a fresh table every frame for an animation that only needs
    -- the clock.
    function RB.GetHealthPreviewAnimationConfig(settings)
        return HealthBar.GetConfig(settings or GetResourceBarSettings())
    end

    function RB.AnimatePreviewHealthEffects(barInfo, config)
        local bar = barInfo and barInfo.frame
        if not (bar and bar:IsShown()) then return end
        HealthBar.UpdateEffectBars(bar, config, UnitHealthMax("player"), HEALTH_EFFECTS.preview)
    end

    ------------------------------------------------------------------------
    -- Ready-state rendering
    ------------------------------------------------------------------------

    local function ApplyPreviewDataToBar(barInfo, settings)
        if not (barInfo and barInfo.frame and barInfo.frame:IsShown()) then
            return
        end

        local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)

        -- The resource aura overlay stand-in. The live shapes are
        -- Blizzard-driven regions on an AuraContainer slot, and the canvas
        -- has no aura to bind one to, so it draws CC regions at the kit's
        -- own geometry — the same arrangement the custom-bar stand-in uses
        -- for the atlas fill it likewise cannot run.
        --
        -- At rest there is nothing to draw at all: an overlay's resting look
        -- is aura-ABSENT, which is the plain resource bar. The shape appears
        -- only while the command center's Active Aura preview runs, and it
        -- is the sanctioned fabrication - no aura is up.
        local function ApplyResourceAuraOverlayStandIn(barInfo)
            local frame = barInfo.frame
            local powerType = barInfo.powerType
            local layer = frame._ccResourceAuraPreview

            local resource = powerType
                and settings and settings.resources and settings.resources[powerType]
                or nil
            local auraEntry = resource and IsResourceAuraOverlayEnabled(resource)
                and GetActiveResourceAuraEntry(resource) or nil
            local auraSpellID = auraEntry and tonumber(auraEntry.auraColorSpellID) or nil
            if not (frame._resourceAuraActivePreview and auraSpellID and auraSpellID > 0) then
                HideResourceAuraOverlayStandIn(layer)
                return
            end

            layer = EnsureResourceAuraOverlayStandIn(frame)
            local inset = GetResourceOverlayHolderInset(barInfo)
            layer.host:ClearAllPoints()
            layer.host:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            layer.host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
            layer.host:SetFrameLevel(frame:GetFrameLevel() + RESOURCE_OVERLAY_HOLDER_LEVEL)
            layer.host:Show()

            local auraColor = auraEntry.auraActiveColor
            if type(auraColor) ~= "table" or not auraColor[1] or not auraColor[2] or not auraColor[3] then
                auraColor = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
            end

            local stackMax = GetResourceOverlayTrackingMode(auraEntry, powerType) == "stacks"
                and ResolveResourceOverlayStackMax(auraEntry, powerType)
                or nil
            if not stackMax then
                -- Active mode: the whole-bar wash, at the kit's strength.
                layer.lane:Hide()
                layer.tint:SetColorTexture(auraColor[1], auraColor[2], auraColor[3],
                    auraColor[4] or RESOURCE_OVERLAY_TINT_ALPHA)
                layer.tint:Show()
                return
            end

            -- Stack mode: the lane, at a fabricated stack count rather than
            -- full, so it reads as a lane filling rather than a solid strip.
            layer.tint:Hide()
            local vertical = IsVerticalResourceLayout(settings) == true
            -- Measured off the BAR, which carries an explicit SetSize, minus
            -- the inset the host sits at. The host itself is anchored and has
            -- not been through a layout pass yet this frame, so asking it
            -- would read last frame's geometry.
            local thickness = ((vertical and frame:GetWidth() or frame:GetHeight()) or 0)
                - (inset * 2)
            local size = math_floor(thickness * 0.5 + 0.5)
            if size < 1 then size = 1 end
            if thickness >= 1 and size > thickness then size = thickness end

            layer.lane:ClearAllPoints()
            if vertical then
                layer.lane:SetPoint("TOPLEFT", layer.host, "TOPLEFT", 0, 0)
                layer.lane:SetPoint("BOTTOMLEFT", layer.host, "BOTTOMLEFT", 0, 0)
                layer.lane:SetWidth(size)
            else
                layer.lane:SetPoint("BOTTOMLEFT", layer.host, "BOTTOMLEFT", 0, 0)
                layer.lane:SetPoint("BOTTOMRIGHT", layer.host, "BOTTOMRIGHT", 0, 0)
                layer.lane:SetHeight(size)
            end
            layer.lane:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(
                ST.GetEffectiveBarTextureName(GetResourceDisplayValue(settings, "barTexture", "Solid"))))
            layer.lane:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
            layer.lane:SetReverseFill(vertical and IsVerticalFillReversed(settings) == true or false)
            layer.lane:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], 1)
            SetStatusBarSmoothRange(layer.lane, 0, stackMax)
            SetStatusBarImmediateValue(layer.lane, math_min(PREVIEW_STACKS, stackMax))
            layer.lane:Show()
        end

        -- Text at a full bar: the real formats against the real maximum.
        -- Percent legs are written as 100 rather than read back from the
        -- unit, because the bar being rendered is full by construction.
        local function SetFullBarText(bar, maxValue)
            if not (bar.text and bar.text:IsShown()) then return end
            local textFormat = bar._textFormat
            if textFormat == "current" then
                bar.text:SetFormattedText("%d", maxValue)
            elseif textFormat == "percent" then
                bar.text:SetFormattedText("%d", 100)
            else
                bar.text:SetFormattedText("%d / %d", maxValue, maxValue)
            end
        end

        if barInfo.barType == "continuous" then
            local maxPower = UnitPowerMax("player", barInfo.powerType or 0)
            SetStatusBarSmoothRange(barInfo.frame, 0, maxPower)
            SetStatusBarSmoothValue(barInfo.frame, maxPower)
            SetFullBarText(barInfo.frame, maxPower)
        elseif barInfo.barType == "health_continuous" then
            local maxHealth = UnitHealthMax("player")
            local config = HealthBar.GetConfig(settings)
            -- A health-effect preview needs a wounded player. Absorbs and
            -- incoming heals are drawn FORWARD from the fill, so a full bar
            -- leaves them nowhere to go, and the low-health alert has no
            -- missing health to cover. The partial fill IS the preview
            -- state; at rest the bar is full like every other resource.
            --
            -- Only when the maximum can actually be divided: it may be a
            -- secret value, and arithmetic on one is forbidden (see
            -- agent-reference/secret-values.md). The resting leg below never
            -- computes on it at all — range and value pass straight through.
            local wounded = HealthBar.HasActiveEffectPreview()
                and not (issecretvalue and issecretvalue(maxHealth))
            local health = maxHealth
            local fraction = 1
            if wounded then
                fraction = HEALTH_EFFECT_PREVIEW_FILL
                health = maxHealth * fraction
            end
            SetStatusBarSmoothRange(barInfo.frame, 0, maxHealth)
            SetStatusBarSmoothValue(barInfo.frame, health)
            HealthBar.ApplyFillColor(barInfo.frame, config, fraction)
            HealthBar.ApplyBackgroundColor(barInfo.frame, config, fraction)
            HealthBar.UpdateEffectBars(barInfo.frame, config, maxHealth, HEALTH_EFFECTS.preview)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                local abbreviated = AbbreviateNumbers(health)
                local percent = fraction * 100
                if textFormat == "current" then
                    barInfo.frame.text:SetFormattedText("%s", abbreviated)
                elseif textFormat == "current_max" then
                    barInfo.frame.text:SetFormattedText("%s / %s", abbreviated, AbbreviateNumbers(maxHealth))
                elseif textFormat == "current_percent" then
                    barInfo.frame.text:SetFormattedText("%s | %d%%", abbreviated, percent)
                elseif textFormat == "current_percent_no_sign" then
                    barInfo.frame.text:SetFormattedText("%s | %d", abbreviated, percent)
                elseif textFormat == "percent_no_sign" then
                    barInfo.frame.text:SetFormattedText("%d", percent)
                else
                    barInfo.frame.text:SetFormattedText("%d%%", percent)
                end
            end
        elseif barInfo.barType == "segmented" then
            local n = #barInfo.frame.segments
            for _, seg in ipairs(barInfo.frame.segments) do
                SetStatusBarSegmentedValue(seg, n, segmentedSmoothing)
            end
            -- Resolves the at-max color leg for every filled segment, the
            -- same one the live bar shows at full.
            ApplySegmentedPreviewColors(barInfo.frame, barInfo.powerType, settings, n)
            SetSegmentedText(barInfo.frame, n, n)
        elseif barInfo.barType == "stagger_continuous" then
            -- A full stagger pool: the real threshold logic puts that in the
            -- red band, so that is what a full stagger bar genuinely looks
            -- like. Stagger has no natural "ready" fill; full keeps it
            -- consistent with every other resource.
            local maxHealth = UnitHealthMax("player")
            SetStatusBarSmoothRange(barInfo.frame, 0, maxHealth)
            SetStatusBarSmoothValue(barInfo.frame, maxHealth)
            local _, _, redColor = GetResourceColors(101, settings)
            barInfo.frame:SetStatusBarColor(redColor[1], redColor[2], redColor[3], 1)
            barInfo.frame.brightnessOverlay:Hide()
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                if textFormat == "current" then
                    barInfo.frame.text:SetFormattedText("%d", maxHealth)
                elseif textFormat == "percent" then
                    barInfo.frame.text:SetFormattedText("%d%%", 100)
                else
                    barInfo.frame.text:SetFormattedText("%d / %d", maxHealth, maxHealth)
                end
            end
        elseif barInfo.barType == "mw_segmented" then
            local half = #barInfo.frame.segments
            local maxStacks = GetMWMaxStacks()
            -- A full Maelstrom bar is at its maximum, so every style
            -- previews in the max colour — what the real bar shows there.
            local _, _, mwMaxColor = GetResourceColors(100, settings)
            for i = 1, half do
                SetStatusBarSegmentedValue(barInfo.frame.segments[i], maxStacks, segmentedSmoothing)
                SetStatusBarSegmentedValue(barInfo.frame.overlaySegments[i], maxStacks, segmentedSmoothing)
                -- At full every overlay half is reached.
                barInfo.frame.overlaySegments[i]:SetAlpha(maxStacks > (half + i - 1) and 1 or 0)
                barInfo.frame.segments[i]:SetStatusBarColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3], 1)
                barInfo.frame.overlaySegments[i]:SetStatusBarColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3], 1)
            end
            SetSegmentedText(barInfo.frame, maxStacks, maxStacks)
        elseif barInfo.barType == "mw_segments" then
            -- One segment per stack, all full at rest.
            local maxStacks = GetMWMaxStacks()
            local _, _, mwMaxColor = GetResourceColors(100, settings)
            for _, seg in ipairs(barInfo.frame.segments) do
                SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                seg:SetStatusBarColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3], 1)
            end
            SetSegmentedText(barInfo.frame, maxStacks, maxStacks)
        elseif barInfo.barType == "mw_continuous" then
            local maxStacks = GetMWMaxStacks()
            local _, _, mwMaxColor = GetResourceColors(100, settings)
            SetStatusBarSmoothRange(barInfo.frame, 0, maxStacks)
            SetStatusBarSmoothValue(barInfo.frame, maxStacks)
            barInfo.frame:SetStatusBarColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3], 1)
            if barInfo.frame.brightnessOverlay then
                barInfo.frame.brightnessOverlay:Hide()
            end
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                if textFormat == "current" then
                    barInfo.frame.text:SetFormattedText("%d", maxStacks)
                elseif textFormat == "percent" then
                    barInfo.frame.text:SetFormattedText("%d", 100)
                else
                    barInfo.frame.text:SetFormattedText("%d / %d", maxStacks, maxStacks)
                end
            end
        elseif barInfo.barType == "custom_cooldown" then
            -- Spell custom bar, ready: full fill in the bar's own color
            -- (StyleCustomAuraBar already applied it), no cooldown or aura
            -- duration text. A stacks-display spell bar reads the same at
            -- rest — its aura shape belongs to the kit, which renders only
            -- while the aura runs.
            local cabConfig = barInfo.cabConfig
            if ApplyCustomBarAuraStandIn(barInfo, settings) then
                return
            end
            SetStatusBarSmoothRange(barInfo.frame, 0, 1)
            SetStatusBarImmediateValue(barInfo.frame, 1)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                barInfo.frame.text:SetText("")
            end
            if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                local maxCharges = GetReadyChargeCount(cabConfig)
                if maxCharges then
                    barInfo.frame.stackText:SetFormattedText("%d / %d", maxCharges, maxCharges)
                else
                    barInfo.frame.stackText:SetText("")
                end
            end
            ClearCustomAuraBarIndicatorState(barInfo, true)
        elseif barInfo.barType == "custom_continuous" then
            -- Aura custom bar, aura ABSENT: an empty fill. Stacks-mode bars
            -- get their capacity blocks from the aura host's absent-state
            -- pass (the canvas calls it alongside this); the empty fill is
            -- what shows beneath either way.
            local cabConfig = barInfo.cabConfig
            if ApplyCustomBarAuraStandIn(barInfo, settings) then
                return
            end
            ClearCustomAuraBarIndicatorState(barInfo, false)
            SetStatusBarSmoothRange(barInfo.frame, 0, 1)
            SetStatusBarImmediateValue(barInfo.frame, 0)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                barInfo.frame.text:SetText("")
            end
            if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                barInfo.frame.stackText:SetText("")
            end
        end

        -- Last, and once for every shape: the overlay draws OVER whatever
        -- the branches above rendered, exactly as the kit draws over the
        -- live bar. Custom bars reach here with no power type and are left
        -- alone.
        ApplyResourceAuraOverlayStandIn(barInfo)
    end

    RB.ApplyPreviewBarState = ApplyPreviewDataToBar
    RB.GetMWMaxStacks = function()
        return GetMWMaxStacks()
    end

    ------------------------------------------------------------------------
    -- Unlock-to-position assist
    --
    -- Deliberately NOT a preview. An independent resource stack is dragged
    -- out in the world, so the bars have to be visible to be positioned —
    -- including a Show Only While Aura Active bar, whose CC frame renders
    -- nothing of its own and would otherwise be an invisible drag target.
    -- Nothing here fabricates data: the bars show what they always show.
    ------------------------------------------------------------------------

    function CooldownCompanion:StartResourceBarUnlockAssist()
        if GetUnlockAssistActive() then return end
        SetUnlockAssistActive(true)
        self:ApplyResourceBars()
    end

    function CooldownCompanion:StopResourceBarUnlockAssist()
        if not GetUnlockAssistActive() then return end
        SetUnlockAssistActive(false)
        if self.ApplyResourceBars then
            self:ApplyResourceBars()
        end
    end

    function CooldownCompanion:IsResourceBarUnlockAssistActive()
        return GetUnlockAssistActive()
    end

    return {
        ApplyPreviewDataToBar = ApplyPreviewDataToBar,
    }
end
