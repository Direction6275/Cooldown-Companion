local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local AddCharacterScopedCopyControls = ST._AddCharacterScopedCopyControls
local CreateInfoButton = ST._CreateInfoButton
local tabInfoButtons = CS.tabInfoButtons

------------------------------------------------------------------------
-- Aura bar autocomplete cache (TrackedBuff + TrackedBar spells only)
------------------------------------------------------------------------
local auraBarAutocompleteCache = nil

local function BuildAuraBarAutocompleteCache()
    local cache = {}
    local seen = {}
    for _, cat in ipairs({
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
    }) do
        local catLabel = (cat == Enum.CooldownViewerCategory.TrackedBuff)
            and "Tracked Buff" or "Tracked Bar"
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info and info.spellID and not seen[info.spellID] then
                    seen[info.spellID] = true
                    local name = C_Spell.GetSpellName(info.spellID)
                    local icon = C_Spell.GetSpellTexture(info.spellID)
                    if name then
                        cache[#cache + 1] = {
                            id = info.spellID,
                            name = name,
                            nameLower = name:lower(),
                            icon = icon or 134400,
                            category = catLabel,
                        }
                    end
                end
            end
        end
    end
    auraBarAutocompleteCache = cache
    return cache
end

------------------------------------------------------------------------
-- CDM Aura Readiness Warning (shared by Resource Aura Overlays & Custom Aura Bars)
------------------------------------------------------------------------
local function AddCdmAuraReadinessWarning(container, spellID)
    if not spellID then return end

    local cdmEnabled = GetCVarBool("cooldownViewerEnabled")
    local hasViewerFrame = false
    if cdmEnabled then
        local viewerFrame = CooldownCompanion:ResolveBuffViewerFrameForSpell(spellID)
        if viewerFrame then
            local parent = viewerFrame:GetParent()
            local parentName = parent and parent:GetName()
            hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
        end
    end

    if hasViewerFrame then return end

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetText("|cffff0000Aura tracking is not ready.|r")
    statusLabel:SetFullWidth(true)
    statusLabel:SetJustifyH("CENTER")
    container:AddChild(statusLabel)

    local explainLabel = AceGUI:Create("Label")
    if not cdmEnabled then
        explainLabel:SetText("|cff888888The Cooldown Manager (CDM) is currently disabled. Enable it in Options > Gameplay > Combat > Cooldown Manager to allow reliable aura tracking in combat.|r")
    else
        local canTrack = false
        for _, cat in ipairs({Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar}) do
            local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if ids then
                for _, cdID in ipairs(ids) do
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info and (info.spellID == spellID or info.overrideSpellID == spellID or info.overrideTooltipSpellID == spellID) then
                        canTrack = true
                        break
                    end
                end
            end
            if canTrack then break end
        end

        if canTrack then
            explainLabel:SetText("|cff888888This spell has a trackable aura in the Cooldown Manager, but it has not been added as a tracked buff or debuff yet. Add it in the CDM to enable aura tracking.|r")
        else
            explainLabel:SetText("|cff888888This spell was not found in the Cooldown Manager's tracked buff or tracked bar categories. Without CDM tracking, aura data may be unreliable during combat.|r")
        end
    end
    explainLabel:SetFullWidth(true)
    container:AddChild(explainLabel)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)
end

------------------------------------------------------------------------
-- RESOURCE BAR: Anchoring Panel
------------------------------------------------------------------------

local resourceBarCollapsedSections = {}
local resourceAuraEntryCollapsedStates = {}
local RESOURCE_AURA_ENTRY_MINIMIZE_ATLAS = "common-icon-minus"
local RESOURCE_AURA_ENTRY_EXPAND_ATLAS = "common-icon-plus"

-- Power names + segmented check for config UI (mirrors ResourceBar.lua constants)
local POWER_NAMES_CONFIG = {
    [0]  = "Mana",
    [1]  = "Rage",
    [2]  = "Focus",
    [3]  = "Energy",
    [4]  = "Combo Points",
    [5]  = "Runes",
    [6]  = "Runic Power",
    [7]  = "Soul Shards",
    [8]  = "Astral Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [12] = "Chi",
    [13] = "Insanity",
    [16] = "Arcane Charges",
    [17] = "Fury",
    [18] = "Pain",
    [19] = "Essence",
    [100] = "Maelstrom Weapon",
}

local DEFAULT_MW_BASE_COLOR_CONFIG = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR_CONFIG = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR_CONFIG = { 0.5, 0.8, 1 }
local DEFAULT_CUSTOM_AURA_MAX_COLOR_CONFIG = { 1, 0.84, 0 }

local SEGMENTED_TYPES_CONFIG = {
    [4]  = true, [5]  = true, [7]  = true, [9]  = true,
    [12] = true, [16] = true, [19] = true,
}

local HIDE_AT_ZERO_ELIGIBLE = {
    [4]  = true, [7]  = true, [9]  = true,
    [12] = true, [16] = true, [100] = true,
}

local function SupportsResourceAuraStackModeConfig(powerType)
    return powerType == 100 or SEGMENTED_TYPES_CONFIG[powerType] == true
end

local DEFAULT_POWER_COLORS_CONFIG = {
    [0]  = { 0, 0, 1 },
    [1]  = { 1, 0, 0 },
    [2]  = { 1, 0.5, 0.25 },
    [3]  = { 1, 1, 0 },
    [4]  = { 1, 0.96, 0.41 },
    [5]  = { 0.5, 0.5, 0.5 },
    [6]  = { 0, 0.82, 1 },
    [7]  = { 0.5, 0.32, 0.55 },
    [8]  = { 0.3, 0.52, 0.9 },
    [9]  = { 0.95, 0.9, 0.6 },
    [11] = { 0, 0.5, 1 },
    [12] = { 0.71, 1, 0.92 },
    [13] = { 0.4, 0, 0.8 },
    [16] = { 0.1, 0.1, 0.98 },
    [17] = { 0.788, 0.259, 0.992 },
    [18] = { 1, 0.612, 0 },
    [19] = { 0.286, 0.773, 0.541 },
}

local DEFAULT_COMBO_COLOR_CONFIG = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_MAX_COLOR_CONFIG = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_CHARGED_COLOR_CONFIG = { 0.24, 0.65, 1.0 }

local DEFAULT_RUNE_READY_COLOR_CONFIG = { 0.8, 0.8, 0.8 }
local DEFAULT_RUNE_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_RUNE_MAX_COLOR_CONFIG = { 0.8, 0.8, 0.8 }

local DEFAULT_SHARD_READY_COLOR_CONFIG = { 0.5, 0.32, 0.55 }
local DEFAULT_SHARD_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_SHARD_MAX_COLOR_CONFIG = { 0.5, 0.32, 0.55 }

local DEFAULT_HOLY_COLOR_CONFIG = { 0.95, 0.9, 0.6 }
local DEFAULT_HOLY_MAX_COLOR_CONFIG = { 0.95, 0.9, 0.6 }

local DEFAULT_CHI_COLOR_CONFIG = { 0.71, 1, 0.92 }
local DEFAULT_CHI_MAX_COLOR_CONFIG = { 0.71, 1, 0.92 }

local DEFAULT_ARCANE_COLOR_CONFIG = { 0.1, 0.1, 0.98 }
local DEFAULT_ARCANE_MAX_COLOR_CONFIG = { 0.1, 0.1, 0.98 }

local DEFAULT_ESSENCE_READY_COLOR_CONFIG = { 0.851, 0.482, 0.780 }
local DEFAULT_ESSENCE_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_ESSENCE_MAX_COLOR_CONFIG = { 0.851, 0.482, 0.780 }
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR_CONFIG = { 1, 0.84, 0 }
local DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG = "current"
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT_CONFIG = "current_max"
local DEFAULT_RESOURCE_TEXT_FONT_CONFIG = "Friz Quadrata TT"
local DEFAULT_RESOURCE_TEXT_SIZE_CONFIG = 10
local DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG = "OUTLINE"
local DEFAULT_RESOURCE_TEXT_COLOR_CONFIG = { 1, 1, 1, 1 }
local DEFAULT_SEG_THRESHOLD_COLOR_CONFIG = { 1, 0.84, 0 }
local DEFAULT_CONTINUOUS_TICK_COLOR_CONFIG = { 1, 0.84, 0, 1 }
local DEFAULT_CONTINUOUS_TICK_MODE_CONFIG = "percent"
local DEFAULT_CONTINUOUS_TICK_PERCENT_CONFIG = 50
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE_CONFIG = 50
local DEFAULT_CONTINUOUS_TICK_WIDTH_CONFIG = 2

-- Class-to-resource mapping for config UI
local CLASS_RESOURCES_CONFIG = {
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
    [11] = { 1, 4, 3, 8, 0 },  -- All possible druid resources
    [12] = { 17 },
    [13] = { 19, 0 },
}

local SPEC_RESOURCES_CONFIG = {
    [258] = { 13, 0 },
    [262] = { 11, 0 },
    [263] = { 100, 0 },
    [62]  = { 16, 0 },
    [269] = { 12, 3 },
    [268] = { 3 },
    [581] = { 17 },
}

local function GetConfigActiveResources()
    local _, _, classID = UnitClass("player")
    if not classID then return {} end

    local specID = nil
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end

    -- For Druid, show all possible resources (user can toggle each)
    if classID == 11 then
        return CLASS_RESOURCES_CONFIG[11]
    end

    if specID and SPEC_RESOURCES_CONFIG[specID] then
        return SPEC_RESOURCES_CONFIG[specID]
    end

    return CLASS_RESOURCES_CONFIG[classID] or {}
end

local function GetCurrentConfigSpecID()
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        return C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end
    return nil
end

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

    local cache = auraBarAutocompleteCache or BuildAuraBarAutocompleteCache()
    local lookup = cleaned:lower()
    for _, entry in ipairs(cache) do
        if entry.nameLower == lookup then
            return entry.id, false
        end
    end

    return nil, false
end

local function GetResourceAuraEntryCountConfig(resource)
    if type(resource) ~= "table" or type(resource.auraOverlayEntries) ~= "table" then
        return 0
    end

    local count = 0
    for _, entry in pairs(resource.auraOverlayEntries) do
        if type(entry) == "table" then
            count = count + 1
        end
    end
    return count
end

local function GetResourceAuraEntryConfig(resource, specID)
    if type(resource) ~= "table" or not specID then
        return nil
    end

    local entries = resource.auraOverlayEntries
    if type(entries) ~= "table" then
        return nil
    end

    local direct = entries[specID]
    if type(direct) == "table" then
        return direct
    end

    local alternate = entries[tostring(specID)]
    if type(alternate) == "table" then
        return alternate
    end

    return nil
end

