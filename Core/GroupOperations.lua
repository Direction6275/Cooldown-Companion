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

    -- For panels, delegate visibility to the parent container
    if group.parentContainerId then
        return self:IsContainerVisibleToCurrentChar(group.parentContainerId)
    end

    -- Legacy path (no container)
    if group.isGlobal then return true end
    return group.createdBy == self.db.keys.char
end

-- Resolve the container for a panel group, or nil if the group has no container.
function CooldownCompanion:GetParentContainer(groupOrGroupId)
    local group = groupOrGroupId
    if type(groupOrGroupId) == "number" then
        group = self.db.profile.groups[groupOrGroupId]
    end
    if not group or not group.parentContainerId then return nil end
    local containers = self.db.profile.groupContainers
    return containers and containers[group.parentContainerId]
end

function CooldownCompanion:GetEffectiveSpecs(group)
    if not group then return nil, false end

    -- Panel: container specs (includes stamped folder specs) → panel's own
    local container = self:GetParentContainer(group)
    if container then
        if container.specs and next(container.specs) then
            return container.specs, true
        end
        -- Fall through to panel's own
        return group.specs, false
    end

    -- Non-panel group: check folder cascade
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

    -- Panel cascade: folder → container → panel's own heroTalents
    local container = self:GetParentContainer(group)
    if container then
        -- Check folder first
        local folderId = container.folderId
        if folderId then
            local folders = self.db and self.db.profile and self.db.profile.folders
            local folder = folders and folders[folderId]
            if folder and folder.heroTalents and next(folder.heroTalents) then
                return folder.heroTalents, true
            end
        end
        -- Then container's own heroTalents
        if container.heroTalents and next(container.heroTalents) then
            return container.heroTalents, true
        end
        -- Fall through to panel's own
        return group.heroTalents, false
    end

    -- Non-panel container: check folder cascade
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
        classID = cond.classID,
        className = cond.className,
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
            if not cond.specID and not cond.classID and not cond.className then
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
                .. "|" .. tostring(cond.classID or 0)
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
                if cond.classID or cond.className or cond.specID == chosenSpecID then
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

