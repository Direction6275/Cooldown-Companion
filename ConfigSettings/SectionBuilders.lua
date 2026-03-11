local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreatePromoteButton = ST._CreatePromoteButton
local CreateRevertButton = ST._CreateRevertButton
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent

-- Module-level aliases
local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

------------------------------------------------------------------------
-- REUSABLE SECTION BUILDER FUNCTIONS
------------------------------------------------------------------------
-- Each builder takes (container, styleTable, refreshCallback) and adds
-- AceGUI widgets to the container, reading/writing values from styleTable.

local function BuildCooldownTextControls(container, styleTable, refreshCallback)
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(styleTable.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTextCb)

    if styleTable.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(8, 32, 1)
        fontSizeSlider:SetValue(styleTable.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFontSize = val
            refreshCallback()
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(styleTable.cooldownFont or "Friz Quadrata TT")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFont = val
            refreshCallback()
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(styleTable.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFontOutline = val
            refreshCallback()
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = styleTable.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.cooldownFontColor = {r, g, b, a}
            refreshCallback()
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.cooldownFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(cdFontColor)

        local cdAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            cdAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local cdAnchorDrop = AceGUI:Create("Dropdown")
        cdAnchorDrop:SetLabel("Anchor")
        cdAnchorDrop:SetList(cdAnchorValues, CS.anchorPoints)
        cdAnchorDrop:SetValue(styleTable.cooldownTextAnchor or "CENTER")
        cdAnchorDrop:SetFullWidth(true)
        cdAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownTextAnchor = val
            refreshCallback()
        end)
        container:AddChild(cdAnchorDrop)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        local cdXSlider = AceGUI:Create("Slider")
        cdXSlider:SetLabel("X Offset")
        cdXSlider:SetSliderValues(-20, 20, 0.1)
        cdXSlider:SetValue(styleTable.cooldownTextXOffset or 0)
        cdXSlider:SetFullWidth(true)
        cdXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownTextXOffset = val
            refreshCallback()
        end)
        container:AddChild(cdXSlider)

        local cdYSlider = AceGUI:Create("Slider")
        cdYSlider:SetLabel("Y Offset")
        cdYSlider:SetSliderValues(-20, 20, 0.1)
        cdYSlider:SetValue(styleTable.cooldownTextYOffset or 0)
        cdYSlider:SetFullWidth(true)
        cdYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownTextYOffset = val
            refreshCallback()
        end)
        container:AddChild(cdYSlider)

    end
end

local function BuildAuraTextControls(container, styleTable, refreshCallback)
    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Duration Text")
    auraTextCb:SetValue(styleTable.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    -- (?) tooltip for shared positioning note
    CreateInfoButton(auraTextCb.frame, auraTextCb.checkbg, "LEFT", "RIGHT", auraTextCb.text:GetStringWidth() + 4, 0, {
        "Shared Position",
        {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' below to use independent positions.", 1, 1, 1, true},
    }, auraTextCb)

    if styleTable.showAuraText ~= false then
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(8, 32, 1)
        auraFontSizeSlider:SetValue(styleTable.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFontSize = val
            refreshCallback()
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(styleTable.auraTextFont or "Friz Quadrata TT")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFont = val
            refreshCallback()
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(styleTable.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFontOutline = val
            refreshCallback()
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(true)
        local ac = styleTable.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.auraTextFontColor = {r, g, b, a}
            refreshCallback()
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.auraTextFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(auraFontColor)

        local sepPosCb = AceGUI:Create("CheckBox")
        sepPosCb:SetLabel("Separate Text Positions")
        sepPosCb:SetValue(styleTable.separateTextPositions or false)
        sepPosCb:SetFullWidth(true)
        sepPosCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.separateTextPositions = val
            refreshCallback()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(sepPosCb)

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0, {
            "Separate Text Positions",
            {"When enabled, aura duration text and cooldown text use independent positions. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
        }, sepPosCb)

        if styleTable.separateTextPositions then
            local atAnchorValues = {}
            for _, pt in ipairs(CS.anchorPoints) do
                atAnchorValues[pt] = CS.anchorPointLabels[pt]
            end
            local atAnchorDrop = AceGUI:Create("Dropdown")
            atAnchorDrop:SetLabel("Anchor")
            atAnchorDrop:SetList(atAnchorValues, CS.anchorPoints)
            atAnchorDrop:SetValue(styleTable.auraTextAnchor or "TOPLEFT")
            atAnchorDrop:SetFullWidth(true)
            atAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.auraTextAnchor = val
                refreshCallback()
            end)
            container:AddChild(atAnchorDrop)

            local atXSlider = AceGUI:Create("Slider")
            atXSlider:SetLabel("X Offset")
            atXSlider:SetSliderValues(-20, 20, 0.1)
            atXSlider:SetValue(styleTable.auraTextXOffset or 2)
            atXSlider:SetFullWidth(true)
            atXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.auraTextXOffset = val
                refreshCallback()
            end)
            container:AddChild(atXSlider)

            local atYSlider = AceGUI:Create("Slider")
            atYSlider:SetLabel("Y Offset")
            atYSlider:SetSliderValues(-20, 20, 0.1)
            atYSlider:SetValue(styleTable.auraTextYOffset or -2)
            atYSlider:SetFullWidth(true)
            atYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.auraTextYOffset = val
                refreshCallback()
            end)
            container:AddChild(atYSlider)
        end
    end
end

local function BuildAuraStackTextControls(container, styleTable, refreshCallback)
    local auraStackCb = AceGUI:Create("CheckBox")
    auraStackCb:SetLabel("Show Aura Stack Text")
    auraStackCb:SetValue(styleTable.showAuraStackText ~= false)
    auraStackCb:SetFullWidth(true)
    auraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraStackText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraStackCb)

    if styleTable.showAuraStackText ~= false then
        local asFontSizeSlider = AceGUI:Create("Slider")
        asFontSizeSlider:SetLabel("Font Size")
        asFontSizeSlider:SetSliderValues(8, 32, 1)
        asFontSizeSlider:SetValue(styleTable.auraStackFontSize or 12)
        asFontSizeSlider:SetFullWidth(true)
        asFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackFontSize = val
            refreshCallback()
        end)
        container:AddChild(asFontSizeSlider)

        local asFontDrop = AceGUI:Create("Dropdown")
        asFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(asFontDrop)
        asFontDrop:SetValue(styleTable.auraStackFont or "Friz Quadrata TT")
        asFontDrop:SetFullWidth(true)
        asFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackFont = val
            refreshCallback()
        end)
        container:AddChild(asFontDrop)

        local asOutlineDrop = AceGUI:Create("Dropdown")
        asOutlineDrop:SetLabel("Font Outline")
        asOutlineDrop:SetList(CS.outlineOptions)
        asOutlineDrop:SetValue(styleTable.auraStackFontOutline or "OUTLINE")
        asOutlineDrop:SetFullWidth(true)
        asOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackFontOutline = val
            refreshCallback()
        end)
        container:AddChild(asOutlineDrop)

        local asFontColor = AceGUI:Create("ColorPicker")
        asFontColor:SetLabel("Font Color")
        asFontColor:SetHasAlpha(true)
        local asc = styleTable.auraStackFontColor or {1, 1, 1, 1}
        asFontColor:SetColor(asc[1], asc[2], asc[3], asc[4])
        asFontColor:SetFullWidth(true)
        asFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.auraStackFontColor = {r, g, b, a}
            refreshCallback()
        end)
        asFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.auraStackFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(asFontColor)

        local asAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            asAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local asAnchorDrop = AceGUI:Create("Dropdown")
        asAnchorDrop:SetLabel("Anchor")
        asAnchorDrop:SetList(asAnchorValues, CS.anchorPoints)
        asAnchorDrop:SetValue(styleTable.auraStackAnchor or "BOTTOMLEFT")
        asAnchorDrop:SetFullWidth(true)
        asAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackAnchor = val
            refreshCallback()
        end)
        container:AddChild(asAnchorDrop)

        local asXSlider = AceGUI:Create("Slider")
        asXSlider:SetLabel("X Offset")
        asXSlider:SetSliderValues(-20, 20, 0.1)
        asXSlider:SetValue(styleTable.auraStackXOffset or 2)
        asXSlider:SetFullWidth(true)
        asXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackXOffset = val
            refreshCallback()
        end)
        container:AddChild(asXSlider)

        local asYSlider = AceGUI:Create("Slider")
        asYSlider:SetLabel("Y Offset")
        asYSlider:SetSliderValues(-20, 20, 0.1)
        asYSlider:SetValue(styleTable.auraStackYOffset or 2)
        asYSlider:SetFullWidth(true)
        asYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraStackYOffset = val
            refreshCallback()
        end)
        container:AddChild(asYSlider)
    end
