--[[
    CooldownCompanion - Core/CooldownRouting.lua: F1 3b readable-identity
    cooldown event router.

    A readable-arg SPELL_UPDATE_COOLDOWN fire is resolved through the D3 spell
    index instead of triggering a broad walk:
      - index hit  -> the matched buttons are added to a pending batch that runs
        the full per-button pipeline (UpdateButtonCooldown) on the next OnUpdate
        boundary (a "mini-pass"), coalescing same-frame fires.
      - index miss -> the fire is DROPPED: no tracked button displays that
        identity, so nothing needs updating. A drop is only taken once the
        index-trust gate below has passed.
      - anything the router cannot fully classify, or any state that makes the
        index untrustworthy, falls back to today's broad path unchanged (fail
        open; accuracy is inviolable): secret/unreadable arg, nil (broadcast-
        form) arg, a matched button in a panel group (cross-button aggregate,
        D4 inventory A4/A5), a structural index rebuild pending or landed
        between enqueue and flush, or any rotation-assistant virtual button
        loaded (those are excluded from the index by design, so a drop could
        starve one -- SpellButtonIndex header).

    CooldownRefresh owns the shared flush frame and broad fallback. The router
    owns eligibility and batches; its mini-pass never marks dirty, satisfies
    scheduler serials, or sets _cooldownUpdatePassActive.
    It does reach NoteButtonTimeState through the shared per-button pipeline,
    which may push the F2 accumulators (_passTimeStateSeen, _tickerIdleEligible)
    in the conservative direction (forcing an extra walk) for a forced routed
    button -- never the permissive one: only a completed broad walk latches
    _tickerIdleEligible true, so a mini-pass can never cause a false idle-skip.
    A stale batch returns to the flush owner for a broad refresh.

    Fire->buttons resolution uses CooldownCompanion:ForEachIndexedSpellButton,
    keeping the router's lookup single-sourced by construction.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local issecretvalue = issecretvalue
local type = type
local wipe = wipe

-- Pending routed batch: buttons to mini-pass at the next OnUpdate boundary.
-- Same-frame fires coalesce with set semantics (a button appears once).
-- Two reusable batches keep requests raised during delivery separate from the
-- batch being read, without allocating a table for each mini-pass.
local pendingBatch = { buttons = {}, order = {}, count = 0 }
local spareBatch = { buttons = {}, order = {}, count = 0 }

-- Per-fire scratch: one fire's matched buttons (union of the spellID bucket and
-- the distinct-baseID bucket), plus a panel-membership flag. A button in both
-- buckets is listed twice; the pending batch deduplicates those matches, the
-- fireCount == 0 drop check only needs "any match", and a duplicate panel check
-- is harmless. Reset at the top of every RouteCooldownEventFire.
local fireList = {}
local fireCount = 0
local firePanel = false

-- A panel group is a cross-button aggregate (D4 inventory A4/A5): its visual
-- ANDs cached per-row state, so updating only the matched row can leave the
-- panel reading stale inputs. One matched panel member makes the whole fire
-- broad -- fail open (panel-as-routing-unit is a later refinement).
local function IsPanelButton(button)
    local groupId = button._groupId
    if not groupId then
        return false
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return CooldownCompanion:IsStandaloneTexturePanelGroup(group)
end

-- ForEachIndexedSpellButton callback: collect this fire's matched buttons and
-- note whether any belongs to a panel group.
local function CollectFireButton(button)
    fireCount = fireCount + 1
    fireList[fireCount] = button
    if IsPanelButton(button) then
        firePanel = true
    end
end

local function ClearBatch(batch)
    wipe(batch.buttons)
    wipe(batch.order)
    batch.count = 0
    batch.generation = nil
end

-- A broad pass covers requests already pending when it starts, including the
-- remainder of a mini-pass if a button triggered a synchronous broad refresh.
-- OnDisable uses the same cancellation through ResetCooldownRefreshState.
function CooldownCompanion:ResetRoutedCooldownBatch()
    ClearBatch(pendingBatch)
    ClearBatch(spareBatch)
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
        -- and stays broad (nil demotion is deliberately shelved, spec
        -- 2026-07-04-017 §9).
        return false
    end

    -- Fold in the distinct readable base ID, matching the router's drop rule.
    local baseNum
    if not issecretvalue(baseSpellID) and type(baseSpellID) == "number"
            and baseSpellID ~= spellID then
        baseNum = baseSpellID
    end

    fireCount = 0
    firePanel = false
    self:ForEachIndexedSpellButton(spellID, CollectFireButton)
    if baseNum then
        self:ForEachIndexedSpellButton(baseNum, CollectFireButton)
    end

    if fireCount == 0 then
        -- Index miss: no tracked button displays this identity -> drop. No dirty
        -- mark, no walk. Counted (dev-gated) so wrong drops are observable.
        self:CountRoutedDrop()
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
    if pendingBatch.count == 0 then
        pendingBatch.generation = index.generation
    end
    for i = 1, fireCount do
        local button = fireList[i]
        if not pendingBatch.buttons[button] then
            pendingBatch.buttons[button] = true
            pendingBatch.count = pendingBatch.count + 1
            pendingBatch.order[pendingBatch.count] = button
        end
    end
    self:EnsureCooldownRefreshQueueFrame()
    return true
end

-- Called only by the shared flush owner. Return true when a stale batch needs
-- broad fallback. An empty batch must not manufacture a cooldown-event refresh.
function CooldownCompanion:FlushRoutedCooldownBatch()
    if pendingBatch.count == 0 then
        return
    end

    -- Recheck both sides of the coalesced index rebuild. Neither callback order
    -- may allow a batch resolved before structural churn to use stale frames.
    local index = self:GetSpellButtonIndex()
    if index.generation ~= pendingBatch.generation or self:IsSpellButtonIndexRebuildPending() then
        ClearBatch(pendingBatch)
        return true
    end

    local batch = pendingBatch
    pendingBatch, spareBatch = spareBatch, pendingBatch
    ClearBatch(pendingBatch)

    -- Detach before even the snapshot: synchronous requests from either the
    -- snapshot or a button belong to the next batch, even for the same button.
    self:SnapshotCooldownPassContext()
    local needsBroad
    local i = 1
    while i <= batch.count do
        -- A callback may remove/reuse a later button while this batch is active.
        if index.generation ~= batch.generation or self:IsSpellButtonIndexRebuildPending() then
            needsBroad = true
            break
        end
        local button = batch.order[i]
        local groupFrame = button:GetParent()
        if button.buttonData and groupFrame and groupFrame:IsShown() then
            button:UpdateCooldown()
        end
        i = i + 1
    end

    ClearBatch(batch)
    return needsBroad
end
