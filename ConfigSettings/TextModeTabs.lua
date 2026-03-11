--[[
    CooldownCompanion - ConfigSettings/TextModeTabs.lua: Text-mode appearance tab builder
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local CreatePromoteButton = ST._CreatePromoteButton
local BuildTextColorsControls = ST._BuildTextColorsControls
local OpenFormatEditor = ST._OpenFormatEditor
local RenderFormatPreview = ST._RenderFormatPreview
local ParseFormatString = ST._ParseFormatString

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

local TOKEN_HELP_TEXT = table.concat({
    "|cffffffffAvailable Tokens:|r",
    "",
    "|cff00ff00{name}|r  Spell/item display name",
    "|cff00ff00{time}|r  Cooldown time remaining (1:23, 4.5)",
    "|cff00ff00{charges}|r  Current charges (if spell has charges)",
    "|cff00ff00{maxcharges}|r  Maximum charges (if spell has charges)",
    "|cff00ff00{stacks}|r  Aura stacks or item count",
    "|cff00ff00{aura}|r  Aura duration remaining",
    "|cff00ff00{keybind}|r  Keybind text",
    "|cff00ff00{status}|r  Shows ready, cooldown, or aura automatically",
    "|cff00ff00{icon}|r  Inline spell icon texture",
    "|cff00ff00{missingcharges}|r  |cff888888(conditional only)|r Recharging with charges left",
    "|cff00ff00{zerocharges}|r  |cff888888(conditional only)|r All charges spent",
    "|cff00ff00{pandemic}|r  |cff888888(conditional only)|r Aura in pandemic window",
    "|cff00ff00{proc}|r  |cff888888(conditional only)|r Spell proc overlay active",
    "|cff00ff00{available}|r  |cff888888(conditional only)|r Off cooldown / has charges",
    "|cff00ff00{unusable}|r  |cff888888(conditional only)|r Spell/item not usable",
    "|cff00ff00{oor}|r  |cff888888(conditional only)|r Target out of range",
    "",
    "{status} resolves to:",
    "  Ready (green) when off CD",
    "  Cooldown time (red) when on CD",
    "  Aura time (cyan) when aura active",
}, "\n")

-- Syntax colors for summary (matching FormatEditor.lua)
local SUM_TOKEN  = "ff00ff00"
local SUM_COND_P = "ffffff00"
local SUM_COND_N = "ffff8844"
local SUM_EFFECT = "ffcc44ff"
local SUM_COLOR  = "ff44bbff"
local SUM_GRAY   = "ff888888"
local SUM_SEP    = "  |cff666666\194\183|r  "

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

local function BuildTextAppearanceTab(container, group, style)
    -- ================================================================
    -- Text Settings (width, height, spacing)
    -- ================================================================
    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text Settings")
    ColorHeading(textHeading)
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    local textSettingsCollapsed = CS.collapsedSections["textappearance_settings"]
    AttachCollapseButton(textHeading, textSettingsCollapsed, function()
        CS.collapsedSections["textappearance_settings"] = not CS.collapsedSections["textappearance_settings"]
        CooldownCompanion:RefreshConfigPanel()
    end)

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

    local headerCb = AceGUI:Create("CheckBox")
    headerCb:SetLabel("Show Group Header")
    headerCb:SetValue(style.showTextGroupHeader == true)
    headerCb:SetFullWidth(true)
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

        local headerColorPicker = AceGUI:Create("ColorPicker")
        headerColorPicker:SetLabel("Header Color")
        headerColorPicker:SetHasAlpha(true)
        local hc = style.textHeaderFontColor or {1, 1, 1, 1}
        headerColorPicker:SetColor(hc[1], hc[2], hc[3], hc[4])
        headerColorPicker:SetFullWidth(true)
        headerColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.textHeaderFontColor = {r, g, b, a}
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        headerColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.textHeaderFontColor = {r, g, b, a}
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(headerColorPicker)
    end
    end -- not textSettingsCollapsed

    -- ================================================================
    -- Format String
    -- ================================================================
    local fmtHeading = AceGUI:Create("Heading")
    fmtHeading:SetText("Format String")
    ColorHeading(fmtHeading)
    fmtHeading:SetFullWidth(true)
    container:AddChild(fmtHeading)

    local fmtCollapsed = CS.collapsedSections["textappearance_format"]
    local fmtCollapseBtn = AttachCollapseButton(fmtHeading, fmtCollapsed, function()
        CS.collapsedSections["textappearance_format"] = not CS.collapsedSections["textappearance_format"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    -- Token reference info button
    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtCollapseBtn, "LEFT", "RIGHT", 4, 0, {
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
    local fontHeading = AceGUI:Create("Heading")
    fontHeading:SetText("Font")
    ColorHeading(fontHeading)
    fontHeading:SetFullWidth(true)
    container:AddChild(fontHeading)

    local fontCollapsed = CS.collapsedSections["textappearance_font"]
    AttachCollapseButton(fontHeading, fontCollapsed, function()
        CS.collapsedSections["textappearance_font"] = not CS.collapsedSections["textappearance_font"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    CreatePromoteButton(fontHeading, "textFont", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not fontCollapsed then
    local fontDrop = AceGUI:Create("Dropdown")
    fontDrop:SetLabel("Font")
    CS.SetupFontDropdown(fontDrop)
    fontDrop:SetValue(style.textFont or "Friz Quadrata TT")
    fontDrop:SetFullWidth(true)
    fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.textFont = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(fontDrop)

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

    local outlineDrop = AceGUI:Create("Dropdown")
    outlineDrop:SetLabel("Font Outline")
    outlineDrop:SetList(CS.outlineOptions)
    outlineDrop:SetValue(style.textFontOutline or "OUTLINE")
    outlineDrop:SetFullWidth(true)
    outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.textFontOutline = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(outlineDrop)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({LEFT = "Left", CENTER = "Center", RIGHT = "Right"})
    alignDrop:SetValue(style.textAlignment or "LEFT")
    alignDrop:SetFullWidth(true)
    alignDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.textAlignment = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(alignDrop)

    local shadowCb = AceGUI:Create("CheckBox")
    shadowCb:SetLabel("Text Shadow")
    shadowCb:SetValue(style.textShadow == true)
    shadowCb:SetFullWidth(true)
    shadowCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.textShadow = val or false
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(shadowCb)
    end -- not fontCollapsed

    -- ================================================================
    -- Colors
    -- ================================================================
    local colorsHeading = AceGUI:Create("Heading")
    colorsHeading:SetText("Colors")
    ColorHeading(colorsHeading)
    colorsHeading:SetFullWidth(true)
    container:AddChild(colorsHeading)

    local colorsCollapsed = CS.collapsedSections["textappearance_colors"]
    AttachCollapseButton(colorsHeading, colorsCollapsed, function()
        CS.collapsedSections["textappearance_colors"] = not CS.collapsedSections["textappearance_colors"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    CreatePromoteButton(colorsHeading, "textColors", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not colorsCollapsed then
    BuildTextColorsControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- not colorsCollapsed

    -- ================================================================
    -- Background & Border
    -- ================================================================
    local bgHeading = AceGUI:Create("Heading")
    bgHeading:SetText("Background & Border")
    ColorHeading(bgHeading)
    bgHeading:SetFullWidth(true)
    container:AddChild(bgHeading)

    local bgCollapsed = CS.collapsedSections["textappearance_bg"]
    AttachCollapseButton(bgHeading, bgCollapsed, function()
        CS.collapsedSections["textappearance_bg"] = not CS.collapsedSections["textappearance_bg"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    CreatePromoteButton(bgHeading, "textBackground", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not bgCollapsed then
    local bgColorPicker = AceGUI:Create("ColorPicker")
    bgColorPicker:SetLabel("Background Color")
    bgColorPicker:SetHasAlpha(true)
    local bg = style.textBgColor or {0, 0, 0, 0}
    bgColorPicker:SetColor(bg[1], bg[2], bg[3], bg[4])
    bgColorPicker:SetFullWidth(true)
    bgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.textBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    bgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.textBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(bgColorPicker)

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.textBorderSize or 0)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.textBorderSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderSlider)

    local borderColorPicker = AceGUI:Create("ColorPicker")
    borderColorPicker:SetLabel("Border Color")
    borderColorPicker:SetHasAlpha(true)
    local bc = style.textBorderColor or {0, 0, 0, 1}
    borderColorPicker:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColorPicker:SetFullWidth(true)
    borderColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.textBorderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    borderColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.textBorderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderColorPicker)

    end -- not bgCollapsed

    -- ================================================================
    -- Compact Mode Controls
    -- ================================================================
    BuildCompactModeControls(container, group, tabInfoButtons)
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildFormatSummary = BuildFormatSummary