end

local function BuildKeybindTextControls(container, styleTable, refreshCallback)
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel("Show Keybind Text")
    kbCb:SetValue(styleTable.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showKeybindText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kbCb)

    if styleTable.showKeybindText then
        local kbAnchorDrop = AceGUI:Create("Dropdown")
        kbAnchorDrop:SetLabel("Anchor")
        local kbAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            kbAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        kbAnchorDrop:SetList(kbAnchorValues, CS.anchorPoints)
        kbAnchorDrop:SetValue(styleTable.keybindAnchor or "TOPRIGHT")
        kbAnchorDrop:SetFullWidth(true)
        kbAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindAnchor = val
            refreshCallback()
        end)
        container:AddChild(kbAnchorDrop)

        local kbXSlider = AceGUI:Create("Slider")
        kbXSlider:SetLabel("X Offset")
        kbXSlider:SetSliderValues(-20, 20, 0.1)
        kbXSlider:SetValue(styleTable.keybindXOffset or -2)
        kbXSlider:SetFullWidth(true)
        kbXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindXOffset = val
            refreshCallback()
        end)
        container:AddChild(kbXSlider)

        local kbYSlider = AceGUI:Create("Slider")
        kbYSlider:SetLabel("Y Offset")
        kbYSlider:SetSliderValues(-20, 20, 0.1)
        kbYSlider:SetValue(styleTable.keybindYOffset or -2)
        kbYSlider:SetFullWidth(true)
        kbYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindYOffset = val
            refreshCallback()
        end)
        container:AddChild(kbYSlider)

        local kbFontSizeSlider = AceGUI:Create("Slider")
        kbFontSizeSlider:SetLabel("Font Size")
        kbFontSizeSlider:SetSliderValues(6, 24, 1)
        kbFontSizeSlider:SetValue(styleTable.keybindFontSize or 10)
        kbFontSizeSlider:SetFullWidth(true)
        kbFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFontSize = val
            refreshCallback()
        end)
        container:AddChild(kbFontSizeSlider)

        local kbFontDrop = AceGUI:Create("Dropdown")
        kbFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(kbFontDrop)
        kbFontDrop:SetValue(styleTable.keybindFont or "Friz Quadrata TT")
        kbFontDrop:SetFullWidth(true)
        kbFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFont = val
            refreshCallback()
        end)
        container:AddChild(kbFontDrop)

        local kbOutlineDrop = AceGUI:Create("Dropdown")
        kbOutlineDrop:SetLabel("Font Outline")
        kbOutlineDrop:SetList(CS.outlineOptions)
        kbOutlineDrop:SetValue(styleTable.keybindFontOutline or "OUTLINE")
        kbOutlineDrop:SetFullWidth(true)
        kbOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFontOutline = val
            refreshCallback()
        end)
        container:AddChild(kbOutlineDrop)

        local kbFontColor = AceGUI:Create("ColorPicker")
        kbFontColor:SetLabel("Font Color")
        kbFontColor:SetHasAlpha(true)
        local kbc = styleTable.keybindFontColor or {1, 1, 1, 1}
        kbFontColor:SetColor(kbc[1], kbc[2], kbc[3], kbc[4])
        kbFontColor:SetFullWidth(true)
        kbFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.keybindFontColor = {r, g, b, a}
            refreshCallback()
        end)
        kbFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.keybindFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(kbFontColor)
    end
