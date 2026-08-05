--[[
    CooldownCompanion - Config/ProfileImport
    Shared full-profile import and diagnostic restore apply/remap helpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ResetConfigSelection = ST._ResetConfigSelection
local StripCharacterEligibilityFromProfile = ST._StripCharacterEligibilityFromProfile
local StripLocalPanelMetadataFromProfile = ST._StripLocalPanelMetadataFromProfile

local PROFILE_IMPORT_METADATA_KEYS = {
    _exporterCharKey = true,
    _characterInfo = true,
    _cdcCharacterEligibilityStripped = true,
    resourceBarMigration = true,
}

local SCOPED_STORE_KEYS = {
    "castBarByChar",
    "frameAnchoringByChar",
}

local function IsUnsupportedImportPayload(data, dataLabel)
    if CooldownCompanion.IsUnsupportedImportPayload
        and CooldownCompanion:IsUnsupportedImportPayload(data)
    then
        if CooldownCompanion.NotifyLegacySupportCutoff then
            CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
        end
        return true
    end
    return false
end

local function ShouldRemapExporterOwned(createdBy, exporterCharKey)
    return exporterCharKey == nil or createdBy == exporterCharKey
end

local function HasPortableEligibilityMap(map)
    if type(map) ~= "table" then
        return map ~= nil
    end
    for _, enabled in pairs(map) do
        if enabled == true then
            return true
        end
    end
    return false
end

local function EntityHasPortableEligibility(entity)
    if type(entity) ~= "table" then return false end
    if HasPortableEligibilityMap(entity.specs)
        or HasPortableEligibilityMap(entity.heroTalents)
    then
        return true
    end

    local loadConditions = entity.loadConditions
    return type(loadConditions) == "table"
        and (HasPortableEligibilityMap(loadConditions.classAllowlist)
            or HasPortableEligibilityMap(loadConditions.specAllowlist))
end

local function AddIndexedEntity(indexMap, key, entity)
    if key == nil then return end
    local bucket = indexMap[key]
    if not bucket then
        bucket = {}
        indexMap[key] = bucket
    end
    bucket[#bucket + 1] = entity
end

local function BuildPortableEligibilityIndex(profile)
    local index = {
        panelsByContainerId = {},
    }
    if type(profile) ~= "table" then return index end

    local groups = type(profile.groups) == "table" and profile.groups or {}
    for _, group in pairs(groups) do
        if type(group) == "table" then
            if group.parentContainerId ~= nil then
                AddIndexedEntity(index.panelsByContainerId, group.parentContainerId, group)
            end
        end
    end

    return index
end

local function ContainerHasPortableEligibility(profile, containerId, container, eligibilityIndex)
    if EntityHasPortableEligibility(container) then
        return true
    end

    local indexedGroups = eligibilityIndex and eligibilityIndex.panelsByContainerId[containerId]
    if indexedGroups then
        for _, group in ipairs(indexedGroups) do
            if EntityHasPortableEligibility(group) then
                return true
            end
        end
        return false
    elseif eligibilityIndex then
        return false
    end

    local groups = type(profile.groups) == "table" and profile.groups or {}
    for _, group in pairs(groups) do
        if type(group) == "table"
            and group.parentContainerId == containerId
            and EntityHasPortableEligibility(group)
        then
            return true
        end
    end
    return false
end

-- Landing is decided by CONTENT, not by owner: the exporter remap can hand
-- another class's groups to the importer (a profile exported on an alt),
-- and spec allowlists can appear on entities that are otherwise
-- single-class. Every piece of portable eligibility maps to the class it
-- belongs to; an entity tree whose eligibility resolves to exactly one
-- class lands in that class's section.

local VIEW_TRAIT_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID) or -3
-- Upper bound for class-ID scans, matching Core/GroupOperations.lua and
-- Core/ScopedSettings.lua (both file-local there).
local CLASS_SCAN_LIMIT = 30

-- Foreign specs return nothing against the player's own config; the shared
-- view loadout resolves them (same pattern as TalentPicker).
local function GetSpecHeroSubTreeIDs(specID, playerLevel)
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specID)
    if subTreeIDs and #subTreeIDs > 0 then
        return subTreeIDs
    end
    if not (C_ClassTalents.InitializeViewLoadout and C_Traits and C_Traits.GetConfigInfo) then
        return subTreeIDs
    end
    if not playerLevel then
        return subTreeIDs
    end
    C_ClassTalents.InitializeViewLoadout(specID, playerLevel)
    if C_Traits.GetConfigInfo(VIEW_TRAIT_CONFIG_ID) then
        subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(VIEW_TRAIT_CONFIG_ID, specID)
    end
    return subTreeIDs
end

-- subTreeID -> classID for every hero talent the client will report. Filled
-- by one full sweep and never by a partial one: the sweep sees every class's
-- subtrees anyway, so recording only the id being asked about would re-pay
-- ~100 view-loadout builds per new id.
--
-- An INCOMPLETE sweep is not cached either, and the completeness test is per
-- class rather than "did anything at all resolve". The importing player's own
-- class resolves against their active config from login, so it alone is
-- enough to make the map non-empty while every FOREIGN class still failed --
-- caching that pinned "not a hero talent" onto every foreign subtree for the
-- session, and each one silently sent its group to Global. A class counts as
-- resolved when any of its specs yields a subtree, so one spec without hero
-- talents cannot block the cache forever.
--
-- The sweep is attempted at most once per import: it costs ~40 view-loadout
-- builds, and without this it re-ran per hero-talent key on every container
-- and panel whenever it was failing. Retrying is what the next import is for.
local heroTalentClassCache = nil
local heroTalentSweepAttempted = false

local function ResetHeroTalentSweepAttempt()
    heroTalentSweepAttempted = false
end

local function EnsureHeroTalentClassMap()
    if heroTalentClassCache then
        return heroTalentClassCache
    end
    if heroTalentSweepAttempted then
        return nil
    end
    heroTalentSweepAttempted = true
    if not (C_ClassTalents
        and C_ClassTalents.GetHeroTalentSpecsForClassSpec
        and C_SpecializationInfo
        and C_SpecializationInfo.GetNumSpecializationsForClassID
        and GetSpecializationInfoForClassID) then
        return nil
    end
    -- Constant for the whole sweep; reading it per spec was ~40 identical
    -- calls, and resolving it here lets the sweep bail before paying any.
    local playerLevel = UnitLevel and UnitLevel("player") or nil
    if playerLevel and playerLevel < 1 then
        playerLevel = nil
    end
    local map = {}
    local complete = true
    for classID = 1, CLASS_SCAN_LIMIT do
        local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
        -- A classID past the real range reports no specs and is not a gap.
        local classResolved = numSpecs == 0
        for specIndex = 1, numSpecs do
            local specID = GetSpecializationInfoForClassID(classID, specIndex)
            local subTreeIDs = specID and GetSpecHeroSubTreeIDs(specID, playerLevel)
            for _, availableSubTreeID in ipairs(subTreeIDs or {}) do
                local numericSubTreeID = tonumber(availableSubTreeID)
                if numericSubTreeID then
                    map[numericSubTreeID] = classID
                    classResolved = true
                end
            end
        end
        if not classResolved then
            complete = false
        end
    end
    if not complete then
        return nil
    end
    heroTalentClassCache = map
    return map
end

local function GetHeroTalentClassID(subTreeID)
    subTreeID = tonumber(subTreeID)
    if not subTreeID then return nil end
    local map = EnsureHeroTalentClassMap()
    return map and map[subTreeID] or nil
end

local function GetSpecClassID(specID)
    specID = tonumber(specID)
    if not (specID and C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID) then
        return nil
    end
    return C_SpecializationInfo.GetClassIDFromSpecID(specID)
end

local function AccumulateMapContentClasses(map, acc, resolveClassID)
    if type(map) ~= "table" then return end
    for key, enabled in pairs(map) do
        if enabled == true then
            local classID = resolveClassID(key)
            if classID then
                acc.classes[classID] = true
            else
                acc.unresolvable = true
            end
        end
    end
end

local function AccumulateEntityContentClasses(entity, acc)
    if type(entity) ~= "table" then return end
    -- Classify the DOMINANT spec gate, not specs and allowlist separately:
    -- when an entity carries both, only the allowlist can actually load, so
    -- unioning them would invent classes the entity never runs on.
    local specs = CooldownCompanion.GetEntitySpecRestriction
        and CooldownCompanion:GetEntitySpecRestriction(entity)
        or entity.specs
    AccumulateMapContentClasses(specs, acc, GetSpecClassID)
    AccumulateMapContentClasses(entity.heroTalents, acc, GetHeroTalentClassID)
    local loadConditions = entity.loadConditions
    if type(loadConditions) == "table" then
        -- Class allowlists are the Global-section vocabulary; entities
        -- carrying one keep the global landing.
        if HasPortableEligibilityMap(loadConditions.classAllowlist) then
            acc.unresolvable = true
        end
    end
end

local function GetSingleContentClassID(acc)
    if acc.unresolvable then return nil end
    local single
    for classID in pairs(acc.classes) do
        if single then return nil end
        single = classID
    end
    return single
end

-- The class section reads entity.specs, so a spec allowlist reaching a
-- class-scoped landing is canonicalized into it. Delegated to the core
-- helper, which collapses to the DOMINANT gate rather than the union: the
-- allowlist is a second required gate at runtime, so unioning it into specs
-- and deleting it would silently widen the entity onto specs it was gated
-- off, and would turn an explicit-empty ("never eligible") allowlist into
-- no restriction at all.
local function FoldSpecAllowlistIntoSpecs(entity)
    if CooldownCompanion.CanonicalizeEntitySpecRestriction then
        CooldownCompanion:CanonicalizeEntitySpecRestriction(entity)
    end
end

local function GetClassNameInfo(classID)
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" then
            return classInfo.className, classInfo.classFile
        end
    end
    if GetClassInfo then
        return GetClassInfo(classID)
    end
    return nil, nil
end

-- Resolve the registry character key a class-scoped landing hangs from
-- (class sections resolve createdBy through db.global.characterInfo).
-- LOOKUP ONLY — never writes. Any already-registered character of the class
-- is preferred, including the numbered placeholders ("Mage 1"/"Mage 2") the
-- foreign-character rename pass mints, so a landing reuses what that pass
-- just created instead of adding a bare-name duplicate beside it.
local function FindClassLandingCharKey(characterInfo, classID)
    if type(characterInfo) ~= "table" then return nil end
    local className = GetClassNameInfo(classID)
    if className then
        local existing = characterInfo[className]
        if type(existing) == "table" and tonumber(existing.classID) == classID then
            return className
        end
    end
    for charKey, info in pairs(characterInfo) do
        if type(info) == "table" and tonumber(info.classID) == classID then
            return charKey
        end
    end
    return nil
end

-- Registry write, made only once a landing is actually committed. Returns
-- nil when the class cannot be named, which keeps the caller on Global
-- rather than inventing an unnamed owner.
local function EnsureClassLandingCharKey(characterInfo, classID)
    local existingKey = FindClassLandingCharKey(characterInfo, classID)
    if existingKey then return existingKey end
    if type(characterInfo) ~= "table" then return nil end
    local className, classFile = GetClassNameInfo(classID)
    if not (className and classFile) then return nil end
    characterInfo[className] = {
        classFilename = classFile,
        classID = classID,
    }
    return className
end

local function ResolvePortableEligibilityLanding(profile)
    if type(profile) ~= "table" then return 0, 0 end

    -- One sweep attempt per import: allow a retry now, then let the sweep
    -- itself refuse to repeat within this pass.
    ResetHeroTalentSweepAttempt()

    local characterInfo = CooldownCompanion
        and CooldownCompanion.db
        and CooldownCompanion.db.global
        and CooldownCompanion.db.global.characterInfo
        or nil

    local globalized, rehomed = 0, 0
    local eligibilityIndex = BuildPortableEligibilityIndex(profile)

    -- Lands one entity tree (a container plus its panels, or a parentless
    -- group alone). Single-class content stays class-scoped under a
    -- matching owner; everything else moves to Global.
    local function LandEntityTree(entity, acc, foldEntities)
        local landingClassID = GetSingleContentClassID(acc)
        if landingClassID then
            local ownerInfo = type(entity.createdBy) == "string"
                and characterInfo
                and characterInfo[entity.createdBy]
                or nil
            local ownerClassID = type(ownerInfo) == "table" and tonumber(ownerInfo.classID) or nil
            if ownerClassID == landingClassID then
                for _, folded in ipairs(foldEntities) do
                    FoldSpecAllowlistIntoSpecs(folded)
                end
                return
            end
            local landingKey = EnsureClassLandingCharKey(characterInfo, landingClassID)
            if landingKey then
                entity.createdBy = landingKey
                rehomed = rehomed + 1
                for _, folded in ipairs(foldEntities) do
                    FoldSpecAllowlistIntoSpecs(folded)
                end
                return
            end
        end
        entity.isGlobal = true
        globalized = globalized + 1
    end

    local groupContainers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    for containerId, container in pairs(groupContainers) do
        if type(container) == "table"
            and container.isGlobal ~= true
            and ContainerHasPortableEligibility(profile, containerId, container, eligibilityIndex)
        then
            local acc = { classes = {} }
            local foldEntities = { container }
            AccumulateEntityContentClasses(container, acc)
            -- eligibilityIndex is always the table BuildPortableEligibilityIndex
            -- returned above; a container with no panels simply has no bucket.
            local containerPanels = eligibilityIndex.panelsByContainerId[containerId]
            if containerPanels then
                for _, panel in ipairs(containerPanels) do
                    AccumulateEntityContentClasses(panel, acc)
                    foldEntities[#foldEntities + 1] = panel
                end
            end
            LandEntityTree(container, acc, foldEntities)
        end
    end

    local groups = type(profile.groups) == "table" and profile.groups or {}
    for _, group in pairs(groups) do
        if type(group) == "table"
            and not group.parentContainerId
            and group.isGlobal ~= true
            and EntityHasPortableEligibility(group)
        then
            local acc = { classes = {} }
            AccumulateEntityContentClasses(group, acc)
            LandEntityTree(group, acc, { group })
        end
    end

    return globalized, rehomed
end

local function RemapCurrentCharacterEntities(profile, charKey, exporterCharKey)
    if type(profile) ~= "table" or type(charKey) ~= "string" or charKey == "" then
        return
    end

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table"
                and not group.isGlobal
                and ShouldRemapExporterOwned(group.createdBy, exporterCharKey)
            then
                group.createdBy = charKey
            end
        end
    end

    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table"
                and not container.isGlobal
                and ShouldRemapExporterOwned(container.createdBy, exporterCharKey)
            then
                container.createdBy = charKey
            end
        end
    end

end

local function CountScopedStoreBuckets(store)
    local count = 0
    local onlyKey = nil
    for charKey, settings in pairs(store) do
        if type(settings) == "table" then
            count = count + 1
            onlyKey = charKey
        end
    end
    return count, onlyKey
end

local function ResolveScopedStoreSourceKey(store, charKey, exporterCharKey)
    if type(store) ~= "table" or type(charKey) ~= "string" or charKey == "" then
        return nil
    end

    if type(exporterCharKey) == "string" and exporterCharKey ~= "" then
        if type(store[exporterCharKey]) == "table" then
            return exporterCharKey
        end
        return nil
    end

    local count, onlyKey = CountScopedStoreBuckets(store)
    if count == 1 then
        return onlyKey
    end
    return nil
end

local function RemapScopedStore(profile, storeKey, charKey, exporterCharKey, remappedSourceKeys)
    local store = type(profile) == "table" and profile[storeKey] or nil
    if type(store) ~= "table" then
        return
    end

    local sourceKey = ResolveScopedStoreSourceKey(store, charKey, exporterCharKey)
    if not sourceKey then
        return
    end

    remappedSourceKeys[sourceKey] = true
    if sourceKey ~= charKey then
        store[charKey] = store[sourceKey]
        store[sourceKey] = nil
    end
end

local function RemapScopedStoreSeenCharacters(profile, charKey, exporterCharKey, remappedSourceKeys)
    local seen = type(profile) == "table" and profile.legacyScopedBarSeenCharacters or nil
    if type(seen) ~= "table" or type(charKey) ~= "string" or charKey == "" then
        return
    end

    if type(exporterCharKey) == "string" and exporterCharKey ~= "" then
        remappedSourceKeys[exporterCharKey] = true
    end

    local sawRemap = false
    for sourceKey in pairs(remappedSourceKeys) do
        if sourceKey ~= charKey then
            seen[sourceKey] = nil
            sawRemap = true
        end
    end
    if sawRemap then
        seen[charKey] = true
    end
end

local function RemapCharacterScopedStores(profile, charKey, exporterCharKey)
    local remappedSourceKeys = {}
    for _, storeKey in ipairs(SCOPED_STORE_KEYS) do
        RemapScopedStore(profile, storeKey, charKey, exporterCharKey, remappedSourceKeys)
    end
    RemapScopedStoreSeenCharacters(profile, charKey, exporterCharKey, remappedSourceKeys)
end

local function MarkForeignCharKey(foreignKeys, importerCharInfo, charKey, createdBy)
    if not createdBy or createdBy == charKey then
        return
    end
    if not importerCharInfo[createdBy] and not foreignKeys[createdBy] then
        foreignKeys[createdBy] = true
    end
end

local function MarkForeignAllowlistKeys(foreignKeys, importerCharInfo, charKey, entity)
    local allowlist = type(entity) == "table"
        and type(entity.loadConditions) == "table"
        and entity.loadConditions.characterAllowlist
        or nil
    if type(allowlist) ~= "table" then
        return
    end
    for allowlistKey, enabled in pairs(allowlist) do
        if enabled == true then
            MarkForeignCharKey(foreignKeys, importerCharInfo, charKey, allowlistKey)
        end
    end
end

local function CollectForeignCharacterKeys(profile, importerCharInfo, charKey)
    local foreignKeys = {}
    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" and not group.isGlobal then
                MarkForeignCharKey(foreignKeys, importerCharInfo, charKey, group.createdBy)
            end
            MarkForeignAllowlistKeys(foreignKeys, importerCharInfo, charKey, group)
        end
    end
    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table" and not container.isGlobal then
                MarkForeignCharKey(foreignKeys, importerCharInfo, charKey, container.createdBy)
            end
            MarkForeignAllowlistKeys(foreignKeys, importerCharInfo, charKey, container)
        end
    end
    return foreignKeys
end

local function BuildForeignCharacterRenames(foreignKeys, exportedCharInfo, importerCharInfo)
    local classCounts = {}
    local classEntries = {}
    for foreignKey in pairs(foreignKeys) do
        local info = type(exportedCharInfo) == "table" and exportedCharInfo[foreignKey] or nil
        local classID = info and info.classID
        local classInfo = classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo
            and C_CreatureInfo.GetClassInfo(classID)
            or nil
        local className = type(classInfo) == "table" and classInfo.className
            or (classID and GetClassInfo and GetClassInfo(classID))
            or "Character"
        classCounts[className] = (classCounts[className] or 0) + 1
        classEntries[foreignKey] = {
            className = className,
            classFilename = info and info.classFilename,
            classID = classID,
        }
    end

    local renames = {}
    local classCounters = {}
    for foreignKey in pairs(foreignKeys) do
        local entry = classEntries[foreignKey]
        local placeholder
        if classCounts[entry.className] == 1 then
            placeholder = entry.className
        else
            classCounters[entry.className] = (classCounters[entry.className] or 0) + 1
            placeholder = entry.className .. " " .. classCounters[entry.className]
        end
        renames[foreignKey] = placeholder
        if entry.classFilename and entry.classID then
            importerCharInfo[placeholder] = {
                classFilename = entry.classFilename,
                classID = entry.classID,
            }
        end
    end

    return renames
end

local function ApplyCharacterRenames(profile, renames)
    local function RenameAllowlist(entity)
        local allowlist = type(entity) == "table"
            and type(entity.loadConditions) == "table"
            and entity.loadConditions.characterAllowlist
            or nil
        if type(allowlist) ~= "table" then
            return
        end
        for oldKey, newKey in pairs(renames or {}) do
            if allowlist[oldKey] == true then
                allowlist[newKey] = true
                allowlist[oldKey] = nil
            end
        end
        if not next(allowlist) then
            entity.loadConditions.characterAllowlist = nil
        end
    end

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" and group.createdBy and renames[group.createdBy] then
                group.createdBy = renames[group.createdBy]
            end
            RenameAllowlist(group)
        end
    end
    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table" and container.createdBy and renames[container.createdBy] then
                container.createdBy = renames[container.createdBy]
            end
            RenameAllowlist(container)
        end
    end
end

local function RenameForeignCharacters(profile, charKey, exportedCharInfo, importerCharInfo)
    if type(profile) ~= "table" or type(charKey) ~= "string" or charKey == "" then
        return
    end

    if type(importerCharInfo) ~= "table" then
        return
    end

    local foreignKeys = CollectForeignCharacterKeys(profile, importerCharInfo, charKey)
    if not next(foreignKeys) then
        return
    end

    local renames = BuildForeignCharacterRenames(foreignKeys, exportedCharInfo, importerCharInfo)
    ApplyCharacterRenames(profile, renames)
end

local function CopyProfileDataIntoActiveProfile(activeProfile, data)
    wipe(activeProfile)
    for key, value in pairs(data) do
        if not PROFILE_IMPORT_METADATA_KEYS[key] then
            activeProfile[key] = value
        end
    end
end

function CooldownCompanion:ApplyFullProfileImport(data, options)
    if type(data) ~= "table" then
        return false
    end

    options = options or {}
    if IsUnsupportedImportPayload(data, options.dataLabel or "profile import") then
        return false
    end

    local db = self.db
    if type(db) ~= "table" or type(db.profile) ~= "table" then
        return false
    end

    local exporterCharKey = options.exporterCharKey
    if exporterCharKey == nil then
        exporterCharKey = data._exporterCharKey
    end
    local exportedCharInfo = options.exportedCharInfo
    if exportedCharInfo == nil then
        exportedCharInfo = data._characterInfo
    end

    local strippedCharacterEligibility = tonumber(data._cdcCharacterEligibilityStripped) or 0
    CopyProfileDataIntoActiveProfile(db.profile, data)
    if StripLocalPanelMetadataFromProfile then
        StripLocalPanelMetadataFromProfile(db.profile)
    end
    strippedCharacterEligibility = strippedCharacterEligibility + (StripCharacterEligibilityFromProfile
        and StripCharacterEligibilityFromProfile(db.profile)
        or 0)
    if self.MigrateFoldersIntoGroups then
        -- Legacy backups are flattened before any ownership remapping so all
        -- later import policy operates on the supported Group-only model.
        self:MigrateFoldersIntoGroups(db.profile, exportedCharInfo)
    end

    if ResetConfigSelection then
        ResetConfigSelection(true)
    end

    local charKey = db.keys and db.keys.char

    -- "The exporter's groups become the importer's" only holds when the two
    -- characters share a class. A string exported on an alt of another
    -- class keeps the exporter as a foreign character instead, so their
    -- groups land in that class's section (the rename pass gives the
    -- exporter a class placeholder). Restore flow only: the diagnostic
    -- path keeps original ownership fidelity and skips renames entirely.
    local exporterIsForeignClass = false
    if options.renameForeignCharacters then
        local exporterInfo = type(exportedCharInfo) == "table"
            and type(exporterCharKey) == "string"
            and exportedCharInfo[exporterCharKey]
            or nil
        local exporterClassID = type(exporterInfo) == "table" and tonumber(exporterInfo.classID) or nil
        local _, _, importerClassID = UnitClass("player")
        exporterIsForeignClass = exporterClassID ~= nil
            and importerClassID ~= nil
            and exporterClassID ~= importerClassID
    end

    if not exporterIsForeignClass then
        RemapCurrentCharacterEntities(db.profile, charKey, exporterCharKey)
        if type(exporterCharKey) == "string" and exporterCharKey ~= ""
            and type(charKey) == "string" and charKey ~= ""
        then
            ApplyCharacterRenames(db.profile, { [exporterCharKey] = charKey })
        end
        -- Character-scoped stores follow the same rule as the groups: a
        -- same-class exporter is "you on another character", so their cast
        -- bar and frame anchoring come along. A foreign-class exporter stays
        -- a separate character throughout — adopting their cast bar while
        -- none of their groups load for you is a state nothing intends.
        RemapCharacterScopedStores(db.profile, charKey, exporterCharKey)
    end

    if options.renameForeignCharacters then
        local importerCharInfo = db.global and db.global.characterInfo or {}
        RenameForeignCharacters(db.profile, charKey, exportedCharInfo, importerCharInfo)
    end
    local globalizedEligibilityImports, rehomedEligibilityImports = ResolvePortableEligibilityLanding(db.profile)

    self._resourceBarImportCharacterInfo = exportedCharInfo
    self._resourceBarImportExporterCharKey = exporterCharKey

    if self.ClearMigrationSentinels then
        self:ClearMigrationSentinels()
    end
    local migrationsOk = not self.RunAllMigrations or self:RunAllMigrations()
    self._resourceBarImportCharacterInfo = nil
    self._resourceBarImportExporterCharKey = nil
    if not migrationsOk then
        return false
    end
    if self.SanitizeCursorAnchorPolicy then
        self:SanitizeCursorAnchorPolicy(db.profile)
    end

    if self.RefreshConfigPanel then
        self:RefreshConfigPanel()
    end
    if self.RefreshAllGroups then
        self:RefreshAllGroups()
    end
    if self.EvaluateBarsAndFramesRuntime then
        self:EvaluateBarsAndFramesRuntime(options.runtimeReason or "profile-import")
    end
    if strippedCharacterEligibility > 0 and self.Print then
        self:Print("Character eligibility is local and was not imported.")
    end
    if rehomedEligibilityImports > 0 and self.Print then
        self:Print("Imported groups were sorted into class sections by their eligibility (x" .. rehomedEligibilityImports .. ").")
    end
    if globalizedEligibilityImports > 0 and self.Print then
        self:Print("Class, specialization, and hero talent eligibility were preserved in Global Groups.")
    end

    return true
end

ST._ApplyFullProfileImport = function(data, options)
    return CooldownCompanion:ApplyFullProfileImport(data, options)
end

-- The whole landing DECISION, shared with the group/setup import door
-- (Popups.lua) so both doors apply one policy rather than two assemblies of
-- the same primitives.
--
--   entities     the tree to judge (a container plus its panels, or one group)
--   ownerClassID the class the tree would land under if left alone; nil when
--                that cannot be determined, which keeps the current owner
--                rather than guessing a re-home.
--
-- Returns (landingCharKey, mustGlobalize):
--   nil,   false -> keep the current owner; the tree already lands right
--   key,   false -> re-home onto key (a registry entry is created if needed)
--   nil,   true  -> the content cannot be represented in any class section
--
-- Callers must canonicalize the tree's spec restrictions whenever they do
-- NOT globalize; ST._FoldSpecAllowlistIntoSpecs does that per entity.
ST._ResolveEntityTreeLanding = function(entities, ownerClassID)
    local acc = { classes = {} }
    for _, entity in ipairs(entities or {}) do
        AccumulateEntityContentClasses(entity, acc)
    end
    local landingClassID = GetSingleContentClassID(acc)
    if not landingClassID then
        return nil, true
    end
    if ownerClassID == nil or ownerClassID == landingClassID then
        return nil, false
    end
    local characterInfo = CooldownCompanion
        and CooldownCompanion.db
        and CooldownCompanion.db.global
        and CooldownCompanion.db.global.characterInfo
        or nil
    local landingKey = EnsureClassLandingCharKey(characterInfo, landingClassID)
    if landingKey then
        return landingKey, false
    end
    return nil, true
end

-- Import doors call this ONCE before they start landing entities, never per
-- entity: it re-arms a hero-talent sweep that a previous import found not
-- ready, and re-arming inside the per-entity loop is exactly the repetition
-- the attempt flag exists to stop.
ST._ResetHeroTalentSweepAttempt = ResetHeroTalentSweepAttempt

ST._FoldSpecAllowlistIntoSpecs = FoldSpecAllowlistIntoSpecs
