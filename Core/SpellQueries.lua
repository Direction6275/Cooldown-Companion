--[[
    CooldownCompanion - SpellQueries
    Spell resolution, spellbook lookups, CDM queries, and tooltip detection
]]

local ADDON_NAME, ST = ...

local ipairs = ipairs

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
-- CDM (Cooldown Manager) Helpers
--------------------------------------------------------------------------------

-- Returns true if spellId (or its override/tooltip override) is tracked by
-- Blizzard's Cooldown Manager in the Essential or Utility categories.
-- Spells with externally-applied cooldowns (class aura / talent passive) are
-- tracked here even when GetSpellBaseCooldown returns 0; true GCD-only spells
-- are not.
function ST.IsSpellInCDMCooldown(spellId)
    if not spellId then return false end
    for _, cat in ipairs({Enum.CooldownViewerCategory.Essential, Enum.CooldownViewerCategory.Utility}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    if info.spellID == spellId or info.overrideSpellID == spellId
                       or info.overrideTooltipSpellID == spellId then
                        return true
                    end
                end
            end
        end
    end
    return false
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
