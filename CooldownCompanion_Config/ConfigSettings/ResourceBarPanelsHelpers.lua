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
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
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
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local CLASS_RESOURCES_CONFIG = RB.CLASS_RESOURCES_CONFIG
local SPEC_RESOURCES_CONFIG = RB.SPEC_RESOURCES_CONFIG
local IsAstralPowerAvailableForCurrentDruidSpec = RB.IsAstralPowerAvailableForCurrentDruidSpec
local DRUID_CLASS_ID = 11
local DRUID_BALANCE_SPEC_ID = 102

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey
local GetResolvedResourceAuraUnit = RB.GetResolvedResourceAuraUnit
local EnsureResourceAuraUnit = RB.EnsureResourceAuraUnit
local RefreshResourceAuraUnitForSpell = RB.RefreshResourceAuraUnitForSpell

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

------------------------------------------------------------------------
-- Resource aura overlay editor helpers
------------------------------------------------------------------------
local function AddResourceAuraTrackingGap(container)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)
end

local function SetupResourceAuraStatusLabel(container, label, text, justifyH)
    label:SetFullWidth(true)
    label:SetJustifyH(justifyH or "LEFT")
    local contentWidth = container.content and container.content:GetWidth()
    if contentWidth and contentWidth > 0 then
        label:SetWidth(math.max(1, contentWidth - 20))
    end
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
end

local function GetResourceAuraCdmEnabledConfig()
    if C_CVar and C_CVar.GetCVarBool then
        return C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    end
    if GetCVarBool then
        return GetCVarBool("cooldownViewerEnabled") == true
    end
    return false
end

local function SetResourceAuraCdmEnabledConfig(enabled)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("cooldownViewerEnabled", enabled and "1" or "0")
    elseif SetCVar then
        SetCVar("cooldownViewerEnabled", enabled and "1" or "0")
    end
end

local function GetResourceAuraDisplayName(spellID)
    return GetAuraBarAutocompleteDisplayName(spellID) or (spellID and ("Spell " .. tostring(spellID))) or nil
end

local function GetResourceAuraDisplayIcon(spellID)
    return GetAuraBarAutocompleteDisplayIcon(spellID) or 134400
end