end

local function BuildChargeTextControls(container, styleTable, refreshCallback)
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Charge Text")
    chargeTextCb:SetValue(styleTable.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showChargeText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    if styleTable.showChargeText ~= false then
        local chargeFontSizeSlider = AceGUI:Create("Slider")
        chargeFontSizeSlider:SetLabel("Font Size")
        chargeFontSizeSlider:SetSliderValues(8, 32, 1)
        chargeFontSizeSlider:SetValue(styleTable.chargeFontSize or 12)
        chargeFontSizeSlider:SetFullWidth(true)
        chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFontSize = val
            refreshCallback()
        end)
        container:AddChild(chargeFontSizeSlider)

        local chargeFontDrop = AceGUI:Create("Dropdown")
        chargeFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(chargeFontDrop)
        chargeFontDrop:SetValue(styleTable.chargeFont or "Friz Quadrata TT")
        chargeFontDrop:SetFullWidth(true)
        chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFont = val
            refreshCallback()
        end)
        container:AddChild(chargeFontDrop)

        local chargeOutlineDrop = AceGUI:Create("Dropdown")
        chargeOutlineDrop:SetLabel("Font Outline")
        chargeOutlineDrop:SetList(CS.outlineOptions)
        chargeOutlineDrop:SetValue(styleTable.chargeFontOutline or "OUTLINE")
        chargeOutlineDrop:SetFullWidth(true)
        chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFontOutline = val
            refreshCallback()
        end)
        container:AddChild(chargeOutlineDrop)

        local chargeFontColor = AceGUI:Create("ColorPicker")
        chargeFontColor:SetLabel("Font Color (Max Charges)")
        chargeFontColor:SetHasAlpha(true)
        local cfc = styleTable.chargeFontColor or {1, 1, 1, 1}
        chargeFontColor:SetColor(cfc[1], cfc[2], cfc[3], cfc[4])
        chargeFontColor:SetFullWidth(true)
        chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColor = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColor)

        local chargeFontColorMissing = AceGUI:Create("ColorPicker")
        chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
        chargeFontColorMissing:SetHasAlpha(true)
        local cfcm = styleTable.chargeFontColorMissing or {1, 1, 1, 1}
        chargeFontColorMissing:SetColor(cfcm[1], cfcm[2], cfcm[3], cfcm[4])
        chargeFontColorMissing:SetFullWidth(true)
        chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorMissing = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorMissing = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColorMissing)

        local chargeFontColorZero = AceGUI:Create("ColorPicker")
        chargeFontColorZero:SetLabel("Font Color (Zero Charges)")
        chargeFontColorZero:SetHasAlpha(true)
        local cfcz = styleTable.chargeFontColorZero or {1, 1, 1, 1}
        chargeFontColorZero:SetColor(cfcz[1], cfcz[2], cfcz[3], cfcz[4])
        chargeFontColorZero:SetFullWidth(true)
        chargeFontColorZero:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorZero = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColorZero:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorZero = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColorZero)

        local chargeAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local chargeAnchorDrop = AceGUI:Create("Dropdown")
        chargeAnchorDrop:SetLabel("Anchor")
        chargeAnchorDrop:SetList(chargeAnchorValues, CS.anchorPoints)
        chargeAnchorDrop:SetValue(styleTable.chargeAnchor or "BOTTOMRIGHT")
        chargeAnchorDrop:SetFullWidth(true)
        chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeAnchor = val
            refreshCallback()
        end)
        container:AddChild(chargeAnchorDrop)

        local chargeXSlider = AceGUI:Create("Slider")
        chargeXSlider:SetLabel("X Offset")
        chargeXSlider:SetSliderValues(-20, 20, 0.1)
        chargeXSlider:SetValue(styleTable.chargeXOffset or -2)
        chargeXSlider:SetFullWidth(true)
        chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeXOffset = val
            refreshCallback()
        end)
        container:AddChild(chargeXSlider)

        local chargeYSlider = AceGUI:Create("Slider")
        chargeYSlider:SetLabel("Y Offset")
        chargeYSlider:SetSliderValues(-20, 20, 0.1)
        chargeYSlider:SetValue(styleTable.chargeYOffset or 2)
        chargeYSlider:SetFullWidth(true)
        chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeYOffset = val
            refreshCallback()
        end)
        container:AddChild(chargeYSlider)
    end
end

local function BuildBorderControls(container, styleTable, refreshCallback)
    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(styleTable.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.borderSize = val
        refreshCallback()
    end)
    container:AddChild(borderSlider)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = styleTable.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.borderColor = {r, g, b, a}
        refreshCallback()
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.borderColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(borderColor)
end

local function BuildBackgroundColorControls(container, styleTable, refreshCallback)
    local bgColor = AceGUI:Create("ColorPicker")
    bgColor:SetLabel("Background Color")
    bgColor:SetHasAlpha(true)
    local bgc = styleTable.backgroundColor or {0, 0, 0, 0.5}
    bgColor:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    bgColor:SetFullWidth(true)
    bgColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.backgroundColor = {r, g, b, a}
        refreshCallback()
    end)
    bgColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.backgroundColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(bgColor)
end

