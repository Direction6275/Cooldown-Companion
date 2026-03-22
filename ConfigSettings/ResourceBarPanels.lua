--[[
    CooldownCompanion - ResourceBarPanels
    Config panel builders for resource bar settings: anchoring, appearance,
    per-resource styling, custom aura bar panels, and layout order.
    Query helpers and shared builders live in ResourceBarPanelsHelpers.lua.
]]

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
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local tabInfoButtons = CS.tabInfoButtons

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local HIDE_AT_ZERO_ELIGIBLE = RB.HIDE_AT_ZERO_ELIGIBLE
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_MW_OVERLAY_COLOR = RB.DEFAULT_MW_OVERLAY_COLOR
local DEFAULT_MW_MAX_COLOR = RB.DEFAULT_MW_MAX_COLOR
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR
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

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local BuildResourceAuraOverlaySection = RBP.BuildResourceAuraOverlaySection
local GetConfigActiveResources = RBP.GetConfigActiveResources
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ReadSpecOverrideKey = RBP.ReadSpecOverrideKey
local WriteSpecOverrideKey = RBP.WriteSpecOverrideKey
local GetSafeRGBConfig = RBP.GetSafeRGBConfig
local GetSafeRGBAConfig = RBP.GetSafeRGBAConfig
local GetSegmentedThresholdValueConfig = RBP.GetSegmentedThresholdValueConfig
local GetContinuousTickModeConfig = RBP.GetContinuousTickModeConfig
local GetContinuousTickPercentConfig = RBP.GetContinuousTickPercentConfig
local GetContinuousTickAbsoluteConfig = RBP.GetContinuousTickAbsoluteConfig
local AddCdmAuraReadinessWarning = RBP.AddCdmAuraReadinessWarning
local BuildAuraBarAutocompleteCache = RBP.BuildAuraBarAutocompleteCache
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local GetResourceGapFieldConfig = RBP.GetResourceGapFieldConfig

