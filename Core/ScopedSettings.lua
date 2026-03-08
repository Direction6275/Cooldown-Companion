local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local CopyTable = CopyTable
local pairs = pairs
local next = next
local rawget = rawget
local tonumber = tonumber
local type = type
local sort = table.sort

local SCOPED_BAR_SYSTEMS = {
    resourceBars = {
        storeKey = "resourceBarsByChar",
        seedKey = "legacyResourceBarsSeed",
        legacyKey = "resourceBars",
    },
    castBar = {
        storeKey = "castBarByChar",
        seedKey = "legacyCastBarSeed",
        legacyKey = "castBar",
    },
    frameAnchoring = {
        storeKey = "frameAnchoringByChar",
        seedKey = "legacyFrameAnchoringSeed",
        legacyKey = "frameAnchoring",
    },
}

local function GetScopedBarSystemSpec(systemKey)
    return SCOPED_BAR_SYSTEMS[systemKey]
end

local function CopySubsystemDefaults(defaultKey)
    local defaults = ST._defaults and ST._defaults.profile and ST._defaults.profile[defaultKey]
    if type(defaults) ~= "table" then
        return {}
    end
    return CopyTable(defaults)
end

local function CloneSettingValue(value)
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function EnsureScopedBarSystemStore(profile, storeKey)
    local store = rawget(profile, storeKey)
    if type(store) ~= "table" then
        store = {}
        profile[storeKey] = store
    end
    return store
end

local function CaptureLegacyScopedBarSystemSeed(profile, systemSpec)
    local seed = rawget(profile, systemSpec.seedKey)
    if type(seed) == "table" then
        return seed
    end

    local legacy = rawget(profile, systemSpec.legacyKey)
    if type(legacy) ~= "table" then
        return nil
    end

    seed = CopyTable(legacy)
    profile[systemSpec.seedKey] = seed
    return seed
end

local function ProfileHasLegacyScopedBarData(profile)
    if type(profile) ~= "table" then
        return false
    end

    for _, systemSpec in pairs(SCOPED_BAR_SYSTEMS) do
        if type(rawget(profile, systemSpec.seedKey)) == "table"
            or type(rawget(profile, systemSpec.legacyKey)) == "table" then
            return true
        end
    end

    return false
end

local function ProfileHasAnyScopedBarBuckets(profile)
    if type(profile) ~= "table" then
        return false
    end

    for _, systemSpec in pairs(SCOPED_BAR_SYSTEMS) do
        local store = rawget(profile, systemSpec.storeKey)
        if type(store) == "table" and next(store) ~= nil then
            return true
        end
    end

    return false
end

local function MarkLegacyScopedBarSeenCharacter(snapshot, charKey)
    if type(snapshot) ~= "table" or type(charKey) ~= "string" or charKey == "" or charKey == "migrated" then
        return
    end
    snapshot[charKey] = true
end

local function GetCurrentClassSpecInfo()
    local _, _, classID = UnitClass("player")
    if not classID then
        return nil, nil
    end

    local specIDs = {}
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for i = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[specID] = true
        end
    end

    local currentSpecID = nil
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    return specIDs, currentSpecID
end

-- Keep these resource mappings aligned with OtherBars/ResourceBar.lua.
local CLASS_RESOURCES_BY_CLASS_ID = {
    [1]  = { 1 },
    [2]  = { 9, 0 },
    [3]  = { 2 },
    [4]  = { 4, 3 },
    [5]  = { 0 },
    [6]  = { 5, 6 },
    [7]  = { 0 },
    [8]  = { 0 },
    [9]  = { 7, 0 },
    [10] = { 0 },
    [11] = { 0 },
    [12] = { 17 },
    [13] = { 19, 0 },
}

local SPEC_RESOURCES_BY_SPEC_ID = {
    [258] = { 13, 0 },
    [262] = { 11, 0 },
    [263] = { 100, 0 },
    [62]  = { 16, 0 },
    [269] = { 12, 3 },
    [268] = { 3 },
    [581] = { 17 },
}

