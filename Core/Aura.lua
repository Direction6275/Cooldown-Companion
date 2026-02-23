--[[
    CooldownCompanion - Core/Aura.lua: Aura event handlers (OnUnitAura, ClearAuraUnit,
    OnTargetChanged), aura resolution, ABILITY_BUFF_OVERRIDES, CDM viewer system
    (ApplyCdmAlpha, BuildViewerAuraMap, FindViewerChildForSpell, FindCooldownViewerChild,
    OnViewerSpellOverrideUpdated)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local tostring = tostring
local tonumber = tonumber

-- Import cross-file variables (viewer system)
local VIEWER_NAMES = ST._VIEWER_NAMES
local COOLDOWN_VIEWER_NAMES = ST._COOLDOWN_VIEWER_NAMES
local BUFF_VIEWER_SET = ST._BUFF_VIEWER_SET
local cdmAlphaGuard = ST._cdmAlphaGuard

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

-------------------------------------------------------------------------------
-- CDM Viewer System (merged from Core/ViewerAura.lua)
-------------------------------------------------------------------------------

-- Shared helper: scan a list of viewer frames for a child matching spellID.
-- Checks cooldownInfo.spellID, overrideSpellID, and overrideTooltipSpellID.
local function FindChildInViewers(viewerNames, spellID)
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                if child.cooldownInfo then
                    if child.cooldownInfo.spellID == spellID
                       or child.cooldownInfo.overrideSpellID == spellID
                       or child.cooldownInfo.overrideTooltipSpellID == spellID then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

function CooldownCompanion:ApplyCdmAlpha()
    local hidden = self.db.profile.cdmHidden and not self._cdmPickMode
    local alpha = hidden and 0 or 1
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            cdmAlphaGuard[viewer] = true
            viewer:SetAlpha(alpha)
            cdmAlphaGuard[viewer] = nil
            viewer:EnableMouse(not hidden)
            if hidden then
                for _, child in pairs({viewer:GetChildren()}) do
                    child:SetMouseMotionEnabled(false)
                end
            else
                -- Restore tooltip state using Blizzard's own pattern
                for itemFrame in viewer.itemFramePool:EnumerateActive() do
                    itemFrame:SetTooltipsShown(viewer.tooltipsShown)
                end
            end
        end
    end
end

-- Build a mapping from spellID → Blizzard cooldown viewer child frame.
-- The viewer frames (EssentialCooldownViewer, UtilityCooldownViewer, etc.)
-- run untainted code that reads secret aura data and stores the result
-- (auraInstanceID, auraDataUnit) as plain frame properties we can read.
function CooldownCompanion:BuildViewerAuraMap()
    wipe(self.viewerAuraFrames)
    wipe(self.viewerAuraAllChildren)
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                if child.cooldownInfo then
                    local spellID = child.cooldownInfo.spellID
                    if spellID then
                        self.viewerAuraFrames[spellID] = child
                        -- Track all children per base spellID for buff viewers only.
                        -- Duplicate detection is for same-section duplicates (e.g.
                        -- Diabolic Ritual twice in Tracked Buffs), not cross-section
                        -- matches (e.g. Agony in Essential + Buffs).
                        if BUFF_VIEWER_SET[name] then
                            if not self.viewerAuraAllChildren[spellID] then
                                self.viewerAuraAllChildren[spellID] = {}
                            end
                            table.insert(self.viewerAuraAllChildren[spellID], child)
                        end
                    end
                    local override = child.cooldownInfo.overrideSpellID
                    if override then
                        self.viewerAuraFrames[override] = child
                    end
                    local tooltipOverride = child.cooldownInfo.overrideTooltipSpellID
                    if tooltipOverride then
                        self.viewerAuraFrames[tooltipOverride] = child
                    end
                end
            end
        end
    end
    -- Ensure tracked buttons can find their viewer child even if
    -- buttonData.id is a non-current override form of a transforming spell.
    self:MapButtonSpellsToViewers()

    -- Map hardcoded overrides: ability IDs and buff IDs → viewer child.
    -- Group by buff string so sibling abilities (e.g. Solar/Lunar Eclipse)
    -- cross-map to the same viewer child even if only one form is current.
    local groupsByBuffs = {}
    for abilityID, buffIDStr in pairs(self.ABILITY_BUFF_OVERRIDES) do
        if not groupsByBuffs[buffIDStr] then
            groupsByBuffs[buffIDStr] = {}
        end
        groupsByBuffs[buffIDStr][#groupsByBuffs[buffIDStr] + 1] = abilityID
    end
    for buffIDStr, abilityIDs in pairs(groupsByBuffs) do
        -- Prefer a BuffIcon/BuffBar child (tracks aura duration) over
        -- Essential/Utility (tracks cooldown only). Check buff IDs first
        -- since the initial scan maps them to the correct viewer type.
        local child
        for id in buffIDStr:gmatch("%d+") do
            local c = self.viewerAuraFrames[tonumber(id)]
            if c then
                local p = c:GetParent()
                local pn = p and p:GetName()
                if pn == "BuffIconCooldownViewer" or pn == "BuffBarCooldownViewer" then
                    child = c
                    break
                end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self.viewerAuraFrames[abilityID]
                if child then break end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self:FindViewerChildForSpell(abilityID)
                if child then break end
            end
        end
        if child then
            for _, abilityID in ipairs(abilityIDs) do
                self.viewerAuraFrames[abilityID] = child
            end
            -- Map buff IDs only if they aren't already mapped by the initial scan.
            -- Each buff may have its own viewer child (e.g. Solar vs Lunar Eclipse).
            for id in buffIDStr:gmatch("%d+") do
                local numID = tonumber(id)
                if not self.viewerAuraFrames[numID] then
                    self.viewerAuraFrames[numID] = child
                end
            end
        end
    end

    -- Re-enforce mouse state for hidden CDM after map rebuild
    if self.db.profile.cdmHidden and not self._cdmPickMode then
        for _, name2 in ipairs(VIEWER_NAMES) do
            local v = _G[name2]
            if v then
                for _, child in pairs({v:GetChildren()}) do
                    child:SetMouseMotionEnabled(false)
                end
            end
        end
    end
end

-- For each tracked button, ensure viewerAuraFrames contains an entry
-- for buttonData.id. Handles the case where the spell was added while
-- in one form (e.g. Solar Eclipse) but the map was rebuilt while the
-- spell is in a different form (e.g. Lunar Eclipse).
function CooldownCompanion:MapButtonSpellsToViewers()
    self:ForEachButton(function(button, bd)
        local id = bd.id
        if id and bd.type == "spell" and not self.viewerAuraFrames[id] then
            local child = self:FindViewerChildForSpell(id)
            if child then
                self.viewerAuraFrames[id] = child
            end
        end
    end)
end

-- Scan viewer children to find one that tracks a given spellID.
-- Checks spellID, overrideSpellID, overrideTooltipSpellID on each child,
-- then uses GetBaseSpell to resolve override forms back to their base spell.
-- Returns the child frame if found, nil otherwise.
function CooldownCompanion:FindViewerChildForSpell(spellID)
    local child = FindChildInViewers(VIEWER_NAMES, spellID)
    if child then return child end
    -- GetBaseSpell (AllowedWhenTainted): resolve override → base, then check map.
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        child = self.viewerAuraFrames[baseSpellID]
        if child then return child end
    end
    -- Override table: check buff IDs and sibling abilities
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        for id in overrideBuffs:gmatch("%d+") do
            child = self.viewerAuraFrames[tonumber(id)]
            if child then return child end
        end
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                child = self.viewerAuraFrames[sibID]
                if child then return child end
            end
        end
    end
    return nil
end

-- Find a cooldown viewer child (Essential/Utility only) for a spell.
-- Used by UpdateButtonIcon to get dynamic icon/name from the cooldown tracker
-- rather than the buff tracker (BuffIcon/BuffBar), which uses static buff spell IDs.
function CooldownCompanion:FindCooldownViewerChild(spellID)
    local child = FindChildInViewers(COOLDOWN_VIEWER_NAMES, spellID)
    if child then return child end
    -- Try base spell resolution
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        return self:FindCooldownViewerChild(baseSpellID)
    end
    -- Try sibling abilities from override table
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                child = FindChildInViewers(COOLDOWN_VIEWER_NAMES, sibID)
                if child then return child end
            end
        end
    end
    return nil
end

-- When a spell transforms (e.g. Solar Eclipse → Lunar Eclipse), map the new
-- override spell ID to the same viewer child frame so lookups work for both forms.
function CooldownCompanion:OnViewerSpellOverrideUpdated(event, baseSpellID, overrideSpellID)
    if not baseSpellID then return end
    -- Multi-child: find the specific child whose overrideSpellID matches
    local allChildren = self.viewerAuraAllChildren[baseSpellID]
    if allChildren and overrideSpellID then
        for _, c in ipairs(allChildren) do
            if c.cooldownInfo and c.cooldownInfo.overrideSpellID == overrideSpellID then
                self.viewerAuraFrames[overrideSpellID] = c
                break
            end
        end
    elseif overrideSpellID then
        -- Single-child fallback (original behavior)
        local child = self.viewerAuraFrames[baseSpellID]
        if child then
            self.viewerAuraFrames[overrideSpellID] = child
        end
    end
    -- Refresh icons/names now that the viewer child's overrideSpellID is current
    self:OnSpellUpdateIcon()
    -- Update config panel if open (name, icon, usability may have changed)
    self:RefreshConfigPanel()
end
