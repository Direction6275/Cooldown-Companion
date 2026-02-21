--[[
    CooldownCompanion - Core/GroupOperations.lua: LSM helpers, group visibility/load conditions,
    state toggles, group frame operations, spell/item info utilities
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local select = select

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

function CooldownCompanion:FetchFont(name)
    return LSM:Fetch("font", name) or LSM:Fetch("font", "Friz Quadrata TT") or STANDARD_TEXT_FONT
end

function CooldownCompanion:FetchStatusBar(name)
    return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Solid") or [[Interface\BUTTONS\WHITE8X8]]
end

-- Re-apply all media after a SharedMedia pack registers new fonts/textures
function CooldownCompanion:RefreshAllMedia()
    self:RefreshAllGroups()
    self:ApplyResourceBars()
    self:ApplyCastBarSettings()
end

function CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.isGlobal then return true end
    return group.createdBy == self.db.keys.char
end

function CooldownCompanion:GetEffectiveSpecs(group)
    return group.specs, false
end

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.displayMode ~= "icons" then return false end
    if group.isGlobal then return false end
    if group.enabled == false then return false end
    if not self:IsGroupVisibleToCurrentChar(groupId) then return false end

    local effectiveSpecs = self:GetEffectiveSpecs(group)
    if effectiveSpecs and next(effectiveSpecs) then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    if not self:CheckLoadConditions(group) then return false end

    return true
end

function CooldownCompanion:GetFirstAvailableAnchorGroup()
    local groups = self.db.profile.groups
    if not groups then return nil end

    local candidates = {}
    for groupId in pairs(groups) do
        if self:IsGroupAvailableForAnchoring(groupId) then
            table.insert(candidates, groupId)
        end
    end
    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        local orderA = groups[a].order or a
        local orderB = groups[b].order or b
        return orderA < orderB
    end)
    return candidates[1]
end

function CooldownCompanion:CheckLoadConditions(group)
    local lc = group.loadConditions
    if not lc then return true end

    local instanceType = self._currentInstanceType

    -- Map instance type to load condition key
    local conditionKey
    if instanceType == "raid" then
        conditionKey = "raid"
    elseif instanceType == "party" then
        conditionKey = "dungeon"
    elseif instanceType == "pvp" then
        conditionKey = "battleground"
    elseif instanceType == "arena" then
        conditionKey = "arena"
    elseif instanceType == "delve" then
        conditionKey = "delve"
    else
        conditionKey = "openWorld"  -- "none" or "scenario"
    end

    -- If the matching instance condition is enabled, unload
    if lc[conditionKey] then return false end

    -- If rested condition is enabled and player is resting, unload
    if lc.rested and self._isResting then return false end

    return true
end


function CooldownCompanion:ToggleGroupGlobal(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return end
    group.isGlobal = not group.isGlobal
    if not group.isGlobal then
        group.createdBy = self.db.keys.char
    end
    -- Clear folder assignment — the folder belongs to the old section
    group.folderId = nil
    self:RefreshAllGroups()
end

function CooldownCompanion:GroupHasPetSpells(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.isPetSpell then return true end
    end
    return false
end

function CooldownCompanion:IsButtonUsable(buttonData)
    -- Passive/proc spells are tracked via aura, not spellbook presence.
    -- Multi-CDM-child buttons: verify their specific slot still exists in the CDM
    -- (spell may not be available on the current spec/talent loadout).
    if buttonData.isPassive then
        if buttonData.cdmChildSlot then
            local allChildren = self.viewerAuraAllChildren[buttonData.id]
            if not allChildren or not allChildren[buttonData.cdmChildSlot] then
                return false
            end
        end
        return true
    end

    if buttonData.type == "spell" then
        local bank = buttonData.isPetSpell
            and Enum.SpellBookSpellBank.Pet
            or Enum.SpellBookSpellBank.Player
        if C_SpellBook.IsSpellKnownOrInSpellBook(buttonData.id, bank) then
            return true
        end
        -- Fallback: spell may be stored as an override form; check the base spell.
        -- Only relevant for player spells (pet spells don't have override forms).
        if not buttonData.isPetSpell then
            local baseID = C_Spell.GetBaseSpell(buttonData.id)
            if baseID and baseID ~= buttonData.id then
                return C_SpellBook.IsSpellKnownOrInSpellBook(baseID)
            end
        end
        return false
    elseif buttonData.type == "item" then
        if buttonData.hasCharges then return true end
        if not CooldownCompanion.IsItemEquippable(buttonData) then return true end
        return C_Item.GetItemCount(buttonData.id) > 0
    end
    return true
end

function CooldownCompanion:CreateAllGroupFrames()
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:CreateGroupFrame(groupId)
        end
    end
end

function CooldownCompanion:RefreshAllGroups()
    -- Fully deactivate frames for groups not in the current profile
    -- (e.g. after a profile switch). Removes from groupFrames so
    -- ForEachButton / event handlers skip them entirely.
    for groupId, frame in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:DeleteMasqueGroup(groupId)
            frame:Hide()
            self.groupFrames[groupId] = nil
            if self.alphaState then
                self.alphaState[groupId] = nil
            end
        end
    end

    -- Refresh current profile's groups
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:RefreshGroupFrame(groupId)
        else
            if self.groupFrames[groupId] then
                self.groupFrames[groupId]:Hide()
            end
        end
    end
end

function CooldownCompanion:UpdateAllCooldowns()
    self._gcdInfo = C_Spell.GetSpellCooldown(61304)
    -- Widget-level GCD activity signal (secret-safe, plain boolean)
    local gcdDuration = C_Spell.GetSpellCooldownDuration(61304)
    if gcdDuration then
        self._gcdScratch:Hide()
        self._gcdScratch:SetCooldownFromDurationObject(gcdDuration)
        self._gcdActive = self._gcdScratch:IsShown()
        self._gcdScratch:Hide()
    else
        self._gcdActive = false
    end
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns and frame:IsShown() then
            frame:UpdateCooldowns()
        end
    end
end

function CooldownCompanion:UpdateAllGroupLayouts()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() and frame._layoutDirty then
            self:UpdateGroupLayout(groupId)
        end
    end
end

function CooldownCompanion:LockAllFrames()
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
end

function CooldownCompanion:UnlockAllFrames()
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if frame.dragHandle then
                frame.dragHandle:Show()
            end
            -- Force 100% alpha while unlocked for easier positioning
            frame:SetAlpha(1)
        end
    end
end

-- Utility functions
function CooldownCompanion:GetSpellInfo(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if spellInfo then
        return spellInfo.name, spellInfo.iconID, spellInfo.castTime
    end
    return nil
end

function CooldownCompanion:GetItemInfo(itemId)
    local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
    if not itemName then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        return nil, icon
    end
    return itemName, itemIcon
end
