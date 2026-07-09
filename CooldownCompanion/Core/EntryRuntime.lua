--[[
    CooldownCompanion - Core/EntryRuntime
    Shared cooldown runtime helpers for display entries.
    12.1 demolition: aura runtime evaluation removed pending the AuraContainer rebuild.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
local IsNoCooldownSpell = ST.IsNoCooldownSpell
local HasPositiveResourceGateCost = ST.HasPositiveResourceGateCost

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
-- Reusable scratch opts — single call site each; wiped immediately before
-- each fill, so a previous call can never leak values into the next one
-- even if an error aborts an update mid-call.
local buttonSpellCooldownLaneOpts = {}
local customBarSpellCooldownLaneOpts = {}

local EntryRuntime = ST.EntryRuntime or {}
ST.EntryRuntime = EntryRuntime

function EntryRuntime.ShouldSuppressSpellRangeVisual(button, buttonData)
    return type(buttonData) == "table"
        and buttonData.type == "spell"
        and buttonData.auraTracking == true
        and button
        and button._auraActive == true
end

function EntryRuntime.ShouldSuppressSpellUnusableVisual(button, buttonData)
    return type(buttonData) == "table"
        and buttonData.type == "spell"
        and buttonData.auraTracking == true
        and button
        and button._auraActive == true
end

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

-- 12.1 demolition: pandemic runtime removed with the aura backend; kept as a
-- no-op because teardown/recycle paths across the addon still call it.
local function ClearAuraPandemicRuntimeState(owner) end
EntryRuntime.ClearAuraPandemicRuntimeState = ClearAuraPandemicRuntimeState

-- Kept as a real field-clearer: recycled buttons/custom bars still carry
-- preview-set aura fields that teardown must wipe.
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

-- Releases legacy per-owner evaluation scratches left over from recycled
-- frames. Call only from teardown/dormancy paths.
function EntryRuntime.ReleaseTrackedAuraScratch(owner)
    if not owner then return end
    owner._trackedAuraStateScratch = nil
    owner._auraDisplayNameStateScratch = nil
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
-- Reusable probe/lane scratch tables, wiped at the start of every fill; each
-- keeps its previous fill's contents (including Blizzard info/duration/charge
-- references) until then. The two probe scratches must stay separate tables:
-- ProbeActionSlotCooldownForSpell fills actionSlotCooldownProbeScratch while
-- MergeActionSlotProbe reads from actionSlotProbeScratch, so sharing one
-- table would wipe the merged result mid-probe.
local actionSlotProbeScratch = {}
local actionSlotCooldownProbeScratch = {}
local spellCooldownLaneResultScratch = {}

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

-- Returns a module-local scratch table. Read it only synchronously in the
-- current probe/merge path; never retain it across calls.
local function ProbeActionSlotsForSpellID(spellID)
    local result = actionSlotProbeScratch
    wipe(result)

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
-- Returns a module-local scratch table. Read it only synchronously in the
-- current update/probe path; never retain it across ticks/events.
local function ProbeActionSlotCooldownForSpell(baseSpellID, displaySpellID)
    local result = actionSlotCooldownProbeScratch
    wipe(result)

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
-- Public alias: external callers receive the same scratch table on every
-- call, so two calls never yield independent results -- consume synchronously,
-- never retain.
EntryRuntime.ProbeActionSlotCooldownForSpell = ProbeActionSlotCooldownForSpell

-- Resolve the action-slot probe state cached on a lane result, re-probing when
-- the lane stored none (nil slotProbeShown means "not probed"). Returns
-- shown, realShown; both nil when no action slot matches the spell.
local function ResolveSlotProbeShown(result, baseSpellID, cooldownSpellID)
    local probeShown = result and result.slotProbeShown
    local probeRealShown = result and result.slotProbeRealShown
    if probeShown == nil then
        local slotProbe = ProbeActionSlotCooldownForSpell(baseSpellID, cooldownSpellID)
        probeShown = slotProbe.shown
        probeRealShown = slotProbe.realShown
    end
    return probeShown, probeRealShown
end
EntryRuntime.ResolveSlotProbeShown = ResolveSlotProbeShown

-- Returns a module-local scratch table. Read it only synchronously within the
-- current button/custom-bar update; never retain it across ticks/events.
local function EvaluateSpellCooldownLane(spellID, secrecy, baseSpellID, options)
    local result = spellCooldownLaneResultScratch
    wipe(result)
    result.spellID = spellID
    result.fetchOk = false
    result.state = COOLDOWN_STATE_READY
    result.source = "ready"
    result.realCooldownShown = false
    result.isOnGCD = false
    result.deferred = false
    result.resourceGatedNoCooldown = false

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
                result.slotProbeShown = slotProbe.shown
                result.slotProbeRealShown = slotProbe.realShown
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
    elseif CooldownLogic.IsSpellGCDOnly(info, result.normalCooldownShown, result.realCooldownShown) then
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
            result.slotProbeShown = slotProbe.shown
            result.slotProbeRealShown = slotProbe.realShown
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
-- Returns the spell cooldown lane scratch; read only synchronously in the
-- current button update and never retain across ticks/events.
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

    wipe(buttonSpellCooldownLaneOpts)
    buttonSpellCooldownLaneOpts.allowActionSlotRealFallback = allowActionSlotRealFallback
    buttonSpellCooldownLaneOpts.allowActionSlotReadyFallback = allowActionSlotReadyFallback
    buttonSpellCooldownLaneOpts.suppressCooldownSurface = resourceGatedNoCooldown == true
    return EvaluateSpellCooldownLane(cooldownSpellId, buttonData._cooldownSecrecy, buttonData.id, buttonSpellCooldownLaneOpts)
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
end

function EntryRuntime.RecordChargeSpent(owner)
    if not owner then return end
    if not owner._chargeRecharging then
        owner._chargesSpent = 1
    else
        owner._chargesSpent = (owner._chargesSpent or 0) + 1
    end
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

    local currentCharges
    if charges and charges.currentCharges ~= nil and not issecretvalue(charges.currentCharges) then
        currentCharges = charges.currentCharges
        result.currentCharges = currentCharges
    elseif C_Spell.GetSpellDisplayCount then
        result.chargeDisplayCount = C_Spell.GetSpellDisplayCount(cooldownSpellID)
    end

    local chargeDurationObj = C_Spell.GetSpellChargeDuration(cooldownSpellID)
    local chargeRecharging = DurationObjectShowsCooldown(chargeDurationObj)
    result.chargeDurationObj = chargeDurationObj
    result.chargeRecharging = chargeRecharging or false

    if owner then
        owner._customCooldownHasCharges = true
        owner._currentReadableCharges = currentCharges
        owner._chargeCountReadable = currentCharges ~= nil
        owner._chargeDurationObj = chargeDurationObj
        owner._chargeRecharging = result.chargeRecharging
    end

    local mainCDShown = false
    if currentCharges ~= nil then
        mainCDShown = currentCharges <= 0
    else
        local probeShown, probeRealShown = ResolveSlotProbeShown(result, baseSpellID, cooldownSpellID)
        if probeShown ~= nil then
            mainCDShown = probeRealShown == true
        elseif result.fetchOk then
            mainCDShown = result.state == COOLDOWN_STATE_COOLDOWN
        end
    end

    if owner then
        owner._mainCDShown = mainCDShown
        if result.chargeRecharging and not owner._chargesSpent then
            owner._chargesSpent = maxCharges or 0
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

-- Returns the spell cooldown lane scratch; read only synchronously in the
-- current custom-bar update and never retain across ticks/events.
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

    local charges = C_Spell.GetSpellCharges(cooldownSpellID)
    local maxCharges = charges and tonumber(charges.maxCharges)
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

    wipe(customBarSpellCooldownLaneOpts)
    customBarSpellCooldownLaneOpts.allowActionSlotRealFallback = allowActionSlotRealFallback
    customBarSpellCooldownLaneOpts.allowActionSlotReadyFallback = allowActionSlotReadyFallback
    customBarSpellCooldownLaneOpts.suppressCooldownSurface = resourceGatedNoCooldown == true
    local result = EvaluateSpellCooldownLane(cooldownSpellID, secrecy, spellID, customBarSpellCooldownLaneOpts)
    result.baseSpellID = spellID
    result.cooldownSpellID = cooldownSpellID
    result.noCooldown = noCooldown or nil

    if hasCharges then
        ApplyCustomBarChargeState(owner, result, spellID, cooldownSpellID, charges, maxCharges)
    else
        ClearOwnerChargeState(owner)
    end

    return result
end
