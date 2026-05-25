--[[
    CooldownCompanion - ButtonFrame/EntryRuntime
    Shared cooldown/aura runtime helpers for bar-panel entries.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic

local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local wipe = wipe
local issecretvalue = issecretvalue

local COOLDOWN_STATE_READY = CooldownLogic.STATE_READY
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

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

local function GetConfiguredAuraUnit(buttonData)
    return buttonData.auraUnit or "player"
end
EntryRuntime.GetConfiguredAuraUnit = GetConfiguredAuraUnit

local function ViewerFrameHasActiveAuraInstance(viewerFrame, configUnit, auraUnit, barAuraStackConfigured)
    local unit = viewerFrame.auraDataUnit or auraUnit
    if not (viewerFrame.auraInstanceID and unit == configUnit) then
        return false
    end

    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, viewerFrame.auraInstanceID)
    if not auraData then
        return false
    end

    return barAuraStackConfigured or C_UnitAuras.GetAuraDuration(unit, viewerFrame.auraInstanceID) ~= nil
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
    if issecretvalue(durMs) then
        return true
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

local function ViewerFrameHasActiveAuraProof(viewerFrame, configUnit, auraUnit, now, barAuraStackConfigured)
    return ViewerFrameHasActiveAuraInstance(viewerFrame, configUnit, auraUnit, barAuraStackConfigured)
        or ViewerFrameHasActiveCooldownWidget(viewerFrame, configUnit, auraUnit, now)
        or ViewerFrameHasActiveTotemDuration(viewerFrame)
end

local function ResolvePreferredStandaloneAuraViewerFrame(candidateIDs, configUnit, auraUnit, now, barAuraStackConfigured)
    local firstTrackedFrame
    for _, spellID in ipairs(candidateIDs or {}) do
        local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(spellID)
        if viewerFrame then
            if ViewerFrameHasActiveAuraProof(viewerFrame, configUnit, auraUnit, now, barAuraStackConfigured) then
                return viewerFrame, firstTrackedFrame
            end
            firstTrackedFrame = firstTrackedFrame or viewerFrame
        end
    end
    return nil, firstTrackedFrame
end
EntryRuntime.ResolvePreferredStandaloneAuraViewerFrame = ResolvePreferredStandaloneAuraViewerFrame
CooldownCompanion.ResolvePreferredStandaloneAuraViewerFrame = ResolvePreferredStandaloneAuraViewerFrame

local function ResolveTrackedAuraViewerFrame(owner, buttonData, auraSpellID, configUnit, auraUnit, now, barAuraStackConfigured)
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
        local originalActiveFrame, firstOriginalFrame = ResolvePreferredStandaloneAuraViewerFrame(
            standaloneOriginalAuraIDs,
            configUnit,
            auraUnit,
            now,
            barAuraStackConfigured
        )
        viewerFrame = originalActiveFrame
        if not viewerFrame then
            local fallbackActiveFrame, firstFallbackFrame = ResolvePreferredStandaloneAuraViewerFrame(
                standaloneFallbackAuraIDs,
                configUnit,
                auraUnit,
                now,
                barAuraStackConfigured
            )
            viewerFrame = fallbackActiveFrame or firstOriginalFrame or firstFallbackFrame
        end
    elseif not viewerFrame and buttonData.auraSpellID then
        local ids = owner._parsedAuraIDs
        if not ids or owner._parsedAuraIDsRaw ~= buttonData.auraSpellID or owner._parsedAuraIDsButtonID ~= buttonData.id then
            ids = {}
            owner._parsedAuraIDsIncludeButtonID = nil
            for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
                local numId = tonumber(id)
                ids[#ids + 1] = numId
                if numId == buttonData.id then
                    owner._parsedAuraIDsIncludeButtonID = true
                end
            end
            owner._parsedAuraIDs = ids
            owner._parsedAuraIDsRaw = buttonData.auraSpellID
            owner._parsedAuraIDsButtonID = buttonData.id
        end
        for _, numId in ipairs(ids) do
            local f = CooldownCompanion:ResolveBuffViewerFrameForSpell(numId)
            if f then
                if f.auraInstanceID then
                    viewerFrame = f
                    break
                elseif not viewerFrame then
                    viewerFrame = f
                end
            end
        end
    end

    if not viewerFrame then
        viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(auraSpellID)
        if not viewerFrame then
            viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(buttonData.id)
                or (owner._displaySpellId and CooldownCompanion:ResolveBuffViewerFrameForSpell(owner._displaySpellId))
            if not viewerFrame then
                local baseId = C_Spell.GetBaseSpell(buttonData.id)
                if baseId and baseId ~= buttonData.id and baseId ~= auraSpellID then
                    viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(baseId)
                end
            end
        end
    end

    return viewerFrame, cdmEnabled, orderedStandaloneAuraIDs
end
EntryRuntime.ResolveTrackedAuraViewerFrame = ResolveTrackedAuraViewerFrame

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
    }

    if not spellID then
        return result
    end

    options = options or {}

    local info = C_Spell.GetSpellCooldown(spellID)
    result.info = info
    if not info then
        if secrecy ~= 0 and ProbeActionSlotCooldownForSpell then
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
    result.deferred = IsSpellCooldownDeferred(info)

    if info.isActive then
        result.durationObj = C_Spell.GetSpellCooldownDuration(spellID)
        result.realDurationObj = C_Spell.GetSpellCooldownDuration(spellID, true)
        result.normalCooldownShown = DurationObjectShowsCooldown(result.durationObj)
        result.realCooldownShown = DurationObjectShowsCooldown(result.realDurationObj)
    end

    if result.deferred then
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
        and (result.isOnGCD == true or result.normalCooldownShown == true)

    if needsRealCooldownFallback
        and options.allowActionSlotRealFallback
        and ProbeActionSlotCooldownForSpell then
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
EntryRuntime.EvaluateSpellCooldownLane = EvaluateSpellCooldownLane

local function EvaluateButtonSpellCooldown(buttonData, cooldownSpellId, noCooldown)
    local allowActionSlotRealFallback = buttonData.hasCharges ~= true
        and cooldownSpellId == buttonData.id
        and noCooldown ~= true

    return EvaluateSpellCooldownLane(cooldownSpellId, buttonData._cooldownSecrecy, buttonData.id, {
        allowActionSlotRealFallback = allowActionSlotRealFallback,
    })
end
EntryRuntime.EvaluateButtonSpellCooldown = EvaluateButtonSpellCooldown

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

function EntryRuntime.EvaluateSpellCooldownStateForCustomBar(customBar)
    local spellID = tonumber(customBar and customBar.spellID)
    local result
    if not spellID then
        return EvaluateSpellCooldownLane(nil, 0, nil)
    end

    local cooldownSpellID = C_Spell.GetOverrideSpell(spellID)
    if not cooldownSpellID or cooldownSpellID == 0 then
        cooldownSpellID = spellID
    end

    if C_Secrets and C_Secrets.GetSpellCooldownSecrecy
        and (customBar._cooldownSecrecy == nil or customBar._cooldownSecrecySpellID ~= cooldownSpellID) then
        customBar._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(cooldownSpellID)
        customBar._cooldownSecrecySpellID = cooldownSpellID
    end

    local charges = C_Spell.GetSpellCharges(cooldownSpellID)
    local maxCharges = charges and tonumber(charges.maxCharges)
    if maxCharges and maxCharges > 1 then
        customBar.hasCharges = true
        customBar.maxCharges = maxCharges
    elseif charges then
        customBar.hasCharges = nil
        customBar.maxCharges = maxCharges
    elseif not charges then
        customBar.hasCharges = nil
    end

    result = EvaluateSpellCooldownLane(cooldownSpellID, customBar._cooldownSecrecy, spellID, {
        allowActionSlotRealFallback = customBar.hasCharges ~= true and cooldownSpellID == spellID,
    })
    result.baseSpellID = spellID
    result.cooldownSpellID = cooldownSpellID

    if customBar.hasCharges == true and maxCharges and maxCharges > 1 then
        result.hasCharges = true
        result.maxCharges = maxCharges
        result.charges = charges

        if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
            result.currentCharges = charges.currentCharges
            if result.currentCharges <= 0 then
                result.chargeState = CHARGE_STATE_ZERO
            elseif result.currentCharges >= maxCharges then
                result.chargeState = CHARGE_STATE_FULL
            else
                result.chargeState = CHARGE_STATE_MISSING
            end
        end

        local chargeDurationObj = C_Spell.GetSpellChargeDuration(cooldownSpellID)
        local chargeRecharging = DurationObjectShowsCooldown(chargeDurationObj)
        result.chargeDurationObj = chargeDurationObj
        result.chargeRecharging = chargeRecharging or false
        if chargeRecharging then
            result.state = COOLDOWN_STATE_COOLDOWN
            result.source = "spell-charge-recharge"
            result.renderDurationObj = chargeDurationObj
        end
    end

    return result
end

function CooldownCompanion:EvaluateSpellCooldownStateForCustomBar(customBar)
    return EntryRuntime.EvaluateSpellCooldownStateForCustomBar(customBar)
end
