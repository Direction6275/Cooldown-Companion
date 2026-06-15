--[[
    CooldownCompanion - Core/CooldownRefresh.lua: same-frame cooldown refresh
    coalescing and ticker-skip bookkeeping.

    Refresh state fields:
    - _cooldownsDirty: true when the next ticker pass must confirm cooldown state.
    - _cooldownDirtySerial: monotonic dirty marker bumped by MarkCooldownsDirty.
    - _queuedCooldownRefreshSource: pending queued refresh source; also the
      queue-pending flag checked by the ticker. Last writer wins; this is only
      a debug breadcrumb, not skip eligibility.
    - _queuedCooldownRefreshReason: structured pending reason passed to the
      eventual refresh walk. Ambiguous combinations escalate to full refresh.
    - _queuedCooldownRefreshCooldownEventSerial: dirty serial captured when a
      queued cooldown-event request enters the queue.
    - _cooldownRefreshSatisfiedSerial: dirty serial covered by an executed
      cooldown-event refresh.
    - _cooldownImmediateRefreshThisFrame: latch allowing only the first
      immediate refresh in a frame to walk synchronously.
    - _cooldownRefreshQueueFrame/_cooldownRefreshQueueArmed: parentless helper
      frame and arm flag used to flush queued work on the next OnUpdate
      boundary. The frame must stay shown; hidden frames do not receive OnUpdate.

    Invariants:
    - Only cooldown-event requests write _cooldownRefreshSatisfiedSerial.
    - MarkCooldownsDirty is the only invalidator; stale satisfied serials are
      inert because they cannot match a later dirty serial.
    - Queued cooldown-event requests satisfy the serial captured at queue time.
      If another dirty mark lands before the flush, the later ticker walks
      instead of skipping. That is intentionally conservative: displays can only
      be fresher, never staler.
    - Clean ticker passes do not perform a full cooldown walk. They only run the
      scoped periodic path when active buttons have semantic polling needs.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local function CooldownRefreshQueueOnUpdate(frame)
    local addon = frame._cooldownCompanion
    if addon then
        addon:FlushQueuedCooldownRefresh()
    end
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
    local queuedReason = self._queuedCooldownRefreshReason
    local cooldownEventSerial = self._queuedCooldownRefreshCooldownEventSerial
    self:ResetCooldownRefreshState()

    if queuedSource then
        self:UpdateAllCooldowns(queuedReason)
        if cooldownEventSerial then
            self._cooldownRefreshSatisfiedSerial = cooldownEventSerial
        end
    end
end

function CooldownCompanion:QueueCooldownRefresh(source)
    local reason = self:NormalizeCooldownRefreshReason(source, "queued-refresh")
    self._queuedCooldownRefreshReason = self:CombineCooldownRefreshReasons(self._queuedCooldownRefreshReason, reason)
    self._queuedCooldownRefreshSource = self:GetCooldownRefreshReasonSource(self._queuedCooldownRefreshReason or source)

    source = self:GetCooldownRefreshReasonSource(source)
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

    local reason = self:NormalizeCooldownRefreshReason(source, "immediate-refresh")
    if self._queuedCooldownRefreshSource then
        reason = self:CombineCooldownRefreshReasons(self._queuedCooldownRefreshReason, reason)
    end

    local refreshSource = self:GetCooldownRefreshReasonSource(source)
    local cooldownEventSerial = self._queuedCooldownRefreshCooldownEventSerial
    if refreshSource == "cooldown-event" then
        cooldownEventSerial = self._cooldownDirtySerial or 0
    end

    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshReason = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    self:UpdateAllCooldowns(reason)
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

function CooldownCompanion:TickCooldownRefresh()
    if self._queuedCooldownRefreshSource then
        local queuedReasonScoped = self:IsScopedCooldownRefreshReason(self._queuedCooldownRefreshReason)
        self:FlushQueuedCooldownRefresh()
        if queuedReasonScoped and self._cooldownsDirty and not self:CanSkipTickerCooldownRefresh() then
            self:UpdateAllCooldowns()
        end
        return false
    end
    if self:CanSkipTickerCooldownRefresh() then
        return true
    end
    if self._cooldownsDirty then
        self:UpdateAllCooldowns()
        return false
    end
    if self:HasPeriodicCooldownRefreshCandidates() then
        self:UpdateAllCooldowns({
            kind = "periodic",
            source = "ticker",
        })
        return false
    end
    return true
end

function CooldownCompanion:ResetCooldownRefreshState()
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshReason = nil
    self._queuedCooldownRefreshCooldownEventSerial = nil
    self._cooldownImmediateRefreshThisFrame = nil
end
