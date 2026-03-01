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
    if not group then return nil, false end
    local folderId = group.folderId
    if folderId then
        local folders = self.db and self.db.profile and self.db.profile.folders
        local folder = folders and folders[folderId]
        if folder and folder.specs and next(folder.specs) then
            return folder.specs, true
        end
    end
    return group.specs, false
end

function CooldownCompanion:GetEffectiveHeroTalents(group)
    if not group then return nil, false end
    local folderId = group.folderId
    if folderId then
        local folders = self.db and self.db.profile and self.db.profile.folders
        local folder = folders and folders[folderId]
        if folder and folder.specs and next(folder.specs) then
            return folder.heroTalents, true
        end
    end
    return group.heroTalents, false
end

-- Folder filters are authoritative. When a folder filter is active, all child
-- groups are normalized to match it.
function CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not (db and folder) then return end

    local folderSpecs = folder.specs
    local hasFolderSpecs = folderSpecs and next(folderSpecs)
    local folderHeroTalents = hasFolderSpecs and folder.heroTalents
    local hasFolderHeroTalents = folderHeroTalents and next(folderHeroTalents)

    for _, group in pairs(db.groups) do
        if group.folderId == folderId then
            if hasFolderSpecs then
                group.specs = CopyTable(folderSpecs)
            else
                group.specs = nil
            end
            if hasFolderHeroTalents then
                group.heroTalents = CopyTable(folderHeroTalents)
            else
                group.heroTalents = nil
            end
        end
    end
end

function CooldownCompanion:SetFolderSpecs(folderId, specs)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not folder then return false end
    local oldSpecs = folder.specs and CopyTable(folder.specs) or nil

    if specs and next(specs) then
        local normalizedSpecs = {}
        for specId, enabled in pairs(specs) do
            local numSpecId = tonumber(specId)
            if enabled and numSpecId then
                normalizedSpecs[numSpecId] = true
            end
        end
        folder.specs = next(normalizedSpecs) and normalizedSpecs or nil
    else
        folder.specs = nil
    end

    -- Hero filters must remain scoped to selected specs.
    if folder.heroTalents and next(folder.heroTalents) then
        if not (folder.specs and next(folder.specs)) then
            folder.heroTalents = nil
        elseif oldSpecs then
            for specId in pairs(oldSpecs) do
                if not folder.specs[specId] then
                    -- Works for folders too; CleanHeroTalentsForSpec only mutates .heroTalents
                    self:CleanHeroTalentsForSpec(folder, specId)
                end
            end
        end
    end

    self:ApplyFolderSpecFilterToChildren(folderId)
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    return true
end

function CooldownCompanion:SetFolderHeroTalent(folderId, subTreeID, enabled)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not folder then return false end
    if not (folder.specs and next(folder.specs)) then return false end

    if enabled then
        if not folder.heroTalents then folder.heroTalents = {} end
        folder.heroTalents[subTreeID] = true
    else
        if folder.heroTalents then
            folder.heroTalents[subTreeID] = nil
            if not next(folder.heroTalents) then
                folder.heroTalents = nil
            end
        end
    end

    self:ApplyFolderSpecFilterToChildren(folderId)
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    return true
end

function CooldownCompanion:IsHeroTalentAllowed(group)
    local effectiveHeroTalents = self:GetEffectiveHeroTalents(group)
    if not (effectiveHeroTalents and next(effectiveHeroTalents)) then return true end
    local heroSpecId = self._currentHeroSpecId
    if not heroSpecId then return true end  -- low level, no hero talent selected
    return effectiveHeroTalents[heroSpecId] == true
end

