local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local CopyTable = CopyTable
local pairs = pairs
local next = next
local rawget = rawget
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local sort = table.sort
local concat = table.concat

local CLASS_SCAN_LIMIT = 30

local RESOURCE_BAR_SYSTEM_SPEC = {
    storeKey = "resourceBarsByChar",
    seedKey = "legacyResourceBarsSeed",
    legacyKey = "resourceBars",
}

local RESOURCE_BAR_CLASS_STORE_KEY = "resourceBarsByClass"
local RESOURCE_BAR_MIGRATION_KEY = "resourceBarMigration"
local RESOURCE_BAR_NORMALIZED_CLASS_KEYS = setmetatable({}, { __mode = "k" })

local function GetEnsureCustomAuraBarAuraUnit()
    local rb = ST and ST._RB
    return rb and rb.EnsureCustomAuraBarAuraUnit
end

local function BackfillLegacyResourceAuraUnit(resourceAuraEntry)
    if type(resourceAuraEntry) ~= "table" then
        return
    end
    if resourceAuraEntry.auraUnit == "player" or resourceAuraEntry.auraUnit == "target" then
        return
    end
    resourceAuraEntry.auraUnit = "player"
    resourceAuraEntry.auraUnitExplicit = nil
end

local SCOPED_BAR_SYSTEMS = {
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

local function NormalizeClassKey(classKey)
    if type(classKey) ~= "string" or classKey == "" then
        return nil
    end
    return string.upper(classKey)
end

local function GetClassInfoByID(classID)
    classID = tonumber(classID)
    if not classID then
        return nil, nil, nil
    end
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" then
            return classInfo.className, classInfo.classFile, classInfo.classID
        end
    end
    if GetClassInfo then
        return GetClassInfo(classID)
    end
    return nil, nil, nil
end

local function GetClassKeyFromClassID(classID)
    local _, classFilename = GetClassInfoByID(classID)
    return NormalizeClassKey(classFilename)
end

local function GetClassIDFromClassKey(classKey)
    classKey = NormalizeClassKey(classKey)
    if not classKey then
        return nil
    end
    for classID = 1, CLASS_SCAN_LIMIT do
        if GetClassKeyFromClassID(classID) == classKey then
            return classID
        end
    end
    return nil
end

local function GetCurrentResourceBarClassKey(addon)
    local classFilename = addon and addon._playerClassFilename
    if not classFilename and UnitClass then
        classFilename = select(2, UnitClass("player"))
    end
    return NormalizeClassKey(classFilename)
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

local function GetSpecKeyedTable(source, specID)
    if type(source) ~= "table" then
        return nil
    end

    local direct = source[specID]
    if type(direct) == "table" then
        return direct
    end

    local numericKey = tonumber(specID)
    if numericKey and type(source[numericKey]) == "table" then
        return source[numericKey]
    end

    local stringKey = tostring(specID)
    if type(source[stringKey]) == "table" then
        return source[stringKey]
    end

    return nil
end

local function ClearSpecKeyedValue(source, specID)
    if type(source) ~= "table" then
        return
    end

    source[specID] = nil

    local numericKey = tonumber(specID)
    if numericKey then
        source[numericKey] = nil
    end

    source[tostring(specID)] = nil
end

local function IsSharedCustomBarsStore(customBars)
    return type(customBars) == "table"
        and (type(customBars.entries) == "table" or type(customBars.order) == "table")
end

local function NormalizeCustomBarSpecID(specID)
    local numericSpecID = tonumber(specID)
    if numericSpecID and numericSpecID > 0 then
        return numericSpecID
    end
    return nil
end

local function ForEachSharedCustomBarSpec(entry, callback)
    if type(entry) ~= "table" or type(callback) ~= "function" then
        return
    end
    if type(entry.specs) == "table" then
        for key, value in pairs(entry.specs) do
            if value == true then
                local specID = NormalizeCustomBarSpecID(key)
                if specID then
                    callback(specID)
                end
            elseif type(value) == "number" or type(value) == "string" then
                local specID = NormalizeCustomBarSpecID(value)
                if specID then
                    callback(specID)
                end
            end
        end
    end
    local legacySpecID = NormalizeCustomBarSpecID(entry.specID or entry.spec or entry.sourceSpecID)
    if legacySpecID then
        callback(legacySpecID)
    end
end

local ResolveSpecOverrideKey

local RESOURCE_SPEC_AURA_KEYS = {
    auraOverlayEnabled = true,
    auraOverlayEntries = true,
    auraColorSpellID = true,
    auraActiveColor = true,
    auraColorTrackingMode = true,
    auraColorMaxStacks = true,
    auraUnit = true,
    auraUnitExplicit = true,
}

local MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = 3

local function CopyColorSetting(color, includeAlpha)
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        return nil
    end
    local copied = { color[1], color[2], color[3] }
    if includeAlpha then
        copied[4] = color[4]
    end
    return copied
end

local function ClampLegacySegmentedThresholdValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    value = math.floor(value)
    if value < 1 then
        value = 1
    elseif value > 99 then
        value = 99
    end
    return value
end

local function ClampLegacyTickPercentValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < 0 then
        value = 0
    elseif value > 100 then
        value = 100
    end
    return value
end

local function ClampLegacyTickAbsoluteValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < 0 then
        value = 0
    end
    return value
end

local function NormalizeSavedEntryList(entries, clampValue, includeAlpha)
    local normalized = {}
    local seen = {}
    if type(entries) ~= "table" then
        return normalized
    end

    local keys = {}
    for key in pairs(entries) do
        if type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    sort(keys)

    for _, key in ipairs(keys) do
        local entry = entries[key]
        local value = type(entry) == "table" and clampValue(entry.value, nil) or nil
        if value ~= nil then
            local valueKey = tostring(value)
            if not seen[valueKey] then
                seen[valueKey] = true
                normalized[#normalized + 1] = {
                    value = value,
                    color = CopyColorSetting(type(entry) == "table" and entry.color or nil, includeAlpha),
                }
                if #normalized >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES then
                    break
                end
            end
        end
    end

    sort(normalized, function(a, b)
        return a.value < b.value
    end)
    return normalized
end

local function StoreNormalizedEntries(target, entriesKey, clearedKey, normalized)
    if #normalized > 0 then
        target[entriesKey] = normalized
        target[clearedKey] = nil
    else
        target[entriesKey] = nil
    end
end

local function NormalizeThresholdEntriesOnTarget(resource, specID, target)
    if type(target) ~= "table" then
        return
    end

    local normalized = NormalizeSavedEntryList(target.segThresholdEntries, ClampLegacySegmentedThresholdValue, false)
    if #normalized == 0
        and target.segThresholdEntriesCleared ~= true
        and ResolveSpecOverrideKey(resource, specID, "segThresholdEnabled") == true
        and (target.segThresholdEnabled ~= nil or target.segThresholdValue ~= nil or target.segThresholdColor ~= nil) then
        normalized[1] = {
            value = ClampLegacySegmentedThresholdValue(
                target.segThresholdValue ~= nil and target.segThresholdValue or ResolveSpecOverrideKey(resource, specID, "segThresholdValue"),
                1
            ),
            color = CopyColorSetting(target.segThresholdColor, false) or CopyColorSetting(ResolveSpecOverrideKey(resource, specID, "segThresholdColor"), false),
        }
    end
    StoreNormalizedEntries(target, "segThresholdEntries", "segThresholdEntriesCleared", normalized)
end

local function GetResolvedTickMode(resource, specID, target)
    local mode = target and target.continuousTickMode or ResolveSpecOverrideKey(resource, specID, "continuousTickMode")
    if mode == "absolute" then
        return "absolute"
    end
    return "percent"
end

local function NormalizeTickEntriesOnTarget(resource, specID, target)
    if type(target) ~= "table" then
        return
    end

    local percentEntries = NormalizeSavedEntryList(target.continuousTickPercentEntries, ClampLegacyTickPercentValue, true)
    local absoluteEntries = NormalizeSavedEntryList(target.continuousTickAbsoluteEntries, ClampLegacyTickAbsoluteValue, true)
    local tickEnabled = ResolveSpecOverrideKey(resource, specID, "continuousTickEnabled") == true
    local mode = GetResolvedTickMode(resource, specID, target)
    local hasLegacyTickData = target.continuousTickEnabled ~= nil
        or target.continuousTickMode ~= nil
        or target.continuousTickPercent ~= nil
        or target.continuousTickAbsolute ~= nil
        or target.continuousTickColor ~= nil

    if tickEnabled and hasLegacyTickData then
        if mode == "absolute" and #absoluteEntries == 0 and target.continuousTickAbsoluteEntriesCleared ~= true then
            absoluteEntries[1] = {
                value = ClampLegacyTickAbsoluteValue(
                    target.continuousTickAbsolute ~= nil and target.continuousTickAbsolute or ResolveSpecOverrideKey(resource, specID, "continuousTickAbsolute"),
                    50
                ),
                color = CopyColorSetting(target.continuousTickColor, true) or CopyColorSetting(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), true),
            }
        elseif mode == "percent" and #percentEntries == 0 and target.continuousTickPercentEntriesCleared ~= true then
            percentEntries[1] = {
                value = ClampLegacyTickPercentValue(
                    target.continuousTickPercent ~= nil and target.continuousTickPercent or ResolveSpecOverrideKey(resource, specID, "continuousTickPercent"),
                    50
                ),
                color = CopyColorSetting(target.continuousTickColor, true) or CopyColorSetting(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), true),
            }
        end
    end

    StoreNormalizedEntries(target, "continuousTickPercentEntries", "continuousTickPercentEntriesCleared", percentEntries)
    StoreNormalizedEntries(target, "continuousTickAbsoluteEntries", "continuousTickAbsoluteEntriesCleared", absoluteEntries)
