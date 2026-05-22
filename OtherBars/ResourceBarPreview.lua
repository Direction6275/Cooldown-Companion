--[[
    CooldownCompanion - ResourceBarPreview
    Resource bar preview data and preview-mode public controls.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

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
local SetCustomAuraMaxThresholdRange = RB.SetCustomAuraMaxThresholdRange
local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry
local GetResourceColors = RB.GetResourceColors
local SetSegmentedText = RB.SetSegmentedText

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
            barInfo.frame:SetMinMaxValues(0, 100)
            barInfo.frame:SetValue(65)
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
            barInfo.frame:SetMinMaxValues(0, 100)
            barInfo.frame:SetValue(65)
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
                    seg:SetValue(1)
                elseif i == filled + 1 then
                    seg:SetValue(0.5)
                else
                    seg:SetValue(0)
                end
            end
            ApplySegmentedPreviewColors(barInfo.frame, barInfo.powerType, settings, previewValue)
            ApplyResourceAuraLanePreview(barInfo, 0.5)
            SetSegmentedText(barInfo.frame, previewValue, n)
        elseif barInfo.barType == "stagger_continuous" then
            barInfo.frame:SetMinMaxValues(0, 100)
            barInfo.frame:SetValue(45)
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
                barInfo.frame.segments[i]:SetValue(previewStacks)
                barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
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
                barInfo.frame:SetMinMaxValues(0, maxStacks)
                previewValue = math.ceil(maxStacks * 0.65)
                barInfo.frame:SetValue(previewValue)
            else
                barInfo.frame:SetMinMaxValues(0, 1)
                previewValue = 0.45
                barInfo.frame:SetValue(previewValue)
            end
            if barInfo.frame.thresholdOverlay then
                barInfo.frame.thresholdOverlay:SetValue(0)
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
                barInfo._maxStacksIndicator:SetValue(0)
            end
        elseif barInfo.barType == "custom_continuous" then
            local cabConfig = barInfo.cabConfig
            local isActive = cabConfig and cabConfig.trackingMode == "active"
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            ClearCustomAuraBarIndicatorState(barInfo, false)
            local previewValue
            if isActive then
                barInfo.frame:SetMinMaxValues(0, 1)
                previewValue = indicatorPreview and 1 or 0.65
                barInfo.frame:SetValue(previewValue)
            else
                barInfo.frame:SetMinMaxValues(0, maxStacks)
                previewValue = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.65)
                barInfo.frame:SetValue(previewValue)
            end
            if barInfo.frame.thresholdOverlay then
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(barInfo.frame.thresholdOverlay, maxStacks)
                    barInfo.frame.thresholdOverlay:SetValue(previewValue or 0)
                    barInfo.frame.thresholdOverlay:Show()
                else
                    barInfo.frame.thresholdOverlay:SetValue(0)
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
                barInfo._maxStacksIndicator:SetValue(maxStacks)
            end
        elseif barInfo.barType == "custom_segmented" then
            local cabConfig = barInfo.cabConfig
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            local n = #barInfo.frame.segments
            local fill = indicatorPreview and n or math.ceil(n * 0.6)
            for _, seg in ipairs(barInfo.frame.segments) do
                seg:SetValue(fill)
            end
            if barInfo.frame.thresholdSegments then
                for _, seg in ipairs(barInfo.frame.thresholdSegments) do
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(seg, maxStacks)
                        seg:SetValue(fill)
                        seg:Show()
                    else
                        seg:SetValue(0)
                        seg:Hide()
                    end
                end
            end
            if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                barInfo._maxStacksIndicator:SetValue(maxStacks)
            end
        elseif barInfo.barType == "custom_overlay" then
            local cabConfig = barInfo.cabConfig
            local maxStacks = (cabConfig and cabConfig.maxStacks) or 1
            local indicatorPreview = cabConfig and cabConfig.maxStacksGlowEnabled
            local previewStacks = indicatorPreview and maxStacks or math.ceil(maxStacks * 0.7)
            local thresholdEnabled = IsCustomAuraMaxThresholdEnabled(cabConfig)
            local half = barInfo.halfSegments or 1
            for i = 1, half do
                barInfo.frame.segments[i]:SetValue(previewStacks)
                barInfo.frame.overlaySegments[i]:SetValue(previewStacks)
                if barInfo.frame.thresholdSegments and barInfo.frame.thresholdSegments[i] then
                    local seg = barInfo.frame.thresholdSegments[i]
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(seg, maxStacks)
                        seg:SetValue(previewStacks)
                        seg:Show()
                    else
                        seg:SetValue(0)
                        seg:Hide()
                    end
                end
            end
            if cabConfig and cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
                barInfo._maxStacksIndicator:SetValue(maxStacks)
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
        if CS then
            CS.customBarIndicatorPreviewActive = nil
        end
        if not GetPreviewActive() then return end
        SetPreviewActive(false)
        wipe(HEALTH_EFFECTS.preview)
        HEALTH_EFFECTS.forcedPreview = nil
        -- Resume live updates on next OnUpdate tick
    end

    function CooldownCompanion:IsResourceBarPreviewActive()
        return GetPreviewActive()
    end


    return {
        ApplyPreviewData = ApplyPreviewData,
        ApplyPreviewDataToBar = ApplyPreviewDataToBar,
    }
end
