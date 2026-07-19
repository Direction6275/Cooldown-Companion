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

local function GetEntityScopeKey(addon, entity, isFolder)
    if type(entity) ~= "table" then
        return "invalid"
    end
    if (isFolder and entity.section == "global") or (not isFolder and entity.isGlobal == true) then
        return "global"
    end

    local owner = entity.createdBy
    local characterInfo = addon
        and addon.db
        and addon.db.global
        and addon.db.global.characterInfo
    local ownerInfo = type(characterInfo) == "table" and characterInfo[owner] or nil
    local classFilename = type(ownerInfo) == "table" and ownerInfo.classFilename or nil
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

local function AssignFlattenedOrders(addon, profile, folders, specId)
    local containers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    local folderChildren = {}
    local looseContainers = {}

    for containerId, container in pairs(containers) do
        if type(container) == "table" then
            local folderId = container.folderId
            local folder = folderId and folders[folderId] or nil
            if type(folder) == "table"
                and GetEntityScopeKey(addon, container, false) == GetEntityScopeKey(addon, folder, true)
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
                    scopeKey = GetEntityScopeKey(addon, container, false),
                    order = GetOrderValue(container, specId, containerId),
                }
            end
        end
    end

    local topItemsByScope = {}
    for folderId, children in pairs(folderChildren) do
        local folder = folders[folderId]
        table_sort(children, CompareOrderedItems)
        local scopeKey = GetEntityScopeKey(addon, folder, true)
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

local function MigrateFoldersIntoGroups(addon, profile)
    if type(profile) ~= "table" then
        return false, 0
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
        return false, 0
    end

    AssignFlattenedOrders(addon, profile, folders, nil)
    for _, specId in ipairs(CollectOrderingSpecIds(profile, folders)) do
        AssignFlattenedOrders(addon, profile, folders, specId)
    end

    local flattenedCount = 0
    for _, container in pairs(containers) do
        if type(container) == "table" and container.folderId ~= nil then
            container.folderId = nil
            flattenedCount = flattenedCount + 1
        end
    end
    for _, group in pairs(groups) do
        if type(group) == "table" and group.folderId ~= nil then
            group.folderId = nil
            flattenedCount = flattenedCount + 1
        end
    end

    profile.folders = nil
    profile.nextFolderId = nil
    return true, flattenedCount
end

function CooldownCompanion:MigrateFoldersIntoGroups(profile)
    return MigrateFoldersIntoGroups(self, profile or (self.db and self.db.profile))
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
    { auraKey = "showAuraDurationSwipeEdge", cooldownKey = "showCooldownSwipeEdge", default = true },
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

local function ClearRetiredAutoAddPrefs(profile)
    if type(profile) ~= "table" or profile.autoAddPrefs == nil then
        return false
    end
    profile.autoAddPrefs = nil
    return true
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
-- Untouched on purpose: pandemic style keys (dormant until Blizzard fixes),
-- stored auraActive trigger clauses (retired-offer pattern), and custom-bar
-- aura entries (the later bars phases own their migration).
local function ClassifyAuraSpellUnit(spellID)
    if not (spellID and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(spellID)) then
        return nil
    end
    return C_Spell.IsSpellHarmful(spellID) and "target" or "player"
end