local function TrimResourceOverlayAuraText(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function BuildResourceOverlayAuraError(token, reason)
    if reason == "ambiguous" then
        return "Multiple CDM auras match " .. token .. ". Pick the specific aura from the dropdown, or enter its aura spell ID."
    end
    return token .. " is not a CDM Tracked Buff/Bar aura."
end

local function ResolveResourceOverlayAuraText(rawText)
    local text = TrimResourceOverlayAuraText(rawText)
    if text == "" then
        return nil
    end
    if text:find("[,;\n\r]") then
        return nil, "Resource aura overlays use one aura. Enter one CDM aura name or spell ID."
    end
    if text:match("^%d+%s+%d+[%d%s]*$") then
        return nil, "Resource aura overlays use one aura. Enter one CDM aura name or spell ID."
    end
    if not CS.ResolveCDMAuraAutocompleteEntry then
        return nil, "CDM aura autocomplete is not ready. Try again in a moment."
    end

    local entry, reason = CS.ResolveCDMAuraAutocompleteEntry(text)
    local spellID = entry and tonumber(entry.id)
    if not spellID or spellID <= 0 then
        return nil, BuildResourceOverlayAuraError(text, reason)
    end
    return spellID
end

local function SetResourceAuraSpellIDConfig(entry, spellID)
    spellID = tonumber(spellID)
    if type(entry) ~= "table" or not spellID or spellID <= 0 then
        return false
    end
    entry.auraColorSpellID = spellID
    if RefreshResourceAuraUnitForSpell then
        RefreshResourceAuraUnitForSpell(entry, spellID)
    end
    return true
end

local function ClearResourceAuraIdentityConfig(entry)
    if type(entry) ~= "table" or entry.auraColorSpellID == nil then
        return false
    end
    entry.auraColorSpellID = nil
    return true
end

local function BuildResourceAuraButtonData(spellID, resolvedAuraUnit)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return nil
    end
    return {
        type = "spell",
        id = spellID,
        auraTracking = true,
        auraUnit = resolvedAuraUnit,
        addedAs = "aura",
    }
end

local function ResolveResourceAuraTrackingStatus(spellID, resolvedAuraUnit)
    local cdmEnabled = GetResourceAuraCdmEnabledConfig()
    local buttonData = BuildResourceAuraButtonData(spellID, resolvedAuraUnit)
    if not (buttonData and CooldownCompanion.ResolveAuraTrackingConfigStatus) then
        return { state = "noAssociatedAura", ready = false, cdmEnabled = cdmEnabled }
    end

    local viewerFrame = CooldownCompanion.ResolveButtonAuraViewerFrame
        and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
        or nil
    return CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
end

local function AddResourceAuraSubHeading(container, text, tooltipLines, infoButtons)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    if tooltipLines then
        local tooltip = { text }
        for _, line in ipairs(tooltipLines) do
            tooltip[#tooltip + 1] = type(line) == "table" and line or { line, 1, 1, 1, true }
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, tooltip, infoButtons or tabInfoButtons)
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
    end

    return heading
end

local function ConfigureResourceAuraClearButton(button, onClear)
    button:SetSize(16, 16)
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    button.icon:SetAtlas("common-icon-redx", false)
    button.icon:Show()
    button:SetScript("OnClick", function()
        if onClear then
            onClear()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Clear Overlay Aura")
        GameTooltip:AddLine("Removes the selected aura while keeping this resource overlay enabled and preserving its display settings.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Show()
end

local function AddResourceAuraRow(container, spellID, onClear)
    spellID = tonumber(spellID)
    if not spellID then
        return nil
    end

    local row = AceGUI:Create("InteractiveLabel")
    local icon = GetResourceAuraDisplayIcon(spellID)
    local name = GetResourceAuraDisplayName(spellID) or ("Spell " .. tostring(spellID))
    if CleanRecycledEntry then
        CleanRecycledEntry(row)
    end
    row:SetText(name)
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlightSmall)
    row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if ApplyConfigRowIcon then
        ApplyConfigRowIcon(row, icon, { rightPad = onClear and 28 or 4 })
    end
    if BindConfigShiftTooltip then
        BindConfigShiftTooltip(row, "spell", spellID, row.frame, "ANCHOR_RIGHT")
    end
    row._cdcAfterConfigRowLayout = function(self)
        local frame = self.frame
        local label = self.label
        local image = self.image
        self:SetHeight(22)
        frame:SetHeight(22)
        frame.height = 22
        if image then
            image:ClearAllPoints()
            image:SetTexture(icon)
            image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            image:SetSize(18, 18)
            image:SetPoint("LEFT", frame, "LEFT", 2, 0)
            image:Show()
        end
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", frame, "LEFT", 24, 0)
            label:SetPoint("RIGHT", frame, "RIGHT", onClear and -28 or -4, 0)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            if label.SetWordWrap then
                label:SetWordWrap(false)
            end
            if label.SetNonSpaceWrap then
                label:SetNonSpaceWrap(false)
            end
            if label.SetMaxLines then
                label:SetMaxLines(1)
            end
        end
    end
    row:_cdcAfterConfigRowLayout()

    if onClear then
        local frame = row.frame
        local clearBtn = frame._cdcResourceAuraClearBtn
        if not clearBtn then
            clearBtn = CreateFrame("Button", nil, frame)
            frame._cdcResourceAuraClearBtn = clearBtn
        end
        clearBtn:ClearAllPoints()
        clearBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
        ConfigureResourceAuraClearButton(clearBtn, onClear)
    end

    container:AddChild(row)
    return row
end

local function AddResourceAuraStatusBlock(container, spellID, resolvedAuraUnit)
    if not spellID then
        return
    end

    local auraStatus = ResolveResourceAuraTrackingStatus(spellID, resolvedAuraUnit)
    local auraConfigReady = auraStatus.ready == true
    local inactiveColor = auraStatus.state == "associatedAuraNotTracked" and "|cffffff00" or "|cffff0000"

    AddResourceAuraTrackingGap(container)

    local statusLabel = AceGUI:Create("Label")
    SetupResourceAuraStatusLabel(container, statusLabel,
        auraConfigReady and "|cff00ff00Aura tracking is active and ready.|r" or inactiveColor .. "Aura tracking is not ready.|r",
        "CENTER")
    container:AddChild(statusLabel)

    AddResourceAuraTrackingGap(container)

    local explainText
    if auraStatus.state == "cdmDisabled" then
        explainText = "|cff888888Blizzard Cooldown Manager is disabled. Enable it above to allow aura tracking.|r"
    elseif auraStatus.state == "noAssociatedAura" then
        explainText = "|cff888888This aura was not found in Blizzard CDM's tracked buff or tracked bar data.|r"
    elseif auraStatus.state == "trackedAuraUnavailable" then
        explainText = "|cff888888This aura is tracked in Blizzard CDM, but its Buffs/Debuffs viewer is not currently readable. Set the CDM Buffs/Debuffs visibility to Always Visible.|r"
    elseif auraStatus.state == "associatedAuraNotTracked" then
        explainText = "|cff888888This aura was found, but it is not currently tracked in CDM as a Tracked Buff or Tracked Bar.|r"
    end

    if explainText then
        local explainLabel = AceGUI:Create("Label")
        SetupResourceAuraStatusLabel(container, explainLabel, explainText)
        container:AddChild(explainLabel)
        AddResourceAuraTrackingGap(container)
    end
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

local function GetConfigEditableResources(settings)
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
        if IsResourceConfigEnabled(settings, powerType) then
            AddUniqueResource(result, seen, powerType)
        end
    end

    for _, specID in ipairs(specIDs) do
        for _, powerType in ipairs(SPEC_RESOURCES_CONFIG[specID] or {}) do
            if IsResourceConfigEnabled(settings, powerType) then
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

local function IsResourceEditableInColumn4(powerType, settings)
    settings = settings or CooldownCompanion:GetResourceBarSettings()
    if powerType == nil or powerType == RESOURCE_HEALTH then
        return false
    end
    if not (type(settings) == "table" and settings.enabled == true) then
        return false
    end
    if not IsResourceConfigEnabled(settings, powerType) then
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

local function IsResourceAuraOverlayEnabledConfig(resource, specID)
    if type(resource) ~= "table" then
        return false
    end
    if specID then
        local specData = type(resource.specOverrides) == "table"
            and (resource.specOverrides[specID] or resource.specOverrides[tostring(specID)])
            or nil
        if type(specData) == "table" and type(specData.auraOverlayEnabled) == "boolean" then
            return specData.auraOverlayEnabled
        end
        if resource.auraOverlayEnabled == false then
            return false
        end
        if type(GetResourceAuraEntryConfig(resource, specID)) == "table" then
            return true
        end
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
        ShowAuraBarAutocompleteResults(text, widget, onAuraSelect)
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

    AddResourceAuraSubHeading(container, "Aura Tracking", {
        "Resource overlays use one CDM-trackable aura for this resource and specialization.",
        "Use the field below or Pick CDM to choose the overlay aura. This is a basic resource overlay editor, not the full Aura Tracking module.",
    }, options.infoButtons)

    local auraEditBox = AceGUI:Create("EditBox")
    if auraEditBox.editbox.Instructions then
        auraEditBox.editbox.Instructions:Hide()
    end
    auraEditBox:SetLabel("Overlay Aura")
    auraEditBox:SetText("")
    auraEditBox:DisableButton(true)
    auraEditBox:SetFullWidth(true)
    if auraEditBox.SetDisabled then
        auraEditBox:SetDisabled(spellID ~= nil)
    end

    local function CommitOverlayAuraID(id)
        CS.HideAutocomplete()
        if options.onSpellChanged then
            options.onSpellChanged(id)
        end
    end

    auraEditBox:SetCallback("OnTextChanged", function(widget, _, text)
        if spellID then
            CS.HideAutocomplete()
            return
        end
        if text and #text >= 1 and CS.SearchCDMAuraAutocomplete then
            CS.ShowAutocompleteResults(CS.SearchCDMAuraAutocomplete(text), widget, function(selectedEntry)
                CommitOverlayAuraID(selectedEntry.id)
            end, { requireExactNumericEnter = true })
        else
            CS.HideAutocomplete()
        end
    end)
    auraEditBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if spellID then
            CS.HideAutocomplete()
            return
        end
        if CS.ConsumeAutocompleteEnter and CS.ConsumeAutocompleteEnter() then
            return
        end
        CS.HideAutocomplete()

        local id, errorText = ResolveResourceOverlayAuraText(text)
        if not id then
            if errorText then
                CooldownCompanion:Print(errorText)
            end
            return
        end

        widget:SetText("")
        CommitOverlayAuraID(id)
    end)
    if CS.SetupAutocompleteKeyHandler then
        CS.SetupAutocompleteKeyHandler(auraEditBox)
    end
    container:AddChild(auraEditBox)

    CreateInfoButton(auraEditBox.frame, auraEditBox.frame, "TOPLEFT", "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2, {
        "Overlay Aura",
        {"Resource overlays use one CDM-trackable aura for the selected resource/spec. Clear the selected aura before typing a replacement, or use Pick CDM to replace it directly.", 1, 1, 1, true},
    }, options.infoButtons or tabInfoButtons)

    if spellID then
        AddResourceAuraRow(container, spellID, options.onClearSpell)
    end

    AddResourceAuraTrackingGap(container)

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
    }, options.infoButtons or tabInfoButtons)

    AddResourceAuraTrackingGap(container)

    local cdmEnabled = GetResourceAuraCdmEnabledConfig()
    local cdmToggleBtn = AceGUI:Create("Button")
    cdmToggleBtn:SetText(cdmEnabled and "Blizzard CDM: |cff00ff00Active|r" or "Blizzard CDM: |cffff0000Inactive|r")
    cdmToggleBtn:SetFullWidth(true)
    cdmToggleBtn:SetCallback("OnClick", function()
        local nextEnabled = not GetResourceAuraCdmEnabledConfig()
        SetResourceAuraCdmEnabledConfig(nextEnabled)
        CooldownCompanion:RefreshConfigPanel()
        if nextEnabled and C_Timer then
            C_Timer.After(0.2, function()
                if CooldownCompanion.BuildViewerAuraMap then
                    CooldownCompanion:BuildViewerAuraMap()
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
        end
    end)
    container:AddChild(cdmToggleBtn)

    local cdmRow = AceGUI:Create("SimpleGroup")
    cdmRow:SetFullWidth(true)
    cdmRow:SetLayout("Flow")

    local openCdmBtn = AceGUI:Create("Button")
    openCdmBtn:SetText("CDM Settings")
    openCdmBtn:SetRelativeWidth(0.5)
    openCdmBtn:SetCallback("OnClick", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:TogglePanel()
        end
    end)
    cdmRow:AddChild(openCdmBtn)

    local pickCDMBtn = AceGUI:Create("Button")
    pickCDMBtn:SetText("Pick CDM")
    pickCDMBtn:SetRelativeWidth(0.5)
    pickCDMBtn:SetCallback("OnClick", function()
        if not CS.StartPickCDM then
            return
        end
        CS.StartPickCDM(function(pickedSpellID)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if pickedSpellID and options.onSpellChanged then
                options.onSpellChanged(pickedSpellID)
            end
        end)
    end)
    pickCDMBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Pick from Cooldown Manager")
        if spellID then
            GameTooltip:AddLine("Shows CDM Tracked Buff/Bar auras. Picking one replaces the current overlay aura for this resource/spec.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Shows CDM Tracked Buff/Bar auras. Picking one sets the overlay aura for this resource/spec.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    pickCDMBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    cdmRow:AddChild(pickCDMBtn)
    container:AddChild(cdmRow)

    AddResourceAuraStatusBlock(container, spellID, resolvedAuraUnit)

    if SupportsResourceAuraStackModeConfig(powerType) then
        AddResourceAuraSubHeading(container, "Aura Display Mode", {
            "Active recolors the resource while the overlay aura is active.",
            "Stack Count maps the aura's current stack count onto the resource bar.",
        }, options.infoButtons)

        local trackingMode = GetResourceAuraTrackingModeConfig(entry)
        local trackDrop = AceGUI:Create("Dropdown")
        trackDrop:SetLabel("Tracking Mode")
        trackDrop:SetList({
            stacks = "Stack Count",
            active = "Active",
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
            ST._ConfigureWrappedHelperLabel(auraStackHint)
            auraStackHint:SetText("|cff888888Stack mode maps aura stacks to a bar proportion (e.g. 1/2 = half bar). Applies only to segmented/overlay resources.|r")
            auraStackHint:SetFullWidth(true)
            container:AddChild(auraStackHint)
        end
    end

    AddResourceAuraSubHeading(container, "Colors", {
        "Controls the resource color while the overlay aura is active.",
    }, options.infoButtons)

    local _auraProxy = { auraActiveColor = GetSafeRGBConfig(entry and entry.auraActiveColor, DEFAULT_RESOURCE_AURA_ACTIVE_COLOR) }
    AddColorPicker(container, _auraProxy, "auraActiveColor", "Bar Color", DEFAULT_RESOURCE_AURA_ACTIVE_COLOR, false,
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
    if type(resource.specOverrides) == "table" then
        local specData = resource.specOverrides[specID] or resource.specOverrides[tostring(specID)]
        if type(specData) == "table" then
            specData.auraOverlayEnabled = nil
            if not next(specData) then
                resource.specOverrides[specID] = nil
                resource.specOverrides[tostring(specID)] = nil
                if not next(resource.specOverrides) then
                    resource.specOverrides = nil
                end
            end
        end
    end

    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:RefreshConfigPanel()
end


local function AddResourceAuraOverrideControls(container, settings, powerType, resourceName, auraAdvButtons, opts)
    if not settings.resources[powerType] then
        settings.resources[powerType] = {}
    end
    local res = settings.resources[powerType]
    local configuredSpecID = opts and tonumber(opts.specID) or nil
    local auraAdvKey = "rbAuraOverlay_" .. powerType .. (configuredSpecID and ("_" .. configuredSpecID) or "")
    local currentSpecID = configuredSpecID or GetCurrentConfigSpecID()
    local advancedContext = opts and opts.context or nil
    if not currentSpecID then
        local specUnavailLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(specUnavailLabel)
        specUnavailLabel:SetText("Specialization data not yet available.")
        specUnavailLabel:SetFullWidth(true)
        container:AddChild(specUnavailLabel)
        return
    end
    local auraOverlayEnabled = IsResourceAuraOverlayEnabledConfig(res, currentSpecID)
    local selectedAuraEntry = GetResourceAuraEntryConfig(res, currentSpecID)
    local selectedAuraSpellID = tonumber(selectedAuraEntry and selectedAuraEntry.auraColorSpellID) or nil

    local enableAuraOverlayCb = AceGUI:Create("CheckBox")
    enableAuraOverlayCb:SetLabel("Enable " .. resourceName .. " Aura Overlay")
    enableAuraOverlayCb:SetValue(auraOverlayEnabled)
    enableAuraOverlayCb:SetFullWidth(true)
    enableAuraOverlayCb:SetCallback("OnValueChanged", function(widget, event, val)
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        WriteSpecOverrideKey(settings, powerType, currentSpecID, "auraOverlayEnabled", val == true)

        if val and CS.QueueAdvancedSettingsPanelOpen then
            CS.QueueAdvancedSettingsPanelOpen(auraAdvKey, advancedContext)
        end
        CooldownCompanion:ApplyResourceBars()
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(enableAuraOverlayCb)

    if auraOverlayEnabled and selectedAuraSpellID then
        AddResourceAuraRow(container, selectedAuraSpellID)
    end

    local function BuildResourceAuraOverlayAdvanced(panel)
        local entryForSpec = GetResourceAuraEntryConfig(res, currentSpecID)

        AddResourceAuraEntryFields(panel, powerType, resourceName, entryForSpec, {
            infoButtons = auraAdvButtons or tabInfoButtons,
            onSpellChanged = function(id)
                local entry = GetOrCreateResourceAuraEntryConfig(res, currentSpecID)
                if not entry then
                    return
                end
                if not SetResourceAuraSpellIDConfig(entry, id) then
                    return
                end
                ClearLegacyResourceAuraFieldsConfig(res)
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end,
            onClearSpell = function()
                local entry = GetResourceAuraEntryConfig(res, currentSpecID)
                if not ClearResourceAuraIdentityConfig(entry) then
                    return
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
    end

    local auraAdvExpanded = AddAdvancedToggle(
        enableAuraOverlayCb,
        auraAdvKey,
        auraAdvButtons or tabInfoButtons,
        auraOverlayEnabled,
        {
            title = resourceName .. " Aura Overlay",
            build = BuildResourceAuraOverlayAdvanced,
            context = advancedContext,
        }
    )

    if not auraOverlayEnabled or not auraAdvExpanded then
        return
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
        {"When enabled, one CDM-trackable aura can recolor each resource bar while that aura is active.", 1, 1, 1, true},
        " ",
        {"These settings are per-specialization. Select a resource in Custom Bars & Resources, then use the specialization tabs to edit each resource/spec overlay.", 1, 1, 1, true},
    }, auraHeading)

    auraHeading.right:ClearAllPoints()
    auraHeading.right:SetPoint("RIGHT", auraHeading.frame, "RIGHT", -3, 0)
    auraHeading.right:SetPoint("LEFT", auraInfoBtn, "RIGHT", 4, 0)

    if not auraCollapsed then
        local rbAuraOverlayAdvBtns = {}
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if pt ~= RESOURCE_HEALTH and not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if pt ~= RESOURCE_HEALTH and settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES[pt] or ("Power " .. pt)
                AddResourceAuraOverrideControls(container, settings, pt, resourceName, rbAuraOverlayAdvBtns)
            end
        end
    end
end

------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- Export via ST._RBP
------------------------------------------------------------------------

ST._RBP = {
    collapsedSections = resourceBarCollapsedSections,
    BuildResourceAuraOverlaySection = BuildResourceAuraOverlaySection,
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
    ResolveResourceOverlayAuraText = ResolveResourceOverlayAuraText,
    SetResourceAuraSpellIDConfig = SetResourceAuraSpellIDConfig,
    ClearResourceAuraIdentityConfig = ClearResourceAuraIdentityConfig,
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
    GetAuraBarAutocompleteDisplayName = GetAuraBarAutocompleteDisplayName,
    GetAuraBarAutocompleteDisplayIcon = GetAuraBarAutocompleteDisplayIcon,
    GetAuraBarAutocompleteEntryName = GetAuraBarAutocompleteEntryName,
    ResolveAuraBarAutocompleteEntry = ResolveAuraBarAutocompleteEntry,
    ShowAuraBarAutocompleteResults = ShowAuraBarAutocompleteResults,
    AddResourceAuraEntryFields = AddResourceAuraEntryFields,
    ClearLegacyResourceAuraFieldsConfig = ClearLegacyResourceAuraFieldsConfig,
    ClearResourceAuraEntryConfig = ClearResourceAuraEntryConfig,
    AddResourceAuraOverrideControls = AddResourceAuraOverrideControls,
    BuildAuraBarAutocompleteCache = BuildAuraBarAutocompleteCache,
    SupportsResourceAuraStackModeConfig = SupportsResourceAuraStackModeConfig,
    IsResourceBarVerticalConfig = IsResourceBarVerticalConfig,
    GetResourceThicknessFieldConfig = GetResourceThicknessFieldConfig,
    GetResourceGapFieldConfig = GetResourceGapFieldConfig,
}
