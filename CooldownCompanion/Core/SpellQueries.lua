--[[
    CooldownCompanion - SpellQueries
    Spell resolution, spellbook lookups, CDM queries, and tooltip detection
]]

local ADDON_NAME, ST = ...

local ipairs = ipairs
local tonumber = tonumber
local issecretvalue = issecretvalue
local Enum = Enum

local function IsConcreteSpellID(spellID)
    return type(spellID) == "number"
        and spellID > 0
        and not (issecretvalue and issecretvalue(spellID))
end
ST.IsConcreteSpellID = IsConcreteSpellID

function ST.ResolveCDMDisplaySpellID(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return nil
    end
    -- linkedSpellID is live aura state on Blizzard item data; starter setup
    -- needs stable CDM metadata so cooldown panels do not capture an aura stage.
    if IsConcreteSpellID(cooldownInfo.overrideTooltipSpellID) then
        return cooldownInfo.overrideTooltipSpellID
    end
    if IsConcreteSpellID(cooldownInfo.overrideSpellID) then
        return cooldownInfo.overrideSpellID
    end
    if IsConcreteSpellID(cooldownInfo.spellID) then
        return cooldownInfo.spellID
    end
    return nil
end

function ST.ResolveCDMAuraSpellID(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return nil
    end
    if IsConcreteSpellID(cooldownInfo.overrideTooltipSpellID) then
        return cooldownInfo.overrideTooltipSpellID
    end
    if IsConcreteSpellID(cooldownInfo.overrideSpellID) then
        return cooldownInfo.overrideSpellID
    end
    if IsConcreteSpellID(cooldownInfo.spellID) then
        return cooldownInfo.spellID
    end
    return nil
end

-- Curated applied-aura corrections, keyed by the CAST (base) spellID. The
-- linked-list rule below trusts Blizzard's CDM data, and that data can be
-- flat wrong in both directions: a row can link an inert record its spell
-- never applies, or carry no link at all for a spell whose aura lands under
-- a different ID. An entry here is authoritative over the row's linked
-- list. Mapping a spell to ITSELF means "the cast ID is the aura; ignore
-- the links entirely."
-- Adding an ID here follows the AURA_UNIT_OVERRIDES rule: bump the
-- aura-rebuild migration generation so stored auraUnit/auraSpellID heal.
local AURA_APPLIED_ID_OVERRIDES = {
    -- Blade Flurry: the row links only 22482, an inert legacy record the
    -- game never applies; the live buff carries the cast ID (in-game dump
    -- 2026-08-28).
    [13877] = 13877,
    -- Dancing Rune Weapon: the row carries no links, but the live buff is
    -- applied as 81256, not the cast ID.
    [49028] = 81256,
}

function ST.GetCuratedAppliedAuraSpellID(spellID)
    local numericID = tonumber(spellID)
    return numericID and AURA_APPLIED_ID_OVERRIDES[numericID] or nil
end

-- Suppressed linked IDs, keyed the same way: the wrong linked IDs a curated
-- correction disowns, listed EXPLICITLY per spell. Pure data on purpose:
-- the first cut confirmed suppression against the live CDM rows, but that
-- read is scoped to the logged-in character's cooldown sets while the
-- migrations that consume this walk whole (often account-shared) profiles,
-- so a wrong-class first login silently skipped the heal and stamped the
-- generation. Explicit listing also means the strip can only ever remove
-- hand-listed IDs, never a legitimate sibling stage on a multi-link row
-- (Hot Streak's row links both 48107 and 48108).
-- Maintenance: an AURA_APPLIED_ID_OVERRIDES entry whose row links wrong
-- IDs lists those IDs here, under the same migration-generation-bump rule.
local AURA_SUPPRESSED_LINKED_IDS = {
    -- Blade Flurry: the inert legacy link its tracked-buff row carries.
    [13877] = { [22482] = true },
}

function ST.GetCuratedSuppressedLinkedAuraIDs(spellID)
    local numericID = tonumber(spellID)
    return numericID and AURA_SUPPRESSED_LINKED_IDS[numericID] or nil
end

-- The identity the APPLIED aura actually carries, for a CDM data row. The
-- row's resolved spellID is the cast or talent spell; when the game applies
-- the aura under a different spellID, that identity exists only in
-- linkedSpellIDs (Fire Breath 357208 applies DoT 357209; Rake 1822 applies
-- bleed 155722). Blizzard's own matcher (GetAssociatedAuraSpellPriority)
-- ranks linked IDs above the row spellID, so when the row ID is absent from
-- a non-empty linked list, the aura that actually gets tracked is the linked
-- one. Same rule the autocomplete attach surfaces validated 2026-08-08.
function ST.ResolveCDMAppliedAuraSpellID(cooldownInfo, resolvedID)
    if type(cooldownInfo) ~= "table" or not IsConcreteSpellID(resolvedID) then
        return resolvedID
    end
    local curated = AURA_APPLIED_ID_OVERRIDES[resolvedID]
    if curated then
        return curated
    end
    local linked = cooldownInfo.linkedSpellIDs
    if type(linked) ~= "table" or #linked == 0 then
        return resolvedID
    end
    for _, linkedID in ipairs(linked) do
        if linkedID == resolvedID then
            return resolvedID
        end
    end
    -- The row ID is absent from a non-empty linked list, so it is not a
    -- matchable aura identity at all — never fall back to it here (that
    -- fallback mis-polarized Shield of the Righteous the moment its live
    -- row grew a second link). With several links (Hot Streak links Heating
    -- Up 48107 AND Hot Streak 48108) the FIRST existing one is promoted,
    -- Blizzard data order; the second return flags that ambiguity so
    -- display surfaces can keep the row's own name instead of naming one
    -- stage. The candidate-set path carries every stage regardless.
    local appliedID, ambiguous
    for _, linkedID in ipairs(linked) do
        if IsConcreteSpellID(linkedID) and C_Spell.DoesSpellExist(linkedID) then
            if appliedID then
                if linkedID ~= appliedID then
                    ambiguous = true
                end
            else
                appliedID = linkedID
            end
        end
    end
    return appliedID or resolvedID, ambiguous
end

function ST.IsDistinctCDMAuraIdentity(spellID, auraID)
    if not IsConcreteSpellID(spellID) or not IsConcreteSpellID(auraID) then
        return false
    end
    if auraID == spellID then
        return false
    end

    local auraBase = C_Spell.GetBaseSpell(auraID)
    if auraBase ~= nil then
        if issecretvalue and issecretvalue(auraBase) then
            return false
        end
        if auraBase ~= 0 then
            if not IsConcreteSpellID(auraBase) then
                return false
            end
            if auraBase == spellID then
                return false
            end
        end
    end

    local spellName = C_Spell.GetSpellName(spellID)
    local auraName = C_Spell.GetSpellName(auraID)
    if type(spellName) ~= "string"
        or type(auraName) ~= "string"
        or (issecretvalue and (issecretvalue(spellName) or issecretvalue(auraName))) then
        return false
    end

    return spellName ~= auraName
end

function ST.IsCDMBuffViewerChild(frame)
    if not (frame and frame.GetParent) then
        return false
    end
    local parent = frame:GetParent()
    local parentName = parent and parent.GetName and parent:GetName()
    local buffViewerSet = ST._BUFF_VIEWER_SET
    return buffViewerSet and buffViewerSet[parentName] == true
end

function ST.IsPlainSpellEntry(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.addedAs ~= "aura"
        and not buttonData.isPassive
        and not buttonData.cdmChildSlot
end

function ST.IsDistinctAuraViewerFrameForSpell(buttonData, frame)
    if not (ST.IsPlainSpellEntry(buttonData) and ST.IsCDMBuffViewerChild(frame)) then
        return false
    end

    local auraID = ST.ResolveCDMAuraSpellID(frame.cooldownInfo)
    return auraID and ST.IsDistinctCDMAuraIdentity(buttonData.id, auraID) or false
end

function ST.ResolveViewerChildForSpellDisplay(addon, buttonData)
    if not (addon and buttonData and buttonData.type == "spell") then
        return nil
    end

    local child
    if buttonData.cdmChildSlot then
        local allChildren = addon.viewerAuraAllChildren and addon.viewerAuraAllChildren[buttonData.id]
        child = allChildren and allChildren[buttonData.cdmChildSlot]
    else
        child = addon.viewerAuraFrames and addon.viewerAuraFrames[buttonData.id]
    end

    if child and ST.IsDistinctAuraViewerFrameForSpell(buttonData, child) then
        return addon.FindCooldownViewerChild and addon:FindCooldownViewerChild(buttonData.id) or nil
    end

    return child
end

--------------------------------------------------------------------------------
-- Spell Resolution
--------------------------------------------------------------------------------

-- Resolve a spell ID to its base form via C_Spell.GetBaseSpell.
-- Used at entry time so buttons always store the root of a transform chain,
-- enabling C_Spell.GetOverrideSpell to freely resolve to any current variant.
function ST.ResolveToBaseSpell(spellID)
    if not spellID then return spellID end
    local baseID = C_Spell.GetBaseSpell(spellID)
    return (baseID and baseID ~= 0) and baseID or spellID
end

--------------------------------------------------------------------------------
-- Spellbook Helpers
--------------------------------------------------------------------------------

-- Returns true if spellId (or its base spell) is an active (non-passive) entry
-- in the player's spellbook. Used by IsPassiveOrProc in Pickers to distinguish
-- real castable spells from aura/proc entries.
function ST.IsActiveSpellBookSpell(spellId)
    if not spellId then return false end

    local function IsActiveFromSpellIdentifier(spellIdentifier)
        local slotIdx, spellBank = C_SpellBook.FindSpellBookSlotForSpell(
            spellIdentifier,
            false, -- includeHidden
            true,  -- includeFlyouts
            false, -- includeFutureSpells
            true   -- includeOffSpec
        )
        if not slotIdx then
            return false
        end
        return not C_SpellBook.IsSpellBookItemPassive(slotIdx, spellBank)
    end

    if IsActiveFromSpellIdentifier(spellId) then
        return true
    end

    local baseSpellID = C_Spell.GetBaseSpell(spellId)
    if baseSpellID and baseSpellID ~= spellId then
        if IsActiveFromSpellIdentifier(baseSpellID) then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Passive Cooldown Helpers
--------------------------------------------------------------------------------

function ST.IsPassiveCooldownSpell(spellId)
    if not spellId or not C_Spell.IsSpellPassive(spellId) then
        return false
    end
    return ST.HasSpellCooldownSurface(spellId)
end

--------------------------------------------------------------------------------
-- Tooltip Cooldown Detection
--------------------------------------------------------------------------------

-- Returns true if the spell's tooltip indicates it has a cooldown.
-- Structurally detects the presence of rightText on the cast time line
-- (last type=0 line before the first type=34 description line) without
-- parsing localized text. Covers ALL spells including those with
-- externally-applied cooldowns that GetSpellBaseCooldown misses.
function ST.HasTooltipCooldown(spellId)
    if not spellId then return false end
    local data = C_TooltipInfo.GetSpellByID(spellId)
    if not data or not data.lines then return false end

    local lastNoneLine
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.SpellDescription then break end
        if line.type == Enum.TooltipDataLineType.None then
            lastNoneLine = line
        end
    end

    return lastNoneLine ~= nil and lastNoneLine.rightText ~= nil and lastNoneLine.rightText ~= ""
end

-- Returns true when the charge API exposes cooldown-bearing data, including
-- single-charge spells whose base cooldown can report as zero.
function ST.HasChargeCooldownInfo(spellId)
    if not spellId then return false end
    local charges = C_Spell.GetSpellCharges(spellId)
    local maxCharges = charges and charges.maxCharges
    if maxCharges and not (issecretvalue and issecretvalue(maxCharges)) then
        return (tonumber(maxCharges) or 0) > 0
    end
    return false
end

local function GetReadableMaxCharges(chargeInfo)
    local maxCharges = chargeInfo and chargeInfo.maxCharges
    if maxCharges and not (issecretvalue and issecretvalue(maxCharges)) then
        return tonumber(maxCharges)
    end
    return nil
end

function ST.ResolveSpellChargeInfo(spellId)
    if not spellId then return nil, spellId, nil end

    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    local chargeQueryID = spellId
    local maxCharges = GetReadableMaxCharges(chargeInfo)

    if not maxCharges or maxCharges <= 1 then
        local overrideID = C_Spell.GetOverrideSpell(spellId)
        if overrideID and overrideID ~= 0 and overrideID ~= spellId then
            local overrideInfo = C_Spell.GetSpellCharges(overrideID)
            local overrideMaxCharges = GetReadableMaxCharges(overrideInfo)
            if not chargeInfo then
                chargeQueryID = overrideID
            end
            if not chargeInfo and overrideInfo then
                chargeInfo = overrideInfo
                maxCharges = overrideMaxCharges
            elseif overrideInfo and (overrideMaxCharges or 0) > (maxCharges or 0) then
                chargeInfo = overrideInfo
                chargeQueryID = overrideID
                maxCharges = overrideMaxCharges
            end
        end
    end

    return chargeInfo, chargeQueryID, maxCharges
end

local function IsPositiveReadableNumber(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return (tonumber(value) or 0) > 0
end

local function IsResourceGatedNoCooldownPowerType(powerType)
    local powerTypes = Enum and Enum.PowerType
    if not powerTypes then return false end

    return powerType == powerTypes.Runes
        or powerType == powerTypes.Essence
end

local function HasPositivePowerCost(spellId, matchesPowerType)
    if not spellId then return false end

    local costs = C_Spell.GetSpellPowerCost(spellId)
    if not costs then return false end

    for _, costInfo in ipairs(costs) do
        if costInfo
            and matchesPowerType(costInfo.type)
            and (IsPositiveReadableNumber(costInfo.cost)
                or IsPositiveReadableNumber(costInfo.minCost)) then
            return true
        end
    end

    return false
end

function ST.HasPositiveResourceGateCost(spellId)
    return HasPositivePowerCost(spellId, IsResourceGatedNoCooldownPowerType)
end

local function HasBaseCooldown(spellId)
    local baseCd = GetSpellBaseCooldown(spellId)
    return baseCd and baseCd > 0
end

function ST.HasSpellCooldownSurface(spellId)
    if not spellId then return false end
    return HasBaseCooldown(spellId)
        or ST.HasTooltipCooldown(spellId)
        or ST.HasChargeCooldownInfo(spellId)
end

-- Returns true if the spell has no real cooldown surface (GCD-only).
function ST.IsNoCooldownSpell(spellId)
    return not ST.HasSpellCooldownSurface(spellId)
end

-- Returns true if the spell tooltip contains a UsageRequirement line
-- (e.g. "Requires Bear Form"). Uses structured tooltip data — no localized
-- text parsing. Complements HasTooltipCooldown for config-time gating.
function ST.HasUsageRequirement(spellId)
    if not spellId then return false end
    local data = C_TooltipInfo.GetSpellByID(spellId)
    if not data or not data.lines then return false end
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.UsageRequirement then
            return true
        end
    end
    return false
end
