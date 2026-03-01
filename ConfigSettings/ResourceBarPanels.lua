local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton

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
-- RESOURCE BAR: Anchoring Panel
------------------------------------------------------------------------

local resourceBarCollapsedSections = {}

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
local DEFAULT_RESOURCE_TEXT_FONT_CONFIG = "Friz Quadrata TT"
local DEFAULT_RESOURCE_TEXT_SIZE_CONFIG = 10
local DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG = "OUTLINE"
local DEFAULT_RESOURCE_TEXT_COLOR_CONFIG = { 1, 1, 1, 1 }

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

    local specIdx = C_SpecializationInfo.GetSpecialization()
    local specID
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

local function IsResourceAuraOverlayEnabledConfig(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
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

local function AddResourceAuraOverrideControls(container, settings, powerType, resourceName)
    if not settings.resources[powerType] then
        settings.resources[powerType] = {}
    end
    local res = settings.resources[powerType]

    local enableAuraOverlayCb = AceGUI:Create("CheckBox")
    enableAuraOverlayCb:SetLabel("Enable " .. resourceName .. " Aura Overlay")
    enableAuraOverlayCb:SetValue(IsResourceAuraOverlayEnabledConfig(res))
    enableAuraOverlayCb:SetFullWidth(true)
    enableAuraOverlayCb:SetCallback("OnValueChanged", function(widget, event, val)
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        settings.resources[powerType].auraOverlayEnabled = (val == true)
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableAuraOverlayCb)

    if not IsResourceAuraOverlayEnabledConfig(res) then
        return
    end

    local spellEdit = AceGUI:Create("EditBox")
    if spellEdit.editbox.Instructions then spellEdit.editbox.Instructions:Hide() end
    spellEdit:SetLabel(resourceName .. " Aura (Spell ID or Name)")
    spellEdit:SetText(res.auraColorSpellID and tostring(res.auraColorSpellID) or "")
    spellEdit:SetFullWidth(true)
    spellEdit:DisableButton(true)

    local function onAuraSelect(entry)
        CS.HideAutocomplete()
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        settings.resources[powerType].auraColorSpellID = entry.id
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end

    spellEdit:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        CS.HideAutocomplete()

        local id, explicitClear = ResolveAuraColorSpellIDFromText(text)
        if not id and not explicitClear then
            return
        end

        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        settings.resources[powerType].auraColorSpellID = id
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end)
    spellEdit:SetCallback("OnTextChanged", function(widget, event, text)
        if text and #text >= 1 then
            local cache = auraBarAutocompleteCache or BuildAuraBarAutocompleteCache()
            local results = CS.SearchAutocompleteInCache(text, cache)
            CS.ShowAutocompleteResults(results, widget, onAuraSelect)
        else
            CS.HideAutocomplete()
        end
    end)

    local editboxFrame = spellEdit.editbox
    if not editboxFrame._cdcAutocompHooked then
        editboxFrame._cdcAutocompHooked = true
        editboxFrame:HookScript("OnKeyDown", function(self, key)
            CS.HandleAutocompleteKeyDown(key)
        end)
    end

    container:AddChild(spellEdit)

    if res.auraColorSpellID then
        local auraName = C_Spell.GetSpellName(res.auraColorSpellID)
        if auraName then
            local auraLabel = AceGUI:Create("Label")
            auraLabel:SetText("|cff888888" .. auraName .. "|r")
            auraLabel:SetFullWidth(true)
            container:AddChild(auraLabel)
        end
    end

    local auraColorPicker = AceGUI:Create("ColorPicker")
    auraColorPicker:SetLabel(resourceName .. " Aura Active Color")
    local auraColor = res.auraActiveColor or DEFAULT_RESOURCE_AURA_ACTIVE_COLOR_CONFIG
    auraColorPicker:SetColor(auraColor[1], auraColor[2], auraColor[3])
    auraColorPicker:SetHasAlpha(false)
    auraColorPicker:SetFullWidth(true)
    auraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b)
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        settings.resources[powerType].auraActiveColor = { r, g, b }
    end)
    auraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
        if not settings.resources[powerType] then settings.resources[powerType] = {} end
        settings.resources[powerType].auraActiveColor = { r, g, b }
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(auraColorPicker)

    if SupportsResourceAuraStackModeConfig(powerType) then
        local trackingMode = GetResourceAuraTrackingModeConfig(res)
        local trackDrop = AceGUI:Create("Dropdown")
        trackDrop:SetLabel("Tracking Mode")
        trackDrop:SetList({
            stacks = "Stack Count",
            active = "Active (On/Off)",
        }, { "stacks", "active" })
        trackDrop:SetValue(trackingMode)
        trackDrop:SetFullWidth(true)
        trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
            if not settings.resources[powerType] then settings.resources[powerType] = {} end
            settings.resources[powerType].auraColorTrackingMode = val
            if val == "stacks" then
                local current = tonumber(settings.resources[powerType].auraColorMaxStacks)
                if not current or current < 2 then
                    settings.resources[powerType].auraColorMaxStacks = 2
                end
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(trackDrop)

        if trackingMode ~= "active" then
            local auraStackEdit = AceGUI:Create("EditBox")
            if auraStackEdit.editbox.Instructions then auraStackEdit.editbox.Instructions:Hide() end
            auraStackEdit:SetLabel(resourceName .. " Aura Max Stacks")
            auraStackEdit:SetText(res.auraColorMaxStacks and tostring(res.auraColorMaxStacks) or "")
            auraStackEdit:SetFullWidth(true)
            auraStackEdit:DisableButton(true)
            auraStackEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                if not settings.resources[powerType] then settings.resources[powerType] = {} end

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
                        local current = settings.resources[powerType].auraColorMaxStacks
                        widget:SetText(current and tostring(current) or "")
                        return
                    end
                end

                settings.resources[powerType].auraColorMaxStacks = parsed
                widget:SetText(parsed and tostring(parsed) or "")
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(auraStackEdit)

            local auraStackHint = AceGUI:Create("Label")
            auraStackHint:SetText("|cff888888Stack mode maps aura stacks to a bar proportion (e.g. 1/2 = half bar). Applies only to segmented/overlay resources.|r")
            auraStackHint:SetFullWidth(true)
            container:AddChild(auraStackHint)
        end
    end

