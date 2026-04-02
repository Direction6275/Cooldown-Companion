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
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders

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
        AddFontControls(container, styleTable, "cooldown", {}, refreshCallback)
        AddColorPicker(container, styleTable, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshCallback, refreshCallback)

        local decimalCheck = AceGUI:Create("CheckBox")
        decimalCheck:SetLabel("Show Decimal Point")
        decimalCheck:SetValue(styleTable.decimalTimers or false)
        decimalCheck:SetFullWidth(true)
        decimalCheck:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.decimalTimers = val or nil
            refreshCallback()
        end)
        container:AddChild(decimalCheck)

        CreateInfoButton(decimalCheck.frame, decimalCheck.checkbg, "LEFT", "RIGHT", decimalCheck.text:GetStringWidth() + 4, 0, {
            "Show Decimal Point",
            {"Shows one decimal place on duration text", 1, 1, 1, true},
            {"(e.g. \"4.5\" instead of \"5\").", 1, 1, 1, true},
            " ",
            {"Bar and text mode only.", 0.7, 0.7, 0.7, true},
        }, decimalCheck)

        local cdAnchorDrop = AddAnchorDropdown(container, styleTable, "cooldownTextAnchor", "CENTER", refreshCallback)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        AddOffsetSliders(container, styleTable, "cooldownTextXOffset", "cooldownTextYOffset", {}, refreshCallback)

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
        AddFontControls(container, styleTable, "auraText", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshCallback, refreshCallback)

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
            AddAnchorDropdown(container, styleTable, "auraTextAnchor", "TOPLEFT", refreshCallback)
            AddOffsetSliders(container, styleTable, "auraTextXOffset", "auraTextYOffset", {x = 2, y = -2}, refreshCallback)
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
        AddFontControls(container, styleTable, "auraStack", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "auraStackAnchor", "BOTTOMLEFT", refreshCallback)
        AddOffsetSliders(container, styleTable, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2}, refreshCallback)
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
        AddAnchorDropdown(container, styleTable, "keybindAnchor", "TOPRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "keybindXOffset", "keybindYOffset", {x = -2, y = -2}, refreshCallback)
        AddFontControls(container, styleTable, "keybind", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "keybindFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildChargeTextControls(container, styleTable, refreshCallback)
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Count Text (Charges/Uses)")
    chargeTextCb:SetValue(styleTable.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showChargeText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    if styleTable.showChargeText ~= false then
        AddFontControls(container, styleTable, "charge", {}, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "chargeAnchor", "BOTTOMRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshCallback)
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

    AddColorPicker(container, styleTable, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildBackgroundColorControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "backgroundColor", "Background Color", {0, 0, 0, 0.5}, true, refreshCallback, refreshCallback)
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

local function BuildIconTintControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "iconTintColor", "Base Icon Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)

    local cdTintCb = AceGUI:Create("CheckBox")
    cdTintCb:SetLabel("Use Separate Cooldown Tint")
    cdTintCb:SetValue(styleTable.iconCooldownTintEnabled or false)
    cdTintCb:SetFullWidth(true)
    cdTintCb:SetCallback("OnValueChanged", function(w, e, val)
        styleTable.iconCooldownTintEnabled = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTintCb)

    if styleTable.iconCooldownTintEnabled then
        AddColorPicker(container, styleTable, "iconCooldownTintColor", "Cooldown Icon Color", {1, 0, 0.102, 1}, true, refreshCallback, refreshCallback)
    end

    local auraTintCb = AceGUI:Create("CheckBox")
    auraTintCb:SetLabel("Use Separate Aura Tint")
    auraTintCb:SetValue(styleTable.iconAuraTintEnabled or false)
    auraTintCb:SetFullWidth(true)
    auraTintCb:SetCallback("OnValueChanged", function(w, e, val)
        styleTable.iconAuraTintEnabled = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTintCb)

    if styleTable.iconAuraTintEnabled then
        AddColorPicker(container, styleTable, "iconAuraTintColor", "Aura Active Icon Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback)
    end

    if styleTable.showUnusable then
        AddColorPicker(container, styleTable, "iconUnusableTintColor", "Unusable Dimming Tint", {0.4, 0.4, 0.4, 1}, true, refreshCallback, refreshCallback)
    end
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
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(fillCb)
    ApplyCheckboxIndent(fillCb, 20)

    -- Swipe Fill Opacity (only when fill is visible)
    if styleTable.showCooldownSwipeFill ~= false then
        local alphaSlider = AceGUI:Create("Slider")
        alphaSlider:SetLabel("Swipe Fill Opacity")
        alphaSlider:SetSliderValues(0, 1, 0.05)
        alphaSlider:SetIsPercent(true)
        alphaSlider:SetValue(styleTable.cooldownSwipeAlpha or 0.8)
        alphaSlider:SetFullWidth(true)
        alphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownSwipeAlpha = val
            refreshCallback()
        end)
        container:AddChild(alphaSlider)
    end

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showCooldownSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(edgeCb)
    ApplyCheckboxIndent(edgeCb, 20)

    -- Swipe Edge Color (only when edge is visible)
    if styleTable.showCooldownSwipeEdge ~= false then
        AddColorPicker(container, styleTable, "cooldownSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
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
        AddColorPicker(container, styleTable, "assistedHighlightColor", "Highlight Color", {0.3, 1, 0.3, 0.9}, true, refreshCallback, refreshCallback)

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
        AddColorPicker(container, styleTable, "assistedHighlightProcColor", "Glow Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)

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
-- keys = { size = "...", thickness = "...", speed = "...", lines = "..." }
-- pixelSizeMin: minimum for the pixel "Line Length" slider (1 for glow
--   style controls, 2 for bar effect controls)
local function BuildGlowSliders(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin)
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 5)
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
        sizeSlider:SetValue(styleTable[keys.size] or 8)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable[keys.thickness] or 4)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.thickness] = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)

        if keys.lines then
            local linesSlider = AceGUI:Create("Slider")
            linesSlider:SetLabel("Number of Lines")
            linesSlider:SetSliderValues(1, 16, 1)
            linesSlider:SetValue(styleTable[keys.lines] or 8)
            linesSlider:SetFullWidth(true)
            linesSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[keys.lines] = val
                refreshCallback()
            end)
            container:AddChild(linesSlider)
        end
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 30)
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
        speedSlider:SetValue(styleTable[keys.speed] or 50)
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
            currentScale = 2
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
        speedSlider:SetValue(styleTable[keys.speed] or 50)
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
--         speedKey, linesKey, defaultStyle, defaultColor }
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

    if not (opts and opts.hidePrimaryColorPicker) then
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    BuildGlowSliders(container, styleTable, currentStyle, {
        size = cfg.sizeKey, thickness = cfg.thicknessKey, speed = cfg.speedKey, lines = cfg.linesKey,
    }, refreshCallback, 1)