local function BuildDesaturationControls(container, styleTable, refreshCallback)
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Show Desaturate On Cooldown")
    desatCb:SetValue(styleTable.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.desaturateOnCooldown = val
        refreshCallback()
    end)
    container:AddChild(desatCb)
end

local function BuildShowTooltipsControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Tooltips")
    cb:SetValue(styleTable.showTooltips == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showTooltips = val
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildShowOutOfRangeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Out of Range")
    cb:SetValue(styleTable.showOutOfRange or false)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showOutOfRange = val
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildShowGCDSwipeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show GCD Swipe")
    cb:SetValue(styleTable.showGCDSwipe == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showGCDSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)
end

local function BuildCooldownSwipeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Cooldown/Duration Swipe")
    cb:SetValue(styleTable.showCooldownSwipe ~= false)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)

    local reverseCb = AceGUI:Create("CheckBox")
    reverseCb:SetLabel("Reverse Swipe")
    reverseCb:SetValue(styleTable.cooldownSwipeReverse or false)
    reverseCb:SetFullWidth(true)
    reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.cooldownSwipeReverse = val
        refreshCallback()
    end)
    container:AddChild(reverseCb)
    ApplyCheckboxIndent(reverseCb, 20)

    local fillCb = AceGUI:Create("CheckBox")
    fillCb:SetLabel("Show Swipe Fill")
    fillCb:SetValue(styleTable.showCooldownSwipeFill ~= false)
    fillCb:SetFullWidth(true)
    fillCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownSwipeFill = val
        refreshCallback()
    end)
    container:AddChild(fillCb)
    ApplyCheckboxIndent(fillCb, 20)

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showCooldownSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
    end)
    container:AddChild(edgeCb)
    ApplyCheckboxIndent(edgeCb, 20)
end

local function BuildLossOfControlControls(container, styleTable, refreshCallback)
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(styleTable.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showLossOfControl = val
        refreshCallback()
    end)
    container:AddChild(locCb)
    return locCb
end

local function BuildUnusableDimmingControls(container, styleTable, refreshCallback)
    local unusableCb = AceGUI:Create("CheckBox")
    unusableCb:SetLabel("Show Unusable Dimming")
    unusableCb:SetValue(styleTable.showUnusable or false)
    unusableCb:SetFullWidth(true)
    unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showUnusable = val
        refreshCallback()
    end)
    container:AddChild(unusableCb)
    return unusableCb
end

local function BuildAssistedHighlightControls(container, styleTable, refreshCallback, opts)
    local hostileOnlyCb = AceGUI:Create("CheckBox")
    hostileOnlyCb:SetLabel("Hostile Target Only")
    hostileOnlyCb:SetValue(styleTable.assistedHighlightHostileTargetOnly ~= false)
    hostileOnlyCb:SetFullWidth(true)
    hostileOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightHostileTargetOnly = val
        refreshCallback()
    end)
    container:AddChild(hostileOnlyCb)
    if not (opts and opts.isOverride) then
        ApplyCheckboxIndent(hostileOnlyCb, 20)
    end

    local highlightStyles = {
        blizzard = "Blizzard (Marching Ants)",
        proc = "Proc Glow",
        solid = "Solid Border",
    }
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Highlight Style")
    styleDrop:SetList(highlightStyles)
    styleDrop:SetValue(styleTable.assistedHighlightStyle or "blizzard")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    if styleTable.assistedHighlightStyle == "solid" then
        local hlColor = AceGUI:Create("ColorPicker")
        hlColor:SetLabel("Highlight Color")
        hlColor:SetHasAlpha(true)
        local c = styleTable.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
        hlColor:SetColor(c[1], c[2], c[3], c[4])
        hlColor:SetFullWidth(true)
        hlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.assistedHighlightColor = {r, g, b, a}
            refreshCallback()
        end)
        hlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.assistedHighlightColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(hlColor)

        local hlSizeSlider = AceGUI:Create("Slider")
        hlSizeSlider:SetLabel("Border Size")
        hlSizeSlider:SetSliderValues(1, 6, 0.1)
        hlSizeSlider:SetValue(styleTable.assistedHighlightBorderSize or 2)
        hlSizeSlider:SetFullWidth(true)
        hlSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBorderSize = val
            refreshCallback()
        end)
        container:AddChild(hlSizeSlider)
    elseif styleTable.assistedHighlightStyle == "blizzard" then
        local blizzSlider = AceGUI:Create("Slider")
        blizzSlider:SetLabel("Glow Size")
        blizzSlider:SetSliderValues(0, 60, 0.1)
        blizzSlider:SetValue(styleTable.assistedHighlightBlizzardOverhang or 32)
        blizzSlider:SetFullWidth(true)
        blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBlizzardOverhang = val
            refreshCallback()
        end)
        container:AddChild(blizzSlider)
    elseif styleTable.assistedHighlightStyle == "proc" then
        local procHlColor = AceGUI:Create("ColorPicker")
        procHlColor:SetLabel("Glow Color")
        procHlColor:SetHasAlpha(true)
        local phc = styleTable.assistedHighlightProcColor or {1, 1, 1, 1}
        procHlColor:SetColor(phc[1], phc[2], phc[3], phc[4])
        procHlColor:SetFullWidth(true)
        procHlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.assistedHighlightProcColor = {r, g, b, a}
            refreshCallback()
        end)
        procHlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.assistedHighlightProcColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(procHlColor)

        local procSlider = AceGUI:Create("Slider")
        procSlider:SetLabel("Glow Size")
        procSlider:SetSliderValues(0, 60, 0.1)
        procSlider:SetValue(styleTable.assistedHighlightProcOverhang or 32)
        procSlider:SetFullWidth(true)
        procSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightProcOverhang = val
            refreshCallback()
        end)
        container:AddChild(procSlider)
    end
end