end

local function BuildResourceBarAnchoringPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars

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

    if not settings.enabled then return end

    -- Anchor Group dropdown
    local groupDropValues = { [""] = "Auto (first available)" }
    local groupDropOrder = { "" }
    for groupId, group in pairs(db.groups) do
        if CooldownCompanion:IsGroupAvailableForAnchoring(groupId) then
            groupDropValues[tostring(groupId)] = group.name or ("Group " .. groupId)
            table.insert(groupDropOrder, tostring(groupId))
        end
    end

    local anchorDrop = AceGUI:Create("Dropdown")
    anchorDrop:SetLabel("Anchor to Group")
    anchorDrop:SetList(groupDropValues, groupDropOrder)
    anchorDrop:SetValue(settings.anchorGroupId and tostring(settings.anchorGroupId) or "")
    anchorDrop:SetFullWidth(true)
    anchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.anchorGroupId = val ~= "" and tonumber(val) or nil
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorDrop)

    if #groupDropOrder <= 1 then
        local noGroupsLabel = AceGUI:Create("Label")
        noGroupsLabel:SetText("No eligible character icon groups are enabled for this spec. Global groups are excluded from anchoring to avoid counterintuitive targets.")
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
        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(0, 50, 0.1)
        ySlider:SetValue(settings.yOffset or 3)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.yOffset = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(ySlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Bar Height")
        hSlider:SetSliderValues(4, 40, 0.1)
        hSlider:SetValue(settings.barHeight or 12)
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.barHeight = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        hSlider:SetDisabled(settings.customBarHeights or false)
        container:AddChild(hSlider)

        local customHeightsCb = AceGUI:Create("CheckBox")
        customHeightsCb:SetLabel("Custom Resource Bar Heights")
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
                    resHeightSlider:SetLabel("Bar Height")
                    resHeightSlider:SetSliderValues(4, 40, 0.1)
                    resHeightSlider:SetValue(settings.resources[pt].barHeight or settings.barHeight or 12)
                    resHeightSlider:SetFullWidth(true)
                    local capturedPt = pt
                    resHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        if not settings.resources[capturedPt] then
                            settings.resources[capturedPt] = {}
                        end
                        settings.resources[capturedPt].barHeight = val
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

local function BuildResourceBarStylingPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure styling.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

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
        -- Per-resource "Show Text" checkboxes (continuous bars only)
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not SEGMENTED_TYPES_CONFIG[pt] and pt ~= 100 then
                if not settings.resources[pt] then
                    settings.resources[pt] = {}
                end
                local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
                local cb = AceGUI:Create("CheckBox")
                cb:SetLabel("Show " .. name .. " Text")
                cb:SetValue(settings.resources[pt].showText ~= false)
                cb:SetFullWidth(true)
                cb:SetCallback("OnValueChanged", function(widget, event, val)
                    if not settings.resources[pt] then settings.resources[pt] = {} end
                    if val then
                        settings.resources[pt].showText = nil
                    else
                        settings.resources[pt].showText = false
                    end
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RefreshConfigPanel()
                end)
                container:AddChild(cb)

                local advExpanded = AddAdvancedToggle(cb, "rbText_" .. pt, rbTextAdvBtns, settings.resources[pt].showText ~= false)
                if advExpanded and settings.resources[pt].showText ~= false then
                    local resSettings = settings.resources[pt]

                    local textFormatDrop = AceGUI:Create("Dropdown")
                    textFormatDrop:SetLabel("Text Format")
                    local textFormatOptions = {
                        current = "Current Value",
                        current_max = "Current / Max",
                        percent = "Percent",
                    }
                    local textFormatOrder = { "current", "current_max", "percent" }
                    textFormatDrop:SetList(textFormatOptions, textFormatOrder)
                    local textFormatValue = resSettings.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" and textFormatValue ~= "percent" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
                    end
                    textFormatDrop:SetValue(textFormatValue)
                    textFormatDrop:SetFullWidth(true)
                    textFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        if val == "current" or val == "current_max" or val == "percent" then
                            settings.resources[pt].textFormat = val
                        else
                            settings.resources[pt].textFormat = DEFAULT_RESOURCE_TEXT_FORMAT_CONFIG
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
                        settings.resources[pt].textFont = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(fontDrop)

                    local sizeDrop = AceGUI:Create("Slider")
                    sizeDrop:SetLabel("Font Size")
                    sizeDrop:SetSliderValues(6, 24, 1)
                    sizeDrop:SetValue(resSettings.textFontSize or DEFAULT_RESOURCE_TEXT_SIZE_CONFIG)
                    sizeDrop:SetFullWidth(true)
                    sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        settings.resources[pt].textFontSize = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(sizeDrop)

                    local outlineDrop = AceGUI:Create("Dropdown")
                    outlineDrop:SetLabel("Outline")
                    outlineDrop:SetList(CS.outlineOptions)
                    outlineDrop:SetValue(resSettings.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE_CONFIG)
                    outlineDrop:SetFullWidth(true)
                    outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        settings.resources[pt].textFontOutline = val
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
                        settings.resources[pt].textFontColor = {r, g, b, a}
                    end)
                    textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        settings.resources[pt].textFontColor = {r, g, b, a}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(textColorPicker)
                end
            end
        end
    end

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

    -- ============ Per-Resource Aura Overlays Section ============
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
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            if settings.resources[pt].enabled ~= false then
                local resourceName = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
                AddResourceAuraOverrideControls(container, settings, pt, resourceName)
            end
        end
    end

