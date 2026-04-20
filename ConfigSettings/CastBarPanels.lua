local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton
local GetBarTextureOptions = ST._GetBarTextureOptions
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local HookSliderEditBox = ST._HookSliderEditBox
local BuildIndependentAnchorTargetRow = ST._BuildIndependentAnchorTargetRow

------------------------------------------------------------------------
-- CAST BAR SETTINGS PANEL
------------------------------------------------------------------------

local function CanShowAttachedCastBarOffsetControls(rbSettings, cbSettings)
    return rbSettings
        and rbSettings.enabled
        and rbSettings.independentAnchorEnabled ~= true
        and cbSettings
        and cbSettings.enabled
        and cbSettings.independentAnchorEnabled ~= true
end

local function RefreshAttachedCastBarOffset(refreshConfig)
    CooldownCompanion:RepositionCastBar()
    if refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function BuildAttachedCastBarOffsetControls(container)
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    if not CanShowAttachedCastBarOffsetControls(rbSettings, cbSettings) then
        return false
    end

    local offsetToggle = AceGUI:Create("CheckBox")
    offsetToggle:SetLabel("Enable Cast Bar-Only Y Offset")
    offsetToggle:SetValue(cbSettings.panelAnchorYOffsetEnabled == true)
    offsetToggle:SetFullWidth(true)
    offsetToggle:SetCallback("OnValueChanged", function(widget, event, val)
        cbSettings.panelAnchorYOffsetEnabled = val == true
        RefreshAttachedCastBarOffset(true)
    end)
    container:AddChild(offsetToggle)

    if cbSettings.panelAnchorYOffsetEnabled then
        local offsetSlider = AceGUI:Create("Slider")
        offsetSlider:SetLabel("Cast Bar Y Offset")
        offsetSlider:SetSliderValues(-100, 100, 0.1)
        offsetSlider:SetValue(cbSettings.panelAnchorYOffset or 0)
        offsetSlider:SetFullWidth(true)
        offsetSlider:SetCallback("OnValueChanged", function(widget, event, val)
            cbSettings.panelAnchorYOffset = val
            RefreshAttachedCastBarOffset(false)
        end)
        HookSliderEditBox(offsetSlider)
        container:AddChild(offsetSlider)
    end

    return true
end

local function BuildCastBarAnchoringPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetCastBarSettings()

    -- Enable Anchoring
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Cast Bar Anchoring")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    CreateCharacterCopyButton(enableCb, "castBar", "Cast Bar", function()
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not settings.enabled then return end

    local isIndependent = settings.independentAnchorEnabled == true

    -- Anchoring Mode dropdown
    local anchorModeDrop = AceGUI:Create("Dropdown")
    anchorModeDrop:SetLabel("Anchoring Mode")
    anchorModeDrop:SetList({
        attached = "Attached to Panel",
        independent = "Independent",
    }, { "attached", "independent" })
    anchorModeDrop:SetValue(isIndependent and "independent" or "attached")
    anchorModeDrop:SetFullWidth(true)
    anchorModeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.independentAnchorEnabled = (val == "independent")
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorModeDrop)

    -- Preview toggle (ephemeral — not saved to DB)
    local previewCb = AceGUI:Create("CheckBox")
    previewCb:SetLabel("Preview Cast Bar")
    previewCb:SetValue(CooldownCompanion:IsCastBarPreviewActive())
    previewCb:SetFullWidth(true)
    previewCb:SetCallback("OnValueChanged", function(widget, event, val)
        if val then
            CooldownCompanion:StartCastBarPreview()
        else
            CooldownCompanion:StopCastBarPreview()
        end
    end)
    container:AddChild(previewCb)

    -- Cast Effects
    local sparkTrailCb = AceGUI:Create("CheckBox")
    sparkTrailCb:SetLabel("Show Spark Trail")
    sparkTrailCb:SetValue(settings.showSparkTrail ~= false)
    sparkTrailCb:SetFullWidth(true)
    sparkTrailCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showSparkTrail = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(sparkTrailCb)

    local intShakeCb = AceGUI:Create("CheckBox")
    intShakeCb:SetLabel("Show Interrupt Shake")
    intShakeCb:SetValue(settings.showInterruptShake ~= false)
    intShakeCb:SetFullWidth(true)
    intShakeCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showInterruptShake = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(intShakeCb)

    local intGlowCb = AceGUI:Create("CheckBox")
    intGlowCb:SetLabel("Show Interrupt Glow")
    intGlowCb:SetValue(settings.showInterruptGlow ~= false)
    intGlowCb:SetFullWidth(true)
    intGlowCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showInterruptGlow = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(intGlowCb)

    local castFinishCb = AceGUI:Create("CheckBox")
    castFinishCb:SetLabel("Show Cast Finish FX")
    castFinishCb:SetValue(settings.showCastFinishFX ~= false)
    castFinishCb:SetFullWidth(true)
    castFinishCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showCastFinishFX = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(castFinishCb)

