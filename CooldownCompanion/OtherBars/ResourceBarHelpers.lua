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
local table_sort = table.sort
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
local MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = 3

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

local RESOURCE_DISPLAY_PROFILE_KEYS = {
    "barTexture",
    "classBarBrightness",
    "backgroundColor",
    "borderStyle",
    "borderColor",
    "borderSize",
    "borderRenderMode",
    "segmentedSmoothing",
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
    "showRechargeText",
    "rechargeTextMode",
    "rechargeTextFont",
    "rechargeTextFontSize",
    "rechargeTextFontOutline",
    "rechargeTextFontColor",
    "rechargeTextAnchor",
    "rechargeTextXOffset",
    "rechargeTextYOffset",
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

local customBarContentFields = {
    "spellID",
    "trackingMode",
    "displayMode",
    "maxStacks",
    "label",
    "barColor",
    "barCooldownColor",
    "barChargeColor",
    "overlayColor",
    "barHeight",
    "barWidth",
    "soundAlerts",
    "loadConditions",
    "talentConditions",
    "hideWhenInactive",
    "hideWhileAuraActive",
    "hideAuraActiveExceptPandemic",
    "auraTracking",
    "auraSpellID",
    "barAuraColor",
    "barAuraEffect",
    "barAuraEffectColor",
    "barAuraEffectSize",
    "barAuraEffectThickness",
    "barAuraEffectSpeed",
    "barAuraEffectLines",
    "auraGlowCombatOnly",
    "barAuraPulseEnabled",
    "barAuraPulseSpeed",
    "barAuraColorShiftEnabled",
    "barAuraColorShiftSpeed",
    "barAuraColorShiftColor",
    "showPandemicGlow",
    "barPandemicColor",
    "pandemicBarEffect",
    "pandemicBarEffectColor",
    "pandemicBarEffectSize",
    "pandemicBarEffectThickness",
    "pandemicBarEffectSpeed",
    "pandemicBarEffectLines",
    "pandemicGlowCombatOnly",
    "pandemicBarPulseEnabled",
    "pandemicBarPulseSpeed",
    "pandemicBarColorShiftEnabled",
    "pandemicBarColorShiftSpeed",
    "pandemicBarColorShiftColor",
    "thresholdColorEnabled",
    "thresholdMaxColor",
    "maxStacksGlowEnabled",
    "maxStacksGlowStyle",
    "maxStacksGlowColor",
    "maxStacksGlowSize",
    "maxStacksGlowSpeed",
    "maxStacksGlowThickness",
    "showDurationText",
    "durationTextFont",
    "durationTextFontSize",
    "durationTextFontOutline",
    "durationTextFontColor",
    "durationFormat",
    "decimalTimers",
    "showStackText",
    "showText",
    "stackTextFormat",
    "stackTextFont",
    "stackTextFontSize",
    "stackTextFontOutline",
    "stackTextFontColor",
    "auraUnit",
    "auraUnitExplicit",
    "hasCharges",
    "maxCharges",
}

local function HasCustomBarContent(cab)
    if type(cab) ~= "table" then
        return false
    end
    if cab.enabled == true then
        return true
    end
    for _, field in ipairs(customBarContentFields) do
        if cab[field] ~= nil then
            return true
        end
    end
    return false
end

local function IsConfiguredCustomBar(cab)
    return type(cab) == "table"
        and (
            HasCustomBarContent(cab)
            or cab.entryType ~= nil
            or cab.independentAnchorEnabled ~= nil
        )
end

local function GetCustomBarEntryType(cab)
    if type(cab) == "table" and cab.entryType == "spell" then
        return "spell"
    end
    return "aura"
end

local function IsSpellCustomBarConfig(cab)
    return GetCustomBarEntryType(cab) == "spell"
end

local function GetCustomBarTrackingMode(cab, isSpellCustomBar)
    local mode = cab and cab.trackingMode
    if mode == "active" or mode == "stacks" then
        return mode
    end

    return isSpellCustomBar and "active" or "stacks"
end

local function IsSpellCustomBarAuraStackDisplay(cab)
    return type(cab) == "table"
        and IsSpellCustomBarConfig(cab)
        and cab.auraTracking == true
        and GetCustomBarTrackingMode(cab, true) ~= "active"
end

local function NormalizeCustomBarEntryType(cab)
    if type(cab) ~= "table" then
        return "aura"
    end
    cab.entryType = GetCustomBarEntryType(cab)
    return cab.entryType
end

local function NormalizeCustomBarAttachedPlacement(cab)
    if type(cab) ~= "table" then
        return
    end

    cab.independentAnchorEnabled = nil
    cab.independentLocked = nil
    cab.independentAnchorTargetMode = nil
    cab.independentAnchorFrameName = nil
    cab.independentAnchorGroupId = nil
    cab.independentAnchor = nil
    cab.independentSize = nil
    cab.independentOrientation = nil
    cab.independentVerticalFillDirection = nil
end

local function NormalizeCustomBarSpecID(specID)
    local numericSpecID = tonumber(specID)
    if numericSpecID and numericSpecID > 0 then
        return numericSpecID
    end
    return nil
end

local function IsCustomBarsSharedStore(customBars)
    return type(customBars) == "table"
        and (type(customBars.entries) == "table" or type(customBars.order) == "table")
end

local function NormalizeCustomBarSpecMembership(entry)
    if type(entry) ~= "table" then
        return {}
    end

    local normalized = {}
    if type(entry.specs) == "table" then
        for key, value in pairs(entry.specs) do
            if value == true then
                local specID = NormalizeCustomBarSpecID(key)
                if specID then normalized[specID] = true end
            elseif type(value) == "number" or type(value) == "string" then
                local specID = NormalizeCustomBarSpecID(value)
                if specID then normalized[specID] = true end
            end
        end
    end

    local legacySpecID = NormalizeCustomBarSpecID(entry.specID or entry.spec or entry.sourceSpecID)
    if legacySpecID then
        normalized[legacySpecID] = true
    end

    entry.specs = normalized
    entry.specID = nil
    entry.spec = nil
    entry.sourceSpecID = nil
    return normalized
end

local function CustomBarHasSpec(entry, specID)
    specID = NormalizeCustomBarSpecID(specID)
    if type(entry) ~= "table" or not specID then
        return false
    end
    local specs = NormalizeCustomBarSpecMembership(entry)
    if not next(specs) then
        return true
    end
    return specs[specID] == true
end

local function CustomBarHasSpecFilters(entry)
    return type(entry) == "table" and next(NormalizeCustomBarSpecMembership(entry)) ~= nil
end

local function CustomBarHasExplicitSpec(entry, specID)
    specID = NormalizeCustomBarSpecID(specID)
    if type(entry) ~= "table" or not specID then
        return false
    end
    return NormalizeCustomBarSpecMembership(entry)[specID] == true
end

local function SetCustomBarSpecMembership(entry, specID, enabled)
    specID = NormalizeCustomBarSpecID(specID)
    if type(entry) ~= "table" or not specID then
        return false
    end
    NormalizeCustomBarSpecMembership(entry)[specID] = enabled == true or nil
    return true
end

local function ForEachCustomBarSpec(entry, callback)
    if type(entry) ~= "table" or type(callback) ~= "function" then
        return
    end
    local specIDs = {}
    for specID in pairs(NormalizeCustomBarSpecMembership(entry)) do
        specIDs[#specIDs + 1] = specID
    end
    table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
    for _, specID in ipairs(specIDs) do
        callback(specID)
    end
end

local function AddCustomBarOrder(store, customBarId)
    if type(store) ~= "table" or type(customBarId) ~= "string" or customBarId == "" then
        return
    end
    if type(store.order) ~= "table" then
        store.order = {}
    end
    for _, existingId in ipairs(store.order) do
        if existingId == customBarId then
            return
        end
    end
    store.order[#store.order + 1] = customBarId
end

local function CustomBarIdOwnedByOther(settings, customBarId, owner)
    if type(settings) ~= "table"
        or type(settings.customBars) ~= "table"
        or type(customBarId) ~= "string"
        or customBarId == "" then
        return false
    end

    local entries = IsCustomBarsSharedStore(settings.customBars)
        and type(settings.customBars.entries) == "table"
        and settings.customBars.entries
        or {}
    for key, entry in pairs(entries) do
        if entry ~= owner and type(entry) == "table" then
            local entryId = type(key) == "string" and key or entry.customBarId
            if entryId == customBarId or entry.customBarId == customBarId then
                return true
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

local function EnsureSharedCustomBarsStore(settings)
    if type(settings) ~= "table" then
        return nil
    end

    local store = IsCustomBarsSharedStore(settings.customBars)
        and settings.customBars
        or { entries = {}, order = {} }
    local legacyCustomBars = not IsCustomBarsSharedStore(settings.customBars) and settings.customBars or nil

    store.entries = type(store.entries) == "table" and store.entries or {}
    store.order = type(store.order) == "table" and store.order or {}
    settings.customBars = store

    local function addEntryForSpec(entry, specID, fallbackOrder)
        if not (specID and IsConfiguredCustomBar(entry)) then
            return
        end
        NormalizeCustomBarAttachedPlacement(entry)
        if not HasCustomBarContent(entry) then
            return
        end
        NormalizeCustomBarEntryType(entry)
        SetCustomBarSpecMembership(entry, specID, true)
        local id = EnsureCustomBarId(settings, entry)
        if id then
            store.entries[id] = entry
            AddCustomBarOrder(store, id)
            EnsureCustomBarLayout(settings, specID, id, fallbackOrder)
        end
    end

    local function addLegacyCustomBarsForSpec(specID, specBars)
        specID = NormalizeCustomBarSpecID(specID)
        if not (specID and type(specBars) == "table") then
            return
        end

        local numericKeys = {}
        for key in pairs(specBars) do
            if type(key) == "number" then
                numericKeys[#numericKeys + 1] = key
            end
        end
        table.sort(numericKeys)

        local seen = {}
        for index, key in ipairs(numericKeys) do
            addEntryForSpec(specBars[key], specID, 1000 + index)
            seen[key] = true
        end
        for key, entry in pairs(specBars) do
            if not seen[key] then
                addEntryForSpec(entry, specID, 1000 + #store.order + 1)
            end
        end
    end

    if type(legacyCustomBars) == "table" then
        local specIDs = {}
        for specID in pairs(legacyCustomBars) do
            specIDs[#specIDs + 1] = specID
        end
        table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
        for _, specID in ipairs(specIDs) do
            addLegacyCustomBarsForSpec(specID, legacyCustomBars[specID])
        end
    end

    if type(settings.customAuraBars) == "table" then
        local legacySpecIDs = {}
        for specID in pairs(settings.customAuraBars) do
            legacySpecIDs[#legacySpecIDs + 1] = specID
        end
        table.sort(legacySpecIDs, function(a, b) return tostring(a) < tostring(b) end)

        for _, legacySpecID in ipairs(legacySpecIDs) do
            local specID = NormalizeCustomBarSpecID(legacySpecID)
            local legacyBars = settings.customAuraBars[legacySpecID]
            local layout = specID and GetSpecLayoutOrder and GetSpecLayoutOrder(settings, specID) or nil
            local numericSlots = {}
            if specID and type(legacyBars) == "table" then
                for slotIdx in pairs(legacyBars) do
                    if tonumber(slotIdx) then
                        numericSlots[#numericSlots + 1] = tonumber(slotIdx)
                    end
                end
            end
            table.sort(numericSlots)

            for _, slotIdx in ipairs(numericSlots) do
                local cab = legacyBars[slotIdx] or legacyBars[tostring(slotIdx)]
                if IsConfiguredCustomBar(cab) then
                    local customBarId = type(cab.customBarId) == "string" and cab.customBarId or nil
                    local entry = customBarId and store.entries[customBarId] or nil
                    local isNewEntry = type(entry) ~= "table"
                    if isNewEntry then
                        entry = CopyTable(cab)
                        NormalizeCustomBarAttachedPlacement(entry)
                        entry.entryType = "aura"
                    end
                    if HasCustomBarContent(entry) then
                        SetCustomBarSpecMembership(entry, specID, true)
                        local id = EnsureCustomBarId(settings, entry)
                        if id then
                            if isNewEntry then
                                store.entries[id] = entry
                                AddCustomBarOrder(store, id)
                            end
                            local legacyLayout = type(layout) == "table"
                                and type(layout.customAuraBarSlots) == "table"
                                and layout.customAuraBarSlots[slotIdx]
                                or nil
                            if type(layout) == "table" then
                                if type(layout.customBars) ~= "table" then
                                    layout.customBars = {}
                                end
                                if type(layout.customBars[id]) ~= "table" then
                                    layout.customBars[id] = type(legacyLayout) == "table"
                                        and CopyTable(legacyLayout)
                                        or { position = "below", order = 1000 + #store.order }
                                end
                            end
                        end
                    end
                end
            end

            settings.customAuraBars[legacySpecID] = nil
            local numericSpecID = tonumber(legacySpecID)
            if numericSpecID then
                settings.customAuraBars[numericSpecID] = nil
            end
            local stringSpecID = specID and tostring(specID) or nil
            if stringSpecID then
                settings.customAuraBars[stringSpecID] = nil
            end
        end
    end

    return store
end

local function NormalizeSharedCustomBars(settings)
    local store = EnsureSharedCustomBarsStore(settings)
    if type(store) ~= "table" then
        return { entries = {}, order = {} }
    end

    local compactOrder = {}
    local seenIds = {}
    local function normalizeEntry(entry, fallbackSpecID)
        if not IsConfiguredCustomBar(entry) then
            return nil
        end
        NormalizeCustomBarAttachedPlacement(entry)
        if not HasCustomBarContent(entry) then
            return nil
        end
        NormalizeCustomBarEntryType(entry)
        if fallbackSpecID and not next(NormalizeCustomBarSpecMembership(entry)) then
            SetCustomBarSpecMembership(entry, fallbackSpecID, true)
        else
            NormalizeCustomBarSpecMembership(entry)
        end
        local id = EnsureCustomBarId(settings, entry)
        if not id then
            return nil
        end
        store.entries[id] = entry
        if not seenIds[id] then
            compactOrder[#compactOrder + 1] = id
            seenIds[id] = true
        end
        return id
    end

    for _, id in ipairs(store.order) do
        local entry = store.entries[id]
        if type(entry) == "table" then
            normalizeEntry(entry)
        end
    end

    for _, entry in pairs(store.entries) do
        local id = type(entry) == "table" and entry.customBarId or nil
        if type(id) == "string" and not seenIds[id] then
            normalizeEntry(entry)
        end
    end

    wipe(store.order)
    for _, id in ipairs(compactOrder) do
        store.order[#store.order + 1] = id
    end
    return store
end

local function NormalizeCustomBars(settings, specID)
    specID = NormalizeCustomBarSpecID(specID)
    local store = NormalizeSharedCustomBars(settings)

    local specBars = {}
    for _, id in ipairs(store.order) do
        local entry = store.entries[id]
        if CustomBarHasSpec(entry, specID) then
            specBars[#specBars + 1] = entry
            EnsureCustomBarLayout(settings, specID, id, 1000 + #specBars)
        end
    end
    return specBars
end

local function GetAllCustomBars(settings)
    local store = NormalizeSharedCustomBars(settings)
    local bars = {}
    for _, id in ipairs(store.order) do
        local entry = store.entries[id]
        if type(entry) == "table" then
            bars[#bars + 1] = entry
        end
    end
    return bars
end

local function FindCustomBarById(settings, customBarId)
    if type(customBarId) ~= "string" or customBarId == "" then
        return nil
    end
    return NormalizeSharedCustomBars(settings).entries[customBarId]
end

local function AddCustomBar(settings, entry, specID, fallbackOrder)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return nil
    end
    specID = NormalizeCustomBarSpecID(specID) or GetCurrentSpecID()
    if not specID then
        return nil
    end
    local store = NormalizeSharedCustomBars(settings)
    NormalizeCustomBarAttachedPlacement(entry)
    NormalizeCustomBarEntryType(entry)
    NormalizeCustomBarSpecMembership(entry)
    local id = EnsureCustomBarId(settings, entry)
    if not id then
        return nil
    end
    store.entries[id] = entry
    AddCustomBarOrder(store, id)
    EnsureCustomBarLayout(settings, specID, id, fallbackOrder or (1000 + #store.order))
    return id, entry
end

local function CopyCustomBarLayoutValues(targetLayout, sourceLayout, incrementOrder)
    if type(targetLayout) ~= "table" or type(sourceLayout) ~= "table" then
        return
    end
    wipe(targetLayout)
    for key, value in pairs(sourceLayout) do
        targetLayout[key] = type(value) == "table" and CopyTable(value) or value
    end
    if incrementOrder and sourceLayout.order ~= nil then
        targetLayout.order = (tonumber(sourceLayout.order) or 1000) + 1
    end
    if incrementOrder and sourceLayout.verticalOrder ~= nil then
        targetLayout.verticalOrder = (tonumber(sourceLayout.verticalOrder) or 1000) + 1
    end
end

local function FindCustomBarLayoutToCopy(settings, entry, targetSpecID, preferredSpecID)
    targetSpecID = NormalizeCustomBarSpecID(targetSpecID)
    local function copyFromSpec(specID)
        specID = NormalizeCustomBarSpecID(specID)
        if not specID or specID == targetSpecID then
            return nil
        end
        local layout = GetCustomBarLayout(settings, specID, entry, false)
        return type(layout) == "table" and CopyTable(layout) or nil
    end

    local copiedLayout = copyFromSpec(preferredSpecID)
    if copiedLayout then
        return copiedLayout
    end

    local specIDs = {}
    ForEachCustomBarSpec(entry, function(specID)
        specID = NormalizeCustomBarSpecID(specID)
        if specID and specID ~= targetSpecID then
            specIDs[#specIDs + 1] = specID
        end
    end)
    table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
    for _, specID in ipairs(specIDs) do
        copiedLayout = copyFromSpec(specID)
        if copiedLayout then
            return copiedLayout
        end
    end

    local customBarId = type(entry) == "table" and entry.customBarId or nil
    local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
    if type(customBarId) == "string" and type(layoutOrder) == "table" then
        wipe(specIDs)
        for specID, layout in pairs(layoutOrder) do
            if type(layout) == "table"
                and type(layout.customBars) == "table"
                and type(layout.customBars[customBarId]) == "table" then
                specID = NormalizeCustomBarSpecID(specID)
                if specID and specID ~= targetSpecID then
                    specIDs[#specIDs + 1] = specID
                end
            end
        end
        table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
        for _, specID in ipairs(specIDs) do
            copiedLayout = copyFromSpec(specID)
            if copiedLayout then
                return copiedLayout
            end
        end
    end

    return nil
end

local function AddCustomBarToSpec(settings, entry, specID, sourceSpecID)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return false
    end
    specID = NormalizeCustomBarSpecID(specID)
    if not specID then
        return false
    end
    local id = EnsureCustomBarId(settings, entry)
    if not id then
        return false
    end
    local targetLayoutExists = GetCustomBarLayout(settings, specID, entry, false) ~= nil
    local copiedLayout = not targetLayoutExists and FindCustomBarLayoutToCopy(settings, entry, specID, sourceSpecID) or nil
    SetCustomBarSpecMembership(entry, specID, true)
    local targetLayout = EnsureCustomBarLayout(settings, specID, id, 1000)
    if not targetLayoutExists and type(copiedLayout) == "table" and type(targetLayout) == "table" then
        CopyCustomBarLayoutValues(targetLayout, copiedLayout)
    end
    return true
end

local function RemoveCustomBarFromSpec(settings, entry, specID)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return false
    end
    specID = NormalizeCustomBarSpecID(specID)
    if not specID then
        return false
    end
    SetCustomBarSpecMembership(entry, specID, false)
    if not CustomBarHasSpecFilters(entry) then
        return true
    end

    local customBarId = entry.customBarId
    local layout = type(settings.layoutOrder) == "table"
        and (settings.layoutOrder[specID] or settings.layoutOrder[tostring(specID)])
        or nil
    if type(layout) == "table" and type(layout.customBars) == "table" and type(customBarId) == "string" then
        layout.customBars[customBarId] = nil
    end
    return true
end

local function DeleteCustomBar(settings, customBarId)
    if type(settings) ~= "table" or type(customBarId) ~= "string" or customBarId == "" then
        return false
    end
    local store = NormalizeSharedCustomBars(settings)
    local entry = store.entries[customBarId]
    if type(entry) ~= "table" then
        return false
    end
    store.entries[customBarId] = nil
    for index = #store.order, 1, -1 do
        if store.order[index] == customBarId then
            table.remove(store.order, index)
        end
    end
    if type(settings.layoutOrder) == "table" then
        for _, layout in pairs(settings.layoutOrder) do
            if type(layout) == "table" and type(layout.customBars) == "table" then
                layout.customBars[customBarId] = nil
            end
        end
    end
    return true
end

local function CollectCustomBarSpecIDs(entry)
    local specIDs = {}
    ForEachCustomBarSpec(entry, function(specID)
        specIDs[#specIDs + 1] = specID
    end)
    return specIDs
end

local function CollectCustomBarLayoutSpecIDs(settings, customBarId)
    local specIDs = {}
    local seen = {}
    local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
    if type(layoutOrder) ~= "table" or type(customBarId) ~= "string" then
        return specIDs
    end
    for specID, layout in pairs(layoutOrder) do
        if type(layout) == "table"
            and type(layout.customBars) == "table"
            and type(layout.customBars[customBarId]) == "table" then
            local normalizedSpecID = NormalizeCustomBarSpecID(specID)
            if normalizedSpecID and not seen[normalizedSpecID] then
                specIDs[#specIDs + 1] = normalizedSpecID
                seen[normalizedSpecID] = true
            end
        end
    end
    table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
    return specIDs
end

local function DuplicateCustomBar(settings, sourceEntry, specID, fallbackOrder)
    if type(settings) ~= "table" or type(sourceEntry) ~= "table" then
        return nil
    end

    local sourceId = type(sourceEntry.customBarId) == "string" and sourceEntry.customBarId or nil
    local sourceSpecIDs = CollectCustomBarSpecIDs(sourceEntry)
    local layoutSeedSpecID = sourceSpecIDs[1] or NormalizeCustomBarSpecID(specID) or GetCurrentSpecID()
    if not layoutSeedSpecID then
        return nil
    end

    local copy = CopyTable(sourceEntry)
    copy.customBarId = nil

    local newId = AddCustomBar(settings, copy, layoutSeedSpecID, fallbackOrder)
    if not newId then
        return nil
    end

    local layoutSpecIDs, seenLayoutSpecs = {}, {}
    local function addLayoutSpec(layoutSpecID)
        if layoutSpecID and not seenLayoutSpecs[layoutSpecID] then
            layoutSpecIDs[#layoutSpecIDs + 1] = layoutSpecID
            seenLayoutSpecs[layoutSpecID] = true
        end
    end
    for _, layoutSpecID in ipairs(sourceSpecIDs) do
        addLayoutSpec(layoutSpecID)
    end
    if sourceId then
        for _, layoutSpecID in ipairs(CollectCustomBarLayoutSpecIDs(settings, sourceId)) do
            addLayoutSpec(layoutSpecID)
        end
    end

    for _, layoutSpecID in ipairs(layoutSpecIDs) do
        local sourceLayout = GetCustomBarLayout(settings, layoutSpecID, sourceEntry, false)
        if type(sourceLayout) == "table" then
            local targetLayout = EnsureCustomBarLayout(settings, layoutSpecID, newId, fallbackOrder)
            CopyCustomBarLayoutValues(targetLayout, sourceLayout, true)
        end
    end

    return newId, copy
end

local function CollectPayloadLayoutSpecIDs(payload, customBarId)
    local specIDs = {}
    local seen = {}
    local layouts = type(payload) == "table" and payload.layouts or nil
    if type(layouts) ~= "table" or type(customBarId) ~= "string" then
        return specIDs
    end
    for specID, specLayouts in pairs(layouts) do
        if type(specLayouts) == "table" and type(specLayouts[customBarId]) == "table" then
            local normalizedSpecID = NormalizeCustomBarSpecID(specID)
            if normalizedSpecID and not seen[normalizedSpecID] then
                specIDs[#specIDs + 1] = normalizedSpecID
                seen[normalizedSpecID] = true
            end
        end
    end
    table.sort(specIDs, function(a, b) return tostring(a) < tostring(b) end)
    return specIDs
end

local function BuildCustomBarsExportPayload(settings, entries)
    if type(settings) ~= "table" or type(entries) ~= "table" then
        return nil
    end

    local _, classFilename, classID = UnitClass("player")
    local payload = {
        type = "customBars",
        version = 1,
        classID = classID,
        classFilename = classFilename,
        bars = {},
        layouts = {},
    }

    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local id = EnsureCustomBarId(settings, entry)
            if id then
                local exportedEntry = CopyTable(entry)
                exportedEntry.customBarId = id
                payload.bars[#payload.bars + 1] = exportedEntry

                local layoutSpecIDs = {}
                local seenLayoutSpecs = {}
                for _, specID in ipairs(CollectCustomBarSpecIDs(entry)) do
                    layoutSpecIDs[#layoutSpecIDs + 1] = specID
                    seenLayoutSpecs[specID] = true
                end
                for _, specID in ipairs(CollectCustomBarLayoutSpecIDs(settings, id)) do
                    if not seenLayoutSpecs[specID] then
                        layoutSpecIDs[#layoutSpecIDs + 1] = specID
                        seenLayoutSpecs[specID] = true
                    end
                end

                for _, specID in ipairs(layoutSpecIDs) do
                    local layout = GetCustomBarLayout(settings, specID, entry, false)
                    if type(layout) == "table" then
                        if type(payload.layouts[specID]) ~= "table" then
                            payload.layouts[specID] = {}
                        end
                        payload.layouts[specID][id] = CopyTable(layout)
                    end
                end
            end
        end
    end

    if #payload.bars == 0 then
        return nil
    end
    return payload
end

local function ImportCustomBarsPayload(settings, payload)
    if type(settings) ~= "table" or type(payload) ~= "table" or payload.type ~= "customBars" then
        return false, "Import failed: this is not a Custom Bars export."
    end

    local _, classFilename, classID = UnitClass("player")
    if payload.classID and payload.classID ~= classID then
        return false, "Import failed: Custom Bars can only be imported on the same class."
    end
    if payload.classFilename and classFilename and payload.classFilename ~= classFilename then
        return false, "Import failed: Custom Bars can only be imported on the same class."
    end
    if type(payload.bars) ~= "table" or #payload.bars == 0 then
        return false, "Import failed: no Custom Bars were found."
    end

    local importedCount = 0
    local importedSpecs = {}
    for _, exportedEntry in ipairs(payload.bars) do
        if IsConfiguredCustomBar(exportedEntry) then
            local oldId = exportedEntry.customBarId
            local specIDs = CollectCustomBarSpecIDs(exportedEntry)
            local firstSpecID = specIDs[1] or GetCurrentSpecID()
            if firstSpecID then
                local entry = CopyTable(exportedEntry)
                entry.customBarId = nil
                entry.specs = nil
                local newId = AddCustomBar(settings, entry, firstSpecID)
                if newId then
                    importedCount = importedCount + 1
                    importedSpecs[firstSpecID] = true
                    local layoutSpecIDs = CollectPayloadLayoutSpecIDs(payload, oldId)
                    local pendingLayoutSpecs = {}
                    for _, specID in ipairs(layoutSpecIDs) do
                        pendingLayoutSpecs[specID] = true
                    end
                    for _, specID in ipairs(specIDs) do
                        importedSpecs[specID] = true
                        AddCustomBarToSpec(settings, entry, specID, firstSpecID)
                        local exportedLayout = type(payload.layouts) == "table"
                            and type(payload.layouts[specID]) == "table"
                            and payload.layouts[specID][oldId]
                            or nil
                        local targetLayout = EnsureCustomBarLayout(settings, specID, newId, 1000)
                        CopyCustomBarLayoutValues(targetLayout, exportedLayout)
                        pendingLayoutSpecs[specID] = nil
                    end
                    for _, specID in ipairs(layoutSpecIDs) do
                        if pendingLayoutSpecs[specID] then
                            importedSpecs[specID] = true
                            local exportedLayout = type(payload.layouts) == "table"
                                and type(payload.layouts[specID]) == "table"
                                and payload.layouts[specID][oldId]
                                or nil
                            local targetLayout = EnsureCustomBarLayout(settings, specID, newId, 1000)
                            CopyCustomBarLayoutValues(targetLayout, exportedLayout)
                        end
                    end
                end
            end
        end
    end

    if importedCount == 0 then
        return false, "Import failed: no valid Custom Bars were found."
    end

    local specCount = 0
    for _ in pairs(importedSpecs) do
        specCount = specCount + 1
    end
    return true, "Imported " .. importedCount .. " Custom Bar" .. (importedCount == 1 and "" or "s")
        .. " across " .. specCount .. " spec" .. (specCount == 1 and "" or "s") .. "."
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

local function GetDefaultSpellCustomBarAuraUnit(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end
    resolvedSpellID = tonumber(resolvedSpellID)

    if CooldownCompanion and CooldownCompanion.ResolveStandaloneAuraDefaultUnit then
        return CooldownCompanion:ResolveStandaloneAuraDefaultUnit({
            type = "spell",
            id = resolvedSpellID,
            auraSpellID = type(cabConfig) == "table" and cabConfig.auraSpellID or nil,
        })
    end

    return GetDefaultCustomAuraUnit(resolvedSpellID)
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

    if type(cabConfig) == "table" and HasExplicitCustomAuraBarAuraUnit(cabConfig) then
        return cabConfig.auraUnit
    end

    if type(cabConfig) == "table" and (cabConfig.entryType == nil or cabConfig.entryType == "aura") then
        return GetDefaultCustomAuraUnit(resolvedSpellID)
    end

    return GetDefaultSpellCustomBarAuraUnit(cabConfig, resolvedSpellID)
end

local function EnsureCustomAuraBarAuraUnit(cabConfig, spellID, unit, explicit)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if type(cabConfig) == "table" then
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

    return GetDefaultSpellCustomBarAuraUnit(cabConfig, resolvedSpellID)
end

local function RefreshCustomAuraBarAuraUnitForSpell(cabConfig, spellID)
    local resolvedSpellID = spellID
    if resolvedSpellID == nil and type(cabConfig) == "table" then
        resolvedSpellID = cabConfig.spellID
    end

    if HasExplicitCustomAuraBarAuraUnit(cabConfig) then
        return cabConfig.auraUnit
    end

    local defaultUnit = GetDefaultCustomAuraUnit(resolvedSpellID)
    if type(cabConfig) == "table" and cabConfig.entryType == "spell" then
        defaultUnit = GetDefaultSpellCustomBarAuraUnit(cabConfig, resolvedSpellID)
    end
    return EnsureCustomAuraBarAuraUnit(cabConfig, resolvedSpellID, defaultUnit, false)
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

    if specID and IsCustomBarsSharedStore(settings.customBars) then
        local specBars = {}
        local entries = type(settings.customBars.entries) == "table" and settings.customBars.entries or {}
        for _, cab in pairs(entries) do
            if CustomBarHasSpec(cab, specID) then
                specBars[#specBars + 1] = cab
            end
        end
        for _, cab in pairs(specBars or {}) do
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
    if profile.borderRenderMode == nil then profile.borderRenderMode = ST.BORDER_RENDER_MODE_CUSTOM end
    if profile.classBarBrightness == nil then profile.classBarBrightness = 1.3 end
    profile.segmentedSmoothing = ST.NormalizeSegmentedSmoothing(profile.segmentedSmoothing)
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

local function GetResourceSegmentedSmoothing(settings, specID)
    local profile = GetSpecResourceDisplayProfile(settings, specID)
    return ST.NormalizeSegmentedSmoothing(profile and profile.segmentedSmoothing or nil)
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

local function ClampSegmentedThresholdValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    value = math_floor(value)
    if value < 1 then
        value = 1
    elseif value > 99 then
        value = 99
    end
    return value
end

local function ClampContinuousTickPercentValue(value, fallback)
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

local function ClampContinuousTickAbsoluteValue(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if value < 0 then
        value = 0
    end
    return value
end

local function CollectNumericKeys(tbl)
    local keys = {}
    if type(tbl) ~= "table" then
        return keys
    end
    for key in pairs(tbl) do
        if type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    table_sort(keys)
    return keys
end

local function NormalizeEntryList(entries, clampValue, colorFallback, colorResolver)
    local normalized = {}
    local seen = {}
    if type(entries) ~= "table" then
        return normalized
    end

    local keys = CollectNumericKeys(entries)
    for _, key in ipairs(keys) do
        local entry = entries[key]
        local value = type(entry) == "table" and clampValue(entry.value, nil) or nil
        if value ~= nil then
            local valueKey = tostring(value)
            if not seen[valueKey] then
                seen[valueKey] = true
                normalized[#normalized + 1] = {
                    value = value,
                    color = colorResolver(type(entry) == "table" and entry.color or nil, colorFallback),
                }
                if #normalized >= MAX_RESOURCE_THRESHOLD_TICK_ENTRIES then
                    break
                end
            end
        end
    end

    table_sort(normalized, function(a, b)
        return a.value < b.value
    end)
    return normalized
end

local function GetNormalizedSegmentedThresholdEntriesFromConfig(entries)
    return NormalizeEntryList(entries, ClampSegmentedThresholdValue, DEFAULT_SEG_THRESHOLD_COLOR, GetSafeRGBColor)
end

local function GetNormalizedContinuousTickEntriesFromConfig(entries, mode)
    local clamp = mode == "absolute" and ClampContinuousTickAbsoluteValue or ClampContinuousTickPercentValue
    return NormalizeEntryList(entries, clamp, DEFAULT_CONTINUOUS_TICK_COLOR, GetSafeRGBAColor)
end

local function BuildLegacySegmentedThresholdEntry(resource, specID)
    return {
        value = ClampSegmentedThresholdValue(ResolveSpecOverrideKey(resource, specID, "segThresholdValue"), 1),
        color = GetSafeRGBColor(ResolveSpecOverrideKey(resource, specID, "segThresholdColor"), DEFAULT_SEG_THRESHOLD_COLOR),
    }
end

local function BuildLegacyContinuousTickEntry(resource, specID, mode)
    local value
    if mode == "absolute" then
        value = ClampContinuousTickAbsoluteValue(ResolveSpecOverrideKey(resource, specID, "continuousTickAbsolute"), DEFAULT_CONTINUOUS_TICK_ABSOLUTE)
    else
        value = ClampContinuousTickPercentValue(ResolveSpecOverrideKey(resource, specID, "continuousTickPercent"), DEFAULT_CONTINUOUS_TICK_PERCENT)
    end
    return {
        value = value,
        color = GetSafeRGBAColor(ResolveSpecOverrideKey(resource, specID, "continuousTickColor"), DEFAULT_CONTINUOUS_TICK_COLOR),
    }
end

local function ResolveSpecEntryList(resource, specID, entriesKey, clearedKey)
    if specID and type(resource) == "table" then
        local specOverrides = resource.specOverrides
        local specData = type(specOverrides) == "table" and specOverrides[specID] or nil
        if type(specData) == "table" then
            if specData[entriesKey] ~= nil then
                return specData[entriesKey], specData[clearedKey] == true
            end
            if specData[clearedKey] == true then
                return nil, true
            end
        end
    end
    return resource and resource[entriesKey], resource and resource[clearedKey] == true
end

local function GetSegmentedThresholdEntriesConfig(powerType, settings)
    if powerType ~= RESOURCE_MAELSTROM_WEAPON and SEGMENTED_TYPES[powerType] ~= true then
        return false, {}
    end
    if not settings or not settings.resources then
        return false, {}
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, {}
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "segThresholdEnabled")
    if enabled ~= true then
        return false, {}
    end

    local rawEntries, cleared = ResolveSpecEntryList(resource, specID, "segThresholdEntries", "segThresholdEntriesCleared")
    local entries = GetNormalizedSegmentedThresholdEntriesFromConfig(rawEntries)
    if #entries == 0 and not cleared then
        entries[1] = BuildLegacySegmentedThresholdEntry(resource, specID)
    end
    return true, entries
end

local function GetSegmentedThresholdColorForValue(powerType, settings, currentValue)
    currentValue = tonumber(currentValue)
    if not currentValue then
        return false, nil
    end

    local enabled, entries = GetSegmentedThresholdEntriesConfig(powerType, settings)
    if not enabled then
        return false, nil
    end

    local activeColor
    for _, entry in ipairs(entries) do
        if currentValue >= entry.value then
            activeColor = entry.color
        else
            break
        end
    end

    return activeColor ~= nil, activeColor
end

local function GetContinuousTickEntriesConfig(powerType, settings)
    if SEGMENTED_TYPES[powerType] or powerType == RESOURCE_MAELSTROM_WEAPON then
        return false, nil, {}, nil, nil
    end
    if not settings or not settings.resources then
        return false, nil, {}, nil, nil
    end

    local resource = settings.resources[powerType]
    if type(resource) ~= "table" then
        return false, nil, {}, nil, nil
    end

    local specID = GetCurrentSpecID()
    local enabled = ResolveSpecOverrideKey(resource, specID, "continuousTickEnabled")
    if enabled ~= true then
        return false, nil, {}, nil, nil
    end

    local mode = ResolveSpecOverrideKey(resource, specID, "continuousTickMode")
    if mode ~= "percent" and mode ~= "absolute" then
        mode = DEFAULT_CONTINUOUS_TICK_MODE
    end

    local entriesKey = mode == "absolute" and "continuousTickAbsoluteEntries" or "continuousTickPercentEntries"
    local clearedKey = mode == "absolute" and "continuousTickAbsoluteEntriesCleared" or "continuousTickPercentEntriesCleared"
    local rawEntries, cleared = ResolveSpecEntryList(resource, specID, entriesKey, clearedKey)
    local entries = GetNormalizedContinuousTickEntriesFromConfig(rawEntries, mode)
    if #entries == 0 and not cleared then
        entries[1] = BuildLegacyContinuousTickEntry(resource, specID, mode)
    end

    local tickWidth = tonumber(ResolveSpecOverrideKey(resource, specID, "continuousTickWidth")) or DEFAULT_CONTINUOUS_TICK_WIDTH
    if tickWidth < 1 then tickWidth = 1 elseif tickWidth > 10 then tickWidth = 10 end
    local combatOnly = ResolveSpecOverrideKey(resource, specID, "continuousTickCombatOnly") or false
    return true, mode, entries, tickWidth, combatOnly
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
RB.NormalizeCustomBars = NormalizeCustomBars
RB.GetAllCustomBars = GetAllCustomBars
RB.FindCustomBarById = FindCustomBarById
RB.AddCustomBar = AddCustomBar
RB.DuplicateCustomBar = DuplicateCustomBar
RB.DeleteCustomBar = DeleteCustomBar
RB.CustomBarHasSpec = CustomBarHasSpec
RB.CustomBarHasSpecFilters = CustomBarHasSpecFilters
RB.CustomBarHasExplicitSpec = CustomBarHasExplicitSpec
RB.SetCustomBarSpecMembership = SetCustomBarSpecMembership
RB.AddCustomBarToSpec = AddCustomBarToSpec
RB.RemoveCustomBarFromSpec = RemoveCustomBarFromSpec
RB.NormalizeCustomBarSpecMembership = NormalizeCustomBarSpecMembership
RB.BuildCustomBarsExportPayload = BuildCustomBarsExportPayload
RB.ImportCustomBarsPayload = ImportCustomBarsPayload
RB.EnsureCustomBarId = EnsureCustomBarId
RB.GetCustomBarLayout = GetCustomBarLayout
RB.EnsureCustomBarLayout = EnsureCustomBarLayout
RB.IsConfiguredCustomBar = IsConfiguredCustomBar
RB.GetCustomBarEntryType = GetCustomBarEntryType
RB.IsSpellCustomBarConfig = IsSpellCustomBarConfig
RB.GetCustomBarTrackingMode = GetCustomBarTrackingMode
RB.IsSpellCustomBarAuraStackDisplay = IsSpellCustomBarAuraStackDisplay
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
RB.GetResourceSegmentedSmoothing = GetResourceSegmentedSmoothing
RB.GetResourceDisplayConfig = GetResourceDisplayConfig
RB.GetResourceSpecOverrideTable = GetResourceSpecOverrideTable
RB.RESOURCE_TEXT_DISPLAY_KEYS = RESOURCE_TEXT_DISPLAY_KEYS
RB.RESOURCE_HEALTH_DISPLAY_KEYS = RESOURCE_HEALTH_DISPLAY_KEYS
RB.GetAnchorOffset = GetAnchorOffset
RB.RoundToTenths = RoundToTenths
RB.ClampIndependentDimension = ClampIndependentDimension
RB.IsBarsConfigActive = IsBarsConfigActive
RB.IsTruthyConfigFlag = IsTruthyConfigFlag
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
RB.MAX_RESOURCE_THRESHOLD_TICK_ENTRIES = MAX_RESOURCE_THRESHOLD_TICK_ENTRIES
RB.ClampSegmentedThresholdValue = ClampSegmentedThresholdValue
RB.ClampContinuousTickPercentValue = ClampContinuousTickPercentValue
RB.ClampContinuousTickAbsoluteValue = ClampContinuousTickAbsoluteValue
RB.GetNormalizedSegmentedThresholdEntriesFromConfig = GetNormalizedSegmentedThresholdEntriesFromConfig
RB.GetNormalizedContinuousTickEntriesFromConfig = GetNormalizedContinuousTickEntriesFromConfig
RB.ResolveSpecEntryList = ResolveSpecEntryList
RB.GetSegmentedThresholdEntriesConfig = GetSegmentedThresholdEntriesConfig
RB.GetSegmentedThresholdColorForValue = GetSegmentedThresholdColorForValue
RB.GetContinuousTickEntriesConfig = GetContinuousTickEntriesConfig
RB.SupportsResourceAuraStackMode = SupportsResourceAuraStackMode
RB.IsResourceEnabled = IsResourceEnabled
RB.IsSegmentedTextResource = IsSegmentedTextResource
RB.FormatSegmentedTextNumber = FormatSegmentedTextNumber
RB.ClearSegmentedText = ClearSegmentedText
RB.SetSegmentedText = SetSegmentedText
