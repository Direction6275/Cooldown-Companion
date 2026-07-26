--[[
    CooldownCompanion - ResourceBarPreview
    Ready-state rendering for the config preview, plus the preview-mode
    public controls.

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
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local RB = ST._RB
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR

local GetResourceAuraConfiguredMaxStacks = RB.GetResourceAuraConfiguredMaxStacks
local HideResourceAuraStackSegments = RB.HideResourceAuraStackSegments
local ApplyResourceAuraStackSegments = RB.ApplyResourceAuraStackSegments
local ClearResourceAuraVisuals = RB.ClearResourceAuraVisuals
local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry
local GetResourceColors = RB.GetResourceColors
local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
local SetSegmentedText = RB.SetSegmentedText
local SetMaxStacksIndicatorActive = RB.SetMaxStacksIndicatorActive
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue

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

function RB.CreateResourceBarPreviewModule(deps)
    local resourceBarFrames = deps.resourceBarFrames
    local HealthBar = deps.HealthBar
    local HEALTH_EFFECTS = deps.HEALTH_EFFECTS
    local GetPreviewActive = deps.GetPreviewActive
    local SetPreviewActive = deps.SetPreviewActive
    local GetMWMaxStacks = deps.GetMWMaxStacks
    local GetResourceBarSettings = deps.GetResourceBarSettings or RB.GetResourceBarSettings
    local ApplySegmentedPreviewColors = deps.ApplySegmentedPreviewColors
    local ClearCustomAuraBarIndicatorState = deps.ClearCustomAuraBarIndicatorState

    ------------------------------------------------------------------------
    -- Ready-state rendering
    ------------------------------------------------------------------------

    local function ApplyPreviewDataToBar(barInfo, settings)
        if not (barInfo and barInfo.frame and barInfo.frame:IsShown()) then
            return
        end

        local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)

        -- Resource aura overlay lane (aura-pass Phase 2 rebuilds this; the
        -- shape survives as its base). Full, like every other ready-state
        -- fill.
        local function ApplyResourceAuraLaneReadyState(barInfo)
            local powerType = barInfo.powerType
            if not powerType then return end

            local resource = settings and settings.resources and settings.resources[powerType]
            if not IsResourceAuraOverlayEnabled(resource) then
                HideResourceAuraStackSegments(barInfo.frame)
                return
            end
            local auraEntry = GetActiveResourceAuraEntry(resource)
            if not auraEntry then
                HideResourceAuraStackSegments(barInfo.frame)
                return
            end
            local auraSpellID = tonumber(auraEntry.auraColorSpellID)
            local auraMaxStacks = GetResourceAuraConfiguredMaxStacks(powerType, settings)
            if not auraSpellID or auraSpellID <= 0 or not auraMaxStacks then
                HideResourceAuraStackSegments(barInfo.frame)
                return
            end

            local auraColor = auraEntry.auraActiveColor
            if type(auraColor) ~= "table" or not auraColor[1] or not auraColor[2] or not auraColor[3] then
                auraColor = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
            end

            ApplyResourceAuraStackSegments(barInfo.frame, settings, auraMaxStacks, auraMaxStacks, auraColor)
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

        ClearResourceAuraVisuals(barInfo.frame)
        if barInfo.barType == "continuous" then
            local maxPower = UnitPowerMax("player", barInfo.powerType or 0)
            SetStatusBarSmoothRange(barInfo.frame, 0, maxPower)
            SetStatusBarSmoothValue(barInfo.frame, maxPower)
            SetFullBarText(barInfo.frame, maxPower)
        elseif barInfo.barType == "health_continuous" then
            local maxHealth = UnitHealthMax("player")
            SetStatusBarSmoothRange(barInfo.frame, 0, maxHealth)
            SetStatusBarSmoothValue(barInfo.frame, maxHealth)
            local config = HealthBar.GetConfig(settings)
            HealthBar.ApplyFillColor(barInfo.frame, config, 1)
            HealthBar.ApplyBackgroundColor(barInfo.frame, config, 1)
            HealthBar.UpdateEffectBars(barInfo.frame, config, maxHealth, HEALTH_EFFECTS.preview)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                local abbreviated = AbbreviateNumbers(maxHealth)
                if textFormat == "current" then
                    barInfo.frame.text:SetFormattedText("%s", abbreviated)
                elseif textFormat == "current_max" then
                    barInfo.frame.text:SetFormattedText("%s / %s", abbreviated, abbreviated)
                elseif textFormat == "current_percent" then
                    barInfo.frame.text:SetFormattedText("%s | %d%%", abbreviated, 100)
                elseif textFormat == "current_percent_no_sign" then
                    barInfo.frame.text:SetFormattedText("%s | %d", abbreviated, 100)
                elseif textFormat == "percent_no_sign" then
                    barInfo.frame.text:SetFormattedText("%d", 100)
                else
                    barInfo.frame.text:SetFormattedText("%d%%", 100)
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
            ApplyResourceAuraLaneReadyState(barInfo)
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
            for i = 1, half do
                SetStatusBarSegmentedValue(barInfo.frame.segments[i], maxStacks, segmentedSmoothing)
                SetStatusBarSegmentedValue(barInfo.frame.overlaySegments[i], maxStacks, segmentedSmoothing)
                -- At full every overlay half is reached.
                barInfo.frame.overlaySegments[i]:SetAlpha(maxStacks > (half + i - 1) and 1 or 0)
            end
            ApplyResourceAuraLaneReadyState(barInfo)
            SetSegmentedText(barInfo.frame, maxStacks, maxStacks)
        elseif barInfo.barType == "custom_cooldown" then
            -- Spell custom bar, ready: full fill in the bar's own color
            -- (StyleCustomAuraBar already applied it), no cooldown or aura
            -- duration text. A stacks-display spell bar reads the same at
            -- rest — its aura shape belongs to the kit, which renders only
            -- while the aura runs.
            local cabConfig = barInfo.cabConfig
            SetStatusBarSmoothRange(barInfo.frame, 0, 1)
            SetStatusBarImmediateValue(barInfo.frame, 1)
            if barInfo.frame.thresholdOverlay then
                SetStatusBarImmediateValue(barInfo.frame.thresholdOverlay, 0)
                barInfo.frame.thresholdOverlay:Hide()
            end
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
            if barInfo._maxStacksIndicator then
                SetStatusBarImmediateValue(barInfo._maxStacksIndicator, 0)
                if SetMaxStacksIndicatorActive then
                    SetMaxStacksIndicatorActive(barInfo, false)
                end
            end
        elseif barInfo.barType == "custom_continuous" then
            -- Aura custom bar, aura ABSENT: an empty fill. Stacks-mode bars
            -- get their capacity blocks from the aura host's absent-state
            -- pass (the canvas calls it alongside this); the empty fill is
            -- what shows beneath either way.
            local cabConfig = barInfo.cabConfig
            ClearCustomAuraBarIndicatorState(barInfo, false)
            SetStatusBarSmoothRange(barInfo.frame, 0, 1)
            SetStatusBarImmediateValue(barInfo.frame, 0)
            -- Max-stack threshold and its effects were dropped by owner
            -- ruling (the aura pass); the runtime forces them dark, so the
            -- preview must too or it advertises unreachable visuals from
            -- dormant keys.
            if barInfo.frame.thresholdOverlay then
                SetStatusBarImmediateValue(barInfo.frame.thresholdOverlay, 0)
                barInfo.frame.thresholdOverlay:Hide()
            end
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                barInfo.frame.text:SetText("")
            end
            if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                barInfo.frame.stackText:SetText("")
            end
            -- Max-stack indicator dropped with the threshold (owner ruling).
            if barInfo._maxStacksIndicator and SetMaxStacksIndicatorActive then
                SetMaxStacksIndicatorActive(barInfo, false)
            end
        end
    end

    RB.ApplyPreviewBarState = ApplyPreviewDataToBar
    RB.GetMWMaxStacks = function()
        return GetMWMaxStacks()
    end

    local function ApplyPreviewData()
        local settings = GetResourceBarSettings()

        for _, barInfo in ipairs(resourceBarFrames) do
            if barInfo.frame and barInfo.frame:IsShown() then
                ApplyPreviewDataToBar(barInfo, settings)
            end
        end
    end

    function CooldownCompanion:StartResourceBarPreview()
        SetPreviewActive(true)
        self:ApplyResourceBars()  -- ApplyPreviewData() called at end when isPreviewActive
    end

    function CooldownCompanion:StopResourceBarPreview()
        if not GetPreviewActive() then return end
        SetPreviewActive(false)
        wipe(HEALTH_EFFECTS.preview)
        HEALTH_EFFECTS.forcedPreview = nil
        if self.ApplyResourceBars then
            self:ApplyResourceBars()
        end
    end

    function CooldownCompanion:IsResourceBarPreviewActive()
        return GetPreviewActive()
    end


    return {
        ApplyPreviewData = ApplyPreviewData,
        ApplyPreviewDataToBar = ApplyPreviewDataToBar,
    }
end