end

-- Generic bar effect builder (Group B): primary color picker + effect
-- dropdown (none/pixel/solid) + conditional effect color +
-- conditional sliders. Replaces BuildPandemicBarControls,
-- BuildBarActiveAuraControls.
--
-- cfg = { colorKey, colorLabel, defaultColor, effectKey, effectLabel,
--         effectColorKey, effectColorLabel, defaultEffectColor,
--         effectSizeKey, effectThicknessKey, effectSpeedKey, effectLinesKey }
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

    if not (opts and opts.hidePrimaryColorPicker) then
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel(cfg.effectLabel)
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
    }, {"none", "pixel", "solid"})
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
        AddColorPicker(container, styleTable, cfg.effectColorKey, cfg.effectColorLabel, cfg.defaultEffectColor, true, refreshCallback, refreshCallback)

        BuildGlowSliders(container, styleTable, currentEffect, {
            size = cfg.effectSizeKey, thickness = cfg.effectThicknessKey, speed = cfg.effectSpeedKey, lines = cfg.effectLinesKey,
        }, refreshCallback, 2)
    end
end

------------------------------------------------------------------------
-- PUBLIC GLOW/EFFECT WRAPPERS (same signatures as original functions)
------------------------------------------------------------------------
local function BuildProcGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "procGlowStyle", colorKey = "procGlowColor", colorLabel = "Glow Color",
        sizeKey = "procGlowSize", thicknessKey = "procGlowThickness", speedKey = "procGlowSpeed", linesKey = "procGlowLines",
        defaultStyle = "glow", defaultColor = {1, 1, 1, 1},
        enableLabel = "Show Proc Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildPandemicGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "pandemicGlowStyle", colorKey = "pandemicGlowColor", colorLabel = "Glow Color",
        sizeKey = "pandemicGlowSize", thicknessKey = "pandemicGlowThickness", speedKey = "pandemicGlowSpeed", linesKey = "pandemicGlowLines",
        defaultStyle = "solid", defaultColor = {1, 0.5, 0, 1},
        enableKey = "showPandemicGlow", enableLabel = "Show Pandemic Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildAuraIndicatorControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "auraGlowStyle", colorKey = "auraGlowColor", colorLabel = "Indicator Color",
        sizeKey = "auraGlowSize", thicknessKey = "auraGlowThickness", speedKey = "auraGlowSpeed", linesKey = "auraGlowLines",
        defaultStyle = "pixel", defaultColor = {1, 0.84, 0, 0.9},
        enableLabel = "Show Aura Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildReadyGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "readyGlowStyle", colorKey = "readyGlowColor", colorLabel = "Glow Color",
        sizeKey = "readyGlowSize", thicknessKey = "readyGlowThickness", speedKey = "readyGlowSpeed", linesKey = "readyGlowLines",
        defaultStyle = "solid", defaultColor = {0.2, 1.0, 0.2, 1},
        enableLabel = "Show Ready Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local KPH_STYLE_OPTIONS = {["solid"] = "Solid Border", ["overlay"] = "Overlay"}
