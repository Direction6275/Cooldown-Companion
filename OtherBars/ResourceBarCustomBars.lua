--[[
    CooldownCompanion - ResourceBarCustomBars
    Custom aura bars, spell custom bars, visibility wakeups, styling, and frame preparation.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
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
local StoreOtherBarsVisualState = RB.StoreOtherBarsVisualState
local AreOtherBarsVisualStateCaptureEnabled = RB.AreOtherBarsVisualStateCaptureEnabled

local FormatTime = CooldownCompanion.FormatTime
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec

local function ShouldCaptureOtherBarsVisualState()
    return type(AreOtherBarsVisualStateCaptureEnabled) == "function"
        and AreOtherBarsVisualStateCaptureEnabled() == true
end

local function IsFrameShown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true or false
end

local function StoreCustomBarVisualState(barInfo, details)
    if type(StoreOtherBarsVisualState) ~= "function" or not ShouldCaptureOtherBarsVisualState() then
        return
    end
    if not (barInfo and barInfo.frame) then
        return
    end

    local cabConfig = barInfo.cabConfig
    details = details or {}
    details.rowKind = "custom"
    details.identity = {
        barType = barInfo.barType,
        powerType = barInfo.powerType,
        customBarId = barInfo.customBarId,
    }
    details.visibility = details.visibility or {
        shown = IsFrameShown(barInfo.frame),
        mode = IsFrameShown(barInfo.frame) and "shown" or "hidden",
    }
    if cabConfig then
        details.custom = details.custom or {}
        details.custom.spellID = tonumber(cabConfig.spellID) or cabConfig.spellID
        details.custom.trackingMode = cabConfig.trackingMode
        details.custom.auraTracking = cabConfig.auraTracking == true
        details.custom.hideWhenInactive = cabConfig.hideWhenInactive == true
        details.custom.hideWhileAuraActive = cabConfig.hideWhileAuraActive == true
    end

    StoreOtherBarsVisualState(barInfo.frame, details)
end

local function StoreCustomCooldownVisualState(
    barInfo,
    bar,
    cooldownResult,
    chargeState,
    cooldownActive,
    auraState,
    auraPresent,
    configUnit,
    inPandemic,
    renderAuraState,
    durationObj,
    phase,
    visibilityReason,
    displayMode,
    visibilityOverride
)
    if not ShouldCaptureOtherBarsVisualState() then
        return
    end

    local durationSecret = durationObj and durationObj.HasSecretValues and durationObj:HasSecretValues() or false
    local auraDurationObj = auraState and auraState.durationObj
    local auraDurationSecret = auraDurationObj and auraDurationObj.HasSecretValues and auraDurationObj:HasSecretValues() or false
    StoreCustomBarVisualState(barInfo, {
        phase = phase or "post-dispatch",
        visibility = visibilityOverride or {
            shown = IsFrameShown(bar),
            mode = IsFrameShown(bar) and "shown" or "hidden",
            reason = visibilityReason,
        },
        custom = {
            display = displayMode or (renderAuraState and "aura" or "cooldown"),
            auraPresent = auraPresent == true,
            auraUnit = auraState and auraState.auraUnit or configUnit,
            auraSource = auraState and auraState.viewerFrame and "viewer" or (auraPresent and "player-fallback" or "none"),
            inPandemic = inPandemic == true,
            cooldownActive = cooldownActive == true,
            cooldownState = cooldownResult and cooldownResult.state,
            chargeState = chargeState,
            valuePath = (durationSecret or auraDurationSecret) and "secret-safe" or "plain",
        },
        text = {
            durationShown = bar and bar.text and bar.text:IsShown() == true or false,
            stackShown = bar and bar.stackText and bar.stackText:IsShown() == true or false,
            durationSecret = durationSecret or auraDurationSecret,
        },
        effects = {
            auraActive = bar and bar._auraActive == true or false,
            pandemic = bar and bar._inPandemic == true or false,
            pulse = bar and bar._barPulseActive == true or false,
            colorShift = bar and bar._barColorShiftActive == true or false,
            maxStacksIndicator = barInfo and barInfo._maxStacksIndicator ~= nil or false,
        },
    })
end

function RB.CreateResourceBarCustomBarsModule(deps)
    local resourceBarFrames = deps.resourceBarFrames
    local GetPreviewActive = deps.GetPreviewActive
    local MarkLayoutDirty = deps.MarkLayoutDirty
    local RelayoutResourceStack = deps.RelayoutResourceStack
    local ClearStaleRecycledBarRuntimeState = deps.ClearStaleRecycledBarRuntimeState
    local ClearCustomAuraBarIndicatorState = deps.ClearCustomAuraBarIndicatorState
    local UpdateCustomAuraBarIndicatorVisuals = deps.UpdateCustomAuraBarIndicatorVisuals
    local ApplyCustomAuraBarPreviewState = deps.ApplyCustomAuraBarPreviewState
    local customAuraWakeRetryFrame = nil
    local customAuraWakeRetryQueue = {}
    local customAuraWakeRetryPending = {}
    local processingCustomAuraWakeRetryQueue = false

    ------------------------------------------------------------------------
    -- Update logic: Custom aura bars (aura-based, secret-safe)
    ------------------------------------------------------------------------

    local function ResolveCustomBarPandemicState(frame, configUnit, auraPresent, viewerFrame, pandemicPreview)
        if not frame then
            return false
        end

        if pandemicPreview then
            return true
        end

        if configUnit == "target" and auraPresent and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if frame._pandemicGraceSuppressed then
                frame._pandemicGraceSuppressed = nil
                frame._pandemicGraceStart = nil
            elseif pi and pi:IsVisible() then
                frame._pandemicGraceStart = nil
                return true
            elseif frame._inPandemic then
                local now = GetTime()
                if not frame._pandemicGraceStart then
                    frame._pandemicGraceStart = now
                end
                if now - frame._pandemicGraceStart <= 0.3 then
                    return true
                end
                frame._pandemicGraceStart = nil
            end
        else
            frame._pandemicGraceStart = nil
            frame._pandemicGraceSuppressed = nil
        end

        return false
    end

    local function PeekCustomBarPandemicState(frame, configUnit, auraPresent, viewerFrame, pandemicPreview)
        if not frame then
            return false
        end
        if pandemicPreview then
            return true
        end
        if configUnit == "target" and auraPresent and viewerFrame then
            if frame._pandemicGraceSuppressed then
                return false
            end
            local pi = viewerFrame.PandemicIcon
            if pi and pi:IsVisible() then
                return true
            end
            if frame._inPandemic then
                return true
            end
        end
        return false
    end

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

    local function GetCustomAuraVisibilityReason(cabConfig)
        return cabConfig and cabConfig.hideWhenInactive
            and "hide-when-inactive"
            or "hide-while-aura-active"
    end

    function RB.RequestCustomBarPresentationRefresh()
        if RB.customBarPresentationRefreshPending then
            return
        end

        RB.customBarPresentationRefreshPending = true
        C_Timer.After(0, function()
            RB.customBarPresentationRefreshPending = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
    end

    local CustomAuraBar = {}

    function CustomAuraBar.BuildAuraButtonData(cabConfig)
        local spellID = tonumber(cabConfig and cabConfig.spellID)
        if not spellID or (RB.IsSpellCustomBarConfig and RB.IsSpellCustomBarConfig(cabConfig)) then
            return nil, spellID
        end

        return {
            type = "spell",
            id = spellID,
            auraSpellID = cabConfig.auraSpellID,
            auraTracking = true,
            auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID),
            addedAs = "aura",
        }, spellID
    end

    function CustomAuraBar.GetCandidateIDs(cabConfig)
        local buttonData
        local spellID
        buttonData, spellID = CustomAuraBar.BuildAuraButtonData(cabConfig)
        if buttonData and CooldownCompanion.GetOrderedAuraCandidateIDs then
            local orderedCandidateIDs = CooldownCompanion:GetOrderedAuraCandidateIDs(buttonData)
            if orderedCandidateIDs and #orderedCandidateIDs > 0 then
                return orderedCandidateIDs
            end
        end

        return spellID and { spellID } or nil
    end

    function CustomAuraBar.ViewerFrameHasAuraForUnit(viewerFrame, configUnit)
        local instId = viewerFrame and viewerFrame.auraInstanceID
        if not instId then
            return false
        end

        local viewerUnit = viewerFrame.auraDataUnit or configUnit
        return viewerUnit == configUnit
            and C_UnitAuras.GetAuraDataByAuraInstanceID(viewerUnit, instId) ~= nil
    end

    function CustomAuraBar.ResolveViewerFrame(cabConfig, configUnit)
        local firstTrackedFrame
        local candidateIDs = CustomAuraBar.GetCandidateIDs(cabConfig)
        for _, auraID in ipairs(candidateIDs or {}) do
            local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(auraID)
            if viewerFrame then
                if CustomAuraBar.ViewerFrameHasAuraForUnit(viewerFrame, configUnit) then
                    return viewerFrame
                end
                if not firstTrackedFrame then
                    firstTrackedFrame = viewerFrame
                end
            end
        end

        return firstTrackedFrame
    end

    function CustomAuraBar.ResolvePlayerAuraData(cabConfig)
        local candidateIDs = CustomAuraBar.GetCandidateIDs(cabConfig)
        for _, auraID in ipairs(candidateIDs or {}) do
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraID)
            if auraData then
                return auraData
            end
        end
        return nil
    end

    local function UpdateCustomAuraBar(barInfo)
        local cabConfig = barInfo.cabConfig
        if not cabConfig or not cabConfig.spellID then return end

        -- Read aura data from viewer frame (applications may be secret in combat)
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local auraState = spellAuraStackDisplay and RB.ResolveSpellCustomBarAuraState and RB.ResolveSpellCustomBarAuraState(barInfo) or nil
        local stacks = 0
        local applications = 0
        local auraPresent = false
        local durationObj
        local isActive = cabConfig.trackingMode == "active"
        local useDrain = isActive
        local needsDuration = (useDrain or cabConfig.showDurationText) and not spellAuraStackDisplay
        local bar = barInfo.barType == "custom_continuous" and barInfo.frame or nil
        local auraPreview = bar and bar._barAuraActivePreview
        local pandemicPreview = bar and bar._pandemicPreview
        local indicatorPreview = isActive and (auraPreview or pandemicPreview)
        local configUnit = EnsureCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
        local viewerFrame = CustomAuraBar.ResolveViewerFrame(cabConfig, configUnit)
        local auraUnit = configUnit
        local instId = viewerFrame and viewerFrame.auraInstanceID

        if spellAuraStackDisplay then
            configUnit = (auraState and auraState.configUnit) or configUnit
            viewerFrame = auraState and auraState.viewerFrame or nil
            if auraState and auraState.ready == true and auraState.auraPresent == true and auraState.auraData then
                auraPresent = true
                instId = auraState.auraInstanceID
                auraUnit = auraState.auraUnit or configUnit
                applications = auraState.auraData.applications or 0
                stacks = applications
            end
        elseif instId then
            local viewerUnit = viewerFrame.auraDataUnit or configUnit
            if viewerUnit == configUnit then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(configUnit, instId)
                if auraData then
                    auraPresent = true
                    applications = auraData.applications or 0
                    if isActive then
                        stacks = 1
                    else
                        stacks = applications
                    end
                    if needsDuration then
                        durationObj = C_UnitAuras.GetAuraDuration(configUnit, instId)
                    end
                end
            end
        end

        if not spellAuraStackDisplay and not auraPresent and configUnit == "player" then
            local auraData = CustomAuraBar.ResolvePlayerAuraData(cabConfig)
            if auraData then
                instId = auraData.auraInstanceID
                auraUnit = "player"
                auraPresent = true
                applications = auraData.applications or 0
                if isActive then
                    stacks = 1
                else
                    stacks = applications
                end
                if needsDuration and instId then
                    durationObj = C_UnitAuras.GetAuraDuration("player", instId)
                end
            end
        end

        if spellAuraStackDisplay and not auraPresent and not GetPreviewActive() then
            if CooldownCompanion.UpdateCustomBarSoundAlerts then
                CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, false)
            end
            if ShouldCaptureOtherBarsVisualState() then
                StoreCustomBarVisualState(barInfo, {
                    phase = "hidden",
                    visibility = {
                        shown = IsFrameShown(barInfo.frame),
                        mode = IsFrameShown(barInfo.frame) and "shown" or "hidden",
                        reason = "spell-aura-stack-missing",
                    },
                    custom = {
                        auraPresent = false,
                        auraSource = "spell-stack",
                        ready = false,
                    },
                })
            end
            RB.RequestCustomBarPresentationRefresh()
            return
        end

        local soundAuraActive = auraPresent
        if indicatorPreview and not auraPresent then
            auraPresent = true
            applications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
            stacks = 1
        end

        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, soundAuraActive)
        end

        local pandemicStateFrame = barInfo.frame
        local inPandemic = ResolveCustomBarPandemicState(pandemicStateFrame, configUnit, auraPresent, viewerFrame, pandemicPreview)

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
                if isActive then
                    UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, false)
                end
                if ShouldCaptureOtherBarsVisualState() then
                    StoreCustomBarVisualState(barInfo, {
                        phase = "hidden",
                        visibility = {
                            shown = false,
                            mode = "hidden",
                            reason = cabConfig.hideWhenInactive and "hide-when-inactive" or "hide-while-aura-active",
                        },
                        custom = {
                            auraPresent = auraPresent == true,
                            auraUnit = auraUnit,
                            inPandemic = inPandemic == true,
                            spellAuraStackDisplay = spellAuraStackDisplay == true,
                        },
                    })
                end
                return
            end
        end

        local maxStacks = cabConfig.maxStacks or 1
        local thresholdEnabled = (not spellAuraStackDisplay) and IsCustomAuraMaxThresholdEnabled(cabConfig)

        if barInfo.barType == "custom_continuous" then
            local bar = barInfo.frame
            if useDrain then
                bar:SetMinMaxValues(0, 1)
                if durationObj then
                    bar:SetValue(durationObj:GetRemainingPercent())  -- secret-safe, 1->0 drain
                elseif indicatorPreview then
                    bar:SetValue(CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
                else
                    -- No DurationObject (indefinite aura or aura absent)
                    bar:SetValue(stacks)  -- 1 if active (full), 0 if absent (empty)
                end
            else
                bar:SetMinMaxValues(0, maxStacks)
                bar:SetValue(stacks)  -- SetValue accepts secrets
            end

            if bar.thresholdOverlay then
                if thresholdEnabled then
                    SetCustomAuraMaxThresholdRange(bar.thresholdOverlay, maxStacks)
                    bar.thresholdOverlay:SetValue(stacks)
                    bar.thresholdOverlay:Show()
                else
                    bar.thresholdOverlay:SetValue(0)
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
                        bar.stackText:SetFormattedText("%d", applications)
                    else
                        local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig.stackTextFormat)
                        if stackTextFormat == "current" then
                            bar.stackText:SetFormattedText("%d", stacks)
                        else
                            bar.stackText:SetFormattedText("%d / %d", stacks, maxStacks)
                        end
                    end
                else
                    bar.stackText:SetText("")
                end
            end

            if isActive then
                UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig, auraPresent)
            else
                ClearCustomAuraBarIndicatorState(barInfo, true)
            end

        elseif barInfo.barType == "custom_segmented" then
            local holder = barInfo.frame
            if not holder.segments then return end
            -- Each segment has MinMax(i-1, i) — SetValue(stacks) with C-level clamping
            -- handles fill/empty without comparing the secret stacks value in Lua
            for i = 1, #holder.segments do
                holder.segments[i]:SetValue(stacks)
            end

            if holder.thresholdSegments then
                for i = 1, #holder.thresholdSegments do
                    local thresholdSeg = holder.thresholdSegments[i]
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                        thresholdSeg:SetValue(stacks)
                        thresholdSeg:Show()
                    else
                        thresholdSeg:SetValue(0)
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
                holder.segments[i]:SetValue(stacks)
                holder.overlaySegments[i]:SetValue(stacks)
            end

            if holder.thresholdSegments then
                for i = 1, half do
                    local thresholdSeg = holder.thresholdSegments[i]
                    if thresholdEnabled then
                        SetCustomAuraMaxThresholdRange(thresholdSeg, maxStacks)
                        thresholdSeg:SetValue(stacks)
                        thresholdSeg:Show()
                    else
                        thresholdSeg:SetValue(0)
                        thresholdSeg:Hide()
                    end
                end
            end
        end

        -- Max stacks indicator: SetValue drives visibility via C-level clamping
        if cabConfig.maxStacksGlowEnabled and barInfo._maxStacksIndicator then
            barInfo._maxStacksIndicator:SetValue(auraPresent and applications or 0)
        end
        if ShouldCaptureOtherBarsVisualState() then
            local stackValuesAreSecret = issecretvalue
                and (issecretvalue(stacks) or issecretvalue(applications))
            StoreCustomBarVisualState(barInfo, {
                phase = "post-dispatch",
                custom = {
                    display = barInfo.barType,
                    auraPresent = auraPresent == true,
                    auraUnit = auraUnit,
                    auraSource = viewerFrame and "viewer" or (auraPresent and "player-fallback" or "none"),
                    inPandemic = inPandemic == true,
                    spellAuraStackDisplay = spellAuraStackDisplay == true,
                    valuePath = (stackValuesAreSecret
                        or (durationObj and durationObj.HasSecretValues and durationObj:HasSecretValues())) and "secret-safe" or "plain",
                    maxStacks = maxStacks,
                    thresholdActive = thresholdEnabled == true,
                    stackValue = stackValuesAreSecret and "secret-safe" or (auraPresent and "present" or "none"),
                },
                text = {
                    durationShown = barInfo.frame.text and barInfo.frame.text:IsShown() == true or false,
                    stackShown = barInfo.frame.stackText and barInfo.frame.stackText:IsShown() == true or false,
                    durationSecret = durationObj and durationObj.HasSecretValues and durationObj:HasSecretValues() or false,
                },
                effects = {
                    auraActive = barInfo.frame._auraActive == true,
                    pandemic = barInfo.frame._inPandemic == true,
                    pulse = barInfo.frame._barPulseActive == true,
                    colorShift = barInfo.frame._barColorShiftActive == true,
                    maxStacksIndicator = barInfo._maxStacksIndicator ~= nil,
                },
            })
        end
    end

    local function BuildSpellCustomBarAuraButtonData(cabConfig)
        local spellID = tonumber(cabConfig and cabConfig.spellID)
        if not spellID or not (cabConfig and cabConfig.auraTracking == true) then
            return nil, nil
        end

        return {
            type = "spell",
            id = spellID,
            auraSpellID = cabConfig.auraSpellID,
            auraTracking = true,
            auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID),
        }, spellID
    end

    local function GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
        if not (bar and cabConfig and cabConfig.auraSpellID) then
            return nil, false
        end

        local rawIDs = tostring(cabConfig.auraSpellID)
        if bar._parsedCustomBarAuraIDsRaw == rawIDs
            and bar._parsedCustomBarAuraIDsSpellID == spellID then
            return bar._parsedCustomBarAuraIDs, bar._parsedCustomBarAuraIDsIncludeSpellID == true
        end

        local ids = {}
        local includesSpellID = false
        for id in rawIDs:gmatch("%d+") do
            local numericID = tonumber(id)
            ids[#ids + 1] = numericID
            if numericID == spellID then
                includesSpellID = true
            end
        end

        bar._parsedCustomBarAuraIDs = ids
        bar._parsedCustomBarAuraIDsRaw = rawIDs
        bar._parsedCustomBarAuraIDsSpellID = spellID
        bar._parsedCustomBarAuraIDsIncludeSpellID = includesSpellID or nil
        return ids, includesSpellID
    end

    local function ResolveSpellCustomBarPlayerAuraData(bar, cabConfig, spellID, resolvedAuraSpellID)
        local auraData
        if cabConfig.auraSpellID then
            local ids, includesSpellID = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
            if ids then
                for _, auraID in ipairs(ids) do
                    auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraID)
                    if auraData then
                        return auraData
                    end
                end
            end
            if not includesSpellID then
                local baseID = C_Spell.GetBaseSpell(spellID)
                local fallbackID = baseID and baseID ~= resolvedAuraSpellID and baseID or nil
                return fallbackID and C_UnitAuras.GetPlayerAuraBySpellID(fallbackID) or nil
            end
            return nil
        end

        local baseID = C_Spell.GetBaseSpell(spellID)
        local fallbackID = baseID and baseID ~= resolvedAuraSpellID and baseID or nil
        auraData = fallbackID and C_UnitAuras.GetPlayerAuraBySpellID(fallbackID) or nil
        if auraData then
            return auraData
        end

        return resolvedAuraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(resolvedAuraSpellID) or nil
    end

    local function ViewerFrameHasAuraForUnit(viewerFrame, configUnit)
        local instId = viewerFrame and viewerFrame.auraInstanceID
        if not instId then
            return false
        end

        local viewerUnit = viewerFrame.auraDataUnit or configUnit
        return viewerUnit == configUnit
            and C_UnitAuras.GetAuraDataByAuraInstanceID(viewerUnit, instId) ~= nil
    end

    local function ResolveSpellCustomBarAuraViewerFrame(bar, cabConfig, spellID, buttonData, configUnit)
        if cabConfig and cabConfig.auraSpellID then
            local ids = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
            local firstTrackedFrame
            if ids then
                for _, auraID in ipairs(ids) do
                    local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(auraID)
                    if viewerFrame then
                        if ViewerFrameHasAuraForUnit(viewerFrame, configUnit) then
                            return viewerFrame
                        end
                        if not firstTrackedFrame then
                            firstTrackedFrame = viewerFrame
                        end
                    end
                end
            end
            if firstTrackedFrame then
                return firstTrackedFrame
            end
        end

        return CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
    end

    local function SpellCustomBarAuraDataMatches(bar, cabConfig, spellID, resolvedAuraSpellID, auraData)
        local auraSpellID = auraData and auraData.spellId
        if not auraSpellID or (issecretvalue and issecretvalue(auraSpellID)) then
            return false
        end

        if cabConfig and cabConfig.auraSpellID then
            local ids = GetSpellCustomBarParsedAuraIDs(bar, cabConfig, spellID)
            if ids then
                for _, auraID in ipairs(ids) do
                    if auraSpellID == auraID then
                        return true
                    end
                end
            end
        end

        local baseID = C_Spell.GetBaseSpell(spellID)
        return auraSpellID == resolvedAuraSpellID
            or auraSpellID == spellID
            or (baseID and auraSpellID == baseID)
    end

    function RB.ResolveSpellCustomBarAuraState(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        local buttonData, spellID = BuildSpellCustomBarAuraButtonData(cabConfig)
        if not (buttonData and spellID and bar) then
            return nil
        end

        local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
        local configUnit = buttonData.auraUnit or "player"
        local viewerFrame = ResolveSpellCustomBarAuraViewerFrame(bar, cabConfig, spellID, buttonData, configUnit)
        if not CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame) then
            return {
                ready = false,
                auraPresent = false,
                configUnit = configUnit,
                viewerFrame = viewerFrame,
            }
        end

        local resolvedAuraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
        local auraData
        local durationObj
        local auraUnit = configUnit
        local instId = viewerFrame and viewerFrame.auraInstanceID

        if instId and (configUnit == "player" or configUnit == "target") then
            local viewerUnit = viewerFrame.auraDataUnit or configUnit
            if viewerUnit == configUnit then
                auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(viewerUnit, instId)
                if auraData then
                    durationObj = C_UnitAuras.GetAuraDuration(viewerUnit, instId)
                    if durationObj then
                        auraUnit = viewerUnit
                    end
                end
            end
        end

        if not (auraData and durationObj) and configUnit == "player" then
            auraData = ResolveSpellCustomBarPlayerAuraData(bar, cabConfig, spellID, resolvedAuraSpellID)
            instId = auraData and auraData.auraInstanceID or nil
            if instId and not issecretvalue(instId) then
                durationObj = C_UnitAuras.GetAuraDuration("player", instId)
                auraUnit = "player"
            end
        end

        if not (auraData and durationObj) and configUnit == "player" and bar._auraInstanceID then
            local cachedUnit = bar._auraUnit or configUnit
            if cachedUnit == configUnit then
                auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, bar._auraInstanceID)
                if SpellCustomBarAuraDataMatches(bar, cabConfig, spellID, resolvedAuraSpellID, auraData) then
                    durationObj = C_UnitAuras.GetAuraDuration(cachedUnit, bar._auraInstanceID)
                    instId = bar._auraInstanceID
                    auraUnit = cachedUnit
                end
            end
        end

        if not auraData then
            return {
                ready = true,
                auraPresent = false,
                configUnit = configUnit,
                viewerFrame = viewerFrame,
            }
        end

        return {
            ready = true,
            auraPresent = true,
            auraData = auraData,
            auraInstanceID = instId,
            auraUnit = auraUnit,
            configUnit = configUnit,
            viewerFrame = viewerFrame,
            durationObj = durationObj,
        }
    end

    local function ClearSpellCustomBarAuraRuntimeState(barInfo)
        ClearCustomAuraBarIndicatorState(barInfo, false)
    end

    local function UpdateSpellCustomBarChargeText(bar, cooldownResult)
        if not (bar and bar.stackText and bar.stackText:IsShown()) then
            return
        end

        local currentCharges = cooldownResult and cooldownResult.currentCharges
        local maxCharges = cooldownResult and cooldownResult.maxCharges
        if currentCharges and maxCharges and maxCharges > 1 then
            bar.stackText:SetFormattedText("%d / %d", currentCharges, maxCharges)
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

        local stackTextFormat = NormalizeCustomAuraStackTextFormat(cabConfig and cabConfig.stackTextFormat)
        if stackTextFormat == "current" then
            bar.stackText:SetFormattedText("%d", stacks)
        else
            bar.stackText:SetFormattedText("%d / %d", stacks, maxStacks)
        end
    end

    function RB.UpdateCustomCooldownBar(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        if not (cabConfig and cabConfig.spellID and bar) then return end

        local cooldownResult = CooldownCompanion.EvaluateSpellCooldownStateForCustomBar
            and CooldownCompanion:EvaluateSpellCooldownStateForCustomBar(cabConfig)
        local durationObj = cooldownResult and cooldownResult.renderDurationObj
        local cooldownActive = cooldownResult
            and cooldownResult.state == ST.CooldownLogic.STATE_COOLDOWN
        local auraState = RB.ResolveSpellCustomBarAuraState(barInfo)
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
        local inPandemic = ResolveCustomBarPandemicState(
            bar,
            configUnit,
            auraPresent,
            auraState and auraState.viewerFrame,
            pandemicPreview
        )

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
                ClearSpellCustomBarAuraRuntimeState(barInfo)
                UpdateSpellCustomBarSounds(auraPresent)
                StoreCustomCooldownVisualState(barInfo, bar, cooldownResult, chargeState, cooldownActive, auraState, auraPresent, configUnit, inPandemic, renderAuraState, durationObj, "hidden", cabConfig.hideWhenInactive and "hide-when-inactive" or "hide-while-aura-active", "hidden")
                return
            end
        elseif (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive)
            and not bar:IsShown() then
            bar:Show()
            MarkLayoutDirty()
        end

        if spellAuraStackDisplay and auraPresent then
            UpdateSpellCustomBarSounds(true)
            StoreCustomCooldownVisualState(barInfo, bar, cooldownResult, chargeState, cooldownActive, auraState, auraPresent, configUnit, inPandemic, renderAuraState, durationObj, "post-dispatch", "spell-aura-stack-display", "aura-stack")
            RB.RequestCustomBarPresentationRefresh()
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
            bar:SetMinMaxValues(0, 1)
            if auraDurationObj then
                bar:SetValue(auraDurationObj:GetRemainingPercent())
            elseif auraPreview or pandemicPreview then
                bar:SetValue(CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL)
            else
                bar:SetValue(1)
            end

            if bar.thresholdOverlay then
                bar.thresholdOverlay:SetValue(0)
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
                barInfo._maxStacksIndicator:SetValue(0)
            end

            UpdateSpellCustomBarSounds(auraPresent)
            StoreCustomCooldownVisualState(barInfo, bar, cooldownResult, chargeState, cooldownActive, auraState, auraPresent, configUnit, inPandemic, renderAuraState, durationObj, "post-dispatch", nil, "aura")
            return
        end

        ClearSpellCustomBarAuraRuntimeState(barInfo)

        bar:SetMinMaxValues(0, 1)
        bar:SetStatusBarColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] ~= nil and fillColor[4] or 1)
        if cooldownActive and durationObj then
            bar:SetValue(durationObj:GetElapsedPercent())
        elseif cooldownActive then
            bar:SetValue(0)
        else
            bar:SetValue(1)
        end

        if bar.thresholdOverlay then
            bar.thresholdOverlay:SetValue(0)
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
            barInfo._maxStacksIndicator:SetValue(0)
        end

        UpdateSpellCustomBarSounds(false)
        StoreCustomCooldownVisualState(barInfo, bar, cooldownResult, chargeState, cooldownActive, auraState, auraPresent, configUnit, inPandemic, renderAuraState, durationObj, "post-dispatch", nil, "cooldown")
    end

    local function CaptureCurrentCustomAuraVisualState(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local frame = barInfo and barInfo.frame
        if not (cabConfig and cabConfig.spellID and frame) then
            return false
        end

        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local auraState = spellAuraStackDisplay and RB.ResolveSpellCustomBarAuraState and RB.ResolveSpellCustomBarAuraState(barInfo) or nil
        local stacks = 0
        local applications = 0
        local auraPresent = false
        local durationObj
        local isActive = cabConfig.trackingMode == "active"
        local useDrain = isActive
        local needsDuration = (useDrain or cabConfig.showDurationText) and not spellAuraStackDisplay
        local bar = barInfo.barType == "custom_continuous" and frame or nil
        local auraPreview = bar and bar._barAuraActivePreview
        local pandemicPreview = bar and bar._pandemicPreview
        local indicatorPreview = isActive and (auraPreview or pandemicPreview)
        local configUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
        local viewerFrame = CustomAuraBar.ResolveViewerFrame(cabConfig, configUnit)
        local auraUnit = configUnit
        local instId = viewerFrame and viewerFrame.auraInstanceID

        if spellAuraStackDisplay then
            configUnit = (auraState and auraState.configUnit) or configUnit
            viewerFrame = auraState and auraState.viewerFrame or nil
            if auraState and auraState.ready == true and auraState.auraPresent == true and auraState.auraData then
                auraPresent = true
                instId = auraState.auraInstanceID
                auraUnit = auraState.auraUnit or configUnit
                applications = auraState.auraData.applications or 0
                stacks = applications
            end
        elseif instId then
            local viewerUnit = viewerFrame.auraDataUnit or configUnit
            if viewerUnit == configUnit then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(configUnit, instId)
                if auraData then
                    auraPresent = true
                    applications = auraData.applications or 0
                    stacks = isActive and 1 or applications
                    auraUnit = configUnit
                    if needsDuration then
                        durationObj = C_UnitAuras.GetAuraDuration(configUnit, instId)
                    end
                end
            end
        end

        if not spellAuraStackDisplay and not auraPresent and configUnit == "player" then
            local auraData = CustomAuraBar.ResolvePlayerAuraData(cabConfig)
            if auraData then
                instId = auraData.auraInstanceID
                auraUnit = "player"
                auraPresent = true
                applications = auraData.applications or 0
                stacks = isActive and 1 or applications
                if needsDuration and instId then
                    durationObj = C_UnitAuras.GetAuraDuration("player", instId)
                end
            end
        end

        if spellAuraStackDisplay and not auraPresent and not GetPreviewActive() then
            local shown = IsFrameShown(frame)
            StoreCustomBarVisualState(barInfo, {
                phase = "hidden",
                visibility = {
                    shown = shown,
                    mode = shown and "shown" or "hidden",
                    reason = "spell-aura-stack-missing",
                },
                custom = {
                    display = barInfo.barType,
                    auraPresent = false,
                    auraSource = "spell-stack",
                    ready = false,
                },
            })
            return true
        end

        if indicatorPreview and not auraPresent then
            auraPresent = true
            applications = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS
            stacks = 1
        end

        local inPandemic = PeekCustomBarPandemicState(frame, configUnit, auraPresent, viewerFrame, pandemicPreview)
        local shouldShow, hasVisibilityRule = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
        if spellAuraStackDisplay and auraState and auraState.ready ~= true then
            hasVisibilityRule = false
            shouldShow = true
        end

        local visibilityReason = nil
        if hasVisibilityRule and not shouldShow then
            visibilityReason = GetCustomAuraVisibilityReason(cabConfig)
        end

        local maxStacks = cabConfig.maxStacks or 1
        local thresholdEnabled = (not spellAuraStackDisplay) and IsCustomAuraMaxThresholdEnabled(cabConfig)
        local stackValuesAreSecret = issecretvalue
            and (issecretvalue(stacks) or issecretvalue(applications))
        local durationSecret = durationObj and durationObj.HasSecretValues and durationObj:HasSecretValues() or false
        StoreCustomBarVisualState(barInfo, {
            phase = shouldShow and "post-dispatch" or "hidden",
            visibility = {
                shown = shouldShow == true,
                mode = shouldShow and "shown" or "hidden",
                reason = visibilityReason,
            },
            custom = {
                display = barInfo.barType,
                auraPresent = auraPresent == true,
                auraUnit = auraUnit,
                auraSource = viewerFrame and "viewer" or (auraPresent and "player-fallback" or "none"),
                inPandemic = inPandemic == true,
                spellAuraStackDisplay = spellAuraStackDisplay == true,
                valuePath = (stackValuesAreSecret or durationSecret) and "secret-safe" or "plain",
                maxStacks = maxStacks,
                thresholdActive = thresholdEnabled == true,
                stackValue = stackValuesAreSecret and "secret-safe" or (auraPresent and "present" or "none"),
            },
            text = {
                durationShown = frame.text and frame.text:IsShown() == true or false,
                stackShown = frame.stackText and frame.stackText:IsShown() == true or false,
                durationSecret = durationSecret,
            },
            effects = {
                auraActive = frame._auraActive == true,
                pandemic = frame._inPandemic == true,
                pulse = frame._barPulseActive == true,
                colorShift = frame._barColorShiftActive == true,
                maxStacksIndicator = barInfo._maxStacksIndicator ~= nil,
            },
        })
        return true
    end

    local function CaptureCurrentCustomCooldownVisualState(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        if not (cabConfig and cabConfig.spellID and bar) then
            return false
        end

        local cooldownResult = CooldownCompanion.EvaluateSpellCooldownStateForCustomBar
            and CooldownCompanion:EvaluateSpellCooldownStateForCustomBar(cabConfig)
        local durationObj = cooldownResult and cooldownResult.renderDurationObj
        local cooldownActive = cooldownResult
            and cooldownResult.state == ST.CooldownLogic.STATE_COOLDOWN
        local auraState = RB.ResolveSpellCustomBarAuraState(barInfo)
        local auraPresent = auraState and auraState.ready == true and auraState.auraPresent == true
        local auraPreview = bar._barAuraActivePreview == true
        local pandemicPreview = bar._pandemicPreview == true
        local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
        local renderAuraState = cabConfig.auraTracking == true
            and not spellAuraStackDisplay
            and (auraPresent or auraPreview or pandemicPreview)
        local chargeState = cooldownResult and cooldownResult.chargeState
        local configUnit = (auraState and auraState.configUnit)
            or GetResolvedCustomAuraBarAuraUnit(cabConfig, cabConfig.spellID)
        local inPandemic = PeekCustomBarPandemicState(
            bar,
            configUnit,
            auraPresent,
            auraState and auraState.viewerFrame,
            pandemicPreview
        )
        local shouldShow = IsFrameShown(bar)
        local visibilityReason = nil

        if auraState
            and auraState.ready == true
            and (cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive) then
            shouldShow = ResolveCustomAuraVisibility(cabConfig, auraPresent, inPandemic, auraPreview, pandemicPreview)
            if not shouldShow then
                visibilityReason = GetCustomAuraVisibilityReason(cabConfig)
            end
        elseif cabConfig.hideWhenInactive or cabConfig.hideWhileAuraActive then
            shouldShow = true
        end

        local displayMode = "cooldown"
        if not shouldShow then
            displayMode = "hidden"
        elseif spellAuraStackDisplay and auraPresent then
            displayMode = "aura-stack"
            visibilityReason = "spell-aura-stack-display"
        elseif renderAuraState then
            displayMode = "aura"
        end

        StoreCustomCooldownVisualState(
            barInfo,
            bar,
            cooldownResult,
            chargeState,
            cooldownActive,
            auraState,
            auraPresent,
            configUnit,
            inPandemic,
            renderAuraState,
            durationObj,
            shouldShow and "post-dispatch" or "hidden",
            visibilityReason,
            displayMode,
            {
                shown = shouldShow == true,
                mode = shouldShow and "shown" or "hidden",
                reason = visibilityReason,
            }
        )
        return true
    end

    local function CaptureCustomBarVisualState(barInfo)
        if not ShouldCaptureOtherBarsVisualState() then
            return false
        end
        if not (barInfo and barInfo.frame and barInfo.cabConfig) then
            return false
        end
        if barInfo.barType == "custom_cooldown" then
            return CaptureCurrentCustomCooldownVisualState(barInfo)
        elseif barInfo.barType == "custom_continuous"
            or barInfo.barType == "custom_segmented"
            or barInfo.barType == "custom_overlay" then
            return CaptureCurrentCustomAuraVisualState(barInfo)
        end
        return false
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

    local function StopDeferredCustomAuraWakeRetryFrame()
        if customAuraWakeRetryFrame then
            customAuraWakeRetryFrame:SetScript("OnUpdate", nil)
        end
    end

    local function ClearDeferredCustomAuraWakeRetries()
        wipe(customAuraWakeRetryQueue)
        wipe(customAuraWakeRetryPending)
        processingCustomAuraWakeRetryQueue = false
        StopDeferredCustomAuraWakeRetryFrame()
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
        if processingCustomAuraWakeRetryQueue then return end
        if #customAuraWakeRetryQueue == 0 then
            StopDeferredCustomAuraWakeRetryFrame()
            return
        end

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
        StopDeferredCustomAuraWakeRetryFrame()

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

        if not customAuraWakeRetryFrame then
            customAuraWakeRetryFrame = CreateFrame("Frame")
        end
        customAuraWakeRetryFrame:SetScript("OnUpdate", function(self, _elapsed)
            self:SetScript("OnUpdate", nil)
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

    local function FinalizeAppliedBarVisibility(barInfo, powerType, previewActive)
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
            local auraState = RB.ResolveSpellCustomBarAuraState and RB.ResolveSpellCustomBarAuraState(barInfo) or nil
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
                bar:SetMinMaxValues(0, maxStacks)
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
            local durationTextOutline = cabConfig.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
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
            local stackTextOutline = cabConfig.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE
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
    RB.StyleCustomAuraBar = StyleCustomAuraBar

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
        CaptureCustomBarVisualState = CaptureCustomBarVisualState,
    }
end
