--[[
    CooldownCompanion - ConfigSettings/BarModeTabs.lua: Bar-mode appearance and effects tab builders
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateColorPickerPromoteButton = ST._CreateColorPickerPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local ColorHeading = ST._ColorHeading
local AddPreviewBadge = ST._AddPreviewBadge

-- Imports from SectionBuilders.lua
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local AddConditionalPreviewBadge = ST._AddConditionalPreviewBadge
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown

local tabInfoButtons = CS.tabInfoButtons


-- Two-column layout (same pattern as the icon-panel tabs): the tab scroll
-- flows half-width compact widgets into side-by-side pairs; sliders, color
-- pickers, and headings stay full width.
local function SetCompactWidth(widget)
    widget:SetRelativeWidth(0.5)
end

local function BuildBarAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    container:SetLayout("Flow")

    -- ================================================================
    -- Bar Settings (length, height, spacing, bar color)
    -- ================================================================
    local barHeading, barSettingsCollapsed = BuildCollapsibleSection(container, "Bar Settings", "barappearance_settings")

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
    CS.SetupBarTextureDropdown(barTexDrop)
    barTexDrop:SetValue(style.barTexture or "Solid")
    SetCompactWidth(barTexDrop)
    CS.SetBarTextureDropdownCallback(barTexDrop, function(widget, event, val)
        style.barTexture = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barTexDrop)

    end -- not barSettingsCollapsed

    -- Bar color grid (always visible, no heading/collapse): a row break
    -- first, so the section's trailing half-width widget can't pull the
    -- first picker up into its row.
    local colorSpacer = AceGUI:Create("Label")
    colorSpacer:SetText(" ")
    colorSpacer:SetFullWidth(true)
    container:AddChild(colorSpacer)

    local barColorPicker = AddColorPicker(container, style, "barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}, true, refreshStyle, refreshStyle)
    SetCompactWidth(barColorPicker)
    CreateColorPickerPromoteButton(barColorPicker, "barColor", group, style)

    local barCooldownColorPicker = AddColorPicker(container, style, "barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}, true, refreshStyle, refreshStyle)
    SetCompactWidth(barCooldownColorPicker)
    CreateColorPickerPromoteButton(barCooldownColorPicker, "barCooldownColor", group, style)

    local barChargeColorPicker = AddColorPicker(container, style, "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}, true, refreshStyle, refreshStyle)
    SetCompactWidth(barChargeColorPicker)
    CreateColorPickerPromoteButton(barChargeColorPicker, "barChargeColor", group, style)

    local barBgColorPicker = AddColorPicker(container, style, "barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}, true, refreshStyle, refreshStyle)
    SetCompactWidth(barBgColorPicker)
    CreateColorPickerPromoteButton(barBgColorPicker, "barBgColor", group, style)

    -- ================================================================
    -- Border (thickness, size, color — mirrors the icon-mode Border section)
    -- ================================================================
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border", "barappearance_border")

    if not borderCollapsed then
    local renderMode, renderModeDrop = AddBorderRenderModeDropdown(container, style, "borderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    SetCompactWidth(renderModeDrop)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    local borderColorPicker = AddColorPicker(container, style, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshStyle, refreshStyle)
    SetCompactWidth(borderColorPicker)
    CreateColorPickerPromoteButton(borderColorPicker, "borderSettings", group, style)

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
    end -- not borderCollapsed

    -- Bar aura timer section: fills the Blizzard-driven aura bar composited
    -- over the CC bar, plus the aura text toggles. Shown only while the group
    -- has an aura-tracking entry (same gate as the icon-side aura sections).
    -- Style edits route through refreshStyle -> UpdateGroupStyle ->
    -- RequestAuraRebind, which defers to combat end with the one-time note
    -- when needed.
    if GroupHasAuraTrackingEntry(group) then
        SetCompactWidth(AddColorPicker(container, style, "barAuraColor", "Bar Aura Timer Color", {0.2, 1.0, 0.2, 1.0}, true, refreshStyle, refreshStyle))

        -- Aura duration text: rendered by the aura display at the bar's time
        -- text position (it follows the Flip Time Text and offset settings
        -- from the Cooldown Text section).
        local auraTextCb = AceGUI:Create("CheckBox")
        auraTextCb:SetLabel("Show Aura Duration Text")
        auraTextCb:SetValue(style.showAuraText ~= false)
        SetCompactWidth(auraTextCb)
        auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showAuraText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(auraTextCb)

        local function BuildBarAuraTextAdvanced(panel)
            AddFontControls(panel, style, "auraText", { size = 12 }, refreshStyle)
            AddColorPicker(panel, style, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshStyle, refreshStyle)
        end
        local _, auraTextAdvBtn = AddAdvancedToggle(auraTextCb, "barAuraText", tabInfoButtons, style.showAuraText ~= false, {
            title = "Aura Duration Text Advanced",
            build = BuildBarAuraTextAdvanced,
        })
        -- Always enabled: the preview drains the bar in the aura color, which
        -- is worth seeing even with the duration text hidden.
        local auraTextPreviewBtn = AddConditionalPreviewBadge(auraTextCb, auraTextAdvBtn, "Preview Aura Timer", "aura_duration_bar", true)
        CreateInfoButton(auraTextCb.frame, auraTextPreviewBtn or auraTextAdvBtn, "LEFT", "RIGHT", 4, 0, {
            "Aura Duration Text",
            {"Shows the remaining aura time at the bar's time text position while the aura is active. Position follows the flip and offset settings in the Cooldown Text section.", 1, 1, 1, true},
        }, auraTextCb)

        -- Aura stack text: Blizzard writes the live stack count; anchored to
        -- the icon square (or the bar with the icon hidden).
        local auraStackCb = AceGUI:Create("CheckBox")
        auraStackCb:SetLabel("Show Aura Stack Text")
        auraStackCb:SetValue(style.showAuraStackText ~= false)
        SetCompactWidth(auraStackCb)
        auraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showAuraStackText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(auraStackCb)

        local function BuildBarAuraStackTextAdvanced(panel)
            AddFontControls(panel, style, "auraStack", { size = 12 }, refreshStyle)
            AddColorPicker(panel, style, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
            AddAnchorDropdown(panel, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle)
            AddOffsetSliders(panel, style, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle)
        end
        local _, auraStackAdvBtn = AddAdvancedToggle(auraStackCb, "barAuraStackText", tabInfoButtons, style.showAuraStackText ~= false, {
            title = "Aura Stack Text Advanced",
            build = BuildBarAuraStackTextAdvanced,
        })
        local auraStackPreviewBtn = AddConditionalPreviewBadge(auraStackCb, auraStackAdvBtn, "Preview Aura Stack Text", "aura_stack_text", style.showAuraStackText ~= false)
        CreateInfoButton(auraStackCb.frame, auraStackPreviewBtn or auraStackAdvBtn, "LEFT", "RIGHT", 4, 0, {
            "Aura Stack Text",
            {"Shows the live stack count while the aura is active, drawn by the game so it stays accurate in combat. Stack counts cannot drive the bar fill; the count is hidden from addons during combat.", 1, 1, 1, true},
        }, auraStackCb)
    end

    -- ================================================================
    -- Show Icon (standalone checkbox with advanced toggle + promote)
    -- ================================================================
    local showIconCb = AceGUI:Create("CheckBox")
    showIconCb:SetLabel("Show Icon")
    showIconCb:SetValue(style.showBarIcon ~= false)
    SetCompactWidth(showIconCb)
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

    local _, iconAdvBtn = AddAdvancedToggle(showIconCb, "barIcon", tabInfoButtons, style.showBarIcon ~= false, {
        title = "Bar Icon Advanced",
        build = BuildBarIconAdvanced,
    })
    CreateCheckboxPromoteButton(showIconCb, iconAdvBtn, "barIcon", group, style)

    -- Show Name Text toggle
    local showNameCbBasic = AceGUI:Create("CheckBox")
    showNameCbBasic:SetLabel("Show Name Text")
    showNameCbBasic:SetValue(style.showBarNameText ~= false)
    SetCompactWidth(showNameCbBasic)
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

    local _, nameAdvBtn = AddAdvancedToggle(showNameCbBasic, "barNameText", tabInfoButtons, style.showBarNameText ~= false, {
        title = "Name Text Advanced",
        build = BuildBarNameTextAdvanced,
    })
    CreateCheckboxPromoteButton(showNameCbBasic, nameAdvBtn, "barNameText", group, style)

    -- Show Cooldown Text toggle
    local showTimeCbBasic = AceGUI:Create("CheckBox")
    showTimeCbBasic:SetLabel("Show Cooldown Text")
    showTimeCbBasic:SetValue(style.showCooldownText or false)
    SetCompactWidth(showTimeCbBasic)
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
            {"Applies to all time-based text, including cooldown time and ready text.", 1, 1, 1, true},
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
    SetCompactWidth(chargeTextCb)
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

    local _, chargeAdvBtn = AddAdvancedToggle(chargeTextCb, "barChargeText", tabInfoButtons, style.showChargeText ~= false, {
        title = "Count Text Advanced",
        build = BuildBarChargeTextAdvanced,
    })
    CreateCheckboxPromoteButton(chargeTextCb, chargeAdvBtn, "chargeText", group, style)


    -- Show Ready Text toggle
    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(style.showBarReadyText or false)
    SetCompactWidth(showReadyCb)
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

    local _, readyAdvBtn = AddAdvancedToggle(showReadyCb, "barReadyText", tabInfoButtons, style.showBarReadyText, {
        title = "Ready Text Advanced",
        build = BuildBarReadyTextAdvanced,
    })
    CreateCheckboxPromoteButton(showReadyCb, readyAdvBtn, "barReadyText", group, style)

    -- Compact Mode toggle + Max Visible Buttons slider
    BuildCompactModeControls(container, group, tabInfoButtons, SetCompactWidth)
    SetCompactWidth(AddDurationFormatDropdown(container, style, refreshStyle))

    BuildGroupSettingPresetControls(container, group, "bars", tabInfoButtons)

end

------------------------------------------------------------------------
-- EFFECTS TAB (Glows / Indicators)
-- Mirrors the icon-mode Indicators tab layout: Glows / Timers / States
-- headings with checkbox rows (advanced toggle + promote + preview badge).
------------------------------------------------------------------------

local function AddIndicatorsHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
    return heading
end

-- Active aura indicator: border effect + fill effects rendered by the aura
-- kit while the tracked aura runs. The checkbox reflects whether anything
-- actually renders (enabled AND a visible effect chosen); checking it with
-- no visible effect forces the pulse border, mirroring the icon aura glow.
local function BuildBarActiveAuraSection(container, group, style, setWidth)
    if not GroupHasAuraTrackingEntry(group) then
        -- The section owning an active preview just disappeared (last aura
        -- entry removed); don't leave the preview glow orphaned.
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
        return false
    end

    local hasBorderEffect = style.barAuraEffect ~= nil
        and style.barAuraEffect ~= "color" and style.barAuraEffect ~= "none"
    local anyEffect = hasBorderEffect
        or style.barAuraPulseEnabled == true
        or style.barAuraColorShiftEnabled == true
    local indicatorOn = ST.IsBarAuraIndicatorEnabled(style) and anyEffect

    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Show Active Aura Indicator")
    enableCb:SetValue(indicatorOn)
    if setWidth then setWidth(enableCb) else enableCb:SetFullWidth(true) end
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.barAuraIndicatorEnabled = val
        if val and not (style.barAuraEffect and style.barAuraEffect ~= "color" and style.barAuraEffect ~= "none"
            or style.barAuraPulseEnabled == true or style.barAuraColorShiftEnabled == true) then
            -- Nothing visible was configured; force the pulse border and
            -- reset its per-style keys (a leftover proc-scale size would
            -- render a 30px wall).
            style.barAuraEffect = "pulse"
            style.barAuraEffectSize = 2
            style.barAuraEffectSpeed = 0.5
        end
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    local function BuildBarActiveAuraAdvanced(panel)
        BuildBarActiveAuraControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
    end

    local _, aaiAdvBtn = AddAdvancedToggle(enableCb, "barActiveAura", tabInfoButtons, indicatorOn, {
        title = "Active Aura Indicator Advanced",
        build = BuildBarActiveAuraAdvanced,
    })
    local aaiPromoteBtn = CreateCheckboxPromoteButton(enableCb, aaiAdvBtn, "barActiveAura", group, style)
    local aaiPreviewBtn = AddPreviewBadge(enableCb, aaiPromoteBtn or aaiAdvBtn, "Preview Active Aura Indicator", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_barAuraEffectPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, show)
        end
    end, indicatorOn)
    CreateInfoButton(enableCb.frame, aaiPreviewBtn or aaiPromoteBtn or aaiAdvBtn, "LEFT", "RIGHT", 4, 0, {
        "Active Aura Indicator",
        {"Adds a border effect to a bar while its tracked aura is active, with optional fill pulse and fill color shift. The preview shows the bar as if the aura were running.", 1, 1, 1, true},
    }, tabInfoButtons)

    if not indicatorOn then
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
    end
    return true
end

local function BuildBarEffectsTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    container:SetLayout("Flow")

    -- ================================================================
    -- Glows
    -- ================================================================
    if GroupHasAuraTrackingEntry(group) then
        AddIndicatorsHeading(container, "Glows")
    end
    -- Runs even without the heading: the section clears its own orphaned
    -- preview when the last aura entry disappears.
    BuildBarActiveAuraSection(container, group, style, SetCompactWidth)

    -- The remaining indicators all render on the bar's icon square.
    if style.showBarIcon ~= false then
        -- ================================================================
        -- Timers
        -- ================================================================
        AddIndicatorsHeading(container, "Timers")

        local gcdCb = AceGUI:Create("CheckBox")
        gcdCb:SetLabel("Show GCD Swipe")
        gcdCb:SetValue(style.showGCDSwipe == true)
        SetCompactWidth(gcdCb)
        gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showGCDSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(gcdCb)
        CreateCheckboxPromoteButton(gcdCb, nil, "showGCDSwipe", group, style)

        -- ================================================================
        -- States
        -- ================================================================
        AddIndicatorsHeading(container, "States")

        local desatCb = AceGUI:Create("CheckBox")
        desatCb:SetLabel("Show Desaturate On Cooldown")
        desatCb:SetValue(style.desaturateOnCooldown or false)
        SetCompactWidth(desatCb)
        desatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.desaturateOnCooldown = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(desatCb)
        CreateCheckboxPromoteButton(desatCb, nil, "desaturation", group, style)

        local locCb = BuildLossOfControlControls(container, style, refreshStyle)
        SetCompactWidth(locCb)
        CreateCheckboxPromoteButton(locCb, nil, "lossOfControl", group, style)

        local unusableCb, unusableAdvBtn = BuildUnusableDimmingControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        SetCompactWidth(unusableCb)
        local unusablePromoteBtn = CreateCheckboxPromoteButton(unusableCb, unusableAdvBtn, "unusableDimming", group, style)
        AddConditionalPreviewBadge(unusableCb, unusablePromoteBtn or unusableAdvBtn, "Preview Unusable State", "unusable", style.showUnusable)

        local tooltipCb = BuildShowTooltipsControls(container, style, refreshStyle)
        SetCompactWidth(tooltipCb)
        CreateCheckboxPromoteButton(tooltipCb, nil, "showTooltips", group, style)
    end

end

-- Expose for GroupTabs.lua dispatchers
ST._BuildBarAppearanceTab = BuildBarAppearanceTab
ST._BuildBarEffectsTab = BuildBarEffectsTab