end

------------------------------------------------------------------------
-- Custom Aura Bar Panel (col2 takeover when resource bar panel active)
------------------------------------------------------------------------

local function BuildCustomAuraBarPanel(container)
    auraBarAutocompleteCache = nil
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local maxSlots = ST.MAX_CUSTOM_AURA_BARS or 3
    local rbCabTextAdvBtns = {}

    -- Spec label
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        if specName then
            local specLabel = AceGUI:Create("Label")
            specLabel:SetText("|T" .. specIcon .. ":14:14:0:0|t  Configuring: |cffffd100" .. specName .. "|r")
            specLabel:SetFullWidth(true)
            specLabel:SetFontObject(GameFontNormal)
            container:AddChild(specLabel)

            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            container:AddChild(spacer)
        end
    end

    for slotIdx = 1, maxSlots do
        if not customBars[slotIdx] then
            customBars[slotIdx] = { enabled = false }
        end
        local cab = customBars[slotIdx]

        local slotKey = "rb_cab_slot_" .. slotIdx
        local slotCollapsed = resourceBarCollapsedSections[slotKey]
        local slotHeadingText = "Slot " .. slotIdx
        if cab.enabled then
            local slotLabel = cab.label or ""
            if cab.spellID then
                local spellName = C_Spell.GetSpellName(cab.spellID)
                if spellName then slotLabel = spellName end
            end
            if slotLabel == "" then slotLabel = "Empty" end
            slotHeadingText = slotHeadingText .. ": " .. slotLabel
        end

        local slotHeading = AceGUI:Create("Heading")
        slotHeading:SetText(slotHeadingText)
        ColorHeading(slotHeading)
        slotHeading:SetFullWidth(true)
        container:AddChild(slotHeading)

        local capturedSlotKey = slotKey
        AttachCollapseButton(slotHeading, slotCollapsed, function()
            resourceBarCollapsedSections[capturedSlotKey] = not resourceBarCollapsedSections[capturedSlotKey]
            CooldownCompanion:RefreshConfigPanel()
        end)

        if not slotCollapsed then
            local capturedIdx = slotIdx

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

            local editboxFrame = spellEdit.editbox
            if not editboxFrame._cdcAutocompHooked then
                editboxFrame._cdcAutocompHooked = true
                editboxFrame:HookScript("OnKeyDown", function(self, key)
                    CS.HandleAutocompleteKeyDown(key)
                end)
            end

            container:AddChild(spellEdit)

            -- Label (read-only display)
            if cab.spellID then
                local spellName = C_Spell.GetSpellName(cab.spellID)
                if spellName then
                    local labelDisplay = AceGUI:Create("Label")
                    labelDisplay:SetText("|cff888888" .. spellName .. "|r")
                    labelDisplay:SetFullWidth(true)
                    container:AddChild(labelDisplay)
                end
            end

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

            -- Per-slot bar height override
            if settings.customBarHeights then
                local cabHeightSlider = AceGUI:Create("Slider")
                cabHeightSlider:SetLabel("Bar Height")
                cabHeightSlider:SetSliderValues(4, 40, 0.1)
                cabHeightSlider:SetValue(cab.barHeight or settings.barHeight or 12)
                cabHeightSlider:SetFullWidth(true)
                local cabIdx = capturedIdx
                cabHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    customBars[cabIdx].barHeight = val
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
                    end

                    local stackAdvExpanded = AddAdvancedToggle(stackTextCb, "rbCabStackText_" .. capturedIdx, rbCabTextAdvBtns, showStack)
                    if stackAdvExpanded and showStack then
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
            end
            end -- if cab.enabled
        end
    end

    -- "Copy from..." button
    local _, _, classID = UnitClass("player")
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    local currentSpecID
    if specIdx then
        currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end
    if currentSpecID and numSpecs and numSpecs > 1 then
        local copySpacer = AceGUI:Create("Label")
        copySpacer:SetText(" ")
        copySpacer:SetFullWidth(true)
        container:AddChild(copySpacer)

        local copyBtn = AceGUI:Create("Button")
        copyBtn:SetText("Copy from\226\128\166")
        copyBtn:SetFullWidth(true)
        copyBtn:SetCallback("OnClick", function()
            local menuFrame = _G["CDCCopyCABMenu"]
            if not menuFrame then
                menuFrame = CreateFrame("Frame", "CDCCopyCABMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(menuFrame, function(self, level)
                for i = 1, numSpecs do
                    local sID, sName, _, sIcon = GetSpecializationInfoForClassID(classID, i)
                    if sID and sID ~= currentSpecID then
                        local info = UIDropDownMenu_CreateInfo()
                        local sourceBars = settings.customAuraBars and settings.customAuraBars[sID]
                        local hasData = false
                        if sourceBars then
                            for _, cab in ipairs(sourceBars) do
                                if cab.enabled and cab.spellID then hasData = true; break end
                            end
                        end
                        info.text = "|T" .. sIcon .. ":14:14:0:0|t " .. sName
                        info.disabled = not hasData
                        info.func = function()
                            settings.customAuraBars[currentSpecID] = CopyTable(sourceBars)
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:UpdateAnchorStacking()
                            CooldownCompanion:RefreshConfigPanel()
                            CloseDropDownMenus()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end, "MENU")
            menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
        end)
        container:AddChild(copyBtn)
    end
