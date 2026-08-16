--[[
    CooldownCompanion - Core/Migrations.lua: migration orchestrator and cutoff helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local type = type
local next = next
local rawget = rawget
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local table_sort = table.sort
local string_upper = string.upper

local IMPORT_CHECKPOINT_KEY = "_cdcImportCheckpoint"
local IMPORT_CHECKPOINT_VERSION = "1.15"
local LEGACY_SUPPORT_FLOOR_VERSION = IMPORT_CHECKPOINT_VERSION
local LEGACY_UNSUPPORTED_MAX_VERSION = "1.14"

local FOLDER_LOAD_CONDITION_KEYS = {
    "raid",
    "dungeon",
    "delve",
    "battleground",
    "arena",
    "openWorld",
    "rested",
    "petBattle",
    "vehicleUI",
}

local function NormalizeNumericRestrictionKey(key)
    return tonumber(key)
end

local function NormalizeClassRestrictionKey(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return string_upper(key)
end

local function NormalizeCharacterRestrictionKey(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

local function ReadRestrictionMap(map, normalizer)
    if map == nil then
        return nil, false
    end
    if type(map) ~= "table" then
        return {}, true
    end

    local values = {}
    local sawEntry = false
    for key, enabled in pairs(map) do
        sawEntry = true
        if enabled == true then
            local normalizedKey = normalizer(key)
            if normalizedKey ~= nil then
                values[normalizedKey] = true
            end
        end
    end

    if next(values) then
        return values, true
    end
    if sawEntry then
        return {}, true
    end
    return nil, false
end

local function CopyRestrictionValues(values)
    local copy = {}
    for key in pairs(values or {}) do
        copy[key] = true
    end
    return copy
end

local function IntersectRestrictionValues(left, right)
    local intersection = {}
    for key in pairs(left or {}) do
        if right and right[key] then
            intersection[key] = true
        end
    end
    return intersection
end

local function EncodeRestrictionMap(values)
    if next(values or {}) then
        return CopyRestrictionValues(values)
    end

    -- Restriction readers distinguish a truly empty table (no restriction)
    -- from a non-empty map with no enabled keys (an explicit empty set).
    return { [0] = false }
end

local function GetEntitySpecRestriction(entity)
    if type(entity) ~= "table" then
        return nil, false
    end

    local loadConditions = entity.loadConditions
    local loadSpecMap = type(loadConditions) == "table" and loadConditions.specAllowlist or nil
    local loadSpecs, hasLoadSpecs = ReadRestrictionMap(loadSpecMap, NormalizeNumericRestrictionKey)
    if hasLoadSpecs then
        -- A load-condition spec allowlist is both part of the entity's effective
        -- spec source and a second required gate, so it dominates entity.specs.
        return loadSpecs, true
    end
    return ReadRestrictionMap(entity.specs, NormalizeNumericRestrictionKey)
end

-- Class-scope landing needs an entity's spec gating expressed where class
-- scope reads it (entity.specs). The allowlist is a SECOND gate that
-- dominates entity.specs at runtime, so the canonical single-map form is
-- that dominant restriction — never the union of the two, which would drop
-- the gate and widen eligibility. An allowlist with nothing enabled means
-- "never eligible" and stays never through EncodeRestrictionMap's sentinel.
function CooldownCompanion:CanonicalizeEntitySpecRestriction(entity)
    if type(entity) ~= "table" then
        return
    end
    local specs, hasSpecs = GetEntitySpecRestriction(entity)
    local loadConditions = entity.loadConditions
    if type(loadConditions) == "table" and loadConditions.specAllowlist ~= nil then
        if hasSpecs then
            entity.specs = EncodeRestrictionMap(specs)
        end
        loadConditions.specAllowlist = nil
    end
end

-- Read-only companion: the effective spec gate without mutating anything.
function CooldownCompanion:GetEntitySpecRestriction(entity)
    return GetEntitySpecRestriction(entity)
end

local function EnsureLoadConditions(entity)
    if type(entity.loadConditions) == "table" then
        return entity.loadConditions
    end

    -- Creating a Group-level source would otherwise acquire the Group defaults
    -- that hide in pet battles and vehicles. Folder sources default both off.
    entity.loadConditions = {
        petBattle = false,
        vehicleUI = false,
    }
    return entity.loadConditions
end

local function MergeFolderInheritanceIntoEntity(entity, folder)
    if type(entity) ~= "table" or type(folder) ~= "table" then
        return
    end

    local folderSpecs, hasFolderSpecs = GetEntitySpecRestriction(folder)
    if hasFolderSpecs then
        local entitySpecs, hasEntitySpecs = GetEntitySpecRestriction(entity)
        local mergedSpecs = hasEntitySpecs
            and IntersectRestrictionValues(folderSpecs, entitySpecs)
            or folderSpecs
        entity.specs = EncodeRestrictionMap(mergedSpecs)
        if type(entity.loadConditions) == "table" then
            entity.loadConditions.specAllowlist = nil
        end
    end

    local folderHeroTalents, hasFolderHeroTalents = ReadRestrictionMap(
        folder.heroTalents,
        NormalizeNumericRestrictionKey
    )
    if hasFolderHeroTalents then
        local entityHeroTalents, hasEntityHeroTalents = ReadRestrictionMap(
            entity.heroTalents,
            NormalizeNumericRestrictionKey
        )
        local mergedHeroTalents = hasEntityHeroTalents
            and IntersectRestrictionValues(folderHeroTalents, entityHeroTalents)
            or folderHeroTalents
        entity.heroTalents = EncodeRestrictionMap(mergedHeroTalents)
    end

    local folderLoadConditions = folder.loadConditions
    if type(folderLoadConditions) ~= "table" then
        return
    end

    for _, key in ipairs(FOLDER_LOAD_CONDITION_KEYS) do
        if folderLoadConditions[key] == true then
            EnsureLoadConditions(entity)[key] = true
        end
    end

    local folderIsGlobal = folder.section == "global"
    local entityIsGlobal = entity.isGlobal == true
    if folderIsGlobal then
        local folderClasses, hasFolderClasses = ReadRestrictionMap(
            folderLoadConditions.classAllowlist,
            NormalizeClassRestrictionKey
        )
        if hasFolderClasses and entityIsGlobal then
            local entityLoadConditions = EnsureLoadConditions(entity)
            local mergedClasses = folderClasses
            local entityClasses, hasEntityClasses = ReadRestrictionMap(
                entityLoadConditions.classAllowlist,
                NormalizeClassRestrictionKey
            )
            if hasEntityClasses then
                mergedClasses = IntersectRestrictionValues(folderClasses, entityClasses)
            end
            entityLoadConditions.classAllowlist = EncodeRestrictionMap(mergedClasses)
        end
    end

    local folderCharacters, hasFolderCharacters = ReadRestrictionMap(
        folderLoadConditions.characterAllowlist,
        NormalizeCharacterRestrictionKey
    )
    if hasFolderCharacters then
        local entityLoadConditions = EnsureLoadConditions(entity)
        local mergedCharacters = folderCharacters
        local entityCharacters, hasEntityCharacters = ReadRestrictionMap(
            entityLoadConditions.characterAllowlist,
            NormalizeCharacterRestrictionKey
        )
        if hasEntityCharacters then
            mergedCharacters = IntersectRestrictionValues(folderCharacters, entityCharacters)
        end
        entityLoadConditions.characterAllowlist = EncodeRestrictionMap(mergedCharacters)
    end
end

local function GetEntityScopeKey(addon, entity, isFolder, sourceCharacterInfo)
    if type(entity) ~= "table" then
        return "invalid"
    end
    if (isFolder and entity.section == "global") or (not isFolder and entity.isGlobal == true) then
        return "global"
    end

    local owner = entity.createdBy
    local sourceOwnerInfo = type(sourceCharacterInfo) == "table" and sourceCharacterInfo[owner] or nil
    local characterInfo = addon
        and addon.db
        and addon.db.global
        and addon.db.global.characterInfo
    local liveOwnerInfo = type(characterInfo) == "table" and characterInfo[owner] or nil
    local classFilename = type(sourceOwnerInfo) == "table" and sourceOwnerInfo.classFilename or nil
    if type(classFilename) ~= "string" or classFilename == "" then
        classFilename = type(liveOwnerInfo) == "table" and liveOwnerInfo.classFilename or nil
    end
    if type(classFilename) == "string" and classFilename ~= "" then
        return "class:" .. string_upper(classFilename)
    end
    if type(owner) == "string" and owner ~= "" then
        return "character:" .. owner
    end
    return "invalid"
end

local function GetOrderValue(entity, specId, fallback)
    local specOrders = type(entity) == "table" and entity.specOrders or nil
    if specId and type(specOrders) == "table" then
        local value = specOrders[specId]
        if value == nil then
            value = specOrders[tostring(specId)]
        end
        value = tonumber(value)
        if value then
            return value
        end
    end
    return tonumber(type(entity) == "table" and entity.order) or tonumber(fallback) or 0
end

local function CompareOrderedItems(left, right)
    if left.order ~= right.order then
        return left.order < right.order
    end
    if left.kind ~= right.kind then
        return left.kind == "folder"
    end
    return tostring(left.id) < tostring(right.id)
end

local function AssignFlattenedOrders(addon, profile, folders, specId, sourceCharacterInfo)
    local containers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    local folderChildren = {}
    local looseContainers = {}

    for containerId, container in pairs(containers) do
        if type(container) == "table" then
            local folderId = container.folderId
            local folder = folderId and folders[folderId] or nil
            if type(folder) == "table"
                and GetEntityScopeKey(addon, container, false, sourceCharacterInfo)
                    == GetEntityScopeKey(addon, folder, true, sourceCharacterInfo)
            then
                folderChildren[folderId] = folderChildren[folderId] or {}
                folderChildren[folderId][#folderChildren[folderId] + 1] = {
                    id = containerId,
                    entity = container,
                    order = GetOrderValue(container, specId, containerId),
                }
            else
                looseContainers[#looseContainers + 1] = {
                    id = containerId,
                    entity = container,
                    scopeKey = GetEntityScopeKey(addon, container, false, sourceCharacterInfo),
                    order = GetOrderValue(container, specId, containerId),
                }
            end
        end
    end

    local topItemsByScope = {}
    for folderId, children in pairs(folderChildren) do
        local folder = folders[folderId]
        table_sort(children, CompareOrderedItems)
        local scopeKey = GetEntityScopeKey(addon, folder, true, sourceCharacterInfo)
        topItemsByScope[scopeKey] = topItemsByScope[scopeKey] or {}
        topItemsByScope[scopeKey][#topItemsByScope[scopeKey] + 1] = {
            kind = "folder",
            id = folderId,
            order = GetOrderValue(folder, specId, folderId),
            children = children,
        }
    end
    for _, item in ipairs(looseContainers) do
        topItemsByScope[item.scopeKey] = topItemsByScope[item.scopeKey] or {}
        item.kind = "container"
        topItemsByScope[item.scopeKey][#topItemsByScope[item.scopeKey] + 1] = item
    end

    for _, topItems in pairs(topItemsByScope) do
        table_sort(topItems, CompareOrderedItems)
        local nextOrder = 1
        for _, item in ipairs(topItems) do
            local orderedContainers = item.kind == "folder" and item.children or { item }
            for _, containerItem in ipairs(orderedContainers) do
                local container = containerItem.entity
                if specId then
                    container.specOrders = type(container.specOrders) == "table" and container.specOrders or {}
                    container.specOrders[specId] = nextOrder
                else
                    container.order = nextOrder
                end
                nextOrder = nextOrder + 1
            end
        end
    end
end

local function CollectOrderingSpecIds(profile, folders)
    local specIds = {}
    local function AddSpecOrders(entity)
        for specId in pairs(type(entity) == "table" and entity.specOrders or {}) do
            specId = tonumber(specId)
            if specId then
                specIds[specId] = true
            end
        end
    end

    for _, folder in pairs(folders) do
        AddSpecOrders(folder)
    end
    for _, container in pairs(type(profile.groupContainers) == "table" and profile.groupContainers or {}) do
        AddSpecOrders(container)
    end

    local sortedSpecIds = {}
    for specId in pairs(specIds) do
        sortedSpecIds[#sortedSpecIds + 1] = specId
    end
    table_sort(sortedSpecIds)
    return sortedSpecIds
end

-- Void on purpose: the flattened-folder count travels ONLY through the
-- profile stash below. An earlier version also returned it, and the second
-- channel was a trap — the full-profile import door runs this pass itself,
-- so by the time RunAllMigrations called it again the folder state was gone
-- and the returned count was a plausible-looking zero.
local function MigrateFoldersIntoGroups(addon, profile, sourceCharacterInfo)
    if type(profile) ~= "table" then
        return
    end

    local storedFolders = rawget(profile, "folders")
    local folders = type(storedFolders) == "table" and storedFolders or {}
    local containers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    local groups = type(profile.groups) == "table" and profile.groups or {}
    local storedNextFolderId = rawget(profile, "nextFolderId")
    local hasFolderState = storedFolders ~= nil or storedNextFolderId ~= nil

    for _, container in pairs(containers) do
        if type(container) == "table" and container.folderId ~= nil then
            hasFolderState = true
            local folder = folders[container.folderId]
            if type(folder) == "table" then
                MergeFolderInheritanceIntoEntity(container, folder)
            end
        end
    end
    for _, group in pairs(groups) do
        if type(group) == "table" and group.folderId ~= nil then
            hasFolderState = true
            local folder = folders[group.folderId]
            if type(folder) == "table" then
                MergeFolderInheritanceIntoEntity(group, folder)
            end
        end
    end

    if not hasFolderState then
        return
    end

    AssignFlattenedOrders(addon, profile, folders, nil, sourceCharacterInfo)
    for _, specId in ipairs(CollectOrderingSpecIds(profile, folders)) do
        AssignFlattenedOrders(addon, profile, folders, specId, sourceCharacterInfo)
    end

    for _, container in pairs(containers) do
        if type(container) == "table" then
            container.folderId = nil
        end
    end
    for _, group in pairs(groups) do
        if type(group) == "table" then
            group.folderId = nil
        end
    end

    -- Count FOLDERS, which is what the notice says. Counting the entities
    -- that carried a folderId reported one folder holding a group with three
    -- panels as "(x4)".
    local flattenedCount = 0
    for _ in pairs(folders) do
        flattenedCount = flattenedCount + 1
    end

    profile.folders = nil
    profile.nextFolderId = nil
    -- The notice reads and clears this stash, so it reports correctly no
    -- matter which door did the flattening.
    if flattenedCount > 0 then
        profile._cdcFlattenedFolderNotice =
            (tonumber(profile._cdcFlattenedFolderNotice) or 0) + flattenedCount
    end
end

function CooldownCompanion:MigrateFoldersIntoGroups(profile, sourceCharacterInfo)
    MigrateFoldersIntoGroups(self, profile or (self.db and self.db.profile), sourceCharacterInfo)
end

local function CompareVersion(left, right)
    left = tostring(left or "")
    right = tostring(right or "")

    local leftParts = {}
    for part in left:gmatch("%d+") do
        leftParts[#leftParts + 1] = tonumber(part) or 0
    end

    local rightParts = {}
    for part in right:gmatch("%d+") do
        rightParts[#rightParts + 1] = tonumber(part) or 0
    end

    if #leftParts == 0 or #rightParts == 0 then
        return nil
    end

    local maxParts = math.max(#leftParts, #rightParts)
    for index = 1, maxParts do
        local leftPart = leftParts[index] or 0
        local rightPart = rightParts[index] or 0
        if leftPart ~= rightPart then
            return leftPart < rightPart and -1 or 1
        end
    end

    return 0
end

local function LooksLikeProfilePayload(profile)
    if type(profile) ~= "table" or rawget(profile, "type") ~= nil then
        return false
    end

    return rawget(profile, "groups") ~= nil
        or rawget(profile, "groupContainers") ~= nil
        or rawget(profile, "globalStyle") ~= nil
        or rawget(profile, "nextGroupId") ~= nil
        or rawget(profile, "nextContainerId") ~= nil
        or rawget(profile, "nextFolderId") ~= nil
        or rawget(profile, "folders") ~= nil
        or rawget(profile, "bars") ~= nil
        or rawget(profile, "resourceBars") ~= nil
        or rawget(profile, "castBar") ~= nil
        or rawget(profile, "frameAnchoring") ~= nil
end

local function HasTriggerConditionConfig(buttonData)
    return buttonData.triggerCondition ~= nil
        or buttonData.triggerExpected ~= nil
        or buttonData.triggerState ~= nil
        or buttonData.triggerConditions ~= nil
end

local function ClearTriggerConditionConfig(buttonData)
    local changed = false
    if buttonData.triggerCondition ~= nil then
        buttonData.triggerCondition = nil
        changed = true
    end
    if buttonData.triggerExpected ~= nil then
        buttonData.triggerExpected = nil
        changed = true
    end
    if buttonData.triggerState ~= nil then
        buttonData.triggerState = nil
        changed = true
    end
    if buttonData.triggerConditions ~= nil then
        buttonData.triggerConditions = nil
        changed = true
    end
    return changed
end

local function NormalizePromotedPassiveCooldownTriggerConditions(buttonData)
    if not HasTriggerConditionConfig(buttonData) then
        return false
    end
    if not (CooldownCompanion.GetTriggerConditionClauses and CooldownCompanion.NormalizeTriggerConditionRowData) then
        return false
    end

    local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)
    local changed = false
    if #clauses == 0 then
        changed = ClearTriggerConditionConfig(buttonData)
    end

    CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    return changed
end

-- A saved strataOrder from an older layer set no longer matches the current
-- one. ApplyStrataOrder already falls back to the default when the length is
-- wrong, but leaving the stale array in the profile makes the Custom Icon
-- Strata checkbox read as ON while none of its values are in effect. Dropping
-- it turns the checkbox off, so the panel says what it is actually doing.
--
-- Deliberately NOT a value-preserving migration: the owner accepted the reset
-- when the set changed from 6 layers to 8 (the aura display replaced a slot
-- that never rendered, and two new layers joined).
local function ClearInvalidStrataOrders(profile)
    if type(profile) ~= "table" then
        return false
    end
    local changed = false

    local function clear(styleTable)
        if type(styleTable) ~= "table" then return end
        local order = styleTable.strataOrder
        -- An empty table is the config's mid-edit state (some layers still
        -- unassigned) and must survive. Anything else is judged by the
        -- renderer's own test, so this cannot drift from what actually gets
        -- honored: a right-length order carrying a retired key is stale too.
        if type(order) == "table" and #order > 0 and not ST._IsUsableStrataOrder(order) then
            styleTable.strataOrder = nil
            changed = true
        end
    end

    clear(profile.globalStyle)
    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                clear(group.style)
            end
        end
    end
    -- Presets too, like every other normalizer in this file. They are a
    -- persistent store the one-shot profile migrations never reached, which is
    -- exactly why a1871266 had to add an inline expander on the apply path
    -- after the 4->6 change. Cleaning them here is what lets that expander go.
    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        clear(presetData.style)
                    end
                end
            end
        end
    end
    return changed
end

local function NormalizePassiveCooldownButtons(profile)
    if type(profile) ~= "table" or type(profile.groups) ~= "table" then
        return false
    end
    if not ST.IsPassiveCooldownSpell then
        return false
    end

    local changed = false
    for _, group in pairs(profile.groups) do
        if type(group) == "table" and type(group.buttons) == "table" then
            for _, buttonData in ipairs(group.buttons) do
                if type(buttonData) == "table"
                    and buttonData.type == "spell"
                    and (buttonData.isPassive == true or buttonData.isPassiveCooldown == true) then
                    local isPassiveCooldown = buttonData.isPassiveCooldown == true
                        or ST.IsPassiveCooldownSpell(buttonData.id)
                    if isPassiveCooldown then
                        if buttonData.isPassiveCooldown ~= true then
                            buttonData.isPassiveCooldown = true
                            changed = true
                        end
                        if buttonData.isPassive ~= nil then
                            buttonData.isPassive = nil
                            changed = true
                        end
                        if buttonData.auraTracking ~= false then
                            buttonData.auraTracking = false
                            changed = true
                        end
                        if buttonData.addedAs ~= "spell" then
                            buttonData.addedAs = "spell"
                            changed = true
                        end
                        if NormalizePromotedPassiveCooldownTriggerConditions(buttonData) then
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

local function BackfillUnusableVisualOverrideModes(profile)
    if type(profile) ~= "table" or type(profile.groups) ~= "table" then
        return false
    end

    local changed = false
    for _, group in pairs(profile.groups) do
        if type(group) == "table" and type(group.buttons) == "table" then
            for _, buttonData in ipairs(group.buttons) do
                local overrides = type(buttonData) == "table" and buttonData.styleOverrides
                local overrideSections = type(buttonData) == "table" and buttonData.overrideSections
                if type(overrides) == "table"
                    and type(overrideSections) == "table"
                    and overrideSections.unusableDimming == true
                    and overrides.unusableVisualMode == nil then
                    overrides.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_DIM or "dim"
                    changed = true
                end
            end
        end
    end
    return changed
end

local AURA_DURATION_SWIPE_STYLE_MIRRORS = {
    { auraKey = "showAuraDurationSwipeFill", cooldownKey = "showCooldownSwipeFill", default = true },
    { auraKey = "auraDurationSwipeReverse", cooldownKey = "cooldownSwipeReverse", default = false },
    { auraKey = "auraDurationSwipeAlpha", cooldownKey = "cooldownSwipeAlpha", default = 0.8 },
    { auraKey = "auraDurationSwipeEdgeColor", cooldownKey = "cooldownSwipeEdgeColor", default = {1, 1, 1, 1} },
}

local function CaptureAuraDurationSwipeStyleState(style)
    if type(style) ~= "table" then
        return nil
    end

    local values = {
        showCooldownSwipe = rawget(style, "showCooldownSwipe"),
        auraUseBlizzardSwipe = rawget(style, "auraUseBlizzardSwipe"),
    }
    local auraKeys = {
        showAuraDurationSwipe = rawget(style, "showAuraDurationSwipe") ~= nil,
    }

    for _, mirror in ipairs(AURA_DURATION_SWIPE_STYLE_MIRRORS) do
        values[mirror.cooldownKey] = rawget(style, mirror.cooldownKey)
        auraKeys[mirror.auraKey] = rawget(style, mirror.auraKey) ~= nil
    end

    return {
        values = values,
        auraKeys = auraKeys,
    }
end

local function HasCapturedAuraDurationSwipeKey(styleState, auraKey)
    return type(styleState) == "table"
        and type(styleState.auraKeys) == "table"
        and styleState.auraKeys[auraKey] == true
end

local function ShouldBackfillAuraDurationSwipeKey(style, styleState, auraKey)
    if type(style) ~= "table" then
        return false
    end
    if rawget(style, auraKey) == nil then
        return true
    end
    return styleState ~= nil and not HasCapturedAuraDurationSwipeKey(styleState, auraKey)
end

local function ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, key, defaultValue)
    local values = type(styleState) == "table" and styleState.values
    local value
    if type(values) == "table" then
        value = values[key]
    end
    if value == nil and type(style) == "table" then
        value = rawget(style, key)
    end

    if value == nil then
        local fallbackValues = type(fallbackState) == "table" and fallbackState.values
        if type(fallbackValues) == "table" then
            value = fallbackValues[key]
        end
    end
    if value == nil and type(fallbackStyle) == "table" then
        value = rawget(fallbackStyle, key)
    end
    if value == nil then
        value = defaultValue
    end
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function BackfillAuraDurationSwipeStyle(style, fallbackStyle, styleState, fallbackState)
    if type(style) ~= "table" then
        return false
    end

    local changed = false
    if ShouldBackfillAuraDurationSwipeKey(style, styleState, "showAuraDurationSwipe") then
        local auraUseBlizzardSwipe = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, "auraUseBlizzardSwipe", false)
        if auraUseBlizzardSwipe == true then
            style.showAuraDurationSwipe = true
        else
            local showCooldownSwipe = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, "showCooldownSwipe", true)
            style.showAuraDurationSwipe = showCooldownSwipe ~= false
        end
        changed = true
    end

    for _, mirror in ipairs(AURA_DURATION_SWIPE_STYLE_MIRRORS) do
        if ShouldBackfillAuraDurationSwipeKey(style, styleState, mirror.auraKey) then
            style[mirror.auraKey] = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, mirror.cooldownKey, mirror.default)
            changed = true
        end
    end

    return changed
end

local function BackfillAuraDurationSwipeSettings(profile, savedProfileState)
    if type(profile) ~= "table" then
        return false
    end

    local globalStyleState = savedProfileState and savedProfileState.globalStyle
    local changed = BackfillAuraDurationSwipeStyle(profile.globalStyle, nil, globalStyleState)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                if BackfillAuraDurationSwipeStyle(group.style, profile.globalStyle) then
                    changed = true
                end

                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            local overrideSections = buttonData.overrideSections
                            local hasAuraSwipeOverride = type(overrideSections) == "table"
                                and (overrideSections.cooldownSwipe == true or overrideSections.auraDurationSwipe == true)
                            if hasAuraSwipeOverride and BackfillAuraDurationSwipeStyle(buttonData.styleOverrides, group.style) then
                                changed = true
                            end

                            if type(overrideSections) == "table"
                                and overrideSections.cooldownSwipe == true
                                and overrideSections.auraDurationSwipe ~= true then
                                overrideSections.auraDurationSwipe = true
                                changed = true
                            end
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" and BackfillAuraDurationSwipeStyle(presetData.style, profile.globalStyle) then
                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

-- 12.1 swipe-edge retirement: the 12.1 client draws the cooldown edge shorter
-- and detached from the swipe boundary, and Blizzard's own cooldowns (action
-- bars, Cooldown Manager, spellbook) all ship edge-off, so the edge is now off
-- by default. The old nil-means-on keys are retired outright; the explicit-true
-- pair cooldownSwipeEdgeEnabled / auraDurationSwipeEdgeEnabled replaces them.
-- Deleting instead of flipping keeps this pass a no-op on migrated data, so
-- import-driven re-runs can never claw back an edge a user re-enabled.
local RETIRED_SWIPE_EDGE_KEYS = { "showCooldownSwipeEdge", "showAuraDurationSwipeEdge" }

local function StripRetiredSwipeEdgeKeysFromStyle(style)
    if type(style) ~= "table" then
        return
    end
    for _, key in ipairs(RETIRED_SWIPE_EDGE_KEYS) do
        if rawget(style, key) ~= nil then
            style[key] = nil
        end
    end
end

local function StripRetiredSwipeEdgeKeys(profile)
    if type(profile) ~= "table" then
        return
    end

    StripRetiredSwipeEdgeKeysFromStyle(profile.globalStyle)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                StripRetiredSwipeEdgeKeysFromStyle(group.style)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            StripRetiredSwipeEdgeKeysFromStyle(buttonData.styleOverrides)
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        StripRetiredSwipeEdgeKeysFromStyle(presetData.style)
                    end
                end
            end
        end
    end
end

-- 12.1 icon-fill aura-color retirement: the aura leg of the icon fill was
-- removed with the AuraContainer rework (aura visuals are Blizzard-driven),
-- so iconFillAuraColor has no runtime reader, no picker, and no seed left.
-- Strip every stored copy so profiles and exports stop carrying a dead
-- color table. Deleting keeps this pass a no-op on migrated data.
local function StripRetiredIconFillAuraColorFromStyle(style)
    if type(style) == "table" and rawget(style, "iconFillAuraColor") ~= nil then
        style.iconFillAuraColor = nil
    end
end

local function StripRetiredIconFillAuraColor(profile)
    if type(profile) ~= "table" then
        return
    end

    StripRetiredIconFillAuraColorFromStyle(profile.globalStyle)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                StripRetiredIconFillAuraColorFromStyle(group.style)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            StripRetiredIconFillAuraColorFromStyle(buttonData.styleOverrides)
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        StripRetiredIconFillAuraColorFromStyle(presetData.style)
                    end
                end
            end
        end
    end
end

-- 12.1 cast-bar styling retirement: the CC-owned cast bar is always
-- CC-styled, so the old "restyle Blizzard's bar or leave it native" switch
-- has no runtime reader. Deleting rather than flipping keeps this pass a
-- no-op on migrated data, so import-driven re-runs change nothing.
--
-- Cast bar settings are CHARACTER-SCOPED: the live table is
-- profile.castBarByChar[<char>], seeded from profile.legacyCastBarSeed, with
-- profile.castBar as the pre-scoping legacy table. All three stores can
-- carry the key (and ride export strings), so all three are stripped.
local function StripCastBarStylingFromStore(castBar)
    if type(castBar) == "table" and rawget(castBar, "stylingEnabled") ~= nil then
        castBar.stylingEnabled = nil
    end
end

local function StripRetiredCastBarStylingKey(profile)
    if type(profile) ~= "table" then return end
    StripCastBarStylingFromStore(profile.castBar)
    StripCastBarStylingFromStore(profile.legacyCastBarSeed)
    if type(profile.castBarByChar) == "table" then
        for _, castBar in pairs(profile.castBarByChar) do
            StripCastBarStylingFromStore(castBar)
        end
    end
end

-- 12.1 text-panel auto-sizing retirement: a text entry now measures a
-- worst-case render of its own format, font and padding, so the manual
-- textWidth / textHeight pair has nothing left to size and no runtime reader.
-- textPadding is the only manual size knob that survives. Deleting the keys
-- rather than remapping them keeps this pass a no-op on migrated data, so
-- import-driven re-runs can never resurrect a size the layout no longer obeys.
local RETIRED_TEXT_SIZE_KEYS = { "textWidth", "textHeight" }

-- Only a value the user actually moved earns the notice; the shipped defaults
-- materialize into every profile and every exported string, so treating those
-- as a change would print for people who never touched the sliders.
local RETIRED_TEXT_SIZE_DEFAULTS = { textWidth = 200, textHeight = 20 }

local function StripRetiredTextSizeKeysFromStyle(style)
    if type(style) ~= "table" then
        return false
    end
    local hadCustomSize = false
    for _, key in ipairs(RETIRED_TEXT_SIZE_KEYS) do
        local value = rawget(style, key)
        if value ~= nil then
            if value ~= RETIRED_TEXT_SIZE_DEFAULTS[key] then
                hadCustomSize = true
            end
            style[key] = nil
        end
    end
    return hadCustomSize
end

local function StripRetiredTextSizeKeys(profile)
    if type(profile) ~= "table" then
        return false
    end

    local hadCustomSize = StripRetiredTextSizeKeysFromStyle(profile.globalStyle)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                if StripRetiredTextSizeKeysFromStyle(group.style) then
                    hadCustomSize = true
                end
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table"
                            and StripRetiredTextSizeKeysFromStyle(buttonData.styleOverrides) then
                            hadCustomSize = true
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table"
                        and StripRetiredTextSizeKeysFromStyle(presetData.style) then
                        hadCustomSize = true
                    end
                end
            end
        end
    end

    return hadCustomSize
end

local RETIRED_PROFILE_FLAGS = { "autoAddPrefs", "cdmHidden" }

local function ClearRetiredProfileFlags(profile)
    if type(profile) ~= "table" then
        return false
    end
    -- cdmHidden was a user-visible main-era setting (hide the Blizzard
    -- Cooldown Manager); only an enabled value earns the notice — the
    -- default false materializes into exported strings.
    local cdmHiddenWasEnabled = profile.cdmHidden == true
    for _, key in ipairs(RETIRED_PROFILE_FLAGS) do
        profile[key] = nil
    end
    return cdmHiddenWasEnabled
end

local function HasSupportedCheckpoint(payload)
    if type(payload) ~= "table" then
        return false
    end

    local comparison = CompareVersion(payload[IMPORT_CHECKPOINT_KEY], IMPORT_CHECKPOINT_VERSION)
    return comparison ~= nil and comparison >= 0
end

local function GetSavedVariablesProfile(savedVariables, defaultProfile)
    if type(savedVariables) ~= "table" then
        return nil
    end

    if defaultProfile == true then
        defaultProfile = "Default"
    end

    local charName = UnitName and UnitName("player")
    local realmName = GetRealmName and GetRealmName()
    local charKey = charName and realmName and (charName .. " - " .. realmName)
    local profileKey = type(savedVariables.profileKeys) == "table"
        and charKey
        and savedVariables.profileKeys[charKey]
        or defaultProfile
        or charKey

    return type(savedVariables.profiles) == "table" and profileKey and savedVariables.profiles[profileKey] or nil
end

function CooldownCompanion:InspectSavedProfileCheckpoint(savedVariables, defaultProfile)
    local state = {
        hadSavedVariables = type(savedVariables) == "table",
        profileExisted = false,
        profileLookedLikePayload = false,
        profileHadSupportedCheckpoint = false,
    }

    local profile = GetSavedVariablesProfile(savedVariables, defaultProfile)
    if type(profile) ~= "table" then
        return state
    end

    state.profileExisted = true
    state.profileLookedLikePayload = LooksLikeProfilePayload(profile)
    state.profileHadSupportedCheckpoint = HasSupportedCheckpoint(profile)
    state.auraDurationSwipe = {
        globalStyle = CaptureAuraDurationSwipeStyleState(profile.globalStyle),
    }
    return state
end

function CooldownCompanion:IsUnsupportedLegacyProfile(profile, allowMissingCheckpoint)
    if type(profile) ~= "table" then return false end

    if LooksLikeProfilePayload(profile) and not HasSupportedCheckpoint(profile) then
        return not allowMissingCheckpoint
    end

    local groups = profile.groups
    local containers = profile.groupContainers
    local hasContainerTable = type(containers) == "table"

    -- Treat profile-shaped payloads without container-era storage as unsupported.
    if LooksLikeProfilePayload(profile) and not hasContainerTable then
        return true
    end

    return type(groups) == "table"
        and next(groups) ~= nil
        and hasContainerTable
        and not next(containers)
end

function CooldownCompanion:StampImportCheckpoint(payload)
    if type(payload) == "table" then
        payload[IMPORT_CHECKPOINT_KEY] = IMPORT_CHECKPOINT_VERSION
    end
    return payload
end

function CooldownCompanion:StampExportPayloadCheckpoint(payload, exportKind)
    self:StampImportCheckpoint(payload)
    if exportKind == "diagnostic" and type(payload) == "table" and type(payload.profile) == "table" then
        self:StampImportCheckpoint(payload.profile)
    end
    return payload
end

function CooldownCompanion:HasSupportedImportCheckpoint(payload)
    return HasSupportedCheckpoint(payload)
end

function CooldownCompanion:IsUnsupportedImportPayload(payload)
    if type(payload) ~= "table" then
        return false
    end
    if payload._cdcUnsupportedCompactFormat then
        return true
    end
    return self:IsUnsupportedLegacyProfile(payload) or not self:HasSupportedImportCheckpoint(payload)
end

function CooldownCompanion:GetLegacySupportCutoffMessage(dataLabel)
    dataLabel = dataLabel or "data"
    return ("This build supports Cooldown Companion %s and newer data. This %s appears to come from %s or older. To recover it, load or import it with an older addon version, then export it again after it has been opened by %s."):format(
        LEGACY_SUPPORT_FLOOR_VERSION,
        dataLabel,
        LEGACY_UNSUPPORTED_MAX_VERSION,
        LEGACY_SUPPORT_FLOOR_VERSION
    )
end

function CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
    self:Print(self:GetLegacySupportCutoffMessage(dataLabel))
end

-- 12.1 aura rebuild migration: keep-what-maps (field names unchanged), drop
-- what has no 12.1 equivalent, recompute the tracked unit from spell polarity
-- (the anti-cheat gate allows only buffs-on-player and own-debuffs-on-target).
-- Idempotent; gated on a one-time profile stamp so users see the summary once.
-- Untouched on purpose: the live pandemic visual keys (the aura glow pass
-- owns their sanitizers and the dead-family strip)
-- and stored auraActive trigger clauses (retired-offer pattern). Custom-bar
-- aura entries get the same treatment from the bar aura effect pass below,
-- including the tracked-unit recompute and mixed-list trim.
local function ClassifyAuraSpellUnit(spellID)
    if not (spellID and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(spellID)) then
        return nil
    end
    return C_Spell.IsSpellHarmful(spellID) and "target" or "player"
end

-- Aura sounds play natively through C_UnitAuras.AddAuraSound, which needs a
-- sound FILE. Both the event set and the playability rule come from
-- SoundAlerts so this cannot drift from the registration path: it covers
-- every native trigger (including stack-gained) and every unplayable form
-- (the Blizzard soundkit and text-to-speech sentinels carried over from the
-- old CC-played path, plus shared media that resolves to a numeric SoundKit).
local function StripUnplayableAuraSoundForms(self, dataTable)
    local events = type(dataTable.soundAlerts) == "table"
        and type(dataTable.soundAlerts.events) == "table"
        and dataTable.soundAlerts.events or nil
    if not (events and self.GetNativeAuraSoundEventKeys and self.IsAuraSoundSelectionUnplayable) then
        return 0
    end
    local stripped = 0
    for eventKey in pairs(self:GetNativeAuraSoundEventKeys()) do
        if self:IsAuraSoundSelectionUnplayable(events[eventKey]) then
            events[eventKey] = nil
            stripped = stripped + 1
        end
    end
    -- Prune what the strip emptied, the same as the setter paths
    -- (SetButtonSoundAlertEvent / SetCustomBarSoundAlertEvent): an entry
    -- left holding soundAlerts = { events = {} } still counts as configured
    -- content, so it survives normalization and ships in every export.
    if stripped > 0 and not next(events) then
        dataTable.soundAlerts.events = nil
        if not next(dataTable.soundAlerts) then
            dataTable.soundAlerts = nil
        end
    end
    return stripped
end

-- Mixed buff/debuff candidate lists are unrepresentable on 12.1 (one slot,
-- one polarity): keep the majority polarity plus IDs that cannot be
-- classified yet. Returns the resolved polarity and whether the stored list
-- was trimmed. Shared by panel entries and custom-bar entries.
local function ResolveAuraCandidatePolarity(dataTable)
    local raw = dataTable.auraSpellID and tostring(dataTable.auraSpellID) or nil
    if not raw then
        return nil, false
    end

    local helpfulCount, harmfulCount = 0, 0
    for id in raw:gmatch("%d+") do
        local unit = ClassifyAuraSpellUnit(tonumber(id))
        if unit == "target" then
            harmfulCount = harmfulCount + 1
        elseif unit == "player" then
            helpfulCount = helpfulCount + 1
        end
    end

    if helpfulCount > 0 and harmfulCount > 0 then
        local keepUnit = harmfulCount > helpfulCount and "target" or "player"
        local rebuilt = {}
        for id in raw:gmatch("%d+") do
            local numericID = tonumber(id)
            local unit = ClassifyAuraSpellUnit(numericID)
            if numericID and (unit == nil or unit == keepUnit) then
                rebuilt[#rebuilt + 1] = tostring(numericID)
            end
        end
        dataTable.auraSpellID = table.concat(rebuilt, ",")
        return keepUnit, true
    end

    if harmfulCount > 0 then
        return "target", false
    end
    if helpfulCount > 0 then
        return "player", false
    end
    return nil, false
end

-- The retired stack-display option family, shared by the two storage shapes
-- that carry it: panel entries (auraBar sub-table, cleared below in
-- MigrateEntryAuraResidue) and custom-bar entries (cleared through the
-- CUSTOM_BAR_RETIRED_* tables, which append these). One inventory so a key
-- retired for one shape cannot linger on the other. Names only — counting
-- policy stays at each call site (panels count threshold/maxGlow into their
-- own notice lines; custom bars lump everything into cabOptions).
local RETIRED_STACK_SILENT_KEYS = {
    "stackTextFormat",
    "overlayColor",
    "thresholdMaxColor",
    "maxStacksGlowStyle",
    "maxStacksGlowColor",
    "maxStacksGlowSize",
    "maxStacksGlowThickness",
    "maxStacksGlowSpeed",
    "maxStacksGlowLines",
    "maxStacksBarPulseEnabled",
    "maxStacksBarPulseSpeed",
    "maxStacksBarColorShiftEnabled",
    "maxStacksBarColorShiftSpeed",
    "maxStacksBarColorShiftColor",
}

-- Counted only when the feature was actually ON: these store explicit false
-- when the user toggled them back off, and an untouched-then-disabled
-- default is not a lost setting.
local RETIRED_STACK_COUNTED_KEYS = {
    { key = "thresholdColorEnabled", panelCount = "threshold" },
    { key = "maxStacksGlowEnabled", panelCount = "maxGlow" },
}

-- Residue that can linger on any entry regardless of its current tracking
-- state (aura tracking may have been toggled off after these were written),
-- so this runs for every button, not just aura entries.
local function MigrateEntryAuraResidue(self, buttonData, counts)
    -- hide-while-aura-active: LOST in 12.1 (no compliant mechanism).
    -- Cleared whenever present, but counted only when it was actually ON:
    -- main wrote an explicit false when the toggle was switched back off,
    -- and reporting those inflates the notice with settings the user had
    -- already disabled.
    if buttonData.hideWhileAuraActive ~= nil then
        if buttonData.hideWhileAuraActive == true then
            counts.hideActive = counts.hideActive + 1
        end
        buttonData.hideWhileAuraActive = nil
    end

    -- hide-except-during-pandemic: LOST in 12.1. Stored true-or-nil, so
    -- presence means enabled. (auraKeepSpellCooldownSwipe was stripped here
    -- too until the 2.0 keep-swipe revival. Removing the strip preserves the
    -- flag only on profiles that have not yet claimed this sentinel -- fresh
    -- 1.x imports; a profile already migrated by an earlier 2.0 build lost
    -- the value and re-ticks the checkbox by hand.)
    if buttonData.hideAuraActiveExceptPandemic ~= nil then
        counts.hidePandemic = counts.hidePandemic + 1
        buttonData.hideAuraActiveExceptPandemic = nil
    end

    -- The hide-while-active baseline fallback rode on hideWhileAuraActive
    -- and dies with it. Not counted here: the parent's drop is counted only
    -- when the parent key is still present, and an earlier sentinel
    -- generation may already have cleared it, leaving this orphan alone.
    buttonData.useBaselineAlphaFallbackAuraActive = nil

    -- Dim While Aura Inactive survives but moves onto the 12.1-native
    -- auraShellDim key. Main stored it as a fallback riding
    -- hideWhileAuraNotActive; on 12.1 the two are mutually exclusive
    -- single-key toggles.
    --   pair (hide + fallback) -> auraShellDim, both legacy keys cleared.
    --   fallback alone         -> dropped: main left this orphan behind when
    --     the hide toggle was switched back off (only the hide-while-ACTIVE
    --     handler cleared its sibling), and it rendered nothing there.
    -- Both arms test == true, never ~= nil: a stored `false` is main's way
    -- of spelling "off", and reading it as "the pair is present" would keep
    -- the fallback alive and start dimming an entry that never dimmed.
    --
    -- Nothing in this pass reads or writes auraShellDim, and that is the
    -- point. The pass re-runs on every import (ClearMigrationSentinels), so
    -- any rule keyed on the SHAPE of the old fallback key would eventually
    -- eat a live setting — a 12.1 entry the user dimmed is indistinguishable
    -- from main-era residue while both share one key. Converting onto a key
    -- this pass never touches makes re-running a genuine no-op.
    -- Uncounted: the pair keeps its meaning and the orphan rendered nothing,
    -- so neither is a setting the user loses.
    if buttonData.useBaselineAlphaFallback ~= nil then
        if buttonData.useBaselineAlphaFallback == true
            and buttonData.hideWhileAuraNotActive == true then
            buttonData.auraShellDim = true
            buttonData.hideWhileAuraNotActive = nil
        end
        buttonData.useBaselineAlphaFallback = nil
    end

    counts.soundForm = counts.soundForm + StripUnplayableAuraSoundForms(self, buttonData)

    -- Bar stack displays: the old mode value carried the display style
    -- ("stack_continuous" etc.); split it onto the mode + stackDisplayMode
    -- vocabulary. Gap and smoothing keep their meaning and carry over. Keys
    -- with no 12.1 home (numeric max, overlay color, threshold colors, the
    -- max-stacks indicator family) clear. New-vocabulary values pass
    -- through untouched so re-running on 12.1-native data changes nothing.
    local auraBar = type(buttonData.auraBar) == "table" and buttonData.auraBar or nil
    if auraBar then
        local mode = auraBar.mode
        local displayMode = auraBar.stackDisplayMode
        local wantsContinuous = mode == "stack_continuous" or displayMode == "stack_continuous"
        if mode == "stack" or mode == "stack_continuous"
            or mode == "stack_segmented" or mode == "stack_overlay" then
            auraBar.mode = "stacks"
            auraBar.stackDisplayMode = wantsContinuous and "continuous" or nil
            counts.stackModes = counts.stackModes + 1
        elseif type(displayMode) == "string" and displayMode:find("^stack") then
            -- Only a revived continuous style is a visible change; a stale
            -- segmented value resolves to nil, which is already the default.
            auraBar.stackDisplayMode = wantsContinuous and "continuous" or nil
            if wantsContinuous then
                counts.stackModes = counts.stackModes + 1
            end
        end
        -- Panel-only: custom bars still use maxStacks, so it is not in the
        -- shared inventory.
        auraBar.maxStacks = nil
        for _, key in ipairs(RETIRED_STACK_SILENT_KEYS) do
            auraBar[key] = nil
        end
        for _, spec in ipairs(RETIRED_STACK_COUNTED_KEYS) do
            if auraBar[spec.key] ~= nil then
                if auraBar[spec.key] == true then
                    counts[spec.panelCount] = counts[spec.panelCount] + 1
                end
                auraBar[spec.key] = nil
            end
        end
    end
end

local function MigrateAuraEntry(self, buttonData, counts)
    local polarity, trimmed = ResolveAuraCandidatePolarity(buttonData)
    if trimmed then
        counts.mixed = counts.mixed + 1
    end
    if polarity == nil then
        polarity = ClassifyAuraSpellUnit(self:ResolveAuraSpellID(buttonData))
    end
    if polarity and buttonData.auraUnit ~= polarity then
        if buttonData.auraUnit ~= nil then
            counts.unit = counts.unit + 1
        end
        buttonData.auraUnit = polarity
    end

    -- Re-assert the standalone-entry invariants (idempotent, CDM-free).
    if buttonData.addedAs == "aura" and self.NormalizeStandaloneAuraButtonData then
        self:NormalizeStandaloneAuraButtonData(buttonData)
    end
end

-- Generation-ordered sentinel registry: `current` is the live guard,
-- `retired` are prior generations cleared when a pass claims a profile.
-- A generation bump is ONE edit here — move the old current into retired,
-- name the new current — and the guard, the retired-clears, and
-- ClearMigrationSentinels all follow. The old shape needed three
-- coordinated edits per bump; missing the ClearMigrationSentinels one left
-- imported profiles permanently stamped and silently un-migrated.
--
-- aura rebuild generations: renamed from _cdcAuraRebuildMigrated when the
-- pass stopped wiping aura-removed sounds, gained the lingering-option and
-- dead-key clears, and began mapping bar stack displays onto the split
-- vocabulary; renamed again when the sound strip moved onto the shared
-- SoundAlerts rule; gen 4 normalizes the fresh active-only Texture aura
-- indicator by dropping unsupported live-era missing/combat qualifiers.
-- bar aura effect generations: from _cdcBarAuraGlowMigrated (size resets
-- and custom-bar traversal), then _cdcBarAuraEffectMigrated, then
-- _cdcBarAuraEffect2Migrated (all custom-bar storage shapes, the seed
-- scope, the identity release).
--
-- Deliberately NOT here: _cdcAuraDormantPlacementNoted (marks an
-- observation, not a transform — survives clears so the notice prints
-- once) and _cdcFlattenedFolderNotice (a notice accumulator, not a guard).
local AURA_REBUILD_SENTINEL = {
    current = "_cdcAuraRebuild4Migrated",
    retired = { "_cdcAuraRebuildMigrated", "_cdcAuraRebuild2Migrated", "_cdcAuraRebuild3Migrated" },
}
-- bar aura effect generations: gen 4 added the custom-bar entry strip of
-- the retired pandemicBar* families (the Phase 3 pandemic retirement).
local BAR_AURA_EFFECT_SENTINEL = {
    current = "_cdcBarAuraEffect4Migrated",
    retired = { "_cdcBarAuraGlowMigrated", "_cdcBarAuraEffectMigrated",
        "_cdcBarAuraEffect2Migrated", "_cdcBarAuraEffect3Migrated" },
}
-- aura glow generations: gen 2 (renamed from _cdcAuraGlowMigrated) gained
-- the pandemic pixel-scale sanitizers and the live-era per-entry
-- pandemicGlow override strip (PTR 8 lit the dormant key family up); gen 3
-- extended the dead-key strip to every style scope and added the
-- texture-indicator pandemic strip and the {?pandemic} text-format scrub
-- (the Phase 3 pandemic retirement).
local AURA_GLOW_SENTINEL = {
    current = "_cdcAuraGlow3Migrated",
    retired = { "_cdcAuraGlowMigrated", "_cdcAuraGlow2Migrated" },
}
-- pandemic override ownership: the pandemicMarker* keys leaving the auraText
-- override section for the pandemic ones, when the config grew a Pandemic
-- section. Claimed through the shared helper so a future generation bump is
-- still one edit.
local PANDEMIC_OVERRIDE_SENTINEL = {
    current = "_cdcPandemicOverrideMigrated",
}
local MIGRATION_SENTINELS = {
    AURA_REBUILD_SENTINEL,
    BAR_AURA_EFFECT_SENTINEL,
    AURA_GLOW_SENTINEL,
    PANDEMIC_OVERRIDE_SENTINEL,
    -- Single-generation passes keep their own inline guard and stamp (the
    -- group-scope pass stamps conditionally on talent data being ready);
    -- registered so ClearMigrationSentinels iterates them.
    { current = "_cdcAuraGroupScopeMigrated" },
    { current = "_cdcLcgGlowMigrated" },
    { current = "_cdcPerModeOrientationMigrated" },
    { current = "_cdcAuraPanelIntegrityMigrated" },
}

-- False when the profile is already stamped; otherwise clears the retired
-- generations and lets the pass run. The caller stamps sentinel.current
-- when its transform completes.
local function ClaimMigrationPass(profile, sentinel)
    if profile[sentinel.current] then return false end
    for _, key in ipairs(sentinel.retired or {}) do
        profile[key] = nil
    end
    return true
end

-- Per-mode orientation split (2026-08-08): bar and text panels stopped
-- reading style.orientation (icons keep it) and moved onto their own
-- barOrientation/textOrientation keys, so a display-mode swap can no longer
-- destroy another mode's layout. A panel from before the split carries its
-- current bar/text layout only in the shared key; copy it across so nothing
-- on screen flips on update. Nil-guarded: new-format bar/text panels always
-- have their key stamped (CreatePanel, mode swap, the config writers), which
-- keeps the sentinel-stripped re-run after a profile import from touching
-- them. Shared with the panel-piece import door, which installs panels into
-- an already-stamped profile the load-time pass will not revisit.
function ST._NormalizePanelOrientationKeys(group)
    if type(group) ~= "table" or type(group.style) ~= "table" then return end
    local style = group.style
    if group.displayMode == "bars" then
        if style.barOrientation == nil then
            style.barOrientation = style.orientation or "vertical"
        end
    elseif group.displayMode == "text" then
        if style.textOrientation == nil then
            -- "horizontal", not "vertical": the pre-split fallback for an
            -- unset TEXT panel was horizontal (only bar mode fell back to
            -- vertical), and this copy preserves what was on screen. The
            -- vertical text default is for panels born after the split.
            style.textOrientation = style.orientation or "horizontal"
        end
    end
end

-- Aura Panel repair for the panel-piece import door (2026-08-15). Every other
-- way an Aura Panel gains an entry runs through CreatePanel and AddButtonToGroup,
-- which enforce the subtype's invariants; an imported panel is raw payload data
-- installed wholesale, so it is the one door with no gate. Re-establishes the
-- invariants the display engine relies on:
--   * the subtype only has icon and bar forms;
--   * its entries render through the aura container's own flow layout, so CC's
--     compact reflow and Masque skinning have nothing to drive;
--   * only aura entries, which is a static property of the stored entry;
--   * every entry carries a per-panel key that no other entry in the panel
--     shares, without which the engine cannot bind it (or binds two entries
--     onto one aura group and renders only the last), and nextAuraKey sits
--     above every numeric key already in use.
--
-- POLARITY IS NEVER REPAIRED HERE, and never deletes an entry. An entry's unit
-- comes from ResolveAuraEntryUnit, which resolves the APPLIED aura through
-- spec-dependent Cooldown Manager / buff-viewer data, so the same stored entry
-- can answer "player" on one spec and "target" on another. A pass that dropped
-- entries on that answer would silently delete a working panel's entries the
-- next time the owner imported anything on the wrong spec -- and this pass
-- re-runs over the WHOLE profile on every import, not just over incoming
-- panels. The add doors still enforce polarity for NEW entries, where the
-- answer is being made rather than second-guessed, and the bind pass skips a
-- mismatched entry non-destructively and counts it (GetAuraDisplayStatus's
-- unitMismatches) -- that counter is the surface for this condition.
--
-- Existing unique keys stay exactly as they are: the engine has already bound
-- them, and renumbering would move live entries between aura groups. Pure data,
-- no frames, and idempotent, so a second pass over a repaired panel changes
-- nothing. Panels without the flag are left alone, residue included: a stray
-- key harms nothing, and stripping it would break a panel re-imported as an
-- Aura Panel later.
function ST._NormalizeAuraPanelEntries(group)
    if type(group) ~= "table" or group.auraPanel ~= true then return end

    if group.displayMode ~= "icons" and group.displayMode ~= "bars" then
        group.displayMode = "icons"
    end
    CooldownCompanion:EnforceAuraPanelInvariants(group)

    local kept = {}
    for _, buttonData in ipairs(type(group.buttons) == "table" and group.buttons or {}) do
        if type(buttonData) == "table"
            and buttonData.type == "spell"
            and buttonData.addedAs == "aura" then
            kept[#kept + 1] = buttonData
        end
    end
    group.buttons = kept

    -- Every key already in the panel is measured first, so the values stamped
    -- below start above all of them and cannot collide with a key that stayed.
    local maxKey = 0
    for _, buttonData in ipairs(kept) do
        local numeric = tonumber(buttonData._auraKey)
        if numeric and numeric > maxKey then
            maxKey = numeric
        end
    end

    -- First occurrence of a key owns it; a later entry repeating it has no aura
    -- group of its own (EnsurePanelGroup would hand it the first entry's) and is
    -- renumbered, exactly like a keyless one.
    local nextKey = math.max(maxKey + 1, tonumber(group.nextAuraKey) or 1)
    local used = {}
    for _, buttonData in ipairs(kept) do
        local key = buttonData._auraKey
        if key == nil or used[key] then
            key = tostring(nextKey)
            nextKey = nextKey + 1
            buttonData._auraKey = key
        end
        used[key] = true
    end
    group.nextAuraKey = nextKey
end

local function MigratePerModeOrientation(self, profile)
    if type(profile) ~= "table" or profile._cdcPerModeOrientationMigrated then return end
    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            ST._NormalizePanelOrientationKeys(group)
        end
    end
    profile._cdcPerModeOrientationMigrated = true
end

-- The same repair, for the FULL PROFILE import door. The panel-piece door calls
-- the normalizer itself as it installs each panel, but a whole-profile import
-- replaces profile.groups wholesale, so nothing walks the incoming panels: an
-- Aura Panel that arrives keyless (or with two entries sharing one key) would
-- reach the display engine, which can only count and skip it. Registered in
-- MIGRATION_SENTINELS so the import hook strips the stamp and forces this
-- re-run over the imported profile.
--
-- Silent by design. The normalizer reports nothing, and no shipped profile can
-- carry a malformed Aura Panel: the subtype is new in this release and every
-- in-client path to an entry goes through CreatePanel/AddButtonToGroup, which
-- enforce the invariants. Only a hand-crafted payload reaches this pass with
-- work to do, and a print for that is noise rather than news. The diagnostics
-- counters in GetAuraDisplayStatus are where an unrepaired panel shows up.
local function MigrateAuraPanelIntegrity(self, profile)
    if type(profile) ~= "table" or profile._cdcAuraPanelIntegrityMigrated then return end
    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            ST._NormalizeAuraPanelEntries(group)
        end
    end
    profile._cdcAuraPanelIntegrityMigrated = true
end

local function MigrateAuraTrackingRebuild(self, profile)
    -- Already-stamped profiles re-run it once (idempotent; new-vocabulary
    -- values pass through untouched).
    if type(profile) ~= "table" or not ClaimMigrationPass(profile, AURA_REBUILD_SENTINEL) then return end
    local counts = {
        hideActive = 0, hidePandemic = 0, stackModes = 0,
        threshold = 0, maxGlow = 0, soundForm = 0, mixed = 0, unit = 0,
        dormantPlacement = 0, textureAuraQualifier = 0,
    }
    local groups = profile.groups
    if type(groups) == "table" then
        for _, group in pairs(groups) do
            local buttons = type(group) == "table" and group.buttons or nil
            if type(buttons) == "table" then
                -- Icon/bar panels compose their existing aura display. Primary
                -- Aura entries in Texture panels are always enabled; ordinary
                -- spell entries require the explicit Texture opt-in. Retained
                -- auraTracking flags and stored aura trigger clauses otherwise
                -- stay dormant and are only counted, never moved.
                local displayMode = group.displayMode or "icons"
                local standardAuraCapable = displayMode == "icons" or displayMode == "bars"
                for _, buttonData in ipairs(buttons) do
                    if type(buttonData) == "table" then
                        MigrateEntryAuraResidue(self, buttonData, counts)
                        local isAuraEntry = buttonData.type == "spell"
                            and (buttonData.auraTracking or buttonData.addedAs == "aura")
                        if isAuraEntry then
                            MigrateAuraEntry(self, buttonData, counts)
                        end
                        local isTexturePanel = displayMode == "textures"
                        local textureAuraChoice
                        if isTexturePanel then
                            if buttonData.type == "spell" and buttonData.addedAs == "aura" then
                                buttonData.textureAuraDisplayEnabled = true
                            end
                            textureAuraChoice = buttonData.textureAuraDisplayEnabled
                            if textureAuraChoice == true then
                                if self:NormalizeTexturePanelAuraIndicatorSettings(group, false) then
                                    counts.textureAuraQualifier = counts.textureAuraQualifier + 1
                                end
                            end
                        end
                        local auraEntryCapable = standardAuraCapable
                            or textureAuraChoice == true
                        local auraEntryPlacementUnsupported = not auraEntryCapable
                            and not (isTexturePanel and textureAuraChoice == false)
                        if not auraEntryCapable or not standardAuraCapable then
                            -- The singular entry-level key is a storage form
                            -- in its own right, not just a clause spelling:
                            -- HasTriggerConditionConfig tests it first, and
                            -- the display reads it whenever no clause array
                            -- exists. Main-era data that never went through
                            -- clause promotion carries only this one, which
                            -- is exactly the data this notice is for.
                            local hasAuraClause = buttonData.triggerCondition == "auraActive"
                            if not hasAuraClause and type(buttonData.triggerConditions) == "table" then
                                for _, clause in ipairs(buttonData.triggerConditions) do
                                    if type(clause) == "table"
                                        and (clause.key == "auraActive"
                                            or clause.conditionKey == "auraActive"
                                            or clause.triggerCondition == "auraActive") then
                                        hasAuraClause = true
                                        break
                                    end
                                end
                            end
                            if (isAuraEntry and auraEntryPlacementUnsupported)
                                or (hasAuraClause and not standardAuraCapable) then
                                counts.dormantPlacement = counts.dormantPlacement + 1
                            end
                        end
                    end
                end
            end
        end
    end
    profile[AURA_REBUILD_SENTINEL.current] = true
    local dropped = {}
    if counts.hideActive > 0 then dropped[#dropped + 1] = ("hide-while-aura-active (x%d)"):format(counts.hideActive) end
    if counts.hidePandemic > 0 then dropped[#dropped + 1] = ("hide-except-during-pandemic (x%d)"):format(counts.hidePandemic) end
    if counts.stackModes > 0 then dropped[#dropped + 1] = ("bar stack displays remapped (x%d)"):format(counts.stackModes) end
    if counts.threshold > 0 then dropped[#dropped + 1] = ("stack threshold colors (x%d)"):format(counts.threshold) end
    if counts.maxGlow > 0 then dropped[#dropped + 1] = ("max-stacks glows (x%d)"):format(counts.maxGlow) end
    if counts.soundForm > 0 then dropped[#dropped + 1] = ("aura sounds needing a file-based sound (x%d)"):format(counts.soundForm) end
    if counts.mixed > 0 then dropped[#dropped + 1] = ("mixed buff/debuff aura lists trimmed (x%d)"):format(counts.mixed) end
    if counts.unit > 0 then dropped[#dropped + 1] = ("tracked-unit corrections (x%d)"):format(counts.unit) end
    if counts.textureAuraQualifier > 0 then
        dropped[#dropped + 1] = ("Texture Aura inactive/combat-only effect qualifiers (x%d)")
            :format(counts.textureAuraQualifier)
    end
    -- Dormant placements are an OBSERVATION, not a transform: nothing is
    -- cleared, so re-running finds the same entries forever. Its own flag
    -- survives ClearMigrationSentinels (which exists to re-run transforms
    -- over freshly imported data) so the notice states the fact once per
    -- profile instead of on every import.
    if counts.dormantPlacement > 0 and not profile._cdcAuraDormantPlacementNoted then
        profile._cdcAuraDormantPlacementNoted = true
        dropped[#dropped + 1] = ("unsupported aura entries or conditions (x%d)"):format(counts.dormantPlacement)
    end
    if #dropped > 0 then
        self:Print("Aura tracking updated for 12.1. Adjusted settings: "
            .. table.concat(dropped, ", ") .. ".")
    end
end

-- Clear group scope only when the primary aura proves target polarity or the
-- corrected castable identity proves the aura foreign. The second predicate
-- result distinguishes a known foreign spell from spell data that is not
-- available yet; indeterminate entries remain untouched.
local function MigrateAuraGroupScopeIdentity(self, profile)
    if type(profile) ~= "table" or profile._cdcAuraGroupScopeMigrated then return end

    -- Castability clears additionally require a readable talent config:
    -- WalkTalentTree matches nothing when the active config is unavailable
    -- (early login), which would read as determinately foreign and wrongly
    -- clear a valid flag on an unlearned-talent entry. Polarity clears do not
    -- depend on talents; the sentinel only stamps once talents were readable
    -- so a too-early run retries on a later login.
    local talentDataReady = C_ClassTalents.GetActiveConfigID() ~= nil

    local groups = profile.groups
    if type(groups) == "table" then
        for _, group in pairs(groups) do
            local buttons = type(group) == "table" and group.buttons or nil
            if type(buttons) == "table" then
                for _, buttonData in ipairs(buttons) do
                    if type(buttonData) == "table" and buttonData.auraTrackGroup == true then
                        local primaryAuraSpellID = self:ResolveAuraSpellID(buttonData)
                        local unit = ClassifyAuraSpellUnit(primaryAuraSpellID)
                        if unit == "target" then
                            buttonData.auraTrackGroup = nil
                        elseif unit == "player" and talentDataReady then
                            local ownsAura, ownershipKnown =
                                self:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
                            if ownershipKnown and not ownsAura then
                                buttonData.auraTrackGroup = nil
                            end
                        end
                    end
                end
            end
        end
    end

    if talentDataReady then
        profile._cdcAuraGroupScopeMigrated = true
    end
end

-- Aura glow rebuild migration (Phase 4): the aura glow renders on the aura
-- slot kit now, with styles none/solid/pulse/colorShift/dashes/ants/proc/
-- overlay. The old default "pixel" and the LCG styles cannot run there
-- (OnUpdate scripts never run on the forbidden subtree; LCG reparents pooled
-- frames into it): "pixel" becomes its "dashes" lookalike (line-length size
-- kept as dash px, 10..200 speed dropped), the LCG styles become "pulse";
-- "glow" becomes "proc", "pulsingBorder" becomes "pulse". Invert (glow while
-- missing) and combat-only cannot exist on the write-once kit and are
-- dropped. Style keys sit physically on every stored style table (full-copy
-- group creation), so renames run silently; only enabled invert/combat-only
-- losses are user-visible and counted.

-- Retired pandemic keys with no 12.1 reader (the Phase 3 retirement): the
-- nil-means-on enable, the unhonorable combat gate, and the unwired
-- pandemicBarEffect/Pulse/ColorShift families. Stripped silently from
-- every style scope (globalStyle, group styles, per-entry overrides,
-- presets); the custom-bar ENTRY twins ride CUSTOM_BAR_RETIRED_SILENT_KEYS.
-- Idempotent; re-runs on every import by design.
local PANDEMIC_DEAD_STYLE_KEYS = {
    "showPandemicGlow", "pandemicGlowCombatOnly",
    "pandemicBarEffect", "pandemicBarEffectColor",
    "pandemicBarEffectSize", "pandemicBarEffectThickness",
    "pandemicBarEffectSpeed", "pandemicBarEffectLines",
    "pandemicBarPulseEnabled", "pandemicBarPulseSpeed",
    "pandemicBarColorShiftEnabled", "pandemicBarColorShiftSpeed",
    "pandemicBarColorShiftColor",
}

-- {?pandemic} conditional spans never rendered their content (the presence
-- read a permanently-false flag) and {!pandemic} spans always did: drop the
-- former with content, unwrap the latter, then drop stray tags and the
-- bare value token (which rendered empty). The parser lowercases tokens,
-- so the matching is case-insensitive too. Degenerate mismatched-tag
-- layouts crossing pandemic and non-pandemic conditionals cannot all be
-- preserved statically; the span walk below mirrors the retired runtime
-- walker so the common classes (flat, nested, unclosed, stray closers)
-- keep exactly what they rendered.

-- The conditional-token set the retired walker knew, frozen at retirement:
-- while skipping a false span it deepened on ANY known cond_start and
-- closed one level on ANY known cond_end, with unknown tags inert — so a
-- stray {/stacks} inside a {?pandemic} span really did close it and rescue
-- the text after it. Runtime token changes must never edit this list.
local SCRUB_CONDITIONAL_TOKENS = {
    time = true, charges = true, maxcharges = true, missingcharges = true,
    zerocharges = true, stacks = true, aura = true, keybind = true,
    pandemic = true, proc = true, unusable = true, oor = true,
    available = true, incombat = true,
}

local PANDEMIC_TOKEN_PATTERN = "[pP][aA][nN][dD][eE][mM][iI][cC]"

-- Remove one false {?pandemic} span exactly as the walker skipped it.
local function DropFalsePandemicSpan(fmt)
    local openStart, openEnd = fmt:find("{%?" .. PANDEMIC_TOKEN_PATTERN .. "}")
    if not openStart then return fmt, false end
    local depth = 1
    local pos = openEnd + 1
    while depth > 0 do
        local tagStart = fmt:find("{", pos, true)
        local tagEnd = tagStart and fmt:find("}", tagStart + 1, true)
        if not tagEnd then
            -- Unclosed span: the walker skipped to end-of-string.
            pos = #fmt + 1
            break
        end
        local inner = fmt:sub(tagStart + 1, tagEnd - 1):lower()
        local prefix = inner:sub(1, 1)
        if (prefix == "?" or prefix == "!") and SCRUB_CONDITIONAL_TOKENS[inner:sub(2)] then
            depth = depth + 1
        elseif prefix == "/" and SCRUB_CONDITIONAL_TOKENS[inner:sub(2)] then
            depth = depth - 1
        end
        pos = tagEnd + 1
    end
    return fmt:sub(1, openStart - 1) .. fmt:sub(pos), true
end

local function ScrubPandemicTextFormat(fmt)
    if type(fmt) ~= "string" or not fmt:find("[pP]") then return fmt, false end
    local out = fmt
    -- Run the whole pass to a fixed point: a tag removal can splice its
    -- surroundings into a NEW pandemic tag ("{?pandem{pandemic}ic}"), and
    -- one call must converge fully. Terminates because every changing
    -- pass strictly shrinks the string.
    repeat
        local before = out
        local dropped = true
        while dropped do
            out, dropped = DropFalsePandemicSpan(out)
        end
        out = out:gsub("{!" .. PANDEMIC_TOKEN_PATTERN .. "}(.-){/" .. PANDEMIC_TOKEN_PATTERN .. "}", "%1")
        out = out:gsub("{[%?!/]?" .. PANDEMIC_TOKEN_PATTERN .. "}", "")
    until out == before
    return out, out ~= fmt
end

local function MigrateAuraGlowStyleTable(styleTable, counts)
    if type(styleTable) ~= "table" then return end

    for _, key in ipairs(PANDEMIC_DEAD_STYLE_KEYS) do
        if rawget(styleTable, key) ~= nil then
            styleTable[key] = nil
        end
    end

    -- The texture-panel pandemic indicator retired with no config surface
    -- to ever enable it, but the store normalizer had been writing its
    -- normalized sub-table into every texture panel's saved style.
    local indicators = rawget(styleTable, "textureIndicators")
    if type(indicators) == "table" and indicators.pandemic ~= nil then
        indicators.pandemic = nil
    end

    local fmt, scrubbed = ScrubPandemicTextFormat(rawget(styleTable, "textFormat"))
    if scrubbed then
        styleTable.textFormat = fmt
        counts.textFormat = counts.textFormat + 1
    end

    local oldStyle = rawget(styleTable, "auraGlowStyle")
    if oldStyle ~= nil and oldStyle ~= "none" and oldStyle ~= "solid"
        and oldStyle ~= "pulse" and oldStyle ~= "proc"
        and oldStyle ~= "colorShift" and oldStyle ~= "dashes"
        and oldStyle ~= "ants" and oldStyle ~= "overlay" then
        if oldStyle == "glow" or oldStyle == "lcgProc" then
            styleTable.auraGlowStyle = "proc"
        elseif oldStyle == "pixel" then
            -- The dashes style is the pixel lookalike. Its size key means
            -- dash px, close enough to the old line length to keep; the
            -- speed key was pixel-scale (10..200) and dies with the
            -- catch-all below. The old line count carries over as the dash
            -- count (capped at the dash pool size) before the lines key is
            -- dropped at the end of this function.
            styleTable.auraGlowStyle = "dashes"
            local lines = rawget(styleTable, "auraGlowLines")
            if type(lines) == "number" and lines >= 1 then
                styleTable.auraGlowDashCount = math.min(math.floor(lines + 0.5), 8)
            end
            local thickness = rawget(styleTable, "auraGlowThickness")
            if type(thickness) == "number" and thickness >= 1 then
                styleTable.auraGlowDashThickness = math.min(thickness, 8)
            end
        else
            styleTable.auraGlowStyle = "pulse"
            if oldStyle ~= "pulsingBorder" then
                -- Leaving LCG: size and speed were pixel-scale.
                if rawget(styleTable, "auraGlowSize") ~= nil then
                    styleTable.auraGlowSize = nil
                end
                if rawget(styleTable, "auraGlowSpeed") ~= nil then
                    styleTable.auraGlowSpeed = nil
                end
            end
        end
    end

    -- Speed stores seconds (cycles up to 2.0, dashes laps up to 3); anything
    -- larger is a leftover pixel-scale value regardless of which style it
    -- arrived with.
    local speed = rawget(styleTable, "auraGlowSpeed")
    if type(speed) == "number" and speed > 3 then
        styleTable.auraGlowSpeed = nil
    end

    -- Border sizes for solid/pulse/colorShift cap at 8 and dash lengths at
    -- 20 (the config slider maximums); anything larger is a leftover pixel
    -- line-length. Needed separately from the style rename above:
    -- defaults-backed tables (globalStyle) can carry a stored size while the
    -- default-equal "pixel" style key itself was never stored.
    local finalStyle = rawget(styleTable, "auraGlowStyle") or "pulse"
    local sizeCap
    if finalStyle == "pulse" or finalStyle == "solid" or finalStyle == "colorShift" then
        sizeCap = 8
    elseif finalStyle == "dashes" then
        sizeCap = 20
    end
    if sizeCap then
        local size = rawget(styleTable, "auraGlowSize")
        if type(size) == "number" and size > sizeCap then
            styleTable.auraGlowSize = nil
        end
    end

    -- Pandemic glow twins (PTR 8 lights the dormant keys up). Legacy style
    -- values remap into the kit vocabulary FIRST — live-era stores carried
    -- pixel/glow/pulsingBorder/lcg* (the LCG pass runs after this one, so
    -- it cannot be relied on here), and the new dropdown only knows kit
    -- values — then the pixel-scale leftovers clear against the remapped
    -- style (dormant-era defaults were speed 50 / size 5 / thickness 4 /
    -- lines 8 in the retired LCG scale). Same idempotence shape as the
    -- auraGlow clears above: kit values and sane numbers pass untouched.
    local pandemicStyle = rawget(styleTable, "pandemicGlowStyle")
    if pandemicStyle == "pixel" then
        styleTable.pandemicGlowStyle = "dashes"
    elseif pandemicStyle == "pulsingBorder" then
        styleTable.pandemicGlowStyle = "pulse"
    elseif pandemicStyle == "glow" then
        styleTable.pandemicGlowStyle = "proc"
    elseif pandemicStyle == "lcgButton" or pandemicStyle == "lcgProc"
        or pandemicStyle == "lcgAutoCast" then
        styleTable.pandemicGlowStyle = "solid"
    end
    local pandemicSpeed = rawget(styleTable, "pandemicGlowSpeed")
    if type(pandemicSpeed) == "number" and pandemicSpeed > 3 then
        styleTable.pandemicGlowSpeed = nil
    end
    pandemicStyle = rawget(styleTable, "pandemicGlowStyle") or "solid"
    local pandemicSizeCap
    if pandemicStyle == "pulse" or pandemicStyle == "solid" or pandemicStyle == "colorShift" then
        pandemicSizeCap = 8
    elseif pandemicStyle == "dashes" then
        pandemicSizeCap = 20
    end
    if pandemicSizeCap then
        local pandemicSize = rawget(styleTable, "pandemicGlowSize")
        if type(pandemicSize) == "number" and pandemicSize > pandemicSizeCap then
            styleTable.pandemicGlowSize = nil
        end
    end
    local pandemicThickness = rawget(styleTable, "pandemicGlowThickness")
    if type(pandemicThickness) == "number" and pandemicThickness > 8 then
        styleTable.pandemicGlowThickness = nil
    end
    local pandemicLines = rawget(styleTable, "pandemicGlowLines")
    if type(pandemicLines) == "number" and pandemicLines > 8 then
        styleTable.pandemicGlowLines = nil
    end

    if rawget(styleTable, "auraGlowInvert") ~= nil then
        if styleTable.auraGlowInvert == true then
            counts.invert = counts.invert + 1
        end
        styleTable.auraGlowInvert = nil
    end
    if rawget(styleTable, "auraGlowCombatOnly") ~= nil then
        if styleTable.auraGlowCombatOnly == true then
            counts.combatOnly = counts.combatOnly + 1
        end
        styleTable.auraGlowCombatOnly = nil
    end
    styleTable.auraGlowThickness = nil
    styleTable.auraGlowLines = nil
end

-- The pandemic section is OFFERED as a per-entry override again on 12.1
-- (owner ruling), so live-era promotions carry forward as visible, revertible
-- overrides — the style-value sanitizers above run on styleOverrides too, and
-- the dead-key strip lives inside them (PANDEMIC_DEAD_STYLE_KEYS, every style
-- scope). MigratePandemicOverrideOwnership below renames the two retired
-- section ids those promotions were stored under.
local function MigrateAuraGlowRebuild(self, profile)
    if type(profile) ~= "table" or not ClaimMigrationPass(profile, AURA_GLOW_SENTINEL) then return end
    local counts = { invert = 0, combatOnly = 0, textFormat = 0 }

    MigrateAuraGlowStyleTable(profile.globalStyle, counts)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                MigrateAuraGlowStyleTable(group.style, counts)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            MigrateAuraGlowStyleTable(buttonData.styleOverrides, counts)
                            -- Per-entry format strings carry the same
                            -- retired text token as the style tables.
                            local fmt, scrubbed = ScrubPandemicTextFormat(rawget(buttonData, "textFormat"))
                            if scrubbed then
                                buttonData.textFormat = fmt
                                counts.textFormat = counts.textFormat + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        MigrateAuraGlowStyleTable(presetData.style, counts)
                    end
                end
            end
        end
    end

    profile[AURA_GLOW_SENTINEL.current] = true
    local dropped = {}
    if counts.invert > 0 then dropped[#dropped + 1] = ("glow-while-missing (x%d)"):format(counts.invert) end
    if counts.combatOnly > 0 then dropped[#dropped + 1] = ("combat-only aura glow (x%d)"):format(counts.combatOnly) end
    if counts.textFormat > 0 then dropped[#dropped + 1] = ("pandemic text tokens (x%d)"):format(counts.textFormat) end
    if #dropped > 0 then
        self:Print("Aura glow updated for 12.1. Dropped settings with no 12.1 equivalent: "
            .. table.concat(dropped, ", ") .. ".")
    end
end

-- LibCustomGlow was removed: lcgButton (Action Button Glow) folds into the
-- built-in "glow" style (its modern Blizzard successor), lcgAutoCast
-- (Autocast Shine) becomes the CC-rendered "autocast" style with identical
-- parameters. Styles that never rendered LCG (pandemic glow, key press
-- highlight) get any stray lcg value reset to their solid default.
local function MigrateLcgStyleTable(styleTable, counts)
    if type(styleTable) ~= "table" then return end

    for _, keys in ipairs({
        { style = "procGlowStyle", size = "procGlowSize" },
        { style = "readyGlowStyle", size = "readyGlowSize" },
    }) do
        local style = rawget(styleTable, keys.style)
        if style == "lcgButton" or style == "lcgProc" then
            styleTable[keys.style] = "glow"
            if style == "lcgButton" then
                counts.buttonGlow = counts.buttonGlow + 1
                -- lcgButton never consumed the size key (its only parameter
                -- was frequency), so any stored value is a leftover from an
                -- earlier style and would render as a tiny Glow overhang.
                -- Clear unconditionally so the glow default (30) applies.
                styleTable[keys.size] = nil
            end
        elseif style == "lcgAutoCast" then
            styleTable[keys.style] = "autocast"
            counts.autocast = counts.autocast + 1
        end
    end

    for _, styleKey in ipairs({ "pandemicGlowStyle", "keyPressHighlightStyle" }) do
        local style = rawget(styleTable, styleKey)
        if style == "lcgButton" or style == "lcgAutoCast" or style == "lcgProc" then
            styleTable[styleKey] = "solid"
        end
    end
end

local function MigrateLcgGlowStyles(self, profile)
    if type(profile) ~= "table" or profile._cdcLcgGlowMigrated then return end
    local counts = { buttonGlow = 0, autocast = 0 }

    MigrateLcgStyleTable(profile.globalStyle, counts)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                MigrateLcgStyleTable(group.style, counts)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            MigrateLcgStyleTable(buttonData.styleOverrides, counts)
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        MigrateLcgStyleTable(presetData.style, counts)
                    end
                end
            end
        end
    end

    profile._cdcLcgGlowMigrated = true
    local changed = {}
    if counts.buttonGlow > 0 then changed[#changed + 1] = ("Action Button Glow entries now use the standard Glow (x%d)"):format(counts.buttonGlow) end
    if counts.autocast > 0 then changed[#changed + 1] = ("Autocast Shine is now addon-rendered (x%d)"):format(counts.autocast) end
    if #changed > 0 then
        self:Print("Glow styles updated: " .. table.concat(changed, "; ") .. ".")
    end
end

-- The bar aura effect now renders through the aura kit (barActiveAura
-- wiring), offering border styles only: remap stored values from the
-- retired renderers to that vocabulary. "pixel" becomes its dashes
-- lookalike (size kept: dash length px matches; line count capped at the
-- kit pool ceiling of 8); "pulsingBorder" canonicalizes to "pulse" (size
-- kept: border px); "glow" and the removed LibCustomGlow values become the
-- pulse border with their overhang/scale sizes cleared so the border
-- default applies; pixel-scale speeds (10..200) clear so the style default
-- in seconds applies.
local function MigrateBarAuraEffectTable(styleTable, counts)
    if type(styleTable) ~= "table" then return end

    -- The pandemicBarEffect* family no longer remaps here: it retired
    -- outright (PANDEMIC_DEAD_STYLE_KEYS strips the style scopes, the
    -- custom-bar silent list strips the entries).
    for _, keys in ipairs({
        { style = "barAuraEffect", size = "barAuraEffectSize", speed = "barAuraEffectSpeed", lines = "barAuraEffectLines" },
    }) do
        local style = rawget(styleTable, keys.style)
        local mapped
        local clearSize = false
        if style == "pixel" then
            mapped = "dashes"
        elseif style == "pulsingBorder" then
            mapped = "pulse"
        elseif style == "glow" or style == "proc" or style == "ants" or style == "overlay"
            or style == "lcgButton" or style == "lcgAutoCast" or style == "lcgProc" then
            mapped = "pulse"
            clearSize = true
        end
        if mapped then
            styleTable[keys.style] = mapped
            counts.remapped = counts.remapped + 1
            if clearSize then
                styleTable[keys.size] = nil
            end
            local lines = rawget(styleTable, keys.lines)
            if type(lines) == "number" and lines > 8 then
                styleTable[keys.lines] = 8
            end
        end
        if style ~= nil then
            local speed = rawget(styleTable, keys.speed)
            if type(speed) == "number" and speed > 3 then
                styleTable[keys.speed] = nil
            end
        end
    end
end

-- Custom-bar entries carry the same effect keys directly on the entry
-- table; canonicalize them so the stored values stay clean. Entries live
-- either in a shared store ({entries = {id = entry}}) or as a plain
-- id-to-entry map. Options the 12.1 custom bars no longer offer clear here
-- (counted only when they were enabled: live stored most as true-or-nil,
-- and the explicit-false toggles must not count untouched defaults), and
-- aura sounds get the same file-form rule as panel entries because the
-- entry's soundAlerts table feeds the native aura sound path by reference.
-- The old pandemic families retired outright (Phase 3 ruling): the toggle,
-- its color, the combat-only flag, and the whole effect/pulse/color-shift
-- family clear from entries. The 12.1 replacements are the pandemic marker
-- and the fresh pandemicEffect/pandemicColor fill-recolor keys — neither of
-- which may ever appear on these lists.
-- Custom-bar-only retired keys, plus the shared stack-display inventory
-- appended below (RETIRED_STACK_*, declared beside MigrateEntryAuraResidue,
-- which clears the same family on panel entries).
local CUSTOM_BAR_RETIRED_OPTION_KEYS = {
    "hideWhileAuraActive",
    "hideAuraActiveExceptPandemic",
    "auraGlowCombatOnly",
    "showPandemicGlow",
}
local CUSTOM_BAR_RETIRED_SILENT_KEYS = {
    "pandemicGlowCombatOnly",
    "barPandemicColor",
    "pandemicBarEffect",
    "pandemicBarEffectColor",
    "pandemicBarEffectSize",
    "pandemicBarEffectThickness",
    "pandemicBarEffectSpeed",
    "pandemicBarEffectLines",
    "pandemicBarPulseEnabled",
    "pandemicBarPulseSpeed",
    "pandemicBarColorShiftEnabled",
    "pandemicBarColorShiftSpeed",
    "pandemicBarColorShiftColor",
    -- auraName stays: the piece importer still reads it as a display-name
    -- fallback for legacy custom-bar entries.
}
for _, spec in ipairs(RETIRED_STACK_COUNTED_KEYS) do
    CUSTOM_BAR_RETIRED_OPTION_KEYS[#CUSTOM_BAR_RETIRED_OPTION_KEYS + 1] = spec.key
end
for _, key in ipairs(RETIRED_STACK_SILENT_KEYS) do
    CUSTOM_BAR_RETIRED_SILENT_KEYS[#CUSTOM_BAR_RETIRED_SILENT_KEYS + 1] = key
end

-- Live let the user pin a custom bar's tracked unit; 12.1 derives it from
-- spell polarity and removed the control, but GetResolvedCustomAuraBarAuraUnit
-- still honours a stored pin ahead of polarity. A stale pin therefore leaves
-- a permanently dark bar with no UI to correct it, so the pin is dropped for
-- EVERY entry — the hazard is not limited to aura-typed ones, and the pin is
-- read for both types.
--
-- The unit itself is deliberately NOT written here. RunResourceBarClassScopeMigration
-- runs later in this same chain and recomputes it through the runtime
-- resolver (EnsureCustomAuraBarAuraUnit), which is also what the live bind
-- path and the native aura sound registration read. Writing a second,
-- differently-derived value here would be overwritten moments later while
-- still being reported to the user as a correction.
local function MigrateCustomBarAuraIdentity(entry, counts)
    local tracksAura = entry.auraTracking == true
        or entry.entryType == nil
        or entry.entryType == "aura"

    if entry.auraUnitExplicit ~= nil then
        entry.auraUnitExplicit = nil
        counts.cabUnit = counts.cabUnit + 1
    end

    if not tracksAura then
        return
    end

    -- Mixed buff/debuff candidate lists are a real transform on stored data
    -- and stay here; the unit that falls out of them is the resolver's.
    local _, trimmed = ResolveAuraCandidatePolarity(entry)
    if trimmed then
        counts.cabMixed = counts.cabMixed + 1
    end
end

local function MigrateOneCustomBarEntry(self, entry, counts)
    MigrateBarAuraEffectTable(entry, counts)
    -- Stack display canonicalization: the overlay mode died with the aura
    -- rebuild (the runtime renders anything but "continuous" as segmented),
    -- and the stack text format is a retired live-era key the preview must
    -- not honor while the live bar ignores it.
    if entry.displayMode == "overlay" then
        entry.displayMode = "segmented"
    end
    for _, key in ipairs(CUSTOM_BAR_RETIRED_OPTION_KEYS) do
        if entry[key] ~= nil then
            if entry[key] == true then
                counts.cabOptions = counts.cabOptions + 1
            end
            entry[key] = nil
        end
    end
    for _, key in ipairs(CUSTOM_BAR_RETIRED_SILENT_KEYS) do
        if entry[key] ~= nil then
            entry[key] = nil
        end
    end
    counts.cabSoundForm = counts.cabSoundForm + StripUnplayableAuraSoundForms(self, entry)
    MigrateCustomBarAuraIdentity(entry, counts)
end

-- An entry is distinguished from a spec bucket by its own scalar fields; a
-- bucket only ever holds entry tables. Every key here must be entry-ONLY:
-- a marker that a layout or style sub-table can also carry (displayMode,
-- order, the colour arrays) would make this pass rewrite that table.
local CUSTOM_BAR_ENTRY_MARKER_KEYS = {
    "spellID", "entryType", "customBarId", "enabled", "label",
    "auraSpellID", "trackingMode", "soundAlerts",
    -- Live-era entries that predate the id/type fields carry these instead,
    -- and without them such an entry is skipped by the whole pass.
    "auraName", "resourceKey", "hideWhenInactive", "auraTracking",
}

local function LooksLikeCustomBarEntry(value)
    for _, key in ipairs(CUSTOM_BAR_ENTRY_MARKER_KEYS) do
        if value[key] ~= nil then
            return true
        end
    end
    return false
end

-- Custom-bar entries reach this pass in every shape the resource-bar
-- normalizer accepts, because that normalizer runs lazily and (for the
-- class-scope migration) only after this pass has stamped: the shared store
-- ({entries = {id = entry}}), the live-era spec-keyed buckets
-- ({[specID] = {[index] = entry}}), and the separate customAuraBars store.
-- Anything missed here is promoted later and never revisited, so the walk
-- covers all three rather than assuming the store was already converted.
local function ForEachStoredCustomBarEntry(self, container, counts)
    if type(container) ~= "table" then
        return
    end

    if type(container.entries) == "table" or type(container.order) == "table" then
        for _, entry in pairs(container.entries or {}) do
            if type(entry) == "table" then
                MigrateOneCustomBarEntry(self, entry, counts)
            end
        end
        return
    end

    -- Descending into a value is a POSITIVE decision, never a fallback: the
    -- pass rewrites and clears ~20 keys per entry, so a table it guesses
    -- wrong about is corrupted. A bucket must be keyed by a spec id and hold
    -- something that itself looks like an entry (or a nested shared store);
    -- anything else is left untouched even if it is also not a recognizable
    -- entry, because doing nothing is recoverable and rewriting is not.
    local function LooksLikeCustomBarBucket(key, value)
        if tonumber(key) == nil then
            return false
        end
        if type(value.entries) == "table" or type(value.order) == "table" then
            return true
        end
        for _, child in pairs(value) do
            if type(child) == "table" and LooksLikeCustomBarEntry(child) then
                return true
            end
        end
        return false
    end

    for key, value in pairs(container) do
        if type(value) == "table" then
            if LooksLikeCustomBarEntry(value) then
                MigrateOneCustomBarEntry(self, value, counts)
            elseif LooksLikeCustomBarBucket(key, value) then
                ForEachStoredCustomBarEntry(self, value, counts)
            end
        end
    end
end

local function MigrateCustomBarEntries(self, settings, counts)
    if type(settings) ~= "table" then return end
    ForEachStoredCustomBarEntry(self, settings.customBars, counts)
    ForEachStoredCustomBarEntry(self, settings.customAuraBars, counts)
end

local function MigrateBarAuraEffectStyles(self, profile)
    -- Generation history lives on BAR_AURA_EFFECT_SENTINEL beside the
    -- registry. Already-stamped profiles re-run it once (idempotent).
    if type(profile) ~= "table" or not ClaimMigrationPass(profile, BAR_AURA_EFFECT_SENTINEL) then return end
    local counts = {
        remapped = 0, cabOptions = 0, cabSoundForm = 0,
        cabMixed = 0, cabUnit = 0,
    }

    MigrateBarAuraEffectTable(profile.globalStyle, counts)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                MigrateBarAuraEffectTable(group.style, counts)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            MigrateBarAuraEffectTable(buttonData.styleOverrides, counts)
                        end
                    end
                end
            end
        end
    end

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" then
                        MigrateBarAuraEffectTable(presetData.style, counts)
                    end
                end
            end
        end
    end

    -- Every scope of the resource-bar stores can hold custom-bar entries.
    -- legacyResourceBarsSeed is a frozen profile-level copy that the
    -- class-scope migration re-injects into the character and class stores
    -- AFTER this pass stamps, so skipping it would reintroduce un-migrated
    -- entries that are never revisited.
    MigrateCustomBarEntries(self, profile.resourceBars, counts)
    MigrateCustomBarEntries(self, profile.legacyResourceBarsSeed, counts)
    for _, storeKey in ipairs({ "resourceBarsByChar", "resourceBarsByClass" }) do
        local store = profile[storeKey]
        if type(store) == "table" then
            for _, settings in pairs(store) do
                MigrateCustomBarEntries(self, settings, counts)
            end
        end
    end

    profile[BAR_AURA_EFFECT_SENTINEL.current] = true
    local changed = {}
    if counts.remapped > 0 then changed[#changed + 1] = ("effect styles moved to the new renderer (x%d)"):format(counts.remapped) end
    if counts.cabOptions > 0 then changed[#changed + 1] = ("custom bar options with no 12.1 equivalent (x%d)"):format(counts.cabOptions) end
    if counts.cabSoundForm > 0 then changed[#changed + 1] = ("custom bar aura sounds needing a file-based sound (x%d)"):format(counts.cabSoundForm) end
    if counts.cabMixed > 0 then changed[#changed + 1] = ("custom bar mixed buff/debuff aura lists trimmed (x%d)"):format(counts.cabMixed) end
    if counts.cabUnit > 0 then changed[#changed + 1] = ("custom bar tracked-unit pins released to automatic (x%d)"):format(counts.cabUnit) end
    if #changed > 0 then
        self:Print("Bar aura effects updated for 12.1: " .. table.concat(changed, "; ") .. ".")
    end
end

------------------------------------------------------------------------
-- PANDEMIC OVERRIDE OWNERSHIP
--
-- Two changes land here, because they touch the same stored tables.
--
-- 1. SECTION MERGE. PTR 8 shipped two per-entry override sections for one
--    feature: pandemicGlow (icons) and pandemicBar (bars). They already shared
--    pandemicEffectEnabled, and nothing clears an override when a panel
--    changes display mode, so an entry could carry the wrong-mode one while
--    the Overtab offered the right-mode one to promote — either click writing
--    or wiping keys the other still listed. They are now one "pandemic"
--    section spanning both modes, and this pass renames the stored ids.
--
-- 2. MARKER RE-HOMING. The four pandemicMarker* keys used to belong to the
--    auraText override section, because the marker is drawn into the aura
--    duration text. The config grew a Pandemic section holding both halves of
--    the refresh window, and the keys moved into it.
--
-- Nothing has to MOVE for (2). styleOverrides is one flat table and IS the
-- effective style (StyleOverrides.lua), so the keys already sit where they
-- render; overrideSections is bookkeeping for the config's Customize, Revert
-- and scope readouts. What this pass fixes is ownership: a key in the flat table
-- that no listed section claims still renders, but revert cannot clear it and
-- no panel draws it. That is the whole bug, and it is invisible in game.
--
-- The rule is "preserve exactly what this entry renders today":
--   * no active override section -> GetEffectiveStyle ignores styleOverrides
--     entirely, so these keys render nothing. Drop them.
--   * every present key equals the group's own value -> dropping them changes
--     nothing (the metatable falls through to the same value) and the entry
--     stops claiming a customisation it never made. This is the common case:
--     PromoteSection copies the whole key list, so an entry promoted only to
--     change a font physically stored all four. Presence proves nothing.
--   * any present key differs -> that difference is what the entry renders
--     right now, stale ride-along copies included, because overrides outrank
--     the panel. The pandemic section takes ownership and it survives.
--
-- The destination is now mode-independent, so a panel converted to any other
-- display mode keeps a single unambiguous owner. Its OTHER keys are
-- deliberately NOT seeded: a section whose group values were nil at promote
-- time already stores nothing for them and reads through the __index
-- fallback, so a partly-populated section is the ordinary state rather than a
-- new one, and not seeding keeps the entry following later panel edits to a
-- pandemic effect it never asked to own.
--
-- Silent: a rename and a re-homing lose nothing, and this file's convention is
-- that only user-visible losses and semantic remaps earn a notice.
------------------------------------------------------------------------
local PANDEMIC_MARKER_OVERRIDE_KEYS = {
    "pandemicMarkerEnabled",
    "pandemicMarkerText",
    "pandemicMarkerColorMode",
    "pandemicMarkerColor",
}

-- What AuraDisplay resolves when the style table is silent. Groups created
-- before the marker existed never received these into group.style (it is a
-- plain copy of globalStyle at creation), so the comparison needs a floor.
local PANDEMIC_MARKER_BASELINE = {
    pandemicMarkerEnabled = true,
    pandemicMarkerText = "!!",
    pandemicMarkerColorMode = "marker",
    pandemicMarkerColor = { 1, 0.5, 0, 1 },
}

local PANDEMIC_OVERRIDE_SECTION = "pandemic"
local PANDEMIC_RETIRED_OVERRIDE_SECTIONS = { "pandemicGlow", "pandemicBar" }

-- Both retired ids collapse onto the one section. An entry that somehow holds
-- both (an icons promote, a conversion to bars, a second promote) merges to a
-- single flag; its keys already live in the one flat table, so there is
-- nothing to reconcile beyond the bookkeeping.
local function RenamePandemicOverrideSections(buttonData)
    local sections = rawget(buttonData, "overrideSections")
    if type(sections) ~= "table" then return end
    for _, retired in ipairs(PANDEMIC_RETIRED_OVERRIDE_SECTIONS) do
        if sections[retired] then
            sections[retired] = nil
            sections[PANDEMIC_OVERRIDE_SECTION] = true
        end
    end
end

-- pandemicMarkerColor is a table, and PromoteSection CopyTable's it, so every
-- promoted entry owns a private one. Identity comparison would call every
-- entry customised.
local function PandemicMarkerValuesMatch(stored, baseline)
    if type(stored) == "table" or type(baseline) == "table" then
        if type(stored) ~= "table" or type(baseline) ~= "table" then
            return false
        end
        for i = 1, 4 do
            if stored[i] ~= baseline[i] then
                return false
            end
        end
        return true
    end
    return stored == baseline
end

local function MigrateOnePandemicOverride(buttonData, group)
    if type(buttonData) ~= "table" then return end

    -- Rename first: the marker logic below reads the section flag, and it must
    -- see the merged id rather than either retired one.
    RenamePandemicOverrideSections(buttonData)

    -- rawget throughout: GetEffectiveStyle leaves __index = groupStyle on this
    -- table and never removes it, so a plain read reports the GROUP's value
    -- for keys the entry never stored and every entry would look customised.
    local overrides = rawget(buttonData, "styleOverrides")
    if type(overrides) ~= "table" then return end

    local present = false
    for _, key in ipairs(PANDEMIC_MARKER_OVERRIDE_KEYS) do
        if rawget(overrides, key) ~= nil then
            present = true
        end
    end
    if not present then return end

    local sections = rawget(buttonData, "overrideSections")
    local hasActiveSection = type(sections) == "table" and next(sections) ~= nil
    local destination = nil
    if hasActiveSection then
        destination = PANDEMIC_OVERRIDE_SECTION
    end

    if destination and sections[destination] then
        -- Already owned. Every import clears the sentinels and re-runs this,
        -- so the second pass must decide nothing: the keys belong to the
        -- destination and re-testing them could unpick a real override.
        return
    end

    if destination and ST.CanButtonUseOverrideSection
        and not ST.CanButtonUseOverrideSection(buttonData, destination) then
        -- PruneDisallowedOverrideSections would delete the flag and the keys
        -- on the next GetEffectiveStyle anyway; drop them rather than hand it
        -- a section to tear down.
        destination = nil
    end

    local customised = false
    if destination then
        local groupStyle = rawget(group, "style")
        for _, key in ipairs(PANDEMIC_MARKER_OVERRIDE_KEYS) do
            local stored = rawget(overrides, key)
            if stored ~= nil then
                local baseline
                if type(groupStyle) == "table" then
                    baseline = rawget(groupStyle, key)
                end
                if baseline == nil then
                    baseline = PANDEMIC_MARKER_BASELINE[key]
                end
                if not PandemicMarkerValuesMatch(stored, baseline) then
                    customised = true
                end
            end
        end
    end

    if customised then
        sections[destination] = true
        return
    end

    for _, key in ipairs(PANDEMIC_MARKER_OVERRIDE_KEYS) do
        overrides[key] = nil
    end
    -- RevertSection's cleanup, plus the guard it does not need: it always
    -- removes a section, this pass never does, and the config reads
    -- buttonData.styleOverrides directly, so a live section must keep a table.
    if not next(overrides) and not hasActiveSection then
        buttonData.styleOverrides = nil
    end
end

local function MigratePandemicOverrideOwnership(self, profile)
    if type(profile) ~= "table" or not ClaimMigrationPass(profile, PANDEMIC_OVERRIDE_SENTINEL) then return end

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" and type(group.buttons) == "table" then
                for _, buttonData in ipairs(group.buttons) do
                    MigrateOnePandemicOverride(buttonData, group)
                end
            end
        end
    end

    -- Custom aura bars are a different store: they hold the marker keys flat
    -- on the entry with no override sections at all, so they need nothing
    -- here. The names must also stay OUT of CUSTOM_BAR_RETIRED_SILENT_KEYS,
    -- which strips the retired barPandemic* families whose names look alike.
    profile[PANDEMIC_OVERRIDE_SENTINEL.current] = true
end

-- Consolidated entry point: enforces the 1.15 data cutoff and stamps profiles
-- that are allowed to continue. Add new post-1.15 migrations here in order.
function CooldownCompanion:RunAllMigrations()
    local checkpointState = self._savedProfileCheckpointState
    local allowMissingCheckpoint = self._allowMissingMigrationCheckpointOnce
        or (checkpointState and (
            not checkpointState.hadSavedVariables
            or not checkpointState.profileExisted
            or not checkpointState.profileLookedLikePayload
        ))
    self._allowMissingMigrationCheckpointOnce = nil
    self._savedProfileCheckpointState = nil

    if self:IsUnsupportedLegacyProfile(self.db and self.db.profile, allowMissingCheckpoint) then
        self._unsupportedLegacyProfile = true
        if not self._unsupportedLegacyProfileNotified then
            self:NotifyLegacySupportCutoff("profile")
            self._unsupportedLegacyProfileNotified = true
        end
        return false
    end

    self._unsupportedLegacyProfile = false
    self._unsupportedLegacyProfileNotified = nil
    self._pendingUnsupportedLegacyHide = nil

    self:StampImportCheckpoint(self.db and self.db.profile)
    self:MigrateFoldersIntoGroups(self.db and self.db.profile)
    -- Read the stash, not the return: an import door may have flattened this
    -- profile before the chain ever reached here.
    local noticeProfile = self.db and self.db.profile
    local flattenedFolders = tonumber(noticeProfile and noticeProfile._cdcFlattenedFolderNotice) or 0
    if noticeProfile then
        noticeProfile._cdcFlattenedFolderNotice = nil
    end
    local retiredCdmHidden = ClearRetiredProfileFlags(self.db and self.db.profile)
    if retiredCdmHidden or flattenedFolders > 0 then
        local parts = {}
        if retiredCdmHidden then
            parts[#parts + 1] = "the Hide Cooldown Manager setting was retired"
        end
        if flattenedFolders > 0 then
            parts[#parts + 1] = ("legacy folders were flattened into groups (x%d)"):format(flattenedFolders)
        end
        self:Print("Updated for 12.1: " .. table.concat(parts, "; ") .. ".")
    end
    NormalizePassiveCooldownButtons(self.db and self.db.profile)
    ClearInvalidStrataOrders(self.db and self.db.profile)
    BackfillUnusableVisualOverrideModes(self.db and self.db.profile)
    BackfillAuraDurationSwipeSettings(self.db and self.db.profile, checkpointState and checkpointState.auraDurationSwipe)
    StripRetiredSwipeEdgeKeys(self.db and self.db.profile)
    StripRetiredIconFillAuraColor(self.db and self.db.profile)
    StripRetiredCastBarStylingKey(self.db and self.db.profile)
    if StripRetiredTextSizeKeys(self.db and self.db.profile) then
        self:Print("Updated for 12.1: text panels now size themselves from their format and font. Use Padding for breathing room.")
    end
    MigratePerModeOrientation(self, self.db and self.db.profile)
    MigrateAuraTrackingRebuild(self, self.db and self.db.profile)
    -- After the aura vocabulary rebuild so the repair walks entries whose
    -- addedAs labels are final, and ahead of the style/override passes below
    -- so they only walk entries that survived the non-aura drop. Polarity
    -- plays no part in this pass anymore -- it never deletes (see the
    -- normalizer's header).
    MigrateAuraPanelIntegrity(self, self.db and self.db.profile)
    MigrateAuraGroupScopeIdentity(self, self.db and self.db.profile)
    MigrateAuraGlowRebuild(self, self.db and self.db.profile)
    MigrateLcgGlowStyles(self, self.db and self.db.profile)
    MigrateBarAuraEffectStyles(self, self.db and self.db.profile)
    -- After the style-table passes above: they strip dead keys from entry
    -- override tables too, so this one compares cleaned data.
    MigratePandemicOverrideOwnership(self, self.db and self.db.profile)
    if self.RunResourceBarClassScopeMigration then
        self:RunResourceBarClassScopeMigration()
    end
    if self.SanitizeCursorAnchorPolicy and not self._deferCursorAnchorPolicySanitizer then
        self:SanitizeCursorAnchorPolicy(self.db and self.db.profile)
    end
    if self.NormalizePanelAlphaInheritance then
        self:NormalizePanelAlphaInheritance(self.db and self.db.profile)
    end
    return true
end

function CooldownCompanion:ClearMigrationSentinels()
    -- Import hook: clear one-time stamps so imported pre-rebuild profiles
    -- re-run their passes (each pass is idempotent; re-running on migrated
    -- data changes nothing and prints nothing). Driven by the registry so a
    -- generation bump cannot forget this site.
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then return end
    for _, sentinel in ipairs(MIGRATION_SENTINELS) do
        for _, key in ipairs(sentinel.retired or {}) do
            profile[key] = nil
        end
        profile[sentinel.current] = nil
    end
end

