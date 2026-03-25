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
local pendingViewerAuraMapToken = 0

local function IsBuffViewerChild(frame)
    if not frame then return false end
    local parent = frame:GetParent()
    local parentName = parent and parent:GetName()
    return BUFF_VIEWER_SET[parentName] == true
end

function CooldownCompanion:OnUnitAura(event, unit, updateInfo)
    self._cooldownsDirty = true
    if unit == "player" and self._isDracthyr then
        self:InvalidateMountAlphaCache()
    end

    if not updateInfo then return end

    -- Merged single-pass processing: removals, pandemic updates, and target-switch
    -- signaling in one ForEachButton call instead of three separate iterations.
    -- Removals are processed first so refreshed auras (remove + add in same event)
    -- work correctly — the update path re-checks _auraInstanceID after removals.
    local removedIDs = updateInfo.removedAuraInstanceIDs
    local updatedIDs = updateInfo.updatedAuraInstanceIDs
    local isTarget = (unit == "target")
    if removedIDs or updatedIDs or isTarget then
        self:ForEachButton(function(button)
            if button._auraInstanceID and button._auraUnit == unit then
                if removedIDs then
                    for _, instId in ipairs(removedIDs) do
                        if button._auraInstanceID == instId then
                            button._auraInstanceID = nil
                            button._inPandemic = false
                            button._auraEventRemoved = true
                            break
                        end
                    end
                end
                -- Aura reapplication (pandemic refresh) arrives as an update, not a
                -- removal + add.  Clear pandemic state and suppress the grace hold so
                -- the next evaluation clears pandemic immediately instead of holding 0.3s.
                if updatedIDs and button._auraInstanceID then
                    for _, instId in ipairs(updatedIDs) do
                        if button._auraInstanceID == instId then
                            button._inPandemic = false
                            button._pandemicGraceStart = nil
                            button._pandemicGraceSuppressed = true
                            break
                        end
                    end
                end
            end
            -- Signal that the server has delivered target aura data, so the hold
            -- logic in CooldownUpdate can terminate early instead of waiting for the
            -- safety cap timeout.
            if isTarget and button._targetSwitchAt then
                button._targetSwitchDataReceived = true
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
    self:ForEachButton(function(button, bd)
        if bd.auraTracking or bd.isPassive then
            local shouldClear = button._auraUnit == unitToken
            -- _auraUnit defaults to "player" even for debuff-tracking buttons
            -- whose viewer frame has auraDataUnit == "target".  Check the viewer
            -- map as a fallback so target-switch clears actually reach them.
            if not shouldClear and unitToken == "target" then
                local f = button._auraSpellID and self:ResolveBuffViewerFrameForSpell(button._auraSpellID)
                if not f and not bd.auraSpellID then
                    f = self:ResolveBuffViewerFrameForSpell(bd.id)
                end
                shouldClear = f and f.auraDataUnit == "target"
            end
            if shouldClear then
                button._auraInstanceID = nil
                button._auraActive = false
                button._inPandemic = false
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
            end
        end
    end)
    self._cooldownsDirty = true
end

function CooldownCompanion:OnTargetChanged()
    if not UnitExists("target") then
        -- Deselected target: clear all target aura state immediately
        self:ClearAuraUnit("target")
        return
    end
    -- New target: clear stale instance IDs so the viewer path doesn't
    -- read old auraInstanceIDs.  Keep _auraActive so the hold can
    -- maintain visual continuity while CDM refreshes.
    local now = GetTime()
    self:ForEachButton(function(button, bd)
        if bd.auraTracking or bd.isPassive then
            local isTarget = button._auraUnit == "target"
            if not isTarget then
                local f = button._auraSpellID and self:ResolveBuffViewerFrameForSpell(button._auraSpellID)
                if not f and not bd.auraSpellID then
                    f = self:ResolveBuffViewerFrameForSpell(bd.id)
                end
                isTarget = f and f.auraDataUnit == "target"
            end
            if isTarget then
                button._auraInstanceID = nil
                button._inPandemic = false
                button._targetSwitchAt = now
                button._targetSwitchDataReceived = nil
            end
        end
    end)
    -- Synchronous probe: CDM viewer frames register their event handlers on
    -- Blizzard frames created before addons load.  If UNIT_TARGET has already
    -- been processed by the time PLAYER_TARGET_CHANGED fires, the CDM children
    -- will have fresh auraInstanceID data.  Probing immediately lets the
    -- primary path clear _targetSwitchAt in the same frame — zero hold.
    self:UpdateAllCooldowns()
end


function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.type == "spell" then
        -- Resolve through base spell so form-variant spells (e.g. Stampeding
        -- Roar: 106898/77764/77761) use the base ID for aura lookups — the
        -- buff is always applied as the base spell regardless of form.
        local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
        local auraId = C_UnitAuras.GetCooldownAuraBySpellID(baseId)
        if auraId and auraId ~= 0 then
            -- If the cooldown aura is a form variant of the same base spell,
            -- use the base spell ID — the buff is always applied as base form.
            local auraBase = C_Spell.GetBaseSpell(auraId)
            if auraBase and auraBase == baseId and auraBase ~= auraId then
                return baseId
            end
            return auraId
        end
        -- Many spells share the same ID for cast and buff; fall back to the base spell ID
        return baseId
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
-- Checks cooldownInfo spell associations used by CDM (base, overrides, linked).
local function FindChildInViewers(viewerNames, spellID, buffOnly)
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                local info = child.cooldownInfo
                if info and (not buffOnly or IsBuffViewerChild(child)) then
                    if info.spellID == spellID
                       or info.overrideSpellID == spellID
                       or info.overrideTooltipSpellID == spellID then
                        return child
                    end
                    if info.linkedSpellIDs then
                        for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                            if linkedSpellID == spellID then
                                return child
                            end
                        end
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
            if not InCombatLockdown() then
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
end

function CooldownCompanion:QueueBuildViewerAuraMap()
    pendingViewerAuraMapToken = pendingViewerAuraMapToken + 1
    local token = pendingViewerAuraMapToken
    C_Timer.After(0, function()
        if pendingViewerAuraMapToken ~= token then return end
        self:BuildViewerAuraMap()
        self:RefreshConfigPanel()
    end)
end

function CooldownCompanion:ResolveBuffViewerFrameForSpell(spellID)
    local enabled = self._cdmViewerEnabled
    if enabled == nil then enabled = GetCVarBool("cooldownViewerEnabled") end
    if not spellID or spellID == 0 or not enabled then
        return nil
    end

    local child = self.viewerAuraFrames and self.viewerAuraFrames[spellID]
    if IsBuffViewerChild(child) and type(child.cooldownInfo) == "table" then
        return child
    end

    child = FindChildInViewers(VIEWER_NAMES, spellID, true)
    if child then
        self.viewerAuraFrames[spellID] = child
        return child
    end
    return nil
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
                local info = child.cooldownInfo
                if info then
                    local spellID = info.spellID
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
                    local override = info.overrideSpellID
                    if override then
                        self.viewerAuraFrames[override] = child
                    end
                    local tooltipOverride = info.overrideTooltipSpellID
                    if tooltipOverride then
                        self.viewerAuraFrames[tooltipOverride] = child
                    end
                    if info.linkedSpellIDs then
                        for _, linked in ipairs(info.linkedSpellIDs) do
                            self.viewerAuraFrames[linked] = child
                        end
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

    -- Rebuild spell -> cooldown alert capability mapping used by per-button sound alerts.
    self:RebuildSoundAlertSpellMap()

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