local function MigrateAuraEntry(self, buttonData, counts)
    -- hide-while-aura-active: LOST in 12.1 (no compliant mechanism).
    if buttonData.hideWhileAuraActive ~= nil then
        buttonData.hideWhileAuraActive = nil
        counts.hideActive = counts.hideActive + 1
    end

    -- Aura-removed sounds: no 12.1 API (gain sounds survive natively).
    local events = type(buttonData.soundAlerts) == "table"
        and type(buttonData.soundAlerts.events) == "table"
        and buttonData.soundAlerts.events or nil
    if events and events.onAuraRemoved ~= nil then
        events.onAuraRemoved = nil
        counts.lossSounds = counts.lossSounds + 1
    end

    -- Bar stack displays: plain numeric text only (pips/segments/overlays
    -- need the numeric stack value, which is secret in combat).
    local auraBar = type(buttonData.auraBar) == "table" and buttonData.auraBar or nil
    if auraBar then
        local touched = false
        local mode = auraBar.mode
        if mode == "stack" or mode == "stack_continuous" or mode == "stack_segmented" or mode == "stack_overlay" then
            auraBar.mode = "stacks"
            touched = true
        end
        if auraBar.stackDisplayMode ~= nil or auraBar.segmentGap ~= nil
            or auraBar.segmentedSmoothing ~= nil or auraBar.maxStacks ~= nil then
            auraBar.stackDisplayMode = nil
            auraBar.segmentGap = nil
            auraBar.segmentedSmoothing = nil
            auraBar.maxStacks = nil
            touched = true
        end
        if touched then
            counts.stackModes = counts.stackModes + 1
        end
    end

    -- Mixed buff/debuff candidate lists are unrepresentable (one slot, one
    -- polarity): keep the majority polarity plus unclassifiable IDs.
    local polarity = nil
    local raw = buttonData.auraSpellID and tostring(buttonData.auraSpellID) or nil
    if raw then
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
            buttonData.auraSpellID = table.concat(rebuilt, ",")
            counts.mixed = counts.mixed + 1
            polarity = keepUnit
        elseif harmfulCount > 0 then
            polarity = "target"
        elseif helpfulCount > 0 then
            polarity = "player"
        end
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

