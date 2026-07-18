--[[
    CooldownCompanion - ConfigSettings/TextModeTabs.lua: Text-mode appearance tab builder
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local CreatePromoteButton = ST._CreatePromoteButton
local BuildTextColorsControls = ST._BuildTextColorsControls
local OpenFormatEditor = ST._OpenFormatEditor
local AddColorPicker = ST._AddColorPicker
local RenderFormatPreview = ST._RenderFormatPreview
local ParseFormatString = ST._ParseFormatString
local AddConditionalPreviewButton = ST._AddConditionalPreviewButton
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

local tabInfoButtons = CS.tabInfoButtons

-- Syntax colors for summary (matching FormatEditor.lua)
local SUM_TOKEN  = "ff00ff00"
local SUM_COND_P = "ffffff00"
local SUM_COND_N = "ffff8844"
local SUM_EFFECT = "ffcc44ff"
local SUM_COLOR  = "ff44bbff"
local SUM_GRAY   = "ff888888"

local function BuildFormatSummary(formatString)
    local segments = ParseFormatString(formatString)
    local tokens, colors, effects, conds = {}, {}, {}, {}
    local seen = {}
    for _, seg in ipairs(segments) do
        if seg.type == "token" and not seg.unknown and not seen["t:" .. seg.value] then
            tokens[#tokens + 1] = "|c" .. SUM_TOKEN .. seg.value .. "|r"
            seen["t:" .. seg.value] = true
        elseif seg.type == "color_start" and not seen["c:" .. seg.value] then
            colors[#colors + 1] = "|c" .. SUM_COLOR .. seg.value .. "|r"
            seen["c:" .. seg.value] = true
        elseif seg.type == "effect_start" and not seen["e:" .. seg.value] then
            effects[#effects + 1] = "|c" .. SUM_EFFECT .. seg.value .. "|r"
            seen["e:" .. seg.value] = true
        elseif seg.type == "cond_start" then
            local prefix = seg.negated and "!" or "?"
            local key = prefix .. seg.value
            if not seen["d:" .. key] then
                local c = seg.negated and SUM_COND_N or SUM_COND_P
                conds[#conds + 1] = "|c" .. c .. key .. "|r"
                seen["d:" .. key] = true
            end
        end
    end

    local parts = {}
    if #tokens > 0 then
        parts[#parts + 1] = "|c" .. SUM_GRAY .. "Tokens:|r " .. table.concat(tokens, ", ")
    end
    if #conds > 0 then
        parts[#parts + 1] = "|c" .. SUM_GRAY .. "Conditions:|r " .. table.concat(conds, ", ")
    end
    if #colors > 0 then
        parts[#parts + 1] = "|c" .. SUM_GRAY .. "Colors:|r " .. table.concat(colors, ", ")
    end
    if #effects > 0 then
        parts[#parts + 1] = "|c" .. SUM_GRAY .. "Effects:|r " .. table.concat(effects, ", ")
    end

    if #parts == 0 then return {} end
    return parts
end

-- Two-column layout (same pattern as the icon/bar-panel tabs): the tab
-- scroll flows half-width compact widgets into side-by-side pairs; sliders,
-- color pickers, labels, and headings stay full width.
local function SetCompactWidth(widget)
    widget:SetRelativeWidth(0.5)
end

local function BuildTextAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local refreshFrame = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end
    container:SetLayout("Flow")

    -- ================================================================
    -- Text Settings (width, height, spacing)
    -- ================================================================
    local textHeading, textSettingsCollapsed = BuildCollapsibleSection(container, "Text Settings", "textappearance_settings")

    if not textSettingsCollapsed then
    local widthSlider = AceGUI:Create("Slider")
    widthSlider:SetLabel("Text Width")
    widthSlider:SetSliderValues(50, 600, 1)
    widthSlider:SetValue(style.textWidth or 200)
    widthSlider:SetFullWidth(true)
    widthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.textWidth = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(widthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Text Height")
    heightSlider:SetSliderValues(10, 100, 1)
    heightSlider:SetValue(style.textHeight or 20)
    heightSlider:SetFullWidth(true)
    heightSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.textHeight = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(heightSlider)

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Entry Spacing")
        spacingSlider:SetSliderValues(-10, 100, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    SetCompactWidth(AddDurationFormatDropdown(container, style, refreshStyle))

    local headerCb = AceGUI:Create("CheckBox")
    headerCb:SetLabel("Show Group Header")
    headerCb:SetValue(style.showTextGroupHeader == true)
    SetCompactWidth(headerCb)
    headerCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTextGroupHeader = val or false
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(headerCb)

    if style.showTextGroupHeader then
        local headerSizeSlider = AceGUI:Create("Slider")
        headerSizeSlider:SetLabel("Header Font Size")
        headerSizeSlider:SetSliderValues(6, 72, 1)
        headerSizeSlider:SetValue(style.textHeaderFontSize or 12)
        headerSizeSlider:SetFullWidth(true)
        headerSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.textHeaderFontSize = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(headerSizeSlider)

        SetCompactWidth(AddColorPicker(container, style, "textHeaderFontColor", "Header Color", {1, 1, 1, 1}, true, refreshFrame, refreshFrame))
    end
    end -- not textSettingsCollapsed

    -- ================================================================
    -- Format String
    -- ================================================================
    local fmtHeading, fmtCollapsed, fmtCollapseBtn = BuildCollapsibleSection(container, "Format String", "textappearance_format")
    local function BuildFormatPreviewAdvanced(panel)
        if AddConditionalPreviewButton then
            AddConditionalPreviewButton(panel, "Preview Cooldown State", "cooldown")
            AddConditionalPreviewButton(panel, "Preview Unusable State", "unusable")
            AddConditionalPreviewButton(panel, "Preview Out of Range State", "out_of_range")
        end
    end

    local _, fmtPreviewAdvBtn = AddAdvancedToggle(fmtHeading, "textFormatPreview", tabInfoButtons, nil, {
        title = "Format String Advanced",
        build = BuildFormatPreviewAdvanced,
    })
    fmtPreviewAdvBtn:SetPoint("LEFT", fmtCollapseBtn, "RIGHT", 4, 0)

    -- Token reference info button
    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtPreviewAdvBtn, "LEFT", "RIGHT", 4, 0, {
        {"Format String", 1, 0.82, 0, true},
        " ",
        {"Controls what each button displays using", 1, 1, 1, true},
        {"|cff00ff00{tokens}|r that resolve to live spell/item data.", 1, 1, 1, true},
        " ",
        {"Use |cffffff00{?token}|r...|cffffff00{/token}|r to show content only", 1, 1, 1, true},
        {"when a condition is met, or |cffff8844{!token}|r to show", 1, 1, 1, true},
        {"content when it is not.", 1, 1, 1, true},
        " ",
        {"Wrap text in |cff44bbff{color}|r...|cff44bbff{/color}|r tags to", 1, 1, 1, true},
        {"override its color, or |cffcc44ff{pulse}|r...|cffcc44ff{/pulse}|r", 1, 1, 1, true},
        {"for a pulsing alpha effect.", 1, 1, 1, true},
        " ",
        {"Use |cff00ff00{br}|r to force a new line within one entry.", 1, 1, 1, true},
        " ",
        {"Click |cffffffffEdit Format|r to open the full editor", 1, 1, 1, true},
        {"with token lists, insertion buttons, and live preview.", 1, 1, 1, true},
    }, tabInfoButtons)
    fmtHeading.right:ClearAllPoints()
    fmtHeading.right:SetPoint("RIGHT", fmtHeading.frame, "RIGHT", -3, 0)
    fmtHeading.right:SetPoint("LEFT", fmtInfo, "RIGHT", 4, 0)

    if not fmtCollapsed then
    local fmt = style.textFormat or "{name}  {status}"

    local preSpacer = AceGUI:Create("Label")
    preSpacer:SetText(" ")
    preSpacer:SetFullWidth(true)
    container:AddChild(preSpacer)

    local fmtPreview = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(fmtPreview)
    fmtPreview:SetText(RenderFormatPreview(fmt, style))
    fmtPreview:SetFullWidth(true)
    fmtPreview:SetFontObject(GameFontHighlight)
    fmtPreview:SetJustifyH("CENTER")
    container:AddChild(fmtPreview)

    local postSpacer = AceGUI:Create("Label")
    postSpacer:SetText(" ")
    postSpacer:SetFullWidth(true)
    container:AddChild(postSpacer)

    local summaryParts = BuildFormatSummary(fmt)
    for _, line in ipairs(summaryParts) do
        local fmtSummary = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(fmtSummary)
        fmtSummary:SetText(line)
        fmtSummary:SetFullWidth(true)
        fmtSummary:SetFontObject(GameFontHighlightSmall)
        container:AddChild(fmtSummary)
    end

    local btnSpacer = AceGUI:Create("Label")
    btnSpacer:SetText(" ")
    btnSpacer:SetFullWidth(true)
    container:AddChild(btnSpacer)

    local editBtn = AceGUI:Create("Button")
    editBtn:SetText("Edit Format")
    editBtn:SetFullWidth(true)
    editBtn:SetCallback("OnClick", function()
        OpenFormatEditor(style, CS.selectedGroup)
    end)
    container:AddChild(editBtn)

    end -- not fmtCollapsed

    -- ================================================================
    -- Font
    -- ================================================================
    local fontHeading, fontCollapsed = BuildCollapsibleSection(container, "Font", "textappearance_font")

    CreatePromoteButton(fontHeading, "textFont", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not fontCollapsed then
    local fontDrop = AceGUI:Create("Dropdown")
    fontDrop:SetLabel("Font")
    CS.SetupFontDropdown(fontDrop)
    fontDrop:SetValue(style.textFont or "Friz Quadrata TT")
    SetCompactWidth(fontDrop)
    CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
        style.textFont = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(fontDrop)

    local outlineDrop = AceGUI:Create("Dropdown")
    outlineDrop:SetLabel("Font Outline")
    CS.SetupFontOutlineDropdown(outlineDrop)
    outlineDrop:SetValue(style.textFontOutline or "OUTLINE")
    SetCompactWidth(outlineDrop)
    CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
        style.textFontOutline = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(outlineDrop)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({LEFT = "Left", CENTER = "Center", RIGHT = "Right"})
    alignDrop:SetValue(style.textAlignment or "LEFT")
    SetCompactWidth(alignDrop)
    alignDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.textAlignment = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(alignDrop)

    local shadowCb = AceGUI:Create("CheckBox")
    shadowCb:SetLabel("Text Shadow")
    shadowCb:SetValue(style.textShadow == true)
    SetCompactWidth(shadowCb)
    shadowCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.textShadow = val or false
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(shadowCb)

    local fontSizeSlider = AceGUI:Create("Slider")
    fontSizeSlider:SetLabel("Font Size")
    fontSizeSlider:SetSliderValues(6, 72, 1)
    fontSizeSlider:SetValue(style.textFontSize or 12)
    fontSizeSlider:SetFullWidth(true)
    fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.textFontSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(fontSizeSlider)
    end -- not fontCollapsed

    -- ================================================================
    -- Colors
    -- ================================================================
    local colorsHeading, colorsCollapsed = BuildCollapsibleSection(container, "Colors", "textappearance_colors")

    CreatePromoteButton(colorsHeading, "textColors", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not colorsCollapsed then
    BuildTextColorsControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, SetCompactWidth)
    end -- not colorsCollapsed

    -- ================================================================
    -- Background & Border
    -- ================================================================
    local bgHeading, bgCollapsed = BuildCollapsibleSection(container, "Background & Border", "textappearance_bg")

    CreatePromoteButton(bgHeading, "textBackground", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not bgCollapsed then
    SetCompactWidth(AddColorPicker(container, style, "textBgColor", "Background Color", {0, 0, 0, 0}, true, refreshStyle, refreshStyle))
    SetCompactWidth(AddColorPicker(container, style, "textBorderColor", "Border Color", {0, 0, 0, 1}, true, refreshStyle, refreshStyle))

    local renderMode, renderModeDrop = AddBorderRenderModeDropdown(container, style, "textBorderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    SetCompactWidth(renderModeDrop)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(style.textBorderSize or 0)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            style.textBorderSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(borderSlider)
    end

    end -- not bgCollapsed

    -- ================================================================
    -- Compact Mode Controls
    -- ================================================================
    BuildCompactModeControls(container, group, tabInfoButtons, SetCompactWidth)
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildFormatSummary = BuildFormatSummary