local DRUID_FORM_RESOURCES = {
    { 1 },
    { 4, 3 },
    { 8 },
}

local function BuildResourceSet(resourceList, result)
    if type(resourceList) ~= "table" or type(result) ~= "table" then
        return result
    end

    for _, powerType in pairs(resourceList) do
        local numericPowerType = tonumber(powerType)
        if numericPowerType then
            result[numericPowerType] = true
        end
    end

    return result
end

local function GetCurrentClassApplicableResourceSet()
    local _, _, classID = UnitClass("player")
    if not classID then
        return {}
    end

    local resourceSet = {}
    BuildResourceSet(CLASS_RESOURCES_BY_CLASS_ID[classID], resourceSet)

    if classID == 11 then
        for _, resourceList in pairs(DRUID_FORM_RESOURCES) do
            BuildResourceSet(resourceList, resourceSet)
        end
    end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for i = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            BuildResourceSet(SPEC_RESOURCES_BY_SPEC_ID[specID], resourceSet)
        end
    end

    return resourceSet
end

local function CopyResourceAuraOverlayColor(color)
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        return nil
    end
    return { color[1], color[2], color[3] }
end

local function HasLegacyResourceAuraOverlayData(resource)
    if type(resource) ~= "table" then
        return false
    end
    return resource.auraColorSpellID ~= nil
        or resource.auraActiveColor ~= nil
        or resource.auraColorTrackingMode ~= nil
        or resource.auraColorMaxStacks ~= nil
end

local function GetEffectiveResourceAuraOverlayEnabled(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    if type(resource.auraOverlayEntries) == "table" then
        for _, entry in pairs(resource.auraOverlayEntries) do
            if type(entry) == "table" then
                return true
            end
        end
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function ClearLegacyResourceAuraOverlayFields(resource)
    if type(resource) ~= "table" then
        return
    end
    resource.auraColorSpellID = nil
    resource.auraActiveColor = nil
    resource.auraColorTrackingMode = nil
    resource.auraColorMaxStacks = nil
end

local function NormalizeResourceAuraOverlayEntriesForCurrentClass(settings)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end

    local allowedSpecIDs, currentSpecID = GetCurrentClassSpecInfo()
    if type(allowedSpecIDs) ~= "table" then
        return
    end

    for _, resource in pairs(settings.resources) do
        if type(resource) == "table" then
            local explicitEnabled = nil
            if type(resource.auraOverlayEnabled) == "boolean" then
                explicitEnabled = resource.auraOverlayEnabled
            end

            local effectiveEnabled = GetEffectiveResourceAuraOverlayEnabled(resource)
            local filteredEntries = nil

            if type(resource.auraOverlayEntries) == "table" then
                for key, entry in pairs(resource.auraOverlayEntries) do
                    local numericSpecID = tonumber(key)
                    if numericSpecID and allowedSpecIDs[numericSpecID] and type(entry) == "table" then
                        if not filteredEntries then
                            filteredEntries = {}
                        end
                        filteredEntries[numericSpecID] = CopyTable(entry)
                    end
                end
            end

            resource.auraOverlayEntries = filteredEntries
            if filteredEntries then
                ClearLegacyResourceAuraOverlayFields(resource)
            end

            local hasLegacyData = HasLegacyResourceAuraOverlayData(resource)
            if not filteredEntries and hasLegacyData and currentSpecID then
                resource.auraOverlayEntries = {
                    [currentSpecID] = {
                        auraColorSpellID = tonumber(resource.auraColorSpellID) or nil,
                        auraActiveColor = CopyResourceAuraOverlayColor(resource.auraActiveColor),
                        auraColorTrackingMode = resource.auraColorTrackingMode,
                        auraColorMaxStacks = resource.auraColorMaxStacks,
                    },
                }
                ClearLegacyResourceAuraOverlayFields(resource)
                hasLegacyData = false
            end

            local hasEntries = type(resource.auraOverlayEntries) == "table" and next(resource.auraOverlayEntries) ~= nil
            if not hasEntries then
                resource.auraOverlayEntries = nil
            end

            local hasRelevantData = hasEntries or hasLegacyData
            if explicitEnabled ~= nil then
                resource.auraOverlayEnabled = explicitEnabled
            elseif hasRelevantData then
                resource.auraOverlayEnabled = effectiveEnabled == true
            else
                resource.auraOverlayEnabled = nil
            end
        end
    end
end

local function NormalizeCustomAuraBarsForCurrentClass(settings)
    if type(settings) ~= "table" or type(settings.customAuraBars) ~= "table" then
        return
    end

    local allowedSpecIDs = GetCurrentClassSpecInfo()
    if type(allowedSpecIDs) ~= "table" then
        return
    end

    local filtered = {}
    for key, specBars in pairs(settings.customAuraBars) do
        local numericSpecID = tonumber(key)
        if type(specBars) == "table" and (
            numericSpecID == 0
            or (numericSpecID and allowedSpecIDs[numericSpecID])
        ) then
            filtered[numericSpecID or key] = CopyTable(specBars)
        end
    end

    settings.customAuraBars = filtered
end

local function SanitizeAnchorGroupID(groupId)
    if not groupId then
        return nil
    end
    local numericGroupID = tonumber(groupId)
    if not numericGroupID then
        return nil
    end
    if not CooldownCompanion:IsGroupAvailableForAnchoring(numericGroupID) then
        return nil
    end
    return numericGroupID
end

local function SanitizeResourceBarAnchors(settings)
    if type(settings) ~= "table" then
        return
    end

    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)

    if type(settings.customAuraBars) ~= "table" then
        return
    end

    for _, specBars in pairs(settings.customAuraBars) do
        if type(specBars) == "table" then
            for _, customAuraBar in pairs(specBars) do
                if type(customAuraBar) == "table" then
                    customAuraBar.independentAnchorGroupId = SanitizeAnchorGroupID(customAuraBar.independentAnchorGroupId)
                end
            end
        end
    end
