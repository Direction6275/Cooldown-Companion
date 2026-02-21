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
local GetBarTextureOptions = ST._GetBarTextureOptions

-- Imports from SectionBuilders.lua
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements


local function BuildBarAppearanceTab(container, group, style)
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
    lengthSlider:SetSliderValues(50, 500, 0.1)
    lengthSlider:SetValue(style.barLength or 180)
    lengthSlider:SetFullWidth(true)
    lengthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barLength = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(lengthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Bar Height")
    heightSlider:SetSliderValues(5, 50, 0.1)
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
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Bar Color")
    barColorPicker:SetHasAlpha(true)
    local brc = style.barColor or {0.2, 0.6, 1.0, 1.0}
    barColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barColorPicker)

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
    local barCdColorPicker = AceGUI:Create("ColorPicker")
    barCdColorPicker:SetLabel("Bar Cooldown Color")
    barCdColorPicker:SetHasAlpha(true)
    local bcc = style.barCooldownColor or {0.6, 0.6, 0.6, 1.0}
    barCdColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
    barCdColorPicker:SetFullWidth(true)
    barCdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barCdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barCdColorPicker)

    local barChargeColorPicker = AceGUI:Create("ColorPicker")
    barChargeColorPicker:SetLabel("Bar Recharging Color")
    barChargeColorPicker:SetHasAlpha(true)
    local bchc = style.barChargeColor or {1.0, 0.82, 0.0, 1.0}
    barChargeColorPicker:SetColor(bchc[1], bchc[2], bchc[3], bchc[4])
    barChargeColorPicker:SetFullWidth(true)
    barChargeColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barChargeColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barChargeColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barChargeColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barChargeColorPicker)

    local barBgColorPicker = AceGUI:Create("ColorPicker")
    barBgColorPicker:SetLabel("Bar Background Color")
    barBgColorPicker:SetHasAlpha(true)
    local bbg = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    barBgColorPicker:SetColor(bbg[1], bbg[2], bbg[3], bbg[4])
    barBgColorPicker:SetFullWidth(true)
    barBgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barBgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barBgColorPicker)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderColor)

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

        local nameFontSizeSlider = AceGUI:Create("Slider")
        nameFontSizeSlider:SetLabel("Font Size")
        nameFontSizeSlider:SetSliderValues(6, 24, 1)
        nameFontSizeSlider:SetValue(style.barNameFontSize or 10)
        nameFontSizeSlider:SetFullWidth(true)
        nameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontSizeSlider)

        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(nameFontDrop)
        nameFontDrop:SetValue(style.barNameFont or "Friz Quadrata TT")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontDrop)

        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Font Outline")
        nameOutlineDrop:SetList(CS.outlineOptions)
        nameOutlineDrop:SetValue(style.barNameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOutlineDrop)

        local nameFontColor = AceGUI:Create("ColorPicker")
        nameFontColor:SetLabel("Font Color")
        nameFontColor:SetHasAlpha(true)
        local nfc = style.barNameFontColor or {1, 1, 1, 1}
        nameFontColor:SetColor(nfc[1], nfc[2], nfc[3], nfc[4])
        nameFontColor:SetFullWidth(true)
        nameFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        nameFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontColor)

        local nameOffXSlider = AceGUI:Create("Slider")
        nameOffXSlider:SetLabel("X Offset")
        nameOffXSlider:SetSliderValues(-50, 50, 0.1)
        nameOffXSlider:SetValue(style.barNameTextOffsetX or 0)
        nameOffXSlider:SetFullWidth(true)
        nameOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOffXSlider)

        local nameOffYSlider = AceGUI:Create("Slider")
        nameOffYSlider:SetLabel("Y Offset")
        nameOffYSlider:SetSliderValues(-50, 50, 0.1)
        nameOffYSlider:SetValue(style.barNameTextOffsetY or 0)
        nameOffYSlider:SetFullWidth(true)
        nameOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOffYSlider)
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
        local flipTimeInfo = CreateFrame("Button", nil, flipTimeCheck.frame)
        flipTimeInfo:SetSize(16, 16)
        flipTimeInfo:SetPoint("LEFT", flipTimeCheck.checkbg, "RIGHT", flipTimeCheck.text:GetStringWidth() + 4, 0)
        local flipTimeInfoIcon = flipTimeInfo:CreateTexture(nil, "OVERLAY")
        flipTimeInfoIcon:SetSize(12, 12)
        flipTimeInfoIcon:SetPoint("CENTER")
        flipTimeInfoIcon:SetAtlas("QuestRepeatableTurnin")
        flipTimeInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Flip Time Text")
            GameTooltip:AddLine("Applies to all time-based text, including cooldown time, aura time, and ready text.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        flipTimeInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        flipTimeCheck:SetCallback("OnRelease", function()
            flipTimeInfo:ClearAllPoints()
            flipTimeInfo:Hide()
            flipTimeInfo:SetParent(nil)
        end)

        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(6, 24, 1)
        fontSizeSlider:SetValue(style.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(style.cooldownFont or "Friz Quadrata TT")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(style.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = style.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdFontColor)

        local cdOffXSlider = AceGUI:Create("Slider")
        cdOffXSlider:SetLabel("X Offset")
        cdOffXSlider:SetSliderValues(-50, 50, 0.1)
        cdOffXSlider:SetValue(style.barCdTextOffsetX or 0)
        cdOffXSlider:SetFullWidth(true)
        cdOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdOffXSlider)

        local cdOffYSlider = AceGUI:Create("Slider")
        cdOffYSlider:SetLabel("Y Offset")
        cdOffYSlider:SetSliderValues(-50, 50, 0.1)
        cdOffYSlider:SetValue(style.barCdTextOffsetY or 0)
        cdOffYSlider:SetFullWidth(true)
        cdOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdOffYSlider)
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
        local chargeFontSizeSlider = AceGUI:Create("Slider")
        chargeFontSizeSlider:SetLabel("Font Size")
        chargeFontSizeSlider:SetSliderValues(8, 32, 1)
        chargeFontSizeSlider:SetValue(style.chargeFontSize or 12)
        chargeFontSizeSlider:SetFullWidth(true)
        chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontSizeSlider)

        local chargeFontDrop = AceGUI:Create("Dropdown")
        chargeFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(chargeFontDrop)
        chargeFontDrop:SetValue(style.chargeFont or "Friz Quadrata TT")
        chargeFontDrop:SetFullWidth(true)
        chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontDrop)

        local chargeOutlineDrop = AceGUI:Create("Dropdown")
        chargeOutlineDrop:SetLabel("Font Outline")
        chargeOutlineDrop:SetList(CS.outlineOptions)
        chargeOutlineDrop:SetValue(style.chargeFontOutline or "OUTLINE")
        chargeOutlineDrop:SetFullWidth(true)
        chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeOutlineDrop)

        local chargeFontColor = AceGUI:Create("ColorPicker")
        chargeFontColor:SetLabel("Font Color (Max Charges)")
        chargeFontColor:SetHasAlpha(true)
        local cfc = style.chargeFontColor or {1, 1, 1, 1}
        chargeFontColor:SetColor(cfc[1], cfc[2], cfc[3], cfc[4])
        chargeFontColor:SetFullWidth(true)
        chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColor)

        local chargeFontColorMissing = AceGUI:Create("ColorPicker")
        chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
        chargeFontColorMissing:SetHasAlpha(true)
        local cfcm = style.chargeFontColorMissing or {1, 1, 1, 1}
        chargeFontColorMissing:SetColor(cfcm[1], cfcm[2], cfcm[3], cfcm[4])
        chargeFontColorMissing:SetFullWidth(true)
        chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorMissing)

        local chargeFontColorZero = AceGUI:Create("ColorPicker")
        chargeFontColorZero:SetLabel("Font Color (Zero Charges)")
        chargeFontColorZero:SetHasAlpha(true)
        local cfcz = style.chargeFontColorZero or {1, 1, 1, 1}
        chargeFontColorZero:SetColor(cfcz[1], cfcz[2], cfcz[3], cfcz[4])
        chargeFontColorZero:SetFullWidth(true)
        chargeFontColorZero:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorZero:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorZero)

        local chargeAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local chargeAnchorDrop = AceGUI:Create("Dropdown")
        chargeAnchorDrop:SetLabel("Anchor")
        chargeAnchorDrop:SetList(chargeAnchorValues, CS.anchorPoints)
        chargeAnchorDrop:SetValue(style.chargeAnchor or "BOTTOMRIGHT")
        chargeAnchorDrop:SetFullWidth(true)
        chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeAnchorDrop)

        local chargeXSlider = AceGUI:Create("Slider")
        chargeXSlider:SetLabel("X Offset")
        chargeXSlider:SetSliderValues(-20, 20, 0.1)
        chargeXSlider:SetValue(style.chargeXOffset or -2)
        chargeXSlider:SetFullWidth(true)
        chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeXSlider)

        local chargeYSlider = AceGUI:Create("Slider")
        chargeYSlider:SetLabel("Y Offset")
        chargeYSlider:SetSliderValues(-20, 20, 0.1)
        chargeYSlider:SetValue(style.chargeYOffset or 2)
        chargeYSlider:SetFullWidth(true)
        chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeYSlider)
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
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(6, 24, 1)
        auraFontSizeSlider:SetValue(style.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(style.auraTextFont or "Friz Quadrata TT")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(style.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(true)
        local ac = style.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontColor)
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
        local asFontSizeSlider = AceGUI:Create("Slider")
        asFontSizeSlider:SetLabel("Font Size")
        asFontSizeSlider:SetSliderValues(8, 32, 1)
        asFontSizeSlider:SetValue(style.auraStackFontSize or 12)
        asFontSizeSlider:SetFullWidth(true)
        asFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontSizeSlider)

        local asFontDrop = AceGUI:Create("Dropdown")
        asFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(asFontDrop)
        asFontDrop:SetValue(style.auraStackFont or "Friz Quadrata TT")
        asFontDrop:SetFullWidth(true)
        asFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontDrop)

        local asOutlineDrop = AceGUI:Create("Dropdown")
        asOutlineDrop:SetLabel("Font Outline")
        asOutlineDrop:SetList(CS.outlineOptions)
        asOutlineDrop:SetValue(style.auraStackFontOutline or "OUTLINE")
        asOutlineDrop:SetFullWidth(true)
        asOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asOutlineDrop)

        local asFontColor = AceGUI:Create("ColorPicker")
        asFontColor:SetLabel("Font Color")
        asFontColor:SetHasAlpha(true)
        local asc = style.auraStackFontColor or {1, 1, 1, 1}
        asFontColor:SetColor(asc[1], asc[2], asc[3], asc[4])
        asFontColor:SetFullWidth(true)
        asFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraStackFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        asFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraStackFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontColor)

        local asAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            asAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local asAnchorDrop = AceGUI:Create("Dropdown")
        asAnchorDrop:SetLabel("Anchor")
        asAnchorDrop:SetList(asAnchorValues, CS.anchorPoints)
        asAnchorDrop:SetValue(style.auraStackAnchor or "BOTTOMLEFT")
        asAnchorDrop:SetFullWidth(true)
        asAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asAnchorDrop)

        local asXSlider = AceGUI:Create("Slider")
        asXSlider:SetLabel("X Offset")
        asXSlider:SetSliderValues(-20, 20, 0.1)
        asXSlider:SetValue(style.auraStackXOffset or 2)
        asXSlider:SetFullWidth(true)
        asXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asXSlider)

        local asYSlider = AceGUI:Create("Slider")
        asYSlider:SetLabel("Y Offset")
        asYSlider:SetSliderValues(-20, 20, 0.1)
        asYSlider:SetValue(style.auraStackYOffset or 2)
        asYSlider:SetFullWidth(true)
        asYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asYSlider)
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

        local readyColorPicker = AceGUI:Create("ColorPicker")
        readyColorPicker:SetLabel("Ready Text Color")
        readyColorPicker:SetHasAlpha(true)
        local rtc = style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
        readyColorPicker:SetColor(rtc[1], rtc[2], rtc[3], rtc[4])
        readyColorPicker:SetFullWidth(true)
        readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyColorPicker)

        local readyFontSizeSlider = AceGUI:Create("Slider")
        readyFontSizeSlider:SetLabel("Font Size")
        readyFontSizeSlider:SetSliderValues(6, 24, 1)
        readyFontSizeSlider:SetValue(style.barReadyFontSize or 12)
        readyFontSizeSlider:SetFullWidth(true)
        readyFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyFontSizeSlider)

        local readyFontDrop = AceGUI:Create("Dropdown")
        readyFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(readyFontDrop)
        readyFontDrop:SetValue(style.barReadyFont or "Friz Quadrata TT")
        readyFontDrop:SetFullWidth(true)
        readyFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyFontDrop)

        local readyOutlineDrop = AceGUI:Create("Dropdown")
        readyOutlineDrop:SetLabel("Font Outline")
        readyOutlineDrop:SetList(CS.outlineOptions)
        readyOutlineDrop:SetValue(style.barReadyFontOutline or "OUTLINE")
        readyOutlineDrop:SetFullWidth(true)
        readyOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyOutlineDrop)
    end

    -- Compact Mode toggle
    local compactCb = AceGUI:Create("CheckBox")
    compactCb:SetLabel("Compact Mode")
    compactCb:SetValue(group.compactLayout or false)
    compactCb:SetFullWidth(true)
    compactCb:SetCallback("OnValueChanged", function(widget, event, val)
        group.compactLayout = val or false
        CooldownCompanion:PopulateGroupButtons(CS.selectedGroup)
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then frame._layoutDirty = true end
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(compactCb)

    local compactAdvExpanded, compactAdvBtn = AddAdvancedToggle(compactCb, "compactLayout", tabInfoButtons, group.compactLayout)

    -- (?) tooltip for compact mode
    local compactInfo = CreateFrame("Button", nil, compactCb.frame)
    compactInfo:SetSize(16, 16)
    if group.compactLayout then
        compactInfo:SetPoint("LEFT", compactAdvBtn, "RIGHT", 4, 0)
    else
        compactInfo:SetPoint("LEFT", compactCb.checkbg, "RIGHT", compactCb.text:GetStringWidth() + 6, 0)
    end
    local compactInfoIcon = compactInfo:CreateTexture(nil, "OVERLAY")
    compactInfoIcon:SetSize(12, 12)
    compactInfoIcon:SetPoint("CENTER")
    compactInfoIcon:SetAtlas("QuestRepeatableTurnin")
    compactInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Compact Mode")
        GameTooltip:AddLine("When per-button visibility rules hide a button, shift remaining buttons to fill the gap and resize the group frame to fit visible buttons only.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    compactInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(tabInfoButtons, compactInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        compactInfo:Hide()
    end

    if compactAdvExpanded and group.compactLayout then
        local totalButtons = #group.buttons
        local maxVisSlider = AceGUI:Create("Slider")
        maxVisSlider:SetLabel("Max Visible Buttons")
        maxVisSlider:SetSliderValues(1, math.max(totalButtons, 1), 1)
        maxVisSlider:SetValue(group.maxVisibleButtons == 0 and totalButtons or group.maxVisibleButtons)
        maxVisSlider:SetFullWidth(true)
        maxVisSlider:SetCallback("OnValueChanged", function(widget, event, val)
            val = math.floor(val + 0.5)
            if val >= totalButtons then
                group.maxVisibleButtons = 0
            else
                group.maxVisibleButtons = val
            end
            local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
            if frame then frame._layoutDirty = true end
        end)
        container:AddChild(maxVisSlider)

        local maxVisInfo = CreateFrame("Button", nil, maxVisSlider.frame)
        maxVisInfo:SetSize(16, 16)
        maxVisInfo:SetPoint("LEFT", maxVisSlider.label, "CENTER", maxVisSlider.label:GetStringWidth() / 2 + 4, 0)
        local maxVisInfoIcon = maxVisInfo:CreateTexture(nil, "OVERLAY")
        maxVisInfoIcon:SetSize(12, 12)
        maxVisInfoIcon:SetPoint("CENTER")
        maxVisInfoIcon:SetAtlas("QuestRepeatableTurnin")
        maxVisInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Max Visible Buttons")
            GameTooltip:AddLine("Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        maxVisInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(tabInfoButtons, maxVisInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            maxVisInfo:Hide()
        end
    end

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
    -- Show Active Aura Glow
    -- ================================================================
    local barAuraEnableCb = AceGUI:Create("CheckBox")
    barAuraEnableCb:SetLabel("Show Active Aura Glow")
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
    BuildBarActiveAuraControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- barAuraAdvExpanded

    -- ================================================================
    -- Show Pandemic Glow
    -- ================================================================
    local pandemicIndicatorCb = AceGUI:Create("CheckBox")
    pandemicIndicatorCb:SetLabel("Show Pandemic Glow")
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
    BuildPandemicBarControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- barPandemicAdvExpanded

    -- ================================================================
    -- Desaturate on Cooldown
    -- ================================================================
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
    -- GCD Swipe
    -- ================================================================
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