-- Folder spec filters are stamped onto child containers so that runtime checks
-- (which read container.specs) pick up folder-level restrictions. Stamping occurs
-- both here (when folder specs change) and in MoveGroupToFolder (when a container
-- joins a folder). Hero talents are NOT stamped — they cascade at read time via
-- GetEffectiveHeroTalents.
function CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
    local db = self.db and self.db.profile
    local folder = db and db.folders and db.folders[folderId]
    if not (db and folder) then return end

    local folderSpecs = folder.specs
    local hasFolderSpecs = folderSpecs and next(folderSpecs)

    -- Post-migration: folderId lives on containers, not groups
    local containers = db.groupContainers or {}
    for _, container in pairs(containers) do
        if container.folderId == folderId then
            if hasFolderSpecs then
                container.specs = CopyTable(folderSpecs)
            else
                container.specs = nil
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

    -- If this panel has a parent container, check container-level state first
    local container = self:GetParentContainer(group)
    if container then
        if container.enabled == false then return false end
        if group.enabled == false then return false end

        -- Container-level load conditions
        if opts.checkLoadConditions ~= false and not self:CheckLoadConditions(container) then
            return false
        end
    else
        -- Legacy path: enabled lives on the group
        if group.enabled == false then return false end
    end

    if opts.requireButtons and (not group.buttons or #group.buttons == 0) then
        return false
    end

    -- Spec and hero talent filtering (GetEffectiveSpecs already delegates to container)
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

    -- Group-level load conditions (for panels, adds to container restrictions)
    if opts.checkLoadConditions ~= false and not self:CheckLoadConditions(group) then
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
    if not group.parentContainerId then return false end
    if group.displayMode ~= "icons" then return false end
    local container = self:GetParentContainer(group)
    if container and container.isGlobal then return false end
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
    local db = self.db.profile
    local groups = db.groups
    if not groups then return nil end
    local containers = db.groupContainers
    if not containers then return nil end
    local folders = db.folders or {}

    -- Build container-to-folder mapping
    local folderContainers = {}  -- [folderId] = { {id, order}, ... }
    local looseContainers = {}   -- { {id, order}, ... }

    for cid, container in pairs(containers) do
        local fid = container.folderId
        if fid and folders[fid] then
            if not folderContainers[fid] then
                folderContainers[fid] = {}
            end
            folderContainers[fid][#folderContainers[fid] + 1] = { id = cid, order = container.order or cid }
        else
            looseContainers[#looseContainers + 1] = { id = cid, order = container.order or cid }
        end
    end

    -- Sort containers within each folder by container.order
    for _, children in pairs(folderContainers) do
        table.sort(children, function(a, b) return a.order < b.order end)
    end
    table.sort(looseContainers, function(a, b) return a.order < b.order end)

    -- Build top-level items: folders + loose containers, sorted by order
    -- (mirrors Column1.lua BuildSectionItems)
    local topItems = {}
    for fid in pairs(folderContainers) do
        topItems[#topItems + 1] = { kind = "folder", id = fid, order = folders[fid].order or fid }
    end
    for _, lc in ipairs(looseContainers) do
        topItems[#topItems + 1] = { kind = "container", id = lc.id, order = lc.order }
    end
    table.sort(topItems, function(a, b) return a.order < b.order end)

    -- Iterate in visual order, return first available panel
    for _, item in ipairs(topItems) do
        local containerList
        if item.kind == "folder" then
            containerList = folderContainers[item.id]
        else
            containerList = { item }
        end
        for _, cInfo in ipairs(containerList) do
            local panels = self:GetPanels(cInfo.id)
            for _, panelInfo in ipairs(panels) do
                if self:IsGroupAvailableForAnchoring(panelInfo.groupId) then
                    return panelInfo.groupId
                end
            end
        end
    end
    return nil
end

function CooldownCompanion:PopulateAnchorDropdown(dropdown)
    local db = self.db.profile
    local containers = db.groupContainers or {}
    local folders = db.folders or {}
    local folderPanels = {}
    local loosePanels = {}
    local eligibleCount = 0

    for groupId, group in pairs(db.groups) do
        if self:IsGroupAvailableForAnchoring(groupId) then
            eligibleCount = eligibleCount + 1
            local cid = group.parentContainerId
            local ctr = cid and containers[cid]
            local fid = ctr and ctr.folderId
            local contName = ctr and ctr.name or "Group"
            local panelName = group.name or ("Panel " .. groupId)
            local entry = { id = groupId, name = panelName, contName = contName }
            if fid and folders[fid] then
                folderPanels[fid] = folderPanels[fid] or {}
                table.insert(folderPanels[fid], entry)
            else
                table.insert(loosePanels, entry)
            end
        end
    end

    dropdown:SetList({ [""] = "Auto (first available)" }, { "" })

    local sortedFolders = {}
    for fid, folder in pairs(folders) do
        if folderPanels[fid] then
            table.insert(sortedFolders, { id = fid, name = folder.name or ("Folder " .. fid), order = folder.order or fid })
        end
    end
    table.sort(sortedFolders, function(a, b) return a.order < b.order end)

    local hasHeaders = #sortedFolders > 0

    for _, folder in ipairs(sortedFolders) do
        local hdrKey = "_hdr_" .. folder.id
        dropdown:AddItem(hdrKey, "|cffffd100" .. folder.name .. "|r")
        dropdown:SetItemDisabled(hdrKey, true)

        table.sort(folderPanels[folder.id], function(a, b)
            if a.contName ~= b.contName then return a.contName < b.contName end
            return a.name < b.name
        end)
        for _, panel in ipairs(folderPanels[folder.id]) do
            local key = tostring(panel.id)
            dropdown:AddItem(key, "   " .. panel.name)
            dropdown.list[key] = panel.contName .. " > " .. panel.name
        end
    end

    if #loosePanels > 0 then
        if hasHeaders then
            dropdown:AddItem("_hdr_none", "|cffffd100No Folder|r")
            dropdown:SetItemDisabled("_hdr_none", true)
        end
        table.sort(loosePanels, function(a, b)
            if a.contName ~= b.contName then return a.contName < b.contName end
            return a.name < b.name
        end)
        for _, panel in ipairs(loosePanels) do
            local key = tostring(panel.id)
            local prefix = hasHeaders and "   " or ""
            dropdown:AddItem(key, prefix .. panel.name)
            dropdown.list[key] = panel.contName .. " > " .. panel.name
        end
    end

    return eligibleCount
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


-- ToggleGroupGlobal is defined in GroupManagement.lua (container-aware version)

function CooldownCompanion:GroupHasPetSpells(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.isPetSpell then return true end
    end
    return false
end

local function SpellIDsMatchCanonicalForm(storedSpellID, resolvedSpellID)
    if not storedSpellID or not resolvedSpellID then
        return false
    end
    if storedSpellID == resolvedSpellID then
        return true
    end

    local storedBaseSpellID = C_Spell.GetBaseSpell(storedSpellID)
    local resolvedBaseSpellID = C_Spell.GetBaseSpell(resolvedSpellID)

    return storedBaseSpellID ~= nil
        and resolvedBaseSpellID ~= nil
        and storedBaseSpellID == resolvedBaseSpellID
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
                and SpellIDsMatchCanonicalForm(buttonData.id, spellID)
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
    -- Re-anchor pass: custom anchors to other group frames may have fallen
    -- back to the container because the target wasn't created yet.
    -- All frames now exist, so re-apply to resolve cross-group anchors.
    for groupId, frame in pairs(self.groupFrames) do
        local group = self.db.profile.groups[groupId]
        if group and group.anchor then
            local relativeTo = group.anchor.relativeTo
            if relativeTo and relativeTo ~= "UIParent" then
                local containerName = group.parentContainerId
                    and ("CooldownCompanionContainer" .. group.parentContainerId)
                if not containerName or relativeTo ~= containerName then
                    self:AnchorGroupFrame(frame, group.anchor)
                end
            end
        end
    end
end

function CooldownCompanion:RefreshAllGroups()
    -- Clean up stale container frames (e.g. after profile switch)
    if self.containerFrames then
        local containers = self.db.profile.groupContainers or {}
        for containerId, frame in pairs(self.containerFrames) do
            if not containers[containerId] then
                frame:Hide()
                self.containerFrames[containerId] = nil
            end
        end
        -- Ensure all current-profile containers have frames
        for containerId, _ in pairs(containers) do
            if self:IsContainerVisibleToCurrentChar(containerId) then
                if not self.containerFrames[containerId] then
                    self:CreateContainerFrame(containerId)
                end
            else
                if self.containerFrames[containerId] then
                    self.containerFrames[containerId]:Hide()
                end
            end
        end
    end

    -- Fully unload frames for groups not in the current profile
    -- (e.g. after a profile switch).
    for groupId, frame in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
        end
    end

    -- Refresh current profile's groups: load active ones, unload inactive ones
    for groupId, group in pairs(self.db.profile.groups) do
        if not self:IsGroupVisibleToCurrentChar(groupId) then
            self:UnloadGroup(groupId)
        elseif self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = false,
            checkLoadConditions = true,
            requireButtons = false,
        }) then
            self:RefreshGroupFrame(groupId)
        else
            self:UnloadGroup(groupId)
        end
    end
end

-- Refresh only frame-level visibility/load-state without rebuilding buttons.
-- Used by zone/resting/pet-battle transitions to avoid compact-layout flash
-- caused by full button repopulation.
function CooldownCompanion:RefreshAllGroupsVisibilityOnly()
    -- Fully unload frames for groups not in the current profile
    for groupId, frame in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
        end
    end

    for groupId, group in pairs(self.db.profile.groups) do
        if not self:IsGroupVisibleToCurrentChar(groupId) then
            self:UnloadGroup(groupId)
        else
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            })

            if not active then
                self:UnloadGroup(groupId)
            else
                local frame = self.groupFrames[groupId]
                if not frame then
                    frame = self:CreateGroupFrame(groupId)
                end

                if frame then
                    local wasShown = frame:IsShown()
                    frame:Show()
                    -- Resolve locked from container (panels defer to container lock)
                    local container = self:GetParentContainer(group)
                    local isLocked
                    if container then
                        isLocked = container.locked ~= false
                    else
                        isLocked = group.locked
                    end
                    -- Force 100% alpha while unlocked for easier positioning
                    if not isLocked then
                        frame:SetAlpha(1)
                    -- Apply current alpha from the alpha fade system so frame
                    -- doesn't flash at 1.0 when baseline alpha is configured.
                    else
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
                end
            end
        end
    end
end

-- Fully unload a group: strip buttons, delete Masque, clear runtime state,
-- remove from groupFrames. Config data (db.profile.groups) is preserved
-- so the group can reload when load conditions change.
function CooldownCompanion:UnloadGroup(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end

    -- Strip buttons: remove from Masque, stop OnUpdate, hide, detach
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            self:RemoveButtonFromMasque(groupId, button)
            button:SetScript("OnUpdate", nil)
            button:Hide()
            button:SetParent(nil)
        end
        wipe(frame.buttons)
    end

    -- Delete Masque group
    self:DeleteMasqueGroup(groupId)

    -- Clear alpha fade state
    if self.alphaState then
        self.alphaState[groupId] = nil
    end

    -- Stop alphaSyncFrame OnUpdate
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end

    -- Hide and remove from active tracking
    frame:Hide()
    self.groupFrames[groupId] = nil
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

-- Refresh all panel frames belonging to a container.
function CooldownCompanion:RefreshContainerPanels(containerId)
    for gid, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            self:RefreshGroupFrame(gid)
        end
    end
end

-- Show or hide the drag handle on a container frame to match its lock state.
function CooldownCompanion:UpdateContainerDragHandle(containerId, locked)
    local cFrame = self.containerFrames and self.containerFrames[containerId]
    if cFrame and cFrame.dragHandle then
        cFrame.dragHandle:SetShown(not locked)
    end
end

function CooldownCompanion:LockAllFrames()
    -- Also lock any individually-unlocked panels
    for groupId, group in pairs(self.db.profile.groups) do
        if group.locked == false then
            group.locked = nil
        end
    end
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
    -- Lock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            self:UpdateContainerDragHandle(containerId, true)
        end
    end
end

function CooldownCompanion:UnlockAllFrames()
    -- Unlock containers only; individual panels retain their own lock state
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            local group = self.db.profile.groups[groupId]
            local panelUnlocked = group and group.locked == false
            if frame.dragHandle then
                if panelUnlocked then
                    frame.dragHandle:Show()
                end
            end
            if panelUnlocked then
                frame:SetAlpha(1)
            end
        end
    end
    -- Unlock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            local container = self.db.profile.groupContainers[containerId]
            self:UpdateContainerDragHandle(containerId, not container or container.locked)
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
        if cond.classID and self._playerClassID and cond.classID ~= self._playerClassID then
            return false
        end

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
