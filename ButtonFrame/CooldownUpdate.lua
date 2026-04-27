--[[
    CooldownCompanion - ButtonFrame/CooldownUpdate
    Main per-tick cooldown orchestrator (UpdateButtonCooldown)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic

-- Localize frequently-used globals
local GetTime = GetTime
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local type = type
local wipe = wipe
local issecretvalue = issecretvalue
local math_max = math.max

-- Imports from Glows
local GetViewerAuraStackText = ST._GetViewerAuraStackText

-- Imports from Visibility
local EvaluateButtonVisibility = ST._EvaluateButtonVisibility

-- Pre-defined color constant tables to avoid per-tick allocation.
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}

-- APIs for text-mode conditional tokens
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local IsUsableItem = C_Item.IsUsableItem
local IsItemInRange = C_Item.IsItemInRange
local InCombatLockdown = InCombatLockdown
local UnitCanAttack = UnitCanAttack

-- Imports from Utils
local HasTooltipCooldown = ST.HasTooltipCooldown

-- Imports from Preview
local GetConditionalVisualPreview = ST._GetConditionalVisualPreview

-- Imports from Tracking
local UpdateChargeTracking = ST._UpdateChargeTracking
local UpdateDisplayCountTracking = ST._UpdateDisplayCountTracking
local UpdateItemChargeTracking = ST._UpdateItemChargeTracking

-- Imports from IconMode
local ApplyIconCountTextStyle = ST._ApplyIconCountTextStyle
local UpdateIconModeVisuals = ST._UpdateIconModeVisuals
local UpdateIconModeGlows = ST._UpdateIconModeGlows

-- Imports from BarMode
local ApplyBarCountTextStyle = ST._ApplyBarCountTextStyle
local UpdateBarDisplay = ST._UpdateBarDisplay
local IsConfigButtonForceVisible = ST.IsConfigButtonForceVisible

-- Imports from TextMode
local UpdateTextDisplay = ST._UpdateTextDisplay

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local UsesChargeTextLane = CooldownCompanion.UsesChargeTextLane
local HasCastCountText = CooldownCompanion.HasCastCountText
local GetCastCountSpellID = CooldownCompanion.GetCastCountSpellID
local GetConditionalCastCountSpellID = CooldownCompanion.GetConditionalCastCountSpellID
local TARGET_SWITCH_SAFETY_CAP = 0.60
local COOLDOWN_API_TRACE_TTL = 30
local COOLDOWN_API_TRACE_VERSION = 2
-- One normal GCD plus a small buffer. The continuity guard is only for the
-- opening post-cast API blind spot, not later cooldown-end GCD transitions.
local REAL_COOLDOWN_GCD_HOLD_WINDOW = 1.60
local COOLDOWN_STATE_READY = CooldownLogic.STATE_READY
local COOLDOWN_STATE_GCD = CooldownLogic.STATE_GCD
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

local function ClearConditionalVisualPreviewFields(button)
    if button._conditionalAuraPreview then
        local buttonData = button.buttonData
        if not (buttonData and (buttonData.auraTracking or buttonData.isPassive)) then
            button._auraActive = false
            button._auraHasTimer = false
            button._auraStackText = ""
        end
    end
    if button._conditionalAuraStackTextPreview then
        button._auraStackText = ""
        if button.auraStackCount then
            button.auraStackCount:SetText("")
        end
    end
    if button._conditionalPandemicPreview then
        local buttonData = button.buttonData
        if not (buttonData and buttonData.auraTracking) then
            button._inPandemic = false
            button._pandemicGraceStart = nil
        end
    end
    button._conditionalPreviewKind = nil
    button._conditionalPreviewStartTime = nil
    button._conditionalPreviewDuration = nil
    button._conditionalPreviewRemaining = nil
    button._conditionalPreviewLoop = nil
    button._conditionalPreviewLoopStartTime = nil
    button._conditionalPreviewLoopDuration = nil
    button._conditionalPreviewDomain = nil
    button._conditionalAuraPreview = nil
    button._conditionalAuraDurationTextPreview = nil
    button._conditionalAuraStackTextPreview = nil
    button._conditionalPandemicPreview = nil
    button._conditionalUnusablePreview = nil
    button._conditionalOutOfRangePreview = nil
    button._conditionalReadyPreview = nil
    button._conditionalBarAuraActivePreview = nil
end

local function ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)
    if not (button and button.count and (style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero)) then
        return
    end

    local cc
    if usesChargeBehavior and button._chargeState == CHARGE_STATE_ZERO then
        cc = style.chargeFontColorZero or DEFAULT_WHITE
    elseif usesChargeBehavior and button._chargeState == CHARGE_STATE_MISSING then
        cc = style.chargeFontColorMissing or DEFAULT_WHITE
    elseif usesChargeBehavior and button._chargeState == CHARGE_STATE_FULL then
        cc = style.chargeFontColor or DEFAULT_WHITE
    elseif usesChargeBehavior then
        cc = style.chargeFontColor or DEFAULT_WHITE
    elseif UsesChargeTextLane(buttonData) then
        cc = style.chargeFontColor or DEFAULT_WHITE
    end

    if cc then
        button.count:SetTextColor(cc[1], cc[2], cc[3], cc[4])
    end
end

local function GetConditionalPreviewTiming(preview, now)
    local duration = tonumber(preview and preview.duration)
    local startTime = tonumber(preview and preview.startTime)
    if not duration or duration <= 0 then
        return nil, nil, nil
    end
    if not startTime then
        startTime = now
    end

    local loopDuration = tonumber(preview and preview.loopDuration)
    local loopStartTime = tonumber(preview and preview.loopStartTime)
    if preview and preview.loop == true and loopDuration and loopDuration > 0 then
        if loopDuration > duration then
            loopDuration = duration
        end
        if not loopStartTime then
            loopStartTime = startTime + (duration - loopDuration)
        end
        local elapsed = now - loopStartTime
        if elapsed < 0 then
            elapsed = 0
        end
        local cycleElapsed = elapsed % loopDuration
        local remaining = loopDuration - cycleElapsed
        if remaining > duration then
            remaining = duration
        end
        startTime = now - (duration - remaining)
        return startTime, duration, remaining, loopStartTime, loopDuration
    end

    local remaining = duration - (now - startTime)
    if remaining < 0 then
        remaining = 0
    end
    return startTime, duration, remaining
end

local function SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
    button._conditionalPreviewStartTime = startTime
    button._conditionalPreviewDuration = duration
    button._conditionalPreviewRemaining = remaining
    button._conditionalPreviewLoop = (loopStartTime and loopDuration) and true or nil
    button._conditionalPreviewLoopStartTime = loopStartTime
    button._conditionalPreviewLoopDuration = loopDuration
end

local function ApplyConditionalVisualPreview(button, buttonData, style, preview, now, usesChargeBehavior)
    if not preview then
        return
    end

    local kind = preview.kind
    button._conditionalPreviewKind = kind

    if kind == "cooldown" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._cooldownState = COOLDOWN_STATE_COOLDOWN
        button._desatCooldownActive = true
        button._cooldownDeferred = nil
        button._conditionalPreviewDomain = "cooldown"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        return
    end

    if kind == "aura" or kind == "pandemic" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._auraActive = true
        button._auraHasTimer = true
        button._auraStackText = preview.stackText or "3"
        button._inPandemic = kind == "pandemic"
        button._conditionalAuraPreview = true
        button._conditionalPandemicPreview = kind == "pandemic" or nil
        button._conditionalBarAuraActivePreview = true
        button._conditionalPreviewDomain = "aura"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        if button.auraStackCount and style.showAuraStackText ~= false then
            button.auraStackCount:SetText(button._auraStackText or "")
        end
        return
    end

    if kind == "aura_duration_text" then
        local startTime, duration, remaining, loopStartTime, loopDuration = GetConditionalPreviewTiming(preview, now)
        if not startTime then return end
        button._conditionalAuraDurationTextPreview = true
        button._conditionalPreviewDomain = "aura_text"
        SetConditionalPreviewTimingFields(button, startTime, duration, remaining, loopStartTime, loopDuration)
        if button.cooldown then
            button.cooldown:SetCooldown(startTime, duration)
        end
        return
    end

    if kind == "aura_stack_text" then
        button._auraStackText = preview.stackText or "3"
        button._conditionalAuraStackTextPreview = true
        if button.auraStackCount and style.showAuraStackText ~= false then
            button.auraStackCount:SetText(button._auraStackText or "")
        end
        return
    end

    if kind == "charge_full" or kind == "charge_missing" or kind == "charge_zero" then
        if not usesChargeBehavior then
            return
        end
        local maxCharges = buttonData.maxCharges or 2
        if maxCharges < 2 then
            maxCharges = 2
        end

        local currentCharges = maxCharges
        if kind == "charge_missing" then
            currentCharges = math_max(1, maxCharges - 1)
            button._chargeState = CHARGE_STATE_MISSING
            button._zeroChargesConfirmed = false
        elseif kind == "charge_zero" then
            currentCharges = 0
            button._chargeState = CHARGE_STATE_ZERO
            button._zeroChargesConfirmed = true
            button._desatCooldownActive = true
        else
            button._chargeState = CHARGE_STATE_FULL
            button._zeroChargesConfirmed = false
            button._desatCooldownActive = false
        end

        button._chargeCountReadable = true
        button._currentReadableCharges = currentCharges
        button._chargeText = currentCharges
        if button.count and style.showChargeText ~= false then
            button.count:SetText(currentCharges)
        end
        return
    end

    if kind == "unusable" then
        button._isUnusable = true
        button._conditionalUnusablePreview = true
        return
    end

    if kind == "out_of_range" then
        button._isOutOfRange = true
        button._conditionalOutOfRangePreview = true
    end