local function GetOrderedResourceAuraEntrySpecsConfig(resource, specOrder)
    local ordered = {}
    local seen = {}

    if type(resource) ~= "table" or type(resource.auraOverlayEntries) ~= "table" then
        return ordered
    end

    for _, specID in ipairs(specOrder or {}) do
        if GetResourceAuraEntryConfig(resource, specID) then
            ordered[#ordered + 1] = specID
            seen[specID] = true
        end
    end

    local extras = {}
    for key, entry in pairs(resource.auraOverlayEntries) do
        if type(entry) == "table" then
            local numericKey = tonumber(key)
            local normalizedKey = numericKey or key
            if not seen[normalizedKey] then
                extras[#extras + 1] = normalizedKey
                seen[normalizedKey] = true
            end
        end
    end

    table.sort(extras, function(a, b)
        local aNum, bNum = tonumber(a), tonumber(b)
        if aNum and bNum then
            return aNum < bNum
        end
        return tostring(a) < tostring(b)
    end)

    for _, specID in ipairs(extras) do
        ordered[#ordered + 1] = specID
    end

    return ordered
end

local function GetUnusedResourceAuraSpecsConfig(resource, specOrder)
    local available = {}

    for _, specID in ipairs(specOrder or {}) do
        if not GetResourceAuraEntryConfig(resource, specID) then
            available[#available + 1] = specID
        end
    end

    return available
end

local function EnsureResourceAuraDraftStoreConfig()
    if type(CS.resourceAuraOverlayDrafts) ~= "table" then
        CS.resourceAuraOverlayDrafts = {}
    end
    return CS.resourceAuraOverlayDrafts
end

local function GetResourceAuraDraftConfig(powerType)
    return EnsureResourceAuraDraftStoreConfig()[powerType]
end

local function SetResourceAuraDraftConfig(powerType, state)
    EnsureResourceAuraDraftStoreConfig()[powerType] = state
end

local function CreateResourceAuraDraftConfig(powerType, resource, preferredSpecID, specOrder)
    local availableSpecs = GetUnusedResourceAuraSpecsConfig(resource, specOrder)
    if #availableSpecs == 0 then
        return nil
    end

    local selectedSpecID = nil
    for _, specID in ipairs(availableSpecs) do
        if specID == preferredSpecID then
            selectedSpecID = specID
            break
        end
    end
    if not selectedSpecID then
        selectedSpecID = availableSpecs[1]
    end

    local draft = {
        specID = selectedSpecID,
    }
    if SupportsResourceAuraStackModeConfig(powerType) then
        draft.auraColorTrackingMode = "active"
    end
    return draft
end

local function IsResourceAuraOverlayEnabledConfig(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    if GetResourceAuraEntryCountConfig(resource) > 0 then
        return true
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function GetResourceAuraTrackingModeConfig(resource)
    if type(resource) ~= "table" then
        return "active"
    end
    if resource.auraColorTrackingMode == "stacks" or resource.auraColorTrackingMode == "active" then
        return resource.auraColorTrackingMode
    end
    local configured = tonumber(resource.auraColorMaxStacks)
    if configured and configured >= 2 then
        return "stacks"
    end
    return "active"
end

local function GetSafeRGBConfig(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

local function GetSafeRGBAConfig(color, fallback)
    if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
        return color
    end
    return fallback
end

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
    return DEFAULT_CONTINUOUS_TICK_MODE_CONFIG
end

local function GetContinuousTickPercentConfig(resource)
    local value = tonumber(resource and resource.continuousTickPercent)
    if not value then
        return DEFAULT_CONTINUOUS_TICK_PERCENT_CONFIG
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
        return DEFAULT_CONTINUOUS_TICK_ABSOLUTE_CONFIG
    end
    if value < 0 then
        value = 0
    end
    return value
end

local function AttachAuraAutocompleteHandlers(editBoxWidget, onAuraSelect)
    editBoxWidget:SetCallback("OnTextChanged", function(widget, event, text)
        if text and #text >= 1 then
            local cache = auraBarAutocompleteCache or BuildAuraBarAutocompleteCache()
            local results = CS.SearchAutocompleteInCache(text, cache)
            CS.ShowAutocompleteResults(results, widget, onAuraSelect)
        else
            CS.HideAutocomplete()
        end
    end)

    CS.SetupAutocompleteKeyHandler(editBoxWidget)
end

local function AddResourceAuraEntryFields(container, powerType, resourceName, entry, options)
    options = options or {}

    if options.specList and options.specOrder and options.onSpecChanged then
        local specDrop = AceGUI:Create("Dropdown")
        specDrop:SetLabel("Specialization")
        specDrop:SetList(options.specList, options.specOrder)
        specDrop:SetValue(options.specID)
        specDrop:SetFullWidth(true)
        specDrop:SetCallback("OnValueChanged", function(widget, event, val)
            options.onSpecChanged(tonumber(val) or val)
        end)
        container:AddChild(specDrop)
    end

    local spellID = tonumber(entry and entry.auraColorSpellID) or nil
    local spellEdit = AceGUI:Create("EditBox")
    if spellEdit.editbox.Instructions then spellEdit.editbox.Instructions:Hide() end
    spellEdit:SetLabel(resourceName .. " Aura (Spell ID or Name)")
    spellEdit:SetText(spellID and tostring(spellID) or "")
    spellEdit:SetFullWidth(true)
    spellEdit:DisableButton(true)

    local function CommitSpellID(id)
        CS.HideAutocomplete()
        if options.onSpellChanged then
            options.onSpellChanged(id)
        end
    end

    spellEdit:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        CS.HideAutocomplete()

        local id, explicitClear = ResolveAuraColorSpellIDFromText(text)
        if not id and not explicitClear then
            return
        end

        CommitSpellID(id)
    end)

    AttachAuraAutocompleteHandlers(spellEdit, function(selectedEntry)
        CommitSpellID(selectedEntry.id)
    end)

    container:AddChild(spellEdit)

    if spellID then
        local auraName = C_Spell.GetSpellName(spellID)
        if auraName then
            local auraLabel = AceGUI:Create("Label")
            auraLabel:SetText("|cff888888" .. auraName .. "|r")
            auraLabel:SetFullWidth(true)
            container:AddChild(auraLabel)
        end
    end

    AddCdmAuraReadinessWarning(container, spellID)

    local auraColorPicker = AceGUI:Create("ColorPicker")
    auraColorPicker:SetLabel(resourceName .. " Aura Active Color")
    local auraColor = GetSafeRGBConfig(entry and entry.auraActiveColor, DEFAULT_RESOURCE_AURA_ACTIVE_COLOR_CONFIG)
    auraColorPicker:SetColor(auraColor[1], auraColor[2], auraColor[3])
    auraColorPicker:SetHasAlpha(false)
    auraColorPicker:SetFullWidth(true)
    auraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b)
        if options.onColorChanged then
            options.onColorChanged(r, g, b)
        end
    end)
    auraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
        if options.onColorConfirmed then
            options.onColorConfirmed(r, g, b)
        end
    end)
    container:AddChild(auraColorPicker)

    if SupportsResourceAuraStackModeConfig(powerType) then
        local trackingMode = GetResourceAuraTrackingModeConfig(entry)
        local trackDrop = AceGUI:Create("Dropdown")
        trackDrop:SetLabel("Tracking Mode")
        trackDrop:SetList({
            stacks = "Stack Count",
            active = "Active (On/Off)",
        }, { "stacks", "active" })
        trackDrop:SetValue(trackingMode)
        trackDrop:SetFullWidth(true)
        trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
            if options.onTrackingChanged then
                options.onTrackingChanged(val)
            end
        end)
        container:AddChild(trackDrop)

        if trackingMode ~= "active" then
            local auraStackEdit = AceGUI:Create("EditBox")
            if auraStackEdit.editbox.Instructions then auraStackEdit.editbox.Instructions:Hide() end
            auraStackEdit:SetLabel(resourceName .. " Aura Max Stacks")
            auraStackEdit:SetText(entry and entry.auraColorMaxStacks and tostring(entry.auraColorMaxStacks) or "")
            auraStackEdit:SetFullWidth(true)
            auraStackEdit:DisableButton(true)
            auraStackEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                local cleaned = text and text:gsub("%s", "") or ""
                local parsed = nil
                if cleaned ~= "" then
                    local num = tonumber(cleaned)
                    if num then
                        num = math.floor(num)
                        if num >= 2 then
                            if num > 99 then num = 99 end
                            parsed = num
                        end
                    end
                    if not parsed then
                        local current = entry and entry.auraColorMaxStacks
                        widget:SetText(current and tostring(current) or "")
                        return
                    end
                end

                if options.onMaxStacksChanged then
                    options.onMaxStacksChanged(parsed)
                end
                widget:SetText(parsed and tostring(parsed) or "")
            end)
            container:AddChild(auraStackEdit)

            local auraStackHint = AceGUI:Create("Label")
            auraStackHint:SetText("|cff888888Stack mode maps aura stacks to a bar proportion (e.g. 1/2 = half bar). Applies only to segmented/overlay resources.|r")
            auraStackHint:SetFullWidth(true)
            container:AddChild(auraStackHint)
        end
    end
end

local function GetSpecDisplayInfoConfig(specID, specInfoByID)
    local numericSpecID = tonumber(specID) or specID
    local info = specInfoByID and specInfoByID[numericSpecID]
    if info then
        return info
    end

    local _, name, _, icon = GetSpecializationInfoForSpecID(numericSpecID)
    return {
        specID = numericSpecID,
        name = name or ("Spec " .. tostring(specID)),
        icon = icon,
    }
end

local function GetResourceAuraEntryCollapsedBucketConfig(powerType, create)
    local powerKey = tonumber(powerType) or powerType
    local bucket = resourceAuraEntryCollapsedStates[powerKey]
    if not bucket and create then
        bucket = {}
        resourceAuraEntryCollapsedStates[powerKey] = bucket
    end
    return bucket, powerKey
end

local function IsResourceAuraEntryCollapsedConfig(powerType, specID)
    local bucket = GetResourceAuraEntryCollapsedBucketConfig(powerType, false)
    return bucket and bucket[tostring(specID)] == true or false
end

local function SetResourceAuraEntryCollapsedConfig(powerType, specID, isCollapsed)
    local specKey = tostring(specID)
    if isCollapsed then
        local bucket = GetResourceAuraEntryCollapsedBucketConfig(powerType, true)
        bucket[specKey] = true
        return
    end

    local bucket, powerKey = GetResourceAuraEntryCollapsedBucketConfig(powerType, false)
    if not bucket then
        return
    end

    bucket[specKey] = nil
    if not next(bucket) then
        resourceAuraEntryCollapsedStates[powerKey] = nil
    end
end

local function ClearLegacyResourceAuraFieldsConfig(resource)
    if type(resource) ~= "table" then
        return
    end
    resource.auraColorSpellID = nil
    resource.auraActiveColor = nil
    resource.auraColorTrackingMode = nil
    resource.auraColorMaxStacks = nil
end

local function GetResourceAuraEntrySummaryTextConfig(powerType, entry)
    local auraSpellID = tonumber(entry and entry.auraColorSpellID)
    local auraText = "No aura selected"
    if auraSpellID then
        auraText = C_Spell.GetSpellName(auraSpellID) or ("Spell ID " .. auraSpellID)
    end

    local trackingText = "Active"
    local maxStacks = nil
    if SupportsResourceAuraStackModeConfig(powerType) then
        local trackingMode = GetResourceAuraTrackingModeConfig(entry)
        if trackingMode == "stacks" then
            trackingText = "Stacks"
            local configuredMaxStacks = tonumber(entry and entry.auraColorMaxStacks)
            if configuredMaxStacks and configuredMaxStacks >= 2 then
                maxStacks = configuredMaxStacks
            end
        end
    end

    local summary = "|cff888888Aura:|r " .. auraText .. " |cff888888Mode:|r " .. trackingText
    if maxStacks then
        summary = summary .. " (Max " .. maxStacks .. ")"
    end
    return summary
end

local function ClearResourceAuraEntryConfig(powerType, resource, specID)
    if type(resource.auraOverlayEntries) ~= "table" then
        return
    end

    SetResourceAuraEntryCollapsedConfig(powerType, specID, false)
    resource.auraOverlayEntries[specID] = nil
    resource.auraOverlayEntries[tostring(specID)] = nil
    if not next(resource.auraOverlayEntries) then
        resource.auraOverlayEntries = nil
        SetResourceAuraDraftConfig(powerType, nil)
    end

    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:RefreshConfigPanel()
end

local CompactUntitledInlineGroupConfig = ST._CompactUntitledInlineGroupConfig

local function AttachResourceAuraEntryToggleButton(parentWidget, isCollapsed, onClickFn)
    local frame = parentWidget and parentWidget.frame
    if not frame then
        return nil
    end

    local btn = frame._cdcResourceAuraEntryToggleBtn
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(15, 15)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetAllPoints()
        frame._cdcResourceAuraEntryToggleBtn = btn
    end

    local atlas = isCollapsed and RESOURCE_AURA_ENTRY_EXPAND_ATLAS or RESOURCE_AURA_ENTRY_MINIMIZE_ATLAS

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    btn:Show()
    btn._icon:Show()
    btn._icon:SetAtlas(atlas, false)
    btn:SetHighlightAtlas(atlas)
    if btn:GetHighlightTexture() then
        btn:GetHighlightTexture():SetAlpha(0.3)
    end

    btn:SetScript("OnClick", onClickFn)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(isCollapsed and "Edit entry" or "Minimize entry")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    parentWidget:SetCallback("OnRelease", function()
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end)

    return btn
end