------------------------------------------------------------------------
-- GENERIC GLOW/EFFECT HELPERS
------------------------------------------------------------------------
-- Shared slider block used by both glow style controls and bar effect
-- controls. Builds conditional size/thickness/speed sliders based on
-- the current glow style.
--
-- keys = { size = "...", thickness = "...", speed = "..." }
-- pixelSizeMin: minimum for the pixel "Line Length" slider (1 for glow
--   style controls, 2 for bar effect controls)
local function BuildGlowSliders(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin)
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(pixelSizeMin, 12, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable[keys.thickness] or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.thickness] = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "lcgButton" then
        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Frequency")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "lcgAutoCast" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Particle Scale")
        sizeSlider:SetSliderValues(0.2, 3, 0.05)
        local currentScale = styleTable[keys.size]
        if not currentScale or currentScale < 0.2 or currentScale > 3 then
            currentScale = 1
        end
        sizeSlider:SetValue(currentScale)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Frequency")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    end
end

-- Legacy profile compatibility: lcgProc was removed because it duplicated Blizzard glow.
local function NormalizeLegacyGlowStyle(style)
    if style == "lcgProc" then
        return "glow"
    end
    return style
end

local LCG_GLOW_STYLE_OPTIONS = {
    ["solid"] = "Solid Border",
    ["pixel"] = "Pixel Glow",
    ["glow"] = "Glow (Blizzard)",
    ["lcgButton"] = "Action Button Glow",
    ["lcgAutoCast"] = "Autocast Shine",
}
local LCG_GLOW_STYLE_ORDER = {"solid", "pixel", "glow", "lcgButton", "lcgAutoCast"}

-- Generic glow style builder (Group A): style dropdown + color picker +
-- conditional sliders. Replaces BuildProcGlowControls,
-- BuildPandemicGlowControls, BuildAuraIndicatorControls.
--
-- cfg = { styleKey, colorKey, colorLabel, sizeKey, thicknessKey,
--         speedKey, defaultStyle, defaultColor }
local function BuildGlowStyleControls(container, styleTable, refreshCallback, cfg, opts)
    local isOverrideMode = opts and opts.isOverride == true
    local isEnabled
    if cfg.enableKey then
        local enabledVal = styleTable[cfg.enableKey]
        if enabledVal == nil and opts and opts.fallbackStyle then
            enabledVal = opts.fallbackStyle[cfg.enableKey]
        end
        isEnabled = enabledVal ~= false
    else
        isEnabled = styleTable[cfg.styleKey] ~= "none"
    end

    if isOverrideMode and cfg.enableLabel then
        local enableCb = AceGUI:Create("CheckBox")
        enableCb:SetLabel(cfg.enableLabel)
        enableCb:SetValue(isEnabled)
        enableCb:SetFullWidth(true)
        enableCb:SetCallback("OnValueChanged", function(widget, event, val)
            if cfg.enableKey then
                styleTable[cfg.enableKey] = val
                if val and styleTable[cfg.styleKey] == "none" then
                    styleTable[cfg.styleKey] = cfg.defaultStyle
                end
            else
                styleTable[cfg.styleKey] = val and cfg.defaultStyle or "none"
            end
            refreshCallback()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(enableCb)

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(container)
    end

    if styleTable[cfg.styleKey] == "lcgProc" then
        styleTable[cfg.styleKey] = "glow"
    end
    local currentStyle = NormalizeLegacyGlowStyle(styleTable[cfg.styleKey] or cfg.defaultStyle)
    if currentStyle == "none" then
        currentStyle = cfg.defaultStyle
    end

    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    local styleOptions = cfg.styleOptions or {
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }
    local styleOrder = cfg.styleOrder or {"solid", "pixel", "glow"}
    styleDrop:SetList(styleOptions, styleOrder)
    styleDrop:SetValue(currentStyle)
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if cfg.enableKey then
            styleTable[cfg.enableKey] = true
        end
        styleTable[cfg.styleKey] = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    local colorPicker = AceGUI:Create("ColorPicker")
    colorPicker:SetLabel(cfg.colorLabel)
    colorPicker:SetHasAlpha(true)
    local c = styleTable[cfg.colorKey] or cfg.defaultColor
    colorPicker:SetColor(c[1], c[2], c[3], c[4])
    colorPicker:SetFullWidth(true)
    colorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable[cfg.colorKey] = {r, g, b, a}
        refreshCallback()
    end)
    colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable[cfg.colorKey] = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(colorPicker)

    BuildGlowSliders(container, styleTable, currentStyle, {
        size = cfg.sizeKey, thickness = cfg.thicknessKey, speed = cfg.speedKey,
    }, refreshCallback, 1)
end