end

local function AuraDataHasTimer(auraData)
    if not auraData then return false end
    local duration = auraData.duration
    if duration == nil then return false end
    if issecretvalue(duration) then return nil end
    return duration > 0
end

local function MergeAuraTimerState(currentHasTimer, auraData)
    local hasTimer = AuraDataHasTimer(auraData)
    if hasTimer ~= nil then
        return hasTimer
    end
    return currentHasTimer
end

local function GetViewerNameFontString(viewerFrame)
    -- BuffBar viewer items render name text on Bar.Name. BuffIcon entries have no name text.
    local bar = viewerFrame and viewerFrame.Bar
    return bar and bar.Name or nil
end

-- Hidden scratch CooldownFrame for probing DurationObject activity.
-- DurationObject:IsZero() returns a secret boolean in tainted contexts;
-- feeding the object to a Cooldown widget and checking IsShown() yields
-- a plain boolean safe for Lua logic.  Used by action-slot and totem
-- probes, which have no isActive companion field on their return values.
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

local function GetConfiguredAuraUnit(buttonData)
    return buttonData.auraUnit or "player"
end

local function DispatchStandaloneTextureVisual(button)
    if not button then
        return
    end
    if type(CooldownCompanion.UpdateAuraTextureVisual) ~= "function" then
        return
    end

    local group = button._groupId and CooldownCompanion.db and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[button._groupId] or nil
    if group and group.displayMode == "trigger" then
        local frame = button:GetParent()
        local runtimeButtons = frame and frame.buttons
        if type(runtimeButtons) == "table" and runtimeButtons[#runtimeButtons] == button then
            CooldownCompanion:UpdateAuraTextureVisual(runtimeButtons[1] or button)
        end
        return
    end

    CooldownCompanion:UpdateAuraTextureVisual(button)
end

local function IsReadyGlowMaxChargeEligible(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.hasCharges == true
        and not buttonData._hasDisplayCount
end

local function IsReadyGlowAtMaxCharges(button, buttonData)
    if not (button and IsReadyGlowMaxChargeEligible(buttonData)) then
        return false
    end

    return button._chargeState == CHARGE_STATE_FULL
end

-- Deferred spell cooldown detection: distinguish true held cooldowns from
-- start-recovery / empower recovery windows. In 12.0.1, unrelated spells can
-- transiently report isEnabled=false, isActive=false, and a positive
-- timeUntilEndOfStartRecovery while an empowered cast is being held. That
-- state should not drive cooldown desaturation, bar fill, text placeholders,
-- or hide-on-cooldown visibility. Treat it as recovery-only, not deferred CD.
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

local ProbeActionSlotCooldownForSpell
local ProbeSpellBookCooldownForSpell

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
                elseif slotProbe.shown and slotProbe.durationObj then
                    result.state = COOLDOWN_STATE_GCD
                    result.source = "action-slot-gcd-no-spell-info"
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
        result.state = COOLDOWN_STATE_GCD
        result.source = "spell-gcd"
        result.renderDurationObj = result.durationObj or CooldownCompanion._gcdDurationObj
    end

    local needsRealCooldownFallback = result.state ~= COOLDOWN_STATE_COOLDOWN
        and (result.isOnGCD == true or result.normalCooldownShown == true)

    -- Some short real cooldowns surface as GCD-only through the spell lane
    -- until the GCD ends. The action-slot duration object matches Blizzard's
    -- button display and can expose the real ignoreGCD cooldown immediately.
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
            result.fallbackUsed = true
            result.renderDurationObj = slotProbe.realDurationObj
        end
    end

    if options.captureLaneDiagnostics then
        if not result.slotProbe and ProbeActionSlotCooldownForSpell then
            result.slotProbe = ProbeActionSlotCooldownForSpell(baseSpellID or spellID, spellID)
        end
        if ProbeSpellBookCooldownForSpell then
            result.spellbookProbe = ProbeSpellBookCooldownForSpell(baseSpellID or spellID, spellID)
        end
    end

    return result
end

local function GetLiveOverrideSpellID(buttonData)
    if not (buttonData and buttonData.type == "spell" and not buttonData.isPassive) then
        return nil
    end

    local overrideID = C_Spell.GetOverrideSpell(buttonData.id)
    if overrideID and overrideID ~= 0 and overrideID ~= buttonData.id then
        return overrideID
    end

    return nil
end

local function EvaluateButtonSpellCooldown(buttonData, cooldownSpellId, noCooldown)
    local allowActionSlotRealFallback = buttonData.hasCharges ~= true
        and cooldownSpellId == buttonData.id
        and noCooldown ~= true

    return EvaluateSpellCooldownLane(cooldownSpellId, buttonData._cooldownSecrecy, buttonData.id, {
        allowActionSlotRealFallback = allowActionSlotRealFallback,
        captureLaneDiagnostics = allowActionSlotRealFallback,
    })
end

local function ClearRealCooldownContinuity(button)
    button._lastRealCooldownSpellID = nil
    button._lastRealCooldownDurationObj = nil
    button._lastRealCooldownSource = nil
    button._lastRealCooldownAt = nil
end

local function CanHoldRealCooldown(buttonData, cooldownSpellId, noCooldown)
    return buttonData.type == "spell"
        and buttonData.isPassive ~= true
        and buttonData.hasCharges ~= true
        and cooldownSpellId == buttonData.id
        and noCooldown ~= true
end

local function ApplyRealCooldownContinuity(button, buttonData, cooldownSpellId, noCooldown, result, now)
    if not (button and result and result.fetchOk) then
        return result
    end

    if not CanHoldRealCooldown(buttonData, cooldownSpellId, noCooldown) then
        ClearRealCooldownContinuity(button)
        return result
    end

    if result.state == COOLDOWN_STATE_COOLDOWN
        and result.realCooldownShown == true
        and result.renderDurationObj then
        button._lastRealCooldownSpellID = cooldownSpellId
        button._lastRealCooldownDurationObj = result.renderDurationObj
        button._lastRealCooldownSource = result.source
        button._lastRealCooldownAt = now
        return result
    end

    local previousDurationObj = button._lastRealCooldownDurationObj
    local previousAt = button._lastRealCooldownAt
    local canReusePrevious = previousDurationObj
        and previousAt
        and button._lastRealCooldownSpellID == cooldownSpellId
        and now - previousAt <= REAL_COOLDOWN_GCD_HOLD_WINDOW
    local lastOwnCastAt = button._lastOwnSpellCastAt
    local castAge = lastOwnCastAt and (now - lastOwnCastAt) or nil
    local recentlyCastThisSpell = castAge and castAge <= REAL_COOLDOWN_GCD_HOLD_WINDOW

    if result.state == COOLDOWN_STATE_READY then
        ClearRealCooldownContinuity(button)
        return result
    end

    if canReusePrevious and result.state == COOLDOWN_STATE_GCD and result.source == "spell-gcd" then
        if recentlyCastThisSpell and DurationObjectShowsCooldown(previousDurationObj) then
            result.preContinuityState = result.state
            result.preContinuitySource = result.source
            result.state = COOLDOWN_STATE_COOLDOWN
            result.source = "held-real-cooldown-over-gcd"
            result.realCooldownShown = true
            result.realDurationObj = previousDurationObj
            result.renderDurationObj = previousDurationObj
            result.continuityHeld = true
            result.continuityAge = now - previousAt
            result.continuityCastAge = castAge
            result.continuitySource = button._lastRealCooldownSource
            return result
        end

        if not recentlyCastThisSpell then
            result.continuityBlockedReason = "not-recent-own-cast"
            result.continuityCastAge = castAge
        end
        ClearRealCooldownContinuity(button)
    end

    return result
end

local function BuildCooldownApiTrace(result, now)
    if not result then
        return nil
    end

    local info = result.info
    local slotProbe = result.slotProbe
    local spellbookProbe = result.spellbookProbe
    local trace = {
        t = now,
        traceVersion = COOLDOWN_API_TRACE_VERSION,
        spellID = result.spellID,
        state = result.state,
        source = result.source,
        fallbackUsed = result.fallbackUsed or false,
        continuityHeld = result.continuityHeld or false,
        continuityAge = result.continuityAge,
        continuityCastAge = result.continuityCastAge,
        continuitySource = result.continuitySource,
        continuityBlockedReason = result.continuityBlockedReason,
        preContinuityState = result.preContinuityState,
        preContinuitySource = result.preContinuitySource,
        fetchOk = result.fetchOk or false,
        spellInfoPresent = info ~= nil,
        spellIsOnGCD = result.isOnGCD or false,
        spellDeferred = result.deferred or false,
        spellNormalShown = result.normalCooldownShown or false,
        spellRealShown = result.realCooldownShown or false,
    }

    if info then
        trace.spellIsActive = info.isActive == true
        trace.spellIsEnabled = info.isEnabled == true
    end

    if slotProbe then
        trace.actionSawSlot = slotProbe.sawAnySlot or false
        trace.actionSlot = slotProbe.slot
        trace.actionMatchedSpellID = slotProbe.matchedSpellID
        trace.actionNormalShown = slotProbe.shown == true
        trace.actionRealShown = slotProbe.realShown == true
    end

    if spellbookProbe then
        trace.spellbookSawSlot = spellbookProbe.sawSlot or false
        trace.spellbookSlot = spellbookProbe.slot
        trace.spellbookBank = spellbookProbe.bank and tostring(spellbookProbe.bank) or nil
        trace.spellbookMatchedSpellID = spellbookProbe.matchedSpellID
        trace.spellbookNormalShown = spellbookProbe.shown == true
        trace.spellbookRealShown = spellbookProbe.realShown == true
    end

    return trace
end

local function StoreCooldownApiTrace(button, result, now)
    if not button then
        return
    end

    local interesting = result
        and (result.state ~= COOLDOWN_STATE_READY
            or result.slotProbe ~= nil
            or result.spellbookProbe ~= nil
            or result.deferred == true)

    if interesting then
        button._cooldownApiTrace = BuildCooldownApiTrace(result, now)
        return
    end

    local existing = button._cooldownApiTrace
    if type(existing) == "table" and existing.t and now - existing.t > COOLDOWN_API_TRACE_TTL then
        button._cooldownApiTrace = nil
    end
end

local function ResolveChargeState(button, buttonData)
    if not UsesChargeBehavior(buttonData) then
        return nil
    end

    local currentCharges = button._currentReadableCharges
    local maxCharges = buttonData.maxCharges
    if button._chargeCountReadable == true and currentCharges ~= nil then
        if currentCharges <= 0 then
            return CHARGE_STATE_ZERO
        end
        if maxCharges and maxCharges > 0 then
            if currentCharges >= maxCharges then
                return CHARGE_STATE_FULL
            end
            return CHARGE_STATE_MISSING
        end
        return CHARGE_STATE_FULL
    end

    if button._zeroChargesConfirmed == true then
        return CHARGE_STATE_ZERO
    end
    if button._chargeRecharging == true then
        return CHARGE_STATE_MISSING
    end
    if button._chargeRecharging == false then
        return CHARGE_STATE_FULL
    end

    return nil
end

-- Probe action-slot cooldown state for a spell ID pair (base + display override).
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
        shown = false,
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

    return result
end

function ProbeActionSlotCooldownForSpell(baseSpellID, displaySpellID)
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

local function ProbeSpellBookCooldownForSpellID(spellID)
    local result = {
        shown = false,
        realShown = false,
        sawSlot = false,
    }

    if not spellID then return result end

    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spellID)
    if not (slot and bank) then
        return result
    end

    result.sawSlot = true
    result.slot = slot
    result.bank = bank
    result.matchedSpellID = spellID

    local durationObj = C_SpellBook.GetSpellBookItemCooldownDuration(slot, bank)
    local realDurationObj = C_SpellBook.GetSpellBookItemCooldownDuration(slot, bank, true)

    if durationObj then
        result.shown = DurationObjectShowsCooldown(durationObj)
    end

    if realDurationObj then
        result.realShown = DurationObjectShowsCooldown(realDurationObj)
    end

    return result
end

function ProbeSpellBookCooldownForSpell(baseSpellID, displaySpellID)
    local result = ProbeSpellBookCooldownForSpellID(baseSpellID)
    if result.sawSlot then
        return result
    end

    if displaySpellID and displaySpellID ~= baseSpellID then
        result = ProbeSpellBookCooldownForSpellID(displaySpellID)
    end

    return result
end

local function EvaluateItemCooldown(button, buttonData, style, renderCooldown)
    button._isEquippableNotEquipped = false
    local isEquippable = IsItemEquippable(buttonData)
    if isEquippable and not C_Item.IsEquippedItem(buttonData.id) then
        button._isEquippableNotEquipped = true
        if renderCooldown then
            button.cooldown:SetCooldown(0, 0)
        end
        button._itemCdStart = 0
        button._itemCdDuration = 0
        button._cooldownState = COOLDOWN_STATE_READY
        return false
    end

    local cdStart, cdDuration, enableCooldownTimer = C_Item.GetItemCooldown(buttonData.id)
    if not enableCooldownTimer and cdStart > 0 then
        if renderCooldown then
            button.cooldown:SetCooldown(0, 0)
        end
        button._itemCdStart = 0
        button._itemCdDuration = 0
        button._cooldownDeferred = true
        button._cooldownState = COOLDOWN_STATE_COOLDOWN
        return false
    end

    button._itemCdStart = cdStart
    button._itemCdDuration = cdDuration
    local itemGCDOnly = CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, CooldownCompanion._gcdInfo)
    if cdDuration and cdDuration > 0 then
        button._cooldownState = itemGCDOnly and COOLDOWN_STATE_GCD
            or COOLDOWN_STATE_COOLDOWN
    else
        button._cooldownState = COOLDOWN_STATE_READY
    end

    if renderCooldown then
        if button._cooldownState == COOLDOWN_STATE_GCD and style.showGCDSwipe ~= true then
            button.cooldown:SetCooldown(0, 0)
            button.cooldown:Hide()
        else
            button.cooldown:SetCooldown(cdStart, cdDuration)
        end
    end

    return itemGCDOnly == true