local function MigrateAuraTrackingRebuild(self, profile)
    if type(profile) ~= "table" or profile._cdcAuraRebuildMigrated then return end
    local counts = { hideActive = 0, stackModes = 0, lossSounds = 0, mixed = 0, unit = 0 }
    local groups = profile.groups
    if type(groups) == "table" then
        for _, group in pairs(groups) do
            local buttons = type(group) == "table" and group.buttons or nil
            if type(buttons) == "table" then
                for _, buttonData in ipairs(buttons) do
                    if type(buttonData) == "table" and buttonData.type == "spell"
                        and (buttonData.auraTracking or buttonData.addedAs == "aura") then
                        MigrateAuraEntry(self, buttonData, counts)
                    end
                end
            end
        end
    end
    profile._cdcAuraRebuildMigrated = true
    local dropped = {}
    if counts.hideActive > 0 then dropped[#dropped + 1] = ("hide-while-aura-active (x%d)"):format(counts.hideActive) end
    if counts.stackModes > 0 then dropped[#dropped + 1] = ("bar stack segment displays (x%d)"):format(counts.stackModes) end
    if counts.lossSounds > 0 then dropped[#dropped + 1] = ("aura-removed sounds (x%d)"):format(counts.lossSounds) end
    if counts.mixed > 0 then dropped[#dropped + 1] = ("mixed buff/debuff aura lists trimmed (x%d)"):format(counts.mixed) end
    if counts.unit > 0 then dropped[#dropped + 1] = ("tracked-unit corrections (x%d)"):format(counts.unit) end
    if #dropped > 0 then
        self:Print("Aura tracking updated for 12.1. Adjusted settings with no 12.1 equivalent: "
            .. table.concat(dropped, ", ") .. ".")
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
local function MigrateAuraGlowStyleTable(styleTable, counts)
    if type(styleTable) ~= "table" then return end

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

    -- Pulse speed stores seconds (0.1..2.0); anything larger is a leftover
    -- pixel-scale value regardless of which style it arrived with.
    local speed = rawget(styleTable, "auraGlowSpeed")
    if type(speed) == "number" and speed > 2 then
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

-- Aura-applied sounds now play through the game's aura system, which needs a
-- sound FILE; Blizzard soundkit and text-to-speech selections carried over
-- from the old CC-played path have no file form and would silently never play.
local function MigrateAuraAppliedSoundSelection(buttonData, counts)
    local events = type(buttonData.soundAlerts) == "table"
        and type(buttonData.soundAlerts.events) == "table"
        and buttonData.soundAlerts.events or nil
    local applied = events and events.onAuraApplied
    if type(applied) == "string"
        and (applied == "__blz_tts" or applied:find("^__blz_soundkit:")) then
        events.onAuraApplied = nil
        counts.soundForm = counts.soundForm + 1
    end
end

local function MigrateAuraGlowRebuild(self, profile)
    if type(profile) ~= "table" or profile._cdcAuraGlowMigrated then return end
    local counts = { invert = 0, combatOnly = 0, soundForm = 0 }

    MigrateAuraGlowStyleTable(profile.globalStyle, counts)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                MigrateAuraGlowStyleTable(group.style, counts)
                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            MigrateAuraGlowStyleTable(buttonData.styleOverrides, counts)
                            MigrateAuraAppliedSoundSelection(buttonData, counts)
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

    profile._cdcAuraGlowMigrated = true
    local dropped = {}
    if counts.invert > 0 then dropped[#dropped + 1] = ("glow-while-missing (x%d)"):format(counts.invert) end
    if counts.combatOnly > 0 then dropped[#dropped + 1] = ("combat-only aura glow (x%d)"):format(counts.combatOnly) end
    if counts.soundForm > 0 then dropped[#dropped + 1] = ("aura-applied sounds needing a file-based sound (x%d)"):format(counts.soundForm) end
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

    for _, keys in ipairs({
        { style = "barAuraEffect", size = "barAuraEffectSize", speed = "barAuraEffectSpeed", lines = "barAuraEffectLines" },
        { style = "pandemicBarEffect", size = "pandemicBarEffectSize", speed = "pandemicBarEffectSpeed", lines = "pandemicBarEffectLines" },
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
            if type(speed) == "number" and speed > 2 then
                styleTable[keys.speed] = nil
            end
        end
    end
end

-- Custom-bar entries (the inactive custom-aura-bar path) carry the same
-- effect keys directly on the entry table; canonicalize them too so the
-- feature returns to clean stored values. Entries live either in a shared
-- store ({entries = {id = entry}}) or as a plain id-to-entry map.
local function MigrateCustomBarEntries(settings, counts)
    if type(settings) ~= "table" or type(settings.customBars) ~= "table" then return end
    local customBars = settings.customBars
    local entries = customBars
    if type(customBars.entries) == "table" or type(customBars.order) == "table" then
        entries = customBars.entries
    end
    if type(entries) ~= "table" then return end
    for _, entry in pairs(entries) do
        if type(entry) == "table" then
            MigrateBarAuraEffectTable(entry, counts)
        end
    end
end

local function MigrateBarAuraEffectStyles(self, profile)
    -- Sentinel renamed from _cdcBarAuraGlowMigrated when the pass gained the
    -- size resets and custom-bar traversal, so already-stamped profiles
    -- re-run it once (idempotent).
    if type(profile) ~= "table" or profile._cdcBarAuraEffectMigrated then return end
    profile._cdcBarAuraGlowMigrated = nil
    local counts = { remapped = 0 }

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
    MigrateCustomBarEntries(profile.resourceBars, counts)
    for _, storeKey in ipairs({ "resourceBarsByChar", "resourceBarsByClass" }) do
        local store = profile[storeKey]
        if type(store) == "table" then
            for _, settings in pairs(store) do
                MigrateCustomBarEntries(settings, counts)
            end
        end
    end

    profile._cdcBarAuraEffectMigrated = true
    if counts.remapped > 0 then
        self:Print(("Bar aura effect styles updated to the new renderer (x%d)."):format(counts.remapped))
    end
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
    ClearRetiredAutoAddPrefs(self.db and self.db.profile)
    NormalizePassiveCooldownButtons(self.db and self.db.profile)
    BackfillUnusableVisualOverrideModes(self.db and self.db.profile)
    BackfillAuraDurationSwipeSettings(self.db and self.db.profile, checkpointState and checkpointState.auraDurationSwipe)
    MigrateAuraTrackingRebuild(self, self.db and self.db.profile)
    MigrateAuraGlowRebuild(self, self.db and self.db.profile)
    MigrateLcgGlowStyles(self, self.db and self.db.profile)
    MigrateBarAuraEffectStyles(self, self.db and self.db.profile)
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
    -- data changes nothing and prints nothing).
    local profile = self.db and self.db.profile
    if type(profile) == "table" then
        profile._cdcAuraRebuildMigrated = nil
        profile._cdcAuraGlowMigrated = nil
        profile._cdcLcgGlowMigrated = nil
        profile._cdcBarAuraGlowMigrated = nil
        profile._cdcBarAuraEffectMigrated = nil
    end
end

