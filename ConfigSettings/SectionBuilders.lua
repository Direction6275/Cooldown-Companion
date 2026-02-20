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
        local cdPosInfo = CreateFrame("Button", nil, cdAnchorDrop.frame)
        cdPosInfo:SetSize(16, 16)
        cdPosInfo:SetPoint("LEFT", cdAnchorDrop.label, "RIGHT", 4, 0)
        local cdPosInfoIcon = cdPosInfo:CreateTexture(nil, "OVERLAY")
        cdPosInfoIcon:SetSize(12, 12)
        cdPosInfoIcon:SetPoint("CENTER")
        cdPosInfoIcon:SetAtlas("QuestRepeatableTurnin")
        cdPosInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Shared Position")
            GameTooltip:AddLine("Anchor and offset settings are shared between Cooldown Text and Aura Text since they use the same text element.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cdPosInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cdAnchorDrop:SetCallback("OnRelease", function()
            cdPosInfo:ClearAllPoints()
            cdPosInfo:Hide()
            cdPosInfo:SetParent(nil)
        end)

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
    local auraPosInfo = CreateFrame("Button", nil, auraTextCb.frame)
    auraPosInfo:SetSize(16, 16)
    auraPosInfo:SetPoint("LEFT", auraTextCb.checkbg, "RIGHT", auraTextCb.text:GetStringWidth() + 4, 0)
    local auraPosInfoIcon = auraPosInfo:CreateTexture(nil, "OVERLAY")
    auraPosInfoIcon:SetSize(12, 12)
    auraPosInfoIcon:SetPoint("CENTER")
    auraPosInfoIcon:SetAtlas("QuestRepeatableTurnin")
    auraPosInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Shared Position")
        GameTooltip:AddLine("Position (anchor, X/Y offset) is controlled in the Cooldown Text section above. Cooldown Text and Aura Duration Text share the same text element.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    auraPosInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    auraTextCb:SetCallback("OnRelease", function()
        auraPosInfo:ClearAllPoints()
        auraPosInfo:Hide()
        auraPosInfo:SetParent(nil)
    end)

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
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isBarMode = group and group.displayMode == "bars"
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(isBarMode and "Show GCD" or "Show GCD Swipe")
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

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showCooldownSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
    end)
    container:AddChild(edgeCb)
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

local function BuildAssistedHighlightControls(container, styleTable, refreshCallback)
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

local function BuildProcGlowControls(container, styleTable, refreshCallback)
    -- Style dropdown
    local procStyleDrop = AceGUI:Create("Dropdown")
    procStyleDrop:SetLabel("Glow Style")
    procStyleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    procStyleDrop:SetValue(styleTable.procGlowStyle or "glow")
    procStyleDrop:SetFullWidth(true)
    procStyleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.procGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(procStyleDrop)

    -- Color picker
    local procGlowColor = AceGUI:Create("ColorPicker")
    procGlowColor:SetLabel("Glow Color")
    procGlowColor:SetHasAlpha(true)
    local pgc = styleTable.procGlowColor or {1, 1, 1, 1}
    procGlowColor:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
    procGlowColor:SetFullWidth(true)
    procGlowColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.procGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    procGlowColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.procGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(procGlowColor)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.procGlowStyle or "glow"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable.procGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 0.1)
        sizeSlider:SetValue(styleTable.procGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable.procGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable.procGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable.procGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildPandemicGlowControls(container, styleTable, refreshCallback)
    -- Style dropdown
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    styleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    styleDrop:SetValue(styleTable.pandemicGlowStyle or "solid")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.pandemicGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    -- Color picker
    local colorPicker = AceGUI:Create("ColorPicker")
    colorPicker:SetLabel("Glow Color")
    colorPicker:SetHasAlpha(true)
    local c = styleTable.pandemicGlowColor or {1, 0.5, 0, 1}
    colorPicker:SetColor(c[1], c[2], c[3], c[4])
    colorPicker:SetFullWidth(true)
    colorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.pandemicGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.pandemicGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(colorPicker)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.pandemicGlowStyle or "solid"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 0.1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable.pandemicGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable.pandemicGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildPandemicBarControls(container, styleTable, refreshCallback)
    -- Pandemic bar color
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Pandemic Bar Color")
    barColorPicker:SetHasAlpha(true)
    local bpc = styleTable.barPandemicColor or {1, 0.5, 0, 1}
    barColorPicker:SetColor(bpc[1], bpc[2], bpc[3], bpc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barPandemicColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barPandemicColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    -- Effect dropdown
    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel("Pandemic Effect")
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
        ["glow"] = "Proc Glow",
    }, {"none", "pixel", "solid", "glow"})
    effectDrop:SetValue(styleTable.pandemicBarEffect or "none")
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.pandemicBarEffect = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(effectDrop)

    local currentEffect = styleTable.pandemicBarEffect or "none"
    if currentEffect ~= "none" then
        -- Effect color
        local effectColorPicker = AceGUI:Create("ColorPicker")
        effectColorPicker:SetLabel("Pandemic Effect Color")
        effectColorPicker:SetHasAlpha(true)
        local ec = styleTable.pandemicBarEffectColor or {1, 0.5, 0, 1}
        effectColorPicker:SetColor(ec[1], ec[2], ec[3], ec[4])
        effectColorPicker:SetFullWidth(true)
        effectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.pandemicBarEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        effectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.pandemicBarEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(effectColorPicker)

        -- Size/thickness/speed sliders (conditional on effect)
        if currentEffect == "solid" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 0.1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        elseif currentEffect == "pixel" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Line Length")
            sizeSlider:SetSliderValues(2, 12, 0.1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 4)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)

            local thicknessSlider = AceGUI:Create("Slider")
            thicknessSlider:SetLabel("Line Thickness")
            thicknessSlider:SetSliderValues(1, 6, 0.1)
            thicknessSlider:SetValue(styleTable.pandemicBarEffectThickness or 2)
            thicknessSlider:SetFullWidth(true)
            thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectThickness = val
                refreshCallback()
            end)
            container:AddChild(thicknessSlider)

            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Speed")
            speedSlider:SetSliderValues(10, 200, 0.1)
            speedSlider:SetValue(styleTable.pandemicBarEffectSpeed or 60)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSpeed = val
                refreshCallback()
            end)
            container:AddChild(speedSlider)
        elseif currentEffect == "glow" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Glow Size")
            sizeSlider:SetSliderValues(0, 60, 0.1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 32)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        end
    end