local KPH_STYLE_ORDER = {"solid", "overlay"}

local function BuildKeyPressHighlightControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "keyPressHighlightStyle", colorKey = "keyPressHighlightColor", colorLabel = "Highlight Color",
        sizeKey = "keyPressHighlightSize",
        defaultStyle = "solid", defaultColor = {1, 1, 1, 0.4},
        enableLabel = "Show Key Press Highlight",
        styleOptions = KPH_STYLE_OPTIONS,
        styleOrder = KPH_STYLE_ORDER,
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
        effectSpeedKey = "pandemicBarEffectSpeed", effectLinesKey = "pandemicBarEffectLines",
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
        effectSpeedKey = "barAuraEffectSpeed", effectLinesKey = "barAuraEffectLines",
    }, opts)
end

------------------------------------------------------------------------
-- BAR MODE PULSE / COLOR SHIFT CONTROLS
------------------------------------------------------------------------

-- cfg = { pulseKey, pulseSpeedKey,
--         colorShiftKey, colorShiftSpeedKey, colorShiftColorKey, defaultShiftColor }
local function BuildBarPulseControls(container, styleTable, refreshCallback, cfg, opts)
    local fb = opts and opts.fallbackStyle
    local function resolve(key, default)
        local v = styleTable[key]
        if v == nil and fb then v = fb[key] end
        if v ~= nil then return v end
        return default
    end

    -- Alpha Pulse
    local pulseCb = AceGUI:Create("CheckBox")
    pulseCb:SetLabel("Alpha Pulse")
    pulseCb:SetValue(resolve(cfg.pulseKey, false))
    pulseCb:SetFullWidth(true)
    pulseCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable[cfg.pulseKey] = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(pulseCb)

    if resolve(cfg.pulseKey, false) then
        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Pulse Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(resolve(cfg.pulseSpeedKey, 0.5))
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.pulseSpeedKey] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    end

    -- Color Shift
    local shiftCb = AceGUI:Create("CheckBox")
    shiftCb:SetLabel("Color Shift Pulse")
    shiftCb:SetValue(resolve(cfg.colorShiftKey, false))
    shiftCb:SetFullWidth(true)
    shiftCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable[cfg.colorShiftKey] = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(shiftCb)

    if resolve(cfg.colorShiftKey, false) then
        AddColorPicker(container, styleTable, cfg.colorShiftColorKey, "Shift Color", resolve(cfg.colorShiftColorKey, cfg.defaultShiftColor), true, refreshCallback, refreshCallback)

        local shiftSpeedSlider = AceGUI:Create("Slider")
        shiftSpeedSlider:SetLabel("Shift Duration")
        shiftSpeedSlider:SetSliderValues(0.1, 2.0, 0.05)
        shiftSpeedSlider:SetValue(resolve(cfg.colorShiftSpeedKey, 0.5))
        shiftSpeedSlider:SetFullWidth(true)
        shiftSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.colorShiftSpeedKey] = val
            refreshCallback()
        end)
        container:AddChild(shiftSpeedSlider)
    end
