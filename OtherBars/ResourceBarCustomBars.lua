--[[
    CooldownCompanion - ResourceBarCustomBars
    Custom aura bars, spell custom bars, visibility wakeups, styling, and frame preparation.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local EntryRuntime = ST.EntryRuntime

local math_max = math.max
local math_min = math.min
local GetTime = GetTime
local issecretvalue = issecretvalue

local RB = ST._RB
local CUSTOM_AURA_BAR_BASE = RB.CUSTOM_AURA_BAR_BASE
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL = 0.65
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS = 3
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION = 12.3

local function GetReadableApplicationCount(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then
        return nil
    end
    return tonumber(value)
end

local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
local EnsureCustomAuraBarAuraUnit = RB.EnsureCustomAuraBarAuraUnit
local GetResourceDisplayValue = RB.GetResourceDisplayValue
local NormalizeCustomAuraStackTextFormat = RB.NormalizeCustomAuraStackTextFormat
local IsCustomAuraMaxThresholdEnabled = RB.IsCustomAuraMaxThresholdEnabled
local GetCustomAuraMaxThresholdColor = RB.GetCustomAuraMaxThresholdColor
local SetCustomAuraMaxThresholdRange = RB.SetCustomAuraMaxThresholdRange
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local ClearResourceAuraVisuals = RB.ClearResourceAuraVisuals
local EnsureMaxStacksIndicator = RB.EnsureMaxStacksIndicator
local LayoutMaxStacksIndicator = RB.LayoutMaxStacksIndicator
local ClearMaxStacksIndicator = RB.ClearMaxStacksIndicator
local EnsureCustomAuraContinuousThresholdOverlay = RB.EnsureCustomAuraContinuousThresholdOverlay
local EnsureCustomAuraSegmentThresholdOverlays = RB.EnsureCustomAuraSegmentThresholdOverlays
local EnsureCustomAuraOverlayThresholdOverlays = RB.EnsureCustomAuraOverlayThresholdOverlays
local LayoutCustomAuraContinuousThresholdOverlay = RB.LayoutCustomAuraContinuousThresholdOverlay
local CreateContinuousBar = RB.CreateContinuousBar
local CreateSegmentedBar = RB.CreateSegmentedBar
local LayoutSegments = RB.LayoutSegments
local CreateOverlayBar = RB.CreateOverlayBar
local LayoutOverlaySegments = RB.LayoutOverlaySegments

local FormatTime = CooldownCompanion.FormatTime
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec
local SetAuraStackCountText = EntryRuntime.SetAuraStackCountText
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarElapsedDuration = ST.SetStatusBarElapsedDuration
local SetStatusBarRemainingDuration = ST.SetStatusBarRemainingDuration

function RB.CreateResourceBarCustomBarsModule(deps)
    local resourceBarFrames = deps.resourceBarFrames
    local GetPreviewActive = deps.GetPreviewActive
    local MarkLayoutDirty = deps.MarkLayoutDirty
    local RelayoutResourceStack = deps.RelayoutResourceStack
    local ClearStaleRecycledBarRuntimeState = deps.ClearStaleRecycledBarRuntimeState
    local ClearCustomAuraBarIndicatorState = deps.ClearCustomAuraBarIndicatorState
    local ClearCustomAuraBarIndicatorVisualState = deps.ClearCustomAuraBarIndicatorVisualState
        or ClearCustomAuraBarIndicatorState
    local UpdateCustomAuraBarIndicatorVisuals = deps.UpdateCustomAuraBarIndicatorVisuals
    local ApplyCustomAuraBarPreviewState = deps.ApplyCustomAuraBarPreviewState
    local customAuraWakeRetryQueue = {}
    local customAuraWakeRetryPending = {}
    local customAuraWakeRetryScheduled = false
    local processingCustomAuraWakeRetryQueue = false
    local customBarPresentationRefreshPending = false

    ------------------------------------------------------------------------
    -- Update logic: Custom aura bars (aura-based, secret-safe)
    ------------------------------------------------------------------------

    local function ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
        if not (cabConfig and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive)) then
            return true, false
        end

        local hideWhileAuraActive = cabConfig.hideWhileAuraActive == true
            and cabConfig.hideWhenInactive ~= true
            and auraPresent
            and not (cabConfig.hideAuraActiveExceptPandemic == true and inPandemic)
        local hideWhileAuraNotActive = cabConfig.hideWhenInactive == true and not auraPresent
        local shouldShow = not (hideWhileAuraActive or hideWhileAuraNotActive)
            or auraPreview
            or pandemicPreview

        return shouldShow, true
    end

    local function RequestCustomBarPresentationRefresh()
        if customBarPresentationRefreshPending then
            return
        end

        customBarPresentationRefreshPending = true
        C_Timer.After(0, function()
            customBarPresentationRefreshPending = false
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
    end

    local function BuildCustomBarAuraButtonData(cabConfig, addedAsAura)
        local spellID = tonumber(cabConfig and cabConfig.spellID)
        if not spellID then
            return nil, spellID
        end

        if addedAsAura then
            if RB.IsSpellCustomBarConfig(cabConfig) then
                return nil, spellID
            end
        elseif not (cabConfig and cabConfig.auraTracking == true) then
            return nil, nil
        end

        local buttonData = {
            type = "spell",
            id = spellID,
            auraSpellID = cabConfig.auraSpellID,
            auraTracking = true,
            auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID),
        }
        if addedAsAura then
            buttonData.addedAs = "aura"
        end
        return buttonData, spellID
    end

    local function ResolveSpellCustomBarAuraState(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        local buttonData, spellID = BuildCustomBarAuraButtonData(cabConfig, false)
        if not (buttonData and spellID and bar) then
            return nil
        end

        local configUnit = buttonData.auraUnit or "player"
        local resolvedAuraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
        return EntryRuntime.EvaluateTrackedAuraState(bar, buttonData, resolvedAuraSpellID, {
            configUnit = configUnit,
            allowDurationlessAuraInstance = true,
            useButtonAuraViewerFallback = true,
            validateCachedAuraData = EntryRuntime.AuraDataMatchesTrackedSpell,
        })
    end

    local function UpdateCustomAuraBar(barInfo)
        local cabConfig = barInfo.cabConfig
        if not cabConfig or not cabConfig.spellID then return end

        -- Read aura data from viewer frame (applications may be secret in combat)
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
        local auraState
        local stacks = 0
        local applications
        local readableApplications
        local auraPresent = false
        local durationObj
        local auraCooldownStart
        local auraCooldownDuration
        local isActive = cabConfig.trackingMode == "active"
        local bar = barInfo.barType == "custom_continuous" and barInfo.frame or nil
        local auraPreview = bar and bar._barAuraActivePreview
        local pandemicPreview = bar and bar._pandemicPreview
        local indicatorPreview = isActive and (auraPreview or pandemicPreview)
        local configUnit = EnsureCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
        local viewerFrame
        local auraUnit = configUnit
        local instId

        if spellAuraStackDisplay then
            auraState = ResolveSpellCustomBarAuraState(barInfo)
        elseif not isSpellCustomBar then
            local buttonData, spellID = BuildCustomBarAuraButtonData(cabConfig, true)
            if buttonData and spellID then
                configUnit = buttonData.auraUnit or configUnit
                auraState = EntryRuntime.EvaluateTrackedAuraState(barInfo.frame, buttonData, spellID, {
                    configUnit = configUnit,
                    allowDurationlessAuraInstance = true,
                    allowPlayerAuraFallbackWithoutReady = true,
                })
                viewerFrame = auraState and auraState.viewerFrame or nil
            end
        end

        if auraState then
            configUnit = auraState.configUnit or configUnit
            viewerFrame = auraState.viewerFrame
            if auraState.auraPresent == true then
                auraPresent = true
                instId = auraState.auraInstanceID
                if instId == nil and auraState.auraGraceHeld and barInfo.frame then
                    instId = barInfo.frame._auraInstanceID
                end
                auraUnit = auraState.auraUnit or configUnit
                local stateApplications = auraState.auraApplications
                if stateApplications == nil and auraState.auraData then
                    stateApplications = auraState.auraData.applications
                end
                if stateApplications == nil
                    and auraState.auraGraceHeld
                    and barInfo.frame then
                    stateApplications = barInfo.frame._customAuraStackValue
                        or barInfo.frame._customAuraApplicationsValue
                end
                applications = stateApplications
                readableApplications = GetReadableApplicationCount(applications)
                if isActive then
                    stacks = 1
                elseif applications ~= nil then
                    stacks = applications
                else
                    stacks = 0
                end
                durationObj = auraState.durationObj
                auraCooldownStart = auraState.auraCooldownStart
                auraCooldownDuration = auraState.auraCooldownDuration
            end
        end

        if spellAuraStackDisplay and not auraPresent and not GetPreviewActive() then
            if barInfo.frame then
                barInfo.frame._customAuraStackValue = nil
                barInfo.frame._customAuraApplicationsValue = nil
            end
            if CooldownCompanion.UpdateCustomBarSoundAlerts then
                CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, false)
            end
            RequestCustomBarPresentationRefresh()
            return
        end

        local soundAuraActive = auraPresent
        if indicatorPreview and not auraPresent then
            auraPresent = true
            applications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
            readableApplications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
            stacks = 1
        end

        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, soundAuraActive)
        end

        local pandemicStateFrame = barInfo.frame
        local inPandemic = EntryRuntime.ResolveAuraPandemicState(pandemicStateFrame, viewerFrame, {
            enabled = configUnit == "target" and auraPresent,
            previewActive = pandemicPreview == true,
            clearWhenDisabled = true,
        })

        if isActive and bar then
            if auraPresent then
                bar._auraInstanceID = instId
                bar._auraUnit = auraUnit
            else
                bar._auraInstanceID = nil
                bar._auraUnit = nil
            end

            bar._inPandemic = inPandemic or nil
        elseif pandemicStateFrame then
            pandemicStateFrame._inPandemic = inPandemic or nil
        end

        local shouldShow, hasVisibilityRule = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
        if spellAuraStackDisplay and auraState and auraState.ready ~= true then
            hasVisibilityRule = false
            shouldShow = true
        end
        if hasVisibilityRule then
            local wasShown = barInfo.frame:IsShown()
            barInfo.frame:SetShown(shouldShow)
            if wasShown ~= shouldShow then
                MarkLayoutDirty()
            end
            if not shouldShow then
                if barInfo.frame then
                    if not auraPresent then
                        barInfo.frame._customAuraStackValue = nil
                        barInfo.frame._customAuraApplicationsValue = nil
                    end
                end
                if isActive then
                    ClearCustomAuraBarIndicatorVisualState(barInfo, false)
                end
                return
            end
        end

        local maxStacks = cabConfig.maxStacks or 1
        local thresholdEnabled = (not spellAuraStackDisplay) and IsCustomAuraMaxThresholdEnabled(cabConfig)

        if barInfo.barType == "custom_continuous" then
            local bar = barInfo.frame
            if isActive then
                SetStatusBarSmoothRange(bar, 0, 1)
                if durationObj then
                    if not SetStatusBarRemainingDuration(bar, durationObj) then
                        SetStatusBarSmoothValue(bar, durationObj:GetRemainingPercent())  -- secret-safe, 1->0 drain
                    end
                elseif auraCooldownStart and auraCooldownDuration and auraCooldownDuration > 0 then
                    local remaining = auraCooldownStart + auraCooldownDuration - GetTime()
                    SetStatusBarSmoothValue(bar, math_max(0, math_min(1, remaining / auraCooldownDuration)))
                elseif indicatorPreview then
                    SetStatusBarImmediateValue(bar, CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
                else
                    -- No DurationObject (indefinite aura or aura absent)
                    SetStatusBarImmediateValue(bar, stacks)  -- 1 if active (full), 0 if absent (empty)
                end
            else
                SetStatusBarSmoothRange(bar, 0, maxStacks)
                SetStatusBarSmoothValue(bar, stacks)  -- SetValue accepts secrets
            end

            if bar.thresholdOverlay then
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(bar.thresholdOverlay, maxStacks)
                    SetStatusBarSmoothValue(bar.thresholdOverlay, stacks)
                    bar.thresholdOverlay:Show()
                else
                    SetStatusBarImmediateValue(bar.thresholdOverlay, 0)
                    bar.thresholdOverlay:Hide()
                end
            end

            -- Duration text (bar.text): driven by showDurationText, independent of drain
            if bar.text and bar.text:IsShown() then
                if durationObj then
                    local remaining = durationObj:GetRemainingDuration()
                    if not durationObj:HasSecretValues() then
                        if remaining > 0 then
                            bar.text:SetText(FormatTime(remaining, cabConfig))
                        else
                            bar.text:SetText("")
                        end
                    else
                        bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
                    end
                elseif auraCooldownStart and auraCooldownDuration and auraCooldownDuration > 0 then
                    local remaining = auraCooldownStart + auraCooldownDuration - GetTime()
                    if remaining > 0 then
                        bar.text:SetText(FormatTime(remaining, cabConfig))
                    else
                        bar.text:SetText("")
                    end
                elseif indicatorPreview then
                    bar.text:SetText(FormatTime(CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION, cabConfig))
                else
                    bar.text:SetText("")
                end
            end

            -- Stack text (bar.stackText): driven by showStackText
            if bar.stackText and bar.stackText:IsShown() then
                if auraPresent then
                    if isActive then
                        SetAuraStackCountText(bar.stackText, applications, maxStacks, "current")
                    else
                        local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig.stackTextFormat)
                        SetAuraStackCountText(bar.stackText, stacks, maxStacks, stackTextFormat)
                    end
                else
                    bar.stackText:SetText("")
                end
            end

            if isActive then
                UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)
            else
                ClearCustomAuraBarIndicatorVisualState(barInfo, true)
            end

        elseif barInfo.barType == "custom_segmented" then
            local holder = barInfo.frame
            if not holder.segments then return end
            -- Each segment has MinMax(i-1, i) — SetValue(stacks) with C-level clamping
            -- handles fill/empty without comparing the secret stacks value in Lua
            for i = 1, #holder.segments do
                SetStatusBarSmoothValue(holder.segments[i], stacks)
            end

            if holder.thresholdSegments then
                for i = 1, #holder.thresholdSegments do
                    local thresholdSeg = holder.thresholdSegments[i]
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                        SetStatusBarSmoothValue(thresholdSeg, stacks)
                        thresholdSeg:Show()
                    else
                        SetStatusBarImmediateValue(thresholdSeg, 0)
                        thresholdSeg:Hide()
                    end
                end
            end

        elseif barInfo.barType == "custom_overlay" then
            local holder = barInfo.frame
            if not holder.segments then return end
            local half = barInfo.halfSegments or 1

            -- Pass stacks to ALL segments (StatusBar C-level clamping handles per-segment fill)
            for i = 1, half do
                SetStatusBarSmoothValue(holder.segments[i], stacks)
                SetStatusBarSmoothValue(holder.overlaySegments[i], stacks)
            end

            if holder.thresholdSegments then
                for i = 1, half do
                    local thresholdSeg = holder.thresholdSegments[i]
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                        SetStatusBarSmoothValue(thresholdSeg, stacks)
                        thresholdSeg:Show()
                    else
                        SetStatusBarImmediateValue(thresholdSeg, 0)
                        thresholdSeg:Hide()
                    end
                end
            end
        end

        if barInfo.frame then
            if auraPresent and applications ~= nil then
                barInfo.frame._customAuraStackValue = applications
                barInfo.frame._customAuraApplicationsValue = readableApplications
            elseif not auraPresent or not (auraState and auraState.auraGraceHeld) then
                barInfo.frame._customAuraStackValue = nil
                barInfo.frame._customAuraApplicationsValue = nil
            end
        end

        -- Max stacks indicator: SetValue drives visibility via C-level clamping
        if cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
            SetStatusBarSmoothValue(barInfo._maxStacksIndicator, (auraPresent and applications ~= nil) and applications or 0)
        end
    end

    local function UpdateSpellCustomBarChargeText(bar, cooldownResult)
        if not (bar and bar.stackText and bar.stackText:IsShown()) then
            return
        end

        local currentCharges = cooldownResult and cooldownResult.currentCharges
        local maxCharges = cooldownResult and cooldownResult.maxCharges
        if currentCharges ~= nil and maxCharges and maxCharges > 1 then
            bar.stackText:SetFormattedText("%d / %d", currentCharges, maxCharges)
        elseif cooldownResult and cooldownResult.chargeDisplayCount ~= nil then
            local displayCount = cooldownResult.chargeDisplayCount
            if issecretvalue and issecretvalue(displayCount) then
                bar.stackText:SetText(displayCount)
            else
                local numericCount = tonumber(displayCount)
                if numericCount and maxCharges and maxCharges > 1 then
                    bar.stackText:SetFormattedText("%d / %d", numericCount, maxCharges)
                elseif displayCount and displayCount ~= "" then
                    bar.stackText:SetText(displayCount)
                else
                    bar.stackText:SetText("")
                end
            end
        else
            bar.stackText:SetText("")
        end
    end

    function RB.UpdateSpellCustomBarAuraStackText(bar, cabConfig, stacks, maxStacks, auraPresent)
        if not (bar and bar.stackText and bar.stackText:IsShown()) then
            return
        end

        if not auraPresent then
            bar.stackText:SetText("")
            return
        end

        SetAuraStackCountText(
            bar.stackText,
            stacks,
            maxStacks,
            NormalizeCustomAuraStackTextFormat(cabConfig and cabConfig.stackTextFormat)
        )
    end

    function RB.UpdateCustomCooldownBar(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        if not (cabConfig and cabConfig.spellID and bar) then return end

        local cooldownResult = EntryRuntime.EvaluateSpellCooldownStateForCustomBar(cabConfig, bar)
        local durationObj = cooldownResult and cooldownResult.renderDurationObj
        local cooldownActive = cooldownResult
            and cooldownResult.state == ST.CooldownLogic.STATE_COOLDOWN
        local auraState = ResolveSpellCustomBarAuraState(barInfo)
        local auraPresent = auraState and auraState.ready == true and auraState.auraPresent == true
        local auraPreview = bar._barAuraActivePreview == true
        local pandemicPreview = bar._pandemicPreview == true
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local renderAuraState = cabConfig.auraTracking == true
            and not spellAuraStackDisplay
            and (auraPresent or auraPreview or pandemicPreview)

        local barColor = cabConfig.barColor or {0.5, 0.5, 1, 1}
        local cooldownColor = cabConfig.barCooldownColor or {0.6, 0.13, 0.18, 1}
        local rechargeColor = cabConfig.barChargeColor or {1.0, 0.82, 0.0, 1}
        local chargeState = cooldownResult and cooldownResult.chargeState
        local fillColor = barColor
        if cooldownResult and cooldownResult.hasCharges == true then
            if chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO then
                fillColor = cooldownColor
            elseif cooldownActive then
                fillColor = rechargeColor
            end
        elseif cooldownActive then
            fillColor = cooldownColor
        end

        local function UpdateSpellCustomBarSounds(soundAuraActive)
            if CooldownCompanion.UpdateCustomBarSoundAlerts then
                local soundCooldownActive = cooldownActive
                if cooldownResult and cooldownResult.hasCharges == true then
                    soundCooldownActive = cooldownResult.chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO
                        or (cooldownResult.chargeState == nil and cooldownActive)
                end
                CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, soundAuraActive, soundCooldownActive, cooldownResult)
            end
        end

        local configUnit = (auraState and auraState.configUnit)
            or GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
        local inPandemic = EntryRuntime.ResolveAuraPandemicState(bar, auraState and auraState.viewerFrame, {
            enabled = configUnit == "target" and auraPresent,
            previewActive = pandemicPreview == true,
            clearWhenDisabled = true,
        })

        if auraState
            and auraState.ready == true
            and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive) then
            local shouldShow = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
            local wasShown = bar:IsShown()
            bar:SetShown(shouldShow)
            if wasShown ~= shouldShow then
                MarkLayoutDirty()
            end
            if not shouldShow then
                ClearCustomAuraBarIndicatorState(barInfo, false)
                UpdateSpellCustomBarSounds(auraPresent)
                return
            end
        elseif (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive)
            and not bar:IsShown() then
            bar:Show()
            MarkLayoutDirty()
        end

        if spellAuraStackDisplay and auraPresent then
            UpdateSpellCustomBarSounds(true)
            RequestCustomBarPresentationRefresh()
            return
        end

        if renderAuraState then
            if auraPresent then
                bar._auraActive = true
                bar._auraInstanceID = auraState.auraInstanceID
                bar._auraUnit = auraState.auraUnit
            else
                bar._auraActive = true
                bar._auraInstanceID = nil
                bar._auraUnit = nil
            end
            bar._inPandemic = inPandemic or nil

            local auraDurationObj = auraState and auraState.durationObj
            bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)
            SetStatusBarSmoothRange(bar, 0, 1)
            if auraDurationObj then
                if not SetStatusBarRemainingDuration(bar, auraDurationObj) then
                    SetStatusBarSmoothValue(bar, auraDurationObj:GetRemainingPercent())
                end
            elseif auraPreview or pandemicPreview then
                SetStatusBarImmediateValue(bar, CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
            else
                SetStatusBarImmediateValue(bar, 1)
            end

            if bar.thresholdOverlay then
                SetStatusBarImmediateValue(bar.thresholdOverlay, 0)
                bar.thresholdOverlay:Hide()
            end

            if bar.text and bar.text:IsShown() then
                if auraDurationObj then
                    local remaining = auraDurationObj:GetRemainingDuration()
                    if auraDurationObj:HasSecretValues() then
                        bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
                    elseif remaining and remaining > 0 then
                        bar.text:SetText(FormatTime(remaining, cabConfig))
                    else
                        bar.text:SetText("")
                    end
                elseif auraPreview or pandemicPreview then
                    bar.text:SetText(FormatTime(CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION, cabConfig))
                else
                    bar.text:SetText("")
                end
            end

            UpdateSpellCustomBarChargeText(bar, cooldownResult)
            UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)

            if barInfo._maxStacksIndicator then
                SetStatusBarImmediateValue(barInfo._maxStacksIndicator, 0)
            end

            UpdateSpellCustomBarSounds(auraPresent)
            return
        end

        ClearCustomAuraBarIndicatorState(barInfo, false)

        SetStatusBarSmoothRange(bar, 0, 1)
        bar:SetStatusBarColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] ~= nil and fillColor[4] or 1)
        if cooldownActive and durationObj then
            if not SetStatusBarElapsedDuration(bar, durationObj) then
                SetStatusBarSmoothValue(bar, durationObj:GetElapsedPercent())
            end
        elseif cooldownActive then
            SetStatusBarImmediateValue(bar, 0)
        else
            SetStatusBarImmediateValue(bar, 1)
        end

        if bar.thresholdOverlay then
            SetStatusBarImmediateValue(bar.thresholdOverlay, 0)
            bar.thresholdOverlay:Hide()
        end

        if bar.text and bar.text:IsShown() then
            if cooldownActive and durationObj then
                local remaining = durationObj:GetRemainingDuration()
                if durationObj:HasSecretValues() then
                    bar.text:SetFormattedText(GetDurationSecretFormatSpec(cabConfig), remaining)
                elseif remaining and remaining > 0 then
                    bar.text:SetText(FormatTime(remaining, cabConfig))
                else
                    bar.text:SetText("")
                end
            else
                bar.text:SetText("")
            end
        end

        UpdateSpellCustomBarChargeText(bar, cooldownResult)

        if barInfo._maxStacksIndicator then
            SetStatusBarImmediateValue(barInfo._maxStacksIndicator, 0)
        end

        UpdateSpellCustomBarSounds(false)
    end

    function CooldownCompanion:RecordCustomBarSpellCast(spellID)
        if not spellID then return end

        for _, barInfo in ipairs(resourceBarFrames) do
            local bar = barInfo and barInfo.frame
            local cabConfig = barInfo and barInfo.cabConfig
            if barInfo
                and barInfo.barType == "custom_cooldown"
                and bar
                and cabConfig
                and cabConfig.entryType == "spell"
            then
                local baseSpellID = tonumber(cabConfig.spellID)
                local runtimeSpellID = baseSpellID and C_Spell.GetOverrideSpell(baseSpellID)
                if not runtimeSpellID or runtimeSpellID == 0 then
                    runtimeSpellID = baseSpellID
                end

                local charges = runtimeSpellID and C_Spell.GetSpellCharges(runtimeSpellID)
                local maxCharges = charges and tonumber(charges.maxCharges)
                if (maxCharges or 0) > 1
                    and (spellID == baseSpellID or spellID == runtimeSpellID) then
                    EntryRuntime.RecordChargeSpent(bar)
                end
            end
        end
    end

    local function GetHiddenCustomAuraWakeUnit(cabConfig)
        if not cabConfig or not cabConfig.spellID then
            return nil
        end
        return EnsureCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
    end

    local function IsEventDrivenCustomAuraBar(barInfo)
        return barInfo
            and (barInfo.barType == "custom_segmented"
                or barInfo.barType == "custom_overlay"
                or barInfo.barType == "custom_cooldown")
    end

    local function ShouldUpdateHiddenCustomAuraPandemicWake(barInfo)
        local frame = barInfo and barInfo.frame
        local cabConfig = barInfo and barInfo.cabConfig
        if not (frame and cabConfig) then
            return false
        end
        if frame:IsShown() then
            return false
        end
        if cabConfig.hideWhileAuraActive ~= true
            or cabConfig.hideWhenInactive == true
            or cabConfig.hideAuraActiveExceptPandemic ~= true then
            return false
        end

        local isTrackedSpellBar = barInfo.barType == "custom_cooldown"
            and cabConfig.auraTracking == true
        local isActiveAuraBar = barInfo.barType == "custom_continuous"
            and cabConfig.trackingMode == "active"
        if not (isTrackedSpellBar or isActiveAuraBar) then
            return false
        end

        return GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID) == "target"
    end

    local function ClearDeferredCustomAuraWakeRetries()
        wipe(customAuraWakeRetryQueue)
        wipe(customAuraWakeRetryPending)
        customAuraWakeRetryScheduled = false
        processingCustomAuraWakeRetryQueue = false
    end

    local function ResolveDeferredCustomAuraWakeRetryBarInfo(entry)
        if not entry or not entry.customBarId or not entry.cabConfig then
            return nil
        end

        -- ApplyResourceBars() can recreate the custom aura bar before the next-frame
        -- retry fires, so re-resolve the active barInfo instead of trusting the
        -- captured table/frame from queue time.
        for _, candidate in ipairs(resourceBarFrames) do
            if candidate
                and candidate.customBarId == entry.customBarId
                and candidate.cabConfig == entry.cabConfig then
                return candidate
            end
        end

        return nil
    end

    local function ProcessDeferredCustomAuraWakeRetries()
        customAuraWakeRetryScheduled = false
        if processingCustomAuraWakeRetryQueue then return end
        if #customAuraWakeRetryQueue == 0 then return end

        processingCustomAuraWakeRetryQueue = true
        local queue = customAuraWakeRetryQueue
        customAuraWakeRetryQueue = {}
        customAuraWakeRetryPending = {}

        local relayoutNeeded = false
        for _, entry in ipairs(queue) do
            local barInfo = ResolveDeferredCustomAuraWakeRetryBarInfo(entry)
            local frame = barInfo and barInfo.frame
            local cabConfig = barInfo and barInfo.cabConfig
            if barInfo
                and frame
                and cabConfig
                and barInfo.cabConfig == entry.cabConfig
                and IsEventDrivenCustomAuraBar(barInfo)
                and (cabConfig.hideWhenInactive == true or cabConfig.hideWhileAuraActive == true)
                and GetHiddenCustomAuraWakeUnit(cabConfig) == entry.unit
                and not frame:IsShown()
            then
                if barInfo.barType == "custom_cooldown" then
                    RB.UpdateCustomCooldownBar(barInfo)
                else
                    UpdateCustomAuraBar(barInfo)
                end
                if frame:IsShown() then
                    relayoutNeeded = true
                end
            end
        end

        processingCustomAuraWakeRetryQueue = false

        if relayoutNeeded then
            RelayoutResourceStack()
        end
    end

    local function QueueDeferredCustomAuraWakeRetry(barInfo, unit)
        if processingCustomAuraWakeRetryQueue then return end
        if unit ~= "player" and unit ~= "target" then return end
        if not IsEventDrivenCustomAuraBar(barInfo) then return end

        local frame = barInfo and barInfo.frame
        local cabConfig = barInfo and barInfo.cabConfig
        local customBarId = barInfo and barInfo.customBarId
        if not frame
            or not cabConfig
            or not customBarId
            or not (cabConfig.hideWhenInactive == true or cabConfig.hideWhileAuraActive == true) then
            return
        end
        if frame:IsShown() then return end
        if GetHiddenCustomAuraWakeUnit(cabConfig) ~= unit then return end
        if customAuraWakeRetryPending[cabConfig] then return end

        customAuraWakeRetryPending[cabConfig] = true
        customAuraWakeRetryQueue[#customAuraWakeRetryQueue + 1] = {
            cabConfig = cabConfig,
            customBarId = customBarId,
            unit = unit,
        }

        if customAuraWakeRetryScheduled then
            return
        end

        customAuraWakeRetryScheduled = true
        C_Timer.After(0, function()
            ProcessDeferredCustomAuraWakeRetries()
        end)
    end

    local function RefreshEventDrivenCustomAuraBarsForUnit(unit)
        if unit ~= "player" and unit ~= "target" then return end

        for _, barInfo in ipairs(resourceBarFrames) do
            local frame = barInfo and barInfo.frame
            local cabConfig = barInfo and barInfo.cabConfig
            local shouldRefresh = frame and (
                IsEventDrivenCustomAuraBar(barInfo)
                or (not frame:IsShown()
                    and cabConfig
                    and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive))
            )
            if shouldRefresh
                and cabConfig
                and (barInfo.barType == "custom_continuous"
                    or barInfo.barType == "custom_segmented"
                    or barInfo.barType == "custom_overlay"
                    or barInfo.barType == "custom_cooldown")
                and GetHiddenCustomAuraWakeUnit(cabConfig) == unit then
                local wasShown = frame:IsShown()
                if barInfo.barType == "custom_cooldown" then
                    RB.UpdateCustomCooldownBar(barInfo)
                else
                    UpdateCustomAuraBar(barInfo)
                end
                if not wasShown and not frame:IsShown() then
                    QueueDeferredCustomAuraWakeRetry(barInfo, unit)
                end
            end
        end
    end

    ------------------------------------------------------------------------
    -- Styling: Custom aura bars
    ------------------------------------------------------------------------

    local function StyleCustomAuraBar(barInfo, cabConfig)
        local barColor = cabConfig.barColor or {0.5, 0.5, 1}
        local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
        local thresholdEnabled = (not isSpellCustomBar) and IsCustomAuraMaxThresholdEnabled(cabConfig)
        local thresholdColor = GetCustomAuraMaxThresholdColor(cabConfig)

        if barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown" then
            local bar = barInfo.frame
            bar.style = cabConfig
            local isVertical = bar._isVertical == true
            bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
            if bar.thresholdOverlay then
                bar.thresholdOverlay:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                bar.thresholdOverlay:SetShown(thresholdEnabled)
            end

            -- Determine visibility for both text elements
            local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
            local spellAuraStackActive = spellAuraStackDisplay and barInfo.barType ~= "custom_cooldown"
            local isActive = isSpellCustomBar and not spellAuraStackActive
                or ((not isSpellCustomBar) and cabConfig.trackingMode == "active")
            local showDuration = cabConfig.showDurationText == true and not spellAuraStackActive
            local showStack = cabConfig.showStackText
            if isSpellCustomBar then
                showStack = showStack == true
            elseif showStack == nil then
                -- Backwards compat: fall back to showText for stacks mode
                if not isActive then
                    showStack = cabConfig.showText == true
                else
                    showStack = false
                end
            end

            -- Duration text (bar.text)
            if bar.text then
                bar.text:SetShown(showDuration)
                if showDuration then
                    bar.text:ClearAllPoints()
                    if showStack then
                        if isVertical then
                            bar.text:SetPoint("BOTTOM", bar, "BOTTOM", 0, 2)
                        else
                            bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
                        end
                    else
                        bar.text:SetPoint("CENTER")
                    end
                end
            end

            -- Stack text (bar.stackText)
            if bar.stackText then
                bar.stackText:SetShown(showStack)
                if showStack then
                    bar.stackText:ClearAllPoints()
                    if showDuration then
                        if isVertical then
                            bar.stackText:SetPoint("TOP", bar, "TOP", 0, -2)
                        else
                            bar.stackText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
                        end
                    else
                        bar.stackText:SetPoint("CENTER")
                    end
                end
            end

        elseif barInfo.barType == "custom_segmented" then
            local holder = barInfo.frame
            if holder.segments then
                for _, seg in ipairs(holder.segments) do
                    seg:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
                end
            end
            if holder.thresholdSegments then
                for _, seg in ipairs(holder.thresholdSegments) do
                    seg:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                    seg:SetShown(thresholdEnabled)
                end
            end

        elseif barInfo.barType == "custom_overlay" then
            local holder = barInfo.frame
            local overlayColor = cabConfig.overlayColor or {1, 0.84, 0}
            local half = barInfo.halfSegments or 1
            if holder.segments then
                for i = 1, half do
                    holder.segments[i]:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)
                    holder.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                    holder.overlaySegments[i]:Show()
                    if holder.thresholdSegments and holder.thresholdSegments[i] then
                        holder.thresholdSegments[i]:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], 1)
                        holder.thresholdSegments[i]:SetShown(thresholdEnabled)
                    end
                end
            end
        end
    end

    local function FinalizeAppliedBarVisibility(barInfo, previewActive)
        if barInfo and type(barInfo.customBarId) == "string" then
            if previewActive then
                barInfo.frame:Show()
            elseif barInfo.cabConfig
                and (barInfo.cabConfig.hideWhenInactive or barInfo.cabConfig.hideWhileAuraActive) then
                if barInfo.barType == "custom_cooldown" then
                    RB.UpdateCustomCooldownBar(barInfo)
                else
                    UpdateCustomAuraBar(barInfo)
                end
            else
                barInfo.frame:Show()
                if barInfo.barType == "custom_cooldown" then
                    RB.UpdateCustomCooldownBar(barInfo)
                else
                    UpdateCustomAuraBar(barInfo)
                end
            end
        else
            barInfo.frame:Show()
        end
    end

    local function HideUnusedResourceBarFrames(firstHiddenIndex)
        for i = firstHiddenIndex, #resourceBarFrames do
            local barInfo = resourceBarFrames[i]
            if barInfo and barInfo.frame then
                ClearStaleRecycledBarRuntimeState(barInfo.frame)
                ClearCustomAuraBarIndicatorState(barInfo, true)
                ClearResourceAuraVisuals(barInfo.frame)
                ClearMaxStacksIndicator(barInfo)
                barInfo.frame:Hide()
                barInfo.cabConfig = nil
                barInfo.powerType = nil
                barInfo.customBarId = nil
                barInfo.customBarIndex = nil
                barInfo._sndInitialized = nil
                barInfo._sndPrevAuraActive = nil
                barInfo._sndPrevCooldownActive = nil
                barInfo._sndPrevCharges = nil
                barInfo._sndPrevChargeRecharging = nil
                barInfo._sndPrevChargeCooldownStart = nil
                barInfo._side = nil
                barInfo._order = nil
                barInfo._effectiveThickness = nil
                if barInfo.frame.brightnessOverlay then
                    barInfo.frame.brightnessOverlay:Hide()
                end
            end
        end
    end

    local function PrepareCustomAuraBar(
        targetContainer,
        barInfo,
        customEntry,
        customBars,
        settings,
        isVerticalLayout,
        reverseVerticalFill,
        effectiveWidth,
        effectiveHeight,
        segmentGap
    )
        local cabIndex
        local cabConfig
        local customBarId
        local legacyPowerType
        if type(customEntry) == "table" then
            cabIndex = customEntry.customBarIndex or customEntry.index
            cabConfig = customEntry.config or (customBars and cabIndex and customBars[cabIndex])
            customBarId = customEntry.customBarId or (cabConfig and cabConfig.customBarId)
        else
            legacyPowerType = customEntry
            cabIndex = legacyPowerType - CUSTOM_AURA_BAR_BASE + 1
            cabConfig = customBars[cabIndex]
            customBarId = cabConfig and cabConfig.customBarId
        end
        if not cabConfig then
            return barInfo
        end
        customBarId = customBarId or RB.EnsureCustomBarId(settings, cabConfig)
        local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local spellAuraStackPresent = spellAuraStackDisplay and GetPreviewActive()
        if spellAuraStackDisplay and not spellAuraStackPresent and barInfo and barInfo.frame then
            local auraState = ResolveSpellCustomBarAuraState(barInfo)
            spellAuraStackPresent = auraState and auraState.ready == true and auraState.auraPresent == true
        end
        local spellAuraStackActive = spellAuraStackDisplay and spellAuraStackPresent
        local isActive = (isSpellCustomBar and not spellAuraStackActive)
            or ((not isSpellCustomBar) and cabConfig.trackingMode == "active")
        local mode = isSpellCustomBar
            and (spellAuraStackActive and (cabConfig.displayMode or "segmented") or "continuous")
            or (isActive and "continuous" or (cabConfig.displayMode or "segmented"))
        local maxStacks = isActive and 1 or (cabConfig.maxStacks or 1)
        local targetBarType = (isSpellCustomBar and not spellAuraStackActive)
            and "custom_cooldown"
            or ("custom_" .. mode)
        local customOrientation = isVerticalLayout and "vertical" or "horizontal"
        local customIsVertical = customOrientation == "vertical"
        local customReverseFill = false
        if customIsVertical then
            customReverseFill = reverseVerticalFill
        end
        local customWidth = effectiveWidth
        local customHeight = effectiveHeight

        local needsRecreate = not barInfo or barInfo.barType ~= targetBarType
        if not needsRecreate and mode == "segmented" then
            needsRecreate = barInfo.frame._numSegments ~= maxStacks
        end
        if not needsRecreate and mode == "overlay" then
            needsRecreate = barInfo.halfSegments ~= math.ceil(maxStacks / 2)
        end

        if needsRecreate then
            if barInfo and barInfo.frame then
                ClearCustomAuraBarIndicatorState(barInfo, true)
                ClearResourceAuraVisuals(barInfo.frame)
                ClearMaxStacksIndicator(barInfo)
                barInfo.frame:Hide()
            end
            if mode == "continuous" then
                local bar = CreateContinuousBar(targetContainer)
                SetStatusBarSmoothRange(bar, 0, maxStacks)
                barInfo = { frame = bar, barType = targetBarType }
            elseif mode == "segmented" then
                local holder = CreateSegmentedBar(targetContainer, maxStacks)
                for si = 1, maxStacks do
                    holder.segments[si]:SetMinMaxValues(si - 1, si)
                end
                barInfo = { frame = holder, barType = "custom_segmented" }
            elseif mode == "overlay" then
                local half = math.ceil(maxStacks / 2)
                local holder = CreateOverlayBar(targetContainer, half)
                barInfo = { frame = holder, barType = "custom_overlay", halfSegments = half }
            end
        end

        if mode == "continuous" then
            EnsureCustomAuraContinuousThresholdOverlay(barInfo.frame)
        elseif mode == "segmented" then
            EnsureCustomAuraSegmentThresholdOverlays(barInfo.frame)
        elseif mode == "overlay" then
            EnsureCustomAuraOverlayThresholdOverlays(barInfo.frame, barInfo.halfSegments or math.ceil(maxStacks / 2))
        end

        if barInfo.customBarId ~= customBarId then
            barInfo._sndInitialized = nil
            barInfo._sndPrevAuraActive = nil
            barInfo._sndPrevCooldownActive = nil
            barInfo._sndPrevCharges = nil
            barInfo._sndPrevChargeRecharging = nil
            barInfo._sndPrevChargeCooldownStart = nil
        end
        barInfo.cabConfig = cabConfig
        barInfo.powerType = legacyPowerType
        barInfo.customBarId = customBarId
        barInfo.customBarIndex = cabIndex
        ApplyCustomAuraBarPreviewState(barInfo)
        barInfo.frame:SetSize(customWidth, customHeight)
        barInfo.frame._isVertical = customIsVertical
        barInfo.frame._reverseFill = customReverseFill
        if mode == "segmented" then
            LayoutSegments(
                barInfo.frame,
                customWidth,
                customHeight,
                segmentGap,
                settings,
                customOrientation,
                customReverseFill
            )
        elseif mode == "overlay" then
            LayoutOverlaySegments(
                barInfo.frame,
                customWidth,
                customHeight,
                segmentGap,
                settings,
                barInfo.halfSegments,
                customOrientation,
                customReverseFill
            )
        end
        if mode == "continuous" then
            local barTextureName = GetResourceDisplayValue(settings, "barTexture", "Solid")
            local barTexture = CooldownCompanion:FetchStatusBar(barTextureName)
            barInfo.frame:SetStatusBarTexture(barTexture)
            barInfo.frame:SetOrientation(customIsVertical and "VERTICAL" or "HORIZONTAL")
            barInfo.frame:SetReverseFill(customIsVertical and customReverseFill or false)
            barInfo.frame._isVertical = customIsVertical
            barInfo.frame._reverseFill = customReverseFill
            local bgc = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
            barInfo.frame.bg:ClearAllPoints()
            barInfo.frame.bg:SetAllPoints(barInfo.frame)
            barInfo.frame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
            local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
            local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
            local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
            local borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)
            if borderStyle == "pixel" then
                ApplyPixelBorders(barInfo.frame.borders, barInfo.frame, borderColor, borderSize, borderRenderMode)
            else
                HidePixelBorders(barInfo.frame.borders)
            end
            LayoutCustomAuraContinuousThresholdOverlay(barInfo.frame, barTexture, borderStyle, borderSize, borderRenderMode)
            local durationTextFontName = cabConfig.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT
            local durationTextSize = tonumber(cabConfig.durationTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
            local durationTextOutline = ST.GetEffectiveFontOutline(cabConfig.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
            local durationTextColor = cabConfig.durationTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
            if type(durationTextColor) ~= "table" or durationTextColor[1] == nil or durationTextColor[2] == nil or durationTextColor[3] == nil then
                durationTextColor = DEFAULT_RESOURCE_TEXT_COLOR
            end
            local durationTextFont = CooldownCompanion:FetchFont(durationTextFontName)
            barInfo.frame.text:SetFont(durationTextFont, durationTextSize, durationTextOutline)
            barInfo.frame.text:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] ~= nil and durationTextColor[4] or 1)
            if not barInfo.frame.stackText then
                barInfo.frame.stackText = (barInfo.frame.textLayer or barInfo.frame):CreateFontString(nil, "OVERLAY")
                barInfo.frame.stackText:SetTextColor(1, 1, 1, 1)
            end
            local stackTextFontName = cabConfig.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT
            local stackTextSize = tonumber(cabConfig.stackTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
            local stackTextOutline = ST.GetEffectiveFontOutline(cabConfig.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
            local stackTextColor = cabConfig.stackTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
            if type(stackTextColor) ~= "table" or stackTextColor[1] == nil or stackTextColor[2] == nil or stackTextColor[3] == nil then
                stackTextColor = DEFAULT_RESOURCE_TEXT_COLOR
            end
            local stackTextFont = CooldownCompanion:FetchFont(stackTextFontName)
            barInfo.frame.stackText:SetFont(stackTextFont, stackTextSize, stackTextOutline)
            barInfo.frame.stackText:SetTextColor(stackTextColor[1], stackTextColor[2], stackTextColor[3], stackTextColor[4] ~= nil and stackTextColor[4] or 1)
            barInfo.frame.brightnessOverlay:Hide()
        end
        StyleCustomAuraBar(barInfo, cabConfig)

        if cabConfig.maxStacksGlowEnabled then
            if isSpellCustomBar then
                ClearMaxStacksIndicator(barInfo)
            else
                EnsureMaxStacksIndicator(barInfo)
                local indBorderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
                local indBorderSize = GetResourceDisplayValue(settings, "borderSize", 1)
                local indBorderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)
                local indBarTexture = CooldownCompanion:FetchStatusBar(GetResourceDisplayValue(settings, "barTexture", "Solid"))
                LayoutMaxStacksIndicator(barInfo, cabConfig, maxStacks, indBarTexture, indBorderStyle, indBorderSize, indBorderRenderMode)
            end
        else
            ClearMaxStacksIndicator(barInfo)
        end

        return barInfo
    end

    RB.PrepareCustomAuraBar = PrepareCustomAuraBar

    ------------------------------------------------------------------------
    -- Live recolor for custom aura bars (called from config color picker)
    ------------------------------------------------------------------------

    function CooldownCompanion:RecolorCustomAuraBar(cabConfig)
        for _, barInfo in ipairs(resourceBarFrames) do
            if barInfo.cabConfig == cabConfig then
                StyleCustomAuraBar(barInfo, cabConfig)
                break
            end
        end
    end



    return {
        UpdateCustomAuraBar = UpdateCustomAuraBar,
        ShouldUpdateHiddenCustomAuraPandemicWake = ShouldUpdateHiddenCustomAuraPandemicWake,
        ClearDeferredCustomAuraWakeRetries = ClearDeferredCustomAuraWakeRetries,
        RefreshEventDrivenCustomAuraBarsForUnit = RefreshEventDrivenCustomAuraBarsForUnit,
        FinalizeAppliedBarVisibility = FinalizeAppliedBarVisibility,
        HideUnusedResourceBarFrames = HideUnusedResourceBarFrames,
        PrepareCustomAuraBar = PrepareCustomAuraBar,
    }
end