end

local function NormalizeResourceThresholdTickEntries(settings)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end
    for _, resource in pairs(settings.resources) do
        if type(resource) == "table" then
            NormalizeThresholdEntriesOnTarget(resource, nil, resource)
            NormalizeTickEntriesOnTarget(resource, nil, resource)
            if type(resource.specOverrides) == "table" then
                for specID, specData in pairs(resource.specOverrides) do
                    if type(specData) == "table" then
                        NormalizeThresholdEntriesOnTarget(resource, specID, specData)
                        NormalizeTickEntriesOnTarget(resource, specID, specData)
                    end
                end
            end
        end
    end
end

local RESOURCE_HEALTH = -1

local function CopySpecOverrideWithoutAura(sourceSpecData, targetSpecData)
    local copied = {}

    if type(sourceSpecData) == "table" then
        for key, value in pairs(sourceSpecData) do
            if not RESOURCE_SPEC_AURA_KEYS[key] then
                copied[key] = CloneSettingValue(value)
            end
        end
    end

    if type(targetSpecData) == "table" then
        for key, value in pairs(targetSpecData) do
            if RESOURCE_SPEC_AURA_KEYS[key] then
                copied[key] = CloneSettingValue(value)
            end
        end
    end

    return next(copied) and copied or nil
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

    if type(rawget(profile, RESOURCE_BAR_SYSTEM_SPEC.seedKey)) == "table"
        or type(rawget(profile, RESOURCE_BAR_SYSTEM_SPEC.legacyKey)) == "table" then
        return true
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

    local resourceStore = rawget(profile, RESOURCE_BAR_SYSTEM_SPEC.storeKey)
    if type(resourceStore) == "table" and next(resourceStore) ~= nil then
        return true
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

local function GetClassSpecInfo(classKey)
    local classID = GetClassIDFromClassKey(classKey)
    if not classID then
        return nil, nil
    end

    local specIDs = {}
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    if numSpecs <= 0 then
        return nil, nil
    end

    for i = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[specID] = true
        end
    end
    if not next(specIDs) then
        return nil, nil
    end

    local currentSpecID = nil
    if NormalizeClassKey(classKey) == GetCurrentResourceBarClassKey(CooldownCompanion) then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex then
            currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        end
    end

    return specIDs, currentSpecID
end

local function GetCurrentClassSpecInfo()
    return GetClassSpecInfo(GetCurrentResourceBarClassKey(CooldownCompanion))
end

local function CopySpecLayoutOrder(settings, sourceSpecID, targetSpecID)
    if type(settings) ~= "table" or type(settings.layoutOrder) ~= "table" then
        return
    end

    local sourceLayout = GetSpecKeyedTable(settings.layoutOrder, sourceSpecID)
    local targetLayout = GetSpecKeyedTable(settings.layoutOrder, targetSpecID)
    local targetCustomBars = type(targetLayout) == "table" and CloneSettingValue(targetLayout.customBars) or nil
    local targetCustomAuraBarSlots = type(targetLayout) == "table" and CloneSettingValue(targetLayout.customAuraBarSlots) or nil
    local targetHealthLayout = type(targetLayout) == "table"
        and GetSpecKeyedTable(targetLayout.resources, RESOURCE_HEALTH)
        or nil
    ClearSpecKeyedValue(settings.layoutOrder, targetSpecID)

    local copiedLayout = type(sourceLayout) == "table" and CopyTable(sourceLayout) or {}
    if type(copiedLayout.resources) == "table" then
        ClearSpecKeyedValue(copiedLayout.resources, RESOURCE_HEALTH)
    end
    if type(targetHealthLayout) == "table" then
        if type(copiedLayout.resources) ~= "table" then
            copiedLayout.resources = {}
        end
        copiedLayout.resources[RESOURCE_HEALTH] = CloneSettingValue(targetHealthLayout)
    end
    copiedLayout.customBars = targetCustomBars
    copiedLayout.customAuraBarSlots = targetCustomAuraBarSlots

    settings.layoutOrder[targetSpecID] = copiedLayout
end

local function CopySpecDisplayProfile(settings, sourceSpecID, targetSpecID)
    if type(settings) ~= "table" or type(settings.displayProfiles) ~= "table" then
        return
    end

    local sourceProfile = GetSpecKeyedTable(settings.displayProfiles, sourceSpecID)
    ClearSpecKeyedValue(settings.displayProfiles, targetSpecID)

    if type(sourceProfile) == "table" then
        settings.displayProfiles[targetSpecID] = CopyTable(sourceProfile)
    end
end

local function CopyResourceSpecOverrides(settings, sourceSpecID, targetSpecID)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end

    for powerType, resource in pairs(settings.resources) do
        local isHealth = powerType == RESOURCE_HEALTH or tonumber(powerType) == RESOURCE_HEALTH
        if not isHealth and type(resource) == "table" and type(resource.specOverrides) == "table" then
            local sourceSpecData = GetSpecKeyedTable(resource.specOverrides, sourceSpecID)
            local targetSpecData = GetSpecKeyedTable(resource.specOverrides, targetSpecID)
            local copiedSpecData = CopySpecOverrideWithoutAura(sourceSpecData, targetSpecData)

            ClearSpecKeyedValue(resource.specOverrides, targetSpecID)
            if copiedSpecData then
                resource.specOverrides[targetSpecID] = copiedSpecData
            end

            if not next(resource.specOverrides) then
                resource.specOverrides = nil
            end
        end
    end
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
    resource.auraUnit = nil
    resource.auraUnitExplicit = nil
end

local function NormalizeResourceAuraOverlayEntriesForClass(settings, classKey)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end

    local allowedSpecIDs, currentSpecID = GetClassSpecInfo(classKey)
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
                        BackfillLegacyResourceAuraUnit(filteredEntries[numericSpecID])
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
                        auraUnit = resource.auraUnit,
                        auraUnitExplicit = resource.auraUnitExplicit,
                    },
                }
                BackfillLegacyResourceAuraUnit(resource.auraOverlayEntries[currentSpecID])
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