local ResolveSpecOverrideKey = ST._ResolveSpecOverrideKey

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
            local name = POWER_NAMES[pt] or ("Power " .. pt)
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
    local showAuraOverlays = (mode == "all" or mode == "colors") -- aura overlays merged into Colors tab

    local applyBars = function() CooldownCompanion:ApplyResourceBars() end

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
    AddColorPicker(container, settings, "backgroundColor", "Background Color", { 0, 0, 0, 0.5 }, true, applyBars)

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
        AddColorPicker(container, settings, "borderColor", "Border Color", { 0, 0, 0, 1 }, true, applyBars)

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
            local isSegmentedResource = (SEGMENTED_TYPES[capturedPt] == true) or (capturedPt == 100)
            if not settings.resources[capturedPt] then
                settings.resources[capturedPt] = {}
            end
            local resSettings = settings.resources[capturedPt]
            local name = POWER_NAMES[capturedPt] or ("Power " .. capturedPt)

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
                local textFormatValue = resSettings.textFormat or DEFAULT_RESOURCE_TEXT_FORMAT
                if isSegmentedResource then
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT
                    end
                else
                    if textFormatValue ~= "current" and textFormatValue ~= "current_max" and textFormatValue ~= "percent" then
                        textFormatValue = DEFAULT_RESOURCE_TEXT_FORMAT
                    end
                end
                textFormatDrop:SetValue(textFormatValue)
                textFormatDrop:SetFullWidth(true)
                textFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    if isSegmentedResource then
                        if val == "current" or val == "current_max" then
                            settings.resources[capturedPt].textFormat = val
                        else
                            settings.resources[capturedPt].textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
                        end
                    else
                        if val == "current" or val == "current_max" or val == "percent" then
                            settings.resources[capturedPt].textFormat = val
                        else
                            settings.resources[capturedPt].textFormat = DEFAULT_RESOURCE_TEXT_FORMAT
                        end
                    end
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textFormatDrop)

                local fontDrop = AceGUI:Create("Dropdown")
                fontDrop:SetLabel("Font")
                CS.SetupFontDropdown(fontDrop)
                fontDrop:SetValue(resSettings.textFont or DEFAULT_RESOURCE_TEXT_FONT)
                fontDrop:SetFullWidth(true)
                fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFont = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(fontDrop)

                local sizeDrop = AceGUI:Create("Slider")
                sizeDrop:SetLabel("Font Size")
                sizeDrop:SetSliderValues(6, 24, 1)
                sizeDrop:SetValue(resSettings.textFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                sizeDrop:SetFullWidth(true)
                sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFontSize = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(sizeDrop)

                local outlineDrop = AceGUI:Create("Dropdown")
                outlineDrop:SetLabel("Outline")
                outlineDrop:SetList(CS.outlineOptions)
                outlineDrop:SetValue(resSettings.textFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                outlineDrop:SetFullWidth(true)
                outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textFontOutline = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(outlineDrop)

                AddColorPicker(container, settings.resources[capturedPt], "textFontColor", "Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, applyBars)

                local textAnchorDrop = AceGUI:Create("Dropdown")
                textAnchorDrop:SetLabel("Text Anchor")
                local textAnchorValues = {}
                for _, pt in ipairs(CS.anchorPoints) do
                    textAnchorValues[pt] = CS.anchorPointLabels[pt]
                end
                textAnchorDrop:SetList(textAnchorValues, CS.anchorPoints)
                textAnchorDrop:SetValue(resSettings.textAnchor or DEFAULT_RESOURCE_TEXT_ANCHOR)
                textAnchorDrop:SetFullWidth(true)
                textAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textAnchor = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textAnchorDrop)

                local textXSlider = AceGUI:Create("Slider")
                textXSlider:SetLabel("Text X Offset")
                textXSlider:SetSliderValues(-50, 50, 0.1)
                textXSlider:SetValue(resSettings.textXOffset or DEFAULT_RESOURCE_TEXT_X_OFFSET)
                textXSlider:SetFullWidth(true)
                textXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textXOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textXSlider)

                local textYSlider = AceGUI:Create("Slider")
                textYSlider:SetLabel("Text Y Offset")
                textYSlider:SetSliderValues(-50, 50, 0.1)
                textYSlider:SetValue(resSettings.textYOffset or DEFAULT_RESOURCE_TEXT_Y_OFFSET)
                textYSlider:SetFullWidth(true)
                textYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.resources[capturedPt].textYOffset = val
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(textYSlider)

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

    local colorCollapseBtn = AttachCollapseButton(colorHeading, colorCollapsed, function()
        resourceBarCollapsedSections[colorKey] = not resourceBarCollapsedSections[colorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local colorInfoBtn = CreateInfoButton(colorHeading.frame, colorCollapseBtn, "LEFT", "RIGHT", 4, 0, {
        "Per-Resource Colors",
        {"These color settings are per-specialization. Switch specs to configure different colors.", 1, 1, 1, true},
    }, colorHeading)

    colorHeading.right:ClearAllPoints()
    colorHeading.right:SetPoint("RIGHT", colorHeading.frame, "RIGHT", -3, 0)
    colorHeading.right:SetPoint("LEFT", colorInfoBtn, "RIGHT", 4, 0)

    local _colorSpecID = GetCurrentConfigSpecID()

    if not _colorSpecID and not colorCollapsed then
        local specUnavailLabel = AceGUI:Create("Label")
        specUnavailLabel:SetText("Specialization data not yet available.")
        specUnavailLabel:SetFullWidth(true)
        container:AddChild(specUnavailLabel)
    end

    if not colorCollapsed and _colorSpecID then
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end

            if pt == 4 then
                -- Combo Points: two color pickers (normal vs at max)
                local _p4n = { comboColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", DEFAULT_COMBO_COLOR) }
                AddColorPicker(container, _p4n, "comboColor", "Combo Points", DEFAULT_COMBO_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", _p4n.comboColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboColor", _p4n.comboColor) end)

                local _p4m = { comboMaxColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", DEFAULT_COMBO_MAX_COLOR) }
                AddColorPicker(container, _p4m, "comboMaxColor", "Combo Points (Max)", DEFAULT_COMBO_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", _p4m.comboMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboMaxColor", _p4m.comboMaxColor) end)

                -- Charged combo point color (Rogue only)
                local _, _, classID = UnitClass("player")
                if classID == 4 then
                    local _p4c = { comboChargedColor = ReadSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", DEFAULT_COMBO_CHARGED_COLOR) }
                    AddColorPicker(container, _p4c, "comboChargedColor", "Combo Points (Charged)", DEFAULT_COMBO_CHARGED_COLOR, false,
                        function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", _p4c.comboChargedColor); applyBars() end,
                        function() WriteSpecOverrideKey(settings, 4, _colorSpecID, "comboChargedColor", _p4c.comboChargedColor) end)
                end
            elseif pt == 5 then
                -- Runes: three color pickers (ready, recharging, max)
                local _p5r = { runeReadyColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", DEFAULT_RUNE_READY_COLOR) }
                AddColorPicker(container, _p5r, "runeReadyColor", "Runes (Ready)", DEFAULT_RUNE_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", _p5r.runeReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeReadyColor", _p5r.runeReadyColor) end)

                local _p5c = { runeRechargingColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", DEFAULT_RUNE_RECHARGING_COLOR) }
                AddColorPicker(container, _p5c, "runeRechargingColor", "Runes (Recharging)", DEFAULT_RUNE_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", _p5c.runeRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeRechargingColor", _p5c.runeRechargingColor) end)

                local _p5m = { runeMaxColor = ReadSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", DEFAULT_RUNE_MAX_COLOR) }
                AddColorPicker(container, _p5m, "runeMaxColor", "Runes (All Ready)", DEFAULT_RUNE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", _p5m.runeMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 5, _colorSpecID, "runeMaxColor", _p5m.runeMaxColor) end)
            elseif pt == 7 then
                -- Soul Shards: three color pickers (ready, recharging, max)
                local _p7r = { shardReadyColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", DEFAULT_SHARD_READY_COLOR) }
                AddColorPicker(container, _p7r, "shardReadyColor", "Soul Shards (Ready)", DEFAULT_SHARD_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", _p7r.shardReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardReadyColor", _p7r.shardReadyColor) end)

                local _p7c = { shardRechargingColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", DEFAULT_SHARD_RECHARGING_COLOR) }
                AddColorPicker(container, _p7c, "shardRechargingColor", "Soul Shards (Recharging)", DEFAULT_SHARD_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", _p7c.shardRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardRechargingColor", _p7c.shardRechargingColor) end)

                local _p7m = { shardMaxColor = ReadSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", DEFAULT_SHARD_MAX_COLOR) }
                AddColorPicker(container, _p7m, "shardMaxColor", "Soul Shards (Max)", DEFAULT_SHARD_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", _p7m.shardMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 7, _colorSpecID, "shardMaxColor", _p7m.shardMaxColor) end)
            elseif pt == 9 then
                -- Holy Power: two color pickers (normal vs max)
                local _p9n = { holyColor = ReadSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", DEFAULT_HOLY_COLOR) }
                AddColorPicker(container, _p9n, "holyColor", "Holy Power", DEFAULT_HOLY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", _p9n.holyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyColor", _p9n.holyColor) end)

                local _p9m = { holyMaxColor = ReadSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", DEFAULT_HOLY_MAX_COLOR) }
                AddColorPicker(container, _p9m, "holyMaxColor", "Holy Power (Max)", DEFAULT_HOLY_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", _p9m.holyMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 9, _colorSpecID, "holyMaxColor", _p9m.holyMaxColor) end)
            elseif pt == 12 then
                -- Chi: two color pickers (normal vs max)
                local _p12n = { chiColor = ReadSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", DEFAULT_CHI_COLOR) }
                AddColorPicker(container, _p12n, "chiColor", "Chi", DEFAULT_CHI_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", _p12n.chiColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiColor", _p12n.chiColor) end)

                local _p12m = { chiMaxColor = ReadSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", DEFAULT_CHI_MAX_COLOR) }
                AddColorPicker(container, _p12m, "chiMaxColor", "Chi (Max)", DEFAULT_CHI_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", _p12m.chiMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 12, _colorSpecID, "chiMaxColor", _p12m.chiMaxColor) end)
            elseif pt == 16 then
                -- Arcane Charges: two color pickers (normal vs max)
                local _p16n = { arcaneColor = ReadSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", DEFAULT_ARCANE_COLOR) }
                AddColorPicker(container, _p16n, "arcaneColor", "Arcane Charges", DEFAULT_ARCANE_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", _p16n.arcaneColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneColor", _p16n.arcaneColor) end)

                local _p16m = { arcaneMaxColor = ReadSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", DEFAULT_ARCANE_MAX_COLOR) }
                AddColorPicker(container, _p16m, "arcaneMaxColor", "Arcane Charges (Max)", DEFAULT_ARCANE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", _p16m.arcaneMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 16, _colorSpecID, "arcaneMaxColor", _p16m.arcaneMaxColor) end)
            elseif pt == 19 then
                -- Essence: three color pickers (ready, recharging, max)
                local _p19r = { essenceReadyColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", DEFAULT_ESSENCE_READY_COLOR) }
                AddColorPicker(container, _p19r, "essenceReadyColor", "Essence (Ready)", DEFAULT_ESSENCE_READY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", _p19r.essenceReadyColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceReadyColor", _p19r.essenceReadyColor) end)

                local _p19c = { essenceRechargingColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", DEFAULT_ESSENCE_RECHARGING_COLOR) }
                AddColorPicker(container, _p19c, "essenceRechargingColor", "Essence (Recharging)", DEFAULT_ESSENCE_RECHARGING_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", _p19c.essenceRechargingColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceRechargingColor", _p19c.essenceRechargingColor) end)

                local _p19m = { essenceMaxColor = ReadSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", DEFAULT_ESSENCE_MAX_COLOR) }
                AddColorPicker(container, _p19m, "essenceMaxColor", "Essence (Max)", DEFAULT_ESSENCE_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", _p19m.essenceMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 19, _colorSpecID, "essenceMaxColor", _p19m.essenceMaxColor) end)
            elseif pt == 100 then
                -- Maelstrom Weapon: three color pickers (base, overlay, max)
                local _p100b = { mwBaseColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", DEFAULT_MW_BASE_COLOR) }
                AddColorPicker(container, _p100b, "mwBaseColor", "MW (Base)", DEFAULT_MW_BASE_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", _p100b.mwBaseColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwBaseColor", _p100b.mwBaseColor) end)

                local _p100o = { mwOverlayColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", DEFAULT_MW_OVERLAY_COLOR) }
                AddColorPicker(container, _p100o, "mwOverlayColor", "MW (Overlay)", DEFAULT_MW_OVERLAY_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", _p100o.mwOverlayColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwOverlayColor", _p100o.mwOverlayColor) end)

                local _p100m = { mwMaxColor = ReadSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", DEFAULT_MW_MAX_COLOR) }
                AddColorPicker(container, _p100m, "mwMaxColor", "MW (Max)", DEFAULT_MW_MAX_COLOR, false,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", _p100m.mwMaxColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 100, _colorSpecID, "mwMaxColor", _p100m.mwMaxColor) end)
            elseif pt == 101 then
                -- Stagger: three color pickers (green/yellow/red thresholds)
                local _p101g = { staggerGreenColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", { 0.52, 0.90, 0.52 }) }
                AddColorPicker(container, _p101g, "staggerGreenColor", "Stagger (Low)", { 0.52, 0.90, 0.52 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", _p101g.staggerGreenColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerGreenColor", _p101g.staggerGreenColor) end)

                local _p101y = { staggerYellowColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", { 1.0, 0.85, 0.36 }) }
                AddColorPicker(container, _p101y, "staggerYellowColor", "Stagger (Medium)", { 1.0, 0.85, 0.36 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", _p101y.staggerYellowColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerYellowColor", _p101y.staggerYellowColor) end)

                local _p101r = { staggerRedColor = ReadSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", { 1.0, 0.42, 0.42 }) }
                AddColorPicker(container, _p101r, "staggerRedColor", "Stagger (High)", { 1.0, 0.42, 0.42 }, false,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", _p101r.staggerRedColor); applyBars() end,
                    function() WriteSpecOverrideKey(settings, 101, _colorSpecID, "staggerRedColor", _p101r.staggerRedColor) end)
            else
                local name = POWER_NAMES[pt] or ("Power " .. pt)

                if settings.barTexture == "blizzard_class" and ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[pt] then
                    -- Atlas-backed type; color picker not applicable
                else
                    local capturedGenericPt = pt
                    local _pGen = { color = ReadSpecOverrideKey(settings, pt, _colorSpecID, "color", DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 }) }
                    AddColorPicker(container, _pGen, "color", name, DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 }, false,
                        function() WriteSpecOverrideKey(settings, capturedGenericPt, _colorSpecID, "color", _pGen.color); applyBars() end,
                        function() WriteSpecOverrideKey(settings, capturedGenericPt, _colorSpecID, "color", _pGen.color) end)
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
                local resourceName = POWER_NAMES[pt] or ("Power " .. pt)
                local capturedPt = pt
                local res = settings.resources[capturedPt]
                local isSegmented = SEGMENTED_TYPES[capturedPt] == true or capturedPt == 100

                if isSegmented then
                    local thresholdAdvKey = "rbSegThreshold_" .. capturedPt
                    local thresholdEnableCb = AceGUI:Create("CheckBox")
                    thresholdEnableCb:SetLabel("Enable " .. resourceName .. " Threshold Color")
                    thresholdEnableCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true)
                    thresholdEnableCb:SetFullWidth(true)
                    thresholdEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", val == true)
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

                    local _segEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdEnabled", false) == true
                    local thresholdAdvExpanded = AddAdvancedToggle(
                        thresholdEnableCb,
                        thresholdAdvKey,
                        rbThresholdTickAdvBtns,
                        _segEnabled
                    )
                    if _segEnabled and thresholdAdvExpanded then
                        local thresholdEdit = AceGUI:Create("EditBox")
                        if thresholdEdit.editbox.Instructions then thresholdEdit.editbox.Instructions:Hide() end
                        thresholdEdit:SetLabel(resourceName .. " Threshold Value (>=)")
                        local _segVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", nil)
                        thresholdEdit:SetText(tostring(GetSegmentedThresholdValueConfig({ segThresholdValue = _segVal })))
                        thresholdEdit:SetFullWidth(true)
                        thresholdEdit:DisableButton(true)
                        thresholdEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                            local parsed = tonumber(text)
                            if not parsed then
                                local curVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", nil)
                                widget:SetText(tostring(GetSegmentedThresholdValueConfig({ segThresholdValue = curVal })))
                                return
                            end
                            parsed = math.floor(parsed)
                            if parsed < 1 then
                                parsed = 1
                            elseif parsed > 99 then
                                parsed = 99
                            end
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdValue", parsed)
                            widget:SetText(tostring(parsed))
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(thresholdEdit)

                        local _pSeg = { segThresholdColor = GetSafeRGBConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", nil), DEFAULT_SEG_THRESHOLD_COLOR) }
                        AddColorPicker(container, _pSeg, "segThresholdColor", resourceName .. " Threshold Color", DEFAULT_SEG_THRESHOLD_COLOR, false,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor); applyBars() end,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "segThresholdColor", _pSeg.segThresholdColor) end)
                    end
                elseif capturedPt ~= 101 then
                    -- Stagger (101) has built-in threshold coloring; tick markers not applicable
                    local tickAdvKey = "rbTickMarker_" .. capturedPt
                    local _tickEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                    local tickEnableCb = AceGUI:Create("CheckBox")
                    tickEnableCb:SetLabel("Enable " .. resourceName .. " Tick Marker")
                    tickEnableCb:SetValue(_tickEnabled)
                    tickEnableCb:SetFullWidth(true)
                    tickEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
                        local wasEnabled = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", false) == true
                        WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickEnabled", val == true)
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

                    if _tickEnabled then
                        local tickCombatCb = AceGUI:Create("CheckBox")
                        tickCombatCb:SetLabel("Show Only In Combat")
                        tickCombatCb:SetValue(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", false))
                        tickCombatCb:SetFullWidth(true)
                        tickCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickCombatOnly", val == true)
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(tickCombatCb)
                        ApplyCheckboxIndent(tickCombatCb, 20)
                    end

                    local tickAdvExpanded = AddAdvancedToggle(
                        tickEnableCb,
                        tickAdvKey,
                        rbThresholdTickAdvBtns,
                        _tickEnabled
                    )
                    if _tickEnabled and tickAdvExpanded then
                        local _tickModeRes = { continuousTickMode = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", nil) }
                        local tickMode = GetContinuousTickModeConfig(_tickModeRes)
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
                                val = DEFAULT_CONTINUOUS_TICK_MODE
                            end
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickMode", val)
                            CooldownCompanion:ApplyResourceBars()
                            C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
                        end)
                        container:AddChild(modeDrop)

                        if tickMode == "percent" then
                            local _tickPercentRes = { continuousTickPercent = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickPercent", nil) }
                            local percentSlider = AceGUI:Create("Slider")
                            percentSlider:SetLabel(resourceName .. " Tick Percent")
                            percentSlider:SetSliderValues(0, 100, 1)
                            percentSlider:SetValue(GetContinuousTickPercentConfig(_tickPercentRes))
                            percentSlider:SetIsPercent(false)
                            percentSlider:SetFullWidth(true)
                            percentSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickPercent", val)
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(percentSlider)
                        else
                            local _tickAbsRes = { continuousTickAbsolute = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", nil) }
                            local absoluteEdit = AceGUI:Create("EditBox")
                            if absoluteEdit.editbox.Instructions then absoluteEdit.editbox.Instructions:Hide() end
                            absoluteEdit:SetLabel(resourceName .. " Tick Absolute Value")
                            absoluteEdit:SetText(tostring(GetContinuousTickAbsoluteConfig(_tickAbsRes)))
                            absoluteEdit:SetFullWidth(true)
                            absoluteEdit:DisableButton(true)
                            absoluteEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                                local parsed = tonumber(text)
                                if not parsed then
                                    local curAbs = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", nil)
                                    widget:SetText(tostring(GetContinuousTickAbsoluteConfig({ continuousTickAbsolute = curAbs })))
                                    return
                                end
                                if parsed < 0 then
                                    parsed = 0
                                end
                                WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickAbsolute", parsed)
                                widget:SetText(tostring(parsed))
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(absoluteEdit)
                        end

                        local _tickColorResolved = GetSafeRGBAConfig(ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", nil), DEFAULT_CONTINUOUS_TICK_COLOR)
                        if _tickColorResolved[4] == nil then _tickColorResolved = { _tickColorResolved[1], _tickColorResolved[2], _tickColorResolved[3], 1 } end
                        local _pTick = { continuousTickColor = _tickColorResolved }
                        AddColorPicker(container, _pTick, "continuousTickColor", resourceName .. " Tick Color", DEFAULT_CONTINUOUS_TICK_COLOR, true,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", _pTick.continuousTickColor); applyBars() end,
                            function() WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickColor", _pTick.continuousTickColor) end)

                        local _tickWidthVal = ReadSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", nil)
                        local tickWidthSlider = AceGUI:Create("Slider")
                        tickWidthSlider:SetLabel(resourceName .. " Tick Width")
                        tickWidthSlider:SetSliderValues(1, 10, 1)
                        tickWidthSlider:SetValue(tonumber(_tickWidthVal) or DEFAULT_CONTINUOUS_TICK_WIDTH)
                        tickWidthSlider:SetFullWidth(true)
                        tickWidthSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            WriteSpecOverrideKey(settings, capturedPt, _colorSpecID, "continuousTickWidth", val)
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
                    local cache = BuildAuraBarAutocompleteCache()
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
                local cabIdx = capturedIdx
                local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end
                AddColorPicker(container, customBars[cabIdx], "barColor", "Bar Color", {0.5, 0.5, 1}, false,
                    cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

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
                        AddColorPicker(container, customBars[cabIdx], "thresholdMaxColor", "Max Stack Color", DEFAULT_CUSTOM_AURA_MAX_COLOR, false,
                            cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)
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
                        AddColorPicker(container, customBars[cabIdx], "maxStacksGlowColor", "Indicator Color", {1, 0.84, 0, 0.9}, true,
                            cabApplyBars, cabApplyBars)

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
                    local cpOverlay = AddColorPicker(container, customBars[cabIdx], "overlayColor", "Overlay Color", {1, 0.84, 0}, false,
                        cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

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
                        fontDrop:SetValue(cab.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Duration Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.durationTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Duration Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        AddColorPicker(container, customBars[cabIdx], "durationTextFontColor", "Duration Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)

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
                            local stackTextFormatValue = cab.stackTextFormat or DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            if stackTextFormatValue ~= "current" and stackTextFormatValue ~= "current_max" then
                                stackTextFormatValue = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                            end
                            stackTextFormatDrop:SetValue(stackTextFormatValue)
                            stackTextFormatDrop:SetFullWidth(true)
                            stackTextFormatDrop:SetCallback("OnValueChanged", function(widget, event, val)
                                if val == "current" or val == "current_max" then
                                    customBars[cabIdx].stackTextFormat = val
                                else
                                    customBars[cabIdx].stackTextFormat = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT
                                end
                                CooldownCompanion:ApplyResourceBars()
                            end)
                            container:AddChild(stackTextFormatDrop)
                        end

                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Stack Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Stack Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.stackTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Stack Outline")
                        outlineDrop:SetList(CS.outlineOptions)
                        outlineDrop:SetValue(cab.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        container:AddChild(outlineDrop)

                        AddColorPicker(container, customBars[cabIdx], "stackTextFontColor", "Stack Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)
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

    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        local label = AceGUI:Create("Label")
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Build the ordered list of all active bar slots
    local activeResources = GetConfigActiveResources()
    local MAX_SLOTS = ST.MAX_CUSTOM_AURA_BARS or 3
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()

    -- Resolve the display color for a power type (respects per-spec overrides)
    local layoutSpecID = GetCurrentConfigSpecID()
    if not layoutSpecID then
        local specLabel = AceGUI:Create("Label")
        specLabel:SetText("Specialization data not yet available.")
        specLabel:SetFullWidth(true)
        container:AddChild(specLabel)
        return
    end
    local function GetResourceColor(pt)
        if pt == 4 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "comboColor", DEFAULT_COMBO_COLOR)
        elseif pt == 5 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "runeReadyColor", DEFAULT_RUNE_READY_COLOR)
        elseif pt == 7 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "shardReadyColor", DEFAULT_SHARD_READY_COLOR)
        elseif pt == 9 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "holyColor", DEFAULT_HOLY_COLOR)
        elseif pt == 12 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "chiColor", DEFAULT_CHI_COLOR)
        elseif pt == 16 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "arcaneColor", DEFAULT_ARCANE_COLOR)
        elseif pt == 19 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "essenceReadyColor", DEFAULT_ESSENCE_READY_COLOR)
        elseif pt == 100 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "mwBaseColor", DEFAULT_MW_BASE_COLOR)
        elseif pt == 101 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "staggerGreenColor", { 0.52, 0.90, 0.52 })
        else return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "color", DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 })
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
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local function ensureLayoutRes()
                if not layout.resources[pt] then layout.resources[pt] = {} end
                return layout.resources[pt]
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        local pos = lr and lr.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (lr and lr.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.verticalOrder) or (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutRes().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.position) or "below"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().position = v end,
                    setOrder = function(v) ensureLayoutRes().order = v end,
                })
            end
        end
    end

    -- Custom aura bar slots
    for slotIdx = 1, MAX_SLOTS do
        local cab = customBars and customBars[slotIdx]
        if cab and cab.enabled and cab.spellID and not IsTruthyConfigFlag(cab.independentAnchorEnabled) then
            local spellInfo = C_Spell.GetSpellInfo(cab.spellID)
            local slotName = "Custom Aura " .. slotIdx
            if spellInfo and spellInfo.name then
                slotName = slotName .. ": " .. spellInfo.name
            end
            local captured = slotIdx
            local function ensureLayoutSlot()
                if not layout.customAuraBarSlots[captured] then
                    layout.customAuraBarSlots[captured] = { position = "below", order = 1000 + captured }
                end
                return layout.customAuraBarSlots[captured]
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = layout.customAuraBarSlots[captured]
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (slot and slot.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local slot = layout.customAuraBarSlots[captured]
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutSlot().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = layout.customAuraBarSlots[captured]
                        return (slot and slot.position) or "below"
                    end,
                    getOrder = function()
                        local slot = layout.customAuraBarSlots[captured]
                        return (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().position = v end,
                    setOrder = function(v) ensureLayoutSlot().order = v end,
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
                getPos = function() return (layout.castBar and layout.castBar.position) or "below" end,
                getOrder = function() return (layout.castBar and layout.castBar.order) or 2000 end,
                setPos = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.position = v
                end,
                setOrder = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.order = v
                end,
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
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
