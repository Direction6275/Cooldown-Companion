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
    - _cooldownRefreshSatisfiedSerial: dirty serial covered by an executed
      cooldown-event refresh.
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
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local COOLDOWN_STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN or "cooldown"
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING or "missing"
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO or "zero"

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
end

function CooldownCompanion:BeginCooldownRefreshEligibilityBuild()
    local build = self._cooldownRefreshEligibilityBuildCache
    if not build then
        build = {}
        self._cooldownRefreshEligibilityBuildCache = build
    else
        build.actionbarFallbackRequired = nil
        build.periodicMaintenanceRequired = nil
    end
    self._cooldownRefreshEligibilityBuild = build
end

function CooldownCompanion:RecordButtonCooldownRefreshEligibility(button, buttonData, displayMode)
    local build = self._cooldownRefreshEligibilityBuild
    if not build or not button then return end

    if button._actionSlotCooldownFallback == true or button._actionSlotCooldownCandidate == true then
        build.actionbarFallbackRequired = true
    end

    if HasActiveIconCooldownText(button, buttonData) then
        build.periodicMaintenanceRequired = true
    end
    if HasCooldownDrivenVisualMaintenance(button, buttonData) then
        build.periodicMaintenanceRequired = true
    end
    if button._isText == true then
        build.periodicMaintenanceRequired = true
    end
    if button._cooldownDeferred == true then
        build.periodicMaintenanceRequired = true
    end
    if button._auraGraceStart ~= nil or button._targetSwitchAt ~= nil then
        build.periodicMaintenanceRequired = true
    end
    if HasTimedReadyGlow(button) then
        build.periodicMaintenanceRequired = true
    end
    if HasSoundAlerts(buttonData) then
        build.periodicMaintenanceRequired = true
    end
    if buttonData and buttonData._rotationAssistantVirtual == true then
        build.periodicMaintenanceRequired = true
    end
    if IsTriggerRuntime(button, displayMode) then
        build.periodicMaintenanceRequired = true
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
end

function CooldownCompanion:MarkCooldownsDirty()
    self._cooldownsDirty = true
    self._cooldownDirtySerial = (self._cooldownDirtySerial or 0) + 1
end

function CooldownCompanion:ClearCooldownsDirty()
    self._cooldownsDirty = false
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
    self:ResetCooldownRefreshState(queuedSource == nil)

    if queuedSource then
        self:UpdateAllCooldowns()
        if cooldownEventSerial then
            self._cooldownRefreshSatisfiedSerial = cooldownEventSerial
        end
    end
end

function CooldownCompanion:QueueCooldownRefresh(source)
    self._queuedCooldownRefreshSource = source or "event"
    if source == "cooldown-event" then
        self._queuedCooldownRefreshCooldownEventSerial = self._cooldownDirtySerial or 0
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

    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    self:UpdateAllCooldowns()
    if cooldownEventSerial then
        self._cooldownRefreshSatisfiedSerial = cooldownEventSerial
    end
end

function CooldownCompanion:CanSkipTickerCooldownRefresh()
    -- Only cooldown-event refreshes can satisfy the next ticker pass. Aura,
    -- target, and other dirty paths keep their normal ticker confirmation.
    return self._cooldownsDirty
        and self._cooldownRefreshSatisfiedSerial == (self._cooldownDirtySerial or 0)
end

function CooldownCompanion:RecordActionbarCooldownPulse()
    self._actionbarCooldownPulsePending = true
end

function CooldownCompanion:ClearActionbarCooldownPulse()
    self._actionbarCooldownPulsePending = nil
end

function CooldownCompanion:GetActionbarCooldownPulseDecision(cooldownEventSatisfied)
    if not self._actionbarCooldownPulsePending then
        return false
    end
    if self._queuedCooldownRefreshSource then
        return false
    end
    if self._cooldownsDirty and not cooldownEventSatisfied then
        return false
    end
    if not self._cooldownRefreshEligibilityKnown then
        return false
    end
    if self._activeActionbarCooldownFallbackRequired then
        return false
    end
    if self._activeCooldownPeriodicMaintenanceRequired and not cooldownEventSatisfied then
        return false
    end
    return true
end

function CooldownCompanion:TickCooldownRefresh()
    if self._queuedCooldownRefreshSource then
        self:FlushQueuedCooldownRefresh()
        return false
    end

    local cooldownEventSatisfied = self:CanSkipTickerCooldownRefresh()
    local actionbarFallbackRequired = false
    if self._actionbarCooldownPulsePending and (not self._cooldownsDirty or cooldownEventSatisfied) then
        local canSkipActionbarPulse = self:GetActionbarCooldownPulseDecision(cooldownEventSatisfied)
        if canSkipActionbarPulse then
            self:ClearActionbarCooldownPulse()
            return true
        end
        actionbarFallbackRequired = true
    end

    if cooldownEventSatisfied and not actionbarFallbackRequired then
        self:ClearActionbarCooldownPulse()
        return true
    end

    self:UpdateAllCooldowns()
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
    self._cooldownImmediateRefreshThisFrame = nil
    if not preserveActionbarPulse then
        self:ClearActionbarCooldownPulse()
    end
end