-- Resolves a per-spec override key: specOverrides[specID][key] -> resource[key] -> nil.
function ResolveSpecOverrideKey(resource, specID, key)
    if specID and type(resource) == "table" then
        local specOverrides = resource.specOverrides
        if type(specOverrides) == "table" then
            local specData = specOverrides[specID]
            if type(specData) == "table" and specData[key] ~= nil then
                return specData[key]
            end
        end
    end
    return type(resource) == "table" and resource[key] or nil
end
ST._ResolveSpecOverrideKey = ResolveSpecOverrideKey

local function NormalizeResourceSpecOverridesForClass(settings, classKey)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end

    local allowedSpecIDs = GetClassSpecInfo(classKey)
    if type(allowedSpecIDs) ~= "table" then
        return
    end

    for _, resource in pairs(settings.resources) do
        if type(resource) == "table" and type(resource.specOverrides) == "table" then
            for specID in pairs(resource.specOverrides) do
                local numericSpecID = tonumber(specID)
                if not numericSpecID or not allowedSpecIDs[numericSpecID] then
                    resource.specOverrides[specID] = nil
                end
            end
            if not next(resource.specOverrides) then
                resource.specOverrides = nil
            end
        end
    end
end

local function ClearCustomBarLegacySpecFields(entry)
    if type(entry) ~= "table" then
        return
    end
    entry.specID = nil
    entry.spec = nil
    entry.sourceSpecID = nil
end

local function NormalizeCustomBarStoreForClass(barsBySpec, allowedSpecIDs)
    local filtered = {}
    if IsSharedCustomBarsStore(barsBySpec) then
        filtered.entries = {}
        filtered.order = {}
        local entries = type(barsBySpec.entries) == "table" and barsBySpec.entries or {}
        local included = {}
        for key, entry in pairs(entries) do
            if type(entry) == "table" then
                local copiedEntry = CopyTable(entry)
                local normalizedSpecs = {}
                local sawSpec = false
                ForEachSharedCustomBarSpec(copiedEntry, function(specID)
                    sawSpec = true
                    if allowedSpecIDs[specID] then
                        normalizedSpecs[specID] = true
                    end
                end)
                if not sawSpec or next(normalizedSpecs) then
                    copiedEntry.specs = normalizedSpecs
                    ClearCustomBarLegacySpecFields(copiedEntry)
                    local customBarId = type(copiedEntry.customBarId) == "string" and copiedEntry.customBarId or key
                    if type(customBarId) == "string" and customBarId ~= "" then
                        filtered.entries[customBarId] = copiedEntry
                        included[customBarId] = true
                    end
                end
            end
        end
        if type(barsBySpec.order) == "table" then
            for _, customBarId in ipairs(barsBySpec.order) do
                if included[customBarId] then
                    filtered.order[#filtered.order + 1] = customBarId
                    included[customBarId] = nil
                end
            end
        end
        for customBarId in pairs(included) do
            filtered.order[#filtered.order + 1] = customBarId
        end
    else
        for key, specBars in pairs(barsBySpec) do
            local numericSpecID = tonumber(key)
            if type(specBars) == "table" and (
                numericSpecID and allowedSpecIDs[numericSpecID]
            ) then
                local copiedSpecBars = CopyTable(specBars)
                for _, entry in pairs(copiedSpecBars) do
                    ClearCustomBarLegacySpecFields(entry)
                end
                filtered[numericSpecID or key] = copiedSpecBars
            end
        end
    end

    return filtered
end

local function NormalizeCustomAuraBarsForClass(settings, classKey)
    if type(settings) ~= "table" then
        return
    end

    local allowedSpecIDs = GetClassSpecInfo(classKey)
    if type(allowedSpecIDs) ~= "table" then
        return
    end

    if type(settings.customBars) == "table" then
        settings.customBars = NormalizeCustomBarStoreForClass(settings.customBars, allowedSpecIDs)
    end
    if type(settings.customAuraBars) == "table" then
        settings.customAuraBars = NormalizeCustomBarStoreForClass(settings.customAuraBars, allowedSpecIDs)
    end
end

local function IsAnchorGroupVisibleForClass(numericGroupID, container, classKey)
    classKey = NormalizeClassKey(classKey)
    if classKey and CooldownCompanion.ResolveContainerClassScope then
        local scope = CooldownCompanion:ResolveContainerClassScope(container, {
            currentClassKey = classKey,
        })
        return type(scope) == "table" and scope.runtimeVisible == true
    end
    return CooldownCompanion:IsGroupVisibleToCurrentChar(numericGroupID)
end

local function SanitizeAnchorGroupID(groupId, classKey)
    if not groupId then
        return nil
    end
    local numericGroupID = tonumber(groupId)
    if not numericGroupID then
        return nil
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local groups = profile and profile.groups
    local group = groups and groups[numericGroupID]
    if type(group) ~= "table" then
        return nil
    end
    if not group.parentContainerId then
        return nil
    end
    local container = profile.groupContainers and profile.groupContainers[group.parentContainerId]
    if not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) or (container and container.isGlobal) then
        return nil
    end
    if not IsAnchorGroupVisibleForClass(numericGroupID, container, classKey) then
        return nil
    end
    return numericGroupID
end

local function SanitizeResourceBarAnchors(settings, classKey)
    if type(settings) ~= "table" then
        return
    end

    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId, classKey)

    if settings.independentAnchor ~= nil and type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = nil
    end

    local ensureCustomAuraBarAuraUnit = GetEnsureCustomAuraBarAuraUnit()
    local function sanitizeCustomBar(customAuraBar)
        if type(customAuraBar) == "table" then
            customAuraBar.independentAnchorEnabled = nil
            customAuraBar.independentLocked = nil
            customAuraBar.independentAnchorTargetMode = nil
            customAuraBar.independentAnchorFrameName = nil
            customAuraBar.independentAnchorGroupId = nil
            customAuraBar.independentAnchor = nil
            customAuraBar.independentSize = nil
            customAuraBar.independentOrientation = nil
            customAuraBar.independentVerticalFillDirection = nil
            if ensureCustomAuraBarAuraUnit then
                ensureCustomAuraBarAuraUnit(customAuraBar, customAuraBar.spellID)
            end
        end
    end

    local function sanitizeCustomBarStore(customBarsBySpec)
        if type(customBarsBySpec) ~= "table" then
            return
        end

        if IsSharedCustomBarsStore(customBarsBySpec) then
            local entries = type(customBarsBySpec.entries) == "table" and customBarsBySpec.entries or {}
            for _, customAuraBar in pairs(entries) do
                sanitizeCustomBar(customAuraBar)
            end
        else
            for _, specBars in pairs(customBarsBySpec) do
                if type(specBars) == "table" then
                    for _, customAuraBar in pairs(specBars) do
                        sanitizeCustomBar(customAuraBar)
                    end
                end
            end
        end
    end

    sanitizeCustomBarStore(settings.customBars)
    sanitizeCustomBarStore(settings.customAuraBars)
end

local function SanitizeCastBarAnchors(settings)
    if type(settings) ~= "table" then
        return
    end
    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)

    if settings.independentAnchor ~= nil and type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = nil
    end
end

local function SanitizeFrameAnchoringAnchors(settings)
    if type(settings) ~= "table" then
        return
    end
    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)
end

local function NormalizeResourceBarSettingsForClass(settings, classKey)
    NormalizeCustomAuraBarsForClass(settings, classKey)
    NormalizeResourceAuraOverlayEntriesForClass(settings, classKey)
    NormalizeResourceSpecOverridesForClass(settings, classKey)
    NormalizeResourceThresholdTickEntries(settings)
    if type(settings) == "table" then
        RESOURCE_BAR_NORMALIZED_CLASS_KEYS[settings] = NormalizeClassKey(classKey)
    end
end

local function NormalizeScopedBarSettings(systemKey, settings)
    if systemKey == "resourceBars" then
        NormalizeResourceBarSettingsForClass(settings, GetCurrentResourceBarClassKey(CooldownCompanion))
    end
