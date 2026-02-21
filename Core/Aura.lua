--[[
    CooldownCompanion - Core/Aura.lua: OnUnitAura, ClearAuraUnit, OnTargetChanged,
    ResolveAuraSpellID, ABILITY_BUFF_OVERRIDES table
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber

function CooldownCompanion:OnUnitAura(event, unit, updateInfo)
    self._cooldownsDirty = true
    if not updateInfo then return end

    -- Process removals first so refreshed auras (remove + add in same event) work.
    -- Single traversal with inner loop (instead of N traversals) to avoid N closures
    -- and N full button scans when many auras are removed at once (e.g. leaving combat).
    if updateInfo.removedAuraInstanceIDs then
        local removedIDs = updateInfo.removedAuraInstanceIDs
        self:ForEachButton(function(button)
            if button._auraInstanceID and button._auraUnit == unit then
                for _, instId in ipairs(removedIDs) do
                    if button._auraInstanceID == instId then
                        button._auraInstanceID = nil
                        button._inPandemic = false
                        break
                    end
                end
            end
        end)
    end

    -- Update immediately — CDM viewer frames registered their event handlers
    -- before our addon loaded, so by the time this handler fires the CDM has
    -- already refreshed its children with fresh auraInstanceID data.
    if unit == "target" or unit == "player" then
        self:UpdateAllCooldowns()
    end
end

-- Clear aura state on buttons tracking a unit when that unit changes (target/focus switch).
-- The viewer will re-evaluate on its next tick; this ensures stale data is cleared promptly.
function CooldownCompanion:ClearAuraUnit(unitToken)
    local vf = self.viewerAuraFrames
    self:ForEachButton(function(button, bd)
        if bd.auraTracking then
            local shouldClear = button._auraUnit == unitToken
            -- _auraUnit defaults to "player" even for debuff-tracking buttons
            -- whose viewer frame has auraDataUnit == "target".  Check the viewer
            -- map as a fallback so target-switch clears actually reach them.
            if not shouldClear and unitToken == "target" and vf then
                local f = (button._auraSpellID and vf[button._auraSpellID])
                    or vf[bd.id]
                shouldClear = f and f.auraDataUnit == "target"
            end
            if shouldClear then
                button._auraInstanceID = nil
                button._auraActive = false
                button._inPandemic = false
            end
        end
    end)
    self._cooldownsDirty = true
end

function CooldownCompanion:OnTargetChanged()
    self._cooldownsDirty = true
end


function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.type == "spell" then
        local auraId = C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
        if auraId and auraId ~= 0 then return auraId end
        -- Many spells share the same ID for cast and buff; fall back to the spell's own ID
        return buttonData.id
    end
    return nil
end

-- Hardcoded ability → buff overrides for spells whose ability ID and buff IDs
-- are completely unlinked by any API (GetCooldownAuraBySpellID returns 0).
-- Both Eclipse forms map to both buff IDs so whichever buff is active gets tracked.
-- Format: [abilitySpellID] = "comma-separated buff spell IDs"
CooldownCompanion.ABILITY_BUFF_OVERRIDES = {
    [1233346] = "48517,48518",  -- Solar Eclipse → Eclipse (Solar) + Eclipse (Lunar) buffs
    [1233272] = "48517,48518",  -- Lunar Eclipse → Eclipse (Solar) + Eclipse (Lunar) buffs
}
