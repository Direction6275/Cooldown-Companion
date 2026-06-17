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

local function AddReason(reasons, seen, reason)
    if not reason or seen[reason] then return end
    seen[reason] = true
    reasons[#reasons + 1] = reason
end

local function HasSoundAlerts(buttonData)
    local cfg = buttonData and buttonData.soundAlerts
    return cfg and type(cfg.events) == "table" and next(cfg.events) ~= nil
end

local function HasTimedReadyGlow(button)
    if not button then return false end
    local style = button.style
    local duration = style and (style.readyGlowDuration or 0) or 0
    if duration <= 0 then
        return false
    end

    local now = GetTime()
    local function WindowNeedsRefresh(startTime)
        if startTime == nil then return false end
        return (now - startTime) <= duration or button._readyGlowActive == true
    end

    return WindowNeedsRefresh(button._readyGlowStartTime)
        or WindowNeedsRefresh(button._readyGlowMaxChargesStartTime)
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
    self._activeActionbarCooldownFallbackReasons = nil
    self._activeCooldownPeriodicMaintenanceReasons = nil
end

function CooldownCompanion:BeginCooldownRefreshEligibilityBuild()
    self._cooldownRefreshEligibilityBuild = {
        actionbarFallbackReasons = {},
        actionbarFallbackSeen = {},
        periodicMaintenanceReasons = {},
        periodicMaintenanceSeen = {},
    }
end

function CooldownCompanion:RecordButtonCooldownRefreshEligibility(button, buttonData, displayMode)
    local build = self._cooldownRefreshEligibilityBuild
    if not build or not button then return end

    if button._actionSlotCooldownFallback == true then
        AddReason(build.actionbarFallbackReasons, build.actionbarFallbackSeen, "action-slot-fallback")
    end

    if button._isText == true then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "text-mode")
    end
    if button._cooldownDeferred == true then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "deferred-cooldown")
    end
    if button._auraGraceStart ~= nil or button._targetSwitchAt ~= nil then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "pending-aura-hold")
    end
    if HasTimedReadyGlow(button) then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "ready-glow-window")
    end
    if HasSoundAlerts(buttonData) then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "sound-alert")
    end
    if buttonData and buttonData._rotationAssistantVirtual == true then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "rotation-assistant")
    end
    if IsTriggerRuntime(button, displayMode) then
        AddReason(build.periodicMaintenanceReasons, build.periodicMaintenanceSeen, "trigger-runtime")
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
    self._activeActionbarCooldownFallbackRequired = #build.actionbarFallbackReasons > 0 or nil
    self._activeCooldownPeriodicMaintenanceRequired = #build.periodicMaintenanceReasons > 0 or nil
    self._activeActionbarCooldownFallbackReasons = #build.actionbarFallbackReasons > 0 and build.actionbarFallbackReasons or nil
    self._activeCooldownPeriodicMaintenanceReasons = #build.periodicMaintenanceReasons > 0 and build.periodicMaintenanceReasons or nil
end

function CooldownCompanion:GetActionbarCooldownEligibilityInfo()
    return {
        known = self._cooldownRefreshEligibilityKnown == true,
        invalidationReason = self._cooldownRefreshEligibilityInvalidationReason,
        actionbarFallbackRequired = self._activeActionbarCooldownFallbackRequired == true,
        actionbarFallbackReasons = self._activeActionbarCooldownFallbackReasons,
        periodicMaintenanceRequired = self._activeCooldownPeriodicMaintenanceRequired == true,
        periodicMaintenanceReasons = self._activeCooldownPeriodicMaintenanceReasons,
    }
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
    self:ResetCooldownRefreshState()

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

function CooldownCompanion:RecordActionbarCooldownPulse(event)
    self._actionbarCooldownPulsePending = true
    self._actionbarCooldownPulseEvent = event or "ACTIONBAR_UPDATE_COOLDOWN"
    self._actionbarCooldownPulseCount = (self._actionbarCooldownPulseCount or 0) + 1
end

function CooldownCompanion:ClearActionbarCooldownPulse()
    self._actionbarCooldownPulsePending = nil
    self._actionbarCooldownPulseEvent = nil
    self._actionbarCooldownPulseCount = nil
end

function CooldownCompanion:GetActionbarCooldownPulseDecision()
    if not self._actionbarCooldownPulsePending then
        return false, "no-actionbar-pulse"
    end
    if self._queuedCooldownRefreshSource then
        return false, "queued-refresh"
    end
    if self._cooldownsDirty then
        return false, "dirty"
    end
    if not self._cooldownRefreshEligibilityKnown then
        return false, self._cooldownRefreshEligibilityInvalidationReason or "eligibility-unknown"
    end
    if self._activeActionbarCooldownFallbackRequired then
        return false, "actionbar-fallback-required"
    end
    if self._activeCooldownPeriodicMaintenanceRequired then
        return false, "periodic-maintenance-required"
    end
    return true, "pulse-only"
end

function CooldownCompanion:GetActionbarCooldownFallbackReason(decision)
    local eligibility = self:GetActionbarCooldownEligibilityInfo()
    return {
        kind = "actionbar-cooldown",
        source = "actionbar-cooldown-event",
        event = self._actionbarCooldownPulseEvent or "ACTIONBAR_UPDATE_COOLDOWN",
        origin = "ticker",
        broad = true,
        actionbarPulseDecision = decision,
        actionbarPulseCount = self._actionbarCooldownPulseCount,
        actionbarFallbackRequired = eligibility.actionbarFallbackRequired,
        actionbarFallbackReasons = eligibility.actionbarFallbackReasons,
        periodicMaintenanceRequired = eligibility.periodicMaintenanceRequired,
        periodicMaintenanceReasons = eligibility.periodicMaintenanceReasons,
        eligibilityKnown = eligibility.known,
    }
end

function CooldownCompanion:TickCooldownRefresh()
    if self._queuedCooldownRefreshSource then
        self:FlushQueuedCooldownRefresh()
        return false
    end
    if self:CanSkipTickerCooldownRefresh() then
        self:ClearActionbarCooldownPulse()
        return true
    end

    local actionbarOnlyReason
    if self._actionbarCooldownPulsePending and not self._cooldownsDirty then
        local canSkipActionbarPulse, decision = self:GetActionbarCooldownPulseDecision()
        if canSkipActionbarPulse then
            self:ClearActionbarCooldownPulse()
            return true
        end
        actionbarOnlyReason = self:GetActionbarCooldownFallbackReason(decision)
    end

    self:UpdateAllCooldowns(actionbarOnlyReason)
    self:ClearActionbarCooldownPulse()
    return false
end

function CooldownCompanion:ResetCooldownRefreshState()
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._cooldownImmediateRefreshThisFrame = nil
    self:ClearActionbarCooldownPulse()
end
