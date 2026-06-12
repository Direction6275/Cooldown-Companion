--[[
    CooldownCompanion - Core/CooldownRefresh.lua: same-frame cooldown refresh
    coalescing and ticker-skip bookkeeping.

    Current refresh state fields:
    - _cooldownsDirty: true when the next ticker pass must confirm cooldown state.
    - _cooldownDirtySerial: monotonic dirty marker bumped by MarkCooldownsDirty.
    - _lastCooldownRefreshSource/_lastCooldownRefreshSerial: last completed
      refresh metadata used to let cooldown-event refreshes satisfy one ticker pass.
    - _queuedCooldownRefreshSource: pending queued refresh source; also the
      queue-pending flag checked by the ticker.
    - _queuedCooldownRefreshCanSkipTicker/_queuedCooldownRefreshSkipSerial:
      queued preservation of cooldown-event skip eligibility.
    - _cooldownImmediateRefreshThisFrame: latch allowing only the first
      immediate refresh in a frame to walk synchronously.
    - _cooldownRefreshQueueFrame/_cooldownRefreshQueueArmed: hidden frame and
      arm flag used to flush queued work on the next OnUpdate boundary.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local function MergeCooldownRefreshSource(currentSource, newSource)
    newSource = newSource or "event"
    if not currentSource or currentSource == newSource then
        return newSource
    end
    return "event"
end

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

function CooldownCompanion:RunCooldownRefresh(source)
    self:UpdateAllCooldowns()
    self._lastCooldownRefreshSerial = self._cooldownDirtySerial or 0
    self._lastCooldownRefreshSource = source
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
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._cooldownImmediateRefreshThisFrame = nil

    local source = self._queuedCooldownRefreshSource
    local canSkipTicker = self._queuedCooldownRefreshCanSkipTicker
    local skipSerial = self._queuedCooldownRefreshSkipSerial
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCanSkipTicker = nil
    self._queuedCooldownRefreshSkipSerial = nil
    if source then
        self:RunCooldownRefresh(source)
        -- Non-dirty queued work should not erase a satisfied cooldown-event
        -- dirty serial, because that would re-enable the next ticker walk.
        if canSkipTicker and skipSerial == (self._cooldownDirtySerial or 0) then
            self._lastCooldownRefreshSource = "cooldown-event"
            self._lastCooldownRefreshSerial = skipSerial
        end
    end
end

function CooldownCompanion:QueueCooldownRefresh(source)
    local dirtySerial = self._cooldownDirtySerial or 0
    local queuedRefreshCanSkipTicker = self._queuedCooldownRefreshCanSkipTicker
        and self._queuedCooldownRefreshSkipSerial == dirtySerial
    local lastRefreshCanSkipTicker = self._lastCooldownRefreshSource == "cooldown-event"
        and self._lastCooldownRefreshSerial == dirtySerial
    local canSkipTicker = source == "cooldown-event"
        or queuedRefreshCanSkipTicker
        or lastRefreshCanSkipTicker

    self._queuedCooldownRefreshSource = MergeCooldownRefreshSource(self._queuedCooldownRefreshSource, source)
    self._queuedCooldownRefreshCanSkipTicker = canSkipTicker or nil
    self._queuedCooldownRefreshSkipSerial = canSkipTicker and dirtySerial or nil
    self:EnsureCooldownRefreshQueueFrame()
end

function CooldownCompanion:RunImmediateCooldownRefresh(source)
    if self._cooldownImmediateRefreshThisFrame then
        self:QueueCooldownRefresh(source)
        return
    end

    local dirtySerial = self._cooldownDirtySerial or 0
    local queuedRefreshCanSkipTicker = self._queuedCooldownRefreshCanSkipTicker
        and self._queuedCooldownRefreshSkipSerial == dirtySerial
    local canSkipTicker = source == "cooldown-event" or queuedRefreshCanSkipTicker
    local skipSerial = canSkipTicker and dirtySerial or nil

    source = MergeCooldownRefreshSource(self._queuedCooldownRefreshSource, source)
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCanSkipTicker = nil
    self._queuedCooldownRefreshSkipSerial = nil
    self._cooldownImmediateRefreshThisFrame = true
    self:EnsureCooldownRefreshQueueFrame()
    self:RunCooldownRefresh(source)
    if canSkipTicker and skipSerial == (self._cooldownDirtySerial or 0) then
        self._lastCooldownRefreshSource = "cooldown-event"
        self._lastCooldownRefreshSerial = skipSerial
    end
end

function CooldownCompanion:CanSkipTickerCooldownRefresh()
    -- Only cooldown-event refreshes can satisfy the next ticker pass. Aura,
    -- target, and other dirty paths keep their normal ticker confirmation.
    return self._cooldownsDirty
        and self._lastCooldownRefreshSource == "cooldown-event"
        and self._lastCooldownRefreshSerial == (self._cooldownDirtySerial or 0)
end

function CooldownCompanion:ResetCooldownRefreshState()
    if self._cooldownRefreshQueueFrame then
        self._cooldownRefreshQueueFrame:SetScript("OnUpdate", nil)
    end
    self._cooldownRefreshQueueArmed = nil
    self._queuedCooldownRefreshSource = nil
    self._queuedCooldownRefreshCanSkipTicker = nil
    self._queuedCooldownRefreshSkipSerial = nil
    self._cooldownImmediateRefreshThisFrame = nil
end