end

local function SanitizeCastBarAnchors(settings)
    if type(settings) ~= "table" then
        return
    end
    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)
end

local function SanitizeFrameAnchoringAnchors(settings)
    if type(settings) ~= "table" then
        return
    end
    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)
end

local function CopyPreservedResourceAuraOverlayState(targetResource, copiedResource)
    if type(copiedResource) ~= "table" then
        return copiedResource
    end

    copiedResource.auraOverlayEnabled = nil
    copiedResource.auraOverlayEntries = nil
    copiedResource.auraColorSpellID = nil
    copiedResource.auraActiveColor = nil
    copiedResource.auraColorTrackingMode = nil
    copiedResource.auraColorMaxStacks = nil

    if type(targetResource) ~= "table" then
        return copiedResource
    end

    if type(targetResource.auraOverlayEnabled) == "boolean" then
        copiedResource.auraOverlayEnabled = targetResource.auraOverlayEnabled
    end
    if type(targetResource.auraOverlayEntries) == "table" then
        copiedResource.auraOverlayEntries = CopyTable(targetResource.auraOverlayEntries)
    end
    if targetResource.auraColorSpellID ~= nil then
        copiedResource.auraColorSpellID = targetResource.auraColorSpellID
    end
    if targetResource.auraActiveColor ~= nil then
        copiedResource.auraActiveColor = CopyTable(targetResource.auraActiveColor)
    end
    if targetResource.auraColorTrackingMode ~= nil then
        copiedResource.auraColorTrackingMode = targetResource.auraColorTrackingMode
    end
    if targetResource.auraColorMaxStacks ~= nil then
        copiedResource.auraColorMaxStacks = targetResource.auraColorMaxStacks
    end

    return copiedResource