function CooldownCompanion:IsGroupActive(groupId, opts)
    opts = opts or {}
    local group = opts.group or self.db.profile.groups[groupId]
    if not group then return false end

    if group.enabled == false then return false end

    if opts.requireButtons and (not group.buttons or #group.buttons == 0) then
        return false
    end

    local effectiveSpecs = self:GetEffectiveSpecs(group)
    if effectiveSpecs and next(effectiveSpecs) then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    if not self:IsHeroTalentAllowed(group) then return false end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then checkCharVisibility = true end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    local checkLoadConditions = opts.checkLoadConditions
    if checkLoadConditions == nil then checkLoadConditions = true end
    if checkLoadConditions and not self:CheckLoadConditions(group) then
        return false
    end

    return true
end

function CooldownCompanion:CleanHeroTalentsForSpec(group, specId)
    if not group.heroTalents or not next(group.heroTalents) then return end
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if not subTreeIDs then return end
    for _, subTreeID in ipairs(subTreeIDs) do
        group.heroTalents[subTreeID] = nil
    end
    if not next(group.heroTalents) then
        group.heroTalents = nil
    end
end

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.displayMode ~= "icons" then return false end
    if group.isGlobal then return false end
    if not self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
    }) then
        return false
    end

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

    -- If pet battle condition is enabled and player is in a pet battle, unload
    -- Default is true (hide during pet battles); nil treated as true since
    -- AceDB has no per-group metatable defaults for loadConditions sub-keys.
    if lc.petBattle ~= false and self._inPetBattle then return false end

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

        -- Pet spells: retain direct known/spellbook check.
        if buttonData.isPetSpell then
            return C_SpellBook.IsSpellKnownOrInSpellBook(buttonData.id, bank, false)
        end

        -- Player spells: require exact active-spec spellbook presence for this
        -- tracked spell ID (not an override/sibling form). This keeps loadability
        -- aligned with current-spec spellbook addability semantics.
        local slot, slotBank = C_SpellBook.FindSpellBookSlotForSpell(
            buttonData.id, false, true, false, false
        )
        if slot and slotBank == Enum.SpellBookSpellBank.Player then
            local itemType, _, spellID = C_SpellBook.GetSpellBookItemType(slot, slotBank)
            if spellID
                and not C_SpellBook.IsSpellBookItemOffSpec(slot, slotBank)
                and itemType ~= Enum.SpellBookItemType.FutureSpell
                and spellID == buttonData.id
            then
                return true
            end
        end

        -- Flyout child spells can be valid even when they don't resolve to a
        -- direct spell slot via FindSpellBookSlotForSpell.
        local flyoutSlot = C_SpellBook.FindFlyoutSlotBySpellID(buttonData.id)
        if not flyoutSlot then
            return false
        end

        local flyoutBank = Enum.SpellBookSpellBank.Player
        local flyoutType = C_SpellBook.GetSpellBookItemType(flyoutSlot, flyoutBank)
        if flyoutType ~= Enum.SpellBookItemType.Flyout then
            return false
        end
        if C_SpellBook.IsSpellBookItemOffSpec(flyoutSlot, flyoutBank) then
            return false
        end

        return true
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

-- Refresh only frame-level visibility/load-state without rebuilding buttons.
-- Used by zone/resting/pet-battle transitions to avoid compact-layout flash
-- caused by full button repopulation.
function CooldownCompanion:RefreshAllGroupsVisibilityOnly()
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

    for groupId, group in pairs(self.db.profile.groups) do
        if not self:IsGroupVisibleToCurrentChar(groupId) then
            if self.groupFrames[groupId] then
                self.groupFrames[groupId]:Hide()
            end
        else
            local frame = self.groupFrames[groupId]
            if not frame then
                frame = self:CreateGroupFrame(groupId)
            end

            if frame then
                local wasShown = frame:IsShown()
                local active = self:IsGroupActive(groupId, {
                    group = group,
                    checkCharVisibility = true,
                    checkLoadConditions = true,
                    requireButtons = true,
                })

                if active then
                    frame:Show()
                    -- Force 100% alpha while unlocked for easier positioning
                    if not group.locked then
                        frame:SetAlpha(1)
                    -- Apply current alpha from the alpha fade system so frame
                    -- doesn't flash at 1.0 when baseline alpha is configured.
                    elseif group.baselineAlpha < 1 then
                        local alphaState = self.alphaState and self.alphaState[groupId]
                        if alphaState and alphaState.currentAlpha then
                            frame:SetAlpha(alphaState.currentAlpha)
                        end
                    end

                    -- When transitioning hidden -> shown, refresh button state
                    -- immediately so compact groups never show stale slots.
                    if not wasShown then
                        if frame.UpdateCooldowns then
                            frame:UpdateCooldowns()
                        end
                        if group.compactLayout then
                            frame._layoutDirty = true
                            self:UpdateGroupLayout(groupId)
                        end
                    end
                else
                    frame:Hide()
                end
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
        if frame and frame:IsShown() then
            if frame._sizeDirty then
                self:ResizeGroupFrame(groupId)
            end
            if frame._layoutDirty then
                self:UpdateGroupLayout(groupId)
            end
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
