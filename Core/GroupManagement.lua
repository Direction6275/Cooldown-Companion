--[[
    CooldownCompanion - Core/GroupManagement.lua: Group/folder CRUD, AddButtonToGroup,
    RemoveButtonFromGroup, spell search (FindTalentSpellByName)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local table_sort = table.sort
local table_remove = table.remove

local GROUP_SETTING_PRESET_MODES = {
    icons = true,
    bars = true,
}

local function IsValidGroupSettingPresetMode(mode)
    return GROUP_SETTING_PRESET_MODES[mode] == true
end

local function CopyPresetValue(v)
    if type(v) == "table" then
        return CopyTable(v)
    end
    return v
end

local function GetGroupDisplayMode(group)
    if group and group.displayMode == "bars" then
        return "bars"
    end
    return "icons"
end

local function BuildGroupSettingPresetBaseline(profile, mode)
    local style = CopyTable(profile.globalStyle or {})
    if mode == "bars" then
        style.orientation = "vertical"
    else
        style.orientation = "horizontal"
    end
    style.buttonsPerRow = 12
    style.showCooldownText = true

    local groupData = {}

    if mode == "icons" then
        groupData.masqueEnabled = false
    end

    return {
        style = style,
        group = groupData,
    }
end

local function CaptureGroupSettingPresetData(profile, mode, group)
    local baseline = BuildGroupSettingPresetBaseline(profile, mode)
    local data = {
        version = 1,
        style = CopyTable(group.style or baseline.style),
        group = CopyTable(baseline.group),
    }

    if mode == "icons" then
        data.group.masqueEnabled = group.masqueEnabled and true or false
    end

    return data
end

local function ApplyGroupSettingPresetData(profile, group, mode, presetData)
    local baseline = BuildGroupSettingPresetBaseline(profile, mode)
    local groupData = presetData and presetData.group
    local styleData = presetData and presetData.style

    if mode == "icons" then
        group.masqueEnabled = nil
    end

    group.style = CopyTable(baseline.style)
    for key, value in pairs(baseline.group) do
        group[key] = CopyPresetValue(value)
    end

    if type(groupData) == "table" then
        if mode == "icons" and groupData.masqueEnabled ~= nil then
            group.masqueEnabled = groupData.masqueEnabled and true or false
        end
    end

    if type(styleData) == "table" then
        for key, value in pairs(styleData) do
            group.style[key] = CopyPresetValue(value)
        end
    end
end

-- Group Management Functions
function CooldownCompanion:NormalizeGroupSettingPresetsStore()
    local profile = self.db and self.db.profile
    if not profile then return nil end

    if type(profile.groupSettingPresets) ~= "table" then
        profile.groupSettingPresets = {}
    end

    local store = profile.groupSettingPresets
    if type(store.icons) ~= "table" then
        store.icons = {}
    end
    if type(store.bars) ~= "table" then
        store.bars = {}
    end

    return store
end

function CooldownCompanion:GetGroupSettingPresetList(mode)
    if not IsValidGroupSettingPresetMode(mode) then
        return {}, {}
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return {}, {}
    end

    local list = {}
    local order = {}
    for presetName, presetData in pairs(store[mode]) do
        if type(presetName) == "string" and presetName ~= "" and type(presetData) == "table" then
            list[presetName] = presetName
            order[#order + 1] = presetName
        end
    end
    table_sort(order)

    return list, order
end

function CooldownCompanion:SaveGroupSettingPreset(mode, presetName, groupId, opts)
    opts = opts or {}
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not group then
        return false, "missing_group"
    end
    if GetGroupDisplayMode(group) ~= mode then
        return false, "mode_mismatch"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return false, "missing_store"
    end

    if not opts.allowOverwrite and store[mode][presetName] ~= nil then
        return false, "already_exists"
    end

    store[mode][presetName] = CaptureGroupSettingPresetData(self.db.profile, mode, group)
    return true
end

function CooldownCompanion:DeleteGroupSettingPreset(mode, presetName)
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return false, "missing_store"
    end
    if store[mode][presetName] == nil then
        return false, "missing_preset"
    end

    store[mode][presetName] = nil
    return true
end

function CooldownCompanion:ApplyGroupSettingPreset(mode, presetName, groupId)
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not group then
        return false, "missing_group"
    end
    if GetGroupDisplayMode(group) ~= mode then
        return false, "mode_mismatch"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    local presetData = store and store[mode] and store[mode][presetName]
    if type(presetData) ~= "table" then
        return false, "missing_preset"
    end

    local oldMasqueEnabled = group.masqueEnabled and true or false
    ApplyGroupSettingPresetData(self.db.profile, group, mode, presetData)
    local newMasqueEnabled = group.masqueEnabled and true or false

    -- Presets can be imported from clients with Masque enabled.
    -- If Masque is unavailable on this client, do not leave groups flagged
    -- as Masque-enabled because that disables icon controls in config.
    if mode == "icons" and not self.Masque and newMasqueEnabled then
        group.masqueEnabled = false
        newMasqueEnabled = false
    end

    -- Keep Masque's internal group/button lifecycle in sync when preset apply
    -- flips skinning state for icon groups.
    if mode == "icons" and self.Masque and oldMasqueEnabled ~= newMasqueEnabled then
        self:ToggleGroupMasque(groupId, newMasqueEnabled)
    end

    self:RefreshGroupFrame(groupId)
    return true
end

function CooldownCompanion:CreateGroup(name)
    local groupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = groupId + 1

    self.db.profile.groups[groupId] = {
        name = name or "New Group",
        anchor = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
        buttons = {},
        style = CopyTable(self.db.profile.globalStyle),
        enabled = true,
        locked = false,
        order = groupId,
        createdBy = self.db.keys.char,
        isGlobal = false,
    }

    self.db.profile.groups[groupId].style.orientation = "horizontal"
    self.db.profile.groups[groupId].style.buttonsPerRow = 12
    self.db.profile.groups[groupId].style.showCooldownText = true

    -- Indicator defaults for new groups (nil-guard respects user-customized globalStyle)
    local style = self.db.profile.groups[groupId].style
    if style.desaturateOnCooldown == nil then style.desaturateOnCooldown = true end
    if style.showOutOfRange == nil then style.showOutOfRange = true end
    if style.showGCDSwipe == nil then style.showGCDSwipe = false end
    if style.showLossOfControl == nil then style.showLossOfControl = false end
    if style.showTooltips == nil then style.showTooltips = false end
    if style.showUnusable == nil then style.showUnusable = true end
    if style.showCooldownSwipe == nil then style.showCooldownSwipe = true end
    -- Bar mode indicator defaults
    if style.barAuraEffect == nil then style.barAuraEffect = "color" end

    -- Alpha fade defaults
    self.db.profile.groups[groupId].baselineAlpha = 1
    self.db.profile.groups[groupId].forceAlphaRegularMounted = false
    self.db.profile.groups[groupId].forceAlphaDragonriding = false
    self.db.profile.groups[groupId].forceHideRegularMounted = false
    self.db.profile.groups[groupId].forceHideDragonriding = false
    self.db.profile.groups[groupId].treatTravelFormAsMounted = false
    self.db.profile.groups[groupId].fadeDelay = 1
    self.db.profile.groups[groupId].fadeInDuration = 0.2
    self.db.profile.groups[groupId].fadeOutDuration = 0.2

    -- Display mode default
    self.db.profile.groups[groupId].displayMode = "icons"

    -- Masque defaults
    self.db.profile.groups[groupId].masqueEnabled = false

    -- Compact layout default (per-button visibility feature)
    self.db.profile.groups[groupId].compactLayout = false

    -- Max visible buttons cap (0 = no cap, use total button count)
    self.db.profile.groups[groupId].maxVisibleButtons = 0

    -- Compact growth direction (start/center/end; default center)
    self.db.profile.groups[groupId].compactGrowthDirection = "center"

    -- Create the frame for this group
    self:CreateGroupFrame(groupId)

    return groupId
end

function CooldownCompanion:DeleteGroup(groupId)
    -- Clean up Masque group before deleting
    self:DeleteMasqueGroup(groupId)

    if self.groupFrames[groupId] then
        self.groupFrames[groupId]:Hide()
        self.groupFrames[groupId] = nil
    end
    if self.alphaState then
        self.alphaState[groupId] = nil
    end
    self.db.profile.groups[groupId] = nil
end

function CooldownCompanion:DuplicateGroup(groupId)
    local sourceGroup = self.db.profile.groups[groupId]
    if not sourceGroup then return nil end

    local newGroupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = newGroupId + 1

    -- Deep copy the entire group
    local newGroup = CopyTable(sourceGroup)

    -- Change the name
    newGroup.name = sourceGroup.name .. " (Copy)"

    -- Assign new order (place after source group)
    newGroup.order = newGroupId

    -- Set ownership to current character
    newGroup.createdBy = self.db.keys.char
    newGroup.isGlobal = false

    -- If source was global but duplicate becomes character-owned, clear folderId
    -- (folder belongs to the global section)
    if sourceGroup.isGlobal and newGroup.folderId then
        newGroup.folderId = nil
    end

    self.db.profile.groups[newGroupId] = newGroup

    -- Create the frame for the new group
    self:CreateGroupFrame(newGroupId)

    return newGroupId
end

function CooldownCompanion:CreateFolder(name, section)
    local db = self.db.profile
    local folderId = db.nextFolderId
    db.nextFolderId = folderId + 1
    db.folders[folderId] = {
        name = name,
        order = folderId,
        section = section or "char",
        createdBy = self.db.keys.char,
    }
    return folderId
end

function CooldownCompanion:DeleteFolder(folderId)
    local db = self.db.profile
    if not db.folders[folderId] then return end
    -- Collect child IDs first (avoid modifying table during pairs iteration)
    local childIds = {}
    for groupId, group in pairs(db.groups) do
        if group.folderId == folderId then
            childIds[#childIds + 1] = groupId
        end
    end
    for _, groupId in ipairs(childIds) do
        self:DeleteGroup(groupId)
    end
    db.folders[folderId] = nil
end

function CooldownCompanion:RenameFolder(folderId, newName)
    local folder = self.db.profile.folders[folderId]
    if folder then
        folder.name = newName
    end
end

function CooldownCompanion:MoveGroupToFolder(groupId, folderId)
    local group = self.db.profile.groups[groupId]
    if not group then return end
    group.folderId = folderId  -- nil = loose (no folder)
    if folderId then
        local folder = self.db.profile.folders and self.db.profile.folders[folderId]
        if folder and folder.specs and next(folder.specs) then
            group.specs = CopyTable(folder.specs)
            if folder.heroTalents and next(folder.heroTalents) then
                group.heroTalents = CopyTable(folder.heroTalents)
            else
                group.heroTalents = nil
            end
        end
    end
    -- Folder moves can change effective spec/hero filters; refresh visibility now.
    self:RefreshGroupFrame(groupId)
end

function CooldownCompanion:ToggleFolderGlobal(folderId)
    local db = self.db.profile
    local folder = db.folders[folderId]
    if not folder then return end
    local newSection = (folder.section == "global") and "char" or "global"
    folder.section = newSection
    if newSection == "char" then
        folder.createdBy = self.db.keys.char
    end
    -- Move all child groups to the new section
    for groupId, group in pairs(db.groups) do
        if group.folderId == folderId then
            if newSection == "global" then
                group.isGlobal = true
            else
                group.isGlobal = false
                group.createdBy = self.db.keys.char
            end
        end
    end
    self:RefreshAllGroups()
end

function CooldownCompanion:AddButtonToGroup(groupId, buttonType, id, name, isPetSpell, isPassive, forceAura, cdmChildSlot)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    local buttonIndex = #group.buttons + 1
    group.buttons[buttonIndex] = {
        type = buttonType,
        id = id,
        name = name,
        isPetSpell = isPetSpell or nil,
        isPassive = isPassive or nil,
        cdmChildSlot = cdmChildSlot or nil,
    }

    -- Auto-detect charges for spells (skip for passives — no cooldown).
    -- Treat as charge-based only when max charges is greater than 1.
    if buttonType == "spell" and not isPassive then
        local chargeInfo = C_Spell.GetSpellCharges(id)
        if chargeInfo then
            local mc = chargeInfo.maxCharges
            if mc and not issecretvalue(mc) and mc > 1 then
                group.buttons[buttonIndex].hasCharges = true
                group.buttons[buttonIndex].showChargeText = true
                group.buttons[buttonIndex].maxCharges = mc

                -- Secondary: display count
                local rawDisplayCount = C_Spell.GetSpellDisplayCount(id)
                if not issecretvalue(rawDisplayCount) then
                    local displayCount = tonumber(rawDisplayCount)
                    if displayCount and displayCount > (group.buttons[buttonIndex].maxCharges or 0) then
                        group.buttons[buttonIndex].maxCharges = displayCount
                    end
                end
            elseif mc == nil or issecretvalue(mc) then
                -- If maxCharges is unreadable in this context, keep a provisional
                -- charge classification until RefreshChargeFlags can resolve it.
                group.buttons[buttonIndex].hasCharges = true
                group.buttons[buttonIndex].showChargeText = true
            end
        end
    end

    -- Auto-detect charges for items (e.g. Hellstone: GetItemCount with includeUses > plain count)
    if buttonType == "item" then
        local plainCount = C_Item.GetItemCount(id)
        local chargeCount = C_Item.GetItemCount(id, false, true)
        if chargeCount > plainCount then
            group.buttons[buttonIndex].hasCharges = true
            group.buttons[buttonIndex].showChargeText = true
            group.buttons[buttonIndex].maxCharges = chargeCount
        end
    end

    -- Aura tracking: forceAura overrides auto-detection for dual-CDM spells
    if forceAura == true then
        group.buttons[buttonIndex].auraTracking = true
        group.buttons[buttonIndex].auraIndicatorEnabled = true
    elseif forceAura == nil then
        -- Force aura tracking for passive/proc spells
        if isPassive then
            group.buttons[buttonIndex].auraTracking = true
            group.buttons[buttonIndex].auraIndicatorEnabled = true
        end

        -- Auto-detect aura tracking for spells with viewer aura frames
        if buttonType == "spell" then
            local newButton = group.buttons[buttonIndex]
            local viewerFrame
            local resolvedAuraId = C_UnitAuras.GetCooldownAuraBySpellID(id)
            viewerFrame = (resolvedAuraId and resolvedAuraId ~= 0
                    and self.viewerAuraFrames[resolvedAuraId])
                or self.viewerAuraFrames[id]
            if not viewerFrame then
                local child = self:FindViewerChildForSpell(id)
                if child then
                    self.viewerAuraFrames[id] = child
                    viewerFrame = child
                end
            end
            if not viewerFrame then
                local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[id]
                if overrideBuffs then
                    for buffId in overrideBuffs:gmatch("%d+") do
                        viewerFrame = self.viewerAuraFrames[tonumber(buffId)]
                        if viewerFrame then break end
                    end
                end
            end
            local hasViewerFrame = false
            if viewerFrame and GetCVarBool("cooldownViewerEnabled") then
                local parent = viewerFrame:GetParent()
                local parentName = parent and parent:GetName()
                hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
            end
            if hasViewerFrame then
                newButton.auraTracking = true
                newButton.auraIndicatorEnabled = true
                local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[id]
                if overrideBuffs then
                    newButton.auraSpellID = overrideBuffs
                end
                if C_Spell.IsSpellHarmful(id) then
                    newButton.auraUnit = "target"
                end
            end
        end
    end
    -- forceAura == false: skip all aura auto-detection (track as cooldown)
    if forceAura == false then
        group.buttons[buttonIndex].auraTracking = false
    end

    -- Record original classification (immutable label for config display).
    -- This represents add intent, not current auraTracking state.
    if buttonType == "spell" then
        if forceAura == true or isPassive then
            group.buttons[buttonIndex].addedAs = "aura"
        else
            group.buttons[buttonIndex].addedAs = "spell"
        end
    end

    self:RefreshGroupFrame(groupId)
    return buttonIndex
end

function CooldownCompanion:RemoveButtonFromGroup(groupId, buttonIndex)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    table_remove(group.buttons, buttonIndex)
    self:RefreshGroupFrame(groupId)
end

-- Walk the class talent tree using the active config, calling visitor(defInfo)
-- for each definition. The tree is shared across all specs, so the active config
-- can query nodes for every specialization.
-- If visitor returns a truthy value, stop and return that value.
local function WalkTalentTree(visitor)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end
    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return nil end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.entryIDs then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo then
                                local result = visitor(defInfo)
                                if result then return result end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Search spec display spells (key abilities shown on the spec selection screen)
-- across all specs for the player's class.
local function FindDisplaySpell(matcher)
    local _, _, classID = UnitClass("player")
    if not classID then return nil end
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    for specIndex = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, specIndex)
        if specID then
            local ids = C_SpecializationInfo.GetSpellsDisplay(specID)
            if ids then
                for _, spellID in ipairs(ids) do
                    local result = matcher(spellID)
                    if result then return result end
                end
            end
        end
    end
    return nil
end

-- Search the off-spec spellbook for a spell by name or ID.
-- Returns spellID, name if found; nil otherwise.
local function FindOffSpecSpell(spellIdentifier)
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spellIdentifier, false, true, false, true)
    if not slot then return nil end
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if info and info.spellID then
        return info.spellID, info.name
    end
    return nil
end

function CooldownCompanion:FindTalentSpellByName(name)
    local lowerName = name:lower()

    -- 1) Search talent tree (covers all talent choices across specs)
    local result = WalkTalentTree(function(defInfo)
        if defInfo.spellID then
            local spellInfo = C_Spell.GetSpellInfo(defInfo.spellID)
            if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
                return { defInfo.spellID, spellInfo.name }
            end
        end
    end)
    if result then return result[1], result[2] end

    -- 2) Search spec display spells (key baseline abilities per spec)
    result = FindDisplaySpell(function(spellID)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
            return { spellID, spellInfo.name }
        end
    end)
    if result then return result[1], result[2] end

    -- 3) Search off-spec spellbook (covers previously activated specs)
    local spellID, spellName = FindOffSpecSpell(name)
    if spellID and spellName then return spellID, spellName end

    return nil
end