end

local function ComposeCopiedResourceBarSettings(source, target)
    local copied = type(target) == "table" and CopyTable(target) or CopySubsystemDefaults("resourceBars")
    local applicableResources = GetCurrentClassApplicableResourceSet()

    if type(source) == "table" then
        for key, value in pairs(source) do
            if key ~= "resources" and key ~= "customAuraBars" and key ~= "customAuraBarSlots" then
                copied[key] = CloneSettingValue(value)
            end
        end
    end

    if type(source) == "table" and type(source.customAuraBarSlots) == "table" then
        copied.customAuraBarSlots = CopyTable(source.customAuraBarSlots)
    end

    if type(copied.resources) ~= "table" then
        copied.resources = {}
    end

    local sourceResources = type(source) == "table" and source.resources or nil
    local targetResources = type(target) == "table" and target.resources or nil
    if type(sourceResources) == "table" then
        for powerType in pairs(applicableResources) do
            local sourceResource = sourceResources[powerType]
            if type(sourceResource) == "table" then
                local targetResource = type(targetResources) == "table" and targetResources[powerType] or nil
                copied.resources[powerType] = CopyPreservedResourceAuraOverlayState(targetResource, CopyTable(sourceResource))
            end
        end
    end

    copied.customAuraBars = type(target) == "table" and CloneSettingValue(target.customAuraBars) or nil

    return copied
end

local function NormalizeScopedBarSettings(systemKey, settings)
    if systemKey == "resourceBars" then
        NormalizeCustomAuraBarsForCurrentClass(settings)
        NormalizeResourceAuraOverlayEntriesForCurrentClass(settings)
    end
end

local function SanitizeCopiedOrSeededScopedBarSettings(systemKey, settings)
    if systemKey == "resourceBars" then
        SanitizeResourceBarAnchors(settings)
    elseif systemKey == "castBar" then
        SanitizeCastBarAnchors(settings)
    elseif systemKey == "frameAnchoring" then
        SanitizeFrameAnchoringAnchors(settings)
    end
end

function CooldownCompanion:CaptureLegacyScopedBarSettingsSeeds()
    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    for _, systemSpec in pairs(SCOPED_BAR_SYSTEMS) do
        CaptureLegacyScopedBarSystemSeed(profile, systemSpec)
    end
end

function CooldownCompanion:EnsureLegacyScopedBarSeenCharacters()
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end

    local snapshot = rawget(profile, "legacyScopedBarSeenCharacters")
    if type(snapshot) == "table" then
        return snapshot
    end

    snapshot = {}

    for _, systemSpec in pairs(SCOPED_BAR_SYSTEMS) do
        local store = rawget(profile, systemSpec.storeKey)
        if type(store) == "table" then
            for charKey, settings in pairs(store) do
                if type(settings) == "table" then
                    MarkLegacyScopedBarSeenCharacter(snapshot, charKey)
                end
            end
        end
    end

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" and group.isGlobal == false then
                MarkLegacyScopedBarSeenCharacter(snapshot, group.createdBy)
            end
        end
    end

    if type(profile.folders) == "table" then
        for _, folder in pairs(profile.folders) do
            if type(folder) == "table" and folder.section == "char" then
                MarkLegacyScopedBarSeenCharacter(snapshot, folder.createdBy)
            end
        end
    end

    local currentProfileKey = self.db and self.db.keys and self.db.keys.profile
    local currentCharKey = self.db and self.db.keys and self.db.keys.char
    local profileKeys = self.db and self.db.sv and self.db.sv.profileKeys
    if type(profileKeys) == "table" and type(currentProfileKey) == "string" then
        for charKey, profileKey in pairs(profileKeys) do
            if profileKey == currentProfileKey and charKey ~= currentCharKey then
                MarkLegacyScopedBarSeenCharacter(snapshot, charKey)
            end
        end
    end

    if not ProfileHasAnyScopedBarBuckets(profile)
        and ProfileHasLegacyScopedBarData(profile)
        and type(currentCharKey) == "string"
        and currentCharKey ~= "" then
        MarkLegacyScopedBarSeenCharacter(snapshot, currentCharKey)
    end

    profile.legacyScopedBarSeenCharacters = snapshot
    return snapshot
