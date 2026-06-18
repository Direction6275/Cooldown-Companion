--[[
    CooldownCompanion - Core/CooldownRefresh.lua: same-frame cooldown refresh
    coalescing and ticker-skip bookkeeping.

    Refresh state fields:
    - _cooldownsDirty: true when the next ticker pass must confirm cooldown state.
    - _cooldownDirtySerial: monotonic dirty marker bumped by MarkCooldownsDirty.
    - _queuedCooldownRefreshSource: pending queued refresh source; also the
      queue-pending flag checked by the ticker. Last writer wins; this is only
      a debug breadcrumb, not skip eligibility.
    - _queuedCooldownRefreshCooldownEventSerial: dirty serial captured when a
      queued cooldown-event request enters the queue.
    - _queuedCooldownRefreshTargetDirtySerial/_queuedCooldownRefreshTargetTransitionSerial:
      target-family state captured when a queued target request enters the
      queue.
    - _queuedCooldownRefreshTargetSource: first queued target-family source
      covered by the pending broad flush.
    - _cooldownRefreshSatisfiedSerial: dirty serial covered by an executed
      cooldown-event refresh.
    - _targetRefreshTransitionSerial: monotonic target-state marker bumped by
      PLAYER_TARGET_CHANGED.
    - _targetRefreshSatisfiedTransitionSerial/_targetRefreshSatisfiedDirtySerial:
      target-family broad work that covered the current transition and, when
      dirty, the serial it covered.
    - _targetRefreshCleanTickerSkipTransitionSerial: one-shot clean ticker
      confirmation covered by the target-exists synchronous probe.
    - _targetRefreshPendingTransitionSerial: target-clear dirty confirmation
      waiting for its first broad pass.
    - _cooldownImmediateRefreshThisFrame: latch allowing only the first
      immediate refresh in a frame to walk synchronously.
    - _cooldownRefreshQueueFrame/_cooldownRefreshQueueArmed: parentless helper
      frame and arm flag used to flush queued work on the next OnUpdate
      boundary. The frame must stay shown; hidden frames do not receive OnUpdate.
    - _actionbarCooldownPulsePending: true when a raw ACTIONBAR_UPDATE_COOLDOWN
      pulse has arrived and the next ticker must decide whether it is safe to
      skip the clean broad pass.
    - _cooldownRefreshEligibilityKnown: true after a broad pass has rebuilt
      cached active-surface eligibility for actionbar fallback and periodic
      maintenance. Unknown eligibility falls back to broad work.

    Invariants:
    - Only cooldown-event requests write _cooldownRefreshSatisfiedSerial.
    - MarkCooldownsDirty is the only invalidator; stale satisfied serials are
      inert because they cannot match a later dirty serial.
    - Queued cooldown-event requests satisfy the serial captured at queue time.
      If another dirty mark lands before the flush, the later ticker walks
      instead of skipping. That is intentionally conservative: displays can only
      be fresher, never staler.
    - Target-family duplicate skips require either the same target transition or
      the exact dirty serial already covered by a target-family broad pass.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local EntryRuntime = ST.EntryRuntime or {}
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN or "cooldown"
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING or "missing"
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO or "zero"
local TARGET_REFRESH_SOURCES = {
    ["target-event"] = true,
    ["target-aura-event"] = true,
    ["unit-target-event"] = true,
    ["target-ticker"] = true,
}

local function IsTargetRefreshSource(source)
    return TARGET_REFRESH_SOURCES[source] == true
end

local function CaptureTargetRefreshState()
    if type(UnitExists) ~= "function" or not UnitExists("target") then
        return false, nil, true
    end
    if type(UnitGUID) ~= "function" then
        return true, nil, false
    end
    local guid = UnitGUID("target")
    if not guid then
        return true, nil, false
    end
    return true, guid, true
end

local function HasSoundAlerts(buttonData)
    local cfg = buttonData and buttonData.soundAlerts
    return cfg and type(cfg.events) == "table" and next(cfg.events) ~= nil
end

local function ReadyGlowWindowNeedsRefresh(startTime, now, duration, active)
    if startTime == nil then return false end
    return (now - startTime) <= duration or active == true
end

local function HasTimedReadyGlow(button)
    if not button then return false end
    local style = button.style
    local duration = style and (style.readyGlowDuration or 0) or 0
    if duration <= 0 then
        return false
    end

    local now = GetTime()
    return ReadyGlowWindowNeedsRefresh(button._readyGlowStartTime, now, duration, button._readyGlowActive)
        or ReadyGlowWindowNeedsRefresh(button._readyGlowMaxChargesStartTime, now, duration, button._readyGlowActive)
end

local function HasActiveIconCooldownText(button, buttonData)
    if not (button and button._cdTextRegion) then return false end
    if button._isBar or button._isText then return false end

    local style = button.style or {}
    local auraTextActive = button._auraPrimarySwipeActive == true
        or button._conditionalAuraDurationTextPreview == true
    if auraTextActive then
        if style.showAuraText == false then
            return false
        end
    else
        if style.showCooldownText == false or button._hideCooldownChargesActive then
            return false
        end
        if buttonData and buttonData.isPassive then
            return false
        end
    end

    return button._durationObj ~= nil
        or button._auraDurationObj ~= nil
        or button._auraCooldownStart ~= nil
        or button._chargeCooldownVisualActive == true
        or button._secondaryCdActive == true
end

local RecordPeriodicMaintenance

local function ClearTable(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function AddUniqueReason(list, seen, reason)
    if not reason or seen[reason] then return end
    seen[reason] = true
    list[#list + 1] = reason
end

local function ClearReasonTracking(build)
    ClearTable(build.periodicMaintenanceReasons)
    ClearTable(build.periodicMaintenanceSeen)
    ClearTable(build.safeTextWidgetMaintenanceReasons)
    ClearTable(build.safeTextWidgetMaintenanceSeen)
    ClearTable(build.unprovenIconTextMaintenanceReasons)
    ClearTable(build.unprovenIconTextMaintenanceSeen)
end

local function EnsureReasonTracking(build)
    build.periodicMaintenanceReasons = build.periodicMaintenanceReasons or {}
    build.periodicMaintenanceSeen = build.periodicMaintenanceSeen or {}
    build.safeTextWidgetMaintenanceReasons = build.safeTextWidgetMaintenanceReasons or {}
    build.safeTextWidgetMaintenanceSeen = build.safeTextWidgetMaintenanceSeen or {}
    build.unprovenIconTextMaintenanceReasons = build.unprovenIconTextMaintenanceReasons or {}
    build.unprovenIconTextMaintenanceSeen = build.unprovenIconTextMaintenanceSeen or {}
end

local function CopyReasonList(list)
    if not list or #list == 0 then return nil end
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function IsSafeTextWidgetMaintenanceOnly(button, buttonData)
    if not buttonData then return false end
    if not HasActiveIconCooldownText(button, buttonData) then return false end
    if button._chargeCooldownVisualActive == true or button._secondaryCdActive == true then
        return false
    end
    return button._durationObj ~= nil
        or button._auraDurationObj ~= nil
        or button._auraCooldownStart ~= nil
end

local function SafeTextWidgetTimingStillActive(button)
    if not button then return false end
    local durationObjectShowsCooldown = EntryRuntime.DurationObjectShowsCooldown
    if type(durationObjectShowsCooldown) ~= "function" then
        return true
    end

    local sawTimingSource = false
    if button._durationObj ~= nil then
        sawTimingSource = true
        if durationObjectShowsCooldown(button._durationObj) then
            return true
        end
    end
    if button._auraDurationObj ~= nil then
        sawTimingSource = true
        if durationObjectShowsCooldown(button._auraDurationObj) then
            return true
        end
    end
    if button._auraCooldownStart ~= nil then
        sawTimingSource = true
        local duration = button._auraCooldownDuration or 0
        if duration > 0 and type(GetTime) == "function" and (GetTime() - button._auraCooldownStart) < duration then
            return true
        end
    end

    return not sawTimingSource
end

local function RecordIconCooldownTextMaintenance(build, button, buttonData)
    if not HasActiveIconCooldownText(button, buttonData) then
        return
    end
    if not buttonData then
        AddUniqueReason(build.unprovenIconTextMaintenanceReasons, build.unprovenIconTextMaintenanceSeen, "missing-button-data")
        RecordPeriodicMaintenance(build, false, "unproven-icon-text", false, true)
        return
    end

    local safeTextWidget = false
    local unproven = false
    if button._durationObj ~= nil then
        safeTextWidget = true
        AddUniqueReason(build.safeTextWidgetMaintenanceReasons, build.safeTextWidgetMaintenanceSeen, "duration-object")
    end
    if button._auraDurationObj ~= nil then
        safeTextWidget = true
        AddUniqueReason(build.safeTextWidgetMaintenanceReasons, build.safeTextWidgetMaintenanceSeen, "aura-duration-object")
    end
    if button._auraCooldownStart ~= nil then
        safeTextWidget = true
        AddUniqueReason(build.safeTextWidgetMaintenanceReasons, build.safeTextWidgetMaintenanceSeen, "aura-cooldown-start")
    end
    if button._chargeCooldownVisualActive == true then
        unproven = true
        AddUniqueReason(build.unprovenIconTextMaintenanceReasons, build.unprovenIconTextMaintenanceSeen, "charge-cooldown-visual")
    end
    if button._secondaryCdActive == true then
        unproven = true
        AddUniqueReason(build.unprovenIconTextMaintenanceReasons, build.unprovenIconTextMaintenanceSeen, "secondary-cooldown-text")
    end
    if not safeTextWidget and not unproven then
        unproven = true
        AddUniqueReason(build.unprovenIconTextMaintenanceReasons, build.unprovenIconTextMaintenanceSeen, "unknown-icon-text")
    end

    if safeTextWidget and not unproven then
        RecordPeriodicMaintenance(build, false, "safe-text-widget", true)
    else
        RecordPeriodicMaintenance(build, false, "unproven-icon-text", false, true)
    end
end

local function HasCooldownDrivenVisualMaintenance(button, buttonData)
    if not (button and buttonData) then return false end

    local style = button.style or {}
    local cooldownActive = button._cooldownState == COOLDOWN_STATE_COOLDOWN
        or button._desatCooldownActive == true
    local chargeState = button._chargeState
    local chargeMissingOrZero = chargeState == CHARGE_STATE_ZERO
        or chargeState == CHARGE_STATE_MISSING
    local chargeTransitionActive = chargeMissingOrZero
        or button._chargeRecharging == true
        or button._chargeCooldownVisualActive == true

    if cooldownActive
        and (style.desaturateOnCooldown
            or style.iconCooldownTintEnabled
            or buttonData.hideWhileOnCooldown
            or buttonData.hideWhileNotOnCooldown) then
        return true
    end

    if chargeTransitionActive
        and (buttonData.hideWhileOnCooldown
            or buttonData.hideWhileNotOnCooldown
            or buttonData.hideCooldownWithCharges) then
        return true
    end

    if chargeState == CHARGE_STATE_ZERO
        and (buttonData.hideWhileZeroCharges
            or buttonData.desaturateWhileZeroCharges) then
        return true
    end

    return false
end

local function IsTriggerRuntime(button, displayMode)
    if not button then return false end
    if displayMode == "trigger" then return true end

    local group = button._groupId
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[button._groupId]
        or nil
    local buttonData = button.buttonData
    return (not displayMode
            and group
            and CooldownCompanion.IsTriggerPanelGroup
            and CooldownCompanion:IsTriggerPanelGroup(group))
        or buttonData and type(buttonData.triggerConditions) == "table"
end

local function CooldownRefreshQueueOnUpdate(frame)
    local addon = frame._cooldownCompanion
    if addon then
        addon:FlushQueuedCooldownRefresh()
    end
end

function CooldownCompanion:InvalidateCooldownRefreshEligibility(reason)
    self._cooldownRefreshEligibilityKnown = nil
    self._cooldownRefreshEligibilityInvalidationReason = reason or "unknown"
    self._activeActionbarCooldownFallbackRequired = nil
    self._activeCooldownPeriodicMaintenanceRequired = nil
    self._activeTargetCooldownMaintenanceRequired = nil
    self._activeNonTargetCooldownMaintenanceRequired = nil
    self._activeSafeTextWidgetMaintenanceRequired = nil
    self._activeUnprovenIconTextMaintenanceRequired = nil
    self._activeOtherPeriodicMaintenanceRequired = nil
    self._activeCooldownPeriodicMaintenanceReasons = nil
    self._activeSafeTextWidgetMaintenanceReasons = nil
    self._activeUnprovenIconTextMaintenanceReasons = nil
    self._lastSafeTextWidgetMaintenanceCount = nil
end

function CooldownCompanion:BeginCooldownRefreshEligibilityBuild()
    local build = self._cooldownRefreshEligibilityBuildCache
    if not build then
        build = {}
        self._cooldownRefreshEligibilityBuildCache = build
    else
        build.actionbarFallbackRequired = nil
        build.periodicMaintenanceRequired = nil
        build.targetMaintenanceRequired = nil
        build.nonTargetMaintenanceRequired = nil
        build.safeTextWidgetMaintenanceRequired = nil
        build.unprovenIconTextMaintenanceRequired = nil
        build.otherPeriodicMaintenanceRequired = nil
        ClearReasonTracking(build)
    end
    EnsureReasonTracking(build)
    self._cooldownRefreshEligibilityBuild = build
end

RecordPeriodicMaintenance = function(build, targetMaintenance, reason, safeTextWidget, unprovenIconText)
    EnsureReasonTracking(build)
    build.periodicMaintenanceRequired = true
    AddUniqueReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, reason or "unknown")
    if safeTextWidget then
        build.safeTextWidgetMaintenanceRequired = true
    elseif unprovenIconText then
        build.unprovenIconTextMaintenanceRequired = true
    else
        build.otherPeriodicMaintenanceRequired = true
    end
    if targetMaintenance then
        build.targetMaintenanceRequired = true
    else
        build.nonTargetMaintenanceRequired = true
    end
end

function CooldownCompanion:RecordButtonCooldownRefreshEligibility(button, buttonData, displayMode)
    local build = self._cooldownRefreshEligibilityBuild
    if not build or not button then return end

    if button._actionSlotCooldownFallback == true or button._actionSlotCooldownCandidate == true then
        build.actionbarFallbackRequired = true
    end

    RecordIconCooldownTextMaintenance(build, button, buttonData)
    if HasCooldownDrivenVisualMaintenance(button, buttonData) then
        if IsSafeTextWidgetMaintenanceOnly(button, buttonData) then
            AddUniqueReason(build.safeTextWidgetMaintenanceReasons, build.safeTextWidgetMaintenanceSeen, "icon-visual-presentation")
            RecordPeriodicMaintenance(build, false, "safe-icon-visual-presentation", true)
        else
            RecordPeriodicMaintenance(build, false, "cooldown-driven-visual")
        end
    end
    if button._isText == true then
        RecordPeriodicMaintenance(build, false, "text-mode")
    end
    if button._cooldownDeferred == true then
        RecordPeriodicMaintenance(build, false, "deferred-cooldown")
    end
    if button._auraGraceStart ~= nil then
        RecordPeriodicMaintenance(build, false, "pending-aura-hold")
    end
    if button._targetSwitchAt ~= nil then
        RecordPeriodicMaintenance(build, true, "pending-aura-hold")
    end
    if HasTimedReadyGlow(button) then
        RecordPeriodicMaintenance(build, false, "ready-glow-window")
    end
    if HasSoundAlerts(buttonData) then
        RecordPeriodicMaintenance(build, false, "sound-alert")
    end
    if buttonData and buttonData._rotationAssistantVirtual == true then
        RecordPeriodicMaintenance(build, false, "rotation-assistant")
    end
    if IsTriggerRuntime(button, displayMode) then
        RecordPeriodicMaintenance(build, false, "trigger-runtime")
    end
end

function CooldownCompanion:FinishCooldownRefreshEligibilityBuild()
    local build = self._cooldownRefreshEligibilityBuild
    self._cooldownRefreshEligibilityBuild = nil
    if not build then
        self:InvalidateCooldownRefreshEligibility("missing-build")
        return
    end

    self._cooldownRefreshEligibilityKnown = true
    self._cooldownRefreshEligibilityInvalidationReason = nil
    self._activeActionbarCooldownFallbackRequired = build.actionbarFallbackRequired == true or nil
    self._activeCooldownPeriodicMaintenanceRequired = build.periodicMaintenanceRequired == true or nil
    self._activeTargetCooldownMaintenanceRequired = build.targetMaintenanceRequired == true or nil
    self._activeNonTargetCooldownMaintenanceRequired = build.nonTargetMaintenanceRequired == true or nil
    self._activeSafeTextWidgetMaintenanceRequired = build.safeTextWidgetMaintenanceRequired == true or nil
    self._activeUnprovenIconTextMaintenanceRequired = build.unprovenIconTextMaintenanceRequired == true or nil
    self._activeOtherPeriodicMaintenanceRequired = build.otherPeriodicMaintenanceRequired == true or nil
    self._activeCooldownPeriodicMaintenanceReasons = CopyReasonList(build.periodicMaintenanceReasons)
    self._activeSafeTextWidgetMaintenanceReasons = CopyReasonList(build.safeTextWidgetMaintenanceReasons)
    self._activeUnprovenIconTextMaintenanceReasons = CopyReasonList(build.unprovenIconTextMaintenanceReasons)
end

function CooldownCompanion:HasOnlySafeTextWidgetMaintenance()
    return self._activeSafeTextWidgetMaintenanceRequired == true
        and not self._activeUnprovenIconTextMaintenanceRequired
        and not self._activeOtherPeriodicMaintenanceRequired
        and not self._activeTargetCooldownMaintenanceRequired
end

function CooldownCompanion:GetActionbarCooldownEligibilityInfo()
    local safeTextOnly = self:HasOnlySafeTextWidgetMaintenance()
    return {
        known = self._cooldownRefreshEligibilityKnown == true,
        invalidationReason = self._cooldownRefreshEligibilityInvalidationReason,
        actionbarFallbackRequired = self._activeActionbarCooldownFallbackRequired == true,
        periodicMaintenanceRequired = self._activeCooldownPeriodicMaintenanceRequired == true,
        targetMaintenanceRequired = self._activeTargetCooldownMaintenanceRequired == true,
        nonTargetMaintenanceRequired = self._activeNonTargetCooldownMaintenanceRequired == true,
        safeTextWidgetMaintenanceRequired = self._activeSafeTextWidgetMaintenanceRequired == true,
        safeTextWidgetMaintenanceOnly = safeTextOnly == true,
        unprovenIconTextMaintenanceRequired = self._activeUnprovenIconTextMaintenanceRequired == true,
        otherPeriodicMaintenanceRequired = self._activeOtherPeriodicMaintenanceRequired == true,
        periodicMaintenanceReasons = self._activeCooldownPeriodicMaintenanceReasons,
        safeTextWidgetMaintenanceReasons = self._activeSafeTextWidgetMaintenanceReasons,
        unprovenIconTextMaintenanceReasons = self._activeUnprovenIconTextMaintenanceReasons,
        lastSafeTextWidgetMaintenanceCount = self._lastSafeTextWidgetMaintenanceCount,
    }
end

function CooldownCompanion:MarkCooldownsDirty()
    self._cooldownsDirty = true
    self._cooldownDirtySerial = (self._cooldownDirtySerial or 0) + 1
end

function CooldownCompanion:ClearCooldownsDirty()
    self._cooldownsDirty = false
end

function CooldownCompanion:BeginTargetCooldownRefreshTransition(reason)
    self._targetRefreshTransitionSerial = (self._targetRefreshTransitionSerial or 0) + 1
    self._targetRefreshTransitionReason = reason or "target"
    self._targetRefreshSatisfiedTransitionSerial = nil
    self._targetRefreshSatisfiedDirtySerial = nil
    self._targetRefreshSatisfiedSource = nil
    self._targetRefreshSatisfiedTargetExists = nil
    self._targetRefreshSatisfiedTargetGUID = nil
    self._targetRefreshCleanTickerSkipTransitionSerial = nil
    self._targetRefreshPendingTransitionSerial = nil
    return self._targetRefreshTransitionSerial
end

function CooldownCompanion:MarkTargetCooldownRefreshPending(transitionSerial)
    transitionSerial = transitionSerial or self._targetRefreshTransitionSerial
    if transitionSerial then
        self._targetRefreshPendingTransitionSerial = transitionSerial
    end
end

function CooldownCompanion:RecordTargetCooldownRefreshSatisfied(source, transitionSerial, dirtySerial, options)
    if not IsTargetRefreshSource(source) then return end

    transitionSerial = transitionSerial or self._targetRefreshTransitionSerial
    if transitionSerial
        and self._targetRefreshTransitionSerial
        and transitionSerial ~= self._targetRefreshTransitionSerial then
        return
    end

    local targetExists, targetGUID, targetStateKnown = CaptureTargetRefreshState()
    if not targetStateKnown then
        self._targetRefreshSatisfiedTransitionSerial = nil
        self._targetRefreshSatisfiedDirtySerial = nil
        self._targetRefreshSatisfiedSource = nil
        self._targetRefreshSatisfiedTargetExists = nil
        self._targetRefreshSatisfiedTargetGUID = nil
        self._targetRefreshCleanTickerSkipTransitionSerial = nil
        return
    end

    if dirtySerial == nil and self._cooldownsDirty then
        dirtySerial = self._cooldownDirtySerial or 0
    end

    self._targetRefreshSatisfiedTransitionSerial = transitionSerial
    self._targetRefreshSatisfiedDirtySerial = dirtySerial
    self._targetRefreshSatisfiedSource = source
    self._targetRefreshSatisfiedTargetExists = targetExists
    self._targetRefreshSatisfiedTargetGUID = targetGUID

    if transitionSerial and self._targetRefreshPendingTransitionSerial == transitionSerial then
        self._targetRefreshPendingTransitionSerial = nil
    end
    if options and options.allowCleanTickerSkip and transitionSerial and dirtySerial == nil then
        self._targetRefreshCleanTickerSkipTransitionSerial = transitionSerial
    end
end

function CooldownCompanion:IsTargetCooldownRefreshStateSatisfied()
    if self._targetRefreshSatisfiedTargetExists == nil then
        return false
    end
    local targetExists, targetGUID, targetStateKnown = CaptureTargetRefreshState()
    if not targetStateKnown or targetExists ~= self._targetRefreshSatisfiedTargetExists then
        return false
    end
    if not targetExists then
        return true
    end
    return targetGUID == self._targetRefreshSatisfiedTargetGUID
end

function CooldownCompanion:CanSkipTargetRefreshDuplicate(source)
    if not IsTargetRefreshSource(source) then return false end
    if self._queuedCooldownRefreshSource then return false end
    if source == "unit-target-event"
        and (not self._cooldownRefreshEligibilityKnown
            or self._activeTargetCooldownMaintenanceRequired) then
        return false
    end

    local transitionSerial = self._targetRefreshTransitionSerial
    if not transitionSerial or self._targetRefreshSatisfiedTransitionSerial ~= transitionSerial then
        return false
    end
    if not self:IsTargetCooldownRefreshStateSatisfied() then
        return false
    end

    if self._cooldownsDirty then
        return self._targetRefreshSatisfiedDirtySerial == (self._cooldownDirtySerial or 0)
    end
    return true
end

function CooldownCompanion:CanSkipCooldownEventTickerRefresh()
    return self._cooldownsDirty
        and self._cooldownRefreshSatisfiedSerial == (self._cooldownDirtySerial or 0)
end

function CooldownCompanion:CanSkipTargetTickerCooldownRefresh()
    if self._queuedCooldownRefreshSource then return false end
    if not self._cooldownRefreshEligibilityKnown then return false end
    if self._activeTargetCooldownMaintenanceRequired then return false end
    if self._activeNonTargetCooldownMaintenanceRequired then return false end
    if not self:IsTargetCooldownRefreshStateSatisfied() then
        return false
    end

    local transitionSerial = self._targetRefreshTransitionSerial
    if self._cooldownsDirty then
        if self._targetRefreshSatisfiedTransitionSerial
            and self._targetRefreshSatisfiedTransitionSerial ~= transitionSerial then
            return false
        end
        return self._targetRefreshSatisfiedDirtySerial == (self._cooldownDirtySerial or 0)
    end

    if not transitionSerial or self._targetRefreshSatisfiedTransitionSerial ~= transitionSerial then
        return false
    end
    return self._targetRefreshCleanTickerSkipTransitionSerial == transitionSerial
end

function CooldownCompanion:ConsumeTargetTickerCooldownRefreshSkip()
    self._targetRefreshCleanTickerSkipTransitionSerial = nil
end

function CooldownCompanion:RecordTargetPendingTickerRefreshSatisfied()
    local transitionSerial = self._targetRefreshPendingTransitionSerial
    if transitionSerial and transitionSerial == self._targetRefreshTransitionSerial then
        self:RecordTargetCooldownRefreshSatisfied("target-ticker", transitionSerial)
    end
    self._targetRefreshCleanTickerSkipTransitionSerial = nil
end

function CooldownCompanion:EnsureCooldownRefreshQueueFrame()
    if not self._cooldownRefreshQueueFrame then
        local frame = CreateFrame("Frame")
        frame._cooldownCompanion = self
        self._cooldownRefreshQueueFrame = frame
    end
    if not self._cooldownRefreshQueueArmed then
        self._cooldownRefreshQueueArmed = true
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", CooldownRefreshQueueOnUpdate)
    end
end

function CooldownCompanion:FlushQueuedCooldownRefresh()
    local queuedSource = self._queuedCooldownRefreshSource
    local cooldownEventSerial = self._queuedCooldownRefreshCooldownEventSerial
    local targetSource = self._queuedCooldownRefreshTargetSource
    local targetDirtySerial = self._queuedCooldownRefreshTargetDirtySerial
    local targetTransitionSerial = self._queuedCooldownRefreshTargetTransitionSerial
    self:ResetCooldownRefreshState(queuedSource == nil)

    if queuedSource then
        self:UpdateAllCooldowns()
        if cooldownEventSerial then
            self._cooldownRefreshSatisfiedSerial = cooldownEventSerial
        end
        if targetSource then
            self:RecordTargetCooldownRefreshSatisfied(targetSource, targetTransitionSerial, targetDirtySerial)
        else
            self:RecordTargetPendingTickerRefreshSatisfied()
        end
    end
end

function CooldownCompanion:QueueCooldownRefresh(source)
    self._queuedCooldownRefreshSource = source or "event"
    if source == "cooldown-event" then
        self._queuedCooldownRefreshCooldownEventSerial = self._cooldownDirtySerial or 0
    end
    if IsTargetRefreshSource(source) then
        self._queuedCooldownRefreshTargetSource = source
        self._queuedCooldownRefreshTargetDirtySerial = self._cooldownsDirty and (self._cooldownDirtySerial or 0) or nil
        self._queuedCooldownRefreshTargetTransitionSerial = self._targetRefreshTransitionSerial
    end
    self:EnsureCooldownRefreshQueueFrame()
end

function CooldownCompanion:RunImmediateCooldownRefresh(source)
    if self._cooldownImmediateRefreshThisFrame then
        self:QueueCooldownRefresh(source)
        return
    end

    local cooldownEventSerial
    if source == "cooldown-event" then
        cooldownEventSerial = self._cooldownDirtySerial or 0
    end
    local targetDirtySerial
    local targetTransitionSerial
    if IsTargetRefreshSource(source) then
        targetDirtySerial = self._cooldownsDirty and (self._cooldownDirtySerial or 0) or nil
        targetTransitionSerial = self._targetRefreshTransitionSerial
    end

    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._queuedCooldownRefreshTargetSource = nil
    self._queuedCooldownRefreshTargetDirtySerial = nil
    self._queuedCooldownRefreshTargetTransitionSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    self:UpdateAllCooldowns()
    if cooldownEventSerial then
        self._cooldownRefreshSatisfiedSerial = cooldownEventSerial
    end
    if IsTargetRefreshSource(source) then
        self:RecordTargetCooldownRefreshSatisfied(source, targetTransitionSerial, targetDirtySerial)
    end
end

function CooldownCompanion:CanSkipTickerCooldownRefresh()
    return self:CanSkipCooldownEventTickerRefresh()
        or self:CanSkipTargetTickerCooldownRefresh()
end

function CooldownCompanion:RecordActionbarCooldownPulse()
    self._actionbarCooldownPulsePending = true
end

function CooldownCompanion:ClearActionbarCooldownPulse()
    self._actionbarCooldownPulsePending = nil
end

function CooldownCompanion:RunSafeTextWidgetMaintenance()
    if type(self.ApplySafeIconTextWidgetMaintenance) ~= "function" then
        return false
    end

    local updated = 0
    if type(self.groupFrames) == "table" then
        for _, frame in pairs(self.groupFrames) do
            if frame and frame.IsShown and frame:IsShown() and type(frame.buttons) == "table" then
                for _, button in ipairs(frame.buttons) do
                    if IsSafeTextWidgetMaintenanceOnly(button, button.buttonData)
                        and SafeTextWidgetTimingStillActive(button)
                        and self:ApplySafeIconTextWidgetMaintenance(button, button.buttonData) ~= false then
                        updated = updated + 1
                    elseif IsSafeTextWidgetMaintenanceOnly(button, button.buttonData) then
                        return false
                    end
                end
            end
        end
    end

    self._lastSafeTextWidgetMaintenanceCount = updated
    return true
end

function CooldownCompanion:GetActionbarCooldownPulseDecision(cooldownEventSatisfied, targetRefreshSatisfied)
    if not self._actionbarCooldownPulsePending then
        return false
    end
    if self._queuedCooldownRefreshSource then
        return false
    end
    if self._cooldownsDirty and not (cooldownEventSatisfied or targetRefreshSatisfied) then
        return false
    end
    if not self._cooldownRefreshEligibilityKnown then
        return false
    end
    if self._activeActionbarCooldownFallbackRequired then
        return false
    end
    if self._activeCooldownPeriodicMaintenanceRequired and not cooldownEventSatisfied then
        return self:HasOnlySafeTextWidgetMaintenance()
            and type(self.ApplySafeIconTextWidgetMaintenance) == "function"
    end
    return true
end

function CooldownCompanion:TickCooldownRefresh()
    if self._queuedCooldownRefreshSource then
        self:FlushQueuedCooldownRefresh()
        return false
    end

    local cooldownEventSatisfied = self:CanSkipCooldownEventTickerRefresh()
    local targetRefreshSatisfied = self:CanSkipTargetTickerCooldownRefresh()
    local tickerRefreshSatisfied = cooldownEventSatisfied or targetRefreshSatisfied
    local actionbarFallbackRequired = false
    if self._actionbarCooldownPulsePending and (not self._cooldownsDirty or tickerRefreshSatisfied) then
        local canSkipActionbarPulse = self:GetActionbarCooldownPulseDecision(cooldownEventSatisfied, targetRefreshSatisfied)
        if canSkipActionbarPulse then
            if self._activeSafeTextWidgetMaintenanceRequired
                and not cooldownEventSatisfied
                and not self:RunSafeTextWidgetMaintenance() then
                self:UpdateAllCooldowns()
                self:RecordTargetPendingTickerRefreshSatisfied()
                self:ClearActionbarCooldownPulse()
                return false
            end
            self:ClearActionbarCooldownPulse()
            if targetRefreshSatisfied then
                self:ConsumeTargetTickerCooldownRefreshSkip()
            end
            return true
        end
        actionbarFallbackRequired = true
    end

    if tickerRefreshSatisfied and not actionbarFallbackRequired then
        self:ClearActionbarCooldownPulse()
        if targetRefreshSatisfied then
            self:ConsumeTargetTickerCooldownRefreshSkip()
        end
        return true
    end

    self:UpdateAllCooldowns()
    self:RecordTargetPendingTickerRefreshSatisfied()
    self:ClearActionbarCooldownPulse()
    return false
end

function CooldownCompanion:ResetCooldownRefreshState(preserveActionbarPulse)
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._queuedCooldownRefreshTargetSource = nil
    self._queuedCooldownRefreshTargetDirtySerial = nil
    self._queuedCooldownRefreshTargetTransitionSerial = nil
    self._cooldownImmediateRefreshThisFrame = nil
    if not preserveActionbarPulse then
        self:ClearActionbarCooldownPulse()
    end
end
