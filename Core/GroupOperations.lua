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
local next = next
local type = type
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack

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
        if folder and folder.heroTalents and next(folder.heroTalents) then
            return folder.heroTalents, true
        end
    end
    return group.heroTalents, false
end

local function CopyTalentCondition(cond)
    return {
        nodeID = cond.nodeID,
        entryID = cond.entryID,
        spellID = cond.spellID,
        name = cond.name,
        show = cond.show or "taken",
        specID = cond.specID,
        specName = cond.specName,
        heroSubTreeID = cond.heroSubTreeID,
        heroName = cond.heroName,
    }
end

local function IsLegacyChoiceRowCondition(cond)
    return type(cond) == "table"
        and cond.entryID == nil
        and cond.spellID == nil
        and type(cond.name) == "string"
        and cond.name:sub(1, 12) == "Choice row: "
end

function CooldownCompanion:NormalizeTalentConditions(conditions)
    if type(conditions) ~= "table" then return nil, false end

    local grouped = {}
    local orderedGroupKeys = {}
    local passthrough = {}
    local hasDuplicateNode = false
    local hasLegacyChoiceRow = false
    local hasUnscopedNodeCondition = false
    local scopedSpecIDs = {}
    local scopedHeroIDs = {}
    local scopedSpecCount = 0
    local scopedHeroCount = 0

    for _, cond in ipairs(conditions) do
        if type(cond) == "table" and cond.nodeID then
            if IsLegacyChoiceRowCondition(cond) then
                hasLegacyChoiceRow = true
            end
            if not cond.specID then
                hasUnscopedNodeCondition = true
            end
            if cond.specID and not scopedSpecIDs[cond.specID] then
                scopedSpecIDs[cond.specID] = true
                scopedSpecCount = scopedSpecCount + 1
            end
            if cond.heroSubTreeID and not scopedHeroIDs[cond.heroSubTreeID] then
                scopedHeroIDs[cond.heroSubTreeID] = true
                scopedHeroCount = scopedHeroCount + 1
            end

            local groupKey = tostring(cond.nodeID)
                .. "|" .. tostring(cond.specID or 0)
                .. "|" .. tostring(cond.heroSubTreeID or 0)
            local group = grouped[groupKey]
            if not group then
                group = {}
                grouped[groupKey] = group
                orderedGroupKeys[#orderedGroupKeys + 1] = groupKey
            else
                hasDuplicateNode = true
            end
            group[#group + 1] = cond
        else
            passthrough[#passthrough + 1] = cond
        end
    end

    if not hasDuplicateNode
        and not hasLegacyChoiceRow
        and scopedSpecCount <= 1
        and scopedHeroCount <= 1
        and not (scopedSpecCount > 0 and hasUnscopedNodeCondition)
    then
        return conditions, false
    end

    local normalized = {}
    for _, cond in ipairs(passthrough) do
        normalized[#normalized + 1] = cond
    end

    for _, groupKey in ipairs(orderedGroupKeys) do
        local group = grouped[groupKey]
        if group and #group > 0 then
            local firstCondition = nil
            local firstSpecific = nil
            local takenCount = 0
            local seenEntries = {}
            local takenCondition = nil
            local uniqueEntryCount = 0
            local specificCount = 0

            for _, cond in ipairs(group) do
                if not firstCondition and not IsLegacyChoiceRowCondition(cond) then
                    firstCondition = cond
                end

                if cond.entryID ~= nil then
                    if not firstSpecific then
                        firstSpecific = cond
                    end
                    specificCount = specificCount + 1
                    if not seenEntries[cond.entryID] then
                        seenEntries[cond.entryID] = true
                        uniqueEntryCount = uniqueEntryCount + 1
                    end

                    if (cond.show or "taken") == "not_taken" then
                        -- no-op
                    else
                        takenCount = takenCount + 1
                        takenCondition = cond
                    end
                end
            end

            local resolved
            if specificCount > 1 and specificCount == uniqueEntryCount and uniqueEntryCount > 1 then
                if takenCount == 1 then
                    resolved = CopyTalentCondition(takenCondition)
                else
                    resolved = CopyTalentCondition(firstSpecific)
                end
            end

            if not resolved then
                local fallback = firstSpecific or firstCondition
                if fallback then
                    resolved = CopyTalentCondition(fallback)
                end
            end

            if resolved then
                normalized[#normalized + 1] = resolved
            end
        end
    end

    local chosenSpecID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.specID then
            chosenSpecID = cond.specID
            break
        end
    end
    if chosenSpecID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if cond.specID == chosenSpecID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    local chosenHeroSubTreeID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.heroSubTreeID then
            chosenHeroSubTreeID = cond.heroSubTreeID
            break
        end
    end
    if chosenHeroSubTreeID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if not cond.heroSubTreeID or cond.heroSubTreeID == chosenHeroSubTreeID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    if #normalized == 0 then
        return nil, true
    end
    return normalized, true
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

    -- If vehicle/override UI condition is enabled and player is in a vehicle or
    -- override bar, unload. Default is true; nil treated as true (same as petBattle).
    if lc.vehicleUI ~= false and self._inVehicleUI then return false end

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
    -- Per-button talent condition: gate visibility on a specific talent node.
    if not self:IsTalentConditionMet(buttonData) then return false end

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

    -- Assisted highlight target gate:
    -- hard target has priority; if none exists, allow soft enemy fallback.
    local hasHostileTarget = false
    if UnitExists("target") then
        hasHostileTarget = UnitCanAttack("player", "target") and true or false
    elseif UnitExists("softenemy") then
        hasHostileTarget = UnitCanAttack("player", "softenemy") and true or false
    end
    self._assistedHighlightHasHostileTarget = hasHostileTarget

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

------------------------------------------------------------------------
-- TALENT NODE CACHE (for per-button talent conditions)
------------------------------------------------------------------------

-- Rebuild the runtime talent node cache from the active talent config.
-- Called on TRAIT_CONFIG_UPDATED, PLAYER_ENTERING_WORLD, spec changes.
function CooldownCompanion:RebuildTalentNodeCache()
    if not self._talentNodeCache then
        self._talentNodeCache = {}
    else
        wipe(self._talentNodeCache)
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local specID = self._currentSpecId
    if not specID then return end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return end
    local activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        local includeNode = nodeInfo
            and nodeInfo.isVisible
            and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection
            and (
                not nodeInfo.subTreeID
                or (
                    activeHeroSubTreeID
                    and nodeInfo.subTreeID == activeHeroSubTreeID
                    and nodeInfo.type == Enum.TraitNodeType.Selection
                )
            )
        if includeNode then
            self._talentNodeCache[nodeID] = {
                activeRank = nodeInfo.activeRank or 0,
                activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
            }
        end
    end
end

-- Check whether per-button talent conditions are satisfied.
-- Returns true if no conditions set. All conditions use AND logic.
-- Missing nodes are treated as not taken.
function CooldownCompanion:IsTalentConditionMet(buttonData)
    local conditions = buttonData.talentConditions
    if not conditions or #conditions == 0 then return true end

    local needsNormalization = #conditions > 1 or IsLegacyChoiceRowCondition(conditions[1])
    if needsNormalization then
        local normalized, changed = self:NormalizeTalentConditions(conditions)
        if changed then
            buttonData.talentConditions = normalized
            conditions = normalized
            if not conditions or #conditions == 0 then return true end
        end
    end

    local cache = self._talentNodeCache
    if not cache then
        self:RebuildTalentNodeCache()
        cache = self._talentNodeCache
    end

    for _, cond in ipairs(conditions) do
        if cond.specID and cond.specID ~= self._currentSpecId then
            return false
        end

        if cond.heroSubTreeID then
            local activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()
            if cond.heroSubTreeID ~= activeHeroSubTreeID then
                return false
            end
        end

        local entry = cache and cache[cond.nodeID] or nil
        local isTaken = entry and entry.activeRank > 0 or false

        -- For choice nodes: if a specific entryID is required, verify it matches
        if isTaken and cond.entryID then
            isTaken = (entry.activeEntryID == cond.entryID)
        end

        local show = cond.show or "taken"
        if show == "not_taken" then
            if isTaken then return false end
        else
            if not isTaken then return false end
        end
    end

    return true
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
