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

    Values pass straight to the C-level widget APIs and SetFormattedText, so
    a secret maximum in combat is carried through rather than read.

    On top of the resting look sit the preview STATES, which the command
    center arms one at a time. Those are the sanctioned fabrications — an
    aura that is not running, a cooldown that is not ticking, a cast that is
    not being cast — and they render on the config canvas only.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local EntryRuntime = ST.EntryRuntime

local math_min = math.min
local math_floor = math.floor
local CreateFrame = CreateFrame

local RB = ST._RB
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
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


local function EnsureResourceAuraOverlayStandIn(frame)
    local layer = frame._ccResourceAuraPreview
    if not layer then
        local host = CreateFrame("Frame", nil, frame)
        host:EnableMouse(false)
        -- The fill-tint stand-in: a texture anchored onto the canvas bar's
        -- own fill texture, clipped to the host rect exactly like the live
        -- kit's clip window. The bar's own fill is never repainted, so the
        -- shape-specific painters (Stagger, MW and aura-stack max colors)
        -- stay authoritative when the preview ends.
        --
        -- Level discipline (the live kit's rule): nesting adds default
        -- frame levels, which would lift the tint above the lane and the
        -- glow — frame level beats creation order. Both tint frames are
        -- pinned to the HOST's level; the pins are relative offsets, so
        -- they survive the host's per-apply level restamp, and the lane
        -- and glow (host children at +1) keep outranking the tint.
        local tintClip = CreateFrame("Frame", nil, host)
        tintClip:SetAllPoints(host)
        tintClip:EnableMouse(false)
        tintClip:SetClipsChildren(true)
        tintClip:Hide()
        tintClip:SetFrameLevel(host:GetFrameLevel())
        local tintHost = CreateFrame("Frame", nil, tintClip)
        tintHost:SetAllPoints(tintClip)
        tintHost:EnableMouse(false)
        tintHost:SetFrameLevel(host:GetFrameLevel())
        local tint = tintHost:CreateTexture(nil, "ARTWORK")
        -- A StatusBar, like the kit's lane, so orientation and reverse fill
        -- come from the widget instead of being recomputed here.
        local lane = CreateFrame("StatusBar", nil, host)
        lane:SetMinMaxValues(0, 1)
        lane:Hide()
        layer = { host = host, lane = lane, tintClip = tintClip, tint = tint }
        frame._ccResourceAuraPreview = layer
    end
    return layer
end

local function HideResourceAuraOverlayStandIn(layer)
    if not layer then return end
    if layer.glow then
        ST._StyleKitBarGlowRegions(layer.glow, nil, layer.host, false)
    end
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

    -- Reached through the module body, not the file scope: the aura host
    -- publishes these when ResourceBar.lua builds it, which is after this
    -- file loads but before this module is created.
    local GetResourceOverlayHolderInset = RB.GetResourceOverlayHolderInset
    local GetResourceOverlayTrackingMode = RB.GetResourceOverlayTrackingMode
    local GetResourceOverlayBorderStyle = RB.GetResourceOverlayBorderStyle
    local IsResourceOverlayBorderEnabled = RB.IsResourceOverlayBorderEnabled
    local GetResourceOverlayLaneColor = RB.GetResourceOverlayLaneColor
    local ResolveResourceOverlayStackMax = RB.ResolveResourceOverlayStackMax
    local IsResourceOverlayFillEnabled = RB.IsResourceOverlayFillEnabled
    local GetResourceOverlayFillColor = RB.GetResourceOverlayFillColor
    local ResourceOverlayFillSupportsBarType = RB.ResourceOverlayFillSupportsBarType

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

            -- The aura border — its own toggle, independent of the lane
            -- (owner ruling 2026-08-02), wrapping the whole bar rect on
            -- every shape (segment clusters included, as if the bar were
            -- continuous). Rendered through the same pure builder the kit
            -- runs on a live slot, in the bar vocabulary the resolvers
            -- read; the enable flag styles the regions off when the border
            -- is switched off, mirroring the runtime adapter.
            local borderStyle = {
                barAuraIndicatorEnabled = IsResourceOverlayBorderEnabled(auraEntry),
                barAuraEffect = GetResourceOverlayBorderStyle(auraEntry),
                barAuraEffectColor = auraColor,
                barAuraEffectSize = tonumber(auraEntry.auraBorderSize),
                barAuraEffectThickness = tonumber(auraEntry.auraBorderThickness),
                barAuraEffectSpeed = tonumber(auraEntry.auraBorderSpeed),
                barAuraEffectLines = tonumber(auraEntry.auraBorderLines),
            }
            if not layer.glow then
                layer.glow = ST._BuildKitGlowRegions(layer.host)
            end
            -- Effects follow the real border. The inset host remains the fill
            -- mount; the bar itself has explicit, current dimensions.
            ST._StyleKitBarGlowRegions(layer.glow, borderStyle, frame, true)

            -- Fill recolor stand-in (continuous shapes only, matching the
            -- runtime gate): the tint overlay anchors onto the canvas
            -- bar's own fill texture, mirroring the live composition —
            -- same blizzard_class-to-Blizzard texture fallback, and the
            -- bar's own fill is never repainted.
            if layer.tint and IsResourceOverlayFillEnabled(auraEntry)
                and ResourceOverlayFillSupportsBarType(barInfo.barType)
                and frame.GetStatusBarTexture then
                local canvasFillTex = frame:GetStatusBarTexture()
                local texName = ST.GetEffectiveBarTextureName(
                    GetResourceDisplayValue(settings, "barTexture", "Solid"))
                layer.tint:SetTexture(CooldownCompanion:FetchStatusBar(
                    texName == "blizzard_class" and "Blizzard" or texName))
                layer.tint:SetTexCoord(0, 1, 0, 1)
                local fillColor = GetResourceOverlayFillColor(auraEntry)
                layer.tint:SetVertexColor(fillColor[1], fillColor[2], fillColor[3])
                layer.tint:ClearAllPoints()
                layer.tint:SetPoint("TOPLEFT", canvasFillTex, "TOPLEFT", 0, 0)
                layer.tint:SetPoint("BOTTOMRIGHT", canvasFillTex, "BOTTOMRIGHT", 0, 0)
                layer.tintClip:Show()
            elseif layer.tintClip then
                layer.tintClip:Hide()
            end

            local stackMax = GetResourceOverlayTrackingMode(auraEntry, powerType) == "stacks"
                and ResolveResourceOverlayStackMax(auraEntry, powerType)
                or nil
            if not stackMax then
                layer.lane:Hide()
                return
            end

            -- Stack mode: the lane, at a fabricated stack count rather than
            -- full, so it reads as a lane filling rather than a solid strip.
            local vertical = IsVerticalResourceLayout(settings) == true
            local width, height = RB.GetResourceBarSize(frame)
            local thickness = (vertical and width or height) - (inset * 2)
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
            -- Own colour per system: the lane resolves its key with the
            -- border-colour fallback, exactly as the runtime adapter does.
            local laneColor = GetResourceOverlayLaneColor(auraEntry)
            layer.lane:SetStatusBarColor(laneColor[1], laneColor[2], laneColor[3], 1)
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
            -- The canvas bar is at max by construction, so the max-stack
            -- border previews lit (and clears when the toggle goes off).
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, barInfo.powerType)
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
            -- The canvas bar is at max by construction, so the max-stack
            -- border previews lit (and clears when the toggle goes off).
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, 100)
        elseif barInfo.barType == "mw_segments" then
            -- One segment per stack, all full at rest.
            local maxStacks = GetMWMaxStacks()
            local _, _, mwMaxColor = GetResourceColors(100, settings)
            for _, seg in ipairs(barInfo.frame.segments) do
                SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                seg:SetStatusBarColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3], 1)
            end
            SetSegmentedText(barInfo.frame, maxStacks, maxStacks)
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, 100)
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
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, 100)
        elseif barInfo.barType == "stackaura_segments" then
            -- Aura-stack family, one segment per stack: full at rest, in the
            -- at-max colour — what the real bar shows at its cap, and what
            -- lights the max-stack border here too.
            local maxStacks = RB.GetAuraStackResourceMax(barInfo.powerType)
            local _, stackMaxColor = GetResourceColors(barInfo.powerType, settings)
            for _, seg in ipairs(barInfo.frame.segments) do
                SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                seg:SetStatusBarColor(stackMaxColor[1], stackMaxColor[2], stackMaxColor[3], 1)
            end
            SetSegmentedText(barInfo.frame, maxStacks, maxStacks)
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, barInfo.powerType)
        elseif barInfo.barType == "stackaura_continuous" then
            local maxStacks = RB.GetAuraStackResourceMax(barInfo.powerType)
            local _, stackMaxColor = GetResourceColors(barInfo.powerType, settings)
            SetStatusBarSmoothRange(barInfo.frame, 0, maxStacks)
            SetStatusBarSmoothValue(barInfo.frame, maxStacks)
            barInfo.frame:SetStatusBarColor(stackMaxColor[1], stackMaxColor[2], stackMaxColor[3], 1)
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
            RB.UpdateMaxStackBorder(barInfo.frame, settings, true, barInfo.powerType)
        end

        -- Last, and once for every shape: the overlay draws OVER whatever
        -- the branches above rendered, exactly as the kit draws over the
        -- live resource bar.
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
