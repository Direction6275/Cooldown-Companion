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

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

local TOKEN_HELP_TEXT = table.concat({
    "|cffffffffAvailable Tokens:|r",
    "",
    "|cff00ff00{name}|r — Spell/item display name",
    "|cff00ff00{time}|r — Cooldown remaining (1:23, 4.5)",
    "|cff00ff00{charges}|r — Current charges",
    "|cff00ff00{maxcharges}|r — Maximum charges",
    "|cff00ff00{stacks}|r — Aura stacks or item count",
    "|cff00ff00{aura}|r — Aura duration remaining",
    "|cff00ff00{keybind}|r — Keybind text",
    "|cff00ff00{status}|r — Auto: Ready / time / Active",
    "|cff00ff00{icon}|r — Inline spell icon texture",
    "",
    "{status} resolves to:",
    "  Ready (green) when off CD",
    "  Cooldown time (red) when on CD",
    "  Aura time (cyan) when aura active",
}, "\n")

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
        headerSizeSlider:SetSliderValues(6, 36, 1)
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
        {"Available Tokens", 1, 0.82, 0, true},
        " ",
        {"{name}  — Spell/item display name", 1, 1, 1, true},
        {"{time}  — Cooldown remaining", 1, 1, 1, true},
        {"{charges}  — Current charges", 1, 1, 1, true},
        {"{maxcharges}  — Maximum charges", 1, 1, 1, true},
        {"{stacks}  — Aura stacks / item count", 1, 1, 1, true},
        {"{aura}  — Aura duration remaining", 1, 1, 1, true},
        {"{keybind}  — Keybind text", 1, 1, 1, true},
        {"{status}  — Auto: Ready / time / Active", 1, 1, 1, true},
        {"{icon}  — Inline spell icon", 1, 1, 1, true},
        " ",
        {"Conditional Sections", 1, 0.82, 0, true},
        " ",
        {"{?token}...{/token}  — Show when token has a value", 0.6, 1, 0.6, true},
        {"{!token}...{/token}  — Show when token is empty", 0.6, 1, 0.6, true},
        " ",
        {"Example:", 0.7, 0.7, 0.7, true},
        {"{name} {?time}(CD: {time}){/time}", 0.7, 0.7, 0.7, true},
    }, tabInfoButtons)
    fmtHeading.right:ClearAllPoints()
    fmtHeading.right:SetPoint("RIGHT", fmtHeading.frame, "RIGHT", -3, 0)
    fmtHeading.right:SetPoint("LEFT", fmtInfo, "RIGHT", 4, 0)

    if not fmtCollapsed then
    local fmtBox = AceGUI:Create("EditBox")
    if fmtBox.editbox.Instructions then fmtBox.editbox.Instructions:Hide() end
    fmtBox:SetLabel("Format")
    fmtBox:SetText(style.textFormat or "{name}  {status}")
    fmtBox:SetFullWidth(true)
    fmtBox:SetCallback("OnEnterPressed", function(widget, event, text)
        style.textFormat = text
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    container:AddChild(fmtBox)

    -- Token insert dropdown
    local tokenDrop = AceGUI:Create("Dropdown")
    tokenDrop:SetLabel("Insert Token")
    tokenDrop:SetList({
        name = "{name}",
        time = "{time}",
        charges = "{charges}",
        maxcharges = "{maxcharges}",
        stacks = "{stacks}",
        aura = "{aura}",
        keybind = "{keybind}",
        status = "{status}",
        icon = "{icon}",
    }, {"name", "time", "charges", "maxcharges", "stacks", "aura", "keybind", "status", "icon"})
    tokenDrop:SetFullWidth(true)
    tokenDrop:SetCallback("OnValueChanged", function(widget, event, token)
        local editbox = fmtBox.editbox
        local text = editbox:GetText() or ""
        local cursor = editbox:GetCursorPosition()
        local insert = "{" .. token .. "}"
        local newText = text:sub(1, cursor) .. insert .. text:sub(cursor + 1)
        editbox:SetText(newText)
        editbox:SetCursorPosition(cursor + #insert)
        editbox:SetFocus()
        -- Reset dropdown so it can be used again for the same token
        widget:SetValue(nil)
        widget:SetText("")
    end)
    container:AddChild(tokenDrop)
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
    fontSizeSlider:SetSliderValues(6, 36, 1)
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

-- Text mode has no effects tab — state is communicated via text color only
local function BuildTextEffectsTab(container, group, style)
    local label = AceGUI:Create("Label")
    label:SetText("|cff888888Text mode uses per-token coloring to indicate state.\nNo glow or animation effects are available.|r")
    label:SetFullWidth(true)
    container:AddChild(label)
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildTextEffectsTab = BuildTextEffectsTab
