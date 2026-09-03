--[[
    CooldownCompanion - Core/TotemTracking.lua: totem-slot duration lane.

    Guardian summons (shaman totems, Consecration, Shadowfiend, treants,
    statues, Efflorescence, Surging Totem, ...) are NOT auras. Their remaining
    time lives only on the totem-slot API, so this module owns the one place
    that reads it and hands render code a duration object per spellID.

    Lane facts this module is built on (live 12.1, owner-validated in game):
    - Out of combat GetTotemInfo returns plain values, and GetTotemDuration
      returns a LuaDurationObject for an occupied slot and NIL for an empty one
      (the generated record claims non-nilable; it is not). GetTotemInfo is
      MayReturnNothing, so every field can also be nil.
    - In combat EVERY GetTotemInfo field is a secret value, haveTotem included:
      slot occupancy itself is undetectable. Nothing here may compare, test,
      concatenate, or do arithmetic on a value before issecretvalue clears it.
    - PLAYER_TOTEM_UPDATE carries a PLAIN slot index, in combat too, and the
      player's own UNIT_SPELLCAST_SUCCEEDED spellID is plain in combat too.

    Identity therefore comes from two different sources:
    - OOC: GetTotemInfo is the source of truth and resyncs every slot.
    - In combat: OWNER-APPROVED cast correlation -- the player's own successful
      cast followed within CAST_CORRELATION_WINDOW by the next
      PLAYER_TOTEM_UPDATE names that slot. One cast names at most one slot
      (first update wins). Only a cast that is a plausible summon is
      accepted as a name: the window is wide enough that an unrelated
      instant (Implosion, Demonbolt) cast just before a slot update -- a
      second summon landing from the same cast, or a summon expiring -- was
      stamped onto that slot and then shown as a summon phase the next time
      the slot went live (Demonology, owner log 2026-09-02). Plausible means
      the spell already carries a learned link, or Blizzard's own Cooldown
      Manager lists it (or its base spell) in a Tracked Buff or Tracked Bar
      row -- the same rows that hand CC the totem identity in the first
      place (Call Dreadstalkers 104316 -> bar row linked to 193332). That
      data answers with no prior out-of-combat sighting, which matters
      because many summons are only ever cast in combat. A name stamps the
      cast ID and its learned partner and clears any totem identity left by
      a previous occupancy. A FRESH occupancy (empty -> live) that arrives
      with no accepted name carries no identity at all -- cast label and
      totem identity are both dropped -- unless this slot was named within
      the correlation window (the second update of the same cast). A live
      slot that updates without a name keeps its identity: that is a refresh
      of the same summon. An unknown slot simply resolves to nothing.

    The cast spellID a user's entry carries and the spellID the totem API
    reports are frequently different IDs for the same summon, so both are kept
    per slot and the observed pairs are learned per character into
    db.global.totemSpellLinks[charKey] (stored in both directions) so a lookup
    by either ID succeeds on later sessions.

    Correlation is a heuristic, so its mistakes must stay transient. Two rules
    keep them that way:
    - A link is learned ONLY from a direct out-of-combat pairing: a consumed
      cast note landing on the very PLAYER_TOTEM_UPDATE it caused, while the
      API itself names the slot. A cast label retained through combat or
      through a same-slot replacement is never proof and is never persisted.
    - Readable truth clears contradicted identities: when an OOC resync sees a
      slot whose retained castSpellID is neither the observed totem spellID nor
      its learned partner, that castSpellID is dropped. A proven link partner
      survives -- that pairing is the feature working.

    GetTotemDurationObjectForSpell is called per button per 0.1s tick by the
    render lane, so lookups read a precomputed spellID -> slot table that is
    rebuilt on slot mutation only -- never a scan per call. On a duplicate
    spellID the preferred slot is the one that expires LATER when both slots
    carry a plain expirationTime read out of combat (Blizzard's own Cooldown
    Manager picks the longer-lived duplicate); otherwise the most recently
    updated slot (updateStamp) wins. Expiration is unknowable in combat, so a
    combat update always clears it and the stamp takes over there.

    Duration objects are opaque here: they are stored and handed out, never
    called. Activity probing belongs to the consumer
    (EntryRuntime.DurationObjectShowsCooldown).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local GetNumTotemSlots = GetNumTotemSlots
local GetTotemInfo = GetTotemInfo
local GetTotemDuration = GetTotemDuration
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local issecretvalue = issecretvalue
local pairs = pairs
local type = type
local wipe = wipe

-- A cast can only name the totem slot that updates right after it.
local CAST_CORRELATION_WINDOW = 1.0

-- [slot] = { castSpellID, totemSpellID, durationObj, updateStamp, expirationTime }
-- A record with a nil durationObj is a known-but-empty (or unreadable) slot:
-- it keeps its identity for the refresh case but contributes no lookup keys.
local slotState = {}

-- Precomputed lookup, rebuilt on every slot mutation.
local spellSlots = {}          -- [spellID] = slot
local spellSlotStamps = {}     -- [spellID] = updateStamp of that slot
local spellSlotExpirations = {} -- [spellID] = plain expirationTime of that slot, or nil

local updateStampCounter = 0

-- Pending cast correlation note (module-local, never persisted).
local lastCastSpellID = nil
local lastCastTime = nil

-- Spells Blizzard's Cooldown Manager tracks as a buff or bar row for the
-- current spec: [spellID] = "bar" | "buff" (bar wins), covering the row
-- spellID, both override forms, linked IDs, and the base spell. The set is
-- handed in by RebuildSoundAlertSpellMap (Core/SoundAlerts.lua), which
-- already walks every viewer row on the viewer-map rebuild, so it is built
-- out of combat and shares that map's lifetime. nil = not built yet.
local summonCandidateSpells = nil

function CooldownCompanion:SetTotemLaneSummonCandidates(set)
    summonCandidateSpells = set
end

-- "bar" / "buff" when the spell (or its base spell) sits in such a row.
local function GetSummonCandidateKind(self, spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    if not summonCandidateSpells then
        self:RebuildSoundAlertSpellMap()
        if not summonCandidateSpells then
            return nil
        end
    end
    local kind = summonCandidateSpells[spellID]
    if kind then
        return kind
    end
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if type(baseSpellID) == "number" and baseSpellID ~= spellID then
        return summonCandidateSpells[baseSpellID]
    end
    return nil
end

-- The combat-correlation gate: a learned link (self-link included) or any
-- Cooldown Manager buff/bar row makes a cast a plausible summon.
local function IsPlausibleSummonCast(self, charLinks, spellID)
    if charLinks and charLinks[spellID] then
        return true
    end
    return GetSummonCandidateKind(self, spellID) ~= nil
end

local function NextStamp()
    updateStampCounter = updateStampCounter + 1
    return updateStampCounter
end

-- Per-character learned cast <-> totem spellID pairs. Nil-chained: the lane
-- runs before/without a db in no path today, but never assume the shape.
local function GetLinkTable(self, createIfMissing)
    local db = self.db
    local links = db and db.global and db.global.totemSpellLinks
    local charKey = db and db.keys and db.keys.char
    if not links or not charKey then
        return nil
    end
    local charLinks = links[charKey]
    if not charLinks and createIfMissing then
        charLinks = {}
        links[charKey] = charLinks
    end
    return charLinks
end

local function LearnLink(self, castSpellID, totemSpellID)
    if type(castSpellID) ~= "number" or type(totemSpellID) ~= "number" then
        return false
    end
    local charLinks = GetLinkTable(self, true)
    if not charLinks then
        return false
    end
    if castSpellID == totemSpellID then
        -- No partner to learn, but the sighting proves the spell is a summon
        -- (most Shaman totems report their own cast ID): a self-link is what
        -- lets the combat gate accept it without a Cooldown Manager row.
        if charLinks[castSpellID] == castSpellID then
            return false
        end
        charLinks[castSpellID] = castSpellID
        return true
    end
    if charLinks[castSpellID] == totemSpellID and charLinks[totemSpellID] == castSpellID then
        return false
    end
    charLinks[castSpellID] = totemSpellID
    charLinks[totemSpellID] = castSpellID
    return true
end

-- expiration is a plain number or nil; it only ever comes from a readable OOC
-- GetTotemInfo pass, so it is never a secret value here.
local function AddLookupKey(spellID, slot, stamp, expiration)
    if type(spellID) ~= "number" then
        return
    end
    local existingStamp = spellSlotStamps[spellID]
    if existingStamp then
        local existingExpiration = spellSlotExpirations[spellID]
        if existingExpiration and expiration then
            -- Two duplicate summons both readable: the longer-lived one wins,
            -- matching Blizzard's own duplicate handling. Order-independent.
            if expiration <= existingExpiration then
                return
            end
        elseif existingStamp >= stamp then
            return
        end
    end
    spellSlots[spellID] = slot
    spellSlotStamps[spellID] = stamp
    spellSlotExpirations[spellID] = expiration
end

local function RebuildSpellSlots(self)
    wipe(spellSlots)
    wipe(spellSlotStamps)
    wipe(spellSlotExpirations)
    local charLinks = GetLinkTable(self, false)
    for slot, record in pairs(slotState) do
        if record.durationObj ~= nil then
            local stamp = record.updateStamp or 0
            local expiration = record.expirationTime
            local castSpellID = record.castSpellID
            local totemSpellID = record.totemSpellID
            AddLookupKey(castSpellID, slot, stamp, expiration)
            AddLookupKey(totemSpellID, slot, stamp, expiration)
            if charLinks then
                if castSpellID then
                    AddLookupKey(charLinks[castSpellID], slot, stamp, expiration)
                end
                if totemSpellID then
                    AddLookupKey(charLinks[totemSpellID], slot, stamp, expiration)
                end
            end
        end
    end
end

local function EnsureSlotRecord(slot)
    local record = slotState[slot]
    if not record then
        record = {}
        slotState[slot] = record
    end
    return record
end

-- Returns the pending cast spellID if it is still inside the correlation
-- window, and consumes the note either way (a stale note never survives).
local function ConsumeCastNote()
    local spellID = lastCastSpellID
    local castTime = lastCastTime
    lastCastSpellID = nil
    lastCastTime = nil
    if not spellID or not castTime then
        return nil
    end
    if (GetTime() - castTime) > CAST_CORRELATION_WINDOW then
        return nil
    end
    return spellID
end

-- Records the player's own successful cast for the next PLAYER_TOTEM_UPDATE.
-- Called from OnSpellCast through a feature-guarded probe; the spellID there is
-- plain in combat.
function CooldownCompanion:NoteTotemLaneSpellCast(spellID)
    -- UNIT_SPELLCAST_SUCCEEDED payloads are SecretWhenUnitSpellCastRestricted.
    -- Player-unit payloads are plain in practice, but a secret must never enter
    -- the note: everything downstream compares and stores it.
    if issecretvalue(spellID) then
        return
    end
    if type(spellID) ~= "number" then
        return
    end
    lastCastSpellID = spellID
    lastCastTime = GetTime()
end

-- Out-of-combat truth pass: GetTotemInfo names every occupied slot and clears
-- every empty one. Runs on enable, on combat end, and on OOC totem updates.
function CooldownCompanion:ResyncTotemSlots()
    if InCombatLockdown() then
        return
    end

    local numSlots = GetNumTotemSlots and GetNumTotemSlots() or 0
    if type(numSlots) ~= "number" then
        return
    end

    local charLinks = GetLinkTable(self, false)
    local changed = false
    for slot = 1, numSlots do
        local haveTotem, _, startTime, duration, _, _, totemSpellID = GetTotemInfo(slot)
        -- Belt and braces: this path is OOC, but a secret field means the slot
        -- is unreadable, not empty. Leave such a slot untouched.
        if not issecretvalue(haveTotem) and not issecretvalue(totemSpellID) then
            local record = slotState[slot]
            if haveTotem then
                record = EnsureSlotRecord(slot)
                local durationObj = GetTotemDuration(slot)
                if type(totemSpellID) ~= "number" then
                    totemSpellID = nil
                end
                -- Expiration is only knowable while both fields read plain.
                local expirationTime = nil
                if not issecretvalue(startTime) and not issecretvalue(duration)
                    and type(startTime) == "number" and type(duration) == "number" then
                    expirationTime = startTime + duration
                end
                -- Readable truth wins over a retained cast label: a castSpellID
                -- that is neither this slot's totem spellID nor its learned
                -- partner was a bad guess and must not outlive this pass.
                local castSpellID = record.castSpellID
                if castSpellID and totemSpellID and castSpellID ~= totemSpellID
                    and (not charLinks or charLinks[castSpellID] ~= totemSpellID) then
                    record.castSpellID = nil
                    changed = true
                end
                local identityChanged = (record.totemSpellID ~= totemSpellID)
                local occupancyChanged = ((record.durationObj ~= nil) ~= (durationObj ~= nil))
                record.totemSpellID = totemSpellID
                record.durationObj = durationObj
                record.expirationTime = expirationTime
                -- A fresh durationObj on an occupied slot is a new observation,
                -- so its stamp must move even when identity and occupancy hold;
                -- otherwise combat-fallback ordering reads a stale recency.
                if identityChanged or occupancyChanged or durationObj ~= nil
                    or not record.updateStamp then
                    record.updateStamp = NextStamp()
                    changed = true
                end
            elseif record then
                slotState[slot] = nil
                changed = true
            end
        end
    end

    if changed then
        RebuildSpellSlots(self)
        self:QueueCooldownRefresh("totem-update")
    end
end

-- PLAYER_TOTEM_UPDATE(slot). The slot index is plain in combat; every value
-- reachable from it is not.
function CooldownCompanion:OnTotemUpdate(event, slot)
    if issecretvalue(slot) then
        return
    end
    if type(slot) ~= "number" then
        return
    end

    if InCombatLockdown() then
        -- Occupancy is unreadable here, so the duration object is the only
        -- fact available: nil means the slot is empty or sealed, and a fresh
        -- object means it is live. Identity can only come from correlation.
        local record = EnsureSlotRecord(slot)
        local wasLive = record.durationObj ~= nil
        record.durationObj = GetTotemDuration(slot)
        local isLive = record.durationObj ~= nil
        -- Start time and duration are secret in combat, so any expiration this
        -- slot carried from an OOC pass is now unverifiable: drop it and let
        -- the update stamp order duplicates here.
        record.expirationTime = nil
        local now = GetTime()
        local castSpellID = ConsumeCastNote()
        local charLinks = GetLinkTable(self, false)
        if castSpellID and IsPlausibleSummonCast(self, charLinks, castSpellID) then
            -- A plausible summon caster names the slot. The learned partner
            -- (nil when unknown or a self-link) replaces whatever totem
            -- identity a previous occupancy left, so no stale ID rides along.
            record.castSpellID = castSpellID
            local partner = charLinks and charLinks[castSpellID]
            if partner == castSpellID then
                partner = nil
            end
            record.totemSpellID = partner
            record.namedAt = now
        elseif isLive and not wasLive then
            -- Fresh occupancy with no accepted name. The one legitimate carry
            -- is the second update of the cast that just named this slot
            -- (a destroy/create pair inside the correlation window);
            -- anything older is a foreign identity and is dropped whole.
            if not (record.namedAt and (now - record.namedAt) <= CAST_CORRELATION_WINDOW) then
                record.castSpellID = nil
                record.totemSpellID = nil
                record.namedAt = nil
            end
        end
        record.updateStamp = NextStamp()
        RebuildSpellSlots(self)
        self:QueueCooldownRefresh("totem-update")
        return
    end

    self:ResyncTotemSlots()

    -- OOC the API already named the slot; pairing the cast that caused this
    -- update teaches the cast ID the user's entry actually carries.
    local castSpellID = ConsumeCastNote()
    local record = castSpellID and slotState[slot]
    if record and record.durationObj ~= nil and record.castSpellID ~= castSpellID then
        record.castSpellID = castSpellID
        record.updateStamp = NextStamp()
        LearnLink(self, castSpellID, record.totemSpellID)
        RebuildSpellSlots(self)
        self:QueueCooldownRefresh("totem-update")
    end
end

-- Public read for the render lane: the duration object of the live slot whose
-- cast or totem spellID matches (directly or through a learned link), else nil.
function CooldownCompanion:GetTotemDurationObjectForSpell(spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    local slot = spellSlots[spellID]
    if not slot then
        return nil
    end
    local record = slotState[slot]
    return record and record.durationObj or nil
end

-- Read-only: the learned partner of a spellID for this character (cast ID ->
-- totem ID or the reverse; a self-linked summon reports itself), else nil.
function CooldownCompanion:GetLinkedTotemSpellID(spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    local charLinks = GetLinkTable(self, false)
    local partner = charLinks and charLinks[spellID]
    if type(partner) ~= "number" then
        return nil
    end
    return partner
end

-- Read-only, for config surfaces: would this spell's active phase be a
-- summon duration read from the totem slot? True on a learned link or a
-- Cooldown Manager Tracked BAR row -- the same evidence the combat gate
-- accepts, minus buff rows, which also hold ordinary self-buffs that never
-- occupy a slot (Demonic Core) and must not be explained as summons.
function CooldownCompanion:IsTotemLaneSummonDisplaySpell(spellID)
    if type(spellID) ~= "number" then
        return false
    end
    if self:GetLinkedTotemSpellID(spellID) then
        return true
    end
    return GetSummonCandidateKind(self, spellID) == "bar"
end

-- Totem phase eligibility (one owner, shared by the render lane and tests).
-- The phase is opt-in through the entry's own "Track an Aura" toggle. Aura-
-- added entries are stamped isPassive by the add path, and that flag gates
-- every cooldown-lane decision, so the phase is the one passive-stamped case
-- admitted: a summon's standing duration IS the aura a standalone entry for
-- it is asking to see (Call Dreadstalkers occupies a totem slot and applies
-- no aura at all). A true passive aura entry costs one table lookup per tick
-- and resolves to nothing. Text panels are excluded at the call site.
function ST.IsTotemPhaseEligibleEntry(buttonData)
    if type(buttonData) ~= "table" then
        return false
    end
    if buttonData.type ~= "spell" or buttonData.auraTracking ~= true then
        return false
    end
    if buttonData.isPassive and buttonData.addedAs ~= "aura" then
        return false
    end
    return true
end

function CooldownCompanion:ResetTotemTracking()
    wipe(slotState)
    wipe(spellSlots)
    wipe(spellSlotStamps)
    wipe(spellSlotExpirations)
    lastCastSpellID = nil
    lastCastTime = nil
end