end

local function IsResourceAuraUnitNormalized(auraEntry)
    if type(auraEntry) ~= "table" then
        return false
    end
    return auraEntry.auraUnit == "player" or auraEntry.auraUnit == "target"
end

local function ResourceAuraOverlayNeedsNormalizationForClass(settings, classKey)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return false
    end
    classKey = NormalizeClassKey(classKey)

    local allowedSpecIDs = nil
    local checkedSpecIDs = false
    local function GetAllowedSpecIDs()
        if not checkedSpecIDs then
            allowedSpecIDs = GetClassSpecInfo(classKey)
            checkedSpecIDs = true
        end
        return allowedSpecIDs
    end

    for _, resource in pairs(settings.resources) do
        if type(resource) == "table" then
            if HasLegacyResourceAuraOverlayData(resource) then
                return true
            end

            if type(resource.auraOverlayEntries) == "table" then
                if not next(resource.auraOverlayEntries) then
                    return true
                end

                local allowed = GetAllowedSpecIDs()
                if type(allowed) ~= "table" then
                    return true
                end

                for specID, entry in pairs(resource.auraOverlayEntries) do
                    local numericSpecID = tonumber(specID)
                    if not numericSpecID
                        or numericSpecID ~= specID
                        or allowed[numericSpecID] ~= true
                        or not IsResourceAuraUnitNormalized(entry) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function ResourceAuraOverlayNeedsNormalization(settings)
    return ResourceAuraOverlayNeedsNormalizationForClass(settings, GetCurrentResourceBarClassKey(CooldownCompanion))
end

local function ResourceBarSettingsNeedsNormalizationForClass(settings, classKey)
    if type(settings) ~= "table" then
        return false
    end
    classKey = NormalizeClassKey(classKey)
    return RESOURCE_BAR_NORMALIZED_CLASS_KEYS[settings] ~= classKey
        or ResourceAuraOverlayNeedsNormalizationForClass(settings, classKey)
end

local function NeedsScopedBarNormalization(systemKey, settings)
    if systemKey == "resourceBars" then
        return ResourceAuraOverlayNeedsNormalization(settings)
    end
    return false
end

local function SanitizeCopiedOrSeededScopedBarSettings(systemKey, settings)
    if systemKey == "resourceBars" then
        SanitizeResourceBarAnchors(settings, GetCurrentResourceBarClassKey(CooldownCompanion))
    elseif systemKey == "castBar" then
        SanitizeCastBarAnchors(settings)
    elseif systemKey == "frameAnchoring" then
        SanitizeFrameAnchoringAnchors(settings)
    end
end

local function EnsureResourceBarClassStore(profile)
    local store = rawget(profile, RESOURCE_BAR_CLASS_STORE_KEY)
    if type(store) ~= "table" then
        store = {}
        profile[RESOURCE_BAR_CLASS_STORE_KEY] = store
    end
    return store
end

local function EnsureResourceBarMigrationState(profile)
    local state = rawget(profile, RESOURCE_BAR_MIGRATION_KEY)
    if type(state) ~= "table" then
        state = {}
        profile[RESOURCE_BAR_MIGRATION_KEY] = state
    end
    if type(state.conflicts) ~= "table" then
        state.conflicts = {}
    end
    if type(state.unsafeCharKeys) ~= "table" then
        state.unsafeCharKeys = {}
    end
    return state
end

local function GetResourceBarLegacyStore(profile, create)
    local store = rawget(profile, RESOURCE_BAR_SYSTEM_SPEC.storeKey)
    if type(store) == "table" then
        return store
    end
    if not create then
        return nil
    end
    store = {}
    profile[RESOURCE_BAR_SYSTEM_SPEC.storeKey] = store
    return store
end

local function DeepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not DeepEqual(value, right and right[key]) then
            return false
        end
    end
    for key in pairs(right or {}) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function IsDefaultResourceBarClassSettings(settings, classKey)
    if type(settings) ~= "table" then
        return false
    end
    local defaults = CopySubsystemDefaults("resourceBars")
    NormalizeResourceBarSettingsForClass(defaults, classKey)
    SanitizeResourceBarAnchors(defaults, classKey)
    return DeepEqual(settings, defaults)
end

local function SortedMapKeys(map)
    local keys = {}
    if type(map) ~= "table" then
        return keys
    end
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function NormalizeClassKeyFromInfo(info)
    if type(info) ~= "table" then
        return nil
    end
    return NormalizeClassKey(info.classFilename or info.classFile or info.className)
        or GetClassKeyFromClassID(info.classID)
end

local function GetImportResourceBarCharacterInfo(addon)
    return addon and addon._resourceBarImportCharacterInfo
end

local function GetImportResourceBarExporterCharKey(addon)
    local charKey = addon and addon._resourceBarImportExporterCharKey
    if type(charKey) == "string" and charKey ~= "" then
        return charKey
    end
    return nil
end

local function ResolveResourceBarCandidateClassKey(addon, charKey)
    local currentCharKey = addon and addon.db and addon.db.keys and addon.db.keys.char
    if charKey == currentCharKey then
        return GetCurrentResourceBarClassKey(addon)
    end

    local importInfo = GetImportResourceBarCharacterInfo(addon)
    local classKey = NormalizeClassKeyFromInfo(type(importInfo) == "table" and importInfo[charKey] or nil)
    if classKey then
        return classKey
    end

    local globalInfo = addon and addon.db and addon.db.global and addon.db.global.characterInfo
    return NormalizeClassKeyFromInfo(type(globalInfo) == "table" and globalInfo[charKey] or nil)
end

local function ClearLegacyResourceBarSeed(profile)
    if type(profile) ~= "table" then
        return
    end
    profile[RESOURCE_BAR_SYSTEM_SPEC.legacyKey] = nil
    profile[RESOURCE_BAR_SYSTEM_SPEC.seedKey] = nil
end

local function SeedImportedLegacyResourceBarBucket(addon, profile)
    local exporterCharKey = GetImportResourceBarExporterCharKey(addon)
    if not exporterCharKey then
        return false
    end

    local seed = CaptureLegacyScopedBarSystemSeed(profile, RESOURCE_BAR_SYSTEM_SPEC)
    if type(seed) ~= "table" then
        return true
    end

    local store = GetResourceBarLegacyStore(profile, false)
    if not (type(store) == "table" and type(store[exporterCharKey]) == "table") then
        local settings = CopyTable(seed)
        local classKey = ResolveResourceBarCandidateClassKey(addon, exporterCharKey)
        if classKey then
            NormalizeResourceBarSettingsForClass(settings, classKey)
        end
        SanitizeResourceBarAnchors(settings, classKey)
        store = GetResourceBarLegacyStore(profile, true)
        store[exporterCharKey] = settings
    end

    ClearLegacyResourceBarSeed(profile)
    return true
end

local function SeedCurrentLegacyResourceBarBucket(addon, profile)
    local currentCharKey = addon and addon.db and addon.db.keys and addon.db.keys.char
    if type(currentCharKey) ~= "string" or currentCharKey == "" then
        return
    end

    local classKey = GetCurrentResourceBarClassKey(addon)
    local classStore = type(profile) == "table" and rawget(profile, RESOURCE_BAR_CLASS_STORE_KEY) or nil
    local classSettings = type(classStore) == "table" and classStore[classKey] or nil
    if type(classSettings) == "table" and not IsDefaultResourceBarClassSettings(classSettings, classKey) then
        ClearLegacyResourceBarSeed(profile)
        return
    end

    local store = GetResourceBarLegacyStore(profile, false)
    if type(store) == "table" and type(store[currentCharKey]) == "table" then
        ClearLegacyResourceBarSeed(profile)
        return
    end

    local seed = CaptureLegacyScopedBarSystemSeed(profile, RESOURCE_BAR_SYSTEM_SPEC)
    local seenCharacters = addon and addon.EnsureLegacyScopedBarSeenCharacters
        and addon:EnsureLegacyScopedBarSeenCharacters()
        or nil
    local shouldUseLegacySeed = type(seed) == "table"
        and type(seenCharacters) == "table"
        and seenCharacters[currentCharKey] == true
    if not shouldUseLegacySeed then
        return
    end

    store = GetResourceBarLegacyStore(profile, true)
    local settings = CopyTable(seed)
    NormalizeResourceBarSettingsForClass(settings, classKey)
    SanitizeResourceBarAnchors(settings, classKey)
    store[currentCharKey] = settings
    ClearLegacyResourceBarSeed(profile)
