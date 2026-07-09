--[[
    CooldownCompanion - Core/RefreshTelemetry.lua: dev-gated, observe-only
    telemetry for the cooldown refresh scheduler. Active only when the
    CC_DevBridge dev addon is loaded (checked at PLAYER_LOGIN). Records:
    - dirty-mark counts by source
    - queue request counts by source, plus per-flush source history
    - every UpdateAllCooldowns pass: time, source, detail, queue history,
      dirty-at-start (ticker passes), frames/buttons walked, duration (ms),
      idle-eligibility at pass start and whether a time-render canary fired
    - ticker skips (satisfied cooldown-event serial)
    - F2 (observe-only): would-skip count under the live-skip predicate and
      false-idle count (a time-render canary that fired during a pass that
      began clean and idle-eligible)
    - forcing attribution (observe-only): which classifier term(s) pinned each
      broad walk (per-term button counts in forcingCounts, per-walk term
      combinations in passForceCombos, and a "force" field on passLog entries)
      -- names what keeps the idle skip from engaging
    - routed drops: cooldown-event fires the router dropped as index misses
      (no dirty mark, no walk) -- the riskiest router outcome, watched so a
      wrong drop starving a button is observable
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
    -- F2 (observe-only): ticks the live-skip predicate accepted, whether then
    -- skipped or walked as a safety tick (consistency invariant:
    -- wouldSkipTotal == tickerIdleSkips + "safety-tick" pass count), and times
    -- a time-render canary fired during a pass that began clean + idle-eligible
    -- (a proven-wrong "false idle"; the diagnostic target is 0).
    -- Neither ever changes scheduling.
    wouldSkipTotal = 0,
    falseIdleTotal = 0,
    -- F2 live skip: clean idle ticks actually suppressed. The "safety-tick"
    -- pass source counts the forced ~1/s walks while skipping.
    tickerIdleSkips = 0,
    -- Combat ticker floor: count of pooled pandemic FX frames the edge-hook has
    -- installed on (coverage). Pairs with the "pandemic-edge" dirtyCounts entry
    -- (fires) to gauge the edge-hook. The pool is small and reused across DoTs,
    -- so this is a handful, not one-per-DoT.
    pandemicEdgeHooks = 0,
    -- Forcing attribution (observe-only): which NoteButtonTimeState term(s)
    -- forced walking. forcingCounts = term -> per-button occurrences across all
    -- broad walks; passForceCombos = sorted "term(+term)" combo -> walks pinned
    -- by exactly that set; passForceTerms = per-walk scratch (wiped each pass).
    forcingCounts = {},
    passForceCombos = {},
    passForceTerms = {},
    -- Router index-miss drops (fires handled with no dirty mark and no walk).
    routedDrops = 0,
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
    -- F2: eligibility snapshot at pass start, and whether a canary fired.
    pendingIdleEligible = nil,
    pendingRenderedTime = nil,
}
ST.RefreshTelemetry = T

-- Every recording method gates on T.enabled internally, so call sites do not
-- need (and should not add) their own enabled guards. Callers still check
-- T.enabled where telemetry drives extra caller-side work (timing captures,
-- dirty-at-start snapshots, per-term evaluation).
function T:CountDirty(source)
    if not self.enabled then return end
    self.dirtyCounts[source] = (self.dirtyCounts[source] or 0) + 1
end

function T:CountQueue(source)
    if not self.enabled then return end
    self.queueCounts[source] = (self.queueCounts[source] or 0) + 1
    if self.queueHistoryLen < QUEUE_HISTORY_CAP then
        self.queueHistoryLen = self.queueHistoryLen + 1
        self.queueHistory[self.queueHistoryLen] = source
    end
end

function T:CountSkip()
    if not self.enabled then return end
    self.tickerSkips = self.tickerSkips + 1
end

-- F2 cross-check: a clean tick the live-skip predicate accepted (then either
-- skipped or walked as a safety tick). Observe-only.
function T:CountWouldSkip()
    if not self.enabled then return end
    self.wouldSkipTotal = self.wouldSkipTotal + 1
end

-- F2 live skip: a clean idle tick was actually suppressed (early return).
function T:CountIdleSkip()
    if not self.enabled then return end
    self.tickerIdleSkips = self.tickerIdleSkips + 1
end

-- Combat ticker floor: an edge-hook was installed on a pooled pandemic FX frame.
function T:CountPandemicEdgeHook()
    if not self.enabled then return end
    self.pandemicEdgeHooks = self.pandemicEdgeHooks + 1
end

-- Forcing attribution: a classifier term forced this button to keep the ticker
-- walking. Only broad walks are relevant to idle-skip pinning (mirrors
-- NoteTimeRender), so ignore routed mini-pass renders.
function T:CountForce(term)
    if not self.enabled then return end
    if not CooldownCompanion._cooldownUpdatePassActive then return end
    self.forcingCounts[term] = (self.forcingCounts[term] or 0) + 1
    self.passForceTerms[term] = true
end

-- Wrapper for call sites inside UpdateButtonCooldown, which sits at the
-- Lua 5.1 60-upvalue ceiling and cannot capture a new file-local; it reaches
-- this through the CooldownCompanion upvalue it already holds.
function CooldownCompanion:CountTickerForce(term)
    T:CountForce(term)
end

-- The router dropped a cooldown-event fire as an index miss.
function CooldownCompanion:CountRoutedDrop()
    if T.enabled then
        T.routedDrops = T.routedDrops + 1
    end
end

-- F2 canary: a time-driven remaining render happened. Only renders that occur
-- during a broad UpdateAllCooldowns walk are relevant to skip safety -- the
-- idle skip suppresses that walk, not the OnUpdate self-animation that runs
-- between passes -- so ignore anything fired outside a pass. A render during a
-- pass that began clean and idle-eligible is a proven false idle: the predicate
-- said "nothing time-animated" yet something drew remaining time.
function T:NoteTimeRender()
    if not self.enabled then return end
    if not CooldownCompanion._cooldownUpdatePassActive then return end
    self.pendingRenderedTime = true
    if self.pendingIdleEligible and self.pendingDirtyAtStart == false then
        self.falseIdleTotal = self.falseIdleTotal + 1
    end
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
    if not self.enabled then return end
    self.pendingSource = source
    self.pendingDetail = detail
    self.pendingHist = hist
    self.pendingDirtyAtStart = dirtyAtStart
    -- F2: snapshot the eligibility latched by the previous completed walk, so a
    -- canary firing during this pass is judged against the state the live skip
    -- decision would have used (eligibility always lags one walk). Reset the
    -- per-pass canary flag.
    self.pendingIdleEligible = CooldownCompanion._tickerIdleEligible == true
    self.pendingRenderedTime = nil
end

-- Called from the end of UpdateAllCooldowns when enabled.
function T:RecordPass(frames, buttons, ms)
    local source = self.pendingSource or "direct-untagged"
    self.passCounts[source] = (self.passCounts[source] or 0) + 1
    self.passTotal = self.passTotal + 1
    -- Forcing attribution: fold this walk's distinct forcing terms into a
    -- stable sorted combo key (nil when nothing forced -- an idle-eligible walk).
    local force
    if next(self.passForceTerms) then
        -- Reused scratch (wiped each pass) instead of a per-pass allocation.
        local terms = self.comboScratch
        if not terms then
            terms = {}
            self.comboScratch = terms
        end
        wipe(terms)
        for term in pairs(self.passForceTerms) do
            terms[#terms + 1] = term
        end
        table.sort(terms)
        force = table.concat(terms, "+")
        self.passForceCombos[force] = (self.passForceCombos[force] or 0) + 1
        wipe(self.passForceTerms)
    end
    local cursor = self.passCursor % RING_SIZE + 1
    self.passCursor = cursor
    local entry = self.passLog[cursor]
    if not entry then
        entry = {}
        self.passLog[cursor] = entry
    end
    entry.t = GetTime()
    entry.force = force
    entry.src = source
    entry.detail = self.pendingDetail
    entry.hist = self.pendingHist
    entry.dirtyAtStart = self.pendingDirtyAtStart
    entry.idleEligible = self.pendingIdleEligible
    entry.renderedTime = self.pendingRenderedTime
    entry.frames = frames
    entry.buttons = buttons
    entry.ms = ms
    self.pendingSource = nil
    self.pendingDetail = nil
    self.pendingHist = nil
    self.pendingDirtyAtStart = nil
    self.pendingIdleEligible = nil
    self.pendingRenderedTime = nil
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
    wipe(T.forcingCounts)
    wipe(T.passForceCombos)
    wipe(T.passForceTerms)
    T.tickerSkips = 0
    T.wouldSkipTotal = 0
    T.falseIdleTotal = 0
    T.tickerIdleSkips = 0
    T.routedDrops = 0
    T.passCursor = 0
    T.passTotal = 0
    T.queueHistoryLen = 0
    T.pendingSource = nil
    T.pendingDetail = nil
    T.pendingHist = nil
    T.pendingDirtyAtStart = nil
    T.pendingIdleEligible = nil
    T.pendingRenderedTime = nil
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
