--[[
    CooldownCompanion - Core/EntryRuntime
    Shared cooldown/aura runtime helpers for display entries.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local IsNoCooldownSpell = ST.IsNoCooldownSpell
local HasPositiveResourceGateCost = ST.HasPositiveResourceGateCost
local IsDistinctAuraViewerFrameForSpell = ST.IsDistinctAuraViewerFrameForSpell
local ResolveCDMAuraSpellID = ST.ResolveCDMAuraSpellID

local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local wipe = wipe
local issecretvalue = issecretvalue
local GetTime = GetTime

local COOLDOWN_STATE_READY = CooldownLogic.STATE_READY
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO
local TARGET_SWITCH_SAFETY_CAP = 0.60

local EntryRuntime = ST.EntryRuntime or {}
ST.EntryRuntime = EntryRuntime

-- Hidden scratch CooldownFrame for probing DurationObject activity.
-- DurationObject:IsZero() returns a secret boolean in tainted contexts;
-- feeding the object to a Cooldown widget and checking IsShown() yields a
-- plain boolean safe for Lua logic.
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

local function DurationObjectShowsCooldown(durationObj)
    if not durationObj then return false end
    scratchCooldown:SetCooldownFromDurationObject(durationObj)
    local shown = scratchCooldown:IsShown()
    scratchCooldown:SetCooldown(0, 0)
    return shown
end
EntryRuntime.DurationObjectShowsCooldown = DurationObjectShowsCooldown

local function SetAuraStackCountText(fontString, value, maxStacks, stackTextFormat)
    if not fontString then return end
    if value == nil then
        fontString:SetText("")
        return
    end

    local displayValue = value
    if not issecretvalue(value) then
        displayValue = tonumber(value)
        if not displayValue then
            fontString:SetText(value or "")
            return
        end
    end

    if stackTextFormat == "current_max" then
        fontString:SetFormattedText("%d / %d", displayValue, maxStacks or 1)
    else
        fontString:SetFormattedText("%d", displayValue)
    end
end
EntryRuntime.SetAuraStackCountText = SetAuraStackCountText

local function GetConfiguredAuraUnit(buttonData)
    return buttonData.auraUnit or "player"
end

local function ViewerFrameHasActiveAuraInstance(viewerFrame, configUnit, auraUnit, allowDurationlessAuraInstance)
    local unit = viewerFrame.auraDataUnit or auraUnit
    if not (viewerFrame.auraInstanceID and unit == configUnit) then
        return false
    end

    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, viewerFrame.auraInstanceID)
    if not auraData then
        return false
    end

    return allowDurationlessAuraInstance or C_UnitAuras.GetAuraDuration(unit, viewerFrame.auraInstanceID) ~= nil
end

local function ViewerFrameHasActiveCooldownWidget(viewerFrame, configUnit, auraUnit, now)
    local viewerCooldown = viewerFrame.Cooldown
    if not (viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown()) then
        return false
    end

    local vUnit = viewerFrame.auraDataUnit or auraUnit
    if vUnit ~= configUnit then
        return false
    end

    local startMs, durMs = viewerCooldown:GetCooldownTimes()
    if issecretvalue(startMs) or issecretvalue(durMs) then
        return true
    end
    if not startMs or not durMs then
        return false
    end

    return durMs > 0 and (startMs + durMs) > now * 1000
end

local function ViewerFrameHasActiveTotemDuration(viewerFrame)
    local totemSlot = viewerFrame.preferredTotemUpdateSlot
    if not (totemSlot and viewerFrame:IsVisible() and viewerFrame.totemData) then
        return false
    end

    return DurationObjectShowsCooldown(GetTotemDuration(totemSlot))
end

local function ViewerFrameHasActiveAuraProof(viewerFrame, configUnit, auraUnit, now, allowDurationlessAuraInstance)
    return ViewerFrameHasActiveAuraInstance(viewerFrame, configUnit, auraUnit, allowDurationlessAuraInstance)
        or ViewerFrameHasActiveCooldownWidget(viewerFrame, configUnit, auraUnit, now)
        or ViewerFrameHasActiveTotemDuration(viewerFrame)
end

local function GetParsedAuraIDs(owner, buttonData)
    if not (owner and buttonData and buttonData.auraSpellID) then
        return nil, false
    end

    local rawIDs = buttonData.auraSpellID
    if not owner._parsedAuraIDs
        or owner._parsedAuraIDsRaw ~= rawIDs
        or owner._parsedAuraIDsButtonID ~= buttonData.id then
        local ids = {}
        owner._parsedAuraIDsIncludeButtonID = nil
        for id in tostring(rawIDs):gmatch("%d+") do
            local spellID = tonumber(id)
            ids[#ids + 1] = spellID
            if spellID == buttonData.id then
                owner._parsedAuraIDsIncludeButtonID = true
            end
        end
        owner._parsedAuraIDs = ids
        owner._parsedAuraIDsRaw = rawIDs
        owner._parsedAuraIDsButtonID = buttonData.id
    end

    return owner._parsedAuraIDs, owner._parsedAuraIDsIncludeButtonID == true
end

local function ButtonExplicitlyTracksViewerAura(buttonData, viewerFrame)
    if not (buttonData and buttonData.auraSpellID and viewerFrame) then
        return false
    end

    local auraID = ResolveCDMAuraSpellID and ResolveCDMAuraSpellID(viewerFrame.cooldownInfo)
    if not auraID then
        return false
    end

    for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
        if tonumber(id) == auraID then
            return true
        end
    end
    return false
end

local function ResolveAllowedBuffViewerFrameForSpell(buttonData, spellID)
    local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(spellID)
    if viewerFrame
        and IsDistinctAuraViewerFrameForSpell
        and IsDistinctAuraViewerFrameForSpell(buttonData, viewerFrame)
        and not ButtonExplicitlyTracksViewerAura(buttonData, viewerFrame) then
        return nil
    end
    return viewerFrame
end

local function ResolveAllowedButtonAuraViewerFrame(buttonData)
    local viewerFrame = CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
    if viewerFrame
        and IsDistinctAuraViewerFrameForSpell
        and IsDistinctAuraViewerFrameForSpell(buttonData, viewerFrame)
        and not ButtonExplicitlyTracksViewerAura(buttonData, viewerFrame) then
        return nil
    end
    return viewerFrame
end

local function ResolvePreferredAuraViewerFrame(buttonData, candidateIDs, configUnit, auraUnit, now, allowDurationlessAuraInstance)
    local firstTrackedFrame
    for _, spellID in ipairs(candidateIDs or {}) do
        local viewerFrame = ResolveAllowedBuffViewerFrameForSpell(buttonData, spellID)
        if viewerFrame then
            if ViewerFrameHasActiveAuraProof(viewerFrame, configUnit, auraUnit, now, allowDurationlessAuraInstance) then
                return viewerFrame, firstTrackedFrame
            end
            firstTrackedFrame = firstTrackedFrame or viewerFrame
        end
    end
    return nil, firstTrackedFrame
end

local function ResolveTrackedAuraViewerFrame(owner, buttonData, auraSpellID, configUnit, auraUnit, now, allowDurationlessAuraInstance, useButtonAuraViewerFallback)
    local viewerFrame
    local cdmEnabled
    if CooldownCompanion._cooldownUpdatePassActive then
        cdmEnabled = CooldownCompanion._cdmViewerEnabled == true
    else
        cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    end

    local orderedStandaloneAuraIDs
    local standaloneOriginalAuraIDs
    local standaloneFallbackAuraIDs
    if buttonData.addedAs == "aura" then
        if not owner._orderedStandaloneAuraIDs
            or owner._orderedStandaloneAuraIDsRaw ~= buttonData.auraSpellID
            or owner._orderedStandaloneAuraIDsButtonID ~= buttonData.id
            or owner._orderedStandaloneAuraIDsAuraSpellID ~= auraSpellID then
            local originalAuraIDs, fallbackAuraIDs = CooldownCompanion:GetStandaloneAuraCandidateGroups(buttonData)
            local allAuraIDs = {}
            for _, spellID in ipairs(originalAuraIDs) do
                allAuraIDs[#allAuraIDs + 1] = spellID
            end
            for _, spellID in ipairs(fallbackAuraIDs) do
                allAuraIDs[#allAuraIDs + 1] = spellID
            end
            owner._standaloneOriginalAuraIDs = originalAuraIDs
            owner._standaloneFallbackAuraIDs = fallbackAuraIDs
            owner._orderedStandaloneAuraIDs = allAuraIDs
            owner._orderedStandaloneAuraIDsRaw = buttonData.auraSpellID
            owner._orderedStandaloneAuraIDsButtonID = buttonData.id
            owner._orderedStandaloneAuraIDsAuraSpellID = auraSpellID
        end
        orderedStandaloneAuraIDs = owner._orderedStandaloneAuraIDs
        standaloneOriginalAuraIDs = owner._standaloneOriginalAuraIDs
        standaloneFallbackAuraIDs = owner._standaloneFallbackAuraIDs
    end

    if buttonData.cdmChildSlot then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        if allChildren then
            viewerFrame = allChildren[buttonData.cdmChildSlot]
        end
    end

    if not viewerFrame and orderedStandaloneAuraIDs then
        local originalActiveFrame, firstOriginalFrame = ResolvePreferredAuraViewerFrame(
            buttonData,
            standaloneOriginalAuraIDs,
            configUnit,
            auraUnit,
            now,
            allowDurationlessAuraInstance
        )
        viewerFrame = originalActiveFrame
        if not viewerFrame then
            local fallbackActiveFrame, firstFallbackFrame = ResolvePreferredAuraViewerFrame(
                buttonData,
                standaloneFallbackAuraIDs,
                configUnit,
                auraUnit,
                now,
                allowDurationlessAuraInstance
            )
            viewerFrame = fallbackActiveFrame or firstOriginalFrame or firstFallbackFrame
        end
    elseif not viewerFrame and buttonData.auraSpellID then
        local ids = GetParsedAuraIDs(owner, buttonData)
        local activeFrame, firstTrackedFrame = ResolvePreferredAuraViewerFrame(
            buttonData,
            ids,
            configUnit,
            auraUnit,
            now,
            allowDurationlessAuraInstance
        )
        viewerFrame = activeFrame or firstTrackedFrame
    end

    if not viewerFrame then
        viewerFrame = ResolveAllowedBuffViewerFrameForSpell(buttonData, auraSpellID)
        if not viewerFrame then
            viewerFrame = ResolveAllowedBuffViewerFrameForSpell(buttonData, buttonData.id)
                or (owner._displaySpellId and ResolveAllowedBuffViewerFrameForSpell(buttonData, owner._displaySpellId))
            if not viewerFrame then
                local baseId = C_Spell.GetBaseSpell(buttonData.id)
                if baseId and baseId ~= buttonData.id and baseId ~= auraSpellID then
                    viewerFrame = ResolveAllowedBuffViewerFrameForSpell(buttonData, baseId)
                end
            end
        end
    end
    if not viewerFrame and useButtonAuraViewerFallback then
        viewerFrame = ResolveAllowedButtonAuraViewerFrame(buttonData)
    end

    return viewerFrame, cdmEnabled, orderedStandaloneAuraIDs
end
local function ResolvePlayerAuraData(owner, buttonData, auraSpellID, orderedStandaloneAuraIDs)
    local auraData
    local activeAuraSpellID
    local activeAuraSpellIDFromFallback

    if orderedStandaloneAuraIDs then
        for _, spellID in ipairs(orderedStandaloneAuraIDs) do
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if auraData then
                activeAuraSpellID = spellID
                activeAuraSpellIDFromFallback = true
                break
            end
        end
    elseif buttonData.auraSpellID then
        local ids, includesButtonID = GetParsedAuraIDs(owner, buttonData)
        for _, spellID in ipairs(ids) do
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if auraData then
                activeAuraSpellID = spellID
                activeAuraSpellIDFromFallback = true
                break
            end
        end
        if not auraData and not includesButtonID then
            local baseId = C_Spell.GetBaseSpell(buttonData.id)
            local fallbackId = baseId and baseId ~= auraSpellID and baseId or nil
            auraData = fallbackId and C_UnitAuras.GetPlayerAuraBySpellID(fallbackId)
            if auraData then
                activeAuraSpellID = fallbackId
                activeAuraSpellIDFromFallback = true
            end
        end
    else
        local baseId = C_Spell.GetBaseSpell(buttonData.id)
        local fallbackId = baseId and baseId ~= auraSpellID and baseId or nil
        auraData = fallbackId and C_UnitAuras.GetPlayerAuraBySpellID(fallbackId)
        if auraData then
            activeAuraSpellID = fallbackId
            activeAuraSpellIDFromFallback = true
        end
        if not auraData then
            auraData = C_UnitAuras.GetPlayerAuraBySpellID(auraSpellID)
            if auraData then
                activeAuraSpellID = auraSpellID
                activeAuraSpellIDFromFallback = true
            end
        end
    end

    return auraData, activeAuraSpellID, activeAuraSpellIDFromFallback
end

local function GetReadableAuraSpellID(auraData)
    local spellID = auraData and auraData.spellId
    if spellID and not issecretvalue(spellID) then
        return spellID
    end
    return nil
end

local function ResolveAuraIconState(auraData)
    if not auraData then
        return nil, false, false
    end

    local icon = auraData.icon
    if issecretvalue(icon) then
        return icon, true, true
    end

    return icon, icon ~= nil, true
end

local function AuraDataMatchesTrackedSpell(owner, buttonData, auraSpellID, auraData)
    local auraDataSpellID = auraData and auraData.spellId
    if not auraDataSpellID or issecretvalue(auraDataSpellID) then
        return false
    end

    if buttonData and buttonData.auraSpellID then
        local ids = GetParsedAuraIDs(owner, buttonData)
        for _, spellID in ipairs(ids or {}) do
            if auraDataSpellID == spellID then
                return true
            end
        end
    end

    local buttonSpellID = buttonData and buttonData.id
    local baseID = buttonSpellID and C_Spell.GetBaseSpell(buttonSpellID)
    return auraDataSpellID == auraSpellID
        or auraDataSpellID == buttonSpellID
        or (baseID and auraDataSpellID == baseID)
end
EntryRuntime.AuraDataMatchesTrackedSpell = AuraDataMatchesTrackedSpell

local function GetReadableAuraTiming(auraData)
    local auraDataSecret = issecretvalue(auraData)
    if auraDataSecret or auraData == nil then
        return nil, nil, false
    end

    local expirationTime = auraData.expirationTime
    local duration = auraData.duration
    local expirationSecret = issecretvalue(expirationTime)
    local durationSecret = issecretvalue(duration)
    if expirationSecret or durationSecret then
        return nil, nil, false
    end
    if expirationTime == nil or duration == nil then
        return nil, nil, false
    end

    return expirationTime, duration, true
end

local function ClearAcceptedPandemicRange(owner)
    if not owner then return end

    owner._pandemicLatchUnit = nil
    owner._pandemicLatchAuraInstanceID = nil
    owner._pandemicLatchStart = nil
    owner._pandemicLatchEnd = nil
    owner._pandemicLatchAuraExpirationTime = nil
    owner._pandemicLatchAuraDuration = nil
end

local function ClearAuraPandemicRuntimeState(owner)
    if not owner then return end

    owner._pandemicGraceStart = nil
    owner._pandemicGraceSuppressed = nil
    owner._pandemicDirtyUnit = nil
    owner._pandemicDirtyAuraInstanceID = nil
    ClearAcceptedPandemicRange(owner)
    owner._pandemicSuppressedUnit = nil
    owner._pandemicSuppressedAuraInstanceID = nil
    owner._pandemicSuppressedStart = nil
    owner._pandemicSuppressedEnd = nil
end
EntryRuntime.ClearAuraPandemicRuntimeState = ClearAuraPandemicRuntimeState

local function ClearAuraPandemicDirtyState(owner)
    if not owner then return end

    owner._pandemicDirtyUnit = nil
    owner._pandemicDirtyAuraInstanceID = nil
end

function EntryRuntime.MarkAuraPandemicStateDirty(owner, unit, auraInstanceID)
    if not owner then return end

    owner._pandemicDirtyUnit = unit
    owner._pandemicDirtyAuraInstanceID = auraInstanceID
end

local function GetReadablePandemicRange(viewerFrame)
    if not viewerFrame then
        return nil, nil, false
    end

    local startTime = viewerFrame.pandemicStartTime
    local endTime = viewerFrame.pandemicEndTime
    local startSecret = issecretvalue(startTime)
    local endSecret = issecretvalue(endTime)
    if startSecret or endSecret then
        return nil, nil, false
    end
    if startTime == nil or endTime == nil then
        return nil, nil, false
    end

    return startTime, endTime, true
end

local function GetPandemicAuraIdentity(owner, options)
    local auraState = options and options.auraState
    local auraUnit = options and options.auraUnit
    if auraUnit == nil and auraState then
        auraUnit = auraState.auraUnit
    end
    if auraUnit == nil and owner then
        auraUnit = owner._auraUnit
    end

    local auraInstanceID = options and options.auraInstanceID
    if auraInstanceID == nil and auraState then
        auraInstanceID = auraState.auraInstanceID
    end
    if auraInstanceID == nil and owner then
        auraInstanceID = owner._auraInstanceID
    end

    return auraUnit, auraInstanceID
end

local function GetPandemicAuraTiming(options)
    local auraState = options and options.auraState
    local auraData = options and options.auraData
    local auraDataSecret = issecretvalue(auraData)
    if auraDataSecret then
        auraData = nil
    elseif auraData == nil and auraState then
        auraData = auraState.auraData
    end

    local expirationTime = options and options.auraExpirationTime
    local expirationSecret = issecretvalue(expirationTime)
    if expirationSecret then
        expirationTime = nil
    elseif expirationTime == nil and auraState then
        expirationTime = auraState.auraExpirationTime
    end
    local duration = options and options.auraDuration
    local durationSecret = issecretvalue(duration)
    if durationSecret then
        duration = nil
    elseif duration == nil and auraState then
        duration = auraState.auraDuration
    end

    expirationSecret = issecretvalue(expirationTime)
    durationSecret = issecretvalue(duration)
    if not expirationSecret and not durationSecret and expirationTime ~= nil and duration ~= nil then
        return expirationTime, duration, true
    end

    return GetReadableAuraTiming(auraData)
end

local function CanLatchPandemicRange(auraUnit, auraInstanceID)
    return auraUnit ~= nil and auraInstanceID ~= nil
end

local function AcceptedPandemicRangeMatches(owner, auraUnit, auraInstanceID, startTime, endTime)
    return owner._pandemicLatchUnit == auraUnit
        and owner._pandemicLatchAuraInstanceID == auraInstanceID
        and owner._pandemicLatchStart == startTime
        and owner._pandemicLatchEnd == endTime
end

local function ClearSuppressedPandemicRange(owner)
    if not owner then return end

    owner._pandemicSuppressedUnit = nil
    owner._pandemicSuppressedAuraInstanceID = nil
    owner._pandemicSuppressedStart = nil
    owner._pandemicSuppressedEnd = nil
end

local function IsCurrentPandemicRangeSuppressed(owner, auraUnit, auraInstanceID, startTime, endTime, hasReadableRange)
    if not CanLatchPandemicRange(auraUnit, auraInstanceID) then
        return false
    end

    if owner._pandemicSuppressedUnit == nil then
        return false
    end

    if owner._pandemicSuppressedUnit ~= auraUnit
        or owner._pandemicSuppressedAuraInstanceID ~= auraInstanceID then
        ClearSuppressedPandemicRange(owner)
        return false
    end

    if hasReadableRange
        and (owner._pandemicSuppressedStart ~= startTime
            or owner._pandemicSuppressedEnd ~= endTime) then
        ClearSuppressedPandemicRange(owner)
        return false
    end

    return true
end

local function RecordAcceptedPandemicRange(owner, auraUnit, auraInstanceID, startTime, endTime, options)
    owner._pandemicGraceStart = nil
    owner._pandemicGraceSuppressed = nil
    ClearAuraPandemicDirtyState(owner)
    ClearSuppressedPandemicRange(owner)

    if not CanLatchPandemicRange(auraUnit, auraInstanceID) then
        ClearAcceptedPandemicRange(owner)
        return
    end

    local expirationTime, duration, timingReadable = GetPandemicAuraTiming(options)
    owner._pandemicLatchUnit = auraUnit
    owner._pandemicLatchAuraInstanceID = auraInstanceID
    owner._pandemicLatchStart = startTime
    owner._pandemicLatchEnd = endTime
    owner._pandemicLatchAuraExpirationTime = timingReadable and expirationTime or nil
    owner._pandemicLatchAuraDuration = timingReadable and duration or nil
end

local function RecordSuppressedPandemicRange(owner, auraUnit, auraInstanceID, startTime, endTime)
    owner._pandemicGraceStart = nil
    owner._pandemicGraceSuppressed = nil
    ClearAuraPandemicDirtyState(owner)
    ClearAcceptedPandemicRange(owner)

    if CanLatchPandemicRange(auraUnit, auraInstanceID) then
        owner._pandemicSuppressedUnit = auraUnit
        owner._pandemicSuppressedAuraInstanceID = auraInstanceID
        owner._pandemicSuppressedStart = startTime
        owner._pandemicSuppressedEnd = endTime
    else
        ClearSuppressedPandemicRange(owner)
    end
end

local function UpdatedAuraTimingProvesStaleRange(owner, auraUnit, auraInstanceID, startTime, endTime, options)
    if not CanLatchPandemicRange(auraUnit, auraInstanceID) then
        return false
    end
    if owner._pandemicDirtyUnit ~= auraUnit
        or owner._pandemicDirtyAuraInstanceID ~= auraInstanceID then
        return false
    end
    if not AcceptedPandemicRangeMatches(owner, auraUnit, auraInstanceID, startTime, endTime) then
        return false
    end

    local expirationTime, duration, timingReadable = GetPandemicAuraTiming(options)
    if not timingReadable then
        return false
    end
    if owner._pandemicLatchAuraExpirationTime == nil or owner._pandemicLatchAuraDuration == nil then
        return false
    end

    return expirationTime ~= owner._pandemicLatchAuraExpirationTime
        or duration ~= owner._pandemicLatchAuraDuration
end

local function HasMatchingPandemicDirtyState(owner, auraUnit, auraInstanceID)
    return CanLatchPandemicRange(auraUnit, auraInstanceID)
        and owner._pandemicDirtyUnit == auraUnit
        and owner._pandemicDirtyAuraInstanceID == auraInstanceID
end

function EntryRuntime.ClearTrackedAuraOwnerState(owner, configUnit, options)
    if not owner then return end
    options = options or {}
    local inactiveValue = options.useFalseState and false or nil

    owner._auraActive = inactiveValue
    owner._auraHasTimer = inactiveValue
    owner._auraDurationObj = nil
    owner._auraCooldownStart = nil
    owner._auraCooldownDuration = nil
    owner._auraInstanceID = nil
    owner._auraUnit = configUnit
    owner._activeAuraSpellID = nil
    owner._activeAuraSpellIDFromFallback = nil
    owner._activeAuraIcon = nil
    owner._activeAuraIconAvailable = nil
    owner._auraEventRemoved = nil
    owner._auraGraceStart = nil
    if not options.preserveTargetSwitch then
        owner._targetSwitchAt = nil
        owner._targetSwitchDataReceived = nil
    end
    owner._inPandemic = inactiveValue
    ClearAuraPandemicRuntimeState(owner)
    if options.clearCustomAuraStacks then
        owner._customAuraStackValue = nil
        owner._customAuraApplicationsValue = nil
    end
end

function EntryRuntime.StartTrackedAuraTargetSwitch(owner, now, unit)
    if not owner then return end
    owner._auraInstanceID = nil
    owner._inPandemic = false
    ClearAuraPandemicRuntimeState(owner)
    owner._targetSwitchAt = now
    owner._targetSwitchDataReceived = nil
    owner._auraUnit = unit or "target"
end

function EntryRuntime.ResolveAuraPandemicState(owner, viewerFrame, options)
    if not owner then return false end
    options = options or {}

    if options.previewActive then
        return true
    end

    if not (options.enabled and viewerFrame) then
        if options.clearWhenDisabled then
            ClearAuraPandemicRuntimeState(owner)
        end
        return false
    end

    local now = options.now or GetTime()
    local auraUnit, auraInstanceID = GetPandemicAuraIdentity(owner, options)
    local pandemicStartTime, pandemicEndTime, hasReadableRange = GetReadablePandemicRange(viewerFrame)
    local hasDirtyUpdate = HasMatchingPandemicDirtyState(owner, auraUnit, auraInstanceID)
    if hasReadableRange and viewerFrame.IsInPandemicTime then
        local semanticResult = viewerFrame:IsInPandemicTime(now)
        if not issecretvalue(semanticResult) then
            if semanticResult == true then
                if IsCurrentPandemicRangeSuppressed(
                    owner,
                    auraUnit,
                    auraInstanceID,
                    pandemicStartTime,
                    pandemicEndTime,
                    true
                ) then
                    owner._pandemicGraceStart = nil
                    return false
                end

                if UpdatedAuraTimingProvesStaleRange(
                    owner,
                    auraUnit,
                    auraInstanceID,
                    pandemicStartTime,
                    pandemicEndTime,
                    options
                ) then
                    RecordSuppressedPandemicRange(owner, auraUnit, auraInstanceID, pandemicStartTime, pandemicEndTime)
                    return false
                end

                RecordAcceptedPandemicRange(owner, auraUnit, auraInstanceID, pandemicStartTime, pandemicEndTime, options)
                return true
            elseif semanticResult == false then
                ClearAuraPandemicRuntimeState(owner)
                return false
            end
        end
    end

    if IsCurrentPandemicRangeSuppressed(owner, auraUnit, auraInstanceID, pandemicStartTime, pandemicEndTime, hasReadableRange) then
        owner._pandemicGraceStart = nil
        return false
    end

    local pandemicIcon = viewerFrame.PandemicIcon
    if owner._pandemicGraceSuppressed then
        owner._pandemicGraceSuppressed = nil
        owner._pandemicGraceStart = nil
    elseif pandemicIcon and pandemicIcon:IsVisible() then
        owner._pandemicGraceStart = nil
        return true
    elseif owner._inPandemic then
        if hasDirtyUpdate then
            ClearAuraPandemicRuntimeState(owner)
            return false
        end
        if not owner._pandemicGraceStart then
            owner._pandemicGraceStart = now
        end
        if now - owner._pandemicGraceStart <= 0.3 then
            return true
        end
        owner._pandemicGraceStart = nil
    end

    return false
end

local function CommitTrackedAuraOwnerState(owner, state)
    if not owner then return end

    if state.auraPresent then
        owner._auraActive = true
        owner._auraHasTimer = state.auraHasTimer == true
        owner._auraDurationObj = state.durationObj
        owner._auraCooldownStart = state.auraCooldownStart
        owner._auraCooldownDuration = state.auraCooldownDuration
        if state.auraGraceHeld ~= true then
            owner._auraInstanceID = state.auraInstanceID
            owner._auraUnit = state.auraUnit
        elseif not owner._auraUnit then
            owner._auraUnit = state.auraUnit
        end
        if state.activeAuraSpellIDResolved then
            owner._activeAuraSpellID = state.activeAuraSpellID or owner._activeAuraSpellID
            owner._activeAuraSpellIDFromFallback = state.activeAuraSpellIDFromFallback or nil
        end
        if state.activeAuraIconResolved then
            if state.activeAuraIconAvailable then
                owner._activeAuraIcon = state.activeAuraIcon
                owner._activeAuraIconAvailable = true
            else
                owner._activeAuraIcon = nil
                owner._activeAuraIconAvailable = nil
            end
        elseif state.auraGraceHeld ~= true then
            owner._activeAuraIcon = nil
            owner._activeAuraIconAvailable = nil
        end
        if owner._targetSwitchAt
            and state.auraGraceHeld ~= true
            and (state.durationObj or state.auraCooldownDuration or state.allowDurationlessAuraInstance) then
            owner._targetSwitchAt = nil
            owner._targetSwitchDataReceived = nil
        end
    else
        EntryRuntime.ClearTrackedAuraOwnerState(owner, state.configUnit, {
            useFalseState = true,
            preserveTargetSwitch = state.wasAuraActive == true,
        })
        if owner._targetSwitchAt and not state.wasAuraActive then
            owner._targetSwitchAt = nil
            owner._targetSwitchDataReceived = nil
        end
    end
end

function EntryRuntime.EvaluateTrackedAuraState(owner, buttonData, auraSpellID, options)
    owner = owner or {}
    options = options or {}
    local now = options.now or GetTime()
    local configUnit = options.configUnit or GetConfiguredAuraUnit(buttonData)
    local auraUnit = owner._auraUnit or configUnit
    local allowDurationlessAuraInstance = options.allowDurationlessAuraInstance == true
    local allowPlayerAuraFallbackWithoutReady = options.allowPlayerAuraFallbackWithoutReady == true
    local mutateOwner = options.mutateOwner ~= false
    local prevAuraDurationObj = options.previousAuraDurationObj
    if prevAuraDurationObj == nil and owner._auraActive then
        prevAuraDurationObj = owner._auraDurationObj
    end
    local wasAuraActive = options.wasAuraActive
    if wasAuraActive == nil then
        wasAuraActive = owner._auraActive == true
    end
    local auraEventRemoved = owner._auraEventRemoved
    owner._auraEventRemoved = nil

    local viewerFrame, cdmEnabled, orderedStandaloneAuraIDs = ResolveTrackedAuraViewerFrame(
        owner,
        buttonData,
        auraSpellID,
        configUnit,
        auraUnit,
        now,
        allowDurationlessAuraInstance,
        options.useButtonAuraViewerFallback == true
    )
    local ready = CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame)

    local auraData
    local durationObj
    local auraPresent = false
    local auraHasTimer = owner._auraHasTimer == true
    local auraApplications
    local auraInstanceID
    local activeAuraSpellID
    local activeAuraSpellIDResolved = false
    local activeAuraSpellIDFromFallback
    local activeAuraIcon
    local activeAuraIconAvailable = false
    local activeAuraIconResolved = false
    local auraCooldownStart
    local auraCooldownDuration
    local viewerBar

    if ready and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
        local viewerInstId = viewerFrame.auraInstanceID
        if viewerInstId then
            local unit = viewerFrame.auraDataUnit or auraUnit
            if unit == configUnit then
                auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, viewerInstId)
                durationObj = C_UnitAuras.GetAuraDuration(unit, viewerInstId)
                if auraData and (durationObj or allowDurationlessAuraInstance) then
                    auraApplications = auraData.applications
                    activeAuraSpellID = GetReadableAuraSpellID(auraData)
                    activeAuraSpellIDResolved = true
                    activeAuraIcon, activeAuraIconAvailable, activeAuraIconResolved = ResolveAuraIconState(auraData)
                    auraInstanceID = viewerInstId
                    auraUnit = unit
                    auraPresent = true
                    auraHasTimer = durationObj and DurationObjectShowsCooldown(durationObj) or false
                end
            end
        else
            local viewerCooldown = viewerFrame.Cooldown
            if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                local vUnit = viewerFrame.auraDataUnit or auraUnit
                if vUnit == configUnit then
                    local startMs, durMs = viewerCooldown:GetCooldownTimes()
                    if issecretvalue(startMs) or issecretvalue(durMs) then
                        auraUnit = vUnit
                        auraPresent = true
                    elseif startMs and durMs and durMs > 0 and (startMs + durMs) > now * 1000 then
                        auraCooldownStart = startMs / 1000
                        auraCooldownDuration = durMs / 1000
                        auraUnit = vUnit
                        auraPresent = true
                        auraHasTimer = true
                    end
                end
                auraInstanceID = nil
            end

            if not auraPresent then
                local totemSlot = viewerFrame.preferredTotemUpdateSlot
                if totemSlot and viewerFrame:IsVisible() and viewerFrame.totemData then
                    local totemDuration = GetTotemDuration(totemSlot)
                    if totemDuration and DurationObjectShowsCooldown(totemDuration) then
                        durationObj = totemDuration
                        auraPresent = true
                        auraHasTimer = true
                        auraInstanceID = nil
                        viewerBar = viewerFrame.Bar
                    end
                end
            end
        end
    end

    local canUsePlayerAuraFallback = configUnit == "player"
        and (ready or allowPlayerAuraFallbackWithoutReady)
    if canUsePlayerAuraFallback and not auraPresent then
        auraData, activeAuraSpellID, activeAuraSpellIDFromFallback =
            ResolvePlayerAuraData(owner, buttonData, auraSpellID, orderedStandaloneAuraIDs)
        local instId = auraData and auraData.auraInstanceID
        if instId and not issecretvalue(instId) then
            durationObj = C_UnitAuras.GetAuraDuration("player", instId)
            if durationObj or allowDurationlessAuraInstance then
                auraApplications = auraData.applications
                activeAuraSpellID = activeAuraSpellID or GetReadableAuraSpellID(auraData)
                activeAuraSpellIDResolved = true
                activeAuraIcon, activeAuraIconAvailable, activeAuraIconResolved = ResolveAuraIconState(auraData)
                auraInstanceID = instId
                auraUnit = "player"
                auraPresent = true
                auraHasTimer = durationObj and DurationObjectShowsCooldown(durationObj) or false
            end
        end
    end

    if canUsePlayerAuraFallback and not auraPresent and owner._auraInstanceID then
        local cachedUnit = owner._auraUnit or configUnit
        if cachedUnit == configUnit then
            auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, owner._auraInstanceID)
            if auraData
                and (not options.validateCachedAuraData
                    or options.validateCachedAuraData(owner, buttonData, auraSpellID, auraData)) then
                durationObj = C_UnitAuras.GetAuraDuration(cachedUnit, owner._auraInstanceID)
                if durationObj or allowDurationlessAuraInstance then
                    auraApplications = auraData.applications
                    activeAuraSpellID = GetReadableAuraSpellID(auraData)
                    activeAuraSpellIDResolved = true
                    activeAuraSpellIDFromFallback = activeAuraSpellID and true or nil
                    activeAuraIcon, activeAuraIconAvailable, activeAuraIconResolved = ResolveAuraIconState(auraData)
                    auraInstanceID = owner._auraInstanceID
                    auraUnit = cachedUnit
                    auraPresent = true
                    auraHasTimer = durationObj and DurationObjectShowsCooldown(durationObj) or false
                end
            end
        end
    end

    local auraGraceHeld = false
    if not auraPresent and wasAuraActive and prevAuraDurationObj and buttonData.isPassive ~= true then
        local expired = false
        if auraEventRemoved then
            expired = true
        elseif owner._targetSwitchAt then
            if viewerFrame and not viewerFrame.auraInstanceID then
                expired = true
            elseif owner._targetSwitchDataReceived then
                expired = true
            else
                expired = (now - owner._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
            end
        elseif prevAuraDurationObj.HasSecretValues and not prevAuraDurationObj:HasSecretValues()
            and prevAuraDurationObj.GetRemainingDuration then
            expired = prevAuraDurationObj:GetRemainingDuration() <= 0
        end
        if not expired then
            if not owner._auraGraceStart then
                owner._auraGraceStart = now
            end
            if now - owner._auraGraceStart <= 0.3 or owner._targetSwitchAt then
                durationObj = prevAuraDurationObj
                auraPresent = true
                auraGraceHeld = true
            else
                owner._auraGraceStart = nil
            end
        else
            owner._auraGraceStart = nil
            owner._targetSwitchAt = nil
            owner._targetSwitchDataReceived = nil
        end
    else
        owner._auraGraceStart = nil
        if owner._targetSwitchAt then
            if auraPresent and (durationObj or auraCooldownDuration or allowDurationlessAuraInstance) then
                owner._targetSwitchAt = nil
                owner._targetSwitchDataReceived = nil
            elseif not wasAuraActive then
                owner._targetSwitchAt = nil
                owner._targetSwitchDataReceived = nil
            end
        end
    end

    if not auraPresent and owner._targetSwitchAt and wasAuraActive then
        local catchAllExpired
        if viewerFrame and not viewerFrame.auraInstanceID then
            catchAllExpired = true
        elseif owner._targetSwitchDataReceived then
            catchAllExpired = true
        else
            catchAllExpired = (now - owner._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
        end
        if catchAllExpired then
            owner._targetSwitchAt = nil
            owner._targetSwitchDataReceived = nil
        else
            if prevAuraDurationObj then
                durationObj = prevAuraDurationObj
            end
            auraPresent = true
            auraGraceHeld = true
        end
    end

    local auraExpirationTime, auraDuration, auraTimingReadable = GetReadableAuraTiming(auraPresent and auraData or nil)
    local state = {
        ready = ready == true,
        auraPresent = auraPresent == true,
        auraTrackingReady = ready == true,
        cdmEnabled = cdmEnabled == true,
        auraData = auraPresent and auraData or nil,
        auraApplications = auraPresent and auraApplications or nil,
        auraInstanceID = auraPresent and auraInstanceID or nil,
        auraUnit = auraPresent and auraUnit or configUnit,
        configUnit = configUnit,
        viewerFrame = viewerFrame,
        viewerBar = viewerBar,
        durationObj = auraPresent and durationObj or nil,
        auraCooldownStart = auraPresent and auraCooldownStart or nil,
        auraCooldownDuration = auraPresent and auraCooldownDuration or nil,
        auraExpirationTime = auraTimingReadable and auraExpirationTime or nil,
        auraDuration = auraTimingReadable and auraDuration or nil,
        auraHasTimer = auraPresent and auraHasTimer == true or false,
        auraGraceHeld = auraGraceHeld == true,
        activeAuraSpellID = activeAuraSpellID,
        activeAuraSpellIDResolved = activeAuraSpellIDResolved == true,
        activeAuraSpellIDFromFallback = activeAuraSpellIDFromFallback,
        activeAuraIcon = activeAuraIcon,
        activeAuraIconAvailable = activeAuraIconAvailable == true,
        activeAuraIconResolved = activeAuraIconResolved == true,
        allowDurationlessAuraInstance = allowDurationlessAuraInstance,
        wasAuraActive = wasAuraActive,
    }

    if mutateOwner then
        CommitTrackedAuraOwnerState(owner, state)
    end

    return state
end

local function IsSpellCooldownDeferred(info)
    if not info or info.isEnabled ~= false or info.isActive == true then
        return false
    end

    if info.isOnGCD == true then
        return false
    end

    local recoveryTime = info.timeUntilEndOfStartRecovery
    if recoveryTime == nil then
        return true
    end

    if issecretvalue(recoveryTime) then
        -- Secret recovery values are unreadable in restricted states; when they
        -- coincide with the GCD the earlier guard already classifies them as
        -- recovery-only. Outside that case, keep the existing deferred-cooldown
        -- behavior until a concrete counterexample is observed in game.
        return true
    end

    return recoveryTime <= 0
end

local actionSlotSeenScratch = {}

local function MergeActionSlotProbe(result, probe)
    if probe.sawAnySlot then result.sawAnySlot = true end
    if probe.sawUnknown then result.sawUnknown = true end
    if probe.slot and not result.slot then result.slot = probe.slot end
    if probe.matchedSpellID and not result.matchedSpellID then result.matchedSpellID = probe.matchedSpellID end
    if probe.shown ~= nil then result.shown = probe.shown end
    if probe.realShown ~= nil then result.realShown = probe.realShown end
    if probe.durationObj then result.durationObj = result.durationObj or probe.durationObj end
    if probe.realDurationObj then result.realDurationObj = result.realDurationObj or probe.realDurationObj end
    if probe.shown or probe.realShown then
        result.shown = probe.shown == true
        result.durationObj = probe.durationObj or result.durationObj
        result.realShown = probe.realShown == true
        result.realDurationObj = probe.realDurationObj or result.realDurationObj
        result.slot = probe.slot or result.slot
        result.matchedSpellID = probe.matchedSpellID or result.matchedSpellID
        return true
    end
    return false
end

local function ProbeActionSlotsForSpellID(spellID)
    local result = {
        shown = nil,
        realShown = nil,
        sawAnySlot = false,
        sawUnknown = false,
    }

    if not spellID then return result end

    local slots = C_ActionBar.FindSpellActionButtons(spellID)
    if not slots then return result end

    for _, slot in ipairs(slots) do
        if not actionSlotSeenScratch[slot] then
            actionSlotSeenScratch[slot] = true
            result.sawAnySlot = true
            result.slot = result.slot or slot
            result.matchedSpellID = result.matchedSpellID or spellID

            local durationObj = C_ActionBar.GetActionCooldownDuration(slot)
            local realDurationObj = C_ActionBar.GetActionCooldownDuration(slot, true)
            local shown = false
            local realShown

            if durationObj then
                shown = DurationObjectShowsCooldown(durationObj)
            end

            if realDurationObj then
                realShown = DurationObjectShowsCooldown(realDurationObj)
            end

            if shown or realShown then
                result.shown = shown == true
                result.durationObj = durationObj
                result.realShown = realShown == true
                result.realDurationObj = realDurationObj
                result.slot = slot
                result.matchedSpellID = spellID
                return result
            end
        end
    end

    if result.sawAnySlot then
        result.shown = false
    end

    return result
end
local function ProbeActionSlotCooldownForSpell(baseSpellID, displaySpellID)
    local result = {
        shown = nil,
        realShown = nil,
        sawAnySlot = false,
        sawUnknown = false,
    }

    if not baseSpellID then return result end

    wipe(actionSlotSeenScratch)

    if MergeActionSlotProbe(result, ProbeActionSlotsForSpellID(baseSpellID)) then
        return result
    end

    if displaySpellID and displaySpellID ~= baseSpellID then
        if MergeActionSlotProbe(result, ProbeActionSlotsForSpellID(displaySpellID)) then
            return result
        end
    end

    if result.sawAnySlot and not result.sawUnknown then
        result.shown = false
        result.realShown = false
    end

    return result
end
EntryRuntime.ProbeActionSlotCooldownForSpell = ProbeActionSlotCooldownForSpell

local function EvaluateSpellCooldownLane(spellID, secrecy, baseSpellID, options)
    local result = {
        spellID = spellID,
        fetchOk = false,
        state = COOLDOWN_STATE_READY,
        source = "ready",
        realCooldownShown = false,
        isOnGCD = false,
        deferred = false,
        resourceGatedNoCooldown = false,
    }

    if not spellID then
        return result
    end

    options = options or {}
    local suppressCooldownSurface = options.suppressCooldownSurface == true
    result.resourceGatedNoCooldown = suppressCooldownSurface

    local info = C_Spell.GetSpellCooldown(spellID)
    result.info = info
    if not info then
        if secrecy ~= 0 and not suppressCooldownSurface then
            local slotProbe = ProbeActionSlotCooldownForSpell(baseSpellID or spellID, spellID)
            if slotProbe.shown ~= nil then
                result.fetchOk = true
                result.normalCooldownShown = slotProbe.shown == true
                result.realCooldownShown = slotProbe.realShown == true
                result.durationObj = slotProbe.durationObj
                result.realDurationObj = slotProbe.realDurationObj
                result.slotProbe = slotProbe
                if result.realCooldownShown and slotProbe.realDurationObj then
                    result.state = COOLDOWN_STATE_COOLDOWN
                    result.source = "action-slot-real-no-spell-info"
                    result.renderDurationObj = slotProbe.realDurationObj
                    result.isOnGCD = CooldownCompanion._gcdActive == true
                elseif slotProbe.shown and slotProbe.durationObj then
                    result.source = "action-slot-gcd-no-spell-info"
                    result.presentationState = COOLDOWN_STATE_GCD
                    result.renderDurationObj = slotProbe.durationObj
                    result.isOnGCD = true
                end
            end
        end
        return result
    end

    result.fetchOk = true
    result.isOnGCD = info.isOnGCD or false
    result.deferred = not suppressCooldownSurface and IsSpellCooldownDeferred(info) or false

    if info.isActive and not suppressCooldownSurface then
        result.durationObj = C_Spell.GetSpellCooldownDuration(spellID)
        result.realDurationObj = C_Spell.GetSpellCooldownDuration(spellID, true)
        result.normalCooldownShown = DurationObjectShowsCooldown(result.durationObj)
        result.realCooldownShown = DurationObjectShowsCooldown(result.realDurationObj)
    end

    if suppressCooldownSurface then
        if result.isOnGCD == true and CooldownCompanion._gcdDurationObj then
            result.source = "resource-gated-gcd"
            result.presentationState = COOLDOWN_STATE_GCD
            result.renderDurationObj = CooldownCompanion._gcdDurationObj
        else
            result.source = "resource-gated-no-cooldown"
        end
        return result
    elseif result.deferred then
        result.state = COOLDOWN_STATE_COOLDOWN
        result.source = "spell-deferred"
    elseif result.realCooldownShown and result.realDurationObj then
        result.state = COOLDOWN_STATE_COOLDOWN
        result.source = "spell-real-ignore-gcd"
        result.renderDurationObj = result.realDurationObj
    elseif CooldownLogic.IsSpellGCDOnly(info, {
        normalCooldownShown = result.normalCooldownShown,
        realCooldownShown = result.realCooldownShown,
    }) then
        result.source = "spell-gcd"
        result.presentationState = COOLDOWN_STATE_GCD
        result.renderDurationObj = result.durationObj or CooldownCompanion._gcdDurationObj
    end

    local needsRealCooldownFallback = result.state ~= COOLDOWN_STATE_COOLDOWN
        and (result.isOnGCD == true
            or result.normalCooldownShown == true
            or options.allowActionSlotReadyFallback == true)

    if needsRealCooldownFallback
        and options.allowActionSlotRealFallback then
        local slotProbe = ProbeActionSlotCooldownForSpell(baseSpellID or spellID, spellID)
        if slotProbe.realShown == true and slotProbe.realDurationObj then
            result.slotProbe = slotProbe
            result.normalCooldownShown = slotProbe.shown == true or result.normalCooldownShown
            result.realCooldownShown = true
            result.durationObj = slotProbe.durationObj or result.durationObj
            result.realDurationObj = slotProbe.realDurationObj
            result.state = COOLDOWN_STATE_COOLDOWN
            result.source = "action-slot-real-fallback"
            result.renderDurationObj = slotProbe.realDurationObj
        end
    end

    return result
end
local function EvaluateButtonSpellCooldown(buttonData, cooldownSpellId, noCooldown, resourceGateCost, baseNoCooldown, baseResourceGateCost)
    local resourceGatedNoCooldown = noCooldown == true
        and (resourceGateCost == true
            or (cooldownSpellId ~= buttonData.id
                and baseNoCooldown == true
                and baseResourceGateCost == true))
    local allowActionSlotRealFallback = buttonData.hasCharges ~= true
        and (noCooldown ~= true
            or (cooldownSpellId ~= buttonData.id and baseNoCooldown ~= true))
    local allowActionSlotReadyFallback = allowActionSlotRealFallback
        and cooldownSpellId ~= buttonData.id

    return EvaluateSpellCooldownLane(cooldownSpellId, buttonData._cooldownSecrecy, buttonData.id, {
        allowActionSlotRealFallback = allowActionSlotRealFallback,
        allowActionSlotReadyFallback = allowActionSlotReadyFallback,
        suppressCooldownSurface = resourceGatedNoCooldown == true,
    })
end
EntryRuntime.EvaluateButtonSpellCooldown = EvaluateButtonSpellCooldown

local function ResolveSpellCooldownSecrecy(owner, spellID)
    if not (spellID and C_Secrets and C_Secrets.GetSpellCooldownSecrecy) then
        return owner and owner._cooldownSecrecy or nil
    end

    if owner then
        if owner._cooldownSecrecy == nil or owner._cooldownSecrecySpellID ~= spellID then
            owner._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(spellID)
            owner._cooldownSecrecySpellID = spellID
        end
        return owner._cooldownSecrecy
    end

    return C_Secrets.GetSpellCooldownSecrecy(spellID)
end

local function ResolveCachedSpellBooleanState(owner, spellID, hasCharges, valueKey, spellKey, resolver)
    if hasCharges then
        if owner then
            owner[valueKey] = false
            owner[spellKey] = nil
        end
        return false
    end

    if not spellID then
        return false
    end

    if owner and owner[valueKey] ~= nil and owner[spellKey] == spellID then
        return owner[valueKey] == true
    end

    local value = resolver(spellID)
    if owner then
        owner[spellKey] = spellID
        owner[valueKey] = value
    end
    return value
end

local function ResolveNoCooldownState(owner, spellID, hasCharges)
    return ResolveCachedSpellBooleanState(
        owner,
        spellID,
        hasCharges,
        "_noCooldown",
        "_noCooldownSpellId",
        IsNoCooldownSpell
    )
end

local function ResolveBaseNoCooldownState(owner, spellID, hasCharges)
    return ResolveCachedSpellBooleanState(
        owner,
        spellID,
        hasCharges,
        "_baseNoCooldown",
        "_baseNoCooldownSpellId",
        IsNoCooldownSpell
    )
end

local function ResolveResourceGateCostState(owner, spellID, hasCharges)
    return ResolveCachedSpellBooleanState(
        owner,
        spellID,
        hasCharges,
        "_resourceGateCost",
        "_resourceGateCostSpellId",
        HasPositiveResourceGateCost
    )
end

local function ResolveBaseResourceGateCostState(owner, spellID, hasCharges)
    return ResolveCachedSpellBooleanState(
        owner,
        spellID,
        hasCharges,
        "_baseResourceGateCost",
        "_baseResourceGateCostSpellId",
        HasPositiveResourceGateCost
    )
end

local function ClearOwnerChargeState(owner)
    if not owner then return end
    owner._customCooldownHasCharges = nil
    owner._currentReadableCharges = nil
    owner._chargeCountReadable = nil
    owner._zeroChargesConfirmed = nil
    owner._chargeDurationObj = nil
    owner._chargeRecharging = nil
    owner._mainCDShown = nil
    owner._chargeState = nil
    owner._chargesSpent = nil
    owner._lastReadableCharges = nil
    owner._chargeSpellId = nil
    owner._chargeInfoFromFallback = nil
end

function EntryRuntime.RecordChargeSpent(owner)
    if not owner then return end
    if not owner._chargeRecharging then
        owner._chargesSpent = 1
    else
        owner._chargesSpent = (owner._chargesSpent or 0) + 1
    end
end

local function InferCurrentChargesFromSpent(maxCharges, spent)
    if maxCharges == nil or (issecretvalue and issecretvalue(maxCharges)) then
        return nil
    end
    if spent == nil or (issecretvalue and issecretvalue(spent)) then
        return nil
    end

    maxCharges = tonumber(maxCharges)
    spent = tonumber(spent)
    if not maxCharges or maxCharges <= 0 or not spent then
        return nil
    end

    local current = maxCharges - spent
    if current < 0 then
        return 0
    end
    if current > maxCharges then
        return maxCharges
    end
    return current
end

local function SyncCustomBarChargeMetadata(customBar, charges, maxCharges)
    if not customBar then return end

    if maxCharges and maxCharges > 1 then
        if customBar.hasCharges ~= true then
            customBar.hasCharges = true
        end
        if customBar.maxCharges ~= maxCharges then
            customBar.maxCharges = maxCharges
        end
    elseif charges then
        if customBar.hasCharges ~= nil then
            customBar.hasCharges = nil
        end
        if customBar.maxCharges ~= maxCharges then
            customBar.maxCharges = maxCharges
        end
    else
        if customBar.hasCharges ~= nil then
            customBar.hasCharges = nil
        end
        if customBar.maxCharges ~= nil then
            customBar.maxCharges = nil
        end
    end
end

local function ApplyCustomBarChargeState(owner, result, baseSpellID, cooldownSpellID, charges, maxCharges)
    result.hasCharges = true
    result.maxCharges = maxCharges
    result.charges = charges

    local chargeDurationObj = C_Spell.GetSpellChargeDuration(cooldownSpellID)
    local chargeRecharging = DurationObjectShowsCooldown(chargeDurationObj)
    result.chargeDurationObj = chargeDurationObj
    result.chargeRecharging = chargeRecharging or false

    local currentCharges
    if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
        currentCharges = charges.currentCharges
        result.currentCharges = currentCharges
    elseif result.preserveReadableCharges == true
        and chargeRecharging == true
        and owner
        and owner._chargeCountReadable == true
        and owner._currentReadableCharges ~= nil then
        currentCharges = InferCurrentChargesFromSpent(maxCharges, owner._chargesSpent)
            or owner._currentReadableCharges
        result.currentCharges = currentCharges
    elseif C_Spell.GetSpellDisplayCount then
        result.chargeDisplayCount = C_Spell.GetSpellDisplayCount(cooldownSpellID)
    end

    if owner then
        owner._customCooldownHasCharges = true
        owner._currentReadableCharges = currentCharges
        owner._chargeCountReadable = currentCharges ~= nil
        owner._chargeDurationObj = chargeDurationObj
        owner._chargeRecharging = result.chargeRecharging
        owner._chargeSpellId = cooldownSpellID
        owner._chargeInfoFromFallback = result.preserveReadableCharges or nil
    end

    local mainCDShown = false
    if currentCharges ~= nil then
        mainCDShown = currentCharges <= 0
    else
        local slotProbe = result.slotProbe or ProbeActionSlotCooldownForSpell(baseSpellID, cooldownSpellID)
        result.chargeSlotProbe = slotProbe
        if slotProbe.shown ~= nil then
            mainCDShown = slotProbe.realShown == true
        elseif result.fetchOk then
            mainCDShown = result.state == COOLDOWN_STATE_COOLDOWN
        end
    end

    if owner then
        owner._mainCDShown = mainCDShown
        if result.chargeRecharging and not owner._chargesSpent then
            owner._chargesSpent = maxCharges or 0
        elseif result.chargeRecharging == false then
            owner._chargesSpent = nil
        end
    end

    local zeroConfirmed = mainCDShown == true
    if zeroConfirmed and currentCharges == nil and owner then
        local spent = owner._chargesSpent
        if maxCharges and maxCharges > 1 and spent and spent < maxCharges then
            zeroConfirmed = false
        end
    end

    if currentCharges ~= nil then
        if currentCharges <= 0 then
            result.chargeState = CHARGE_STATE_ZERO
        elseif currentCharges >= maxCharges then
            result.chargeState = CHARGE_STATE_FULL
        else
            result.chargeState = CHARGE_STATE_MISSING
        end
    elseif zeroConfirmed then
        result.chargeState = CHARGE_STATE_ZERO
    elseif result.chargeRecharging then
        result.chargeState = CHARGE_STATE_MISSING
    elseif result.chargeRecharging == false then
        result.chargeState = CHARGE_STATE_FULL
    end

    if owner then
        owner._zeroChargesConfirmed = zeroConfirmed
        owner._chargeState = result.chargeState
    end

    if result.chargeRecharging then
        result.state = COOLDOWN_STATE_COOLDOWN
        result.source = "spell-charge-recharge"
        result.renderDurationObj = chargeDurationObj
    end
end

function EntryRuntime.ApplyBarAuraStackState(
    button,
    auraOverrideActive,
    auraApplications,
    auraGraceHeld,
    previousBarAuraStackValue,
    previousBarAuraStackValueAvailable,
    previousBarAuraStackValueSecret
)
    local barAuraSecretStackValue
    local preserveBarAuraStackText
    local stackValue = 0
    local stackValueAvailable = true
    local stackValueFromSecretText
    local previousValueIsSecret = previousBarAuraStackValueSecret
        or (previousBarAuraStackValueAvailable and issecretvalue(previousBarAuraStackValue))

    if auraOverrideActive then
        stackValue = auraApplications
        local stackValueIsSecret = issecretvalue(stackValue)
        if not stackValueIsSecret and stackValue == nil and button._auraStackText ~= nil then
            if issecretvalue(button._auraStackText) then
                stackValue = button._auraStackText
                stackValueIsSecret = true
                stackValueFromSecretText = true
            else
                stackValue = tonumber(button._auraStackText)
                stackValueIsSecret = false
            end
        end
        if not stackValueIsSecret and stackValue == nil then
            if auraGraceHeld and previousBarAuraStackValueAvailable and not previousValueIsSecret then
                stackValue = previousBarAuraStackValue
                stackValueIsSecret = previousValueIsSecret
            elseif auraGraceHeld and previousValueIsSecret then
                stackValueAvailable = false
                preserveBarAuraStackText = true
            else
                stackValue = 1
            end
        end
        if stackValueAvailable and not stackValueIsSecret and stackValue < 1 then
            stackValue = 1
        end
    end

    local stackValueIsSecret = stackValueAvailable and issecretvalue(stackValue)
    local stackValueChanged = previousBarAuraStackValueAvailable ~= stackValueAvailable
    if not stackValueChanged and stackValueAvailable and not stackValueIsSecret and not previousValueIsSecret then
        stackValueChanged = previousBarAuraStackValue ~= stackValue
    end

    if auraGraceHeld and previousValueIsSecret and not stackValueAvailable then
        button._barAuraStackValue = nil
        button._barAuraStackValueAvailable = nil
        button._barAuraStackValueSecret = true
        button._barAuraStackValueDirty = nil
    elseif stackValueIsSecret then
        if not stackValueFromSecretText then
            barAuraSecretStackValue = stackValue
        end
        button._barAuraStackValue = nil
        button._barAuraStackValueAvailable = nil
        button._barAuraStackValueSecret = true
        button._barAuraStackValueDirty = nil
        if not stackValueFromSecretText and CooldownCompanion.ApplyBarPanelAuraStackVisual then
            CooldownCompanion.ApplyBarPanelAuraStackVisual(button, stackValue, true)
        end
    else
        button._barAuraStackValue = stackValue
        button._barAuraStackValueAvailable = stackValueAvailable or nil
        button._barAuraStackValueDirty = previousValueIsSecret or stackValueChanged
    end

    return barAuraSecretStackValue, preserveBarAuraStackText
end

function EntryRuntime.EvaluateSpellCooldownStateForCustomBar(customBar, owner)
    local spellID = tonumber(customBar and customBar.spellID)
    if not spellID then
        return EvaluateSpellCooldownLane(nil, 0, nil)
    end
    owner = owner or customBar

    local cooldownSpellID = C_Spell.GetOverrideSpell(spellID)
    if not cooldownSpellID or cooldownSpellID == 0 then
        cooldownSpellID = spellID
    end

    if owner then
        owner._customCooldownBaseSpellID = spellID
        owner._customCooldownSpellID = cooldownSpellID
    end

    local chargeSpellID = cooldownSpellID
    local charges = C_Spell.GetSpellCharges(cooldownSpellID)
    local maxCharges = charges and tonumber(charges.maxCharges)
    local preserveReadableCharges = false
    if (not maxCharges or maxCharges <= 1) and ST.ResolveSpellChargeInfo then
        local resolvedCharges, resolvedChargeSpellID, resolvedMaxCharges = ST.ResolveSpellChargeInfo(spellID)
        if resolvedCharges and (resolvedMaxCharges or 0) > 1 then
            charges = resolvedCharges
            chargeSpellID = resolvedChargeSpellID or spellID
            maxCharges = resolvedMaxCharges
            preserveReadableCharges = true
        end
    end
    SyncCustomBarChargeMetadata(customBar, charges, maxCharges)
    local hasCharges = (maxCharges or 0) > 1
    local secrecy = ResolveSpellCooldownSecrecy(owner, cooldownSpellID)
    local noCooldown = ResolveNoCooldownState(owner, cooldownSpellID, hasCharges)
    local resourceGateCost = ResolveResourceGateCostState(owner, cooldownSpellID, hasCharges)
    local baseNoCooldown = noCooldown
    local baseResourceGateCost = resourceGateCost
    if cooldownSpellID ~= spellID then
        baseNoCooldown = ResolveBaseNoCooldownState(owner, spellID, hasCharges)
        baseResourceGateCost = ResolveBaseResourceGateCostState(owner, spellID, hasCharges)
    end
    local resourceGatedNoCooldown = noCooldown == true
        and (resourceGateCost == true
            or (cooldownSpellID ~= spellID
                and baseNoCooldown == true
                and baseResourceGateCost == true))

    local allowActionSlotRealFallback = not hasCharges
        and (noCooldown ~= true
            or (cooldownSpellID ~= spellID and baseNoCooldown ~= true))
    local allowActionSlotReadyFallback = allowActionSlotRealFallback
        and cooldownSpellID ~= spellID

    local result = EvaluateSpellCooldownLane(cooldownSpellID, secrecy, spellID, {
        allowActionSlotRealFallback = allowActionSlotRealFallback,
        allowActionSlotReadyFallback = allowActionSlotReadyFallback,
        suppressCooldownSurface = resourceGatedNoCooldown == true,
    })
    result.baseSpellID = spellID
    result.cooldownSpellID = cooldownSpellID
    result.chargeSpellID = chargeSpellID
    result.preserveReadableCharges = preserveReadableCharges or nil
    result.noCooldown = noCooldown or nil

    if hasCharges then
        ApplyCustomBarChargeState(owner, result, spellID, chargeSpellID, charges, maxCharges)
    else
        ClearOwnerChargeState(owner)
    end

    return result
end
