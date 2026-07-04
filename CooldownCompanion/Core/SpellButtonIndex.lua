--[[
    CooldownCompanion - Core/SpellButtonIndex.lua: reverse identity -> buttons
    index (F1 prerequisite D3).

    Maps identity keys to loaded button frames so a future event router can ask
    "which buttons care about spell/item X?" without walking every button.

    PASSIVE BY DESIGN: nothing at runtime consumes this index. Its only readers
    are the diagnostics below (and, later, the D1 shadow-parity harness). It
    ships early so it soaks through real talent/spec/pet/equipment churn while
    nothing depends on it.

    Keys are multi-key per button, mirroring what event-arg matching will need:
    - spell entries: base spellID, live override spellID
      (C_Spell.GetOverrideSpell), and the cached display ID
      (button._displaySpellId) when they differ
    - item entries ("item"/"equipitem"): base itemID and the runtime-resolved
      itemID (button._resolvedItemId) when they differ
    - equipment-slot entries: inventory slot number, plus the resolved itemID
      when the display lane has resolved one

    Entry kind uses addedAs (immutable add intent) — never the runtime
    auraTracking flag, which can auto-enable on addedAs == "spell" entries.

    Rotation-assistant virtual buttons are EXCLUDED (counted in diagnostics):
    their spell identity follows the assisted-combat recommendation and changes
    mid-combat with no structural refresh, so an index entry for them is
    permanently stale. Any future router keeps those groups on the broad path.

    Rebuilds are requested from the structural paths that change button
    populations or identity (PopulateGroupButtons, UnloadGroup,
    RecoverDormantFrame, RefreshAllGroupsForSpellAvailability) and coalesced to
    the next frame — never run inside the per-tick cooldown walk.

    Diagnostics (owner-runnable):
      /run CooldownCompanion:VerifySpellButtonIndexAll()   -- full self-check
      /run CooldownCompanion:VerifySpellButtonIndex(1822)  -- one spellID
      /dump CooldownCompanion:GetSpellButtonIndexDiagnostics()
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local type = type

local index = {
    spell = {},             -- [spellID] = { buttonFrame, ... }
    item = {},              -- [itemID]  = { buttonFrame, ... }
    slot = {},              -- [invSlot] = { buttonFrame, ... }
    buttonCount = 0,        -- buttons indexed in the last rebuild
    keyCount = 0,           -- total key->button links
    excludedCount = 0,      -- rotation-assistant virtual buttons skipped
    rebuildCount = 0,
    lastRebuildReason = nil,
    lastRebuildAt = nil,
    generation = 0,
}

local pendingRebuildToken = 0
local pendingRebuildReason = nil

-- Shared key derivation, used by both the rebuild and the self-checks so a
-- verify failure means the index is STALE (identity changed since the last
-- structural rebuild), not that two derivations disagree.
-- callback(kind, key, button) with kind = "spell" | "item" | "slot".
local function ForEachIdentityKey(button, buttonData, callback)
    local entryType = buttonData.type
    if entryType == "spell" then
        local baseId = buttonData.id
        if type(baseId) ~= "number" then return end
        callback("spell", baseId, button)
        -- GetOverrideSpell returns 0 (a truthy value in Lua) when there is no
        -- override; normalize that (and a self-referential override) to nil so
        -- we never index under key 0 and the displayId de-dup below stays sound.
        local overrideId = C_Spell.GetOverrideSpell(baseId)
        if overrideId == 0 or overrideId == baseId then
            overrideId = nil
        end
        if overrideId then
            callback("spell", overrideId, button)
        end
        local displayId = button._displaySpellId
        if displayId and displayId ~= baseId and displayId ~= overrideId then
            callback("spell", displayId, button)
        end
    elseif entryType == "item" or entryType == "equipitem" then
        local baseId = buttonData.id
        if type(baseId) == "number" then
            callback("item", baseId, button)
        end
        local resolvedId = button._resolvedItemId
        if type(resolvedId) == "number" and resolvedId ~= baseId then
            callback("item", resolvedId, button)
        end
    elseif CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        callback("slot", buttonData.itemSlot, button)
        local resolvedId = button._resolvedItemId
        if type(resolvedId) == "number" then
            callback("item", resolvedId, button)
        end
    end
end

-- Immutable add intent, not the runtime auraTracking flag.
local function GetEntryKind(buttonData)
    if buttonData.addedAs == "aura" then
        return "aura"
    end
    return buttonData.type
end

-- Passed directly as the ForEachIdentityKey callback (no per-button closures).
local function AddIndexKey(kind, key, button)
    local map = index[kind]
    local bucket = map[key]
    if not bucket then
        bucket = {}
        map[key] = bucket
    end
    bucket[#bucket + 1] = button
    index.keyCount = index.keyCount + 1
end

function CooldownCompanion:RebuildSpellButtonIndex(reason)
    wipe(index.spell)
    wipe(index.item)
    wipe(index.slot)
    index.buttonCount = 0
    index.keyCount = 0
    index.excludedCount = 0

    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData then
                    if buttonData._rotationAssistantVirtual == true then
                        index.excludedCount = index.excludedCount + 1
                    else
                        index.buttonCount = index.buttonCount + 1
                        ForEachIdentityKey(button, buttonData, AddIndexKey)
                    end
                end
            end
        end
    end

    index.rebuildCount = index.rebuildCount + 1
    index.generation = index.generation + 1
    index.lastRebuildReason = reason or "unspecified"
    index.lastRebuildAt = GetTime()
end

-- Coalesced next-frame rebuild request. Structural paths can fire several
-- requests in one action (e.g. RefreshAllGroups repopulating every group);
-- they collapse into one rebuild. Never called from the per-tick walk.
function CooldownCompanion:RequestSpellButtonIndexRebuild(reason)
    pendingRebuildReason = reason or pendingRebuildReason or "unspecified"
    pendingRebuildToken = pendingRebuildToken + 1
    local token = pendingRebuildToken
    C_Timer.After(0, function()
        if pendingRebuildToken ~= token then return end
        local rebuildReason = pendingRebuildReason
        pendingRebuildReason = nil
        CooldownCompanion:RebuildSpellButtonIndex(rebuildReason)
    end)
end

-- Live index table (diagnostics and, later, the D1 shadow-parity harness).
function CooldownCompanion:GetSpellButtonIndex()
    return index
end

-- Shared fire->buttons resolution used by BOTH the live router (F1 3b) and the
-- shadow-parity watchdog (ShadowParity StampCovered). callback(button) runs once
-- per button indexed under this readable spellID; returns true when at least one
-- button is indexed. Single lookup by construction, so "what the router routes"
-- and "what the watchdog checks" cannot drift.
function CooldownCompanion:ForEachIndexedSpellButton(spellID, callback)
    local bucket = index.spell[spellID]
    if not bucket then
        return false
    end
    for _, button in ipairs(bucket) do
        callback(button)
    end
    return true
end

local function DescribeButton(button)
    local buttonData = button.buttonData
    local groupId = button._groupId or (button:GetParent() and button:GetParent().groupId)
    return ("%s#%s:%s:%s"):format(
        tostring(groupId),
        tostring(button.index),
        tostring(buttonData and GetEntryKind(buttonData)),
        tostring(buttonData and (buttonData.id or buttonData.itemSlot)))
end

-- SV-safe scalar summary (DevBridge snapshots copy this table verbatim).
function CooldownCompanion:GetSpellButtonIndexDiagnostics()
    local spellKeys, itemKeys, slotKeys, maxBucket = 0, 0, 0, 0
    for _, bucket in pairs(index.spell) do
        spellKeys = spellKeys + 1
        if #bucket > maxBucket then maxBucket = #bucket end
    end
    for _, bucket in pairs(index.item) do
        itemKeys = itemKeys + 1
        if #bucket > maxBucket then maxBucket = #bucket end
    end
    for _, bucket in pairs(index.slot) do
        slotKeys = slotKeys + 1
        if #bucket > maxBucket then maxBucket = #bucket end
    end
    return {
        buttonCount = index.buttonCount,
        keyCount = index.keyCount,
        excludedCount = index.excludedCount,
        spellKeys = spellKeys,
        itemKeys = itemKeys,
        slotKeys = slotKeys,
        maxButtonsPerKey = maxBucket,
        rebuildCount = index.rebuildCount,
        lastRebuildReason = index.lastRebuildReason,
        lastRebuildAt = index.lastRebuildAt,
        generation = index.generation,
    }
end

-- Self-check for one spellID: buttons a live scan maps to the ID (deriving
-- keys NOW) vs buttons the index has for it (keys derived at last rebuild).
-- A difference means identity churned without a structural rebuild request —
-- exactly the bug class Phase 1 exists to catch early.
function CooldownCompanion:VerifySpellButtonIndex(spellID)
    local expected = {}
    local expectedCount = 0
    local function CollectMatch(kind, key, matchButton)
        if kind == "spell" and key == spellID and not expected[matchButton] then
            expected[matchButton] = true
            expectedCount = expectedCount + 1
        end
    end
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData and buttonData._rotationAssistantVirtual ~= true then
                    ForEachIdentityKey(button, buttonData, CollectMatch)
                end
            end
        end
    end

    local missing, extra = 0, 0
    local bucket = index.spell[spellID]
    local indexed = {}
    if bucket then
        for _, button in ipairs(bucket) do
            indexed[button] = true
        end
    end
    for button in pairs(expected) do
        if not indexed[button] then
            missing = missing + 1
            self:Print(("SpellButtonIndex MISSING %d -> %s"):format(spellID, DescribeButton(button)))
        end
    end
    for button in pairs(indexed) do
        if not expected[button] then
            extra = extra + 1
            self:Print(("SpellButtonIndex EXTRA %d -> %s"):format(spellID, DescribeButton(button)))
        end
    end

    local ok = missing == 0 and extra == 0
    self:Print(("SpellButtonIndex check %d: %s (%d expected, %d missing, %d extra, gen %d)"):format(
        spellID, ok and "OK" or "MISMATCH", expectedCount, missing, extra, index.generation))
    return ok, expectedCount, missing, extra
end

-- Full consistency sweep: every live button's freshly-derived keys must hit
-- the index, and every indexed button must still be a live, key-matching
-- button (catches stale frames after unload and identity churn after talent/
-- spec/pet/equipment swaps). Owner soak tool:
--   /run CooldownCompanion:VerifySpellButtonIndexAll()
function CooldownCompanion:VerifySpellButtonIndexAll()
    local mismatches = 0
    local liveButtons = 0
    local liveLinks = {}   -- [kind:key -> set of buttons] derived now

    local function CheckLiveKey(kind, key, liveButton)
        local linkKey = kind .. ":" .. key
        local set = liveLinks[linkKey]
        if not set then
            set = {}
            liveLinks[linkKey] = set
        end
        set[liveButton] = true

        -- Forward check: fresh key must be in the index.
        local bucket = index[kind][key]
        local found = false
        if bucket then
            for _, indexedButton in ipairs(bucket) do
                if indexedButton == liveButton then
                    found = true
                    break
                end
            end
        end
        if not found then
            mismatches = mismatches + 1
            self:Print(("SpellButtonIndex MISSING %s:%s -> %s"):format(
                kind, tostring(key), DescribeButton(liveButton)))
        end
    end

    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData and buttonData._rotationAssistantVirtual ~= true then
                    liveButtons = liveButtons + 1
                    ForEachIdentityKey(button, buttonData, CheckLiveKey)
                end
            end
        end
    end

    -- Reverse check: every indexed link must exist in the fresh derivation.
    for _, kind in ipairs({ "spell", "item", "slot" }) do
        for key, bucket in pairs(index[kind]) do
            local linkKey = kind .. ":" .. key
            for _, button in ipairs(bucket) do
                if not (liveLinks[linkKey] and liveLinks[linkKey][button]) then
                    mismatches = mismatches + 1
                    self:Print(("SpellButtonIndex STALE %s:%s -> %s"):format(
                        kind, tostring(key), DescribeButton(button)))
                end
            end
        end
    end

    self:Print(("SpellButtonIndex sweep: %s — %d live buttons, %d keys, %d excluded, %d mismatches (gen %d, last rebuild: %s)"):format(
        mismatches == 0 and "OK" or "MISMATCH",
        liveButtons, index.keyCount, index.excludedCount, mismatches,
        index.generation, tostring(index.lastRebuildReason)))
    return mismatches
end