end

function CooldownCompanion:UpdateButtonCooldown(button)
    local buttonData = button.buttonData
    local style = button.style
    local usesChargeBehavior = UsesChargeBehavior(buttonData)
    local useChargeTextLane = UsesChargeTextLane(buttonData)
    local now = GetTime()
    local isGCDOnly = false
    local desatWasActive = button._desatCooldownActive == true
    local conditionalPreview = GetConditionalVisualPreview and GetConditionalVisualPreview(button)
    ClearConditionalVisualPreviewFields(button)

    if button.count and button._countTextLaneStyled ~= useChargeTextLane then
        if button._isBar then
            ApplyBarCountTextStyle(button, style)
        elseif not button._isText then
            ApplyIconCountTextStyle(button, style)
        else
            button._countTextLaneStyled = useChargeTextLane
        end
    end

    -- For transforming spells (e.g. Void Eruption -> Void Volley), keep the
    -- displayed spell fresh even when the game does not fire SPELL_UPDATE_ICON.
    local cooldownSpellId = button._displaySpellId or buttonData.id
    local liveOverrideId
    local forceBaseDisplayId = false
    if buttonData.type == "spell" and not buttonData.cdmChildSlot then
        local refreshIcon = false
        local previousLiveOverrideId = button._liveOverrideSpellId
        liveOverrideId = GetLiveOverrideSpellID(buttonData)
        button._liveOverrideSpellId = liveOverrideId
        if liveOverrideId then
            if liveOverrideId ~= cooldownSpellId then
                refreshIcon = true
            end
            cooldownSpellId = liveOverrideId
        elseif previousLiveOverrideId then
            cooldownSpellId = buttonData.id
            forceBaseDisplayId = true
            refreshIcon = true
        end

        if button._displaySpellId ~= cooldownSpellId then
            refreshIcon = true
        end

        -- Per-tick icon staleness detection for silent transforms (e.g. Tiger's
        -- Fury changing Rake/Rip icons). GetSpellTexture dynamically resolves
        -- the current visual, but no event fires for these transforms.
        local freshIcon = C_Spell.GetSpellTexture(buttonData.id)
        if freshIcon and freshIcon ~= button._lastSpellTexture then
            button._lastSpellTexture = freshIcon
            refreshIcon = true
        end

        if refreshIcon then
            if forceBaseDisplayId then
                button._forceBaseDisplaySpellId = true
            end
            CooldownCompanion:UpdateButtonIcon(button)
            button._forceBaseDisplaySpellId = nil
            cooldownSpellId = forceBaseDisplayId and buttonData.id
                or liveOverrideId
                or button._displaySpellId
                or buttonData.id
        end
    end

    -- Deferred icon refresh for cdmChildSlot buttons (set by OnSpellUpdateIcon).
    -- One-tick delay ensures the CDM viewer's RefreshSpellTexture has already
    -- run, so child.Icon:GetTextureFileID() returns the current texture.
    if button._iconDirty then
        button._iconDirty = nil
        CooldownCompanion:UpdateButtonIcon(button)
        cooldownSpellId = liveOverrideId or button._displaySpellId or buttonData.id
    end

    -- Lazy-cache no-cooldown detection for spells (GCD-only, no real CD).
    -- Tie the cache to the displayed spell so replacements do not inherit the
    -- base spell's cooldown classification.
    if buttonData.type == "spell" and not buttonData.isPassive and not usesChargeBehavior then
        if button._noCooldown == nil or button._noCooldownSpellId ~= cooldownSpellId then
            button._noCooldownSpellId = cooldownSpellId
            local baseCd = GetSpellBaseCooldown(cooldownSpellId)
            button._noCooldown = (not baseCd or baseCd == 0) and not HasTooltipCooldown(cooldownSpellId)
        end
    else
        button._noCooldown = false
        button._noCooldownSpellId = nil
    end

    -- Proc state: event-driven table lookup (base spell + current displayed override).
    -- Keeps visibility and glow checks aligned without polling overlay APIs.
    local procOverlayActive = false
    if buttonData.type == "spell" and not buttonData.isPassive then
        local displaySpellId = button._displaySpellId
        procOverlayActive = CooldownCompanion.procOverlaySpells[buttonData.id] ~= nil
        if not procOverlayActive and displaySpellId and displaySpellId ~= buttonData.id then
            procOverlayActive = CooldownCompanion.procOverlaySpells[displaySpellId] ~= nil
        end
    end

    -- Clear per-tick DurationObject; set below if cooldown/aura active.
    -- Used by bar fill, desaturation, visibility checks instead of
    -- GetCooldownTimes() which returns secret values after
    -- SetCooldownFromDurationObject() in 12.0.1.
    -- Save previous aura DurationObject for one-tick grace period on target switch.
    local prevAuraDurationObj = button._auraActive and button._durationObj or nil
    button._durationObj = nil
    button._cooldownDeferred = nil
    button._cooldownState = COOLDOWN_STATE_READY
    button._chargeState = nil
    button._chargeCooldownVisualActive = nil
    if buttonData.type ~= "spell" or buttonData.isPassive then
        button._cooldownApiTrace = nil
    end

    -- Fetch cooldown data and update the cooldown widget.
    -- isOnGCD is NeverSecret (always readable even during restricted combat).
    local fetchOk, isOnGCD
    local spellCooldownInfo
    local spellCooldownDuration
    local spellRealCooldownShown = false
    local spellCooldownResult
    -- Aura-override probe: cached for reuse by secondary CD and sound alerts.
    local auraProbeInfo, auraProbeIsGCDOnly
    local auraProbeDuration
    local auraProbeNormalCooldownShown = false
    local auraProbeRealCooldownShown = false

    -- Aura tracking: check for active buff/debuff and override cooldown swipe
    local auraOverrideActive = false
    local auraHasTimer = button._auraHasTimer == true
    local auraTrackingReady = buttonData.isPassive == true
    -- Capture and clear event-driven removal flag (set by OnUnitAura when
    -- removedAuraInstanceIDs confirms the aura is gone).  Used to bypass the
    -- grace hold, which otherwise can't detect expiry in combat (secret values).
    local auraEventRemoved = button._auraEventRemoved
    button._auraEventRemoved = nil
    if buttonData.auraTracking and button._auraSpellID then
        local configUnit = GetConfiguredAuraUnit(buttonData)
        local auraUnit = button._auraUnit or configUnit

        local viewerFrame
        local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true

        -- Viewer-based aura tracking: Blizzard's cooldown viewer frames run
        -- untainted code that matches spell IDs to auras during combat and
        -- stores auraInstanceID + auraDataUnit as plain readable properties.
        -- Requires the Blizzard Cooldown Manager to be visible with this spell.
        -- CDM child slot: use specific child for multi-entry spells (e.g., Diabolic Ritual)
        if buttonData.cdmChildSlot then
            local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
            if allChildren then
                viewerFrame = allChildren[buttonData.cdmChildSlot]
            end
        end
        -- Try each override ID (comma-separated), prefer one with active aura.
        -- Cache parsed IDs on the button to avoid per-tick gmatch allocation.
        if not viewerFrame and buttonData.auraSpellID then
            local ids = button._parsedAuraIDs
            if not ids or button._parsedAuraIDsRaw ~= buttonData.auraSpellID then
                ids = {}
                for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
                    ids[#ids + 1] = tonumber(id)
                end
                button._parsedAuraIDs = ids
                button._parsedAuraIDsRaw = buttonData.auraSpellID
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
        -- Fall back to resolved aura ID, then ability ID, then current override form.
        -- _displaySpellId tracks the current override (e.g. Solar → Lunar Eclipse)
        -- and is always present in the viewer map after BuildViewerAuraMap.
        if not viewerFrame then
            viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(button._auraSpellID)
            if not viewerFrame then
                viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(buttonData.id)
                    or (button._displaySpellId and CooldownCompanion:ResolveBuffViewerFrameForSpell(button._displaySpellId))
                -- Try base spell for form-variant spells (e.g. Stampeding Roar)
                if not viewerFrame then
                    local baseId = C_Spell.GetBaseSpell(buttonData.id)
                    if baseId and baseId ~= buttonData.id and baseId ~= button._auraSpellID then
                        viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(baseId)
                    end
                end
            end
        end
        auraTrackingReady = CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame)
        if auraTrackingReady and not auraOverrideActive and viewerFrame and (auraUnit == "player" or auraUnit == "target") then
            local viewerInstId = viewerFrame.auraInstanceID
            if viewerInstId then
                local unit = viewerFrame.auraDataUnit or auraUnit
                local durationObj = C_UnitAuras.GetAuraDuration(unit, viewerInstId)
                -- Gate on unit compatibility: CDM's GetAuraData() checks player
                -- auras first, so auraDataUnit can incorrectly be "player" for a
                -- viewer child that tracks a target debuff.  Reject the mismatch
                -- so target-debuff buttons don't display random player buff durations.
                if durationObj and unit == configUnit then
                    -- Cross-validate: confirm the aura instance actually exists
                    -- on the claimed unit.  GetAuraDuration may return data for
                    -- stale instance IDs that belong to a different unit (e.g.
                    -- old target after a target switch), causing ghost auras.
                    local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, viewerInstId)
                    if auraData then
                        button._durationObj = durationObj
                        button._viewerBar = nil  -- primary path: DurationObject available
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        button._auraInstanceID = viewerInstId
                        button._auraUnit = unit
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            else
                -- No auraInstanceID — fall back to reading the viewer's cooldown widget.
                -- Covers spells where the viewer tracks the buff duration internally
                -- (auraDataUnit set by GetAuraData) but doesn't expose auraInstanceID.
                local viewerCooldown = viewerFrame.Cooldown
                if viewerFrame.auraDataUnit and viewerCooldown and viewerCooldown:IsShown() then
                    local startMs, durMs = viewerCooldown:GetCooldownTimes()
                    if not issecretvalue(durMs) then
                        -- Plain values: safe to do ms->s arithmetic
                        if durMs > 0 and (startMs + durMs) > now * 1000 then
                            local vUnit = viewerFrame.auraDataUnit or auraUnit
                            if vUnit == configUnit then
                                button.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                                button._auraUnit = vUnit
                                auraOverrideActive = true
                                auraHasTimer = true
                                fetchOk = true
                            end
                        end
                    else
                        -- Secret values: can't convert ms->s. Mark aura active;
                        -- grace period covers continuity from previous tick's display.
                        -- (HasSecretValues() on viewer widgets is unreliable when
                        -- Blizzard secure code set the values — check the returned
                        -- value directly with issecretvalue() instead.)
                        local vUnit = viewerFrame.auraDataUnit or auraUnit
                        if vUnit == configUnit then
                            button._auraUnit = vUnit
                            auraOverrideActive = true
                            fetchOk = true
                        end
                    end
                    if button._auraInstanceID then
                        button._auraInstanceID = nil
                    end
                end
                -- Fallback 2: GetTotemDuration for totem/summoning spells
                -- (TrackedBar category). Returns a LuaDurationObject.
                -- GetTotemDuration is a global (not C_Totem-namespaced).
                -- Read preferredTotemUpdateSlot directly from the viewer
                -- frame (plain number set by CDM) rather than caching it,
                -- since the slot may not be populated at BuildViewerAuraMap time.
                -- Guard: viewerFrame.totemData is non-nil only when CDM has
                -- validated that the totem slot still contains this child's
                -- spell (GetPreferredTotemSlotInfo checks spellID).  Without
                -- this, a stale preferredTotemUpdateSlot causes CC to read a
                -- different spell's totem duration after slot reuse.
                if not auraOverrideActive then
                    local totemSlot = viewerFrame.preferredTotemUpdateSlot
                    if totemSlot and viewerFrame:IsVisible() and viewerFrame.totemData then
                        local totemDuration = GetTotemDuration(totemSlot)
                        local totemActive = false
                        if totemDuration then
                            scratchCooldown:SetCooldownFromDurationObject(totemDuration)
                            totemActive = scratchCooldown:IsShown()
                            scratchCooldown:SetCooldown(0, 0)
                        end
                        if totemActive then
                            button.cooldown:SetCooldownFromDurationObject(totemDuration)
                            button._durationObj = totemDuration
                            auraOverrideActive = true
                            auraHasTimer = true
                            fetchOk = true
                            -- Bar mode: cache viewer's StatusBar for bar fill pass-through
                            if button._isBar and viewerFrame.Bar then
                                button._viewerBar = viewerFrame.Bar
                            end
                            if button._auraInstanceID then
                                button._auraInstanceID = nil
                            end
                        else
                            if button._isBar then
                                button._viewerBar = nil
                            end
                        end
                    end
                end
            end
        end
        -- Fallback: direct GetPlayerAuraBySpellID for player-tracked auras when
        -- the viewer path has no auraInstanceID (form-variant spells like
        -- Stampeding Roar where the CDM can't match the buff across shapeshifts).
        local canUsePlayerAuraFallback = auraTrackingReady and configUnit == "player"

        if canUsePlayerAuraFallback and not auraOverrideActive then
            local baseId = C_Spell.GetBaseSpell(buttonData.id)
            -- Try base spell first (buff is applied as base), then _auraSpellID
            local fallbackId = baseId and baseId ~= button._auraSpellID and baseId or nil
            local auraData = fallbackId and C_UnitAuras.GetPlayerAuraBySpellID(fallbackId)
            if not auraData then
                auraData = C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID)
            end
            if auraData then
                local instId = auraData.auraInstanceID
                if instId and not issecretvalue(instId) then
                    local durationObj = C_UnitAuras.GetAuraDuration("player", instId)
                    if durationObj then
                        button._durationObj = durationObj
                        button._viewerBar = nil
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        button._auraInstanceID = instId
                        button._auraUnit = "player"
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            end
        end
        -- Cached instance ID fallback: when the viewer and GetPlayerAuraBySpellID
        -- both fail (restricted combat + form-variant spells), the previously-cached
        -- _auraInstanceID may still be valid.  GetAuraDuration works in restricted
        -- combat and the instance ID persists until OnUnitAura removal clears it.
        -- Target-debuff tracking intentionally skips this fallback because a stale
        -- target auraInstanceID can survive brief viewer churn and show ghost time.
        if canUsePlayerAuraFallback and not auraOverrideActive and button._auraInstanceID then
            local cachedUnit = button._auraUnit or configUnit
            if cachedUnit == configUnit then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(cachedUnit, button._auraInstanceID)
                if auraData then
                    local durationObj = C_UnitAuras.GetAuraDuration(cachedUnit, button._auraInstanceID)
                    if durationObj then
                        button._durationObj = durationObj
                        button._viewerBar = nil
                        button.cooldown:SetCooldownFromDurationObject(durationObj)
                        auraOverrideActive = true
                        auraHasTimer = DurationObjectShowsCooldown(durationObj)
                        fetchOk = true
                    end
                end
            end
        end
        -- Grace period: if aura data is momentarily unavailable but we had an
        -- active aura DurationObject last tick, keep aura state alive.
        -- Restoring _durationObj preserves bar fill, color, and time text.
        -- Target-switch path: holds until UNIT_AURA confirms data received
        -- (debuff absent on new target) or primary path provides fresh data.
        -- Player path: DurationObject expiry + time-based grace window.
        if not auraOverrideActive and button._auraActive
           and prevAuraDurationObj and not buttonData.isPassive then
            local expired = false
            if auraEventRemoved then
                -- Server confirmed aura removal via UNIT_AURA
                -- removedAuraInstanceIDs — bypass grace hold entirely.
                -- Without this, combat secret values prevent
                -- GetRemainingDuration() from detecting expiry, causing
                -- a ~0.3s ghost hold on every aura-tracked proc consumed.
                expired = true
            elseif button._targetSwitchAt then
                -- CDM processes UNIT_TARGET before PLAYER_TARGET_CHANGED,
                -- so the viewer frame already reflects the new target.
                -- If CDM has no auraInstanceID, the debuff is confirmed
                -- absent on the new target — expire immediately.
                -- Ghost auras from stale instance IDs are prevented by the
                -- cross-validation (GetAuraDataByAuraInstanceID) in the
                -- viewer path, so this nil check is safe.
                if viewerFrame and not viewerFrame.auraInstanceID then
                    expired = true
                elseif button._targetSwitchDataReceived then
                    expired = true
                else
                    expired = (now - button._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
                end
            elseif not prevAuraDurationObj:HasSecretValues() then
                expired = prevAuraDurationObj:GetRemainingDuration() <= 0
            end
            if not expired then
                if not button._auraGraceStart then
                    button._auraGraceStart = now
                end
                if now - button._auraGraceStart <= 0.3 or button._targetSwitchAt then
                    button._durationObj = prevAuraDurationObj
                    auraOverrideActive = true
                else
                    button._auraGraceStart = nil
                end
            else
                button._auraGraceStart = nil
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
            end
        else
            button._auraGraceStart = nil
            if button._targetSwitchAt then
                if auraOverrideActive and button._durationObj then
                    -- Primary path provided fresh DurationObject: hold complete
                    button._targetSwitchAt = nil
                    button._targetSwitchDataReceived = nil
                elseif not button._auraActive then
                    -- Safety: _auraActive already false, clear stale hold
                    button._targetSwitchAt = nil
                    button._targetSwitchDataReceived = nil
                end
            end
        end
        -- Target-switch hold catch-all: preserve _auraActive for buttons
        -- without a previous DurationObject (tracked via fallback path only)
        if not auraOverrideActive and button._targetSwitchAt and button._auraActive then
            local catchAllExpired
            -- Same expiry logic as the grace period hold above.
            if viewerFrame and not viewerFrame.auraInstanceID then
                catchAllExpired = true
            elseif button._targetSwitchDataReceived then
                catchAllExpired = true
            else
                catchAllExpired = (now - button._targetSwitchAt) > TARGET_SWITCH_SAFETY_CAP
            end
            if catchAllExpired then
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
            else
                button._durationObj = prevAuraDurationObj
                auraOverrideActive = true
            end
        end
        button._auraActive = auraOverrideActive
        if auraOverrideActive then
            button._auraHasTimer = auraHasTimer
        end
        if not auraOverrideActive then
            button._auraInstanceID = nil
            button._auraUnit = configUnit
        end

        -- Viewer icon change detection: for passive aura-tracked buttons, the
        -- viewer frame's Icon widget updates per-stage (e.g. Heating Up → Hot Streak)
        -- but UpdateButtonIcon is not called per-tick. Detect texture changes here
        -- and trigger an icon update only when the viewer icon actually changes.
        if buttonData.isPassive and viewerFrame then
            local iconObj = viewerFrame.Icon
            if iconObj and not iconObj.GetTextureFileID then
                iconObj = iconObj.Icon
            end
            if iconObj and iconObj.GetTextureFileID then
                local vfTexId = iconObj:GetTextureFileID()
                if issecretvalue(vfTexId) then
                    -- Secret in combat: can't compare, always refresh
                    -- (SetTexture accepts secret values as pass-through)
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                elseif vfTexId ~= button._lastViewerTexId then
                    button._lastViewerTexId = vfTexId
                    button._auraViewerFrame = viewerFrame
                    CooldownCompanion:UpdateButtonIcon(button)
                end
            end
        elseif buttonData.isPassive and button._lastViewerTexId then
            button._lastViewerTexId = nil
            button._auraViewerFrame = nil
            CooldownCompanion:UpdateButtonIcon(button)
        end

        -- Aura icon swap: trigger icon update on _auraActive transition
        if buttonData.auraShowAuraIcon and button._auraSpellID then
            local shouldShow = auraOverrideActive
            button._auraViewerFrame = shouldShow and viewerFrame or nil
            if shouldShow ~= (button._showingAuraIcon or false) then
                button._showingAuraIcon = shouldShow
                CooldownCompanion:UpdateButtonIcon(button)
            elseif shouldShow and viewerFrame then
                -- Detect viewer Icon texture changes for stage transitions
                -- within an already-active aura (e.g. Heating Up → Hot Streak).
                local iconObj = viewerFrame.Icon
                if iconObj and not iconObj.GetTextureFileID then
                    iconObj = iconObj.Icon
                end
                if iconObj and iconObj.GetTextureFileID then
                    local vfTexId = iconObj:GetTextureFileID()
                    if issecretvalue(vfTexId) then
                        -- Secret in combat: can't compare, always refresh
                        CooldownCompanion:UpdateButtonIcon(button)
                    elseif vfTexId ~= button._lastViewerTexId then
                        button._lastViewerTexId = vfTexId
                        CooldownCompanion:UpdateButtonIcon(button)
                    end
                end
            end
        else
            button._showingAuraIcon = nil
            -- Don't clear _auraViewerFrame for passive buttons — managed above
            if not buttonData.isPassive then
                button._auraViewerFrame = nil
            end
        end

        -- Read aura stack text from viewer frame (combat-safe, secret pass-through)
        if button._auraTrackingReady or buttonData.isPassive then
            if auraOverrideActive and viewerFrame then
                button._auraStackText = GetViewerAuraStackText(viewerFrame)
            else
                button._auraStackText = ""
            end
        end

        -- Pandemic window check: read Blizzard's PandemicIcon from the viewer frame.
        -- Blizzard calculates the exact per-spell pandemic window internally and
        -- shows/hides PandemicIcon accordingly.  Use IsVisible() so that a
        -- PandemicIcon whose parent viewer item was hidden (e.g. aura expired
        -- before OnUpdate could clean it up) is not treated as active.
        -- Grace window: PandemicIcon lives on a pool-managed CDM child frame.
        -- During RefreshLayout, child frames are recycled and re-acquired,
        -- which briefly invalidates the viewerFrame reference resolved from
        -- the aura map.  During this window viewerFrame.PandemicIcon may be
        -- nil or stale, so hold pandemic state for a fixed wall-clock duration
        -- (0.3s) to absorb brief dropouts.  Time-based rather than tick-based
        -- so that rapid UNIT_AURA-driven UpdateAllCooldowns() calls during
        -- heavy combat don't burn through the grace window prematurely.
        -- Genuine pandemic end sets _inPandemic = false via event handlers
        -- (Aura.lua aura removal / target switch), causing the grace guard
        -- to fail on the next evaluation.  Aura reapplication (pandemic
        -- refresh) sets _pandemicGraceSuppressed, bypassing the grace hold
        -- entirely so pandemic clears immediately on refresh.
        local inPandemic = false
        if button._pandemicPreview then
            inPandemic = true
        -- Pandemic detection: style-level (Show Pandemic Glow) OR per-button visibility toggle.
        elseif auraOverrideActive and (style.showPandemicGlow ~= false or buttonData.hideAuraActiveExceptPandemic) and viewerFrame then
            local pi = viewerFrame.PandemicIcon
            if button._pandemicGraceSuppressed then
                -- Aura was just refreshed (pandemic recast).  Clear pandemic
                -- immediately regardless of PandemicIcon visibility — CDM may
                -- not have run its OnUpdate yet, leaving PandemicIcon stale.
                button._pandemicGraceSuppressed = nil
                button._pandemicGraceStart = nil
                -- inPandemic stays false
            elseif pi and pi:IsVisible() then
                inPandemic = true
                button._pandemicGraceStart = nil
            elseif button._inPandemic then
                -- Grace hold: absorbs brief CDM RefreshLayout recycling dropouts.
                -- Time-based rather than tick-based so rapid UNIT_AURA-driven
                -- UpdateAllCooldowns() calls don't burn through the window.
                if not button._pandemicGraceStart then
                    button._pandemicGraceStart = now
                end
                if now - button._pandemicGraceStart <= 0.3 then
                    inPandemic = true
                else
                    button._pandemicGraceStart = nil
                end
            end
        end
        button._inPandemic = inPandemic

        -- Pass through the CDM item's current name text when aura tracking is
        -- active. This mirrors CDM state-based names (e.g. Light/Moderate/Heavy).
        -- Icon is NOT passed through — UpdateButtonIcon is the sole authoritative source.
        if auraOverrideActive then
            if viewerFrame then
                local viewerName = GetViewerNameFontString(viewerFrame)
                if button.nameText and not buttonData.customName and viewerName and viewerName.GetText then
                    -- Pass through the CDM-rendered text directly; avoid calling viewer mixin methods
                    -- from tainted code (they can execute secret-value logic internally).
                    button.nameText:SetText(viewerName:GetText())
                end
                -- Multi-slot buttons read their icon from the viewer's Icon widget.
                -- Event-driven UpdateButtonIcon calls can race with the CDM viewer's
                -- internal icon update on transforms (e.g. Diabolic Ritual), so re-sync
                -- the icon every tick to ensure it reflects the viewer's current state.
                if buttonData.cdmChildSlot then
                    CooldownCompanion:UpdateButtonIcon(button)
                end
                button._viewerAuraVisualsActive = true
            end
        elseif button._viewerAuraVisualsActive then
            button._viewerAuraVisualsActive = nil
            if button.nameText and not buttonData.customName then
                local restoreSpellID = button._displaySpellId or buttonData.id
                local baseName = C_Spell.GetSpellName(restoreSpellID)
                if baseName then
                    button.nameText:SetText(baseName)
                end
            end
            -- Multi-slot buttons got their icon from per-tick viewer reads while
            -- the aura was active. Now that the aura has dropped, re-sync the icon
            -- to the viewer's current (base) state.
            if buttonData.cdmChildSlot then
                CooldownCompanion:UpdateButtonIcon(button)
            end
        end
    end
    button._auraTrackingReady = auraTrackingReady

    if buttonData.isPassive and not auraOverrideActive then
        button.cooldown:Hide()
    end

    -- Probe spell CD during aura override (shared by secondary CD and sound alerts).
    if auraOverrideActive and buttonData.type == "spell" and not buttonData.isPassive then
        auraProbeInfo = C_Spell.GetSpellCooldown(cooldownSpellId)
        if auraProbeInfo and auraProbeInfo.isActive then
            local auraProbeNormalDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId)
            auraProbeNormalCooldownShown = DurationObjectShowsCooldown(auraProbeNormalDuration)
            auraProbeDuration = C_Spell.GetSpellCooldownDuration(cooldownSpellId, true)
            auraProbeRealCooldownShown = DurationObjectShowsCooldown(auraProbeDuration)
        end
        auraProbeIsGCDOnly = auraProbeInfo and CooldownLogic.IsSpellGCDOnly(auraProbeInfo, {
            normalCooldownShown = auraProbeNormalCooldownShown,
            realCooldownShown = auraProbeRealCooldownShown,
        }) or false
    end

    -- Secondary cooldown text display during aura override
    if auraOverrideActive and button.secondaryCooldown then
        if buttonData.type == "spell" and not buttonData.isPassive then
            if auraProbeInfo then
                if not auraProbeIsGCDOnly then
                    if auraProbeDuration and auraProbeRealCooldownShown then
                        button.secondaryCooldown:SetCooldownFromDurationObject(auraProbeDuration)
                        button._secondaryCdActive = true
                    else
                        button.secondaryCooldown:SetCooldown(0, 0)
                        button._secondaryCdActive = false
                    end
                else
                    button.secondaryCooldown:SetCooldown(0, 0)
                    button._secondaryCdActive = false
                end
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        elseif buttonData.type == "item" then
            local cdStart, cdDuration = C_Item.GetItemCooldown(buttonData.id)
            local probeIsGCDOnly = CooldownLogic.IsItemGCDOnly(cdStart, cdDuration, CooldownCompanion._gcdInfo)
            if cdDuration and cdDuration > 0 and not probeIsGCDOnly then
                button.secondaryCooldown:SetCooldown(cdStart, cdDuration)
                button._secondaryCdActive = true
            else
                button.secondaryCooldown:SetCooldown(0, 0)
                button._secondaryCdActive = false
            end
        end
    elseif button.secondaryCooldown and button._secondaryCdActive then
        button._secondaryCdActive = false
        button.secondaryCooldown:SetCooldown(0, 0)
    end

    if not auraOverrideActive then
        if buttonData.type == "spell" and not buttonData.isPassive then
            spellCooldownResult = EvaluateButtonSpellCooldown(buttonData, cooldownSpellId, button._noCooldown)
            spellCooldownResult = ApplyRealCooldownContinuity(
                button,
                buttonData,
                cooldownSpellId,
                button._noCooldown,
                spellCooldownResult,
                now
            )
            StoreCooldownApiTrace(button, spellCooldownResult, now)
            if spellCooldownResult and spellCooldownResult.fetchOk then
                spellCooldownInfo = spellCooldownResult.info
                spellCooldownDuration = spellCooldownResult.durationObj
                spellRealCooldownShown = spellCooldownResult.realCooldownShown == true
                isOnGCD = spellCooldownResult.isOnGCD or false
                button._cooldownState = spellCooldownResult.state or COOLDOWN_STATE_READY
                local renderDurationObj = spellCooldownResult.renderDurationObj
                button._cooldownDeferred = spellCooldownResult.deferred or nil
                isGCDOnly = button._cooldownState == COOLDOWN_STATE_GCD

                if button._cooldownState == COOLDOWN_STATE_COOLDOWN then
                    if renderDurationObj then
                        button._durationObj = renderDurationObj
                        button.cooldown:SetCooldownFromDurationObject(renderDurationObj)
                    else
                        button.cooldown:SetCooldown(0, 0)
                    end
                elseif button._cooldownState == COOLDOWN_STATE_GCD then
                    if style.showGCDSwipe == true and renderDurationObj then
                        button.cooldown:SetCooldownFromDurationObject(renderDurationObj)
                    else
                        button.cooldown:SetCooldown(0, 0)
                        button.cooldown:Hide()
                    end
                else
                    button.cooldown:SetCooldown(0, 0)
                end
                fetchOk = true
            elseif not fetchOk then
                button.cooldown:SetCooldown(0, 0)
            end
        elseif buttonData.type == "item" then
            isGCDOnly = EvaluateItemCooldown(button, buttonData, style, true)
            fetchOk = true
        end
    elseif buttonData.type == "item" then
        -- Items keep underlying cooldown state during aura override for visibility/desaturation.
        -- Spell aura overrides intentionally do not: the aura owns the spell visual state.
        isGCDOnly = EvaluateItemCooldown(button, buttonData, style, false)
        fetchOk = true
    end

    -- Update spell charge data before zero-charge state classification.
    -- When readable, charge count is authoritative for "zero charges" (unusable),
    -- even if the spell also has a per-cast cooldown lockout.
    local charges
    if usesChargeBehavior and buttonData.hasCharges and buttonData.type == "spell" then
        button._displayCountZeroUsabilityFallback = nil
        charges = UpdateChargeTracking(button, buttonData, cooldownSpellId)
        button._chargeCooldownVisualActive = DurationObjectShowsCooldown(button._chargeDurationObj)
        button._chargeRecharging = button._chargeCooldownVisualActive
    elseif usesChargeBehavior
        and (buttonData._hasDisplayCount or buttonData._displayCountFamily)
        and buttonData.type == "spell"
    then
        UpdateDisplayCountTracking(button, buttonData, cooldownSpellId)
    elseif usesChargeBehavior and buttonData.type == "item" then
        UpdateItemChargeTracking(button, buttonData)
        button._chargeRecharging = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif not usesChargeBehavior then
        -- hasCharges cleared: wipe stale charge state.
        button._currentReadableCharges = nil
        button._chargeCountReadable = nil
        button._zeroChargesConfirmed = nil
        button._chargeRecharging = nil
        button._chargeDurationObj = nil
        button._chargesSpent = nil
        button._chargeText = nil
        button._displayCountZeroUsabilityFallback = nil
        if buttonData.type == "spell" then
            button.count:SetText("")
        end
        -- Shared count-text lane for non-charge spells:
        --   1) Blizzard display/use counts (e.g. pooled/shared uses)
        --   2) Cast-count stacks (e.g. Mana Tea)
        -- Both intentionally reuse the charge-text font/toggle without driving
        -- charge-specific cooldown logic.
        if buttonData.type == "spell"
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false)
                and button.style and button.style.showChargeText then
            local displayCountShown = false
            local hasCastCountText = HasCastCountText(buttonData)
            local conditionalCastCountSpellID
            if buttonData._hasDisplayCount or buttonData._displayCountFamily then
                local displayCount = button.count:GetText()
                if issecretvalue(displayCount) then
                    displayCountShown = true
                elseif displayCount and displayCount ~= "" then
                    displayCountShown = true
                end
            end
            if not hasCastCountText and buttonData._castCountCandidate then
                conditionalCastCountSpellID = GetConditionalCastCountSpellID(buttonData, cooldownSpellId)
            end

            if not displayCountShown and hasCastCountText then
                -- Cast-count text is only shown for explicitly supported
                -- spell families. Use the current live spell/override path
                -- when it belongs to that family.
                button._chargeText = nil
                local castCountSpellID = GetCastCountSpellID(buttonData, cooldownSpellId)
                local castCount = castCountSpellID and C_Spell.GetSpellCastCount(castCountSpellID)
                if castCountSpellID and issecretvalue(castCount) then
                    button.count:SetText(castCount)
                elseif castCountSpellID and not issecretvalue(castCount) and castCount and castCount > 0 then
                    button.count:SetText(castCount)
                else
                    button.count:SetText("")
                end
            elseif not displayCountShown and conditionalCastCountSpellID then
                -- Conditional cast-count text is tied to the live override spell
                -- identified by SPELL_UPDATE_USES. This keeps transformed spells
                -- like Thunderblast showing text without making the base spell
                -- render a stale or always-on count.
                button._chargeText = nil
                local castCount = C_Spell.GetSpellCastCount(conditionalCastCountSpellID)
                if issecretvalue(castCount) then
                    button.count:SetText(castCount)
                elseif castCount and castCount > 0 then
                    button.count:SetText(castCount)
                else
                    button.count:SetText("")
                end
            elseif not displayCountShown then
                button.count:SetText("")
            end
        elseif (buttonData._hasDisplayCount or buttonData._displayCountFamily or HasCastCountText(buttonData) or buttonData._castCountCandidate) and buttonData.type == "spell"
                and not (button._auraTrackingReady and button.style and button.style.showAuraStackText ~= false) then
            -- Count text disabled: ensure display/use-count and cast-count text is cleared.
            button.count:SetText("")
        elseif button._chargeText ~= nil then
            button._chargeText = nil
            button.count:SetText("")
        end
    end

    button._isOnGCD = isOnGCD or false
    -- Bar mode: suppress GCD-only display in bars (checked by UpdateBarFill OnUpdate).
    -- Skip for charge spells: their _durationObj is the recharge cycle, never the GCD.
    if button._isBar then
        button._barGCDSuppressed = fetchOk and isGCDOnly
            and not usesChargeBehavior and not buttonData.isPassive
    end

    -- Bar mode icon-only GCD swipe.
    if button._isBar and button.iconGCDCooldown then
        local showBarGCDSwipe = (style.showBarIcon ~= false)
            and style.showGCDSwipe == true
            and buttonData.type == "spell"
            and isOnGCD == true
        if showBarGCDSwipe then
            local gcdDurationObj = CooldownCompanion._gcdDurationObj
            if not gcdDurationObj and spellCooldownDuration then
                gcdDurationObj = spellCooldownDuration
            end
            if gcdDurationObj then
                local iconGCDCooldown = button.iconGCDCooldown
                iconGCDCooldown:SetDrawEdge(style.showCooldownSwipeEdge ~= false)
                iconGCDCooldown:SetReverse(style.cooldownSwipeReverse or false)
                iconGCDCooldown:Hide()
                iconGCDCooldown:SetCooldownFromDurationObject(gcdDurationObj)
            else
                button.iconGCDCooldown:Hide()
            end
        else
            button.iconGCDCooldown:Hide()
        end
    end

    -- Charge count tracking: detect whether the main cooldown (0 charges)
    -- is active.  Filter GCD so only real cooldown reads as true.
    -- Item and readable-spell paths are always safe. Restricted-spell fallbacks
    -- that depend on button.cooldown or isGCDOnly are gated on not auraOverrideActive.
    if usesChargeBehavior then
        -- Default to non-zero each tick; set true only when a current probe confirms zero.
        button._mainCDShown = false
        if buttonData.type == "item" then
            -- Items: 0 charges = on cooldown. No GCD to filter.
            local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
            button._mainCDShown = (chargeCount == 0)
        elseif buttonData.type == "spell"
           and button._chargeCountReadable == true
           and button._currentReadableCharges ~= nil then
            -- Readable charge count is the source of truth for zero-charge state.
            -- Prevents short lockout cooldowns (e.g., dragonriding flyout abilities)
            -- from being misclassified as "zero charges".
            button._mainCDShown = (button._currentReadableCharges == 0)
        elseif buttonData.type == "spell" and (buttonData._hasDisplayCount or buttonData._displayCountFamily) then
            -- Secret display counts do not expose a readable number in combat for
            -- some use-count spells. Do not guess zero-state from unrelated
            -- usability signals; leave the zero-state unknown instead.
            button._mainCDShown = false
        elseif buttonData.type == "spell" and usesChargeBehavior and buttonData.hasCharges then
            -- Restricted mode: charges unreadable (secret values).
            -- Action bar probe reflects the regular-cooldown DurationObject
            -- which is NOT charge-aware (isActive = isEnabled and startTime > 0
            -- and duration > 0).  It can report true during per-cast lockouts
            -- and recharge, so the _chargesSpent heuristic below guards both
            -- this path and the isActive fallback.
            local slotProbe = spellCooldownResult and spellCooldownResult.slotProbe
                or ProbeActionSlotCooldownForSpell(buttonData.id, cooldownSpellId)
            if slotProbe.shown ~= nil then
                button._mainCDShown = slotProbe.realShown == true
            elseif not auraOverrideActive then
                -- No action bar slot found; use the ignoreGCD-backed real cooldown state.
                if spellCooldownResult and spellCooldownResult.fetchOk then
                    button._mainCDShown = spellCooldownResult.state == COOLDOWN_STATE_COOLDOWN
                elseif spellCooldownInfo then
                    button._mainCDShown = spellRealCooldownShown
                else
                    button._mainCDShown = false
                end
            end
        end
    end

    -- Canonical zero-charge state for downstream visuals/visibility.
    -- _mainCDShown is the raw "main cooldown sweep shown" signal; suppress zero
    -- while we have explicit cast-history evidence that not all charges are spent.
    if usesChargeBehavior then
        -- Seed _chargesSpent when recharging without cast history (e.g. after
        -- /reload mid-recharge).  Defaults to maxCharges ("all spent") so the
        -- heuristic below does not suppress genuine zero-charge signals.
        -- OnSpellCast takes over on the next cast; full recharge resets the cycle.
        if button._chargeRecharging and not button._chargesSpent then
            button._chargesSpent = buttonData.maxCharges or 0
        end

        local zeroConfirmed = (button._mainCDShown == true)
        if zeroConfirmed
           and buttonData.type == "spell"
           and usesChargeBehavior
           and buttonData.hasCharges
           and button._chargeCountReadable ~= true then
            -- Heuristic: suppress zero-charge when cast history says charges remain.
            -- Applies to both the action bar probe and isActive fallback paths.
            -- The probe reflects the regular-cooldown DurationObject which is
            -- not charge-aware and can report true during lockouts/recharge;
            -- _chargesSpent provides authoritative cast-history evidence.
            local maxCharges = buttonData.maxCharges
            local spent = button._chargesSpent
            if maxCharges and maxCharges > 1 and spent and spent < maxCharges then
                zeroConfirmed = false
            end
        end
        button._zeroChargesConfirmed = zeroConfirmed
    else
        button._zeroChargesConfirmed = false
    end
    button._chargeState = ResolveChargeState(button, buttonData)

    -- Cooldown desaturation follows the canonical cooldown state, never the GCD.
    if buttonData.type == "item" then
        button._desatCooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    elseif usesChargeBehavior then
        button._desatCooldownActive = button._chargeState == CHARGE_STATE_ZERO
    elseif auraOverrideActive and auraProbeInfo then
        button._desatCooldownActive = (auraProbeRealCooldownShown and not auraProbeIsGCDOnly) or false
    else
        button._desatCooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
    end
    -- Track on-CD → off-CD transition for ready glow duration timer.
    -- desatWasActive is true only when the previous tick had an active cooldown,
    -- so nil → false (initial load) does NOT set a start time.
    if desatWasActive and button._desatCooldownActive == false then
        button._readyGlowStartTime = now
    elseif button._desatCooldownActive == true then
        button._readyGlowStartTime = nil
    end

    if usesChargeBehavior then
      if buttonData.type == "spell" and buttonData.hasCharges then
        -- Bar/text mode: charge bars are driven by the recharge DurationObject, not
        -- the main spell CD or GCD. Save and clear the main CD so recharge
        -- timing fully controls bar fill for charge spells.
        if (button._isBar or button._isText) and not auraOverrideActive and button._chargeDurationObj then
            button._durationObj = nil
        end

        local normalCooldownDisplayActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
            or (button._cooldownState == COOLDOWN_STATE_GCD and style.showGCDSwipe == true)
        if not auraOverrideActive and button._chargeDurationObj then
            if not button._isBar and not button._isText then
                if button._chargeCooldownVisualActive then
                    -- Icon mode: active recharge owns the shared cooldown frame.
                    button._durationObj = button._chargeDurationObj
                    button.cooldown:SetCooldownFromDurationObject(button._chargeDurationObj)
                elseif not normalCooldownDisplayActive then
                    button.cooldown:SetCooldown(0, 0)
                end
            elseif button._chargeRecharging then
                -- Bar/text mode: only set _durationObj if actually recharging
                button._durationObj = button._chargeDurationObj
            end
        elseif not button._isBar and not button._isText and not auraOverrideActive then
            -- Icon mode fallback: no chargeDurationObj, try fetching one.
            -- Only an active charge DurationObject may replace an existing GCD display.
            local chargeSpellID = cooldownSpellId or buttonData.id
            local fallbackDuration = C_Spell.GetSpellChargeDuration(chargeSpellID)
            local fallbackActive = DurationObjectShowsCooldown(fallbackDuration)
            button._chargeCooldownVisualActive = fallbackActive or nil
            if fallbackActive then
                button._chargeRecharging = true
                button._durationObj = fallbackDuration
                button.cooldown:SetCooldownFromDurationObject(fallbackDuration)
            elseif not normalCooldownDisplayActive then
                button.cooldown:SetCooldown(0, 0)
            end
        end

      end
    end

    if IsReadyGlowMaxChargeEligible(buttonData) then
        local readyGlowSpellID = cooldownSpellId or buttonData.id
        if button._readyGlowMaxChargesSpellID ~= readyGlowSpellID then
            button._readyGlowMaxChargesSpellID = readyGlowSpellID
            button._readyGlowMaxChargesStartTime = nil
            button._readyGlowMaxChargesActive = nil
        end

        local isCapped = IsReadyGlowAtMaxCharges(button, buttonData)
        if button._readyGlowMaxChargesActive ~= true and isCapped then
            button._readyGlowMaxChargesStartTime = now
        elseif not isCapped then
            button._readyGlowMaxChargesStartTime = nil
        end
        button._readyGlowMaxChargesActive = isCapped
    else
        button._readyGlowMaxChargesSpellID = nil
        button._readyGlowMaxChargesActive = nil
        button._readyGlowMaxChargesStartTime = nil
    end

    -- Item count display (inventory quantity for non-equipment tracked items)
    if buttonData.type == "item" and not buttonData.hasCharges and not IsItemEquippable(buttonData) then
        local count = C_Item.GetItemCount(buttonData.id)
        if button._itemCount ~= count then
            button._itemCount = count
            if count and count >= 1 then
                button.count:SetText(count)
            else
                button.count:SetText("")
            end
        end
    end

    -- Aura stack count display (aura-tracking spells with stackable auras)
    -- Text is a secret value in combat — pass through directly to SetText.
    -- Blizzard sets it to "" when stacks <= 1 and the count string when > 1.
    if button.auraStackCount and (button._auraTrackingReady or buttonData.isPassive or button._conditionalAuraStackTextPreview)
       and (style.showAuraStackText ~= false) then
        if button._auraActive or button._conditionalAuraStackTextPreview then
            button.auraStackCount:SetText(button._auraStackText or "")
        else
            button.auraStackCount:SetText("")
        end
    end

    -- Charge text color: three-state (zero / partial / max).
    -- Uses the canonical charge state resolved above.
    ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)

    -- Per-button sound alerts (Blizzard-scoped events, CDM-valid only).
    if buttonData.type == "spell" then
        local soundCfg = buttonData.soundAlerts
        local hasSoundConfig = soundCfg and type(soundCfg.events) == "table" and next(soundCfg.events) ~= nil
        if hasSoundConfig then
            local currentCharges
            local maxCharges
            local chargeRecharging = false
            local chargeCooldownStartTime
            if usesChargeBehavior then
                if button._currentReadableCharges ~= nil then
                    currentCharges = button._currentReadableCharges
                elseif charges and charges.currentCharges ~= nil
                   and not issecretvalue(charges.currentCharges) then
                    currentCharges = charges.currentCharges
                end

                if charges then
                    maxCharges = charges.maxCharges
                elseif buttonData.maxCharges and buttonData.maxCharges > 0 then
                    maxCharges = buttonData.maxCharges
                end

                chargeRecharging = button._chargeRecharging
                if charges and charges.cooldownStartTime ~= nil
                   and not issecretvalue(charges.cooldownStartTime) then
                    chargeCooldownStartTime = charges.cooldownStartTime
                end
            end

            local cooldownActive
            if usesChargeBehavior then
                -- Charge spells: cooldown-active means zero available charges.
                cooldownActive = button._chargeState == CHARGE_STATE_ZERO
            elseif auraOverrideActive then
                -- Aura visuals replace button.cooldown; reuse the shared
                -- probe computed above (same spell, same tick).
                if auraProbeInfo then
                    cooldownActive = auraProbeRealCooldownShown and not auraProbeIsGCDOnly
                else
                    cooldownActive = false
                end
            else
                -- Normal path: real cooldown ignores GCD-only presentation.
                cooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
            end

            self:UpdateButtonSoundAlerts(
                button,
                cooldownSpellId,
                isOnGCD or false,
                cooldownActive,
                auraOverrideActive,
                currentCharges,
                maxCharges,
                chargeRecharging,
                chargeCooldownStartTime
            )
        else
            button._sndInitialized = nil
        end
    end

    -- Per-button visibility evaluation (after charge tracking)
    button._procOverlayActive = procOverlayActive
    EvaluateButtonVisibility(button, buttonData, auraOverrideActive, procOverlayActive)
    button._rawVisibilityHidden = button._visibilityHidden
    button._rawVisibilityAlphaOverride = button._visibilityAlphaOverride

    local group = button._groupId and CooldownCompanion.db.profile.groups[button._groupId]
    local isTriggerPanel = group and group.displayMode == "trigger"
    local forceVisibleByUnlockPreview = group
        and group.parentContainerId
        and CooldownCompanion.IsContainerUnlockPreviewActive
        and CooldownCompanion:IsContainerUnlockPreviewActive(group.parentContainerId)
        and not isTriggerPanel
    if isTriggerPanel then
        button._visibilityHidden = true
        button._visibilityAlphaOverride = 0
    end

    -- Config panel QOL: selected buttons in column 2 are always fully visible.
    local forceVisibleByConfig = IsConfigButtonForceVisible(button)
    local forceVisibleByPreview = conditionalPreview ~= nil and not isTriggerPanel
    if forceVisibleByUnlockPreview or forceVisibleByPreview then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = 1
    elseif forceVisibleByConfig and not isTriggerPanel then
        button._visibilityHidden = false
        button._visibilityAlphaOverride = 1
    end
    button._forceVisibleByConfig = ((forceVisibleByConfig or forceVisibleByUnlockPreview or forceVisibleByPreview) and not isTriggerPanel) or nil

    -- Track visibility/force-visible state changes for compact layout reflow.
    local visibilityChanged = button._visibilityHidden ~= button._prevVisibilityHidden
    if visibilityChanged then
        button._prevVisibilityHidden = button._visibilityHidden
    end
    local forceVisibleChanged = button._forceVisibleByConfig ~= button._prevForceVisibleByConfig
    if forceVisibleChanged then
        button._prevForceVisibleByConfig = button._forceVisibleByConfig
    end
    if visibilityChanged or forceVisibleChanged then
        local groupFrame = button:GetParent()
        if groupFrame then groupFrame._layoutDirty = true end
    end

    -- Apply visibility alpha or early-return for hidden buttons
    if not group or not group.compactLayout then
        -- Non-compact mode: alpha=0 for hidden, restore for visible
        if button._visibilityHidden then
            button.cooldown:Hide()  -- prevent stale IsShown() across ticks
            if button._lastVisAlpha ~= 0 then
                button:SetAlpha(0)
                button._lastVisAlpha = 0
            end
            DispatchStandaloneTextureVisual(button)
            return  -- Skip all visual updates
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    else
        -- Compact mode: Show/Hide handled by UpdateGroupLayout
        if button._visibilityHidden then
            -- Prevent stale IsShown() across ticks. SetCooldown(0,0) does not
            -- auto-hide the CooldownFrame; without this, bar mode _mainCDShown
            -- and icon mode force-show both read stale true on next tick.
            button.cooldown:Hide()
            DispatchStandaloneTextureVisual(button)
            return  -- Skip visual updates for hidden buttons
        else
            local targetAlpha = button._visibilityAlphaOverride or 1
            if button._lastVisAlpha ~= targetAlpha then
                button:SetAlpha(targetAlpha)
                button._lastVisAlpha = targetAlpha
            end
        end
    end

    -- Unusable/out-of-range state for text mode {unusable}/{oor} conditionals
    if button._isText then
        if buttonData.isPassive then
            button._isUnusable = false
        elseif buttonData.type == "spell" then
            local spellID = button._displaySpellId or buttonData.id
            button._isUnusable = not C_Spell_IsSpellUsable(spellID)
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            local usable = IsUsableItem(buttonData.id)
            button._isUnusable = not usable
        else
            button._isUnusable = false
        end

        if buttonData.type == "spell" then
            button._isOutOfRange = button._spellOutOfRange or false
        elseif buttonData.type == "item" or buttonData.type == "equipitem" then
            -- C_Item.IsItemInRange is protected in combat for non-enemy targets (10.2.0)
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = IsItemInRange(buttonData.id, "target")
                button._isOutOfRange = (inRange == false)
            else
                button._isOutOfRange = false
            end
        else
            button._isOutOfRange = false
        end
    else
        button._isUnusable = false
        button._isOutOfRange = false
    end

    ApplyConditionalVisualPreview(
        button,
        buttonData,
        style,
        conditionalPreview,
        now,
        usesChargeBehavior
    )
    ApplyChargeTextColor(button, buttonData, style, usesChargeBehavior)

    -- Mode-specific visual dispatch
    if button._isText then
        UpdateTextDisplay(button)
    elseif button._isBar then
        UpdateBarDisplay(button)
        DispatchStandaloneTextureVisual(button)
    else
        UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, isGCDOnly)
        UpdateIconModeGlows(button, buttonData, style, procOverlayActive)
        DispatchStandaloneTextureVisual(button)
    end
end
