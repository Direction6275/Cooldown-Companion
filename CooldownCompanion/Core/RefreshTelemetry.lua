--[[
    CooldownCompanion - Core/RefreshTelemetry.lua: dev-gated, observe-only
    telemetry for the cooldown refresh scheduler. Active only when the
    CC_DevBridge dev addon is loaded (checked at PLAYER_LOGIN). Records:
    - dirty-mark counts by source
    - queue request counts by source, plus per-flush source history
    - every UpdateAllCooldowns pass: time, source, detail, queue history,
      dirty-at-start (ticker passes), frames/buttons walked, duration (ms)
    - ticker skips (satisfied cooldown-event serial)
    Read via CooldownCompanion:GetRefreshTelemetry(); reset via
    CooldownCompanion:ResetRefreshTelemetry(). Never alters refresh behavior.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local RING_SIZE = 2000          -- pass log entries (field-reuse ring)
local QUEUE_HISTORY_CAP = 16    -- max sources remembered per queue flush

local T = {
    enabled = false,
    dirtyCounts = {},           -- source -> count
    queueCounts = {},           -- source -> count
    passCounts = {},            -- source -> count
    tickerSkips = 0,
    passLog = {},               -- ring buffer of reused entry tables
    passCursor = 0,             -- last written index (1..RING_SIZE)
    passTotal = 0,              -- total passes recorded since reset
    queueHistory = {},          -- pending sources for the next flush
    queueHistoryLen = 0,
    -- pending attribution for the next UpdateAllCooldowns call
    pendingSource = nil,
    pendingDetail = nil,
    pendingHist = nil,
    pendingDirtyAtStart = nil,
}
ST.RefreshTelemetry = T

function T:CountDirty(source)
    self.dirtyCounts[source] = (self.dirtyCounts[source] or 0) + 1
end

function T:CountQueue(source)
    self.queueCounts[source] = (self.queueCounts[source] or 0) + 1
    if self.queueHistoryLen < QUEUE_HISTORY_CAP then
        self.queueHistoryLen = self.queueHistoryLen + 1
        self.queueHistory[self.queueHistoryLen] = source
    end
end

function T:CountSkip()
    self.tickerSkips = self.tickerSkips + 1
end

-- Consume and clear the accumulated queue-source history (called at flush).
function T:TakeQueueHistory()
    if self.queueHistoryLen == 0 then return nil end
    local hist = table.concat(self.queueHistory, ",", 1, self.queueHistoryLen)
    self.queueHistoryLen = 0
    return hist
end

function T:ClearQueueHistory()
    self.queueHistoryLen = 0
end

function T:SetPending(source, detail, hist, dirtyAtStart)
    self.pendingSource = source
    self.pendingDetail = detail
    self.pendingHist = hist
    self.pendingDirtyAtStart = dirtyAtStart
end

-- Called from the end of UpdateAllCooldowns when enabled.
function T:RecordPass(frames, buttons, ms)
    local source = self.pendingSource or "direct-untagged"
    self.passCounts[source] = (self.passCounts[source] or 0) + 1
    self.passTotal = self.passTotal + 1
    local cursor = self.passCursor % RING_SIZE + 1
    self.passCursor = cursor
    local entry = self.passLog[cursor]
    if not entry then
        entry = {}
        self.passLog[cursor] = entry
    end
    entry.t = GetTime()
    entry.src = source
    entry.detail = self.pendingDetail
    entry.hist = self.pendingHist
    entry.dirtyAtStart = self.pendingDirtyAtStart
    entry.frames = frames
    entry.buttons = buttons
    entry.ms = ms
    self.pendingSource = nil
    self.pendingDetail = nil
    self.pendingHist = nil
    self.pendingDirtyAtStart = nil
end

-- One-line tag helper for direct UpdateAllCooldowns callsites.
function ST.TagRefreshPass(source, detail)
    if T.enabled then
        T:SetPending(source, detail, nil, nil)
    end
end

function CooldownCompanion:GetRefreshTelemetry()
    return T
end

function CooldownCompanion:ResetRefreshTelemetry()
    wipe(T.dirtyCounts)
    wipe(T.queueCounts)
    wipe(T.passCounts)
    T.tickerSkips = 0
    T.passCursor = 0
    T.passTotal = 0
    T.queueHistoryLen = 0
    T.pendingSource = nil
    T.pendingDetail = nil
    T.pendingHist = nil
    T.pendingDirtyAtStart = nil
    -- Entry tables in passLog are reused; stale entries beyond passTotal are
    -- ignored by readers (passTotal + passCursor define the valid window).
end

-- Gate: enable only when the CC_DevBridge dev addon is present. Checked at
-- PLAYER_LOGIN because addon load order is not guaranteed at file-load time.
local gateFrame = CreateFrame("Frame")
gateFrame:RegisterEvent("PLAYER_LOGIN")
gateFrame:SetScript("OnEvent", function(frame)
    frame:UnregisterAllEvents()
    local _, loaded = C_AddOns.IsAddOnLoaded("CC_DevBridge")
    if loaded then
        T.enabled = true
    end
end)
