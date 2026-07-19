--[[
    CooldownCompanion - ResourceBarPanelsHelpers
    Query helpers, autocomplete, and shared resource-bar config utilities
    for the resource bar config panel.

    Exports via ST._RBP table. Consuming files alias to locals at load time.
    Shared constants are imported from ST._RB (eliminating _CONFIG duplicates).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

-- Shared constants from ResourceBarConstants (eliminates _CONFIG duplicates)
local RB = ST._RB
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_PERCENT = RB.DEFAULT_CONTINUOUS_TICK_PERCENT
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = RB.DEFAULT_CONTINUOUS_TICK_ABSOLUTE
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local CLASS_RESOURCES_CONFIG = RB.CLASS_RESOURCES_CONFIG
local SPEC_RESOURCES_CONFIG = RB.SPEC_RESOURCES_CONFIG
local IsAstralPowerAvailableForCurrentDruidSpec = RB.IsAstralPowerAvailableForCurrentDruidSpec
local DRUID_CLASS_ID = 11
local DRUID_BALANCE_SPEC_ID = 102

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

------------------------------------------------------------------------
-- Aura bar autocomplete cache (spell/aura entries only)
------------------------------------------------------------------------
local auraBarAutocompleteCache = nil
local auraBarAutocompleteSource = nil

local function IsSharedAuraAutocompleteEntry(entry)
    return type(entry) == "table" and entry.isItem ~= true
end

local function BuildAuraBarAutocompleteCache()
    local sharedCache = CS.autocompleteCache
        or (ST._BuildAutocompleteCache and ST._BuildAutocompleteCache())
        or {}
    if auraBarAutocompleteCache and auraBarAutocompleteSource == sharedCache then
        return auraBarAutocompleteCache
    end

    local cache = {}
    for _, entry in ipairs(sharedCache) do
        if IsSharedAuraAutocompleteEntry(entry) then
            cache[#cache + 1] = entry
        end
    end
    auraBarAutocompleteCache = cache
    auraBarAutocompleteSource = sharedCache
    return cache
end

local function FindAuraBarAutocompleteEntryByID(spellID)
    if not spellID then
        return nil
    end
    local cache = BuildAuraBarAutocompleteCache()
    for _, entry in ipairs(cache) do
        if entry.id == spellID then
            return entry
        end
    end
    return nil
end

local function GetAuraBarAutocompleteDisplayName(spellID)
    local entry = FindAuraBarAutocompleteEntryByID(spellID)
    if entry and entry.name then
        return entry.name
    end
    return spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or nil
end

local function GetAuraBarAutocompleteDisplayIcon(spellID)
    local entry = FindAuraBarAutocompleteEntryByID(spellID)
    if entry and entry.icon then
        return entry.icon
    end
    return spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or nil
end

local function GetAuraBarAutocompleteEntryName(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return type(entry.name) == "string" and entry.name ~= "" and entry.name or nil
end

local function ResolveAuraBarAutocompleteEntry(text)
    if not text then return nil end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil
    end

    local numeric = tonumber(cleaned)
    local lookup = cleaned:lower()
    local cache = BuildAuraBarAutocompleteCache()
    for _, entry in ipairs(cache) do
        local entryNameLower = type(entry.name) == "string" and entry.name:lower() or nil
        if (numeric and entry.id == numeric) or entry.nameLower == lookup or entryNameLower == lookup then
            return entry
        end
    end

    return nil
end

local function SearchAuraBarAutocomplete(text)
    local cache = BuildAuraBarAutocompleteCache()
    return CS.SearchAutocompleteInCache(text, cache)
end

local function ShowAuraBarAutocompleteResults(text, widget, onAuraSelect)
    if text and #text >= 1 then
        local results = SearchAuraBarAutocomplete(text)
        CS.ShowAutocompleteResults(results, widget, onAuraSelect)
    else
        CS.HideAutocomplete()
    end
end

local function AddHealthResourceConfig(resources)
    local result = { RESOURCE_HEALTH }
    if type(resources) ~= "table" then
        return result
    end

    for _, powerType in ipairs(resources) do
        if powerType ~= RESOURCE_HEALTH then
            result[#result + 1] = powerType
        end
    end

    return result
end

local function GetConfigActiveResources()
    local _, _, classID = UnitClass("player")
    if not classID then return {} end

    local specID = nil
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end

    -- For Druid, only expose Astral Power while currently in Balance spec.
    if classID == 11 then
        if IsAstralPowerAvailableForCurrentDruidSpec() then
            return AddHealthResourceConfig(CLASS_RESOURCES_CONFIG[11])
        end
        local resources = {}
        for _, powerType in ipairs(CLASS_RESOURCES_CONFIG[11] or {}) do
            if powerType ~= 8 then
                resources[#resources + 1] = powerType
            end
        end
        return AddHealthResourceConfig(resources)
    end

    if specID and SPEC_RESOURCES_CONFIG[specID] then
        return AddHealthResourceConfig(SPEC_RESOURCES_CONFIG[specID])
    end

    return AddHealthResourceConfig(CLASS_RESOURCES_CONFIG[classID] or {})
end

------------------------------------------------------------------------
-- Collapsed section state
------------------------------------------------------------------------
local resourceBarCollapsedSections = {}

local function CopyTableValue(value)
    return type(value) == "table" and CopyTable(value) or value
end

local function GetCurrentConfigSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        return C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end
    return nil
end

local function AddUniqueResource(result, seen, powerType)
    if powerType == nil or powerType == RESOURCE_HEALTH or seen[powerType] then
        return
    end
    result[#result + 1] = powerType
    seen[powerType] = true
end

local function ResourceListContains(resourceList, powerType)
    if type(resourceList) ~= "table" then
        return false
    end
    for _, listedPowerType in ipairs(resourceList) do
        if listedPowerType == powerType then
            return true
        end
    end
    return false
end

local function IsResourceConfigEnabled(settings, powerType)
    local resource = settings and settings.resources and settings.resources[powerType]
    return not (type(resource) == "table" and resource.enabled == false)
end

local function GetPlayerClassAndSpecsConfig()
    local _, _, classID = UnitClass("player")
    local specIDs = {}
    local numSpecs = GetNumSpecializations() or 0
    for specIndex = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    return classID, specIDs
end

local function GetConfigEditableResources(settings, includeDisabled)
    settings = settings or CooldownCompanion:GetResourceBarSettings()
    if not (type(settings) == "table" and settings.enabled == true) then
        return {}
    end

    local classID, specIDs = GetPlayerClassAndSpecsConfig()
    if not classID then
        return {}
    end

    local result = {}
    local seen = {}
    for _, powerType in ipairs(CLASS_RESOURCES_CONFIG[classID] or {}) do
        if includeDisabled or IsResourceConfigEnabled(settings, powerType) then
            AddUniqueResource(result, seen, powerType)
        end
    end

    for _, specID in ipairs(specIDs) do
        for _, powerType in ipairs(SPEC_RESOURCES_CONFIG[specID] or {}) do
            if includeDisabled or IsResourceConfigEnabled(settings, powerType) then
                AddUniqueResource(result, seen, powerType)
            end
        end
    end

    return result
end

local function GetResourceApplicableSpecIDs(powerType)
    local classID, specIDs = GetPlayerClassAndSpecsConfig()
    if not classID or powerType == nil or powerType == RESOURCE_HEALTH then
        return {}
    end

    local applicable = {}
    for _, specID in ipairs(specIDs) do
        local belongs
        if classID == DRUID_CLASS_ID then
            if powerType == 8 then
                belongs = specID == DRUID_BALANCE_SPEC_ID
            else
                belongs = ResourceListContains(CLASS_RESOURCES_CONFIG[DRUID_CLASS_ID], powerType)
            end
        elseif SPEC_RESOURCES_CONFIG[specID] then
            belongs = ResourceListContains(SPEC_RESOURCES_CONFIG[specID], powerType)
        else
            belongs = ResourceListContains(CLASS_RESOURCES_CONFIG[classID], powerType)
        end
        if belongs then
            applicable[#applicable + 1] = specID
        end
    end
    return applicable
end

local function IsResourceEditableInColumn4(powerType, settings, includeDisabled)
    settings = settings or CooldownCompanion:GetResourceBarSettings()
    if powerType == nil or powerType == RESOURCE_HEALTH then
        return false
    end
    if not (type(settings) == "table" and settings.enabled == true) then
        return false
    end
    if not includeDisabled and not IsResourceConfigEnabled(settings, powerType) then
        return false
    end
    return #GetResourceApplicableSpecIDs(powerType) > 0
end

local function GetDefaultResourceSettingsSpecID(powerType, preferredSpecID)
    local applicable = GetResourceApplicableSpecIDs(powerType)
    if #applicable == 0 then
        return nil
    end

    if preferredSpecID then
        for _, specID in ipairs(applicable) do
            if specID == preferredSpecID then
                return specID
            end
        end
    end
    local currentSpecID = GetCurrentConfigSpecID()
    for _, specID in ipairs(applicable) do
        if specID == currentSpecID then
            return specID
        end
    end
    return applicable[1]
end

------------------------------------------------------------------------
-- Spec override helpers
------------------------------------------------------------------------

-- Returns specOverrides[specID] table, auto-vivifying intermediate tables when
-- create is true. Returns nil if any level is missing and create is false.
local function GetSpecOverrideTable(settings, powerType, specID, create)
    if not specID then return nil end
    if not settings.resources then
        if create then settings.resources = {} else return nil end
    end
    if not settings.resources[powerType] then
        if create then settings.resources[powerType] = {} else return nil end
    end
    local resource = settings.resources[powerType]
    if not resource.specOverrides then
        if create then resource.specOverrides = {} else return nil end
    end
    if not resource.specOverrides[specID] then
        if create then resource.specOverrides[specID] = {} else return nil end
    end
    return resource.specOverrides[specID]
end

-- Resolves a per-spec override key with a caller-supplied default.
-- Uses the shared resolver: specOverrides[specID][key] -> resource[key] -> default.
local function ReadSpecOverrideKey(settings, powerType, specID, key, default)
    local resource = settings.resources and settings.resources[powerType]
    if not resource then return default end
    local resolved = ResolveSpecOverrideKey(resource, specID, key)
    if resolved ~= nil then return resolved end
    return default
end

-- Writes a key into specOverrides[specID]. Passing value=nil clears the key and
-- prunes empty tables to keep SavedVariables clean.
local function WriteSpecOverrideKey(settings, powerType, specID, key, value)
    if not specID then
        geterrorhandler()("WriteSpecOverrideKey: nil specID for key " .. tostring(key))
        return
    end
    if value == nil then
        local specTable = GetSpecOverrideTable(settings, powerType, specID, false)
        if specTable then
            specTable[key] = nil
            if not next(specTable) then
                local resource = settings.resources and settings.resources[powerType]
                if resource and resource.specOverrides then
                    resource.specOverrides[specID] = nil
                    if not next(resource.specOverrides) then
                        resource.specOverrides = nil
                    end
                end
            end
        end
    else
        local specTable = GetSpecOverrideTable(settings, powerType, specID, true)
        specTable[key] = value
    end
end

------------------------------------------------------------------------
-- More query functions
------------------------------------------------------------------------

local function GetPlayerSpecOptionsConfig()
    local specList = {}
    local specOrder = {}
    local specInfoByID = {}

    for i = 1, (GetNumSpecializations() or 0) do
        local specID, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID and name then
            specList[specID] = name
            specOrder[#specOrder + 1] = specID
            specInfoByID[specID] = {
                specID = specID,
                name = name,
                icon = icon,
                order = i,
            }
        end
    end

    return specList, specOrder, specInfoByID
end

local function ResolveAuraColorSpellIDFromText(text)
    if not text then return nil, false end
    local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then
        return nil, true
    end

    local numeric = tonumber(cleaned)
    if numeric and numeric > 0 then
        return numeric, false
    end

    local entry = ResolveAuraBarAutocompleteEntry(cleaned)
    if entry then
        return entry.id, false
    end

    local spellInfo = C_Spell.GetSpellInfo(cleaned)
    if spellInfo and spellInfo.spellID then
        return spellInfo.spellID, false
    end

    if CooldownCompanion.FindTalentSpellByName then
        local spellID = CooldownCompanion:FindTalentSpellByName(cleaned)
        if spellID then
            return spellID, false
        end
    end

    return nil, false
end

local function GetSafeRGBConfig(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

-- Identical to GetSafeRGBConfig; alias kept for call-site clarity (RGB vs RGBA intent)
local GetSafeRGBAConfig = GetSafeRGBConfig

local function CopyRGBConfig(color)
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        return nil
    end
    return { color[1], color[2], color[3] }
end

local function GetSegmentedThresholdValueConfig(resource)
    local value = tonumber(resource and resource.segThresholdValue)
    if not value then
        return 1
    end
    value = math.floor(value)
    if value < 1 then
        value = 1
    elseif value > 99 then
        value = 99
    end
    return value
end

local function GetContinuousTickModeConfig(resource)
    local mode = resource and resource.continuousTickMode
    if mode == "percent" or mode == "absolute" then
        return mode
    end
    return DEFAULT_CONTINUOUS_TICK_MODE
end

local function GetContinuousTickPercentConfig(resource)
    local value = tonumber(resource and resource.continuousTickPercent)
    if not value then
        return DEFAULT_CONTINUOUS_TICK_PERCENT
    end
    if value < 0 then
        value = 0
    elseif value > 100 then
        value = 100
    end
    return value
end

local function GetContinuousTickAbsoluteConfig(resource)
    local value = tonumber(resource and resource.continuousTickAbsolute)
    if not value then
        return DEFAULT_CONTINUOUS_TICK_ABSOLUTE
    end
    if value < 0 then
        value = 0
    end
    return value
end

-- Simple queries
------------------------------------------------------------------------

local function IsResourceBarVerticalConfig(settings, layout)
    if layout and layout.orientation ~= nil then
        return layout.orientation == "vertical"
    end
    return settings and settings.orientation == "vertical"
end

local function GetResourceThicknessFieldConfig(settings, layout)
    if IsResourceBarVerticalConfig(settings, layout) then
        return "barWidth", "Bar Width", "Custom Resource Bar Widths"
    end
    return "barHeight", "Bar Height", "Custom Resource Bar Heights"
end

local function GetResourceGapFieldConfig(settings, layout)
    if IsResourceBarVerticalConfig(settings, layout) then
        return "verticalXOffset", "X Offset"
    end
    return "yOffset", "Y Offset"
end

local function OpenResourceBarConflictChooser(force)
    local classKey = CooldownCompanion.GetCurrentResourceBarClassKey and CooldownCompanion:GetCurrentResourceBarClassKey()
    local showChooser = ST._ShowResourceBarConflictChooser
    if showChooser then
        return showChooser(classKey, { force = force })
    end
    CooldownCompanion:Print("Resource Bar conflict chooser is unavailable.")
    return false
end

local function BuildResourceBarConflictGate(container, editSurface, autoOpen)
    local conflict = CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict()
    if not conflict then
        return false
    end

    local classKey = CooldownCompanion.GetCurrentResourceBarClassKey and CooldownCompanion:GetCurrentResourceBarClassKey() or "current class"
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText("Resource Bars for " .. tostring(classKey) .. " have multiple legacy setups. Choose one setup before editing " .. (editSurface or "Resource Bars") .. ".")
    label:SetFullWidth(true)
    container:AddChild(label)

    local resolveBtn = AceGUI:Create("Button")
    resolveBtn:SetText("Resolve Resource Bars")
    resolveBtn:SetFullWidth(true)
    resolveBtn:SetCallback("OnClick", function()
        OpenResourceBarConflictChooser(true)
    end)
    container:AddChild(resolveBtn)
    CS.resourceBarConflictResolveButton = resolveBtn

    if autoOpen and not (CS.resourceBarConflictChooserDismissed and CS.resourceBarConflictChooserDismissed[classKey]) then
        local function openIfStillPending()
            if CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
                OpenResourceBarConflictChooser(false)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, openIfStillPending)
        else
            openIfStillPending()
        end
    end

    return true
end

------------------------------------------------------------------------
-- Export via ST._RBP
------------------------------------------------------------------------

ST._RBP = {
    collapsedSections = resourceBarCollapsedSections,
    CopyTableValue = CopyTableValue,
    GetConfigActiveResources = GetConfigActiveResources,
    GetConfigEditableResources = GetConfigEditableResources,
    GetResourceApplicableSpecIDs = GetResourceApplicableSpecIDs,
    IsResourceEditableInColumn4 = IsResourceEditableInColumn4,
    GetDefaultResourceSettingsSpecID = GetDefaultResourceSettingsSpecID,
    GetCurrentConfigSpecID = GetCurrentConfigSpecID,
    GetSpecOverrideTable = GetSpecOverrideTable,
    ReadSpecOverrideKey = ReadSpecOverrideKey,
    WriteSpecOverrideKey = WriteSpecOverrideKey,
    GetPlayerSpecOptionsConfig = GetPlayerSpecOptionsConfig,
    ResolveAuraColorSpellIDFromText = ResolveAuraColorSpellIDFromText,
    GetSafeRGBConfig = GetSafeRGBConfig,
    GetSafeRGBAConfig = GetSafeRGBAConfig,
    CopyRGBConfig = CopyRGBConfig,
    GetSegmentedThresholdValueConfig = GetSegmentedThresholdValueConfig,
    GetContinuousTickModeConfig = GetContinuousTickModeConfig,
    GetContinuousTickPercentConfig = GetContinuousTickPercentConfig,
    GetContinuousTickAbsoluteConfig = GetContinuousTickAbsoluteConfig,
    GetAuraBarAutocompleteDisplayName = GetAuraBarAutocompleteDisplayName,
    GetAuraBarAutocompleteDisplayIcon = GetAuraBarAutocompleteDisplayIcon,
    GetAuraBarAutocompleteEntryName = GetAuraBarAutocompleteEntryName,
    ResolveAuraBarAutocompleteEntry = ResolveAuraBarAutocompleteEntry,
    ShowAuraBarAutocompleteResults = ShowAuraBarAutocompleteResults,
    BuildAuraBarAutocompleteCache = BuildAuraBarAutocompleteCache,
    IsResourceBarVerticalConfig = IsResourceBarVerticalConfig,
    GetResourceThicknessFieldConfig = GetResourceThicknessFieldConfig,
    GetResourceGapFieldConfig = GetResourceGapFieldConfig,
    BuildResourceBarConflictGate = BuildResourceBarConflictGate,
}
