--[[
    CooldownCompanion - Config/ProfileImport
    Shared full-profile import and diagnostic restore apply/remap helpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ResetConfigSelection = ST._ResetConfigSelection
local StripCharacterEligibilityFromProfile = ST._StripCharacterEligibilityFromProfile

local PROFILE_IMPORT_METADATA_KEYS = {
    _exporterCharKey = true,
    _characterInfo = true,
    _cdcCharacterEligibilityStripped = true,
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
        looseGroupsByFolderId = {},
        containersByFolderId = {},
    }
    if type(profile) ~= "table" then return index end

    local groups = type(profile.groups) == "table" and profile.groups or {}
    for _, group in pairs(groups) do
        if type(group) == "table" then
            if group.parentContainerId ~= nil then
                AddIndexedEntity(index.panelsByContainerId, group.parentContainerId, group)
            elseif group.folderId ~= nil then
                AddIndexedEntity(index.looseGroupsByFolderId, group.folderId, group)
            end
        end
    end

    local groupContainers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    for containerId, container in pairs(groupContainers) do
        if type(container) == "table" and container.folderId ~= nil then
            AddIndexedEntity(index.containersByFolderId, container.folderId, {
                id = containerId,
                container = container,
            })
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

local function FolderHasPortableEligibility(profile, folderId, folder, eligibilityIndex)
    if EntityHasPortableEligibility(folder) then
        return true
    end

    local indexedContainers = eligibilityIndex and eligibilityIndex.containersByFolderId[folderId]
    if indexedContainers then
        for _, entry in ipairs(indexedContainers) do
            if ContainerHasPortableEligibility(profile, entry.id, entry.container, eligibilityIndex) then
                return true
            end
        end
    elseif not eligibilityIndex then
        local groupContainers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
        for containerId, container in pairs(groupContainers) do
            if type(container) == "table"
                and container.folderId == folderId
                and ContainerHasPortableEligibility(profile, containerId, container)
            then
                return true
            end
        end
    end

    local indexedLooseGroups = eligibilityIndex and eligibilityIndex.looseGroupsByFolderId[folderId]
    if indexedLooseGroups then
        for _, group in ipairs(indexedLooseGroups) do
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
            and group.folderId == folderId
            and not group.parentContainerId
            and EntityHasPortableEligibility(group)
        then
            return true
        end
    end
    return false
end

local function GlobalizePortableCharacterScopedEligibility(profile)
    if type(profile) ~= "table" then return 0 end

    local globalized = 0
    local globalFolders = {}
    local eligibilityIndex = BuildPortableEligibilityIndex(profile)
    local folders = type(profile.folders) == "table" and profile.folders or {}
    for folderId, folder in pairs(folders) do
        if type(folder) == "table"
            and folder.section == "char"
            and FolderHasPortableEligibility(profile, folderId, folder, eligibilityIndex)
        then
            folder.section = "global"
            globalFolders[folderId] = true
            globalized = globalized + 1
        end
    end

    local groupContainers = type(profile.groupContainers) == "table" and profile.groupContainers or {}
    for containerId, container in pairs(groupContainers) do
        if type(container) == "table"
            and container.isGlobal ~= true
            and (globalFolders[container.folderId]
                or ContainerHasPortableEligibility(profile, containerId, container, eligibilityIndex))
        then
            container.isGlobal = true
            globalized = globalized + 1
        end
    end

    local groups = type(profile.groups) == "table" and profile.groups or {}
    for _, group in pairs(groups) do
        if type(group) == "table"
            and not group.parentContainerId
            and group.isGlobal ~= true
            and (globalFolders[group.folderId] or EntityHasPortableEligibility(group))
        then
            group.isGlobal = true
            globalized = globalized + 1
        end
    end

    return globalized
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

    if type(profile.folders) == "table" then
        for _, folder in pairs(profile.folders) do
            if type(folder) == "table"
                and folder.section == "char"
                and ShouldRemapExporterOwned(folder.createdBy, exporterCharKey)
            then
                folder.createdBy = charKey
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
    if type(profile.folders) == "table" then
        for _, folder in pairs(profile.folders) do
            if type(folder) == "table" and folder.section == "char" then
                MarkForeignCharKey(foreignKeys, importerCharInfo, charKey, folder.createdBy)
            end
            MarkForeignAllowlistKeys(foreignKeys, importerCharInfo, charKey, folder)
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
    if type(profile.folders) == "table" then
        for _, folder in pairs(profile.folders) do
            if type(folder) == "table" and folder.createdBy and renames[folder.createdBy] then
                folder.createdBy = renames[folder.createdBy]
            end
            RenameAllowlist(folder)
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
    strippedCharacterEligibility = strippedCharacterEligibility + (StripCharacterEligibilityFromProfile
        and StripCharacterEligibilityFromProfile(db.profile)
        or 0)

    if ResetConfigSelection then
        ResetConfigSelection(true)
    end

    local charKey = db.keys and db.keys.char
    RemapCurrentCharacterEntities(db.profile, charKey, exporterCharKey)
    if type(exporterCharKey) == "string" and exporterCharKey ~= ""
        and type(charKey) == "string" and charKey ~= ""
    then
        ApplyCharacterRenames(db.profile, { [exporterCharKey] = charKey })
    end
    RemapCharacterScopedStores(db.profile, charKey, exporterCharKey)

    if options.renameForeignCharacters then
        local importerCharInfo = db.global and db.global.characterInfo or {}
        RenameForeignCharacters(db.profile, charKey, exportedCharInfo, importerCharInfo)
    end
    local globalizedEligibilityImports = GlobalizePortableCharacterScopedEligibility(db.profile)

    self._resourceBarImportCharacterInfo = exportedCharInfo

    if self.ClearMigrationSentinels then
        self:ClearMigrationSentinels()
    end
    local migrationsOk = not self.RunAllMigrations or self:RunAllMigrations()
    self._resourceBarImportCharacterInfo = nil
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
    if globalizedEligibilityImports > 0 and self.Print then
        self:Print("Class, specialization, and hero talent eligibility were preserved in Global Groups.")
    end

    return true
end

ST._ApplyFullProfileImport = function(data, options)
    return CooldownCompanion:ApplyFullProfileImport(data, options)
end