end

local function BuildCastBarPositioningPanel(container)
    local settings = CooldownCompanion:GetCastBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Cast Bar Anchoring to configure positioning.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    if not settings.independentAnchorEnabled then
        local rbSettings = CooldownCompanion:GetResourceBarSettings()
        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-100, 100, 0.1)
        ySlider:SetValue(rbSettings and rbSettings.yOffset or 3)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(widget, event, val)
            if rbSettings then rbSettings.yOffset = val end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(ySlider)

        BuildAttachedCastBarOffsetControls(container)
        return
    end

    -- Anchor Settings
    local castPosHeading = AceGUI:Create("Heading")
    castPosHeading:SetText("Anchor Settings")
    ColorHeading(castPosHeading)
    castPosHeading:SetFullWidth(true)
    container:AddChild(castPosHeading)

    if type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    local anchor = settings.independentAnchor

    local unlockCb = AceGUI:Create("CheckBox")
    unlockCb:SetLabel("Unlock Placement")
    unlockCb:SetValue(not settings.independentAnchorLocked)
    unlockCb:SetFullWidth(true)
    unlockCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.independentAnchorLocked = not val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(unlockCb)

    local widthSlider = AceGUI:Create("Slider")
    widthSlider:SetLabel("Cast Bar Width")
    widthSlider:SetSliderValues(20, 600, 1)
    widthSlider:SetValue(settings.independentWidth or 200)
    widthSlider:SetFullWidth(true)
    widthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.independentWidth = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(widthSlider)

    local function refreshCastBarAnchor()
        CooldownCompanion:ApplyCastBarSettings()
    end

    BuildIndependentAnchorTargetRow(container, anchor, refreshCastBarAnchor)

    AddAnchorDropdown(container, anchor, "point", "CENTER", refreshCastBarAnchor, "Anchor Point")
    AddAnchorDropdown(container, anchor, "relativePoint", "CENTER", refreshCastBarAnchor, "Relative Point")

    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 0.1)
    xSlider:SetValue(anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        anchor.x = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    HookSliderEditBox(xSlider)
    container:AddChild(xSlider)

    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 0.1)
    ySlider:SetValue(anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        anchor.y = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    HookSliderEditBox(ySlider)
    container:AddChild(ySlider)
end

local function BuildCastBarStylingPanel(container)
    local settings = CooldownCompanion:GetCastBarSettings()
    local applyCastBar = function() CooldownCompanion:ApplyCastBarSettings() end

    -- Enable Styling checkbox — always visible, but grayed out when anchoring is off
    local styleCb = AceGUI:Create("CheckBox")
    styleCb:SetLabel("Enable Cast Bar Styling")
    styleCb:SetValue(settings.stylingEnabled ~= false)
    styleCb:SetFullWidth(true)
    styleCb:SetDisabled(not settings.enabled)
    styleCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.stylingEnabled = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleCb)

    if not settings.enabled then return end
    if not settings.stylingEnabled then return end

    local cbAdvBtns = {}

    -- ============ Texture & Colors ============

    -- Bar Texture
    local texDrop = AceGUI:Create("Dropdown")
    texDrop:SetLabel("Bar Texture")
    texDrop:SetList(GetBarTextureOptions())
    texDrop:SetValue(settings.barTexture or "Solid")
    texDrop:SetFullWidth(true)
    texDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.barTexture = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(texDrop)

    -- Bar Color
    AddColorPicker(container, settings, "barColor", "Bar Color", {1.0, 0.7, 0.0, 1.0}, true, applyCastBar)

    -- Background Color
    AddColorPicker(container, settings, "backgroundColor", "Background Color", {0, 0, 0, 0.5}, true, applyCastBar)

    -- ============ Border ============

    -- Border Style
    local borderDrop = AceGUI:Create("Dropdown")
    borderDrop:SetLabel("Border Style")
    borderDrop:SetList({
        blizzard = "Blizzard",
        pixel = "Pixel",
        none = "None",
    }, { "blizzard", "pixel", "none" })
    borderDrop:SetValue(settings.borderStyle or "pixel")
    borderDrop:SetFullWidth(true)
    borderDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.borderStyle = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(borderDrop)

    -- Border Color and Size (only when pixel)
    if settings.borderStyle == "pixel" then
        AddColorPicker(container, settings, "borderColor", "Border Color", {0, 0, 0, 1}, true, applyCastBar)

        local borderSizeSlider = AceGUI:Create("Slider")
        borderSizeSlider:SetLabel("Border Size")
        borderSizeSlider:SetSliderValues(0, 5, 0.1)
        borderSizeSlider:SetValue(settings.borderSize or 1)
        borderSizeSlider:SetFullWidth(true)
        borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.borderSize = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(borderSizeSlider)
    end

    -- ============ Size ============

    -- Height
    local hSlider = AceGUI:Create("Slider")
    hSlider:SetLabel("Height")
    hSlider:SetSliderValues(4, 40, 0.1)
    hSlider:SetValue(settings.height or 15)
    hSlider:SetFullWidth(true)
    hSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.height = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(hSlider)

    -- ============ Feature Toggles ============

    -- Show Spell Icon
    local iconCb = AceGUI:Create("CheckBox")
    iconCb:SetLabel("Show Spell Icon")
    iconCb:SetValue(settings.showIcon ~= false)
    iconCb:SetFullWidth(true)
    iconCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showIcon = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(iconCb)

    local iconAdvExpanded = AddAdvancedToggle(iconCb, "castbarIcon", cbAdvBtns, settings.showIcon ~= false)

    if iconAdvExpanded and settings.showIcon ~= false then
        -- Icon on Right Side
        local iconFlipCb = AceGUI:Create("CheckBox")
        iconFlipCb:SetLabel("Icon on Right Side")
        iconFlipCb:SetValue(settings.iconFlipSide or false)
        iconFlipCb:SetFullWidth(true)
        iconFlipCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.iconFlipSide = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(iconFlipCb)

        -- Icon Offset toggle
        local iconOffsetCb = AceGUI:Create("CheckBox")
        iconOffsetCb:SetLabel("Icon Offset")
        iconOffsetCb:SetValue(settings.iconOffset or false)
        iconOffsetCb:SetFullWidth(true)
        iconOffsetCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.iconOffset = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(iconOffsetCb)

        local iconOffsetAdvExpanded = AddAdvancedToggle(iconOffsetCb, "castbarIconOffset", cbAdvBtns, settings.iconOffset or false)

        if iconOffsetAdvExpanded and settings.iconOffset then
            -- Icon Size slider (offset mode only)
            local iconSizeSlider = AceGUI:Create("Slider")
            iconSizeSlider:SetLabel("Icon Size")
            iconSizeSlider:SetSliderValues(8, 64, 0.1)
            iconSizeSlider:SetValue(settings.iconSize or 16)
            iconSizeSlider:SetFullWidth(true)
            iconSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconSize = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(iconSizeSlider)

            -- Icon X Offset slider
            local iconXSlider = AceGUI:Create("Slider")
            iconXSlider:SetLabel("Icon X Offset")
            iconXSlider:SetSliderValues(-50, 50, 0.1)
            iconXSlider:SetValue(settings.iconOffsetX or 0)
            iconXSlider:SetFullWidth(true)
            iconXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconOffsetX = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(iconXSlider)

            -- Icon Y Offset slider
            local iconYSlider = AceGUI:Create("Slider")
            iconYSlider:SetLabel("Icon Y Offset")
            iconYSlider:SetSliderValues(-50, 50, 0.1)
            iconYSlider:SetValue(settings.iconOffsetY or 0)
            iconYSlider:SetFullWidth(true)
            iconYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconOffsetY = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(iconYSlider)

            -- Icon Border Size slider (offset mode only)
            local iconBorderSlider = AceGUI:Create("Slider")
            iconBorderSlider:SetLabel("Icon Border Size")
            iconBorderSlider:SetSliderValues(0, 4, 0.1)
            iconBorderSlider:SetValue(settings.iconBorderSize or 1)
            iconBorderSlider:SetFullWidth(true)
            iconBorderSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconBorderSize = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(iconBorderSlider)
        end
    end

    -- Show Spark
    local sparkCb = AceGUI:Create("CheckBox")
    sparkCb:SetLabel("Show Spark")
    sparkCb:SetValue(settings.showSpark ~= false)
    sparkCb:SetFullWidth(true)
    sparkCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showSpark = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(sparkCb)

    -- Show Spell Name
    local nameCb = AceGUI:Create("CheckBox")
    nameCb:SetLabel("Show Spell Name")
    nameCb:SetValue(settings.showNameText ~= false)
    nameCb:SetFullWidth(true)
    nameCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showNameText = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(nameCb)

    local nameAdvExpanded = AddAdvancedToggle(nameCb, "castbarNameText", cbAdvBtns, settings.showNameText ~= false)

    if nameAdvExpanded and settings.showNameText ~= false then
        -- Font
        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(nameFontDrop)
        nameFontDrop:SetValue(settings.nameFont or "Friz Quadrata TT")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.nameFont = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(nameFontDrop)

        -- Size
        local nameSizeSlider = AceGUI:Create("Slider")
        nameSizeSlider:SetLabel("Font Size")
        nameSizeSlider:SetSliderValues(6, 24, 0.1)
        nameSizeSlider:SetValue(settings.nameFontSize or 10)
        nameSizeSlider:SetFullWidth(true)
        nameSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.nameFontSize = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(nameSizeSlider)

        -- Outline
        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Outline")
        nameOutlineDrop:SetList(CS.outlineOptions)
        nameOutlineDrop:SetValue(settings.nameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.nameFontOutline = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(nameOutlineDrop)

        -- Color
        AddColorPicker(container, settings, "nameFontColor", "Font Color", {1, 1, 1, 1}, true, applyCastBar)
    end

    -- Show Cast Time
    local ctCb = AceGUI:Create("CheckBox")
    ctCb:SetLabel("Show Cast Time")
    ctCb:SetValue(settings.showCastTimeText ~= false)
    ctCb:SetFullWidth(true)
    ctCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.showCastTimeText = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(ctCb)

    local ctAdvExpanded = AddAdvancedToggle(ctCb, "castbarCastTime", cbAdvBtns, settings.showCastTimeText ~= false)

    if ctAdvExpanded and settings.showCastTimeText ~= false then
        -- Font
        local ctFontDrop = AceGUI:Create("Dropdown")
        ctFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(ctFontDrop)
        ctFontDrop:SetValue(settings.castTimeFont or "Friz Quadrata TT")
        ctFontDrop:SetFullWidth(true)
        ctFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.castTimeFont = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ctFontDrop)

        -- Size
        local ctSizeSlider = AceGUI:Create("Slider")
        ctSizeSlider:SetLabel("Font Size")
        ctSizeSlider:SetSliderValues(6, 24, 0.1)
        ctSizeSlider:SetValue(settings.castTimeFontSize or 10)
        ctSizeSlider:SetFullWidth(true)
        ctSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.castTimeFontSize = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ctSizeSlider)

        -- Outline
        local ctOutlineDrop = AceGUI:Create("Dropdown")
        ctOutlineDrop:SetLabel("Outline")
        ctOutlineDrop:SetList(CS.outlineOptions)
        ctOutlineDrop:SetValue(settings.castTimeFontOutline or "OUTLINE")
        ctOutlineDrop:SetFullWidth(true)
        ctOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.castTimeFontOutline = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ctOutlineDrop)

        -- Color
        AddColorPicker(container, settings, "castTimeFontColor", "Font Color", {1, 1, 1, 1}, true, applyCastBar)

        -- X Offset
        local ctXSlider = AceGUI:Create("Slider")
        ctXSlider:SetLabel("X Offset")
        ctXSlider:SetSliderValues(-50, 50, 0.1)
        ctXSlider:SetValue(settings.castTimeXOffset or 0)
        ctXSlider:SetFullWidth(true)
        ctXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.castTimeXOffset = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ctXSlider)

        -- Y Offset
        local ctYSlider = AceGUI:Create("Slider")
        ctYSlider:SetLabel("Y Offset")
        ctYSlider:SetSliderValues(-20, 20, 0.1)
        ctYSlider:SetValue(settings.castTimeYOffset or 0)
        ctYSlider:SetFullWidth(true)
        ctYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.castTimeYOffset = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ctYSlider)
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCastBarAnchoringPanel = BuildCastBarAnchoringPanel
ST._BuildCastBarPositioningPanel = BuildCastBarPositioningPanel
ST._BuildCastBarStylingPanel = BuildCastBarStylingPanel
ST._BuildAttachedCastBarOffsetControls = BuildAttachedCastBarOffsetControls
