--[[
    CooldownCompanion - ResourceBarPanelsHelpers
    Query helpers, aura overlay UI builders, autocomplete, and CDM warnings
    for the resource bar config panel.

    Exports via ST._RBP table. Consuming files alias to locals at load time.
    Shared constants are imported from ST._RB (eliminating _CONFIG duplicates).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddColorPicker = ST._AddColorPicker
local tabInfoButtons = CS.tabInfoButtons

-- Shared constants from ResourceBarConstants (eliminates _CONFIG duplicates)
local RB = ST._RB
local POWER_NAMES = RB.POWER_NAMES
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_MW_OVERLAY_COLOR = RB.DEFAULT_MW_OVERLAY_COLOR
local DEFAULT_MW_MAX_COLOR = RB.DEFAULT_MW_MAX_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local HIDE_AT_ZERO_ELIGIBLE = RB.HIDE_AT_ZERO_ELIGIBLE
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
local DEFAULT_RESOURCE_TEXT_FORMAT = RB.DEFAULT_RESOURCE_TEXT_FORMAT
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = RB.DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local DEFAULT_RESOURCE_TEXT_ANCHOR = RB.DEFAULT_RESOURCE_TEXT_ANCHOR
local DEFAULT_RESOURCE_TEXT_X_OFFSET = RB.DEFAULT_RESOURCE_TEXT_X_OFFSET
local DEFAULT_RESOURCE_TEXT_Y_OFFSET = RB.DEFAULT_RESOURCE_TEXT_Y_OFFSET
local DEFAULT_SEG_THRESHOLD_COLOR = RB.DEFAULT_SEG_THRESHOLD_COLOR
local DEFAULT_CONTINUOUS_TICK_COLOR = RB.DEFAULT_CONTINUOUS_TICK_COLOR
local DEFAULT_CONTINUOUS_TICK_MODE = RB.DEFAULT_CONTINUOUS_TICK_MODE
local DEFAULT_CONTINUOUS_TICK_PERCENT = RB.DEFAULT_CONTINUOUS_TICK_PERCENT
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = RB.DEFAULT_CONTINUOUS_TICK_ABSOLUTE
local DEFAULT_CONTINUOUS_TICK_WIDTH = RB.DEFAULT_CONTINUOUS_TICK_WIDTH
local DEFAULT_COMBO_COLOR = RB.DEFAULT_COMBO_COLOR
local DEFAULT_COMBO_MAX_COLOR = RB.DEFAULT_COMBO_MAX_COLOR
local DEFAULT_COMBO_CHARGED_COLOR = RB.DEFAULT_COMBO_CHARGED_COLOR
local DEFAULT_RUNE_READY_COLOR = RB.DEFAULT_RUNE_READY_COLOR
local DEFAULT_RUNE_RECHARGING_COLOR = RB.DEFAULT_RUNE_RECHARGING_COLOR
local DEFAULT_RUNE_MAX_COLOR = RB.DEFAULT_RUNE_MAX_COLOR
local DEFAULT_SHARD_READY_COLOR = RB.DEFAULT_SHARD_READY_COLOR
local DEFAULT_SHARD_RECHARGING_COLOR = RB.DEFAULT_SHARD_RECHARGING_COLOR
local DEFAULT_SHARD_MAX_COLOR = RB.DEFAULT_SHARD_MAX_COLOR
local DEFAULT_HOLY_COLOR = RB.DEFAULT_HOLY_COLOR
local DEFAULT_HOLY_MAX_COLOR = RB.DEFAULT_HOLY_MAX_COLOR
local DEFAULT_CHI_COLOR = RB.DEFAULT_CHI_COLOR
local DEFAULT_CHI_MAX_COLOR = RB.DEFAULT_CHI_MAX_COLOR
local DEFAULT_ARCANE_COLOR = RB.DEFAULT_ARCANE_COLOR
local DEFAULT_ARCANE_MAX_COLOR = RB.DEFAULT_ARCANE_MAX_COLOR
local DEFAULT_ESSENCE_READY_COLOR = RB.DEFAULT_ESSENCE_READY_COLOR
local DEFAULT_ESSENCE_RECHARGING_COLOR = RB.DEFAULT_ESSENCE_RECHARGING_COLOR
local DEFAULT_ESSENCE_MAX_COLOR = RB.DEFAULT_ESSENCE_MAX_COLOR
local CLASS_RESOURCES_CONFIG = RB.CLASS_RESOURCES_CONFIG
local SPEC_RESOURCES_CONFIG = RB.SPEC_RESOURCES_CONFIG
local IsAstralPowerAvailableForCurrentDruidSpec = RB.IsAstralPowerAvailableForCurrentDruidSpec

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey
local GetResolvedResourceAuraUnit = RB.GetResolvedResourceAuraUnit
local EnsureResourceAuraUnit = RB.EnsureResourceAuraUnit
local RefreshResourceAuraUnitForSpell = RB.RefreshResourceAuraUnitForSpell

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
-- Collapsed section state
------------------------------------------------------------------------
local resourceBarCollapsedSections = {}

------------------------------------------------------------------------
-- Query functions
------------------------------------------------------------------------

local function SupportsResourceAuraStackModeConfig(powerType)
    return powerType == 100 or SEGMENTED_TYPES[powerType] == true
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
            return CLASS_RESOURCES_CONFIG[11]
        end
        local resources = {}
        for _, powerType in ipairs(CLASS_RESOURCES_CONFIG[11] or {}) do
            if powerType ~= 8 then
                resources[#resources + 1] = powerType
            end
        end
        return resources
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

local function GetOrCreateResourceAuraEntryConfig(resource, specID)
    if type(resource) ~= "table" or not specID then
        return nil
    end

    if type(resource.auraOverlayEntries) ~= "table" then
        resource.auraOverlayEntries = {}
    end

    local entry = resource.auraOverlayEntries[specID]
    if type(entry) ~= "table" then
        entry = resource.auraOverlayEntries[tostring(specID)]
        if type(entry) == "table" then
            resource.auraOverlayEntries[tostring(specID)] = nil
            resource.auraOverlayEntries[specID] = entry
        else
            entry = {}
            resource.auraOverlayEntries[specID] = entry
        end
    end

    return entry
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

------------------------------------------------------------------------
-- Autocomplete handlers
------------------------------------------------------------------------

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

------------------------------------------------------------------------
-- Aura overlay UI builders
------------------------------------------------------------------------

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
    local resolvedAuraUnit = GetResolvedResourceAuraUnit and GetResolvedResourceAuraUnit(entry, spellID) or "player"
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

    local auraUnitDrop = AceGUI:Create("Dropdown")
    auraUnitDrop:SetLabel("Aura Unit")
    auraUnitDrop:SetList({
        player = "Player",
        target = "Target",
    }, { "player", "target" })
    auraUnitDrop:SetValue(resolvedAuraUnit)
    auraUnitDrop:SetFullWidth(true)
    auraUnitDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if val ~= "player" and val ~= "target" then
            return
        end
        if options.onAuraUnitChanged then
            options.onAuraUnitChanged(val)
        end
    end)
    container:AddChild(auraUnitDrop)
    CreateInfoButton(auraUnitDrop.frame, auraUnitDrop.label, "LEFT", "RIGHT",
        4, 0, {
        "Aura Unit",
        {"This controls where the tracked aura is expected to exist. Use Target for debuffs on your target, or Player for buffs and procs on yourself.", 1, 1, 1, true},
    }, tabInfoButtons)

    local auraUnitSpacer = AceGUI:Create("Label")
    auraUnitSpacer:SetText(" ")
    auraUnitSpacer:SetFullWidth(true)
    container:AddChild(auraUnitSpacer)

    local _auraProxy = { auraActiveColor = GetSafeRGBConfig(entry and entry.auraActiveColor, DEFAULT_RESOURCE_AURA_ACTIVE_COLOR) }
    AddColorPicker(container, _auraProxy, "auraActiveColor", resourceName .. " Aura Active Color", DEFAULT_RESOURCE_AURA_ACTIVE_COLOR, false,
        function()
            if options.onColorConfirmed then
                local c = _auraProxy.auraActiveColor
                options.onColorConfirmed(c[1], c[2], c[3])
            end
        end,
        function()
            if options.onColorChanged then
                local c = _auraProxy.auraActiveColor
                options.onColorChanged(c[1], c[2], c[3])
            end
        end)

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

local function ClearLegacyResourceAuraFieldsConfig(resource)
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

local function ClearResourceAuraEntryConfig(powerType, resource, specID)
    if type(resource.auraOverlayEntries) ~= "table" then
        return
    end

    resource.auraOverlayEntries[specID] = nil
    resource.auraOverlayEntries[tostring(specID)] = nil
    if not next(resource.auraOverlayEntries) then
        resource.auraOverlayEntries = nil
    end

    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:RefreshConfigPanel()
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
        settings.resources[powerType].auraOverlayEnabled = (val == true)

        if val then
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

    -- Aura overlay fields are shown for the current spec only; switching specs reconfigures the fields
    local currentSpecID = GetCurrentConfigSpecID()
    if not currentSpecID then
        local specUnavailLabel = AceGUI:Create("Label")
        specUnavailLabel:SetText("Specialization data not yet available.")
        specUnavailLabel:SetFullWidth(true)
        container:AddChild(specUnavailLabel)
        return
    end

    local entryForSpec = GetResourceAuraEntryConfig(res, currentSpecID)

    AddResourceAuraEntryFields(container, powerType, resourceName, entryForSpec, {
        onSpellChanged = function(id)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            entry.auraColorSpellID = id
            if RefreshResourceAuraUnitForSpell then
                RefreshResourceAuraUnitForSpell(entry, id)
            end
            ClearLegacyResourceAuraFieldsConfig(res)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
        onAuraUnitChanged = function(val)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            if EnsureResourceAuraUnit then
                EnsureResourceAuraUnit(entry, entry.auraColorSpellID, val, true)
            else
                entry.auraUnit = val
                entry.auraUnitExplicit = true
            end
            ClearLegacyResourceAuraFieldsConfig(res)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
        onColorChanged = function(r, g, b)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            entry.auraActiveColor = { r, g, b }
        end,
        onColorConfirmed = function(r, g, b)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            entry.auraActiveColor = { r, g, b }
            ClearLegacyResourceAuraFieldsConfig(res)
            CooldownCompanion:ApplyResourceBars()
        end,
        onTrackingChanged = function(val)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            entry.auraColorTrackingMode = val
            if val == "stacks" then
                local current = tonumber(entry.auraColorMaxStacks)
                if not current or current < 2 then
                    entry.auraColorMaxStacks = 2
                end
            end
            ClearLegacyResourceAuraFieldsConfig(res)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
        onMaxStacksChanged = function(parsed)
            local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
            if not entry then
                return
            end
            entry.auraColorMaxStacks = parsed
            ClearLegacyResourceAuraFieldsConfig(res)
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Clear Overlay button (only if entry exists)
    if type(entryForSpec) == "table" then
        local clearSpacer = AceGUI:Create("Label")
        clearSpacer:SetText(" ")
        clearSpacer:SetFullWidth(true)
        container:AddChild(clearSpacer)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Overlay")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            ClearResourceAuraEntryConfig(powerType, res, currentSpecID)
        end)
        container:AddChild(clearBtn)
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
        {"These settings are per-specialization. Switch specs to configure different aura overlays.", 1, 1, 1, true},
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
                local resourceName = POWER_NAMES[pt] or ("Power " .. pt)
                AddResourceAuraOverrideControls(container, settings, pt, resourceName, rbAuraOverlayAdvBtns)
            end
        end
    end
end

------------------------------------------------------------------------
-- Simple queries
------------------------------------------------------------------------

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

------------------------------------------------------------------------
-- Export via ST._RBP
------------------------------------------------------------------------

ST._RBP = {
    collapsedSections = resourceBarCollapsedSections,
    BuildResourceAuraOverlaySection = BuildResourceAuraOverlaySection,
    GetConfigActiveResources = GetConfigActiveResources,
    GetCurrentConfigSpecID = GetCurrentConfigSpecID,
    GetSpecOverrideTable = GetSpecOverrideTable,
    ReadSpecOverrideKey = ReadSpecOverrideKey,
    WriteSpecOverrideKey = WriteSpecOverrideKey,
    GetPlayerSpecOptionsConfig = GetPlayerSpecOptionsConfig,
    ResolveAuraColorSpellIDFromText = ResolveAuraColorSpellIDFromText,
    GetResourceAuraEntryCountConfig = GetResourceAuraEntryCountConfig,
    GetResourceAuraEntryConfig = GetResourceAuraEntryConfig,
    IsResourceAuraOverlayEnabledConfig = IsResourceAuraOverlayEnabledConfig,
    GetResourceAuraTrackingModeConfig = GetResourceAuraTrackingModeConfig,
    GetSafeRGBConfig = GetSafeRGBConfig,
    GetSafeRGBAConfig = GetSafeRGBAConfig,
    CopyRGBConfig = CopyRGBConfig,
    GetSegmentedThresholdValueConfig = GetSegmentedThresholdValueConfig,
    GetContinuousTickModeConfig = GetContinuousTickModeConfig,
    GetContinuousTickPercentConfig = GetContinuousTickPercentConfig,
    GetContinuousTickAbsoluteConfig = GetContinuousTickAbsoluteConfig,
    AttachAuraAutocompleteHandlers = AttachAuraAutocompleteHandlers,
    AddResourceAuraEntryFields = AddResourceAuraEntryFields,
    ClearLegacyResourceAuraFieldsConfig = ClearLegacyResourceAuraFieldsConfig,
    ClearResourceAuraEntryConfig = ClearResourceAuraEntryConfig,
    AddResourceAuraOverrideControls = AddResourceAuraOverrideControls,
    AddCdmAuraReadinessWarning = AddCdmAuraReadinessWarning,
    BuildAuraBarAutocompleteCache = BuildAuraBarAutocompleteCache,
    SupportsResourceAuraStackModeConfig = SupportsResourceAuraStackModeConfig,
    IsResourceBarVerticalConfig = IsResourceBarVerticalConfig,
    GetResourceThicknessFieldConfig = GetResourceThicknessFieldConfig,
    GetResourceGapFieldConfig = GetResourceGapFieldConfig,
}
