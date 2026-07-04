--[[
    CooldownCompanion - Core/CooldownRouting.lua: F1 3b readable-identity
    cooldown event router.

    When routing is enabled (SetCooldownRoutingEnabled; default ON as of F1 3b
    Commit G, disable with SetCooldownRoutingEnabled(false)), a
    readable-arg SPELL_UPDATE_COOLDOWN fire is resolved through the D3 spell
    index instead of triggering a broad walk:
      - index hit  -> the matched buttons are added to a pending batch that runs
        the full per-button pipeline (UpdateButtonCooldown) on the next OnUpdate
        boundary (a "mini-pass"), coalescing same-frame fires.
      - index miss -> the fire is DROPPED: no tracked button displays that
        identity, so nothing needs updating (policed live by the watchdog's
        mismatchDropOnly counter). A drop is only taken once the index-trust
        gate below has passed.
      - anything the router cannot fully classify, or any state that makes the
        index untrustworthy, falls back to today's broad path unchanged (fail
        open; accuracy is inviolable): secret/unreadable arg, nil (broadcast-
        form) arg, a matched button in a panel group (cross-button aggregate,
        D4 inventory A4/A5), a structural index rebuild pending or landed
        between enqueue and flush, or any rotation-assistant virtual button
        loaded (those are excluded from the index by design, so a drop could
        starve one -- SpellButtonIndex header).

    Runs beside the refresh scheduler, never through it (CooldownRefresh.lua
    header invariants): the mini-pass never marks dirty, never touches the
    scheduler serial/queue/latch state, and never sets _cooldownUpdatePassActive.
    It does reach NoteButtonTimeState through the shared per-button pipeline,
    which may push the F2 accumulators (_passTimeStateSeen, _tickerIdleEligible)
    in the conservative direction (forcing an extra walk) for a forced routed
    button -- never the permissive one: only a completed broad walk latches
    _tickerIdleEligible true, so a mini-pass can never cause a false idle-skip.
    The single sanctioned scheduler touch is the generation-escalation fail-open
    in the flush.

    Fire->buttons resolution is shared with the ShadowParity watchdog via
    CooldownCompanion:ForEachIndexedSpellButton, so "what the router routes" and
    "what the watchdog checks" are the same lookup by construction.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local issecretvalue = issecretvalue
local type = type
local wipe = wipe
local CreateFrame = CreateFrame

-- Pending routed batch: buttons to mini-pass at the next OnUpdate boundary.
-- Same-frame fires coalesce with set semantics (a button appears once).
-- Persists until FlushRoutedCooldownBatch clears it.
local batchButtons = {}     -- button -> true (dedup across the whole batch)
local batchOrder = {}       -- ordered buttons (1..batchCount); stale tail ignored
local batchCount = 0
local batchGeneration = nil -- index.generation stamped when the batch was armed

-- Per-fire scratch: one fire's matched buttons (union of the spellID bucket and
-- the distinct-baseID bucket), deduped within the fire, plus a panel-membership
-- flag. Reset at the top of every RouteCooldownEventFire.
local fireSeen = {}         -- button -> true within this fire
local fireList = {}
local fireCount = 0
local firePanel = false

-- A panel group (displayMode "textures"/"trigger") is a cross-button aggregate
-- (D4 inventory A4/A5): its visual ANDs cached per-row state, so updating only
-- the matched row can leave the panel reading stale inputs. One matched panel
-- member makes the whole fire broad -- fail open (panel-as-routing-unit is a
-- later refinement).
local function IsPanelButton(button)
    local groupId = button._groupId
    if not groupId then
        return false
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local mode = group and group.displayMode
    return mode == "textures" or mode == "trigger"
end

-- ForEachIndexedSpellButton callback: collect this fire's matched buttons
-- (deduped) and note whether any belongs to a panel group.
local function CollectFireButton(button)
    if not fireSeen[button] then
        fireSeen[button] = true
        fireCount = fireCount + 1
        fireList[fireCount] = button
        if IsPanelButton(button) then
            firePanel = true
        end
    end
end

local function ClearRoutedBatch()
    wipe(batchButtons)
    batchCount = 0
    batchGeneration = nil
    -- batchOrder entries beyond batchCount are never read; no need to wipe.
end

local function RoutedBatchOnUpdate(frame)
    local addon = frame._cooldownCompanion
    if addon then
        addon:FlushRoutedCooldownBatch()
    end
end

-- Dedicated parentless always-shown flush frame (mirrors the OnUpdate pattern
-- of EnsureCooldownRefreshQueueFrame -- NOT the scheduler's queue frame;
-- constraint 3). It disarms itself on flush and is re-armed by the next routed
-- fire, so an idle routing world costs no OnUpdate.
function CooldownCompanion:EnsureRoutedBatchFrame()
    if not self._routedBatchFrame then
        local frame = CreateFrame("Frame")
        frame._cooldownCompanion = self
        self._routedBatchFrame = frame
    end
    if not self._routedBatchArmed then
        self._routedBatchArmed = true
        self._routedBatchFrame:SetScript("OnUpdate", RoutedBatchOnUpdate)
    end
end

