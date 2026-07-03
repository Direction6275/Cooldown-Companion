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
    - _tickerIdleEligible (set in GroupOperations.UpdateAllCooldowns): true after
      a completed walk that saw no time-animated button. Read by
      IsIdleTickerSkipEligible; it gates the idle ticker skip
      (CanSkipIdleTickerRefresh) and the observe-only would-skip count.
    - _tickerSkipStreak: consecutive idle skips since the last walk; forces a 1s
      safety walk (TICKER_MAX_CONSECUTIVE_SKIPS). Reset by every walk.

    Invariants:
    - Only cooldown-event requests write _cooldownRefreshSatisfiedSerial.
    - MarkCooldownsDirty is the only invalidator; stale satisfied serials are
      inert because they cannot match a later dirty serial.
    - Queued cooldown-event requests satisfy the serial captured at queue time.
      If another dirty mark lands before the flush, the later ticker walks
      instead of skipping. That is intentionally conservative: displays can only
      be fresher, never staler.
    - Refresh telemetry fields are observe-only and never change scheduling.
    - The idle ticker skip (PR F2) can only suppress the ticker's clean broad
      walk. It never suppresses dirty ticks, queued flushes, immediate
      refreshes, or direct passes, and never touches serials or queue state.
    - _tickerIdleEligible is latched true only by a completed
      UpdateAllCooldowns walk that saw no time-animated button; every other
      writer may only clear it. Eligibility is never older than the last walk.
    - The skip fails open: combat, config, a disabled cd-done signal, or any
      unclassified state forces walking. A 1s safety walk runs while skipping.
    - cd-done marks come from ST.OnButtonCooldownDone (ButtonFrame/Helpers.lua)
      and are ordinary MarkCooldownsDirty calls; the hidden kill switch only
      stops the marks, never adds skips.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- F2: while the idle skip is active, force a full walk at least once per this
-- many ticks (1.0s at the 0.1s ticker) so nothing can go stale longer than the
-- safety window even if the predicate ever mis-latched. Skip at most this many
-- ticks in a row; the next tick walks.
local TICKER_MAX_CONSECUTIVE_SKIPS = 9

-- F2: authoritative "config UI is open" check (read-only, nil-safe; the same
-- indicator used elsewhere, e.g. AuraTexturesDisplay). Conditional previews are
-- the only time-animated config surface, so an open config forces walking.
local function IsConfigWindowOpen()
    local cs = ST._configState
    return cs and cs.configFrame and cs.configFrame.frame
        and cs.configFrame.frame:IsShown() and true or false
end

local function CooldownRefreshQueueOnUpdate(frame)
    local addon = frame._cooldownCompanion
    if addon then
        addon:FlushQueuedCooldownRefresh()
    end
end

function CooldownCompanion:MarkCooldownsDirty(source)
    self._cooldownsDirty = true
    self._cooldownDirtySerial = (self._cooldownDirtySerial or 0) + 1
    local T = ST.RefreshTelemetry
    if T and T.enabled then
        T:CountDirty(source or "unspecified")
    end
end

function CooldownCompanion:ClearCooldownsDirty()
    self._cooldownsDirty = false
end

-- F3 hidden kill switch (no config UI). Disable the cooldown-expiry signal
-- live (no reload) with:
--   /run CooldownCompanion:SetCooldownDoneSignalDisabled(true)
-- Persists in db.global; default (absent) = signal enabled.
function CooldownCompanion:SetCooldownDoneSignalDisabled(disabled)
    disabled = disabled == true
    self.db.global.cooldownDoneSignalDisabled = disabled or nil
    self._cooldownDoneSignalOff = disabled
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
        local T = ST.RefreshTelemetry
        if T and T.enabled then
            T:SetPending("queue-flush", queuedSource, T:TakeQueueHistory(), nil)
        end
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
    local T = ST.RefreshTelemetry
    if T and T.enabled then
        T:CountQueue(source or "event")
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

    local T = ST.RefreshTelemetry
    if self._queuedCooldownRefreshSource and T and T.enabled then
        T:ClearQueueHistory()
    end
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    if T and T.enabled then
        T:SetPending("immediate", source, nil, nil)
    end
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

-- F2 idle-skip eligibility (inner predicate, shared by the PR-A observe-only
-- would-skip counter and, later, the PR-B live skip, so the two can never
-- drift). This is everything except the user switch. It latches on
-- _tickerIdleEligible, which a completed walk sets true only when it saw no
-- time-animated button. Fail open: any term unclear forces a walk.
function CooldownCompanion:IsIdleTickerSkipEligible()
    return not self._cooldownsDirty
        and not self._queuedCooldownRefreshSource
        and self._tickerIdleEligible == true
        and not self._inCombatForTicker
        and not self._cooldownDoneSignalOff
end

-- F2 live-skip predicate: the shared inner eligibility plus the config-open
-- interlock. Fail open on every term (any false forces a walk).
function CooldownCompanion:CanSkipIdleTickerRefresh()
    return self:IsIdleTickerSkipEligible()
        and not IsConfigWindowOpen()
end

function CooldownCompanion:TickCooldownRefresh()
    local T = ST.RefreshTelemetry
    local telemetryOn = T and T.enabled
    local dirtyAtStart
    if telemetryOn then
        dirtyAtStart = self._cooldownsDirty and true or false
    end
    if self._queuedCooldownRefreshSource then
        self:FlushQueuedCooldownRefresh()
        return false
    end
    if self:CanSkipTickerCooldownRefresh() then
        if telemetryOn then T:CountSkip() end
        return true
    end
    -- F2 shadow: keep counting would-skips even with the live skip on, so the
    -- soak can cross-check tickerIdleSkips (+ safety-tick walks) against it.
    if telemetryOn and self:IsIdleTickerSkipEligible() then
        T:CountWouldSkip()
    end
    -- F2 live skip: early-return a clean idle tick when the switch is on and the
    -- predicate holds, except after TICKER_MAX_CONSECUTIVE_SKIPS skips in a row,
    -- where the next tick walks anyway (safety-tick) so nothing goes stale
    -- longer than ~1s. This only ever suppresses the clean broad walk; queued
    -- flushes and dirty ticks were already handled above.
    if self:CanSkipIdleTickerRefresh() then
        if (self._tickerSkipStreak or 0) >= TICKER_MAX_CONSECUTIVE_SKIPS then
            if telemetryOn then
                T:SetPending("safety-tick", nil, nil, false)
            end
            self:UpdateAllCooldowns()   -- resets _tickerSkipStreak
            return false
        end
        self._tickerSkipStreak = (self._tickerSkipStreak or 0) + 1
        if telemetryOn then T:CountIdleSkip() end
        return true
    end
    if telemetryOn then
        T:SetPending(dirtyAtStart and "ticker-dirty" or "ticker-clean",
            nil, nil, dirtyAtStart)
    end
    self:UpdateAllCooldowns()
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
end
