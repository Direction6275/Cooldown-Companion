local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local CopyTable = CopyTable
local pairs = pairs
local next = next
local rawget = rawget
local tonumber = tonumber
local type = type
local sort = table.sort

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

-- Keep these resource mappings aligned with OtherBars/ResourceBarConstants.lua.
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

local function PreserveTargetCustomBarLayouts(copied, target)
    if type(copied) ~= "table"
        or type(target) ~= "table"
        or type(target.customBars) ~= "table"
    then
        return
    end

    if type(copied.layoutOrder) ~= "table" then
        copied.layoutOrder = {}
    end

    for _, layout in pairs(copied.layoutOrder) do
        if type(layout) == "table" then
            layout.customBars = {}
        end
    end

    local targetLayoutOrder = type(target.layoutOrder) == "table" and target.layoutOrder or nil
    local function preserveLayout(specID, customBarId)
        if type(customBarId) ~= "string" or customBarId == "" then
            return
        end
        local targetLayout = GetSpecKeyedTable(targetLayoutOrder, specID)
        local copiedLayout = GetSpecKeyedTable(copied.layoutOrder, specID)
        if not copiedLayout then
            copiedLayout = type(targetLayout) == "table" and CopyTable(targetLayout) or {}
            copied.layoutOrder[specID] = copiedLayout
        end
        if type(copiedLayout.customBars) ~= "table" then
            copiedLayout.customBars = {}
        end

        local targetCustomBarLayouts = type(targetLayout) == "table" and targetLayout.customBars or nil
        local targetCustomBarLayout = type(targetCustomBarLayouts) == "table"
            and targetCustomBarLayouts[customBarId]
            or nil
        if type(targetCustomBarLayout) == "table" then
            copiedLayout.customBars[customBarId] = CopyTable(targetCustomBarLayout)
        end
    end

    if IsSharedCustomBarsStore(target.customBars) then
        local entries = type(target.customBars.entries) == "table" and target.customBars.entries or {}
        for _, entry in pairs(entries) do
            local customBarId = type(entry) == "table" and entry.customBarId or nil
            local sawSpec = false
            ForEachSharedCustomBarSpec(entry, function(specID)
                sawSpec = true
                preserveLayout(specID, customBarId)
            end)
            if not sawSpec and type(targetLayoutOrder) == "table" then
                for specID, layout in pairs(targetLayoutOrder) do
                    if type(layout) == "table"
                        and type(layout.customBars) == "table"
                        and type(layout.customBars[customBarId]) == "table" then
                        preserveLayout(specID, customBarId)
                    end
                end
            end
        end
    else
        for specID, targetSpecBars in pairs(target.customBars) do
            if type(targetSpecBars) == "table" then
                local copiedLayout = GetSpecKeyedTable(copied.layoutOrder, specID)
                if copiedLayout then
                    copiedLayout.customBars = {}
                end
                for _, entry in pairs(targetSpecBars) do
                    preserveLayout(specID, type(entry) == "table" and entry.customBarId or nil)
                end
            end
        end
    end
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
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    return specIDs, currentSpecID
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
    resourceSet[RESOURCE_HEALTH] = true
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
    resource.auraUnit = nil
    resource.auraUnitExplicit = nil
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

local function NormalizeResourceSpecOverridesForCurrentClass(settings)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return
    end

    local allowedSpecIDs = GetCurrentClassSpecInfo()
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

local function NormalizeCustomAuraBarsForCurrentClass(settings)
    if type(settings) ~= "table" then
        return
    end
    local barsBySpec = type(settings.customBars) == "table" and settings.customBars or settings.customAuraBars
    if type(barsBySpec) ~= "table" then return end

    local allowedSpecIDs = GetCurrentClassSpecInfo()
    if type(allowedSpecIDs) ~= "table" then
        return
    end

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
                filtered[numericSpecID or key] = CopyTable(specBars)
            end
        end
    end

    if type(settings.customBars) == "table" then
        settings.customBars = filtered
    else
        settings.customAuraBars = filtered
    end
end

local function SanitizeAnchorGroupID(groupId)
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
    if group.displayMode ~= "icons" or (container and container.isGlobal) then
        return nil
    end
    if not CooldownCompanion:IsGroupVisibleToCurrentChar(numericGroupID) then
        return nil
    end
    return numericGroupID
end