-- Dispatch classifier, called from OnCooldownStateChanged for readable-arg
-- SPELL_UPDATE_COOLDOWN when routing is on. Returns true only when the fire is
-- fully handled (routed into the batch, or dropped as an index miss); false
-- forces the broad path. issecretvalue guards precede every read, and a
-- distinct readable base ID is folded in so a fire is a real drop only when
-- NEITHER readable identity maps to a tracked button.
function CooldownCompanion:RouteCooldownEventFire(spellID, baseSpellID)
    -- Index-trust gate (fail open BEFORE any route or drop): the flush
    -- generation guard only re-checks routed batches, never the immediate
    -- index-miss drop, so an untrustworthy index must broad-fallback here.
    local index = self:GetSpellButtonIndex()
    if self:IsSpellButtonIndexRebuildPending() then
        -- Rebuild queued but not run: buckets predate the change, so a fire for
        -- a not-yet-indexed button could be wrongly dropped.
        return false
    end
    if index.excludedCount > 0 then
        -- Rotation-assistant virtual buttons are index-excluded (their identity
        -- follows the assisted-combat recommendation and is permanently stale);
        -- keep every fire broad while any is loaded so a drop can never starve
        -- one (SpellButtonIndex header intent).
        return false
    end

    -- Secret/unreadable primary identity -> broad, never routable.
    if issecretvalue(spellID) then
        return false
    end
    if type(spellID) ~= "number" then
        -- Non-nil non-number is unreadable (broad); nil is the broadcast form
        -- (nil demotion is out of scope for this PR).
        return false
    end

    -- Fold in the distinct readable base ID (same rule as the watchdog).
    local baseNum
    if not issecretvalue(baseSpellID) and type(baseSpellID) == "number"
            and baseSpellID ~= spellID then
        baseNum = baseSpellID
    end

    wipe(fireSeen)
    fireCount = 0
    firePanel = false
    self:ForEachIndexedSpellButton(spellID, CollectFireButton)
    if baseNum then
        self:ForEachIndexedSpellButton(baseNum, CollectFireButton)
    end

    if fireCount == 0 then
        -- Index miss: no tracked button displays this identity -> drop. No dirty
        -- mark, no walk.
        return true
    end
    if firePanel then
        -- A matched button is a panel aggregate member -> fail open to broad.
        return false
    end

    -- Route: merge this fire's buttons into the pending batch (set semantics)
    -- and arm the flush. Stamp the index generation ONCE, when the batch first
    -- arms -- re-stamping on later fires would mask a rebuild that landed after
    -- the earliest batched button was resolved, letting the flush generation
    -- guard pass on a stale batch. A later fire resolved under a newer
    -- generation still coalesces in; the guard then escalates the whole batch to
    -- broad, which is the correct fail-open.
    if batchCount == 0 then
        batchGeneration = index.generation
    end
    for i = 1, fireCount do
        local button = fireList[i]
        if not batchButtons[button] then
            batchButtons[button] = true
            batchCount = batchCount + 1
            batchOrder[batchCount] = button
        end
    end
    self:EnsureRoutedBatchFrame()
    return true
end

-- The mini-pass: runs on the next OnUpdate boundary after one or more fires
-- routed. Never marks dirty and never touches scheduler serial/queue/latch
-- state; the generation-escalation fail-open is the one sanctioned scheduler
-- touch (the dispatch choosing the broad path, not the mini-pass).
function CooldownCompanion:FlushRoutedCooldownBatch()
    -- Disarm first: one flush per armed batch (re-armed by the next routed fire).
    if self._routedBatchFrame then
        self._routedBatchFrame:SetScript("OnUpdate", nil)
    end
    self._routedBatchArmed = nil

    -- 1. Supersede: a queued broad refresh flushes at this same boundary and
    --    strictly covers the batch, so drop it. OnUpdate order between the two
    --    frames is not guaranteed; if the broad flush already ran this is nil
    --    and the mini-pass runs redundantly -- safe, just not free.
    if self._queuedCooldownRefreshSource ~= nil then
        ClearRoutedBatch()
        return
    end

    -- 2. Generation / pending rebuild: a structural rebuild landed between
    --    enqueue and flush (generation bumped), OR one is queued but has not run
    --    yet (buckets about to change, generation not yet bumped). The dispatch
    --    index-trust gate blocks NEW fires while pending, but a batch armed
    --    BEFORE the structural change still reaches here; without this the
    --    generation compare passes (unchanged) and stale/pooled/removed frames
    --    mini-pass. Either way the stamped buttons may be stale, so escalate to
    --    the broad path (the one sanctioned scheduler touch) and drop the batch.
    local index = self:GetSpellButtonIndex()
    if index.generation ~= batchGeneration or self:IsSpellButtonIndexRebuildPending() then
        self:MarkCooldownsDirty("cooldown-event")
        self:QueueCooldownRefresh("cooldown-event")
        ClearRoutedBatch()
        return
    end

    -- 3. Mini-pass: shared A1 snapshot, then the full per-button pipeline on
    --    exactly the matched buttons whose group frame is shown (mirrors the
    --    broad walk's gate). button:UpdateCooldown delegates to
    --    UpdateButtonCooldown in every display mode.
    self:SnapshotCooldownPassContext()
    for i = 1, batchCount do
        local button = batchOrder[i]
        local groupFrame = button:GetParent()
        if button.buttonData and groupFrame and groupFrame:IsShown() then
            button:UpdateCooldown()
        end
    end

    ClearRoutedBatch()
end
