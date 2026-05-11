--[[
    CooldownCompanion - ResourceBarHelpers
    Pure query/helper functions with no mutable state writes (aside from
    auto-vivification of config tables and a power-type secrecy memoization
    cache). Used by both ResourceBar.lua and ResourceBarVisuals.lua at runtime.

    All functions are added to ST._RB so consuming files can alias them to
    locals at load time.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_floor = math.floor
local string_format = string.format
local SecretsAPI = C_Secrets

-- Import constants from ResourceBarConstants
local RB = ST._RB
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local RESOURCE_COLOR_DEFS = RB.RESOURCE_COLOR_DEFS
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_PERCENT = RB.DEFAULT_CONTINUOUS_TICK_PERCENT
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = RB.DEFAULT_CONTINUOUS_TICK_ABSOLUTE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = RB.DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local CLASS_RESOURCES = RB.CLASS_RESOURCES
local SPEC_RESOURCES = RB.SPEC_RESOURCES
local DRUID_FORM_RESOURCES = RB.DRUID_FORM_RESOURCES
local DRUID_DEFAULT_RESOURCES = RB.DRUID_DEFAULT_RESOURCES
local DRUID_BALANCE_SPEC_ID = 102

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

local RESOURCE_DISPLAY_PROFILE_KEYS = {
    "barTexture",
    "classBarBrightness",
    "backgroundColor",
    "borderStyle",
    "borderColor",
    "borderSize",
}

local RESOURCE_TEXT_DISPLAY_KEYS = {
    "showText",
    "textFormat",
    "textFont",
    "textFontSize",
    "textFontOutline",
    "textFontColor",
    "textAnchor",
    "textXOffset",
    "textYOffset",
    "hideTextAtZero",
}

local RESOURCE_HEALTH_DISPLAY_KEYS = {
    "healthBarColor",
    "healthBarOpacity",
    "healthBarGradient",
    "healthBarFullColor",
    "healthBarHalfColor",
    "healthBarLowColor",
    "healthBackgroundColor",
    "healthBackgroundGradient",
    "healthBackgroundFullColor",
    "healthBackgroundHalfColor",
    "healthBackgroundLowColor",
    "healthBackgroundOpacity",
    "showAbsorbs",
    "showHealAbsorbs",
    "showIncomingHeals",
    "showLowHealthAlert",
    "healthAbsorbColor",
    "healthAbsorbTexture",
    "healthHealAbsorbColor",
    "healthHealAbsorbTexture",
    "healthIncomingHealColor",
    "healthIncomingHealTexture",
    "healthLowHealthAlertColor",
    "healthLowHealthAlertTexture",
    "healthLowHealthAlertMissingHealthOnly",
}

------------------------------------------------------------------------
-- Layout Helpers
------------------------------------------------------------------------

local GetSpecLayoutOrder

local function GetResourceBarSettings()
    return CooldownCompanion:GetResourceBarSettings()
end

local function GetResourceLayout(settings)
    if type(settings) ~= "table" then return nil end
    return GetSpecLayoutOrder and GetSpecLayoutOrder(settings) or nil
end

local function GetResourceLayoutValue(settings, key, fallback)
    local layout = GetResourceLayout(settings)
    if layout and layout[key] ~= nil then
        return layout[key]
    end
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    return fallback
end

local function IsVerticalResourceLayout(settings)
    return GetResourceLayoutValue(settings, "orientation", "horizontal") == "vertical"
end

local function GetResourceLayoutOrientation(settings)
    return IsVerticalResourceLayout(settings) and "vertical" or "horizontal"
end

local function IsVerticalFillReversed(settings)
    if not IsVerticalResourceLayout(settings) then
        return false
    end
    return GetResourceLayoutValue(settings, "verticalFillDirection", "bottom_to_top") == "top_to_bottom"
end

local function GetResourcePrimaryLength(groupFrame, settings)
    if not groupFrame then return 0 end
    if IsVerticalResourceLayout(settings) then
        return groupFrame:GetHeight()
    end
    return groupFrame:GetWidth()
end

local function GetResourceGlobalThickness(settings)
    if IsVerticalResourceLayout(settings) then
        return GetResourceLayoutValue(settings, "barWidth")
            or GetResourceLayoutValue(settings, "barHeight")
            or 12
    end
    return GetResourceLayoutValue(settings, "barHeight")
        or GetResourceLayoutValue(settings, "barWidth")
        or 12
end

local function GetResourceAnchorGap(settings, layout)
    layout = layout or GetResourceLayout(settings)
    if IsVerticalResourceLayout(settings) then
        return (layout and (layout.verticalXOffset or layout.yOffset))
            or settings.verticalXOffset
            or settings.yOffset
            or 3
    end
    return (layout and (layout.yOffset or layout.verticalXOffset))
        or settings.yOffset
        or settings.verticalXOffset
        or 3
end

local function GetVerticalSideFallback(horizontalSide)
    return horizontalSide == "above" and "left" or "right"
end

local function GetEffectiveAnchorGroupId(settings)
    if not settings then return nil end
    return CooldownCompanion:GetFirstAvailableAnchorGroup()
end

local function GetAnchorGroupFrame(settings)
    local groupId = GetEffectiveAnchorGroupId(settings)
    if not groupId then return nil end
    return CooldownCompanion.groupFrames[groupId]
end

local function GetCurrentSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return specID
    end
    return nil
end

local function GetPlayerClassID()
    local _, _, classID = UnitClass("player")
    return classID
end

local function IsConfiguredCustomBar(cab)
    return type(cab) == "table"
        and (
            cab.spellID ~= nil
            or cab.entryType ~= nil
            or cab.enabled == true
            or cab.independentAnchorEnabled ~= nil
            or cab.trackingMode ~= nil
            or cab.displayMode ~= nil
            or cab.maxStacks ~= nil
            or cab.barColor ~= nil
            or cab.soundAlerts ~= nil
            or cab.loadConditions ~= nil
            or cab.talentConditions ~= nil
        )
end

local function GetCustomBarEntryType(cab)
    if type(cab) == "table" and cab.entryType == "spell" then
        return "spell"
    end
    return "aura"
end

local function NormalizeCustomBarEntryType(cab)
    if type(cab) ~= "table" then
        return "aura"
    end
    cab.entryType = GetCustomBarEntryType(cab)
    return cab.entryType
end

local function CustomBarIdOwnedByOther(settings, customBarId, owner)
    if type(settings) ~= "table"
        or type(settings.customBars) ~= "table"
        or type(customBarId) ~= "string"
        or customBarId == "" then
        return false
    end

    for _, specBars in pairs(settings.customBars) do
        if type(specBars) == "table" then
            for _, entry in pairs(specBars) do
                if entry ~= owner
                    and type(entry) == "table"
                    and entry.customBarId == customBarId then
                    return true
                end
            end
        end
    end
    return false
end

local function EnsureCustomBarId(settings, entry)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return nil
    end

    if type(entry.customBarId) == "string"
        and entry.customBarId ~= ""
        and not CustomBarIdOwnedByOther(settings, entry.customBarId, entry) then
        return entry.customBarId
    end

    settings.nextCustomBarId = tonumber(settings.nextCustomBarId) or 1
    local id
    repeat
        id = "custom_bar_" .. tostring(settings.nextCustomBarId)
        settings.nextCustomBarId = settings.nextCustomBarId + 1
    until not CustomBarIdOwnedByOther(settings, id, entry)
    entry.customBarId = id
    return id
end

local function EnsureCustomBarLayout(settings, specID, customBarId, fallbackOrder)
    local layout = GetSpecLayoutOrder and GetSpecLayoutOrder(settings, specID)
    if type(layout) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end

    if type(layout.customBars) ~= "table" then
        layout.customBars = {}
    end
    if type(layout.customBars[customBarId]) ~= "table" then
        layout.customBars[customBarId] = {
            position = "below",
            order = fallbackOrder or 1000,
        }
    end
    return layout.customBars[customBarId]
end

local function GetCustomBarLayout(settings, specID, entry, create)
    if type(entry) ~= "table" then
        return nil
    end
    local customBarId = entry.customBarId
    local layout = GetSpecLayoutOrder and GetSpecLayoutOrder(settings, specID)
    if type(layout) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end
    if type(layout.customBars) ~= "table" then
        if not create then return nil end
        layout.customBars = {}
    end
    if type(layout.customBars[customBarId]) ~= "table" and create then
        layout.customBars[customBarId] = { position = "below", order = 1000 }
    end
    return layout.customBars[customBarId]
end

local function MigrateLegacyCustomAuraBars(settings, specID, target)
    specID = tonumber(specID) or specID
    local legacyBySpec = type(settings.customAuraBars) == "table" and settings.customAuraBars or nil
    local legacyBars = legacyBySpec and (legacyBySpec[specID] or legacyBySpec[tostring(specID)])
    if type(legacyBars) ~= "table" then
        return
    end

    local numericSlots = {}
    for slotIdx in pairs(legacyBars) do
        if tonumber(slotIdx) then
            numericSlots[#numericSlots + 1] = tonumber(slotIdx)
        end
    end
    table.sort(numericSlots)

    local layout = GetSpecLayoutOrder and GetSpecLayoutOrder(settings, specID)
    for _, slotIdx in ipairs(numericSlots) do
        local cab = legacyBars[slotIdx] or legacyBars[tostring(slotIdx)]
        if IsConfiguredCustomBar(cab) then
            local entry = CopyTable(cab)
            entry.entryType = "aura"
            local id = EnsureCustomBarId(settings, entry)
            target[#target + 1] = entry

            local legacyLayout = layout
                and type(layout.customAuraBarSlots) == "table"
                and layout.customAuraBarSlots[slotIdx]
            if type(legacyLayout) == "table" and id then
                if type(layout.customBars) ~= "table" then
                    layout.customBars = {}
                end
                layout.customBars[id] = CopyTable(legacyLayout)
            else
                EnsureCustomBarLayout(settings, specID, id, 1000 + #target)
            end
        end
    end
end

local function NormalizeCustomBars(settings, specID)
    if type(settings.customBars) ~= "table" then
        settings.customBars = {}
    end

    specID = tonumber(specID) or specID
    local stringSpecID = tostring(specID)
    local specBars = settings.customBars[specID]
    if type(specBars) ~= "table" and stringSpecID ~= specID and type(settings.customBars[stringSpecID]) == "table" then
        specBars = settings.customBars[stringSpecID]
        settings.customBars[specID] = specBars
        settings.customBars[stringSpecID] = nil
    end

    if type(specBars) ~= "table" then
        specBars = {}
        settings.customBars[specID] = specBars
        MigrateLegacyCustomAuraBars(settings, specID, specBars)
    end

    local compact = {}
    local numericKeys = {}
    for key in pairs(specBars) do
        if type(key) == "number" then
            numericKeys[#numericKeys + 1] = key
        end
    end
    table.sort(numericKeys)

    local seen = {}
    for _, key in ipairs(numericKeys) do
        local entry = specBars[key]
        if IsConfiguredCustomBar(entry) then
            NormalizeCustomBarEntryType(entry)
            EnsureCustomBarId(settings, entry)
            compact[#compact + 1] = entry
        end
        seen[key] = true
    end

    for key, entry in pairs(specBars) do
        if not seen[key] and IsConfiguredCustomBar(entry) then
            NormalizeCustomBarEntryType(entry)
            EnsureCustomBarId(settings, entry)
            compact[#compact + 1] = entry
        end
    end

    wipe(specBars)
    for index, entry in ipairs(compact) do
        specBars[index] = entry
    end
    settings.customBars[specID] = specBars
    return specBars
end

local function GetSpecCustomAuraBars(settings)
    local specID = GetCurrentSpecID()
    if not specID then return {} end
    return NormalizeCustomBars(settings, specID)
end

local function IsValidCustomAuraUnit(unit)
    return unit == "player" or unit == "target"
end

local function GetDefaultCustomAuraUnit(spellID)
    return (spellID and C_Spell.IsSpellHarmful(spellID)) and "target" or "player"
end

local function HasExplicitCustomAuraBarAuraUnit(cabConfig)
    return type(cabConfig) == "table"
        and cabConfig.auraUnitExplicit == true
        and IsValidCustomAuraUnit(cabConfig.auraUnit)
end

local function GetResolvedCustomAuraBarAuraUnit(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" and (cabConfig.entryType == nil or cabConfig.entryType == "aura") then
        return GetDefaultCustomAuraUnit(resolvedSpellID)
    end

    if type(cabConfig) == "table" and IsValidCustomAuraUnit(cabConfig.auraUnit) then
        return cabConfig.auraUnit
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
end

local function EnsureCustomAuraBarAuraUnit(cabConfig, spellID, unit, explicit)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" then
        if cabConfig.entryType == nil or cabConfig.entryType == "aura" then
            local resolvedUnit = GetDefaultCustomAuraUnit(resolvedSpellID)
            cabConfig.auraUnit = resolvedUnit
            cabConfig.auraUnitExplicit = nil
            return resolvedUnit
        end

        local wasExplicit = HasExplicitCustomAuraBarAuraUnit(cabConfig)
        local resolvedUnit = IsValidCustomAuraUnit(unit) and unit
            or GetResolvedCustomAuraBarAuraUnit(cabConfig, resolvedSpellID)

        cabConfig.auraUnit = resolvedUnit

        if IsValidCustomAuraUnit(unit) then
            cabConfig.auraUnitExplicit = explicit == false and nil or true
        elseif not wasExplicit then
            cabConfig.auraUnitExplicit = nil
        end

        if IsValidCustomAuraUnit(cabConfig.auraUnit) then
            return cabConfig.auraUnit
        end
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
end

local function RefreshCustomAuraBarAuraUnitForSpell(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if HasExplicitCustomAuraBarAuraUnit(cabConfig) then
        return cabConfig.auraUnit
    end

    return EnsureCustomAuraBarAuraUnit(cabConfig, resolvedSpellID, GetDefaultCustomAuraUnit(resolvedSpellID), false)
end

local function IsValidResourceAuraUnit(unit)
    return unit == "player" or unit == "target"
end

local function GetDefaultResourceAuraUnit(spellID)
    return (spellID and C_Spell.IsSpellHarmful(spellID)) and "target" or "player"
end

local function HasExplicitResourceAuraUnit(resourceAuraEntry)
    return type(resourceAuraEntry) == "table"
        and resourceAuraEntry.auraUnitExplicit == true
        and IsValidResourceAuraUnit(resourceAuraEntry.auraUnit)
end

local function GetResolvedResourceAuraUnit(resourceAuraEntry, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(resourceAuraEntry) == "table" then
        resolvedSpellID = tonumber(resourceAuraEntry.auraColorSpellID) or nil
    end

    if type(resourceAuraEntry) == "table" and IsValidResourceAuraUnit(resourceAuraEntry.auraUnit) then
        return resourceAuraEntry.auraUnit
    end

    return GetDefaultResourceAuraUnit(resolvedSpellID)
end

local function EnsureResourceAuraUnit(resourceAuraEntry, spellID, unit, explicit)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(resourceAuraEntry) == "table" then
        resolvedSpellID = tonumber(resourceAuraEntry.auraColorSpellID) or nil
    end

    if type(resourceAuraEntry) == "table" then
        local wasExplicit = HasExplicitResourceAuraUnit(resourceAuraEntry)
        local resolvedUnit = IsValidResourceAuraUnit(unit) and unit
            or GetResolvedResourceAuraUnit(resourceAuraEntry, resolvedSpellID)

        resourceAuraEntry.auraUnit = resolvedUnit

        if IsValidResourceAuraUnit(unit) then
            resourceAuraEntry.auraUnitExplicit = explicit == false and nil or true
        elseif not wasExplicit then
            resourceAuraEntry.auraUnitExplicit = nil
        end

        if IsValidResourceAuraUnit(resourceAuraEntry.auraUnit) then
            return resourceAuraEntry.auraUnit
        end
    end

    return GetDefaultResourceAuraUnit(resolvedSpellID)
end

local function RefreshResourceAuraUnitForSpell(resourceAuraEntry, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(resourceAuraEntry) == "table" then
        resolvedSpellID = tonumber(resourceAuraEntry.auraColorSpellID) or nil
    end

    if HasExplicitResourceAuraUnit(resourceAuraEntry) then
        return resourceAuraEntry.auraUnit
    end

    return EnsureResourceAuraUnit(resourceAuraEntry, resolvedSpellID, GetDefaultResourceAuraUnit(resolvedSpellID), false)
end

local function CopyIndependentAnchor(anchor)
    if type(anchor) ~= "table" then
        return nil
    end
    return CopyTable(anchor)
end

local function SeedResourceLayoutFromGlobal(layout, settings, cbSettings, specID)
    if type(layout) ~= "table" or type(settings) ~= "table" then
        return layout
    end

    if type(layout.resources) ~= "table" then layout.resources = {} end
    if type(layout.customAuraBarSlots) ~= "table" then layout.customAuraBarSlots = {} end
    if type(layout.customBars) ~= "table" then layout.customBars = {} end
    if type(layout.castBar) ~= "table" then layout.castBar = {} end

    if layout.independentAnchorEnabled == nil then
        layout.independentAnchorEnabled = settings.independentAnchorEnabled == true
    end
    if layout.orientation == nil then layout.orientation = settings.orientation or "horizontal" end
    if layout.verticalFillDirection == nil then layout.verticalFillDirection = settings.verticalFillDirection or "bottom_to_top" end
    if layout.barSpacing == nil then layout.barSpacing = settings.barSpacing or 3.6 end
    if layout.segmentGap == nil then layout.segmentGap = settings.segmentGap or 4 end
    if layout.barHeight == nil then layout.barHeight = settings.barHeight or 12 end
    if layout.barWidth == nil then layout.barWidth = settings.barWidth or layout.barHeight or 12 end
    if layout.customBarHeights == nil then layout.customBarHeights = settings.customBarHeights == true end
    if layout.inheritAlpha == nil then layout.inheritAlpha = settings.inheritAlpha == true end
    if layout.yOffset == nil then layout.yOffset = settings.yOffset or 3 end
    if layout.verticalXOffset == nil then layout.verticalXOffset = settings.verticalXOffset or layout.yOffset or 3 end
    if layout.independentWidth == nil then layout.independentWidth = settings.independentWidth end
    if layout.independentAnchorLocked == nil then layout.independentAnchorLocked = settings.independentAnchorLocked end
    if type(layout.independentAnchor) ~= "table" then
        layout.independentAnchor = CopyIndependentAnchor(settings.independentAnchor)
    end

    if type(settings.resources) == "table" then
        for pt, res in pairs(settings.resources) do
            if type(res) == "table" and (res.barHeight ~= nil or res.barWidth ~= nil) then
                if type(layout.resources[pt]) ~= "table" then layout.resources[pt] = {} end
                local target = layout.resources[pt]
                if target.barHeight == nil then target.barHeight = res.barHeight end
                if target.barWidth == nil then target.barWidth = res.barWidth end
            end
        end
    end

    if specID and type(settings.customBars) == "table" and type(settings.customBars[specID]) == "table" then
        for _, cab in pairs(settings.customBars[specID]) do
            local customBarId = type(cab) == "table" and cab.customBarId
            if type(customBarId) == "string" and (cab.barHeight ~= nil or cab.barWidth ~= nil) then
                if type(layout.customBars[customBarId]) ~= "table" then layout.customBars[customBarId] = {} end
                local target = layout.customBars[customBarId]
                if target.barHeight == nil then target.barHeight = cab.barHeight end
                if target.barWidth == nil then target.barWidth = cab.barWidth end
            end
        end
    end

    if type(cbSettings) ~= "table" and CooldownCompanion.GetCastBarSettings then
        cbSettings = CooldownCompanion:GetCastBarSettings()
    end
    if type(cbSettings) == "table" then
        if layout.castBar.position == nil then layout.castBar.position = cbSettings.position or "below" end
        if layout.castBar.order == nil then layout.castBar.order = cbSettings.order or 2000 end
        if layout.castBar.panelAnchorYOffsetEnabled == nil then
            layout.castBar.panelAnchorYOffsetEnabled = cbSettings.panelAnchorYOffsetEnabled == true
        end
        if layout.castBar.panelAnchorYOffset == nil then
            layout.castBar.panelAnchorYOffset = cbSettings.panelAnchorYOffset or 0
        end
    else
        if layout.castBar.position == nil then layout.castBar.position = "below" end
        if layout.castBar.order == nil then layout.castBar.order = 2000 end
        if layout.castBar.panelAnchorYOffsetEnabled == nil then layout.castBar.panelAnchorYOffsetEnabled = false end
        if layout.castBar.panelAnchorYOffset == nil then layout.castBar.panelAnchorYOffset = 0 end
    end

    return layout
end

local function CreateDefaultLayoutOrder(settings, cbSettings, specID)
    return SeedResourceLayoutFromGlobal({
        resources = {},
        customAuraBarSlots = {},
        customBars = {},
        castBar = { position = "below", order = 2000 },
    }, settings, cbSettings, specID)
end

GetSpecLayoutOrder = function(settings, specID)
    if type(settings) ~= "table" then return nil end
    specID = specID or GetCurrentSpecID()
    if not specID then return nil end
    specID = tonumber(specID) or specID
    if not settings.layoutOrder then settings.layoutOrder = {} end
    if type(settings.layoutOrder[specID]) ~= "table" then
        settings.layoutOrder[specID] = CreateDefaultLayoutOrder(settings, nil, specID)
    else
        SeedResourceLayoutFromGlobal(settings.layoutOrder[specID], settings, nil, specID)
    end
    return settings.layoutOrder[specID]
end

local function SeedResourceDisplayProfileFromGlobal(profile, settings)
    if type(profile) ~= "table" or type(settings) ~= "table" then
        return profile
    end
    for _, key in ipairs(RESOURCE_DISPLAY_PROFILE_KEYS) do
        if profile[key] == nil then
            local value = settings[key]
            profile[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    if profile.barTexture == nil then profile.barTexture = "Solid" end
    if profile.backgroundColor == nil then profile.backgroundColor = { 0, 0, 0, 0.5 } end
    if profile.borderStyle == nil then profile.borderStyle = "pixel" end
    if profile.borderColor == nil then profile.borderColor = { 0, 0, 0, 1 } end
    if profile.borderSize == nil then profile.borderSize = 1 end
    if profile.classBarBrightness == nil then profile.classBarBrightness = 1.3 end
    return profile
end

local function GetSpecResourceDisplayProfile(settings, specID)
    if type(settings) ~= "table" then return nil end
    specID = specID or GetCurrentSpecID()
    if not specID then return nil end
    specID = tonumber(specID) or specID
    if type(settings.displayProfiles) ~= "table" then
        settings.displayProfiles = {}
    end
    if type(settings.displayProfiles[specID]) ~= "table" then
        settings.displayProfiles[specID] = {}
    end
    return SeedResourceDisplayProfileFromGlobal(settings.displayProfiles[specID], settings)
end

local function GetResourceDisplayValue(settings, key, fallback)
    local profile = GetSpecResourceDisplayProfile(settings)
    if profile and profile[key] ~= nil then
        return profile[key]
    end
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    return fallback
end

local function GetResourceDisplayConfig(settings, powerType)
    local resource = settings and settings.resources and settings.resources[powerType]
    if type(resource) ~= "table" then return nil end
    local specID = GetCurrentSpecID()
    if not specID then return resource end
    local resolved = CopyTable(resource)
    local specOverrides = resource.specOverrides
    local specData = type(specOverrides) == "table" and (specOverrides[specID] or specOverrides[tostring(specID)]) or nil
    if type(specData) == "table" then
        for key, value in pairs(specData) do
            resolved[key] = value
        end
    end
    return resolved
end

local function GetResourceSpecOverrideTable(settings, powerType, specID, create)
    if type(settings) ~= "table" or not specID then return nil end
    specID = tonumber(specID) or specID
    if type(settings.resources) ~= "table" then
        if not create then return nil end
        settings.resources = {}
    end
    if type(settings.resources[powerType]) ~= "table" then
        if not create then return nil end
        settings.resources[powerType] = {}
    end
    local resource = settings.resources[powerType]
    if type(resource.specOverrides) ~= "table" then
        if not create then return nil end
        resource.specOverrides = {}
    end
    if type(resource.specOverrides[specID]) ~= "table" then
        if not create then return nil end
        resource.specOverrides[specID] = {}
    end
    return resource.specOverrides[specID]
end

local function GetAnchorOffset(point, width, height)
    if point == "TOPLEFT" then
        return -width / 2, height / 2
    elseif point == "TOP" then
        return 0, height / 2
    elseif point == "TOPRIGHT" then
        return width / 2, height / 2
    elseif point == "LEFT" then
        return -width / 2, 0
    elseif point == "CENTER" then
        return 0, 0
    elseif point == "RIGHT" then
        return width / 2, 0
    elseif point == "BOTTOMLEFT" then
        return -width / 2, -height / 2
    elseif point == "BOTTOM" then
        return 0, -height / 2
    elseif point == "BOTTOMRIGHT" then
        return width / 2, -height / 2
    end
    return 0, 0
end

------------------------------------------------------------------------
-- Independent Anchor Validation Helpers
------------------------------------------------------------------------

local function RoundToTenths(value)
    return math_floor((tonumber(value) or 0) * 10 + 0.5) / 10
end

local function ClampIndependentDimension(value, fallback, minVal)
    local dim = tonumber(value) or tonumber(fallback) or 120
    minVal = minVal or 4
    if dim < minVal then
        dim = minVal
    elseif dim > 1200 then
        dim = 1200
    end
    return dim
end

local function IsTruthyConfigFlag(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function NormalizeCustomAuraIndependentOrientation(value)
    if value == "horizontal" or value == "vertical" then
        return value
    end
    return nil
end

local function NormalizeCustomAuraIndependentVerticalFillDirection(value)
    if value == "bottom_to_top" or value == "top_to_bottom" or value == "inherit" then
        return value
    end
    return "inherit"
end

local function IsCustomAuraBarIndependent(cabConfig)
    return type(cabConfig) == "table" and IsTruthyConfigFlag(cabConfig.independentAnchorEnabled)
end

------------------------------------------------------------------------
-- Resource Detection
------------------------------------------------------------------------

local function NormalizeCustomAuraStackTextFormat(textFormat)
    if textFormat == "current" or textFormat == "current_max" then
        return textFormat
    end
    return DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
end

local function IsHealerSpec()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        return role == "HEALER"
    end
    return false
end

local function IsAstralPowerAvailableForCurrentDruidSpec()
    return GetCurrentSpecID() == DRUID_BALANCE_SPEC_ID
end

local function GetDruidResources()
    local formID = GetShapeshiftFormID()
    if formID and DRUID_FORM_RESOURCES[formID] then
        local resources = DRUID_FORM_RESOURCES[formID]
        if formID == 31 and not IsAstralPowerAvailableForCurrentDruidSpec() then
            return DRUID_DEFAULT_RESOURCES
        end
        return resources
    end
    return DRUID_DEFAULT_RESOURCES
end

local function AddHealthResource(resources)
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

--- Determine which resources the current class/spec should display.
local function DetermineActiveResources()
    local classID = GetPlayerClassID()
    if not classID then return {} end

    -- Druid: form-dependent
    if classID == 11 then
        local resources = GetDruidResources()
        -- Always add Mana if not already present and not hidden
        local hasMana = false
        for _, pt in ipairs(resources) do
            if pt == 0 then hasMana = true; break end
        end
        if not hasMana then
            local result = {}
            for _, pt in ipairs(resources) do
                table.insert(result, pt)
            end
            table.insert(result, 0)
            return AddHealthResource(result)
        end
        return AddHealthResource(resources)
    end

    -- Check spec-specific override first
    local specID = GetCurrentSpecID()
    if specID and SPEC_RESOURCES[specID] then
        return AddHealthResource(SPEC_RESOURCES[specID])
    end

    return AddHealthResource(CLASS_RESOURCES[classID] or {})
end

------------------------------------------------------------------------
-- Color & Secret Functions
------------------------------------------------------------------------

--- Generic color resolver. Resolves per-spec overrides first, falling back to
--- resource-level values and then hardcoded defaults. Returns one color per key
--- defined in RESOURCE_COLOR_DEFS. For power types without an entry (generic
--- continuous), returns the single power color.
local function GetResourceColors(powerType, settings)
    local def = RESOURCE_COLOR_DEFS[powerType]
    local specID = GetCurrentSpecID()
    if not def then
        -- Generic single-color fallback (continuous resources)
        if settings and settings.resources then
            local override = settings.resources[powerType]
            if override then
                local resolved = ResolveSpecOverrideKey(override, specID, "color")
                if resolved then return resolved end
            end
        end
        return DEFAULT_POWER_COLORS[powerType] or { 1, 1, 1 }
    end

    local override = settings and settings.resources and settings.resources[powerType]
    local keys, defaults = def.keys, def.defaults
    local n = #keys
    if n == 2 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2]
    elseif n == 3 then
        return ResolveSpecOverrideKey(override, specID, keys[1]) or defaults[1],
               ResolveSpecOverrideKey(override, specID, keys[2]) or defaults[2],
               ResolveSpecOverrideKey(override, specID, keys[3]) or defaults[3]
    end
    -- Shouldn't happen, but safe fallback
    return defaults[1]
end

local POWER_SECRECY_CACHE = {}
local SECRET_LEVEL_NEVER = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret or 0

local function IsPowerTypePotentiallySecret(powerType)
    local cached = POWER_SECRECY_CACHE[powerType]
    if cached ~= nil then
        return cached
    end

    local potentiallySecret = true
    if SecretsAPI and SecretsAPI.GetPowerTypeSecrecy then
        potentiallySecret = SecretsAPI.GetPowerTypeSecrecy(powerType) ~= SECRET_LEVEL_NEVER
    end

    POWER_SECRECY_CACHE[powerType] = potentiallySecret
    return potentiallySecret
end

local function IsUnitPowerSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerBeSecret then
        return SecretsAPI.ShouldUnitPowerBeSecret(unit, powerType) == true
    end
    return false
end

local function IsUnitPowerMaxSecret(unit, powerType)
    if not IsPowerTypePotentiallySecret(powerType) then
        return false
    end
    if SecretsAPI and SecretsAPI.ShouldUnitPowerMaxBeSecret then
        return SecretsAPI.ShouldUnitPowerMaxBeSecret(unit, powerType) == true
    end
    return false
end

------------------------------------------------------------------------
-- Color/Config Helpers
------------------------------------------------------------------------

local function GetSafeRGBColor(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

-- Identical to GetSafeRGBColor; alias kept for call-site clarity (RGB vs RGBA intent)
local GetSafeRGBAColor = GetSafeRGBColor

local function GetSegmentedThresholdConfig(powerType, settings)
    if powerType ~= RESOURCE_MAELSTROM_WEAPON and SEGMENTED_TYPES[powerType] ~= true then
        return false, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "segThresholdEnabled")
    if enabled ~= true then
        return false, nil, nil
    end

    local threshold = tonumber(ResolveSpecOverrideKey(resource, specID, "segThresholdValue"))
    if not threshold then
        threshold = 1
    end
    threshold = math_floor(threshold)
    if threshold < 1 then
        threshold = 1
    elseif threshold > 99 then
        threshold = 99
    end

    local thresholdColor = GetSafeRGBColor(ResolveSpecOverrideKey(resource, specID, "segThresholdColor"), DEFAULT_SEG_THRESHOLD_COLOR)
    return true, threshold, thresholdColor
end

local function GetContinuousTickConfig(powerType, settings)
    if SEGMENTED_TYPES[powerType] or powerType == RESOURCE_MAELSTROM_WEAPON then
        return false, nil, nil, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, nil, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, nil, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "continuousTickEnabled")
    if enabled ~= true then
        return false, nil, nil, nil, nil
    end

    local mode = ResolveSpecOverrideKey(resource, specID, "continuousTickMode")
    if mode ~= "percent" and mode ~= "absolute" then
        mode = DEFAULT_CONTINUOUS_TICK_MODE
    end

    local percentValue = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickPercent"))
    if not percentValue then
        percentValue = DEFAULT_CONTINUOUS_TICK_PERCENT
    end
    if percentValue < 0 then
        percentValue = 0
    elseif percentValue > 100 then
        percentValue = 100
    end

    local absoluteValue = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickAbsolute"))
    if not absoluteValue then
        absoluteValue = DEFAULT_CONTINUOUS_TICK_ABSOLUTE
    end
    if absoluteValue < 0 then
        absoluteValue = 0
    end

    local tickColor = GetSafeRGBAColor(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), DEFAULT_CONTINUOUS_TICK_COLOR)
    local tickWidth = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickWidth")) or DEFAULT_CONTINUOUS_TICK_WIDTH
    if tickWidth < 1 then tickWidth = 1 elseif tickWidth > 10 then tickWidth = 10 end
    local combatOnly = ResolveSpecOverrideKey(resource, specID, "continuousTickCombatOnly") or false
    return true, mode, percentValue, absoluteValue, tickColor, tickWidth, combatOnly
end

local function SupportsResourceAuraStackMode(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
end

------------------------------------------------------------------------
-- IsResourceEnabled
------------------------------------------------------------------------

--- Check if a specific resource is enabled in settings.
local function IsResourceEnabled(powerType, settings)
    if powerType == RESOURCE_HEALTH then
        local health = settings and settings.resources and settings.resources[RESOURCE_HEALTH]
        return type(health) == "table" and health.enabled == true
    end

    if settings and settings.resources then
        local override = settings.resources[powerType]
        if override and override.enabled == false then
            return false
        end
    end
    -- Hide mana for non-healer toggle
    if powerType == 0 and settings and settings.hideManaForNonHealer then
        if not IsHealerSpec() and GetCurrentSpecID() ~= 62 then
            return false
        end
    end
    return true
end

------------------------------------------------------------------------
-- Segmented Text Helpers
------------------------------------------------------------------------

local function IsSegmentedTextResource(powerType)
    return powerType == RESOURCE_MAELSTROM_WEAPON or SEGMENTED_TYPES[powerType] == true
end

local function FormatSegmentedTextNumber(value)
    local n = tonumber(value) or 0
    local rounded = math_floor((n * 10) + 0.5) / 10
    local formatted = string_format("%.1f", rounded)
    return (formatted:gsub("%.0$", ""))
end

local function ClearSegmentedText(holder)
    if holder and holder.text then
        holder.text:SetText("")
    end
end

local function SetSegmentedText(holder, currentValue, maxValue)
    if not holder or not holder.text or not holder.text:IsShown() then return end
    if type(currentValue) ~= "number" then
        holder.text:SetText("")
        return
    end

    if holder._hideTextAtZero and currentValue == 0 then
        holder.text:SetText("")
        return
    end

    local textFormat = holder._textFormat
    if textFormat == "current_max" then
        if type(maxValue) ~= "number" then
            holder.text:SetText("")
            return
        end
        holder.text:SetText(FormatSegmentedTextNumber(currentValue) .. " / " .. FormatSegmentedTextNumber(maxValue))
    else
        holder.text:SetText(FormatSegmentedTextNumber(currentValue))
    end
end

------------------------------------------------------------------------
-- Shared Independent Mover Utilities
------------------------------------------------------------------------

local function IsBarsConfigActive()
    local cs = ST and ST._configState
    if not cs or not cs.resourceBarPanelActive then
        return false
    end
    if not CooldownCompanion.GetConfigFrame then
        return false
    end
    local configFrame = CooldownCompanion:GetConfigFrame()
    return configFrame and configFrame.frame and configFrame.frame:IsShown() == true
end

local function CancelNudgeTimers(button)
    if not button then return end
    if button._cdcNudgeDelayTimer then
        button._cdcNudgeDelayTimer:Cancel()
        button._cdcNudgeDelayTimer = nil
    end
    if button._cdcNudgeTicker then
        button._cdcNudgeTicker:Cancel()
        button._cdcNudgeTicker = nil
    end
end

------------------------------------------------------------------------
-- Add all helpers to ST._RB
------------------------------------------------------------------------

RB.GetResourceBarSettings = GetResourceBarSettings
RB.IsVerticalResourceLayout = IsVerticalResourceLayout
RB.GetResourceLayoutOrientation = GetResourceLayoutOrientation
RB.IsVerticalFillReversed = IsVerticalFillReversed
RB.GetResourcePrimaryLength = GetResourcePrimaryLength
RB.GetResourceGlobalThickness = GetResourceGlobalThickness
RB.GetResourceAnchorGap = GetResourceAnchorGap
RB.GetVerticalSideFallback = GetVerticalSideFallback
RB.GetEffectiveAnchorGroupId = GetEffectiveAnchorGroupId
RB.GetAnchorGroupFrame = GetAnchorGroupFrame
RB.GetCurrentSpecID = GetCurrentSpecID
RB.GetPlayerClassID = GetPlayerClassID
RB.GetSpecCustomAuraBars = GetSpecCustomAuraBars
RB.EnsureCustomBarId = EnsureCustomBarId
RB.GetCustomBarLayout = GetCustomBarLayout
RB.EnsureCustomBarLayout = EnsureCustomBarLayout
RB.IsConfiguredCustomBar = IsConfiguredCustomBar
RB.GetCustomBarEntryType = GetCustomBarEntryType
RB.IsValidCustomAuraUnit = IsValidCustomAuraUnit
RB.GetDefaultCustomAuraUnit = GetDefaultCustomAuraUnit
RB.GetResolvedCustomAuraBarAuraUnit = GetResolvedCustomAuraBarAuraUnit
RB.EnsureCustomAuraBarAuraUnit = EnsureCustomAuraBarAuraUnit
RB.RefreshCustomAuraBarAuraUnitForSpell = RefreshCustomAuraBarAuraUnitForSpell
RB.IsValidResourceAuraUnit = IsValidResourceAuraUnit
RB.GetDefaultResourceAuraUnit = GetDefaultResourceAuraUnit
RB.HasExplicitResourceAuraUnit = HasExplicitResourceAuraUnit
RB.GetResolvedResourceAuraUnit = GetResolvedResourceAuraUnit
RB.EnsureResourceAuraUnit = EnsureResourceAuraUnit
RB.RefreshResourceAuraUnitForSpell = RefreshResourceAuraUnitForSpell
RB.CreateDefaultLayoutOrder = CreateDefaultLayoutOrder
RB.GetSpecLayoutOrder = GetSpecLayoutOrder
RB.SeedResourceLayoutFromGlobal = SeedResourceLayoutFromGlobal
RB.GetSpecResourceDisplayProfile = GetSpecResourceDisplayProfile
RB.GetResourceDisplayValue = GetResourceDisplayValue
RB.GetResourceDisplayConfig = GetResourceDisplayConfig
RB.GetResourceSpecOverrideTable = GetResourceSpecOverrideTable
RB.RESOURCE_TEXT_DISPLAY_KEYS = RESOURCE_TEXT_DISPLAY_KEYS
RB.RESOURCE_HEALTH_DISPLAY_KEYS = RESOURCE_HEALTH_DISPLAY_KEYS
RB.GetAnchorOffset = GetAnchorOffset
RB.RoundToTenths = RoundToTenths
RB.ClampIndependentDimension = ClampIndependentDimension
RB.IsBarsConfigActive = IsBarsConfigActive
RB.CancelNudgeTimers = CancelNudgeTimers
RB.IsTruthyConfigFlag = IsTruthyConfigFlag
RB.NormalizeCustomAuraIndependentOrientation = NormalizeCustomAuraIndependentOrientation
RB.NormalizeCustomAuraIndependentVerticalFillDirection = NormalizeCustomAuraIndependentVerticalFillDirection
RB.IsCustomAuraBarIndependent = IsCustomAuraBarIndependent
RB.NormalizeCustomAuraStackTextFormat = NormalizeCustomAuraStackTextFormat
RB.IsHealerSpec = IsHealerSpec
RB.IsAstralPowerAvailableForCurrentDruidSpec = IsAstralPowerAvailableForCurrentDruidSpec
RB.GetDruidResources = GetDruidResources
RB.DetermineActiveResources = DetermineActiveResources
RB.GetResourceColors = GetResourceColors
RB.IsPowerTypePotentiallySecret = IsPowerTypePotentiallySecret
RB.IsUnitPowerSecret = IsUnitPowerSecret
RB.IsUnitPowerMaxSecret = IsUnitPowerMaxSecret
RB.GetSafeRGBColor = GetSafeRGBColor
RB.GetSafeRGBAColor = GetSafeRGBAColor
RB.GetSegmentedThresholdConfig = GetSegmentedThresholdConfig
RB.GetContinuousTickConfig = GetContinuousTickConfig
RB.SupportsResourceAuraStackMode = SupportsResourceAuraStackMode
RB.IsResourceEnabled = IsResourceEnabled
RB.IsSegmentedTextResource = IsSegmentedTextResource
RB.FormatSegmentedTextNumber = FormatSegmentedTextNumber
RB.ClearSegmentedText = ClearSegmentedText
RB.SetSegmentedText = SetSegmentedText