-- Generic bar effect builder (Group B): primary color picker + effect
-- dropdown (none/pixel/solid/glow) + conditional effect color +
-- conditional sliders. Replaces BuildPandemicBarControls,
-- BuildBarActiveAuraControls.
--
-- cfg = { colorKey, colorLabel, defaultColor, effectKey, effectLabel,
--         effectColorKey, effectColorLabel, defaultEffectColor,
--         effectSizeKey, effectThicknessKey, effectSpeedKey }
local function BuildBarEffectControls(container, styleTable, refreshCallback, cfg, opts)
    local isOverrideMode = opts and opts.isOverride == true
    local isEnabled
    if cfg.enableKey then
        local enabledVal = styleTable[cfg.enableKey]
        if enabledVal == nil and opts and opts.fallbackStyle then
            enabledVal = opts.fallbackStyle[cfg.enableKey]
        end
        isEnabled = enabledVal ~= false
    else
        isEnabled = (styleTable[cfg.effectKey] or "none") ~= "none"
    end

    if isOverrideMode and cfg.enableLabel then
        local enableCb = AceGUI:Create("CheckBox")
        enableCb:SetLabel(cfg.enableLabel)
        enableCb:SetValue(isEnabled)
        enableCb:SetFullWidth(true)
        enableCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.enableKey] = val
            refreshCallback()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(enableCb)

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(container)
    end

    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel(cfg.colorLabel)
    barColorPicker:SetHasAlpha(true)
    local bc = styleTable[cfg.colorKey] or cfg.defaultColor
    barColorPicker:SetColor(bc[1], bc[2], bc[3], bc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable[cfg.colorKey] = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable[cfg.colorKey] = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel(cfg.effectLabel)
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
        ["glow"] = "Proc Glow",
    }, {"none", "pixel", "solid", "glow"})
    effectDrop:SetValue(styleTable[cfg.effectKey] or "none")
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable[cfg.effectKey] = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(effectDrop)

    local currentEffect = styleTable[cfg.effectKey] or "none"
    if currentEffect ~= "none" then
        local effectColorPicker = AceGUI:Create("ColorPicker")
        effectColorPicker:SetLabel(cfg.effectColorLabel)
        effectColorPicker:SetHasAlpha(true)
        local ec = styleTable[cfg.effectColorKey] or cfg.defaultEffectColor
        effectColorPicker:SetColor(ec[1], ec[2], ec[3], ec[4])
        effectColorPicker:SetFullWidth(true)
        effectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable[cfg.effectColorKey] = {r, g, b, a}
            refreshCallback()
        end)
        effectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable[cfg.effectColorKey] = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(effectColorPicker)

        BuildGlowSliders(container, styleTable, currentEffect, {
            size = cfg.effectSizeKey, thickness = cfg.effectThicknessKey, speed = cfg.effectSpeedKey,
        }, refreshCallback, 2)
    end
end

------------------------------------------------------------------------
-- PUBLIC GLOW/EFFECT WRAPPERS (same signatures as original functions)
------------------------------------------------------------------------
local function BuildProcGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "procGlowStyle", colorKey = "procGlowColor", colorLabel = "Glow Color",
        sizeKey = "procGlowSize", thicknessKey = "procGlowThickness", speedKey = "procGlowSpeed",
        defaultStyle = "glow", defaultColor = {1, 1, 1, 1},
        enableLabel = "Show Proc Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildPandemicGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "pandemicGlowStyle", colorKey = "pandemicGlowColor", colorLabel = "Glow Color",
        sizeKey = "pandemicGlowSize", thicknessKey = "pandemicGlowThickness", speedKey = "pandemicGlowSpeed",
        defaultStyle = "solid", defaultColor = {1, 0.5, 0, 1},
        enableKey = "showPandemicGlow", enableLabel = "Show Pandemic Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildAuraIndicatorControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "auraGlowStyle", colorKey = "auraGlowColor", colorLabel = "Indicator Color",
        sizeKey = "auraGlowSize", thicknessKey = "auraGlowThickness", speedKey = "auraGlowSpeed",
        defaultStyle = "pixel", defaultColor = {1, 0.84, 0, 0.9},
        enableLabel = "Show Aura Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildReadyGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "readyGlowStyle", colorKey = "readyGlowColor", colorLabel = "Glow Color",
        sizeKey = "readyGlowSize", thicknessKey = "readyGlowThickness", speedKey = "readyGlowSpeed",
        defaultStyle = "solid", defaultColor = {0.2, 1.0, 0.2, 1},
        enableLabel = "Show Ready Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildPandemicBarControls(container, styleTable, refreshCallback, opts)
    BuildBarEffectControls(container, styleTable, refreshCallback, {
        colorKey = "barPandemicColor", colorLabel = "Pandemic Bar Color",
        defaultColor = {1, 0.5, 0, 1},
        enableKey = "showPandemicGlow", enableLabel = "Show Pandemic Color/Glow",
        effectKey = "pandemicBarEffect", effectLabel = "Pandemic Effect",
        effectColorKey = "pandemicBarEffectColor", effectColorLabel = "Pandemic Effect Color",
        defaultEffectColor = {1, 0.5, 0, 1},
        effectSizeKey = "pandemicBarEffectSize", effectThicknessKey = "pandemicBarEffectThickness",
        effectSpeedKey = "pandemicBarEffectSpeed",
    }, opts)
end

local function BuildBarActiveAuraControls(container, styleTable, refreshCallback, opts)
    BuildBarEffectControls(container, styleTable, refreshCallback, {
        colorKey = "barAuraColor", colorLabel = "Active Aura Bar Color",
        defaultColor = {0.2, 1.0, 0.2, 1.0},
        effectKey = "barAuraEffect", effectLabel = "Active Aura Effect",
        effectColorKey = "barAuraEffectColor", effectColorLabel = "Effect Color",
        defaultEffectColor = {1, 0.84, 0, 0.9},
        effectSizeKey = "barAuraEffectSize", effectThicknessKey = "barAuraEffectThickness",
        effectSpeedKey = "barAuraEffectSpeed",
    }, opts)
end

local function BuildBarColorsControls(container, styleTable, refreshCallback)
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Bar Color")
    barColorPicker:SetHasAlpha(true)
    local brc = styleTable.barColor or {0.2, 0.6, 1.0, 1.0}
    barColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    local barCdColorPicker = AceGUI:Create("ColorPicker")
    barCdColorPicker:SetLabel("Bar Cooldown Color")
    barCdColorPicker:SetHasAlpha(true)
    local bcc = styleTable.barCooldownColor or {0.6, 0.6, 0.6, 1.0}
    barCdColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
    barCdColorPicker:SetFullWidth(true)
    barCdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    barCdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barCdColorPicker)

    local barChargeColorPicker = AceGUI:Create("ColorPicker")
    barChargeColorPicker:SetLabel("Bar Recharging Color")
    barChargeColorPicker:SetHasAlpha(true)
    local bchc = styleTable.barChargeColor or {1.0, 0.82, 0.0, 1.0}
    barChargeColorPicker:SetColor(bchc[1], bchc[2], bchc[3], bchc[4])
    barChargeColorPicker:SetFullWidth(true)
    barChargeColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barChargeColor = {r, g, b, a}
        refreshCallback()
    end)
    barChargeColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barChargeColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barChargeColorPicker)

    local barBgColorPicker = AceGUI:Create("ColorPicker")
    barBgColorPicker:SetLabel("Bar Background Color")
    barBgColorPicker:SetHasAlpha(true)
    local bbg = styleTable.barBgColor or {0.1, 0.1, 0.1, 0.8}
    barBgColorPicker:SetColor(bbg[1], bbg[2], bbg[3], bbg[4])
    barBgColorPicker:SetFullWidth(true)
    barBgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barBgColor = {r, g, b, a}
        refreshCallback()
    end)
    barBgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barBgColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barBgColorPicker)