end

function CooldownCompanion:GetCharacterScopedSettings(systemKey)
    local profile = self.db and self.db.profile
    local charKey = self.db and self.db.keys and self.db.keys.char
    local systemSpec = GetScopedBarSystemSpec(systemKey)
    if not profile or not charKey or not systemSpec then
        return nil
    end

    local store = EnsureScopedBarSystemStore(profile, systemSpec.storeKey)
    local settings = store[charKey]
    if type(settings) ~= "table" then
        local seed = CaptureLegacyScopedBarSystemSeed(profile, systemSpec)
        local seenCharacters = self:EnsureLegacyScopedBarSeenCharacters()
        local shouldUseLegacySeed = type(seed) == "table"
            and type(seenCharacters) == "table"
            and seenCharacters[charKey] == true
        settings = shouldUseLegacySeed and CopyTable(seed) or CopySubsystemDefaults(systemSpec.legacyKey)
        NormalizeScopedBarSettings(systemKey, settings)
        SanitizeCopiedOrSeededScopedBarSettings(systemKey, settings)
        store[charKey] = settings
    else
        NormalizeScopedBarSettings(systemKey, settings)
    end

    return settings
end

function CooldownCompanion:EnsureCurrentCharacterScopedBarSettings()
    self:GetCharacterScopedSettings("resourceBars")
    self:GetCharacterScopedSettings("castBar")
    self:GetCharacterScopedSettings("frameAnchoring")
end

function CooldownCompanion:GetResourceBarSettings()
    return self:GetCharacterScopedSettings("resourceBars")
end

function CooldownCompanion:GetCastBarSettings()
    return self:GetCharacterScopedSettings("castBar")
end

function CooldownCompanion:GetFrameAnchoringSettings()
    return self:GetCharacterScopedSettings("frameAnchoring")
end

function CooldownCompanion:GetCharacterScopedSettingsStore(systemKey)
    local profile = self.db and self.db.profile
    local systemSpec = GetScopedBarSystemSpec(systemKey)
    if not profile or not systemSpec then
        return nil
    end
    return EnsureScopedBarSystemStore(profile, systemSpec.storeKey)
end

function CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
    local store = self:GetCharacterScopedSettingsStore(systemKey)
    local currentChar = self.db and self.db.keys and self.db.keys.char
    local values = {}
    local order = {}

    if type(store) ~= "table" then
        return values, order
    end

    for charKey, settings in pairs(store) do
        if charKey ~= currentChar and type(settings) == "table" then
            values[charKey] = charKey
            order[#order + 1] = charKey
        end
    end

    sort(order)
    return values, order
end

function CooldownCompanion:CopyCharacterScopedSettings(systemKey, sourceCharKey)
    local profile = self.db and self.db.profile
    local currentChar = self.db and self.db.keys and self.db.keys.char
    local systemSpec = GetScopedBarSystemSpec(systemKey)
    if not profile or not currentChar or not sourceCharKey or not systemSpec then
        return false, "invalid_request"
    end

    local store = EnsureScopedBarSystemStore(profile, systemSpec.storeKey)
    local source = store[sourceCharKey]
    if type(source) ~= "table" then
        return false, "missing_source"
    end

    local copied
    if systemKey == "resourceBars" then
        copied = ComposeCopiedResourceBarSettings(source, self:GetResourceBarSettings())
    else
        copied = CopyTable(source)
    end
    NormalizeScopedBarSettings(systemKey, copied)
    SanitizeCopiedOrSeededScopedBarSettings(systemKey, copied)
    store[currentChar] = copied
    return true
end