end

local function BuildBarAuraPulseControls(container, styleTable, refreshCallback, opts)
    BuildBarPulseControls(container, styleTable, refreshCallback, {
        pulseKey = "barAuraPulseEnabled", pulseSpeedKey = "barAuraPulseSpeed",
        colorShiftKey = "barAuraColorShiftEnabled", colorShiftSpeedKey = "barAuraColorShiftSpeed",
        colorShiftColorKey = "barAuraColorShiftColor", defaultShiftColor = {1, 1, 1, 1},
    }, opts)
end

local function BuildPandemicBarPulseControls(container, styleTable, refreshCallback, opts)
    BuildBarPulseControls(container, styleTable, refreshCallback, {
        pulseKey = "pandemicBarPulseEnabled", pulseSpeedKey = "pandemicBarPulseSpeed",
        colorShiftKey = "pandemicBarColorShiftEnabled", colorShiftSpeedKey = "pandemicBarColorShiftSpeed",
        colorShiftColorKey = "pandemicBarColorShiftColor", defaultShiftColor = {1, 1, 1, 1},
    }, opts)
end

local function BuildBarColorsControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}, true, refreshCallback, refreshCallback)
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

        AddFontControls(container, styleTable, "barName", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "barNameFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
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

        AddColorPicker(container, styleTable, "barReadyTextColor", "Ready Text Color", {0.2, 1.0, 0.2, 1.0}, true, refreshCallback, refreshCallback)
        AddFontControls(container, styleTable, "barReady", {sizeMin = 6, sizeMax = 24}, refreshCallback)
    end
end

------------------------------------------------------------------------
-- Text Mode — Text Colors
------------------------------------------------------------------------
local function BuildTextBackgroundControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "textBgColor", "Background Color", {0, 0, 0, 0}, true, refreshCallback, refreshCallback)

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

    AddColorPicker(container, styleTable, "textBorderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildTextFontControls(container, styleTable, refreshCallback)
    AddFontControls(container, styleTable, "text", {sizeMin = 6, sizeMax = 72}, refreshCallback)

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
    AddColorPicker(container, styleTable, "textFontColor", "Text Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "textCooldownColor", "Cooldown Color", {1, 0.3, 0.3, 1}, true, refreshCallback, refreshCallback)

    local readyColorPicker = AddColorPicker(container, styleTable, "textReadyColor", "Ready Color", {0.2, 1.0, 0.2, 1}, true, refreshCallback, refreshCallback)

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

    AddColorPicker(container, styleTable, "textAuraColor", "Aura Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback)
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
ST._BuildIconTintControls = BuildIconTintControls
ST._BuildAssistedHighlightControls = BuildAssistedHighlightControls
ST._BuildProcGlowControls = BuildProcGlowControls
ST._BuildPandemicGlowControls = BuildPandemicGlowControls
ST._BuildPandemicBarControls = BuildPandemicBarControls
ST._BuildAuraIndicatorControls = BuildAuraIndicatorControls
ST._BuildReadyGlowControls = BuildReadyGlowControls
ST._BuildKeyPressHighlightControls = BuildKeyPressHighlightControls
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildBarAuraPulseControls = BuildBarAuraPulseControls
ST._BuildPandemicBarPulseControls = BuildPandemicBarPulseControls
ST._BuildBarColorsControls = BuildBarColorsControls
ST._BuildBarNameTextControls = BuildBarNameTextControls
ST._BuildBarReadyTextControls = BuildBarReadyTextControls
ST._BuildTextFontControls = BuildTextFontControls
ST._BuildTextColorsControls = BuildTextColorsControls
ST._BuildTextBackgroundControls = BuildTextBackgroundControls