end

local function BuildBarNameTextControls(container, styleTable, refreshCallback)
    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(styleTable.showBarNameText ~= false)
    showNameCb:SetFullWidth(true)
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarNameText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showNameCb)

    if styleTable.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(styleTable.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameTextReverse = val
            refreshCallback()
        end)
        container:AddChild(flipNameCheck)

        local nameFontSizeSlider = AceGUI:Create("Slider")
        nameFontSizeSlider:SetLabel("Font Size")
        nameFontSizeSlider:SetSliderValues(6, 24, 1)
        nameFontSizeSlider:SetValue(styleTable.barNameFontSize or 10)
        nameFontSizeSlider:SetFullWidth(true)
        nameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFontSize = val
            refreshCallback()
        end)
        container:AddChild(nameFontSizeSlider)

        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(nameFontDrop)
        nameFontDrop:SetValue(styleTable.barNameFont or "Friz Quadrata TT")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFont = val
            refreshCallback()
        end)
        container:AddChild(nameFontDrop)

        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Font Outline")
        nameOutlineDrop:SetList(CS.outlineOptions)
        nameOutlineDrop:SetValue(styleTable.barNameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFontOutline = val
            refreshCallback()
        end)
        container:AddChild(nameOutlineDrop)

        local nameFontColor = AceGUI:Create("ColorPicker")
        nameFontColor:SetLabel("Font Color")
        nameFontColor:SetHasAlpha(true)
        local nfc = styleTable.barNameFontColor or {1, 1, 1, 1}
        nameFontColor:SetColor(nfc[1], nfc[2], nfc[3], nfc[4])
        nameFontColor:SetFullWidth(true)
        nameFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barNameFontColor = {r, g, b, a}
            refreshCallback()
        end)
        nameFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barNameFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(nameFontColor)
    end
end

local function BuildBarReadyTextControls(container, styleTable, refreshCallback)
    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(styleTable.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarReadyText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showReadyCb)

    if styleTable.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.barReadyText = val
            refreshCallback()
        end)
        container:AddChild(readyTextBox)

        local readyColorPicker = AceGUI:Create("ColorPicker")
        readyColorPicker:SetLabel("Ready Text Color")
        readyColorPicker:SetHasAlpha(true)
        local rtc = styleTable.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
        readyColorPicker:SetColor(rtc[1], rtc[2], rtc[3], rtc[4])
        readyColorPicker:SetFullWidth(true)
        readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barReadyTextColor = {r, g, b, a}
            refreshCallback()
        end)
        readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barReadyTextColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(readyColorPicker)

        local readyFontSizeSlider = AceGUI:Create("Slider")
        readyFontSizeSlider:SetLabel("Font Size")
        readyFontSizeSlider:SetSliderValues(6, 24, 1)
        readyFontSizeSlider:SetValue(styleTable.barReadyFontSize or 12)
        readyFontSizeSlider:SetFullWidth(true)
        readyFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFontSize = val
            refreshCallback()
        end)
        container:AddChild(readyFontSizeSlider)

        local readyFontDrop = AceGUI:Create("Dropdown")
        readyFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(readyFontDrop)
        readyFontDrop:SetValue(styleTable.barReadyFont or "Friz Quadrata TT")
        readyFontDrop:SetFullWidth(true)
        readyFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFont = val
            refreshCallback()
        end)
        container:AddChild(readyFontDrop)

        local readyOutlineDrop = AceGUI:Create("Dropdown")
        readyOutlineDrop:SetLabel("Font Outline")
        readyOutlineDrop:SetList(CS.outlineOptions)
        readyOutlineDrop:SetValue(styleTable.barReadyFontOutline or "OUTLINE")
        readyOutlineDrop:SetFullWidth(true)
        readyOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFontOutline = val
            refreshCallback()
        end)
        container:AddChild(readyOutlineDrop)
    end
end

------------------------------------------------------------------------
-- Text Mode — Text Colors
------------------------------------------------------------------------
local function BuildTextBackgroundControls(container, styleTable, refreshCallback)
    local bgColorPicker = AceGUI:Create("ColorPicker")
    bgColorPicker:SetLabel("Background Color")
    bgColorPicker:SetHasAlpha(true)
    local bg = styleTable.textBgColor or {0, 0, 0, 0}
    bgColorPicker:SetColor(bg[1], bg[2], bg[3], bg[4])
    bgColorPicker:SetFullWidth(true)
    bgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textBgColor = {r, g, b, a}
        refreshCallback()
    end)
    bgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textBgColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(bgColorPicker)

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(styleTable.textBorderSize or 0)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textBorderSize = val
        refreshCallback()
    end)
    container:AddChild(borderSlider)

    local borderColorPicker = AceGUI:Create("ColorPicker")
    borderColorPicker:SetLabel("Border Color")
    borderColorPicker:SetHasAlpha(true)
    local bc = styleTable.textBorderColor or {0, 0, 0, 1}
    borderColorPicker:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColorPicker:SetFullWidth(true)
    borderColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textBorderColor = {r, g, b, a}
        refreshCallback()
    end)
    borderColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textBorderColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(borderColorPicker)