end

local function BuildAuraIndicatorControls(container, styleTable, refreshCallback)
    -- Style dropdown (no "none" — toggle handles enable/disable)
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    styleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    styleDrop:SetValue(styleTable.auraGlowStyle or "pixel")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.auraGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    -- Color picker
    local colorPicker = AceGUI:Create("ColorPicker")
    colorPicker:SetLabel("Indicator Color")
    colorPicker:SetHasAlpha(true)
    local c = styleTable.auraGlowColor or {1, 0.84, 0, 0.9}
    colorPicker:SetColor(c[1], c[2], c[3], c[4])
    colorPicker:SetFullWidth(true)
    colorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.auraGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.auraGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(colorPicker)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.auraGlowStyle or "pixel"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 0.1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable.auraGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable.auraGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildBarActiveAuraControls(container, styleTable, refreshCallback)
    -- Bar aura color
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Active Aura Bar Color")
    barColorPicker:SetHasAlpha(true)
    local bac = styleTable.barAuraColor or {0.2, 1.0, 0.2, 1.0}
    barColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    -- Effect dropdown
    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel("Active Aura Effect")
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
        ["glow"] = "Proc Glow",
    }, {"none", "pixel", "solid", "glow"})
    effectDrop:SetValue(styleTable.barAuraEffect or "none")
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.barAuraEffect = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(effectDrop)

    local currentEffect = styleTable.barAuraEffect or "none"
    if currentEffect ~= "none" then
        -- Effect color
        local effectColorPicker = AceGUI:Create("ColorPicker")
        effectColorPicker:SetLabel("Effect Color")
        effectColorPicker:SetHasAlpha(true)
        local ec = styleTable.barAuraEffectColor or {1, 0.84, 0, 0.9}
        effectColorPicker:SetColor(ec[1], ec[2], ec[3], ec[4])
        effectColorPicker:SetFullWidth(true)
        effectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barAuraEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        effectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barAuraEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(effectColorPicker)

        -- Size/thickness/speed sliders (conditional on effect)
        if currentEffect == "solid" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 0.1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        elseif currentEffect == "pixel" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Line Length")
            sizeSlider:SetSliderValues(2, 12, 0.1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 4)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)

            local thicknessSlider = AceGUI:Create("Slider")
            thicknessSlider:SetLabel("Line Thickness")
            thicknessSlider:SetSliderValues(1, 6, 0.1)
            thicknessSlider:SetValue(styleTable.barAuraEffectThickness or 2)
            thicknessSlider:SetFullWidth(true)
            thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectThickness = val
                refreshCallback()
            end)
            container:AddChild(thicknessSlider)

            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Speed")
            speedSlider:SetSliderValues(10, 200, 0.1)
            speedSlider:SetValue(styleTable.barAuraEffectSpeed or 60)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSpeed = val
                refreshCallback()
            end)
            container:AddChild(speedSlider)
        elseif currentEffect == "glow" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Glow Size")
            sizeSlider:SetSliderValues(0, 60, 0.1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 32)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        end
    end
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
            styleTable.barNameTextReverse = val or nil
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
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildBarColorsControls = BuildBarColorsControls
ST._BuildBarNameTextControls = BuildBarNameTextControls
ST._BuildBarReadyTextControls = BuildBarReadyTextControls