local function AddResourceAuraEntryCard(container, settings, powerType, resourceName, resource, specID, specInfoByID)
    local entry = GetResourceAuraEntryConfig(resource, specID)
    if type(entry) ~= "table" then
        return
    end

    local specInfo = GetSpecDisplayInfoConfig(specID, specInfoByID)
    local isCollapsed = IsResourceAuraEntryCollapsedConfig(powerType, specID)
    local entryGroup = AceGUI:Create("InlineGroup")
    entryGroup:SetTitle("")
    entryGroup:SetLayout("List")
    entryGroup:SetFullWidth(true)
    CompactUntitledInlineGroupConfig(entryGroup)
    container:AddChild(entryGroup)

    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetLayout("Flow")
    headerRow:SetFullWidth(true)

    local specLabel = AceGUI:Create("Label")
    specLabel:SetText(specInfo.name or ("Spec " .. tostring(specID)))
    specLabel:SetFontObject(GameFontNormalLarge)
    if specInfo.icon then
        specLabel:SetImage(specInfo.icon)
        specLabel:SetImageSize(20, 20)
    else
        specLabel:SetImage(nil)
    end
    specLabel:SetRelativeWidth(0.88)
    headerRow:AddChild(specLabel)
    entryGroup:AddChild(headerRow)
    AttachResourceAuraEntryToggleButton(headerRow, isCollapsed, function()
        SetResourceAuraEntryCollapsedConfig(powerType, specID, not isCollapsed)
        CooldownCompanion:RefreshConfigPanel()
    end)

    if isCollapsed then
        local summaryLabel = AceGUI:Create("Label")
        summaryLabel:SetText(GetResourceAuraEntrySummaryTextConfig(powerType, entry))
        summaryLabel:SetFullWidth(true)
        entryGroup:AddChild(summaryLabel)
        return
    end

    AddResourceAuraEntryFields(entryGroup, powerType, resourceName, entry, {
        onSpellChanged = function(id)
            entry.auraColorSpellID = id
            ClearLegacyResourceAuraFieldsConfig(resource)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
        onColorChanged = function(r, g, b)
            entry.auraActiveColor = { r, g, b }
        end,
        onColorConfirmed = function(r, g, b)
            entry.auraActiveColor = { r, g, b }
            ClearLegacyResourceAuraFieldsConfig(resource)
            CooldownCompanion:ApplyResourceBars()
        end,
        onTrackingChanged = function(val)
            entry.auraColorTrackingMode = val
            if val == "stacks" then
                local current = tonumber(entry.auraColorMaxStacks)
                if not current or current < 2 then
                    entry.auraColorMaxStacks = 2
                end
            end
            ClearLegacyResourceAuraFieldsConfig(resource)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
        onMaxStacksChanged = function(parsed)
            entry.auraColorMaxStacks = parsed
            ClearLegacyResourceAuraFieldsConfig(resource)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    local clearSpacer = AceGUI:Create("Label")
    clearSpacer:SetText(" ")
    clearSpacer:SetFullWidth(true)
    entryGroup:AddChild(clearSpacer)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear Entry")
    clearBtn:SetFullWidth(true)
    clearBtn:SetCallback("OnClick", function()
        ClearResourceAuraEntryConfig(powerType, resource, specID)
    end)
    entryGroup:AddChild(clearBtn)
end

local function AddResourceAuraDraftEditor(container, settings, powerType, resourceName, resource, specList, specOrder)
    local draft = GetResourceAuraDraftConfig(powerType)
    if type(draft) ~= "table" then
        return
    end

    local draftGroup = AceGUI:Create("InlineGroup")
    draftGroup:SetTitle("Add Entry")
    draftGroup:SetLayout("List")
    draftGroup:SetFullWidth(true)
    container:AddChild(draftGroup)

    local helpLabel = AceGUI:Create("Label")
    helpLabel:SetText("|cff888888Choose which specialization this aura overlay should load for, then fill in the overlay settings.|r")
    helpLabel:SetFullWidth(true)
    draftGroup:AddChild(helpLabel)

    AddResourceAuraEntryFields(draftGroup, powerType, resourceName, draft, {
        specList = specList,
        specOrder = specOrder,
        specID = draft.specID,
        onSpecChanged = function(val)
            draft.specID = val
        end,
        onSpellChanged = function(id)
            draft.auraColorSpellID = id
            CooldownCompanion:RefreshConfigPanel()
        end,
        onColorChanged = function(r, g, b)
            draft.auraActiveColor = { r, g, b }
        end,
        onColorConfirmed = function(r, g, b)
            draft.auraActiveColor = { r, g, b }
        end,
        onTrackingChanged = function(val)
            draft.auraColorTrackingMode = val
            if val == "stacks" then
                local current = tonumber(draft.auraColorMaxStacks)
                if not current or current < 2 then
                    draft.auraColorMaxStacks = 2
                end
            end
            CooldownCompanion:RefreshConfigPanel()
        end,
        onMaxStacksChanged = function(parsed)
            draft.auraColorMaxStacks = parsed
        end,
    })

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetLayout("Flow")
    buttonRow:SetFullWidth(true)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add Entry")
    addBtn:SetRelativeWidth(0.49)
    addBtn:SetCallback("OnClick", function()
        local specID = tonumber(draft.specID)
        if not specID or GetResourceAuraEntryConfig(resource, specID) then
            return
        end

        if type(resource.auraOverlayEntries) ~= "table" then
            resource.auraOverlayEntries = {}
        end

        local savedEntry = {
            auraColorSpellID = tonumber(draft.auraColorSpellID) or nil,
            auraActiveColor = CopyRGBConfig(draft.auraActiveColor),
            auraColorTrackingMode = draft.auraColorTrackingMode,
            auraColorMaxStacks = draft.auraColorMaxStacks,
        }
        resource.auraOverlayEntries[specID] = savedEntry
        resource.auraOverlayEnabled = true
        ClearLegacyResourceAuraFieldsConfig(resource)
        SetResourceAuraEntryCollapsedConfig(powerType, specID, false)
        SetResourceAuraDraftConfig(powerType, nil)

        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    buttonRow:AddChild(addBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetRelativeWidth(0.49)
    cancelBtn:SetCallback("OnClick", function()
        SetResourceAuraDraftConfig(powerType, false)
        CooldownCompanion:RefreshConfigPanel()
    end)
    buttonRow:AddChild(cancelBtn)

    draftGroup:AddChild(buttonRow)
end

local function AddResourceAuraOverrideControls(container, settings, powerType, resourceName, auraAdvButtons)
    if not settings.resources[powerType] then
        settings.resources[powerType] = {}
    end
    local res = settings.resources[powerType]
    local auraAdvKey = "rbAuraOverlay_" .. powerType

    local enableAuraOverlayCb = AceGUI:Create("CheckBox")
    enableAuraOverlayCb:SetLabel("Enable " .. resourceName .. " Aura Overlay")
    enableAuraOverlayCb:SetValue(IsResourceAuraOverlayEnabledConfig(res))
    enableAuraOverlayCb:SetFullWidth(true)
    enableAuraOverlayCb:SetCallback("OnValueChanged", function(widget, event, val)
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        local wasEnabled = IsResourceAuraOverlayEnabledConfig(settings.resources[powerType])
        settings.resources[powerType].auraOverlayEnabled = (val == true)
        SetResourceAuraDraftConfig(powerType, nil)

        if val and not wasEnabled then
            if type(CooldownCompanion.db.profile.showAdvanced) ~= "table" then
                CooldownCompanion.db.profile.showAdvanced = {}
            end
            CooldownCompanion.db.profile.showAdvanced[auraAdvKey] = true
        end
        CooldownCompanion:ApplyResourceBars()
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(enableAuraOverlayCb)

    local auraAdvExpanded = AddAdvancedToggle(
        enableAuraOverlayCb,
        auraAdvKey,
        auraAdvButtons or tabInfoButtons,
        IsResourceAuraOverlayEnabledConfig(res)
    )

    if not IsResourceAuraOverlayEnabledConfig(res) or not auraAdvExpanded then
        return
    end

    local specList, specOrder, specInfoByID = GetPlayerSpecOptionsConfig()
    local currentSpecID = GetCurrentConfigSpecID()
    local entryCount = GetResourceAuraEntryCountConfig(res)
    local draftState = GetResourceAuraDraftConfig(powerType)

    if entryCount == 0 and draftState == nil then
        SetResourceAuraDraftConfig(powerType, CreateResourceAuraDraftConfig(powerType, res, currentSpecID, specOrder))
        draftState = GetResourceAuraDraftConfig(powerType)
    end

    local orderedSpecs = GetOrderedResourceAuraEntrySpecsConfig(res, specOrder)
    for _, specID in ipairs(orderedSpecs) do
        AddResourceAuraEntryCard(container, settings, powerType, resourceName, res, specID, specInfoByID)
    end

    local availableSpecs = GetUnusedResourceAuraSpecsConfig(res, specOrder)
    if type(draftState) == "table" then
        AddResourceAuraDraftEditor(container, settings, powerType, resourceName, res, specList, availableSpecs)
    elseif #availableSpecs > 0 then
        local addBtn = AceGUI:Create("Button")
        addBtn:SetText("Add Entry")
        addBtn:SetFullWidth(true)
        addBtn:SetCallback("OnClick", function()
            SetResourceAuraDraftConfig(powerType, CreateResourceAuraDraftConfig(powerType, res, currentSpecID, specOrder))
            CooldownCompanion:RefreshConfigPanel()
        end)
        addBtn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
            if entryCount == 0 then
                GameTooltip:AddLine("No specialization entries configured yet.")
            else
                GameTooltip:AddLine("Add another specialization entry for this resource aura overlay.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        addBtn:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        container:AddChild(addBtn)
    end
end

local function BuildResourceAuraOverlaySection(container, settings)
    local auraHeading = AceGUI:Create("Heading")
    auraHeading:SetText("Resource Aura Overlays")
    ColorHeading(auraHeading)
    auraHeading:SetFullWidth(true)
    container:AddChild(auraHeading)

    local auraKey = "rb_resource_aura_overlays"
    local auraCollapsed = resourceBarCollapsedSections[auraKey]

    local auraCollapseBtn = AttachCollapseButton(auraHeading, auraCollapsed, function()
        resourceBarCollapsedSections[auraKey] = not resourceBarCollapsedSections[auraKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local auraInfoBtn = CreateInfoButton(auraHeading.frame, auraCollapseBtn, "LEFT", "RIGHT", 4, 0, {
        "Resource Aura Overlays",
        {"When enabled, a selected aura (by Spell ID) recolors the resource bar while that aura is active.", 1, 1, 1, true},
        " ",
        {"You can set the active color, and optional stack lanes for segmented resources.", 1, 1, 1, true},
    }, auraHeading)

    auraHeading.right:ClearAllPoints()
    auraHeading.right:SetPoint("RIGHT", auraHeading.frame, "RIGHT", -3, 0)
    auraHeading.right:SetPoint("LEFT", auraInfoBtn, "RIGHT", 4, 0)

    if not auraCollapsed then
        local rbAuraOverlayAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
                AddResourceAuraOverrideControls(container, settings, pt, resourceName, rbAuraOverlayAdvBtns)
            end
        end
    end
end

local function IsResourceBarVerticalConfig(settings)
    return settings and settings.orientation == "vertical"
end

local function GetResourceThicknessFieldConfig(settings)
    if IsResourceBarVerticalConfig(settings) then
        return "barWidth", "Bar Width", "Custom Resource Bar Widths"
    end
    return "barHeight", "Bar Height", "Custom Resource Bar Heights"
end

local function GetResourceGapFieldConfig(settings)
    if IsResourceBarVerticalConfig(settings) then
        return "verticalXOffset", "X Offset"
    end
    return "yOffset", "Y Offset"
end

local function BuildResourceBarAnchoringPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetResourceBarSettings()
    local isVerticalLayout = IsResourceBarVerticalConfig(settings)
    local thicknessField, thicknessLabel, customThicknessLabel = GetResourceThicknessFieldConfig(settings)
    local gapField, gapLabel = GetResourceGapFieldConfig(settings)

    -- Enable Resource Bars
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Resource Bars")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    AddCharacterScopedCopyControls(container, "resourceBars", "Resource Bars", function()
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not settings.enabled then return end
    if not settings.resources then settings.resources = {} end

    -- Anchor Group dropdown
    local anchorDrop = AceGUI:Create("Dropdown")
    anchorDrop:SetLabel("Anchor to Panel")
    local eligibleCount = CooldownCompanion:PopulateAnchorDropdown(anchorDrop)
    anchorDrop:SetValue(settings.anchorGroupId and tostring(settings.anchorGroupId) or "")
    anchorDrop:SetFullWidth(true)
    anchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.anchorGroupId = val ~= "" and tonumber(val) or nil
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorDrop)

    local orientDrop = AceGUI:Create("Dropdown")
    orientDrop:SetLabel("Bar Orientation")
    orientDrop:SetList({
        horizontal = "Horizontal",
        vertical = "Vertical",
    }, { "horizontal", "vertical" })
    orientDrop:SetValue(settings.orientation or "horizontal")
    orientDrop:SetFullWidth(true)
    orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.orientation = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(orientDrop)

    local fillDirDrop = AceGUI:Create("Dropdown")
    fillDirDrop:SetLabel("Vertical Fill Direction")
    fillDirDrop:SetList({
        bottom_to_top = "Bottom to Top",
        top_to_bottom = "Top to Bottom",
    }, { "bottom_to_top", "top_to_bottom" })
    fillDirDrop:SetValue(settings.verticalFillDirection or "bottom_to_top")
    fillDirDrop:SetDisabled(not isVerticalLayout)
    fillDirDrop:SetFullWidth(true)
    fillDirDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.verticalFillDirection = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
    end)
    container:AddChild(fillDirDrop)

    if eligibleCount == 0 then
        local noGroupsLabel = AceGUI:Create("Label")
        noGroupsLabel:SetText("No eligible character icon panels are enabled for this spec. Global panels are excluded from anchoring.")
        noGroupsLabel:SetFullWidth(true)
        container:AddChild(noGroupsLabel)
    end

    -- Preview toggle (ephemeral)
    local previewCb = AceGUI:Create("CheckBox")
    previewCb:SetLabel("Preview Resource Bars")
    previewCb:SetValue(CooldownCompanion:IsResourceBarPreviewActive())
    previewCb:SetFullWidth(true)
    previewCb:SetCallback("OnValueChanged", function(widget, event, val)
        if val then
            CooldownCompanion:StartResourceBarPreview()
        else
            CooldownCompanion:StopResourceBarPreview()
        end
    end)
    container:AddChild(previewCb)

    -- Inherit group alpha checkbox
    local alphaCb = AceGUI:Create("CheckBox")
    alphaCb:SetLabel("Inherit group alpha")
    alphaCb:SetValue(settings.inheritAlpha)
    alphaCb:SetFullWidth(true)
    alphaCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.inheritAlpha = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(alphaCb)

    -- ============ Position Section ============
    local posHeading = AceGUI:Create("Heading")
    posHeading:SetText("Position")
    ColorHeading(posHeading)
    posHeading:SetFullWidth(true)
    container:AddChild(posHeading)

    local posKey = "rb_position"
    local posCollapsed = resourceBarCollapsedSections[posKey]

    AttachCollapseButton(posHeading, posCollapsed, function()
        resourceBarCollapsedSections[posKey] = not resourceBarCollapsedSections[posKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not posCollapsed then
        local gapSlider = AceGUI:Create("Slider")
        gapSlider:SetLabel(gapLabel)
        gapSlider:SetSliderValues(0, 50, 0.1)
        if gapField == "verticalXOffset" then
            gapSlider:SetValue(settings.verticalXOffset or settings.yOffset or 3)
        else
            gapSlider:SetValue(settings.yOffset or settings.verticalXOffset or 3)
        end
        gapSlider:SetFullWidth(true)
        gapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings[gapField] = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(gapSlider)

        if isVerticalLayout then
            local castGapSlider = AceGUI:Create("Slider")
            castGapSlider:SetLabel("Cast Bar Y Offset")
            castGapSlider:SetSliderValues(0, 50, 0.1)
            castGapSlider:SetValue(settings.yOffset or 3)
            castGapSlider:SetFullWidth(true)
            castGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.yOffset = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(castGapSlider)
        end

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel(thicknessLabel)
        hSlider:SetSliderValues(4, 40, 0.1)
        if thicknessField == "barWidth" then
            hSlider:SetValue(settings.barWidth or settings.barHeight or 12)
        else
            hSlider:SetValue(settings.barHeight or settings.barWidth or 12)
        end
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings[thicknessField] = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        hSlider:SetDisabled(settings.customBarHeights or false)
        container:AddChild(hSlider)

        local customHeightsCb = AceGUI:Create("CheckBox")
        customHeightsCb:SetLabel(customThicknessLabel)
        customHeightsCb:SetValue(settings.customBarHeights or false)
        customHeightsCb:SetFullWidth(true)
        customHeightsCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.customBarHeights = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(customHeightsCb)

        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Bar Spacing")
        spacingSlider:SetSliderValues(0, 20, 0.1)
        spacingSlider:SetValue(settings.barSpacing or 3.6)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.barSpacing = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(spacingSlider)
    end

    -- ============ Resource Toggles Section ============
    local toggleHeading = AceGUI:Create("Heading")
    toggleHeading:SetText("Resource Toggles")
    ColorHeading(toggleHeading)
    toggleHeading:SetFullWidth(true)
    container:AddChild(toggleHeading)

    local toggleKey = "rb_toggles"
    local toggleCollapsed = resourceBarCollapsedSections[toggleKey]

    AttachCollapseButton(toggleHeading, toggleCollapsed, function()
        resourceBarCollapsedSections[toggleKey] = not resourceBarCollapsedSections[toggleKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not toggleCollapsed then
        -- Only show mana toggle for classes that actually use mana
        local _, _, classID = UnitClass("player")
        local NO_MANA_CLASSES = { [1] = true, [3] = true, [4] = true, [6] = true, [12] = true }
        if classID and not NO_MANA_CLASSES[classID] then
            local manaCb = AceGUI:Create("CheckBox")
            manaCb:SetLabel("Hide Mana for Non-Healer Specs")
            manaCb:SetValue(settings.hideManaForNonHealer ~= false)
            manaCb:SetFullWidth(true)
            manaCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.hideManaForNonHealer = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(manaCb)
        end

        -- Per-resource enable/disable
        local rbHeightAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            local enabled = settings.resources[pt].enabled ~= false

            local resCb = AceGUI:Create("CheckBox")
            resCb:SetLabel("Show " .. name)
            resCb:SetValue(enabled)
            resCb:SetFullWidth(true)
            resCb:SetCallback("OnValueChanged", function(widget, event, val)
                if not settings.resources[pt] then
                    settings.resources[pt] = {}
                end
                settings.resources[pt].enabled = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(resCb)

            if settings.customBarHeights then
                local advExpanded = AddAdvancedToggle(resCb, "rbHeight_" .. pt, rbHeightAdvBtns, enabled)
                if advExpanded then
                    local resHeightSlider = AceGUI:Create("Slider")
                    resHeightSlider:SetLabel(thicknessLabel)
                    resHeightSlider:SetSliderValues(4, 40, 0.1)
                    if thicknessField == "barWidth" then
                        resHeightSlider:SetValue(
                            settings.resources[pt].barWidth or settings.resources[pt].barHeight
                            or settings.barWidth or settings.barHeight or 12
                        )
                    else
                        resHeightSlider:SetValue(
                            settings.resources[pt].barHeight or settings.resources[pt].barWidth
                            or settings.barHeight or settings.barWidth or 12
                        )
                    end
                    resHeightSlider:SetFullWidth(true)
                    local capturedPt = pt
                    resHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        if not settings.resources[capturedPt] then
                            settings.resources[capturedPt] = {}
                        end
                        settings.resources[capturedPt][thicknessField] = val
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                    end)
                    container:AddChild(resHeightSlider)
                end
            end
        end
    end
end

------------------------------------------------------------------------

local LSM = LibStub("LibSharedMedia-3.0")

local function GetResourceBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    t["blizzard_class"] = "Blizzard (Class)"
    return t
end

local function BuildResourceBarStylingPanel(container, sectionMode)
    local settings = CooldownCompanion:GetResourceBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure styling.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local mode = sectionMode or "all"
    local showBarText = (mode == "all" or mode == "bar_text")
    local showColors = (mode == "all" or mode == "colors")
    local showAuraOverlays = (mode == "all" or mode == "aura_overlays")

    if showBarText then
    -- Bar Texture
    local texDrop = AceGUI:Create("Dropdown")
    texDrop:SetLabel("Bar Texture")
    texDrop:SetList(GetResourceBarTextureOptions())
    texDrop:SetValue(settings.barTexture or "Solid")
    texDrop:SetFullWidth(true)
    texDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.barTexture = val
        CooldownCompanion:ApplyResourceBars()
        -- Defer panel rebuild to next frame so it doesn't interfere with current callback
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(texDrop)

    -- Brightness slider (only for Blizzard Class texture)
    if settings.barTexture == "blizzard_class" then
        local brightSlider = AceGUI:Create("Slider")
        brightSlider:SetLabel("Class Texture Brightness")
        brightSlider:SetSliderValues(0.5, 2.0, 0.1)
        brightSlider:SetValue(settings.classBarBrightness or 1.3)
        brightSlider:SetFullWidth(true)
        brightSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.classBarBrightness = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(brightSlider)
    end

    -- Background Color
    local bgColorPicker = AceGUI:Create("ColorPicker")
    bgColorPicker:SetLabel("Background Color")
    local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
    bgColorPicker:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    bgColorPicker:SetHasAlpha(true)
    bgColorPicker:SetFullWidth(true)
    bgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        settings.backgroundColor = {r, g, b, a}
    end)
    bgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        settings.backgroundColor = {r, g, b, a}
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(bgColorPicker)

    -- Border Style
    local borderDrop = AceGUI:Create("Dropdown")
    borderDrop:SetLabel("Border Style")
    borderDrop:SetList({
        pixel = "Pixel",
        none = "None",
    }, { "pixel", "none" })
    borderDrop:SetValue(settings.borderStyle or "pixel")
    borderDrop:SetFullWidth(true)
    borderDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.borderStyle = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(borderDrop)

    if settings.borderStyle == "pixel" then
        local borderColorPicker = AceGUI:Create("ColorPicker")
        borderColorPicker:SetLabel("Border Color")
        local brc = settings.borderColor or { 0, 0, 0, 1 }
        borderColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
        borderColorPicker:SetHasAlpha(true)
        borderColorPicker:SetFullWidth(true)
        borderColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            settings.borderColor = {r, g, b, a}
        end)
        borderColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            settings.borderColor = {r, g, b, a}
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(borderColorPicker)

        local borderSizeSlider = AceGUI:Create("Slider")
        borderSizeSlider:SetLabel("Border Size")
        borderSizeSlider:SetSliderValues(0, 4, 0.1)
        borderSizeSlider:SetValue(settings.borderSize or 1)
        borderSizeSlider:SetIsPercent(false)
        borderSizeSlider:SetFullWidth(true)
        borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.borderSize = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(borderSizeSlider)
    end

    -- Segment Gap
    local gapSlider = AceGUI:Create("Slider")
    gapSlider:SetLabel("Segment Gap")
    gapSlider:SetSliderValues(0, 20, 0.1)
    gapSlider:SetValue(settings.segmentGap or 4)
    gapSlider:SetFullWidth(true)
    gapSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.segmentGap = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(gapSlider)

    -- ============ Text Section ============
    local rbTextAdvBtns = {}

    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text")
    ColorHeading(textHeading)
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    local textKey = "rb_text"
    local textCollapsed = resourceBarCollapsedSections[textKey]

    local textCollapseBtn = AttachCollapseButton(textHeading, textCollapsed, function()
        resourceBarCollapsedSections[textKey] = not resourceBarCollapsedSections[textKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    textHeading.right:ClearAllPoints()
    textHeading.right:SetPoint("RIGHT", textHeading.frame, "RIGHT", -3, 0)
    textHeading.right:SetPoint("LEFT", textCollapseBtn, "RIGHT", 4, 0)

    if not textCollapsed then
        -- Per-resource "Show Text" checkboxes (continuous + segmented resources)
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local capturedPt = pt
            local isSegmentedResource = (SEGMENTED_TYPES_CONFIG[capturedPt] == true) or (capturedPt == 100)
            if not settings.resources[capturedPt] then
                settings.resources[capturedPt] = {}
            end
            local resSettings = settings.resources[capturedPt]
            local name = POWER_NAMES_CONFIG[capturedPt] or ("Power " .. capturedPt)

            local showTextEnabled
            if isSegmentedResource then
                -- Segmented resources are off by default unless explicitly enabled.
                showTextEnabled = resSettings.showText == true
            else
                showTextEnabled = resSettings.showText ~= false
            end

            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel("Show " .. name .. " Text")
            cb:SetValue(showTextEnabled)
            cb:SetFullWidth(true)
            cb:SetCallback("OnValueChanged", function(widget, event, val)
                if not settings.resources[capturedPt] then settings.resources[capturedPt] = {} end
                if isSegmentedResource then
                    settings.resources[capturedPt].showText = val and true or nil
                else
                    if val then
                        settings.resources[capturedPt].showText = nil
                    else
                        settings.resources[capturedPt].showText = false
                    end
                end
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(cb)

            local advExpanded = AddAdvancedToggle(cb, "rbText_" .. capturedPt, rbTextAdvBtns, showTextEnabled)
            if advExpanded and showTextEnabled then
                local textFormatDrop = AceGUI:Create("Dropdown")
                textFormatDrop:SetLabel("Text Format")
                local textFormatOptions
                local textFormatOrder
                if isSegmentedResource then
                    textFormatOptions = {
                        current = "Current Value",
                        current_max = "Current / Max",
                    }
                    textFormatOrder = { "current", "current_max" }
                else
                    textFormatOptions = {
                        current = "Current Value",
                        current_max = "Current / Max",
                        percent = "Percent",
                    }
                    textFormatOrder = { "current", "current_max", "percent" }
                end
                textFormatDrop:SetList(textFormatOptions, textFormatOrder)
                local textFormatValue = resSettings.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                if isSegmentedResource then
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                    end
                else
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" and textFormatValue ~= "percent" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                    end
                end
                textFormatDrop:SetValue(textFormatValue)
                textFormatDrop:SetFullWidth(true)
                textFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    if isSegmentedResource then
                        if val == "current" or val == "current_max" then
                            settings.resources[capturedPt].textFormat = val
                        else
                            settings.resources[capturedPt].textFormat = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                        end
                    else
                        if val == "current" or val == "current_max" or val == "percent" then
                            settings.resources[capturedPt].textFormat = val
                        else
                            settings.resources[capturedPt].textFormat = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                        end
                    end
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textFormatDrop)

                local fontDrop = AceGUI:Create("Dropdown")
                fontDrop:SetLabel("Font")
                CS.SetupFontDropdown(fontDrop)
                fontDrop:SetValue(resSettings.textFont or DEFAULT_RESOURCE_TEXT_FONT_CONFIG)
                fontDrop:SetFullWidth(true)
                fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFont = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(fontDrop)

                local sizeDrop = AceGUI:Create("Slider")
                sizeDrop:SetLabel("Font Size")
                sizeDrop:SetSliderValues(6, 24, 1)
                sizeDrop:SetValue(resSettings.textFontSize or DEFAULT_RESOURCE_TEXT_SIZE_CONFIG)
                sizeDrop:SetFullWidth(true)
                sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFontSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(sizeDrop)

                local outlineDrop = AceGUI:Create("Dropdown")
                outlineDrop:SetLabel("Outline")
                outlineDrop:SetList(CS.outlineOptions)
                outlineDrop:SetValue(resSettings.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG)
                outlineDrop:SetFullWidth(true)
                outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFontOutline = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(outlineDrop)

                local textColorPicker = AceGUI:Create("ColorPicker")
                textColorPicker:SetLabel("Text Color")
                local tc = resSettings.textFontColor or DEFAULT_RESOURCE_TEXT_COLOR_CONFIG
                textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
                textColorPicker:SetHasAlpha(true)
                textColorPicker:SetFullWidth(true)
                textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    settings.resources[capturedPt].textFontColor = {r, g, b, a}
                end)
                textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    settings.resources[capturedPt].textFontColor = {r, g, b, a}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textColorPicker)

                if HIDE_AT_ZERO_ELIGIBLE[capturedPt] then
                    local hideAtZeroCb = AceGUI:Create("CheckBox")
                    hideAtZeroCb:SetLabel("Hide at 0")
                    hideAtZeroCb:SetValue(resSettings.hideTextAtZero == true)
                    hideAtZeroCb:SetFullWidth(true)
                    hideAtZeroCb:SetCallback("OnValueChanged", function(widget, event, val)
                        if not settings.resources[capturedPt] then settings.resources[capturedPt] = {} end
                        settings.resources[capturedPt].hideTextAtZero = val and true or nil
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(hideAtZeroCb)
                end
            end
        end
    end

    end

    if showColors then
    -- ============ Per-Resource Colors Section ============
    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Per-Resource Colors")
    ColorHeading(colorHeading)
    colorHeading:SetFullWidth(true)
    container:AddChild(colorHeading)

    local colorKey = "rb_colors"
    local colorCollapsed = resourceBarCollapsedSections[colorKey]

    AttachCollapseButton(colorHeading, colorCollapsed, function()
        resourceBarCollapsedSections[colorKey] = not resourceBarCollapsedSections[colorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not colorCollapsed then
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end

            if pt == 4 then
                -- Combo Points: two color pickers (normal vs at max)
                local normalColor = settings.resources[4].comboColor or DEFAULT_COMBO_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Combo Points")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[4].comboMaxColor or DEFAULT_COMBO_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Combo Points (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)

                -- Charged combo point color (Rogue only)
                local _, _, classID = UnitClass("player")
                if classID == 4 then
                    local chargedColor = settings.resources[4].comboChargedColor or DEFAULT_COMBO_CHARGED_COLOR_CONFIG
                    local cpCharged = AceGUI:Create("ColorPicker")
                    cpCharged:SetLabel("Combo Points (Charged)")
                    cpCharged:SetColor(chargedColor[1], chargedColor[2], chargedColor[3])
                    cpCharged:SetHasAlpha(false)
                    cpCharged:SetFullWidth(true)
                    cpCharged:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                        if not settings.resources[4] then settings.resources[4] = {} end
                        settings.resources[4].comboChargedColor = {r, g, b}
                    end)
                    cpCharged:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                        if not settings.resources[4] then settings.resources[4] = {} end
                        settings.resources[4].comboChargedColor = {r, g, b}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(cpCharged)
                end
            elseif pt == 5 then
                -- Runes: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[5].runeReadyColor or DEFAULT_RUNE_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Runes (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[5].runeRechargingColor or DEFAULT_RUNE_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Runes (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[5].runeMaxColor or DEFAULT_RUNE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Runes (All Ready)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 7 then
                -- Soul Shards: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[7].shardReadyColor or DEFAULT_SHARD_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Soul Shards (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[7].shardRechargingColor or DEFAULT_SHARD_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Soul Shards (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[7].shardMaxColor or DEFAULT_SHARD_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Soul Shards (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 9 then
                -- Holy Power: two color pickers (normal vs max)
                local normalColor = settings.resources[9].holyColor or DEFAULT_HOLY_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Holy Power")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[9].holyMaxColor or DEFAULT_HOLY_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Holy Power (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 12 then
                -- Chi: two color pickers (normal vs max)
                local normalColor = settings.resources[12].chiColor or DEFAULT_CHI_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Chi")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[12].chiMaxColor or DEFAULT_CHI_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Chi (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 16 then
                -- Arcane Charges: two color pickers (normal vs max)
                local normalColor = settings.resources[16].arcaneColor or DEFAULT_ARCANE_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Arcane Charges")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[16].arcaneMaxColor or DEFAULT_ARCANE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Arcane Charges (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 19 then
                -- Essence: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[19].essenceReadyColor or DEFAULT_ESSENCE_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Essence (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[19].essenceRechargingColor or DEFAULT_ESSENCE_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Essence (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[19].essenceMaxColor or DEFAULT_ESSENCE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Essence (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 100 then
                -- Maelstrom Weapon: three color pickers (base, overlay, max)
                local baseColor = settings.resources[100].mwBaseColor or DEFAULT_MW_BASE_COLOR_CONFIG
                local cpBase = AceGUI:Create("ColorPicker")
                cpBase:SetLabel("MW (Base)")
                cpBase:SetColor(baseColor[1], baseColor[2], baseColor[3])
                cpBase:SetHasAlpha(false)
                cpBase:SetFullWidth(true)
                cpBase:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwBaseColor = {r, g, b}
                end)
                cpBase:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwBaseColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpBase)

                local overlayColor = settings.resources[100].mwOverlayColor or DEFAULT_MW_OVERLAY_COLOR_CONFIG
                local cpOverlay = AceGUI:Create("ColorPicker")
                cpOverlay:SetLabel("MW (Overlay)")
                cpOverlay:SetColor(overlayColor[1], overlayColor[2], overlayColor[3])
                cpOverlay:SetHasAlpha(false)
                cpOverlay:SetFullWidth(true)
                cpOverlay:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwOverlayColor = {r, g, b}
                end)
                cpOverlay:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwOverlayColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpOverlay)

                local mwMaxColor = settings.resources[100].mwMaxColor or DEFAULT_MW_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("MW (Max)")
                cpMax:SetColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            else
                local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)

                if settings.barTexture == "blizzard_class" and ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[pt] then
                    -- Atlas-backed type; color picker not applicable
                else
                    local currentColor = settings.resources[pt].color or DEFAULT_POWER_COLORS_CONFIG[pt] or { 1, 1, 1 }

                    local cp = AceGUI:Create("ColorPicker")
                    cp:SetLabel(name)
                    cp:SetColor(currentColor[1], currentColor[2], currentColor[3])
                    cp:SetHasAlpha(false)
                    cp:SetFullWidth(true)
                    cp:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                        if not settings.resources[pt] then
                            settings.resources[pt] = {}
                        end
                        settings.resources[pt].color = {r, g, b}
                    end)
                    cp:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                        if not settings.resources[pt] then
                            settings.resources[pt] = {}
                        end
                        settings.resources[pt].color = {r, g, b}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(cp)
                end
            end

        end
    end

    -- ============ Thresholds & Ticks Section ============
    local thresholdHeading = AceGUI:Create("Heading")
    thresholdHeading:SetText("Thresholds & Ticks")
    ColorHeading(thresholdHeading)
    thresholdHeading:SetFullWidth(true)
    container:AddChild(thresholdHeading)

    local thresholdKey = "rb_thresholds_ticks"
    local thresholdCollapsed = resourceBarCollapsedSections[thresholdKey]

    local thresholdCollapseBtn = AttachCollapseButton(thresholdHeading, thresholdCollapsed, function()
        resourceBarCollapsedSections[thresholdKey] = not resourceBarCollapsedSections[thresholdKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local thresholdInfoBtn = CreateInfoButton(thresholdHeading.frame, thresholdCollapseBtn, "LEFT", "RIGHT", 4, 0, {
        "Thresholds & Ticks",
        {"Segmented resources: recolor when current value is at/above a configured threshold.", 1, 1, 1, true},
        " ",
        {"Continuous resources: draw a static marker by percent or absolute value.", 1, 1, 1, true},
    }, thresholdHeading)

    thresholdHeading.right:ClearAllPoints()
    thresholdHeading.right:SetPoint("RIGHT", thresholdHeading.frame, "RIGHT", -3, 0)
    thresholdHeading.right:SetPoint("LEFT", thresholdInfoBtn, "RIGHT", 4, 0)

    if not thresholdCollapsed then
        local rbThresholdTickAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
                local capturedPt = pt
                local res = settings.resources[capturedPt]
                local isSegmented = SEGMENTED_TYPES_CONFIG[capturedPt] == true or capturedPt == 100

                if isSegmented then
                    local thresholdAdvKey = "rbSegThreshold_" .. capturedPt
                    local thresholdEnableCb = AceGUI:Create("CheckBox")
                    thresholdEnableCb:SetLabel("Enable " .. resourceName .. " Threshold Color")
                    thresholdEnableCb:SetValue(res.segThresholdEnabled == true)
                    thresholdEnableCb:SetFullWidth(true)
                    thresholdEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        if not settings.resources[capturedPt] then settings.resources[capturedPt] = {} end
                        local wasEnabled = settings.resources[capturedPt].segThresholdEnabled == true
                        settings.resources[capturedPt].segThresholdEnabled = val and true or nil
                        if val and not wasEnabled then
                            if type(CooldownCompanion.db.profile.showAdvanced) ~= "table" then
                                CooldownCompanion.db.profile.showAdvanced = {}
                            end
                            CooldownCompanion.db.profile.showAdvanced[thresholdAdvKey] = true
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(thresholdEnableCb)

                    local thresholdAdvExpanded = AddAdvancedToggle(
                        thresholdEnableCb,
                        thresholdAdvKey,
                        rbThresholdTickAdvBtns,
                        res.segThresholdEnabled == true
                    )
                    if res.segThresholdEnabled == true and thresholdAdvExpanded then
                        local thresholdEdit = AceGUI:Create("EditBox")
                        if thresholdEdit.editbox.Instructions then thresholdEdit.editbox.Instructions:Hide() end
                        thresholdEdit:SetLabel(resourceName .. " Threshold Value (>=)")
                        thresholdEdit:SetText(tostring(GetSegmentedThresholdValueConfig(res)))
                        thresholdEdit:SetFullWidth(true)
                        thresholdEdit:DisableButton(true)
                        thresholdEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                            local parsed = tonumber(text)
                            if not parsed then
                                widget:SetText(tostring(GetSegmentedThresholdValueConfig(settings.resources[capturedPt])))
                                return
                            end
                            parsed = math.floor(parsed)
                            if parsed < 1 then
                                parsed = 1
                            elseif parsed > 99 then
                                parsed = 99
                            end
                            settings.resources[capturedPt].segThresholdValue = parsed
                            widget:SetText(tostring(parsed))
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(thresholdEdit)

                        local thresholdColor = GetSafeRGBConfig(res.segThresholdColor, DEFAULT_SEG_THRESHOLD_COLOR_CONFIG)
                        local thresholdColorPicker = AceGUI:Create("ColorPicker")
                        thresholdColorPicker:SetLabel(resourceName .. " Threshold Color")
                        thresholdColorPicker:SetColor(thresholdColor[1], thresholdColor[2], thresholdColor[3])
                        thresholdColorPicker:SetHasAlpha(false)
                        thresholdColorPicker:SetFullWidth(true)
                        thresholdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                            settings.resources[capturedPt].segThresholdColor = { r, g, b }
                        end)
                        thresholdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                            settings.resources[capturedPt].segThresholdColor = { r, g, b }
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(thresholdColorPicker)
                    end
                else
                    local tickAdvKey = "rbTickMarker_" .. capturedPt
                    local tickEnableCb = AceGUI:Create("CheckBox")
                    tickEnableCb:SetLabel("Enable " .. resourceName .. " Tick Marker")
                    tickEnableCb:SetValue(res.continuousTickEnabled == true)
                    tickEnableCb:SetFullWidth(true)
                    tickEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        if not settings.resources[capturedPt] then settings.resources[capturedPt] = {} end
                        local wasEnabled = settings.resources[capturedPt].continuousTickEnabled == true
                        settings.resources[capturedPt].continuousTickEnabled = val and true or nil
                        if val and not wasEnabled then
                            if type(CooldownCompanion.db.profile.showAdvanced) ~= "table" then
                                CooldownCompanion.db.profile.showAdvanced = {}
                            end
                            CooldownCompanion.db.profile.showAdvanced[tickAdvKey] = true
                        end
                        CooldownCompanion:ApplyResourceBars()
                        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                    end)
                    container:AddChild(tickEnableCb)

                    local tickAdvExpanded = AddAdvancedToggle(
                        tickEnableCb,
                        tickAdvKey,
                        rbThresholdTickAdvBtns,
                        res.continuousTickEnabled == true
                    )
                    if res.continuousTickEnabled == true and tickAdvExpanded then
                        local tickMode = GetContinuousTickModeConfig(res)
                        local modeDrop = AceGUI:Create("Dropdown")
                        modeDrop:SetLabel("Tick Mode")
                        modeDrop:SetList({
                            percent = "Percent",
                            absolute = "Absolute Value",
                        }, { "percent", "absolute" })
                        modeDrop:SetValue(tickMode)
                        modeDrop:SetFullWidth(true)
                        modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            if val ~= "percent" and val ~= "absolute" then
                                val = DEFAULT_CONTINUOUS_TICK_MODE_CONFIG
                            end
                            settings.resources[capturedPt].continuousTickMode = val
                            CooldownCompanion:ApplyResourceBars()
                            C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                        end)
                        container:AddChild(modeDrop)

                        if tickMode == "percent" then
                            local percentSlider = AceGUI:Create("Slider")
                            percentSlider:SetLabel(resourceName .. " Tick Percent")
                            percentSlider:SetSliderValues(0, 100, 1)
                            percentSlider:SetValue(GetContinuousTickPercentConfig(res))
                            percentSlider:SetIsPercent(false)
                            percentSlider:SetFullWidth(true)
                            percentSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                settings.resources[capturedPt].continuousTickPercent = val
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(percentSlider)
                        else
                            local absoluteEdit = AceGUI:Create("EditBox")
                            if absoluteEdit.editbox.Instructions then absoluteEdit.editbox.Instructions:Hide() end
                            absoluteEdit:SetLabel(resourceName .. " Tick Absolute Value")
                            absoluteEdit:SetText(tostring(GetContinuousTickAbsoluteConfig(res)))
                            absoluteEdit:SetFullWidth(true)
                            absoluteEdit:DisableButton(true)
                            absoluteEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                                local parsed = tonumber(text)
                                if not parsed then
                                    widget:SetText(tostring(GetContinuousTickAbsoluteConfig(settings.resources[capturedPt])))
                                    return
                                end
                                if parsed < 0 then
                                    parsed = 0
                                end
                                settings.resources[capturedPt].continuousTickAbsolute = parsed
                                widget:SetText(tostring(parsed))
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(absoluteEdit)
                        end

                        local tickColor = GetSafeRGBAConfig(res.continuousTickColor, DEFAULT_CONTINUOUS_TICK_COLOR_CONFIG)
                        local tickColorPicker = AceGUI:Create("ColorPicker")
                        tickColorPicker:SetLabel(resourceName .. " Tick Color")
                        tickColorPicker:SetColor(tickColor[1], tickColor[2], tickColor[3], tickColor[4] ~= nil and tickColor[4] or 1)
                        tickColorPicker:SetHasAlpha(true)
                        tickColorPicker:SetFullWidth(true)
                        tickColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                            settings.resources[capturedPt].continuousTickColor = { r, g, b, a }
                        end)
                        tickColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                            settings.resources[capturedPt].continuousTickColor = { r, g, b, a }
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(tickColorPicker)

                        local tickWidthSlider = AceGUI:Create("Slider")
                        tickWidthSlider:SetLabel(resourceName .. " Tick Width")
                        tickWidthSlider:SetSliderValues(1, 10, 1)
                        tickWidthSlider:SetValue(tonumber(res.continuousTickWidth) or DEFAULT_CONTINUOUS_TICK_WIDTH_CONFIG)
                        tickWidthSlider:SetFullWidth(true)
                        tickWidthSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            settings.resources[capturedPt].continuousTickWidth = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(tickWidthSlider)
                    end
                end
            end
        end
    end

    end

    if showAuraOverlays then
        BuildResourceAuraOverlaySection(container, settings)
    end

end

local function BuildResourceBarBarTextStylingPanel(container)
    BuildResourceBarStylingPanel(container, "bar_text")
end

local function BuildResourceBarColorsStylingPanel(container)
    BuildResourceBarStylingPanel(container, "colors")
end

local function BuildResourceBarAuraOverlaysStylingPanel(container)
    BuildResourceBarStylingPanel(container, "aura_overlays")
end

------------------------------------------------------------------------
-- Custom Aura Bar Panel (col2 takeover when resource bar panel active)
------------------------------------------------------------------------

local function ClampCustomAuraIndependentDimension(value, fallback)
    local dimension = tonumber(value) or tonumber(fallback) or 120
    if dimension < 4 then
        dimension = 4
    elseif dimension > 1200 then
        dimension = 1200
    end
    return dimension
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

local function GetResolvedCustomAuraIndependentOrientation(cab, settings)
    local orientation = NormalizeCustomAuraIndependentOrientation(cab and cab.independentOrientation)
    if orientation then
        return orientation
    end
    return IsResourceBarVerticalConfig(settings) and "vertical" or "horizontal"
end

local function EnsureCustomAuraIndependentConfig(cab, settings)
    if type(cab) ~= "table" then return end

    if cab.independentAnchorEnabled ~= nil then
        cab.independentAnchorEnabled = IsTruthyConfigFlag(cab.independentAnchorEnabled) and true or nil
    end

    if cab.independentAnchorTargetMode ~= "group" and cab.independentAnchorTargetMode ~= "frame" then
        cab.independentAnchorTargetMode = "group"
    end
    if type(cab.independentLocked) ~= "boolean" then
        cab.independentLocked = IsTruthyConfigFlag(cab.independentLocked) and true or false
    end

    cab.independentOrientation = NormalizeCustomAuraIndependentOrientation(cab.independentOrientation)
    cab.independentVerticalFillDirection = NormalizeCustomAuraIndependentVerticalFillDirection(cab.independentVerticalFillDirection)

    if type(cab.independentAnchor) ~= "table" then
        cab.independentAnchor = {}
    end
    cab.independentAnchor.point = cab.independentAnchor.point or "CENTER"
    cab.independentAnchor.relativePoint = cab.independentAnchor.relativePoint or "CENTER"
    cab.independentAnchor.x = tonumber(cab.independentAnchor.x) or 0
    cab.independentAnchor.y = tonumber(cab.independentAnchor.y) or 0

    if type(cab.independentSize) ~= "table" then
        cab.independentSize = {}
    end
    cab.independentSize.width = ClampCustomAuraIndependentDimension(cab.independentSize.width, 120)
    cab.independentSize.height = ClampCustomAuraIndependentDimension(cab.independentSize.height, settings and (settings.barHeight or settings.barWidth or 12) or 12)
end

local function BuildCustomAuraBarAnchorSettings(container, customBars, settings, capturedIdx)
    local cab = customBars[capturedIdx]
    if not cab then return end
    EnsureCustomAuraIndependentConfig(cab, settings)

    local unlockCb = AceGUI:Create("CheckBox")
    unlockCb:SetLabel("Unlock Placement")
    unlockCb:SetValue(cab.independentLocked ~= true)
    unlockCb:SetFullWidth(true)
    unlockCb:SetCallback("OnValueChanged", function(widget, event, val)
        local unlocked = IsTruthyConfigFlag(val)
        customBars[capturedIdx].independentLocked = not unlocked
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(unlockCb)

    local modeDrop = AceGUI:Create("Dropdown")
    modeDrop:SetLabel("Anchor Target")
    modeDrop:SetList({
        group = "Group",
        frame = "Frame Name / Pick",
    }, { "group", "frame" })
    modeDrop:SetValue(cab.independentAnchorTargetMode or "group")
    modeDrop:SetFullWidth(true)
    modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentAnchorTargetMode = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(modeDrop)

    if (cab.independentAnchorTargetMode or "group") == "group" then
        local groupDrop = AceGUI:Create("Dropdown")
        groupDrop:SetLabel("Anchor to Panel")
        CooldownCompanion:PopulateAnchorDropdown(groupDrop)
        groupDrop:SetValue(cab.independentAnchorGroupId and tostring(cab.independentAnchorGroupId) or "")
        groupDrop:SetFullWidth(true)
        groupDrop:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[capturedIdx].independentAnchorGroupId = val ~= "" and tonumber(val) or nil
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(groupDrop)
    else
        local frameRow = AceGUI:Create("SimpleGroup")
        frameRow:SetLayout("Flow")
        frameRow:SetFullWidth(true)

        local frameEdit = AceGUI:Create("EditBox")
        if frameEdit.editbox.Instructions then frameEdit.editbox.Instructions:Hide() end
        frameEdit:SetLabel("Anchor to Frame")
        frameEdit:SetText(cab.independentAnchorFrameName or "")
        frameEdit:SetRelativeWidth(0.68)
        frameEdit:SetCallback("OnEnterPressed", function(widget, event, text)
            customBars[capturedIdx].independentAnchorFrameName = text or ""
            CooldownCompanion:ApplyResourceBars()
        end)
        frameRow:AddChild(frameEdit)

        local pickBtn = AceGUI:Create("Button")
        pickBtn:SetText("Pick")
        pickBtn:SetRelativeWidth(0.24)
        pickBtn:SetCallback("OnClick", function()
            CS.StartPickFrame(function(name)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if name then
                    customBars[capturedIdx].independentAnchorFrameName = name
                    CooldownCompanion:ApplyResourceBars()
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
        end)
        frameRow:AddChild(pickBtn)

        container:AddChild(frameRow)
    end

    local pointValues = {}
    for _, pt in ipairs(CS.anchorPoints) do
        pointValues[pt] = CS.anchorPointLabels[pt]
    end

    local anchorPointDrop = AceGUI:Create("Dropdown")
    anchorPointDrop:SetLabel("Anchor Point")
    anchorPointDrop:SetList(pointValues, CS.anchorPoints)
    anchorPointDrop:SetValue(cab.independentAnchor.point or "CENTER")
    anchorPointDrop:SetFullWidth(true)
    anchorPointDrop:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentAnchor.point = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(anchorPointDrop)

    local relativePointDrop = AceGUI:Create("Dropdown")
    relativePointDrop:SetLabel("Relative Point")
    relativePointDrop:SetList(pointValues, CS.anchorPoints)
    relativePointDrop:SetValue(cab.independentAnchor.relativePoint or "CENTER")
    relativePointDrop:SetFullWidth(true)
    relativePointDrop:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentAnchor.relativePoint = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(relativePointDrop)

    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 0.1)
    xSlider:SetValue(cab.independentAnchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentAnchor.x = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(xSlider)

    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 0.1)
    ySlider:SetValue(cab.independentAnchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentAnchor.y = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(ySlider)

    local widthSlider = AceGUI:Create("Slider")
    widthSlider:SetLabel("Width")
    widthSlider:SetSliderValues(4, 1200, 0.1)
    widthSlider:SetValue(cab.independentSize.width or 120)
    widthSlider:SetFullWidth(true)
    widthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentSize.width = ClampCustomAuraIndependentDimension(val, 120)
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(widthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Height")
    heightSlider:SetSliderValues(4, 1200, 0.1)
    heightSlider:SetValue(cab.independentSize.height or 12)
    heightSlider:SetFullWidth(true)
    heightSlider:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].independentSize.height = ClampCustomAuraIndependentDimension(val, 12)
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(heightSlider)

    local resolvedOrientation = GetResolvedCustomAuraIndependentOrientation(cab, settings)

    local orientationDrop = AceGUI:Create("Dropdown")
    orientationDrop:SetLabel("Orientation")
    orientationDrop:SetList({
        horizontal = "Horizontal",
        vertical = "Vertical",
    }, { "horizontal", "vertical" })
    orientationDrop:SetValue(resolvedOrientation)
    orientationDrop:SetFullWidth(true)
    orientationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if val ~= "horizontal" and val ~= "vertical" then
            return
        end
        customBars[capturedIdx].independentOrientation = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(orientationDrop)

    if resolvedOrientation == "vertical" then
        local fillDrop = AceGUI:Create("Dropdown")
        fillDrop:SetLabel("Vertical Fill Direction")
        fillDrop:SetList({
            inherit = "Inherit Global",
            bottom_to_top = "Bottom to Top",
            top_to_bottom = "Top to Bottom",
        }, { "inherit", "bottom_to_top", "top_to_bottom" })
        fillDrop:SetValue(cab.independentVerticalFillDirection or "inherit")
        fillDrop:SetFullWidth(true)
        fillDrop:SetCallback("OnValueChanged", function(widget, event, val)
            customBars[capturedIdx].independentVerticalFillDirection = NormalizeCustomAuraIndependentVerticalFillDirection(val)
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(fillDrop)
    end

end

local function BuildCustomAuraBarPanel(container, slotIdx)
    auraBarAutocompleteCache = nil
    local settings = CooldownCompanion:GetResourceBarSettings()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings)
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local maxSlots = ST.MAX_CUSTOM_AURA_BARS or 3
    local rbCabTextAdvBtns = {}
    local selectedSlot = tonumber(slotIdx) or 1

    if selectedSlot < 1 then
        selectedSlot = 1
    elseif selectedSlot > maxSlots then
        selectedSlot = maxSlots
    end

    if not customBars[selectedSlot] then
        customBars[selectedSlot] = { enabled = false }
    end
    local cab = customBars[selectedSlot]
    local capturedIdx = selectedSlot
    EnsureCustomAuraIndependentConfig(cab, settings)

    local function ClassColorText(text)
        local safeText = tostring(text or "")
        local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
        if classColor then
            if classColor.WrapTextInColorCode then
                return classColor:WrapTextInColorCode(safeText)
            end
            local r = math.floor(((classColor.r or 1) * 255) + 0.5)
            local g = math.floor(((classColor.g or 1) * 255) + 0.5)
            local b = math.floor(((classColor.b or 1) * 255) + 0.5)
            return string.format("|cff%02x%02x%02x%s|r", r, g, b, safeText)
        end
        return safeText
    end

    -- Enable checkbox
    local enableCab = AceGUI:Create("CheckBox")
    enableCab:SetLabel("Enable")
    enableCab:SetValue(cab.enabled == true)
    enableCab:SetFullWidth(true)
    enableCab:SetCallback("OnValueChanged", function(widget, event, val)
        customBars[capturedIdx].enabled = val
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCab)

    if cab.enabled then
        local independentCb = AceGUI:Create("CheckBox")
        independentCb:SetLabel("Independent Anchor & Size")
        independentCb:SetValue(IsTruthyConfigFlag(cab.independentAnchorEnabled))
        independentCb:SetFullWidth(true)
        independentCb:SetCallback("OnValueChanged", function(widget, event, val)
            local bars = CooldownCompanion:GetSpecCustomAuraBars()
            if not bars[capturedIdx] then
                bars[capturedIdx] = { enabled = false }
            end

            local enabled = IsTruthyConfigFlag(val)
            local wasEnabled = IsTruthyConfigFlag(bars[capturedIdx].independentAnchorEnabled)
            bars[capturedIdx].independentAnchorEnabled = enabled and true or nil
            if enabled then
                EnsureCustomAuraIndependentConfig(bars[capturedIdx], settings)
                bars[capturedIdx].independentLocked = false
                if CS.customAuraBarSubTabs then
                    local prior = CS.customAuraBarSubTabs[capturedIdx]
                    if prior ~= "settings" and prior ~= "anchor" then
                        CS.customAuraBarSubTabs[capturedIdx] = "settings"
                    end
                end
                if not wasEnabled and CooldownCompanion.InitializeCustomAuraIndependentAnchor then
                    CooldownCompanion:InitializeCustomAuraIndependentAnchor(capturedIdx)
                end
            elseif CS.customAuraBarSubTabs then
                CS.customAuraBarSubTabs[capturedIdx] = nil
            end

            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(independentCb)
    end

    local independentSubTab = "settings"
    if cab.enabled and IsTruthyConfigFlag(cab.independentAnchorEnabled) then
        independentSubTab = CS.customAuraBarSubTabs and CS.customAuraBarSubTabs[capturedIdx] or "settings"
        if independentSubTab ~= "settings" and independentSubTab ~= "anchor" then
            independentSubTab = "settings"
        end
        if CS.customAuraBarSubTabs then
            CS.customAuraBarSubTabs[capturedIdx] = independentSubTab
        end

        local subTabRow = AceGUI:Create("SimpleGroup")
        subTabRow:SetLayout("Flow")
        subTabRow:SetFullWidth(true)

        local settingsBtn = AceGUI:Create("Button")
        settingsBtn:SetText(independentSubTab == "settings" and ClassColorText("[Settings]") or "Settings")
        settingsBtn:SetRelativeWidth(0.49)
        settingsBtn:SetCallback("OnClick", function()
            local currentTab = CS.customAuraBarSubTabs and CS.customAuraBarSubTabs[capturedIdx] or "settings"
            if currentTab == "settings" then return end
            if CS.customAuraBarSubTabs then
                CS.customAuraBarSubTabs[capturedIdx] = "settings"
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        subTabRow:AddChild(settingsBtn)

        local anchorBtn = AceGUI:Create("Button")
        anchorBtn:SetText(independentSubTab == "anchor" and ClassColorText("[Anchor Settings]") or "Anchor Settings")
        anchorBtn:SetRelativeWidth(0.49)
        anchorBtn:SetCallback("OnClick", function()
            local currentTab = CS.customAuraBarSubTabs and CS.customAuraBarSubTabs[capturedIdx] or "settings"
            if currentTab == "anchor" then return end
            if CS.customAuraBarSubTabs then
                CS.customAuraBarSubTabs[capturedIdx] = "anchor"
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        subTabRow:AddChild(anchorBtn)

        container:AddChild(subTabRow)

        local subTabDivider = AceGUI:Create("Heading")
        subTabDivider:SetFullWidth(true)
        container:AddChild(subTabDivider)
    elseif cab.enabled and CS.customAuraBarSubTabs then
        CS.customAuraBarSubTabs[capturedIdx] = nil
    end

    if cab.enabled and independentSubTab ~= "anchor" then

            local trackedAuraName = cab.spellID and C_Spell.GetSpellName(cab.spellID)
            local trackedAuraIcon = cab.spellID and C_Spell.GetSpellTexture(cab.spellID)
            local trackedAuraLabel = AceGUI:Create("Label")
            local trackedAuraText
            if trackedAuraName then
                local iconPrefix = trackedAuraIcon and ("|T" .. trackedAuraIcon .. ":16:16:0:0|t ") or ""
                trackedAuraText = "|cffffcc00Tracking Aura:|r " .. iconPrefix
                    .. "|cffffffff" .. trackedAuraName .. "|r"
            elseif cab.spellID then
                trackedAuraText = "|cffffcc00Tracking Aura:|r |cffffffffSpell ID "
                    .. tostring(cab.spellID) .. "|r"
            else
                trackedAuraText = "|cffffcc00Tracking Aura:|r |cff999999None selected|r"
            end
            trackedAuraLabel:SetText(trackedAuraText)
            trackedAuraLabel:SetFullWidth(true)
            container:AddChild(trackedAuraLabel)

            -- Spell ID edit box with autocomplete
            local spellEdit = AceGUI:Create("EditBox")
            if spellEdit.editbox.Instructions then spellEdit.editbox.Instructions:Hide() end
            spellEdit:SetLabel("Spell ID or Name")
            spellEdit:SetText(cab.spellID and tostring(cab.spellID) or "")
            spellEdit:SetFullWidth(true)
            spellEdit:DisableButton(true)

            -- Autocomplete: onSelect closure for this slot
            local function onAuraBarSelect(entry)
                CS.HideAutocomplete()
                local bars = CooldownCompanion:GetSpecCustomAuraBars()
                bars[capturedIdx].spellID = entry.id
                bars[capturedIdx].label = C_Spell.GetSpellName(entry.id) or ""
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end

            spellEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                if CS.ConsumeAutocompleteEnter() then return end
                CS.HideAutocomplete()
                text = text:gsub("%s", "")
                local id = tonumber(text)
                local bars = CooldownCompanion:GetSpecCustomAuraBars()
                bars[capturedIdx].spellID = id
                if id then
                    bars[capturedIdx].label = C_Spell.GetSpellName(id) or ""
                else
                    bars[capturedIdx].label = ""
                end
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            spellEdit:SetCallback("OnTextChanged", function(widget, event, text)
                if text and #text >= 1 then
                    local cache = auraBarAutocompleteCache or BuildAuraBarAutocompleteCache()
                    local results = CS.SearchAutocompleteInCache(text, cache)
                    CS.ShowAutocompleteResults(results, widget, onAuraBarSelect)
                else
                    CS.HideAutocomplete()
                end
            end)

            CS.SetupAutocompleteKeyHandler(spellEdit)

            container:AddChild(spellEdit)

            AddCdmAuraReadinessWarning(container, cab.spellID)

            -- Tracking Mode dropdown
            local trackDrop = AceGUI:Create("Dropdown")
            trackDrop:SetLabel("Tracking Mode")
            trackDrop:SetList({
                stacks = "Stack Count",
                active = "Active (On/Off)",
            }, { "stacks", "active" })
            trackDrop:SetValue(cab.trackingMode or "stacks")
            trackDrop:SetFullWidth(true)
            trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].trackingMode = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(trackDrop)

            -- Max Stacks editbox (hidden in "active" tracking mode)
            if (cab.trackingMode or "stacks") ~= "active" then
            local maxEdit = AceGUI:Create("EditBox")
            if maxEdit.editbox.Instructions then maxEdit.editbox.Instructions:Hide() end
            maxEdit:SetLabel("Max Stacks")
            maxEdit:SetText(tostring(cab.maxStacks or 1))
            maxEdit:SetFullWidth(true)
            maxEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                local val = tonumber(text)
                if val and val >= 1 and val <= 99 then
                    customBars[capturedIdx].maxStacks = val
                end
                widget:SetText(tostring(customBars[capturedIdx].maxStacks or 1))
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(maxEdit)
            end

            -- Display Mode dropdown (hidden in "active" tracking mode)
            if (cab.trackingMode or "stacks") ~= "active" then
            local modeDrop = AceGUI:Create("Dropdown")
            modeDrop:SetLabel("Display Mode")
            modeDrop:SetList({
                continuous = "Continuous",
                segmented = "Segmented",
                overlay = "Overlay",
            }, { "continuous", "segmented", "overlay" })
            modeDrop:SetValue(cab.displayMode or "segmented")
            modeDrop:SetFullWidth(true)
            modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].displayMode = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(modeDrop)
            end

            -- Per-slot bar thickness override
            if settings.customBarHeights then
                local cabHeightSlider = AceGUI:Create("Slider")
                cabHeightSlider:SetLabel(thicknessLabel)
                cabHeightSlider:SetSliderValues(4, 40, 0.1)
                if thicknessField == "barWidth" then
                    cabHeightSlider:SetValue(cab.barWidth or cab.barHeight or settings.barWidth or settings.barHeight or 12)
                else
                    cabHeightSlider:SetValue(cab.barHeight or cab.barWidth or settings.barHeight or settings.barWidth or 12)
                end
                cabHeightSlider:SetFullWidth(true)
                local cabIdx = capturedIdx
                cabHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx][thicknessField] = val
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                end)
                container:AddChild(cabHeightSlider)
            end

            -- ---- Colors section (only when has spell ID) ----
            if cab.spellID then
                local colorHeading = AceGUI:Create("Heading")
                colorHeading:SetText("Colors")
                ColorHeading(colorHeading)
                colorHeading:SetFullWidth(true)
                container:AddChild(colorHeading)

                -- Bar Color (all modes)
                local barColor = cab.barColor or {0.5, 0.5, 1}
                local cpBar = AceGUI:Create("ColorPicker")
                cpBar:SetLabel("Bar Color")
                cpBar:SetColor(barColor[1], barColor[2], barColor[3])
                cpBar:SetHasAlpha(false)
                cpBar:SetFullWidth(true)
                local cabIdx = capturedIdx
                cpBar:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    customBars[cabIdx].barColor = {r, g, b}
                    CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx])
                end)
                cpBar:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    customBars[cabIdx].barColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpBar)

                local isActiveTracking = (cab.trackingMode or "stacks") == "active"
                if not isActiveTracking then
                    local thresholdCb = AceGUI:Create("CheckBox")
                    thresholdCb:SetLabel("Enable Max Stack Color")
                    thresholdCb:SetValue(cab.thresholdColorEnabled == true)
                    thresholdCb:SetFullWidth(true)
                    thresholdCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].thresholdColorEnabled = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(thresholdCb)

                    if cab.thresholdColorEnabled == true then
                        local maxThresholdColor = cab.thresholdMaxColor or DEFAULT_CUSTOM_AURA_MAX_COLOR_CONFIG
                        local cpThreshold = AceGUI:Create("ColorPicker")
                        cpThreshold:SetLabel("Max Stack Color")
                        cpThreshold:SetColor(maxThresholdColor[1], maxThresholdColor[2], maxThresholdColor[3])
                        cpThreshold:SetHasAlpha(false)
                        cpThreshold:SetFullWidth(true)
                        cpThreshold:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                            customBars[cabIdx].thresholdMaxColor = {r, g, b}
                            CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx])
                        end)
                        cpThreshold:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                            customBars[cabIdx].thresholdMaxColor = {r, g, b}
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(cpThreshold)
                    end
                end

                -- Max Stacks Glow (independent of threshold color)
                if not isActiveTracking then
                    local glowCb = AceGUI:Create("CheckBox")
                    glowCb:SetLabel("Max Stack Indicator")
                    glowCb:SetValue(cab.maxStacksGlowEnabled == true)
                    glowCb:SetFullWidth(true)
                    glowCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].maxStacksGlowEnabled = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(glowCb)

                    local glowAdvExpanded, glowAdvBtn = AddAdvancedToggle(glowCb, "maxStacksIndicator", tabInfoButtons, cab.maxStacksGlowEnabled == true)

                    CreateInfoButton(glowCb.frame, glowAdvBtn, "LEFT", "RIGHT", 4, 0, {
                        "Max Stack Indicator",
                        {"Due to combat restrictions, individual bar segments cannot be highlighted independently.", 1, 1, 1, true},
                        " ",
                        {"The indicator covers the entire resource bar and appears automatically when your buff reaches its maximum stack count.", 1, 1, 1, true},
                        " ",
                        {"The Pulsing Overlay style is only available for continuous display mode.", 1, 1, 1, true},
                    }, glowCb)

                    if glowAdvExpanded and cab.maxStacksGlowEnabled then
                        -- Preview (ephemeral, not saved)
                        local previewCb = AceGUI:Create("CheckBox")
                        previewCb:SetLabel("Preview Indicator")
                        previewCb:SetValue(CooldownCompanion:IsResourceBarPreviewActive())
                        previewCb:SetFullWidth(true)
                        previewCb:SetCallback("OnValueChanged", function(widget, event, val)
                            if val then
                                CooldownCompanion:StartResourceBarPreview()
                            else
                                CooldownCompanion:StopResourceBarPreview()
                            end
                        end)
                        container:AddChild(previewCb)

                        -- Pulsing Overlay only available for continuous display
                        local isContinuousDisplay = (cab.trackingMode == "active") or (cab.displayMode == "continuous")
                        local currentStyle = cab.maxStacksGlowStyle or "solidBorder"
                        if currentStyle == "pulsingOverlay" and not isContinuousDisplay then
                            currentStyle = "solidBorder"
                            customBars[cabIdx].maxStacksGlowStyle = "solidBorder"
                        end

                        -- Style dropdown
                        local styleList, styleOrder
                        if isContinuousDisplay then
                            styleList = {
                                solidBorder = "Solid Border",
                                pulsingBorder = "Pulsing Border",
                                pulsingOverlay = "Pulsing Overlay",
                            }
                            styleOrder = { "solidBorder", "pulsingBorder", "pulsingOverlay" }
                        else
                            styleList = {
                                solidBorder = "Solid Border",
                                pulsingBorder = "Pulsing Border",
                            }
                            styleOrder = { "solidBorder", "pulsingBorder" }
                        end
                        local styleDrop = AceGUI:Create("Dropdown")
                        styleDrop:SetLabel("Indicator Style")
                        styleDrop:SetList(styleList, styleOrder)
                        styleDrop:SetValue(currentStyle)
                        styleDrop:SetFullWidth(true)
                        styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].maxStacksGlowStyle = val
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        container:AddChild(styleDrop)

                        -- Color picker
                        local glowColor = cab.maxStacksGlowColor or {1, 0.84, 0, 0.9}
                        local cpGlow = AceGUI:Create("ColorPicker")
                        cpGlow:SetLabel("Indicator Color")
                        cpGlow:SetColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 0.9)
                        cpGlow:SetHasAlpha(true)
                        cpGlow:SetFullWidth(true)
                        cpGlow:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                            customBars[cabIdx].maxStacksGlowColor = {r, g, b, a}
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        cpGlow:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                            customBars[cabIdx].maxStacksGlowColor = {r, g, b, a}
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(cpGlow)

                        -- Border size slider (border styles only — overlay has no size param)
                        if currentStyle ~= "pulsingOverlay" then
                            local sizeSlider = AceGUI:Create("Slider")
                            sizeSlider:SetLabel("Border Size")
                            sizeSlider:SetSliderValues(1, 8, 1)
                            sizeSlider:SetValue(cab.maxStacksGlowSize or 2)
                            sizeSlider:SetFullWidth(true)
                            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                customBars[cabIdx].maxStacksGlowSize = val
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(sizeSlider)
                        end

                        -- Pulse speed slider (pulsing styles only)
                        if currentStyle == "pulsingBorder" or currentStyle == "pulsingOverlay" then
                            local speedSlider = AceGUI:Create("Slider")
                            speedSlider:SetLabel("Pulse Duration")
                            speedSlider:SetSliderValues(0.1, 2.0, 0.1)
                            speedSlider:SetValue(cab.maxStacksGlowSpeed or 0.5)
                            speedSlider:SetFullWidth(true)
                            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                customBars[cabIdx].maxStacksGlowSpeed = val
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(speedSlider)
                        end
                    end -- glowAdvExpanded
                end

                -- Overlay Color (overlay mode only)
                if cab.displayMode == "overlay" and (cab.trackingMode or "stacks") ~= "active" then
                    local overlayColor = cab.overlayColor or {1, 0.84, 0}
                    local cpOverlay = AceGUI:Create("ColorPicker")
                    cpOverlay:SetLabel("Overlay Color")
                    cpOverlay:SetColor(overlayColor[1], overlayColor[2], overlayColor[3])
                    cpOverlay:SetHasAlpha(false)
                    cpOverlay:SetFullWidth(true)
                    cpOverlay:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                        customBars[cabIdx].overlayColor = {r, g, b}
                        CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx])
                    end)
                    cpOverlay:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                        customBars[cabIdx].overlayColor = {r, g, b}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(cpOverlay)

                    -- Overlay Color tooltip (?) — use SetDescription for AceGUI-safe approach
                    cpOverlay:SetCallback("OnEnter", function(widget)
                        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Overlay Color")
                        GameTooltip:AddLine("Number of bar segments equals half the max stacks. Overlay color activates once base segments are full.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    cpOverlay:SetCallback("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                -- ---- Text / Duration controls ----
                local isActive = (cab.trackingMode or "stacks") == "active"
                local isContinuous = isActive or (cab.displayMode == "continuous")

                if isContinuous then
                    -- Show Duration Text
                    local durationTextCb = AceGUI:Create("CheckBox")
                    durationTextCb:SetLabel("Show Duration Text")
                    durationTextCb:SetValue(cab.showDurationText == true)
                    durationTextCb:SetFullWidth(true)
                    durationTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showDurationText = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(durationTextCb)

                    -- Show Stack Text
                    local stackVal = cab.showStackText
                    if stackVal == nil and not isActive then
                        stackVal = cab.showText  -- backwards compat
                    end

                    local stackTextCb = AceGUI:Create("CheckBox")
                    stackTextCb:SetLabel("Show Stack Text")
                    stackTextCb:SetValue(stackVal == true)
                    stackTextCb:SetFullWidth(true)
                    stackTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showStackText = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(stackTextCb)

                    local showDuration = cab.showDurationText == true
                    local showStack = (stackVal == true)
                    local durationAdvExpanded = AddAdvancedToggle(durationTextCb, "rbCabDurationText_" .. capturedIdx, rbCabTextAdvBtns, showDuration)
                    if durationAdvExpanded and showDuration then
                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Duration Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT_CONFIG)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Duration Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.durationTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE_CONFIG)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Duration Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        local textColorPicker = AceGUI:Create("ColorPicker")
                        textColorPicker:SetLabel("Duration Text Color")
                        local tc = cab.durationTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR_CONFIG
                        textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
                        textColorPicker:SetHasAlpha(true)
                        textColorPicker:SetFullWidth(true)
                        textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                            customBars[cabIdx].durationTextFontColor = {r, g, b, a}
                        end)
                        textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                            customBars[cabIdx].durationTextFontColor = {r, g, b, a}
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(textColorPicker)

                        local decimalCheck = AceGUI:Create("CheckBox")
                        decimalCheck:SetLabel("Show Decimal Point")
                        decimalCheck:SetValue(cab.decimalTimers or false)
                        decimalCheck:SetFullWidth(true)
                        decimalCheck:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].decimalTimers = val or nil
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(decimalCheck)

                        CreateInfoButton(decimalCheck.frame, decimalCheck.checkbg, "LEFT", "RIGHT", decimalCheck.text:GetStringWidth() + 4, 0, {
                            "Show Decimal Point",
                            {"Shows one decimal place on duration text", 1, 1, 1, true},
                            {"(e.g. \"4.5\" instead of \"5\").", 1, 1, 1, true},
                        }, decimalCheck)
                    end

                    local stackAdvExpanded = AddAdvancedToggle(stackTextCb, "rbCabStackText_" .. capturedIdx, rbCabTextAdvBtns, showStack)
                    if stackAdvExpanded and showStack then
                        if not isActive then
                            local stackTextFormatDrop = AceGUI:Create("Dropdown")
                            stackTextFormatDrop:SetLabel("Text Format")
                            local stackTextFormatOptions = {
                                current = "Current Value",
                                current_max = "Current / Max",
                            }
                            local stackTextFormatOrder = { "current", "current_max" }
                            stackTextFormatDrop:SetList(stackTextFormatOptions, stackTextFormatOrder)
                            local stackTextFormatValue = cab.stackTextFormat or DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT_CONFIG
                            if stackTextFormatValue ~= "current" and stackTextFormatValue ~= "current_max" then
                                stackTextFormatValue = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT_CONFIG
                            end
                            stackTextFormatDrop:SetValue(stackTextFormatValue)
                            stackTextFormatDrop:SetFullWidth(true)
                            stackTextFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                                if val == "current" or val == "current_max" then
                                    customBars[cabIdx].stackTextFormat = val
                                else
                                    customBars[cabIdx].stackTextFormat = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT_CONFIG
                                end
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(stackTextFormatDrop)
                        end

                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Stack Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT_CONFIG)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Stack Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.stackTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE_CONFIG)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Stack Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        local textColorPicker = AceGUI:Create("ColorPicker")
                        textColorPicker:SetLabel("Stack Text Color")
                        local tc = cab.stackTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR_CONFIG
                        textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
                        textColorPicker:SetHasAlpha(true)
                        textColorPicker:SetFullWidth(true)
                        textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                            customBars[cabIdx].stackTextFontColor = {r, g, b, a}
                        end)
                        textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                            customBars[cabIdx].stackTextFontColor = {r, g, b, a}
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(textColorPicker)
                    end
                end

                -- Hide When Inactive
                local hideCb = AceGUI:Create("CheckBox")
                hideCb:SetLabel("Hide When Inactive")
                hideCb:SetValue(cab.hideWhenInactive == true)
                hideCb:SetFullWidth(true)
                hideCb:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].hideWhenInactive = val or nil
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(hideCb)

                -- ---- Talent Conditions section ----
                local talentHeading = AceGUI:Create("Heading")
                talentHeading:SetText("Talent Conditions")
                ColorHeading(talentHeading)
                talentHeading:SetFullWidth(true)
                container:AddChild(talentHeading)

                local talentKey = "cab_talent_" .. capturedIdx
                local talentCollapsed = resourceBarCollapsedSections[talentKey]

                local talentCollapseBtn = AttachCollapseButton(talentHeading, talentCollapsed, function()
                    resourceBarCollapsedSections[talentKey] = not resourceBarCollapsedSections[talentKey]
                    CooldownCompanion:RefreshConfigPanel()
                end)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentCollapseBtn, "LEFT", "RIGHT", 2, 0, {
                    "Talent Conditions",
                    {"Show or hide this custom aura bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, tabInfoButtons)
                talentHeading.right:ClearAllPoints()
                talentHeading.right:SetPoint("RIGHT", talentHeading.frame, "RIGHT", -3, 0)
                talentHeading.right:SetPoint("LEFT", talentInfoBtn, "RIGHT", 4, 0)

                local conditions = cab.talentConditions
                local condCount = conditions and #conditions or 0

                if talentCollapsed then
                    local summaryLabel = AceGUI:Create("Label")
                    if condCount > 0 then
                        local firstCond = conditions[1]
                        local displayIcon = firstCond.spellID and C_Spell.GetSpellTexture(firstCond.spellID)
                        if displayIcon then
                            summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            summaryLabel:SetImageSize(16, 16)
                        end
                        if condCount == 1 then
                            local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                            summaryLabel:SetText(ST._GetConditionDisplayName(firstCond) .. showText)
                        else
                            summaryLabel:SetText(condCount .. " conditions" .. ST._GetConditionListContextSuffix(conditions))
                        end
                    else
                        summaryLabel:SetText("|cff888888None|r")
                    end
                    summaryLabel:SetFullWidth(true)
                    container:AddChild(summaryLabel)
                end

                if not talentCollapsed then

                -- Condition list display
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local condLabel = AceGUI:Create("Label")
                        local displayIcon = cond.spellID and C_Spell.GetSpellTexture(cond.spellID)
                        if displayIcon then
                            condLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            condLabel:SetImageSize(16, 16)
                        end
                        local nameText = ST._GetConditionDisplayName(cond)
                        local showText
                        if cond.show == "not_taken" then
                            showText = " |cffff4d4d(not taken)|r"
                        else
                            showText = " |cff33dd33(taken)|r"
                        end
                        condLabel:SetText("|cffFFFFFF" .. nameText .. "|r" .. showText)
                        condLabel:SetFullWidth(true)
                        container:AddChild(condLabel)

                        -- Per-condition stale node warning
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            warnLabel:SetText("|cffff8800  This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            container:AddChild(warnLabel)
                        end
                    end
                else
                    local emptyLabel = AceGUI:Create("Label")
                    emptyLabel:SetText("|cff888888No talent conditions set.|r")
                    emptyLabel:SetFullWidth(true)
                    container:AddChild(emptyLabel)
                end

                -- Button row: side-by-side Pick + Clear using Flow layout
                local talentBtnRow = AceGUI:Create("SimpleGroup")
                talentBtnRow:SetFullWidth(true)
                talentBtnRow:SetLayout("Flow")

                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetRelativeWidth(condCount > 0 and 0.5 or 1)
                pickBtn:SetCallback("OnClick", function()
                    local initialConditions = cab.talentConditions
                    -- Restrict picker to current spec (aura bars are per-spec)
                    local specID = CooldownCompanion._currentSpecId
                    local specHint = specID and { specs = { [specID] = true } } or nil
                    CooldownCompanion:OpenTalentPicker(function(results)
                        if results then
                            local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                            if changed then
                                results = normalized
                            end
                            customBars[cabIdx].talentConditions = results
                        else
                            customBars[cabIdx].talentConditions = nil
                        end
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end, initialConditions, specHint)
                end)
                talentBtnRow:AddChild(pickBtn)

                -- Clear button (only when conditions exist)
                if condCount > 0 then
                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetRelativeWidth(0.5)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    talentBtnRow:AddChild(clearBtn)
                end

                container:AddChild(talentBtnRow)

                end -- not talentCollapsed
            end
    end -- if cab.enabled and settings subtab selected

    if cab.enabled and IsTruthyConfigFlag(cab.independentAnchorEnabled) and independentSubTab == "anchor" then
        BuildCustomAuraBarAnchorSettings(container, customBars, settings, capturedIdx)
    end

end

------------------------------------------------------------------------
-- Layout & Order panel: per-element position/order control
------------------------------------------------------------------------

local function BuildLayoutOrderPanel(container)
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    local isVerticalLayout = IsResourceBarVerticalConfig(rbSettings)

    if not rbSettings or not rbSettings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure layout.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Build the ordered list of all active bar slots
    local activeResources = GetConfigActiveResources()
    local MAX_SLOTS = ST.MAX_CUSTOM_AURA_BARS or 3
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()

    -- Resolve the display color for a power type
    local function GetResourceColor(pt)
        local res = rbSettings.resources and rbSettings.resources[pt]
        if pt == 4 then return res and res.comboColor or DEFAULT_COMBO_COLOR_CONFIG
        elseif pt == 5 then return res and res.runeReadyColor or DEFAULT_RUNE_READY_COLOR_CONFIG
        elseif pt == 7 then return res and res.shardReadyColor or DEFAULT_SHARD_READY_COLOR_CONFIG
        elseif pt == 9 then return res and res.holyColor or DEFAULT_HOLY_COLOR_CONFIG
        elseif pt == 12 then return res and res.chiColor or DEFAULT_CHI_COLOR_CONFIG
        elseif pt == 16 then return res and res.arcaneColor or DEFAULT_ARCANE_COLOR_CONFIG
        elseif pt == 19 then return res and res.essenceReadyColor or DEFAULT_ESSENCE_READY_COLOR_CONFIG
        elseif pt == 100 then return res and res.mwBaseColor or DEFAULT_MW_BASE_COLOR_CONFIG
        else return res and res.color or DEFAULT_POWER_COLORS_CONFIG[pt] or { 1, 1, 1 }
        end
    end

    -- Helper: refresh after any order/position change
    local function ApplyAndRefresh()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function RenderSlotOrdering(slots, sectionTitle, sideOne, sideTwo, dividerLabel, moveOneLabel, moveTwoLabel)
        if sectionTitle and sectionTitle ~= "" then
            local sectionHeading = AceGUI:Create("Heading")
            sectionHeading:SetText(sectionTitle)
            sectionHeading:SetFullWidth(true)
            container:AddChild(sectionHeading)
        end

        if #slots == 0 then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetText("|cff888888No active entries in this section.|r")
            emptyLabel:SetFullWidth(true)
            container:AddChild(emptyLabel)
            return
        end

        local sideOneSlots = {}
        local sideTwoSlots = {}
        for _, slot in ipairs(slots) do
            if slot.getPos() == sideOne then
                table.insert(sideOneSlots, slot)
            else
                table.insert(sideTwoSlots, slot)
            end
        end
        table.sort(sideOneSlots, function(a, b) return a.getOrder() > b.getOrder() end)
        table.sort(sideTwoSlots, function(a, b) return a.getOrder() < b.getOrder() end)

        local displayList = {}
        for _, s in ipairs(sideOneSlots) do table.insert(displayList, s) end
        local dividerIdx = #displayList + 1
        for _, s in ipairs(sideTwoSlots) do table.insert(displayList, s) end

        for rowIdx, slot in ipairs(displayList) do
            if rowIdx == dividerIdx then
                local divLabel = AceGUI:Create("Heading")
                divLabel:SetText(dividerLabel or "Icons")
                divLabel:SetFullWidth(true)
                container:AddChild(divLabel)
            end

            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)
            container:AddChild(rowGroup)

            local nameLabel = AceGUI:Create("Label")
            local c = slot.color
            local coloredText = slot.label
            if c then
                local r, g, b = (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255
                coloredText = string.format("|cff%02x%02x%02x%s|r", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), slot.label)
            end
            nameLabel:SetText(coloredText)
            nameLabel:SetRelativeWidth(0.48)
            rowGroup:AddChild(nameLabel)

            local moveOneBtn = AceGUI:Create("Button")
            moveOneBtn:SetText(moveOneLabel)
            moveOneBtn:SetRelativeWidth(0.20)
            moveOneBtn:SetDisabled(rowIdx == 1 and slot.getPos() == sideOne)
            moveOneBtn:SetCallback("OnClick", function()
                local prev = displayList[rowIdx - 1]
                if prev and prev.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local prevOrder = prev.getOrder()
                    slot.setOrder(prevOrder)
                    prev.setOrder(myOrder)
                else
                    local minSideOne
                    for _, s in ipairs(sideOneSlots) do
                        local o = s.getOrder()
                        if not minSideOne or o < minSideOne then minSideOne = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideOne)
                    slot.setOrder(minSideOne and (minSideOne - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveOneBtn)

            local moveTwoBtn = AceGUI:Create("Button")
            moveTwoBtn:SetText(moveTwoLabel)
            moveTwoBtn:SetRelativeWidth(0.24)
            moveTwoBtn:SetDisabled(rowIdx == #displayList and slot.getPos() == sideTwo)
            moveTwoBtn:SetCallback("OnClick", function()
                local nextSlot = displayList[rowIdx + 1]
                if nextSlot and nextSlot.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local nextOrder = nextSlot.getOrder()
                    slot.setOrder(nextOrder)
                    nextSlot.setOrder(myOrder)
                else
                    local minSideTwo
                    for _, s in ipairs(sideTwoSlots) do
                        local o = s.getOrder()
                        if not minSideTwo or o < minSideTwo then minSideTwo = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideTwo)
                    slot.setOrder(minSideTwo and (minSideTwo - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveTwoBtn)
        end
    end

    local resourceSlots = {}
    if not rbSettings.resources then rbSettings.resources = {} end

    -- Class resource slots
    for _, pt in ipairs(activeResources) do
        if not rbSettings.resources[pt] then rbSettings.resources[pt] = {} end
        local res = rbSettings.resources[pt]
        local showResource = res.enabled ~= false
        if showResource and pt == 0 and rbSettings.hideManaForNonHealer then
            local specIdx = C_SpecializationInfo.GetSpecialization()
            if specIdx then
                local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
                if specID ~= 62 and role ~= "HEALER" then
                    showResource = false
                end
            end
        end
        if showResource then
            local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local pos = rbSettings.resources[pt].verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (rbSettings.resources[pt].position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        return rbSettings.resources[pt].verticalOrder or rbSettings.resources[pt].order or 1
                    end,
                    setPos = function(v) rbSettings.resources[pt].verticalPosition = v end,
                    setOrder = function(v) rbSettings.resources[pt].verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function() return rbSettings.resources[pt].position or "below" end,
                    getOrder = function() return rbSettings.resources[pt].order or 1 end,
                    setPos = function(v) rbSettings.resources[pt].position = v end,
                    setOrder = function(v) rbSettings.resources[pt].order = v end,
                })
            end
        end
    end

    -- Custom aura bar slots
    for slotIdx = 1, MAX_SLOTS do
        local cab = customBars and customBars[slotIdx]
        if cab and cab.enabled and cab.spellID and not IsTruthyConfigFlag(cab.independentAnchorEnabled) then
            if not rbSettings.customAuraBarSlots then rbSettings.customAuraBarSlots = {} end
            if not rbSettings.customAuraBarSlots[slotIdx] then
                rbSettings.customAuraBarSlots[slotIdx] = { position = "below", order = 1000 + slotIdx }
            end
            local spellInfo = C_Spell.GetSpellInfo(cab.spellID)
            local slotName = "Custom Aura " .. slotIdx
            if spellInfo and spellInfo.name then
                slotName = slotName .. ": " .. spellInfo.name
            end
            local captured = slotIdx
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = rbSettings.customAuraBarSlots[captured]
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (slot and slot.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local slot = rbSettings.customAuraBarSlots[captured]
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) rbSettings.customAuraBarSlots[captured].verticalPosition = v end,
                    setOrder = function(v) rbSettings.customAuraBarSlots[captured].verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function() return rbSettings.customAuraBarSlots[captured].position or "below" end,
                    getOrder = function() return rbSettings.customAuraBarSlots[captured].order or (1000 + captured) end,
                    setPos = function(v) rbSettings.customAuraBarSlots[captured].position = v end,
                    setOrder = function(v) rbSettings.customAuraBarSlots[captured].order = v end,
                })
            end
        end
    end

    local castSlots = {}
    if cbSettings and cbSettings.enabled then
        local defaultAnchor = CooldownCompanion:GetFirstAvailableAnchorGroup()
        local cbAnchor = cbSettings.anchorGroupId or defaultAnchor
        local rbAnchor = rbSettings.anchorGroupId or defaultAnchor
        if cbAnchor and cbAnchor == rbAnchor then
            local cbColor = cbSettings.barColor or { 1.0, 0.7, 0.0 }
            table.insert(castSlots, {
                label = "Cast Bar",
                color = cbColor,
                getPos = function() return cbSettings.position or "below" end,
                getOrder = function() return cbSettings.order or 2000 end,
                setPos = function(v) cbSettings.position = v end,
                setOrder = function(v) cbSettings.order = v end,
            })
        end
    end

    if not isVerticalLayout then
        for _, slot in ipairs(castSlots) do
            table.insert(resourceSlots, slot)
        end
        if #resourceSlots == 0 then
            local label = AceGUI:Create("Label")
            label:SetText("No active bars to order. Enable resources or custom aura bars first.")
            label:SetFullWidth(true)
            container:AddChild(label)
            return
        end
        RenderSlotOrdering(resourceSlots, nil, "above", "below", "Icons", "Up", "Down")
        return
    end

    if #resourceSlots == 0 and #castSlots == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No active bars to order. Enable resources, custom aura bars, or cast bar first.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    RenderSlotOrdering(resourceSlots, "Resources & Custom Aura Bars", "left", "right", "Icons", "Left", "Right")

    if #castSlots > 0 then
        local spacer = AceGUI:Create("Label")
        spacer:SetText(" ")
        spacer:SetFullWidth(true)
        container:AddChild(spacer)
        RenderSlotOrdering(castSlots, "Cast Bar", "above", "below", "Icons", "Up", "Down")
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildResourceBarBarTextStylingPanel = BuildResourceBarBarTextStylingPanel
ST._BuildResourceBarColorsStylingPanel = BuildResourceBarColorsStylingPanel
ST._BuildResourceBarAuraOverlaysStylingPanel = BuildResourceBarAuraOverlaysStylingPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
