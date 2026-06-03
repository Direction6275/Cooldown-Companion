--[[
    CooldownCompanion - ConfigSettings/BarModeTabs.lua: Bar-mode appearance and effects tab builders
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateColorPickerPromoteButton = ST._CreateColorPickerPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local GetBarTextureOptions = ST._GetBarTextureOptions
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from SectionBuilders.lua
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local AddPreviewBadge = ST._AddPreviewBadge
local AddConditionalPreviewBadge = ST._AddConditionalPreviewBadge
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements


local function BuildBarAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

    -- ================================================================
    -- Bar Settings (length, height, spacing, bar color)
    -- ================================================================
    local barHeading = AceGUI:Create("Heading")
    barHeading:SetText("Bar Settings")
    ColorHeading(barHeading)
    barHeading:SetFullWidth(true)
    container:AddChild(barHeading)

    local barSettingsCollapsed = CS.collapsedSections["barappearance_settings"]
    AttachCollapseButton(barHeading, barSettingsCollapsed, function()
        CS.collapsedSections["barappearance_settings"] = not CS.collapsedSections["barappearance_settings"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not barSettingsCollapsed then
    local lengthSlider = AceGUI:Create("Slider")
    lengthSlider:SetLabel("Bar Length")
    lengthSlider:SetSliderValues(10, 500, 0.1)
    lengthSlider:SetValue(style.barLength or 180)
    lengthSlider:SetFullWidth(true)
    lengthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barLength = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(lengthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Bar Height")
    heightSlider:SetSliderValues(5, 100, 0.1)
    heightSlider:SetValue(style.barHeight or 20)
    heightSlider:SetFullWidth(true)
    heightSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barHeight = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(heightSlider)

    local renderMode = AddBorderRenderModeDropdown(container, style, "borderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            style.borderSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(borderSlider)
    end

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Bar Spacing")
        spacingSlider:SetSliderValues(-10, 100, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    -- Bar Texture
    local barTexDrop = AceGUI:Create("Dropdown")
    barTexDrop:SetLabel("Bar Texture")
    barTexDrop:SetList(GetBarTextureOptions())
    barTexDrop:SetValue(style.barTexture or "Solid")
    barTexDrop:SetFullWidth(true)
    barTexDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.barTexture = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barTexDrop)

    -- Bar Color (basic)
    local barColorPicker = AddColorPicker(container, style, "barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}, true, refreshStyle, refreshStyle)
    CreateColorPickerPromoteButton(barColorPicker, "barColor", group, style)

    end -- not barSettingsCollapsed

    -- Contextual color pickers (no heading/collapse/promote)
    local barCooldownColorPicker = AddColorPicker(container, style, "barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}, true, refreshStyle, refreshStyle)
    CreateColorPickerPromoteButton(barCooldownColorPicker, "barCooldownColor", group, style)

    local barChargeColorPicker = AddColorPicker(container, style, "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}, true, refreshStyle, refreshStyle)
    CreateColorPickerPromoteButton(barChargeColorPicker, "barChargeColor", group, style)

    local barBgColorPicker = AddColorPicker(container, style, "barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}, true, refreshStyle, refreshStyle)
    CreateColorPickerPromoteButton(barBgColorPicker, "barBgColor", group, style)

    local borderColorPicker = AddColorPicker(container, style, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshStyle, refreshStyle)
    CreateColorPickerPromoteButton(borderColorPicker, "borderSettings", group, style)

    -- ================================================================
    -- Show Icon (standalone checkbox with advanced toggle + promote)
    -- ================================================================
    local showIconCb = AceGUI:Create("CheckBox")
    showIconCb:SetLabel("Show Icon")
    showIconCb:SetValue(style.showBarIcon ~= false)
    showIconCb:SetFullWidth(true)
    showIconCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarIcon = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showIconCb)

    local function BuildBarIconAdvanced(panel)
        local flipIconCheck = AceGUI:Create("CheckBox")
        flipIconCheck:SetLabel("Flip Icon Side")
        flipIconCheck:SetValue(style.barIconReverse or false)
        flipIconCheck:SetFullWidth(true)
        flipIconCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconReverse = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        panel:AddChild(flipIconCheck)

        local iconOffsetSlider = AceGUI:Create("Slider")
        iconOffsetSlider:SetLabel("Icon Offset")
        iconOffsetSlider:SetSliderValues(-5, 50, 0.1)
        iconOffsetSlider:SetValue(style.barIconOffset or 0)
        iconOffsetSlider:SetFullWidth(true)
        iconOffsetSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(iconOffsetSlider)

        local customIconSizeCb = AceGUI:Create("CheckBox")
        customIconSizeCb:SetLabel("Custom Icon Size")
        customIconSizeCb:SetValue(style.barIconSizeOverride or false)
        customIconSizeCb:SetFullWidth(true)
        customIconSizeCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconSizeOverride = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        panel:AddChild(customIconSizeCb)

        if style.barIconSizeOverride then
            local iconSizeSlider = AceGUI:Create("Slider")
            iconSizeSlider:SetLabel("Icon Size")
            iconSizeSlider:SetSliderValues(5, 100, 0.1)
            iconSizeSlider:SetValue(style.barIconSize or 20)
            iconSizeSlider:SetFullWidth(true)
            iconSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.barIconSize = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            panel:AddChild(iconSizeSlider)
        end
    end

    local iconAdvExpanded, iconAdvBtn = AddAdvancedToggle(showIconCb, "barIcon", tabInfoButtons, style.showBarIcon ~= false, {
        title = "Bar Icon Advanced",
        build = BuildBarIconAdvanced,
    })
    CreateCheckboxPromoteButton(showIconCb, iconAdvBtn, "barIcon", group, style)

    -- Show Name Text toggle
    local showNameCbBasic = AceGUI:Create("CheckBox")
    showNameCbBasic:SetLabel("Show Name Text")
    showNameCbBasic:SetValue(style.showBarNameText ~= false)
    showNameCbBasic:SetFullWidth(true)
    showNameCbBasic:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarNameText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showNameCbBasic)

    local function BuildBarNameTextAdvanced(panel)
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(style.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(flipNameCheck)

        AddFontControls(panel, style, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle)
        AddColorPicker(panel, style, "barNameFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddOffsetSliders(panel, style, "barNameTextOffsetX", "barNameTextOffsetY", {range = 50}, refreshStyle)
    end

    local nameAdvExpanded, nameAdvBtn = AddAdvancedToggle(showNameCbBasic, "barNameText", tabInfoButtons, style.showBarNameText ~= false, {
        title = "Name Text Advanced",
        build = BuildBarNameTextAdvanced,
    })
    CreateCheckboxPromoteButton(showNameCbBasic, nameAdvBtn, "barNameText", group, style)

    -- Show Cooldown Text toggle
    local showTimeCbBasic = AceGUI:Create("CheckBox")
    showTimeCbBasic:SetLabel("Show Cooldown Text")
    showTimeCbBasic:SetValue(style.showCooldownText or false)
    showTimeCbBasic:SetFullWidth(true)
    showTimeCbBasic:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showTimeCbBasic)

    local function BuildBarCooldownTextAdvanced(panel)
        local flipTimeCheck = AceGUI:Create("CheckBox")
        flipTimeCheck:SetLabel("Flip Time Text")
        flipTimeCheck:SetValue(style.barTimeTextReverse or false)
        flipTimeCheck:SetFullWidth(true)
        flipTimeCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barTimeTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(flipTimeCheck)

        -- (?) tooltip for Flip Time Text
        CreateInfoButton(flipTimeCheck.frame, flipTimeCheck.checkbg, "LEFT", "RIGHT", flipTimeCheck.text:GetStringWidth() + 4, 0, {
            "Flip Time Text",
            {"Applies to all time-based text, including cooldown time, aura time, and ready text.", 1, 1, 1, true},
        }, flipTimeCheck)

        AddFontControls(panel, style, "cooldown", {sizeMin = 6, sizeMax = 24}, refreshStyle)
        AddColorPicker(panel, style, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshStyle, refreshStyle)
        AddOffsetSliders(panel, style, "barCdTextOffsetX", "barCdTextOffsetY", {range = 50}, refreshStyle)
    end

    local _, timeAdvBtn = AddAdvancedToggle(showTimeCbBasic, "barCooldownText", tabInfoButtons, style.showCooldownText, {
        title = "Cooldown Text Advanced",
        build = BuildBarCooldownTextAdvanced,
    })
    local timePromoteBtn = CreateCheckboxPromoteButton(showTimeCbBasic, timeAdvBtn, "cooldownText", group, style)
    AddConditionalPreviewBadge(showTimeCbBasic, timePromoteBtn or timeAdvBtn, "Preview Cooldown Text", "cooldown", style.showCooldownText)

    -- Show Charge Text toggle
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Count Text (Charges/Uses)")
    chargeTextCb:SetValue(style.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showChargeText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    local function BuildBarChargeTextAdvanced(panel)
        AddFontControls(panel, style, "charge", {}, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(panel, style, "chargeAnchor", "BOTTOMRIGHT", refreshStyle)
        AddOffsetSliders(panel, style, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle)
    end

    local chargeAdvExpanded, chargeAdvBtn = AddAdvancedToggle(chargeTextCb, "barChargeText", tabInfoButtons, style.showChargeText ~= false, {
        title = "Count Text Advanced",
        build = BuildBarChargeTextAdvanced,
    })
    CreateCheckboxPromoteButton(chargeTextCb, chargeAdvBtn, "chargeText", group, style)

    -- ================================================================
    -- Aura Duration Text
    -- ================================================================
    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Duration Text")
    auraTextCb:SetValue(style.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    local function BuildBarAuraTextAdvanced(panel)
        AddFontControls(panel, style, "auraText", {sizeMin = 6, sizeMax = 24}, refreshStyle)
        AddColorPicker(panel, style, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshStyle, refreshStyle)
    end

    local _, barAuraTextAdvBtn = AddAdvancedToggle(auraTextCb, "barAuraText", tabInfoButtons, style.showAuraText ~= false, {
        title = "Aura Duration Text Advanced",
        build = BuildBarAuraTextAdvanced,
    })
    local barAuraTextPromoteBtn = CreateCheckboxPromoteButton(auraTextCb, barAuraTextAdvBtn, "auraText", group, style)
    AddConditionalPreviewBadge(auraTextCb, barAuraTextPromoteBtn or barAuraTextAdvBtn, "Preview Aura Duration Text", "aura_duration_text", style.showAuraText ~= false)

    -- ================================================================
    -- Aura Stack Text
    -- ================================================================
    local barAuraStackCb = AceGUI:Create("CheckBox")
    barAuraStackCb:SetLabel("Show Aura Stack Text")
    barAuraStackCb:SetValue(style.showAuraStackText ~= false)
    barAuraStackCb:SetFullWidth(true)
    barAuraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraStackText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(barAuraStackCb)

    local function BuildBarAuraStackAdvanced(panel)
        AddFontControls(panel, style, "auraStack", {}, refreshStyle)
        AddColorPicker(panel, style, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(panel, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle)
        AddOffsetSliders(panel, style, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2}, refreshStyle)
    end

    local _, barAuraStackAdvBtn = AddAdvancedToggle(barAuraStackCb, "barAuraStackText", tabInfoButtons, style.showAuraStackText ~= false, {
        title = "Aura Stack Text Advanced",
        build = BuildBarAuraStackAdvanced,
    })
    local barAuraStackPromoteBtn = CreateCheckboxPromoteButton(barAuraStackCb, barAuraStackAdvBtn, "auraStackText", group, style)
    AddConditionalPreviewBadge(barAuraStackCb, barAuraStackPromoteBtn or barAuraStackAdvBtn, "Preview Aura Stack Text", "aura_stack_text", style.showAuraStackText ~= false)

    -- Show Ready Text toggle
    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(style.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarReadyText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showReadyCb)

    local function BuildBarReadyTextAdvanced(panel)
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(style.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            style.barReadyText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(readyTextBox)

        AddColorPicker(panel, style, "barReadyTextColor", "Ready Text Color", {0.2, 1.0, 0.2, 1.0}, true, refreshStyle, refreshStyle)
        AddFontControls(panel, style, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle)
    end

    local readyAdvExpanded, readyAdvBtn = AddAdvancedToggle(showReadyCb, "barReadyText", tabInfoButtons, style.showBarReadyText, {
        title = "Ready Text Advanced",
        build = BuildBarReadyTextAdvanced,
    })
    CreateCheckboxPromoteButton(showReadyCb, readyAdvBtn, "barReadyText", group, style)

    -- Compact Mode toggle + Max Visible Buttons slider
    BuildCompactModeControls(container, group, tabInfoButtons)
    AddDurationFormatDropdown(container, style, refreshStyle)

    BuildGroupSettingPresetControls(container, group, "bars", tabInfoButtons)

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- EFFECTS TAB (Glows / Indicators)
------------------------------------------------------------------------
local function BuildBarEffectsTab(container, group, style)
    -- ================================================================
    -- Show Active Aura Indicator
    -- ================================================================
    local barAuraEnableCb = AceGUI:Create("CheckBox")
    barAuraEnableCb:SetLabel("Show Active Aura Indicator")
    barAuraEnableCb:SetValue(style.barAuraEffect ~= "none")
    barAuraEnableCb:SetFullWidth(true)
    barAuraEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.barAuraEffect = val and "color" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(barAuraEnableCb)

    local function BuildBarActiveAuraAdvanced(panel)
        local barAuraCombatCb = AceGUI:Create("CheckBox")
        barAuraCombatCb:SetLabel("Show Only In Combat")
        barAuraCombatCb:SetValue(style.auraGlowCombatOnly or false)
        barAuraCombatCb:SetFullWidth(true)
        barAuraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraGlowCombatOnly = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(barAuraCombatCb)

        BuildBarActiveAuraControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)

        BuildBarAuraPulseControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
    end

    local _, barAuraAdvBtn = AddAdvancedToggle(barAuraEnableCb, "barActiveAura", tabInfoButtons, style.barAuraEffect ~= "none", {
        title = "Active Aura Indicator Advanced",
        build = BuildBarActiveAuraAdvanced,
    })
    local barAuraPromoteBtn = CreateCheckboxPromoteButton(barAuraEnableCb, barAuraAdvBtn, "barActiveAura", group, style)
    AddPreviewBadge(barAuraEnableCb, barAuraPromoteBtn or barAuraAdvBtn, "Preview Active Aura Effects", function()
        return CS.selectedGroup and CooldownCompanion:IsBarAuraActivePreviewActive(CS.selectedGroup, nil)
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetBarAuraActivePreview(CS.selectedGroup, nil, show)
        end
    end, style.barAuraEffect ~= "none")

    if style.barAuraEffect == "none" and CS.selectedGroup then
        CooldownCompanion:SetBarAuraActivePreview(CS.selectedGroup, nil, false)
    end -- barAuraAdvExpanded

    -- ================================================================
    -- Show Pandemic Indicator
    -- ================================================================
    local pandemicIndicatorCb = AceGUI:Create("CheckBox")
    pandemicIndicatorCb:SetLabel("Show Pandemic Indicator")
    pandemicIndicatorCb:SetValue(style.showPandemicGlow ~= false)
    pandemicIndicatorCb:SetFullWidth(true)
    pandemicIndicatorCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showPandemicGlow = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(pandemicIndicatorCb)

    local function BuildBarPandemicAdvanced(panel)
        local barPandemicCombatCb = AceGUI:Create("CheckBox")
        barPandemicCombatCb:SetLabel("Show Only In Combat")
        barPandemicCombatCb:SetValue(style.pandemicGlowCombatOnly or false)
        barPandemicCombatCb:SetFullWidth(true)
        barPandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.pandemicGlowCombatOnly = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(barPandemicCombatCb)

        BuildPandemicBarControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)

        BuildPandemicBarPulseControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
    end

    local _, barPandemicAdvBtn = AddAdvancedToggle(pandemicIndicatorCb, "barPandemicIndicator", tabInfoButtons, style.showPandemicGlow ~= false, {
        title = "Pandemic Indicator Advanced",
        build = BuildBarPandemicAdvanced,
    })
    local barPandemicPromoteBtn = CreateCheckboxPromoteButton(pandemicIndicatorCb, barPandemicAdvBtn, "pandemicBar", group, style)
    AddPreviewBadge(pandemicIndicatorCb, barPandemicPromoteBtn or barPandemicAdvBtn, "Preview Pandemic Effects", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_pandemicPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, show)
        end
    end, style.showPandemicGlow ~= false)

    if style.showPandemicGlow == false and CS.selectedGroup then
        CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
    end -- barPandemicAdvExpanded

    -- ================================================================
    -- Desaturate on Cooldown
    -- ================================================================
    if style.showBarIcon ~= false then
        local gcdCb = AceGUI:Create("CheckBox")
        gcdCb:SetLabel("Show GCD Swipe")
        gcdCb:SetValue(style.showGCDSwipe == true)
        gcdCb:SetFullWidth(true)
        gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showGCDSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(gcdCb)
        CreateCheckboxPromoteButton(gcdCb, nil, "showGCDSwipe", group, style)

        local desatCb = AceGUI:Create("CheckBox")
        desatCb:SetLabel("Show Desaturate On Cooldown")
        desatCb:SetValue(style.desaturateOnCooldown or false)
        desatCb:SetFullWidth(true)
        desatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.desaturateOnCooldown = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(desatCb)
        CreateCheckboxPromoteButton(desatCb, nil, "desaturation", group, style)

        -- ================================================================
        -- Loss of Control
        -- ================================================================
        local locCb = BuildLossOfControlControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        CreateCheckboxPromoteButton(locCb, nil, "lossOfControl", group, style)

        -- ================================================================
        -- Unusable Dimming
        -- ================================================================
        local unusableCb = BuildUnusableDimmingControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        local unusablePromoteBtn = CreateCheckboxPromoteButton(unusableCb, nil, "unusableDimming", group, style)
        AddConditionalPreviewBadge(unusableCb, unusablePromoteBtn, "Preview Unusable State", "unusable", style.showUnusable)

        -- Show Tooltips
        local tooltipCb = BuildShowTooltipsControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        CreateCheckboxPromoteButton(tooltipCb, nil, "showTooltips", group, style)
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end

-- Expose for GroupTabs.lua dispatchers
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
