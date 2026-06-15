--[[
    CooldownCompanion - Core/CooldownRefresh.lua: same-frame cooldown refresh
    coalescing and ticker-skip bookkeeping.

    Refresh state fields:
    - _cooldownsDirty: true when the next ticker pass must confirm cooldown state.
    - _cooldownDirtySerial: monotonic dirty marker bumped by MarkCooldownsDirty.
    - _queuedCooldownRefreshSource: pending queued refresh source; also the
      queue-pending flag checked by the ticker. Last writer wins; this is only
      a debug breadcrumb, not skip eligibility.
    - _queuedCooldownRefreshEvent: event name for the pending queued refresh;
      kept separate so actionbar cooldown work can be satisfied by narrower
      same-frame refreshes.
    - _queuedCooldownRefreshSatisfiedSerial: dirty serial captured when a
      queued refresh is expected to cover the pending dirty state.
    - _cooldownRefreshSatisfiedSerial: dirty serial covered by an executed
      refresh that can safely satisfy the next ticker pass.
    - _cooldownImmediateRefreshThisFrame: latch allowing only the first
      immediate refresh in a frame to walk synchronously.
    - _cooldownRefreshQueueFrame/_cooldownRefreshQueueArmed: parentless helper
      frame and arm flag used to flush queued work on the next OnUpdate
      boundary. The frame must stay shown; hidden frames do not receive OnUpdate.
    - _cooldownPeriodicRefreshActive: true when the last full cooldown pass
      saw active timing/hold state that still needs 0.1s confirmation.
    - _lastCooldownMaintenanceRefreshAt: GetTime() of the last full cooldown
      pass. Idle ticker passes use it for low-frequency fallback polling.

    Invariants:
    - Only explicitly satisfying refresh sources write _cooldownRefreshSatisfiedSerial.
    - MarkCooldownsDirty is the only invalidator; stale satisfied serials are
      inert because they cannot match a later dirty serial.
    - Queued satisfying requests satisfy the serial captured at queue time.
      If another dirty mark lands before the flush, the later ticker walks
      instead of skipping. That is intentionally conservative: displays can only
      be fresher, never staler.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local type = type

local IDLE_COOLDOWN_MAINTENANCE_INTERVAL = 1.0

local function RefreshSourceSatisfiesDirty(source)
    return source == "cooldown-event"
        or source == "target-event"
end

local function GetRefreshTime()
    return type(GetTime) == "function" and GetTime() or nil
end

local function CooldownRefreshQueueOnUpdate(frame)
    local addon = frame._cooldownCompanion
    if addon then
        addon:FlushQueuedCooldownRefresh()
    end
end

local function RunCooldownRefresh(addon)
    addon:UpdateAllCooldowns()
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
    local satisfiedSerial = self._queuedCooldownRefreshSatisfiedSerial
    self:ResetCooldownRefreshState()

    if queuedSource then
        RunCooldownRefresh(self)
        if satisfiedSerial then
            self._cooldownRefreshSatisfiedSerial = satisfiedSerial
        end
    end
end

function CooldownCompanion:QueueCooldownRefresh(source, eventName)
    self._queuedCooldownRefreshSource = source or "event"
    self._queuedCooldownRefreshEvent = eventName
    if RefreshSourceSatisfiesDirty(source) then
        self._queuedCooldownRefreshSatisfiedSerial = self._cooldownDirtySerial or 0
    else
        self._queuedCooldownRefreshSatisfiedSerial = nil
        self._cooldownRefreshSatisfiedSerial = nil
    end
    self:EnsureCooldownRefreshQueueFrame()
end

function CooldownCompanion:SatisfyQueuedCooldownRefresh(source)
    local queuedSource = self._queuedCooldownRefreshSource
    if not queuedSource or (source and queuedSource ~= source) then
        return false
    end

    local satisfiedSerial = self._queuedCooldownRefreshSatisfiedSerial
    self:ResetCooldownRefreshState()
    self._cooldownRefreshSatisfiedSerial = satisfiedSerial
    return true
end

function CooldownCompanion:RunImmediateCooldownRefresh(source)
    if self._cooldownImmediateRefreshThisFrame then
        self:QueueCooldownRefresh(source)
        return
    end

    local satisfiedSerial
    if RefreshSourceSatisfiesDirty(source) then
        satisfiedSerial = self._cooldownDirtySerial or 0
    end

    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshEvent = nil
    self._queuedCooldownRefreshSatisfiedSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    RunCooldownRefresh(self)
    if satisfiedSerial then
        self._cooldownRefreshSatisfiedSerial = satisfiedSerial
    end
end

function CooldownCompanion:CanSkipTickerCooldownRefresh()
    -- Only refresh sources that ran after the matching dirty mark can satisfy
    -- the next ticker pass.  Aura and other viewer-sensitive paths keep their
    -- normal ticker confirmation.
    return self._cooldownsDirty
        and self._cooldownRefreshSatisfiedSerial == (self._cooldownDirtySerial or 0)
end

function CooldownCompanion:ShouldRunTickerCooldownRefresh()
    if self._cooldownsDirty then
        return true
    end

    local now = GetRefreshTime()
    if not now then
        return true
    end

    local lastRefreshAt = self._lastCooldownMaintenanceRefreshAt
    if not lastRefreshAt then
        return true
    end

    local interval = self._cooldownIdleMaintenanceInterval or IDLE_COOLDOWN_MAINTENANCE_INTERVAL
    return now - lastRefreshAt >= interval
end

function CooldownCompanion:TickCooldownRefresh()
    if self._queuedCooldownRefreshSource then
        self:FlushQueuedCooldownRefresh()
        return false
    end
    if self:CanSkipTickerCooldownRefresh() then
        return true
    end
    local shouldRunFullRefresh = self:ShouldRunTickerCooldownRefresh()
    if self._cooldownPeriodicRefreshActive
            and not self._cooldownsDirty
            and not shouldRunFullRefresh then
        if self.UpdateActiveCooldownButtons then
            self:UpdateActiveCooldownButtons()
            return false
        end
    end
    if not shouldRunFullRefresh then
        return true
    end
    RunCooldownRefresh(self)
    return false
end

function CooldownCompanion:ResetCooldownRefreshState()
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshEvent = nil
    self._queuedCooldownRefreshSatisfiedSerial = nil
    self._cooldownImmediateRefreshThisFrame = nil
end
