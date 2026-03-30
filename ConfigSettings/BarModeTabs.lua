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
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local GetBarTextureOptions = ST._GetBarTextureOptions
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders

-- Imports from SectionBuilders.lua
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls

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
    local collapseBtn = AttachCollapseButton(barHeading, barSettingsCollapsed, function()
        CS.collapsedSections["barappearance_settings"] = not CS.collapsedSections["barappearance_settings"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    local barAdvExpanded, barAdvBtn = AddAdvancedToggle(barHeading, "barSettings", tabInfoButtons)
    barAdvBtn:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    barHeading.right:ClearAllPoints()
    barHeading.right:SetPoint("RIGHT", barHeading.frame, "RIGHT", -3, 0)
    barHeading.right:SetPoint("LEFT", barAdvBtn, "RIGHT", 4, 0)

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

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.borderSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderSlider)

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
    AddColorPicker(container, style, "barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}, true, refreshStyle, refreshStyle)

    if barAdvExpanded then
    local updateFreqSlider = AceGUI:Create("Slider")
    updateFreqSlider:SetLabel("Update Frequency (Hz)")
    updateFreqSlider:SetSliderValues(10, 60, 0.1)
    local curInterval = style.barUpdateInterval or 0.025
    updateFreqSlider:SetValue(math.floor(1 / curInterval + 0.5))
    updateFreqSlider:SetFullWidth(true)
    updateFreqSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barUpdateInterval = 1 / val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(updateFreqSlider)
    end -- barAdvExpanded (update freq)
    end -- not barSettingsCollapsed

    -- Contextual color pickers (no heading/collapse/promote)
    AddColorPicker(container, style, "barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}, true, refreshStyle, refreshStyle)

    AddColorPicker(container, style, "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}, true, refreshStyle, refreshStyle)

    AddColorPicker(container, style, "barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}, true, refreshStyle, refreshStyle)

    AddColorPicker(container, style, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshStyle, refreshStyle)

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

    local iconAdvExpanded, iconAdvBtn = AddAdvancedToggle(showIconCb, "barIcon", tabInfoButtons, style.showBarIcon ~= false)
    CreateCheckboxPromoteButton(showIconCb, iconAdvBtn, "barIcon", group, style)

    if iconAdvExpanded and style.showBarIcon ~= false then
        local flipIconCheck = AceGUI:Create("CheckBox")
        flipIconCheck:SetLabel("Flip Icon Side")
        flipIconCheck:SetValue(style.barIconReverse or false)
        flipIconCheck:SetFullWidth(true)
        flipIconCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconReverse = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(flipIconCheck)

        local iconOffsetSlider = AceGUI:Create("Slider")
        iconOffsetSlider:SetLabel("Icon Offset")
        iconOffsetSlider:SetSliderValues(-5, 50, 0.1)
        iconOffsetSlider:SetValue(style.barIconOffset or 0)
        iconOffsetSlider:SetFullWidth(true)
        iconOffsetSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(iconOffsetSlider)

        local customIconSizeCb = AceGUI:Create("CheckBox")
        customIconSizeCb:SetLabel("Custom Icon Size")
        customIconSizeCb:SetValue(style.barIconSizeOverride or false)
        customIconSizeCb:SetFullWidth(true)
        customIconSizeCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconSizeOverride = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(customIconSizeCb)

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
            container:AddChild(iconSizeSlider)
        end
    end

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

    local nameAdvExpanded, nameAdvBtn = AddAdvancedToggle(showNameCbBasic, "barNameText", tabInfoButtons, style.showBarNameText ~= false)
    CreateCheckboxPromoteButton(showNameCbBasic, nameAdvBtn, "barNameText", group, style)

    if nameAdvExpanded and style.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(style.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(flipNameCheck)

        AddFontControls(container, style, "barName", {sizeMin = 6, sizeMax = 24, size = 10}, refreshStyle)
        AddColorPicker(container, style, "barNameFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddOffsetSliders(container, style, "barNameTextOffsetX", "barNameTextOffsetY", {range = 50}, refreshStyle)
    end

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

    local timeAdvExpanded, timeAdvBtn = AddAdvancedToggle(showTimeCbBasic, "barCooldownText", tabInfoButtons, style.showCooldownText)
    CreateCheckboxPromoteButton(showTimeCbBasic, timeAdvBtn, "cooldownText", group, style)

    if timeAdvExpanded and style.showCooldownText then
        local flipTimeCheck = AceGUI:Create("CheckBox")
        flipTimeCheck:SetLabel("Flip Time Text")
        flipTimeCheck:SetValue(style.barTimeTextReverse or false)
        flipTimeCheck:SetFullWidth(true)
        flipTimeCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barTimeTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(flipTimeCheck)

        -- (?) tooltip for Flip Time Text
        CreateInfoButton(flipTimeCheck.frame, flipTimeCheck.checkbg, "LEFT", "RIGHT", flipTimeCheck.text:GetStringWidth() + 4, 0, {
            "Flip Time Text",
            {"Applies to all time-based text, including cooldown time, aura time, and ready text.", 1, 1, 1, true},
        }, flipTimeCheck)

        AddFontControls(container, style, "cooldown", {sizeMin = 6, sizeMax = 24}, refreshStyle)
        AddColorPicker(container, style, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshStyle, refreshStyle)
        AddOffsetSliders(container, style, "barCdTextOffsetX", "barCdTextOffsetY", {range = 50}, refreshStyle)
    end

    -- Show Charge Text toggle
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Charge Text")
    chargeTextCb:SetValue(style.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showChargeText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    local chargeAdvExpanded, chargeAdvBtn = AddAdvancedToggle(chargeTextCb, "barChargeText", tabInfoButtons, style.showChargeText ~= false)
    CreateCheckboxPromoteButton(chargeTextCb, chargeAdvBtn, "chargeText", group, style)

    if chargeAdvExpanded and style.showChargeText ~= false then
        AddFontControls(container, style, "charge", {}, refreshStyle)
        AddColorPicker(container, style, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(container, style, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(container, style, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(container, style, "chargeAnchor", "BOTTOMRIGHT", refreshStyle)
        AddOffsetSliders(container, style, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshStyle)
    end

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

    local barAuraTextAdvExpanded, barAuraTextAdvBtn = AddAdvancedToggle(auraTextCb, "barAuraText", tabInfoButtons, style.showAuraText ~= false)
    CreateCheckboxPromoteButton(auraTextCb, barAuraTextAdvBtn, "auraText", group, style)

    if barAuraTextAdvExpanded and style.showAuraText ~= false then
        AddFontControls(container, style, "auraText", {sizeMin = 6, sizeMax = 24}, refreshStyle)
        AddColorPicker(container, style, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshStyle, refreshStyle)
    end -- barAuraTextAdvExpanded

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

    local barAuraStackAdvExpanded, barAuraStackAdvBtn = AddAdvancedToggle(barAuraStackCb, "barAuraStackText", tabInfoButtons, style.showAuraStackText ~= false)
    CreateCheckboxPromoteButton(barAuraStackCb, barAuraStackAdvBtn, "auraStackText", group, style)

    if barAuraStackAdvExpanded and style.showAuraStackText ~= false then
        AddFontControls(container, style, "auraStack", {}, refreshStyle)
        AddColorPicker(container, style, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(container, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle)
        AddOffsetSliders(container, style, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2}, refreshStyle)
    end -- barAuraStackAdvExpanded

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

    local readyAdvExpanded, readyAdvBtn = AddAdvancedToggle(showReadyCb, "barReadyText", tabInfoButtons, style.showBarReadyText)
    CreateCheckboxPromoteButton(showReadyCb, readyAdvBtn, "barReadyText", group, style)

    if readyAdvExpanded and style.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(style.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            style.barReadyText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyTextBox)

        AddColorPicker(container, style, "barReadyTextColor", "Ready Text Color", {0.2, 1.0, 0.2, 1.0}, true, refreshStyle, refreshStyle)
        AddFontControls(container, style, "barReady", {sizeMin = 6, sizeMax = 24}, refreshStyle)
    end

    -- Show Decimal Point toggle (affects both cooldown and aura duration text)
    local decimalCheck = AceGUI:Create("CheckBox")
    decimalCheck:SetLabel("Show Decimal Point")
    decimalCheck:SetValue(style.decimalTimers or false)
    decimalCheck:SetFullWidth(true)
    decimalCheck:SetCallback("OnValueChanged", function(widget, event, val)
        style.decimalTimers = val or nil
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(decimalCheck)

    CreateInfoButton(decimalCheck.frame, decimalCheck.checkbg, "LEFT", "RIGHT", decimalCheck.text:GetStringWidth() + 4, 0, {
        "Show Decimal Point",
        {"Shows one decimal place on duration text", 1, 1, 1, true},
        {"(e.g. \"4.5\" instead of \"5\").", 1, 1, 1, true},
    }, decimalCheck)

    -- Compact Mode toggle + Max Visible Buttons slider
    BuildCompactModeControls(container, group, tabInfoButtons)
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
    -- Show Active Aura Color/Glow
    -- ================================================================
    local barAuraEnableCb = AceGUI:Create("CheckBox")
    barAuraEnableCb:SetLabel("Show Active Aura Color/Glow")
    barAuraEnableCb:SetValue(style.barAuraEffect ~= "none")
    barAuraEnableCb:SetFullWidth(true)
    barAuraEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.barAuraEffect = val and "color" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(barAuraEnableCb)

    local barAuraAdvExpanded, barAuraAdvBtn = AddAdvancedToggle(barAuraEnableCb, "barActiveAura", tabInfoButtons, style.barAuraEffect ~= "none")
    CreateCheckboxPromoteButton(barAuraEnableCb, barAuraAdvBtn, "barActiveAura", group, style)

    if barAuraAdvExpanded and style.barAuraEffect ~= "none" then
    local barAuraCombatCb = AceGUI:Create("CheckBox")
    barAuraCombatCb:SetLabel("Show Only In Combat")
    barAuraCombatCb:SetValue(style.auraGlowCombatOnly or false)
    barAuraCombatCb:SetFullWidth(true)
    barAuraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.auraGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barAuraCombatCb)
    ApplyCheckboxIndent(barAuraCombatCb, 20)

    BuildBarActiveAuraControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    BuildBarAuraPulseControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local auraActivePreviewBtn = AceGUI:Create("Button")
    auraActivePreviewBtn:SetText("Preview Active Aura Effects (3s)")
    auraActivePreviewBtn:SetFullWidth(true)
    auraActivePreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayBarAuraActivePreview(CS.selectedGroup, 3)
    end)
    container:AddChild(auraActivePreviewBtn)
    end -- barAuraAdvExpanded

    -- ================================================================
    -- Show Pandemic Color/Glow
    -- ================================================================
    local pandemicIndicatorCb = AceGUI:Create("CheckBox")
    pandemicIndicatorCb:SetLabel("Show Pandemic Color/Glow")
    pandemicIndicatorCb:SetValue(style.showPandemicGlow ~= false)
    pandemicIndicatorCb:SetFullWidth(true)
    pandemicIndicatorCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showPandemicGlow = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(pandemicIndicatorCb)

    local barPandemicAdvExpanded, barPandemicAdvBtn = AddAdvancedToggle(pandemicIndicatorCb, "barPandemicIndicator", tabInfoButtons, style.showPandemicGlow ~= false)
    CreateCheckboxPromoteButton(pandemicIndicatorCb, barPandemicAdvBtn, "pandemicBar", group, style)

    if barPandemicAdvExpanded and style.showPandemicGlow ~= false then
    local barPandemicCombatCb = AceGUI:Create("CheckBox")
    barPandemicCombatCb:SetLabel("Show Only In Combat")
    barPandemicCombatCb:SetValue(style.pandemicGlowCombatOnly or false)
    barPandemicCombatCb:SetFullWidth(true)
    barPandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.pandemicGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barPandemicCombatCb)
    ApplyCheckboxIndent(barPandemicCombatCb, 20)

    BuildPandemicBarControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    BuildPandemicBarPulseControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local pandemicPreviewBtn = AceGUI:Create("Button")
    pandemicPreviewBtn:SetText("Preview Pandemic Effects (3s)")
    pandemicPreviewBtn:SetFullWidth(true)
    pandemicPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupPandemicPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(pandemicPreviewBtn)
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
        end)
        CreateCheckboxPromoteButton(unusableCb, nil, "unusableDimming", group, style)

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