end

------------------------------------------------------------------------
-- Layout & Order panel: per-element position/order control
------------------------------------------------------------------------

local function BuildLayoutOrderPanel(container)
    local db = CooldownCompanion.db.profile
    local rbSettings = db.resourceBars
    local cbSettings = db.castBar

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

    local allSlots = {}

    -- Class resource slots
    for _, pt in ipairs(activeResources) do
        if not rbSettings.resources then rbSettings.resources = {} end
        if not rbSettings.resources[pt] then rbSettings.resources[pt] = {} end
        local res = rbSettings.resources[pt]
        local showResource = res.enabled ~= false
        -- Apply hideManaForNonHealer, matching ApplyResourceBars filtering
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
            table.insert(allSlots, {
                label = name,
                color = GetResourceColor(pt),
                getPos = function() return rbSettings.resources[pt].position or "below" end,
                getOrder = function() return rbSettings.resources[pt].order or 1 end,
                setPos = function(v) rbSettings.resources[pt].position = v end,
                setOrder = function(v) rbSettings.resources[pt].order = v end,
            })
        end
    end

    -- Custom aura bar slots
    for slotIdx = 1, MAX_SLOTS do
        local cab = customBars and customBars[slotIdx]
        if cab and cab.enabled and cab.spellID then
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
            table.insert(allSlots, {
                label = slotName,
                color = cab.barColor or {0.5, 0.5, 1},
                getPos = function() return rbSettings.customAuraBarSlots[captured].position or "below" end,
                getOrder = function() return rbSettings.customAuraBarSlots[captured].order or (1000 + captured) end,
                setPos = function(v) rbSettings.customAuraBarSlots[captured].position = v end,
                setOrder = function(v) rbSettings.customAuraBarSlots[captured].order = v end,
            })
        end
    end

    -- Cast bar slot (if enabled and anchored to same group)
    if cbSettings and cbSettings.enabled then
        local defaultAnchor = CooldownCompanion:GetFirstAvailableAnchorGroup()
        local cbAnchor = cbSettings.anchorGroupId or defaultAnchor
        local rbAnchor = rbSettings.anchorGroupId or defaultAnchor
        if cbAnchor and cbAnchor == rbAnchor then
            local cbColor = cbSettings.barColor or { 1.0, 0.7, 0.0 }
            table.insert(allSlots, {
                label = "Cast Bar",
                color = cbColor,
                getPos = function() return db.castBar.position or "below" end,
                getOrder = function() return db.castBar.order or 2000 end,
                setPos = function(v) db.castBar.position = v end,
                setOrder = function(v) db.castBar.order = v end,
            })
        end
    end

    if #allSlots == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No active bars to order. Enable resources or custom aura bars first.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Helper: refresh after any order/position change
    local function ApplyAndRefresh()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end

    -- Sort all slots by (side, order): above slots first (in reverse order = top down), then below
    -- For display we show: above bars (furthest first = highest order), divider, below bars (closest first = lowest order)
    local aboveSlots = {}
    local belowSlots = {}
    for _, slot in ipairs(allSlots) do
        if slot.getPos() == "above" then
            table.insert(aboveSlots, slot)
        else
            table.insert(belowSlots, slot)
        end
    end
    table.sort(aboveSlots, function(a, b) return a.getOrder() > b.getOrder() end)  -- furthest first (top of screen)
    table.sort(belowSlots, function(a, b) return a.getOrder() < b.getOrder() end)  -- closest first

    -- Build ordered display list: above (top-screen order) then below (top-to-bottom)
    local displayList = {}
    for _, s in ipairs(aboveSlots) do table.insert(displayList, s) end
    local dividerIdx = #displayList + 1  -- where the group frame divider goes
    for _, s in ipairs(belowSlots) do table.insert(displayList, s) end

    -- Render rows
    for rowIdx, slot in ipairs(displayList) do
        -- Insert icons divider between above and below sections
        if rowIdx == dividerIdx then
            local divLabel = AceGUI:Create("Heading")
            divLabel:SetText("Icons")
            divLabel:SetFullWidth(true)
            container:AddChild(divLabel)
        end

        -- Row: Name  [Up][Down]
        local rowGroup = AceGUI:Create("SimpleGroup")
        rowGroup:SetLayout("Flow")
        rowGroup:SetFullWidth(true)
        container:AddChild(rowGroup)

        -- Slot name label (colored to match resource/bar color)
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

        -- Up button
        local upBtn = AceGUI:Create("Button")
        upBtn:SetText("Up")
        upBtn:SetRelativeWidth(0.20)
        upBtn:SetDisabled(rowIdx == 1 and slot.getPos() == "above")
        upBtn:SetCallback("OnClick", function()
            -- Swap order with the slot above in display order
            local prev = displayList[rowIdx - 1]
            if prev and prev.getPos() == slot.getPos() then
                -- Same side: swap orders
                local myOrder = slot.getOrder()
                local prevOrder = prev.getOrder()
                slot.setOrder(prevOrder)
                prev.setOrder(myOrder)
            else
                -- Crossing the group-frame boundary (below to above):
                -- slot should become the closest-to-group above bar (displayed last, just above divider)
                local minAbove
                for _, s in ipairs(aboveSlots) do
                    local o = s.getOrder()
                    if not minAbove or o < minAbove then minAbove = o end
                end
                slot.setPos("above")
                slot.setOrder(minAbove and (minAbove - 1) or 1)
            end
            ApplyAndRefresh()
        end)
        rowGroup:AddChild(upBtn)

        -- Down button
        local downBtn = AceGUI:Create("Button")
        downBtn:SetText("Down")
        downBtn:SetRelativeWidth(0.24)
        downBtn:SetDisabled(rowIdx == #displayList and slot.getPos() == "below")
        downBtn:SetCallback("OnClick", function()
            local nextSlot = displayList[rowIdx + 1]
            if nextSlot and nextSlot.getPos() == slot.getPos() then
                -- Same side: swap orders
                local myOrder = slot.getOrder()
                local nextOrder = nextSlot.getOrder()
                slot.setOrder(nextOrder)
                nextSlot.setOrder(myOrder)
            else
                -- Crossing boundary (only above to below is reachable via Down)
                local minBelow
                for _, s in ipairs(belowSlots) do
                    local o = s.getOrder()
                    if not minBelow or o < minBelow then minBelow = o end
                end
                slot.setPos("below")
                slot.setOrder(minBelow and (minBelow - 1) or 1)
            end
            ApplyAndRefresh()
        end)
        rowGroup:AddChild(downBtn)
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