local function SanitizeResourceBarAnchors(settings)
    if type(settings) ~= "table" then
        return
    end

    settings.anchorGroupId = SanitizeAnchorGroupID(settings.anchorGroupId)

    if settings.independentAnchor ~= nil and type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = nil
    end

    local customBarsBySpec = type(settings.customBars) == "table" and settings.customBars or settings.customAuraBars
    if type(customBarsBySpec) ~= "table" then
        return
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

-- Preserves per-spec state (aura overlay entries, spec overrides) from targetResource
-- when composing a copy. Strips these fields from copiedResource first, then re-applies
-- targetResource's values to prevent copy/seed operations from overwriting per-character
-- spec customizations.
local function CopyPreservedResourcePerSpecState(targetResource, copiedResource)
    if type(copiedResource) ~= "table" then
        return copiedResource
    end

    copiedResource.auraOverlayEnabled = nil
    copiedResource.auraOverlayEntries = nil
    copiedResource.specOverrides = nil
    copiedResource.auraColorSpellID = nil
    copiedResource.auraActiveColor = nil
    copiedResource.auraColorTrackingMode = nil
    copiedResource.auraColorMaxStacks = nil
    copiedResource.auraUnit = nil
    copiedResource.auraUnitExplicit = nil

    if type(targetResource) ~= "table" then
        return copiedResource
    end

    if type(targetResource.auraOverlayEnabled) == "boolean" then
        copiedResource.auraOverlayEnabled = targetResource.auraOverlayEnabled
    end
    if type(targetResource.auraOverlayEntries) == "table" then
        copiedResource.auraOverlayEntries = CopyTable(targetResource.auraOverlayEntries)
    end
    if type(targetResource.specOverrides) == "table" then
        copiedResource.specOverrides = CopyTable(targetResource.specOverrides)
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
    if targetResource.auraUnit ~= nil then
        copiedResource.auraUnit = targetResource.auraUnit
    end
    if targetResource.auraUnitExplicit ~= nil then
        copiedResource.auraUnitExplicit = targetResource.auraUnitExplicit
    end

    return copiedResource
end

local function ComposeCopiedResourceBarSettings(source, target)
    local copied = type(target) == "table" and CopyTable(target) or CopySubsystemDefaults("resourceBars")
    local applicableResources = GetCurrentClassApplicableResourceSet()

    if type(source) == "table" then
        for key, value in pairs(source) do
            if key ~= "resources"
                and key ~= "customAuraBars"
                and key ~= "customBars"
                and key ~= "customAuraBarSlots"
                and key ~= "displayProfiles"
                and key ~= "layoutOrder"
                and key ~= "nextCustomBarId" then
                copied[key] = CloneSettingValue(value)
            end
        end
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
                copied.resources[powerType] = CopyPreservedResourcePerSpecState(targetResource, CopyTable(sourceResource))
            end
        end
    end

    copied.customAuraBars = type(target) == "table" and CloneSettingValue(target.customAuraBars) or copied.customAuraBars
    copied.customBars = type(target) == "table" and CloneSettingValue(target.customBars) or copied.customBars
    PreserveTargetCustomBarLayouts(copied, target)

    return copied
end

local function NormalizeScopedBarSettings(systemKey, settings)
    if systemKey == "resourceBars" then
        NormalizeCustomAuraBarsForCurrentClass(settings)
        NormalizeResourceAuraOverlayEntriesForCurrentClass(settings)
        NormalizeResourceSpecOverridesForCurrentClass(settings)
        NormalizeResourceThresholdTickEntries(settings)
    end
end

local function IsResourceAuraUnitNormalized(auraEntry)
    if type(auraEntry) ~= "table" then
        return false
    end
    return auraEntry.auraUnit == "player" or auraEntry.auraUnit == "target"
end

local function ResourceAuraOverlayNeedsNormalization(settings)
    if type(settings) ~= "table" or type(settings.resources) ~= "table" then
        return false
    end

    local allowedSpecIDs = nil
    local checkedSpecIDs = false
    local function GetAllowedSpecIDs()
        if not checkedSpecIDs then
            allowedSpecIDs = GetCurrentClassSpecInfo()
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

local function NeedsScopedBarNormalization(systemKey, settings)
    if systemKey == "resourceBars" then
        return ResourceAuraOverlayNeedsNormalization(settings)
    end
    return false
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
    elseif NeedsScopedBarNormalization(systemKey, settings) then
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