end

local function CopyNormalizedResourceBarCandidate(settings, classKey)
    local normalized = CopyTable(settings)
    NormalizeResourceBarSettingsForClass(normalized, classKey)
    SanitizeResourceBarAnchors(normalized, classKey)
    return normalized
end

local function FindMatchingResourceBarCandidateIndex(candidates, normalized)
    for index, candidate in ipairs(candidates) do
        if DeepEqual(candidate.normalized, normalized) then
            return index
        end
    end
    return nil
end

local function RemoveLegacyResourceBarCandidates(profile, charKeys)
    local store = GetResourceBarLegacyStore(profile, false)
    if type(store) ~= "table" then
        return
    end
    for _, charKey in ipairs(charKeys or {}) do
        store[charKey] = nil
    end
    if next(store) == nil then
        profile[RESOURCE_BAR_SYSTEM_SPEC.storeKey] = nil
    end
end

local function ClearResourceBarUnsafeLegacyKeys(state, charKeys)
    local unsafe = type(state) == "table" and state.unsafeCharKeys or nil
    if type(unsafe) ~= "table" then
        return
    end
    for _, charKey in ipairs(charKeys or {}) do
        unsafe[charKey] = nil
    end
end

local function ClearResourceBarConflict(state, classKey)
    if type(state) == "table" and type(state.conflicts) == "table" then
        state.conflicts[classKey] = nil
    end
end

local function StoreResourceBarConflict(state, classKey, charKeys, includeExistingClass)
    local conflict = {
        classKey = classKey,
        candidateCharKeys = CopyTable(charKeys),
    }
    if includeExistingClass then
        conflict.includeExistingClass = true
    end
    state.conflicts[classKey] = conflict
end

local function BuildResourceBarMigrationBuckets(addon, profile, state)
    local buckets = {}
    local store = GetResourceBarLegacyStore(profile, false)
    if type(store) ~= "table" then
        return buckets
    end

    state.unsafeCharKeys = {}
    for _, charKey in ipairs(SortedMapKeys(store)) do
        local settings = store[charKey]
        if type(settings) == "table" then
            local classKey = ResolveResourceBarCandidateClassKey(addon, charKey)
            if classKey then
                local bucket = buckets[classKey]
                if not bucket then
                    bucket = {}
                    buckets[classKey] = bucket
                end
                bucket[#bucket + 1] = {
                    charKey = charKey,
                    settings = settings,
                    normalized = CopyNormalizedResourceBarCandidate(settings, classKey),
                }
            else
                state.unsafeCharKeys[charKey] = true
            end
        end
    end

    return buckets
end

