--[[
    CooldownCompanion - ResourceBarPreview
    Resource bar preview data and preview-mode public controls.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local math_min = math.min
local math_max = math.max

local RB = ST._RB
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR

local FormatTime = CooldownCompanion.FormatTime
local NormalizeCustomAuraStackTextFormat = RB.NormalizeCustomAuraStackTextFormat
local GetResourceAuraConfiguredMaxStacks = RB.GetResourceAuraConfiguredMaxStacks
local HideResourceAuraStackSegments = RB.HideResourceAuraStackSegments
local ApplyResourceAuraStackSegments = RB.ApplyResourceAuraStackSegments
local ClearResourceAuraVisuals = RB.ClearResourceAuraVisuals
local IsCustomAuraMaxThresholdEnabled = RB.IsCustomAuraMaxThresholdEnabled
local IsCustomAuraMaxBarEffectEnabled = RB.IsCustomAuraMaxBarEffectEnabled
local GetCustomAuraMaxBarEffectColor = RB.GetCustomAuraMaxBarEffectColor
local ApplyCustomAuraMaxBarEffects = RB.ApplyCustomAuraMaxBarEffects
local ClearCustomAuraMaxBarEffects = RB.ClearCustomAuraMaxBarEffects
local SetCustomAuraMaxThresholdRange = RB.SetCustomAuraMaxThresholdRange
local SetMaxStacksIndicatorActive = RB.SetMaxStacksIndicatorActive
local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry
local GetResourceColors = RB.GetResourceColors
local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
local SetSegmentedText = RB.SetSegmentedText
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarSegmentedValue = ST.SetStatusBarSegmentedValue

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
    -- Preview mode
    ------------------------------------------------------------------------

    local function ApplyPreviewDataToBar(barInfo, settings)
        if not (barInfo and barInfo.frame and barInfo.frame:IsShown()) then
            return
        end

        local segmentedSmoothing = GetResourceSegmentedSmoothing(settings)

        local function ApplyResourceAuraLanePreview(barInfo, previewRatio)
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

            local previewStacks = math_max(1, math_floor((auraMaxStacks * previewRatio) + 0.5))
            ApplyResourceAuraStackSegments(barInfo.frame, settings, previewStacks, auraMaxStacks, auraColor)
        end

        ClearResourceAuraVisuals(barInfo.frame)
        if barInfo.barType == "continuous" then
            SetStatusBarSmoothRange(barInfo.frame, 0, 100)
            SetStatusBarSmoothValue(barInfo.frame, 65)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                if textFormat == "current" then
                    barInfo.frame.text:SetText("65")
                elseif textFormat == "percent" then
                    barInfo.frame.text:SetText("65")
                else
                    barInfo.frame.text:SetText("65 / 100")
                end
            end
        elseif barInfo.barType == "health_continuous" then
            SetStatusBarSmoothRange(barInfo.frame, 0, 100)
            SetStatusBarSmoothValue(barInfo.frame, 65)
            local config = HealthBar.GetConfig(settings)
            HealthBar.ApplyFillColor(barInfo.frame, config, 0.65)
            HealthBar.ApplyBackgroundColor(barInfo.frame, config, 0.65)
            HealthBar.UpdateEffectBars(barInfo.frame, config, 100, HEALTH_EFFECTS.preview)
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                if textFormat == "current" then
                    barInfo.frame.text:SetText("650K")
                elseif textFormat == "current_max" then
                    barInfo.frame.text:SetText("650K / 1M")
                elseif textFormat == "current_percent" then
                    barInfo.frame.text:SetText("650K | 65%")
                elseif textFormat == "current_percent_no_sign" then
                    barInfo.frame.text:SetText("650K | 65")
                elseif textFormat == "percent_no_sign" then
                    barInfo.frame.text:SetText("65")
                else
                    barInfo.frame.text:SetText("65%")
                end
            end
        elseif barInfo.barType == "segmented" then
            local n = #barInfo.frame.segments
            local filled = math_floor(n * 0.6)
            local previewValue = filled + 0.5
            for i, seg in ipairs(barInfo.frame.segments) do
                if i <= filled then
                    SetStatusBarSegmentedValue(seg, 1, segmentedSmoothing)
                elseif i == filled + 1 then
                    SetStatusBarSegmentedValue(seg, 0.5, segmentedSmoothing)
                else
                    SetStatusBarSegmentedValue(seg, 0, segmentedSmoothing)
                end
            end
            ApplySegmentedPreviewColors(barInfo.frame, barInfo.powerType, settings, previewValue)
            ApplyResourceAuraLanePreview(barInfo, 0.5)
            SetSegmentedText(barInfo.frame, previewValue, n)
        elseif barInfo.barType == "stagger_continuous" then
            SetStatusBarSmoothRange(barInfo.frame, 0, 100)
            SetStatusBarSmoothValue(barInfo.frame, 45)
            local _, yellowColor = GetResourceColors(101, settings)
            barInfo.frame:SetStatusBarColor(yellowColor[1], yellowColor[2], yellowColor[3], 1)
            barInfo.frame.brightnessOverlay:Hide()
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                local textFormat = barInfo.frame._textFormat
                if textFormat == "current" then
                    barInfo.frame.text:SetText("45")
                elseif textFormat == "percent" then
                    barInfo.frame.text:SetText("45%")
                else
                    barInfo.frame.text:SetText("45 / 100")
                end
            end
        elseif barInfo.barType == "mw_segmented" then
            local half = #barInfo.frame.segments
            local previewStacks = math_min(GetMWMaxStacks(), math_max(1, math_floor((GetMWMaxStacks() * 0.7) + 0.5)))
            if GetMWMaxStacks() > 5 then
                previewStacks = math_min(GetMWMaxStacks(), math_max(previewStacks, 7))
            end
            for i = 1, half do
                SetStatusBarSegmentedValue(barInfo.frame.segments[i], previewStacks, segmentedSmoothing)
                SetStatusBarSegmentedValue(barInfo.frame.overlaySegments[i], previewStacks, segmentedSmoothing)
                if previewStacks > (half + i - 1) then
                    barInfo.frame.overlaySegments[i]:SetAlpha(1)
                else
                    barInfo.frame.overlaySegments[i]:SetAlpha(0)
                end
            end
            ApplyResourceAuraLanePreview(barInfo, 0.5)
            SetSegmentedText(barInfo.frame, previewStacks, GetMWMaxStacks())
        elseif barInfo.barType == "custom_cooldown" then
            local cabConfig = barInfo.cabConfig
            local isSpellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local previewValue
            if isSpellAuraStackDisplay then
                SetStatusBarSmoothRange(barInfo.frame, 0, maxStacks)
                previewValue = math.ceil(maxStacks * 0.65)
                SetStatusBarSmoothValue(barInfo.frame, previewValue)
            else
                SetStatusBarSmoothRange(barInfo.frame, 0, 1)
                previewValue = 0.45
                SetStatusBarSmoothValue(barInfo.frame, previewValue)
            end
            if barInfo.frame.thresholdOverlay then
                SetStatusBarImmediateValue(barInfo.frame.thresholdOverlay, 0)
                barInfo.frame.thresholdOverlay:Hide()
            end
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                if isSpellAuraStackDisplay then
                    barInfo.frame.text:SetText("")
                else
                    barInfo.frame.text:SetText(FormatTime(12.3, cabConfig))
                end
            end
            if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                if isSpellAuraStackDisplay then
                    RB.UpdateSpellCustomBarAuraStackText(barInfo.frame, cabConfig, previewValue, maxStacks, true)
                else
                    barInfo.frame.stackText:SetText("1 / 2")
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
            local cabConfig = barInfo.cabConfig
            local isActive = cabConfig and cabConfig.trackingMode == "active"
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local maxStackBarEffectsEnabled = IsCustomAuraMaxBarEffectEnabled and IsCustomAuraMaxBarEffectEnabled(cabConfig)
            local thresholdVisible = thresholdEnabled or maxStackBarEffectsEnabled
            local thresholdColor = maxStackBarEffectsEnabled and GetCustomAuraMaxBarEffectColor
                and GetCustomAuraMaxBarEffectColor(cabConfig)
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            ClearCustomAuraBarIndicatorState(barInfo, false)
            local previewValue
            if isActive then
                SetStatusBarSmoothRange(barInfo.frame, 0, 1)
                previewValue = indicatorPreview and 1 or 0.65
                SetStatusBarSmoothValue(barInfo.frame, previewValue)
            else
                SetStatusBarSmoothRange(barInfo.frame, 0, maxStacks)
                previewValue = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.65)
                SetStatusBarSmoothValue(barInfo.frame, previewValue)
            end
            if barInfo.frame.thresholdOverlay then
                if thresholdVisible then
                    SetCustomAuraMaxThresholdRange(barInfo.frame.thresholdOverlay, maxStacks)
                    if thresholdColor then
                        barInfo.frame.thresholdOverlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
                    end
                    if maxStackBarEffectsEnabled and ApplyCustomAuraMaxBarEffects then
                        ApplyCustomAuraMaxBarEffects(barInfo.frame.thresholdOverlay, cabConfig, thresholdColor)
                    elseif ClearCustomAuraMaxBarEffects then
                        ClearCustomAuraMaxBarEffects(barInfo.frame.thresholdOverlay, thresholdColor)
                    end
                    SetStatusBarSmoothValue(barInfo.frame.thresholdOverlay, previewValue or 0)
                    barInfo.frame.thresholdOverlay:Show()
                else
                    if ClearCustomAuraMaxBarEffects then
                        ClearCustomAuraMaxBarEffects(barInfo.frame.thresholdOverlay, thresholdColor)
                    end
                    SetStatusBarImmediateValue(barInfo.frame.thresholdOverlay, 0)
                    barInfo.frame.thresholdOverlay:Hide()
                end
            end
            if barInfo.frame.text and barInfo.frame.text:IsShown() then
                barInfo.frame.text:SetText(FormatTime(12.3, cabConfig))
            end
            if barInfo.frame.stackText and barInfo.frame.stackText:IsShown() then
                if isActive then
                    barInfo.frame.stackText:SetFormattedText("%d", 3)
                else
                    local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig and cabConfig.stackTextFormat)
                    if stackTextFormat == "current" then
                        barInfo.frame.stackText:SetFormattedText("%d", previewValue)
                    else
                        barInfo.frame.stackText:SetFormattedText("%d / %d", previewValue, maxStacks)
                    end
                end
            end
            if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                SetStatusBarSmoothValue(barInfo._maxStacksIndicator, maxStacks)
                if SetMaxStacksIndicatorActive then
                    SetMaxStacksIndicatorActive(barInfo, true)
                end
            elseif barInfo._maxStacksIndicator and SetMaxStacksIndicatorActive then
                SetMaxStacksIndicatorActive(barInfo, false)
            end
        elseif barInfo.barType == "custom_segmented" then
            local cabConfig = barInfo.cabConfig
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local maxStackBarEffectsEnabled = IsCustomAuraMaxBarEffectEnabled and IsCustomAuraMaxBarEffectEnabled(cabConfig)
            local thresholdVisible = thresholdEnabled or maxStackBarEffectsEnabled
            local thresholdColor = maxStackBarEffectsEnabled and GetCustomAuraMaxBarEffectColor
                and GetCustomAuraMaxBarEffectColor(cabConfig)
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            local n = #barInfo.frame.segments
            local fill = indicatorPreview and n or math.ceil(n * 0.6)
            for _, seg in ipairs(barInfo.frame.segments) do
                SetStatusBarSegmentedValue(seg, fill, segmentedSmoothing)
            end
            if barInfo.frame.thresholdSegments then
                for _, seg in ipairs(barInfo.frame.thresholdSegments) do
                    if thresholdVisible then
                        SetCustomAuraMaxThresholdRange(seg, maxStacks)
                        if thresholdColor then
                            seg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
                        end
                        if maxStackBarEffectsEnabled and ApplyCustomAuraMaxBarEffects then
                            ApplyCustomAuraMaxBarEffects(seg, cabConfig, thresholdColor)
                        elseif ClearCustomAuraMaxBarEffects then
                            ClearCustomAuraMaxBarEffects(seg, thresholdColor)
                        end
                        SetStatusBarSegmentedValue(seg, fill, segmentedSmoothing)
                        seg:Show()
                    else
                        if ClearCustomAuraMaxBarEffects then
                            ClearCustomAuraMaxBarEffects(seg, thresholdColor)
                        end
                        SetStatusBarImmediateValue(seg, 0)
                        seg:Hide()
                    end
                end
            end
            if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                SetStatusBarSegmentedValue(barInfo._maxStacksIndicator, maxStacks, segmentedSmoothing)
                if SetMaxStacksIndicatorActive then
                    SetMaxStacksIndicatorActive(barInfo, true)
                end
            elseif barInfo._maxStacksIndicator and SetMaxStacksIndicatorActive then
                SetMaxStacksIndicatorActive(barInfo, false)
            end
        elseif barInfo.barType == "custom_overlay" then
            local cabConfig = barInfo.cabConfig
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            local previewStacks = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.7)
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local maxStackBarEffectsEnabled = IsCustomAuraMaxBarEffectEnabled and IsCustomAuraMaxBarEffectEnabled(cabConfig)
            local thresholdVisible = thresholdEnabled or maxStackBarEffectsEnabled
            local thresholdColor = maxStackBarEffectsEnabled and GetCustomAuraMaxBarEffectColor
                and GetCustomAuraMaxBarEffectColor(cabConfig)
            local half = barInfo.halfSegments or 1
            for i = 1, half do
                SetStatusBarSegmentedValue(barInfo.frame.segments[i], previewStacks, segmentedSmoothing)
                SetStatusBarSegmentedValue(barInfo.frame.overlaySegments[i], previewStacks, segmentedSmoothing)
                if barInfo.frame.thresholdSegments and barInfo.frame.thresholdSegments[i] then
                    local seg = barInfo.frame.thresholdSegments[i]
                    if thresholdVisible then
                        SetCustomAuraMaxThresholdRange(seg, maxStacks)
                        if thresholdColor then
                            seg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
                        end
                        if maxStackBarEffectsEnabled and ApplyCustomAuraMaxBarEffects then
                            ApplyCustomAuraMaxBarEffects(seg, cabConfig, thresholdColor)
                        elseif ClearCustomAuraMaxBarEffects then
                            ClearCustomAuraMaxBarEffects(seg, thresholdColor)
                        end
                        SetStatusBarSegmentedValue(seg, previewStacks, segmentedSmoothing)
                        seg:Show()
                    else
                        if ClearCustomAuraMaxBarEffects then
                            ClearCustomAuraMaxBarEffects(seg, thresholdColor)
                        end
                        SetStatusBarImmediateValue(seg, 0)
                        seg:Hide()
                    end
                end
            end
            if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                SetStatusBarSegmentedValue(barInfo._maxStacksIndicator, maxStacks, segmentedSmoothing)
                if SetMaxStacksIndicatorActive then
                    SetMaxStacksIndicatorActive(barInfo, true)
                end
            elseif barInfo._maxStacksIndicator and SetMaxStacksIndicatorActive then
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
