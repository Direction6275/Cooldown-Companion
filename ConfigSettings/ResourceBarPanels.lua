local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle

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

local SEGMENTED_TYPES_CONFIG = {
    [4]  = true, [5]  = true, [7]  = true, [9]  = true,
    [12] = true, [16] = true, [19] = true,
}

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
    [581] = { 18 },
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
        noGroupsLabel:SetText("No icon groups are currently enabled for this spec. Enable an icon group to anchor here.")
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
        local posDrop = AceGUI:Create("Dropdown")
        posDrop:SetLabel("Position")
        posDrop:SetList({ below = "Below Group", above = "Above Group" }, { "below", "above" })
        posDrop:SetValue(settings.position or "below")
        posDrop:SetFullWidth(true)
        posDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.position = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(posDrop)

        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-50, 50, 0.1)
        ySlider:SetValue(settings.yOffset or -3)
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

    -- Stack Order
    local stackDrop = AceGUI:Create("Dropdown")
    stackDrop:SetLabel("Stack Order")
    stackDrop:SetList({
        cast_first = "Cast Bar First",
        resource_first = "Resource Bars First",
    }, { "cast_first", "resource_first" })
    stackDrop:SetValue(settings.stackOrder or "resource_first")
    stackDrop:SetFullWidth(true)
    stackDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.stackOrder = val
        CooldownCompanion:UpdateAnchorStacking()
    end)
    container:AddChild(stackDrop)

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

        local flipCb = AceGUI:Create("CheckBox")
        flipCb:SetLabel("Flip primary and secondary bars")
        flipCb:SetValue(settings.reverseResourceOrder)
        flipCb:SetFullWidth(true)
        flipCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.reverseResourceOrder = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(flipCb)

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
    local rbAdvBtns = {}

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

    local rbTextAdvExpanded, rbTextAdvBtn = AddAdvancedToggle(textHeading, "rbText", rbAdvBtns)
    rbTextAdvBtn:SetPoint("LEFT", textCollapseBtn, "RIGHT", 4, 0)
    textHeading.right:ClearAllPoints()
    textHeading.right:SetPoint("RIGHT", textHeading.frame, "RIGHT", -3, 0)
    textHeading.right:SetPoint("LEFT", rbTextAdvBtn, "RIGHT", 4, 0)

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
                end)
                container:AddChild(cb)
            end
        end

        if rbTextAdvExpanded then
            local fontDrop = AceGUI:Create("Dropdown")
            fontDrop:SetLabel("Font")
            CS.SetupFontDropdown(fontDrop)
            fontDrop:SetValue(settings.textFont or "Friz Quadrata TT")
            fontDrop:SetFullWidth(true)
            fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.textFont = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(fontDrop)

            local sizeDrop = AceGUI:Create("Slider")
            sizeDrop:SetLabel("Font Size")
            sizeDrop:SetSliderValues(6, 24, 1)
            sizeDrop:SetValue(settings.textFontSize or 10)
            sizeDrop:SetFullWidth(true)
            sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.textFontSize = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(sizeDrop)

            local outlineDrop = AceGUI:Create("Dropdown")
            outlineDrop:SetLabel("Outline")
            outlineDrop:SetList(CS.outlineOptions)
            outlineDrop:SetValue(settings.textFontOutline or "OUTLINE")
            outlineDrop:SetFullWidth(true)
            outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.textFontOutline = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(outlineDrop)

            local textColorPicker = AceGUI:Create("ColorPicker")
            textColorPicker:SetLabel("Text Color")
            local tc = settings.textFontColor or { 1, 1, 1, 1 }
            textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
            textColorPicker:SetHasAlpha(true)
            textColorPicker:SetFullWidth(true)
            textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                settings.textFontColor = {r, g, b, a}
            end)
            textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                settings.textFontColor = {r, g, b, a}
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(textColorPicker)
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

                -- Overlay Color (overlay mode only)
                if cab.displayMode == "overlay" then
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
                end

                -- Show Text checkbox (continuous mode only)
                if cab.displayMode == "continuous" then
                    local textCb = AceGUI:Create("CheckBox")
                    textCb:SetLabel("Show Text")
                    textCb:SetValue(cab.showText == true)
                    textCb:SetFullWidth(true)
                    textCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showText = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(textCb)
                end
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

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