end

local function BuildTextFontControls(container, styleTable, refreshCallback)
    local fontDrop = AceGUI:Create("Dropdown")
    fontDrop:SetLabel("Font")
    CS.SetupFontDropdown(fontDrop)
    fontDrop:SetValue(styleTable.textFont or "Friz Quadrata TT")
    fontDrop:SetFullWidth(true)
    fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textFont = val
        refreshCallback()
    end)
    container:AddChild(fontDrop)

    local outlineDrop = AceGUI:Create("Dropdown")
    outlineDrop:SetLabel("Font Outline")
    outlineDrop:SetList(CS.outlineOptions)
    outlineDrop:SetValue(styleTable.textFontOutline or "OUTLINE")
    outlineDrop:SetFullWidth(true)
    outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textFontOutline = val
        refreshCallback()
    end)
    container:AddChild(outlineDrop)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({LEFT = "Left", CENTER = "Center", RIGHT = "Right"})
    alignDrop:SetValue(styleTable.textAlignment or "LEFT")
    alignDrop:SetFullWidth(true)
    alignDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textAlignment = val
        refreshCallback()
    end)
    container:AddChild(alignDrop)

    local shadowCb = AceGUI:Create("CheckBox")
    shadowCb:SetLabel("Text Shadow")
    shadowCb:SetValue(styleTable.textShadow == true)
    shadowCb:SetFullWidth(true)
    shadowCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textShadow = val or false
        refreshCallback()
    end)
    container:AddChild(shadowCb)
end

local function BuildTextColorsControls(container, styleTable, refreshCallback)
    local textColorPicker = AceGUI:Create("ColorPicker")
    textColorPicker:SetLabel("Text Color")
    textColorPicker:SetHasAlpha(true)
    local tc = styleTable.textFontColor or {1, 1, 1, 1}
    textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
    textColorPicker:SetFullWidth(true)
    textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textFontColor = {r, g, b, a}
        refreshCallback()
    end)
    textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textFontColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(textColorPicker)

    local cdColorPicker = AceGUI:Create("ColorPicker")
    cdColorPicker:SetLabel("Cooldown Color")
    cdColorPicker:SetHasAlpha(true)
    local cdc = styleTable.textCooldownColor or {1, 0.3, 0.3, 1}
    cdColorPicker:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
    cdColorPicker:SetFullWidth(true)
    cdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    cdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(cdColorPicker)

    local readyColorPicker = AceGUI:Create("ColorPicker")
    readyColorPicker:SetLabel("Ready Color")
    readyColorPicker:SetHasAlpha(true)
    local rc = styleTable.textReadyColor or {0.2, 1.0, 0.2, 1}
    readyColorPicker:SetColor(rc[1], rc[2], rc[3], rc[4])
    readyColorPicker:SetFullWidth(true)
    readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textReadyColor = {r, g, b, a}
        refreshCallback()
    end)
    readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textReadyColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(readyColorPicker)

    local readyAdvExpanded, readyAdvBtn = AddAdvancedToggle(readyColorPicker, "textReadyText", tabInfoButtons)
    readyAdvBtn:SetPoint("LEFT", readyColorPicker.colorSwatch, "RIGHT", readyColorPicker.text:GetStringWidth() + 8, 0)

    if readyAdvExpanded then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.textReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.textReadyText = val
            refreshCallback()
        end)
        container:AddChild(readyTextBox)
    end

    local auraColorPicker = AceGUI:Create("ColorPicker")
    auraColorPicker:SetLabel("Aura Color")
    auraColorPicker:SetHasAlpha(true)
    local ac = styleTable.textAuraColor or {0, 0.925, 1, 1}
    auraColorPicker:SetColor(ac[1], ac[2], ac[3], ac[4])
    auraColorPicker:SetFullWidth(true)
    auraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.textAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    auraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.textAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(auraColorPicker)
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildCooldownTextControls = BuildCooldownTextControls
ST._BuildAuraTextControls = BuildAuraTextControls
ST._BuildAuraStackTextControls = BuildAuraStackTextControls
ST._BuildKeybindTextControls = BuildKeybindTextControls
ST._BuildChargeTextControls = BuildChargeTextControls
ST._BuildBorderControls = BuildBorderControls
ST._BuildBackgroundColorControls = BuildBackgroundColorControls
ST._BuildDesaturationControls = BuildDesaturationControls
ST._BuildShowTooltipsControls = BuildShowTooltipsControls
ST._BuildShowOutOfRangeControls = BuildShowOutOfRangeControls
ST._BuildShowGCDSwipeControls = BuildShowGCDSwipeControls
ST._BuildCooldownSwipeControls = BuildCooldownSwipeControls
ST._BuildLossOfControlControls = BuildLossOfControlControls
ST._BuildUnusableDimmingControls = BuildUnusableDimmingControls
ST._BuildAssistedHighlightControls = BuildAssistedHighlightControls
ST._BuildProcGlowControls = BuildProcGlowControls
ST._BuildPandemicGlowControls = BuildPandemicGlowControls
ST._BuildPandemicBarControls = BuildPandemicBarControls
ST._BuildAuraIndicatorControls = BuildAuraIndicatorControls
ST._BuildReadyGlowControls = BuildReadyGlowControls
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildBarColorsControls = BuildBarColorsControls
ST._BuildBarNameTextControls = BuildBarNameTextControls
ST._BuildBarReadyTextControls = BuildBarReadyTextControls
ST._BuildTextFontControls = BuildTextFontControls
ST._BuildTextColorsControls = BuildTextColorsControls
ST._BuildTextBackgroundControls = BuildTextBackgroundControls