local function AddMergedCustomBarOrder(store, customBarId)
    if type(store) ~= "table" or type(customBarId) ~= "string" or customBarId == "" then
        return
    end
    store.order = type(store.order) == "table" and store.order or {}
    for _, existingId in ipairs(store.order) do
        if existingId == customBarId then
            return
        end
    end
    store.order[#store.order + 1] = customBarId
end

local function AllocateMergedCustomBarId(settings, store)
    settings.nextCustomBarId = tonumber(settings.nextCustomBarId) or 1
    local id
    repeat
        id = "custom_bar_" .. tostring(settings.nextCustomBarId)
        settings.nextCustomBarId = settings.nextCustomBarId + 1
    until type(store.entries[id]) ~= "table"
    return id
end

local function EnsureMergedCustomBarLayout(settings, specID)
    specID = NormalizeCustomBarSpecID(specID)
    if type(settings) ~= "table" or not specID then
        return nil
    end
    settings.layoutOrder = type(settings.layoutOrder) == "table" and settings.layoutOrder or {}
    local layout = GetSpecKeyedTable(settings.layoutOrder, specID)
    if type(layout) ~= "table" then
        layout = {}
        settings.layoutOrder[specID] = layout
    end
    layout.customBars = type(layout.customBars) == "table" and layout.customBars or {}
    return layout
end

local function AddMergedSpecID(specIDs, seen, specID)
    specID = NormalizeCustomBarSpecID(specID)
    if specID and not seen[specID] then
        seen[specID] = true
        specIDs[#specIDs + 1] = specID
    end
end

local function CollectMergedCustomBarLayoutSpecIDs(sourceSettings, sourceCustomBarId, entry, fallbackSpecID, legacySlotIndex)
    local specIDs = {}
    local seen = {}
    AddMergedSpecID(specIDs, seen, fallbackSpecID)

    if type(entry) == "table" and type(entry.specs) == "table" then
        for specID, enabled in pairs(entry.specs) do
            if enabled == true then
                AddMergedSpecID(specIDs, seen, specID)
            end
        end
    end

    local layoutOrder = type(sourceSettings) == "table" and sourceSettings.layoutOrder or nil
    if type(layoutOrder) == "table" then
        for specID, layout in pairs(layoutOrder) do
            if type(layout) == "table" then
                local hasCustomLayout = type(sourceCustomBarId) == "string"
                    and type(layout.customBars) == "table"
                    and type(layout.customBars[sourceCustomBarId]) == "table"
                local hasLegacyAuraLayout = legacySlotIndex ~= nil
                    and type(layout.customAuraBarSlots) == "table"
                    and type(layout.customAuraBarSlots[legacySlotIndex]) == "table"
                if hasCustomLayout or hasLegacyAuraLayout then
                    AddMergedSpecID(specIDs, seen, specID)
                end
            end
        end
    end

    sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
    return specIDs
end

local function CopyMergedCustomBarLayout(targetSettings, sourceSettings, specID, sourceCustomBarId, targetCustomBarId, fallbackOrder, legacySlotIndex)
    local targetLayout = EnsureMergedCustomBarLayout(targetSettings, specID)
    if type(targetLayout) ~= "table"
        or type(targetCustomBarId) ~= "string"
        or type(targetLayout.customBars[targetCustomBarId]) == "table" then
        return
    end

    local sourceLayout = type(sourceSettings) == "table"
        and type(sourceSettings.layoutOrder) == "table"
        and GetSpecKeyedTable(sourceSettings.layoutOrder, specID)
        or nil
    local sourceCustomLayout = nil
    if type(sourceLayout) == "table" then
        if type(sourceCustomBarId) == "string"
            and type(sourceLayout.customBars) == "table"
            and type(sourceLayout.customBars[sourceCustomBarId]) == "table" then
            sourceCustomLayout = sourceLayout.customBars[sourceCustomBarId]
        elseif legacySlotIndex ~= nil
            and type(sourceLayout.customAuraBarSlots) == "table"
            and type(sourceLayout.customAuraBarSlots[legacySlotIndex]) == "table" then
            sourceCustomLayout = sourceLayout.customAuraBarSlots[legacySlotIndex]
        end
    end

    targetLayout.customBars[targetCustomBarId] = type(sourceCustomLayout) == "table"
        and CopyTable(sourceCustomLayout)
        or {
            position = "below",
            order = fallbackOrder or 1000,
        }
end

local function NormalizeMergedCustomBarEntry(entry, fallbackSpecID, entryTypeFallback)
    if type(entry) ~= "table" then
        return nil
    end

    local copy = CopyTable(entry)
    if copy.entryType == nil and entryTypeFallback then
        copy.entryType = entryTypeFallback
    end

    local specs = {}
    local sawSpec = false
    ForEachSharedCustomBarSpec(copy, function(specID)
        sawSpec = true
        specs[specID] = true
    end)
    fallbackSpecID = NormalizeCustomBarSpecID(fallbackSpecID)
    if fallbackSpecID then
        sawSpec = true
        specs[fallbackSpecID] = true
    end
    copy.specs = sawSpec and specs or {}
    ClearCustomBarLegacySpecFields(copy)
    return copy
end

local AddMergedCustomBar

local function MergeLegacyCustomBarBuckets(targetSettings, sourceSettings, barsBySpec, isAuraStore)
    if type(barsBySpec) ~= "table" then
        return
    end

    local specKeys = {}
    for specID in pairs(barsBySpec) do
        specKeys[#specKeys + 1] = specID
    end
    sort(specKeys, function(a, b) return tostring(a) < tostring(b) end)

    for _, specKey in ipairs(specKeys) do
        local specID = NormalizeCustomBarSpecID(specKey)
        local specBars = specID and barsBySpec[specKey] or nil
        if type(specBars) == "table" then
            local numericKeys = {}
            local seen = {}
            for key in pairs(specBars) do
                if tonumber(key) then
                    numericKeys[#numericKeys + 1] = tonumber(key)
                end
            end
            sort(numericKeys)
            for index, numericKey in ipairs(numericKeys) do
                local entry = specBars[numericKey] or specBars[tostring(numericKey)]
                if type(entry) == "table" then
                    AddMergedCustomBar(targetSettings, sourceSettings, entry, specID, entry.customBarId, 1000 + index, isAuraStore and numericKey or nil, isAuraStore and "aura" or nil)
                end
                seen[numericKey] = true
                seen[tostring(numericKey)] = true
            end
            for key, entry in pairs(specBars) do
                if type(entry) == "table" and not seen[key] then
                    AddMergedCustomBar(targetSettings, sourceSettings, entry, specID, entry.customBarId, 1000 + #numericKeys + 1, isAuraStore and tonumber(key) or nil, isAuraStore and "aura" or nil)
                end
            end
        end
    end
end

local function EnsureMergedCustomBarStore(settings)
    if type(settings) ~= "table" then
        return nil
    end

    if IsSharedCustomBarsStore(settings.customBars) then
        local store = settings.customBars
        store.entries = type(store.entries) == "table" and store.entries or {}
        store.order = type(store.order) == "table" and store.order or {}
        local ordered = {}
        for _, customBarId in ipairs(store.order) do
            ordered[customBarId] = true
        end
        for customBarId, entry in pairs(store.entries) do
            if type(entry) == "table" and type(customBarId) == "string" then
                entry.customBarId = type(entry.customBarId) == "string" and entry.customBarId or customBarId
                if not ordered[customBarId] then
                    store.order[#store.order + 1] = customBarId
                end
            end
        end
        return store
    end

    local legacyCustomBars = settings.customBars
    local legacyCustomAuraBars = settings.customAuraBars
    settings.customBars = { entries = {}, order = {} }
    settings.customAuraBars = {}
    MergeLegacyCustomBarBuckets(settings, settings, legacyCustomBars, false)
    MergeLegacyCustomBarBuckets(settings, settings, legacyCustomAuraBars, true)
    return settings.customBars
end

AddMergedCustomBar = function(targetSettings, sourceSettings, sourceEntry, fallbackSpecID, sourceCustomBarId, fallbackOrder, legacySlotIndex, entryTypeFallback)
    local store = EnsureMergedCustomBarStore(targetSettings)
    local entry = NormalizeMergedCustomBarEntry(sourceEntry, fallbackSpecID, entryTypeFallback)
    if type(store) ~= "table" or type(entry) ~= "table" then
        return nil
    end

    local preferredId = type(entry.customBarId) == "string" and entry.customBarId ~= "" and entry.customBarId
        or (type(sourceCustomBarId) == "string" and sourceCustomBarId ~= "" and sourceCustomBarId or nil)
    local targetId = preferredId
    if not targetId then
        targetId = AllocateMergedCustomBarId(targetSettings, store)
    elseif type(store.entries[targetId]) == "table" then
        if DeepEqual(store.entries[targetId], entry) then
            local specIDs = CollectMergedCustomBarLayoutSpecIDs(sourceSettings, sourceCustomBarId or targetId, entry, fallbackSpecID, legacySlotIndex)
            for _, specID in ipairs(specIDs) do
                CopyMergedCustomBarLayout(targetSettings, sourceSettings, specID, sourceCustomBarId or targetId, targetId, fallbackOrder, legacySlotIndex)
            end
            return targetId
        end
        targetId = AllocateMergedCustomBarId(targetSettings, store)
    end

    entry.customBarId = targetId
    store.entries[targetId] = entry
    AddMergedCustomBarOrder(store, targetId)

    local specIDs = CollectMergedCustomBarLayoutSpecIDs(sourceSettings, sourceCustomBarId or preferredId or targetId, entry, fallbackSpecID, legacySlotIndex)
    for _, specID in ipairs(specIDs) do
        CopyMergedCustomBarLayout(targetSettings, sourceSettings, specID, sourceCustomBarId or preferredId or targetId, targetId, fallbackOrder, legacySlotIndex)
    end

    return targetId
end

local function MergeCustomBarsFromResourceBarSettings(targetSettings, sourceSettings, classKey)
    if type(targetSettings) ~= "table" or type(sourceSettings) ~= "table" then
        return
    end

    local source = CopyNormalizedResourceBarCandidate(sourceSettings, classKey)
    EnsureMergedCustomBarStore(targetSettings)

    if IsSharedCustomBarsStore(source.customBars) then
        local entries = type(source.customBars.entries) == "table" and source.customBars.entries or {}
        local seen = {}
        if type(source.customBars.order) == "table" then
            for _, customBarId in ipairs(source.customBars.order) do
                local entry = entries[customBarId]
                if type(entry) == "table" then
                    AddMergedCustomBar(targetSettings, source, entry, nil, customBarId, 1000 + #targetSettings.customBars.order)
                    seen[customBarId] = true
                end
            end
        end
        for customBarId, entry in pairs(entries) do
            if type(entry) == "table" and not seen[customBarId] then
                AddMergedCustomBar(targetSettings, source, entry, nil, customBarId, 1000 + #targetSettings.customBars.order + 1)
            end
        end
    else
        MergeLegacyCustomBarBuckets(targetSettings, source, source.customBars, false)
    end

    MergeLegacyCustomBarBuckets(targetSettings, source, source.customAuraBars, true)
    NormalizeResourceBarSettingsForClass(targetSettings, classKey)
    SanitizeResourceBarAnchors(targetSettings, classKey)
end

local function MergeResourceBarConflictCustomBars(targetSettings, classKey, conflict, legacyStore, selectedCharKey, existingClassSettings)
    if type(targetSettings) ~= "table" or type(conflict) ~= "table" then
        return
    end

    if type(existingClassSettings) == "table" then
        MergeCustomBarsFromResourceBarSettings(targetSettings, existingClassSettings, classKey)
    end

    if type(legacyStore) ~= "table" then
        return
    end
    for _, candidateCharKey in ipairs(conflict.candidateCharKeys or {}) do
        if candidateCharKey ~= selectedCharKey and type(legacyStore[candidateCharKey]) == "table" then
            MergeCustomBarsFromResourceBarSettings(targetSettings, legacyStore[candidateCharKey], classKey)
        end
    end
end

local function PromoteResourceBarClassSettings(classStore, classKey, settings)
    classStore[classKey] = CopyTable(settings)
    NormalizeResourceBarSettingsForClass(classStore[classKey], classKey)
    SanitizeResourceBarAnchors(classStore[classKey], classKey)
end

local function MigrateResourceBarClass(profile, classStore, state, classKey, candidates)
    local candidateCharKeys = {}
    for _, candidate in ipairs(candidates) do
        candidateCharKeys[#candidateCharKeys + 1] = candidate.charKey
    end
    sort(candidateCharKeys)

    if type(classStore[classKey]) == "table" then
        NormalizeResourceBarSettingsForClass(classStore[classKey], classKey)
        SanitizeResourceBarAnchors(classStore[classKey], classKey)
        if IsDefaultResourceBarClassSettings(classStore[classKey], classKey) then
            classStore[classKey] = nil
        else
            local hasDifferingCandidate = false
            for _, candidate in ipairs(candidates) do
                if not DeepEqual(candidate.normalized, classStore[classKey]) then
                    hasDifferingCandidate = true
                    break
                end
            end
            if hasDifferingCandidate then
                StoreResourceBarConflict(state, classKey, candidateCharKeys, true)
            else
                RemoveLegacyResourceBarCandidates(profile, candidateCharKeys)
                ClearResourceBarUnsafeLegacyKeys(state, candidateCharKeys)
                ClearResourceBarConflict(state, classKey)
            end
            return
        end
    end

    local unique = {}
    for _, candidate in ipairs(candidates) do
        local matchIndex = FindMatchingResourceBarCandidateIndex(unique, candidate.normalized)
        if matchIndex then
            local uniqueCandidate = unique[matchIndex]
            uniqueCandidate.charKeys[#uniqueCandidate.charKeys + 1] = candidate.charKey
        else
            unique[#unique + 1] = {
                charKeys = { candidate.charKey },
                normalized = candidate.normalized,
            }
        end
    end

    if #unique == 1 then
        PromoteResourceBarClassSettings(classStore, classKey, unique[1].normalized)
        RemoveLegacyResourceBarCandidates(profile, candidateCharKeys)
        ClearResourceBarUnsafeLegacyKeys(state, candidateCharKeys)
        ClearResourceBarConflict(state, classKey)
        return
    end

    StoreResourceBarConflict(state, classKey, candidateCharKeys)
end

local function GetResourceBarConflict(profile, classKey)
    if not classKey then
        return nil
    end
    local state = type(profile) == "table" and rawget(profile, RESOURCE_BAR_MIGRATION_KEY) or nil
    local conflicts = type(state) == "table" and state.conflicts or nil
    local conflict = type(conflicts) == "table" and conflicts[classKey] or nil
    if type(conflict) ~= "table" then
        return nil
    end
    local candidateCharKeys = type(conflict.candidateCharKeys) == "table" and conflict.candidateCharKeys or nil
    if not candidateCharKeys or #candidateCharKeys == 0 then
        return nil
    end
    local classStore = rawget(profile, RESOURCE_BAR_CLASS_STORE_KEY)
    if type(classStore) == "table"
        and type(classStore[classKey]) == "table"
        and conflict.includeExistingClass ~= true then
        return nil
    end
    return conflict
end

local function BuildResourceBarConflictSummary(profile)
    local summaries = {}
    local state = type(profile) == "table" and rawget(profile, RESOURCE_BAR_MIGRATION_KEY) or nil
    local conflicts = type(state) == "table" and state.conflicts or nil
    if type(conflicts) ~= "table" then
        return summaries
    end
    for _, classKey in ipairs(SortedMapKeys(conflicts)) do
        local conflict = GetResourceBarConflict(profile, classKey)
        if conflict then
            local candidateCharKeys = CopyTable(conflict.candidateCharKeys or {})
            sort(candidateCharKeys)
            summaries[#summaries + 1] = {
                classKey = classKey,
                candidateCharKeys = candidateCharKeys,
                candidateCount = #candidateCharKeys + (conflict.includeExistingClass and 1 or 0),
                includeExistingClass = conflict.includeExistingClass == true,
            }
        end
    end
    return summaries
end

local function FormatResourceBarConflictExportMessage(summaries)
    if type(summaries) ~= "table" or #summaries == 0 then
        return nil
    end

    local parts = {}
    for _, summary in ipairs(summaries) do
        local candidateText = summary.candidateCount .. " candidate"
        if summary.candidateCount ~= 1 then
            candidateText = candidateText .. "s"
        end
        if summary.includeExistingClass then
            candidateText = candidateText .. " including current class setup"
        end
        if #summary.candidateCharKeys > 0 then
            candidateText = candidateText .. ": " .. concat(summary.candidateCharKeys, ", ")
        end
        parts[#parts + 1] = summary.classKey .. " (" .. candidateText .. ")"
    end

    return "Resolve pending Resource Bar conflicts before exporting. Affected classes: "
        .. concat(parts, "; ")
        .. ". Open Resource Bar settings on the affected class and choose the setup to keep."
end

local function GetFallbackResourceBarSettings(addon, classKey)
    if type(addon._resourceBarConflictFallbackSettings) ~= "table" then
        addon._resourceBarConflictFallbackSettings = {}
    end
    local settings = addon._resourceBarConflictFallbackSettings[classKey]
    if type(settings) ~= "table" then
        local profile = addon.db and addon.db.profile
        local classStore = type(profile) == "table" and rawget(profile, RESOURCE_BAR_CLASS_STORE_KEY) or nil
        local classSettings = type(classStore) == "table" and classStore[classKey] or nil
        settings = type(classSettings) == "table" and CopyTable(classSettings) or CopySubsystemDefaults("resourceBars")
        NormalizeResourceBarSettingsForClass(settings, classKey)
        addon._resourceBarConflictFallbackSettings[classKey] = settings
    end
    return settings
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

    local resourceStore = rawget(profile, RESOURCE_BAR_SYSTEM_SPEC.storeKey)
    if type(resourceStore) == "table" then
        for charKey, settings in pairs(resourceStore) do
            if type(settings) == "table" then
                MarkLegacyScopedBarSeenCharacter(snapshot, charKey)
            end
        end
    end

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

    -- Legacy: groups may have isGlobal (pre-migration data)
    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" and group.isGlobal == false then
                MarkLegacyScopedBarSeenCharacter(snapshot, group.createdBy)
            end
        end
    end

    -- Post-migration: containers own isGlobal/createdBy
    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table" and container.isGlobal == false then
                MarkLegacyScopedBarSeenCharacter(snapshot, container.createdBy)
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
    elseif NeedsScopedBarNormalization(systemKey, settings) then
        NormalizeScopedBarSettings(systemKey, settings)
    end

    return settings
end

function CooldownCompanion:RunResourceBarClassScopeMigration()
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return
    end

    local state = EnsureResourceBarMigrationState(profile)
    state.unsafeCharKeys = {}
    if GetImportResourceBarExporterCharKey(self) then
        SeedImportedLegacyResourceBarBucket(self, profile)
    else
        SeedCurrentLegacyResourceBarBucket(self, profile)
    end

    local classStore = EnsureResourceBarClassStore(profile)
    for classKey, settings in pairs(classStore) do
        if type(settings) == "table" then
            NormalizeResourceBarSettingsForClass(settings, classKey)
            SanitizeResourceBarAnchors(settings, classKey)
        end
    end

    local buckets = BuildResourceBarMigrationBuckets(self, profile, state)
    for classKey in pairs(state.conflicts) do
        if not buckets[classKey] then
            state.conflicts[classKey] = nil
        end
    end
    for _, classKey in ipairs(SortedMapKeys(buckets)) do
        MigrateResourceBarClass(profile, classStore, state, classKey, buckets[classKey])
    end
end

function CooldownCompanion:GetCurrentResourceBarClassKey()
    return GetCurrentResourceBarClassKey(self)
end

function CooldownCompanion:GetResourceBarSettings()
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return nil
    end

    local classKey = GetCurrentResourceBarClassKey(self)
    if not classKey then
        return nil
    end

    local conflict = GetResourceBarConflict(profile, classKey)
    if conflict then
        local currentCharKey = self.db and self.db.keys and self.db.keys.char
        local legacyStore = GetResourceBarLegacyStore(profile, false)
        local currentLegacy = type(legacyStore) == "table" and legacyStore[currentCharKey] or nil
        if type(currentLegacy) == "table" then
            if ResourceBarSettingsNeedsNormalizationForClass(currentLegacy, classKey) then
                NormalizeResourceBarSettingsForClass(currentLegacy, classKey)
            end
            return currentLegacy
        end
        return GetFallbackResourceBarSettings(self, classKey)
    end

    local classStore = EnsureResourceBarClassStore(profile)
    local settings = classStore[classKey]
    if type(settings) ~= "table" then
        settings = CopySubsystemDefaults("resourceBars")
        NormalizeResourceBarSettingsForClass(settings, classKey)
        SanitizeResourceBarAnchors(settings, classKey)
        classStore[classKey] = settings
    elseif ResourceBarSettingsNeedsNormalizationForClass(settings, classKey) then
        NormalizeResourceBarSettingsForClass(settings, classKey)
    end

    return settings
end

function CooldownCompanion:GetCastBarSettings()
    return self:GetCharacterScopedSettings("castBar")
end

function CooldownCompanion:GetFrameAnchoringSettings()
    return self:GetCharacterScopedSettings("frameAnchoring")
end

function CooldownCompanion:GetResourceBarConflict(classKey)
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return nil
    end
    return GetResourceBarConflict(profile, NormalizeClassKey(classKey))
end

function CooldownCompanion:GetCurrentResourceBarConflict()
    return self:GetResourceBarConflict(GetCurrentResourceBarClassKey(self))
end

function CooldownCompanion:GetPendingResourceBarConflictSummary()
    local profile = self.db and self.db.profile
    return BuildResourceBarConflictSummary(profile)
end

function CooldownCompanion:GetPendingResourceBarConflictExportMessage()
    local summaries = self:GetPendingResourceBarConflictSummary()
    return FormatResourceBarConflictExportMessage(summaries)
end

function CooldownCompanion:GetResourceBarConflictExportMessage(classKey)
    classKey = NormalizeClassKey(classKey)
    if not classKey then
        return nil
    end

    local profile = self.db and self.db.profile
    local conflict = GetResourceBarConflict(profile, classKey)
    if not conflict then
        return nil
    end

    local candidateCharKeys = CopyTable(conflict.candidateCharKeys or {})
    sort(candidateCharKeys)
    return FormatResourceBarConflictExportMessage({
        {
            classKey = classKey,
            candidateCharKeys = candidateCharKeys,
            candidateCount = #candidateCharKeys + (conflict.includeExistingClass and 1 or 0),
            includeExistingClass = conflict.includeExistingClass == true,
        },
    })
end

function CooldownCompanion:GetCurrentResourceBarConflictExportMessage()
    return self:GetResourceBarConflictExportMessage(GetCurrentResourceBarClassKey(self))
end

function CooldownCompanion:ResolveResourceBarConflict(classKey, sourceCharKey, options)
    local profile = self.db and self.db.profile
    classKey = NormalizeClassKey(classKey)
    local keepExistingClassStore = type(options) == "table" and options.keepExistingClassStore == true
    if type(profile) ~= "table"
        or not classKey
        or (not keepExistingClassStore and (type(sourceCharKey) ~= "string" or sourceCharKey == "")) then
        return false, "invalid_request"
    end

    local conflict = GetResourceBarConflict(profile, classKey)
    if not conflict then
        return false, "missing_conflict"
    end

    local classStore = EnsureResourceBarClassStore(profile)
    local legacyStore = GetResourceBarLegacyStore(profile, false)
    if keepExistingClassStore then
        if conflict.includeExistingClass ~= true then
            return false, "invalid_candidate"
        end
        if type(classStore[classKey]) ~= "table" then
            return false, "missing_candidate"
        end
        NormalizeResourceBarSettingsForClass(classStore[classKey], classKey)
        if classKey == GetCurrentResourceBarClassKey(self) then
            SanitizeResourceBarAnchors(classStore[classKey], classKey)
        end
        MergeResourceBarConflictCustomBars(classStore[classKey], classKey, conflict, legacyStore, nil, nil)
        RemoveLegacyResourceBarCandidates(profile, conflict.candidateCharKeys)
        local state = EnsureResourceBarMigrationState(profile)
        ClearResourceBarUnsafeLegacyKeys(state, conflict.candidateCharKeys)
        ClearResourceBarConflict(state, classKey)
        if type(self._resourceBarConflictFallbackSettings) == "table" then
            self._resourceBarConflictFallbackSettings[classKey] = nil
        end
        return true
    end

    local sourceAllowed = false
    for _, candidateCharKey in ipairs(conflict.candidateCharKeys or {}) do
        if candidateCharKey == sourceCharKey then
            sourceAllowed = true
            break
        end
    end
    if not sourceAllowed then
        return false, "invalid_candidate"
    end

    local source = type(legacyStore) == "table" and legacyStore[sourceCharKey] or nil
    if type(source) ~= "table" then
        return false, "missing_candidate"
    end

    local existingClassSettings = conflict.includeExistingClass == true
        and type(classStore[classKey]) == "table"
        and CopyTable(classStore[classKey])
        or nil
    PromoteResourceBarClassSettings(classStore, classKey, source)
    if classKey == GetCurrentResourceBarClassKey(self) then
        SanitizeResourceBarAnchors(classStore[classKey], classKey)
    end
    MergeResourceBarConflictCustomBars(classStore[classKey], classKey, conflict, legacyStore, sourceCharKey, existingClassSettings)

    RemoveLegacyResourceBarCandidates(profile, conflict.candidateCharKeys)
    local state = EnsureResourceBarMigrationState(profile)
    ClearResourceBarUnsafeLegacyKeys(state, conflict.candidateCharKeys)
    ClearResourceBarConflict(state, classKey)
    if type(self._resourceBarConflictFallbackSettings) == "table" then
        self._resourceBarConflictFallbackSettings[classKey] = nil
    end
    return true
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

function CooldownCompanion:GetResourceBarSpecCopyOptions()
    local _, _, classID = UnitClass("player")
    if not classID then
        return {}, {}, nil, nil
    end

    local currentSpecID
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    local values = {}
    local order = {}
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for i = 1, numSpecs do
        local specID, specName = GetSpecializationInfoForClassID(classID, i)
        if specID then
            if specID ~= currentSpecID then
                values[specID] = specName or ("Spec " .. tostring(specID))
                order[#order + 1] = specID
            end
        end
    end

    sort(order, function(a, b)
        return (values[a] or "") < (values[b] or "")
    end)

    return values, order, currentSpecID
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

    local copied = CopyTable(source)
    NormalizeScopedBarSettings(systemKey, copied)
    SanitizeCopiedOrSeededScopedBarSettings(systemKey, copied)
    store[currentChar] = copied
    return true
end

function CooldownCompanion:CopyResourceBarSpecSettings(sourceSpecID, targetSpecID)
    sourceSpecID = tonumber(sourceSpecID)
    targetSpecID = tonumber(targetSpecID)

    local allowedSpecIDs, currentSpecID = GetCurrentClassSpecInfo()
    if not targetSpecID then
        targetSpecID = currentSpecID
    end

    if not sourceSpecID
        or not targetSpecID
        or sourceSpecID == targetSpecID
        or type(allowedSpecIDs) ~= "table"
        or allowedSpecIDs[sourceSpecID] ~= true
        or allowedSpecIDs[targetSpecID] ~= true then
        return false, "invalid_spec"
    end

    local settings = self:GetResourceBarSettings()
    if type(settings) ~= "table" then
        return false, "missing_settings"
    end

    CopySpecLayoutOrder(settings, sourceSpecID, targetSpecID)
    CopySpecDisplayProfile(settings, sourceSpecID, targetSpecID)
    CopyResourceSpecOverrides(settings, sourceSpecID, targetSpecID)

    NormalizeScopedBarSettings("resourceBars", settings)
    SanitizeCopiedOrSeededScopedBarSettings("resourceBars", settings)

    return true
end
