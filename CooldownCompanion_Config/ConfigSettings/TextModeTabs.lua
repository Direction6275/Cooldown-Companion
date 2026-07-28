--[[
    CooldownCompanion - ConfigSettings/TextModeTabs.lua: Text-mode appearance tab builder
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local CreatePromoteButton = ST._CreatePromoteButton
local OpenFormatEditor = ST._OpenFormatEditor
local RenderFormatPreview = ST._RenderFormatPreview
local ParseFormatString = ST._ParseFormatString

-- Imports from SectionBuilders.lua
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddColorRow = ST._AddColorRow
local BeginRowGrid = ST._BeginRowGrid

local tabInfoButtons = CS.tabInfoButtons

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right. The rules every row-grammar section follows are stated
-- once, in the recipe comment at the top of BuildAppearanceTab's icons path in
-- GroupTabs.lua; the sections below conform to them rather than restating them.
local ROW_SECTION = { leftAligned = true }

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

local function BuildTextAppearanceTab(container, group, style)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    local refreshFrame = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end

    -- ================================================================
    -- Text Settings (width, height, spacing, header)
    -- ================================================================
    local _, textSettingsCollapsed = BuildCollapsibleSection(container, "Text Settings", "textappearance_settings", nil, nil, ROW_SECTION)

    if not textSettingsCollapsed then
    -- LEFT column: how one entry is sized and how the entries stack.
    -- RIGHT column: what the entries say - the duration format and the
    -- optional group header with the two rows it owns.
    local textLeft, textRight = BeginRowGrid(container)

    AddSliderRow(textLeft, {
        label = "Text Width",
        min = 50, max = 600, step = 1,
        value = style.textWidth or 200,
        onChange = function(val)
            style.textWidth = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    AddSliderRow(textLeft, {
        label = "Text Height",
        min = 10, max = 100, step = 1,
        value = style.textHeight or 20,
        onChange = function(val)
            style.textHeight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    if group.buttons and #group.buttons > 1 then
        AddSliderRow(textLeft, {
            label = "Entry Spacing",
            min = -10, max = 100, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            onChange = function(val)
                style.buttonSpacing = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })
    end

    AddDurationFormatDropdown(textRight, style, refreshStyle, { row = true })

    AddCheckboxRow(textRight, {
        label = "Show Group Header",
        value = style.showTextGroupHeader == true,
        onChange = function(val)
            style.showTextGroupHeader = val or false
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if style.showTextGroupHeader then
        AddSliderRow(textRight, {
            label = "Header Font Size",
            indent = true,
            min = 6, max = 72, step = 1,
            value = style.textHeaderFontSize or 12,
            onChange = function(val)
                style.textHeaderFontSize = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        AddColorRow(textRight, {
            label = "Header Color",
            indent = true,
            tbl = style, key = "textHeaderFontColor",
            default = {1, 1, 1, 1}, hasAlpha = true,
            onConfirm = refreshFrame, onChange = refreshFrame,
        })
    end
    end -- not textSettingsCollapsed

    -- ================================================================
    -- Format String
    --
    -- The only section on this tab that is prose rather than settings: a
    -- rendered preview of the current format and a plain-language summary of
    -- what it uses. Those are full-width labels, not rows - there is no value
    -- to edit on them - and the editor itself opens from a compact action
    -- button, the same shape every other section action takes.
    -- ================================================================
    local fmtHeading, fmtCollapsed = BuildCollapsibleSection(container, "Format String", "textappearance_format", nil, nil, ROW_SECTION)
    -- The cooldown / unusable / out-of-range previews this heading used to
    -- open now live on the preview command center.

    -- Token reference info button
    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtHeading.label, "LEFT", "RIGHT", 4, 0, {
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
    AnchorLeftAlignedHeadingRule(fmtHeading, fmtInfo)

    if not fmtCollapsed then
    local fmt = style.textFormat or "{name}  {status}"

    local fmtPreview = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(fmtPreview)
    fmtPreview:SetText(RenderFormatPreview(fmt, style))
    fmtPreview:SetFullWidth(true)
    fmtPreview:SetFontObject(GameFontHighlight)
    fmtPreview:SetJustifyH("CENTER")
    container:AddChild(fmtPreview)

    local summaryParts = BuildFormatSummary(fmt)
    for _, line in ipairs(summaryParts) do
        local fmtSummary = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(fmtSummary)
        fmtSummary:SetText(line)
        fmtSummary:SetFullWidth(true)
        fmtSummary:SetFontObject(GameFontHighlightSmall)
        container:AddChild(fmtSummary)
    end

    -- Section action: compact and flush left. SetAutoWidth leaves widget.width
    -- nil, so the host's List layout neither stretches nor right-anchors it.
    local editBtn = AceGUI:Create("Button")
    editBtn:SetText("Edit Format")
    editBtn:SetAutoWidth(true)
    editBtn:SetCallback("OnClick", function()
        OpenFormatEditor(style, CS.selectedGroup)
    end)
    container:AddChild(editBtn)

    end -- not fmtCollapsed

    -- ================================================================
    -- Font
    -- ================================================================
    local fontHeading, fontCollapsed = BuildCollapsibleSection(container, "Font", "textappearance_font", nil, nil, ROW_SECTION)

    CreatePromoteButton(fontHeading, "textFont", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not fontCollapsed then
    -- The shared builder splits its own rows: LEFT what the text is drawn
    -- with, RIGHT how the line is laid out.
    local fontLeft, fontRight = BeginRowGrid(container)
    BuildTextFontControls(fontLeft, style, refreshStyle, { row = true, rightColumn = fontRight })
    end -- not fontCollapsed

    -- ================================================================
    -- Colors
    -- ================================================================
    local colorsHeading, colorsCollapsed = BuildCollapsibleSection(container, "Colors", "textappearance_colors", nil, nil, ROW_SECTION)

    CreatePromoteButton(colorsHeading, "textColors", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not colorsCollapsed then
    -- Three colors of one thing, so they stay in one column. The right column
    -- is deliberately empty.
    local colorsLeft = BeginRowGrid(container)
    BuildTextColorsControls(colorsLeft, style, refreshStyle, nil, { row = true })
    end -- not colorsCollapsed

    -- ================================================================
    -- Background & Border
    -- ================================================================
    local bgHeading, bgCollapsed = BuildCollapsibleSection(container, "Background & Border", "textappearance_bg", nil, nil, ROW_SECTION)

    CreatePromoteButton(bgHeading, "textBackground", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not bgCollapsed then
    -- The backdrop and the border that frames it read together, so they stay
    -- in one column. The right column is deliberately empty.
    local bgLeft = BeginRowGrid(container)
    BuildTextBackgroundControls(bgLeft, style, refreshStyle, { row = true })
    end -- not bgCollapsed

    -- ================================================================
    -- Compact Mode Controls
    -- ================================================================
    -- One row, in a grid of its own so it keeps the grammar's half-width cell
    -- rather than stretching its control column across the whole tab.
    local compactLeft = BeginRowGrid(container)
    BuildCompactModeControls(compactLeft, group, tabInfoButtons)
end

-- Exports
ST._BuildTextAppearanceTab = BuildTextAppearanceTab
ST._BuildFormatSummary = BuildFormatSummary
